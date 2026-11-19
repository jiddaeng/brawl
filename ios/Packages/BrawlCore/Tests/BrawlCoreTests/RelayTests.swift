import XCTest
@testable import BrawlCore

final class RelayTests: XCTestCase {
    let reg = LiveActivityPushRegistration(token: "a1b2c3d4" + String(repeating: "0", count: 56), environment: "development",
                                           activityID: "ACT", updatedAt: Date(timeIntervalSince1970: 1), alertOnMapChange: true)
    var ready: ActivityDisplayState {
        var r = SessionReducer { _ in Fixtures.result("result-bounty") }
        r.reduce(.started(Date(timeIntervalSince1970: 1_000)))
        r.reduce(.recognition(.recognized(Fixtures.map(15001395), confidence: 0.9), frame: nil, at: Date(timeIntervalSince1970: 1_010)))
        return ActivityDisplayState(session: r.session)
    }

    func testContentStateRoundTripsWithDefaultDecoderLikeActivityKit() throws {
        let body = try RelayRequest(registration: reg, state: ready, event: .update, alert: nil).body()
        let obj = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        let cs = obj["contentState"] as! [String: Any]
        XCTAssertTrue(Set(cs.keys).isSubset(of: RelayRequest.contentStateKeys), "\(cs.keys)")
        // ActivityKit 은 기본 JSONDecoder 로 읽는다: 같은 값으로 되돌아와야 한다 (Date 는 2001 기준 초)
        let csData = try JSONSerialization.data(withJSONObject: cs)
        XCTAssertEqual(try JSONDecoder().decode(ActivityDisplayState.self, from: csData), ready)
        XCTAssertEqual(cs["updatedAt"] as? Double, Date(timeIntervalSince1970: 1_010).timeIntervalSinceReferenceDate)
        XCTAssertEqual(obj["token"] as? String, reg.token)
        XCTAssertEqual(obj["environment"] as? String, "development")
        XCTAssertEqual(obj["event"] as? String, "update")
        XCTAssertNil(obj["alert"])
        XCTAssertLessThan(body.count, 4096, "APNs 페이로드 4KB 제한 안")
    }

    /// 서버 테스트(server/live-activity-relay)가 검증하는 공용 입력: RELAY_FIXTURE_OUT 를 주면 iOS 가 만든 요청을 저장
    func testWriteRelayFixtureForServer() throws {
        guard let out = ProcessInfo.processInfo.environment["RELAY_FIXTURE_OUT"] else { return }
        let alert = LiveActivityRelayClient.alert(for: ready, previous: nil, enabled: true)
        try RelayRequest(registration: reg, state: ready, event: .update, alert: alert).body().write(to: URL(fileURLWithPath: out))
    }

    func testOnlyMinimalDataIsSent() throws {
        let body = String(decoding: try RelayRequest(registration: reg, state: ready, event: .update, alert: nil).body(), as: UTF8.self)
        XCTAssertFalse(body.contains("http"), "이미지 URL 등은 보내지 않음")
        XCTAssertFalse(body.contains("reasons"))
    }

    func testAlertOnlyWhenMapChanges() {
        XCTAssertNotNil(LiveActivityRelayClient.alert(for: ready, previous: nil, enabled: true))
        XCTAssertNil(LiveActivityRelayClient.alert(for: ready, previous: ready, enabled: true))
        XCTAssertNil(LiveActivityRelayClient.alert(for: ready, previous: nil, enabled: false))
        XCTAssertNil(LiveActivityRelayClient.alert(for: ActivityDisplayState(status: .broadcasting, updatedAt: Date()), previous: nil, enabled: true))
    }

    final class FakeSender: RelaySending, @unchecked Sendable {
        var url: URL?; var body: Data?; var status = 200
        func post(_ url: URL, body: Data) async throws -> (Int, Data) { self.url = url; self.body = body; return (status, Data("{\"ok\":false,\"reason\":\"BadDeviceToken\"}".utf8)) }
    }

    func testClientEndpointAndErrors() async throws {
        XCTAssertFalse(LiveActivityRelayClient(baseURL: "").isConfigured)
        XCTAssertFalse(LiveActivityRelayClient(baseURL: nil).isConfigured)
        let f = FakeSender()
        let c = LiveActivityRelayClient(baseURL: "https://relay.example.com/", sender: f)
        try await c.send(RelayRequest(registration: reg, state: ready, event: .update, alert: nil))
        XCTAssertEqual(f.url?.absoluteString, "https://relay.example.com/v1/live-activity")
        f.status = 410
        do { try await c.send(RelayRequest(registration: reg, state: ready, event: .end, alert: nil)); XCTFail() }
        catch let e as RelayError { if case .http(410, let m) = e { XCTAssertTrue(m.contains("BadDeviceToken")) } else { XCTFail("\(e)") } }
        do { try await LiveActivityRelayClient(baseURL: nil).send(RelayRequest(registration: reg, state: ready, event: .update, alert: nil)); XCTFail() }
        catch let e as RelayError { XCTAssertEqual(e, .notConfigured) }
    }

    func testRegistrationStoredInAppGroup() throws {
        let s = tempStore()
        try s.write(reg, .liveActivityPush)
        XCTAssertEqual(s.read(LiveActivityPushRegistration.self, .liveActivityPush), reg)
        XCTAssertEqual(LiveActivityPushRegistration.hex(Data([0x0a, 0xff])), "0aff")
    }
}
