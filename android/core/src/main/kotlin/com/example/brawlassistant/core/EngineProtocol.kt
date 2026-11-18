package com.example.brawlassistant.core

import kotlinx.serialization.json.JsonPrimitive
import java.util.Base64

/**
 * engine/draft-engine.js 를 "문자열 코드를 실행하고 마지막 값을 문자열로 돌려주는" JS 실행기에서 부르는 규약.
 * Android 에서는 androidx.javascriptengine(JavaScriptSandbox), JVM 테스트에서는 Node 가 실행기다.
 * 큰 입력(맵 목록·픽셀)은 실행기 한 번에 넘길 수 있는 크기 제한(Binder 1MB)을 넘지 않게 나눠 보낸다.
 * 계산은 하지 않는다: 웹과 같은 DraftEngine 함수를 부를 뿐이다.
 */
fun interface ScriptRunner { suspend fun eval(code: String): String }

object EngineProtocol {
    /** 한 번에 보내는 문자열 조각 크기 (문자) */
    const val CHUNK = 200_000
    /** 픽셀 조각 (3의 배수 바이트 → base64 4의 배수 문자) */
    const val PIXEL_CHUNK_BYTES = 150_000

    /** 엔진 다음에 실행하는 보조 코드: 조각 모으기, base64 → Uint8ClampedArray */
    val hostShim = """
        var __host = (function () {
          var strs = {}, bufs = {}, T = new Int16Array(128).fill(-1),
              A = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
          for (var i = 0; i < 64; i++) T[A.charCodeAt(i)] = i;
          return {
            s: function (id, part) { (strs[id] = strs[id] || []).push(part); return '0'; },
            take: function (id) { var v = (strs[id] || []).join(''); delete strs[id]; return v; },
            alloc: function (id, n) { bufs[id] = { a: new Uint8ClampedArray(n), o: 0 }; return '0'; },
            b64: function (id, s) {
              var b = bufs[id], a = b.a, o = b.o;
              for (var i = 0; i < s.length; i += 4) {
                var c0 = T[s.charCodeAt(i)], c1 = T[s.charCodeAt(i + 1)],
                    c2 = s.charCodeAt(i + 2) === 61 ? -1 : T[s.charCodeAt(i + 2)],
                    c3 = s.charCodeAt(i + 3) === 61 ? -1 : T[s.charCodeAt(i + 3)];
                a[o++] = (c0 << 2) | (c1 >> 4);
                if (c2 >= 0) { a[o++] = ((c1 & 15) << 4) | (c2 >> 2); if (c3 >= 0) a[o++] = ((c2 & 3) << 6) | c3; }
              }
              b.o = o; return String(o);
            },
            buf: function (id) { var a = bufs[id].a; delete bufs[id]; return a; }
          };
        })();
        'ok'
    """.trimIndent()

    private fun lit(s: String) = JsonPrimitive(s).toString()

    /** 긴 문자열을 조각으로 보내는 코드들 */
    fun putString(id: String, text: String): List<String> =
        if (text.isEmpty()) listOf("__host.s(${lit(id)}, '')")
        else text.chunked(CHUNK).map { "__host.s(${lit(id)}, ${lit(it)})" }

    fun load(mapsJson: String, brawlersJson: String, strengthJson: String?): List<String> =
        putString("maps", mapsJson) + putString("brawlers", brawlersJson) + putString("strength", strengthJson ?: "null") +
            "JSON.stringify(DraftEngine.load(JSON.parse(__host.take('maps')), JSON.parse(__host.take('brawlers')), JSON.parse(__host.take('strength'))))"

    /** 실패하면 "null" (웹과 같이 통계 없음) */
    fun parseStats(raw: String): List<String> =
        putString("stats", raw) + "JSON.stringify(DraftEngine.parseStats(JSON.parse(__host.take('stats'))))"

    fun fallbackFeat(mode: String) = listOf("JSON.stringify(DraftEngine.fallbackFeat(${lit(mode)}))")

    fun analyzePixels(rgba: ByteArray, width: Int, height: Int): List<String> {
        val enc = Base64.getEncoder()
        val parts = ArrayList<String>()
        parts += "__host.alloc('px', ${rgba.size})"
        var i = 0
        while (i < rgba.size) {
            val end = minOf(rgba.size, i + PIXEL_CHUNK_BYTES)
            parts += "__host.b64('px', '${enc.encodeToString(rgba.copyOfRange(i, end))}')"
            i = end
        }
        parts += "JSON.stringify(DraftEngine.analyzePixels(__host.buf('px'), $width, $height))"
        return parts
    }

    fun recommend(mapId: MapId, featJson: String, statsJson: String?, lock: List<Int>, enemy: List<Int>, ban: List<Int>): List<String> {
        val ids = { a: List<Int> -> a.joinToString(",", "[", "]") }
        // 주의: List + String + String 은 문자열이 따로따로 원소가 되므로 마지막 코드는 괄호로 하나로 만든다
        val call = "JSON.stringify(DraftEngine.recommend(${mapId.jsonLiteral}, JSON.parse(__host.take('feat')), " +
            "{stats: JSON.parse(__host.take('st')), lock: ${ids(lock)}, enemy: ${ids(enemy)}, ban: ${ids(ban)}}))"
        return putString("feat", featJson) + putString("st", statsJson ?: "null") + call
    }
}

class EngineException(message: String, cause: Throwable? = null) : Exception(message, cause)

/** DraftEngine 호출 (실행기 하나를 순서대로 쓴다. 호출자는 동시에 부르지 않는다) */
class DraftEngineClient(private val runner: ScriptRunner) {
    private suspend fun run(parts: List<String>): String {
        var last = ""
        for (p in parts) last = runner.eval(p)
        return last
    }

    /** 엔진 스크립트 + 보조 코드 로딩 */
    suspend fun boot(engineScript: String) {
        runner.eval(engineScript + "\n;'loaded'")
        val ok = runner.eval(EngineProtocol.hostShim)
        if (ok != "ok") throw EngineException("엔진 보조 코드 로딩 실패: $ok")
        val v = runner.eval("String(typeof DraftEngine === 'object' && DraftEngine.version)")
        if (v == "false") throw EngineException("DraftEngine 이 없습니다")
    }

    suspend fun load(maps: List<SlimMap>, brawlers: List<SlimBrawler>, strength: String?): EngineCatalog =
        EngineJson.decodeFromString(EngineCatalog.serializer(),
            run(EngineProtocol.load(DataSourceLoader.mapsJson(maps), DataSourceLoader.brawlersJson(brawlers), strength)))

    suspend fun parseStats(raw: String): String? = run(EngineProtocol.parseStats(raw)).takeIf { it != "null" }
    suspend fun fallbackFeat(mode: String): String = run(EngineProtocol.fallbackFeat(mode))
    suspend fun analyzePixels(rgba: ByteArray, width: Int, height: Int): String = run(EngineProtocol.analyzePixels(rgba, width, height))

    /** 결과와 원문 JSON */
    suspend fun recommend(mapId: MapId, featJson: String, statsJson: String?, lock: List<Int> = emptyList(), enemy: List<Int> = emptyList(), ban: List<Int> = emptyList()): Pair<EngineResult, String> {
        val json = run(EngineProtocol.recommend(mapId, featJson, statsJson, lock, enemy, ban))
        return try { EngineJson.decodeFromString(EngineResult.serializer(), json) to json }
        catch (e: Exception) { throw EngineException("추천 결과를 읽을 수 없습니다: ${json.take(200)}", e) }
    }
}
