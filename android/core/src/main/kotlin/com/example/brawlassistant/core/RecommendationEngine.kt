package com.example.brawlassistant.core

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** PNG → RGBA 원본 바이트 (색 변환 없이). Android: BitmapFactory, JVM 테스트: ImageIO */
fun interface PixelDecoder { fun decode(png: ByteArray): Pixels? }
class Pixels(val rgba: ByteArray, val width: Int, val height: Int)

/** 작은 초상화 PNG 만들기 (알림·화면용) */
fun interface Thumbnailer { fun thumbnail(image: ByteArray, side: Int): ByteArray? }

/**
 * 데이터 받기 → 엔진 구성 → 맵 이미지 분석 → 통계 → 추천 계산 → 저장.
 * 웹 boot → selectMap → loadStats → runEngine 과 같은 흐름 (iOS RecommendationEngine 과 같음).
 */
class RecommendationEngine(
    private val client: DraftEngineClient,
    private val store: FileStore,
    private val fetcher: HttpFetcher,
    private val pixels: PixelDecoder,
    private val thumbnailer: Thumbnailer? = null,
) {
    data class RefreshResult(val catalog: EngineCatalog, val cachedAt: Long?)

    private val lock = Mutex()   // 엔진 실행기는 한 번에 하나
    private val loader = DataSourceLoader(fetcher, store)
    var catalog: EngineCatalog? = null; private set
    private val statsCache = HashMap<String, String?>()
    private var features = store.read(FeatureCache.serializer(), FileStore.Entry.Features) ?: FeatureCache()

    suspend fun refresh(): RefreshResult = lock.withLock {
        val src = loader.load()
        val cat = client.load(src.maps, src.brawlers, src.strength)
        catalog = cat
        statsCache.clear()
        store.write(EngineCatalog.serializer(), cat, FileStore.Entry.Catalog)
        ModeNames.register(cat)
        RefreshResult(cat, src.cachedAt)
    }

    /** 맵 특성 JSON: 이미지 후보를 순서대로 받아 분석, 모두 실패하면 모드 기본값 (웹 selectMap 과 같음) */
    private suspend fun featureJson(map: CatalogMap): String {
        val key = map.id.toString()
        for (u in map.images) {
            features.entries[key]?.let { if (it.source == u) return it.json }
            val bytes = runCatching { fetcher.get(u) }.getOrNull() ?: continue
            val px = pixels.decode(bytes) ?: continue
            val j = client.analyzePixels(px.rgba, px.width, px.height)
            features = FeatureCache(features.entries + (key to FeatureCache.Item(u, j)))
            store.write(FeatureCache.serializer(), features, FileStore.Entry.Features)
            return j
        }
        features.entries[key]?.let { return it.json }   // 오프라인: 마지막 분석값
        return client.fallbackFeat(map.mode)
    }

    private suspend fun stats(map: CatalogMap): String? {
        val ref = map.bt ?: return null
        if (statsCache.containsKey(ref.statsPath)) return statsCache[ref.statsPath]
        val parsed = loader.mapStats(ref)?.let { client.parseStats(it) }
        statsCache[ref.statsPath] = parsed
        return parsed
    }

    /** 한 맵 추천. 픽·밴이 없으면 결과를 저장해 화면 분석이 바로 쓰게 한다 */
    suspend fun recommend(map: CatalogMap, lockIds: List<Int> = emptyList(), enemy: List<Int> = emptyList(), ban: List<Int> = emptyList()): EngineResult = lock.withLock {
        val (r, json) = client.recommend(map.id, featureJson(map), stats(map), lockIds, enemy, ban)
        if (lockIds.isEmpty() && enemy.isEmpty() && ban.isEmpty()) store.writeText(json, FileStore.Entry.Recommendation(map.id))
        r
    }

    /** 맵 풀 전체 기본 추천 미리 계산 (랭크 모드 먼저) */
    suspend fun precompute(maps: List<CatalogMap>, progress: (Int, Int) -> Unit) {
        val ordered = maps.filter { it.ranked } + maps.filter { !it.ranked }
        ordered.forEachIndexed { i, m ->
            runCatching { recommend(m) }
            progress(i + 1, ordered.size)
        }
    }

    suspend fun cachePortraits(ids: Collection<Int>) {
        val cat = catalog ?: return
        val t = thumbnailer ?: return
        for (b in cat.brawlers) {
            if (b.id !in ids) continue
            val f = store.portrait(b.id)
            if (f.exists()) continue
            val url = b.img ?: continue
            val bytes = runCatching { fetcher.get(url) }.getOrNull() ?: continue
            t.thumbnail(bytes, 96)?.let { f.writeBytes(it) }
        }
    }
}
