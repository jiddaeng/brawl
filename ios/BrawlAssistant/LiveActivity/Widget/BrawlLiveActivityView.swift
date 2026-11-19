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
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(state.modeName ?? "Brawl Assistant")
                .font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(1)
        }
        .padding(.leading, 4)
    }
}

/// 오른쪽 위: 아래 리스트의 승률 열 제목 (추천 완료일 때) 또는 상태 기호
struct IslandColumnLabel: View {
    let state: ActivityDisplayState
    var body: some View {
        if state.isReady {
            Text("추정 승률").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondaryText)
                .frame(maxHeight: .infinity, alignment: .bottom).padding(.trailing, 4)
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
                RankingList(teams: state.rankedTeams, portrait: 24, rowSpacing: 6)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.status.title).font(.system(size: 15, weight: .semibold))
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: Theme.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                Text(state.mapName ?? "Brawl Assistant").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                if let mode = state.modeName { Text(mode).font(.system(size: 13)).foregroundStyle(Theme.secondaryText).lineLimit(1) }
                Spacer(minLength: 8)
                if state.isReady {
                    Text("추정 승률").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondaryText)
                } else {
                    Text(state.status.title).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(state.status.isError ? Theme.error : Theme.secondaryText)
                }
            }
            if state.isReady {
                RankingList(teams: state.rankedTeams, portrait: 26, rowSpacing: 6)
            } else if let m = state.message {
                Text(m).font(.system(size: 13)).foregroundStyle(Theme.secondaryText).lineLimit(2)
            }
        }
        .padding(14)
    }
}

// MARK: - 순위 리스트

/// 한 줄: 순위 · 캐릭터(초상화 + 이름) · 오른쪽 추정 승률. 1위 승률만 강조색
struct RankingList: View {
    let teams: [RankedTeam]
    let portrait: CGFloat
    let rowSpacing: CGFloat

    var body: some View {
        VStack(spacing: rowSpacing) {
            ForEach(teams, id: \.rank) { t in
                HStack(spacing: 8) {
                    Text("\(t.rank)").font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(t.rank == 1 ? Theme.text : Theme.secondaryText).frame(width: 12)
                    TeamMembersInline(members: t.members, portrait: portrait)
                    Spacer(minLength: 6)
                    WinRateText(value: t.winRate, size: 16, highlight: t.rank == 1)
                }
            }
        }
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
                    MiniPortrait(id: m.id, size: showNames ? portrait : portrait - 4, circle: true)
                    if showNames {
                        Text(m.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
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
            Text(value).font(.system(size: size, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(highlight ? Theme.accent : Theme.text)
            Text("%").font(.system(size: max(11, size * 0.65), weight: .medium)).foregroundStyle(Theme.secondaryText)
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
                MiniPortrait(id: m.id, size: size, circle: true)
                    .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
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
struct MiniPortrait: View {
    let id: Int
    let size: CGFloat
    var circle = false
    var body: some View {
        Group {
            if let path = AppGroup.store?.portraitURL(brawlerID: id).path, let img = UIImage(contentsOfFile: path) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Theme.secondaryBackground
            }
        }
        .frame(width: size, height: size)
        .background(Theme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: circle ? size / 2 : size * 0.25, style: .continuous))
    }
}
