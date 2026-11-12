# Toolchord product plan and design

Toolchord is a native macOS command palette for the small tasks developers do between edits: format an API response, check when a token expires, decode a value, or generate an ID. The main interaction is to open the panel over the current app, inspect a result, then copy it and return to the same work.

[IT Tools](https://it-tools.tech/) provides a broad catalog of candidate utilities. [Devly](https://devly.techfixpro.net/) and [DevUtils](https://devutils.com/) already bring offline utilities to the Mac with shortcuts, and [Anvil](https://anvilmac.com/en/events/command-center/) offers searchable clipboard actions. Toolchord’s hypothesis is that putting a useful preview and **Copy & Close** in the same panel will shorten common workflows. Benchmark that before expanding the catalog.

## First release

| Tool | Commands and result |
| --- | --- |
| **JSON** | Format, minify, or validate. Preserve key order and numeric precision when formatting or minifying. For invalid JSON, show the first syntax error with a line and column. |
| **Base64** | Encode and decode text using standard Base64 or Base64URL. Make the alphabet selectable and give clear feedback for malformed input or decoded bytes that cannot be shown as UTF-8 text. |
| **URL** | Percent encode or decode text and inspect URL query parameters. Keep repeated parameters in order and let users copy values individually. Apply form-style plus-to-space decoding only where appropriate for query parameters. |
| **JWT** | Decode and display the header and claims with a readable expiry when present. Make individual claims copyable and show **Signature unverified** next to the result. |
| **Timestamp** | Convert Unix seconds or milliseconds to and from ISO 8601. Show the unit used, let the user override it, and label UTC and local time. |
| **UUID** | Generate a v4 UUID without input. Keep the UUID stable while it is on screen and provide an explicit **Regenerate** action. |

Raycast Store listings show tens of thousands of installs each for Base64, Unix Timestamp, and JWT Decoder. That makes them candidates for a shortcut palette. JSON and UUID make a useful first implementation pair because they exercise both the pasted-input and no-input paths. [Base64](https://www.raycast.com/DanielSinclair/base64) · [Unix Timestamp](https://www.raycast.com/destiner/unix-timestamp) · [JWT Decoder](https://www.raycast.com/gdsmith/jwt-decoder)

## Panel layout

Use one floating panel centered on the display where the user is working. Keep search and shortcuts in consistent positions as the panel expands. Use the native system font for controls, monospaced text for payloads, a visible selection, and a clear difference between input and output. Support light and dark appearance. On a display with less room, stack input and output or constrain the preview so the footer stays reachable.

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
| **Global shortcut** | Open the panel with search focused. Offer `⌥⇧Space` when available, let users record a different binding, and keep **Open Toolchord** in the menu bar. If registration fails, show the conflict or failure and let the user choose another binding. |
| **Paste · `⌘V`** | Attach or replace the payload when search has focus. In an editor, paste at the insertion point as normal. |
| **Arrows · `↑` `↓`** | Move through search results and update the preview. In text editors, arrows move the caret. |
| **Return · `↵`** | Open the selected command or generator from the list. In the multiline input, insert a newline. |
| **Copy & Close · `⌘↵`** | Copy the current valid result and dismiss the panel. Return focus to the originating app so the user can paste there. If copying fails, keep the panel open and show the error. |
| **Escape · `Esc`** | Return from a tool to the command list with the draft intact. At the root, dismiss the panel and discard the draft. |
| **Tab · `⇥`** | Move through controls in their visible order. Keep all available actions reachable with the keyboard and VoiceOver. |

macOS uses `⌃⌘Space` for Character Viewer, so the shortcut recorder and menu-bar entry are part of the design. Start with user-initiated paste because programmatic reads from the general pasteboard can trigger a system prompt. [Apple keyboard shortcuts](https://support.apple.com/en-us/102650) · [Apple pasteboard behavior](https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum)

Process tool input on-device and keep it in memory for the current panel session. Persist preferences such as the shortcut separately from payloads. Clear input and output on dismissal. Opening, previewing, and cancelling leave the system clipboard untouched. If the user switches to another app while the panel is open, dismiss the panel and leave focus where the user moved it.

## Implementation milestones

1. **Prove the native panel.** Use Swift and try an AppKit `NSPanel` for window placement, search focus, and focus return. Evaluate SwiftUI for panel content. Exercise shortcut registration and rebinding, menu-bar launch, copy, app switching, multiple displays, and full-screen Spaces before choosing the minimum macOS version and distribution route. [Apple NSPanel documentation](https://developer.apple.com/documentation/appkit/nspanel)
2. **Build the full interaction with JSON and UUID.** Implement command search, explicit paste, live preview, the expanded editor, and Copy & Close. Keep tool evaluation separate from panel state so the same input and options produce the same result in both views. Discard a pending preview if the user changes its input or closes the panel.
3. **Add Base64, URL, JWT, and timestamps.** Reuse the same input, result, error, and copy interactions. Add tool-specific options and copyable fields where they help answer the user’s question.
4. **Verify the first release.** Exercise the workflows below on the supported macOS versions. Use sample payloads to compare Devly and DevUtils on elapsed time and keyboard actions from input on the clipboard to result on the clipboard with the source app focused. Compare JSON formatting, Base64 decoding, and JWT expiry inspection.

Toolchord is a working name. Revisit naming before committing to release branding, including the existing software uses of [ToolCord](https://github.com/imhvit/ToolCord) and [Chord](https://github.com/KeyChord/Chord).

## First release acceptance checks

- **JSON:** From an editor, open the palette, paste minified JSON, preview it, and use `⌘↵`. The copied result matches the preview and the editor regains focus. Malformed JSON identifies the error location and disables copying. Fixing it produces a new valid result.
- **Base64 and URL:** Round-trip non-ASCII text through Base64 and Base64URL. Inspect a URL with repeated query keys and copy the second value without dismissing the panel. Malformed percent escapes show an error.
- **JWT and time:** Decode a sample token with an expiry, see **Signature unverified**, and copy an individual claim. Convert equivalent seconds and milliseconds to the same instant and check the labels on UTC and local results.
- **UUID:** Open Generate UUID without pasting anything. The value stays stable until regeneration, and Copy & Close copies the UUID shown.
- **Focus and clipboard:** Verify a custom shortcut and the menu-bar fallback across multiple displays and full-screen apps. Escape from the editor preserves the draft. Dismissing the panel clears it. An invalid or stale preview cannot overwrite the clipboard.
- **Offline and accessible use:** Run all six tools with networking unavailable. Verify that pasted data is absent from stored preferences and logs, and that the panel can be used with the keyboard and VoiceOver.

## After the first release

Grow the catalog along the [tool catalog roadmap](tool-catalog.md). The fast-follow tier adds hashing and HMAC, number base conversion, case and slug, hex ⇄ text, line tools, escapes, random strings, ULID and UUID v7, HTML entities, a URL inspector, colors, and cron parsing, in that order of value. Deepen the first six tools with options before adding adjacent commands. Text diff and regex testing wait for a roomier editor until the compact interaction has been validated.
