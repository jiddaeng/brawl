package com.example.brawlassistant

import android.app.Application
import android.content.Context
import androidx.core.content.edit
import com.example.brawlassistant.core.*
import com.example.brawlassistant.engine.AndroidPixels
import com.example.brawlassistant.engine.SandboxRunner
import com.example.brawlassistant.engine.UrlFetcher
import com.example.brawlassistant.live.LiveNotifier
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File

class BrawlApp : Application() {
    lateinit var graph: AppGraph; private set
    override fun onCreate() {
        super.onCreate()
        graph = AppGraph(this)
        LiveNotifier.ensureChannel(this)
    }
}

val Context.graph: AppGraph get() = (applicationContext as BrawlApp).graph

/**
 * 앱 전체 상태 (iOS AppState 와 같은 역할). 화면 분석 서비스와 화면이 같은 프로세스에서 이 객체를 함께 쓴다.
 * 추천 계산은 모두 RecommendationEngine → DraftEngineClient → JavaScriptSandbox(engine/draft-engine.js) 로 한다.
 */
class AppGraph(private val app: Context) {
    sealed class DataStatus {
        object Idle : DataStatus(); object Loading : DataStatus()
        data class Ready(val at: Long) : DataStatus()
        data class Offline(val cachedAt: Long) : DataStatus()
        data class Failed(val message: String) : DataStatus()
    }

    val store = FileStore(File(app.filesDir, "brawl"))
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private val _catalog = MutableStateFlow(store.read(EngineCatalog.serializer(), FileStore.Entry.Catalog))
    val catalog: StateFlow<EngineCatalog?> = _catalog.asStateFlow()
    private val _data = MutableStateFlow<DataStatus>(DataStatus.Idle)
    val dataStatus: StateFlow<DataStatus> = _data.asStateFlow()
    private val _precompute = MutableStateFlow(0 to 0)
    val precompute: StateFlow<Pair<Int, Int>> = _precompute.asStateFlow()
    private val _session = MutableStateFlow(initialSession())
    val session: StateFlow<AnalysisSession> = _session.asStateFlow()
    private val _manual = MutableStateFlow<EngineResult?>(null)
    val manual: StateFlow<EngineResult?> = _manual.asStateFlow()
    private val _computing = MutableStateFlow(false)
    val computing: StateFlow<Boolean> = _computing.asStateFlow()
    private val _alert = MutableStateFlow<String?>(null)
    val alert: StateFlow<String?> = _alert.asStateFlow()

    private val prefs = app.getSharedPreferences("settings", Context.MODE_PRIVATE)
    /** 실험 기능: 드래프트 화면에서 읽은 브롤러를 추천에 반영 */
    var usePicks: Boolean
        get() = prefs.getBoolean("usePicks", false)
        set(v) { prefs.edit { putBoolean("usePicks", v) } }

    private val engineLock = Mutex()
    private var engine: RecommendationEngine? = null
    private var runner: SandboxRunner? = null
    private var precomputeJob: Job? = null

    init { _catalog.value?.let(ModeNames::register) }

    /** 앱이 다시 켜졌을 때 이전 분석 세션이 남아 있으면 정리 (서비스는 프로세스와 함께 끝난다) */
    private fun initialSession(): AnalysisSession {
        val s = store.read(AnalysisSession.serializer(), FileStore.Entry.Session) ?: return AnalysisSession.idle
        return if (s.status in HomePresentation.activeStatuses || s.status == AnalysisStatus.waiting) AnalysisSession(AnalysisStatus.ended, s.startedAt, System.currentTimeMillis()) else s
    }

    fun dismissAlert() { _alert.value = null }
    fun alert(message: String) { _alert.value = message }

    /** 엔진 준비 (JavaScriptSandbox 생성 → 엔진 스크립트 로딩). 샌드박스가 죽었으면 다시 만든다 */
    private suspend fun engine(): RecommendationEngine = engineLock.withLock {
        engine?.let { return it }
        val r = SandboxRunner.create(app)
        val client = DraftEngineClient(r)
        client.boot(app.assets.open("draft-engine.js").bufferedReader().use { it.readText() })
        runner = r
        RecommendationEngine(client, store, UrlFetcher, AndroidPixels, AndroidPixels).also { engine = it }
    }

    private suspend fun <T> withEngine(block: suspend (RecommendationEngine) -> T): T = try {
        val e = engine()
        if (e.catalog == null) e.refresh()   // 엔진 상태가 비어 있으면 (재생성 직후) 데이터 다시 구성
        block(e)
    } catch (t: Throwable) {
        // 샌드박스 프로세스가 죽은 경우 한 번 다시 만든다
        if (t.javaClass.name.startsWith("androidx.javascriptengine")) {
            engineLock.withLock { runner?.close(); runner = null; engine = null }
            val e = engine(); e.refresh(); block(e)
        } else throw t
    }

    /** 데이터 새로고침: 웹과 같은 규칙으로 받고, 맵 풀 전체 기본 추천을 미리 계산 */
    fun refresh() = scope.launch {
        _data.value = DataStatus.Loading
        try {
            val r = engine().refresh()
            _catalog.value = r.catalog
            _data.value = r.cachedAt?.let { DataStatus.Offline(it) } ?: DataStatus.Ready(System.currentTimeMillis())
            engine().cachePortraits(r.catalog.brawlers.map { it.id })
            precomputeJob?.cancel()
            precomputeJob = scope.launch {
                engine().precompute(r.catalog.maps) { done, total -> _precompute.value = done to total }
            }
        } catch (t: Throwable) {
            _data.value = DataStatus.Failed(t.message ?: t.toString())
        }
    }

    /** 한 맵 추천 (픽 반영 가능: 우리 팀 → 고정 픽, 상대 팀 → 상대 픽. 웹 드래프트 시뮬레이터와 같은 입력) */
    suspend fun recommend(map: CatalogMap, picks: List<PickedBrawler> = emptyList()): EngineResult = withEngine { e ->
        e.recommend(map, picks.filter { it.side == PickedBrawler.Side.ally }.map { it.brawlerId }.take(map.size),
            picks.filter { it.side == PickedBrawler.Side.enemy }.map { it.brawlerId }.take(map.size))
    }

    fun chooseManually(map: CatalogMap) = scope.launch {
        _computing.value = true
        try { _manual.value = recommend(map) } catch (t: Throwable) { _alert.value = t.message } finally { _computing.value = false }
    }

    fun clearManual() { _manual.value = null }

    /** 화면 분석 서비스가 세션을 바꿀 때 */
    fun publishSession(s: AnalysisSession, persist: Boolean = true) {
        _session.value = s
        if (persist) store.write(AnalysisSession.serializer(), s, FileStore.Entry.Session)
    }

    fun setComputing(v: Boolean) { _computing.value = v }
}
