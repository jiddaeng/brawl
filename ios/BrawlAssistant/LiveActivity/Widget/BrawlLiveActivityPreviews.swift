#if DEBUG
import SwiftUI
import WidgetKit
import BrawlCore

// Xcode 캔버스에서 앱을 실행하지 않고 Dynamic Island·잠금 화면 모양을 확인한다 (Widget 스킴 실행은 필요 없음)
private extension ActivityDisplayState {
    static let ready = ActivityDisplayState(status: .ready, mapName: "기습적 움직임", modeName: "바운티",
        members: [.init(id: 16000015, name: "파이퍼"), .init(id: 16000109, name: "코스모"), .init(id: 16000106, name: "볼트")],
        score: 84, winRate: "57.5", updatedAt: .now, teams: [
            RankedTeam(rank: 1, members: [.init(id: 16000015, name: "파이퍼"), .init(id: 16000109, name: "코스모"), .init(id: 16000106, name: "볼트")], winRate: "57.5", score: 84),
            RankedTeam(rank: 2, members: [.init(id: 16000027, name: "8비트"), .init(id: 16000110, name: "빈스"), .init(id: 16000106, name: "볼트")], winRate: "60.2", score: 83),
            RankedTeam(rank: 3, members: [.init(id: 16000067, name: "윌로우"), .init(id: 16000072, name: "펄"), .init(id: 16000106, name: "볼트")], winRate: "57.5", score: 82),
        ])
    static let searching = ActivityDisplayState(status: .broadcasting, message: "브롤스타즈에서 맵 이름이 보이는 화면을 띄우면 인식합니다.", updatedAt: .now)
    static let failed = ActivityDisplayState(status: .mapFailed, message: "맵 이름을 찾지 못했습니다.", updatedAt: .now)
}

#Preview("Dynamic Island 펼침", as: .dynamicIsland(.expanded), using: BrawlActivityAttributes(startedAt: .now)) {
    BrawlLiveActivity()
} contentStates: {
    ActivityDisplayState.ready
    ActivityDisplayState.searching
    ActivityDisplayState.failed
}

#Preview("Dynamic Island 축소", as: .dynamicIsland(.compact), using: BrawlActivityAttributes(startedAt: .now)) {
    BrawlLiveActivity()
} contentStates: {
    ActivityDisplayState.ready
    ActivityDisplayState.searching
}

#Preview("Dynamic Island 최소", as: .dynamicIsland(.minimal), using: BrawlActivityAttributes(startedAt: .now)) {
    BrawlLiveActivity()
} contentStates: {
    ActivityDisplayState.ready
}

#Preview("잠금 화면", as: .content, using: BrawlActivityAttributes(startedAt: .now)) {
    BrawlLiveActivity()
} contentStates: {
    ActivityDisplayState.ready
    ActivityDisplayState.failed
}
#endif
