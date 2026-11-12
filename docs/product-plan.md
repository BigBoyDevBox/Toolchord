# Toolchord product plan and design

Toolchord is a native macOS command palette for the small tasks developers do between edits: format an API response, check when a token expires, decode a value, or generate an ID. The main interaction is to open the panel over the current app, inspect a result, then copy it and return to the same work.

The [shortcut UX](shortcut-ux.md) specifies panel behavior and includes a clickable design study. The [implementation contracts](implementation-contracts.md) define copy results, format rules, expected-result fixtures, and the checks for the native prototype.

[IT Tools](https://it-tools.tech/) provides a broad catalog of candidate utilities. [Devly](https://devly.techfixpro.net/) and [DevUtils](https://devutils.com/) already bring offline utilities to the Mac with shortcuts, and [Anvil](https://anvilmac.com/en/events/command-center/) offers searchable clipboard actions. Toolchord’s hypothesis is that putting a useful preview and **Copy & Close** in the same panel will shorten common workflows. Benchmark that before expanding the catalog.

## First release

| Tool | Commands and result |
| --- | --- |
| **JSON** | Format, minify, or validate. Preserve key order and numeric precision when formatting or minifying. For invalid JSON, show the first syntax error with a line and column. |
| **XML** | **Format XML** indents structural markup while preserving mixed content and `xml:space="preserve"` regions. **Validate XML** checks XML 1.0 well-formedness and reports syntax errors with a line and column. Documents containing a DOCTYPE get a distinct unsupported message. |
| **Base64** | Encode and decode text using standard Base64 or Base64URL. Make the alphabet selectable and give clear feedback for malformed input or decoded bytes that cannot be shown as UTF-8 text. |
| **URL** | Percent encode or decode text and inspect URL query parameters. Keep repeated parameters in order and let users copy values individually. Apply form-style plus-to-space decoding only where appropriate for query parameters. |
| **JWT** | Decode and display the header and claims with a readable expiry when present. Make individual claims copyable and show **Signature unverified** next to the result. |
| **Timestamp** | Convert Unix seconds or milliseconds to and from ISO 8601. Show the unit used, let the user override it, and label UTC and local time. |
| **UUID** | Generate a v4 UUID without input. Keep the UUID stable while it is on screen and provide an explicit **Regenerate** action. |

JSON and UUID make the first implementation pair because they exercise the pasted-input and no-input paths. The [catalog research](research.md) explains the launch choices and how to compare the workflow with existing tools.

## Panel layout

Use one floating panel centered on the display with the frontmost window when it can be determined, with the pointer’s display as the fallback. Keep search and shortcuts in consistent positions as the panel expands. Use the system font for controls, monospaced text for payloads, and a visible selection. Support light and dark appearance, Reduce Motion, and Reduce Transparency. On a display with less room, stack input and output so the footer stays reachable.

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

Pasting into search replaces the attached text and keeps any typed filter. With no filter, put likely actions first. Show the source, detected type when available, and UTF-8 byte count, with a clear button to remove the attachment. Raw text appears in the selected result or the input editor. A guess changes command order. The user chooses what to copy.

The preview follows the selected action. Show an actionable message for an incompatible value or a parse error. Copy becomes available when the preview represents a successful result for the current input, action, and options.

```text
┌──────────────────────────────────────────────────────────────────┐
│ Toolchord                                                        │
│ Find a tool or paste input…                                  ⌘V  │
├──────────────────────────────────────────────────────────────────┤
│ Pasted input · JSON · 28 bytes                             Clear │
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

Return opens the selected tool in the same panel. Give transforms a multiline input, selectable live output, and the options that affect that action. Give inspectors structured rows with individual copy controls. Field-level **Copy** keeps the panel open. **Copy & Close** uses the tool’s declared primary result and dismisses the panel. Name its target in the footer, such as **Copy claims & Close** for JWT or **Copy parameters & Close** for the ordered URL-query pairs; focusing a field does not change this target.

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
| **Global shortcut** | Open the panel with search focused. Repeating the shortcut refocuses the current view and keeps the draft. On first launch, offer `⌥⇧Space` when available and explain how to paste. Let users record another shortcut and open the palette from the menu bar even if registration fails. |
| **Paste · `⌘V`** | Attach or replace the payload when search has focus. In an editor, paste at the insertion point as normal. |
| **Arrows · `↑` `↓`** | Move through search results and update the preview. In text editors, arrows move the caret. |
| **Return · `↵`** | Open the selected command or generator from the list. In the multiline input, insert a newline. |
| **Copy & Close · `⌘↵`** | Copy the exact primary result shown for the current command, then dismiss the panel. If the originating app needs to be reactivated, request activation. If copying fails, keep the panel open and show the error. |
| **Actions · `⌘K`** | Open a small menu for secondary actions, such as copying without closing, clearing the input, or regenerating a UUID. |
| **Escape · `Esc`** | Close Actions if open. Otherwise, return from a tool to the command list with the draft intact or dismiss the root panel and discard the draft. |
| **Tab · `⇥`** | Move through controls in their visible order. Keep all available actions reachable with the keyboard and VoiceOver. |

macOS uses `⌃⌘Space` for Character Viewer, so the shortcut recorder and menu-bar entry are part of the design. Start with user-initiated paste because programmatic reads from the general pasteboard can trigger a system prompt. [Apple keyboard shortcuts](https://support.apple.com/en-us/102650) · [Apple pasteboard behavior](https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum)

Process tool input on-device and keep it in memory for the current panel session. The draft includes query, input, edits, options, selection, generated values, and results. Persist preferences such as the shortcut separately from the draft. Clear the draft and retire pending work on dismissal or screen lock. Opening, previewing, and cancelling leave the system clipboard untouched. If the user switches to another app while the panel is open, dismiss the panel and leave focus where the user moved it. Do not log payloads, derived text, or queries.

## Implementation milestones

1. **Prove the native panel.** Use Swift and try an AppKit `NSPanel` for window placement, search focus, and focus return. Evaluate SwiftUI for panel content. Exercise shortcut registration and rebinding, menu-bar launch, copy, app switching, multiple displays, full-screen Spaces, Stage Manager, and paste permission states before choosing the minimum macOS version and distribution route. [Apple NSPanel documentation](https://developer.apple.com/documentation/appkit/nspanel)
2. **Build the full interaction with JSON and UUID.** Implement command search, explicit paste, live preview, the expanded editor, and Copy & Close. Keep deterministic tool evaluation separate from panel state; generate UUIDs only on first selection or explicit regeneration. Bind previews and copy eligibility to session, revision, command, and options so delayed completions cannot publish after a change or close/reopen. Apply input/output limits before expensive work. Use the independent fixtures in the implementation contracts.
3. **Add XML, Base64, URL, JWT, and timestamps.** Reuse the same input, result, error, and copy interactions. Add the XML formatter and validator with fixtures for mixed content, preserved whitespace, and blocked external resources.
4. **Verify the first release.** Exercise the workflows below on supported macOS versions. Use the [research plan](research.md#validation-before-catalog-expansion) to compare elapsed time, keystrokes, and copy accuracy with existing tools.

Toolchord is a working name. Revisit naming before committing to release branding, including the existing software uses of [ToolCord](https://github.com/imhvit/ToolCord) and [Chord](https://github.com/KeyChord/Chord).

## First release acceptance checks

- **JSON:** From an editor, open the palette, paste minified JSON, preview it, and use `⌘↵`. The copied result matches the preview and the editor regains focus when macOS permits activation. A refused activation or exited origin app does not invalidate a successful copy. Malformed JSON identifies the error location and disables copying. Fixing it produces a new valid result.
- **XML:** Format a namespaced document, preserving mixed content, CDATA, and significant whitespace. Verify that Validate XML copies well-formed input unchanged and gives a line and column for a mismatched tag. A document with a DOCTYPE reports unsupported, leaves the clipboard untouched, and causes no network or file access.
- **Base64 and URL:** Round-trip non-ASCII text through Base64 and Base64URL. Inspect a URL with repeated query keys and copy the second value without dismissing the panel. Malformed percent escapes show an error.
- **JWT and time:** Decode a sample token with an expiry, see **Signature unverified**, and copy an individual claim. Convert equivalent seconds and milliseconds to the same instant and check the labels on UTC and local results.
- **UUID:** Open Generate UUID without pasting anything. The value stays stable until regeneration, and Copy & Close copies the UUID shown.
- **Focus and clipboard:** Verify a custom shortcut and the menu-bar fallback across multiple displays and full-screen apps. Invoking the shortcut again refocuses the panel. Escape from the editor preserves the draft. Dismissal or switching apps clears it. An invalid or stale preview cannot overwrite the clipboard.
- **Offline and accessible use:** Run all seven tools with networking unavailable. Verify that pasted data is absent from stored preferences and logs, and that the panel can be used with the keyboard and VoiceOver.

## After the first release

Evaluate JSON ↔ YAML conversion, SHA-256, and text cleanup after testing the core workflow. Text diff and regex testing need a roomier editor. Consider XML schema validation, XPath, and conversion separately from the first release’s syntax check and formatter. See the [catalog research](research.md#tool-selection) for more candidates.
