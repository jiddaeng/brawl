import SwiftUI
import ReplayKit
import BrawlCore
import BrawlEngine

/// 앱 전체 상태. 데이터 갱신·추천 계산·방송 확장과의 연결·Live Activity 를 관리한다.
@MainActor
final class AppState: ObservableObject {
    enum DataStatus: Equatable {
        case idle, loading
        case ready(Date)
        case offline(cachedAt: Date)
        case failed(String)
    }

    @Published private(set) var catalog: EngineCatalog?
    @Published private(set) var dataStatus: DataStatus = .idle
    @Published private(set) var precomputed = 0
    @Published private(set) var precomputeTotal = 0
    @Published private(set) var session: AnalysisSession = .idle
    @Published private(set) var manualRecommendation: Recommendation?
    @Published private(set) var manualResult: EngineResult?
    @Published private(set) var lastResult: EngineResult?
    @Published private(set) var isComputing = false
    @Published var alert: String?
    @Published var now = Date()
    /// 실험 기능: 드래프트 화면에서 읽은 브롤러를 추천에 반영 (앱이 화면에 있을 때 다시 계산). 화면의 토글과 같은 키
    static let usePicksKey = "recognition.usePicks"
    var usePickedBrawlers: Bool { UserDefaults.standard.bool(forKey: Self.usePicksKey) }

    let store: SharedStore?
    let liveActivity = LiveActivityController()
    private var service: RecommendationService?
    private let darwin = DarwinObserver()
    private var precomputeTask: Task<Void, Never>?
    private var clock: Timer?
    private var computingMap: MapID?

    init() {
        store = AppGroup.store
        liveActivity.store = store
        #if DEBUG
        if loadDemoIfRequested() { return }
        #endif
        guard let store else {
            dataStatus = .failed("App Group 컨테이너를 열 수 없습니다. 서명 설정의 App Groups 를 확인하세요.")
            return
        }
        do { service = try RecommendationService(store: store) }
        catch { dataStatus = .failed(error.localizedDescription) }
        catalog = store.read(EngineCatalog.self, .catalog)
        if let c = catalog { ModeNames.register(c) }
        session = store.read(AnalysisSession.self, .session) ?? .idle
        darwin.observe(.sessionChanged) { [weak self] in Task { @MainActor in self?.sessionDidChange() } }
        liveActivity.reattach()
        clock = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in self?.now = Date() } }
    }

    var presentation: HomePresentation {
        HomePresentation.make(session: session, manual: manualRecommendation, computing: isComputing, now: now)
    }

    // MARK: 데이터

    /// 앱 실행·새로고침: 웹과 같은 규칙으로 맵·브롤러·현재 맵 풀을 받고, 맵 풀 전체의 기본 추천을 미리 계산한다
    func refresh() async {
        guard let service, let store else { return }
        dataStatus = .loading
        do {
            let r = try await service.refresh()
            catalog = r.catalog
            ModeNames.register(r.catalog)
            dataStatus = r.cachedAt.map { .offline(cachedAt: $0) } ?? .ready(Date())
            await service.cachePortraits(r.catalog.brawlers.map(\.id))
            startPrecompute(r.catalog, store: store)
        } catch {
            dataStatus = .failed(error.localizedDescription)
        }
    }

    private func startPrecompute(_ cat: EngineCatalog, store: SharedStore) {
        precomputeTask?.cancel()
        precomputed = 0; precomputeTotal = cat.maps.count
        guard let service else { return }
        precomputeTask = Task { [weak self] in
            // 앱이 백그라운드로 가도 조금 더 이어서 계산 (시스템이 허락하는 동안)
            let bg = UIApplication.shared.beginBackgroundTask(withName: "precompute", expirationHandler: nil)
            await service.precompute(cat.maps) { done, total in
                Task { @MainActor in
                    self?.precomputed = done; self?.precomputeTotal = total
                    // 방송 확장이 기다리는 맵이 있을 수 있으므로 주기적으로 알림
                    if done % 10 == 0 || done == total { DarwinSignal.recommendationsChanged.post() }
                }
            }
            UIApplication.shared.endBackgroundTask(bg)
        }
    }

    // MARK: 방송 확장과 연결

    func sessionDidChange() {
        guard let store else { return }
        let s = store.read(AnalysisSession.self, .session) ?? .idle
        session = s
        now = Date()
        switch s.status {
        case .noRecommendation:
            // 확장에 미리 계산된 추천이 없음 → 앱이 화면에 있으면 바로 계산해 파일로 넘긴다
            if let id = s.recognition?.recognizedMap, let map = catalog?.maps.first(where: { $0.id == id }) { computeForExtension(map) }
        case .ready:
            if usePickedBrawlers, let r = s.recognition, !r.pickedBrawlers.isEmpty, let map = catalog?.maps.first(where: { $0.id == r.recognizedMap }) {
                recomputeWithPicks(map, picks: r.pickedBrawlers)
            }
        case .ended:
            liveActivity.end(final: ActivityDisplayState(session: s), immediately: false)
            return
        default: break
        }
        syncLiveActivity()
    }

    /// 확장이 Live Activity 를 갱신하지 못했으면(또는 확장 경로를 쓰지 않으면) 앱이 대신 갱신
    func syncLiveActivity() {
        guard liveActivity.isRunning else { return }
        let state = manualRecommendation != nil && !HomePresentation.activeStatuses.contains(session.status)
            ? ActivityDisplayState(manual: manualRecommendation!)
            : ActivityDisplayState(session: session)
        if liveActivity.displayedState?.contentKey != state.contentKey { liveActivity.publish(state) }
    }

    private func computeForExtension(_ map: CatalogMap) {
        guard let service, computingMap != map.id else { return }
        computingMap = map.id; isComputing = true
        Task {
            do {
                _ = try await service.recommend(map: map)   // 기본 추천은 엔진이 App Group 에 저장
                DarwinSignal.recommendationsChanged.post()
            } catch { self.alert = error.localizedDescription }
            self.computingMap = nil
            self.isComputing = false
        }
    }

    private func recomputeWithPicks(_ map: CatalogMap, picks: [PickedBrawler]) {
        guard let service else { return }
        Task {
            guard let r = try? await service.recommend(map: map, picks: picks), let rec = Recommendation(result: r) else { return }
            await MainActor.run {
                self.lastResult = r
                self.session.recommendation = rec
                self.syncLiveActivity()
            }
        }
    }

    // MARK: 사용자 동작

    /// 화면 분석 시작 전 점검. 통과하면 방송 시트를 띄우면 된다
    func prepareBroadcast() -> Bool {
        guard RPScreenRecorder.shared().isAvailable else {
            alert = "이 기기에서 화면 방송을 사용할 수 없습니다 (스크린 타임 제한, 화면 미러링 중 등)."
            return false
        }
        guard catalog != nil else { alert = "맵 데이터를 먼저 불러와야 합니다. ‘데이터 새로고침’을 눌러 주세요."; return false }
        guard AppGroup.broadcastExtensionBundleID != nil else { alert = "방송 확장 설정이 없습니다 (BrawlBroadcastExtensionBundleID)."; return false }
        manualRecommendation = nil; manualResult = nil
        if !HomePresentation.activeStatuses.contains(session.status) || presentation.isError {
            writeSession(AnalysisSession(status: .waiting, updatedAt: Date()))
        }
        if !liveActivity.isRunning, liveActivity.availability == .available { liveActivity.start(with: ActivityDisplayState(session: session)) }
        return true
    }

    func stopBroadcast() {
        DarwinSignal.stopRequested.post()
        // 확장이 이미 죽어 있으면 응답이 없으므로 앱이 정리
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                if self.session.status != .ended { self.writeSession(AnalysisSession(status: .ended, startedAt: self.session.startedAt, updatedAt: Date())) }
                self.liveActivity.end(final: ActivityDisplayState(session: self.session), immediately: true)
            }
        }
    }

    func retryRecognition() {
        if presentation.broadcastActive { DarwinSignal.retryRequested.post() }
        else { writeSession(AnalysisSession(status: .idle, updatedAt: Date())) }
    }

    /// 인식이 어려울 때 맵을 직접 고른다 (같은 엔진으로 계산)
    func chooseMapManually(_ map: CatalogMap) {
        guard let service else { return }
        isComputing = true
        Task {
            do {
                let r = try await service.recommend(map: map)
                await MainActor.run {
                    self.manualResult = r
                    self.manualRecommendation = Recommendation(result: r)
                    self.isComputing = false
                    self.syncLiveActivity()
                }
            } catch {
                await MainActor.run { self.isComputing = false; self.alert = error.localizedDescription }
            }
        }
    }

    func toggleLiveActivity() {
        if liveActivity.isRunning { liveActivity.end(final: nil, immediately: true); return }
        let state = manualRecommendation.map(ActivityDisplayState.init(manual:)) ?? ActivityDisplayState(session: session)
        liveActivity.start(with: state)
        if let e = liveActivity.lastError { alert = e }
    }

    /// 화면에 보여 줄 전체 엔진 결과 (순위·대안 조합). 방송 인식 결과면 저장된 파일에서 읽는다
    var displayedResult: EngineResult? {
        let p = presentation
        if p.isManual { return manualResult }
        guard let id = p.recommendation?.mapID else { return nil }
        if let r = lastResult, r.map.id == id, usePickedBrawlers { return r }
        return store?.recommendation(for: id)
    }

    #if DEBUG
    /// 디자인 확인용 데모 모드 (UI 테스트·스크린샷). 환경 변수 BRAWL_DEMO_RESULT 에 엔진 결과 JSON 경로를 주면
    /// 네트워크·엔진 없이 그 결과를 '맵 직접 선택' 결과로 띄우고, BRAWL_DEMO_LIVE=1 이면 Live Activity 도 시작한다.
    static var isDemo: Bool { ProcessInfo.processInfo.environment["BRAWL_DEMO_RESULT"] != nil }

    private func loadDemoIfRequested() -> Bool {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["BRAWL_DEMO_RESULT"], let data = FileManager.default.contents(atPath: path),
              let r = try? JSONDecoder().decode(EngineResult.self, from: data), let rec = Recommendation(result: r) else { return false }
        manualResult = r
        manualRecommendation = rec
        dataStatus = .ready(Date())
        UserDefaults.standard.set(true, forKey: "onboarding.done")
        Task {
            // Live Activity 용 초상화를 App Group 에 넣어 둔다 (서명 없이 실행되면 App Group 이 없어 건너뜀)
            if let store {
                for b in rec.brawlers {
                    guard let s = b.img, let u = URL(string: s), let (d, _) = try? await URLSession.shared.data(from: u),
                          let png = PixelDecoder.thumbnailPNG(d, side: 96) else { continue }
                    try? png.write(to: store.portraitURL(brawlerID: b.id), options: .atomic)
                }
            }
            if env["BRAWL_DEMO_LIVE"] == "1" { liveActivity.start(with: ActivityDisplayState(manual: rec)) }
        }
        return true
    }
    #endif

    private func writeSession(_ s: AnalysisSession) {
        session = s
        try? store?.write(s, .session)
    }
}
