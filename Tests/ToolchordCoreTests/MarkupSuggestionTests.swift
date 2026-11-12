import Testing
@testable import ToolchordCore

/// The plain-text and Markdown tools rank first for the input they convert
/// and stay out of the way for other input.
@Suite struct MarkupSuggestionTests {
    /// Suggested command IDs in the order the palette lists them: affinity
    /// of at least 30, highest first, ties in catalog order.
    private func suggestions(_ text: String) -> [String] {
        let profile = InputDetector.profile(for: text)
        return ToolCatalog.commands.enumerated()
            .map { (index: $0.offset, id: $0.element.id, affinity: $0.element.affinity(profile)) }
            .filter { $0.affinity >= 30 }
            .sorted { ($0.affinity, -$0.index) > ($1.affinity, -$1.index) }
            .map(\.id)
    }

    @Test func markdownSuggestsRenderingFirst() {
        let ids = suggestions("# Title\n\n- one\n- two\n\nSee [docs](https://example.com).")
        #expect(Array(ids.prefix(2)) == ["markdown.html", "markdown.plaintext"])
        #expect(!ids.contains("html.plaintext"))
        #expect(ids.contains("text.count"))
    }

    @Test func htmlSuggestsPlainTextBeforeXML() {
        let ids = suggestions("<!DOCTYPE html><html><body><p>Hi</p></body></html>")
        #expect(ids.first == "html.plaintext")
        #expect(ids.contains("xml.format") && ids.contains("html.escape"))
        #expect(!ids.contains("markdown.html"))
    }

    @Test func xmlIsNotHTML() {
        let ids = suggestions("<config><item>1</item></config>")
        #expect(ids.first == "xml.format")
        #expect(!ids.contains("html.plaintext"))
    }

    @Test func copiedProseSuggestsMakePlainText() {
        #expect(suggestions("It’s “quoted” text").first == "plaintext.clean")
        #expect(suggestions("ls\u{00A0}-la").first == "plaintext.clean")
        #expect(!suggestions("plain ASCII text").contains("plaintext.clean"))
    }

    @Test func searchFindsEachToolByItsUsualName() {
        func top(_ query: String) -> String? { CommandSearch.search(query, in: ToolCatalog.commands).first?.id }
        #expect(top("plain text") == "plaintext.clean")
        #expect(top("paste as plain text") == "plaintext.clean")
        #expect(top("zero width space") == "plaintext.clean")
        #expect(top("strip html") == "html.plaintext")
        #expect(top("html to text") == "html.plaintext")
        #expect(top("markdown to html") == "markdown.html")
        #expect(top("markdown") == "markdown.html")
        #expect(top("md to text") == "markdown.plaintext")
        #expect(top("strip markdown") == "markdown.plaintext")
    }

    @Test func jsonStillLeadsWhenItHasSmartQuotes() {
        let ids = suggestions(#"{"a": "“x”"}"#)
        #expect(ids.first == "json.format")
        #expect(ids.contains("plaintext.clean"))
    }
}
