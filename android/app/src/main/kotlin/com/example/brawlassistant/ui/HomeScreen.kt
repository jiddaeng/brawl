package com.example.brawlassistant.ui

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.edit
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.example.brawlassistant.AppGraph
import com.example.brawlassistant.core.*
import com.example.brawlassistant.live.LiveNotifier
import kotlinx.coroutines.delay
import java.text.DateFormat
import java.util.Date

@Composable
fun HomeScreen(graph: AppGraph, onStartCapture: () -> Unit, onStopCapture: () -> Unit, onRetry: () -> Unit) {
    val ctx = LocalContext.current
    val session by graph.session.collectAsStateWithLifecycle()
    val manual by graph.manual.collectAsStateWithLifecycle()
    val catalog by graph.catalog.collectAsStateWithLifecycle()
    val data by graph.dataStatus.collectAsStateWithLifecycle()
    val pre by graph.precompute.collectAsStateWithLifecycle()
    val computing by graph.computing.collectAsStateWithLifecycle()
    val alert by graph.alert.collectAsStateWithLifecycle()
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(5000); now = System.currentTimeMillis() } }
    var showPicker by remember { mutableStateOf(false) }
    var usePicks by remember { mutableStateOf(graph.usePicks) }
    val prefs = remember { ctx.getSharedPreferences("settings", 0) }
    var onboardingDone by remember { mutableStateOf(prefs.getBoolean("onboarding", false)) }

    val manualRec = manual?.let { Recommendation.from(it) }
    val p = HomePresentation.make(session, manualRec, computing, now)
    val result = if (p.isManual) manual else p.recommendation?.let { graph.store.recommendation(it.mapId) }

    Column(
        Modifier.fillMaxSize().background(Tokens.background).systemBarsPadding().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        Column {
            Text("BRAWL ASSISTANT", color = Tokens.secondaryText, fontSize = 12.sp, fontWeight = FontWeight.Black, letterSpacing = 3.sp)
            Text("DRAFT ROOM", color = Tokens.text, fontSize = 34.sp, fontWeight = FontWeight.Black)
        }
        StatusRow(p)
        val rec = p.recommendation
        if (rec != null) Card { RecommendationCard(rec, result, graph.store) }
        else if (!onboardingDone || catalog == null) Card { Onboarding { onboardingDone = true; prefs.edit { putBoolean("onboarding", true) } } }

        if (p.canRetry) Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Secondary("다시 인식", Modifier.weight(1f)) { if (p.captureActive) onRetry() else graph.publishSession(AnalysisSession(AnalysisStatus.idle)) }
            Secondary("맵 직접 선택", Modifier.weight(1f)) { showPicker = true }
        }

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (p.captureActive || session.status == AnalysisStatus.waiting) Primary("화면 분석 종료") { onStopCapture() }
            else Primary("화면 분석 시작") { onStartCapture() }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Secondary("상태 알림 표시", Modifier.weight(1f)) {
                    val s = manualRec?.let { LiveDisplayState.manual(it) } ?: LiveDisplayState.from(session)
                    if (!LiveNotifier.showStandalone(ctx, s)) graph.alert("알림이 꺼져 있습니다. 설정에서 Brawl Assistant 알림을 켜 주세요.")
                }
                Secondary("데이터 새로고침", Modifier.weight(1f)) { graph.refresh() }
            }
            if (!p.canRetry) Secondary("맵 직접 선택", Modifier.fillMaxWidth()) { showPicker = true }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("드래프트 픽 글자 인식 반영 (실험)", color = Tokens.secondaryText, fontSize = 13.sp, modifier = Modifier.weight(1f))
                Switch(checked = usePicks, onCheckedChange = { usePicks = it; graph.usePicks = it },
                    colors = SwitchDefaults.colors(checkedThumbColor = Tokens.background, checkedTrackColor = Tokens.accent))
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            catalog?.let { c -> SmallText("${if (c.hasLive) "현재 맵 풀" else "활성 맵"} ${c.maps.size} · 브롤러 ${c.brawlers.size}${c.window?.let { " · 실전 데이터 $it" } ?: ""}", Tokens.secondaryText) }
            when (val d = data) {
                is AppGraph.DataStatus.Loading -> SmallText("데이터 불러오는 중…", Tokens.secondaryText)
                is AppGraph.DataStatus.Ready -> SmallText("동기화 ${DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(d.at))}", Tokens.secondaryText)
                is AppGraph.DataStatus.Offline -> SmallText("API 응답 없음 · 저장본 사용 (${DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(d.cachedAt))})", Tokens.accent)
                is AppGraph.DataStatus.Failed -> SmallText(d.message, Tokens.error)
                else -> Unit
            }
            if (pre.second > 0 && pre.first < pre.second) SmallText("추천 미리 계산 ${pre.first}/${pre.second} · 계산된 맵은 바로 인식됩니다", Tokens.secondaryText)
            if (android.os.Build.VERSION.SDK_INT >= 36 && !LiveNotifier.canPromote(ctx)) SmallText("Live Updates(상태 표시줄 칩)가 꺼져 있어 일반 알림으로 표시됩니다", Tokens.secondaryText)
            SmallText("비공식 팬메이드 도구 · 데이터: Brawlify, BrawlTime", Tokens.secondaryText)
        }
    }

    if (showPicker) MapPicker(catalog?.maps.orEmpty(), onDismiss = { showPicker = false }) { showPicker = false; graph.chooseManually(it) }
    alert?.let { msg ->
        AlertDialog(onDismissRequest = graph::dismissAlert, confirmButton = { TextButton(onClick = graph::dismissAlert) { Text("확인", color = Tokens.accent) } },
            text = { Text(msg) }, containerColor = Tokens.card)
    }
}

@Composable
private fun SmallText(t: String, c: androidx.compose.ui.graphics.Color) = Text(t, color = c, fontSize = 11.sp)

@Composable
private fun Card(content: @Composable ColumnScope.() -> Unit) =
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Tokens.card).padding(16.dp), content = content)

@Composable
private fun StatusRow(p: HomePresentation) {
    Row(verticalAlignment = Alignment.Top) {
        Box(Modifier.padding(top = 7.dp).size(8.dp).clip(CircleShape).background(if (p.isError) Tokens.error else if (p.captureActive) Tokens.accent else Tokens.secondaryText))
        Spacer(Modifier.width(10.dp))
        Column {
            Text(p.statusTitle, color = Tokens.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            p.statusDetail?.let { Text(it, color = Tokens.secondaryText, fontSize = 13.sp) }
            val r = p.recognition
            if (r?.mapName != null && p.recommendation == null)
                Text("인식: ${r.mapName}${r.recognizedMode?.let { " · " + (ModeNames.korean[it] ?: it) } ?: ""}", color = Tokens.secondaryText, fontSize = 13.sp)
        }
    }
}

@Composable
fun RecommendationCard(rec: Recommendation, result: EngineResult?, store: FileStore) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Column(Modifier.weight(1f)) {
                Text(rec.mapName, color = Tokens.text, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                Text("${rec.gameMode} · ${rec.mapNameEn}", color = Tokens.secondaryText, fontSize = 12.sp)
            }
            Text(rec.archetype, color = Tokens.secondaryText, fontSize = 12.sp)
        }
        Text("BEST TEAM", color = Tokens.accent, fontSize = 12.sp, fontWeight = FontWeight.Black, letterSpacing = 2.sp)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            rec.brawlers.forEach { b -> BrawlerCell(b, store, Modifier.weight(1f)) }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(28.dp)) {
            Metric("종합 점수", "${rec.score}", "/100", highlight = true)
            Metric("추정 승률", rec.estimatedWinRate, "%")
            result?.let { Metric("시뮬레이션", it.countText, "") }
        }
        Text("종합 점수·추정 승률은 Draft Room 엔진의 계산값이며 공식 통계가 아닙니다.", color = Tokens.secondaryText, fontSize = 11.sp)
        HorizontalDivider(color = Tokens.divider)
        Text("추천 근거", color = Tokens.text, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
        rec.reasons.forEach { Text("· $it", color = Tokens.secondaryText, fontSize = 13.sp) }
        val others = result?.teams?.drop(1).orEmpty()
        if (others.isNotEmpty()) {
            HorizontalDivider(color = Tokens.divider)
            Text("다른 순위", color = Tokens.text, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            others.forEach { t ->
                Row {
                    Text("#${t.rank}", color = Tokens.secondaryText, fontSize = 13.sp, modifier = Modifier.width(32.dp))
                    Text(t.members.joinToString(" · ") { it.ko }, color = Tokens.text, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    Text("${t.score}", color = Tokens.text, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

@Composable
private fun BrawlerCell(m: TeamMember, store: FileStore, modifier: Modifier) {
    val bmp = remember(m.id) { store.portrait(m.id).takeIf { it.exists() }?.let { BitmapFactory.decodeFile(it.path)?.asImageBitmap() } }
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(Modifier.size(64.dp).clip(RoundedCornerShape(10.dp)).background(Tokens.secondaryBackground)) {
            bmp?.let { Image(it, contentDescription = m.ko, modifier = Modifier.fillMaxSize()) }
        }
        Text(m.ko, color = Tokens.text, fontSize = 14.sp, fontWeight = FontWeight.Bold, maxLines = 1)
        m.role?.let { Text(it, color = Tokens.secondaryText, fontSize = 11.sp, maxLines = 1) }
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            m.pick?.let { Text("${it}픽", color = Tokens.secondaryText, fontSize = 11.sp) }
            // 표시 문자열은 엔진(웹과 같은 toFixed) 값 그대로
            if (m.eff != null && m.effPct != null) Text("${m.effPct}%p", color = if (m.eff!! >= 0) Tokens.positive else Tokens.error, fontSize = 11.sp)
        }
        if (m.estimatedProfile) Text("추정 프로필", color = Tokens.secondaryText, fontSize = 10.sp)
    }
}

@Composable
private fun Metric(title: String, value: String, suffix: String, highlight: Boolean = false) {
    Column {
        Text(title, color = Tokens.secondaryText, fontSize = 12.sp)
        Row(verticalAlignment = Alignment.Bottom) {
            Text(value, color = if (highlight) Tokens.accent else Tokens.text, fontSize = 28.sp, fontWeight = FontWeight.Bold)
            Text(suffix, color = Tokens.secondaryText, fontSize = 12.sp, modifier = Modifier.padding(bottom = 4.dp, start = 2.dp))
        }
    }
}

@Composable
private fun Onboarding(onDone: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("사용 방법", color = Tokens.text, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
        listOf(
            "‘화면 분석 시작’ → 화면 공유 창에서 ‘앱 하나 공유 → 브롤스타즈’(또는 전체 화면) 선택",
            "브롤스타즈에서 로비의 이벤트·드래프트·로딩 화면처럼 맵 이름이 보이는 화면을 띄웁니다",
            "맵이 인식되면 상태 알림(Android 16 은 상태 표시줄 칩)과 이 화면에 BEST TEAM 이 표시됩니다",
        ).forEachIndexed { i, t ->
            Row { Text("${i + 1}", color = Tokens.accent, fontWeight = FontWeight.Bold, fontSize = 13.sp, modifier = Modifier.width(18.dp)); Text(t, color = Tokens.text, fontSize = 13.sp) }
        }
        Text("화면은 기기 안에서만 글자 인식에 쓰이고 저장·전송되지 않습니다. 알림의 ‘분석 종료’나 이 앱에서 언제든 끌 수 있습니다.", color = Tokens.secondaryText, fontSize = 12.sp)
        Text("확인", color = Tokens.accent, fontWeight = FontWeight.SemiBold, fontSize = 13.sp, modifier = Modifier.clickable(onClick = onDone))
    }
}

@Composable
private fun Primary(title: String, onClick: () -> Unit) =
    Button(onClick = onClick, modifier = Modifier.fillMaxWidth().height(52.dp), shape = RoundedCornerShape(12.dp),
        colors = ButtonDefaults.buttonColors(containerColor = Tokens.text, contentColor = Tokens.background)) { Text(title, fontWeight = FontWeight.SemiBold) }

@Composable
private fun Secondary(title: String, modifier: Modifier, onClick: () -> Unit) =
    Button(onClick = onClick, modifier = modifier.height(44.dp), shape = RoundedCornerShape(12.dp),
        colors = ButtonDefaults.buttonColors(containerColor = Tokens.secondaryBackground, contentColor = Tokens.text)) { Text(title, fontSize = 13.sp, fontWeight = FontWeight.SemiBold) }

@Composable
private fun MapPicker(maps: List<CatalogMap>, onDismiss: () -> Unit, onPick: (CatalogMap) -> Unit) {
    var q by remember { mutableStateOf("") }
    val list = remember(q, maps) {
        val f = if (q.isBlank()) maps else maps.filter { it.ko.contains(q, true) || it.name.contains(q, true) || it.modeKo.contains(q) }
        f.filter { it.ranked } + f.filter { !it.ranked }
    }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(Modifier.fillMaxSize().background(Tokens.background).systemBarsPadding().padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("맵 직접 선택", color = Tokens.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                TextButton(onClick = onDismiss) { Text("닫기", color = Tokens.accent) }
            }
            OutlinedTextField(q, { q = it }, placeholder = { Text("맵 이름 (한글·영문)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(8.dp))
            LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                items(list, key = { it.id.toString() + it.mode }) { m ->
                    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(Tokens.card).clickable { onPick(m) }.padding(12.dp)) {
                        Text(m.ko, color = Tokens.text, fontSize = 15.sp)
                        Text("${m.modeKo} · ${m.name}", color = Tokens.secondaryText, fontSize = 12.sp)
                    }
                }
            }
        }
    }
}
