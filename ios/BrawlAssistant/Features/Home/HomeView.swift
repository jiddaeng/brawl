import SwiftUI
import BrawlCore

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var picker = BroadcastPickerHolder()
    @ObservedObject private var activity: LiveActivityController
    @State private var showMapPicker = false
    @State private var showPlayer = false
    @AppStorage(AppState.ownedOnlyKey) private var ownedOnly = true
    @AppStorage("onboarding.done") private var onboardingDone = false
    @AppStorage(AppState.usePicksKey) private var usePicks = false
    @AppStorage("liveActivity.alertOnChange") private var alertOnChange = false

    init(activity: LiveActivityController) { _activity = ObservedObject(wrappedValue: activity) }

    var body: some View {
        let vm = HomeViewModel(app: app)
        let p = vm.presentation
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(p)
                if app.gameDataAvailable || app.gameData.player != nil {
                    PlayerCard { showPlayer = true }
                }
                let maps = app.currentMaps
                if !maps.isEmpty {
                    CurrentMapsStrip(maps: maps, selected: p.recommendation?.mapID, recent: app.recentMap?.map.id)
                }
                if p.broadcastActive || p.isError || p.recommendation == nil {
                    StatusRow(presentation: p)
                }
                if let rec = p.recommendation {
                    RecommendationView(recommendation: rec, result: vm.result, store: app.store)
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
        .background(DraftRoomBackground())
        // 주 동작은 화면 아래에 고정 (안전 영역 위, 위쪽 구분선)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(p) }
        .overlay(alignment: .bottomTrailing) {
            // 방송 시트를 띄우는 시스템 뷰 (보이지 않게 둔다)
            BroadcastPickerHost(holder: picker).frame(width: 1, height: 1).opacity(0.01).allowsHitTesting(false)
        }
        .sheet(isPresented: $showMapPicker) { MapPickerView(maps: app.catalog?.maps ?? []) { app.chooseMapManually($0) } }
        .sheet(isPresented: $showPlayer) { PlayerLinkSheet().environmentObject(app) }
        .alert("알림", isPresented: Binding(get: { app.alert != nil }, set: { if !$0 { app.alert = nil } })) {
            Button("확인", role: .cancel) {}
        } message: { Text(app.alert ?? "") }
        .preferredColorScheme(.dark)
    }

    private func header(_ p: HomePresentation) -> some View {
        // 웹 Draft Room 머리: 금색 로고 + 상태 칩 (LIVE · 맵 풀 · 브롤러)
        VStack(alignment: .leading, spacing: 14) {
            DraftRoomLogo(size: 44)
            HStack(spacing: 6) {
                Chip {
                    LiveDot(on: p.broadcastActive)
                    Text(p.broadcastActive ? "LIVE" : "READY").foregroundStyle(Theme.text)
                }
                if let c = app.catalog {
                    Chip { Text("맵 풀 \(c.maps.count)") }
                    Chip { Text("브롤러 \(c.brawlers.count)") }
                }
            }
        }
        .padding(.top, 10)
    }

    private func bottomBar(_ p: HomePresentation) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.line).frame(height: 1)
            Group {
                // 주 동작: Dynamic Island 켜기. 게임 중에는 ◀ ▶ 로 맵을 바꾼다 (화면 녹화 불필요)
                if p.broadcastActive || app.session.status == .waiting {
                    PrimaryButton(title: "화면 인식 종료", systemImage: "stop.fill", destructive: true) { app.stopBroadcast() }
                } else if activity.isRunning {
                    PrimaryButton(title: "Dynamic Island 끄기", systemImage: "xmark", destructive: true) { app.toggleLiveActivity() }
                } else {
                    PrimaryButton(title: "Dynamic Island 켜기", systemImage: "capsule.fill") { app.toggleLiveActivity() }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(Theme.background.opacity(0.94))
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
            ActionRow(title: "맵 직접 선택 (전체 맵 풀)", systemImage: "map") { showMapPicker = true }
            RowDivider()
            if !p.broadcastActive {
                ActionRow(title: "화면 인식으로 맵 찾기 (선택)", systemImage: "record.circle") {
                    if app.prepareBroadcast() { picker.present() }
                }
                RowDivider()
            }
            ActionRow(title: "데이터 새로고침", systemImage: "arrow.triangle.2.circlepath") { Task { await app.refresh() } }
        }
        .draftCard()
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("설정")
            VStack(spacing: 0) {
                if app.gameData.player != nil {
                    Toggle("보유 브롤러만 추천", isOn: $ownedOnly)
                        .onChange(of: ownedOnly) { _, _ in app.ownedSettingsChanged() }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    RowDivider(inset: 16)
                }
                Toggle("추천이 바뀌면 Dynamic Island 펼치기", isOn: $alertOnChange)
                    .onChange(of: alertOnChange) { _, v in activity.alertOnChange = v }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                RowDivider(inset: 16)
                Toggle("화면 인식: 드래프트 픽 반영 (실험)", isOn: $usePicks)
                    .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .font(.body)
            .foregroundStyle(Theme.text)
            .tint(Theme.accent)
            .draftCard()
            Text("Dynamic Island 를 켜면 게임 중에도 추천이 보이고, ◀ ▶ 로 지금 열린 맵을 바꿀 수 있습니다. 화면 녹화는 필요 없습니다")
                .font(.footnote).foregroundStyle(Theme.secondaryText).padding(.horizontal, 4)
        }
    }

    private func footer(_ vm: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(vm.dataLine)
            if let s = vm.dataStatusLine { Text(s) }
            if let s = vm.precomputeLine { Text(s) }
            if let s = vm.gameDataLine { Text(s) }
            if let s = vm.extensionActivityLine { Text(s) }
            if activity.availability == .disabledByUser { Text("Live Activity 가 꺼져 있습니다. 설정 > Brawl Assistant > 실시간 현황에서 켤 수 있습니다").foregroundStyle(Theme.error) }
            if let e = activity.lastError { Text(e).foregroundStyle(Theme.error) }
            Text("비공식 팬메이드 도구. 데이터 출처 Supercell 공식 API, Brawlify, BrawlTime. 이 앱은 Supercell 과 관련이 없습니다")
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
            Circle().fill(dotColor)
                .frame(width: 9, height: 9).padding(.top, 7)
                .shadow(color: dotColor, radius: 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.statusTitle).font(Theme.ko(19)).foregroundStyle(Theme.text)
                if let d = presentation.statusDetail { Text(d).font(.subheadline).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true) }
                if let r = presentation.recognition, let name = r.mapName, presentation.recommendation == nil {
                    Text("인식: \(name)\(r.recognizedMode.map { " · " + (ModeNames.korean[$0] ?? $0) } ?? "")").font(Theme.mono(12)).foregroundStyle(Theme.accent)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .draftCard()
    }

    private var dotColor: Color { presentation.isError ? Theme.error : (presentation.broadcastActive ? Theme.positive : Theme.secondaryText) }
}

struct OnboardingView: View {
    let onDone: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("사용 방법").font(Theme.ko(20)).foregroundStyle(Theme.accent)
            step(1, "플레이어 태그를 연결하면 내가 가진 브롤러로만 추천합니다")
            step(2, "‘지금 열린 맵’에서 들어갈 맵을 누릅니다. 최근 경기 맵은 초록색으로 표시됩니다")
            step(3, "‘Dynamic Island 켜기’를 누르고 게임으로 갑니다. 게임 중에는 Dynamic Island 를 길게 눌러 ◀ ▶ 로 맵을 바꿉니다")
            Text("화면 녹화는 필요 없습니다. 맵을 자동으로 찾고 싶을 때만 아래의 ‘화면 인식’을 쓰세요 (화면은 기기 안에서만 분석).")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
            Button("확인", action: onDone).font(Theme.ko(16)).foregroundStyle(Theme.accent)
                .frame(minHeight: 44)
        }
        .padding(18).draftCard()
    }
    private func step(_ n: Int, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(Theme.display(20)).foregroundStyle(Theme.accent).frame(width: 16)
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
            HStack(spacing: 8) {
                Image(systemName: systemImage).font(.system(size: 17, weight: .bold))
                Text(title).font(Theme.ko(20, relativeTo: .headline))
            }
            .frame(maxWidth: .infinity).frame(height: 54)
            .foregroundStyle(destructive ? Theme.text : Theme.goldInk)
            .background(background)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(destructive ? Theme.error : Color.white.opacity(0.35), lineWidth: 1))
            .shadow(color: destructive ? .clear : Theme.goldShadow, radius: 0, x: 0, y: 4)
            .shadow(color: (destructive ? Theme.error : Theme.accent).opacity(0.3), radius: 14)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if destructive {
            shape.fill(Theme.error.opacity(0.18))
        } else {
            shape.fill(Theme.goldGradient)
        }
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
                Image(systemName: systemImage).font(.body.weight(.semibold)).foregroundStyle(Theme.accent).frame(width: 24)
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
    var body: some View { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, inset) }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Theme.ko(16)).foregroundStyle(Theme.accent).padding(.leading, 4)
    }
}

/// 웹 .dot: 켜지면 빨간 빛 점 (깜빡임은 동작 줄이기 설정을 따른다)
struct LiveDot: View {
    let on: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false
    var body: some View {
        Circle().fill(on ? Theme.error : Theme.secondaryText)
            .frame(width: 7, height: 7)
            .shadow(color: on ? Theme.error : .clear, radius: 4)
            .opacity(on && dim ? 0.35 : 1)
            .onAppear {
                guard on, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

extension View {
    /// 웹 .card: 패널→바탕 그라데이션 + 선 색 테두리
    func draftCard(radius: CGFloat = Theme.corner) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self.background(Theme.cardGradient, in: shape).overlay(shape.stroke(Theme.line, lineWidth: 1))
    }
}
