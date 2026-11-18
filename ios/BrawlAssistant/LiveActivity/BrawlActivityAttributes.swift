import Foundation
import ActivityKit
import BrawlCore

/// Live Activity 정의 (앱·위젯·방송 확장 공용). 표시 값은 BrawlCore.ActivityDisplayState (세션에서 계산, 테스트됨)
struct BrawlActivityAttributes: ActivityAttributes {
    typealias ContentState = ActivityDisplayState
    var startedAt: Date
}
