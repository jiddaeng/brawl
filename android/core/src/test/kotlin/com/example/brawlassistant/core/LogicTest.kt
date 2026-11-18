package com.example.brawlassistant.core

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.builtins.ListSerializer
import org.junit.Assert.*
import org.junit.Test

class ModelTest {
    @Test fun recommendationComesFromEngineResult() {
        val r = Fixtures.result("result-bounty")
        val rec = Recommendation.from(r)!!
        assertEquals(3, rec.brawlers.size)
        assertEquals("기습적 움직임", rec.mapName)
        assertEquals("바운티", rec.gameMode)
        assertEquals(r.teams[0].score, rec.score)
        assertEquals(r.teams[0].estimatedWinRate, rec.estimatedWinRate)
        assertEquals(listOf("파이퍼", "코스모", "볼트"), rec.brawlers.map { it.ko })
        assertNotNull(Recommendation.from(r, rank = 2)); assertNull(Recommendation.from(r, rank = 99))
    }

    @Test fun teamSizeFollowsEngine() {
        assertEquals(5, Recommendation.from(Fixtures.result("result-5v5"))!!.brawlers.size)
        val solo = Recommendation.from(Fixtures.result("result-solo"))!!
        assertEquals(1, solo.brawlers.size); assertNull(solo.brawlers[0].pick)
    }

    @Test fun displayStringsComeFromEngine() {
        val m = Fixtures.result("result-bounty").teams[0].members
        assertEquals("+11.1", m.first { it.name == "Bolt" }.effPct)
        assertEquals("3,276", Fixtures.result("result-bounty").countText)
    }

    @Test fun contentKeyAndEntities() {
        val r = Fixtures.result("result-bounty")
        assertEquals(Recommendation.from(r, at = 1)!!.contentKey, Recommendation.from(r, at = 99)!!.contentKey)
        assertNotEquals(Recommendation.from(r)!!.contentKey, Recommendation.from(r, rank = 2)!!.contentKey)
        assertEquals("래리 & 로리 <b> \"x\"", HtmlEntities.decode("래리 &amp; 로리 &lt;b&gt; &quot;x&quot;"))
        assertEquals("&lt;", HtmlEntities.decode("&amp;lt;"))
    }

    @Test fun mapIdJson() {
        val ids = listOf(MapId.Num(15001395), MapId.Str("bt-gemGrab-x"))
        val s = EngineJson.encodeToString(ListSerializer(MapId.serializer()), ids)
        assertEquals("[15001395,\"bt-gemGrab-x\"]", s)
        assertEquals(ids, EngineJson.decodeFromString(ListSerializer(MapId.serializer()), s))
        assertEquals("\"a\\\"b\"", MapId.Str("a\"b").jsonLiteral)
    }

    @Test fun statusHidesRecommendationUnlessReady() {
        for (s in AnalysisStatus.entries) assertEquals(s.name, s != AnalysisStatus.ready, s.hidesRecommendation)
    }
}

class PipelineTest {
    private val matcher = GameScreenMatcher(Fixtures.catalog)
    private val t0 = 1_000_000_000L

    @Test fun frameSampler() {
        val f = FrameSampler(1000, 8000, 4.0)
        val a = ByteArray(144) { 100 }; val b = ByteArray(144) { 140.toByte() }
        assertTrue(f.shouldAnalyze(a, t0))
        assertFalse("분석 중", f.isDue(t0 + 2000))
        f.finish()
        assertFalse("최소 간격", f.shouldAnalyze(b, t0 + 500))
        assertFalse("화면 변화 없음", f.shouldAnalyze(a, t0 + 3000))
        assertTrue("화면 바뀜", f.shouldAnalyze(b, t0 + 3000))
        f.finish()
        assertTrue("maxInterval 뒤 재확인", f.shouldAnalyze(b, t0 + 12000))
    }

    @Test fun liveUpdatePolicy() {
        val p = LiveUpdatePolicy(5000)
        assertEquals(LiveUpdatePolicy.Decision.UpdateNow, p.decide("A", t0))
        p.markPublished("A", t0)
        assertEquals(LiveUpdatePolicy.Decision.Skip, p.decide("A", t0 + 60000))
        assertEquals(LiveUpdatePolicy.Decision.DeferUntil(t0 + 5000), p.decide("B", t0 + 2000))
        assertEquals(LiveUpdatePolicy.Decision.UpdateNow, p.decide("B", t0 + 6000))
    }

    @Test fun normalizeAndSimilarity() {
        assertEquals("기습적움직임", TextNormalizer.normalize("기습적 움직임!"))
        assertEquals("dontleafme", TextNormalizer.normalize("Don't Leaf Me"))
        // 자모가 분리된(NFD) 한글도 같은 글자로 본다
        assertEquals("가", TextNormalizer.normalize(java.text.Normalizer.normalize("가", java.text.Normalizer.Form.NFD)))
        assertEquals(3, TextNormalizer.distance("kitten", "sitting"))
        assertEquals(1.0, TextNormalizer.similarity(TextNormalizer.normalize("바운티 · 기습적 움직임 ·  3:00"), TextNormalizer.normalize("기습적 움직임")), 0.0)
    }
}

class SessionLogicTest {
    private val t0 = 2_000_000_000L
    private val bounty = Fixtures.map(15001395)
    private fun reducer(has: Boolean = true) = SessionReducer { id -> if (has && id == MapId.Num(15001395)) Fixtures.result("result-bounty") else null }
    private fun rec(m: CatalogMap, c: Double = 0.9) = RecognitionStabilizer.Event.Recognized(m, c)

    @Test fun recognizedWithPrecomputedBecomesReady() {
        val r = reducer()
        r.reduce(SessionReducer.Input.Started(t0))
        assertEquals(AnalysisStatus.broadcasting, r.session.status)
        assertTrue(r.reduce(SessionReducer.Input.Recognition(rec(bounty, 0.92), null, t0 + 3000)))
        assertEquals(AnalysisStatus.ready, r.session.status)
        assertEquals(listOf("파이퍼", "코스모", "볼트"), r.session.recommendation!!.brawlers.map { it.ko })
        assertEquals(0.92, r.session.recognition!!.confidence, 0.0)
    }

    @Test fun missingRecommendationShowsNothing() {
        val r = reducer(false)
        r.reduce(SessionReducer.Input.Started(t0)); r.reduce(SessionReducer.Input.Recognition(rec(bounty), null, t0))
        assertEquals(AnalysisStatus.noRecommendation, r.session.status)
        assertNull(r.session.recommendation); assertNull(LiveDisplayState.from(r.session).score)
    }

    @Test fun recommendationsChangedResolvesPending() {
        var have = false
        val r = SessionReducer { if (have) Fixtures.result("result-bounty") else null }
        r.reduce(SessionReducer.Input.Started(t0)); r.reduce(SessionReducer.Input.Recognition(rec(bounty), null, t0))
        have = true
        assertTrue(r.reduce(SessionReducer.Input.RecommendationsChanged(t0 + 5000)))
        assertEquals(AnalysisStatus.ready, r.session.status)
    }

    @Test fun failureOnlyBeforeMapKnown() {
        val r = reducer()
        r.reduce(SessionReducer.Input.Started(t0))
        r.reduce(SessionReducer.Input.Recognition(RecognitionStabilizer.Event.Failed, null, t0 + 30000))
        assertEquals(AnalysisStatus.mapFailed, r.session.status)
        val rock = Fixtures.catalog.maps.filter { it.name == "Rockwall Brawl" }
        r.reduce(SessionReducer.Input.Recognition(RecognitionStabilizer.Event.ModeAmbiguous(rock), null, t0 + 31000))
        assertEquals(AnalysisStatus.modeFailed, r.session.status)
        assertTrue(r.session.message!!.contains("바위 장벽 전투"))
        r.reduce(SessionReducer.Input.Recognition(rec(bounty), null, t0 + 40000))
        r.reduce(SessionReducer.Input.Recognition(RecognitionStabilizer.Event.Failed, null, t0 + 90000))
        assertEquals("맵을 아는 상태에서는 추천 유지", AnalysisStatus.ready, r.session.status)
    }

    @Test fun retryAndHeartbeat() {
        val r = reducer()
        r.reduce(SessionReducer.Input.Started(t0)); r.reduce(SessionReducer.Input.Recognition(rec(bounty), null, t0))
        r.reduce(SessionReducer.Input.Retry(t0 + 10000))
        assertEquals(AnalysisStatus.broadcasting, r.session.status); assertNull(r.session.recognition); assertEquals(t0, r.session.startedAt)
        assertFalse(r.reduce(SessionReducer.Input.Heartbeat(t0 + 20000)))
        assertEquals(t0 + 20000, r.session.updatedAt)
    }

    @Test fun liveDisplayState() {
        val r = reducer()
        r.reduce(SessionReducer.Input.Started(t0))
        val waiting = LiveDisplayState.from(r.session)
        r.reduce(SessionReducer.Input.Recognition(rec(bounty), null, t0))
        val ready = LiveDisplayState.from(r.session)
        assertEquals(listOf("파이퍼", "코스모", "볼트"), ready.members.map { it.name })
        assertEquals("기습적 움직임", ready.mapName); assertEquals("바운티", ready.modeName); assertEquals(84, ready.score)
        assertNotEquals(waiting.contentKey, ready.contentKey)
        r.reduce(SessionReducer.Input.Heartbeat(t0 + 20000))
        assertEquals(ready.contentKey, LiveDisplayState.from(r.session).contentKey)
    }

    @Test fun homePresentation() {
        val rec = Recommendation.from(Fixtures.result("result-bounty"))!!
        val r = reducer()
        r.reduce(SessionReducer.Input.Started(t0)); r.reduce(SessionReducer.Input.Recognition(rec(bounty), null, t0))
        val ready = HomePresentation.make(r.session, null, now = t0 + 5000)
        assertEquals("추천 완료", ready.statusTitle); assertEquals(84, ready.recommendation!!.score); assertTrue(ready.captureActive)
        val stale = HomePresentation.make(r.session, null, now = t0 + 120_000)
        assertEquals("분석 연결 끊김", stale.statusTitle); assertNull(stale.recommendation); assertTrue(stale.canRetry)
        assertEquals("화면 인식 대기", HomePresentation.make(AnalysisSession.idle, null, now = t0).statusTitle)
        assertTrue(HomePresentation.make(AnalysisSession.idle, rec, now = t0).isManual)
        val failed = HomePresentation.make(AnalysisSession(AnalysisStatus.mapFailed, updatedAt = t0, message = "x"), rec, now = t0)
        assertNull("인식 실패 중에는 추천 숨김", failed.recommendation); assertTrue(failed.isError && failed.canRetry)
        assertTrue(HomePresentation.make(AnalysisSession(AnalysisStatus.waiting, updatedAt = t0), null, now = t0 + 90_000).isError)
    }
}

class StoreAndSourceTest {
    private val maps = """{"list":[{"id":1,"name":"A","gameMode":{"name":"Gem Grab"}}]}"""
    private val brawlers = """{"list":[{"id":7,"name":"Shelly","class":{"name":"Damage Dealer"}}]}"""
    private val strength = """{"from":"a","until":"b","files":{"maps":{}}}"""

    class Fake(var responses: Map<String, String> = emptyMap()) : HttpFetcher {
        override suspend fun get(url: String) = responses[url]?.toByteArray() ?: throw java.io.IOException("offline $url")
    }

    @Test fun sessionRoundTrip() {
        val s = tempStore()
        val rec = Recommendation.from(Fixtures.result("result-bounty"), at = 123)!!
        val session = AnalysisSession(AnalysisStatus.ready, 10, 20, GameRecognition(rec.mapId, rec.mapName, "Bounty", 0.9, 20), rec)
        s.write(AnalysisSession.serializer(), session, FileStore.Entry.Session)
        assertEquals(session, s.read(AnalysisSession.serializer(), FileStore.Entry.Session))
        assertNull(s.read(AnalysisSession.serializer(), FileStore.Entry.Catalog))
    }

    @Test fun onlineThenOffline() = runTest {
        val store = tempStore()
        val f = Fake(mapOf(Endpoints.BRAWLIFY_MAPS to maps, Endpoints.BRAWLIFY_BRAWLERS to brawlers, Endpoints.BRAWLTIME_STRENGTH to strength))
        val online = DataSourceLoader(f, store) { 5 }.load()
        assertNull(online.cachedAt); assertEquals("A", online.maps[0].name); assertEquals(strength, online.strength)
        f.responses = emptyMap()
        val offline = DataSourceLoader(f, store).load()
        assertEquals(5L, offline.cachedAt); assertEquals("Shelly", offline.brawlers[0].name); assertEquals(strength, offline.strength)
    }

    @Test fun oneFailureWithoutCacheThrows() = runTest {
        try { DataSourceLoader(Fake(mapOf(Endpoints.BRAWLIFY_MAPS to maps)), tempStore()).load(); fail() } catch (e: DataSourceException) {}
    }

    @Test fun badStrengthWithoutCacheIsNull() = runTest {
        val r = DataSourceLoader(Fake(mapOf(Endpoints.BRAWLIFY_MAPS to maps, Endpoints.BRAWLIFY_BRAWLERS to brawlers, Endpoints.BRAWLTIME_STRENGTH to "not json")), tempStore()).load()
        assertNull(r.strength); assertNull(r.cachedAt)
    }
}
