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
            VStack(alignment: .leading, spacing: 24) {
                header
                StatusRow(presentation: p)
                if let rec = p.recommendation {
                    RecommendationView(recommendation: rec, result: vm.result, store: app.store)
                        .padding(20)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                } else if !onboardingDone || app.catalog == nil {
                    OnboardingView { onboardingDone = true }
                }
                actions(p)
                settings
                footer(vm)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        // 스크롤한 내용이 상태 표시줄(시계) 아래로 비치지 않게 스크롤 영역(안전 영역 안)으로 자른다
        .clipped()
        .background(Theme.background.ignoresSafeArea())
        // 주 동작은 화면 아래에 고정 (안전 영역 위, 위쪽 구분선)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(p) }
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
        // 로고: 제품 이름 (DRAFT ROOM 워드마크는 웹 Draft Room 의 브랜드). 위 줄은 앱 이름을 조용한 텍스트로
        VStack(alignment: .leading, spacing: 4) {
            Text("Brawl Assistant").font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondaryText)
            Text("DRAFT ROOM").font(.system(.largeTitle, design: .default, weight: .black)).foregroundStyle(Theme.text)
        }
        .padding(.top, 8)
    }

    private func bottomBar(_ p: HomePresentation) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.divider).frame(height: 0.5)
            Group {
                if p.broadcastActive || app.session.status == .waiting {
                    PrimaryButton(title: "화면 분석 종료", systemImage: "stop.fill", destructive: true) { app.stopBroadcast() }
                } else {
                    PrimaryButton(title: "화면 분석 시작", systemImage: "record.circle") {
                        if app.prepareBroadcast() { picker.present() }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(Theme.background)
    }

    /// 보조 동작: 목록형 한 카드
    private func actions(_ p: HomePresentation) -> some View {
        VStack(spacing: 0) {
            if p.canRetry {
                ActionRow(title: "다시 인식", systemImage: "arrow.clockwise") { app.retryRecognition() }
                RowDivider()
            }
            if p.broadcastActive {
                ActionRow(title: "방송 시트 열기", systemImage: "dot.radiowaves.left.and.right") { picker.present() }
                RowDivider()
            }
            ActionRow(title: "맵 직접 선택", systemImage: "map") { showMapPicker = true }
            RowDivider()
            ActionRow(title: "데이터 새로고침", systemImage: "arrow.triangle.2.circlepath") { Task { await app.refresh() } }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("설정")
            VStack(spacing: 0) {
                Toggle("Live Activity (Dynamic Island)", isOn: Binding(get: { activity.isRunning }, set: { if $0 != activity.isRunning { app.toggleLiveActivity() } }))
                    .padding(.horizontal, 16).padding(.vertical, 12)
                RowDivider(inset: 16)
                Toggle("추천이 바뀌면 Dynamic Island 펼치기", isOn: $alertOnChange)
                    .onChange(of: alertOnChange) { _, v in activity.alertOnChange = v }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                RowDivider(inset: 16)
                Toggle("드래프트 픽 글자 인식 반영 (실험)", isOn: $usePicks)
                    .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .font(.body)
            .foregroundStyle(Theme.text)
            .tint(Theme.accent)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            Text("Live Activity 를 켜면 이 앱이 화면에 없을 때 Dynamic Island 와 잠금 화면에 BEST TEAM 이 표시됩니다")
                .font(.footnote).foregroundStyle(Theme.secondaryText).padding(.horizontal, 4)
        }
    }

    private func footer(_ vm: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(vm.dataLine)
            if let s = vm.dataStatusLine { Text(s) }
            if let s = vm.precomputeLine { Text(s) }
            if let s = vm.extensionActivityLine { Text(s) }
            if activity.availability == .disabledByUser { Text("Live Activity 가 꺼져 있습니다. 설정 > Brawl Assistant > 실시간 현황에서 켤 수 있습니다").foregroundStyle(Theme.error) }
            if let e = activity.lastError { Text(e).foregroundStyle(Theme.error) }
            Text("비공식 팬메이드 도구. 데이터 출처 Brawlify, BrawlTime")
        }
        .font(.caption)
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 4)
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
                if let d = presentation.statusDetail { Text(d).font(.subheadline).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true) }
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
            Text("사용 방법").font(.headline).foregroundStyle(Theme.text)
            step(1, "‘화면 분석 시작’ → 방송 시트에서 Brawl Assistant 선택 → ‘방송 시작’")
            step(2, "브롤스타즈를 실행하고 로비의 이벤트·드래프트·로딩 화면처럼 맵 이름이 보이는 화면을 띄웁니다")
            step(3, "맵이 인식되면 Dynamic Island 와 이 화면에 BEST TEAM 이 표시됩니다")
            Text("화면은 기기 안에서만 분석되고 저장하거나 전송하지 않습니다. 방송은 이 앱, 제어 센터, 상단 상태 표시줄에서 언제든 끌 수 있습니다.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
            Button("확인", action: onDone).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                .frame(minHeight: 44)
        }
        .padding(20).background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
    private func step(_ n: Int, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.subheadline.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.secondaryText)
            Text(t).font(.subheadline).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PrimaryButton: View {
    let title: String
    let systemImage: String
    var destructive = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity).frame(height: 52)
        }
        .foregroundStyle(destructive ? Theme.text : Color.black)
        .background(destructive ? Theme.secondaryBackground : Theme.text, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// 목록형 카드의 한 줄
struct ActionRow: View {
    let title: String
    let systemImage: String
    var detail: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage).font(.body).foregroundStyle(Theme.secondaryText).frame(width: 24)
                Text(title).font(.body).foregroundStyle(Theme.text)
                Spacer()
                if let detail { Text(detail).font(.subheadline).foregroundStyle(Theme.secondaryText) }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText.opacity(0.6))
            }
            .padding(.horizontal, 16).frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct RowDivider: View {
    var inset: CGFloat = 50
    var body: some View { Rectangle().fill(Theme.divider).frame(height: 0.5).padding(.leading, inset) }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText).padding(.leading, 4)
    }
}
