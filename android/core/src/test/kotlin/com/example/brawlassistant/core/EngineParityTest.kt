package com.example.brawlassistant.core

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.*
import org.junit.AfterClass
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.BeforeClass
import org.junit.Test
import java.io.File

/**
 * Android 와 같은 호출 경로(EngineProtocol 조각 전송·base64 픽셀·RecommendationEngine)로 엔진을 돌려
 * 웹 결과 카드 정답(tests/engine-regression/golden.json)과 비교한다. 실행기: Node (Android 에서는 JavaScriptSandbox).
 */
class EngineParityTest {
    companion object {
        private var runner: NodeRunner? = null
        private lateinit var client: DraftEngineClient
        private val fx = File(Fixtures.regression, "fixtures")
        private val golden by lazy { Json.parseToJsonElement(File(Fixtures.regression, "golden.json").readText()).jsonObject }
        private fun slimMaps() = Json { ignoreUnknownKeys = true }.decodeFromJsonElement(ListSerializer(SlimMap.serializer()),
            Json.parseToJsonElement(File(fx, "maps.json").readText()).jsonObject["list"]!!)
        private fun slimBrawlers() = Json { ignoreUnknownKeys = true }.decodeFromJsonElement(ListSerializer(SlimBrawler.serializer()),
            Json.parseToJsonElement(File(fx, "brawlers.json").readText()).jsonObject["list"]!!)

        @BeforeClass @JvmStatic fun boot() {
            runner = NodeRunner.start()
            assumeTrue("node 가 없어 건너뜀", runner != null)
            client = DraftEngineClient(runner!!)
            runBlocking { client.boot(File(Fixtures.repo, "engine/draft-engine.js").readText()) }
        }

        @AfterClass @JvmStatic fun close() { runner?.close() }

        fun view(R: EngineResult, k: Int) = WebCardView.of(R, k)
    }

    @Test fun allGoldenScenariosMatchWeb() = runBlocking {
        client.load(slimMaps(), slimBrawlers(), File(fx, "strength.json").readText())
        val stats = HashMap<String, String?>()
        var teams = 0; val bad = ArrayList<String>()
        for (c in golden["cases"]!!.jsonArray.map { it.jsonObject }) {
            val id = c["map"]!!.jsonPrimitive.let { if (it.isString) MapId.Str(it.content) else MapId.Num(it.long) }
            val sp = c["stats"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content
            val st = sp?.let { stats.getOrPut(it) { runBlocking { client.parseStats(File(fx, "stats/" + it.replace("/", "__") + ".json").readText()) } } }
            val sc = c["scenario"]!!.jsonObject
            val ints = { k: String -> sc[k]!!.jsonArray.map { it.jsonPrimitive.int } }
            // 맵 특성은 JSON 원문 그대로 (Kotlin 에서 숫자를 다시 쓰지 않는다)
            val (r, _) = client.recommend(id, c["feat"]!!.toString(), st, ints("lock"), ints("enemy"), ints("ban"))
            val expected = c["expected"]!!.jsonArray
            assertEquals(expected.size, r.teams.size)
            for (k in r.teams.indices) {
                teams++
                if (view(r, k) != expected[k]) bad += "map $id ${sc["name"]} #${k + 1}\n web: ${expected[k]}\n got: ${view(r, k)}"
            }
        }
        println("Android 경로 엔진 일치: 조합 ${teams - bad.size}/$teams, 실행기 호출 ${runner!!.calls}회")
        assertTrue(bad.take(3).joinToString("\n"), bad.isEmpty())
    }

    @Test fun pixelAnalysisThroughBase64ChunksMatchesBrowser() = runBlocking {
        val browser = golden["cases"]!!.jsonArray.map { it.jsonObject }.associate { it["map"]!!.jsonPrimitive.content to it["feat"]!!.jsonObject }
        val files = File(fx, "maps").listFiles { f -> f.name.endsWith(".png") }!!
        assertTrue(files.isNotEmpty())
        for (f in files) {
            val px = ImageIoPixels.decode(f.readBytes())!!
            val got = Json.parseToJsonElement(client.analyzePixels(px.rgba, px.width, px.height)).jsonObject
            val exp = browser[f.nameWithoutExtension]!!
            for (k in listOf("ok", "cols", "rows", "TX", "TY", "cover", "bush", "wall", "open", "sight", "midOpen", "laneSplit"))
                assertEquals("${f.name} $k", exp[k]!!.jsonPrimitive.content, got[k]!!.jsonPrimitive.content)
        }
    }

    /** RecommendationEngine 전체 흐름 (데이터 받기 → 맵 이미지 분석 → 통계 → 추천 → 저장): 네트워크 대신 녹화본 */
    @Test fun orchestrationMatchesWebBaseScenario() = runBlocking {
        val manifest = Json.parseToJsonElement(File(fx, "manifest.json").readText()).jsonObject["maps"]!!.jsonArray.map { it.jsonObject }
        val fetcher = HttpFetcher { url ->
            when {
                url == Endpoints.BRAWLIFY_MAPS -> File(fx, "maps.json").readBytes()
                url == Endpoints.BRAWLIFY_BRAWLERS -> File(fx, "brawlers.json").readBytes()
                url == Endpoints.BRAWLTIME_STRENGTH -> File(fx, "strength.json").readBytes()
                url.contains("/brawler-strength/") -> File(fx, "stats/" + url.substringAfter("/brawler-strength/").removeSuffix(".json").replace("/", "__") + ".json").let { if (it.exists()) it.readBytes() else throw java.io.IOException("404") }
                else -> manifest.firstOrNull { it["image"]?.jsonPrimitive?.contentOrNull == url }?.let { File(fx, "maps/${it.str("id")}.png").readBytes() } ?: throw java.io.IOException("404 $url")
            }
        }
        val store = tempStore()
        val engine = RecommendationEngine(client, store, fetcher, ImageIoPixels)
        val cat = engine.refresh().catalog
        var checked = 0
        for (c in golden["cases"]!!.jsonArray.map { it.jsonObject }.filter { it["scenario"]!!.jsonObject.str("name") == "base" }) {
            val id = MapId.Num(c["map"]!!.jsonPrimitive.long)
            val r = engine.recommend(cat.maps.first { it.id == id })
            val expected = c["expected"]!!.jsonArray
            for (k in r.teams.indices) assertEquals("map $id #${k + 1}", expected[k], view(r, k))
            assertEquals("저장된 추천", r.teams[0].score, store.recommendation(id)!!.teams[0].score)
            checked++
        }
        println("Android 오케스트레이션: 기본 시나리오 맵 $checked 개 웹과 일치")
        assertEquals(manifest.size, checked)
    }
}
