package com.example.brawlassistant.engine

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ColorSpace
import androidx.core.graphics.scale
import com.example.brawlassistant.core.HttpFetcher
import com.example.brawlassistant.core.PixelDecoder
import com.example.brawlassistant.core.Pixels
import com.example.brawlassistant.core.Thumbnailer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/**
 * PNG → RGBA 원본 바이트. 웹 canvas getImageData 와 같게: 알파 미리곱 없이, 색 변환 없이(sRGB 그대로).
 * (회귀 테스트로 확인: 맵 PNG 에는 색 프로필이 없고, 원본 픽셀로 계산한 값이 브라우저와 같다)
 */
object AndroidPixels : PixelDecoder, Thumbnailer {
    override fun decode(png: ByteArray): Pixels? {
        val o = BitmapFactory.Options().apply {
            inPremultiplied = false
            inPreferredConfig = Bitmap.Config.ARGB_8888
            inPreferredColorSpace = ColorSpace.get(ColorSpace.Named.SRGB)
        }
        val bmp = BitmapFactory.decodeByteArray(png, 0, png.size, o) ?: return null
        val w = bmp.width; val h = bmp.height
        val argb = IntArray(w * h)
        bmp.getPixels(argb, 0, w, 0, 0, w, h)
        bmp.recycle()
        val out = ByteArray(w * h * 4)
        for (i in argb.indices) {
            val c = argb[i]
            out[i * 4] = (c shr 16).toByte(); out[i * 4 + 1] = (c shr 8).toByte(); out[i * 4 + 2] = c.toByte(); out[i * 4 + 3] = (c ushr 24).toByte()
        }
        return Pixels(out, w, h)
    }

    override fun thumbnail(image: ByteArray, side: Int): ByteArray? {
        val src = BitmapFactory.decodeByteArray(image, 0, image.size) ?: return null
        val scale = side.toFloat() / maxOf(src.width, src.height)
        val bmp = src.scale(maxOf(1, (src.width * scale).toInt()), maxOf(1, (src.height * scale).toInt()))
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
        return out.toByteArray()
    }
}

/** HTTP GET (요청에 사용자 정보는 넣지 않는다) */
object UrlFetcher : HttpFetcher {
    override suspend fun get(url: String): ByteArray = withContext(Dispatchers.IO) {
        val c = URL(url).openConnection() as HttpURLConnection
        c.connectTimeout = 15_000; c.readTimeout = 20_000
        c.setRequestProperty("User-Agent", "BrawlAssistant/0.1 (Android)")
        try {
            if (c.responseCode !in 200..299) throw IOException("HTTP ${c.responseCode} $url")
            c.inputStream.use { it.readBytes() }
        } finally { c.disconnect() }
    }
}
