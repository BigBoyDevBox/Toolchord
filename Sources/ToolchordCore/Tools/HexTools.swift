import Foundation

public enum HexTools {
    public static let commands: [ToolCommand] = [
        ToolCommand(id: "hex.encode", title: "Encode Text as Hex", summary: "UTF-8 bytes as hexadecimal",
            group: .hex, icon: .glyph("0x"), aliases: ["text to hex", "hex encode", "string to hex", "ascii to hex"],
            options: [.choice("separator", "Separator", [.init("none", "None"), .init("space", "Spaces")], default: "none")],
            copyNoun: "hex", evaluate: encode),
        ToolCommand(id: "hex.decode", title: "Decode Hex to Text", summary: "Hex bytes to UTF-8 text",
            group: .hex, icon: .glyph("0x"), aliases: ["hex to text", "hex decode", "hex to string", "hex to ascii"],
            copyNoun: "text", affinity: { $0.has(.hex) ? 70 : 0 }, evaluate: decode),
    ]

    static func encode(_ request: ToolRequest) -> ToolResult {
        guard let text = request.input.text else { return .needsInput("Paste text to encode.") }
        if request.cancellation.isCancelled { return .cancelled }
        let spaced = request.options.choice("separator", default: "none") == "space"
        let count = text.utf8.count
        let size = count * 2 + (spaced ? max(0, count - 1) : 0)
        guard size <= request.limits.maxOutputBytes else { return .tooLarge(request.limits.outputLimitMessage) }
        let digits = Array("0123456789abcdef".utf8)
        var output: [UInt8] = []
        output.reserveCapacity(size)
        for (index, byte) in text.utf8.enumerated() {
            if index % 4096 == 0, request.cancellation.isCancelled { return .cancelled }
            if spaced && index > 0 { output.append(32) }
            output.append(digits[Int(byte >> 4)])
            output.append(digits[Int(byte & 15)])
        }
        return .success(ToolOutput(primaryText: String(decoding: output, as: UTF8.self), status: ByteCountText.string(count)))
    }

    static func decode(_ request: ToolRequest) -> ToolResult {
        guard let text = request.input.text else { return .needsInput("Paste hex to decode.") }
        if request.cancellation.isCancelled { return .cancelled }
        // Trim with scalar indices so diagnostics always retain offsets into the original text.
        let scalars = text.unicodeScalars
        var start = scalars.startIndex
        var end = scalars.endIndex
        var trimmed = 0
        while start < end, CharacterSet.whitespacesAndNewlines.contains(scalars[start]) {
            if trimmed % 4096 == 0, request.cancellation.isCancelled { return .cancelled }
            scalars.formIndex(after: &start)
            trimmed += 1
        }
        while end > start {
            let previous = scalars.index(before: end)
            guard CharacterSet.whitespacesAndNewlines.contains(scalars[previous]) else { break }
            if trimmed % 4096 == 0, request.cancellation.isCancelled { return .cancelled }
            end = previous
            trimmed += 1
        }
        if start < end, scalars[start] == "0" {
            let next = scalars.index(after: start)
            if next < end, scalars[next] == "x" || scalars[next] == "X" { start = scalars.index(after: next) }
        }
        var bytes: [UInt8] = []
        var high: UInt8?
        var offset = text.utf8.distance(from: text.utf8.startIndex, to: start)
        var nextCheck = offset
        for scalar in scalars[start..<end] {
            if offset >= nextCheck {
                if request.cancellation.isCancelled { return .cancelled }
                nextCheck = offset + 4096
            }
            defer { offset += scalar.utf8.count }
            let n = scalar.value
            if n == 32 || n == 9 || n == 10 || n == 13 || n == 58 { continue }
            let digit: UInt8
            switch n {
            case 48...57: digit = UInt8(n - 48)
            case 65...70: digit = UInt8(n - 65 + 10)
            case 97...102: digit = UInt8(n - 97 + 10)
            default:
                return .invalid(ToolDiagnostic("Invalid hex digit “\(scalar)”.", at: TextLocator.location(ofUTF8Offset: offset, in: text)))
            }
            if let first = high {
                guard bytes.count < request.limits.maxOutputBytes else { return .tooLarge(request.limits.outputLimitMessage) }
                bytes.append(first << 4 | digit)
                high = nil
            } else { high = digit }
        }
        if high != nil {
            return .invalid(ToolDiagnostic("Hex text has an odd number of digits.", at: TextLocator.location(ofUTF8Offset: offset, in: text)))
        }
        guard let decoded = String(bytes: bytes, encoding: .utf8) else {
            return .invalid(ToolDiagnostic("Decoded bytes are not UTF-8 text."))
        }
        return .success(ToolOutput(primaryText: decoded, status: "Decoded · \(ByteCountText.string(bytes.count))"))
    }
}
