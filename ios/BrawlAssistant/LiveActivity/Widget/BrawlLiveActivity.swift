import ActivityKit
import WidgetKit
import SwiftUI
import BrawlCore

/// Dynamic Island + 잠금 화면 Live Activity
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
                Image(systemName: Theme.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(s.isReady ? Theme.accent : Theme.secondaryText)
            } compactTrailing: {
                if s.isReady {
                    StackedPortraits(members: Array(s.members.prefix(3)), size: 20)
                } else {
                    StatusGlyph(status: s.status).font(.system(size: 13, weight: .semibold))
                }
            } minimal: {
                Image(systemName: Theme.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(s.isReady ? Theme.accent : Theme.secondaryText)
            }
            .keylineTint(Theme.accent)
        }
    }
}
