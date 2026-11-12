import Testing
@testable import ToolchordCore

@Suite struct CommandSearchTests {
    private let catalog = ToolCatalog.commands

    private func top(_ query: String, input: String? = nil) -> String? {
        let profile = input.map { InputDetector.profile(for: $0) } ?? .none
        return CommandSearch.search(query, in: catalog, profile: profile).first?.id
    }

    @Test func normalizesCaseSeparatorsAndDiacritics() {
        #expect(CommandSearch.normalize("  Snake_Case  ") == "snake case")
        #expect(CommandSearch.normalize("Décode-URL") == "decode url")
        #expect(CommandSearch.normalize("") == "")
    }

    @Test func aliasesFromThePlanResolve() {
        #expect(top("pretty print") == "json.format")
        #expect(top("epoch") == "time.fromUnix")
        #expect(top("guid") == "uuid.v4")
        #expect(top("json format") == "json.format")
        #expect(top("format json") == "json.format")
    }

    @Test func explicitQueriesOutrankDetection() {
        #expect(top("uuid", input: #"{"a":1}"#) == "uuid.v4")
        #expect(top("decode", input: "SGVsbG8gd29ybGQ=") == "base64.decode")
    }

    @Test func rankOrderIsExactPrefixWordsFuzzy() throws {
        let format = try #require(catalog.first { $0.id == "json.format" })
        #expect(CommandSearch.match("format json", format) == .exact)
        #expect(CommandSearch.match("form", format) == .prefix)
        #expect(CommandSearch.match("json fmt", format) == nil || CommandSearch.match("json fmt", format) == .fuzzy)
        #expect(CommandSearch.match("jso form", format) == .words)
        #expect(CommandSearch.match("frmtjsn", format) == .fuzzy)
        #expect(CommandSearch.match("zzz", format) == nil)
    }

    @Test func groupNamesAreSearchable() {
        let results = CommandSearch.search("base64", in: catalog).map(\.id)
        #expect(results.contains("base64.encode") && results.contains("base64url.decode"))
    }

    @Test func emptyQueryReturnsEverything() {
        #expect(CommandSearch.search("   ", in: catalog).count == catalog.count)
    }

    @Test func plausibleCommandTextIsRecognized() {
        #expect(CommandSearch.plausiblyNamesCommand("json format", in: catalog))
        #expect(CommandSearch.plausiblyNamesCommand("GUID", in: catalog))
        #expect(!CommandSearch.plausiblyNamesCommand("qqqq zzzz", in: catalog))
        #expect(!CommandSearch.plausiblyNamesCommand("", in: catalog))
    }
}
