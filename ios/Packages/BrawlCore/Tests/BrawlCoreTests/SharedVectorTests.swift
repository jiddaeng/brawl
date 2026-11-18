import XCTest
@testable import BrawlCore

/// tests/app-fixtures/recognition-cases.json: Android core 테스트와 같은 입력·기대값
final class SharedVectorTests: XCTestCase {
    struct Line: Decodable { var text: String; var confidence: Double; var x: Double; var y: Double }
    struct Pick: Decodable { var brawler: String; var side: String }
    struct Expect: Decodable { var map: Int?; var mode: String?; var ambiguousModes: [String]?; var picks: [Pick]? }
    struct MatcherCase: Decodable { var name: String; var lines: [Line]; var expect: Expect }
    struct Config: Decodable { var requiredAgreement: Int; var agreementWindow: Double; var failAfter: Double }
    struct Step: Decodable { var t: Double; var lines: [Line]; var expect: String }
    struct StabilizerCase: Decodable { var name: String; var config: Config; var steps: [Step] }
    struct File: Decodable { var matcher: [MatcherCase]; var stabilizer: [StabilizerCase] }

    let file = try! JSONDecoder().decode(File.self, from: Fixtures.data("recognition-cases.json"))
    let matcher = GameScreenMatcher(catalog: Fixtures.catalog)
    func ocr(_ l: [Line]) -> [OCRLine] { l.map { OCRLine(text: $0.text, confidence: $0.confidence, midX: $0.x, midY: $0.y) } }

    func testMatcherVectors() {
        XCTAssertFalse(file.matcher.isEmpty)
        for c in file.matcher {
            let r = matcher.analyze(ocr(c.lines))
            if c.expect.map != nil || c.expect.ambiguousModes != nil {
                XCTAssertEqual(r.map?.id, c.expect.map.map { .number($0) }, c.name)
            }
            if let m = c.expect.mode { XCTAssertEqual(r.mode, m, c.name) }
            if let a = c.expect.ambiguousModes { XCTAssertEqual(r.ambiguousMaps.map(\.mode).sorted(), a.sorted(), c.name) }
            if let picks = c.expect.picks {
                let got = r.picks.map { p in (Fixtures.catalog.brawlers.first { $0.id == p.brawlerID }!.name, p.side.rawValue) }.sorted { $0.0 < $1.0 }
                XCTAssertEqual(got.map { "\($0.0):\($0.1)" }, picks.map { "\($0.brawler):\($0.side)" }.sorted(), c.name)
            }
        }
    }

    func testStabilizerVectors() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        for c in file.stabilizer {
            var s = RecognitionStabilizer(requiredAgreement: c.config.requiredAgreement, agreementWindow: c.config.agreementWindow, failAfter: c.config.failAfter)
            s.start(at: t0)
            for st in c.steps {
                let e = s.feed(matcher.analyze(ocr(st.lines)), at: t0.addingTimeInterval(st.t))
                let got: String
                switch e {
                case .none: got = "none"
                case .recognized(let m, _): got = "recognized:\(m.id)"
                case .failed: got = "failed"
                case .modeAmbiguous(let maps): got = "ambiguous:\(maps.count)"
                }
                XCTAssertEqual(got, st.expect, "\(c.name) t=\(st.t)")
            }
        }
    }
}
