# Toolchord product plan and design

Toolchord is a native macOS command palette for the small tasks developers do between edits: format an API response, check when a token expires, decode a value, or generate an ID. The main interaction is to open the panel over the current app, inspect a result, then copy it and return to the same work.

[IT Tools](https://it-tools.tech/) provides a broad catalog of candidate utilities. [Devly](https://devly.techfixpro.net/) and [DevUtils](https://devutils.com/) already bring offline utilities to the Mac with shortcuts, [DevHub](https://wangchujiang.com/DevHub/) adds a menu bar toolbox with URL-scheme automation, and [Anvil](https://anvilmac.com/en/events/command-center/) offers searchable clipboard actions. [Boop](https://github.com/IvanMathy/Boop) is the closest open-source precedent — a scriptable transform scratchpad worth studying for its pure-function tool core, though it has no global palette or preview. The incumbent for the shortcut slot itself is the launcher: Raycast covers several of these tools through free extensions, so detection and instant preview have to be visibly faster than opening an extension form. Toolchord’s hypothesis is that putting a useful preview and **Copy & Close** in the same panel will shorten common workflows. Benchmark that before expanding the catalog.

## First release

| Tool | Commands and result |
| --- | --- |
| **JSON** | Format, minify, or validate. Preserve key order and numeric precision when formatting or minifying. For invalid JSON, show the first syntax error with a line and column. |
| **Base64** | Encode and decode text using standard Base64 or Base64URL. Make the alphabet selectable and give clear feedback for malformed input or decoded bytes that cannot be shown as UTF-8 text. For non-UTF-8 output, offer a hex view and **Save to file** so the result is still usable. |
| **URL** | Percent encode or decode text and inspect URLs. Parse a full URL into scheme, host, port, path, and query components; keep repeated parameters in order and let users copy values individually. Apply form-style plus-to-space decoding only where appropriate for query parameters. |
| **JWT** | Decode and display the header and claims with a readable expiry when present — including a relative form such as *expires in 14m* or *expired 3d ago*. Make individual claims copyable and show **Signature unverified** next to the result. |
| **Timestamp** | Convert Unix seconds or milliseconds to and from ISO 8601. Infer the unit from magnitude (for example, a 13-digit value is almost certainly milliseconds), show the unit used, let the user override it, and label UTC and local time. Offer the current time as a live, copyable input. |
| **UUID** | Generate a v4 UUID without input. Keep the UUID stable while it is on screen and provide an explicit **Regenerate** action. The same generator row can host ULID and nanoid — both are common requests in every catalog surveyed and share the same UI. |

Raycast Store listings show tens of thousands of installs each for Base64, Unix Timestamp, and JWT Decoder. That makes them candidates for a shortcut palette. JSON and UUID make a useful first implementation pair because they exercise both the pasted-input and no-input paths. [Base64](https://www.raycast.com/DanielSinclair/base64) · [Unix Timestamp](https://www.raycast.com/destiner/unix-timestamp) · [JWT Decoder](https://www.raycast.com/gdsmith/jwt-decoder)

## Panel layout

Use one floating panel centered on the display where the user is working — the display holding the key window or the pointer, not always the main display. The app runs with `.accessory` activation policy (no Dock icon); its presence is the global shortcut plus a menu bar status item. An `NSPanel` with `.nonactivatingPanel` in its style mask can become key for typing without activating the app, so the originating app keeps focus and **Copy & Close** needs no focus-restoration step. To appear over full-screen apps and other Spaces, set `collectionBehavior` to `[.canJoinAllSpaces, .fullScreenAuxiliary]` and a level around `.floating`. Keep search and shortcuts in consistent positions as the panel expands. Use the native system font for controls, monospaced text for payloads, a visible selection, and a clear difference between input and output. Support light and dark appearance, Reduce Motion, and Reduce Transparency. On a display with less room, stack input and output or constrain the preview so the footer stays reachable.

### Compact search

The launch state focuses search and shows a short list of commands. Match verb-first names and common aliases such as `pretty print`, `epoch`, and `GUID`. The user can type a command or paste input directly from the search field.

```text
┌────────────────────────────────────────────────────────────┐
│ Toolchord                                                  │
│ Find a tool or paste input…                            ⌘V  │
├────────────────────────────────────────────────────────────┤
│ › Format JSON                                              │
│   Decode Base64                                            │
│   Inspect JWT                                              │
│   Generate UUID                                            │
├────────────────────────────────────────────────────────────┤
│ ↑↓ Navigate                     ↵ Open       Esc Dismiss   │
└────────────────────────────────────────────────────────────┘
```

### Live preview

Pasting into search attaches text as a separate input and keeps any typed filter. With no filter, put likely actions first. Show the source and a short snippet for ordinary text, with a clear button to remove it. For tokens, show the detected type in place of the raw value. A guess changes the order of commands while the user keeps control of which action runs and what is copied.

The preview follows the selected action. Show an actionable message for an incompatible value or a parse error. Copy becomes available when the preview represents a successful result for the current input, action, and options.

```text
┌──────────────────────────────────────────────────────────────────┐
│ Toolchord                                                        │
│ Find a tool or paste input…                                  ⌘V  │
├──────────────────────────────────────────────────────────────────┤
│ Pasted input   {"status":200,"cache":"HIT"}                Clear │
├──────────────────────────────────────────────────────────────────┤
│ › Format JSON               Preview                 Valid JSON   │
│   Minify JSON               {                                    │
│                                "status": 200,                    │
│                                "cache": "HIT"                    │
│                              }                                   │
├──────────────────────────────────────────────────────────────────┤
│ ↑↓ Navigate                    ↵ Open          ⌘↵ Copy & Close   │
└──────────────────────────────────────────────────────────────────┘
```

### Expanded tool

Return opens the selected tool in the same panel. Give transforms a multiline input, selectable live output, and the options that affect that action. Give inspectors structured rows with individual copy controls. Field-level **Copy** keeps the panel open. **Copy & Close** uses the tool’s primary result and dismisses the panel.

```text
┌──────────────────────────────────────────────────────────────────┐
│ ‹ Tools   Format JSON                                            │
├──────────────────────────────────────────────────────────────────┤
│ Input                           Result              Valid JSON   │
│ {"status":200,"cache":"HIT"}    {                                │
│                                   "status": 200,                 │
│                                   "cache": "HIT"                 │
│                                 }                                │
├──────────────────────────────────────────────────────────────────┤
│ Esc Back                                       ⌘↵ Copy & Close   │
└──────────────────────────────────────────────────────────────────┘
```

## Keyboard and clipboard behavior

| Input | Behavior |
| --- | --- |
| **Global shortcut** | Open the panel with search focused. Offer `⌥⇧Space` when available, let users record a different binding, and keep **Open Toolchord** in the menu bar. If registration fails, show the conflict or failure and let the user choose another binding. Avoid the system-reserved `⌘Space` (Spotlight), `⌃Space` (input source), and `⌃⌘Space` (Character Viewer), plus `⌥Space`, which most launcher users already have bound. |
| **Copy & Stay · `⌥↵`** | Copy the current valid result without dismissing, for copying multiple fields or generating several values in a row. |
| **Action menu · `⌘K`** | List secondary actions for the current result: Copy as…, Save to file, field-level copies. Mirrors the launcher convention so the habit transfers. |
| **Paste · `⌘V`** | Attach or replace the payload when search has focus. In an editor, paste at the insertion point as normal. |
| **Arrows · `↑` `↓`** | Move through search results and update the preview. In text editors, arrows move the caret. |
| **Return · `↵`** | Open the selected command or generator from the list. In the multiline input, insert a newline. |
| **Copy & Close · `⌘↵`** | Copy the current valid result and dismiss the panel. Return focus to the originating app so the user can paste there. If copying fails, keep the panel open and show the error. |
| **Escape · `Esc`** | Return from a tool to the command list with the draft intact. At the root, dismiss the panel and discard the draft. |
| **Tab · `⇥`** | Move through controls in their visible order. Keep all available actions reachable with the keyboard and VoiceOver. |

Start with user-initiated paste: reading the general pasteboard outside a paste action is exactly what Apple's upcoming paste-consent alert targets (developer preview since macOS 15.4). Detection can stay prompt-free by reading only metadata — `NSPasteboard.general.types`, `detectedMetadata(for:)`, and on macOS 15.4+ `detectedPatterns(for:)` to classify links, probable web URLs, and numbers without touching contents. `NSPasteboard.accessBehavior` reports whether the user has already allowed or denied the app, and an opt-in **Attach clipboard on open** preference can build on that without silently reading at launch. [Apple keyboard shortcuts](https://support.apple.com/en-us/102650) · [Apple pasteboard behavior](https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum) · [Pasteboard detection patterns](https://developer.apple.com/documentation/appkit/nspasteboard-detection-patterns)

Process tool input on-device and keep it in memory for the current panel session. Persist preferences such as the shortcut separately from payloads. Clear input and output on dismissal. Opening, previewing, and cancelling leave the system clipboard untouched. Mark secret-shaped results (decoded token payloads, generated secrets) with `org.nspasteboard.ConcealedType` so clipboard managers and Universal Clipboard skip them. If the user switches to another app while the panel is open, dismiss the panel — hiding on `didResignKeyNotification` covers this — and leave focus where the user moved it.

## Implementation milestones

1. **Prove the native panel and pick the distribution route.** Decide App Store (sandboxed) versus direct download with Sparkle updates first, because it constrains everything else: global hotkey registration, pasteboard access, and a future auto-paste feature all interact with sandboxing and entitlements. Use Swift and try an AppKit `NSPanel` for window placement, search focus, and focus return. Evaluate SwiftUI for panel content. Exercise shortcut registration and rebinding — Carbon `RegisterEventHotKey` needs no Accessibility permission and is what the [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) package wraps, including a recorder control — along with `.accessory` app policy, launch-at-login via `SMAppService` so the hotkey is always live, menu-bar launch, copy, app switching, multiple displays, and full-screen Spaces before choosing the minimum macOS version. [Apple NSPanel documentation](https://developer.apple.com/documentation/appkit/nspanel)
2. **Build the full interaction with JSON and UUID.** Implement command search, explicit paste, live preview, the expanded editor, and Copy & Close. Keep tool evaluation in its own library target — pure functions of input and options — so the same input and options produce the same result in both views and the whole engine is testable without the panel. Fuzz the parsers (JSON, Base64, percent-encoding, JWT structure); a crash in the palette is a crash over the user's current app. Set the performance budget here: panel open under ~150 ms, preview under ~50 ms, and a hard input cap (~10 MB) with a clear message rather than a stall. Discard a pending preview if the user changes its input or closes the panel.
3. **Add Base64, URL, JWT, and timestamps.** Reuse the same input, result, error, and copy interactions. Add tool-specific options and copyable fields where they help answer the user’s question.
4. **Verify the first release.** Exercise the workflows below on the supported macOS versions. Use sample payloads to compare Devly and DevUtils on elapsed time and keyboard actions from input on the clipboard to result on the clipboard with the source app focused. Compare JSON formatting, Base64 decoding, and JWT expiry inspection.

Toolchord is a working name. Revisit naming before committing to release branding, including the existing software uses of [ToolCord](https://github.com/imhvit/ToolCord) and [Chord](https://github.com/KeyChord/Chord).

## First release acceptance checks

- **JSON:** From an editor, open the palette, paste minified JSON, preview it, and use `⌘↵`. The copied result matches the preview and the editor regains focus. Malformed JSON identifies the error location and disables copying. Fixing it produces a new valid result.
- **Base64 and URL:** Round-trip non-ASCII text through Base64 and Base64URL. Inspect a URL with repeated query keys and copy the second value without dismissing the panel. Malformed percent escapes show an error.
- **JWT and time:** Decode a sample token with an expiry, see **Signature unverified**, and copy an individual claim. Convert equivalent seconds and milliseconds to the same instant and check the labels on UTC and local results.
- **UUID:** Open Generate UUID without pasting anything. The value stays stable until regeneration, and Copy & Close copies the UUID shown.
- **Focus and clipboard:** Verify a custom shortcut and the menu-bar fallback across multiple displays and full-screen apps. Escape from the editor preserves the draft. Dismissing the panel clears it. An invalid or stale preview cannot overwrite the clipboard. `⌥↵` copies while the panel stays open.
- **Pasteboard privacy:** On macOS versions with pasteboard privacy, opening the palette, matching commands, and previewing must never trigger a consent alert. `⌘V` and the opt-in attach-on-open behave correctly under each `accessBehavior` state (default, ask, always allow, always deny).
- **Offline and accessible use:** Run all six tools with networking unavailable. Verify that pasted data is absent from stored preferences and logs, and that the panel can be used with the keyboard and VoiceOver.

## After the first release

Grow the catalog in order of implementation cost. Hashes (SHA-256/512, SHA-1, MD5 via CryptoKit), number bases, HTML entities, case conversion and slugify, hex ↔ text, line tools (sort, dedupe, join), and a QR generator (`CIQRCodeGenerator` needs no dependency) reuse the first-release interactions almost unchanged. JSON ↔ YAML conversion, JSONPath queries, and a cron explainer follow. Add text diff and regex testing in a roomier editor when the compact interaction has been validated. For power users, a `toolchord://` URL scheme with Shortcuts actions and a Services-menu item lets launchers and scripts drive the palette; auto-paste-back after copy stays opt-in and needs Accessibility permission. The ranked candidate list lives in the catalog research (`docs/tool-catalog.md`).
