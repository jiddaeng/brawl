#if canImport(JavaScriptCore) && canImport(CoreGraphics)
import XCTest
import Foundation
@testable import BrawlEngine
import BrawlCore

/// 웹 결과 카드에서 뽑은 정답(tests/engine-regression/golden.json)과 iOS 엔진 브리지 결과를 비교한다.
/// macOS: `swift test` (iOS 와 같이 JIT 없이 돌리려면 `JSC_useJIT=false swift test`)
/// iOS 시뮬레이터·기기: Xcode 에서 BrawlEngineTests 실행
final class EngineParityTests: XCTestCase {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let regression = repo.appendingPathComponent("tests/engine-regression")
    static let fixtures = regression.appendingPathComponent("fixtures")

    func makeEngine() throws -> DraftEngineJS {
        let e = try DraftEngineJS(scriptURL: Self.repo.appendingPathComponent("engine/draft-engine.js"))
        let maps = try JSONDecoder().decode(ListOf<SlimMap>.self, from: Data(contentsOf: Self.fixtures.appendingPathComponent("maps.json"))).list
        let brs = try JSONDecoder().decode(ListOf<SlimBrawler>.self, from: Data(contentsOf: Self.fixtures.appendingPathComponent("brawlers.json"))).list
        _ = try e.load(maps: maps, brawlers: brs, strength: try Data(contentsOf: Self.fixtures.appendingPathComponent("strength.json")))
        return e
    }
    struct ListOf<T: Decodable>: Decodable { var list: [T] }

    /// golden 시나리오 전부: 1위 조합과 대안 조합을 메인으로 올린 화면까지 웹과 같아야 한다
    func testRecommendationsMatchWebGolden() throws {
        let engine = try makeEngine()
        let goldenText = try String(contentsOf: Self.regression.appendingPathComponent("golden.json"), encoding: .utf8)
        let golden = try JSONSerialization.jsonObject(with: Data(goldenText.utf8)) as! [String: Any]
        let cases = golden["cases"] as! [[String: Any]]
        // 맵 특성은 Swift 에서 다시 쓰지 않고 JS 원문으로 넘긴다 (실제 앱과 같은 경로)
        _ = try engine.evaluateForTesting("var __golden = \(goldenText); 0")
        var statsCache: [String: String?] = [:]
        var mismatches = 0, teams = 0
        var results: [Any] = []
        for (i, c) in cases.enumerated() {
            let featJSON = try engine.evaluateForTesting("JSON.stringify(__golden.cases[\(i)].feat)")!
            var stats: String?
            if let path = c["stats"] as? String {
                if let s = statsCache[path] { stats = s } else {
                    stats = try engine.parseStats(Data(contentsOf: Self.fixtures.appendingPathComponent("stats/" + path.replacingOccurrences(of: "/", with: "__") + ".json")))
                    statsCache[path] = stats
                }
            }
            let sc = c["scenario"] as! [String: Any]
            let id: MapID = (c["map"] as? Int).map { .number($0) } ?? .string(c["map"] as! String)
            let (r, json) = try engine.recommend(mapID: id, featJSON: featJSON, statsJSON: stats, lock: sc["lock"] as! [Int], enemy: sc["enemy"] as! [Int], ban: sc["ban"] as! [Int])
            results.append(try JSONSerialization.jsonObject(with: Data(json.utf8)))
            let expected = c["expected"] as! [[String: Any]]
            XCTAssertEqual(r.teams.count, expected.count, "map \(id) \(sc["name"]!)")
            for k in 0..<min(r.teams.count, expected.count) {
                teams += 1
                let got = WebView.view(r, k)
                if !NSDictionary(dictionary: got).isEqual(to: expected[k]) {
                    mismatches += 1
                    XCTFail("map \(id) \(sc["name"]!) #\(k + 1)\n web: \(expected[k])\n ios: \(got)")
                }
            }
        }
        // compare.cjs --results 로도 확인할 수 있게 저장
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("brawl-engine-results.json")
        try JSONSerialization.data(withJSONObject: ["results": results]).write(to: out)
        print("엔진 일치: 조합 \(teams - mismatches)/\(teams), 결과 파일 \(out.path)")
    }

    /// 맵 PNG 를 iOS 방식(PixelDecoder)으로 풀어 분석한 값이 브라우저 canvas 결과와 같아야 한다
    func testMapImageAnalysisMatchesBrowser() throws {
        let engine = try makeEngine()
        let golden = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.regression.appendingPathComponent("golden.json"))) as! [String: Any]
        var browserFeat: [Int: [String: Any]] = [:]
        for c in golden["cases"] as! [[String: Any]] { if let id = c["map"] as? Int { browserFeat[id] = c["feat"] as? [String: Any] } }
        let dir = Self.fixtures.appendingPathComponent("maps")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".png") }
        XCTAssertFalse(files.isEmpty)
        for f in files {
            let id = Int(f.dropLast(4))!
            guard var px = PixelDecoder.decode(try Data(contentsOf: dir.appendingPathComponent(f))) else { XCTFail("decode \(f)"); continue }
            XCTAssertTrue(px.raw, "\(f): 원본 바이트로 읽지 못하고 그려서 얻음 (색 변환 가능성)")
            let json = try engine.analyzePixels(&px.bytes, width: px.width, height: px.height)
            let got = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
            let exp = try XCTUnwrap(browserFeat[id])
            for k in ["ok", "cols", "rows", "TX", "TY", "cover", "bush", "wall", "open", "sight", "midOpen", "laneSplit"] {
                XCTAssertEqual(got[k] as? NSNumber, exp[k] as? NSNumber, "\(f) \(k)")
            }
        }
    }

    func testInvalidStatsIsNilLikeWeb() throws {
        XCTAssertNil(try makeEngine().parseStats(Data(#"{"presets":{}}"#.utf8)))
    }
}

/// tests/engine-regression/compare.cjs 의 view() 와 같은 변환 (웹 결과 카드에 보이는 값)
enum WebView {
    /// JS Math.round (0.5 는 +∞ 방향)
    static func jsRound(_ x: Double) -> Int { Int(Foundation.floor(x + 0.5)) }
    static func grouped(_ n: Int) -> String {
        let s = String(n); var out = ""
        for (i, ch) in s.reversed().enumerated() { if i > 0 && i % 3 == 0 { out.append(",") }; out.append(ch) }
        return String(out.reversed())
    }
    static func eff(_ e: Double) -> String { "실전 \(e >= 0 ? "+" : "")\(String(format: "%.1f", e * 100))%p" }

    static func view(_ R: EngineResult, _ k: Int) -> [String: Any] {
        var L = R.teams; L.swapAt(0, k)
        let T = L[0]
        var koById: [Int: String] = [:]
        for t in R.teams { for m in t.members { koById[m.id] = m.ko } }
        let ordered = T.members.filter { $0.pick != nil }.sorted { $0.pick! < $1.pick! }
        let f = { (key: String) -> Double in (T.f[key] ?? nil) ?? 0 }
        return [
            "archetype": T.archetype,
            "members": T.members.map { m -> [String: Any] in ["name": m.name, "role": m.role ?? NSNull(), "pick": m.pick.map { "\($0)픽" } ?? NSNull(), "eff": m.eff.map(eff) ?? NSNull()] },
            "score": T.score,
            "kpi": ["\(T.estimatedWinRate)%", grouped(R.count), String(jsRound(f("counter") * 100))],
            "bars": T.factors.map { [$0.label, jsRound(($0.value ?? 0) * 100)] as [Any] },
            "reasons": T.plainReasons,
            "order": R.map.size > 1 ? ordered.enumerated().map { i, m in "\(i + 1)픽 \(m.ko) — \(i == 0 ? "카운터가 적어 블라인드 픽으로 안전" : i == ordered.count - 1 ? "카운터당하기 쉬워 마지막에 상대를 보고 확정" : "중간 픽, 상대 첫 픽에 맞춰 교체 가능")" } : [],
            "threats": T.threats.map(\.ko),
            "alts": L.dropFirst().map { o -> [String: Any] in
                let of = { (key: String) -> Double in (o.f[key] ?? nil) ?? 0 }
                return ["names": o.ids.map { koById[$0] ?? "" }.joined(separator: " · "),
                        "ar": "\(o.archetype) · 맵 \(jsRound(of("mapN") * 100)) · 밸런스 \(jsRound(of("balance") * 100)) · 내성 \(jsRound(of("counter") * 100))",
                        "score": o.score]
            },
        ]
    }
}
#endif
