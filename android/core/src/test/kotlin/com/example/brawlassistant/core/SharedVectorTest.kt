package com.example.brawlassistant.core

import kotlinx.serialization.json.*
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** tests/app-fixtures/recognition-cases.json: iOS BrawlCore SharedVectorTests 와 같은 입력·기대값 */
class SharedVectorTest {
    private val file = Json.parseToJsonElement(Fixtures.text("recognition-cases.json")).jsonObject
    private val matcher = GameScreenMatcher(Fixtures.catalog)
    private fun ocr(a: JsonArray) = a.map { val o = it.jsonObject; OcrLine(o.str("text"), o["confidence"]!!.jsonPrimitive.double, o["x"]!!.jsonPrimitive.double, o["y"]!!.jsonPrimitive.double) }

    @Test fun matcherVectors() {
        val cases = file["matcher"]!!.jsonArray
        assertTrue(cases.isNotEmpty())
        for (c in cases.map { it.jsonObject }) {
            val name = c.str("name")
            val e = c["expect"]!!.jsonObject
            val r = matcher.analyze(ocr(c["lines"]!!.jsonArray))
            if (e.containsKey("map") || e.containsKey("ambiguousModes")) {
                val want = e["map"]?.let { if (it is JsonNull) null else MapId.Num(it.jsonPrimitive.long) }
                assertEquals(name, want, r.map?.id)
            }
            e["mode"]?.let { assertEquals(name, it.jsonPrimitive.content, r.mode) }
            e["ambiguousModes"]?.let { assertEquals(name, it.jsonArray.map { m -> m.jsonPrimitive.content }.sorted(), r.ambiguousMaps.map { m -> m.mode }.sorted()) }
            e["picks"]?.let { p ->
                val want = p.jsonArray.map { val o = it.jsonObject; "${o.str("brawler")}:${o.str("side")}" }.sorted()
                val got = r.picks.map { pk -> "${Fixtures.catalog.brawlers.first { it.id == pk.brawlerId }.name}:${pk.side}" }.sorted()
                assertEquals(name, want, got)
            }
        }
    }

    @Test fun stabilizerVectors() {
        val t0 = 1_000_000_000L
        for (c in file["stabilizer"]!!.jsonArray.map { it.jsonObject }) {
            val cfg = c["config"]!!.jsonObject
            val s = RecognitionStabilizer(cfg["requiredAgreement"]!!.jsonPrimitive.int,
                (cfg["agreementWindow"]!!.jsonPrimitive.double * 1000).toLong(), (cfg["failAfter"]!!.jsonPrimitive.double * 1000).toLong())
            s.start(t0)
            for (st in c["steps"]!!.jsonArray.map { it.jsonObject }) {
                val t = st["t"]!!.jsonPrimitive.double
                val got = when (val e = s.feed(matcher.analyze(ocr(st["lines"]!!.jsonArray)), t0 + (t * 1000).toLong())) {
                    RecognitionStabilizer.Event.None -> "none"
                    is RecognitionStabilizer.Event.Recognized -> "recognized:${e.map.id}"
                    RecognitionStabilizer.Event.Failed -> "failed"
                    is RecognitionStabilizer.Event.ModeAmbiguous -> "ambiguous:${e.maps.size}"
                }
                assertEquals("${c.str("name")} t=$t", st.str("expect"), got)
            }
        }
    }
}
