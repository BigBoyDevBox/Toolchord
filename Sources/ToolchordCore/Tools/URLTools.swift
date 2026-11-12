import Foundation

/// URL component encode/decode and lossless inspection of raw URL components.
public enum URLTools {
    public static let commands: [ToolCommand] = [
        ToolCommand(
            id: "url.encode", title: "Encode URL Component", summary: "Percent-encode reserved characters",
            group: .url, icon: .glyph("%"),
            aliases: ["url encode", "percent encode", "urlencode", "encodeuricomponent", "escape url"],
            copyNoun: "component", affinity: { $0.isPlainText && !$0.has(.multiline) ? 30 : 0 },
            evaluate: { evaluate($0, operation: .encode) }
        ),
        ToolCommand(
            id: "url.decode", title: "Decode URL Component", summary: "Decode percent escapes once",
            group: .url, icon: .glyph("%"),
            aliases: ["url decode", "percent decode", "urldecode", "decodeuricomponent", "unescape url"],
            copyNoun: "component", affinity: { $0.has(.percentEncoded) ? 90 : ($0.has(.url) ? 35 : 0) },
            evaluate: { evaluate($0, operation: .decode) }
        ),
        ToolCommand(
            id: "url.inspect", title: "Inspect URL", summary: "Components and query parameters",
            group: .url, icon: .symbol("link"),
            aliases: ["parse url", "url parser", "query string", "query parameters", "inspect query", "url params"],
            options: [.choice("mode", "Plus sign", [.init("uri", "Keep +"), .init("form", "+ is space")], default: "uri")],
            copyNoun: "parameters", affinity: { $0.has(.url) ? 95 : ($0.has(.queryString) ? 90 : 0) },
            evaluate: { evaluate($0, operation: .inspect) }
        ),
    ]

    enum Operation { case encode, decode, inspect }
    struct Failure: Error { let result: ToolResult }
    static let hex = Array("0123456789ABCDEF".utf8)

    static func evaluate(_ request: ToolRequest, operation: Operation) -> ToolResult {
        guard let text = request.input.text else { return .needsInput("Paste text to inspect.") }
        do {
            try checkCancellation(request)
            let bytes = Array(text.utf8)
            switch operation {
            case .encode:
                var output = [UInt8]()
                for (index, byte) in bytes.enumerated() {
                    if index % 4096 == 0 { try checkCancellation(request) }
                    if isLetter(byte) || (48...57).contains(byte) || [45, 46, 95, 126].contains(byte) {
                        try append([byte], to: &output, request: request)
                    } else {
                        try append([37, hex[Int(byte >> 4)], hex[Int(byte & 15)]], to: &output, request: request)
                    }
                }
                return .success(ToolOutput(primaryText: String(decoding: output, as: UTF8.self), status: "Encoded"))
            case .decode:
                let decoded = try decode(bytes, range: bytes.indices, form: false, request: request)
                return .success(ToolOutput(primaryText: decoded, status: "Decoded"))
            case .inspect:
                return try inspect(text, bytes: bytes, request: request)
            }
        } catch let failure as Failure {
            return failure.result
        } catch {
            return .invalid(ToolDiagnostic("Unable to process URL text."))
        }
    }

    static func checkCancellation(_ request: ToolRequest) throws {
        if request.cancellation.isCancelled { throw Failure(result: .cancelled) }
    }

    static func append<C: Collection>(_ bytes: C, to output: inout [UInt8], request: ToolRequest) throws where C.Element == UInt8 {
        guard bytes.count <= request.limits.maxOutputBytes - output.count else {
            throw Failure(result: .tooLarge(request.limits.outputLimitMessage))
        }
        output.append(contentsOf: bytes)
    }

    static func isLetter(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) }
    static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: byte - 48
        case 65...70: byte - 55
        case 97...102: byte - 87
        default: nil
        }
    }

    static func decode(_ bytes: [UInt8], range: Range<Int>, form: Bool, request: ToolRequest) throws -> String {
        var output = [UInt8]()
        var index = range.lowerBound
        var checkedAt = index
        while index < range.upperBound {
            if index - checkedAt >= 4096 { try checkCancellation(request); checkedAt = index }
            let byte = bytes[index]
            if byte == 37 {
                guard index + 2 < range.upperBound,
                      let high = hexValue(bytes[index + 1]), let low = hexValue(bytes[index + 2]) else {
                    // The diagnostic quotes up to two Unicode scalars, not two UTF-8 bytes.
                    let tail = String(decoding: bytes[(index + 1)..<range.upperBound], as: UTF8.self)
                    let fragment = "%" + String(tail.unicodeScalars.prefix(2))
                    throw Failure(result: .invalid(ToolDiagnostic(
                        "Invalid percent escape “\(fragment)”.", at: TextLocator.location(ofUTF8Offset: index, in: bytes)
                    )))
                }
                try append([high * 16 + low], to: &output, request: request)
                index += 3
            } else {
                try append([form && byte == 43 ? 32 : byte], to: &output, request: request)
                index += 1
            }
        }
        guard let text = String(bytes: output, encoding: .utf8) else {
            throw Failure(result: .invalid(ToolDiagnostic("Decoded bytes are not UTF-8 text.")))
        }
        return text
    }

    static func inspect(_ text: String, bytes: [UInt8], request: ToolRequest) throws -> ToolResult {
        let scalars = text.unicodeScalars
        var start = scalars.startIndex
        var end = scalars.endIndex
        var trimmed = 0
        while start < end, CharacterSet.whitespacesAndNewlines.contains(scalars[start]) {
            start = scalars.index(after: start)
            trimmed += 1
            if trimmed % 4096 == 0 { try checkCancellation(request) }
        }
        while start < end {
            let previous = scalars.index(before: end)
            guard CharacterSet.whitespacesAndNewlines.contains(scalars[previous]) else { break }
            end = previous
            trimmed += 1
            if trimmed % 4096 == 0 { try checkCancellation(request) }
        }
        let lower = text.utf8.distance(from: text.utf8.startIndex, to: start)
        let upper = text.utf8.distance(from: text.utf8.startIndex, to: end)
        var fragment: Int?
        var question: Int?
        var firstPairMarker: Int?
        for index in lower..<upper {
            if (index - lower) % 4096 == 0 { try checkCancellation(request) }
            if bytes[index] == 35, fragment == nil { fragment = index }
            if bytes[index] == 63, question == nil, fragment == nil { question = index }
            if bytes[index] == 61 || bytes[index] == 38, firstPairMarker == nil, fragment == nil { firstPairMarker = index }
        }
        let contentEnd = fragment ?? upper
        var schemeEnd = lower
        if lower < upper, isLetter(bytes[lower]) {
            schemeEnd += 1
            while schemeEnd < upper {
                let byte = bytes[schemeEnd]
                guard isLetter(byte) || (48...57).contains(byte) || [43, 45, 46].contains(byte) else { break }
                if (schemeEnd - lower) % 4096 == 0 { try checkCancellation(request) }
                schemeEnd += 1
            }
        }
        // RFC 3986 §3: a URI is `scheme ":" hier-part`, and the "//" authority
        // is optional (mailto:, data:, file:/path). A one-letter scheme needs
        // "//", so drive paths such as "C:x" are not mistaken for URIs.
        let colonAfterScheme = schemeEnd > lower && schemeEnd < upper && bytes[schemeEnd] == 58
        let slashesFollow = schemeEnd + 2 < upper && bytes[schemeEnd + 1] == 47 && bytes[schemeEnd + 2] == 47
        let hasScheme = colonAfterScheme && (schemeEnd - lower >= 2 || slashesFollow)
        let fullURL = hasScheme && slashesFollow
        var fields = [ResultField]()
        func field(_ id: String, _ label: String, _ range: Range<Int>) {
            fields.append(ResultField(id: id, label: label, value: String(decoding: bytes[range], as: UTF8.self)))
        }
        if fullURL {
            field("scheme", "Scheme", lower..<schemeEnd)
            let authorityStart = schemeEnd + 3
            var authorityEnd = authorityStart
            var lastAt: Int?
            while authorityEnd < upper, ![47, 63, 35].contains(bytes[authorityEnd]) {
                if (authorityEnd - authorityStart) % 4096 == 0 { try checkCancellation(request) }
                if bytes[authorityEnd] == 64 { lastAt = authorityEnd }
                authorityEnd += 1
            }
            var hostStart = authorityStart
            if let lastAt {
                field("userinfo", "User info", authorityStart..<lastAt)
                hostStart = lastAt + 1
            }
            var colon: Int?
            var bracketed = false
            for index in hostStart..<authorityEnd {
                if (index - hostStart) % 4096 == 0 { try checkCancellation(request) }
                if bytes[index] == 91 { bracketed = true }
                if bytes[index] == 93 { bracketed = false }
                if bytes[index] == 58, !bracketed { colon = index }
            }
            var port: Int?
            if let colon, colon + 1 < authorityEnd {
                var digits = true
                for index in (colon + 1)..<authorityEnd {
                    if (index - colon) % 4096 == 0 { try checkCancellation(request) }
                    if !(48...57).contains(bytes[index]) { digits = false; break }
                }
                if digits { port = colon }
            }
            field("host", "Host", hostStart..<(port ?? authorityEnd))
            if let port { field("port", "Port", (port + 1)..<authorityEnd) }
            let pathEnd = question ?? contentEnd
            if authorityEnd < pathEnd, bytes[authorityEnd] == 47 {
                field("path", "Path", authorityEnd..<pathEnd)
            }
            if let fragment { field("fragment", "Fragment", (fragment + 1)..<upper) }
        } else if hasScheme {
            field("scheme", "Scheme", lower..<schemeEnd)
            let pathStart = schemeEnd + 1
            let pathEnd = question ?? contentEnd
            if pathStart < pathEnd { field("path", "Path", pathStart..<pathEnd) }
            if let fragment { field("fragment", "Fragment", (fragment + 1)..<upper) }
        }
        // Without a scheme, text whose first "=" or "&" comes before any "?"
        // is already a raw query (so "q=what?yes" keeps its "?").
        let queryStart: Int?
        if hasScheme {
            queryStart = question.map { $0 + 1 }
        } else if let marker = firstPairMarker, question.map({ marker < $0 }) ?? true {
            queryStart = lower
        } else {
            queryStart = question.map { $0 + 1 }
        }
        var output = [UInt8]()
        try append([91], to: &output, request: request)
        var count = 0
        if let queryStart {
            var segmentStart = queryStart
            var equals: Int?
            for index in queryStart...contentEnd {
                if (index - queryStart) % 4096 == 0 { try checkCancellation(request) }
                if index < contentEnd, bytes[index] == 61, equals == nil { equals = index }
                if index == contentEnd || bytes[index] == 38 {
                    if segmentStart < index {
                        let form = request.options.choice("mode", default: "uri") == "form"
                        let name = try decode(bytes, range: segmentStart..<(equals ?? index), form: form, request: request)
                        let value = try decode(bytes, range: (equals.map { $0 + 1 } ?? index)..<index, form: form, request: request)
                        try append(Array((count == 0 ? "\n  {\"name\": " : ",\n  {\"name\": ").utf8), to: &output, request: request)
                        try appendJSON(name, to: &output, request: request)
                        try append(Array(", \"value\": ".utf8), to: &output, request: request)
                        try appendJSON(value, to: &output, request: request)
                        try append([125], to: &output, request: request)
                        fields.append(ResultField(id: "param-\(count)", label: name.isEmpty ? "(empty name)" : name, value: value))
                        count += 1
                    }
                    segmentStart = index + 1
                    equals = nil
                }
            }
        }
        try append(count == 0 ? [93] : [10, 93], to: &output, request: request)
        return .success(ToolOutput(
            primaryText: String(decoding: output, as: UTF8.self),
            status: count == 0 ? "No query parameters" : (count == 1 ? "1 parameter" : "\(count) parameters"),
            presentation: .fields, syntax: .json, fields: fields
        ))
    }

    static func appendJSON(_ text: String, to output: inout [UInt8], request: ToolRequest) throws {
        try append([34], to: &output, request: request)
        let bytes = Array(text.utf8)
        var index = 0
        while index < bytes.count {
            if index % 4096 == 0 { try checkCancellation(request) }
            let byte = bytes[index]
            // U+2028 and U+2029 (E2 80 A8 / E2 80 A9) are legal in JSON but
            // terminate lines in older JavaScript; escape them for safe pasting.
            if byte == 0xE2, index + 2 < bytes.count, bytes[index + 1] == 0x80, bytes[index + 2] == 0xA8 || bytes[index + 2] == 0xA9 {
                try append(Array((bytes[index + 2] == 0xA8 ? "\\u2028" : "\\u2029").utf8), to: &output, request: request)
                index += 3
                continue
            }
            index += 1
            let escaped: [UInt8]
            switch byte {
            case 34, 92: escaped = [92, byte]
            case 8: escaped = [92, 98]
            case 9: escaped = [92, 116]
            case 10: escaped = [92, 110]
            case 12: escaped = [92, 102]
            case 13: escaped = [92, 114]
            case 0...31: escaped = [92, 117, 48, 48, hex[Int(byte >> 4)], hex[Int(byte & 15)]]
            default: escaped = [byte]
            }
            try append(escaped, to: &output, request: request)
        }
        try append([34], to: &output, request: request)
    }
}
