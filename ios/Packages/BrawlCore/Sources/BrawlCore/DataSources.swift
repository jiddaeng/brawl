import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Brawlify·BrawlTime 데이터 받기. 웹 index.html 의 loadSources 와 같은 규칙:
/// - 맵·브롤러 목록이 둘 다 성공하면 새 데이터, 하나라도 실패하면 저장본, 저장본도 없으면 오류
/// - BrawlTime 맵 풀(brawler-strength.json)은 실패하면 저장본, 없으면 null (엔진이 활성 맵 기준으로 동작)
/// - 새로 받은 경우에만 저장본을 덮어쓴다
public enum Endpoints {
    public static let brawlifyMaps = URL(string: "https://api.brawlapi.com/v1/maps")!
    public static let brawlifyBrawlers = URL(string: "https://api.brawlapi.com/v1/brawlers")!
    public static let brawlTimeBase = "https://brawltime.ninja/media"
    public static var brawlTimeStrength: URL { URL(string: brawlTimeBase + "/brawler-strength.json")! }
    public static func brawlTimeMapStats(_ ref: BrawlTimeRef) -> URL {
        URL(string: "\(brawlTimeBase)/brawler-strength/\(ref.statsPath).json")!
    }
}

/// 웹 slimMap / slimBrawler 와 같은 필드만 남긴 형식 (엔진에 그대로 넘긴다)
public struct SlimMap: Codable, Sendable {
    public struct Mode: Codable, Sendable { public var name: String; public var imageUrl: String?; public var color: String? }
    public struct Env: Codable, Sendable { public var name: String? }
    public var id: Int
    public var name: String
    public var imageUrl: String?
    public var disabled: Bool?
    public var new: Bool?
    public var gameMode: Mode
    public var environment: Env?
}

public struct SlimBrawler: Codable, Sendable {
    public struct Named: Codable, Sendable { public var name: String? }
    public struct Rarity: Codable, Sendable { public var color: String? }
    public var id: Int
    public var name: String
    public var imageUrl2: String?
    public var released: Bool?
    public var `class`: Named?
    public var rarity: Rarity?
}

public struct SourceBundle: Codable, Sendable {
    public var at: Date
    public var maps: [SlimMap]
    public var brawlers: [SlimBrawler]
    /// brawler-strength.json 원본 (엔진이 해석)
    public var strength: Data?
}

public struct LoadedSources: Sendable {
    public var maps: [SlimMap]
    public var brawlers: [SlimBrawler]
    public var strength: Data?
    /// 저장본을 썼다면 저장 시각
    public var cachedAt: Date?
}

public enum DataSourceError: Error, LocalizedError, Equatable {
    case offlineNoCache(String)
    case http(Int, String)

    public var errorDescription: String? {
        switch self {
        case .offlineNoCache(let m): return "데이터를 불러오지 못했고 저장된 데이터도 없습니다. 인터넷 연결을 확인하세요. (\(m))"
        case .http(let c, let u): return "서버 응답 오류 \(c): \(u)"
        }
    }
}

public protocol HTTPFetching: Sendable {
    func data(from url: URL) async throws -> Data
}

public struct URLSessionFetcher: HTTPFetching {
    public init() {}
    public func data(from url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        let (d, r) = try await URLSession.shared.data(for: req)
        if let h = r as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw DataSourceError.http(h.statusCode, url.absoluteString) }
        return d
    }
}

public struct DataSourceLoader: Sendable {
    let fetcher: HTTPFetching
    let store: SharedStore

    public init(fetcher: HTTPFetching = URLSessionFetcher(), store: SharedStore) { self.fetcher = fetcher; self.store = store }

    struct ListResponse<T: Decodable>: Decodable { var list: [T] }

    public func load() async throws -> LoadedSources {
        async let m = Result(catching: { try JSONDecoder().decode(ListResponse<SlimMap>.self, from: try await fetcher.data(from: Endpoints.brawlifyMaps)).list })
        async let b = Result(catching: { try JSONDecoder().decode(ListResponse<SlimBrawler>.self, from: try await fetcher.data(from: Endpoints.brawlifyBrawlers)).list })
        async let s = Result(catching: { try await fetcher.data(from: Endpoints.brawlTimeStrength) })
        let (mr, br, sr) = await (m, b, s)
        let cache = store.read(SourceBundle.self, .sources)
        var out: LoadedSources
        if case .success(let maps) = mr, case .success(let brs) = br {
            out = LoadedSources(maps: maps, brawlers: brs, strength: nil, cachedAt: nil)
        } else if let c = cache {
            out = LoadedSources(maps: c.maps, brawlers: c.brawlers, strength: nil, cachedAt: c.at)
        } else {
            let err: Error? = { if case .failure(let e) = mr { return e }; if case .failure(let e) = br { return e }; return nil }()
            throw DataSourceError.offlineNoCache(err.map { "\($0)" } ?? "unknown")
        }
        if case .success(let d) = sr, (try? JSONSerialization.jsonObject(with: d)) != nil { out.strength = d }
        else if let cs = cache?.strength { out.strength = cs; out.cachedAt = out.cachedAt ?? cache?.at }
        if out.cachedAt == nil {
            try? store.write(SourceBundle(at: Date(), maps: out.maps, brawlers: out.brawlers, strength: out.strength), .sources)
        }
        return out
    }

    /// BrawlTime 맵별 통계 원본. 실패하면 저장본, 없으면 nil (웹과 같이 통계 없이 계산)
    public func mapStats(_ ref: BrawlTimeRef) async -> Data? {
        if let d = try? await fetcher.data(from: Endpoints.brawlTimeMapStats(ref)) {
            try? store.writeData(d, .stats(ref.statsPath))
            return d
        }
        return store.readData(.stats(ref.statsPath))
    }
}

extension Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}
