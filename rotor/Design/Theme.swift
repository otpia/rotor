import AppKit
import SwiftUI

// 从 Sketch 设计稿提炼的视觉令牌；macOS 原生动态色优先，品牌色固定
enum RotorTheme {
    static let cornerRadius: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let cardSpacing: CGFloat = 12
    static let ringDiameter: CGFloat = 28
    static let ringStroke: CGFloat = 3
}

extension Color {
    // 品牌色：蓝色主色 / 危险红（到期 TOTP 和错误态）
    static let rotorPrimary = Color(red: 47 / 255, green: 111 / 255, blue: 255 / 255)
    static let rotorDanger  = Color(red: 240 / 255, green: 65 / 255, blue: 29 / 255)

    // 动态 light/dark 辅助构造
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(
                from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]
            ) != nil
            return isDark ? NSColor(dark) : NSColor(light)
        })
    }

    // 窗口背景（light #F2F3F5 / dark #000）
    static let rotorBackground = Color(
        light: Color(red: 242 / 255, green: 243 / 255, blue: 245 / 255),
        dark:  Color(red: 0, green: 0, blue: 0)
    )

    // 卡片背景（light #FFF / dark #1C1C1E）
    static let rotorCard = Color(
        light: Color.white,
        dark:  Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    )

    // 卡片 hover（仅 light 高亮，dark 下维持卡片色但提升透明度）
    static let rotorCardHover = Color(
        light: Color(red: 230 / 255, green: 232 / 255, blue: 235 / 255),
        dark:  Color(red: 44 / 255, green: 44 / 255, blue: 46 / 255)
    )
}

extension Font {
    // TOTP 数字：Courier Prime Bold（bundle 字体），fallback 回 SF Mono
    static let rotorCode        = Font.custom("CourierPrime-Bold", size: 36).monospacedDigit()
    static let rotorCodeCompact = Font.custom("CourierPrime-Bold", size: 28).monospacedDigit()
    // issuer / label 使用系统字体；macOS 简中默认 fallback 苹方 SC
    static let rotorIssuer      = Font.system(size: 15, weight: .semibold)
    static let rotorLabel       = Font.system(size: 12, weight: .regular)
}

// TOTP 码按 3+3 分组，用单空格分隔
func formatTOTP(_ code: String) -> String {
    guard code.count == 6 else { return code }
    let mid = code.index(code.startIndex, offsetBy: 3)
    return String(code[..<mid]) + " " + String(code[mid...])
}
