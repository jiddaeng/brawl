package com.example.brawlassistant.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.longOrNull

// engine/draft-engine.js 의 DraftEngine API 가 돌려주는 JSON 과 같은 모양 (iOS BrawlCore EngineModels 와 같은 필드).
// 엔진이 주지 않는 값은 만들지 않는다.

val EngineJson = Json { ignoreUnknownKeys = true; explicitNulls = false; encodeDefaults = true }

/** 맵 id: Brawlify 맵은 숫자, BrawlTime 에만 있는 맵은 "bt-모드-슬러그" 문자열 */
@Serializable(with = MapIdSerializer::class)
sealed class MapId {
    data class Num(val value: Long) : MapId() { override fun toString() = value.toString() }
    data class Str(val value: String) : MapId() { override fun toString() = value }

    /** 파일 이름에 쓰는 키 */
    val fileKey: String get() = toString().replace("/", "_")
    /** JS 로 넘길 때의 리터럴 */
    val jsonLiteral: String get() = when (this) { is Num -> value.toString(); is Str -> JsonPrimitive(value).toString() }
}

object MapIdSerializer : KSerializer<MapId> {
    override val descriptor = PrimitiveSerialDescriptor("MapId", PrimitiveKind.STRING)
    override fun deserialize(decoder: Decoder): MapId {
        val p = (decoder as JsonDecoder).decodeJsonElement() as JsonPrimitive
        return if (p.isString) MapId.Str(p.content) else MapId.Num(p.longOrNull ?: error("bad map id $p"))
    }
    override fun serialize(encoder: Encoder, value: MapId) {
        val e: JsonElement = when (value) { is MapId.Num -> JsonPrimitive(value.value); is MapId.Str -> JsonPrimitive(value.value) }
        (encoder as JsonEncoder).encodeJsonElement(e)
    }
}

@Serializable data class BrawlTimeRef(val mode: String, val slug: String) { val statsPath get() = "$mode/$slug" }

@Serializable data class EngineCatalog(val window: String? = null, val hasLive: Boolean, val maps: List<CatalogMap>, val brawlers: List<CatalogBrawler>)

@Serializable data class CatalogMap(
    val id: MapId, val name: String, val ko: String, val mode: String, val modeKo: String,
    val ranked: Boolean, val size: Int, val live: Boolean, val isNew: Boolean,
    val bt: BrawlTimeRef? = null,
    /** 맵 이미지 후보 (웹 mapImgs 순서: BrawlTime → Brawlify) */
    val images: List<String>,
)

@Serializable data class CatalogBrawler(val id: Int, val name: String, val ko: String, val img: String? = null, val position: String, val estimatedProfile: Boolean)

@Serializable data class MapFeatures(
    val ok: Boolean, val cols: Int? = null, val rows: Int? = null, val TX: Double? = null, val TY: Double? = null,
    val cover: Double, val bush: Double, val wall: Double, val open: Double, val sight: Double, val midOpen: Double, val laneSplit: Double,
)

@Serializable data class EngineResult(
    val engineVersion: Int, val map: ResultMap, val feat: MapFeatures, val demands: Map<String, Double>,
    val stats: StatsInfo? = null, val count: Int,
    /** 웹과 같은 표시 문자열 (예: "3,276") */
    val countText: String,
    val poolSize: Int, val teams: List<TeamResult>,
)

@Serializable data class ResultMap(val id: MapId, val name: String, val ko: String, val mode: String, val modeKo: String, val kind: String, val size: Int, val live: Boolean)

@Serializable data class StatsInfo(val preset: String, val battles: Int, val from: String, val until: String)

@Serializable data class TeamResult(
    val rank: Int, val ids: List<Int>, val score: Int,
    /** 웹과 같은 소수 첫째 자리 문자열 */
    val estimatedWinRate: String,
    val archetype: String, val f: Map<String, Double?>,
    val counterPercent: Int, val summary: String,
    /** 역할 순서 (웹 결과 카드 순서) */
    val members: List<TeamMember>, val factors: List<Factor>,
    /** 웹 화면용 HTML 이스케이프 문자열 → plainReasons 사용 */
    val reasons: List<String>, val threats: List<TeamMember>,
) { val plainReasons: List<String> get() = reasons.map(HtmlEntities::decode) }

@Serializable data class TeamMember(
    val id: Int, val name: String, val ko: String, val img: String? = null, val position: String, val positionKo: String,
    val estimatedProfile: Boolean,
    val eff: Double? = null,
    /** 웹과 같은 표시 문자열 (예: "+6.0"). 다시 반올림하지 않는다 */
    val effPct: String? = null,
    val role: String? = null, val pick: Int? = null,
)

@Serializable data class Factor(val key: String, val label: String, val value: Double? = null, val percent: Int? = null)

object HtmlEntities {
    /** 웹 esc() 가 바꾼 문자만 되돌린다 */
    fun decode(s: String) = s.replace("&quot;", "\"").replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")
}
