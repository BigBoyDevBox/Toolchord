import Foundation
import Testing
import ToolchordCore
@testable import ToolchordSession

/// An evaluator that holds every evaluation until the test releases it, so
/// tests control completion order.
actor GatedEvaluator: ToolEvaluating {
    private var waiting: [(text: String?, resume: CheckedContinuation<Void, Never>)] = []

    func evaluate(_ command: ToolCommand, _ request: ToolRequest) async -> ToolResult {
        await withCheckedContinuation { continuation in
            waiting.append((request.input.text, continuation))
        }
        return command.run(request)
    }

    var pendingInputs: [String?] { waiting.map(\.text) }

    func waitForPending(_ count: Int) async {
        while waiting.count < count { await Task.yield() }
    }

    /// Releases the pending evaluation whose input is `text`.
    func release(input text: String?) {
        guard let index = waiting.firstIndex(where: { $0.text == text }) else { return }
        waiting.remove(at: index).resume.resume()
    }

    func releaseAll() {
        let all = waiting
        waiting.removeAll()
        for item in all { item.resume.resume() }
    }
}

/// Evaluates immediately on the calling task.
struct InlineEvaluator: ToolEvaluating {
    func evaluate(_ command: ToolCommand, _ request: ToolRequest) async -> ToolResult {
        command.run(request)
    }
}

@MainActor
@Suite struct PaletteSessionTests {
    let clipboard = MemoryClipboard()
    let preferences = MemoryPreferences()

    func makeSession(evaluator: any ToolEvaluating = InlineEvaluator()) -> PaletteSession {
        let session = PaletteSession(
            evaluator: evaluator,
            clipboard: clipboard,
            preferences: preferences,
            clock: { Date(timeIntervalSince1970: 1_700_000_000) },
            timeZone: { TimeZone(identifier: "UTC")! }
        )
        session.editDebounce = .zero
        return session
    }

    private func settle(_ session: PaletteSession) async {
        await session.waitForIdle()
    }

    // MARK: Paste, preview, and Copy & Close

    @Test func pastedJSONSuggestsFormatterAndCopiesThePreview() async {
        let session = makeSession()
        session.attach(#"{"status":200,"cache":"HIT"}"#)
        await settle(session)
        #expect(session.listing.sections.first?.title == "Suggested for JSON")
        #expect(session.selectedID == "json.format")
        #expect(session.copyTitle == "Copy JSON & Close")
        #expect(session.copyPrimary() == .copied)
        #expect(clipboard.text == "{\n  \"status\": 200,\n  \"cache\": \"HIT\"\n}")
        #expect(preferences.recentCommandIDs == ["json.format"])
    }

    @Test func invalidInputCannotBeCopiedAndFixingItRestoresCopy() async {
        let session = makeSession()
        session.attach("{\n  \"a\": }")
        await settle(session)
        #expect(!session.canCopy)
        #expect(session.copyPrimary() == .unavailable)
        #expect(clipboard.writes.isEmpty)
        if case .ready(.invalid(let diagnostic)) = session.preview {
            #expect(diagnostic.location == TextLocation(line: 2, column: 8))
        } else {
            Issue.record("Expected an invalid result, got \(session.preview)")
        }
        session.openSelected()
        session.editInput("{\n  \"a\": 1 }")
        await settle(session)
        #expect(session.canCopy)
    }

    @Test func pasteKeepsTheQueryAndReplacesTheAttachment() async {
        let session = makeSession()
        session.setQuery("minify")
        session.attach(#"{"a": 1}"#)
        session.attach(#"{"b": 2}"#)
        await settle(session)
        #expect(session.query == "minify")
        #expect(session.payload?.text == #"{"b": 2}"#)
        #expect(session.selectedID == "json.minify")
        #expect(session.copyableOutput?.primaryText == #"{"b":2}"#)
    }

    @Test func clipboardWithoutTextKeepsThePayload() async {
        let session = makeSession()
        session.attach("abc")
        session.rejectPaste()
        #expect(session.payload?.text == "abc")
        #expect(session.notice?.kind == .error)
    }

    @Test func failedClipboardWriteKeepsThePanelOpen() async {
        let session = makeSession()
        session.attach(#"{"a":1}"#)
        await settle(session)
        clipboard.failsWrites = true
        #expect(session.copyPrimary() == .failed)
        #expect(session.notice?.kind == .error)
        #expect(session.payload != nil)
    }

    @Test func emptyAttachmentIsRealInput() async {
        let session = makeSession()
        session.attach("")
        session.setQuery("decode base64")
        await settle(session)
        #expect(session.selectedID == "base64.decode")
        #expect(session.copyableOutput?.primaryText == "")
        #expect(session.copyPrimary() == .copied)
        #expect(clipboard.text == "")
    }

    // MARK: Stale results

    @Test func staleCompletionsNeverPublish() async {
        let gate = GatedEvaluator()
        let session = makeSession(evaluator: gate)
        session.setQuery("minify json")
        session.attach(#"{"a": 1}"#)
        await gate.waitForPending(1)
        #expect(!session.canCopy)
        session.attach(#"{"b": 2}"#)
        await gate.waitForPending(2)

        await gate.release(input: #"{"b": 2}"#)
        await settle(session)
        #expect(session.copyableOutput?.primaryText == #"{"b":2}"#)

        await gate.release(input: #"{"a": 1}"#)
        for _ in 0..<20 { await Task.yield() }
        #expect(session.copyableOutput?.primaryText == #"{"b":2}"#)
        #expect(session.copyPrimary() == .copied)
        #expect(clipboard.text == #"{"b":2}"#)
    }

    @Test func completionsFromAnEndedSessionNeverPublish() async {
        let gate = GatedEvaluator()
        let session = makeSession(evaluator: gate)
        session.attach(#"{"a": 1}"#)
        await gate.waitForPending(1)
        session.end()
        await gate.releaseAll()
        for _ in 0..<20 { await Task.yield() }
        #expect(session.payload == nil)
        #expect(!session.canCopy)
        #expect(session.copyPrimary() == .unavailable)
        #expect(clipboard.writes.isEmpty)
    }

    @Test func changingOptionsInvalidatesTheResultUntilReevaluated() async {
        let gate = GatedEvaluator()
        let session = makeSession(evaluator: gate)
        session.attach(#"{"a":1}"#)
        await gate.waitForPending(1)
        await gate.releaseAll()
        await settle(session)
        #expect(session.canCopy)
        session.setOption("indent", to: "4", for: "json.format")
        #expect(!session.canCopy)
        await gate.waitForPending(1)
        await gate.releaseAll()
        await settle(session)
        #expect(session.copyableOutput?.primaryText == "{\n    \"a\": 1\n}")
    }

    @Test func clearingInputImmediatelyInvalidatesTheResult() async {
        let session = makeSession()
        session.attach(#"{"a":1}"#)
        await settle(session)
        session.clearInput()
        #expect(!session.canCopy)
        if case .ready(.needsInput) = session.preview {} else { Issue.record("Expected needsInput, got \(session.preview)") }
    }

    // MARK: Selection and search

    @Test func explicitQueryOutranksDetection() async {
        let session = makeSession()
        session.attach(#"{"a":1}"#)
        session.setQuery("guid")
        await settle(session)
        #expect(session.selectedID == "uuid.v4")
        #expect(session.copyTitle == "Copy UUID & Close")
    }

    @Test func explicitSelectionSurvivesCompatibleInput() async {
        let session = makeSession()
        session.attach(#"{"a":1}"#)
        session.select("json.validate")
        session.attach(#"{"b":2}"#)
        #expect(session.selectedID == "json.validate")
        // New input with different suggestions replaces an incompatible choice.
        session.attach("1700000000")
        #expect(session.selectedID == "time.fromUnix")
    }

    @Test func arrowNavigationIsClamped() {
        let session = makeSession()
        session.setQuery("json")
        let ids = session.listing.orderedIDs
        session.moveSelection(by: -1)
        #expect(session.selectedID == ids.first)
        session.moveSelection(by: 100)
        #expect(session.selectedID == ids.last)
    }

    @Test func noMatchesLeaveNothingSelected() {
        let session = makeSession()
        session.attach("abc")
        session.setQuery("zzzzqqq")
        #expect(session.listing.isEmpty)
        #expect(session.selectedID == nil)
        #expect(session.preview == .none)
        #expect(session.payload?.text == "abc")
    }

    @Test func pastedCommandTextCanBecomeTheQuery() {
        let session = makeSession()
        session.attach("json format")
        #expect(session.canUseAsSearchText)
        session.useAsSearchText()
        #expect(session.query == "json format")
        #expect(session.payload == nil)
        #expect(session.selectedID == "json.format")
        session.attach("{ not a command }")
        #expect(!session.canUseAsSearchText)
    }

    @Test func recentToolsComeFirstWithoutInput() {
        preferences.recordUse(of: "uuid.v4")
        let session = makeSession()
        #expect(session.listing.sections.first?.title == "Recent")
        #expect(session.selectedID == "uuid.v4")
    }

    // MARK: Generated values

    @Test func generatedValueStaysStableUntilRegenerated() async throws {
        let session = makeSession()
        session.setQuery("generate uuid")
        await settle(session)
        let first = try #require(session.copyableOutput?.primaryText)
        session.setQuery("json")
        session.setQuery("generate uuid")
        session.openSelected()
        session.back()
        await settle(session)
        #expect(session.copyableOutput?.primaryText == first)
        session.regenerate()
        await settle(session)
        let second = try #require(session.copyableOutput?.primaryText)
        #expect(second != first)
        session.end()
        session.setQuery("generate uuid")
        await settle(session)
        #expect(session.copyableOutput?.primaryText != second)
    }

    // MARK: Escape and the draft

    @Test func escapeClosesActionsThenLeavesTheToolThenDismisses() async {
        let session = makeSession()
        session.attach(#"{"a":1}"#)
        session.openSelected()
        session.toggleActionsMenu()
        #expect(session.escape() == .closedActions)
        #expect(session.escape() == .returnedToSearch)
        #expect(session.payload?.text == #"{"a":1}"#)
        #expect(session.escape() == .dismiss)
    }

    @Test func backPreservesTheDraftAndEndClearsIt() async {
        let session = makeSession()
        session.setQuery("format")
        session.attach(#"{"a":1}"#)
        session.setOption("indent", to: "tab", for: "json.format")
        session.openSelected()
        session.editInput(#"{"a":2}"#)
        session.back()
        #expect(session.query == "format")
        #expect(session.payload?.text == #"{"a":2}"#)
        #expect(session.payload?.source == .edited)
        #expect(session.options(for: "json.format").choice("indent", default: "2") == "tab")
        let oldID = session.sessionID
        session.end()
        #expect(session.sessionID != oldID)
        #expect(session.query.isEmpty && session.payload == nil && session.chosenOptions.isEmpty && session.seeds.isEmpty)
        #expect(session.mode == .search)
    }

    @Test func fieldCopyKeepsTheSession() async {
        let session = makeSession()
        session.setQuery("inspect url")
        session.attach("https://example.test/?a=1&a=2")
        await settle(session)
        #expect(session.copyField("param-1") == .copied)
        #expect(clipboard.text == "2")
        #expect(session.payload != nil)
        #expect(session.copyField("missing") == .unavailable)
    }

    @Test func preferencesSupplyDefaultOptions() async {
        preferences.overrides["json.format"] = ToolOptions(["indent": "4"])
        let session = makeSession()
        session.attach(#"{"a":1}"#)
        await settle(session)
        #expect(session.copyableOutput?.primaryText == "{\n    \"a\": 1\n}")
    }
}

@MainActor
@Suite struct PaletteSessionLifecycleTests {
    @Test func noWorkUntilActivatedAndNoneAfterEnd() async {
        let preferences = MemoryPreferences(recentCommandIDs: ["uuid.v4"])
        let session = PaletteSession(evaluator: InlineEvaluator(), clipboard: MemoryClipboard(), preferences: preferences)
        #expect(session.selectedID == "uuid.v4")
        #expect(session.seeds.isEmpty)
        #expect(session.preview == .none)
        session.activate()
        await session.waitForIdle()
        #expect(session.seeds["uuid.v4"] != nil)
        #expect(session.canCopy)
        session.end()
        await session.waitForIdle()
        #expect(session.seeds.isEmpty)
        #expect(!session.canCopy)
        #expect(session.preview == .none)
    }

    @Test func oversizedPasteIsNotScannedAndCannotBeCopied() async {
        let limits = ToolLimits(maxInputBytes: 16)
        let session = PaletteSession(evaluator: InlineEvaluator(), clipboard: MemoryClipboard(), preferences: MemoryPreferences(), limits: limits)
        session.activate()
        session.attach(#"{"a": "this is longer than sixteen bytes"}"#)
        await session.waitForIdle()
        #expect(session.payload?.exceedsLimit == true)
        #expect(session.payload?.profile.kinds == [.text])
        #expect(!session.canCopy)
        if case .ready(.tooLarge) = session.preview {} else { Issue.record("Expected tooLarge, got \(session.preview)") }
    }
}

/// Counts evaluator calls, for checking that one change schedules one evaluation.
actor CountingEvaluator: ToolEvaluating {
    private(set) var calls: [String] = []

    func evaluate(_ command: ToolCommand, _ request: ToolRequest) async -> ToolResult {
        calls.append(command.id)
        return command.run(request)
    }
}

@MainActor
@Suite struct PaletteSessionReviewTests {
    /// Review P2: "é" and "e" + U+0301 are equal Swift strings but different bytes.
    @Test func canonicallyEquivalentEditsReevaluate() async {
        let clipboard = MemoryClipboard()
        let session = PaletteSession(evaluator: InlineEvaluator(), clipboard: clipboard, preferences: MemoryPreferences())
        session.editDebounce = .zero
        session.activate()
        session.setQuery("encode base64")
        session.attach("\u{E9}")
        await session.waitForIdle()
        #expect(session.copyableOutput?.primaryText == "w6k=")
        session.openSelected()
        session.editInput("e\u{301}")
        await session.waitForIdle()
        #expect(session.copyPrimary() == .copied)
        #expect(Array((clipboard.text ?? "").utf8) == Array("ZcyB".utf8))
    }

    /// Review P2: a paste that changes the selected command evaluated twice.
    @Test func eachChangeEvaluatesOnce() async {
        let counter = CountingEvaluator()
        let session = PaletteSession(evaluator: counter, clipboard: MemoryClipboard(), preferences: MemoryPreferences())
        session.editDebounce = .zero
        session.activate()
        await session.waitForIdle()
        let before = await counter.calls.count
        session.attach("<r><a/></r>")
        await session.waitForIdle()
        #expect(session.selectedID == "xml.format")
        #expect(await counter.calls.count == before + 1)

        session.attach("json format")
        session.useAsSearchText()
        await session.waitForIdle()
        let afterSearch = await counter.calls.count
        session.attach(#"{"a":1}"#)
        await session.waitForIdle()
        #expect(await counter.calls.count == afterSearch + 1)
        session.clearInput()
        await session.waitForIdle()
        #expect(await counter.calls.count == afterSearch + 1, "Missing input needs no evaluator call")
    }
}
