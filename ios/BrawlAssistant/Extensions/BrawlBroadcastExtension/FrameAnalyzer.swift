import Foundation
import Vision
import CoreVideo
import BrawlCore

/// Apple Vision 글자 인식. 한국어는 .accurate 에서만 지원되므로 accurate 를 쓰고, 사전 매칭을 하므로 언어 보정은 끈다.
final class FrameAnalyzer {
    private let request: VNRecognizeTextRequest = {
        let r = VNRecognizeTextRequest()
        r.revision = VNRecognizeTextRequestRevision3   // iOS 16+, 한국어 지원
        r.recognitionLevel = .accurate
        r.recognitionLanguages = ["ko-KR", "en-US"]
        r.usesLanguageCorrection = false
        r.minimumTextHeight = 0.02                      // 아주 작은 글자는 무시 (속도·메모리)
        return r
    }()

    func recognizeText(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) throws -> [OCRLine] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap { obs in
            guard let c = obs.topCandidates(1).first else { return nil }
            let b = obs.boundingBox   // Vision 좌표: 왼쪽 아래 원점
            return OCRLine(text: c.string, confidence: Double(c.confidence), midX: Double(b.midX), midY: Double(1 - b.midY))
        }
    }
}
