import AppKit
import ToolchordSession

/// The general pasteboard. Toolchord reads it only inside the user's Paste
/// command (⌘V or Edit › Paste), which macOS treats as user-initiated and
/// does not gate behind the "Paste from Other Apps" privacy alert. Opening,
/// navigating, and dismissing the palette never touch the pasteboard.
@MainActor
public final class SystemClipboard: ClipboardWriting {
    public init() {}

    public func writeText(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    /// Reads plain text. Call only in response to a paste command.
    public func readTextForPaste() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
}
