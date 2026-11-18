package com.example.brawlassistant.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import java.io.File

/** 앱 파일 저장소 (iOS SharedStore 와 같은 파일 구성). 쓰기는 임시 파일 → 이름 바꾸기로 원자적으로 */
class FileStore(val root: File) {
    init { listOf("recommendations", "portraits", "stats").forEach { File(root, it).mkdirs() } }

    sealed class Entry(val path: String) {
        object Sources : Entry("sources.json")
        object Catalog : Entry("catalog.json")
        object Features : Entry("features.json")
        object Session : Entry("session.json")
        class Recommendation(id: MapId) : Entry("recommendations/${id.fileKey}.json")
        class Stats(statsPath: String) : Entry("stats/${statsPath.replace("/", "__")}.json")
    }

    fun file(e: Entry) = File(root, e.path)
    fun portrait(brawlerId: Int) = File(root, "portraits/$brawlerId.png")

    fun <T> read(serializer: KSerializer<T>, e: Entry): T? = readText(e)?.let { runCatching { EngineJson.decodeFromString(serializer, it) }.getOrNull() }
    fun <T> write(serializer: KSerializer<T>, value: T, e: Entry) = writeText(EngineJson.encodeToString(serializer, value), e)

    fun readText(e: Entry): String? = file(e).takeIf { it.exists() }?.readText()
    fun writeText(text: String, e: Entry) {
        val f = file(e); f.parentFile?.mkdirs()
        val tmp = File(f.parentFile, f.name + ".tmp")
        tmp.writeText(text); if (!tmp.renameTo(f)) { f.delete(); tmp.renameTo(f) }
    }

    fun recommendation(id: MapId): EngineResult? = read(EngineResult.serializer(), Entry.Recommendation(id))
}

/** 맵 이미지 분석 결과 캐시 (엔진이 준 JSON 원문을 그대로 보관해 다시 넘긴다) */
@Serializable data class FeatureCache(val entries: Map<String, Item> = emptyMap()) {
    @Serializable data class Item(val source: String? = null, val json: String)
}
