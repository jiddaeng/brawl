package com.example.brawlassistant.live

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.example.brawlassistant.R
import com.example.brawlassistant.capture.ScreenCaptureService
import com.example.brawlassistant.core.AnalysisStatus
import com.example.brawlassistant.core.LiveDisplayState
import com.example.brawlassistant.graph
import com.example.brawlassistant.ui.MainActivity

/**
 * iOS Dynamic Island(Live Activity)에 해당하는 Android 표시: 진행 중 알림.
 * Android 16+ 에서는 Live Updates(승격된 진행 중 알림)로 요청해 상태 표시줄 칩에 점수를 띄운다.
 * 지원하지 않거나 사용자가 끈 기기에서는 일반 진행 중 알림으로 보인다.
 */
object LiveNotifier {
    const val CHANNEL = "live"
    const val ID = 1001

    fun ensureChannel(ctx: Context) {
        val ch = NotificationChannel(CHANNEL, ctx.getString(R.string.channel_live), NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = ctx.getString(R.string.channel_live_desc)
            setSound(null, null)        // 게임 중 소리·진동 없음
            enableVibration(false)
            setShowBadge(false)
        }
        ctx.getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
    }

    /** Android 16 Live Updates 로 표시될 수 있는지 (권한·사용자 설정) */
    fun canPromote(ctx: Context): Boolean =
        Build.VERSION.SDK_INT >= 36 && ctx.getSystemService(NotificationManager::class.java).canPostPromotedNotifications()

    fun build(ctx: Context, s: LiveDisplayState, capturing: Boolean): Notification {
        val open = PendingIntent.getActivity(ctx, 0, Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE)
        val ready = s.status == AnalysisStatus.ready && s.members.isNotEmpty()
        val title = if (ready) "BEST TEAM · ${s.members.joinToString(" ") { it.name }}" else s.status.title
        val place = listOfNotNull(s.mapName, s.modeName).joinToString(" · ")
        val big = buildString {
            if (s.mapName != null) appendLine("현재 맵: ${s.mapName}")
            if (s.modeName != null) appendLine("모드: ${s.modeName}")
            if (ready) {
                appendLine("BEST TEAM: ${s.members.joinToString(" · ") { it.name }}")
                append("종합 점수: ${s.score}${s.winRate?.let { " · 추정 승률 $it%" } ?: ""}")
            } else if (s.message != null) append(s.message)
        }.trim()
        val b = NotificationCompat.Builder(ctx, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_brawl)
            .setContentTitle(title)
            .setContentText(if (ready) place else (s.message ?: place))
            .setStyle(NotificationCompat.BigTextStyle().bigText(big.ifEmpty { s.status.title }))
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setRequestPromotedOngoing(true)
            .setShortCriticalText(if (ready) "${s.score}" else s.status.title)
        // 1위 브롤러 초상화 (앱이 저장해 둔 작은 이미지)
        s.members.firstOrNull()?.let { m ->
            val f = ctx.graph.store.portrait(m.id)
            if (ready && f.exists()) BitmapFactory.decodeFile(f.path)?.let(b::setLargeIcon)
        }
        if (capturing) {
            val stop = PendingIntent.getService(ctx, 1, Intent(ctx, ScreenCaptureService::class.java).setAction(ScreenCaptureService.ACTION_STOP), PendingIntent.FLAG_IMMUTABLE)
            b.addAction(0, "분석 종료", stop)
        }
        return b.build()
    }

    /** 화면 분석 없이(맵 직접 선택) 상태 알림만 띄우기 */
    fun showStandalone(ctx: Context, s: LiveDisplayState): Boolean {
        val nm = NotificationManagerCompat.from(ctx)
        if (!nm.areNotificationsEnabled()) return false
        return try { nm.notify(ID, build(ctx, s, capturing = false)); true } catch (e: SecurityException) { false }
    }

    fun cancel(ctx: Context) = NotificationManagerCompat.from(ctx).cancel(ID)
}
