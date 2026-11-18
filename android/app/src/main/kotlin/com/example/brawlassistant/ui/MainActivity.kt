package com.example.brawlassistant.ui

import android.Manifest
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import com.example.brawlassistant.capture.ScreenCaptureService
import com.example.brawlassistant.core.AnalysisSession
import com.example.brawlassistant.core.AnalysisStatus
import com.example.brawlassistant.graph

class MainActivity : ComponentActivity() {
    /** 화면 공유 동의 (매번 사용자가 직접 허락. Android 14+ 에서는 '앱 하나'만 공유 가능) */
    private val projection = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        val data = r.data
        if (r.resultCode == RESULT_OK && data != null) ScreenCaptureService.start(this, r.resultCode, data)
        else { graph.publishSession(AnalysisSession(AnalysisStatus.idle)); graph.alert("화면 공유가 취소되었습니다.") }
    }
    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { startCapture(askedNotifications = true) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (graph.dataStatus.value is com.example.brawlassistant.AppGraph.DataStatus.Idle) graph.refresh()
        setContent { BrawlTheme { HomeScreen(graph, onStartCapture = { startCapture() }, onStopCapture = { ScreenCaptureService.send(this, ScreenCaptureService.ACTION_STOP) },
            onRetry = { ScreenCaptureService.send(this, ScreenCaptureService.ACTION_RETRY) }) } }
    }

    private fun startCapture(askedNotifications: Boolean = false) {
        if (graph.catalog.value == null) { graph.alert("맵 데이터를 먼저 불러와야 합니다. ‘데이터 새로고침’을 눌러 주세요."); return }
        // 상태 알림 권한 (Android 13+). 거부해도 분석은 되지만 게임 중 추천을 볼 수 없다
        if (Build.VERSION.SDK_INT >= 33 && !askedNotifications &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS); return
        }
        graph.clearManual()
        graph.publishSession(AnalysisSession(AnalysisStatus.waiting))
        projection.launch(getSystemService(MediaProjectionManager::class.java).createScreenCaptureIntent())
    }
}
