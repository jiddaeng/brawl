import Foundation
import os
import BrawlCore

/// OCR 결과 → 맵·모드 확정 → 세션 상태(App Group) → Live Activity.
/// 상태 규칙은 BrawlCore 의 GameScreenMatcher / RecognitionStabilizer / SessionReducer (Linux 에서 테스트됨).
/// analysisQueue 에서만 호출된다.
final class GameScreenRecognizer {
    private let store = AppGroup.store
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
        Task { await ExtensionActivityUpdater.end(ActivityDisplayState(session: reducer.session)) }
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
        let state = ActivityDisplayState(session: reducer.session)
        let now = Date()
        // 보이는 내용이 바뀌었을 때만. 너무 잦으면 다음 이벤트 때 반영 (앱이 화면에 오면 앱이 맞춘다)
        guard activity.decide(key: state.contentKey, now: now) == .updateNow else { return }
        activity.markPublished(key: state.contentKey, at: now)
        let key = state.contentKey
        let log = self.log
        Task { [store] in
            let (ok, error) = await ExtensionActivityUpdater.update(state)
            // 결과는 세션과 별도 파일에 기록 (세션 파일은 분석 큐만 쓴다). 앱이 진단 화면에 보여 준다
            try? store?.write(ExtensionActivityUpdate(contentKey: key, succeeded: ok, error: error, at: Date()), .extensionActivity)
            if !ok { log.notice("확장에서 Live Activity 갱신 실패: \(error ?? "")") }
        }
    }
}
