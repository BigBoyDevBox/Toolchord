import AppKit
import SwiftUI
import ToolchordCore

/// Remembers the AppKit views that the controller moves focus between.
@MainActor
final class PaletteFocus {
    weak var searchField: SearchTextField?
    weak var inputEditor: CodeTextView?
    weak var resultView: CodeTextView?

    func focusSearch() {
        guard let searchField, let window = searchField.window else { return }
        if window.firstResponder !== searchField.currentEditor() {
            window.makeFirstResponder(searchField)
        }
        // Put the caret at the end instead of selecting the whole query.
        if let editor = searchField.currentEditor() {
            editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0)
        }
    }

    func focusEditor() {
        guard let inputEditor, let window = inputEditor.window else { return }
        window.makeFirstResponder(inputEditor)
    }

    func focusResult() {
        guard let resultView, let window = resultView.window else { return }
        window.makeFirstResponder(resultView)
    }
}

/// A plain-text code view. As an input editor it is editable with native
/// undo, find, and IME; as a result view it is read-only but selectable.
/// Escape goes back (after any IME composition), and Tab moves focus;
/// Option-Tab inserts a tab character.
final class CodeTextView: NSTextView {
    override func cancelOperation(_ sender: Any?) {
        if hasMarkedText() {
            super.cancelOperation(sender)
        } else {
            (window as? PalettePanel)?.commandHandler?.escape()
        }
    }

    override func complete(_ sender: Any?) {
        cancelOperation(sender)
    }

    override func insertTab(_ sender: Any?) {
        window?.selectNextKeyView(self)
    }

    override func insertBacktab(_ sender: Any?) {
        window?.selectPreviousKeyView(self)
    }

    static func makeScrollable(editable: Bool) -> (NSScrollView, CodeTextView) {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = CodeTextView(frame: scrollView.contentView.bounds)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = editable
        textView.isEditable = editable
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.font = Theme.codeFont
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.lineFragmentPadding = 2
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = Theme.codeLineHeight
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [.font: Theme.codeFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        scrollView.documentView = textView
        return (scrollView, textView)
    }
}

/// The editable input editor for the expanded tool view.
struct InputEditor: NSViewRepresentable {
    let text: String
    let accessibilityLabel: String
    let focus: PaletteFocus
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = CodeTextView.makeScrollable(editable: true)
        textView.delegate = context.coordinator
        textView.string = text
        textView.setAccessibilityLabel(accessibilityLabel)
        context.coordinator.lastText = text
        focus.inputEditor = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        guard let textView = scrollView.documentView as? CodeTextView else { return }
        focus.inputEditor = textView
        // Only replace the text when it changed outside the editor, so typing
        // never loses the caret or undo history.
        if text != context.coordinator.lastText && text != textView.string {
            textView.string = text
            context.coordinator.lastText = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: (String) -> Void
        var lastText = ""

        init(onChange: @escaping (String) -> Void) {
            self.onChange = onChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !textView.hasMarkedText() else { return }
            lastText = textView.string
            onChange(textView.string)
        }
    }
}

/// A read-only, selectable, syntax-colored result.
struct ResultTextView: NSViewRepresentable {
    let text: String
    let syntax: SyntaxKind
    let dimmed: Bool
    let accessibilityLabel: String
    var focus: PaletteFocus?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = CodeTextView.makeScrollable(editable: false)
        textView.setAccessibilityLabel(accessibilityLabel)
        apply(to: textView, coordinator: context.coordinator)
        focus?.resultView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CodeTextView else { return }
        focus?.resultView = textView
        textView.setAccessibilityLabel(accessibilityLabel)
        apply(to: textView, coordinator: context.coordinator)
    }

    private func apply(to textView: CodeTextView, coordinator: Coordinator) {
        if coordinator.text != text || coordinator.syntax != syntax {
            coordinator.text = text
            coordinator.syntax = syntax
            textView.textStorage?.setAttributedString(SyntaxHighlighter.attributedString(for: text, syntax: syntax))
            textView.scroll(.zero)
        }
        textView.alphaValue = dimmed ? 0.45 : 1
    }

    final class Coordinator {
        var text: String?
        var syntax: SyntaxKind?
    }
}
