import XCTest
@testable import BrawlCore

/// 공식 API(서버 중계) 응답 해석, 지금 열린 맵 목록, 최근 경기 맵, 보유 브롤러 필터
final class GameDataTests: XCTestCase {
    let player = try! JSONDecoder().decode(PlayerResponse.self, from: Fixtures.data("player.json")).player
    let rotation = try! JSONDecoder().decode(RotationResponse.self, from: Fixtures.data("rotation.json")).rotation
    let now = GameDataDates.parse("2026-11-19T02:30:00.000Z")!

    func testTagNormalize() {
        XCTAssertEqual(PlayerTag.normalize("2pp"), "#2PP")
        XCTAssertEqual(PlayerTag.normalize(" #y0lq "), "#Y0LQ")
        XCTAssertEqual(PlayerTag.normalize("#yolq"), "#Y0LQ")
        XCTAssertNil(PlayerTag.normalize("#A1"))
        XCTAssertNil(PlayerTag.normalize(""))
        XCTAssertNil(PlayerTag.normalize("../x"))
    }

    func testDecodeServerFixtures() {
        XCTAssertEqual(player.tag, "#2PP")
        XCTAssertEqual(player.brawlers.count, 81)
        XCTAssertEqual(player.recent.first?.mapId, 15001395)
        XCTAssertNotNil(player.recent.first?.date)
        XCTAssertEqual(rotation.count, 9)
        XCTAssertNotNil(rotation.first?.endDate)
    }

    func testCurrentMapsFollowSlotOrderAndSkipDuplicatesAndEnded() {
        let list = QuickMaps.current(rotation: rotation, catalog: Fixtures.catalog, now: now)
        XCTAssertEqual(list.first?.id, .number(15001395))
        XCTAssertEqual(list.count, Set(list.map(\.id)).count)
        // 같은 맵이 두 슬롯(솔로·듀오 쇼다운)에 있으면 모드가 달라도 맵 id 가 같아 한 번만
        XCTAssertLessThanOrEqual(list.count, rotation.count)
        let later = GameDataDates.parse("2026-11-20T00:00:01.000Z")!
        XCTAssertTrue(QuickMaps.current(rotation: rotation, catalog: Fixtures.catalog, now: later).isEmpty)
    }

    func testCycleListFallsBackToRankedMaps() {
        let empty = QuickMaps.cycleList(rotation: [], catalog: Fixtures.catalog, now: now)
        XCTAssertFalse(empty.isEmpty)
        XCTAssertTrue(empty.allSatisfy(\.ranked))
    }

    func testStepWrapsAround() {
        let list = QuickMaps.current(rotation: rotation, catalog: Fixtures.catalog, now: now)
        XCTAssertEqual(QuickMaps.step(from: list[0].id, in: list, by: 1)?.id, list[1].id)
        XCTAssertEqual(QuickMaps.step(from: list[0].id, in: list, by: -1)?.id, list.last?.id)
        XCTAssertEqual(QuickMaps.step(from: list.last!.id, in: list, by: 1)?.id, list[0].id)
        XCTAssertEqual(QuickMaps.step(from: nil, in: list, by: 1)?.id, list[0].id)
        XCTAssertNil(QuickMaps.step(from: nil, in: [], by: 1))
    }

    func testRecentMapOnlyWhenFreshAndOpen() {
        let list = QuickMaps.current(rotation: rotation, catalog: Fixtures.catalog, now: now)
        XCTAssertEqual(QuickMaps.recentMap(player: player, in: list, now: now)?.map.id, .number(15001395))
        let tooLate = now.addingTimeInterval(3600)
        XCTAssertNil(QuickMaps.recentMap(player: player, in: list, now: tooLate))
        XCTAssertNil(QuickMaps.recentMap(player: player, in: list.filter { $0.id != .number(15001395) }, now: now))
        XCTAssertNil(QuickMaps.recentMap(player: nil, in: list, now: now))
    }

    func testOwnedFilter() {
        XCTAssertNil(OwnedFilter.ids(nil, minPower: 1))
        let all = OwnedFilter.ids(player, minPower: 1)!
        XCTAssertEqual(all.count, 81)
        let strong = OwnedFilter.ids(player, minPower: 10)!
        XCTAssertTrue(strong.count < all.count && !strong.isEmpty)
        XCTAssertTrue(Set(strong).isSubset(of: Set(all)))
    }

    func testSnapshotRoundTripInStore() throws {
        let store = tempStore()
        let snap = GameDataSnapshot(tag: "#2PP", player: player, playerFetchedAt: now, rotation: rotation, rotationFetchedAt: now)
        try store.write(snap, .gameData)
        XCTAssertEqual(store.read(GameDataSnapshot.self, .gameData), snap)
    }
}
