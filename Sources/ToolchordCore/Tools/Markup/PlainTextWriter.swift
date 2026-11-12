import Foundation

/// Shared deferred boundaries, prefixes, whitespace, and output accounting.
final class PlainTextWriter {
    struct Prefix { var text: String; var quote: Bool; var item = false }
    let request: ToolRequest
    var bytes: [UInt8] = []
    var prefixes: [Prefix] = []
    /// How many prefixes, from the outermost, are already written on the
    /// current line. Prefixes are always written outermost first, so a count
    /// keeps each character O(1) however deep the nesting.
    var emittedPrefixes = 0
    var pendingBoundary = 0
    var pendingEndings: [String] = []
    var preserveLeadingBreaks = false
    var pendingSpace = false
    var markerGap = false
    var lineContent = false
    var lineVerbatim = false
    var trailingBreaks = 0
    var ticks = 0
    var meaningfulEnd = 0
    var lastContentVerbatim = false
    /// The fewest prefixes in effect while a boundary was pending. Blank lines
    /// between blocks only repeat those quote prefixes, so a blank line before
    /// a nested quote reads `>`, not `> >`, and one before a top-level quote is empty.
    var boundaryPrefixFloor = Int.max

    init(request: ToolRequest) { self.request = request; bytes.reserveCapacity(min(4096, request.limits.maxOutputBytes)) }

    func check() throws {
        ticks += 1
        if ticks % 2048 == 0, request.cancellation.isCancelled { throw MarkupFailure.cancelled }
        if bytes.count > request.limits.maxOutputBytes { throw MarkupFailure.output }
    }

    func append(_ text: String) throws {
        guard text.utf8.count <= request.limits.maxOutputBytes - bytes.count else { throw MarkupFailure.output }
        bytes.append(contentsOf: text.utf8)
        try check()
    }

    func trimLine() {
        if !lineVerbatim { while bytes.last == 32 { bytes.removeLast() } }
        meaningfulEnd = min(meaningfulEnd, bytes.count)
    }

    func boundary(_ count: Int) {
        pendingSpace = false
        // Prefixes and an empty item marker do not constitute item content.
        if !lineContent && trailingBreaks == 0 && pendingEndings.isEmpty && !bytes.isEmpty { return }
        pendingBoundary = max(pendingBoundary, count)
        boundaryPrefixFloor = min(boundaryPrefixFloor, prefixes.count)
    }

    func newline(blank: Bool = false, ending: String = "\n", prefixLimit: Int = .max) throws {
        trimLine()
        if blank {
            for prefix in prefixes.prefix(prefixLimit) where prefix.quote { try append(prefix.text) }
            while bytes.last == 32 { bytes.removeLast() }
        }
        try append(ending)
        trailingBreaks += 1
        pendingSpace = false; markerGap = false; lineContent = false; lineVerbatim = false
        emittedPrefixes = 0
    }

    func prepare(flushMarkerGap: Bool = true) throws {
        let needed = max(pendingBoundary, trailingBreaks + pendingEndings.count)
        if needed > 0 {
            if !bytes.isEmpty || preserveLeadingBreaks {
                while trailingBreaks + pendingEndings.count < needed { pendingEndings.append("\n") }
                let floor = min(boundaryPrefixFloor, prefixes.count)
                for ending in pendingEndings { try newline(blank: trailingBreaks > 0, ending: ending, prefixLimit: floor) }
            }
            pendingBoundary = 0; pendingEndings.removeAll(keepingCapacity: true); preserveLeadingBreaks = false
            boundaryPrefixFloor = .max
        }
        if markerGap && flushMarkerGap { try append(" "); markerGap = false }
        while emittedPrefixes < prefixes.count {
            try append(prefixes[emittedPrefixes].text)
            emittedPrefixes += 1
        }
    }

    func pushQuote() { prefixes.append(Prefix(text: "> ", quote: true)) }
    func pushIndent(_ width: Int) { prefixes.append(Prefix(text: String(repeating: " ", count: width), quote: false)) }
    func popPrefix() {
        if let last = prefixes.popLast(), last.item { lineContent = true }
        emittedPrefixes = min(emittedPrefixes, prefixes.count)
    }

    func beginItem(_ marker: String) throws {
        try prepare()
        try append(String(marker.dropLast()))
        markerGap = true
        // The marker stands in for this item's indentation on its first line.
        prefixes.append(Prefix(text: String(repeating: " ", count: marker.unicodeScalars.count), quote: false, item: true))
        emittedPrefixes = prefixes.count
        trailingBreaks = 0
        meaningfulEnd = bytes.count; lastContentVerbatim = false
    }

    func deferBreak(_ ending: String, verbatim: Bool = false) throws {
        // Record discarded final breaks without consuming the output limit.
        while trailingBreaks + pendingEndings.count < pendingBoundary { pendingEndings.append("\n") }
        pendingEndings.append(ending)
        pendingBoundary = 0; pendingSpace = false; markerGap = false; lineContent = false
        preserveLeadingBreaks = preserveLeadingBreaks || verbatim
        try check()
    }

    func hardBreak() throws { try deferBreak("\n") }

    func write(_ text: String, verbatim: Bool = false, collapse: Bool = true) throws {
        let scalars = text.unicodeScalars
        var previousCR = false
        for scalar in scalars {
            try check()
            if verbatim {
                if scalar == "\n" && previousCR { pendingEndings[pendingEndings.count - 1] = "\r\n"; previousCR = false; continue }
                if scalar == "\r" || scalar == "\n" {
                    lineVerbatim = true; try deferBreak(scalar == "\r" ? "\r" : "\n", verbatim: true); previousCR = scalar == "\r"; continue
                }
                previousCR = false
                try prepare(); lineVerbatim = true
                try append(String(scalar == "\u{00A0}" ? " " : scalar))
                lineContent = true; trailingBreaks = 0
                meaningfulEnd = bytes.count; lastContentVerbatim = true
            } else if collapse && (scalar == " " || scalar == "\t" || scalar == "\r" || scalar == "\n" || scalar == "\u{0C}") {
                if lineContent { pendingSpace = true }
            } else {
                try prepare()
                if pendingSpace && lineContent { try append(" ") }
                pendingSpace = false
                try append(String(scalar == "\u{00A0}" ? " " : scalar))
                lineContent = true; trailingBreaks = 0
                meaningfulEnd = bytes.count; lastContentVerbatim = false
            }
        }
    }

    /// Rows have already flattened and trimmed their cells. Tabs are significant.
    func row(_ cells: [String]) throws {
        try prepare()
        for (index, cell) in cells.enumerated() {
            if index > 0 { try append("\t") }
            try append(cell)
        }
        lineContent = true; trailingBreaks = 0
        meaningfulEnd = bytes.count; lastContentVerbatim = false
    }

    func finish() -> String {
        if meaningfulEnd < bytes.count { bytes.removeSubrange(meaningfulEnd...) }
        if !lastContentVerbatim { while bytes.last == 32 { bytes.removeLast() } }
        while bytes.last == 10 || bytes.last == 13 { bytes.removeLast() }
        return String(decoding: bytes, as: UTF8.self)
    }
}
