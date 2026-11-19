import AppIntents

/// Dynamic Island·잠금 화면의 ◀ ▶ 버튼: 지금 열린 맵을 차례로 바꾼다.
/// LiveActivityIntent 는 위젯이 아니라 앱 프로세스에서 실행된다 (앱이 백그라운드·게임 중이어도 시스템이 앱을 깨워 실행).
/// 그래서 앱이 직접 추천을 바꾸고 Live Activity 를 갱신한다. 화면 녹화·서버·푸시가 필요 없다.
/// 이 파일은 앱과 위젯 둘 다에 들어간다 (버튼이 같은 타입을 써야 함). 실제 동작은 앱 쪽에서만 컴파일된다.
struct ChangeMapIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "맵 바꾸기"
    static var description = IntentDescription("지금 열린 맵을 차례로 바꾸고 추천을 갱신합니다.")

    @Parameter(title: "이동")
    var step: Int

    init() { step = 1 }
    init(step: Int) { self.step = step }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await runCycle(step)
        #endif
        return .result()
    }
}

#if !WIDGET_EXTENSION
@MainActor private func runCycle(_ step: Int) async {
    await AppState.shared.cycleMap(step: step)
}
#endif
