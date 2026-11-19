import SwiftUI

/// Draft Room 디자인 토큰. 검은 배경 · 미니멀 · 강조색(웹 --gold #FFCF1F)은 필요한 곳에만
enum Theme {
    static let background = Color(hex: 0x000000)
    static let card = Color(hex: 0x111111)
    static let secondaryBackground = Color(hex: 0x1A1A1A)
    static let text = Color(hex: 0xFFFFFF)
    static let secondaryText = Color(hex: 0x8E8E93)
    static let divider = Color(hex: 0x292929)
    /// Draft Room 웹의 강조색 (--gold)
    static let accent = Color(hex: 0xFFCF1F)
    /// 오류 표시 (웹 --red)
    static let error = Color(hex: 0xFF3D6E)
    /// 실전 승률 효과 + (웹 --green)
    static let positive = Color(hex: 0x36E39B)

    static let corner: CGFloat = 20
    static let symbol = "scope"   // 앱 심볼 (Dynamic Island compact/minimal)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}
