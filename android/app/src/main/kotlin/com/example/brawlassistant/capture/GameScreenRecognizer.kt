package com.example.brawlassistant.capture

import com.example.brawlassistant.AppGraph
import com.example.brawlassistant.core.*
import kotlinx.coroutines.launch

/**
 * OCR 결과 → 맵·모드 확정 → 세션 → 추천. 규칙은 core(iOS 와 같은 GameScreenMatcher·RecognitionStabilizer·SessionReducer).
 * 한 스레드(분석 디스패처)에서만 호출된다.
 */
class GameScreenRecognizer(private val graph: AppGraph, private val onChange: (AnalysisSession) -> Unit) {
    private var matcher: GameScreenMatcher? = null
    private var matcherFor: EngineCatalog? = null
    private val stabilizer = RecognitionStabilizer(requiredAgreement = 2, agreementWindowMs = 10_000, failAfterMs = 25_000)
    private val reducer = SessionReducer { id -> graph.store.recommendation(id) }
    private var computingFor: MapId? = null
    private var picksAppliedFor: List<PickedBrawler>? = null

    private fun ensureMatcher(): GameScreenMatcher? {
        val cat = graph.catalog.value ?: return null
        if (cat !== matcherFor) { matcher = GameScreenMatcher(cat); matcherFor = cat }
        return matcher
    }

    fun start(now: Long) {
        stabilizer.start(now)
        reducer.reduce(SessionReducer.Input.Started(now))
        if (ensureMatcher() == null) reducer.reduce(SessionReducer.Input.CatalogMissing(now))
        commit()
    }

    fun retry(now: Long) {
        stabilizer.start(now); picksAppliedFor = null
        reducer.reduce(SessionReducer.Input.Retry(now))
        commit()
    }

    fun heartbeat(now: Long) {
        reducer.reduce(SessionReducer.Input.Heartbeat(now))
        graph.publishSession(reducer.session, persist = false)
    }

    fun process(lines: List<OcrLine>, now: Long) {
        val m = ensureMatcher() ?: return
        val frame = m.analyze(lines)
        val event = stabilizer.feed(frame, now)
        if (reducer.reduce(SessionReducer.Input.Recognition(event, frame, now))) commit()
    }

    fun recommendationsChanged(now: Long) { if (reducer.reduce(SessionReducer.Input.RecommendationsChanged(now))) commit() }

    fun finish(now: Long) { reducer.reduce(SessionReducer.Input.Finished(now)); commit() }

    private fun commit() {
        val s = reducer.session
        graph.publishSession(s)
        onChange(s)
        val rec = s.recognition
        val map = rec?.recognizedMap?.let { id -> graph.catalog.value?.maps?.firstOrNull { it.id == id } } ?: return
        when {
            // 미리 계산되지 않은 맵: 바로 계산 (Android 는 앱 프로세스가 살아 있으므로 게임 중에도 가능)
            s.status == AnalysisStatus.noRecommendation && computingFor != map.id -> {
                computingFor = map.id
                graph.setComputing(true)
                graph.scope.launch {
                    runCatching { graph.recommend(map) }.onFailure { graph.alert("추천 계산 실패: ${it.message}") }
                    graph.setComputing(false)
                    computingFor = null
                    onRecomputed?.invoke()
                }
            }
            // 실험: 드래프트 픽이 읽히면 픽을 반영해 다시 계산
            s.status == AnalysisStatus.ready && graph.usePicks && rec.pickedBrawlers.isNotEmpty() && rec.pickedBrawlers != picksAppliedFor -> {
                picksAppliedFor = rec.pickedBrawlers
                graph.scope.launch {
                    val r = runCatching { graph.recommend(map, rec.pickedBrawlers) }.getOrNull() ?: return@launch
                    val updated = Recommendation.from(r) ?: return@launch
                    onPicksApplied?.invoke(updated)
                }
            }
        }
    }

    /** 서비스가 연결: 계산이 끝나면 분석 스레드에서 recommendationsChanged 를 부른다 */
    var onRecomputed: (() -> Unit)? = null
    /** 서비스가 연결: 픽 반영 결과를 분석 스레드에서 적용 */
    var onPicksApplied: ((Recommendation) -> Unit)? = null

    fun applyPicks(rec: Recommendation, now: Long) {
        val s = reducer.session
        if (s.status != AnalysisStatus.ready || s.recognition?.recognizedMap != rec.mapId) return
        reducer.session = s.copy(recommendation = rec, updatedAt = now)
        commit()
    }
}
