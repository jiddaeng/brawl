import Foundation

// 앱·확장·위젯이 공유하는 모델. 추천 값은 모두 EngineResult 에서 가져온다.

public struct Recommendation: Codable, Hashable, Sendable {
    public var mapID: MapID
    public var mapName: String
    public var mapNameEn: String
    public var gameMode: String
    public var gameModeEn: String
    public var rank: Int
    public var brawlers: [TeamMember]
    public var score: Int
    public var estimatedWinRate: String
    public var reasons: [String]
    public var archetype: String
    public var statsInfo: StatsInfo?
    public var updatedAt: Date

    /// 엔진 결과의 rank 번째 조합 (기본 1위)
    public init?(result: EngineResult, rank: Int = 1, at date: Date = Date()) {
        guard let t = result.teams.first(where: { $0.rank == rank }) else { return nil }
        mapID = result.map.id
        mapName = result.map.ko
        mapNameEn = result.map.name
        gameMode = result.map.modeKo
        gameModeEn = result.map.mode
        self.rank = t.rank
        brawlers = t.members
        score = t.score
        estimatedWinRate = t.estimatedWinRate
        reasons = t.plainReasons
        archetype = t.archetype
        statsInfo = result.stats
        updatedAt = date
    }

    /// Live Activity 갱신 여부 판단용: 사용자에게 보이는 추천 내용이 같으면 같은 키
    public var contentKey: String {
        "\(mapID)|\(gameModeEn)|\(brawlers.map { String($0.id) }.joined(separator: ","))|\(score)|\(estimatedWinRate)"
    }
}

public struct PickedBrawler: Codable, Hashable, Sendable {
    public enum Side: String, Codable, Sendable { case ally, enemy, unknown }
    public var brawlerID: Int
    public var side: Side
    public var confidence: Double
}

public struct GameRecognition: Codable, Hashable, Sendable {
    public var recognizedMap: MapID?
    public var mapName: String?
    public var recognizedMode: String?
    public var confidence: Double
    public var timestamp: Date
    /// 실험 기능: 드래프트 화면에서 글자로 읽힌 브롤러
    public var pickedBrawlers: [PickedBrawler]

    public init(recognizedMap: MapID?, mapName: String?, recognizedMode: String?, confidence: Double, timestamp: Date, pickedBrawlers: [PickedBrawler] = []) {
        self.recognizedMap = recognizedMap
        self.mapName = mapName
        self.recognizedMode = recognizedMode
        self.confidence = confidence
        self.timestamp = timestamp
        self.pickedBrawlers = pickedBrawlers
    }
}

/// 화면 분석 세션 상태 (방송 확장이 쓰고 앱이 읽는다)
public enum AnalysisStatus: String, Codable, Sendable, CaseIterable {
    case idle            // 분석 꺼짐
    case waiting         // 화면 인식 대기 (방송 시작 전)
    case broadcasting    // 화면 방송 중, 아직 맵 못 찾음
    case mapRecognized   // 맵 인식 완료
    case computing       // 추천 계산 중
    case ready           // 추천 완료
    case mapFailed       // 맵 인식 실패 (일정 시간 맵을 못 찾음)
    case modeFailed      // 맵 이름은 읽었지만 모드를 확정하지 못함
    case noRecommendation // 인식은 됐지만 추천 데이터 없음 (앱에서 계산 필요)
    case ended           // 방송 종료

    public var title: String {
        switch self {
        case .idle: return "분석 꺼짐"
        case .waiting: return "화면 인식 대기"
        case .broadcasting: return "화면 방송 중"
        case .mapRecognized: return "맵 인식 완료"
        case .computing: return "추천 계산 중"
        case .ready: return "추천 완료"
        case .mapFailed: return "맵 인식 실패"
        case .modeFailed: return "모드 인식 실패"
        case .noRecommendation: return "추천 데이터 없음"
        case .ended: return "방송 종료"
        }
    }

    /// 이 상태에서는 추천을 보여 주면 안 된다 (잘못된 추천 방지)
    public var hidesRecommendation: Bool {
        switch self { case .ready: return false; default: return true }
    }
}

public struct AnalysisSession: Codable, Hashable, Sendable {
    public var status: AnalysisStatus
    public var startedAt: Date?
    public var updatedAt: Date
    public var recognition: GameRecognition?
    public var recommendation: Recommendation?
    public var message: String?

    public init(status: AnalysisStatus, startedAt: Date? = nil, updatedAt: Date = Date(), recognition: GameRecognition? = nil, recommendation: Recommendation? = nil, message: String? = nil) {
        self.status = status
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.recognition = recognition
        self.recommendation = recommendation
        self.message = message
    }

    public static let idle = AnalysisSession(status: .idle)
}

/// 방송 확장이 Live Activity 를 직접 갱신한 결과 (기기 검증·진단용, 세션과 별도 파일)
public struct ExtensionActivityUpdate: Codable, Hashable, Sendable {
    public var contentKey: String
    public var succeeded: Bool
    public var error: String?
    public var at: Date
    public init(contentKey: String, succeeded: Bool, error: String?, at: Date) {
        self.contentKey = contentKey; self.succeeded = succeeded; self.error = error; self.at = at
    }
}
