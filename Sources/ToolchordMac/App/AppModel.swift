import AppKit
import Observation

/// App-wide state shown in Settings, the welcome window, and the menu bar:
/// the shortcut and whether macOS accepted it, and the login item.
@MainActor
@Observable
final class AppModel {
    let preferences: AppPreferences
    /// Why the current shortcut is not active, if it is not.
    private(set) var shortcutProblem: String?
    private(set) var loginItemState: LoginItem.State = .disabled
    private(set) var loginItemError: String?
    /// Called after the shortcut changes so the menu bar can update.
    @ObservationIgnored var onShortcutChange: (() -> Void)?

    init(preferences: AppPreferences) {
        self.preferences = preferences
    }

    var shortcut: KeyboardShortcut { preferences.shortcut }

    var isShortcutActive: Bool {
        if case .registered(let active) = HotKeyCenter.shared.registration { return active == preferences.shortcut }
        return false
    }

    /// Registers the stored shortcut. If the built-in default is rejected
    /// (macOS 15.0–15.1 refused Option-only hotkeys in sandboxed apps), falls
    /// back to ⌃⌥⌘Space and keeps the menu bar entry available either way.
    func registerStoredShortcut() {
        let result = HotKeyCenter.shared.register(preferences.shortcut)
        if case .failed = result, !preferences.hasStoredShortcut {
            let fallback = KeyboardShortcut.controlOptionCommandSpace
            if case .registered = HotKeyCenter.shared.register(fallback) {
                preferences.shortcut = fallback
            }
        }
        refreshShortcutProblem()
    }

    /// Tries a new shortcut; keeps it only if macOS accepts it.
    @discardableResult
    func setShortcut(_ shortcut: KeyboardShortcut) -> Bool {
        let previous = preferences.shortcut
        switch HotKeyCenter.shared.register(shortcut) {
        case .registered:
            preferences.shortcut = shortcut
            shortcutProblem = nil
            onShortcutChange?()
            return true
        case .failed(_, let status):
            shortcutProblem = HotKeyCenter.failureMessage(for: status, shortcut: shortcut)
            HotKeyCenter.shared.register(previous)
            onShortcutChange?()
            return false
        case .none:
            return false
        }
    }

    func reportRecorderProblem(_ message: String) {
        shortcutProblem = message
    }

    private func refreshShortcutProblem() {
        switch HotKeyCenter.shared.registration {
        case .registered: shortcutProblem = nil
        case .failed(let shortcut, let status): shortcutProblem = HotKeyCenter.failureMessage(for: status, shortcut: shortcut)
        case .none: shortcutProblem = "No shortcut is registered. Open Toolchord from the menu bar or record a shortcut."
        }
        onShortcutChange?()
    }

    // MARK: Login item

    func refreshLoginItem() {
        loginItemState = LoginItem.state
    }

    func setOpensAtLogin(_ enabled: Bool) {
        loginItemError = LoginItem.setEnabled(enabled)
        refreshLoginItem()
    }
}
