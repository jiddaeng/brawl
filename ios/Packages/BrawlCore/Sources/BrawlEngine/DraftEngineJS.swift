#if canImport(JavaScriptCore)
import Foundation
import JavaScriptCore
import BrawlCore

public enum EngineError: Error, LocalizedError {
    case contextUnavailable
    case scriptMissing(String)
    case javaScript(String, String)
    case badResult(String)

    public var errorDescription: String? {
        switch self {
        case .contextUnavailable: return "JavaScript 엔진을 만들 수 없습니다."
        case .scriptMissing(let p): return "추천 엔진 파일을 찾을 수 없습니다: \(p)"
        case .javaScript(let w, let e): return "추천 엔진 오류 (\(w)): \(e)"
        case .badResult(let w): return "추천 엔진 결과를 읽을 수 없습니다 (\(w))"
        }
    }
}

/// engine/draft-engine.js 를 JavaScriptCore 로 실행한다. 계산은 모두 JS 쪽(웹과 같은 코드)에서 한다.
/// 스레드 안전하지 않으므로 한 번에 한 곳(RecommendationEngine actor)에서만 쓴다.
public final class DraftEngineJS {
    private let context: JSContext
    private var lastException: String?

    public convenience init(scriptURL: URL) throws {
        guard let s = try? String(contentsOf: scriptURL, encoding: .utf8) else { throw EngineError.scriptMissing(scriptURL.path) }
        try self.init(script: s, sourceURL: scriptURL)
    }

    public init(script: String, sourceURL: URL? = nil) throws {
        // SDK 버전에 따라 non-optional / IUO 로 들어오므로 Optional 로 받아 확인한다
        let made: JSContext? = JSContext(virtualMachine: JSVirtualMachine())
        guard let ctx = made else { throw EngineError.contextUnavailable }
        context = ctx
        ctx.name = "DraftEngine"
        ctx.exceptionHandler = { [weak self] _, exc in self?.lastException = exc?.toString() ?? "unknown" }
        ctx.evaluateScript(script, withSourceURL: sourceURL)
        try check("엔진 스크립트 로딩")
        // 인자·결과를 JSON 문자열로 주고받는 얇은 호스트 함수 (숫자를 Swift 에서 다시 쓰지 않도록 원문 그대로 전달)
        ctx.evaluateScript("""
        var __host = {
          call: function (name, argsJSON) { return JSON.stringify(DraftEngine[name].apply(DraftEngine, JSON.parse(argsJSON))); },
          analyze: function (bytes, w, h) { return JSON.stringify(DraftEngine.analyzePixels(bytes, w, h)); },
          recommend: function (mapIdJSON, featJSON, optJSON) {
            var opt = JSON.parse(optJSON);
            return JSON.stringify(DraftEngine.recommend(JSON.parse(mapIdJSON), JSON.parse(featJSON), opt));
          }
        };
        """)
        try check("호스트 함수")
        guard ctx.objectForKeyedSubscript("DraftEngine")?.isObject == true else { throw EngineError.javaScript("로딩", "DraftEngine 이 없습니다") }
    }

    private func check(_ what: String) throws {
        if let e = lastException { lastException = nil; throw EngineError.javaScript(what, e) }
    }

    private func invoke(_ method: String, _ args: [Any], _ what: String) throws -> String {
        guard let host = context.objectForKeyedSubscript("__host") else { throw EngineError.contextUnavailable }
        let r = host.invokeMethod(method, withArguments: args)
        try check(what)
        guard let r, r.isString, let s = r.toString() else { throw EngineError.badResult(what) }
        return s
    }

    public var version: Int { Int(context.evaluateScript("DraftEngine.version")?.toInt32() ?? 0) }

    /// Brawlify 목록 + BrawlTime 맵 풀로 엔진 데이터 구성 (웹 buildData). 반환: 현재 맵 풀·브롤러 목록
    public func load(maps: [SlimMap], brawlers: [SlimBrawler], strength: Data?) throws -> (EngineCatalog, json: String) {
        let enc = JSONEncoder()
        let m = String(decoding: try enc.encode(maps), as: UTF8.self)
        let b = String(decoding: try enc.encode(brawlers), as: UTF8.self)
        let s = strength.map { String(decoding: $0, as: UTF8.self) } ?? "null"
        let json = try invoke("call", ["load", "[\(m),\(b),\(s)]"], "load")
        return (try JSONDecoder().decode(EngineCatalog.self, from: Data(json.utf8)), json)
    }

    /// BrawlTime 맵별 통계 원본 → 엔진용 승률 효과 JSON (해석 실패 시 nil, 웹과 같음)
    public func parseStats(_ raw: Data) throws -> String? {
        let json = try invoke("call", ["parseStats", "[\(String(decoding: raw, as: UTF8.self))]"], "parseStats")
        return json == "null" ? nil : json
    }

    /// 모드 기본 맵 특성 (이미지 분석 실패 시 웹과 같이 사용)
    public func fallbackFeat(mode: String) throws -> String {
        let arg = String(decoding: try JSONEncoder().encode([mode]), as: UTF8.self)
        return try invoke("call", ["fallbackFeat", arg], "fallbackFeat")
    }

    /// RGBA 픽셀 → 맵 특성 JSON. 픽셀 버퍼를 복사하지 않고 Uint8ClampedArray 로 넘긴다
    public func analyzePixels(_ rgba: inout [UInt8], width: Int, height: Int) throws -> String {
        try rgba.withUnsafeMutableBytes { buf -> String in
            var exc: JSValueRef?
            guard let base = buf.baseAddress,
                  let obj = JSObjectMakeTypedArrayWithBytesNoCopy(context.jsGlobalContextRef, kJSTypedArrayTypeUint8ClampedArray, base, buf.count, nil, nil, &exc),
                  exc == nil, let arr = JSValue(jsValueRef: obj, in: context)
            else { throw EngineError.javaScript("analyzePixels", "typed array 생성 실패") }
            return try invoke("analyze", [arr, width, height], "analyzePixels")
        }
    }

    /// 추천 계산 (웹 runEngine + renderResult 와 같은 함수 호출)
    /// - featJSON / statsJSON: 이 엔진이 돌려준 JSON 원문
    /// - owned: 보유 브롤러 id (우리 팀 후보만 이 안에서). nil 이면 전체 (웹과 같음)
    public func recommend(mapID: MapID, featJSON: String, statsJSON: String?, lock: [Int] = [], enemy: [Int] = [], ban: [Int] = [], owned: [Int]? = nil) throws -> (EngineResult, json: String) {
        let ids = { (a: [Int]) in "[" + a.map(String.init).joined(separator: ",") + "]" }
        let ownedJSON = owned.map(ids) ?? "null"
        let opt = "{\"stats\":\(statsJSON ?? "null"),\"lock\":\(ids(lock)),\"enemy\":\(ids(enemy)),\"ban\":\(ids(ban)),\"owned\":\(ownedJSON)}"
        let json = try invoke("recommend", [mapID.jsonLiteral, featJSON, opt], "recommend")
        do { return (try JSONDecoder().decode(EngineResult.self, from: Data(json.utf8)), json) }
        catch { throw EngineError.badResult("recommend: \(error)") }
    }

    /// 테스트 전용: 임의 스크립트를 실행하고 문자열 결과를 돌려준다
    func evaluateForTesting(_ script: String) throws -> String? {
        let r = context.evaluateScript(script)
        try check("test")
        return r?.isUndefined == true ? nil : r?.toString()
    }
}
#endif
