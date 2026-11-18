import SwiftUI
import BrawlCore

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var picker = BroadcastPickerHolder()
    @ObservedObject private var activity: LiveActivityController
    @State private var showMapPicker = false
    @AppStorage("onboarding.done") private var onboardingDone = false
    @AppStorage(AppState.usePicksKey) private var usePicks = false
    @AppStorage("liveActivity.alertOnChange") private var alertOnChange = false

    init(activity: LiveActivityController) { _activity = ObservedObject(wrappedValue: activity) }

    var body: some View {
        let vm = HomeViewModel(app: app)
        let p = vm.presentation
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                StatusRow(presentation: p)
                if let rec = p.recommendation {
                    RecommendationView(recommendation: rec, result: vm.result, store: app.store)
                        .padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.corner))
                } else if !onboardingDone || app.catalog == nil {
                    OnboardingView { onboardingDone = true }
                }
                if p.canRetry {
                    HStack(spacing: 10) {
                        SecondaryButton(title: "다시 인식") { app.retryRecognition() }
                        SecondaryButton(title: "맵 직접 선택") { showMapPicker = true }
                    }
                }
                controls(p)
                footer(vm)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
        }
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            // 방송 시트를 띄우는 시스템 뷰 (보이지 않게 둔다)
            BroadcastPickerHost(holder: picker).frame(width: 1, height: 1).opacity(0.01).allowsHitTesting(false)
        }
        .sheet(isPresented: $showMapPicker) { MapPickerView(maps: app.catalog?.maps ?? []) { app.chooseMapManually($0) } }
        .alert("알림", isPresented: Binding(get: { app.alert != nil }, set: { if !$0 { app.alert = nil } })) {
            Button("확인", role: .cancel) {}
        } message: { Text(app.alert ?? "") }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("BRAWL ASSISTANT").font(.caption.weight(.heavy)).tracking(3).foregroundStyle(Theme.secondaryText)
            Text("DRAFT ROOM").font(.system(size: 34, weight: .black)).foregroundStyle(Theme.text)
        }
    }

    @ViewBuilder private func controls(_ p: HomePresentation) -> some View {
        VStack(spacing: 10) {
            if p.broadcastActive || app.session.status == .waiting {
                PrimaryButton(title: "화면 분석 종료", systemImage: "stop.fill") { app.stopBroadcast() }
                SecondaryButton(title: "방송 시트 열기") { picker.present() }
            } else {
                PrimaryButton(title: "화면 분석 시작", systemImage: "record.circle") {
                    if app.prepareBroadcast() { picker.present() }
                }
            }
            HStack(spacing: 10) {
                SecondaryButton(title: activity.isRunning ? "Live Activity 종료" : "Live Activity 시작") { app.toggleLiveActivity() }
                SecondaryButton(title: "데이터 새로고침") { Task { await app.refresh() } }
            }
            if !p.canRetry { SecondaryButton(title: "맵 직접 선택") { showMapPicker = true } }
            VStack(alignment: .leading, spacing: 6) {
                Toggle("추천이 바뀌면 Dynamic Island 펼치기", isOn: $alertOnChange)
                    .onChange(of: alertOnChange) { _, v in activity.alertOnChange = v }
                Toggle("드래프트 픽 글자 인식 반영 (실험)", isOn: $usePicks)
            }
            .font(.footnote).foregroundStyle(Theme.secondaryText).tint(Theme.accent).padding(.top, 4)
        }
    }

    private func footer(_ vm: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(vm.dataLine)
            if let s = vm.dataStatusLine { Text(s) }
            if let s = vm.precomputeLine { Text(s) }
            if let s = vm.extensionActivityLine { Text(s) }
            if activity.availability == .disabledByUser { Text("Live Activity 가 꺼져 있습니다: 설정 > Brawl Assistant > 실시간 현황").foregroundStyle(Theme.error) }
            Text("비공식 팬메이드 도구 · 데이터: Brawlify, BrawlTime")
        }
        .font(.caption2).foregroundStyle(Theme.secondaryText)
    }
}

struct StatusRow: View {
    let presentation: HomePresentation
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(presentation.isError ? Theme.error : (presentation.broadcastActive ? Theme.accent : Theme.secondaryText))
                .frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.statusTitle).font(.headline).foregroundStyle(Theme.text)
                if let d = presentation.statusDetail { Text(d).font(.footnote).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true) }
                if let r = presentation.recognition, let name = r.mapName, presentation.recommendation == nil {
                    Text("인식: \(name)\(r.recognizedMode.map { " · " + (ModeNames.korean[$0] ?? $0) } ?? "")").font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }
}

struct OnboardingView: View {
    let onDone: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("사용 방법").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
            step(1, "‘화면 분석 시작’ → 방송 시트에서 Brawl Assistant 선택 → ‘방송 시작’")
            step(2, "브롤스타즈를 실행하고 로비의 이벤트·드래프트·로딩 화면처럼 맵 이름이 보이는 화면을 띄웁니다")
            step(3, "맵이 인식되면 Dynamic Island 와 이 화면에 BEST TEAM 이 표시됩니다")
            Text("화면은 기기 안에서만 분석되고 저장·전송되지 않습니다. 방송은 언제든 이 앱이나 제어 센터·상단 상태 표시줄에서 끌 수 있습니다.")
                .font(.caption).foregroundStyle(Theme.secondaryText)
            Button("확인", action: onDone).font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
        }
        .padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.corner))
    }
    private func step(_ n: Int, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.footnote.monospacedDigit().weight(.bold)).foregroundStyle(Theme.accent)
            Text(t).font(.footnote).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 14)
        }
        .foregroundStyle(Color.black).background(Theme.text, in: RoundedRectangle(cornerRadius: Theme.corner))
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Text(title).font(.footnote.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12) }
            .foregroundStyle(Theme.text).background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: Theme.corner))
    }
}
