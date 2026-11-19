import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Supercell 공식 Brawl Stars API 에서 받는 정보 (서버 server/live-activity-relay 의 /v1/brawlstars/* 응답).
// 공식 API 키는 서버에만 있다. 앱은 플레이어 태그만 보낸다.
// 공식 API 에는 진행 중인 경기 정보가 없다. 그래서 '지금 열린 맵'과 '최근 경기 맵'으로 맵 고르기를 빠르게 하고,
// 보유 브롤러로 추천 후보를 줄인다.

/// 게임 태그: 게임 프로필의 #으로 시작하는 코드. 쓰이는 글자는 0289PYLQGRJCUV (O 는 0 으로 바꾼다)
public enum PlayerTag {
    private static let allowed = Set("0289PYLQGRJCUV")
    public static func normalize(_ input: String) -> String? {
        let t = input.uppercased().filter { !$0.isWhitespace && $0 != "#" }.replacingOccurrences(of: "O", with: "0")
        guard (3...14).contains(t.count), t.allSatisfy({ allowed.contains($0) }) else { return nil }
        return "#" + t
    }
}

public struct OwnedBrawler: Codable, Hashable, Sendable {
    public var id: Int
    public var power: Int
    public init(id: Int, power: Int) { self.id = id; self.power = power }
}

public struct RecentBattle: Codable, Hashable, Sendable {
    public var at: String
    public var mode: String?
    public var mapId: Int?
    public var map: String?
    public var result: String?
    public var date: Date? { GameDataDates.parse(at) }
}

public struct PlayerProfile: Codable, Hashable, Sendable {
    public var tag: String?
    public var name: String?
    public var trophies: Int?
    public var brawlers: [OwnedBrawler]
    public var recent: [RecentBattle]
}

public struct RotationEvent: Codable, Hashable, Sendable {
    public var slot: Int?
    public var start: String?
    public var end: String?
    public var mode: String?
    public var mapId: Int
    public var map: String?
    public var endDate: Date? { end.flatMap(GameDataDates.parse) }
    public var startDate: Date? { start.flatMap(GameDataDates.parse) }
}

public struct PlayerResponse: Codable, Sendable { public var ok: Bool; public var player: PlayerProfile }
public struct RotationResponse: Codable, Sendable { public var ok: Bool; public var rotation: [RotationEvent] }

/// App Group 에 저장하는 마지막 값 (Live Activity 버튼으로 맵을 바꿀 때 네트워크 없이 쓴다)
public struct GameDataSnapshot: Codable, Sendable, Equatable {
    public var tag: String?
    public var player: PlayerProfile?
    public var playerFetchedAt: Date?
    public var rotation: [RotationEvent]
    public var rotationFetchedAt: Date?
    public init(tag: String? = nil, player: PlayerProfile? = nil, playerFetchedAt: Date? = nil, rotation: [RotationEvent] = [], rotationFetchedAt: Date? = nil) {
        self.tag = tag; self.player = player; self.playerFetchedAt = playerFetchedAt; self.rotation = rotation; self.rotationFetchedAt = rotationFetchedAt
    }
}

enum GameDataDates {
    static func parse(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

public enum GameDataError: Error, LocalizedError, Equatable {
    case notConfigured
    case invalidTag
    case playerNotFound
    case server(Int, String?)
    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "서버 주소가 설정되지 않았습니다 (project.yml 의 PUSH_RELAY_URL)."
        case .invalidTag: return "플레이어 태그 형식이 맞지 않습니다. 게임 프로필의 # 으로 시작하는 코드를 입력해 주세요."
        case .playerNotFound: return "이 태그의 플레이어를 찾지 못했습니다."
        case .server(let c, let r): return "서버 오류 \(c)\(r.map { ": " + $0 } ?? "")"
        }
    }
}

/// 서버의 /v1/brawlstars/* 를 부른다
public struct GameDataClient: Sendable {
    public let base: URL
    let session: URLSession
    public init(base: URL, session: URLSession = .shared) { self.base = base; self.session = session }

    public func rotation() async throws -> [RotationEvent] {
        try await get(RotationResponse.self, "v1/brawlstars/rotation").rotation
    }

    public func player(tag: String) async throws -> PlayerProfile {
        guard let t = PlayerTag.normalize(tag) else { throw GameDataError.invalidTag }
        // '#' 은 %23 으로 (경로 조각)
        let enc = t.replacingOccurrences(of: "#", with: "%23")
        return try await get(PlayerResponse.self, "v1/brawlstars/player/" + enc).player
    }

    private func get<T: Decodable>(_ type: T.Type, _ path: String) async throws -> T {
        guard let url = URL(string: base.absoluteString.hasSuffix("/") ? base.absoluteString + path : base.absoluteString + "/" + path) else { throw GameDataError.notConfigured }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let (d, r) = try await session.data(for: req)
        let code = (r as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 && path.contains("/player/") { throw GameDataError.playerNotFound }
        guard (200..<300).contains(code) else {
            let reason = (try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["reason"] as? String
            throw GameDataError.server(code, reason)
        }
        return try JSONDecoder().decode(T.self, from: d)
    }
}

/// 맵을 빨리 고르기 위한 목록
public enum QuickMaps {
    /// 지금 열린 이벤트 맵 중 엔진 맵 풀에 있는 맵 (슬롯 순서, 같은 맵은 한 번, 끝난 이벤트 제외)
    public static func current(rotation: [RotationEvent], catalog: EngineCatalog, now: Date) -> [CatalogMap] {
        var out: [CatalogMap] = []
        var seen = Set<MapID>()
        let sorted = rotation.enumerated().sorted { ($0.element.slot ?? Int.max, $0.offset) < ($1.element.slot ?? Int.max, $1.offset) }.map(\.element)
        for e in sorted {
            if let end = e.endDate, end <= now { continue }
            if let start = e.startDate, start > now { continue }
            guard let m = match(e, catalog), seen.insert(m.id).inserted else { continue }
            out.append(m)
        }
        return out
    }

    /// 맵 전환 순서: 지금 열린 맵이 있으면 그 목록, 없으면 맵 풀의 랭크 모드 맵 (엔진 카탈로그 순서)
    public static func cycleList(rotation: [RotationEvent], catalog: EngineCatalog, now: Date) -> [CatalogMap] {
        let cur = current(rotation: rotation, catalog: catalog, now: now)
        if !cur.isEmpty { return cur }
        let ranked = catalog.maps.filter(\.ranked)
        return ranked.isEmpty ? catalog.maps : ranked
    }

    /// 목록에서 step 만큼 이동 (처음·끝에서 돌아간다). 현재 맵이 목록에 없으면 첫 맵(또는 끝 맵)
    public static func step(from current: MapID?, in list: [CatalogMap], by step: Int) -> CatalogMap? {
        guard !list.isEmpty else { return nil }
        guard let c = current, let i = list.firstIndex(where: { $0.id == c }) else { return step >= 0 ? list.first : list.last }
        let n = list.count
        return list[((i + step) % n + n) % n]
    }

    /// 최근 경기 맵: 가장 최근 전적의 맵이 지금 열린 맵이고 maxAge 이내면 그 맵.
    /// 공식 전적은 경기가 끝난 뒤 늦게 올라오므로 '다음 경기도 같은 맵일 가능성이 높다'는 추정일 뿐이다
    public static func recentMap(player: PlayerProfile?, in list: [CatalogMap], now: Date, maxAge: TimeInterval = 45 * 60) -> (map: CatalogMap, at: Date)? {
        guard let p = player else { return nil }
        let battles = p.recent.compactMap { b -> (RecentBattle, Date)? in b.date.map { (b, $0) } }.sorted { $0.1 > $1.1 }
        guard let (b, at) = battles.first, now.timeIntervalSince(at) <= maxAge, let id = b.mapId,
              let m = list.first(where: { $0.id == .number(id) }) else { return nil }
        return (m, at)
    }

    /// 공식 API 맵 id 는 Brawlify 맵 id 와 같다. 없으면 영문 이름으로 찾는다
    static func match(_ e: RotationEvent, _ catalog: EngineCatalog) -> CatalogMap? {
        if let m = catalog.maps.first(where: { $0.id == .number(e.mapId) }) { return m }
        guard let name = e.map.map(norm) else { return nil }
        return catalog.maps.first { norm($0.name) == name }
    }

    static func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
}

/// 보유 브롤러로 추천 후보 줄이기
public enum OwnedFilter {
    /// 엔진 opt.owned 에 넘길 id 목록. 플레이어 정보가 없으면 nil (전체 브롤러)
    public static func ids(_ player: PlayerProfile?, minPower: Int) -> [Int]? {
        guard let p = player, !p.brawlers.isEmpty else { return nil }
        return p.brawlers.filter { $0.power >= minPower }.map(\.id).sorted()
    }
}
