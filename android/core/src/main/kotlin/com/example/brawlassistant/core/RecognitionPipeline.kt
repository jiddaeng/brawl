package com.example.brawlassistant.core

import kotlin.math.abs

/** 프레임 샘플링 (iOS FrameSampler 와 같은 규칙). 시각은 ms */
class FrameSampler(val minIntervalMs: Long = 1000, val maxIntervalMs: Long = 8000, val changeThreshold: Double = 4.0) {
    var lastAnalyzedAt: Long? = null; private set
    var lastSignature: ByteArray? = null; private set
    var busy = false; private set

    fun isDue(now: Long): Boolean {
        if (busy) return false
        val t = lastAnalyzedAt ?: return true
        return now - t >= minIntervalMs
    }

    fun shouldAnalyze(signature: ByteArray, now: Long): Boolean {
        if (!isDue(now)) return false
        val t = lastAnalyzedAt; val last = lastSignature
        if (t != null && last != null && difference(last, signature) < changeThreshold && now - t < maxIntervalMs) return false
        lastAnalyzedAt = now; lastSignature = signature; busy = true
        return true
    }

    fun finish() { busy = false }

    companion object {
        fun difference(a: ByteArray, b: ByteArray): Double {
            if (a.size != b.size || a.isEmpty()) return Double.POSITIVE_INFINITY
            var s = 0L
            for (i in a.indices) s += abs((a[i].toInt() and 0xFF) - (b[i].toInt() and 0xFF))
            return s.toDouble() / a.size
        }
    }
}

/** 프레임별 인식을 모아 안정된 인식만 내보낸다 (iOS RecognitionStabilizer 와 같은 규칙) */
class RecognitionStabilizer(val requiredAgreement: Int = 2, val agreementWindowMs: Long = 10_000, val failAfterMs: Long = 25_000) {
    sealed class Event {
        object None : Event()
        data class Recognized(val map: CatalogMap, val confidence: Double) : Event()
        data class ModeAmbiguous(val maps: List<CatalogMap>) : Event()
        object Failed : Event()
    }

    var current: CatalogMap? = null; private set
    var currentConfidence = 0.0; private set
    var lastSeen: Long? = null; private set
    private data class Candidate(val map: CatalogMap, val count: Int, val first: Long, val conf: Double)
    private var candidate: Candidate? = null
    private var ambiguousCount = 0
    private var startedAt: Long? = null
    private var failedReported = false

    fun start(at: Long) { startedAt = at; current = null; candidate = null; lastSeen = null; failedReported = false; ambiguousCount = 0 }

    fun feed(r: GameScreenMatcher.FrameResult, now: Long): Event {
        if (startedAt == null) startedAt = now
        val m = r.map
        if (m != null) {
            ambiguousCount = 0
            if (m == current) { lastSeen = now; candidate = null; currentConfidence = maxOf(currentConfidence * 0.8, r.mapConfidence); return Event.None }
            val c = candidate
            candidate = if (c != null && c.map == m && now - c.first <= agreementWindowMs)
                Candidate(m, c.count + 1, c.first, (c.conf * c.count + r.mapConfidence) / (c.count + 1))
            else Candidate(m, 1, now, r.mapConfidence)
            val n = candidate!!
            if (n.count >= requiredAgreement) {
                current = n.map; currentConfidence = n.conf; lastSeen = now; candidate = null; failedReported = false
                return Event.Recognized(n.map, n.conf)
            }
            return Event.None
        }
        if (r.ambiguousMaps.isNotEmpty()) {
            ambiguousCount += 1
            return if (ambiguousCount >= requiredAgreement && current == null) Event.ModeAmbiguous(r.ambiguousMaps) else Event.None
        }
        val s = startedAt
        if (current == null && !failedReported && s != null && now - s >= failAfterMs) { failedReported = true; return Event.Failed }
        return Event.None
    }
}

/** 상태 알림(iOS Live Activity) 갱신 정책: 보이는 내용이 바뀔 때만, 최소 간격을 두고 */
class LiveUpdatePolicy(val minIntervalMs: Long = 5000) {
    sealed class Decision { object Skip : Decision(); object UpdateNow : Decision(); data class DeferUntil(val at: Long) : Decision() }
    var publishedKey: String? = null; private set
    var publishedAt: Long? = null; private set

    fun decide(key: String, now: Long): Decision {
        if (key == publishedKey) return Decision.Skip
        val t = publishedAt
        if (t != null && now - t < minIntervalMs) return Decision.DeferUntil(t + minIntervalMs)
        return Decision.UpdateNow
    }

    fun markPublished(key: String, at: Long) { publishedKey = key; publishedAt = at }
    fun reset() { publishedKey = null; publishedAt = null }
}
