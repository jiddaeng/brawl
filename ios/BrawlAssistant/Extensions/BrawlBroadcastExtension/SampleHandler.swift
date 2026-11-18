import ReplayKit

/// ReplayKit Broadcast Upload Extension 진입점.
/// 사용자가 방송 시트에서 직접 시작해야만 실행되며, 화면 프레임은 기기 안에서 글자 인식에만 쓰고 저장·전송하지 않는다.
final class SampleHandler: RPBroadcastSampleHandler {
    private lazy var manager = ScreenCaptureManager { [weak self] message in
        // 앱에서 '화면 분석 종료'를 누르면 방송을 끝낸다 (시스템이 이 문구로 알림을 띄운다)
        self?.finishBroadcastWithError(NSError(domain: "BrawlAssistant", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
    }

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) { manager.start() }
    override func broadcastPaused() { manager.pause() }
    override func broadcastResumed() { manager.resume() }
    override func broadcastFinished() { manager.finish() }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }   // 오디오는 쓰지 않는다
        manager.handle(sampleBuffer)
    }
}
