import XCTest
@testable import BrawlCore

final class MatcherTests: XCTestCase {
    let matcher = GameScreenMatcher(catalog: Fixtures.catalog)

    func testNormalizeKeepsHangulLatinDigits() {
        XCTAssertEqual(String(TextNormalizer.normalize("기습적 움직임!")), "기습적움직임")
        XCTAssertEqual(String(TextNormalizer.normalize("Don't Leaf Me")), "dontleafme")
        XCTAssertEqual(String(TextNormalizer.normalize("Knockout 5v5")), "knockout5v5")
    }

    func testDistanceAndWindowSimilarity() {
        XCTAssertEqual(TextNormalizer.distance(Array("kitten"), Array("sitting")), 3)
        let s = TextNormalizer.similarity(line: TextNormalizer.normalize("바운티 · 기습적 움직임 ·  3:00"), name: TextNormalizer.normalize("기습적 움직임"))
        XCTAssertEqual(s, 1)
    }

    func testKoreanMapNameRecognized() {
        let r = matcher.analyze([line("기습적 움직임")])
        XCTAssertEqual(r.map?.id, .number(15001395))
        XCTAssertEqual(r.mode, "Bounty")
    }

    func testEnglishNameWithOCRNoise() {
        let r = matcher.analyze([line("SUDDEN MOVERNENTS")])
        XCTAssertEqual(r.map?.name, "Sudden Movements")
        XCTAssertGreaterThan(r.mapConfidence, 0.7)
    }

    func testMapInsideLongerLineWithMode() {
        let r = matcher.analyze([line("바운티"), line("기습적 움직임 - 랭크전")])
        XCTAssertEqual(r.map?.name, "Sudden Movements")
        XCTAssertEqual(r.mode, "Bounty")
    }

    func testSameMapNameInSeveralModesNeedsMode() {
        let noMode = matcher.analyze([line("바위 장벽 전투")])
        XCTAssertNil(noMode.map, "모드 없이 확정하면 안 됨")
        XCTAssertEqual(Set(noMode.ambiguousMaps.map(\.mode)), ["Solo Showdown", "Duo Showdown", "Trio Showdown"])
        let duo = matcher.analyze([line("듀오 쇼다운"), line("바위 장벽 전투")])
        XCTAssertEqual(duo.map?.mode, "Duo Showdown")
    }

    func testUnrelatedTextGivesNothing() {
        let r = matcher.analyze([line("플레이"), line("트로피 로드"), line("12:45"), line("친구 초대")])
        XCTAssertNil(r.map)
        XCTAssertTrue(r.ambiguousMaps.isEmpty)
    }

    func testLowConfidenceLinesIgnored() {
        XCTAssertNil(matcher.analyze([line("기습적 움직임", conf: 0.1)]).map)
    }

    func testShortBrawlerNamesOnlyExact() {
        let r = matcher.analyze([line("불", x: 0.2), line("보니", x: 0.8), line("보물 상자", x: 0.8)])
        let bull = Fixtures.brawler("Bull").id, bonnie = Fixtures.brawler("Bonnie").id, bo = Fixtures.brawler("Bo").id
        XCTAssertEqual(r.picks.first { $0.brawlerID == bull }?.side, .ally)
        XCTAssertEqual(r.picks.first { $0.brawlerID == bonnie }?.side, .enemy)
        XCTAssertNil(r.picks.first { $0.brawlerID == bo }, "'보물 상자' 를 '보' 로 읽으면 안 됨")
    }
}

final class PipelineTests: XCTestCase {
    let matcher = GameScreenMatcher(catalog: Fixtures.catalog)
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testStabilizerNeedsTwoAgreeingFrames() {
        var s = RecognitionStabilizer()
        s.start(at: t0)
        let a = matcher.analyze([line("기습적 움직임")])
        XCTAssertEqual(s.feed(a, at: t0.addingTimeInterval(1)), .none)
        guard case .recognized(let m, _) = s.feed(a, at: t0.addingTimeInterval(2.5)) else { return XCTFail() }
        XCTAssertEqual(m.name, "Sudden Movements")
        // 한 번 다른 맵으로 잘못 읽혀도 바뀌지 않음
        let other = matcher.analyze([line("작별 인사")])
        XCTAssertEqual(s.feed(other, at: t0.addingTimeInterval(4)), .none)
        XCTAssertEqual(s.current?.name, "Sudden Movements")
        XCTAssertEqual(s.feed(a, at: t0.addingTimeInterval(5)), .none)
        // 두 번 연속이면 바뀜
        _ = s.feed(other, at: t0.addingTimeInterval(6))
        guard case .recognized(let m2, _) = s.feed(other, at: t0.addingTimeInterval(7)) else { return XCTFail() }
        XCTAssertEqual(m2.name, "Don't Leaf Me")
    }

    func testStabilizerAgreementWindow() {
        var s = RecognitionStabilizer(agreementWindow: 10)
        s.start(at: t0)
        let a = matcher.analyze([line("기습적 움직임")])
        _ = s.feed(a, at: t0)
        XCTAssertEqual(s.feed(a, at: t0.addingTimeInterval(30)), .none, "너무 멀리 떨어진 두 프레임은 합치지 않음")
    }

    func testStabilizerReportsFailureAndAmbiguity() {
        var s = RecognitionStabilizer(failAfter: 25)
        s.start(at: t0)
        let empty = matcher.analyze([line("플레이")])
        XCTAssertEqual(s.feed(empty, at: t0.addingTimeInterval(10)), .none)
        XCTAssertEqual(s.feed(empty, at: t0.addingTimeInterval(26)), .failed)
        XCTAssertEqual(s.feed(empty, at: t0.addingTimeInterval(40)), .none, "실패는 한 번만 알림")
        let amb = matcher.analyze([line("바위 장벽 전투")])
        _ = s.feed(amb, at: t0.addingTimeInterval(41))
        guard case .modeAmbiguous(let maps) = s.feed(amb, at: t0.addingTimeInterval(42)) else { return XCTFail() }
        XCTAssertEqual(maps.count, 3)
    }

    func testFrameSampler() {
        var f = FrameSampler(minInterval: 1, maxInterval: 8, changeThreshold: 4)
        let a = [UInt8](repeating: 100, count: 144), b = [UInt8](repeating: 140, count: 144)
        XCTAssertTrue(f.shouldAnalyze(signature: a, now: t0))
        XCTAssertFalse(f.isDue(now: t0.addingTimeInterval(2)), "분석 중에는 건너뜀")
        f.finish()
        XCTAssertFalse(f.shouldAnalyze(signature: b, now: t0.addingTimeInterval(0.5)), "최소 간격")
        XCTAssertFalse(f.shouldAnalyze(signature: a, now: t0.addingTimeInterval(3)), "화면 변화 없음")
        XCTAssertTrue(f.shouldAnalyze(signature: b, now: t0.addingTimeInterval(3)), "화면 바뀜")
        f.finish()
        XCTAssertTrue(f.shouldAnalyze(signature: b, now: t0.addingTimeInterval(12)), "변화가 없어도 maxInterval 뒤에는 다시 봄")
    }

    func testActivityUpdatePolicy() {
        var p = ActivityUpdatePolicy(minInterval: 5)
        XCTAssertEqual(p.decide(key: "A", now: t0), .updateNow)
        p.markPublished(key: "A", at: t0)
        XCTAssertEqual(p.decide(key: "A", now: t0.addingTimeInterval(60)), .skip)
        XCTAssertEqual(p.decide(key: "B", now: t0.addingTimeInterval(2)), .deferUntil(t0.addingTimeInterval(5)))
        XCTAssertEqual(p.decide(key: "B", now: t0.addingTimeInterval(6)), .updateNow)
    }
}
