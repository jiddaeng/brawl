import Foundation
import ReplayKit
import CoreMedia
import CoreVideo
import os
import BrawlCore

/// 프레임 샘플링 + 분석 큐 관리. 매 프레임을 분석하지 않는다:
/// 최소 1초 간격, 화면 변화가 없으면 건너뜀(최대 8초마다 한 번은 확인), 이전 분석이 끝나야 다음 분석, 메모리가 부족하면 건너뜀.
final class ScreenCaptureManager {
    private let stopHandler: (String) -> Void
    private let stateQueue = DispatchQueue(label: "brawl.capture.state")
    private let analysisQueue = DispatchQueue(label: "brawl.capture.analysis", qos: .utility)
    private var sampler = FrameSampler(minInterval: 1.0, maxInterval: 8, changeThreshold: 4)
    private var paused = false
    private let analyzer = FrameAnalyzer()
    private let recognizer = GameScreenRecognizer()
    private let darwin = DarwinObserver()
    private var heartbeat: DispatchSourceTimer?
    private let log = Logger(subsystem: "BrawlAssistant.Broadcast", category: "capture")
    /// 방송 확장 메모리 상한(약 50MB) 안에서 Vision 이 돌 여유가 있는지
    private let minimumFreeMemory = 12 * 1024 * 1024

    init(stopHandler: @escaping (String) -> Void) { self.stopHandler = stopHandler }

    func start() {
        analysisQueue.sync { recognizer.start() }
        darwin.observe(.stopRequested) { [weak self] in self?.stopHandler("Brawl Assistant 에서 화면 분석을 종료했습니다.") }
        darwin.observe(.retryRequested) { [weak self] in self?.analysisQueue.async { self?.recognizer.retry() } }
        darwin.observe(.recommendationsChanged) { [weak self] in self?.analysisQueue.async { self?.recognizer.recommendationsChanged() } }
        let t = DispatchSource.makeTimerSource(queue: analysisQueue)
        t.schedule(deadline: .now() + 10, repeating: 10)
        t.setEventHandler { [weak self] in self?.recognizer.heartbeat() }
        t.resume()
        heartbeat = t
    }

    func pause() { stateQueue.sync { paused = true } }
    func resume() { stateQueue.sync { paused = false } }

    func finish() {
        heartbeat?.cancel(); heartbeat = nil
        analysisQueue.sync { recognizer.finish() }
    }

    func handle(_ sampleBuffer: CMSampleBuffer) {
        let now = Date()
        // 시간 조건을 먼저 본다 (서명 계산 비용도 아낌)
        guard stateQueue.sync(execute: { !paused && sampler.isDue(now: now) }) else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard let signature = Self.signature(pixelBuffer) else { return }
        let go = stateQueue.sync { sampler.shouldAnalyze(signature: signature, now: now) }
        guard go else { return }
        let available = os_proc_available_memory()
        if available > 0 && available < minimumFreeMemory {
            log.notice("메모리 부족으로 분석 건너뜀: \(available) bytes")
            stateQueue.sync { sampler.finish() }
            return
        }
        let orientation = Self.orientation(sampleBuffer)
        analysisQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                do {
                    let lines = try self.analyzer.recognizeText(in: pixelBuffer, orientation: orientation)
                    self.recognizer.process(lines, at: now)
                } catch {
                    self.log.error("OCR 실패: \(error.localizedDescription)")
                }
            }
            self.stateQueue.sync { self.sampler.finish() }
        }
    }

    /// ReplayKit 이 붙여 주는 화면 방향 (가로로 하는 게임 대응)
    static func orientation(_ sb: CMSampleBuffer) -> CGImagePropertyOrientation {
        guard let n = CMGetAttachment(sb, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
              let o = CGImagePropertyOrientation(rawValue: n.uint32Value) else { return .up }
        return o
    }

    /// 16×9 밝기 썸네일 (화면 변화 감지용). 복사 없이 픽셀 버퍼에서 바로 읽는다
    static func signature(_ pb: CVPixelBuffer) -> [UInt8]? {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let format = CVPixelBufferGetPixelFormatType(pb)
        let gw = 16, gh = 9
        var out = [UInt8](repeating: 0, count: gw * gh)
        switch format {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            guard let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else { return nil }
            let w = CVPixelBufferGetWidthOfPlane(pb, 0), h = CVPixelBufferGetHeightOfPlane(pb, 0), row = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
            let p = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<gh { for x in 0..<gw { out[y * gw + x] = p[(y * h / gh + h / gh / 2) * row + (x * w / gw + w / gw / 2)] } }
        case kCVPixelFormatType_32BGRA:
            guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
            let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), row = CVPixelBufferGetBytesPerRow(pb)
            let p = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<gh { for x in 0..<gw {
                let i = (y * h / gh + h / gh / 2) * row + (x * w / gw + w / gw / 2) * 4
                out[y * gw + x] = UInt8((Int(p[i]) + 2 * Int(p[i + 1]) + Int(p[i + 2])) / 4)
            } }
        default:
            return [UInt8](repeating: 0, count: gw * gh)   // 알 수 없는 형식: 시간 조건만으로 샘플링
        }
        return out
    }
}
