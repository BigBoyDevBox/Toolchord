import Foundation

/// Make Plain Text: removes invisible characters and normalizes spaces,
/// line breaks, and (optionally) typographic punctuation.
public enum PlainTextTools {

    // MARK: - Command

    public static let commands: [ToolCommand] = [
        ToolCommand(
            id: "plaintext.clean",
            title: "Make Plain Text",
            summary: "Remove hidden characters and smart quotes",
            group: .plainText,
            icon: .symbol("doc.plaintext"),
            aliases: [
                "plain text",
                "paste as plain text",
                "strip formatting",
                "remove formatting",
                "clean text",
                "clean up text",
                "remove invisible characters",
                "zero width space",
                "straighten quotes",
                "smart quotes",
                "non-breaking space",
            ],
            options: [
                ToolOption.toggle("punctuation", "Straighten quotes and dashes", default: true),
                ToolOption.toggle("trim", "Trim trailing spaces", default: true),
            ],
            copyNoun: "text",
            affinity: { profile in
                profile.has(.specialCharacters) ? 80 : 0
            },
            evaluate: evaluate
        )
    ]

    // MARK: - isSpecial

    /// Returns `true` for every scalar the default options would remove or
    /// replace in categories 2, 3, and 4, plus U+000B, U+000C, U+0085,
    /// U+2028, and U+2029 — but not CR, LF, tab, space, or anything else.
    static func isSpecial(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        // Category 2: Hidden characters
        case 0x0000...0x0008, 0x000E...0x001F, 0x007F: return true
        case 0x0080...0x0084, 0x0086...0x009F: return true
        case 0x00AD: return true // soft hyphen
        case 0x061C: return true // Arabic letter mark
        case 0x180E: return true // Mongolian vowel separator
        case 0x200B: return true // zero-width space
        case 0x200E, 0x200F: return true // LTR/RTL mark
        case 0x202A...0x202E: return true // bidi controls
        case 0x2060: return true // word joiner
        case 0x2061...0x2064: return true // invisible operator
        case 0x2066...0x2069: return true // bidi controls
        case 0x206A...0x206F: return true // deprecated format
        case 0xFEFF: return true // BOM
        case 0xFFF9...0xFFFB: return true // interlinear annotation
        case 0xFFFC: return true // object replacement
        case 0xE0001: return true // tag character
        case 0xE0020...0xE007F: return true // tag characters
        // Category 3: Unusual spaces
        case 0x00A0: return true // non-breaking space
        case 0x2000: return true // en quad
        case 0x2001: return true // em quad
        case 0x2002: return true // en space
        case 0x2003: return true // em space
        case 0x2004: return true // three-per-em space
        case 0x2005: return true // four-per-em space
        case 0x2006: return true // six-per-em space
        case 0x2007: return true // figure space
        case 0x2008: return true // punctuation space
        case 0x2009: return true // thin space
        case 0x200A: return true // hair space
        case 0x202F: return true // narrow no-break space
        case 0x205F: return true // medium mathematical space
        // Category 4: Punctuation
        case 0x2018, 0x2019, 0x201A, 0x201B, 0x2032: return true
        case 0x201C, 0x201D, 0x201E, 0x201F, 0x2033: return true
        case 0x2010, 0x2011, 0x2012, 0x2013, 0x2212: return true
        case 0x2014, 0x2015: return true
        case 0x2026: return true
        // Line break specials (not CR/LF)
        case 0x000B, 0x000C, 0x0085, 0x2028, 0x2029: return true
        default: return false
        }
    }

    // MARK: - Evaluate

    static func evaluate(_ request: ToolRequest) -> ToolResult {
        guard let text = request.input.text else {
            return .needsInput("Paste text to clean.")
        }

        if request.cancellation.isCancelled { return .cancelled }
        let doPunctuation = request.options.flag("punctuation", default: true)
        let doTrim = request.options.flag("trim", default: true)

        let scalars = Array(text.unicodeScalars)
        let count = scalars.count

        // Empty input → empty output
        if count == 0 {
            return .success(ToolOutput(
                primaryText: "",
                status: "Already plain text",
                presentation: .text,
                syntax: .plain
            ))
        }

        // Counters
        var lineBreaks = 0
        var invisible = 0
        var spaces = 0
        var punctuation = 0
        var trailing = 0

        // Kind tracking: (kindName, count, firstIndex)
        var invisibleKinds: [(name: String, count: Int, firstIndex: Int)] = []
        var spacesKinds: [(name: String, count: Int, firstIndex: Int)] = []
        var invisibleKindIndex = 0
        var spacesKindIndex = 0

        // Warning counters
        var bidiRemoved = 0
        var tagRemoved = 0

        // Output buffer
        var output: [Unicode.Scalar] = []
        output.reserveCapacity(count)

        // Trailing space buffer: stores scalars that are spaces/tabs pending flush
        // These are dropped at line break or end of text
        var trailingBuffer: [Unicode.Scalar] = []

        var i = 0
        var iterations = 0
        while i < count {
            // Cancellation check every 4096 iterations (CRLF advances `i` by two).
            iterations += 1
            if iterations & 0xFFF == 0, request.cancellation.isCancelled {
                return .cancelled
            }

            let scalar = scalars[i]
            let value = scalar.value

            // Category 1: Line breaks (always)
            if value == 0x000D {
                // CR
                if i + 1 < count, scalars[i + 1].value == 0x000A {
                    // CRLF → LF (one change)
                    output.append(Unicode.Scalar(0x000A)!)
                    lineBreaks += 1
                    i += 2
                    // Flush trailing buffer
                    trailing += trailingBuffer.count
                    trailingBuffer.removeAll()
                    continue
                } else {
                    // Lone CR → LF
                    output.append(Unicode.Scalar(0x000A)!)
                    lineBreaks += 1
                    i += 1
                    // Flush trailing buffer
                    trailing += trailingBuffer.count
                    trailingBuffer.removeAll()
                    continue
                }
            }

            // Check for LF first (not a change, just a line break for trimming)
            if value == 0x000A {
                output.append(scalar)
                // Flush trailing buffer
                trailing += trailingBuffer.count
                trailingBuffer.removeAll()
                i += 1
                continue
            }

            // Category 1 continued: other line breaks
            if value == 0x000B || value == 0x000C || value == 0x0085
                || value == 0x2028 || value == 0x2029 {
                output.append(Unicode.Scalar(0x000A)!)
                lineBreaks += 1
                i += 1
                // Flush trailing buffer
                trailing += trailingBuffer.count
                trailingBuffer.removeAll()
                continue
            }

            // Check for emoji tag sequence starting with U+1F3F4
            if value == 0x1F3F4, let sequence = tryConsumeEmojiTagSequence(scalars, from: i) {
                // Copy the entire sequence unchanged
                if doTrim, !trailingBuffer.isEmpty {
                    output.append(contentsOf: trailingBuffer)
                    trailingBuffer.removeAll()
                }
                output.append(contentsOf: sequence)
                i += sequence.count
                continue
            }

            // Category 2: Hidden characters (always removed)
            if let kind = classifyHidden(scalar) {
                // It's a hidden character to remove
                invisible += 1
                let existing = findKind(&invisibleKinds, name: kind)
                if existing >= 0 {
                    invisibleKinds[existing].count += 1
                } else {
                    invisibleKinds.append((name: kind, count: 1, firstIndex: invisibleKindIndex))
                    invisibleKindIndex += 1
                }

                // Track bidi and tag warnings
                if isBidiControl(value) {
                    bidiRemoved += 1
                }
                if isTagChar(value) {
                    tagRemoved += 1
                }

                i += 1
                continue
            }

            // Category 3: Unusual spaces (always → U+0020)
            if let kind = classifySpace(scalar) {
                spaces += 1
                let existing = findKind(&spacesKinds, name: kind)
                if existing >= 0 {
                    spacesKinds[existing].count += 1
                } else {
                    spacesKinds.append((name: kind, count: 1, firstIndex: spacesKindIndex))
                    spacesKindIndex += 1
                }

                // If trimming, add to trailing buffer; otherwise output space
                if doTrim {
                    trailingBuffer.append(Unicode.Scalar(0x0020)!)
                } else {
                    output.append(Unicode.Scalar(0x0020)!)
                }
                i += 1
                continue
            }

            // Category 4: Punctuation (only when enabled)
            if doPunctuation, let replacement = classifyPunctuation(scalar) {
                punctuation += 1
                // Flush trailing buffer before punctuation output
                if doTrim, !trailingBuffer.isEmpty {
                    output.append(contentsOf: trailingBuffer)
                    trailingBuffer.removeAll()
                }
                output.append(contentsOf: replacement)
                i += 1
                continue
            }

            // Category 5: Trailing spaces (only when trim is on)
            // Regular space (U+0020) or tab (U+0009)
            if doTrim && (value == 0x0020 || value == 0x0009) {
                trailingBuffer.append(scalar)
                i += 1
                continue
            }

            // Default: copy unchanged
            if doTrim, !trailingBuffer.isEmpty {
                // Flush trailing buffer before non-space output
                output.append(contentsOf: trailingBuffer)
                trailingBuffer.removeAll()
            }
            output.append(scalar)
            i += 1
        }

        // Flush remaining trailing buffer at end of text
        if doTrim {
            trailing += trailingBuffer.count
            trailingBuffer.removeAll()
        } else if !trailingBuffer.isEmpty {
            output.append(contentsOf: trailingBuffer)
            trailingBuffer.removeAll()
        }

        let totalChanges = lineBreaks + invisible + spaces + punctuation + trailing

        // Build result
        var primaryText = ""
        primaryText.unicodeScalars.append(contentsOf: output)

        let status: String
        if totalChanges == 0 {
            status = "Already plain text"
        } else if totalChanges == 1 {
            status = "1 change"
        } else {
            status = "\(totalChanges) changes"
        }

        // Build fields
        var fields: [ResultField] = []

        if invisible > 0 {
            let note = kindNote(from: invisibleKinds)
            fields.append(ResultField(
                id: "invisible",
                label: "Hidden characters removed",
                value: "\(invisible)",
                note: note,
                isCopyable: false,
                isMonospaced: false
            ))
        }

        if spaces > 0 {
            let note = kindNote(from: spacesKinds)
            fields.append(ResultField(
                id: "spaces",
                label: "Spaces normalized",
                value: "\(spaces)",
                note: note,
                isCopyable: false,
                isMonospaced: false
            ))
        }

        if punctuation > 0 {
            fields.append(ResultField(
                id: "punctuation",
                label: "Quotes and dashes straightened",
                value: "\(punctuation)",
                isCopyable: false,
                isMonospaced: false
            ))
        }

        if lineBreaks > 0 {
            fields.append(ResultField(
                id: "lineBreaks",
                label: "Line breaks normalized",
                value: "\(lineBreaks)",
                isCopyable: false,
                isMonospaced: false
            ))
        }

        if trailing > 0 {
            fields.append(ResultField(
                id: "trailing",
                label: "Trailing spaces removed",
                value: "\(trailing)",
                isCopyable: false,
                isMonospaced: false
            ))
        }

        // Build warnings
        var warnings: [String] = []
        if bidiRemoved > 0 {
            let n = bidiRemoved
            let charWord = n == 1 ? "character" : "characters"
            warnings.append("Removed \(n) bidirectional control \(charWord), which can make text display in a different order than it is stored.")
        }
        if tagRemoved > 0 {
            let n = tagRemoved
            let charWord = n == 1 ? "character" : "characters"
            warnings.append("Removed \(n) tag \(charWord), which can hide text from readers.")
        }

        return .success(ToolOutput(
            primaryText: primaryText,
            status: status,
            presentation: .text,
            syntax: .plain,
            fields: fields,
            warnings: warnings
        ))
    }

    // MARK: - Classification helpers

    static func classifyHidden(_ scalar: Unicode.Scalar) -> String? {
        let v = scalar.value
        switch v {
        case 0x0000...0x0008, 0x000E...0x001F, 0x007F, 0x0080...0x0084, 0x0086...0x009F:
            return "control character"
        case 0x00AD:
            return "soft hyphen"
        case 0x061C:
            return "Arabic letter mark"
        case 0x180E:
            return "Mongolian vowel separator"
        case 0x200B:
            return "zero-width space"
        case 0x200E:
            return "left-to-right mark"
        case 0x200F:
            return "right-to-left mark"
        case 0x202A...0x202E, 0x2066...0x2069:
            return "bidirectional control"
        case 0x2060:
            return "word joiner"
        case 0x2061...0x2064:
            return "invisible operator"
        case 0x206A...0x206F:
            return "deprecated format character"
        case 0xFEFF:
            return "byte order mark"
        case 0xFFF9...0xFFFB:
            return "interlinear annotation character"
        case 0xFFFC:
            return "object replacement character"
        case 0xE0001, 0xE0020...0xE007F:
            return "tag character"
        default:
            return nil
        }
    }

    static func classifySpace(_ scalar: Unicode.Scalar) -> String? {
        switch scalar.value {
        case 0x00A0: return "non-breaking space"
        case 0x2000: return "en quad"
        case 0x2001: return "em quad"
        case 0x2002: return "en space"
        case 0x2003: return "em space"
        case 0x2004: return "three-per-em space"
        case 0x2005: return "four-per-em space"
        case 0x2006: return "six-per-em space"
        case 0x2007: return "figure space"
        case 0x2008: return "punctuation space"
        case 0x2009: return "thin space"
        case 0x200A: return "hair space"
        case 0x202F: return "narrow no-break space"
        case 0x205F: return "medium mathematical space"
        default: return nil
        }
    }

    static func classifyPunctuation(_ scalar: Unicode.Scalar) -> [Unicode.Scalar]? {
        switch scalar.value {
        case 0x2018, 0x2019, 0x201A, 0x201B, 0x2032:
            return [Unicode.Scalar(0x27)!] // '
        case 0x201C, 0x201D, 0x201E, 0x201F, 0x2033:
            return [Unicode.Scalar(0x22)!] // "
        case 0x2010, 0x2011, 0x2012, 0x2013, 0x2212:
            return [Unicode.Scalar(0x2D)!] // -
        case 0x2014, 0x2015:
            return [Unicode.Scalar(0x2D)!, Unicode.Scalar(0x2D)!] // --
        case 0x2026:
            return [Unicode.Scalar(0x2E)!, Unicode.Scalar(0x2E)!, Unicode.Scalar(0x2E)!] // ...
        default:
            return nil
        }
    }

    static func isBidiControl(_ value: UInt32) -> Bool {
        (0x202A...0x202E).contains(value) || (0x2066...0x2069).contains(value)
    }

    static func isTagChar(_ value: UInt32) -> Bool {
        value == 0xE0001 || (0xE0020...0xE007F).contains(value)
    }

    /// Try to consume an emoji tag sequence starting at index `from`.
    /// Returns the scalars consumed (including U+1F3F4) or nil if not a valid sequence.
    static func tryConsumeEmojiTagSequence(_ scalars: [Unicode.Scalar], from: Int) -> ArraySlice<Unicode.Scalar>? {
        // Must start with U+1F3F4
        guard from < scalars.count, scalars[from].value == 0x1F3F4 else { return nil }

        var j = from + 1
        // Consume 1 to 32 tag chars (E0020-E007E)
        var tagCount = 0
        while j < scalars.count, tagCount < 32 {
            let v = scalars[j].value
            if (0xE0020...0xE007E).contains(v) {
                tagCount += 1
                j += 1
            } else {
                break
            }
        }
        // Must end with E007F
        guard j < scalars.count, scalars[j].value == 0xE007F else { return nil }
        // Must have at least 1 tag char
        guard tagCount >= 1 else { return nil }

        j += 1 // include E007F
        return scalars[from..<j]
    }

    // MARK: - Kind note formatting

    static func findKind(_ kinds: inout [(name: String, count: Int, firstIndex: Int)], name: String) -> Int {
        for i in 0..<kinds.count {
            if kinds[i].name == name { return i }
        }
        return -1
    }

    static func kindNote(from kinds: [(name: String, count: Int, firstIndex: Int)]) -> String {
        // Sort by count descending, then by firstIndex ascending for ties
        let sorted = kinds.sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            return a.firstIndex < b.firstIndex
        }

        // Capitalize first letter of the first kind name
        var items: [String] = []
        for (idx, kind) in sorted.enumerated() {
            let name: String
            if idx == 0 {
                // Capitalize first letter
                let chars = Array(kind.name)
                if let first = chars.first {
                    name = String(first.uppercased()) + String(chars.dropFirst())
                } else {
                    name = kind.name
                }
            } else {
                name = kind.name
            }
            items.append("\(name) (\(kind.count))")
        }

        let result: String
        if items.count <= 3 {
            result = items.joined(separator: ", ")
        } else {
            let extra = kinds.count - 3
            result = items.prefix(3).joined(separator: ", ") + ", and \(extra) more"
        }

        return result
    }
}
