package com.example.brawlassistant.capture

import android.graphics.Bitmap
import com.example.brawlassistant.core.OcrLine
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
import kotlinx.coroutines.tasks.await

/** ML Kit 한국어 글자 인식 (기기 안에서 처리, 라틴 문자 포함). 화면은 저장·전송하지 않는다 */
class TextRecognizer : AutoCloseable {
    private val client = TextRecognition.getClient(KoreanTextRecognizerOptions.Builder().build())

    suspend fun lines(bmp: Bitmap): List<OcrLine> {
        val text = client.process(InputImage.fromBitmap(bmp, 0)).await()
        val w = bmp.width.toDouble(); val h = bmp.height.toDouble()
        return text.textBlocks.flatMap { it.lines }.mapNotNull { l ->
            val b = l.boundingBox ?: return@mapNotNull null
            OcrLine(l.text, l.confidence.toDouble(), b.exactCenterX() / w, b.exactCenterY() / h)
        }
    }

    override fun close() = client.close()
}
