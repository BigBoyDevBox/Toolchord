import Foundation

/// Cheap lexical checks for Markdown and HTML. Like the rest of detection,
/// they only order suggestions: the converters accept any text. Both scan a
/// bounded prefix in linear time.
enum MarkupDetector {
    // MARK: - HTML

    /// HTML element names. For text that starts with markup the first element
    /// decides, so XML vocabularies that share a name with HTML (RSS and Atom
    /// reuse `title`, `link`, and `summary`) still read as XML. Names that
    /// are common XML roots (`data`, `map`, `menu`, `object`, `source`,
    /// `template`) and standalone `svg` and `math` documents are left out.
    static let htmlElementNames: Set<String> = [
        "a", "abbr", "address", "area", "article", "aside", "audio", "b", "base", "bdi", "bdo", "blockquote",
        "body", "br", "button", "canvas", "caption", "center", "cite", "code", "col", "colgroup", "datalist",
        "dd", "del", "details", "dfn", "dialog", "div", "dl", "dt", "em", "embed", "fieldset", "figcaption",
        "figure", "font", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hgroup",
        "hr", "html", "i", "iframe", "img", "input", "ins", "kbd", "label", "legend", "li", "link", "main",
        "mark", "meta", "meter", "nav", "noscript", "ol", "optgroup", "option", "p", "picture", "pre",
        "progress", "q", "rp", "rt", "ruby", "s", "samp", "script", "search", "section", "select", "slot",
        "small", "span", "strong", "style", "sub", "summary", "sup", "table", "tbody", "td", "textarea",
        "tfoot", "th", "thead", "time", "title", "tr", "track", "u", "ul", "var", "video", "wbr",
    ]

    /// HTML when the text has `<!DOCTYPE html>`, starts with an HTML element,
    /// or — for text that doesn't start with markup and isn't Markdown —
    /// contains at least two HTML tags.
    static func isHTML(_ sample: Substring, startsWithMarkup: Bool, isMarkdown: Bool) -> Bool {
        if !startsWithMarkup && isMarkdown { return false }
        let bytes = Array(sample.utf8)
        var tagCount = 0
        var index = 0
        while index < bytes.count {
            guard bytes[index] == ascii("<"), index + 1 < bytes.count else {
                index += 1
                continue
            }
            let next = index + 1
            if bytes[next] == ascii("!") || bytes[next] == ascii("?") {
                if bytes[next] == ascii("!"), hasDoctypeHTML(bytes, at: next + 1) { return true }
                // Skip comments, declarations, and processing instructions
                // whole, so markup inside a comment never counts.
                let isComment = next + 2 < bytes.count && bytes[next + 1] == ascii("-") && bytes[next + 2] == ascii("-")
                index = isComment ? end(of: "-->", in: bytes, from: next + 3) : end(of: ">", in: bytes, from: next + 1)
                continue
            }
            let isEndTag = bytes[next] == ascii("/")
            let nameStart = isEndTag ? next + 1 : next
            guard nameStart < bytes.count, isLetter(bytes[nameStart]) else {
                index = next
                continue
            }
            var nameEnd = nameStart
            while nameEnd < bytes.count, nameEnd - nameStart <= 32, isLetter(bytes[nameEnd]) || isDigit(bytes[nameEnd]) || bytes[nameEnd] == ascii("-") {
                nameEnd += 1
            }
            if nameEnd < bytes.count, !(isSpace(bytes[nameEnd]) || bytes[nameEnd] == ascii(">") || bytes[nameEnd] == ascii("/")) {
                index = nameEnd
                continue
            }
            let name = String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self).lowercased()
            let isHTMLName = htmlElementNames.contains(name)
            if startsWithMarkup && !isEndTag { return isHTMLName }
            if isHTMLName {
                tagCount += 1
                if tagCount >= 2 { return true }
            }
            index = nameEnd
        }
        return false
    }

    /// The index just past the first `terminator` at or after `start`, or the end.
    private static func end(of terminator: String, in bytes: [UInt8], from start: Int) -> Int {
        let pattern = Array(terminator.utf8)
        var index = start
        while index + pattern.count <= bytes.count {
            if bytes[index] == pattern[0], bytes[index..<(index + pattern.count)].elementsEqual(pattern) {
                return index + pattern.count
            }
            index += 1
        }
        return bytes.count
    }

    /// `doctype` (any case), whitespace, then `html` followed by whitespace, `>`, or the end.
    private static func hasDoctypeHTML(_ bytes: [UInt8], at start: Int) -> Bool {
        var index = start
        for expected in "doctype".utf8 {
            guard index < bytes.count, lowercase(bytes[index]) == expected else { return false }
            index += 1
        }
        let whitespaceStart = index
        while index < bytes.count, isSpace(bytes[index]) { index += 1 }
        guard index > whitespaceStart else { return false }
        for expected in "html".utf8 {
            guard index < bytes.count, lowercase(bytes[index]) == expected else { return false }
            index += 1
        }
        return index == bytes.count || isSpace(bytes[index]) || bytes[index] == ascii(">")
    }

    // MARK: - Markdown

    /// Markdown constructs, weighted by how rarely they appear in other text.
    /// Text is Markdown when the distinct constructs found add up to at least
    /// ``markdownThreshold``: a fence, an inline link, or a table alone; a
    /// heading or bold text with one more construct; or three weak ones.
    private enum Signal: Int, CaseIterable {
        case fence, link, table, heading, bold, reference, list, quote, code, emphasis, rule

        var weight: Int {
            switch self {
            case .fence, .link, .table: 3
            case .heading, .bold, .reference: 2
            case .list, .quote, .code, .emphasis, .rule: 1
            }
        }
    }

    static let markdownThreshold = 3

    static func isMarkdown(_ sample: Substring) -> Bool {
        let bytes = Array(sample.utf8)
        var found = [Bool](repeating: false, count: Signal.allCases.count)
        var score = 0
        func note(_ signal: Signal) {
            guard !found[signal.rawValue] else { return }
            found[signal.rawValue] = true
            score += signal.weight
        }

        var lines: [Range<Int>] = []
        var lineStart = 0
        var index = 0
        while index < bytes.count {
            if bytes[index] == 0x0A || bytes[index] == 0x0D {
                lines.append(lineStart..<index)
                if bytes[index] == 0x0D, index + 1 < bytes.count, bytes[index + 1] == 0x0A { index += 1 }
                lineStart = index + 1
            }
            index += 1
        }
        lines.append(lineStart..<bytes.count)

        func isBlank(_ lineIndex: Int) -> Bool {
            lineIndex >= lines.count || lines[lineIndex].allSatisfy { isSpace(bytes[$0]) }
        }

        for (number, line) in lines.enumerated() {
            var contentStart = line.lowerBound
            var indent = 0
            while contentStart < line.upperBound, bytes[contentStart] == ascii(" ") || bytes[contentStart] == 0x09 {
                indent += bytes[contentStart] == 0x09 ? 4 : 1
                contentStart += 1
            }
            let content = contentStart..<line.upperBound
            guard !content.isEmpty else { continue }

            if indent <= 3 {
                if isHeading(bytes, content) && isBlank(number + 1) { note(.heading) }
                if startsWith(bytes, content, "```") || startsWith(bytes, content, "~~~") { note(.fence) }
                if bytes[content.lowerBound] == ascii(">") { note(.quote) }
                if isRule(bytes, content) { note(.rule) }
                if isReferenceDefinition(bytes, content) { note(.reference) }
                if number > 0, isTableDelimiter(bytes, content), lines[number - 1].contains(where: { bytes[$0] == ascii("|") }) {
                    note(.table)
                }
            }
            if isListItem(bytes, content) { note(.list) }
            if hasInlineLink(bytes, content) { note(.link) }
            if hasCodeSpan(bytes, content) { note(.code) }
            // Only `*`: underscores are far more common in code (`snake_case`,
            // `__init__`) than as Markdown emphasis.
            if hasDelimited(bytes, content, ascii("*"), count: 2) { note(.bold) }
            if hasDelimited(bytes, content, ascii("*"), count: 1) { note(.emphasis) }
            if score >= markdownThreshold { return true }
        }
        return false
    }

    /// `#` to `######`, a space or tab, then text.
    private static func isHeading(_ bytes: [UInt8], _ range: Range<Int>) -> Bool {
        var index = range.lowerBound
        while index < range.upperBound, bytes[index] == ascii("#") { index += 1 }
        let level = index - range.lowerBound
        guard (1...6).contains(level), index < range.upperBound, isSpace(bytes[index]) else { return false }
        return bytes[index..<range.upperBound].contains { !isSpace($0) }
    }

    /// Three or more `-`, `*`, `_`, or `=` with optional spaces: a thematic
    /// break or a setext heading underline.
    private static func isRule(_ bytes: [UInt8], _ range: Range<Int>) -> Bool {
        let marker = bytes[range.lowerBound]
        guard [ascii("-"), ascii("*"), ascii("_"), ascii("=")].contains(marker) else { return false }
        var count = 0
        for index in range {
            if bytes[index] == marker {
                count += 1
            } else if !isSpace(bytes[index]) {
                return false
            }
        }
        return count >= 3
    }

    /// `[label]: destination`.
    private static func isReferenceDefinition(_ bytes: [UInt8], _ range: Range<Int>) -> Bool {
        guard bytes[range.lowerBound] == ascii("[") else { return false }
        var index = range.lowerBound + 1
        while index < range.upperBound, bytes[index] != ascii("]") {
            if bytes[index] == ascii("[") { return false }
            index += 1
        }
        guard index > range.lowerBound + 1, index + 1 < range.upperBound, bytes[index + 1] == ascii(":") else { return false }
        return bytes[(index + 2)..<range.upperBound].contains { !isSpace($0) }
    }

    /// A GitHub table delimiter row such as `|---|:--:|`.
    private static func isTableDelimiter(_ bytes: [UInt8], _ range: Range<Int>) -> Bool {
        var hasPipe = false
        var hasDash = false
        for index in range {
            switch bytes[index] {
            case ascii("|"): hasPipe = true
            case ascii("-"): hasDash = true
            case ascii(":"), ascii(" "), 0x09: break
            default: return false
            }
        }
        return hasPipe && hasDash
    }

    /// `- item`, `* item`, `+ item`, `1. item`, or `1) item`.
    private static func isListItem(_ bytes: [UInt8], _ range: Range<Int>) -> Bool {
        var index = range.lowerBound
        if [ascii("-"), ascii("*"), ascii("+")].contains(bytes[index]) {
            index += 1
        } else {
            while index < range.upperBound, index - range.lowerBound < 9, isDigit(bytes[index]) { index += 1 }
            guard index > range.lowerBound, index < range.upperBound, bytes[index] == ascii(".") || bytes[index] == ascii(")") else {
                return false
            }
            index += 1
        }
        guard index < range.upperBound, isSpace(bytes[index]) else { return false }
        return bytes[index..<range.upperBound].contains { !isSpace($0) }
    }

    /// `[text](destination)` or `![alt](source)`, where `[` doesn't follow a
    /// name or a closing bracket (so `items[0](x)` in code doesn't count).
    private static func hasInlineLink(_ bytes: [UInt8], _ range: Range<Int>) -> Bool {
        var openBracket: Int?
        var destinationStart: Int?
        for index in range {
            let byte = bytes[index]
            if let start = destinationStart {
                if byte == ascii(")") && index > start { return true }
                continue
            }
            if byte == ascii("[") {
                let previous = index > range.lowerBound ? bytes[index - 1] : ascii(" ")
                let followsName = isLetter(previous) || isDigit(previous) || previous == ascii("_") || previous == ascii(")") || previous == ascii("]")
                openBracket = followsName ? nil : index
            } else if byte == ascii("]"), let open = openBracket {
                if index + 1 < range.upperBound, bytes[index + 1] == ascii("("), index > open + 1 || (open > range.lowerBound && bytes[open - 1] == ascii("!")) {
                    destinationStart = index + 2
                }
                openBracket = nil
            }
        }
        return false
    }

    /// A code span: a run of backticks, some text, and a later run of the
    /// same length. Openers are remembered per length, so ``` ``a ` b`` ```
    /// still counts.
    private static func hasCodeSpan(_ bytes: [UInt8], _ range: Range<Int>) -> Bool {
        var openers = Set<Int>()
        var index = range.lowerBound
        while index < range.upperBound {
            guard bytes[index] == ascii("`") else {
                index += 1
                continue
            }
            let start = index
            while index < range.upperBound, bytes[index] == ascii("`") { index += 1 }
            let length = index - start
            // A closer must follow its opener with text in between; runs are
            // separated by at least one other byte, so any earlier opener of
            // the same length qualifies.
            if openers.contains(length) { return true }
            openers.insert(length)
        }
        return false
    }

    /// A run of exactly `count` `marker` characters that can open emphasis
    /// (after a boundary, before text) followed later by one that can close
    /// it (after text, before a boundary). Requiring word boundaries keeps
    /// `a**2 + b**2` and `int *p = *q` from counting.
    private static func hasDelimited(_ bytes: [UInt8], _ range: Range<Int>, _ marker: UInt8, count: Int) -> Bool {
        var isOpen = false
        var index = range.lowerBound
        while index < range.upperBound {
            guard bytes[index] == marker else {
                index += 1
                continue
            }
            let start = index
            while index < range.upperBound, bytes[index] == marker { index += 1 }
            guard index - start == count else { continue }
            let before = start > range.lowerBound ? bytes[start - 1] : ascii(" ")
            let after = index < range.upperBound ? bytes[index] : ascii(" ")
            if isOpen, !isSpace(before), isBoundary(after) {
                return true
            }
            if isBoundary(before), !isSpace(after) {
                isOpen = true
            }
        }
        return false
    }

    // MARK: - Bytes

    private static func ascii(_ character: Unicode.Scalar) -> UInt8 { UInt8(character.value) }

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0C
    }

    private static func isLetter(_ byte: UInt8) -> Bool {
        (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
    }

    private static func isDigit(_ byte: UInt8) -> Bool { (0x30...0x39).contains(byte) }

    /// Whitespace or ASCII punctuation: where emphasis may start or end.
    /// Non-ASCII bytes count as word characters.
    private static func isBoundary(_ byte: UInt8) -> Bool {
        isSpace(byte) || (byte < 0x80 && !isLetter(byte) && !isDigit(byte))
    }

    private static func lowercase(_ byte: UInt8) -> UInt8 { isLetter(byte) ? byte | 0x20 : byte }

    private static func startsWith(_ bytes: [UInt8], _ range: Range<Int>, _ prefix: String) -> Bool {
        let prefixBytes = Array(prefix.utf8)
        guard range.count >= prefixBytes.count else { return false }
        return bytes[range.lowerBound..<(range.lowerBound + prefixBytes.count)].elementsEqual(prefixBytes)
    }
}
