import Foundation

/// HTML entity escaping and unescaping.
public enum HTMLTools {
    public static let commands: [ToolCommand] = [
        escapeCommand,
        unescapeCommand,
    ]

    // ─── Escape ──────────────────────────────────────────────────────────────

    private static let escapeCommand = ToolCommand(
        id: "html.escape",
        title: "Escape HTML",
        summary: "Replace & < > \" ' with entities",
        group: .escape,
        icon: .glyph("&;"),
        aliases: ["html escape", "html encode", "escape html entities", "encode html entities"],
        copyNoun: "HTML",
        affinity: { profile in profile.has(.xml) || profile.has(.html) ? 30 : 0 },
        evaluate: { request in escapeHTML(request) }
    )

    static func escapeHTML(_ request: ToolRequest) -> ToolResult {
        guard let text = request.input.text else { return .needsInput("Paste text to escape.") }
        switch escape(text, maxBytes: request.limits.maxOutputBytes, cancellation: request.cancellation) {
        case .success(let output): return .success(ToolOutput(primaryText: output, status: "Escaped"))
        case .failure(.tooLarge): return .tooLarge(request.limits.outputLimitMessage)
        case .failure(.cancelled): return .cancelled
        }
    }

    enum EscapeFailure: Error { case tooLarge, cancelled }

    /// Replaces `& < > " '` with entities, stopping as soon as the output
    /// would exceed `maxBytes` (escaping can grow text sixfold).
    static func escape(_ text: String, maxBytes: Int = .max, cancellation: CancellationCheck = .never) -> Result<String, EscapeFailure> {
        let bytes = Array(text.utf8)
        var result: [UInt8] = []
        result.reserveCapacity(min(bytes.count + bytes.count / 8, maxBytes))
        for (index, byte) in bytes.enumerated() {
            if index % 4096 == 0, cancellation.isCancelled { return .failure(.cancelled) }
            switch byte {
            case 0x26: result.append(contentsOf: "&amp;".utf8)
            case 0x3C: result.append(contentsOf: "&lt;".utf8)
            case 0x3E: result.append(contentsOf: "&gt;".utf8)
            case 0x22: result.append(contentsOf: "&quot;".utf8)
            case 0x27: result.append(contentsOf: "&#39;".utf8)
            default: result.append(byte)
            }
            if result.count > maxBytes { return .failure(.tooLarge) }
        }
        return .success(String(decoding: result, as: UTF8.self))
    }

    // ─── Unescape ────────────────────────────────────────────────────────────

    private static let unescapeCommand = ToolCommand(
        id: "html.unescape",
        title: "Unescape HTML",
        summary: "Decode named and numeric entities",
        group: .escape,
        icon: .glyph("&;"),
        aliases: ["html unescape", "html decode", "decode html entities", "unescape html entities"],
        copyNoun: "text",
        affinity: { profile in profile.has(.htmlEntities) ? 85 : 0 },
        evaluate: { request in unescapeHTML(request) }
    )

    static func unescapeHTML(_ request: ToolRequest) -> ToolResult {
        guard let text = request.input.text else { return .needsInput("Paste text to unescape.") }
        guard let (output, warnings) = unescape(text, cancellation: request.cancellation) else { return .cancelled }
        return .success(ToolOutput(primaryText: output, status: "Unescaped", warnings: warnings))
    }

    /// Longest entity name or digit run examined after `&` or `&#`. Bounding
    /// the look-ahead keeps decoding linear for input full of `&`.
    static let maxReferenceLength = 32

    /// Decodes character references in a single left-to-right pass; decoded
    /// text is never rescanned. Returns `nil` when cancelled.
    static func unescape(_ text: String, cancellation: CancellationCheck = .never) -> (String, [String])? {
        let scalars = Array(text.unicodeScalars)
        var result = String.UnicodeScalarView()
        result.reserveCapacity(scalars.count)
        var invalid: [String] = []
        var unknown: [String] = []
        var unknownSeen = Set<String>()
        var index = 0
        while index < scalars.count {
            if index % 4096 == 0, cancellation.isCancelled { return nil }
            let scalar = scalars[index]
            guard scalar == "&" else {
                result.append(scalar)
                index += 1
                continue
            }
            if let numeric = numericReference(in: scalars, at: index) {
                if let decoded = numeric.scalar {
                    result.append(decoded)
                } else {
                    result.append("\u{FFFD}")
                    invalid.append(numeric.spelling)
                }
                index = numeric.end
            } else if let named = namedReference(in: scalars, at: index) {
                if let codePoint = HTMLEntityTable.codePoints[named.name], let decoded = Unicode.Scalar(codePoint) {
                    result.append(decoded)
                } else {
                    result.append(contentsOf: scalars[index..<named.end])
                    if unknownSeen.insert(named.name).inserted { unknown.append(named.name) }
                }
                index = named.end
            } else {
                result.append(scalar)
                index += 1
            }
        }

        var warnings: [String] = []
        for spelling in invalid.prefix(5) {
            warnings.append("Replaced invalid character reference “\(spelling)” with U+FFFD.")
        }
        if invalid.count > 5 {
            warnings.append("…and \(invalid.count - 5) more invalid character references.")
        }
        for name in unknown.prefix(5) {
            warnings.append("Unknown entity “&\(name);” was left unchanged.")
        }
        if unknown.count > 5 {
            warnings.append("…and \(unknown.count - 5) more unknown entities.")
        }
        return (String(result), warnings)
    }

    /// `&#123;` or `&#x1F600;` starting at `start`. `scalar` is `nil` for 0,
    /// surrogates, and values above U+10FFFF.
    static func numericReference(in scalars: [Unicode.Scalar], at start: Int) -> (scalar: Unicode.Scalar?, end: Int, spelling: String)? {
        var index = start + 1
        guard index < scalars.count, scalars[index] == "#" else { return nil }
        index += 1
        var radix: UInt32 = 10
        if index < scalars.count, scalars[index] == "x" || scalars[index] == "X" {
            radix = 16
            index += 1
        }
        let digitsStart = index
        var value: UInt32 = 0
        while index < scalars.count, index - digitsStart < maxReferenceLength, let digit = digitValue(scalars[index], radix: radix) {
            // Saturate above the Unicode range; the exact value no longer matters.
            value = value > 0x10FFFF ? value : value * radix + digit
            index += 1
        }
        guard index > digitsStart, index < scalars.count, scalars[index] == ";" else { return nil }
        let end = index + 1
        let spelling = String(String.UnicodeScalarView(scalars[start..<end]))
        let isValid = value != 0 && !(0xD800...0xDFFF).contains(value) && value <= 0x10FFFF
        return (isValid ? Unicode.Scalar(value) : nil, end, spelling)
    }

    /// `&name;` starting at `start`, where the name is 1–32 ASCII letters and digits.
    static func namedReference(in scalars: [Unicode.Scalar], at start: Int) -> (name: String, end: Int)? {
        var index = start + 1
        let nameStart = index
        while index < scalars.count, index - nameStart < maxReferenceLength, scalars[index].isASCII,
              scalars[index].properties.isAlphabetic || ("0"..."9").contains(scalars[index]) {
            index += 1
        }
        guard index > nameStart, index < scalars.count, scalars[index] == ";" else { return nil }
        return (String(String.UnicodeScalarView(scalars[nameStart..<index])), index + 1)
    }

    private static func digitValue(_ scalar: Unicode.Scalar, radix: UInt32) -> UInt32? {
        switch scalar {
        case "0"..."9": return scalar.value - 48
        case "a"..."f" where radix == 16: return scalar.value - 87
        case "A"..."F" where radix == 16: return scalar.value - 55
        default: return nil
        }
    }
}
