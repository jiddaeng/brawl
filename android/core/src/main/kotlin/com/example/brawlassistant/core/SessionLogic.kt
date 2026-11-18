package com.example.brawlassistant.core

import kotlinx.serialization.Serializable

/** 화면 분석 세션 상태 전이 (iOS SessionReducer 와 같은 규칙). 확정되지 않은 인식으로는 추천을 보여 주지 않는다 */
class SessionReducer(var session: AnalysisSession = AnalysisSession.idle, private val lookup: (MapId) -> EngineResult?) {
    sealed class Input {
        data class Started(val at: Long) : Input()
        data class Heartbeat(val at: Long) : Input()
        data class Recognition(val event: RecognitionStabilizer.Event, val frame: GameScreenMatcher.FrameResult?, val at: Long) : Input()
        data class RecommendationsChanged(val at: Long) : Input()
        data class Retry(val at: Long) : Input()
        data class CatalogMissing(val at: Long) : Input()
        data class Finished(val at: Long) : Input()
    }

    companion object {
        const val MAP_FAILED = "맵 이름을 찾지 못했습니다. 로비의 이벤트 선택 화면이나 드래프트·로딩 화면을 띄워 주세요."
        const val NO_RECOMMENDATION = "이 맵의 추천을 계산하고 있습니다."
        const val CATALOG_MISSING = "맵 데이터가 없습니다. 앱에서 데이터를 먼저 불러와 주세요."
    }

    /** 반환: 저장·알림이 필요한 변화가 있었는지 */
    fun reduce(input: Input): Boolean {
        val before = session
        var s = session
        when (input) {
            is Input.Started -> s = AnalysisSession(AnalysisStatus.broadcasting, startedAt = input.at, updatedAt = input.at)
            is Input.Heartbeat -> { session = s.copy(updatedAt = input.at); return false }
            is Input.Retry -> s = AnalysisSession(AnalysisStatus.broadcasting, startedAt = s.startedAt ?: input.at, updatedAt = input.at)
            is Input.CatalogMissing -> s = s.copy(status = AnalysisStatus.mapFailed, message = CATALOG_MISSING, recommendation = null, updatedAt = input.at)
            is Input.Finished -> s = s.copy(status = AnalysisStatus.ended, updatedAt = input.at, message = null)
            is Input.RecommendationsChanged -> {
                val id = s.recognition?.recognizedMap
                if (s.status == AnalysisStatus.noRecommendation && id != null) s = apply(s, id, input.at)
            }
            is Input.Recognition -> when (val e = input.event) {
                is RecognitionStabilizer.Event.Recognized -> {
                    val r = GameRecognition(e.map.id, e.map.ko, e.map.mode, e.confidence, input.at, input.frame?.picks ?: emptyList())
                    s = apply(s.copy(recognition = r, status = AnalysisStatus.mapRecognized), e.map.id, input.at)
                }
                is RecognitionStabilizer.Event.ModeAmbiguous -> if (s.recognition == null) {
                    s = s.copy(status = AnalysisStatus.modeFailed, recommendation = null, updatedAt = input.at,
                        message = "‘${e.maps.firstOrNull()?.ko ?: ""}’ 맵은 여러 모드(${e.maps.joinToString(", ") { it.modeKo }})에 있습니다. 모드 이름이 함께 보이는 화면을 띄워 주세요.")
                }
                RecognitionStabilizer.Event.Failed -> if (s.recognition == null) {
                    s = s.copy(status = AnalysisStatus.mapFailed, recommendation = null, message = MAP_FAILED, updatedAt = input.at)
                }
                RecognitionStabilizer.Event.None -> {
                    val picks = input.frame?.picks.orEmpty()
                    val r = s.recognition
                    if (picks.isNotEmpty() && r != null && r.pickedBrawlers != picks && input.frame?.map?.id == r.recognizedMap) {
                        s = s.copy(recognition = r.copy(pickedBrawlers = picks), updatedAt = input.at)
                    }
                }
            }
        }
        session = s
        return s != before
    }

    private fun apply(s: AnalysisSession, id: MapId, at: Long): AnalysisSession {
        val rec = lookup(id)?.let { Recommendation.from(it, at = at) }
        return if (rec != null) s.copy(status = AnalysisStatus.ready, recommendation = rec, message = null, updatedAt = at)
        else s.copy(status = AnalysisStatus.noRecommendation, recommendation = null, message = NO_RECOMMENDATION, updatedAt = at)
    }
}

/** 영문 모드 → 한국어 (카탈로그에서 채운다) */
object ModeNames {
    @Volatile var korean: Map<String, String> = emptyMap(); private set
    fun register(c: EngineCatalog) { korean = korean + c.maps.associate { it.mode to it.modeKo } }
}

/** 상태 알림(Android Live Update)·iOS Live Activity 에 보여 줄 값 */
@Serializable data class LiveDisplayState(
    val status: AnalysisStatus, val mapName: String? = null, val modeName: String? = null,
    val members: List<Member> = emptyList(), val score: Int? = null, val winRate: String? = null,
    val message: String? = null, val updatedAt: Long,
) {
    @Serializable data class Member(val id: Int, val name: String)

    val contentKey: String get() = listOf(status.name, mapName ?: "", modeName ?: "", members.joinToString(",") { it.id.toString() },
        score?.toString() ?: "", winRate ?: "", message ?: "").joinToString("|")

    companion object {
        fun from(session: AnalysisSession): LiveDisplayState {
            var st = LiveDisplayState(session.status, updatedAt = session.updatedAt, message = session.message,
                mapName = session.recognition?.mapName, modeName = session.recognition?.recognizedMode)
            val rec = session.recommendation
            if (!session.status.hidesRecommendation && rec != null) {
                st = st.copy(mapName = rec.mapName, modeName = rec.gameMode, members = rec.brawlers.take(5).map { Member(it.id, it.ko) },
                    score = rec.score, winRate = rec.estimatedWinRate)
            } else {
                session.recognition?.recognizedMode?.let { st = st.copy(modeName = ModeNames.korean[it] ?: it) }
            }
            return st
        }

        fun manual(rec: Recommendation) = LiveDisplayState(AnalysisStatus.ready, rec.mapName, rec.gameMode,
            rec.brawlers.take(5).map { Member(it.id, it.ko) }, rec.score, rec.estimatedWinRate, null, rec.updatedAt)
    }
}

/** 메인 화면 표시 규칙 (iOS HomePresentation 과 같은 규칙) */
data class HomePresentation(
    val statusTitle: String, val statusDetail: String?, val isError: Boolean, val recommendation: Recommendation?,
    val recognition: GameRecognition?, val captureActive: Boolean, val canRetry: Boolean, val isManual: Boolean,
) {
    companion object {
        val activeStatuses = setOf(AnalysisStatus.broadcasting, AnalysisStatus.mapRecognized, AnalysisStatus.computing, AnalysisStatus.ready,
            AnalysisStatus.mapFailed, AnalysisStatus.modeFailed, AnalysisStatus.noRecommendation)

        /** heartbeatTimeoutMs: 분석 서비스가 이 시간 넘게 소식이 없으면 끊긴 것으로 본다 */
        fun make(s: AnalysisSession, manual: Recommendation?, computing: Boolean = false, now: Long,
                 heartbeatTimeoutMs: Long = 30_000, waitingTimeoutMs: Long = 60_000): HomePresentation {
            var p = HomePresentation(s.status.title, s.message, false, null, s.recognition, false, false, false)
            val active = s.status in activeStatuses
            if (active && now - s.updatedAt > heartbeatTimeoutMs) {
                return p.copy(statusTitle = "분석 연결 끊김", statusDetail = "화면 분석이 종료되었거나 중단되었습니다. 다시 시작하세요.",
                    isError = true, canRetry = true, recognition = null)
            }
            p = p.copy(captureActive = active)
            p = when (s.status) {
                AnalysisStatus.idle, AnalysisStatus.ended ->
                    if (manual != null) p.copy(statusTitle = AnalysisStatus.ready.title, statusDetail = "직접 고른 맵", recommendation = manual, isManual = true)
                    else p.copy(statusTitle = if (s.status == AnalysisStatus.ended) AnalysisStatus.ended.title else AnalysisStatus.waiting.title,
                        statusDetail = "‘화면 분석 시작’을 누르고 브롤스타즈를 실행하세요.")
                AnalysisStatus.waiting ->
                    if (now - s.updatedAt > waitingTimeoutMs) p.copy(statusDetail = "화면 공유가 시작되지 않았습니다. 다시 시도하세요.", isError = true, canRetry = true)
                    else p.copy(statusDetail = "화면 공유 창에서 브롤스타즈(또는 전체 화면)를 고르고 시작하세요.")
                AnalysisStatus.broadcasting -> p.copy(statusDetail = "브롤스타즈에서 맵 이름이 보이는 화면을 띄우면 인식합니다.")
                AnalysisStatus.mapRecognized, AnalysisStatus.computing -> p.copy(statusTitle = if (computing) AnalysisStatus.computing.title else s.status.title)
                AnalysisStatus.ready -> p.copy(recommendation = s.recommendation,
                    statusDetail = s.recognition?.let { "인식 신뢰도 ${Math.round(it.confidence * 100)}%" } ?: p.statusDetail)
                AnalysisStatus.mapFailed, AnalysisStatus.modeFailed, AnalysisStatus.noRecommendation ->
                    p.copy(isError = s.status != AnalysisStatus.noRecommendation, canRetry = true,
                        statusTitle = if (s.status == AnalysisStatus.noRecommendation && computing) AnalysisStatus.computing.title else p.statusTitle)
            }
            return p
        }
    }
}
