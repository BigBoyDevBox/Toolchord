import Foundation

/// A lexical JSON processor: tokens retain their original UTF-8 spelling.
enum JSONText {
    enum Style: Sendable, Equatable { case original, minified, indented(String) }
    enum RootKind: Sendable, Equatable { case object, array, string, number, literal }
    struct Processed: Sendable, Equatable {
        var text: String
        var rootKind: RootKind
        var warnings: [String]
    }
    enum Failure: Error, Sendable, Equatable {
        case invalid(ToolDiagnostic)
        case tooLarge(String)
        case cancelled
    }

    static func process(_ text: String, style: Style, limits: ToolLimits = .standard,
                        cancellation: CancellationCheck = .never) -> Result<Processed, Failure> {
        do {
            var parser = JSONParser(bytes: Array(text.utf8), limits: limits, cancellation: cancellation)
            let root = try parser.parse()
            let output = try parser.render(text, style: style)
            return .success(Processed(text: output, rootKind: root, warnings: parser.warnings))
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(.invalid(ToolDiagnostic("Unable to process JSON.")))
        }
    }

    static func quote(_ text: String, includeQuotes: Bool = true) -> String {
        // This convenience API has no limit or cancellation failure path.
        // Commands use the bounded codec directly.
        (try? JSONStringCodec.quote(text, includeQuotes: includeQuotes,
                                   limits: ToolLimits(maxOutputBytes: .max), cancellation: .never)) ?? ""
    }
}

struct JSONByteOutput {
    var bytes: [UInt8] = []
    let limits: ToolLimits

    mutating func append<C: Collection>(_ value: C) throws where C.Element == UInt8 {
        guard value.count <= limits.maxOutputBytes - bytes.count else {
            throw JSONText.Failure.tooLarge(limits.outputLimitMessage)
        }
        bytes.append(contentsOf: value)
    }

    mutating func append(_ text: String) throws { try append(text.utf8) }
    var text: String { String(decoding: bytes, as: UTF8.self) }
}

struct JSONParser {
    let bytes: [UInt8]
    let limits: ToolLimits
    let cancellation: CancellationCheck
    var index = 0
    var nextCancellationCheck = 0
    var tokens: [Range<Int>] = []
    var warnings: [String] = []
    var duplicateCount = 0

    mutating func checkpoint() throws {
        if index >= nextCancellationCheck {
            if cancellation.isCancelled { throw JSONText.Failure.cancelled }
            nextCancellationCheck = index + 4096
        }
    }

    func invalid(_ message: String, at offset: Int) -> JSONText.Failure {
        .invalid(ToolDiagnostic(message, at: TextLocator.location(ofUTF8Offset: offset, in: bytes)))
    }

    static func whitespace(_ byte: UInt8) -> Bool { byte == 32 || byte == 9 || byte == 10 || byte == 13 }
    static func digit(_ byte: UInt8) -> Bool { byte >= 48 && byte <= 57 }
    static func letter(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) }

    mutating func skipWhitespace() throws {
        while index < bytes.count, Self.whitespace(bytes[index]) {
            try checkpoint()
            index += 1
        }
        try checkpoint()
        if index + 1 < bytes.count, bytes[index] == 47, bytes[index + 1] == 47 || bytes[index + 1] == 42 {
            throw invalid("Comments aren’t allowed in JSON.", at: index)
        }
    }

    struct Frame {
        enum State { case first, afterComma(Int), commaOrEnd }
        let object: Bool
        var state: State = .first
        // Code units avoid Swift String's canonical-equivalence comparison
        // and preserve syntactically valid lone surrogate escapes.
        var names = Set<[UInt16]>()
        var closer: UInt8 { object ? 125 : 93 }
    }

    mutating func parse() throws -> JSONText.RootKind {
        try checkpoint()
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            throw invalid("Remove the byte order mark (U+FEFF) at the start of the input.", at: 0)
        }
        let root = try value(depth: 0, closer: nil)
        var frames: [Frame] = []
        if root == .object || root == .array { frames.append(Frame(object: root == .object)) }
        // Keep nesting on the heap: even the allowed 128 levels can exceed
        // the small stack available on a Swift concurrency worker thread.
        while !frames.isEmpty {
            try skipWhitespace()
            let frameIndex = frames.count - 1
            let object = frames[frameIndex].object
            let closer = frames[frameIndex].closer
            guard index < bytes.count else { throw unclosed(closer) }
            switch frames[frameIndex].state {
            case .commaOrEnd:
                if bytes[index] == closer {
                    punctuation()
                    frames.removeLast()
                } else {
                    guard bytes[index] == 44 else {
                        throw invalid("Expected “,” or “\(object ? "}" : "]")”.", at: index)
                    }
                    frames[frameIndex].state = .afterComma(index)
                    punctuation()
                }
            case .first, .afterComma:
                if bytes[index] == closer {
                    if case .afterComma(let comma) = frames[frameIndex].state {
                        throw invalid("Remove the trailing comma before “\(object ? "}" : "]")”.", at: comma)
                    }
                    punctuation()
                    frames.removeLast()
                    continue
                }
                if object {
                    guard bytes[index] == 34 else {
                        throw invalid(bytes[index] == 39 ? "Use double quotes for JSON strings." : "Member names must be double-quoted strings.", at: index)
                    }
                    let nameStart = index
                    let name = try string(decodeName: true)
                    if !frames[frameIndex].names.insert(name).inserted {
                        duplicateCount += 1
                        if duplicateCount <= 5 {
                            let location = TextLocator.location(ofUTF8Offset: nameStart, in: bytes)
                            warnings.append("Duplicate member name “\(String(decoding: name, as: UTF16.self))” at line \(location.line), column \(location.column). Some parsers keep only the last value.")
                        }
                    }
                    try skipWhitespace()
                    guard index < bytes.count, bytes[index] == 58 else {
                        throw invalid("Expected “:” after the member name.", at: index)
                    }
                    punctuation()
                }
                frames[frameIndex].state = .commaOrEnd
                let kind = try value(depth: frames.count, closer: closer)
                if kind == .object || kind == .array { frames.append(Frame(object: kind == .object)) }
            }
        }
        try skipWhitespace()
        guard index == bytes.count else { throw invalid("Unexpected text after the JSON value.", at: index) }
        if duplicateCount > 5 { warnings.append("…and \(duplicateCount - 5) more duplicate member names.") }
        return root
    }

    mutating func punctuation() {
        tokens.append(index..<(index + 1))
        index += 1
    }

    mutating func value(depth: Int, closer: UInt8?) throws -> JSONText.RootKind {
        try skipWhitespace()
        guard index < bytes.count else {
            if let closer { throw unclosed(closer) }
            throw invalid("Expected a JSON value.", at: index)
        }
        let start = index
        switch bytes[index] {
        case 123, 91:
            let object = bytes[index] == 123
            guard depth < limits.maxNestingDepth else { throw JSONText.Failure.tooLarge(limits.nestingLimitMessage) }
            punctuation()
            return object ? .object : .array
        case 34:
            _ = try string(decodeName: false)
            return .string
        case 39: throw invalid("Use double quotes for JSON strings.", at: index)
        case 43: throw invalid("Numbers can’t start with “+”.", at: index)
        case 46: throw invalid("Expected a digit before “.”.", at: index)
        case 45 where bytes[index...].starts(with: Array("-Infinity".utf8)):
            throw invalid("“-Infinity” isn’t valid JSON. Use null or a string.", at: index)
        case 45, 48...57:
            try number()
            return .number
        case let byte where Self.letter(byte):
            while index < bytes.count, Self.letter(bytes[index]) {
                try checkpoint()
                index += 1
            }
            let word = String(decoding: bytes[start..<index], as: UTF8.self)
            if word == "NaN" || word == "Infinity" {
                throw invalid("“\(word)” isn’t valid JSON. Use null or a string.", at: start)
            }
            guard word == "true" || word == "false" || word == "null" else {
                throw invalid("Invalid literal. Use true, false, or null.", at: start)
            }
            tokens.append(start..<index)
            return .literal
        default:
            let scalar = String(decoding: bytes[index...].prefix(4), as: UTF8.self).unicodeScalars.first!
            throw invalid("Expected a value, found “\(scalar)”.", at: index)
        }
    }

    func unclosed(_ closer: UInt8) -> JSONText.Failure {
        invalid("Expected “\(closer == 125 ? "}" : "]")” before the end of the input.", at: bytes.count)
    }

    mutating func number() throws {
        let start = index
        if bytes[index] == 45 { index += 1 }
        guard index < bytes.count, Self.digit(bytes[index]) else {
            throw invalid("Expected a JSON value.", at: index)
        }
        let firstDigit = index
        if bytes[index] == 48 {
            index += 1
            if index < bytes.count, Self.digit(bytes[index]) {
                throw invalid("Numbers can’t have leading zeros.", at: firstDigit)
            }
        } else {
            while index < bytes.count, Self.digit(bytes[index]) { try checkpoint(); index += 1 }
        }
        if index < bytes.count, bytes[index] == 46 {
            let dot = index
            index += 1
            guard index < bytes.count, Self.digit(bytes[index]) else {
                throw invalid("Expected a digit after “.”.", at: dot)
            }
            while index < bytes.count, Self.digit(bytes[index]) { try checkpoint(); index += 1 }
        }
        if index < bytes.count, bytes[index] == 101 || bytes[index] == 69 {
            index += 1
            if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 { index += 1 }
            guard index < bytes.count, Self.digit(bytes[index]) else {
                throw invalid("Expected a digit in the exponent.", at: index)
            }
            while index < bytes.count, Self.digit(bytes[index]) { try checkpoint(); index += 1 }
        }
        tokens.append(start..<index)
    }

    mutating func string(decodeName: Bool) throws -> [UInt16] {
        let start = index
        index += 1
        var rawStart = index
        var name: [UInt16] = []
        while index < bytes.count {
            try checkpoint()
            let byte = bytes[index]
            if byte == 34 {
                if decodeName { name.append(contentsOf: String(decoding: bytes[rawStart..<index], as: UTF8.self).utf16) }
                index += 1
                tokens.append(start..<index)
                return name
            }
            if byte < 32 {
                throw invalid(String(format: "Escape control character U+%04X in this string.", Int(byte)), at: index)
            }
            if byte == 92 {
                if decodeName { name.append(contentsOf: String(decoding: bytes[rawStart..<index], as: UTF8.self).utf16) }
                let escape = index
                index += 1
                guard index < bytes.count else { throw invalid("Unterminated string.", at: start) }
                if bytes[index] == 117 {
                    let unit = try JSONStringCodec.hexUnit(bytes, at: escape, end: bytes.count)
                    if decodeName { name.append(unit) }
                    index += 5
                } else if let decoded = JSONStringCodec.simpleEscape(bytes[index]) {
                    if decodeName { name.append(UInt16(decoded)) }
                    index += 1
                } else {
                    throw JSONStringCodec.invalidEscape(bytes, at: escape)
                }
                rawStart = index
            } else {
                index += 1
            }
        }
        throw invalid("Unterminated string.", at: start)
    }

    func render(_ original: String, style: JSONText.Style) throws -> String {
        if cancellation.isCancelled { throw JSONText.Failure.cancelled }
        if style == .original {
            guard bytes.count <= limits.maxOutputBytes else { throw JSONText.Failure.tooLarge(limits.outputLimitMessage) }
            return original
        }
        var output = JSONByteOutput(limits: limits)
        let indent: String
        if case .indented(let value) = style { indent = value } else { indent = "" }
        let pretty: Bool
        if case .indented = style { pretty = true } else { pretty = false }
        var depth = 0
        for (position, token) in tokens.enumerated() {
            if position % 2048 == 0, cancellation.isCancelled { throw JSONText.Failure.cancelled }
            let byte = bytes[token.lowerBound]
            if pretty, byte == 125 || byte == 93 {
                depth -= 1
                let previous = bytes[tokens[position - 1].lowerBound]
                if previous != 123 && previous != 91 {
                    try output.append("\n")
                    for _ in 0..<depth { try output.append(indent) }
                }
            }
            try output.append(bytes[token])
            if pretty {
                if byte == 123 || byte == 91 {
                    depth += 1
                    let next = bytes[tokens[position + 1].lowerBound]
                    if next != 125 && next != 93 {
                        try output.append("\n")
                        for _ in 0..<depth { try output.append(indent) }
                    }
                } else if byte == 44 {
                    try output.append("\n")
                    for _ in 0..<depth { try output.append(indent) }
                } else if byte == 58 {
                    try output.append(" ")
                }
            }
        }
        return output.text
    }
}
