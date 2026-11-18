package com.example.brawlassistant

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.brawlassistant.core.*
import com.example.brawlassistant.engine.AndroidPixels
import com.example.brawlassistant.engine.SandboxRunner
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.*
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * 기기·에뮬레이터에서 실제 JavaScriptSandbox(WebView V8) 와 BitmapFactory 로 엔진을 돌려 웹 정답과 비교한다.
 * 입력: tests/engine-regression (androidTest assets 로 포함)
 */
@RunWith(AndroidJUnit4::class)
class EngineSandboxParityTest {
    private val ctx = InstrumentationRegistry.getInstrumentation().context          // 테스트 APK (assets)
    private val app = InstrumentationRegistry.getInstrumentation().targetContext    // 앱 (draft-engine.js)
    private fun asset(p: String) = ctx.assets.open(p).use { it.readBytes() }
    private val lenient = Json { ignoreUnknownKeys = true }

    private suspend fun client(): Pair<DraftEngineClient, SandboxRunner> {
        assumeTrue("이 기기 WebView 는 JavaScriptSandbox 미지원", SandboxRunner.isSupported())
        val r = SandboxRunner.create(app)
        val c = DraftEngineClient(r)
        c.boot(app.assets.open("draft-engine.js").bufferedReader().use { it.readText() })
        return c to r
    }

    @Test fun goldenScenariosMatchWeb() = runBlocking {
        val (c, r) = client()
        r.use {
            val maps = lenient.decodeFromJsonElement(ListSerializer(SlimMap.serializer()), lenient.parseToJsonElement(asset("fixtures/maps.json").decodeToString()).jsonObject["list"]!!)
            val brs = lenient.decodeFromJsonElement(ListSerializer(SlimBrawler.serializer()), lenient.parseToJsonElement(asset("fixtures/brawlers.json").decodeToString()).jsonObject["list"]!!)
            c.load(maps, brs, asset("fixtures/strength.json").decodeToString())
            val golden = Json.parseToJsonElement(asset("golden.json").decodeToString()).jsonObject
            val stats = HashMap<String, String?>()
            var teams = 0; val bad = ArrayList<String>()
            for (cs in golden["cases"]!!.jsonArray.map { it.jsonObject }) {
                val id = cs["map"]!!.jsonPrimitive.let { if (it.isString) MapId.Str(it.content) else MapId.Num(it.long) }
                val sp = cs["stats"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content
                val st = sp?.let { p -> if (stats.containsKey(p)) stats[p] else c.parseStats(asset("fixtures/stats/" + p.replace("/", "__") + ".json").decodeToString()).also { stats[p] = it } }
                val sc = cs["scenario"]!!.jsonObject
                val ints = { k: String -> sc[k]!!.jsonArray.map { it.jsonPrimitive.int } }
                val (res, _) = c.recommend(id, cs["feat"]!!.toString(), st, ints("lock"), ints("enemy"), ints("ban"))
                val exp = cs["expected"]!!.jsonArray
                for (k in res.teams.indices) { teams++; if (WebCardView.of(res, k) != exp[k]) bad += "map $id ${sc["name"]} #${k + 1}" }
            }
            println("JavaScriptSandbox 엔진 일치: 조합 ${teams - bad.size}/$teams")
            assertTrue(bad.take(5).joinToString(), bad.isEmpty())
        }
    }

    @Test fun bitmapFactoryPixelsMatchBrowser() = runBlocking {
        val (c, r) = client()
        r.use {
            val golden = Json.parseToJsonElement(asset("golden.json").decodeToString()).jsonObject
            val browser = golden["cases"]!!.jsonArray.map { it.jsonObject }.associate { it["map"]!!.jsonPrimitive.content to it["feat"]!!.jsonObject }
            val files = ctx.assets.list("fixtures/maps")!!.filter { it.endsWith(".png") }
            assertTrue(files.isNotEmpty())
            for (f in files) {
                val px = AndroidPixels.decode(asset("fixtures/maps/$f"))!!
                val got = Json.parseToJsonElement(c.analyzePixels(px.rgba, px.width, px.height)).jsonObject
                val exp = browser[f.removeSuffix(".png")]!!
                for (k in listOf("ok", "cols", "rows", "TX", "TY", "cover", "bush", "wall", "open", "sight", "midOpen", "laneSplit"))
                    assertEquals("$f $k", exp[k]!!.jsonPrimitive.content, got[k]!!.jsonPrimitive.content)
            }
        }
    }
}
