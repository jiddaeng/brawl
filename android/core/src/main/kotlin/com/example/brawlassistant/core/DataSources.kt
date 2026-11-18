package com.example.brawlassistant.core

import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray

/** Brawlify·BrawlTime 데이터 받기. 웹 index.html loadSources 와 같은 규칙 (iOS DataSourceLoader 와 같음) */
object Endpoints {
    const val BRAWLIFY_MAPS = "https://api.brawlapi.com/v1/maps"
    const val BRAWLIFY_BRAWLERS = "https://api.brawlapi.com/v1/brawlers"
    const val BRAWLTIME = "https://brawltime.ninja/media"
    const val BRAWLTIME_STRENGTH = "$BRAWLTIME/brawler-strength.json"
    fun mapStats(ref: BrawlTimeRef) = "$BRAWLTIME/brawler-strength/${ref.statsPath}.json"
}

/** 웹 slimMap / slimBrawler 와 같은 필드 */
@Serializable data class SlimMap(
    val id: Long, val name: String, val imageUrl: String? = null, val disabled: Boolean? = null, val new: Boolean? = null,
    val gameMode: Mode, val environment: Env? = null,
) {
    @Serializable data class Mode(val name: String, val imageUrl: String? = null, val color: String? = null)
    @Serializable data class Env(val name: String? = null)
}

@Serializable data class SlimBrawler(
    val id: Int, val name: String, val imageUrl2: String? = null, val released: Boolean? = null,
    val `class`: Named? = null, val rarity: Rarity? = null,
) {
    @Serializable data class Named(val name: String? = null)
    @Serializable data class Rarity(val color: String? = null)
}

@Serializable data class SourceBundle(val at: Long, val maps: List<SlimMap>, val brawlers: List<SlimBrawler>, val strength: String? = null)

data class LoadedSources(val maps: List<SlimMap>, val brawlers: List<SlimBrawler>, val strength: String?, val cachedAt: Long?)

class DataSourceException(message: String) : Exception(message)

fun interface HttpFetcher { suspend fun get(url: String): ByteArray }

class DataSourceLoader(private val fetcher: HttpFetcher, private val store: FileStore, private val now: () -> Long = System::currentTimeMillis) {
    private val lenient = Json { ignoreUnknownKeys = true }

    private fun <T> list(bytes: ByteArray, s: kotlinx.serialization.KSerializer<T>): List<T> {
        val arr = lenient.parseToJsonElement(bytes.decodeToString()).let { (it as JsonObject)["list"]!!.jsonArray }
        return arr.map { lenient.decodeFromJsonElement(s, it) }
    }

    suspend fun load(): LoadedSources = coroutineScope {
        val m = async { runCatching { list(fetcher.get(Endpoints.BRAWLIFY_MAPS), SlimMap.serializer()) } }
        val b = async { runCatching { list(fetcher.get(Endpoints.BRAWLIFY_BRAWLERS), SlimBrawler.serializer()) } }
        val s = async { runCatching { fetcher.get(Endpoints.BRAWLTIME_STRENGTH).decodeToString() } }
        val mr = m.await(); val br = b.await(); val sr = s.await()
        val cache = store.read(SourceBundle.serializer(), FileStore.Entry.Sources)
        var out = when {
            mr.isSuccess && br.isSuccess -> LoadedSources(mr.getOrThrow(), br.getOrThrow(), null, null)
            cache != null -> LoadedSources(cache.maps, cache.brawlers, null, cache.at)
            else -> throw DataSourceException("데이터를 불러오지 못했고 저장된 데이터도 없습니다. 인터넷 연결을 확인하세요. (${(mr.exceptionOrNull() ?: br.exceptionOrNull())?.message})")
        }
        val strength = sr.getOrNull()?.takeIf { runCatching { lenient.parseToJsonElement(it) }.isSuccess }
        out = if (strength != null) out.copy(strength = strength)
        else if (cache?.strength != null) out.copy(strength = cache.strength, cachedAt = out.cachedAt ?: cache.at) else out
        if (out.cachedAt == null) store.write(SourceBundle.serializer(), SourceBundle(now(), out.maps, out.brawlers, out.strength), FileStore.Entry.Sources)
        out
    }

    /** BrawlTime 맵별 통계 원본. 실패하면 저장본, 없으면 null (웹과 같이 통계 없이 계산) */
    suspend fun mapStats(ref: BrawlTimeRef): String? {
        val d = runCatching { fetcher.get(Endpoints.mapStats(ref)).decodeToString() }.getOrNull()
        if (d != null) { store.writeText(d, FileStore.Entry.Stats(ref.statsPath)); return d }
        return store.readText(FileStore.Entry.Stats(ref.statsPath))
    }

    companion object {
        fun mapsJson(maps: List<SlimMap>) = EngineJson.encodeToString(ListSerializer(SlimMap.serializer()), maps)
        fun brawlersJson(b: List<SlimBrawler>) = EngineJson.encodeToString(ListSerializer(SlimBrawler.serializer()), b)
    }
}
