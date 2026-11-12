import AppKit
import Carbon.HIToolbox

/// Registers one global shortcut with the Carbon Event Manager.
///
/// `RegisterEventHotKey` needs no Accessibility or Input Monitoring
/// permission and works in the App Sandbox. The handler runs on the main
/// thread.
@MainActor
public final class HotKeyCenter {
    public enum Registration: Equatable, Sendable {
        case registered(KeyboardShortcut)
        case failed(KeyboardShortcut, status: Int32)
        case none
    }

    public static let shared = HotKeyCenter()

    /// Called on the main thread when the registered shortcut is pressed.
    public var onPress: (() -> Void)?
    public private(set) var registration: Registration = .none

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let signature: OSType = 0x5443_4844 // "TCHD"

    private init() {}

    /// Replaces any current registration. Returns whether it succeeded.
    @discardableResult
    public func register(_ shortcut: KeyboardShortcut) -> Registration {
        unregister()
        installHandlerIfNeeded()
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr, let reference {
            hotKeyRef = reference
            registration = .registered(shortcut)
        } else {
            registration = .failed(shortcut, status: status)
        }
        return registration
    }

    /// Removes the registration, for example while recording a new shortcut.
    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        registration = .none
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var identifier = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &identifier
            )
            guard status == noErr, identifier.signature == 0x5443_4844 else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                HotKeyCenter.shared.onPress?()
            }
            return noErr
        }, 1, &eventType, nil, &handlerRef)
    }

    /// A user-facing explanation for a failed registration.
    public static func failureMessage(for status: Int32, shortcut: KeyboardShortcut) -> String {
        switch Int(status) {
        case eventHotKeyExistsErr:
            return "\(shortcut.displayString) is already used by another app. Choose a different shortcut."
        case eventInternalErr where shortcut.modifierFlags.isSubset(of: [.option, .shift]):
            return "This version of macOS doesn’t allow shortcuts that use only Option and Shift. Add ⌘ or ⌃."
        default:
            return "macOS couldn’t register \(shortcut.displayString) (error \(status)). Choose a different shortcut."
        }
    }
}
