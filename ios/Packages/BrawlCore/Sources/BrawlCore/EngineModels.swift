import Foundation

// engine/draft-engine.js 의 DraftEngine API 가 돌려주는 JSON 과 같은 모양의 모델.
// 필드명은 JS 쪽 이름을 그대로 쓴다. 엔진이 주지 않는 값은 만들지 않는다.

/// 맵 id. Brawlify 맵은 숫자, BrawlTime 에만 있는 맵은 "bt-모드-슬러그" 문자열이다 (웹 buildData 와 같음).
public enum MapID: Hashable, Codable, CustomStringConvertible, Sendable {
    case number(Int)
    case string(String)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Int.self) { self = .number(n) } else { self = .string(try c.decode(String.self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .number(let n): try c.encode(n); case .string(let s): try c.encode(s) }
    }
    public var description: String { switch self { case .number(let n): return String(n); case .string(let s): return s } }
    /// 파일 이름 등에 쓰는 안전한 키
    public var fileKey: String { description.replacingOccurrences(of: "/", with: "_") }
    /// JS 로 넘길 때의 리터럴 (JSON)
    public var jsonLiteral: String {
        switch self {
        case .number(let n): return String(n)
        case .string(let s): return String(data: try! JSONEncoder().encode(s), encoding: .utf8)!
        }
    }
}

public struct BrawlTimeRef: Codable, Hashable, Sendable {
    public var mode: String
    public var slug: String
    public var statsPath: String { "\(mode)/\(slug)" }
}

/// DraftEngine.catalog() — 현재 맵 풀(웹의 inPool)과 브롤러 목록
public struct EngineCatalog: Codable, Sendable {
    public var window: String?
    public var hasLive: Bool
    public var maps: [CatalogMap]
    public var brawlers: [CatalogBrawler]
}

public struct CatalogMap: Codable, Hashable, Sendable, Identifiable {
    public var id: MapID
    public var name: String
    public var ko: String
    public var mode: String
    public var modeKo: String
    public var ranked: Bool
    public var size: Int
    public var live: Bool
    public var isNew: Bool
    public var bt: BrawlTimeRef?
    /// 맵 이미지 후보 URL (웹 mapImgs 와 같은 순서: BrawlTime → Brawlify)
    public var images: [String]
}

public struct CatalogBrawler: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var ko: String
    public var img: String?
    /// 희귀도 색 (Brawlify, 예: "#b9eaff"). 웹 브롤러 카드 테두리·배경색
    public var rarity: String?
    public var position: String
    public var estimatedProfile: Bool
}

/// 맵 이미지 분석 결과 (웹 analyzeImage / fallbackFeat 의 스칼라 값). tiles 는 엔진 계산에 쓰이지 않아 넘기지 않는다.
public struct MapFeatures: Codable, Hashable, Sendable {
    public var ok: Bool
    public var cols: Int?
    public var rows: Int?
    public var TX: Double?
    public var TY: Double?
    public var cover: Double
    public var bush: Double
    public var wall: Double
    public var open: Double
    public var sight: Double
    public var midOpen: Double
    public var laneSplit: Double
}

/// DraftEngine.recommend() 결과
public struct EngineResult: Codable, Sendable {
    public var engineVersion: Int
    public var map: ResultMap
    public var feat: MapFeatures
    public var demands: [String: Double]
    public var stats: StatsInfo?
    public var count: Int
    /// 웹과 같은 표시 문자열 (예: "3,276")
    public var countText: String
    public var poolSize: Int
    public var teams: [TeamResult]
}

public struct ResultMap: Codable, Hashable, Sendable {
    public var id: MapID
    public var name: String
    public var ko: String
    public var mode: String
    public var modeKo: String
    public var kind: String
    public var size: Int
    public var live: Bool
}

public struct StatsInfo: Codable, Hashable, Sendable {
    public var preset: String
    public var battles: Int
    public var from: String
    public var until: String
}

public struct TeamResult: Codable, Sendable {
    public var rank: Int
    /// 엔진 내부 팀 순서의 브롤러 id (웹 대안 조합 줄의 순서)
    public var ids: [Int]
    public var score: Int
    /// 웹과 같은 소수 첫째 자리 문자열 (예: "57.5")
    public var estimatedWinRate: String
    public var archetype: String
    /// teamEval 의 평가 항목 원값
    public var f: [String: Double?]
    /// 카운터 내성 % (웹 결과 카드 값)
    public var counterPercent: Int
    /// 웹 대안 조합 줄의 요약 문구 (예: "밸런스 표준 · 맵 100 · 밸런스 100 · 내성 69")
    public var summary: String
    /// 역할 순서로 정렬된 멤버 (웹 결과 카드 순서)
    public var members: [TeamMember]
    public var factors: [Factor]
    /// 추천 근거. 웹 화면용으로 HTML 이스케이프된 문자열 → `plainReasons` 사용
    public var reasons: [String]
    public var threats: [TeamMember]

    public var plainReasons: [String] { reasons.map(HTMLEntities.decode) }
}

public struct TeamMember: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var ko: String
    public var img: String?
    /// 희귀도 색 (웹 브롤러 카드와 같은 테두리·배경색)
    public var rarity: String?
    public var position: String
    public var positionKo: String
    public var estimatedProfile: Bool
    /// BrawlTime 승률 효과 (예: 0.06 = +6.0%p). 통계가 없으면 nil
    public var eff: Double?
    /// 웹과 같은 표시 문자열 (예: "+6.0"). 화면에는 이 값 + "%p" 를 쓴다 (Swift 에서 다시 반올림하지 않는다)
    public var effPct: String?
    public var role: String?
    /// 드래프트 픽 순서 (1부터). 솔로 모드는 nil
    public var pick: Int?
}

public struct Factor: Codable, Hashable, Sendable {
    public var key: String
    public var label: String
    public var value: Double?
    /// 웹 막대에 표시되는 % (Math.round(value×100))
    public var percent: Int?
}

public enum HTMLEntities {
    /// 웹 esc() 가 바꾼 문자만 되돌린다 (& < > ")
    public static func decode(_ s: String) -> String {
        s.replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
