import XCTest
@testable import BrawlCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class ModelTests: XCTestCase {
    func testRecommendationComesFromEngineResult() {
        let r = Fixtures.result("result-bounty")
        let rec = Recommendation(result: r)!
        XCTAssertEqual(rec.brawlers.count, 3)
        XCTAssertEqual(rec.mapName, "기습적 움직임")
        XCTAssertEqual(rec.gameMode, "바운티")
        XCTAssertEqual(rec.score, r.teams[0].score)
        XCTAssertEqual(rec.estimatedWinRate, r.teams[0].estimatedWinRate)
        XCTAssertEqual(rec.reasons.count, r.teams[0].reasons.count)
        XCTAssertEqual(rec.brawlers.map(\.ko), r.teams[0].members.map(\.ko))
        XCTAssertNotNil(Recommendation(result: r, rank: 2))
        XCTAssertNil(Recommendation(result: r, rank: 99))
    }

    func testTeamSizeFollowsEngine() {
        XCTAssertEqual(Recommendation(result: Fixtures.result("result-5v5"))!.brawlers.count, 5)
        let solo = Recommendation(result: Fixtures.result("result-solo"))!
        XCTAssertEqual(solo.brawlers.count, 1)
        XCTAssertNil(solo.brawlers[0].pick)
    }

    func testContentKeyChangesOnlyWithVisibleContent() {
        let r = Fixtures.result("result-bounty")
        let a = Recommendation(result: r, at: Date(timeIntervalSince1970: 1))!, b = Recommendation(result: r, at: Date(timeIntervalSince1970: 99))!
        XCTAssertEqual(a.contentKey, b.contentKey)
        XCTAssertNotEqual(a.contentKey, Recommendation(result: r, rank: 2)!.contentKey)
    }

    func testHTMLEntities() {
        XCTAssertEqual(HTMLEntities.decode("래리 &amp; 로리 &lt;b&gt; &quot;x&quot;"), "래리 & 로리 <b> \"x\"")
        XCTAssertEqual(HTMLEntities.decode("&amp;lt;"), "&lt;", "한 번만 되돌림")
    }

    func testMapIDCodable() throws {
        let ids: [MapID] = [.number(15001395), .string("bt-gemGrab-x")]
        let d = try JSONEncoder().encode(ids)
        XCTAssertEqual(String(data: d, encoding: .utf8), "[15001395,\"bt-gemGrab-x\"]")
        XCTAssertEqual(try JSONDecoder().decode([MapID].self, from: d), ids)
        XCTAssertEqual(MapID.string("a\"b").jsonLiteral, "\"a\\\"b\"")
    }

    func testStatusHidesRecommendationUnlessReady() {
        for s in AnalysisStatus.allCases { XCTAssertEqual(s.hidesRecommendation, s != .ready, s.rawValue) }
    }
}

final class StoreTests: XCTestCase {
    func testSessionRoundTrip() throws {
        let store = tempStore()
        let rec = Recommendation(result: Fixtures.result("result-bounty"))!
        let s = AnalysisSession(status: .ready, startedAt: Date(timeIntervalSince1970: 10), recognition: GameRecognition(recognizedMap: rec.mapID, mapName: rec.mapName, recognizedMode: "Bounty", confidence: 0.9, timestamp: Date(timeIntervalSince1970: 20)), recommendation: rec)
        try store.write(s, .session)
        XCTAssertEqual(store.read(AnalysisSession.self, .session), s)
        XCTAssertNil(store.read(AnalysisSession.self, .catalog), "형식이 다르면 nil")
    }

    func testRecommendationFileByMap() throws {
        let store = tempStore()
        try store.writeData(Fixtures.data("result-bounty.json"), .recommendation(.number(15001395)))
        XCTAssertEqual(store.recommendation(for: .number(15001395))?.teams.first?.score, Fixtures.result("result-bounty").teams[0].score)
        XCTAssertNil(store.recommendation(for: .number(1)))
    }
}

/// 네트워크 대신 정해진 응답을 주는 fetcher
final class FakeFetcher: HTTPFetching, @unchecked Sendable {
    var responses: [String: Data] = [:]
    func data(from url: URL) async throws -> Data {
        if let d = responses[url.absoluteString] { return d }
        throw URLError(.notConnectedToInternet)
    }
}

final class DataSourceTests: XCTestCase {
    let maps = Data(#"{"list":[{"id":1,"name":"A","gameMode":{"name":"Gem Grab"}}]}"#.utf8)
    let brawlers = Data(#"{"list":[{"id":7,"name":"Shelly","class":{"name":"Damage Dealer"}}]}"#.utf8)
    let strength = Data(#"{"from":"a","until":"b","files":{"maps":{}}}"#.utf8)

    func testOnlineWritesCacheThenOfflineUsesIt() async throws {
        let store = tempStore(), f = FakeFetcher()
        f.responses = [Endpoints.brawlifyMaps.absoluteString: maps, Endpoints.brawlifyBrawlers.absoluteString: brawlers, Endpoints.brawlTimeStrength.absoluteString: strength]
        let online = try await DataSourceLoader(fetcher: f, store: store).load()
        XCTAssertNil(online.cachedAt)
        XCTAssertEqual(online.maps.first?.name, "A")
        XCTAssertEqual(online.strength, strength)

        f.responses = [:]
        let offline = try await DataSourceLoader(fetcher: f, store: store).load()
        XCTAssertNotNil(offline.cachedAt)
        XCTAssertEqual(offline.brawlers.first?.name, "Shelly")
        XCTAssertEqual(offline.strength, strength, "BrawlTime 저장본도 사용")
    }

    func testOneBrawlifyFailureUsesWholeCache() async throws {
        let store = tempStore(), f = FakeFetcher()
        f.responses = [Endpoints.brawlifyMaps.absoluteString: maps]   // 브롤러 목록 실패
        do { _ = try await DataSourceLoader(fetcher: f, store: store).load(); XCTFail("저장본 없으면 오류") }
        catch let e as DataSourceError { if case .offlineNoCache = e {} else { XCTFail() } }
    }

    func testStrengthFailureWithoutCacheIsNil() async throws {
        let store = tempStore(), f = FakeFetcher()
        f.responses = [Endpoints.brawlifyMaps.absoluteString: maps, Endpoints.brawlifyBrawlers.absoluteString: brawlers, Endpoints.brawlTimeStrength.absoluteString: Data("not json".utf8)]
        let r = try await DataSourceLoader(fetcher: f, store: store).load()
        XCTAssertNil(r.strength)
        XCTAssertNil(r.cachedAt)
    }
}
