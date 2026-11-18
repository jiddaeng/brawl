import SwiftUI

@main
struct BrawlAssistantApp: App {
    @StateObject private var app = AppState()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            HomeView(activity: app.liveActivity)
                .environmentObject(app)
                .task {
                    #if DEBUG
                    if AppState.isDemo { return }
                    #endif
                    await app.refresh()
                }
                .onChange(of: phase) { _, p in
                    // 앱으로 돌아오면 방송 확장이 남긴 상태를 다시 읽고 Live Activity 를 맞춘다
                    if p == .active { app.sessionDidChange() }
                }
        }
    }
}
