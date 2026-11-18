import Foundation

/// 프레임 샘플링: 매 프레임을 분석하지 않는다.
/// - 최소 간격(minInterval) 안에는 분석하지 않는다
/// - 화면이 거의 안 바뀌었으면(서명 차이 < changeThreshold) 건너뛰되, maxInterval 이 지나면 한 번은 다시 본다
/// - 이전 분석이 끝나지 않았으면 건너뛴다
public struct FrameSampler: Sendable {
    public var minInterval: TimeInterval
    public var maxInterval: TimeInterval
    public var changeThreshold: Double
    public private(set) var lastAnalyzedAt: Date?
    public private(set) var lastSignature: [UInt8]?
    public private(set) var busy = false

    public init(minInterval: TimeInterval = 1.0, maxInterval: TimeInterval = 8, changeThreshold: Double = 4) {
        self.minInterval = minInterval; self.maxInterval = maxInterval; self.changeThreshold = changeThreshold
    }

    /// 서명: 작은 흑백 썸네일 (예: 16×9 밝기값)
    public static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return .infinity }
        var s = 0
        for i in 0..<a.count { s += abs(Int(a[i]) - Int(b[i])) }
        return Double(s) / Double(a.count)
    }

    /// 서명을 계산하기 전에 시간만으로 거를 수 있는지 (서명 계산 비용도 아끼기 위해)
    public func isDue(now: Date) -> Bool {
        guard !busy else { return false }
        guard let t = lastAnalyzedAt else { return true }
        return now.timeIntervalSince(t) >= minInterval
    }

    public mutating func shouldAnalyze(signature: [UInt8], now: Date) -> Bool {
        guard isDue(now: now) else { return false }
        if let t = lastAnalyzedAt, let last = lastSignature,
           FrameSampler.difference(last, signature) < changeThreshold,
           now.timeIntervalSince(t) < maxInterval { return false }
        lastAnalyzedAt = now
        lastSignature = signature
        busy = true
        return true
    }

    public mutating func finish() { busy = false }
}

/// 프레임별 인식 결과를 모아 안정된 인식만 내보낸다 (한 번 잘못 읽힌 글자로 추천이 바뀌지 않도록)
public struct RecognitionStabilizer: Sendable {
    public enum Event: Equatable, Sendable {
        case none
        case recognized(CatalogMap, confidence: Double)       // 새 맵이 확정됨
        case modeAmbiguous([CatalogMap])                      // 맵 이름은 계속 읽히지만 모드를 못 정함
        case failed                                           // 방송 시작 후 오랫동안 맵을 못 찾음
    }

    public var requiredAgreement: Int
    public var agreementWindow: TimeInterval
    public var failAfter: TimeInterval
    public private(set) var current: CatalogMap?
    public private(set) var currentConfidence: Double = 0
    public private(set) var lastSeen: Date?
    private var candidate: (map: CatalogMap, count: Int, first: Date, conf: Double)?
    private var ambiguousCount = 0
    private var startedAt: Date?
    private var failedReported = false

    public init(requiredAgreement: Int = 2, agreementWindow: TimeInterval = 10, failAfter: TimeInterval = 25) {
        self.requiredAgreement = requiredAgreement; self.agreementWindow = agreementWindow; self.failAfter = failAfter
    }

    public mutating func start(at date: Date) {
        startedAt = date; current = nil; candidate = nil; lastSeen = nil; failedReported = false; ambiguousCount = 0
    }

    public mutating func feed(_ r: GameScreenMatcher.FrameResult, at now: Date) -> Event {
        if startedAt == nil { startedAt = now }
        if let m = r.map {
            ambiguousCount = 0
            if m == current { lastSeen = now; candidate = nil; currentConfidence = max(currentConfidence * 0.8, r.mapConfidence); return .none }
            if let c = candidate, c.map == m, now.timeIntervalSince(c.first) <= agreementWindow {
                candidate = (m, c.count + 1, c.first, (c.conf * Double(c.count) + r.mapConfidence) / Double(c.count + 1))
            } else {
                candidate = (m, 1, now, r.mapConfidence)
            }
            if let c = candidate, c.count >= requiredAgreement {
                current = c.map; currentConfidence = c.conf; lastSeen = now; candidate = nil; failedReported = false
                return .recognized(c.map, confidence: c.conf)
            }
            return .none
        }
        if !r.ambiguousMaps.isEmpty {
            ambiguousCount += 1
            if ambiguousCount >= requiredAgreement && current == nil { return .modeAmbiguous(r.ambiguousMaps) }
            return .none
        }
        if current == nil, !failedReported, let s = startedAt, now.timeIntervalSince(s) >= failAfter {
            failedReported = true
            return .failed
        }
        return .none
    }
}

/// Live Activity 갱신 정책: 보이는 내용이 바뀌었을 때만, 그리고 너무 자주는 갱신하지 않는다
public struct ActivityUpdatePolicy: Sendable {
    public enum Decision: Equatable, Sendable { case skip, updateNow, deferUntil(Date) }
    public var minInterval: TimeInterval
    public private(set) var publishedKey: String?
    public private(set) var publishedAt: Date?

    public init(minInterval: TimeInterval = 5) { self.minInterval = minInterval }

    public func decide(key: String, now: Date) -> Decision {
        if key == publishedKey { return .skip }
        if let t = publishedAt, now.timeIntervalSince(t) < minInterval { return .deferUntil(t.addingTimeInterval(minInterval)) }
        return .updateNow
    }

    public mutating func markPublished(key: String, at: Date) { publishedKey = key; publishedAt = at }
    public mutating func reset() { publishedKey = nil; publishedAt = nil }
}
