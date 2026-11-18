import SwiftUI
import WidgetKit
import BrawlCore

/// Expanded: 현재 맵 / 모드 / BEST TEAM / 종합 점수
struct BrawlExpandedView: View {
    let state: ActivityDisplayState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let map = state.mapName {
                Text("현재 맵: \(map)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
            }
            if let mode = state.modeName { Text("모드: \(mode)").font(.caption).foregroundStyle(Theme.secondaryText) }
            if state.status == .ready, !state.members.isEmpty {
                Text("BEST TEAM").font(.caption2.weight(.heavy)).tracking(1.5).foregroundStyle(Theme.accent).padding(.top, 2)
                HStack(spacing: 10) {
                    ForEach(state.members, id: \.id) { m in
                        VStack(spacing: 2) {
                            MiniPortrait(id: m.id, size: state.members.count > 3 ? 30 : 36)
                            Text(m.name).font(.caption2).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                if let score = state.score {
                    Text("종합 점수: \(score)\(state.winRate.map { " · 추정 승률 \($0)%" } ?? "")")
                        .font(.caption2.monospacedDigit()).foregroundStyle(Theme.secondaryText)
                }
            } else {
                Text(state.status.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                if let m = state.message { Text(m).font(.caption2).foregroundStyle(Theme.secondaryText).lineLimit(2) }
            }
        }
    }
}

/// 잠금 화면 (Dynamic Island 가 없는 기기·화면에서도 보이는 형태)
struct BrawlLockScreenView: View {
    let state: ActivityDisplayState
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("BRAWL ASSISTANT", systemImage: Theme.symbol).font(.caption2.weight(.heavy)).foregroundStyle(Theme.secondaryText)
                Spacer()
                if let s = state.score { Text("\(s)").font(.headline.monospacedDigit()).foregroundStyle(Theme.accent) } else { StatusBadge(status: state.status) }
            }
            BrawlExpandedView(state: state)
        }
        .padding(14)
    }
}

struct StatusBadge: View {
    let status: AnalysisStatus
    var compact = false
    var body: some View {
        let color: Color = [AnalysisStatus.mapFailed, .modeFailed].contains(status) ? Theme.error : Theme.secondaryText
        if compact {
            Image(systemName: icon).foregroundStyle(color)
        } else {
            Text(status.title).font(.caption2).foregroundStyle(color).lineLimit(1)
        }
    }
    private var icon: String {
        switch status {
        case .ready: return "checkmark"
        case .mapFailed, .modeFailed: return "exclamationmark"
        case .noRecommendation, .computing: return "hourglass"
        case .ended, .idle: return "stop"
        default: return "dot.radiowaves.left.and.right"
        }
    }
}

/// 앱이 App Group 에 저장한 96px 초상화 (Live Activity 는 네트워크 이미지를 불러올 수 없다)
struct MiniPortrait: View {
    let id: Int
    let size: CGFloat
    var body: some View {
        Group {
            if let path = AppGroup.store?.portraitURL(brawlerID: id).path, let img = UIImage(contentsOfFile: path) {
                Image(uiImage: img).resizable().scaledToFit()
            } else {
                Circle().fill(Theme.secondaryBackground)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
    }
}
