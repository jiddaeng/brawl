import ActivityKit
import WidgetKit
import SwiftUI
import BrawlCore

/// Dynamic Island + 잠금 화면 Live Activity: 순위별 조합 리스트 (캐릭터 → 오른쪽 추정 승률)
/// HIG(Live Activities): 축소형은 하나의 정보(왼쪽 1위 조합 · 오른쪽 1위 추정 승률), 최소형은 로고 대신 갱신되는 값,
/// 펼침은 축소형과 같은 배치(캐릭터 왼쪽 · 승률 오른쪽)를 줄마다 이어 간다. 높이 160pt, 잠금 화면 여백 14pt, 글자 11pt 이상
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
                    IslandColumnLabel(state: s)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandRanking(state: s)
                }
            } compactLeading: {
                if s.isReady {
                    StackedPortraits(members: Array(s.members.prefix(3)), size: 22)
                } else {
                    Image(systemName: Theme.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                }
            } compactTrailing: {
                if s.isReady, let wr = s.winRate {
                    WinRateText(value: wr, size: 15, highlight: true)
                } else {
                    StatusGlyph(status: s.status).font(.system(size: 14, weight: .semibold))
                }
            } minimal: {
                if s.isReady, let wr = s.winRate {
                    Text(wr).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Theme.accent).minimumScaleFactor(0.7).lineLimit(1)
                } else {
                    Image(systemName: Theme.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                }
            }
            .keylineTint(Theme.accent)
        }
    }
}
