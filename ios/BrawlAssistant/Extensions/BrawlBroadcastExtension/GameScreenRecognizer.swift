import Foundation
import os
import BrawlCore

/// OCR 결과 → 맵·모드 확정 → 세션 상태(App Group) → Live Activity.
/// 상태 규칙은 BrawlCore 의 GameScreenMatcher / RecognitionStabilizer / SessionReducer (Linux 에서 테스트됨).
/// analysisQueue 에서만 호출된다.
final class GameScreenRecognizer {
    private let store = AppGroup.store
    /// 분석 큐 (지연된 Live Activity 갱신을 같은 큐에서 처리)
    private let queue: DispatchQueue
    private var lastPublished: ActivityDisplayState?
    private var pendingState: ActivityDisplayState?
    private var pendingScheduled = false

    init(queue: DispatchQueue) { self.queue = queue }
    private var matcher: GameScreenMatcher?
    private var catalogDate: Date?
    private var stabilizer = RecognitionStabilizer(requiredAgreement: 2, agreementWindow: 10, failAfter: 25)
    private lazy var reducer = SessionReducer { [store] id in store?.recommendation(for: id) }
    private var activity = ActivityUpdatePolicy(minInterval: 5)
    private let log = Logger(subsystem: "BrawlAssistant.Broadcast", category: "recognizer")

    func start() {
        let now = Date()
        loadCatalogIfNeeded()
        stabilizer.start(at: now)
        reducer.reduce(.started(now))
        if matcher == nil { reducer.reduce(.catalogMissing(now)) }
        commit()
    }

    func retry() {
        let now = Date()
        loadCatalogIfNeeded()
        stabilizer.start(at: now)
        reducer.reduce(.retry(now))
        commit()
    }

    func recommendationsChanged() {
        if reducer.reduce(.recommendationsChanged(Date())) { commit() }
    }

    func heartbeat() {
        reducer.reduce(.heartbeat(Date()))
        save()   // 앱이 '방송 연결 끊김'을 판단할 수 있도록 시각만 갱신 (알림 없음)
    }

    func process(_ lines: [OCRLine], at now: Date) {
        loadCatalogIfNeeded()
        guard let matcher else { return }
        let frame = matcher.analyze(lines)
        let event = stabilizer.feed(frame, at: now)
        if reducer.reduce(.recognition(event, frame: frame, at: now)) { commit() }
    }

    func finish() {
        reducer.reduce(.finished(Date()))
        save()
        DarwinSignal.sessionChanged.post()
        let final = ActivityDisplayState(session: reducer.session)
        Task { [store] in try? store?.write(await ExtensionActivityUpdater.end(final, store: store), .extensionActivity) }
    }

    /// 앱이 데이터를 새로 받았으면 사전을 다시 만든다
    private func loadCatalogIfNeeded() {
        guard let store else { return }
        let url = store.url(.catalog)
        let mod = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        guard mod != catalogDate, let cat = store.read(EngineCatalog.self, .catalog) else { return }
        matcher = GameScreenMatcher(catalog: cat)
        ModeNames.register(cat)
        catalogDate = mod
    }

    private func save() { try? store?.write(reducer.session, .session) }

    private func commit() {
        save()
        DarwinSignal.sessionChanged.post()
        publishActivity(ActivityDisplayState(session: reducer.session))
    }

    /// Live Activity 갱신: 보이는 내용이 바뀌었을 때만, 최소 5초 간격. 너무 빠르면 마지막 값을 모아 두었다가 보낸다
    private func publishActivity(_ state: ActivityDisplayState) {
        let now = Date()
        switch activity.decide(key: state.contentKey, now: now) {
        case .skip: return
        case .deferUntil(let t):
            pendingState = state
            guard !pendingScheduled else { return }
            pendingScheduled = true
            queue.asyncAfter(deadline: .now() + max(0, t.timeIntervalSinceNow)) { [weak self] in
                guard let self else { return }
                self.pendingScheduled = false
                if let p = self.pendingState { self.pendingState = nil; self.publishActivity(p) }
            }
        case .updateNow:
            pendingState = nil
            activity.markPublished(key: state.contentKey, at: now)
            let previous = lastPublished
            lastPublished = state
            let log = self.log
            Task { [store] in
                let result = await ExtensionActivityUpdater.update(state, previous: previous, store: store)
                // 결과는 세션과 별도 파일에 기록 (세션 파일은 분석 큐만 쓴다). 앱이 진단 화면에 보여 준다
                try? store?.write(result, .extensionActivity)
                if !result.succeeded { log.notice("Live Activity 갱신 실패(\(result.path?.rawValue ?? "-")): \(result.error ?? "")") }
            }
        }
    }
}
