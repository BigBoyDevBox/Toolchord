import AppKit
import Carbon.HIToolbox

/// Keyboard commands the panel routes to its controller.
@MainActor
protocol PaletteCommandHandling: AnyObject {
    func copyAndClose()
    func copyWithoutClosing()
    func showActions()
    func openSettings()
    func regenerate()
    func clearInput()
    func escape()
    func dismissPanel()
    /// The search field's field editor received a paste command.
    func pasteIntoSearch()
}

/// A borderless, non-activating floating panel.
///
/// `.nonactivatingPanel` must be part of the style mask at initialization:
/// AppKit tags the window for WindowServer only then. The panel becomes key
/// without activating Toolchord, so the app the user was working in keeps
/// its menu bar and regains keyboard focus as soon as the panel closes.
final class PalettePanel: NSPanel {
    weak var commandHandler: PaletteCommandHandling?
    /// The custom field editor for the search field.
    private lazy var searchFieldEditor: SearchFieldEditor = {
        let editor = SearchFieldEditor()
        editor.isFieldEditor = true
        return editor
    }()

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 760, height: 460),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .canJoinAllApplications]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        worksWhenModal = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .utilityWindow
        titleVisibility = .hidden
        setAccessibilityLabel("Toolchord")
        setAccessibilitySubrole(.floatingWindow)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Gives the search field a field editor that routes Paste to the session.
    func fieldEditor(for client: Any?) -> NSText? {
        guard client is SearchTextField else { return nil }
        searchFieldEditor.searchField = client as? SearchTextField
        return searchFieldEditor
    }

    override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        if let editor = fieldEditor(for: object) { return editor }
        return super.fieldEditor(createFlag, for: object)
    }

    override func cancelOperation(_ sender: Any?) {
        commandHandler?.escape()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        // While an input method is composing, its marked text is not part of
        // the input yet; leave every key to the input method.
        if let textView = firstResponder as? NSTextView, textView.hasMarkedText() {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let key = Int(event.keyCode)
        let isReturn = key == kVK_Return || key == kVK_ANSI_KeypadEnter

        switch (flags, key) {
        case ([.command], _) where isReturn:
            commandHandler?.copyAndClose()
            return true
        case ([.command, .shift], _) where isReturn:
            commandHandler?.copyWithoutClosing()
            return true
        case ([.command], kVK_ANSI_K):
            commandHandler?.showActions()
            return true
        case ([.command], kVK_ANSI_Comma):
            commandHandler?.openSettings()
            return true
        case ([.command], kVK_ANSI_R):
            commandHandler?.regenerate()
            return true
        case ([.command, .shift], kVK_Delete):
            commandHandler?.clearInput()
            return true
        case ([.command], kVK_ANSI_W):
            commandHandler?.dismissPanel()
            return true
        default:
            break
        }

        if super.performKeyEquivalent(with: event) { return true }

        // Accessory apps may not route standard editing shortcuts through a
        // main menu while another app is active; send them directly.
        let editingAction: Selector?
        switch (flags, key) {
        case ([.command], kVK_ANSI_X): editingAction = #selector(NSText.cut(_:))
        case ([.command], kVK_ANSI_C): editingAction = #selector(NSText.copy(_:))
        case ([.command], kVK_ANSI_V): editingAction = #selector(NSText.paste(_:))
        case ([.command], kVK_ANSI_A): editingAction = #selector(NSText.selectAll(_:))
        case ([.command], kVK_ANSI_Z): editingAction = Selector(("undo:"))
        case ([.command, .shift], kVK_ANSI_Z): editingAction = Selector(("redo:"))
        case ([.command], kVK_ANSI_F): editingAction = #selector(NSResponder.performTextFinderAction(_:))
        default: editingAction = nil
        }
        if let editingAction {
            if editingAction == #selector(NSResponder.performTextFinderAction(_:)) {
                let item = NSMenuItem()
                item.tag = NSTextFinder.Action.showFindInterface.rawValue
                return NSApp.sendAction(editingAction, to: firstResponder, from: item)
            }
            return NSApp.sendAction(editingAction, to: nil, from: self)
        }
        return false
    }
}

/// The search field. Arrow keys, Return, and Escape are handled by its
/// delegate; Paste is handled by ``SearchFieldEditor``.
final class SearchTextField: NSTextField {
    override var acceptsFirstResponder: Bool { true }
}

/// Field editor for the search field: Paste attaches the clipboard text as
/// input instead of inserting it into the query.
final class SearchFieldEditor: NSTextView {
    weak var searchField: SearchTextField?

    private var handler: PaletteCommandHandling? {
        (window as? PalettePanel)?.commandHandler
    }

    override func paste(_ sender: Any?) {
        handler?.pasteIntoSearch() ?? super.paste(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        paste(sender)
    }

    override func pasteAsRichText(_ sender: Any?) {
        paste(sender)
    }
}
