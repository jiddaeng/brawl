import SwiftUI
import WidgetKit
import BrawlCore

extension ActivityDisplayState {
    var isReady: Bool { status == .ready && !members.isEmpty }
}

// MARK: - Dynamic Island 펼침

/// 왼쪽 위: 앱 이름 · 현재 맵 · 모드
struct IslandHeader: View {
    let state: ActivityDisplayState
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("BRAWL ASSISTANT")
                .font(.system(size: 10, weight: .heavy)).tracking(1.2)
                .foregroundStyle(Theme.secondaryText)
            Text(state.mapName ?? state.status.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.8)
            if let mode = state.modeName {
                Text(mode).font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
        }
        .padding(.leading, 4)
    }
}

/// 오른쪽 위: 종합 점수 (추천 완료일 때만)
struct IslandScore: View {
    let state: ActivityDisplayState
    var body: some View {
        if state.isReady, let score = state.score {
            VStack(alignment: .trailing, spacing: 0) {
                Text("종합 점수").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                Text("\(score)")
                    .font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Theme.accent)
            }
            .padding(.trailing, 4)
        } else {
            StatusGlyph(status: state.status).font(.system(size: 18, weight: .semibold)).padding(.trailing, 6)
        }
    }
}

/// 아래: BEST TEAM (초상화 + 이름) 또는 상태 안내
struct IslandTeam: View {
    let state: ActivityDisplayState
    var body: some View {
        Group {
            if state.isReady {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("BEST TEAM").font(.system(size: 10, weight: .heavy)).tracking(1.2).foregroundStyle(Theme.accent)
                        Spacer()
                        if let wr = state.winRate {
                            Text("추정 승률 \(wr)%").font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(Theme.secondaryText)
                        }
                    }
                    TeamChips(members: state.members)
                }
            } else {
                HStack(spacing: 8) {
                    Text(state.status.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                    if let m = state.message {
                        Text(m).font(.system(size: 11)).foregroundStyle(Theme.secondaryText).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }
}

/// 펼침용: [초상화 이름] 칩을 가로로 (펼침 높이 한도 안에 들어가도록 한 줄)
struct TeamChips: View {
    let members: [ActivityDisplayState.Member]
    var body: some View {
        let small = members.count > 3
        HStack(spacing: small ? 4 : 8) {
            ForEach(members, id: \.id) { m in
                HStack(spacing: 6) {
                    MiniPortrait(id: m.id, size: small ? 22 : 28, circle: true)
                    if !small || members.count <= 4 {
                        Text(m.name).font(.system(size: small ? 10 : 13, weight: .semibold)).foregroundStyle(Theme.text)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                .padding(.leading, 3).padding(.trailing, small ? 4 : 10).padding(.vertical, 3)
                .background(Theme.secondaryBackground, in: Capsule())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - 잠금 화면

/// 잠금 화면 카드 (높이 한도 약 160pt 안에서 여백 14 로 통일)
struct BrawlLockScreenView: View {
    let state: ActivityDisplayState
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: Theme.symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent)
                Text("BRAWL ASSISTANT").font(.system(size: 10, weight: .heavy)).tracking(1.2).foregroundStyle(Theme.secondaryText)
                Spacer()
                if state.isReady, let wr = state.winRate {
                    Text("추정 승률 \(wr)%").font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(Theme.secondaryText)
                } else {
                    Text(state.status.title).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(state.status.isError ? Theme.error : Theme.secondaryText)
                }
            }
            if state.isReady {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(state.mapName ?? "").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
                        if let mode = state.modeName { Text(mode).font(.system(size: 12)).foregroundStyle(Theme.secondaryText) }
                    }
                    Spacer()
                    if let score = state.score {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(score)").font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.accent)
                            Text("/100").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
                TeamRow(members: state.members, portrait: state.members.count > 3 ? 30 : 38, nameSize: 12)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    if let map = state.mapName {
                        Text([map, state.modeName].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    }
                    Text(state.message ?? state.status.title).font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(2)
                }
            }
        }
        .padding(14)
    }
}

// MARK: - 공용 조각

/// 초상화 + 이름을 같은 폭으로 나란히
struct TeamRow: View {
    let members: [ActivityDisplayState.Member]
    let portrait: CGFloat
    let nameSize: CGFloat
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(members, id: \.id) { m in
                VStack(spacing: 4) {
                    MiniPortrait(id: m.id, size: portrait)
                    Text(m.name).font(.system(size: nameSize, weight: .semibold)).foregroundStyle(Theme.text)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// 축소형: 초상화를 살짝 겹쳐 좁은 폭에 3명
struct StackedPortraits: View {
    let members: [ActivityDisplayState.Member]
    let size: CGFloat
    var body: some View {
        HStack(spacing: -size * 0.3) {
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
        .clipShape(RoundedRectangle(cornerRadius: circle ? size / 2 : size * 0.28, style: .continuous))
    }
}
