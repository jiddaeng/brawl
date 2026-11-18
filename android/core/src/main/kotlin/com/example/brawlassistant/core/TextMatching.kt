package com.example.brawlassistant.core

import java.text.Normalizer
import kotlin.math.max
import kotlin.math.min

/** OCR 줄 ↔ 맵·모드·브롤러 이름 사전 비교 (iOS BrawlCore TextMatching 과 같은 규칙, 공유 벡터로 확인) */
object TextNormalizer {
    /** 영문 소문자·숫자·한글 음절만 남긴다 (NFC 로 합친 뒤) */
    fun normalize(s: String): String {
        val n = Normalizer.normalize(s, Normalizer.Form.NFC).lowercase()
        val sb = StringBuilder(n.length)
        for (c in n) if (c in 'a'..'z' || c in '0'..'9' || c in '가'..'힣') sb.append(c)
        return sb.toString()
    }

    fun distance(a: CharSequence, b: CharSequence): Int {
        if (a.isEmpty()) return b.length
        if (b.isEmpty()) return a.length
        var prev = IntArray(b.length + 1) { it }
        var cur = IntArray(b.length + 1)
        for (i in 1..a.length) {
            cur[0] = i
            for (j in 1..b.length) cur[j] = min(min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + if (a[i - 1] == b[j - 1]) 0 else 1)
            val t = prev; prev = cur; cur = t
        }
        return prev[b.length]
    }

    /** 0..1 유사도. 줄이 이름보다 길면 이름 길이 근처 구간들 중 최댓값 */
    fun similarity(line: String, name: String): Double {
        if (line.isEmpty() || name.isEmpty()) return 0.0
        fun sim(x: CharSequence) = 1 - distance(x, name).toDouble() / max(x.length, name.length)
        var best = sim(line)
        if (line.length > name.length + 1) {
            for (len in max(1, name.length - 1)..(name.length + 1)) {
                if (len > line.length) continue
                for (start in 0..(line.length - len)) {
                    best = max(best, sim(line.subSequence(start, start + len)))
                    if (best == 1.0) return 1.0
                }
            }
        }
        return best
    }

    fun threshold(length: Int): Double = when {
        length <= 3 -> 1.0
        length <= 5 -> 0.8
        else -> 0.78
    }
}

data class TextMatch<V>(val value: V, val matchedText: String, val similarity: Double)

class NameDictionary<V> {
    private data class Entry<V>(val value: V, val text: String, val key: String)
    private val entries = mutableListOf<Entry<V>>()

    fun add(value: V, names: List<String>) {
        val seen = HashSet<String>()
        for (n in names) if (seen.add(n)) {
            val k = TextNormalizer.normalize(n)
            if (k.isNotEmpty()) entries.add(Entry(value, n, k))
        }
    }

    /** 기준을 넘는 후보 (값별 최고). 정렬: 유사도 내림차순, 같으면 사전에 먼저 넣은 순서 */
    fun matches(line: String, minimumLength: Int = 1): List<TextMatch<V>> {
        val l = TextNormalizer.normalize(line)
        if (l.isEmpty()) return emptyList()
        val best = HashMap<V, TextMatch<V>>()
        val firstSeen = HashMap<V, Int>()
        entries.forEachIndexed { order, e ->
            if (e.key.length < minimumLength) return@forEachIndexed
            if (l.length * 10 < e.key.length * 7) return@forEachIndexed
            val s = if (e.key.length <= 3) (if (l == e.key) 1.0 else 0.0) else TextNormalizer.similarity(l, e.key)
            if (s < TextNormalizer.threshold(e.key.length)) return@forEachIndexed
            firstSeen.putIfAbsent(e.value, order)
            if ((best[e.value]?.similarity ?: -1.0) < s) best[e.value] = TextMatch(e.value, e.text, s)
        }
        return best.values.sortedWith(compareByDescending<TextMatch<V>> { it.similarity }.thenBy { firstSeen[it.value]!! })
    }
}

/** OCR 한 줄 (화면 기준 정규화 좌표, 왼쪽 위 원점) */
data class OcrLine(val text: String, val confidence: Double, val midX: Double, val midY: Double)

class GameScreenMatcher(catalog: EngineCatalog) {
    data class FrameResult(
        val map: CatalogMap?, val ambiguousMaps: List<CatalogMap>, val mode: String?,
        val mapConfidence: Double, val picks: List<PickedBrawler>,
    )

    private val maps = catalog.maps
    private val mapDict = NameDictionary<Int>()
    private val modeDict = NameDictionary<String>()
    private val brawlerDict = NameDictionary<Int>()

    init {
        maps.forEachIndexed { i, m -> mapDict.add(i, listOf(m.name, m.ko)) }
        val modes = LinkedHashMap<String, MutableSet<String>>()
        for (m in maps) modes.getOrPut(m.mode) { mutableSetOf() }.addAll(listOf(m.mode, m.modeKo))
        for ((k, v) in modes) modeDict.add(k, listOf(k) + v.filter { it != k }.sorted())
        for (b in catalog.brawlers) brawlerDict.add(b.id, listOf(b.name, b.ko))
    }

    fun analyze(lines: List<OcrLine>, minimumLineConfidence: Double = 0.3): FrameResult {
        val usable = lines.filter { it.confidence >= minimumLineConfidence }
        var modeHit: TextMatch<String>? = null
        for (l in usable) {
            val m = modeDict.matches(l.text, 2).firstOrNull() ?: continue
            if (m.similarity > (modeHit?.similarity ?: 0.0)) modeHit = m
        }
        val hits = ArrayList<Pair<Int, Double>>()
        for (l in usable) for (m in mapDict.matches(l.text, 3)) hits.add(m.value to m.similarity * l.confidence.coerceIn(0.5, 1.0))

        var map: CatalogMap? = null
        var ambiguous: List<CatalogMap> = emptyList()
        var conf = 0.0
        var mode = modeHit?.value
        val top = hits.maxByOrNull { it.second }
        if (top != null) {
            val norm = { i: Int -> TextNormalizer.normalize(maps[i].name) }
            val topName = norm(top.first)
            val sameName = hits.filter { norm(it.first) == topName }.map { it.first }.toSortedSet().map { maps[it] }
            val rivals = hits.filter { it.second >= top.second - 0.05 && norm(it.first) != topName }.map { it.first }.toSortedSet().toList()
            if (rivals.isEmpty()) {
                when {
                    sameName.size == 1 -> map = sameName[0]
                    modeHit != null && sameName.any { it.mode == modeHit.value } -> map = sameName.first { it.mode == modeHit.value }
                    else -> ambiguous = sameName.sortedBy { it.mode }
                }
            } else {
                ambiguous = (listOf(top.first) + rivals).map { maps[it] }
            }
            conf = top.second
            if (map != null && mode == null) mode = map.mode
        }
        // 브롤러(실험): 정확히 읽힌 이름만. 화면 왼쪽 = 우리 팀, 오른쪽 = 상대 팀으로 추정
        val picks = HashMap<Int, PickedBrawler>()
        for (l in usable) {
            if (l.confidence < 0.5) continue
            val b = brawlerDict.matches(l.text, 1).firstOrNull() ?: continue
            if (b.similarity < 0.9) continue
            val side = if (l.midX < 0.4) PickedBrawler.Side.ally else if (l.midX > 0.6) PickedBrawler.Side.enemy else PickedBrawler.Side.unknown
            val p = PickedBrawler(b.value, side, b.similarity * l.confidence)
            if ((picks[b.value]?.confidence ?: 0.0) < p.confidence) picks[b.value] = p
        }
        return FrameResult(map, ambiguous, mode, conf, picks.values.sortedBy { it.brawlerId })
    }
}
