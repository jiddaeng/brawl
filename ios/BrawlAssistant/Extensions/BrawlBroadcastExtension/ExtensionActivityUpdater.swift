import Foundation
import BrawlCore
#if BROADCAST_UPDATES_ACTIVITY
import ActivityKit
#endif

/// 방송 확장에서 Live Activity 갱신.
/// 1) ActivityKit 직접 갱신: 실기기(iPhone 14 Pro, iOS 26.6.1)에서 확장 프로세스의 Activity.activities 가 비어 있어 동작하지 않음을 확인.
///    이후 iOS 에서 바뀔 수 있으므로 시도는 남겨 둔다 (비용 거의 없음).
/// 2) 푸시 중계: 앱이 받아 둔 ActivityKit 푸시 토큰 + 표시 값을 중계 서버로 보내면 서버가 APNs 로 갱신 푸시를 보낸다.
enum ExtensionActivityUpdater {
    static func update(_ state: ActivityDisplayState, previous: ActivityDisplayState?, store: SharedStore?) async -> ExtensionActivityUpdate {
        await send(state, previous: previous, store: store, event: .update)
    }

    static func end(_ state: ActivityDisplayState, store: SharedStore?) async -> ExtensionActivityUpdate {
        await send(state, previous: nil, store: store, event: .end)
    }

    private static func send(_ state: ActivityDisplayState, previous: ActivityDisplayState?, store: SharedStore?, event: RelayRequest.Event) async -> ExtensionActivityUpdate {
        let key = state.contentKey
        #if BROADCAST_UPDATES_ACTIVITY
        let acts = Activity<BrawlActivityAttributes>.activities
        if !acts.isEmpty {
            for a in acts {
                if event == .end {
                    await a.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(15 * 60)))
                } else {
                    await a.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(30 * 60)))
                }
            }
            return ExtensionActivityUpdate(contentKey: key, succeeded: true, error: nil, at: Date(), path: .direct)
        }
        #endif
        let client = LiveActivityRelayClient(baseURL: AppGroup.pushRelayURL)
        guard client.isConfigured else {
            return ExtensionActivityUpdate(contentKey: key, succeeded: false,
                error: "확장 프로세스에서 Live Activity 가 보이지 않고 푸시 중계 서버가 설정되지 않음", at: Date(), path: ExtensionActivityUpdate.Path.none)
        }
        guard let reg = store?.read(LiveActivityPushRegistration.self, .liveActivityPush) else {
            return ExtensionActivityUpdate(contentKey: key, succeeded: false, error: RelayError.noRegistration.localizedDescription, at: Date(), path: .relay)
        }
        let alert = event == .update ? LiveActivityRelayClient.alert(for: state, previous: previous, enabled: reg.alertOnMapChange) : nil
        do {
            try await client.send(RelayRequest(registration: reg, state: state, event: event, alert: alert))
            return ExtensionActivityUpdate(contentKey: key, succeeded: true, error: nil, at: Date(), path: .relay)
        } catch {
            return ExtensionActivityUpdate(contentKey: key, succeeded: false, error: error.localizedDescription, at: Date(), path: .relay)
        }
    }
}
