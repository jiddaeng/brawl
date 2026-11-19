import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 앱이 백그라운드일 때 Live Activity 를 갱신하는 경로: ActivityKit 푸시(APNs).
/// 방송 확장은 앱이 만든 Live Activity 에 접근할 수 없으므로(실기기 확인: 확장에서 Activity.activities 가 비어 있음),
/// 확장은 중계 서버(server/live-activity-relay)에 '푸시 토큰 + 표시 값'만 보내고, 서버가 APNs 로 갱신 푸시를 보낸다.
/// APNs 인증 키(.p8)는 서버에만 있다. 앱·확장에는 비밀 값이 없다.

/// 앱이 Live Activity 를 시작할 때 받은 푸시 토큰 (App Group 에 저장, 방송 확장이 읽는다)
public struct LiveActivityPushRegistration: Codable, Hashable, Sendable {
    /// ActivityKit 푸시 토큰 (hex)
    public var token: String
    /// "development"(Xcode 로 설치한 개발 빌드) 또는 "production"(TestFlight·App Store)
    public var environment: String
    public var activityID: String
    public var updatedAt: Date
    /// 맵이 바뀔 때 알림(펼침)으로 갱신할지 (앱 설정 값을 복사해 둔다)
    public var alertOnMapChange: Bool

    public init(token: String, environment: String, activityID: String, updatedAt: Date, alertOnMapChange: Bool) {
        self.token = token; self.environment = environment; self.activityID = activityID
        self.updatedAt = updatedAt; self.alertOnMapChange = alertOnMapChange
    }

    public static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
}

/// 중계 서버로 보내는 요청 (server/live-activity-relay 의 POST /v1/live-activity 와 같은 형식)
public struct RelayRequest: Codable, Hashable, Sendable {
    public enum Event: String, Codable, Sendable { case update, end }
    public struct Alert: Codable, Hashable, Sendable { public var title: String; public var body: String }

    public var token: String
    public var environment: String
    public var event: Event
    /// ActivityKit ContentState 그대로. ActivityKit 은 기본 설정 JSONDecoder 로 읽으므로 기본 JSONEncoder 로 만든다
    /// (Date 는 2001-01-01 기준 초). 서버는 이 값을 바꾸지 않고 그대로 넘긴다
    public var contentState: ActivityDisplayState
    /// 중요한 갱신(맵 변경)만 알림으로. 너무 자주 보내면 시스템이 제한한다
    public var alert: Alert?

    public init(registration: LiveActivityPushRegistration, state: ActivityDisplayState, event: Event, alert: Alert?) {
        token = registration.token; environment = registration.environment
        self.event = event; contentState = state; self.alert = alert
    }

    /// 요청 본문. contentState 는 기본 JSONEncoder 와 같은 형식이어야 한다
    public func body() throws -> Data { try JSONEncoder().encode(self) }

    /// 표시 값에 들어가는 키 (서버 검증 목록과 같아야 한다: server/live-activity-relay/relay.mjs CONTENT_STATE_KEYS)
    public static let contentStateKeys: Set<String> = ["status", "mapName", "modeName", "members", "score", "winRate", "message", "updatedAt", "teams"]
}

public enum RelayError: Error, LocalizedError, Equatable {
    case notConfigured
    case noRegistration
    case http(Int, String)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "푸시 중계 서버 주소가 설정되지 않았습니다"
        case .noRegistration: return "Live Activity 푸시 토큰이 없습니다 (앱에서 Live Activity 를 다시 켜 주세요)"
        case .http(let c, let m): return "중계 서버 오류 \(c): \(m)"
        case .transport(let m): return "중계 서버에 연결하지 못했습니다: \(m)"
        }
    }
}

public protocol RelaySending: Sendable {
    func post(_ url: URL, body: Data) async throws -> (Int, Data)
}

public struct URLSessionRelaySender: RelaySending {
    public init() {}
    public func post(_ url: URL, body: Data) async throws -> (Int, Data) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (d, r) = try await URLSession.shared.data(for: req)
        return ((r as? HTTPURLResponse)?.statusCode ?? 0, d)
    }
}

/// 방송 확장이 쓰는 중계 클라이언트
public struct LiveActivityRelayClient: Sendable {
    public let endpoint: URL?
    let sender: RelaySending

    /// baseURL: 예) https://relay.example.com  → POST {baseURL}/v1/live-activity
    public init(baseURL: String?, sender: RelaySending = URLSessionRelaySender()) {
        let trimmed = baseURL?.trimmingCharacters(in: .whitespaces) ?? ""
        endpoint = trimmed.isEmpty ? nil : URL(string: trimmed.hasSuffix("/") ? trimmed + "v1/live-activity" : trimmed + "/v1/live-activity")
        self.sender = sender
    }

    public var isConfigured: Bool { endpoint != nil }

    public func send(_ request: RelayRequest) async throws {
        guard let url = endpoint else { throw RelayError.notConfigured }
        let status: Int, data: Data
        do { (status, data) = try await sender.post(url, body: try request.body()) }
        catch { throw RelayError.transport(error.localizedDescription) }
        guard (200..<300).contains(status) else { throw RelayError.http(status, String(decoding: data.prefix(300), as: UTF8.self)) }
    }

    /// 맵이 바뀐 갱신인지 (알림 여부 판단)
    public static func alert(for state: ActivityDisplayState, previous: ActivityDisplayState?, enabled: Bool) -> RelayRequest.Alert? {
        guard enabled, state.status == .ready, let map = state.mapName, map != previous?.mapName else { return nil }
        return RelayRequest.Alert(title: "BEST TEAM", body: "\(map) · \(state.members.map(\.name).joined(separator: " "))")
    }
}
