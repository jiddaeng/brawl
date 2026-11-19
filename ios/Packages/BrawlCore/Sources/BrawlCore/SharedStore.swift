import Foundation

/// 앱·방송 확장·위젯이 App Group 컨테이너에서 공유하는 파일 저장소.
/// 프로세스가 서로 다르므로 파일 단위로 원자적으로 쓰고, 읽을 때 실패하면 nil 로 처리한다.
public struct SharedStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("recommendations"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("portraits"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("stats"), withIntermediateDirectories: true)
    }

    public enum File {
        case sources            // API 응답 저장본 (웹 localStorage 캐시와 같은 역할)
        case catalog            // 현재 맵 풀 + 브롤러 (인식 사전)
        case features           // 맵 이미지 분석 결과
        case session            // 분석 세션 상태
        case extensionActivity  // 방송 확장의 Live Activity 갱신 결과 (진단)
        case liveActivityPush   // Live Activity 푸시 토큰 (앱 → 방송 확장)
        case gameData           // 공식 API: 플레이어 태그·보유 브롤러·최근 경기·지금 열린 맵
        case recommendation(MapID)
        case stats(String)      // BrawlTime 맵별 통계 원본 (mode/slug)

        var path: String {
            switch self {
            case .sources: return "sources.json"
            case .catalog: return "catalog.json"
            case .features: return "features.json"
            case .session: return "session.json"
            case .extensionActivity: return "extension-activity.json"
            case .liveActivityPush: return "live-activity-push.json"
            case .gameData: return "game-data.json"
            case .recommendation(let id): return "recommendations/\(id.fileKey).json"
            case .stats(let p): return "stats/\(p.replacingOccurrences(of: "/", with: "__")).json"
            }
        }
    }

    public func url(_ f: File) -> URL { root.appendingPathComponent(f.path) }
    public func portraitURL(brawlerID: Int) -> URL { root.appendingPathComponent("portraits/\(brawlerID).png") }

    // 날짜는 기본 형식(기준 시각부터의 초, 소수 포함)으로 저장한다. ISO8601 은 1초 미만을 잘라 상태 비교가 틀어진다
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    public func read<T: Decodable>(_ type: T.Type, _ f: File) -> T? {
        guard let d = try? Data(contentsOf: url(f)) else { return nil }
        return try? SharedStore.decoder.decode(T.self, from: d)
    }

    public func write<T: Encodable>(_ value: T, _ f: File) throws {
        try SharedStore.encoder.encode(value).write(to: url(f), options: .atomic)
    }

    public func readData(_ f: File) -> Data? { try? Data(contentsOf: url(f)) }
    public func writeData(_ d: Data, _ f: File) throws { try d.write(to: url(f), options: .atomic) }
    public func remove(_ f: File) { try? FileManager.default.removeItem(at: url(f)) }

    /// 미리 계산된 추천 결과 (엔진 원본 JSON)
    public func recommendation(for id: MapID) -> EngineResult? { read(EngineResult.self, .recommendation(id)) }
}

/// 맵 이미지 분석 결과 캐시. 같은 맵이라도 이미지 URL 이 바뀌면 다시 분석한다
public struct FeatureCache: Codable, Sendable {
    public struct Entry: Codable, Sendable {
        public var source: String?
        public var feat: MapFeatures
        /// 엔진이 돌려준 JSON 원문 (추천 계산에 그대로 다시 넘긴다)
        public var json: String?
        public init(source: String?, feat: MapFeatures, json: String?) { self.source = source; self.feat = feat; self.json = json }
    }
    public var entries: [String: Entry] = [:]
    public init() {}
}
