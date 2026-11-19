import ActivityKit
import WidgetKit
import SwiftUI
import BrawlCore

/// Dynamic Island + 잠금 화면 Live Activity
/// HIG(Live Activities): 축소형은 하나의 정보로(왼쪽 팀 · 오른쪽 점수), 최소형은 로고 대신 갱신되는 값(점수),
/// 펼침은 축소형과 같은 상대 위치(점수는 오른쪽), 잠금 화면 여백 14pt, 글자 11pt 이상
struct BrawlLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BrawlActivityAttributes.self) { context in
            BrawlLockScreenView(state: context.state)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(Theme.text)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandHeader(state: s).dynamicIsland(verticalPlacement: .belowIfTooWide)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandScore(state: s)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandTeam(state: s)
                }
            } compactLeading: {
                if s.isReady {
                    StackedPortraits(members: Array(s.members.prefix(3)), size: 22)
                } else {
                    Image(systemName: Theme.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                }
            } compactTrailing: {
                if s.isReady, let score = s.score {
                    Text("\(score)").font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Theme.accent)
                } else {
                    StatusGlyph(status: s.status).font(.system(size: 14, weight: .semibold))
                }
            } minimal: {
                if s.isReady, let score = s.score {
                    Text("\(score)").font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Theme.accent)
                } else {
                    Image(systemName: Theme.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                }
            }
            .keylineTint(Theme.accent)
        }
    }
}
