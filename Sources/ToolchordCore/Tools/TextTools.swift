import Foundation

/// Character, word, line, and byte counts.
public enum TextTools {

    public static let commands: [ToolCommand] = [
        countCommand,
    ]

    private static let countCommand = ToolCommand(
        id: "text.count",
        title: "Count Characters",
        summary: "Characters, words, lines, and bytes",
        group: .inspect,
        icon: .symbol("textformat.123"),
        aliases: ["count", "word count", "character count", "char count",
                   "length", "string length", "text statistics", "count words"],
        copyNoun: "character count",
        affinity: { profile in profile.isPlainText ? (profile.has(.multiline) ? 45 : 25) : 0 },
        evaluate: evaluate
    )

    // MARK: - Evaluation

    static func evaluate(_ request: ToolRequest) -> ToolResult {
        let text = request.input.text ?? ""

        let (characters, words, lines, utf8Bytes, utf16Units, scalars) = countAll(text)

        let primaryText = String(characters)
        let status: String
        if characters == 1 {
            status = "1 character"
        } else {
            status = "\(characters) characters"
        }

        let fields: [ResultField] = [
            ResultField(id: "characters", label: "Characters", value: String(characters)),
            ResultField(id: "words", label: "Words", value: String(words)),
            ResultField(id: "lines", label: "Lines", value: String(lines)),
            ResultField(id: "utf8", label: "UTF-8 bytes", value: String(utf8Bytes)),
            ResultField(id: "utf16", label: "UTF-16 code units", value: String(utf16Units),
                        note: "JavaScript string length"),
            ResultField(id: "scalars", label: "Unicode scalars", value: String(scalars)),
        ]

        return .success(ToolOutput(
            primaryText: primaryText,
            status: status,
            presentation: .fields,
            fields: fields
        ))
    }

    // MARK: - Counting

    /// Returns (characters, words, lines, utf8Bytes, utf16CodeUnits, unicodeScalars).
    static func countAll(_ text: String) -> (
        characters: Int,
        words: Int,
        lines: Int,
        utf8Bytes: Int,
        utf16CodeUnits: Int,
        unicodeScalars: Int
    ) {
        let utf8Bytes = text.utf8.count
        let utf16CodeUnits = text.utf16.count
        let unicodeScalars = text.unicodeScalars.count
        let characters = text.count // grapheme clusters (Swift Character count)

        if text.isEmpty {
            return (characters: 0, words: 0, lines: 0,
                    utf8Bytes: 0, utf16CodeUnits: 0, unicodeScalars: 0)
        }

        // Words: maximal runs of non-whitespace characters.
        let words = countWords(text)

        // Lines: count line breaks (LF, CR, CRLF each count once), then apply rules.
        let lines = countLines(text)

        return (characters: characters, words: words, lines: lines,
                utf8Bytes: utf8Bytes, utf16CodeUnits: utf16CodeUnits,
                unicodeScalars: unicodeScalars)
    }

    /// Count maximal runs of non-whitespace characters.
    private static func countWords(_ text: String) -> Int {
        var count = 0
        var inWord = false
        for char in text {
            if char.isWhitespace {
                if inWord {
                    inWord = false
                }
            } else {
                if !inWord {
                    count += 1
                    inWord = true
                }
            }
        }
        return count
    }

    /// Count lines per the spec:
    /// - 0 for empty input
    /// - number of line breaks + 1, except a single trailing line break does not start a new line
    private static func countLines(_ text: String) -> Int {
        let bytes = Array(text.utf8)
        var lineBreaks = 0
        var i = 0
        while i < bytes.count {
            if bytes[i] == 0x0D {
                // CR: counts as one line break; if followed by LF, skip the LF too.
                lineBreaks += 1
                if i + 1 < bytes.count, bytes[i + 1] == 0x0A {
                    i += 2
                } else {
                    i += 1
                }
            } else if bytes[i] == 0x0A {
                // LF
                lineBreaks += 1
                i += 1
            } else {
                i += 1
            }
        }

        guard lineBreaks > 0 else { return 1 }

        // Check if the text ends with a single trailing line break.
        // A "single trailing line break" means the last line break is at the end
        // and there's no content after it.
        let endsWithLineBreak: Bool
        if bytes.last == 0x0A {
            endsWithLineBreak = true
        } else if bytes.last == 0x0D {
            endsWithLineBreak = true
        } else {
            endsWithLineBreak = false
        }

        if endsWithLineBreak {
            // The trailing line break does not start a new line.
            return lineBreaks
        } else {
            return lineBreaks + 1
        }
    }
}
