import Foundation

/// CSS color conversion: hex, rgb(), hsl() notations.
public enum ColorTools {
    public static let commands: [ToolCommand] = [
        ToolCommand(
            id: "color.hex",
            title: "Convert Color to Hex",
            summary: "Hex notation for any CSS color",
            group: .color,
            icon: .symbol("paintpalette"),
            aliases: ["to hex color", "rgb to hex", "hsl to hex", "hex color"],
            copyNoun: "hex color",
            affinity: { profile in
                if profile.has(.hexColor) { return 40 }
                if profile.has(.color) { return 90 }
                return 0
            },
            evaluate: { request in evaluateHex(request) }
        ),
        ToolCommand(
            id: "color.rgb",
            title: "Convert Color to RGB",
            summary: "rgb() notation for any CSS color",
            group: .color,
            icon: .symbol("paintpalette"),
            aliases: ["to rgb", "hex to rgb", "hsl to rgb", "rgb color"],
            copyNoun: "RGB color",
            affinity: { profile in
                if profile.has(.hexColor) { return 95 }
                if profile.has(.color) { return 85 }
                return 0
            },
            evaluate: { request in evaluateRgb(request) }
        ),
        ToolCommand(
            id: "color.hsl",
            title: "Convert Color to HSL",
            summary: "hsl() notation for any CSS color",
            group: .color,
            icon: .symbol("paintpalette"),
            aliases: ["to hsl", "hex to hsl", "rgb to hsl", "hsl color"],
            copyNoun: "HSL color",
            affinity: { profile in
                if profile.has(.color) { return 80 }
                return 0
            },
            evaluate: { request in evaluateHsl(request) }
        ),
    ]

    // MARK: - Evaluation

    static func evaluateHex(_ request: ToolRequest) -> ToolResult {
        guard let text = request.input.text else {
            return .invalid(ToolDiagnostic("Enter a hex, rgb(), or hsl() color, such as #ff8800."))
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .invalid(ToolDiagnostic("Enter a hex, rgb(), or hsl() color, such as #ff8800."))
        }
        guard let color = parseColor(trimmed) else {
            if trimmed.hasPrefix("#") {
                return .invalid(ToolDiagnostic("\"\(trimmed)\" isn't a valid hex color."))
            }
            return .invalid(ToolDiagnostic("Enter a hex, rgb(), or hsl() color, such as #ff8800."))
        }
        let hex = formatHex(color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        let rgb = formatRgb(color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        let hsl = formatHsl(color.red, color.green, color.blue, alpha: color.alpha)
        let swatch = ColorSwatch(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        let fields: [ResultField] = [
            ResultField(id: "hex", label: "Hex", value: hex),
            ResultField(id: "rgb", label: "RGB", value: rgb),
            ResultField(id: "hsl", label: "HSL", value: hsl),
        ]
        return .success(ToolOutput(primaryText: hex, status: "sRGB", fields: fields, swatch: swatch))
    }

    static func evaluateRgb(_ request: ToolRequest) -> ToolResult {
        guard let text = request.input.text else {
            return .invalid(ToolDiagnostic("Enter a hex, rgb(), or hsl() color, such as #ff8800."))
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .invalid(ToolDiagnostic("Enter a hex, rgb(), or hsl() color, such as #ff8800."))
        }
        guard let color = parseColor(trimmed) else {
            if trimmed.hasPrefix("#") {
                return .invalid(ToolDiagnostic("\"\(trimmed)\" isn't a valid hex color."))
            }
            return .invalid(ToolDiagnostic("Enter a hex, rgb(), or hsl() color, such as #ff8800."))
        }
        let rgb = formatRgb(color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        let hex = formatHex(color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        let hsl = formatHsl(color.red, color.green, color.blue, alpha: color.alpha)
        let swatch = ColorSwatch(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        let fields: [ResultField] = [
            ResultField(id: "hex", label: "Hex", value: hex),
            ResultField(id: "rgb", label: "RGB", value: rgb),
            ResultField(id: "hsl", label: "HSL", value: hsl),
        ]
        return .success(ToolOutput(primaryText: rgb, status: "sRGB", fields: fields, swatch: swatch))
    }

    static func evaluateHsl(_ request: ToolRequest) -> ToolResult {
        guard let text = request.input.text else {
            return .invalid(ToolDiagnostic("Enter a hex, rgb(), or hsl() color, such as #ff8800."))
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .invalid(ToolDiagnostic("Enter a hex, rgb(), or hsl() color, such as #ff8800."))
        }
        guard let color = parseColor(trimmed) else {
            if trimmed.hasPrefix("#") {
                return .invalid(ToolDiagnostic("\"\(trimmed)\" isn't a valid hex color."))
            }
            return .invalid(ToolDiagnostic("Enter a hex, rgb(), or hsl() color, such as #ff8800."))
        }
        let hsl = formatHsl(color.red, color.green, color.blue, alpha: color.alpha)
        let hex = formatHex(color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        let rgb = formatRgb(color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        let swatch = ColorSwatch(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        let fields: [ResultField] = [
            ResultField(id: "hex", label: "Hex", value: hex),
            ResultField(id: "rgb", label: "RGB", value: rgb),
            ResultField(id: "hsl", label: "HSL", value: hsl),
        ]
        return .success(ToolOutput(primaryText: hsl, status: "sRGB", fields: fields, swatch: swatch))
    }

    // MARK: - Color Parsing

    /// Parsed sRGB color with components in 0…1.
    struct ParsedColor: Sendable {
        var red: Double
        var green: Double
        var blue: Double
        var alpha: Double
    }

    static func parseColor(_ text: String) -> ParsedColor? {
        if text.hasPrefix("#") {
            return parseHex(text)
        }
        return parseFunctional(text)
    }

    static func parseHex(_ text: String) -> ParsedColor? {
        let body = String(text.dropFirst()) // remove '#'
        let upper = body.uppercased()
        // Validate hex digits
        guard upper.allSatisfy({ $0.isHexDigit }) else { return nil }

        let len = upper.count
        guard len == 3 || len == 4 || len == 6 || len == 8 else { return nil }

        func hexDigitValue(_ c: Character) -> UInt8? {
            switch c {
            case "0"..."9": return UInt8(c.asciiValue! - 0x30)
            case "a"..."f": return UInt8(c.asciiValue! - 0x57)
            case "A"..."F": return UInt8(c.asciiValue! - 0x37)
            default: return nil
            }
        }

        func hexByte(_ s: String) -> Double? {
            let chars = Array(s)
            guard chars.count == 2 else { return nil }
            guard let h = hexDigitValue(chars[0]), let l = hexDigitValue(chars[1]) else { return nil }
            return Double((h << 4) | l) / 255.0
        }

        func hexSingle(_ s: String) -> Double? {
            let doubled = s + s
            return hexByte(doubled)
        }

        if len == 3 {
            let chars = Array(upper)
            guard let r = hexSingle(String(chars[0])),
                  let g = hexSingle(String(chars[1])),
                  let b = hexSingle(String(chars[2])) else { return nil }
            return ParsedColor(red: r, green: g, blue: b, alpha: 1.0)
        } else if len == 4 {
            let chars = Array(upper)
            guard let r = hexSingle(String(chars[0])),
                  let g = hexSingle(String(chars[1])),
                  let b = hexSingle(String(chars[2])),
                  let a = hexSingle(String(chars[3])) else { return nil }
            return ParsedColor(red: r, green: g, blue: b, alpha: a)
        } else if len == 6 {
            guard let r = hexByte(String(upper.prefix(2))),
                  let g = hexByte(String(upper.dropFirst(2).prefix(2))),
                  let b = hexByte(String(upper.dropFirst(4).prefix(2))) else { return nil }
            return ParsedColor(red: r, green: g, blue: b, alpha: 1.0)
        } else {
            // len == 8
            guard let r = hexByte(String(upper.prefix(2))),
                  let g = hexByte(String(upper.dropFirst(2).prefix(2))),
                  let b = hexByte(String(upper.dropFirst(4).prefix(2))),
                  let a = hexByte(String(upper.dropFirst(6).prefix(2))) else { return nil }
            return ParsedColor(red: r, green: g, blue: b, alpha: a)
        }
    }

    /// `name(body)` with nothing after the closing parenthesis.
    static func parseFunctional(_ text: String) -> ParsedColor? {
        guard text.hasSuffix(")"), let open = text.firstIndex(of: "(") else { return nil }
        let close = text.index(before: text.endIndex)
        guard open < close else { return nil }
        let name = text[..<open].lowercased()
        let body = String(text[text.index(after: open)..<close])
        guard !body.contains("("), !body.contains(")") else { return nil }

        switch name {
        case "rgb", "rgba":
            return parseRgbBody(body)
        case "hsl", "hsla":
            return parseHslBody(body)
        default:
            return nil
        }
    }

    static func parseRgbBody(_ body: String) -> ParsedColor? {
        guard let (channels, alpha) = splitChannelsAndAlpha(body),
              let r = parseRgbChannel(channels[0]),
              let g = parseRgbChannel(channels[1]),
              let b = parseRgbChannel(channels[2]) else { return nil }
        // r, g, b are on a 0–255 scale; clamp then convert to 0–1 (CSS clamps out-of-range values).
        return ParsedColor(
            red: Swift.max(0, Swift.min(255, r)) / 255.0,
            green: Swift.max(0, Swift.min(255, g)) / 255.0,
            blue: Swift.max(0, Swift.min(255, b)) / 255.0,
            alpha: Swift.max(0, Swift.min(1, alpha ?? 1))
        )
    }

    static func parseHslBody(_ body: String) -> ParsedColor? {
        guard let (channels, alpha) = splitChannelsAndAlpha(body),
              let h = parseHue(channels[0]),
              let s = parsePercent(channels[1]),
              let l = parsePercent(channels[2]) else { return nil }
        let hue = ((h.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
        let sat = Swift.max(0, Swift.min(100, s))
        let lit = Swift.max(0, Swift.min(100, l))
        let rgb = hslToRgb(hue, saturation: sat, lightness: lit)
        return ParsedColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: Swift.max(0, Swift.min(1, alpha ?? 1)))
    }

    /// Splits a function body into exactly three channel strings and an
    /// optional alpha. Comma syntax: `a, b, c` or `a, b, c, alpha`. Space
    /// syntax: `a b c` or `a b c / alpha`. Returns `nil` for any other shape
    /// or an invalid alpha, so malformed input is never read as a color.
    static func splitChannelsAndAlpha(_ body: String) -> (channels: [String], alpha: Double?)? {
        if body.contains(",") {
            guard !body.contains("/") else { return nil }
            let parts = body.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 3 || parts.count == 4, parts.allSatisfy({ !$0.isEmpty && !$0.contains(" ") }) else { return nil }
            if parts.count == 4 {
                guard let alpha = parseAlphaValue(parts[3]) else { return nil }
                return (Array(parts.prefix(3)), alpha)
            }
            return (parts, nil)
        }
        let slashParts = body.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        guard slashParts.count <= 2 else { return nil }
        let channels = slashParts[0].split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard channels.count == 3 else { return nil }
        if slashParts.count == 2 {
            guard !slashParts[1].contains(" "), let alpha = parseAlphaValue(slashParts[1]) else { return nil }
            return (channels, alpha)
        }
        return (channels, nil)
    }

    static func parseRgbChannel(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("%") {
            let numPart = String(trimmed.dropLast())
            guard let val = strictDouble(numPart) else { return nil }
            return val / 100.0 * 255.0
        }
        return strictDouble(trimmed)
    }

    /// Parse a hue value: number or number with "deg" suffix.
    static func parseHue(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        if lower.hasSuffix("deg") {
            let numPart = String(lower.dropLast(3)).trimmingCharacters(in: .whitespaces)
            return strictDouble(numPart)
        }
        return strictDouble(trimmed)
    }

    /// Parse a percentage value (e.g., "50%" → 50.0).
    static func parsePercent(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix("%") else { return nil }
        let numPart = String(trimmed.dropLast())
        return strictDouble(numPart)
    }

    /// Parse an alpha value: number 0-1 or percentage.
    static func parseAlphaValue(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("%") {
            let numPart = String(trimmed.dropLast())
            guard let val = strictDouble(numPart) else { return nil }
            return val / 100.0
        }
        guard let val = strictDouble(trimmed) else { return nil }
        return val
    }

    // MARK: - Color Space Conversion

    /// HSL to RGB. Hue in degrees 0-360, saturation and lightness in 0-100.
    /// Returns (r, g, b) each in 0-1.
    static func hslToRgb(_ h: Double, saturation s: Double, lightness l: Double) -> (Double, Double, Double) {
        let sNorm = s / 100.0
        let lNorm = l / 100.0

        let c = (1.0 - abs(2.0 * lNorm - 1.0)) * sNorm
        let x = c * (1.0 - abs((h / 60.0).truncatingRemainder(dividingBy: 2) - 1.0))
        let m = lNorm - c / 2.0

        var r: Double, g: Double, b: Double

        if h < 60 {
            r = c; g = x; b = 0
        } else if h < 120 {
            r = x; g = c; b = 0
        } else if h < 180 {
            r = 0; g = c; b = x
        } else if h < 240 {
            r = 0; g = x; b = c
        } else if h < 300 {
            r = x; g = 0; b = c
        } else {
            r = c; g = 0; b = x
        }

        return (r + m, g + m, b + m)
    }

    /// RGB to HSL. r, g, b in 0-1. Returns (hue in degrees, saturation %, lightness %).
    static func rgbToHsl(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let l = (maxC + minC) / 2.0

        if maxC == minC {
            // Achromatic
            return (0, 0, l * 100.0)
        }

        let diff = maxC - minC
        let s: Double
        if l > 0.5 {
            s = diff / (2.0 - maxC - minC)
        } else {
            s = diff / (maxC + minC)
        }

        var h: Double
        if maxC == r {
            h = ((g - b) / diff).truncatingRemainder(dividingBy: 6)
        } else if maxC == g {
            h = (b - r) / diff + 2
        } else {
            h = (r - g) / diff + 4
        }
        h *= 60
        if h < 0 { h += 360 }

        return (h, s * 100.0, l * 100.0)
    }

    // MARK: - Formatting

    static func formatHex(_ r: Double, green g: Double, blue b: Double, alpha a: Double) -> String {
        let ri = Int(round(r * 255))
        let gi = Int(round(g * 255))
        let bi = Int(round(b * 255))

        if a < 1.0 {
            let ai = Int(round(a * 255))
            return String(format: "#%02x%02x%02x%02x", ri, gi, bi, ai)
        }
        return String(format: "#%02x%02x%02x", ri, gi, bi)
    }

    static func formatRgb(_ r: Double, green g: Double, blue b: Double, alpha a: Double) -> String {
        let ri = Int(round(r * 255))
        let gi = Int(round(g * 255))
        let bi = Int(round(b * 255))

        if a < 1.0 {
            let alphaStr = formatAlpha(a)
            return String(format: "rgba(%d, %d, %d, %@)", ri, gi, bi, alphaStr)
        }
        return String(format: "rgb(%d, %d, %d)", ri, gi, bi)
    }

    static func formatHsl(_ r: Double, _ g: Double, _ b: Double, alpha a: Double) -> String {
        // Convert from the unquantized channels: rounding to 8-bit first would
        // erase hue and saturation for dark or desaturated colors, so
        // hsl(30 1% 1%) would come back as hsl(0, 0%, 1.2%). Only hex and
        // rgb() output quantize to 0–255.
        let (h, s, l) = rgbToHsl(r, g, b)

        let hStr = formatOneDecimal(h)
        let sStr = formatOneDecimal(s)
        let lStr = formatOneDecimal(l)

        if a < 1.0 {
            let alphaStr = formatAlpha(a)
            return "hsla(\(hStr), \(sStr)%, \(lStr)%, \(alphaStr))"
        }
        return "hsl(\(hStr), \(sStr)%, \(lStr)%)"
    }

    /// Format a value to one decimal place, removing trailing .0.
    static func formatOneDecimal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10.0
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }

    /// Format alpha with at most 3 decimals, trailing zeros removed.
    static func formatAlpha(_ a: Double) -> String {
        // Round to 3 decimal places
        let rounded = (a * 1000).rounded() / 1000.0
        // Format with 3 decimals then strip trailing zeros
        let formatted = String(format: "%.3f", rounded)
        // Remove trailing zeros after decimal point
        var result = formatted
        while result.hasSuffix("0") {
            result = String(result.dropLast())
        }
        if result.hasSuffix(".") {
            result = String(result.dropLast())
        }
        return result
    }

    /// A finite CSS number: optional sign, digits with an optional fraction,
    /// and an optional exponent. Rejects `nan`, `inf`, and other spellings
    /// that `Double(_:)` accepts, so conversion to integers can never trap.
    static func strictDouble(_ text: String) -> Double? {
        let scalars = Array(text.unicodeScalars)
        guard !scalars.isEmpty else { return nil }
        var index = 0
        if scalars[index] == "+" || scalars[index] == "-" { index += 1 }
        var digits = 0
        while index < scalars.count, ("0"..."9").contains(scalars[index]) { index += 1; digits += 1 }
        if index < scalars.count, scalars[index] == "." {
            index += 1
            while index < scalars.count, ("0"..."9").contains(scalars[index]) { index += 1; digits += 1 }
        }
        guard digits > 0 else { return nil }
        if index < scalars.count, scalars[index] == "e" || scalars[index] == "E" {
            index += 1
            if index < scalars.count, scalars[index] == "+" || scalars[index] == "-" { index += 1 }
            let exponentStart = index
            while index < scalars.count, ("0"..."9").contains(scalars[index]) { index += 1 }
            guard index > exponentStart else { return nil }
        }
        guard index == scalars.count, let value = Double(text), value.isFinite else { return nil }
        return value
    }
}
