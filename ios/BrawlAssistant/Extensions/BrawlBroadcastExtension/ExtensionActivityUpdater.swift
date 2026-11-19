import Foundation
import BrawlCore
#if BROADCAST_UPDATES_ACTIVITY
import ActivityKit
#endif

/// 방송 확장에서 Live Activity 직접 갱신 시도.
/// 앱 확장에서 ActivityKit 갱신이 되는지는 Apple 문서로 확인되지 않아 실제 기기 검증이 필요하다.
/// 빌드가 안 되면 project.yml 에서 BROADCAST_UPDATES_ACTIVITY 를 빼면 된다 (그러면 앱이 화면에 올 때 앱이 갱신).
enum ExtensionActivityUpdater {
    static func update(_ state: ActivityDisplayState) async -> (Bool, String?) {
        #if BROADCAST_UPDATES_ACTIVITY
        let acts = Activity<BrawlActivityAttributes>.activities
        guard !acts.isEmpty else { return (false, "확장 프로세스에서 Live Activity 가 보이지 않음") }
        for a in acts { await a.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(30 * 60))) }
        return (true, nil)
        #else
        return (false, "확장 갱신 비활성화")
        #endif
    }

    static func end(_ state: ActivityDisplayState) async {
        #if BROADCAST_UPDATES_ACTIVITY
        for a in Activity<BrawlActivityAttributes>.activities {
            await a.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(15 * 60)))
        }
        #endif
    }
}
