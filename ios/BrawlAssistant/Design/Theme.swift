import SwiftUI

/// Draft Room 웹(index.html :root)과 같은 디자인 토큰: e스포츠 방송 화면 느낌의 남보라 바탕 + 금색·바이올렛·블루
enum Theme {
    // 바탕
    static let background = Color(hex: 0x0B0A1F)       // --bg
    static let background2 = Color(hex: 0x141235)      // --bg2
    static let panel = Color(hex: 0x1B1846)            // --panel
    static let deep = Color(hex: 0x0D0B26)             // 브롤러 카드·박스 바탕
    static let track = Color(hex: 0x0A0920)            // 막대 바탕
    static let line = Color(hex: 0x2E2A6B)             // --line
    // 글자
    static let text = Color(hex: 0xF3F1FF)             // --fg
    static let secondaryText = Color(hex: 0x9C97D6)    // --dim
    // 강조
    static let accent = Color(hex: 0xFFCF1F)           // --gold
    static let gold2 = Color(hex: 0xFF9F1C)            // --gold2
    static let goldInk = Color(hex: 0x2A1600)          // 금색 위 글자
    static let goldShadow = Color(hex: 0x6B2F00)       // 로고·큰 숫자 그림자
    static let blue = Color(hex: 0x2EA8FF)
    static let violet = Color(hex: 0x9B5CFF)
    static let error = Color(hex: 0xFF3D6E)            // --red
    static let positive = Color(hex: 0x36E39B)         // --green

    // 예전 이름 (다른 화면 호환)
    static var card: Color { panel }
    static var secondaryBackground: Color { deep }
    static var divider: Color { line }

    static let corner: CGFloat = 20
    static let symbol = "scope"

    // 그라데이션
    static let cardGradient = LinearGradient(colors: [panel, background2], startPoint: .top, endPoint: .bottom)
    static let goldGradient = LinearGradient(colors: [Color(hex: 0xFFF7C2), accent, gold2], startPoint: .top, endPoint: .bottom)
    static let barGradient = LinearGradient(colors: [violet, blue], startPoint: .leading, endPoint: .trailing)
    static let barHigh = LinearGradient(colors: [gold2, accent], startPoint: .leading, endPoint: .trailing)
    static let barLow = LinearGradient(colors: [Color(hex: 0x7A1230), error], startPoint: .leading, endPoint: .trailing)

    // 글꼴 (Resources/Fonts, OFL): 웹 --f-display / --f-ko / --f-mono
    /// 영문 로고·숫자 (Lilita One, 한글 글리프 없음)
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font { .custom("LilitaOne", size: size, relativeTo: style) }
    /// 한글 제목 (Black Han Sans)
    static func ko(_ size: CGFloat, relativeTo style: Font.TextStyle = .headline) -> Font { .custom("BlackHanSans-Regular", size: size, relativeTo: style) }
    /// 칩·보조 정보 (JetBrains Mono)
    static func mono(_ size: CGFloat, relativeTo style: Font.TextStyle = .caption) -> Font { .custom("JetBrainsMono-Regular", size: size, relativeTo: style) }
    /// Live Activity 용 고정 크기
    static func displayFixed(_ size: CGFloat) -> Font { .custom("LilitaOne", fixedSize: size) }
    static func koFixed(_ size: CGFloat) -> Font { .custom("BlackHanSans-Regular", fixedSize: size) }
    static func monoFixed(_ size: CGFloat) -> Font { .custom("JetBrainsMono-Regular", fixedSize: size) }

    /// 브롤러 희귀도 색 ("#rrggbb", 없으면 회색 #555 — 웹 --rc 기본값)
    static func rarity(_ hex: String?) -> Color {
        guard let h = hex, h.hasPrefix("#"), let v = UInt32(h.dropFirst(), radix: 16), h.count == 7 else { return Color(hex: 0x555555) }
        return Color(hex: v)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

/// 웹 로고: 금색 그라데이션 + 갈색 그림자 + 살짝 기울임
struct DraftRoomLogo: View {
    var size: CGFloat = 42
    var subtitle = true
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DRAFT ROOM")
                .font(Theme.displayFixed(size))
                .foregroundStyle(Theme.goldGradient)
                .shadow(color: Theme.goldShadow, radius: 0, x: 0, y: size * 0.07)
                .shadow(color: Theme.accent.opacity(0.35), radius: size * 0.4)
            if subtitle {
                Text("브롤스타즈 조합 연구소").font(Theme.koFixed(size * 0.3)).tracking(size * 0.13).foregroundStyle(Theme.text)
            }
        }
        .transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.105, d: 1, tx: size * 0.1, ty: 0))   // skew(-6deg)
    }
}

/// 웹 .chip: 모노 글꼴 알약
struct Chip<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        HStack(spacing: 6) { content }
            .font(Theme.mono(12))
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.panel.opacity(0.7), in: Capsule())
            .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
    }
}

/// 웹 .tag: 금색 바탕 모노 태그 (S-TIER 등)
struct GoldTag: View {
    let text: String
    var body: some View {
        Text(text).font(Theme.mono(11).weight(.bold)).foregroundStyle(Theme.goldInk)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// 웹 배경: 남보라 바탕 + 오른쪽 위 바이올렛 빛 + 금·보라 입자 (움직이지 않음)
struct DraftRoomBackground: View {
    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [Theme.violet.opacity(0.28), .clear], center: UnitPoint(x: 0.85, y: -0.05), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Theme.accent.opacity(0.06), .clear], center: UnitPoint(x: 0.1, y: 1.0), startRadius: 0, endRadius: 360)
            Canvas { ctx, size in
                var g = SeededRandom(seed: 7)
                for _ in 0..<46 {
                    let p = CGPoint(x: g.next() * size.width, y: g.next() * size.height)
                    let r = g.next() * 1.6 + 0.5
                    let c = g.next() < 0.5 ? Theme.accent : Theme.violet
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(c.opacity(0.45)))
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// 입자 위치를 매번 같게 (화면이 다시 그려져도 깜빡이지 않게)
struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) % 10_000) / 10_000
    }
}
