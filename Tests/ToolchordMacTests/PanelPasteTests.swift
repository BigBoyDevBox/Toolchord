import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import ToolchordMac

/// ⌘V reaches the controller only when no editable text has focus, as in a
/// generator tool, so the Find field and the editors keep their own Paste.
@MainActor
@Suite struct PanelPasteTests {
    /// A text view that records Paste instead of reading the clipboard.
    final class RecordingTextView: NSTextView {
        private(set) var pastes = 0
        override func paste(_ sender: Any?) { pastes += 1 }
    }

    /// A controller that records each Paste it is asked to handle.
    final class RecordingHandler: PaletteCommandHandling {
        private(set) var pasteRequests = 0
        func copyAndClose() {}
        func copyWithoutClosing() {}
        func showActions() {}
        func openSettings() {}
        func regenerate() {}
        func clearInput() {}
        func escape() {}
        func dismissPanel() {}
        func pasteIntoSearch() {}
        func explainPasteWithoutInput() -> Bool {
            pasteRequests += 1
            return true
        }
    }

    /// The panel with `textView` as its first responder.
    func panel(focusing textView: NSTextView, handler: RecordingHandler) -> PalettePanel {
        let panel = PalettePanel()
        panel.commandHandler = handler
        panel.contentView?.addSubview(textView)
        panel.makeFirstResponder(textView)
        return panel
    }

    func commandV(in panel: NSWindow) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "v",
            charactersIgnoringModifiers: "v", isARepeat: false, keyCode: UInt16(kVK_ANSI_V)
        ))
    }

    @Test func editableTextKeepsItsPaste() throws {
        // The Find field, the input editor, and the search field all edit text.
        let handler = RecordingHandler()
        let findField = RecordingTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 20))
        let panel = panel(focusing: findField, handler: handler)
        defer { panel.close() }
        #expect(panel.firstResponder === findField)
        _ = panel.performKeyEquivalent(with: try commandV(in: panel))
        #expect(handler.pasteRequests == 0)
    }

    @Test func readOnlyTextLetsTheControllerExplain() throws {
        // A generator tool's only text is its read-only result.
        let handler = RecordingHandler()
        let result = RecordingTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 20))
        result.isEditable = false
        let panel = panel(focusing: result, handler: handler)
        defer { panel.close() }
        #expect(panel.firstResponder === result)
        _ = panel.performKeyEquivalent(with: try commandV(in: panel))
        #expect(handler.pasteRequests == 1)
        #expect(result.pastes == 0)
    }
}
