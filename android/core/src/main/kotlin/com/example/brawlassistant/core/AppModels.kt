package com.example.brawlassistant.core

import kotlinx.serialization.Serializable

// 앱·서비스가 공유하는 모델 (iOS BrawlCore AppModels 와 같은 규칙). 시각은 epoch 밀리초.

@Serializable data class Recommendation(
    val mapId: MapId, val mapName: String, val mapNameEn: String, val gameMode: String, val gameModeEn: String,
    val rank: Int, val brawlers: List<TeamMember>, val score: Int, val estimatedWinRate: String,
    val reasons: List<String>, val archetype: String, val statsInfo: StatsInfo? = null, val updatedAt: Long,
) {
    /** 사용자에게 보이는 추천 내용이 같으면 같은 키 */
    val contentKey: String get() = "$mapId|$gameModeEn|${brawlers.joinToString(",") { it.id.toString() }}|$score|$estimatedWinRate"

    companion object {
        fun from(result: EngineResult, rank: Int = 1, at: Long = System.currentTimeMillis()): Recommendation? {
            val t = result.teams.firstOrNull { it.rank == rank } ?: return null
            return Recommendation(result.map.id, result.map.ko, result.map.name, result.map.modeKo, result.map.mode, t.rank, t.members,
                t.score, t.estimatedWinRate, t.plainReasons, t.archetype, result.stats, at)
        }
    }
}

@Serializable data class PickedBrawler(val brawlerId: Int, val side: Side, val confidence: Double) {
    @Serializable enum class Side { ally, enemy, unknown }
}

@Serializable data class GameRecognition(
    val recognizedMap: MapId? = null, val mapName: String? = null, val recognizedMode: String? = null,
    val confidence: Double, val timestamp: Long, val pickedBrawlers: List<PickedBrawler> = emptyList(),
)

@Serializable enum class AnalysisStatus(val title: String) {
    idle("분석 꺼짐"), waiting("화면 인식 대기"), broadcasting("화면 분석 중"), mapRecognized("맵 인식 완료"),
    computing("추천 계산 중"), ready("추천 완료"), mapFailed("맵 인식 실패"), modeFailed("모드 인식 실패"),
    noRecommendation("추천 데이터 없음"), ended("분석 종료");

    /** 추천 완료 상태가 아니면 추천을 보여 주지 않는다 (잘못된 추천 방지) */
    val hidesRecommendation: Boolean get() = this != ready
}

@Serializable data class AnalysisSession(
    val status: AnalysisStatus, val startedAt: Long? = null, val updatedAt: Long = System.currentTimeMillis(),
    val recognition: GameRecognition? = null, val recommendation: Recommendation? = null, val message: String? = null,
) { companion object { val idle = AnalysisSession(AnalysisStatus.idle, updatedAt = 0) } }
