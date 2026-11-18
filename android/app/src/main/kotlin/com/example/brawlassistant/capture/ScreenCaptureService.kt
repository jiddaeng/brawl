package com.example.brawlassistant.capture

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.HandlerThread
import android.util.DisplayMetrics
import android.view.Display
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.core.content.IntentCompat
import androidx.core.graphics.createBitmap
import androidx.lifecycle.LifecycleService
import com.example.brawlassistant.core.*
import com.example.brawlassistant.graph
import com.example.brawlassistant.live.LiveNotifier
import kotlinx.coroutines.*
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * 화면 분석 서비스 (iOS 방송 확장에 해당).
 * 사용자가 화면 공유 동의 창에서 직접 허락해야 시작되며, 알림의 '분석 종료'나 앱에서 언제든 끌 수 있다.
 * 프레임은 기기 안에서 글자 인식에만 쓰고 저장·전송하지 않는다. 게임 입력·메모리에는 접근하지 않는다.
 */
class ScreenCaptureService : LifecycleService() {
    companion object {
        const val ACTION_START = "start"
        const val ACTION_STOP = "stop"
        const val ACTION_RETRY = "retry"
        private const val EXTRA_CODE = "code"
        private const val EXTRA_DATA = "data"
        /** 분석용 캡처 해상도 (긴 변). 맵 이름 글자를 읽기에 충분하고 메모리를 아낀다 */
        private const val CAPTURE_LONG_SIDE = 1280

        fun start(ctx: Context, resultCode: Int, data: Intent) {
            ContextCompat.startForegroundService(ctx, Intent(ctx, ScreenCaptureService::class.java).setAction(ACTION_START)
                .putExtra(EXTRA_CODE, resultCode).putExtra(EXTRA_DATA, data))
        }
        fun send(ctx: Context, action: String) = ctx.startService(Intent(ctx, ScreenCaptureService::class.java).setAction(action))
    }

    private val analysis = Dispatchers.Default.limitedParallelism(1)
    private val sampler = FrameSampler(minIntervalMs = 1000, maxIntervalMs = 8000, changeThreshold = 4.0)
    private val policy = LiveUpdatePolicy(minIntervalMs = 5000)
    private lateinit var recognizer: GameScreenRecognizer
    private val ocr by lazy { TextRecognizer() }
    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private var thread: HandlerThread? = null
    private var handler: Handler? = null
    private var heartbeat: Job? = null
    private var pendingNotify: Job? = null
    private var lastState: LiveDisplayState? = null
    private var stopping = false

    override fun onCreate() {
        super.onCreate()
        recognizer = GameScreenRecognizer(graph) { s -> notifyState(LiveDisplayState.from(s)) }
        recognizer.onRecomputed = { lifecycleScope().launch(analysis) { recognizer.recommendationsChanged(System.currentTimeMillis()) } }
        recognizer.onPicksApplied = { rec -> lifecycleScope().launch(analysis) { recognizer.applyPicks(rec, System.currentTimeMillis()) } }
    }

    private fun lifecycleScope(): CoroutineScope = graph.scope

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        when (intent?.action) {
            ACTION_START -> begin(intent)
            ACTION_STOP -> stopAll()
            ACTION_RETRY -> graph.scope.launch(analysis) { recognizer.retry(System.currentTimeMillis()) }
        }
        return START_NOT_STICKY
    }

    private fun begin(intent: Intent) {
        val code = intent.getIntExtra(EXTRA_CODE, Activity.RESULT_CANCELED)
        val data = IntentCompat.getParcelableExtra(intent, EXTRA_DATA, Intent::class.java)
        // Android 14+: getMediaProjection 전에 mediaProjection 타입 포그라운드 서비스가 시작돼 있어야 한다
        val first = LiveDisplayState(AnalysisStatus.broadcasting, updatedAt = System.currentTimeMillis())
        ServiceCompat.startForeground(this, LiveNotifier.ID, LiveNotifier.build(this, first, capturing = true), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        if (code != Activity.RESULT_OK || data == null) { graph.alert("화면 공유가 허락되지 않았습니다."); stopAll(); return }
        val mpm = getSystemService(MediaProjectionManager::class.java)
        val mp = try { mpm.getMediaProjection(code, data) } catch (e: Exception) { null }
        if (mp == null) { graph.alert("화면 공유를 시작하지 못했습니다. 다시 시도하세요."); stopAll(); return }
        projection = mp
        val t = HandlerThread("brawl-capture").also { it.start() }
        thread = t; handler = Handler(t.looper)
        // Android 14+: 가상 디스플레이를 만들기 전에 콜백을 등록해야 한다
        mp.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() { stopAll() }   // 사용자가 상태 표시줄 칩 등에서 공유를 끔
            override fun onCapturedContentResize(width: Int, height: Int) { resize(width, height) }
        }, handler)
        val (w, h, dpi) = captureSize(null)
        val r = newReader(w, h)
        display = mp.createVirtualDisplay("brawl-assistant", w, h, dpi, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, r.surface, null, handler)
        graph.scope.launch(analysis) { recognizer.start(System.currentTimeMillis()) }
        heartbeat = graph.scope.launch(analysis) { while (isActive) { delay(10_000); recognizer.heartbeat(System.currentTimeMillis()) } }
    }

    /** 캡처 크기: 화면(또는 공유된 앱 창) 비율 그대로, 긴 변 1280 */
    private fun captureSize(content: Pair<Int, Int>?): Triple<Int, Int, Int> {
        val dm = DisplayMetrics()
        @Suppress("DEPRECATION")
        getSystemService(DisplayManager::class.java).getDisplay(Display.DEFAULT_DISPLAY).getRealMetrics(dm)
        val (sw, sh) = content ?: (dm.widthPixels to dm.heightPixels)
        val scale = CAPTURE_LONG_SIDE.toDouble() / max(sw, sh)
        val w = ((sw * scale).roundToInt() / 2) * 2; val h = ((sh * scale).roundToInt() / 2) * 2
        return Triple(max(2, w), max(2, h), dm.densityDpi)
    }

    private fun newReader(w: Int, h: Int): ImageReader {
        val r = ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 2)
        r.setOnImageAvailableListener({ onFrame(it) }, handler)
        reader = r
        return r
    }

    /** 화면 회전·공유 창 크기 변경 (Android 14 부터는 가상 디스플레이를 다시 만들 수 없어 크기만 바꾼다) */
    private fun resize(contentW: Int, contentH: Int) {
        val d = display ?: return
        val (w, h, dpi) = captureSize(if (contentW > 0 && contentH > 0) contentW to contentH else null)
        val old = reader
        if (old != null && old.width == w && old.height == h) return
        val r = newReader(w, h)
        d.resize(w, h, dpi)
        d.surface = r.surface
        old?.close()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        handler?.post { resize(0, 0) }
    }

    private fun onFrame(r: ImageReader) {
        val img = try { r.acquireLatestImage() } catch (e: Exception) { null } ?: return
        try {
            val now = System.currentTimeMillis()
            if (!synchronized(sampler) { sampler.isDue(now) }) return
            val plane = img.planes[0]
            val buf = plane.buffer
            val w = img.width; val h = img.height; val ps = plane.pixelStride; val rs = plane.rowStride
            // 16×9 밝기 서명 (화면 변화 감지)
            val sig = ByteArray(16 * 9)
            for (y in 0 until 9) for (x in 0 until 16) {
                val i = (y * h / 9 + h / 18) * rs + (x * w / 16 + w / 32) * ps
                sig[y * 16 + x] = (((buf.get(i).toInt() and 0xFF) + 2 * (buf.get(i + 1).toInt() and 0xFF) + (buf.get(i + 2).toInt() and 0xFF)) / 4).toByte()
            }
            if (!synchronized(sampler) { sampler.shouldAnalyze(sig, now) }) return
            buf.rewind()
            val padded = createBitmap(rs / ps, h)
            padded.copyPixelsFromBuffer(buf)
            val bmp = if (padded.width == w) padded else Bitmap.createBitmap(padded, 0, 0, w, h).also { padded.recycle() }
            graph.scope.launch(analysis) {
                try { recognizer.process(ocr.lines(bmp), now) }
                catch (e: Exception) { /* 한 프레임 실패는 다음 샘플에서 다시 */ }
                finally { bmp.recycle(); synchronized(sampler) { sampler.finish() } }
            }
        } finally { img.close() }
    }

    /** 상태 알림 갱신: 보이는 내용이 바뀔 때만, 최소 5초 간격 (iOS Live Activity 와 같은 정책) */
    private fun notifyState(s: LiveDisplayState) {
        lastState = s
        if (stopping) return
        val now = System.currentTimeMillis()
        when (val d = policy.decide(s.contentKey, now)) {
            LiveUpdatePolicy.Decision.Skip -> Unit
            LiveUpdatePolicy.Decision.UpdateNow -> post(s, now)
            is LiveUpdatePolicy.Decision.DeferUntil -> if (pendingNotify?.isActive != true) {
                pendingNotify = graph.scope.launch(analysis) { delay(d.at - now); lastState?.let { notifyState(it) } }
            }
        }
    }

    private fun post(s: LiveDisplayState, now: Long) {
        policy.markPublished(s.contentKey, now)
        runCatching { getSystemService(android.app.NotificationManager::class.java).notify(LiveNotifier.ID, LiveNotifier.build(this, s, capturing = true)) }
    }

    private fun stopAll() {
        if (stopping) return
        stopping = true
        heartbeat?.cancel(); pendingNotify?.cancel()
        runBlocking(analysis) { recognizer.finish(System.currentTimeMillis()) }
        runCatching { display?.release() }; display = null
        runCatching { reader?.close() }; reader = null
        runCatching { projection?.stop() }; projection = null
        thread?.quitSafely(); thread = null
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        if (!stopping) stopAll()
        runCatching { ocr.close() }
        super.onDestroy()
    }
}
