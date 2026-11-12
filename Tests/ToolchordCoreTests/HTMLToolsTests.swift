import Foundation
import Testing
@testable import ToolchordCore

@Suite struct HTMLToolsTests {

    // ─── Helpers ─────────────────────────────────────────────────────────────

    private func run(_ id: String, _ text: String) throws -> ToolOutput {
        let command = try #require(HTMLTools.commands.first { $0.id == id })
        let result = command.run(ToolRequest(input: .text(text)))
        return try #require(result.output, "Expected success, got \(result)")
    }

    // ─── Escape ──────────────────────────────────────────────────────────────

    @Test func escapeBasic() throws {
        let output = try run("html.escape", "<a href=\"x\">Tom & 'Jerry'</a>")
        #expect(output.primaryText == "&lt;a href=&quot;x&quot;&gt;Tom &amp; &#39;Jerry&#39;&lt;/a&gt;")
        #expect(output.status == "Escaped")
    }

    @Test func escapeEmptyInput() throws {
        let output = try run("html.escape", "")
        #expect(output.primaryText == "")
    }

    @Test func escapeNoSpecialChars() throws {
        let output = try run("html.escape", "Hello world")
        #expect(output.primaryText == "Hello world")
    }

    // ─── Unescape ────────────────────────────────────────────────────────────

    @Test func unescapeMixed() throws {
        let output = try run("html.unescape", "&lt;p&gt;caf&eacute; &amp; cr&#232;me &#x1F600; &unknown;")
        #expect(output.primaryText == "<p>café & crème 😀 &unknown;")
        #expect(output.warnings.count == 1)
        #expect(output.warnings[0] == "Unknown entity “&unknown;” was left unchanged.")
    }

    @Test func unescapeAmpLt() throws {
        // &amp;lt; → first &amp; is decoded to &, then lt; is literal text
        // But in a single left-to-right pass: &amp; → &, then lt; is just text
        let output = try run("html.unescape", "&amp;lt;")
        #expect(output.primaryText == "&lt;")
    }

    @Test func unescapeInvalidZero() throws {
        let output = try run("html.unescape", "&#0;")
        #expect(output.primaryText == "\u{FFFD}")
        #expect(output.warnings.count == 1)
        #expect(output.warnings[0] == "Replaced invalid character reference “&#0;” with U+FFFD.")
    }

    @Test func unescapeNbsp() throws {
        let output = try run("html.unescape", "&nbsp;")
        #expect(output.primaryText == "\u{00A0}")
    }

    @Test func unescapeCaseSensitive() throws {
        let output = try run("html.unescape", "&Eacute;&eacute;")
        #expect(output.primaryText == "Éé")
    }

    @Test func unescapeNoSemicolon() throws {
        // AT&T and &copy — no semicolons, should be left unchanged
        let output = try run("html.unescape", "AT&T and &copy")
        #expect(output.primaryText == "AT&T and &copy")
        #expect(output.warnings.isEmpty)
    }

    @Test func unescapeEmptyInput() throws {
        let output = try run("html.unescape", "")
        #expect(output.primaryText == "")
    }

    @Test func unescapeStatus() throws {
        let output = try run("html.unescape", "&lt;")
        #expect(output.status == "Unescaped")
    }

    // ─── Affinity ────────────────────────────────────────────────────────────

    @Test func escapeAffinity() throws {
        let command = try #require(HTMLTools.commands.first { $0.id == "html.escape" })
        let xmlProfile = InputProfile(isAttached: true, kinds: [.xml], primaryKind: .xml, byteCount: 10, lineCount: 1, isBlank: false)
        let textProfile = InputProfile(isAttached: true, kinds: [.text], primaryKind: .text, byteCount: 10, lineCount: 1, isBlank: false)
        #expect(command.affinity(xmlProfile) == 30)
        #expect(command.affinity(textProfile) == 0)
    }

    @Test func unescapeAffinity() throws {
        let command = try #require(HTMLTools.commands.first { $0.id == "html.unescape" })
        let entitiesProfile = InputProfile(isAttached: true, kinds: [.htmlEntities], primaryKind: .htmlEntities, byteCount: 10, lineCount: 1, isBlank: false)
        let textProfile = InputProfile(isAttached: true, kinds: [.text], primaryKind: .text, byteCount: 10, lineCount: 1, isBlank: false)
        #expect(command.affinity(entitiesProfile) == 85)
        #expect(command.affinity(textProfile) == 0)
    }

    // ─── Edge cases ──────────────────────────────────────────────────────────

    @Test func unescapeSurrogate() throws {
        // &#xD800; is a surrogate → U+FFFD
        let output = try run("html.unescape", "&#xD800;")
        #expect(output.primaryText == "\u{FFFD}")
        #expect(output.warnings.count == 1)
    }

    @Test func unescapeAboveMax() throws {
        // &#x110000; is above 10FFFF → U+FFFD
        let output = try run("html.unescape", "&#x110000;")
        #expect(output.primaryText == "\u{FFFD}")
        #expect(output.warnings.count == 1)
    }

    @Test func unescapeHexCase() throws {
        // &#X1f600; (uppercase X) should work
        let output = try run("html.unescape", "&#X1f600;")
        #expect(output.primaryText == "😀")
    }

    @Test func escapeCopyNoun() throws {
        let command = try #require(HTMLTools.commands.first { $0.id == "html.escape" })
        #expect(command.copyNoun(ToolOptions()) == "HTML")
    }

    @Test func unescapeCopyNoun() throws {
        let command = try #require(HTMLTools.commands.first { $0.id == "html.unescape" })
        #expect(command.copyNoun(ToolOptions()) == "text")
    }
}


@Suite struct HTMLToolsRobustnessTests {
    private func unescape(_ text: String) throws -> ToolOutput {
        let command = try #require(HTMLTools.commands.first { $0.id == "html.unescape" })
        return try #require(command.run(ToolRequest(input: .text(text))).output)
    }

    @Test func malformedNumericReferencesStayLiteral() throws {
        for text in ["&#x;", "&#;", "&#", "&#x", "&#12", "&#x+41;", "&#-1;"] {
            #expect(try unescape(text).primaryText == text)
        }
    }

    @Test func hugeNumbersBecomeReplacementCharacters() throws {
        let output = try unescape("&#99999999999999;")
        #expect(output.primaryText == "\u{FFFD}")
        #expect(output.warnings.count == 1)
    }

    @Test func manyAmpersandsDecodeInLinearTime() throws {
        let text = String(repeating: "&", count: 1 << 20)
        #expect(try unescape(text).primaryText == text)
        let names = String(repeating: "&abcdefghijklmnopqrstuvwxyzabcdefghijkl", count: 20_000)
        #expect(try unescape(names).primaryText == names)
    }
}

@Suite struct HTMLEscapeLimitTests {
    @Test func escapingStopsAtTheOutputLimit() throws {
        let command = try #require(HTMLTools.commands.first { $0.id == "html.escape" })
        let quotes = String(repeating: "\"", count: 1_000_000)
        #expect(command.run(ToolRequest(input: .text(quotes))) == .tooLarge(ToolLimits.standard.outputLimitMessage))
        let cancelled = command.run(ToolRequest(input: .text("<a>"), cancellation: CancellationCheck { true }))
        #expect(cancelled == .cancelled)
    }
}
