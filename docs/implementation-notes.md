# Implementation notes

Mechanisms, risks, and open decisions behind the milestones in the [product plan](product-plan.md). Nothing here is a commitment; milestone 1 exists to turn these into decisions.

## Process model

Run as a menu bar agent: `NSApplication` activation policy `.accessory`, no Dock icon, one status item that mirrors **Open Toolchord** and recent commands. Keep the process resident so the global shortcut opens the panel on the warm path only, and register a login item with `SMAppService` (macOS 13 and later) so the shortcut survives a reboot.

## Global shortcut

- Register with Carbon `RegisterEventHotKey`. It consumes the keystroke, needs no Accessibility permission, and works inside the App Store sandbox. `NSEvent` global monitors observe but cannot consume; a `CGEventTap` consumes but requires Accessibility trust, which is not worth it for a hotkey.
- The [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) package wraps Carbon registration and ships a conflict-aware recorder control; using it or copying its approach is reasonable for v1.
- Registration failure usually means a conflict. Surface the failure in the recorder, keep the menu-bar entry as the always-works fallback, and remember that `⌥⇧Space` is not system-reserved (system bindings to avoid: `⌘Space` Spotlight, `⌃Space` input source, `⌃⌘Space` Character Viewer) but can still collide with user launchers and IDE bindings.
- Define toggle behavior now: pressing the shortcut while the panel is open dismisses it.

## Panel window

- `NSPanel` with `.nonactivatingPanel` in the style mask can become key for typing without activating the app, so the originating app stays frontmost and focus restoration is usually unnecessary. This is the single highest-risk component; prototype it first.
- `collectionBehavior` of `[.canJoinAllSpaces, .fullScreenAuxiliary]` and a window level around `.floating` put the panel over full-screen Spaces.
- SwiftUI content hosted through `NSHostingView` is viable, but keyboard handling needs verification: SwiftUI keyboard shortcuts may not fire when a nested text view (`TextEditor` wraps `NSTextView`) holds first responder. Intercept `⌘↵`, `⌥↵`, Escape, and arrow-key list navigation with a local `NSEvent` monitor before default handling.
- Place the panel on the `NSScreen` containing the frontmost window (find the window bounds by PID through the window list), falling back to the screen with the pointer.
- Hide on `didResignKeyNotification`; the plan's draft-retention rules decide what happens to state then.

## Activation and focus return

Record `NSWorkspace.shared.frontmostApplication` when the panel opens. After Copy & Close, order out the panel and re-activate that application (`activate(options:)` on macOS 14 and later, `activateWithOptions(_:)` earlier). If the source app has quit, fall back to simply hiding. Do not use `AXUIElement` anywhere; it drags in the Accessibility permission.

## Clipboard

- **Writes.** `clearContents` plus `setString` or `setData`, declaring the UTI explicitly. Verify the pasteboard `changeCount` advanced afterward; if not, keep the panel open and show the error, as the plan requires.
- **Secrets.** When the payload is secret-shaped (decoded tokens, generated passwords, TOTP codes), also write `org.nspasteboard.ConcealedType`, the [nspasteboard.org](https://nspasteboard.org) convention honored by Maccy, Paste, Alfred, and Raycast, so clipboard managers and Universal Clipboard skip it. Generated one-shot values such as UUIDs can also be marked transient so history skips them where honored.
- **Reads.** Never read the general pasteboard programmatically without a user gesture. macOS asks the user for consent on programmatic reads: the consent APIs arrived in macOS 15.4, and `NSPasteboard.AccessBehavior` (`.default`, `.ask`, `.alwaysAllow`, `.alwaysDeny`) reports the app's standing, with user-initiated paste always allowed prompt-free. If an *attach clipboard on open* preference is ever added, gate the prompt-free detection on `NSPasteboard.detectedPatterns(for:)`, which classifies pasteboard content (probable web URL, number, and so on) without reading contents and without notifying the user.

## Tool kernels

- Evaluate tools in a separate library target: pure functions of `(input, options)` returning `(result, diagnostics)`, no AppKit imports. The same evaluation must drive both the live preview and the expanded tool view, as milestone 2 requires.
- Tests: round-trip properties for every encoder (encode then decode is the identity), error-location tests for JSON syntax errors, unicode edge cases (emoji, combining marks, CJK, lone surrogates), duplicate keys, byte-order marks, and parser edge cases from the review: line-wrapped and unpadded Base64, percent-escape errors, missing or non-numeric JWT `exp`, and duplicate claims.
- A palette crash lands on top of the user's work. Fuzz all parsers with arbitrary bytes in CI, cap input size (around 10 MB) with a clear message rather than a stall, and budget a 10 MB JSON format at well under a second.

## Performance budgets

| Path | Budget |
| --- | --- |
| Cold launch to keystroke-ready | 150 ms |
| Warm open to keystroke-ready | 50 ms |
| Preview after typing stops | debounce 150 ms, then evaluate off the main thread and cancel on input change |
| Preview render | cap at roughly the first 256 KB with **Show more**; Copy uses the full result |
| Copy round trip | 50 ms |
| Resident memory | 60 MB or less |

## Distribution and OS support

Decide in milestone 1, because it constrains everything else:

- **App Store.** Sandbox-compatible with everything above (Carbon hotkey, `SMAppService`, pasteboard). No Sparkle; updates ride the store, and review adds latency.
- **Direct download.** Notarization and hardened runtime, Sparkle for updates, and a bit more operational surface.

Minimum macOS is coupled to two decisions: `SMAppService` needs macOS 13, and the pasteboard consent APIs need 15.4. If the minimum stays below 15.4, feature-detect the consent APIs and fall back to never reading the pasteboard programmatically. Write the decision and its cost down when milestone 1 closes.

## Security and privacy

Payloads live in memory only: never in `UserDefaults`, logs, or crash reports. If logging is ever added, log lengths and tool names, not contents. Ship with no network entitlement and say so in the App Privacy label. Consider masking the signature half of a pasted JWT in the rendered preview so a screenshot leaks less.

## Test matrix

Exercise the acceptance checks across: macOS versions in support, light and dark appearance, Reduce Motion and Reduce Transparency, single and multiple displays, a full-screen Space in the foreground, Secure Input active (a terminal password prompt), clipboard managers installed (Maccy, Paste, Raycast), and sandboxed versus direct builds of the same bits.
