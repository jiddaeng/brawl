package com.example.brawlassistant.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.buildJsonObject
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import javax.imageio.ImageIO

object Fixtures {
    val repo = File(System.getProperty("repoRoot") ?: "../..")
    val app = File(repo, "tests/app-fixtures")
    val regression = File(repo, "tests/engine-regression")
    fun text(name: String) = File(app, name).readText()
    val catalog: EngineCatalog by lazy { EngineJson.decodeFromString(EngineCatalog.serializer(), text("catalog.json")) }
    fun result(name: String) = EngineJson.decodeFromString(EngineResult.serializer(), text("$name.json"))
    fun map(id: Long) = catalog.maps.first { it.id == MapId.Num(id) }
    fun brawler(en: String) = catalog.brawlers.first { it.name == en }
}

fun line(t: String, x: Double = 0.5, y: Double = 0.1, conf: Double = 0.9) = OcrLine(t, conf, x, y)

fun tempStore(): FileStore = FileStore(kotlin.io.path.createTempDirectory("brawlcore").toFile())

/** Node 를 JS 실행기로 쓴다 (Android 의 JavaScriptSandbox 자리). node 가 없으면 null */
class NodeRunner private constructor(private val p: Process) : ScriptRunner, AutoCloseable {
    private val w = OutputStreamWriter(p.outputStream, Charsets.UTF_8)
    private val r = BufferedReader(InputStreamReader(p.inputStream, Charsets.UTF_8))
    var calls = 0; private set

    override suspend fun eval(code: String): String {
        calls++
        w.write(buildJsonObject { put("code", code) }.toString()); w.write("\n"); w.flush()
        val o = Json.parseToJsonElement(r.readLine() ?: error("node 종료")).jsonObject
        if (!o["ok"]!!.jsonPrimitive.boolean) throw EngineException(o["error"]!!.jsonPrimitive.content)
        return o["value"]!!.jsonPrimitive.content
    }

    override fun close() { p.destroy() }

    companion object {
        fun start(): NodeRunner? {
            val script = File(NodeRunner::class.java.getResource("/node-runner.js")!!.toURI())
            return runCatching { NodeRunner(ProcessBuilder("node", script.absolutePath).redirectErrorStream(false).start()) }.getOrNull()
        }
    }
}

/** JVM 의 PNG 디코더 (색 프로필 없는 PNG 는 변환 없이 원본 값). Android 에서는 BitmapFactory 가 같은 역할 */
object ImageIoPixels : PixelDecoder {
    override fun decode(png: ByteArray): Pixels? {
        val img = ImageIO.read(png.inputStream()) ?: return null
        val w = img.width; val h = img.height
        val argb = img.getRGB(0, 0, w, h, null, 0, w)
        val out = ByteArray(w * h * 4)
        for (i in argb.indices) {
            val c = argb[i]
            out[i * 4] = (c shr 16).toByte(); out[i * 4 + 1] = (c shr 8).toByte(); out[i * 4 + 2] = c.toByte(); out[i * 4 + 3] = (c ushr 24).toByte()
        }
        return Pixels(out, w, h)
    }
}

fun JsonObject.str(k: String) = this[k]!!.jsonPrimitive.content
