import Foundation

/// OCR 결과 줄을 맵·모드·브롤러 이름 사전과 맞춰 보는 매처.
/// 한국어(공식 명칭)와 영어 이름을 모두 사전에 넣고, 띄어쓰기·문장부호·대소문자를 무시하고 비교한다.
public enum TextNormalizer {
    /// 영문 소문자·숫자·한글만 남긴다
    public static func normalize(_ s: String) -> [Character] {
        var out: [Character] = []
        for ch in s.lowercased() {
            guard let u = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else {
                // 합성 문자(자모 조합 등)는 NFC 로 합쳐진 경우만 들어온다
                if ch.isLetter || ch.isNumber { out.append(ch) }
                continue
            }
            let v = u.value
            let isLatin = (0x61...0x7A).contains(v) || (0x30...0x39).contains(v)
            let isHangul = (0xAC00...0xD7A3).contains(v)
            if isLatin || isHangul { out.append(ch) }
        }
        return out
    }

    /// 레벤슈타인 거리
    public static func distance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count), cur = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    /// 0...1 유사도. 줄이 이름보다 길면 이름 길이 근처의 구간들과 비교해 가장 높은 값을 쓴다
    /// (예: "젬 그랩 · 작별 인사" 줄에서 "작별인사" 찾기)
    public static func similarity(line: [Character], name: [Character]) -> Double {
        guard !line.isEmpty, !name.isEmpty else { return 0 }
        func sim(_ x: ArraySlice<Character>) -> Double {
            let a = Array(x)
            return 1 - Double(distance(a, name)) / Double(max(a.count, name.count))
        }
        var best = sim(line[...])
        if line.count > name.count + 1 {
            for len in max(1, name.count - 1)...(name.count + 1) where len <= line.count {
                for start in 0...(line.count - len) {
                    best = max(best, sim(line[start..<(start + len)]))
                    if best == 1 { return 1 }
                }
            }
        }
        return best
    }

    /// 이름 길이별 인정 기준. 짧은 이름일수록 엄격하게 (1~2글자는 정확히 같아야 함)
    public static func threshold(forLength n: Int) -> Double {
        switch n {
        case ...2: return 1.0
        case 3: return 1.0
        case 4...5: return 0.8
        default: return 0.78
        }
    }
}

public struct TextMatch<Value: Hashable>: Hashable {
    public var value: Value
    public var matchedText: String
    public var similarity: Double
}

/// 이름 사전. 한 값에 여러 이름(한국어·영어)을 붙일 수 있다
public struct NameDictionary<Value: Hashable> {
    struct Entry { var value: Value; var text: String; var key: [Character] }
    var entries: [Entry] = []

    public init() {}
    public mutating func add(_ value: Value, names: [String]) {
        var seen = Set<String>()
        for n in names where seen.insert(n).inserted {
            let k = TextNormalizer.normalize(n)
            if !k.isEmpty { entries.append(Entry(value: value, text: n, key: k)) }
        }
    }

    /// 한 줄에서 기준을 넘는 모든 후보 (값별 최고 유사도).
    /// 정렬: 유사도 내림차순, 같으면 사전에 먼저 넣은 순서 (실행마다 같은 결과, Android core 와 같은 규칙)
    public func matches(in line: String, minimumLength: Int = 1) -> [TextMatch<Value>] {
        let l = TextNormalizer.normalize(line)
        guard !l.isEmpty else { return [] }
        var best: [Value: TextMatch<Value>] = [:]
        var firstSeen: [Value: Int] = [:]
        for (order, e) in entries.enumerated() where e.key.count >= minimumLength {
            // 길이 차이가 크면 계산하지 않는다 (줄이 훨씬 짧으면 불가능)
            if l.count * 10 < e.key.count * 7 { continue }
            let s: Double
            if e.key.count <= 3 {
                // 짧은 이름은 줄 전체가 그 이름일 때만 인정 (부분 일치 오탐 방지)
                s = l == e.key ? 1 : 0
            } else {
                s = TextNormalizer.similarity(line: l, name: e.key)
            }
            guard s >= TextNormalizer.threshold(forLength: e.key.count) else { continue }
            if firstSeen[e.value] == nil { firstSeen[e.value] = order }
            if (best[e.value]?.similarity ?? -1) < s { best[e.value] = TextMatch(value: e.value, matchedText: e.text, similarity: s) }
        }
        return best.values.sorted { a, b in
            a.similarity != b.similarity ? a.similarity > b.similarity : firstSeen[a.value]! < firstSeen[b.value]!
        }
    }
}

/// OCR 로 읽힌 글자 한 줄 (Vision 결과를 플랫폼과 무관하게 옮긴 것)
public struct OCRLine: Hashable, Sendable {
    public var text: String
    public var confidence: Double
    /// 화면 기준 정규화 좌표 (0...1, 왼쪽 위 원점)
    public var midX: Double
    public var midY: Double
    public init(text: String, confidence: Double, midX: Double, midY: Double) {
        self.text = text; self.confidence = confidence; self.midX = midX; self.midY = midY
    }
}

/// 한 프레임의 OCR 결과에서 맵·모드·브롤러를 찾는다
public struct GameScreenMatcher {
    public struct FrameResult: Hashable {
        /// 확정된 맵 (같은 이름이 여러 모드에 있으면 모드까지 맞아야 확정)
        public var map: CatalogMap?
        /// 맵 이름은 읽혔지만 모드를 정하지 못한 후보들
        public var ambiguousMaps: [CatalogMap]
        public var mode: String?
        public var mapConfidence: Double
        public var picks: [PickedBrawler]
    }

    let maps: [CatalogMap]
    var mapDict = NameDictionary<Int>()       // 값 = maps 인덱스
    var modeDict = NameDictionary<String>()   // 값 = 영문 모드 이름
    var brawlerDict = NameDictionary<Int>()   // 값 = 브롤러 id

    public init(catalog: EngineCatalog) {
        maps = catalog.maps
        for (i, m) in maps.enumerated() { mapDict.add(i, names: [m.name, m.ko]) }
        var modes: [String: Set<String>] = [:]
        for m in maps { modes[m.mode, default: []].formUnion([m.mode, m.modeKo]) }
        // 모드 순서: 카탈로그에 처음 나온 순서, 이름 순서: 영문 → 한국어
        var order: [String] = []
        for m in maps where !order.contains(m.mode) { order.append(m.mode) }
        for k in order { modeDict.add(k, names: [k] + (modes[k] ?? []).filter { $0 != k }.sorted()) }
        for b in catalog.brawlers { brawlerDict.add(b.id, names: [b.name, b.ko]) }
    }

    public func analyze(_ lines: [OCRLine], minimumLineConfidence: Double = 0.3) -> FrameResult {
        let usable = lines.filter { $0.confidence >= minimumLineConfidence }
        // 모드: 가장 높은 유사도
        var modeHit: TextMatch<String>?
        for l in usable { if let m = modeDict.matches(in: l.text, minimumLength: 2).first, m.similarity > (modeHit?.similarity ?? 0) { modeHit = m } }
        // 맵: 줄마다 후보를 모아 같은 이름끼리 묶는다
        var hits: [(idx: Int, sim: Double)] = []
        for l in usable {
            for m in mapDict.matches(in: l.text, minimumLength: 3) { hits.append((m.value, m.similarity * l.confidence.clamped(0.5, 1))) }
        }
        var result = FrameResult(map: nil, ambiguousMaps: [], mode: modeHit?.value, mapConfidence: 0, picks: [])
        if let top = hits.max(by: { $0.sim < $1.sim }) {
            let topName = TextNormalizer.normalize(maps[top.idx].name)
            // 최고 점수와 거의 같은 후보 중 같은 맵 이름(모드만 다른 맵)을 모은다
            let sameName = Set(hits.filter { TextNormalizer.normalize(maps[$0.idx].name) == topName }.map { $0.idx }).sorted().map { maps[$0] }
            let rivals = Set(hits.filter { $0.sim >= top.sim - 0.05 && TextNormalizer.normalize(maps[$0.idx].name) != topName }.map { $0.idx }).sorted()
            if rivals.isEmpty {
                if sameName.count == 1 {
                    result.map = sameName[0]
                } else if let mode = modeHit?.value, let m = sameName.first(where: { $0.mode == mode }) {
                    result.map = m
                } else {
                    result.ambiguousMaps = sameName.sorted { $0.mode < $1.mode }
                }
                result.mapConfidence = top.sim
            } else {
                // 서로 다른 맵 이름이 비슷한 점수로 읽힘 → 확정하지 않는다
                result.ambiguousMaps = ([top.idx] + rivals).map { maps[$0] }
                result.mapConfidence = top.sim
            }
            if let m = result.map, result.mode == nil { result.mode = m.mode }
        }
        // 브롤러(실험): 이름이 정확히 읽힌 줄만, 화면 왼쪽 = 우리 팀 / 오른쪽 = 상대 팀으로 추정
        var picks: [Int: PickedBrawler] = [:]
        for l in usable where l.confidence >= 0.5 {
            guard let b = brawlerDict.matches(in: l.text, minimumLength: 1).first, b.similarity >= 0.9 else { continue }
            let side: PickedBrawler.Side = l.midX < 0.4 ? .ally : (l.midX > 0.6 ? .enemy : .unknown)
            let p = PickedBrawler(brawlerID: b.value, side: side, confidence: b.similarity * l.confidence)
            if (picks[b.value]?.confidence ?? 0) < p.confidence { picks[b.value] = p }
        }
        result.picks = picks.values.sorted { $0.brawlerID < $1.brawlerID }
        return result
    }
}

extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(hi, Swift.max(lo, self)) }
}
