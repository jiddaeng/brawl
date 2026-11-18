#if canImport(CoreGraphics) && canImport(ImageIO)
import Foundation
import CoreGraphics
import ImageIO

/// PNG 를 브라우저 canvas getImageData 와 같은 RGBA 바이트로 푼다.
/// 웹과 결과를 맞추려면 색 관리(색 공간 변환)를 거치면 안 되므로, 디코딩된 원본 바이트를 직접 읽는다.
/// (회귀 테스트로 확인: 맵 PNG 18개 모두 색 프로필이 없고, 원본 픽셀로 계산한 값이 브라우저와 같다)
public enum PixelDecoder {
    public struct RGBA {
        public var bytes: [UInt8]
        public var width: Int
        public var height: Int
        /// 원본 바이트를 그대로 읽었는지 (false 면 CGContext 에 그려서 얻음: 기기 검증 필요)
        public var raw: Bool
    }

    public static func decode(_ data: Data) -> RGBA? {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, opts),
              let img = CGImageSourceCreateImageAtIndex(src, 0, opts) else { return nil }
        return raw(img) ?? drawn(img)
    }

    static func raw(_ img: CGImage) -> RGBA? {
        guard img.bitsPerComponent == 8, let cf = img.dataProvider?.data, let p = CFDataGetBytePtr(cf) else { return nil }
        let bpp = img.bitsPerPixel / 8
        guard bpp == 3 || bpp == 4 else { return nil }
        var r = 0, g = 1, b = 2, a = -1
        switch img.alphaInfo {
        case .none: guard bpp == 3 else { return nil }
        case .noneSkipLast: break
        case .last, .premultipliedLast: a = 3
        case .noneSkipFirst: r = 1; g = 2; b = 3
        case .first, .premultipliedFirst: a = 0; r = 1; g = 2; b = 3
        default: return nil
        }
        switch img.byteOrderInfo {
        case .orderDefault, .order32Big: break
        case .order32Little where bpp == 4: r = 3 - r; g = 3 - g; b = 3 - b; if a >= 0 { a = 3 - a }
        default: return nil
        }
        let premul = img.alphaInfo == .premultipliedLast || img.alphaInfo == .premultipliedFirst
        let w = img.width, h = img.height, rowBytes = img.bytesPerRow
        guard CFDataGetLength(cf) >= rowBytes * h else { return nil }
        var out = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            let row = p + y * rowBytes
            for x in 0..<w {
                let s = row + x * bpp, o = (y * w + x) * 4
                var R = Int(s[r]), G = Int(s[g]), B = Int(s[b])
                let A = a >= 0 ? Int(s[a]) : 255
                if premul && A > 0 && A < 255 { R = min(255, (R * 255 + A / 2) / A); G = min(255, (G * 255 + A / 2) / A); B = min(255, (B * 255 + A / 2) / A) }
                out[o] = UInt8(R); out[o + 1] = UInt8(G); out[o + 2] = UInt8(B); out[o + 3] = UInt8(A)
            }
        }
        return RGBA(bytes: out, width: w, height: h, raw: true)
    }

    static func drawn(_ img: CGImage) -> RGBA? {
        let w = img.width, h = img.height
        // 이미지 자신의 색 공간에 그려 변환을 피한다 (RGB 가 아니면 sRGB)
        let space = (img.colorSpace?.model == .rgb ? img.colorSpace : nil) ?? CGColorSpace(name: CGColorSpace.sRGB)!
        var out = [UInt8](repeating: 0, count: w * h * 4)
        let ok = out.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? RGBA(bytes: out, width: w, height: h, raw: false) : nil
    }

    /// Live Activity 에 넣을 작은 정사각형 PNG (브롤러 초상화)
    public static func thumbnailPNG(_ data: Data, side: Int) -> Data? {
        let opts = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: side, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts) else { return nil }
        let out = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(out as CFMutableData, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, thumb, nil)
        return CGImageDestinationFinalize(dst) ? out as Data : nil
    }
}
#endif
