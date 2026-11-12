import AppKit
import SwiftUI

/// Sizes, fonts, and colors shared by the palette views. Colors are dynamic
/// system or custom colors, so light/dark appearance and Increase Contrast
/// work without extra code.
@MainActor
enum Theme {
    // MARK: Layout

    static let panelWidth: CGFloat = 760
    static let searchHeight: CGFloat = 460
    static let toolHeight: CGFloat = 600
    /// Below this width, editors and results stack vertically.
    static let narrowWidth: CGFloat = 640
    static let cornerRadius: CGFloat = 18
    static let listWidth: CGFloat = 300
    static let rowHeight: CGFloat = 36

    // MARK: Fonts

    static let searchFont = NSFont.systemFont(ofSize: 20, weight: .regular)
    static let codeFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let codeLineHeight: CGFloat = 1.25

    // MARK: Colors

    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua])
                .map { $0 == .darkAqua || $0 == .accessibilityHighContrastDarkAqua } == true ? dark : light
        }
    }

    static func hex(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    // Token colors keep at least 4.5:1 contrast on the panel in both appearances.
    static let syntaxKey = dynamic(light: hex(0x2F4FB8), dark: hex(0xA3B5FF))
    static let syntaxString = dynamic(light: hex(0x1B6E2E), dark: hex(0x93DCA2))
    static let syntaxNumber = dynamic(light: hex(0x9A4A0B), dark: hex(0xF4B57E))
    static let syntaxLiteral = dynamic(light: hex(0x7D2AA8), dark: hex(0xD9A6F7))
    static let syntaxComment = NSColor.secondaryLabelColor
    static let syntaxPunctuation = NSColor.secondaryLabelColor

    static let success = Color(nsColor: dynamic(light: hex(0x1B7F3B), dark: hex(0x6FD68C)))
    static let warning = Color(nsColor: dynamic(light: hex(0x9A5B00), dark: hex(0xF5C46B)))
    static let failure = Color(nsColor: dynamic(light: hex(0xB3261E), dark: hex(0xFF9B91)))

    /// Background for code and result areas, slightly separated from the panel material.
    static let well = Color(nsColor: dynamic(
        light: NSColor.black.withAlphaComponent(0.035),
        dark: NSColor.white.withAlphaComponent(0.045)
    ))
    static let selection = Color.accentColor.opacity(0.22)
    static let chip = Color.primary.opacity(0.07)
    static let hairline = Color(nsColor: .separatorColor)
}

/// A small keycap label such as "⌘K" or "↵".
struct Keycap: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.secondary.opacity(0.45), lineWidth: 0.8))
            .accessibilityHidden(true)
    }
}
