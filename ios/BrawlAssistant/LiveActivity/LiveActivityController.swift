import Foundation
import ActivityKit
import BrawlCore

/// 앱 쪽 Live Activity 관리. 시작은 앱이 화면에 있을 때만 가능하다 (ActivityKit 제한).
/// 보이는 내용이 바뀌었을 때만, 최소 5초 간격으로 갱신한다.
@MainActor
final class LiveActivityController: ObservableObject {
    enum Availability: Equatable {
        case available
        case disabledByUser          // 설정 > Brawl Assistant > 실시간 현황 꺼짐
        case unsupported(String)
    }

    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    /// 게임 중(앱이 백그라운드) 갱신용 푸시 토큰을 받았는지
    @Published private(set) var hasPushToken = false
    /// 추천 변경 시 Dynamic Island 를 잠깐 펼쳐 알림 (기본 꺼짐: 게임 중 방해 방지). 방송 확장도 쓰도록 푸시 등록 정보에 복사
    var alertOnChange = UserDefaults.standard.bool(forKey: "liveActivity.alertOnChange") {
        didSet { if let r = store?.read(LiveActivityPushRegistration.self, .liveActivityPush) { savePushToken(r.token, activityID: r.activityID) } }
    }
    /// App Group 저장소 (푸시 토큰을 방송 확장에 넘긴다)
    var store: SharedStore?
    private var tokenTask: Task<Void, Never>?

    private var policy = ActivityUpdatePolicy(minInterval: 5)
    private var pending: ActivityDisplayState?
    private var pendingTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?

    private var current: Activity<BrawlActivityAttributes>? { Activity<BrawlActivityAttributes>.activities.first }

    var availability: Availability {
        let info = ActivityAuthorizationInfo()
        return info.areActivitiesEnabled ? .available : .disabledByUser
    }

    /// 앱 재실행 시 이미 떠 있는 Live Activity 에 다시 연결
    func reattach() {
        isRunning = current != nil
        if let a = current { watch(a) }
    }

    func start(with state: ActivityDisplayState) {
        lastError = nil
        guard availability == .available else { lastError = "Live Activity 가 꺼져 있습니다. 설정 > Brawl Assistant > 실시간 현황을 켜 주세요."; return }
        if current != nil { publish(state, force: true); return }
        do {
            // 앱이 백그라운드(게임 중)일 때는 앱도 방송 확장도 Live Activity 를 갱신할 수 없다 (실기기 확인).
            // 그래서 푸시 토큰을 받아 두고, 방송 확장이 중계 서버 → APNs ActivityKit 푸시로 갱신한다
            let a = try Activity.request(attributes: BrawlActivityAttributes(startedAt: Date()), content: ActivityContent(state: state, staleDate: nil),
                                         pushType: AppGroup.pushRelayURL != nil ? .token : nil)
            policy.reset(); policy.markPublished(key: state.contentKey, at: Date())
            isRunning = true
            watch(a)
        } catch {
            lastError = "Live Activity 를 시작하지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// 내용이 바뀌었을 때만 갱신. 너무 빠르면 마지막 값만 모아 두었다가 갱신
    func publish(_ state: ActivityDisplayState, force: Bool = false) {
        guard let a = current else { isRunning = false; return }
        let now = Date()
        let decision: ActivityUpdatePolicy.Decision = force ? .updateNow : policy.decide(key: state.contentKey, now: now)
        switch decision {
        case .skip: return
        case .deferUntil(let t):
            pending = state
            if pendingTask == nil {
                pendingTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(max(0, t.timeIntervalSinceNow) * 1_000_000_000))
                    guard let self else { return }
                    self.pendingTask = nil
                    if let p = self.pending { self.pending = nil; self.publish(p) }
                }
            }
        case .updateNow:
            let previousMap = policy.publishedKey?.split(separator: "|").dropFirst().first
            policy.markPublished(key: state.contentKey, at: now)
            let content = ActivityContent(state: state, staleDate: now.addingTimeInterval(30 * 60))
            let mapChanged = state.status == .ready && previousMap.map(String.init) != state.mapName
            let alert = alertOnChange && mapChanged
            Task {
                if alert {
                    await a.update(content, alertConfiguration: AlertConfiguration(title: "BEST TEAM", body: "\(state.mapName ?? "") · \(state.members.map(\.name).joined(separator: " "))", sound: .default))
                } else {
                    await a.update(content)
                }
            }
        }
    }

    /// 현재 Live Activity 에 실제로 표시 중인 값 (방송 확장이 갱신에 성공했는지 확인할 때 사용)
    var displayedState: ActivityDisplayState? { current?.content.state }

    func end(final state: ActivityDisplayState?, immediately: Bool) {
        pendingTask?.cancel(); pendingTask = nil; pending = nil
        let acts = Activity<BrawlActivityAttributes>.activities
        Task {
            for a in acts {
                let content = state.map { ActivityContent(state: $0, staleDate: nil) }
                await a.end(content, dismissalPolicy: immediately ? .immediate : .after(Date().addingTimeInterval(15 * 60)))
            }
        }
        policy.reset()
        isRunning = false
        tokenTask?.cancel(); tokenTask = nil
        store?.remove(.liveActivityPush); hasPushToken = false
    }

    private func savePushToken(_ token: String, activityID: String) {
        let reg = LiveActivityPushRegistration(token: token, environment: AppGroup.apsEnvironment, activityID: activityID,
                                               updatedAt: Date(), alertOnMapChange: alertOnChange)
        try? store?.write(reg, .liveActivityPush)
        hasPushToken = true
    }

    private func watch(_ a: Activity<BrawlActivityAttributes>) {
        // 푸시 토큰은 바뀔 수 있으므로 계속 받아 App Group 에 갱신
        tokenTask?.cancel()
        tokenTask = Task { [weak self] in
            for await data in a.pushTokenUpdates {
                let hex = LiveActivityPushRegistration.hex(data)
                await MainActor.run { self?.savePushToken(hex, activityID: a.id) }
            }
        }
        stateTask?.cancel()
        stateTask = Task { [weak self] in
            for await s in a.activityStateUpdates {
                // 사용자가 잠금 화면에서 지웠거나 시스템이 종료함 (최대 8시간 등)
                if s == .ended || s == .dismissed {
                    await MainActor.run {
                        self?.isRunning = false; self?.policy.reset()
                        self?.store?.remove(.liveActivityPush); self?.hasPushToken = false
                    }
                }
            }
        }
    }
}
