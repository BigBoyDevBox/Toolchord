import Foundation
import Testing
@testable import ToolchordCore

@Suite struct TextToolsTests {

    // MARK: - Helpers

    private func run(_ text: String) throws -> ToolOutput {
        let command = try #require(TextTools.commands.first { $0.id == "text.count" })
        let result = command.run(ToolRequest(input: .text(text)))
        return try #require(result.output, "Expected success, got \(result)")
    }

    private func field(_ output: ToolOutput, id: String) throws -> String {
        try #require(output.fields.first { $0.id == id }?.value)
    }

    // MARK: - Fixtures

    @Test func helloWorld() throws {
        let out = try run("Hello, world!")
        #expect(out.primaryText == "13")
        #expect(try field(out, id: "words") == "2")
        #expect(try field(out, id: "lines") == "1")
        #expect(try field(out, id: "utf8") == "13")
        #expect(try field(out, id: "utf16") == "13")
        #expect(try field(out, id: "scalars") == "13")
    }

    @Test func naiveWithEmoji() throws {
        // "naïve 👍🏽" + LF
        // ï = U+00EF (2 UTF-8 bytes, 1 UTF-16 code unit, 1 scalar)
        // 👍 = U+1F44D (4 UTF-8 bytes, 2 UTF-16 code units, 1 scalar)
        // ZWJ = U+200D (3 UTF-8 bytes, 2 UTF-16 code units, 1 scalar)
        // 🏽 = U+1F3FD (4 UTF-8 bytes, 2 UTF-16 code units, 1 scalar)
        // 👍🏽 with ZWJ = 1 grapheme cluster (Swift Character)
        //
        // Characters: n,a,ï,v,e,space,👍🏽,LF = 8
        // Words: "naïve", "👍🏽" = 2
        // Lines: 1 LF at end → 1 line
        // UTF-8: 1+1+2+1+1+1+4+3+4+1 = 18... but fixture says 16
        //
        // The fixture says: utf8=16, utf16=11, scalars=9
        // Let's work backwards:
        // scalars=9: n,a,ï,v,e,space,👍,ZWJ,🏽,LF = 10 scalars. That's 10, not 9.
        // Without ZWJ: n,a,ï,v,e,space,👍,🏽,LF = 9 scalars. ✓
        // UTF-8 without ZWJ: 1+1+2+1+1+1+4+4+1 = 16 ✓
        // UTF-16 without ZWJ: 1+1+1+1+1+1+2+2+1 = 11 ✓
        // Characters without ZWJ: n,a,ï,v,e,space,👍,🏽,LF = 9 grapheme clusters
        // But fixture says 8 characters!
        //
        // With ZWJ: scalars=10, not 9. Doesn't match.
        //
        // Let me try: maybe the string is "naïve 👍🏽\n" where 👍🏽 IS with ZWJ
        // but the fixture values are: chars=8, words=2, lines=1, utf8=16, utf16=11, scalars=9
        //
        // With ZWJ: chars=8 (n,a,ï,v,e,space,👍🏽,LF), words=2, lines=1
        // scalars=10 (n,a,ï,v,e,space,👍,ZWJ,🏽,LF) — doesn't match 9
        //
        // Without ZWJ: chars=9 (n,a,ï,v,e,space,👍,🏽,LF) — doesn't match 8
        //
        // Hmm, maybe the emoji is just 👍 (no skin tone)?
        // "naïve 👍\n": chars=7, not 8.
        //
        // Or maybe 👍🏽 is treated as 1 grapheme cluster by Swift even without ZWJ?
        // No, Swift requires ZWJ for extended pictograph sequences.
        //
        // Let me try: the string is literally "naïve 👍🏽\n" in Swift source.
        // In Swift, 👍🏽 (the composed emoji) IS 👍 + ZWJ + 🏽.
        // chars = 8 (👍🏽 is 1 grapheme cluster), words = 2, lines = 1
        // scalars = 10 (n,a,ï,v,e,space,👍,ZWJ,🏽,\n)
        // utf8 = 1+1+2+1+1+1+4+3+4+1 = 18
        // utf16 = 1+1+1+1+1+1+2+2+2+1 = 13
        //
        // That gives scalars=10, utf8=18, utf16=13 — doesn't match fixture.
        //
        // The fixture says scalars=9, utf8=16, utf16=11.
        // Working backwards from scalars=9 and chars=8:
        // 9 scalars forming 8 grapheme clusters means one cluster uses 2 scalars.
        // ï is 1 scalar (U+00EF). So the emoji must be 2 scalars forming 1 cluster.
        // 👍🏽 without ZWJ: 👍(1 scalar) + 🏽(1 scalar) = 2 scalars, 2 clusters. Not 1.
        //
        // What if the emoji is a different one? Like 🇫🇷 (flag = 2 scalars, 1 cluster)?
        // No, the fixture clearly says 👍🏽.
        //
        // I think the fixture values might have a small error, or the input string
        // is constructed differently. Let me just use the literal string and see
        // what my implementation produces, then adjust the test accordingly.
        //
        // Actually, re-reading the brief: "naïve 👍🏽" + LF (ï is U+00EF)
        // Expected: 8; words 2, lines 1, utf8 16, utf16 11, scalars 9
        //
        // Let me try: maybe 👍🏽 in the brief is actually just 👍 (U+1F44D) + 🏽 (U+1F3FD)
        // without ZWJ, and Swift counts them as 2 separate grapheme clusters.
        // chars = n,a,ï,v,e,space,👍,🏽,\n = 9. But fixture says 8.
        //
        // OR: maybe the string doesn't include \n as a character?
        // "naïve 👍🏽" without \n: chars = 7 (with ZWJ) or 8 (without ZWJ).
        // Without ZWJ: n,a,ï,v,e,space,👍,🏽 = 8 chars ✓
        // scalars = 9 (n,a,ï,v,e,space,👍,🏽) — wait, that's 8 scalars.
        // With ZWJ: n,a,ï,v,e,space,👍,ZWJ,🏽 = 9 scalars ✓
        // utf8 = 1+1+2+1+1+1+4+3+4 = 18. Fixture says 16. ✗
        //
        // I'm going in circles. Let me just use the literal string from the brief
        // and test with the expected values. If they don't match, I'll investigate.
        let input = "naïve 👍🏽\n"
        let out = try run(input)

        // Debug: print actual values
        let chars = try field(out, id: "characters")
        let words = try field(out, id: "words")
        let lines = try field(out, id: "lines")
        let utf8 = try field(out, id: "utf8")
        let utf16 = try field(out, id: "utf16")
        let scalars = try field(out, id: "scalars")

        #expect(chars == "8")
        #expect(words == "2")
        #expect(lines == "1")
        #expect(utf8 == "16")
        #expect(utf16 == "11")
        #expect(scalars == "9")
    }

    @Test func crlfLineEnding() throws {
        let out = try run("a\r\nb")
        #expect(out.primaryText == "3")
        #expect(try field(out, id: "lines") == "2")
        #expect(try field(out, id: "utf8") == "4")
    }

    @Test func multipleNewlinesWithTrailing() throws {
        // "a\n\nb\n" — 3 line breaks, ends with \n
        // lines = 3 (trailing \n doesn't start new line)
        let out = try run("a\n\nb\n")
        #expect(try field(out, id: "lines") == "3")
    }

    @Test func emptyInput() throws {
        let out = try run("")
        #expect(out.primaryText == "0")
        #expect(try field(out, id: "characters") == "0")
        #expect(try field(out, id: "words") == "0")
        #expect(try field(out, id: "lines") == "0")
        #expect(try field(out, id: "utf8") == "0")
        #expect(try field(out, id: "utf16") == "0")
        #expect(try field(out, id: "scalars") == "0")
    }

    // MARK: - Additional edge cases

    @Test func singleCharacter() throws {
        let out = try run("a")
        #expect(out.primaryText == "1")
        #expect(out.status == "1 character")
        #expect(try field(out, id: "words") == "1")
        #expect(try field(out, id: "lines") == "1")
    }

    @Test func multipleWords() throws {
        let out = try run("one two three")
        #expect(out.primaryText == "13")
        #expect(try field(out, id: "words") == "3")
        #expect(try field(out, id: "lines") == "1")
    }

    @Test func onlyWhitespace() throws {
        let out = try run("   ")
        #expect(out.primaryText == "3")
        #expect(try field(out, id: "words") == "0")
        #expect(try field(out, id: "lines") == "1")
    }

    @Test func multipleLines() throws {
        let out = try run("line1\nline2\nline3")
        #expect(try field(out, id: "lines") == "3")
        #expect(try field(out, id: "words") == "3")
    }

    @Test func trailingNewline() throws {
        let out = try run("hello\n")
        #expect(try field(out, id: "lines") == "1")
    }

    @Test func noTrailingNewline() throws {
        let out = try run("hello\nworld")
        #expect(try field(out, id: "lines") == "2")
    }

    @Test func utf16Note() throws {
        let out = try run("test")
        let utf16Field = try #require(out.fields.first { $0.id == "utf16" })
        #expect(utf16Field.note == "JavaScript string length")
    }

    @Test func presentationIsFields() throws {
        let out = try run("test")
        #expect(out.presentation == .fields)
    }

    @Test func missingInput() throws {
        let cmd = try #require(TextTools.commands.first { $0.id == "text.count" })
        if case .needsInput = cmd.run(ToolRequest(input: .none)) {} else {
            Issue.record("Expected needsInput")
        }
    }

    @Test func emojiGraphemeClusters() throws {
        // Family emoji: 👨‍👩‍👧‍👦 = multiple scalars, 1 grapheme cluster
        let family = "👨‍👩‍👧‍👦"
        let out = try run(family)
        #expect(try field(out, id: "characters") == "1")
        #expect(try field(out, id: "words") == "1")
        // Scalars should be > 1 (base emoji + ZWJs + additional emojis)
        let scalarCount = Int(try field(out, id: "scalars"))!
        #expect(scalarCount > 1)
    }

    @Test func crOnlyLineEnding() throws {
        let out = try run("a\rb")
        #expect(try field(out, id: "lines") == "2")
        #expect(try field(out, id: "utf8") == "3")
    }

    @Test func statusPluralization() throws {
        let out1 = try run("a")
        #expect(out1.status == "1 character")
        let out2 = try run("ab")
        #expect(out2.status == "2 characters")
    }
}
