import SwiftUI
import BrawlCore

/// 플레이어 카드: 연결된 플레이어(이름·태그·보유 브롤러) 또는 연결 안내
struct PlayerCard: View {
    @EnvironmentObject var app: AppState
    let onLink: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 30)).foregroundStyle(Theme.accent)
            if let p = app.gameData.player {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(p.name ?? "플레이어").font(Theme.ko(18)).foregroundStyle(Theme.text).lineLimit(1)
                        Text(p.tag ?? app.gameData.tag ?? "").font(Theme.mono(11)).foregroundStyle(Theme.secondaryText)
                    }
                    Text(ownedLine(p)).font(Theme.mono(11)).foregroundStyle(Theme.secondaryText).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                if let t = p.trophies {
                    HStack(spacing: 3) {
                        Image(systemName: "trophy.fill").font(.system(size: 12)).foregroundStyle(Theme.accent)
                        Text(t.formatted()).font(Theme.display(18)).foregroundStyle(Theme.text)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("플레이어 연결").font(Theme.ko(18)).foregroundStyle(Theme.text)
                    Text("게임 태그를 넣으면 내가 가진 브롤러로만 추천합니다")
                        .font(.caption).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(14)
        .draftCard()
        .contentShape(Rectangle())
        .onTapGesture(perform: onLink)
        .accessibilityAddTraits(.isButton)
    }

    private func ownedLine(_ p: PlayerProfile) -> String {
        let total = app.catalog?.brawlers.count
        let owned = p.brawlers.count
        let used = app.ownedIDs?.count
        var s = "보유 \(owned)\(total.map { "/\($0)" } ?? "")"
        if let u = used, u != owned { s += " · 추천 후보 \(u) (파워 \(app.minPower)+)" }
        if !app.ownedOnly { s += " · 전체 브롤러로 추천 중" }
        return s
    }
}

/// 지금 열린 맵: 한 번 탭하면 추천. 최근 경기 맵에는 표시
struct CurrentMapsStrip: View {
    @EnvironmentObject var app: AppState
    let maps: [CatalogMap]
    let selected: MapID?
    let recent: MapID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("지금 열린 맵").font(Theme.ko(20)).foregroundStyle(Theme.text)
                Text("공식 이벤트").font(Theme.mono(11)).foregroundStyle(Theme.secondaryText)
                Spacer()
                if app.gameDataLoading { ProgressView().controlSize(.small).tint(Theme.accent) }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(maps) { m in
                        Button { app.chooseMapManually(m) } label: {
                            MapTile(map: m, selected: m.id == selected, recent: m.id == recent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct MapTile: View {
    let map: CatalogMap
    let selected: Bool
    let recent: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(map.modeKo).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.goldInk)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                if map.ranked { Text("랭크").font(Theme.mono(9).weight(.bold)).foregroundStyle(Theme.blue) }
            }
            Text(map.ko).font(Theme.ko(16)).foregroundStyle(Theme.text).lineLimit(2).minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            if recent {
                Text("최근 경기").font(Theme.mono(10).weight(.bold)).foregroundStyle(Theme.positive)
            } else {
                Text(map.name).font(Theme.mono(9)).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
        }
        .padding(10)
        .frame(width: 128, height: 96, alignment: .topLeading)
        .background(Theme.deep, in: shape)
        .overlay(shape.stroke(selected ? Theme.accent : Theme.line, lineWidth: selected ? 1.5 : 1))
        .shadow(color: selected ? Theme.accent.opacity(0.25) : .clear, radius: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(map.ko), \(map.modeKo)\(recent ? ", 최근 경기 맵" : "")")
    }
}

/// 플레이어 태그 입력
struct PlayerLinkSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var tag = ""
    @AppStorage(AppState.ownedOnlyKey) private var ownedOnly = true
    @AppStorage(AppState.minPowerKey) private var minPower = 1

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("게임 프로필의 # 으로 시작하는 태그를 넣으세요. 브롤스타즈 → 프로필 → 이름 아래 태그를 눌러 복사할 수 있습니다.")
                        .font(.subheadline).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
                    TextField("#2PP", text: $tag)
                        .font(Theme.mono(20))
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .padding(14)
                        .background(Theme.deep, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line, lineWidth: 1))
                    if let e = app.gameDataError { Text(e).font(.footnote).foregroundStyle(Theme.error) }
                    PrimaryButton(title: app.gameDataLoading ? "불러오는 중…" : "연결", systemImage: "link") {
                        Task { if await app.linkPlayer(tag: tag) { dismiss() } }
                    }
                    .disabled(app.gameDataLoading || tag.isEmpty)

                    if app.gameData.player != nil {
                        VStack(spacing: 0) {
                            Toggle("보유 브롤러만 추천", isOn: $ownedOnly)
                                .onChange(of: ownedOnly) { _, _ in app.ownedSettingsChanged() }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                            RowDivider(inset: 16)
                            Stepper("최소 파워 \(minPower)", value: $minPower, in: 1...11)
                                .onChange(of: minPower) { _, _ in app.ownedSettingsChanged() }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .disabled(!ownedOnly)
                        }
                        .foregroundStyle(Theme.text).tint(Theme.accent)
                        .draftCard()
                        Button("연결 해제", role: .destructive) { app.unlinkPlayer(); dismiss() }
                            .font(.subheadline).frame(minHeight: 44)
                    }
                    Text("태그는 이 앱의 서버를 거쳐 Supercell 공식 API 로만 보냅니다. 받는 정보는 보유 브롤러(파워), 최근 경기의 모드·맵입니다. 게임 화면이나 계정 정보는 쓰지 않습니다.")
                        .font(.caption).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .background(DraftRoomBackground())
            .navigationTitle("플레이어 연결")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
            .onAppear { tag = app.gameData.tag ?? "" }
        }
        .preferredColorScheme(.dark)
    }
}
