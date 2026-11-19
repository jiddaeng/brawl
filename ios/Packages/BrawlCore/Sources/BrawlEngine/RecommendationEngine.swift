#if canImport(JavaScriptCore) && canImport(CoreGraphics)
import Foundation
import BrawlCore

/// 데이터 받기 → 엔진 구성 → 맵 이미지 분석 → 통계 → 추천 계산 → App Group 저장.
/// 웹 페이지의 boot → selectMap → loadStats → runEngine 흐름을 그대로 따른다.
public actor RecommendationEngine {
    public struct RefreshResult: Sendable {
        public var catalog: EngineCatalog
        /// 저장본을 썼다면 그 시각 (API 응답 없음)
        public var cachedAt: Date?
    }

    private let engine: DraftEngineJS
    private let store: SharedStore
    private let loader: DataSourceLoader
    private let fetcher: HTTPFetching
    public private(set) var catalog: EngineCatalog?
    private var statsJSON: [String: String?] = [:]   // 웹 STATS 와 같이 세션 동안 캐시 (실패도 캐시)
    private var features: FeatureCache
    /// 보유 브롤러만 추천 (공식 API 플레이어 정보). nil 이면 전체 브롤러. 바뀌면 미리 계산을 다시 해야 한다
    public private(set) var owned: [Int]?
    public func setOwned(_ ids: [Int]?) { owned = ids }

    public init(scriptURL: URL, store: SharedStore, fetcher: HTTPFetching = URLSessionFetcher()) throws {
        engine = try DraftEngineJS(scriptURL: scriptURL)
        self.store = store
        self.fetcher = fetcher
        loader = DataSourceLoader(fetcher: fetcher, store: store)
        features = store.read(FeatureCache.self, .features) ?? FeatureCache()
    }

    /// 맵·브롤러·현재 맵 풀 갱신. API 가 실패하면 저장본으로 (웹과 같음)
    public func refresh() async throws -> RefreshResult {
        let src = try await loader.load()
        let (cat, _) = try engine.load(maps: src.maps, brawlers: src.brawlers, strength: src.strength)
        catalog = cat
        statsJSON = [:]
        try? store.write(cat, .catalog)
        return RefreshResult(catalog: cat, cachedAt: src.cachedAt)
    }

    /// 맵 특성: 이미지 후보를 순서대로 받아 분석, 모두 실패하면 모드 기본값 (웹 selectMap 과 같음)
    public func featureJSON(for map: CatalogMap) async throws -> String {
        let key = map.id.description
        for u in map.images {
            if let e = features.entries[key], e.source == u, let j = e.json { return j }
            guard let url = URL(string: u), let data = try? await fetcher.data(from: url), var px = PixelDecoder.decode(data) else { continue }
            let j = try engine.analyzePixels(&px.bytes, width: px.width, height: px.height)
            let feat = try JSONDecoder().decode(MapFeatures.self, from: Data(j.utf8))
            features.entries[key] = FeatureCache.Entry(source: u, feat: feat, json: j)
            try? store.write(features, .features)
            return j
        }
        if let e = features.entries[key], let j = e.json { return j }   // 오프라인: 마지막 분석값
        return try engine.fallbackFeat(mode: map.mode)
    }

    private func stats(for map: CatalogMap) async throws -> String? {
        guard let ref = map.bt else { return nil }
        if let cached = statsJSON[ref.statsPath] { return cached }
        var parsed: String?
        if let raw = await loader.mapStats(ref) { parsed = try engine.parseStats(raw) }
        statsJSON[ref.statsPath] = parsed
        return parsed
    }

    /// 한 맵 추천 계산 (보유 브롤러 설정 반영). lock/enemy/ban 이 비어 있으면 결과를 App Group 에 저장해
    /// 방송 확장과 Live Activity 맵 전환 버튼이 계산 없이 바로 쓰게 한다
    public func recommend(map: CatalogMap, lock: [Int] = [], enemy: [Int] = [], ban: [Int] = []) async throws -> EngineResult {
        let feat = try await featureJSON(for: map)
        let st = try await stats(for: map)
        let (r, json) = try engine.recommend(mapID: map.id, featJSON: feat, statsJSON: st, lock: lock, enemy: enemy, ban: ban, owned: owned)
        if lock.isEmpty && enemy.isEmpty && ban.isEmpty { try? store.writeData(Data(json.utf8), .recommendation(map.id)) }
        return r
    }

    /// 현재 맵 풀 전체의 기본 추천을 미리 계산 (랭크 모드 먼저). 방송 확장은 계산 없이 이 결과를 읽는다
    /// first: 먼저 계산할 맵 (지금 열린 맵)
    public func precompute(maps: [CatalogMap], first: [MapID] = [], progress: @Sendable (Int, Int) -> Void) async {
        let head = first.compactMap { id in maps.first { $0.id == id } }
        let rest = maps.filter { m in !first.contains(m.id) }
        let ordered = head + rest.filter { $0.ranked } + rest.filter { !$0.ranked }
        for (i, m) in ordered.enumerated() {
            if Task.isCancelled { return }
            _ = try? await recommend(map: m)
            progress(i + 1, ordered.count)
        }
    }

    /// Live Activity 용 브롤러 초상화 (Live Activity 는 네트워크 이미지를 못 쓰므로 App Group 에 저장)
    public func cachePortraits(_ ids: [Int]) async {
        guard let cat = catalog else { return }
        for b in cat.brawlers where ids.contains(b.id) {
            let dst = store.portraitURL(brawlerID: b.id)
            if FileManager.default.fileExists(atPath: dst.path) { continue }
            guard let s = b.img, let u = URL(string: s), let d = try? await fetcher.data(from: u), let png = PixelDecoder.thumbnailPNG(d, side: 96) else { continue }
            try? png.write(to: dst, options: .atomic)
        }
    }
}
#endif
