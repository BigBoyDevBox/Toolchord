import Foundation
import Testing
@testable import ToolchordCore

@Suite struct PlainTextToolsTests {

    // MARK: - Helpers

    private func run(_ text: String, options: [String: String] = [:]) throws -> ToolOutput {
        let command = try #require(PlainTextTools.commands.first { $0.id == "plaintext.clean" })
        let result = command.run(ToolRequest(input: .text(text), options: ToolOptions(options)))
        return try #require(result.output, "Expected success, got \(result)")
    }

    private func runPunctuationOff(_ text: String) throws -> ToolOutput {
        try run(text, options: ["punctuation": "false"])
    }

    private func runTrimOff(_ text: String) throws -> ToolOutput {
        try run(text, options: ["trim": "false"])
    }

    // MARK: - Command structure

    @Test func commandFoundByID() throws {
        let command = PlainTextTools.commands.first { $0.id == "plaintext.clean" }
        #expect(command != nil)
        let cmd = try #require(command)
        #expect(cmd.title == "Make Plain Text")
        #expect(cmd.summary == "Remove hidden characters and smart quotes")
        #expect(cmd.group.id == "plaintext")
        #expect(cmd.copyNoun(ToolOptions()) == "text")
    }

    @Test func commandAliases() throws {
        let cmd = try #require(PlainTextTools.commands.first { $0.id == "plaintext.clean" })
        #expect(cmd.aliases == [
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
        ])
    }

    @Test func commandOptions() throws {
        let cmd = try #require(PlainTextTools.commands.first { $0.id == "plaintext.clean" })
        #expect(cmd.options.count == 2)
        let punct = try #require(cmd.options.first { $0.id == "punctuation" })
        #expect(punct.label == "Straighten quotes and dashes")
        if case .toggle(let defaultVal) = punct.kind {
            #expect(defaultVal == true)
        } else {
            Issue.record("Expected toggle")
        }
        let trim = try #require(cmd.options.first { $0.id == "trim" })
        #expect(trim.label == "Trim trailing spaces")
        if case .toggle(let defaultVal) = trim.kind {
            #expect(defaultVal == true)
        } else {
            Issue.record("Expected toggle")
        }
    }

    @Test func affinityWithSpecialCharacters() throws {
        let cmd = try #require(PlainTextTools.commands.first { $0.id == "plaintext.clean" })
        let profileWith = InputProfile(
            isAttached: true,
            kinds: [.specialCharacters],
            primaryKind: .text,
            byteCount: 10,
            lineCount: 1,
            isBlank: false
        )
        let profileWithout = InputProfile(
            isAttached: true,
            kinds: [.text],
            primaryKind: .text,
            byteCount: 10,
            lineCount: 1,
            isBlank: false
        )
        #expect(cmd.affinity(profileWith) == 80)
        #expect(cmd.affinity(profileWithout) == 0)
    }

    // MARK: - Fixture: punctuation

    @Test func punctuationSmartQuotesAndDashes() throws {
        let input = "\u{201C}Hello,\u{201D} she said \u{2014} it\u{2019}s 5\u{2013}10 pages\u{2026}"
        let output = try run(input)
        #expect(output.primaryText == "\"Hello,\" she said -- it's 5-10 pages...")
        #expect(output.status == "6 changes")
        let punctField = output.fields.first { $0.id == "punctuation" }
        #expect(punctField != nil)
        #expect(punctField?.value == "6")
    }

    @Test func punctuationOffLeavesUnchanged() throws {
        let input = "\u{201C}Hello,\u{201D} she said \u{2014} it\u{2019}s 5\u{2013}10 pages\u{2026}"
        let output = try runPunctuationOff(input)
        #expect(output.primaryText.hasSameUTF8(as: input))
        #expect(output.status == "Already plain text")
        #expect(output.fields.isEmpty)
    }

    // MARK: - Fixture: spaces

    @Test func unusualSpacesNormalized() throws {
        let input = "a\u{00A0}b\u{202F}c\u{2009}d"
        let output = try run(input)
        #expect(output.primaryText == "a b c d")
        let spacesField = output.fields.first { $0.id == "spaces" }
        #expect(spacesField != nil)
        #expect(spacesField?.value == "3")
        #expect(spacesField?.note == "Non-breaking space (1), narrow no-break space (1), thin space (1)")
    }

    // MARK: - Fixture: hidden characters

    @Test func hiddenCharactersRemoved() throws {
        let input = "zero\u{200B}width\u{FEFF}\u{00AD}"
        let output = try run(input)
        #expect(output.primaryText == "zerowidth")
        let invField = output.fields.first { $0.id == "invisible" }
        #expect(invField != nil)
        #expect(invField?.value == "3")
        #expect(invField?.note == "Zero-width space (1), byte order mark (1), soft hyphen (1)")
    }

    @Test func hiddenCharactersWithMultipleSameKind() throws {
        let input = "x\u{200B}y\u{200B}z\u{00AD}"
        let output = try run(input)
        #expect(output.primaryText == "xyz")
        let invField = output.fields.first { $0.id == "invisible" }
        #expect(invField?.note == "Zero-width space (2), soft hyphen (1)")
    }

    // MARK: - Fixture: line breaks

    @Test func lineBreaksNormalized() throws {
        let input = "line1\r\nline2\rline3\u{2028}line4"
        let output = try run(input)
        #expect(output.primaryText == "line1\nline2\nline3\nline4")
        let lbField = output.fields.first { $0.id == "lineBreaks" }
        #expect(lbField != nil)
        #expect(lbField?.value == "3")
    }

    @Test func crlfSingleChange() throws {
        let input = "a\r\n"
        let output = try run(input)
        #expect(output.primaryText == "a\n")
        #expect(output.status == "1 change")
    }

    // MARK: - Fixture: trailing spaces

    @Test func trailingSpacesRemoved() throws {
        let input = "trailing   \nspaces\t\n"
        let output = try run(input)
        #expect(output.primaryText == "trailing\nspaces\n")
        let trailField = output.fields.first { $0.id == "trailing" }
        #expect(trailField != nil)
        #expect(trailField?.value == "4")
        #expect(output.status == "4 changes")
    }

    @Test func trailingSpacesTrimOff() throws {
        let input = "trailing   \nspaces\t\n"
        let output = try runTrimOff(input)
        #expect(output.primaryText.hasSameUTF8(as: input))
        #expect(output.status == "Already plain text")
    }

    @Test func nonBreakingSpaceThenNewline() throws {
        let input = "\u{00A0}\n"
        let output = try run(input)
        #expect(output.primaryText == "\n")
        #expect(output.status == "2 changes")
    }

    @Test func hiddenCharBetweenSpaceAndNewline() throws {
        let input = "a \u{200B}\nb"
        let output = try run(input)
        #expect(output.primaryText == "a\nb")
    }

    // MARK: - Fixture: emoji and preserved characters

    @Test func emojiWithZeroWidthJoinerPreserved() throws {
        let input = "👨\u{200D}👩\u{200D}👧"
        let output = try run(input)
        #expect(output.primaryText.hasSameUTF8(as: input))
    }

    @Test func emojiTagSequencePreserved() throws {
        let input = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"
        let output = try run(input)
        #expect(output.primaryText.hasSameUTF8(as: input))
        #expect(output.warnings.isEmpty)
    }

    @Test func tagCharactersRemoved() throws {
        let input = "hi\u{E0001}\u{E0068}\u{E0069}\u{E007F}"
        let output = try run(input)
        #expect(output.primaryText == "hi")
        #expect(output.warnings.count == 1)
        #expect(output.warnings[0] == "Removed 4 tag characters, which can hide text from readers.")
    }

    @Test func incompleteEmojiTagSequence() throws {
        let input = "\u{1F3F4}\u{E0067}x"
        let output = try run(input)
        #expect(output.primaryText == "\u{1F3F4}x")
        #expect(output.warnings.count == 1)
        #expect(output.warnings[0] == "Removed 1 tag character, which can hide text from readers.")
    }

    // MARK: - Fixture: bidirectional controls

    @Test func bidirectionalControlsRemoved() throws {
        let input = "abc\u{202E}def\u{202C}"
        let output = try run(input)
        #expect(output.primaryText == "abcdef")
        #expect(output.warnings.count == 1)
        #expect(output.warnings[0] == "Removed 2 bidirectional control characters, which can make text display in a different order than it is stored.")
    }

    // MARK: - Fixture: em dash

    @Test func emDashBecomesDoubleDash() throws {
        let input = "\u{2014}verbose"
        let output = try run(input)
        #expect(output.primaryText == "--verbose")
    }

    // MARK: - Fixture: control characters and line breaks

    @Test func controlCharsAndLineBreaks() throws {
        let input = "a\u{0000}b\u{0007}c\u{007F}d\u{0085}e"
        let output = try run(input)
        #expect(output.primaryText == "abcd\ne")
    }

    // MARK: - Fixture: dashes

    @Test func variousDashes() throws {
        let input = "x\u{2011}y\u{2212}z"
        let output = try run(input)
        #expect(output.primaryText == "x-y-z")
    }

    // MARK: - Fixture: vertical and form feed

    @Test func verticalTabAndFormFeed() throws {
        let input = "a\u{000B}b\u{000C}c"
        let output = try run(input)
        #expect(output.primaryText == "a\nb\nc")
    }

    // MARK: - Fixture: object replacement character

    @Test func objectReplacementCharacter() throws {
        let input = "Image\u{FFFC} here"
        let output = try run(input)
        #expect(output.primaryText == "Image here")
    }

    // MARK: - Fixture: combining diacritics preserved

    @Test func combiningDiacriticsPreserved() throws {
        let input = "nai\u{0308}ve cafe\u{0301}"
        let output = try run(input)
        #expect(output.primaryText.utf8.elementsEqual(input.utf8))
    }

    // MARK: - Fixture: ideographic space preserved

    @Test func ideographicSpacePreserved() throws {
        let input = "\u{3000}全角"
        let output = try run(input)
        #expect(output.primaryText.hasSameUTF8(as: input))
    }

    // MARK: - Fixture: guillemets preserved

    @Test func guillemetsPreserved() throws {
        let input = "«Bonjour» ‹x›"
        let output = try run(input)
        #expect(output.primaryText.hasSameUTF8(as: input))
    }

    // MARK: - Fixture: empty input

    @Test func emptyInput() throws {
        let output = try run("")
        #expect(output.primaryText == "")
        #expect(output.status == "Already plain text")
    }

    // MARK: - isSpecial tests

    @Test func isSpecialReturnsTrueForSpecialScalars() {
        #expect(PlainTextTools.isSpecial(Unicode.Scalar(0x200B)!) == true)  // zero-width space
        #expect(PlainTextTools.isSpecial(Unicode.Scalar(0x00A0)!) == true)  // non-breaking space
        #expect(PlainTextTools.isSpecial(Unicode.Scalar(0x2019)!) == true)  // right single quote
        #expect(PlainTextTools.isSpecial(Unicode.Scalar(0x2014)!) == true)  // em dash
        #expect(PlainTextTools.isSpecial(Unicode.Scalar(0x2028)!) == true)  // line separator
        #expect(PlainTextTools.isSpecial(Unicode.Scalar(0x000B)!) == true)  // vertical tab
        #expect(PlainTextTools.isSpecial(Unicode.Scalar(0xE0041)!) == true) // tag character
        #expect(PlainTextTools.isSpecial(Unicode.Scalar(0x0007)!) == true)  // bell (control)
    }

    @Test func isSpecialReturnsFalseForNormalScalars() {
        #expect(PlainTextTools.isSpecial(Unicode.Scalar("a")) == false)
        #expect(PlainTextTools.isSpecial(Unicode.Scalar(0x0020)!) == false)  // space
        #expect(PlainTextTools.isSpecial(Unicode.Scalar(0x0009)!) == false)  // tab
        #expect(PlainTextTools.isSpecial(Unicode.Scalar(0x000A)!) == false)  // LF
        #expect(PlainTextTools.isSpecial(Unicode.Scalar(0x000D)!) == false)  // CR
        #expect(PlainTextTools.isSpecial(Unicode.Scalar(0x200D)!) == false)  // zero-width joiner
        #expect(PlainTextTools.isSpecial(Unicode.Scalar(0xFE0F)!) == false)  // variation selector
        #expect(PlainTextTools.isSpecial(Unicode.Scalar(0x3000)!) == false)  // ideographic space
        #expect(PlainTextTools.isSpecial(Unicode.Scalar("«")) == false)     // guillemet
    }

    // MARK: - Performance test

    @Test func largeInputPerformance() throws {
        // Build a 1 MiB input mixing every category using a repeating pattern
        let pattern = "a\u{200B}\u{00A0}\u{2019}b\u{2014}c\n"
        let targetSize = 1 * 1024 * 1024
        let patternBytes = pattern.utf8.count
        let repeats = (targetSize / patternBytes) + 1
        var largeInput = ""
        largeInput.reserveCapacity(targetSize)
        for _ in 0..<repeats {
            largeInput += pattern
        }
        if largeInput.utf8.count > targetSize {
            largeInput = String(decoding: largeInput.utf8.prefix(targetSize), as: UTF8.self)
        }

        var output: ToolOutput?
        let elapsed = try ContinuousClock().measure { output = try run(largeInput) }

        #expect(output?.primaryText.isEmpty == false)
        // About 0.2 s alone in a debug build; the bound is generous for
        // parallel runs and still catches quadratic behavior.
        #expect(elapsed < .seconds(5), "Should complete in under 5 seconds, took \(elapsed)")
    }

    // MARK: - Cancellation

    /// Reports cancellation from its second check on, so only the loop's
    /// periodic checks can catch it.
    private final class SecondCallCancels: @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        func check() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            calls += 1
            return calls > 1
        }
    }

    @Test func cancelledEmptyInputIsCancelled() throws {
        let command = try #require(PlainTextTools.commands.first { $0.id == "plaintext.clean" })
        #expect(command.run(ToolRequest(input: .text(""), cancellation: CancellationCheck { true })) == .cancelled)
    }

    @Test func cancellationIsCheckedWhenCRLFSkipsIndices() throws {
        let command = try #require(PlainTextTools.commands.first { $0.id == "plaintext.clean" })
        let counter = SecondCallCancels()
        let input = "a" + String(repeating: "\r\n", count: 100_000)
        let result = command.run(ToolRequest(input: .text(input), cancellation: CancellationCheck { counter.check() }))
        #expect(result == .cancelled)
    }

    // MARK: - Contract fixture

    @Test func contractFixture() throws {
        let output = try run("curl\u{00A0}\u{2014}silent \u{201C}https://e.test\u{201D}")
        #expect(output.primaryText == "curl --silent \"https://e.test\"")
        #expect(output.status == "4 changes")
    }

    // MARK: - Missing input

    @Test func missingInputAsksForText() throws {
        let cmd = try #require(PlainTextTools.commands.first { $0.id == "plaintext.clean" })
        let result = cmd.run(ToolRequest(input: .none))
        if case .needsInput = result {} else {
            Issue.record("Expected needsInput, got \(result)")
        }
    }

    // MARK: - Status formatting

    @Test func statusAlreadyPlainText() throws {
        let output = try run("hello world")
        #expect(output.status == "Already plain text")
    }

    @Test func statusOneChange() throws {
        let output = try run("a\u{200B}b")
        #expect(output.status == "1 change")
    }

    @Test func statusMultipleChanges() throws {
        let output = try run("a\u{200B}b\u{200B}c")
        #expect(output.status == "2 changes")
    }

    // MARK: - Field ordering

    @Test func fieldOrdering() throws {
        // Input that triggers all categories
        let input = "\u{201C}a\u{00A0}b\u{200B}c\r\ntrailing  \n"
        let output = try run(input)
        let fieldIds = output.fields.map { $0.id }
        #expect(fieldIds == ["invisible", "spaces", "punctuation", "lineBreaks", "trailing"])
    }

    // MARK: - Single bidi warning

    @Test func singleBidiWarning() throws {
        let input = "a\u{202E}b"
        let output = try run(input)
        #expect(output.warnings.count == 1)
        #expect(output.warnings[0] == "Removed 1 bidirectional control character, which can make text display in a different order than it is stored.")
    }

    // MARK: - Tab trimming

    @Test func tabTrailingRemoved() throws {
        let input = "text\t\n"
        let output = try run(input)
        #expect(output.primaryText == "text\n")
        let trailField = output.fields.first { $0.id == "trailing" }
        #expect(trailField?.value == "1")
    }

    // MARK: - Tab preserved when not trailing

    @Test func tabPreservedWhenNotTrailing() throws {
        let input = "a\tb"
        let output = try run(input)
        #expect(output.primaryText.hasSameUTF8(as: input))
        #expect(output.status == "Already plain text")
    }
}
