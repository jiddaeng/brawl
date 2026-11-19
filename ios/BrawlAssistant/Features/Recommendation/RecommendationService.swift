import Foundation
import BrawlCore
import BrawlEngine

/// 기존 Draft Room 엔진(engine/draft-engine.js, 앱 번들에 그대로 포함)으로 추천을 계산한다.
/// 계산식은 이 앱에 없다. 모두 RecommendationEngine → DraftEngineJS → JavaScriptCore 를 거쳐 웹과 같은 코드로 계산한다.
final class RecommendationService {
    let engine: RecommendationEngine

    init(store: SharedStore) throws {
        guard let url = Bundle.main.url(forResource: "draft-engine", withExtension: "js") else {
            throw EngineError.scriptMissing("draft-engine.js (앱 번들)")
        }
        engine = try RecommendationEngine(scriptURL: url, store: store)
    }

    func refresh() async throws -> RecommendationEngine.RefreshResult { try await engine.refresh() }

    /// picks: 실험 기능으로 읽은 드래프트 픽 (우리 팀 → 고정 픽, 상대 팀 → 상대 픽). 웹 드래프트 시뮬레이터와 같은 입력
    func recommend(map: CatalogMap, picks: [PickedBrawler] = []) async throws -> EngineResult {
        let ally = picks.filter { $0.side == .ally }.map(\.brawlerID)
        let enemy = picks.filter { $0.side == .enemy }.map(\.brawlerID)
        return try await engine.recommend(map: map, lock: Array(ally.prefix(map.size)), enemy: Array(enemy.prefix(map.size)))
    }

    func precompute(_ maps: [CatalogMap], first: [MapID] = [], progress: @escaping @Sendable (Int, Int) -> Void) async {
        await engine.precompute(maps: maps, first: first, progress: progress)
    }

    func cachePortraits(_ ids: [Int]) async { await engine.cachePortraits(ids) }
}
