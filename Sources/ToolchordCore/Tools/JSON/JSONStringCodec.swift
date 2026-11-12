import Foundation

enum JSONStringCodec {
    static func simpleEscape(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 34, 47, 92: byte
        case 98: 8
        case 102: 12
        case 110: 10
        case 114: 13
        case 116: 9
        default: nil
        }
    }

    static func invalid(_ message: String, bytes: [UInt8], at offset: Int) -> JSONText.Failure {
        .invalid(ToolDiagnostic(message, at: TextLocator.location(ofUTF8Offset: offset, in: bytes)))
    }

    static func invalidEscape(_ bytes: [UInt8], at offset: Int) -> JSONText.Failure {
        let scalar = String(decoding: bytes.dropFirst(offset + 1).prefix(4), as: UTF8.self).unicodeScalars.first
        return invalid("Invalid escape “\\\(scalar.map(String.init) ?? "")”.", bytes: bytes, at: offset)
    }

    static func hexUnit(_ bytes: [UInt8], at offset: Int, end: Int) throws -> UInt16 {
        guard offset + 6 <= end else {
            throw invalid("Expected four hex digits after “\\u”.", bytes: bytes, at: offset)
        }
        var result: UInt16 = 0
        for byte in bytes[(offset + 2)..<(offset + 6)] {
            let digit: UInt16
            switch byte {
            case 48...57: digit = UInt16(byte - 48)
            case 65...70: digit = UInt16(byte - 65 + 10)
            case 97...102: digit = UInt16(byte - 97 + 10)
            default: throw invalid("Expected four hex digits after “\\u”.", bytes: bytes, at: offset)
            }
            result = result * 16 + digit
        }
        return result
    }

    static func quote(_ text: String, includeQuotes: Bool, limits: ToolLimits,
                      cancellation: CancellationCheck) throws -> String {
        let bytes = Array(text.utf8)
        var output = JSONByteOutput(limits: limits)
        if cancellation.isCancelled { throw JSONText.Failure.cancelled }
        if includeQuotes { try output.append("\"") }
        var index = 0
        var rawStart = 0
        var nextCheck = 0
        let hex = Array("0123456789abcdef".utf8)
        while index < bytes.count {
            if index >= nextCheck {
                if cancellation.isCancelled { throw JSONText.Failure.cancelled }
                try output.append(bytes[rawStart..<index])
                rawStart = index
                nextCheck = index + 4096
            }
            var escaped: [UInt8]?
            var consumed = 1
            switch bytes[index] {
            case 34: escaped = [92, 34]
            case 92: escaped = [92, 92]
            case 8: escaped = [92, 98]
            case 12: escaped = [92, 102]
            case 10: escaped = [92, 110]
            case 13: escaped = [92, 114]
            case 9: escaped = [92, 116]
            case 0...31: escaped = [92, 117, 48, 48, hex[Int(bytes[index] >> 4)], hex[Int(bytes[index] & 15)]]
            case 0xE2 where index + 2 < bytes.count && bytes[index + 1] == 0x80 && (bytes[index + 2] == 0xA8 || bytes[index + 2] == 0xA9):
                escaped = Array((bytes[index + 2] == 0xA8 ? "\\u2028" : "\\u2029").utf8)
                consumed = 3
            default: break
            }
            if let escaped {
                try output.append(bytes[rawStart..<index])
                try output.append(escaped)
                index += consumed
                rawStart = index
            } else {
                index += 1
            }
        }
        try output.append(bytes[rawStart..<index])
        if includeQuotes { try output.append("\"") }
        return output.text
    }

    static func unescape(_ text: String, limits: ToolLimits, cancellation: CancellationCheck) throws -> String {
        if cancellation.isCancelled { throw JSONText.Failure.cancelled }
        let bytes = Array(text.utf8)
        // Find trimmed bounds without losing offsets into the original input.
        var first = bytes.count
        var last = 0
        var offset = 0
        var nextCheck = 0
        for scalar in text.unicodeScalars {
            if offset >= nextCheck {
                if cancellation.isCancelled { throw JSONText.Failure.cancelled }
                nextCheck = offset + 4096
            }
            let length = scalar.value < 0x80 ? 1 : scalar.value < 0x800 ? 2 : scalar.value < 0x10000 ? 3 : 4
            if !CharacterSet.whitespacesAndNewlines.contains(scalar) {
                first = min(first, offset)
                last = offset + length
            }
            offset += length
        }
        let literal = last - first >= 2 && bytes[first] == 34 && bytes[last - 1] == 34
        var index = literal ? first + 1 : 0
        let end = literal ? last - 1 : bytes.count
        var rawStart = index
        nextCheck = index
        var output = JSONByteOutput(limits: limits)
        while index < end {
            if index >= nextCheck {
                if cancellation.isCancelled { throw JSONText.Failure.cancelled }
                try output.append(bytes[rawStart..<index])
                rawStart = index
                nextCheck = index + 4096
            }
            if literal, bytes[index] == 34 {
                throw invalid("Unescaped “\"” inside the string.", bytes: bytes, at: index)
            }
            if bytes[index] != 92 { index += 1; continue }
            try output.append(bytes[rawStart..<index])
            let escape = index
            guard index + 1 < end else { throw invalidEscape(bytes, at: escape) }
            let code = bytes[index + 1]
            if let decoded = simpleEscape(code) {
                try output.append([decoded])
                index += 2
            } else if code == 117 {
                let unit = try hexUnit(bytes, at: index, end: end)
                index += 6
                let scalar: Unicode.Scalar
                if (0xD800...0xDBFF).contains(unit) {
                    guard index + 6 <= end, bytes[index] == 92, bytes[index + 1] == 117 else {
                        throw unpaired(bytes, at: escape)
                    }
                    let low = try hexUnit(bytes, at: index, end: end)
                    guard (0xDC00...0xDFFF).contains(low) else { throw unpaired(bytes, at: escape) }
                    scalar = Unicode.Scalar(0x10000 + (UInt32(unit) - 0xD800) * 1024 + UInt32(low) - 0xDC00)!
                    index += 6
                } else if (0xDC00...0xDFFF).contains(unit) {
                    throw unpaired(bytes, at: escape)
                } else {
                    scalar = Unicode.Scalar(UInt32(unit))!
                }
                try output.append(String(scalar))
            } else {
                throw invalidEscape(bytes, at: escape)
            }
            rawStart = index
        }
        try output.append(bytes[rawStart..<end])
        return output.text
    }

    static func unpaired(_ bytes: [UInt8], at offset: Int) -> JSONText.Failure {
        let spelling = String(decoding: bytes[offset..<(offset + 6)], as: UTF8.self)
        return invalid("Unpaired surrogate “\(spelling)” can’t be decoded to text.", bytes: bytes, at: offset)
    }
}
