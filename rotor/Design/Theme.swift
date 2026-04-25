import AppKit
import SwiftUI

// Visual tokens distilled from the Sketch design; prefer macOS native dynamic colors, brand colors are fixed
enum RotorTheme {
    static let cornerRadius: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let cardSpacing: CGFloat = 12
    static let ringDiameter: CGFloat = 28
    static let ringStroke: CGFloat = 3
}

extension Color {
    // Brand colors: primary blue / danger red (used for expiring TOTP and error states)
    static let rotorPrimary = Color(red: 47 / 255, green: 111 / 255, blue: 255 / 255)
    static let rotorDanger  = Color(red: 240 / 255, green: 65 / 255, blue: 29 / 255)

    // Dynamic light/dark helper initializer
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(
                from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]
            ) != nil
            return isDark ? NSColor(dark) : NSColor(light)
        })
    }

    // Window background (light #F2F3F5 / dark #000)
    static let rotorBackground = Color(
        light: Color(red: 242 / 255, green: 243 / 255, blue: 245 / 255),
        dark:  Color(red: 0, green: 0, blue: 0)
    )

    // Card background (light #FFF / dark #1C1C1E)
    static let rotorCard = Color(
        light: Color.white,
        dark:  Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    )

    // Card hover (light highlights only; in dark mode keep card color but bump opacity)
    static let rotorCardHover = Color(
        light: Color(red: 230 / 255, green: 232 / 255, blue: 235 / 255),
        dark:  Color(red: 44 / 255, green: 44 / 255, blue: 46 / 255)
    )
}

extension Font {
    // TOTP digits: Courier Prime Bold (bundled font); falls back to SF Mono
    static let rotorCode        = Font.custom("CourierPrime-Bold", size: 36).monospacedDigit()
    static let rotorCodeCompact = Font.custom("CourierPrime-Bold", size: 28).monospacedDigit()
    // issuer / label use the system font; macOS Simplified Chinese falls back to PingFang SC by default
    static let rotorIssuer      = Font.system(size: 15, weight: .semibold)
    static let rotorLabel       = Font.system(size: 12, weight: .regular)
}

// Group the TOTP code as 3+3 separated by a single space
func formatTOTP(_ code: String) -> String {
    guard code.count == 6 else { return code }
    let mid = code.index(code.startIndex, offsetBy: 3)
    return String(code[..<mid]) + " " + String(code[mid...])
}
