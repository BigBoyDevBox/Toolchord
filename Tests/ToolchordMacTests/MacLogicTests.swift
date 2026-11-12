import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
import ToolchordCore
@testable import ToolchordMac

@MainActor
@Suite struct KeyboardShortcutTests {
    @Test func defaultAvoidsSystemShortcuts() {
        let shortcut = KeyboardShortcut.defaultShortcut
        #expect(shortcut.displayString == "⌥⇧Space")
        #expect(shortcut.problem == nil)
        #expect(shortcut.accessibilityLabel == "Option Shift Space")
    }

    @Test func reservedAndIncompleteShortcutsAreRejected() {
        let space = UInt16(kVK_Space)
        #expect(KeyboardShortcut(keyCode: space, modifierFlags: [.command]).problem == .reserved("⌘Space opens Spotlight."))
        #expect(KeyboardShortcut(keyCode: space, modifierFlags: [.command, .option]).problem != nil)
        #expect(KeyboardShortcut(keyCode: space, modifierFlags: [.control]).problem != nil)
        #expect(KeyboardShortcut(keyCode: space, modifierFlags: [.shift]).problem == .needsModifier)
        #expect(KeyboardShortcut(keyCode: UInt16(kVK_ANSI_A), modifierFlags: []).problem == .needsModifier)
        #expect(KeyboardShortcut(keyCode: UInt16(kVK_F5), modifierFlags: []).problem == nil)
    }

    @Test func controlCommandSpaceIsAllowedWithANote() {
        let shortcut = KeyboardShortcut.controlCommandSpace
        #expect(shortcut.problem == nil)
        #expect(shortcut.displayString == "⌃⌘Space")
        #expect(shortcut.conflictNote?.contains("Emoji") == true)
    }

    @Test func modifierOrderFollowsApple() {
        let shortcut = KeyboardShortcut(keyCode: UInt16(kVK_Space), modifierFlags: [.command, .shift, .option, .control])
        #expect(shortcut.modifierSymbols == "⌃⌥⇧⌘")
        #expect(KeyboardShortcut(keyCode: shortcut.keyCode, carbonModifiers: shortcut.carbonModifiers).modifierFlags == [.command, .shift, .option, .control])
    }

    @Test func roundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(KeyboardShortcut.controlCommandSpace)
        #expect(try JSONDecoder().decode(KeyboardShortcut.self, from: data) == .controlCommandSpace)
    }
}

@MainActor
@Suite struct AppPreferencesTests {
    private func makeDefaults(name: String = "ToolchordTests.\(UUID().uuidString)") -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func storesOnlySettingsAndCommandIDs() {
        let suite = "ToolchordTests.\(UUID().uuidString)"
        let defaults = makeDefaults(name: suite)
        let preferences = AppPreferences(defaults: defaults)
        #expect(preferences.shortcut == .defaultShortcut)
        #expect(!preferences.hasStoredShortcut)
        preferences.shortcut = .controlCommandSpace
        preferences.indent = .four
        preferences.recordUse(of: "json.format")
        preferences.recordUse(of: "uuid.v4")
        preferences.recordUse(of: "json.format")

        let reloaded = AppPreferences(defaults: defaults)
        #expect(reloaded.shortcut == .controlCommandSpace)
        #expect(reloaded.indent == .four)
        #expect(reloaded.recentCommandIDs == ["json.format", "uuid.v4"])
        let stored = Set(defaults.persistentDomain(forName: suite)?.keys ?? [:].keys)
        #expect(stored.isSubset(of: ["shortcut", "hasCompletedWelcome", "indent", "recentCommandIDs", "remembersRecentCommands", "showsMenuBarIcon"]), "\(stored)")
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func recentsAreBoundedAndCanBeTurnedOff() {
        let preferences = AppPreferences(defaults: makeDefaults())
        for id in ["a", "b", "c", "d", "e"] { preferences.recordUse(of: id) }
        #expect(preferences.recentCommandIDs == ["e", "d", "c", "b"])
        preferences.remembersRecents = false
        #expect(preferences.recentCommandIDs.isEmpty)
        preferences.recordUse(of: "f")
        #expect(preferences.recentCommandIDs.isEmpty)
    }

    @Test func indentationPreferenceAppliesToFormatters() throws {
        let preferences = AppPreferences(defaults: makeDefaults())
        preferences.indent = .tab
        let format = try #require(ToolCatalog.command(id: "json.format"))
        let minify = try #require(ToolCatalog.command(id: "json.minify"))
        #expect(preferences.defaultOptions(for: format).values == ["indent": "tab"])
        #expect(preferences.defaultOptions(for: minify).values.isEmpty)
    }
}

@Suite struct ErrorContextTests {
    @Test func showsTheLineWithACaret() throws {
        let context = try #require(ErrorContext(text: "{\n  \"a\": }", location: TextLocation(line: 2, column: 8)))
        #expect(context.line == "  \"a\": }")
        #expect(context.caret == "       ^")
    }

    @Test func handlesCRLFAndMissingLines() throws {
        let context = try #require(ErrorContext(text: "a\r\nbc", location: TextLocation(line: 2, column: 2)))
        #expect(context.line == "bc")
        #expect(context.caret == " ^")
        #expect(ErrorContext(text: "a", location: TextLocation(line: 3, column: 1)) == nil)
    }

    @Test func windowsLongLinesAroundTheColumn() throws {
        let line = String(repeating: "x", count: 500)
        let context = try #require(ErrorContext(text: line, location: TextLocation(line: 1, column: 300), width: 40))
        #expect(context.line.hasPrefix("…") && context.line.hasSuffix("…"))
        let caretIndex = context.caret.count - 1
        #expect(Array(context.line)[caretIndex] == "x")
    }
}

@MainActor
@Suite struct ScreenLocatorTests {
    @Test func frameIsCenteredHorizontallyAndClamped() throws {
        let screen = try #require(NSScreen.screens.first)
        let frame = ScreenLocator.frame(for: CGSize(width: 760, height: 460), on: screen)
        let visible = screen.visibleFrame
        #expect(abs(frame.midX - visible.midX) <= 1)
        #expect(visible.contains(frame))
        let huge = ScreenLocator.frame(for: CGSize(width: 100_000, height: 100_000), on: screen)
        #expect(visible.contains(huge))
    }

    @Test func quartzRectsFlipToCocoa() throws {
        let primary = try #require(NSScreen.screens.first)
        let rect = ScreenLocator.cocoaRect(fromQuartz: CGRect(x: 10, y: 20, width: 100, height: 50))
        #expect(rect.minX == 10)
        #expect(rect.maxY == primary.frame.height - 20)
    }
}
