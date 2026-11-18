package com.example.brawlassistant.core

import kotlinx.serialization.json.*

/**
 * 검증용: 엔진 결과를 웹 결과 카드에 보이는 값과 같은 모양으로 바꾼다 (tests/engine-regression/compare.cjs view() 와 같음).
 * JVM 테스트(Node)와 기기 테스트(JavaScriptSandbox)가 golden.json 과 비교할 때 쓴다. 숫자 표시 문자열은 엔진 값 그대로.
 */
object WebCardView {
    fun of(R: EngineResult, k: Int): JsonObject {
        val L = R.teams.toMutableList(); val tmp = L[0]; L[0] = L[k]; L[k] = tmp
        val T = L[0]
        val koById = R.teams.flatMap { it.members }.associate { it.id to it.ko }
        val ordered = T.members.filter { it.pick != null }.sortedBy { it.pick }
        return buildJsonObject {
            put("archetype", T.archetype)
            putJsonArray("members") { T.members.forEach { m -> addJsonObject {
                put("name", m.name); put("role", m.role); put("pick", m.pick?.let { "${it}픽" }); put("eff", m.effPct?.let { "실전 ${it}%p" })
            } } }
            put("score", T.score)
            putJsonArray("kpi") { add("${T.estimatedWinRate}%"); add(R.countText); add(T.counterPercent.toString()) }
            putJsonArray("bars") { T.factors.forEach { f -> addJsonArray { add(f.label); add(f.percent) } } }
            putJsonArray("reasons") { T.plainReasons.forEach { add(it) } }
            putJsonArray("order") {
                if (R.map.size > 1) ordered.forEachIndexed { i, m ->
                    add("${i + 1}픽 ${m.ko} — " + when (i) { 0 -> "카운터가 적어 블라인드 픽으로 안전"; ordered.size - 1 -> "카운터당하기 쉬워 마지막에 상대를 보고 확정"; else -> "중간 픽, 상대 첫 픽에 맞춰 교체 가능" })
                }
            }
            putJsonArray("threats") { T.threats.forEach { add(it.ko) } }
            putJsonArray("alts") { L.drop(1).forEach { o -> addJsonObject {
                put("names", o.ids.joinToString(" · ") { koById[it] ?: "" }); put("ar", o.summary); put("score", o.score)
            } } }
        }
    }
}
