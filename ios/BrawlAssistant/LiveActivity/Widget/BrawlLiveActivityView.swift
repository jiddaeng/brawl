import SwiftUI
import WidgetKit
import BrawlCore

extension ActivityDisplayState {
    var isReady: Bool { status == .ready && !members.isEmpty }
}

// MARK: - Dynamic Island 펼침 (너비 371~408pt, 높이 84~160pt)

/// 왼쪽 위: 앱 이름 · 현재 맵 · 모드
struct IslandHeader: View {
    let state: ActivityDisplayState
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Brawl Assistant")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            Text(state.mapName ?? state.status.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.8)
            if let mode = state.modeName {
                Text(mode).font(.system(size: 13)).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
        }
        .padding(.leading, 4)
    }
}

/// 오른쪽 위: 종합 점수 (축소형의 오른쪽과 같은 자리)
struct IslandScore: View {
    let state: ActivityDisplayState
    var body: some View {
        if state.isReady, let score = state.score {
            VStack(alignment: .trailing, spacing: 0) {
                Text("종합 점수").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondaryText)
                Text("\(score)")
                    .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Theme.accent)
            }
            .padding(.trailing, 4)
        } else {
            StatusGlyph(status: state.status).font(.system(size: 20, weight: .semibold)).padding(.trailing, 8)
        }
    }
}

/// 아래: BEST TEAM 칩 또는 상태 안내
struct IslandTeam: View {
    let state: ActivityDisplayState
    var body: some View {
        Group {
            if state.isReady {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("BEST TEAM").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                        Spacer()
                        if let wr = state.winRate {
                            Text("추정 승률 \(wr)%").font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(Theme.secondaryText)
                        }
                    }
                    TeamChips(members: state.members)
                }
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
        .padding(.top, 4)
        .padding(.bottom, 4)
    }
}

/// 펼침용: [초상화 이름] 칩 한 줄 (높이 한도 안)
struct TeamChips: View {
    let members: [ActivityDisplayState.Member]
    var body: some View {
        let small = members.count > 3
        HStack(spacing: small ? 4 : 8) {
            ForEach(members, id: \.id) { m in
                HStack(spacing: 8) {
                    MiniPortrait(id: m.id, size: small ? 24 : 28, circle: true)
                    if members.count <= 4 {
                        Text(m.name).font(.system(size: small ? 12 : 14, weight: .semibold)).foregroundStyle(Theme.text)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                .padding(.leading, 4).padding(.trailing, small ? 8 : 12).padding(.vertical, 4)
                .background(Theme.secondaryBackground, in: Capsule())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - 잠금 화면 (HIG 표준 여백 14pt, 높이 84~160pt)

struct BrawlLockScreenView: View {
    let state: ActivityDisplayState
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: Theme.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                Text("Brawl Assistant").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondaryText)
                Spacer()
                if state.isReady, let wr = state.winRate {
                    Text("추정 승률 \(wr)%").font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(Theme.secondaryText)
                } else {
                    Text(state.status.title).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(state.status.isError ? Theme.error : Theme.secondaryText)
                }
            }
            if state.isReady {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.mapName ?? "").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        if let mode = state.modeName { Text(mode).font(.system(size: 13)).foregroundStyle(Theme.secondaryText) }
                    }
                    Spacer(minLength: 8)
                    if let score = state.score {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(score)").font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.accent)
                            Text("/100").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
                TeamChips(members: state.members)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    if let map = state.mapName {
                        Text([map, state.modeName].compactMap { $0 }.joined(separator: ", "))
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    }
                    Text(state.message ?? state.status.title).font(.system(size: 13)).foregroundStyle(Theme.secondaryText).lineLimit(2)
                }
            }
        }
        .padding(14)
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
