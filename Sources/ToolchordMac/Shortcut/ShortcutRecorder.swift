import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A control that records a global shortcut. Click (or press Space when it
/// has focus) to start recording, then press the combination; Escape cancels.
/// The global hotkey is suspended while recording, so the current shortcut
/// can be recorded again.
final class ShortcutRecorderControl: NSControl {
    var shortcut: KeyboardShortcut? { didSet { needsDisplay = true; updateAccessibility() } }
    var onRecord: ((KeyboardShortcut) -> Void)?
    var onProblem: ((String) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?

    private(set) var isRecording = false {
        didSet {
            needsDisplay = true
            updateAccessibility()
            onRecordingChange?(isRecording)
        }
    }

    private var pendingModifiers: NSEvent.ModifierFlags = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.button)
        setAccessibilityHelp("Press to record a new shortcut, then type the key combination. Press Escape to cancel.")
        focusRingType = .exterior
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 168, height: 26) }
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording ? cancelRecording() : startRecording()
    }

    override func accessibilityPerformPress() -> Bool {
        // Take focus first, like a click, so the keystrokes reach the recorder.
        window?.makeFirstResponder(self)
        isRecording ? cancelRecording() : startRecording()
        return true
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { cancelRecording() }
        return super.resignFirstResponder()
    }

    private var windowObservers: [NSObjectProtocol] = []

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        // Closing Settings mid-recording must restore the global shortcut.
        if isRecording { cancelRecording() }
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers = []
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        for name in [NSWindow.willCloseNotification, NSWindow.didResignKeyNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if self?.isRecording == true { self?.cancelRecording() }
                }
            })
        }
    }

    func startRecording() {
        pendingModifiers = []
        isRecording = true
    }

    func cancelRecording() {
        pendingModifiers = []
        isRecording = false
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return super.flagsChanged(with: event) }
        pendingModifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        needsDisplay = true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            if event.keyCode == UInt16(kVK_Space) || event.keyCode == UInt16(kVK_Return) {
                startRecording()
            } else {
                super.keyDown(with: event)
            }
            return
        }
        record(event)
    }

    private func record(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == UInt16(kVK_Escape) && flags.isEmpty {
            cancelRecording()
            return
        }
        let candidate = KeyboardShortcut(keyCode: event.keyCode, modifierFlags: flags)
        switch candidate.problem {
        case .needsModifier:
            onProblem?("Include ⌘, ⌃, or ⌥ in the shortcut.")
            NSSound.beep()
        case .reserved(let reason):
            onProblem?("\(candidate.displayString) is reserved: \(reason)")
            NSSound.beep()
        case nil:
            pendingModifiers = []
            shortcut = candidate
            // Register the new shortcut before recording ends, so ending does
            // not restore the previous one.
            onRecord?(candidate)
            isRecording = false
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text: String
        let color: NSColor
        if isRecording {
            let modifiers = KeyboardShortcut(keyCode: 0, carbonModifiers: KeyboardShortcut.carbonFlags(from: pendingModifiers)).modifierSymbols
            text = modifiers.isEmpty ? "Type shortcut…" : modifiers
            color = .secondaryLabelColor
        } else {
            text = shortcut?.displayString ?? "Record Shortcut"
            color = shortcut == nil ? .secondaryLabelColor : .labelColor
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: color,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }

    private func updateAccessibility() {
        if isRecording {
            setAccessibilityLabel("Recording shortcut. Type the key combination.")
        } else {
            setAccessibilityLabel("Shortcut \(shortcut?.accessibilityLabel ?? "none"). Press to record a new shortcut.")
        }
    }
}

/// SwiftUI wrapper for ``ShortcutRecorderControl``.
struct ShortcutRecorder: NSViewRepresentable {
    static func dismantleNSView(_ control: ShortcutRecorderControl, coordinator: ()) {
        if control.isRecording { control.cancelRecording() }
    }

    let shortcut: KeyboardShortcut
    let onRecord: (KeyboardShortcut) -> Void
    let onProblem: (String) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let control = ShortcutRecorderControl()
        control.shortcut = shortcut
        configure(control)
        return control
    }

    func updateNSView(_ control: ShortcutRecorderControl, context: Context) {
        if control.shortcut != shortcut && !control.isRecording {
            control.shortcut = shortcut
        }
        configure(control)
    }

    private func configure(_ control: ShortcutRecorderControl) {
        control.onRecord = onRecord
        control.onProblem = onProblem
        control.onRecordingChange = { recording in
            // Suspend the global hotkey while recording so its own combination can be captured.
            if recording {
                HotKeyCenter.shared.unregister()
            } else if case .none = HotKeyCenter.shared.registration {
                HotKeyCenter.shared.register(shortcut)
            }
        }
    }
}
