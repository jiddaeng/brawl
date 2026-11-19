import SwiftUI
import WidgetKit
import BrawlCore

extension ActivityDisplayState {
    var isReady: Bool { status == .ready && !members.isEmpty }
}

// MARK: - Dynamic Island 펼침 (너비 371~408pt, 높이 84~160pt)

/// 왼쪽 위: 현재 맵 · 모드
struct IslandHeader: View {
    let state: ActivityDisplayState
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(state.mapName ?? state.status.title)
                .font(Theme.koFixed(17)).foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.8)
            HStack(spacing: 5) {
                Text("DRAFT ROOM").font(Theme.displayFixed(11)).foregroundStyle(Theme.goldGradient)
                if let mode = state.modeName {
                    Text(mode).font(Theme.koFixed(11)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
            }
        }
        .padding(.leading, 10)
        .padding(.top, 2)
    }
}

/// 오른쪽 위: 아래 리스트의 승률 열 제목 (추천 완료일 때) 또는 상태 기호
struct IslandColumnLabel: View {
    let state: ActivityDisplayState
    var body: some View {
        if state.isReady {
            Text("추정 승률").font(Theme.koFixed(11)).foregroundStyle(Theme.secondaryText)
                .frame(maxHeight: .infinity, alignment: .bottom).padding(.trailing, 6)
        } else {
            StatusGlyph(status: state.status).font(.system(size: 18, weight: .semibold)).padding(.trailing, 8)
        }
    }
}

/// 아래: 순위 리스트 (최대 3줄) 또는 상태 안내
struct IslandRanking: View {
    let state: ActivityDisplayState
    var body: some View {
        Group {
            if state.isReady {
                RankingList(teams: state.rankedTeams, portrait: 22, rowSpacing: 4)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.status.title).font(Theme.koFixed(16))
                        .foregroundStyle(state.status.isError ? Theme.error : Theme.text)
                    if let m = state.message {
                        Text(m).font(.system(size: 13)).foregroundStyle(Theme.secondaryText).lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }
}

// MARK: - 잠금 화면 (HIG 표준 여백 14pt, 높이 84~160pt)

struct BrawlLockScreenView: View {
    let state: ActivityDisplayState
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("DRAFT ROOM").font(Theme.displayFixed(13)).foregroundStyle(Theme.goldGradient)
                    .shadow(color: Theme.goldShadow, radius: 0, x: 0, y: 1.5)
                Text(state.mapName ?? "Brawl Assistant").font(Theme.koFixed(16)).foregroundStyle(Theme.text).lineLimit(1)
                if let mode = state.modeName { Text(mode).font(Theme.koFixed(12)).foregroundStyle(Theme.secondaryText).lineLimit(1) }
                Spacer(minLength: 6)
                if state.isReady {
                    Text("추정 승률").font(Theme.koFixed(11)).foregroundStyle(Theme.secondaryText)
                } else {
                    Text(state.status.title).font(Theme.koFixed(12))
                        .foregroundStyle(state.status.isError ? Theme.error : Theme.secondaryText)
                }
            }
            if state.isReady {
                RankingList(teams: state.rankedTeams, portrait: 24, rowSpacing: 4)
            } else if let m = state.message {
                Text(m).font(.system(size: 13)).foregroundStyle(Theme.secondaryText).lineLimit(2)
            }
        }
        .padding(14)
    }
}

// MARK: - 순위 리스트

/// 한 줄 (웹 .alt 축소판): 순위(Lilita) · 캐릭터(희귀도 테두리 초상화 + 이름) · 오른쪽 추정 승률. 1위 줄은 금색 테두리
struct RankingList: View {
    let teams: [RankedTeam]
    let portrait: CGFloat
    let rowSpacing: CGFloat

    var body: some View {
        VStack(spacing: rowSpacing) {
            ForEach(teams, id: \.rank) { t in RankingRow(team: t, portrait: portrait) }
        }
    }
}

struct RankingRow: View {
    let team: RankedTeam
    let portrait: CGFloat
    private var best: Bool { team.rank == 1 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        HStack(spacing: 7) {
            Text("\(team.rank)").font(Theme.displayFixed(16))
                .foregroundStyle(best ? Theme.accent : Theme.secondaryText).frame(width: 12)
            TeamMembersInline(members: team.members, portrait: portrait)
            Spacer(minLength: 4)
            WinRateText(value: team.winRate, size: 17, highlight: best)
        }
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Theme.deep.opacity(0.9), in: shape)
        .overlay(shape.stroke(best ? Theme.accent.opacity(0.9) : Theme.line, lineWidth: 1))
    }
}

/// 캐릭터 나열: 3명 이하면 [초상화 이름], 그보다 많으면 초상화만
struct TeamMembersInline: View {
    let members: [ActivityDisplayState.Member]
    let portrait: CGFloat
    var body: some View {
        let showNames = members.count <= 3
        HStack(spacing: showNames ? 8 : 3) {
            ForEach(members, id: \.id) { m in
                HStack(spacing: 4) {
                    MiniPortrait(id: m.id, size: showNames ? portrait : portrait - 4, rarity: m.rarity)
                    if showNames {
                        Text(m.name).font(Theme.koFixed(12)).foregroundStyle(Theme.text)
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                }
            }
        }
    }
}

/// 추정 승률 숫자 (줄바꿈·축소 없이 고정)
struct WinRateText: View {
    let value: String
    let size: CGFloat
    let highlight: Bool
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(value).font(Theme.displayFixed(size))
                .foregroundStyle(highlight ? Theme.accent : Theme.text)
            Text("%").font(Theme.displayFixed(max(11, size * 0.62))).foregroundStyle(Theme.secondaryText)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

// MARK: - 공용 조각

/// 축소형: 초상화를 살짝 겹쳐 좁은 폭(52pt)에 3명
struct StackedPortraits: View {
    let members: [ActivityDisplayState.Member]
    let size: CGFloat
    var body: some View {
        HStack(spacing: -size * 0.35) {
            ForEach(members, id: \.id) { m in
                MiniPortrait(id: m.id, size: size, rarity: m.rarity, circle: true)
                    .overlay(Circle().stroke(Color.black, lineWidth: 1))
            }
        }
    }
}

struct StatusGlyph: View {
    let status: AnalysisStatus
    var body: some View {
        Image(systemName: icon).foregroundStyle(status.isError ? Theme.error : Theme.secondaryText)
    }
    private var icon: String {
        switch status {
        case .ready: return "checkmark"
        case .mapFailed, .modeFailed: return "exclamationmark.triangle.fill"
        case .noRecommendation, .computing: return "hourglass"
        case .ended, .idle: return "stop.fill"
        default: return "dot.radiowaves.left.and.right"
        }
    }
}

extension AnalysisStatus {
    var isError: Bool { self == .mapFailed || self == .modeFailed }
}

/// 앱이 App Group 에 저장한 96px 초상화 (Live Activity 는 네트워크 이미지를 불러올 수 없다)
/// 희귀도 색 빛 바탕 + 같은 색 테두리 (웹 .br 축소판)
struct MiniPortrait: View {
    let id: Int
    let size: CGFloat
    var rarity: String? = nil
    var circle = false
    var body: some View {
        let rc = Theme.rarity(rarity)
        let shape = RoundedRectangle(cornerRadius: circle ? size / 2 : size * 0.28, style: .continuous)
        ZStack {
            Theme.deep
            RadialGradient(colors: [rc.opacity(0.8), .clear], center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: size * 0.7)
            if let path = AppGroup.store?.portraitURL(brawlerID: id).path, let img = UIImage(contentsOfFile: path) {
                Image(uiImage: img).resizable().scaledToFit().padding(1)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.stroke(rc, lineWidth: 1.2))
    }
}
