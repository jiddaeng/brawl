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
                    Label { Text("BRAWL ASSISTANT").font(.caption2.weight(.heavy)) } icon: { Image(systemName: Theme.symbol) }
                        .foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let score = s.score {
                        Text("\(score)").font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(Theme.accent)
                    } else {
                        StatusBadge(status: s.status)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    BrawlExpandedView(state: s)
                }
            } compactLeading: {
                Image(systemName: Theme.symbol).foregroundStyle(s.status == .ready ? Theme.accent : Theme.secondaryText)
            } compactTrailing: {
                if s.status == .ready, !s.members.isEmpty {
                    HStack(spacing: 2) { ForEach(s.members.prefix(3), id: \.id) { MiniPortrait(id: $0.id, size: 18) } }
                } else {
                    StatusBadge(status: s.status, compact: true)
                }
            } minimal: {
                Image(systemName: Theme.symbol).foregroundStyle(s.status == .ready ? Theme.accent : Theme.secondaryText)
            }
            .keylineTint(Theme.accent)
        }
    }
}
