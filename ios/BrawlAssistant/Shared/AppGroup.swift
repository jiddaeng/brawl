import Foundation
import BrawlCore

/// 앱·위젯·방송 확장이 함께 쓰는 App Group. 식별자는 각 타깃 Info.plist 의 BrawlAppGroup (project.yml 의 APP_GROUP_ID)
enum AppGroup {
    static var identifier: String {
        (Bundle.main.object(forInfoDictionaryKey: "BrawlAppGroup") as? String) ?? "group.com.example.brawlassistant"
    }

    static var store: SharedStore? {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else { return nil }
        return SharedStore(root: url.appendingPathComponent("BrawlAssistant", isDirectory: true))
    }

    /// Live Activity 푸시 중계 서버 주소 (Info.plist BrawlPushRelayURL ← project.yml PUSH_RELAY_URL). 비어 있으면 사용 안 함
    static var pushRelayURL: String? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "BrawlPushRelayURL") as? String, !s.isEmpty, !s.contains("$(") else { return nil }
        return s
    }

    /// APNs 환경: Xcode 로 설치한 개발 빌드는 development, TestFlight·App Store 는 production
    static var apsEnvironment: String {
        (Bundle.main.object(forInfoDictionaryKey: "BrawlAPSEnvironment") as? String) ?? "development"
    }

    /// 방송 확장 번들 id (RPSystemBroadcastPickerView.preferredExtension)
    static var broadcastExtensionBundleID: String? {
        Bundle.main.object(forInfoDictionaryKey: "BrawlBroadcastExtensionBundleID") as? String
    }
}

/// 프로세스 사이 알림 (Darwin notify). 내용은 싣지 않고 "바뀌었으니 파일을 다시 읽어라" 신호만 보낸다
enum DarwinSignal: String, CaseIterable {
    case sessionChanged = "session.changed"            // 확장 → 앱: session.json 갱신
    case recommendationsChanged = "recommendations.changed" // 앱 → 확장: 미리 계산된 추천 파일 갱신
    case stopRequested = "broadcast.stop"              // 앱 → 확장: 방송 종료 요청
    case retryRequested = "broadcast.retry"            // 앱 → 확장: 인식 다시 시도

    var name: String { AppGroup.identifier + "." + rawValue }

    func post() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }
}

final class DarwinObserver {
    private var handlers: [String: () -> Void] = [:]
    private let lock = NSLock()

    func observe(_ signal: DarwinSignal, _ handler: @escaping () -> Void) {
        lock.lock(); handlers[signal.name] = handler; lock.unlock()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), observer, { _, observer, name, _, _ in
            guard let observer, let name else { return }
            Unmanaged<DarwinObserver>.fromOpaque(observer).takeUnretainedValue().fire(name.rawValue as String)
        }, signal.name as CFString, nil, .deliverImmediately)
    }

    private func fire(_ name: String) {
        lock.lock(); let h = handlers[name]; lock.unlock()
        h?()
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
    }
}
