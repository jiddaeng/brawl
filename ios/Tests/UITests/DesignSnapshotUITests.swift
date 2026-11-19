import XCTest

/// 디자인 확인용 스크린샷: 메인 화면(위·아래), Dynamic Island(축소·펼침), 잠금 화면.
/// 데모 데이터(tests/app-fixtures/result-bounty.json)를 앱에 넣어 네트워크 없이 같은 화면을 만든다.
/// 결과: 테스트 첨부(xcresult) + 환경 변수 SNAPSHOT_DIR(xcodebuild 에는 TEST_RUNNER_SNAPSHOT_DIR 로 전달) 폴더의 PNG
final class DesignSnapshotUITests: XCTestCase {
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("tests/app-fixtures")
    static let fixture = fixtures.appendingPathComponent("result-bounty.json").path

    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let a = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        a.name = name; a.lifetime = .keepAlways
        add(a)
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }
    }

    func testCaptureScreens() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchEnvironment["BRAWL_DEMO_RESULT"] = Self.fixture
        app.launchEnvironment["BRAWL_DEMO_LIVE"] = "1"
        // 공식 API 데모 데이터 (플레이어·지금 열린 맵). ◀ ▶ 맵 전환은 실제 엔진으로 계산
        app.launchEnvironment["BRAWL_DEMO_FIXTURES"] = Self.fixtures.path
        app.launch()
        XCTAssertTrue(app.staticTexts["BEST TEAM"].waitForExistence(timeout: 30), "추천 카드가 보여야 함")
        sleep(4)   // 초상화 로딩
        shot("01-home-top")
        app.swipeUp(); sleep(1)
        shot("02-home-middle")
        app.swipeUp(); sleep(1)
        shot("02b-home-detail")
        app.swipeUp(); sleep(1)
        shot("02c-home-boxes")
        app.swipeUp(); app.swipeUp(); sleep(1)
        shot("03-home-bottom")

        // 잠금 화면 카드 (처음에는 iOS 가 Live Activity 허용을 묻는다 → 허용)
        _ = XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton")); sleep(2)
        XCUIDevice.shared.press(.home); sleep(2)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // 허용 버튼은 버튼이 아닌 요소로 노출되기도 한다: 종류와 상관없이 찾는다
        for label in ["Allow", "허용"] {
            let el = springboard.descendants(matching: .any).matching(identifier: label).firstMatch
            let byLabel = springboard.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
            if el.waitForExistence(timeout: 2) { el.tap(); sleep(2); break }
            if byLabel.exists { byLabel.tap(); sleep(2); break }
        }
        shot("06-lock-screen")

        // 잠금 해제 → 홈 화면: Dynamic Island 축소
        XCUIDevice.shared.press(.home); sleep(2)
        XCUIDevice.shared.press(.home); sleep(3)
        shot("04-island-compact")
        // 섬을 길게 눌러 펼침
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).press(forDuration: 1.5); sleep(2)
        shot("05-island-expanded")

        // ▶ 다음 맵: 앱이 백그라운드에서 ChangeMapIntent 를 실행해 Live Activity 를 갱신해야 한다
        let next = springboard.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "다음 맵")).firstMatch
        if next.waitForExistence(timeout: 3) {
            next.tap(); sleep(12)
            shot("09-island-after-next")
            XCUIDevice.shared.press(.home); sleep(2)
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).press(forDuration: 1.5); sleep(2)
            shot("10-island-next-map")
        } else {
            XCTFail("Dynamic Island 의 ‘다음 맵’ 버튼을 찾지 못함")
            shot("09-island-next-map-missing")
        }

        // 한 번 더: 위젯 확장이 이미 떠 있는 상태에서 축소형·잠금 화면 (처음 렌더링이 늦는 경우 확인)
        XCUIDevice.shared.press(.home); sleep(4)
        shot("07-island-compact-again")
        _ = XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton")); sleep(2)
        XCUIDevice.shared.press(.home); sleep(4)
        shot("08-lock-screen-again")
    }
}
