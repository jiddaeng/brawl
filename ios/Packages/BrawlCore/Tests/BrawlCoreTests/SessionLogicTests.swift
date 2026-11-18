import XCTest
@testable import BrawlCore

final class SessionLogicTests: XCTestCase {
    let matcher = GameScreenMatcher(catalog: Fixtures.catalog)
    let t0 = Date(timeIntervalSince1970: 2_000_000)
    let bounty = Fixtures.map(15001395)

    func reducer(hasRecommendation: Bool = true) -> SessionReducer {
        SessionReducer { id in hasRecommendation && id == .number(15001395) ? Fixtures.result("result-bounty") : nil }
    }

    func testRecognizedMapWithPrecomputedRecommendationBecomesReady() {
        var r = reducer()
        r.reduce(.started(t0))
        XCTAssertEqual(r.session.status, .broadcasting)
        XCTAssertTrue(r.reduce(.recognition(.recognized(bounty, confidence: 0.92), frame: nil, at: t0.addingTimeInterval(3))))
        XCTAssertEqual(r.session.status, .ready)
        XCTAssertEqual(r.session.recommendation?.brawlers.map(\.ko), ["파이퍼", "코스모", "볼트"])
        XCTAssertEqual(r.session.recognition?.recognizedMode, "Bounty")
        XCTAssertEqual(r.session.recognition?.confidence, 0.92)
    }

    func testMissingRecommendationDoesNotShowAnything() {
        var r = reducer(hasRecommendation: false)
        r.reduce(.started(t0))
        r.reduce(.recognition(.recognized(bounty, confidence: 0.9), frame: nil, at: t0))
        XCTAssertEqual(r.session.status, .noRecommendation)
        XCTAssertNil(r.session.recommendation)
        XCTAssertNil(ActivityDisplayState(session: r.session).score)
    }

    func testRecommendationsChangedResolvesPendingMap() {
        var have = false
        var r = SessionReducer { _ in have ? Fixtures.result("result-bounty") : nil }
        r.reduce(.started(t0))
        r.reduce(.recognition(.recognized(bounty, confidence: 0.9), frame: nil, at: t0))
        XCTAssertEqual(r.session.status, .noRecommendation)
        have = true
        XCTAssertTrue(r.reduce(.recommendationsChanged(t0.addingTimeInterval(5))))
        XCTAssertEqual(r.session.status, .ready)
    }

    func testFailureAndAmbiguityOnlyBeforeAMapIsKnown() {
        var r = reducer()
        r.reduce(.started(t0))
        r.reduce(.recognition(.failed, frame: nil, at: t0.addingTimeInterval(30)))
        XCTAssertEqual(r.session.status, .mapFailed)
        let rock = Fixtures.catalog.maps.filter { $0.name == "Rockwall Brawl" }
        r.reduce(.recognition(.modeAmbiguous(rock), frame: nil, at: t0.addingTimeInterval(31)))
        XCTAssertEqual(r.session.status, .modeFailed)
        XCTAssertTrue(r.session.message!.contains("바위 장벽 전투"))
        r.reduce(.recognition(.recognized(bounty, confidence: 0.9), frame: nil, at: t0.addingTimeInterval(40)))
        XCTAssertEqual(r.session.status, .ready)
        // 이미 맵을 아는 상태에서는 게임 중 맵 글자가 안 보여도 추천을 지우지 않는다
        r.reduce(.recognition(.failed, frame: nil, at: t0.addingTimeInterval(90)))
        XCTAssertEqual(r.session.status, .ready)
    }

    func testRetryClearsRecognition() {
        var r = reducer()
        r.reduce(.started(t0))
        r.reduce(.recognition(.recognized(bounty, confidence: 0.9), frame: nil, at: t0))
        r.reduce(.retry(t0.addingTimeInterval(10)))
        XCTAssertEqual(r.session.status, .broadcasting)
        XCTAssertNil(r.session.recognition)
        XCTAssertNil(r.session.recommendation)
        XCTAssertEqual(r.session.startedAt, t0)
    }

    func testHeartbeatOnlyTouchesTime() {
        var r = reducer()
        r.reduce(.started(t0))
        XCTAssertFalse(r.reduce(.heartbeat(t0.addingTimeInterval(10))))
        XCTAssertEqual(r.session.updatedAt, t0.addingTimeInterval(10))
    }

    func testActivityStateAndKey() {
        var r = reducer()
        r.reduce(.started(t0))
        let waiting = ActivityDisplayState(session: r.session)
        XCTAssertTrue(waiting.members.isEmpty)
        r.reduce(.recognition(.recognized(bounty, confidence: 0.9), frame: nil, at: t0))
        let ready = ActivityDisplayState(session: r.session)
        XCTAssertEqual(ready.members.map(\.name), ["파이퍼", "코스모", "볼트"])
        XCTAssertEqual(ready.mapName, "기습적 움직임")
        XCTAssertEqual(ready.modeName, "바운티")
        XCTAssertEqual(ready.score, 84)
        XCTAssertNotEqual(waiting.contentKey, ready.contentKey)
        r.reduce(.heartbeat(t0.addingTimeInterval(20)))
        XCTAssertEqual(ActivityDisplayState(session: r.session).contentKey, ready.contentKey, "시각만 바뀌면 갱신하지 않음")
        XCTAssertLessThan(try JSONEncoder().encode(ready).count, 4096, "ActivityKit 4KB 제한")
    }

    func testHomePresentation() {
        let rec = Recommendation(result: Fixtures.result("result-bounty"))!
        var r = reducer()
        r.reduce(.started(t0))
        r.reduce(.recognition(.recognized(bounty, confidence: 0.9), frame: nil, at: t0))
        let ready = HomePresentation.make(session: r.session, manual: nil, now: t0.addingTimeInterval(5))
        XCTAssertEqual(ready.statusTitle, "추천 완료")
        XCTAssertEqual(ready.recommendation?.score, 84)
        XCTAssertTrue(ready.broadcastActive)

        let stale = HomePresentation.make(session: r.session, manual: nil, now: t0.addingTimeInterval(120))
        XCTAssertEqual(stale.statusTitle, "방송 연결 끊김")
        XCTAssertNil(stale.recommendation, "끊긴 방송의 추천은 보여 주지 않음")
        XCTAssertTrue(stale.canRetry)

        let idle = HomePresentation.make(session: .idle, manual: nil, now: t0)
        XCTAssertEqual(idle.statusTitle, "화면 인식 대기")
        XCTAssertNil(idle.recommendation)
        let manual = HomePresentation.make(session: .idle, manual: rec, now: t0)
        XCTAssertTrue(manual.isManual)
        XCTAssertEqual(manual.recommendation, rec)

        let failed = HomePresentation.make(session: AnalysisSession(status: .mapFailed, updatedAt: t0, message: "x"), manual: rec, now: t0)
        XCTAssertNil(failed.recommendation, "인식 실패 중에는 다른 추천도 보여 주지 않음")
        XCTAssertTrue(failed.isError && failed.canRetry)

        let waitingLong = HomePresentation.make(session: AnalysisSession(status: .waiting, updatedAt: t0), manual: nil, now: t0.addingTimeInterval(90))
        XCTAssertTrue(waitingLong.isError)
    }
}
