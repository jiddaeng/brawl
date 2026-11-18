import Foundation

/// 방송 확장의 세션 상태 전이. 플랫폼 코드(Vision·ReplayKit)는 이벤트만 넘기고, 상태 결정은 여기서 한다.
/// 원칙: 확정되지 않은 인식으로는 추천을 보여 주지 않는다.
public struct SessionReducer {
    public enum Input {
        case started(Date)
        case heartbeat(Date)
        case recognition(RecognitionStabilizer.Event, frame: GameScreenMatcher.FrameResult?, at: Date)
        case recommendationsChanged(Date)
        case retry(Date)
        case catalogMissing(Date)
        case finished(Date)
    }

    public private(set) var session: AnalysisSession
    let lookup: (MapID) -> EngineResult?

    public init(session: AnalysisSession = .idle, lookup: @escaping (MapID) -> EngineResult?) {
        self.session = session
        self.lookup = lookup
    }

    static let mapFailedMessage = "맵 이름을 찾지 못했습니다. 로비의 이벤트 선택 화면이나 드래프트·로딩 화면을 띄워 주세요."
    static let noRecommendationMessage = "이 맵의 추천이 아직 계산되지 않았습니다. Brawl Assistant 앱을 열면 계산합니다."
    static let catalogMissingMessage = "맵 데이터가 없습니다. Brawl Assistant 앱에서 데이터를 먼저 불러와 주세요."

    /// 반환값: 저장·알림이 필요한 변화가 있었는지
    @discardableResult
    public mutating func reduce(_ input: Input) -> Bool {
        let before = session
        switch input {
        case .started(let t):
            session = AnalysisSession(status: .broadcasting, startedAt: t, updatedAt: t)
        case .heartbeat(let t):
            session.updatedAt = t
            return false   // 심장 박동은 저장만 하고 알림은 하지 않는다
        case .retry(let t):
            session = AnalysisSession(status: .broadcasting, startedAt: session.startedAt ?? t, updatedAt: t)
        case .catalogMissing(let t):
            session.status = .mapFailed; session.message = Self.catalogMissingMessage; session.recommendation = nil; session.updatedAt = t
        case .finished(let t):
            session.status = .ended; session.updatedAt = t; session.message = nil
        case .recommendationsChanged(let t):
            if session.status == .noRecommendation, let id = session.recognition?.recognizedMap { applyRecommendation(for: id, at: t) }
        case .recognition(let event, let frame, let t):
            switch event {
            case .recognized(let map, let conf):
                session.recognition = GameRecognition(recognizedMap: map.id, mapName: map.ko, recognizedMode: map.mode, confidence: conf, timestamp: t, pickedBrawlers: frame?.picks ?? [])
                session.status = .mapRecognized
                applyRecommendation(for: map.id, at: t)
            case .modeAmbiguous(let maps):
                guard session.recognition == nil else { break }
                session.status = .modeFailed
                session.recommendation = nil
                session.message = "‘\(maps.first?.ko ?? "")’ 맵은 여러 모드(\(maps.map(\.modeKo).joined(separator: ", ")))에 있습니다. 모드 이름이 함께 보이는 화면을 띄워 주세요."
                session.updatedAt = t
            case .failed:
                guard session.recognition == nil else { break }
                session.status = .mapFailed; session.recommendation = nil; session.message = Self.mapFailedMessage; session.updatedAt = t
            case .none:
                // 실험 기능: 같은 맵에서 드래프트 픽 글자가 새로 읽히면 기록만 갱신 (추천은 앱에서 다시 계산)
                if let picks = frame?.picks, !picks.isEmpty, var r = session.recognition, r.pickedBrawlers != picks, frame?.map?.id == r.recognizedMap {
                    r.pickedBrawlers = picks; session.recognition = r; session.updatedAt = t
                }
            }
        }
        return session != before
    }

    private mutating func applyRecommendation(for id: MapID, at t: Date) {
        session.updatedAt = t
        if let r = lookup(id), let rec = Recommendation(result: r, at: t) {
            session.status = .ready; session.recommendation = rec; session.message = nil
        } else {
            session.status = .noRecommendation; session.recommendation = nil; session.message = Self.noRecommendationMessage
        }
    }
}

/// Dynamic Island / 잠금 화면에 보여 줄 값 (ActivityKit ContentState 로 그대로 쓴다. 4KB 제한 안에서 작게 유지)
public struct ActivityDisplayState: Codable, Hashable, Sendable {
    public struct Member: Codable, Hashable, Sendable { public var id: Int; public var name: String }
    public var status: AnalysisStatus
    public var mapName: String?
    public var modeName: String?
    public var members: [Member]
    public var score: Int?
    public var winRate: String?
    public var message: String?
    public var updatedAt: Date

    public init(status: AnalysisStatus, mapName: String? = nil, modeName: String? = nil, members: [Member] = [], score: Int? = nil, winRate: String? = nil, message: String? = nil, updatedAt: Date) {
        self.status = status; self.mapName = mapName; self.modeName = modeName; self.members = members
        self.score = score; self.winRate = winRate; self.message = message; self.updatedAt = updatedAt
    }

    /// 세션 → 표시 값. 추천 완료(.ready) 상태에서만 추천 브롤러·점수를 넣는다
    public init(session: AnalysisSession) {
        self.init(status: session.status, updatedAt: session.updatedAt)
        if let r = session.recognition { mapName = r.mapName; modeName = r.recognizedMode }
        message = session.message
        if !session.status.hidesRecommendation, let rec = session.recommendation {
            mapName = rec.mapName; modeName = rec.gameMode
            members = rec.brawlers.prefix(5).map { Member(id: $0.id, name: $0.ko) }
            score = rec.score; winRate = rec.estimatedWinRate
        } else if let r = session.recognition, let m = r.recognizedMode {
            modeName = ModeNames.korean[m] ?? m
        }
    }

    /// 수동으로 고른 맵의 추천
    public init(manual rec: Recommendation) {
        self.init(status: .ready, mapName: rec.mapName, modeName: rec.gameMode, members: rec.brawlers.prefix(5).map { Member(id: $0.id, name: $0.ko) }, score: rec.score, winRate: rec.estimatedWinRate, updatedAt: rec.updatedAt)
    }

    /// 갱신 판단용 키 (시각 제외, 보이는 내용만)
    public var contentKey: String {
        [status.rawValue, mapName ?? "", modeName ?? "", members.map { String($0.id) }.joined(separator: ","), score.map(String.init) ?? "", winRate ?? "", message ?? ""].joined(separator: "|")
    }
}

/// 영문 모드 이름 → 한국어 (엔진 MODE_KO 와 같은 값은 카탈로그에서 채운다)
public enum ModeNames {
    nonisolated(unsafe) public static var korean: [String: String] = [:]
    public static func register(_ catalog: EngineCatalog) { for m in catalog.maps { korean[m.mode] = m.modeKo } }
}

/// 메인 화면 표시 규칙
public struct HomePresentation: Equatable, Sendable {
    public var statusTitle: String
    public var statusDetail: String?
    public var isError: Bool
    public var recommendation: Recommendation?
    public var recognition: GameRecognition?
    public var broadcastActive: Bool
    public var canRetry: Bool
    /// 수동 선택 결과를 보여 주는 중인지
    public var isManual: Bool

    public static let activeStatuses: Set<AnalysisStatus> = [.broadcasting, .mapRecognized, .computing, .ready, .mapFailed, .modeFailed, .noRecommendation]

    /// - heartbeatTimeout: 방송 확장이 이 시간 넘게 소식이 없으면 끊긴 것으로 본다
    /// - waitingTimeout: '화면 인식 대기'가 이 시간 넘게 이어지면 방송이 시작되지 않은 것으로 본다
    public static func make(session s: AnalysisSession, manual: Recommendation?, computing: Bool = false, now: Date, heartbeatTimeout: TimeInterval = 30, waitingTimeout: TimeInterval = 60) -> HomePresentation {
        var p = HomePresentation(statusTitle: s.status.title, statusDetail: s.message, isError: false, recommendation: nil, recognition: s.recognition, broadcastActive: false, canRetry: false, isManual: false)
        let active = activeStatuses.contains(s.status)
        if active && now.timeIntervalSince(s.updatedAt) > heartbeatTimeout {
            p.statusTitle = "방송 연결 끊김"
            p.statusDetail = "화면 방송이 종료되었거나 분석 확장이 중단되었습니다. 다시 시작하세요."
            p.isError = true; p.canRetry = true; p.recognition = nil
            return p
        }
        p.broadcastActive = active
        switch s.status {
        case .idle, .ended:
            if let m = manual {
                p.statusTitle = AnalysisStatus.ready.title; p.statusDetail = "직접 고른 맵"; p.recommendation = m; p.isManual = true
            } else {
                p.statusTitle = s.status == .ended ? AnalysisStatus.ended.title : AnalysisStatus.waiting.title
                p.statusDetail = "‘화면 분석 시작’을 누르고 브롤스타즈를 실행하세요."
            }
        case .waiting:
            if now.timeIntervalSince(s.updatedAt) > waitingTimeout {
                p.statusDetail = "화면 방송이 시작되지 않았습니다. 방송 시트에서 ‘방송 시작’을 눌렀는지 확인하고 다시 시도하세요."
                p.isError = true; p.canRetry = true
            } else { p.statusDetail = "방송 시트에서 Brawl Assistant 를 고르고 ‘방송 시작’을 누르세요." }
        case .broadcasting:
            p.statusDetail = "브롤스타즈에서 맵 이름이 보이는 화면을 띄우면 인식합니다."
        case .mapRecognized, .computing:
            p.statusTitle = computing ? AnalysisStatus.computing.title : s.status.title
        case .ready:
            p.recommendation = s.recommendation
            if let r = s.recognition { p.statusDetail = "인식 신뢰도 \(Int((r.confidence * 100).rounded()))%" }
        case .mapFailed, .modeFailed, .noRecommendation:
            p.isError = s.status != .noRecommendation
            p.canRetry = true
            if s.status == .noRecommendation && computing { p.statusTitle = AnalysisStatus.computing.title }
        }
        return p
    }
}
