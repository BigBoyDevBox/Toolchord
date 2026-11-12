# Palette interaction and UX spec

Companion to the [product plan](product-plan.md). The plan fixes the surfaces — compact search, live preview, expanded tool — and this document works out the interaction details a shortcut palette needs to feel instant: direct answers, input detection that never triggers a paste prompt, ranking, and window behavior.

## Interaction model

Three surfaces, one window, consistent footer. The user should never wonder which state they are in or how to get back.

```text
Search ──────────► Search + preview ──────────► Tool
(typing)          (input attached)             (↵ on a command)
   ▲                    ▲                          │
   └──── Esc keeps draft ┴──────── Esc ────────────┘
```

- **Search** is the launch state: field focused, short ranked command list.
- **Search + preview** appears when input is attached (pasted). Commands are ranked by detected type; the selected command previews live.
- **Tool** is the expanded single-tool view with its options.
- Esc always walks one level up; dismissing from search clears the session.

## Direct answers

The fastest flow skips the tool entirely: rows that *are* results. When the query itself parses as input for a stateless command, show the answer inline and let Return copy it.

```text
┌────────────────────────────────────────────────────────────┐
│ Toolchord                                                  │
│ 1712345678                                                 │
├────────────────────────────────────────────────────────────┤
│ › = Fri, Apr 5 2024 18:45:58 UTC     Unix seconds          │
│   Convert timestamp                  open in Timestamp     │
│   Search tools for "1712345678"                            │
├────────────────────────────────────────────────────────────┤
│ ↑↓ Navigate                     ↵ Copy       Esc Dismiss   │
└────────────────────────────────────────────────────────────┘
```

Worth supporting at launch: unix timestamps (s/ms), UUID-looking strings (validate and name the version), `uuid`/`ulid`/`nanoid` (offer to generate), numbers in `0x`/`0b` form (base conversion), and a URL (offer "Open URL" actions? no — offer parse/encode). Generators get a result-first row too:

```text
│ › UUID    3F2504E0-4F89-41D3-9A0C-0305E82C3301    ↵ Copy   │
│   ⌥↵ keep panel open · ⇥ options                           │
```

This is the Spotlight/Raycast pattern that makes a palette feel faster than any per-tool app: zero commands remembered, two keystrokes to clipboard.

## Input detection without paste prompts

Reading the general pasteboard outside a paste action will trigger macOS's paste-consent alert once that ships (developer preview since macOS 15.4). Detection must work without touching contents:

1. **Metadata, always safe.** `NSPasteboard.general.types` and `detectedMetadata(for:)` reveal whether the board holds a string, file URL, or image. Enough to badge "Paste to attach" vs "Nothing to paste".
2. **Pattern detection on macOS 15.4+.** `detectedPatterns(for:)` / `detectedValues(for:)` classify `.links`, `.probableWebURL`, `.number`, `.emailAddresses` etc. without consent. Enough to pre-rank URL and timestamp commands.
3. **Content sniffing only after `⌘V`.** Once the user pastes, run ordered heuristics (cheap first): JWT shape (`^[\w-]+\.[\w-]+\.[\w-]+$`), JSON (`{`/`[` + parse), timestamp magnitude, Base64 alphabet + round-trip, URL scheme. Store the guess with the input chip, not the raw value.
4. **Opt-in auto-attach.** A preference "attach clipboard on open" trades one consent prompt (or `accessBehavior` set to *always allow* in System Settings) for a zero-keystroke flow — DevUtils' main advantage. Off by default; explain it during onboarding.
5. **Never read silently at launch.** No background polling of the pasteboard; `changeCount` only for the opt-in feature.

## Ranking and matching

Deterministic enough to learn by heart, adaptive where it helps:

- **Match** on verb-first names plus alias table (`pretty print`, `epoch`, `GUID`, `b64`, `jwt`, `md5`, `epoch ms`…). Fuzzy subsequence match, scored; prefix beats subsequence.
- **Order** = detected-action boost > frecency (frequency × recency) > curated default order. A guess changes order, never which action fires.
- **Direct answers always sort above commands** — they are strictly faster.
- Pin/favorite commands: defer; frecency usually suffices at this catalog size.

## Keyboard map

Extends the plan's table; unchanged rows omitted.

| Input | Behavior |
| --- | --- |
| `↵` | On a direct answer or generator row: copy result and close. On a command: open the tool. |
| `⌥↵` | Copy result, keep panel open ("Copy & Stay"). For generating a second value or copying multiple fields in sequence. |
| `⌘↵` | Copy & Close (as planned — fires the primary result). |
| `⌘K` | Action menu for the current result: Copy / Copy as… / Save to file… / field-level copies. Mirrors Raycast so the habit transfers. |
| `⇥` | Search → input chip → list → (tool: options) → footer, in visible order. `⇧⇥` reverses. |
| `⌫` on empty query | Removes the attached input chip. |
| `⌥⌫` in tool | Clears the input field. |
| `⌘V` / `⇧⌘V` | Paste at focus / paste-and-run top guess (power move — worth prototyping). |
| `⌘1`…`⌘9` | Toggle the nth option of the open tool (Base64 alphabet, timestamp unit, UUID format). |

## Window and activation

The palette must float over whatever the user is doing, including full-screen Spaces, without stealing app focus:

- `NSPanel` with `.nonactivatingPanel` in the style mask — becomes key for typing without activating the app, so the originating app keeps focus and **Copy & Close** needs no focus-restore work.
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]` and a level around `.floating`/`.statusBar` to appear over full-screen apps.
- Hide on `didResignKeyNotification` when the user clicks into another app — the plan's dismiss-on-switch behavior falls out of this naturally.
- Launch-time app policy: `.accessory` (`LSUIElement`) — no Dock icon; presence is the hotkey plus a status item whose menu offers Open, recent tools, and Settings.
- Center on the display that holds the key window or the pointer (`NSEvent.mouseLocation` fallback), not always the main display.
- `isReleasedWhenClosed = false`; reuse one panel instance so open is instant.
- Honor Reduce Motion (skip the scale/fade-in) and Reduce Transparency in the panel background.

## Clipboard output

- Write only on explicit copy actions — preview never touches the board (already in the plan).
- For secret-shaped results (decoded JWT payload, token generators), mark the item with `org.nspasteboard.ConcealedType` so clipboard managers and Universal Clipboard skip it.
- Optionally include a `public.plain-text` plus a richer type (e.g., `public.utf8-plain-text` always; no RTF needed — targets are terminals and editors).
- After Copy & Close, the prior app still owns focus; the user's `⌘V` lands where they started. Auto-paste-back is the obvious next feature but needs Accessibility permission — list it post-release, opt-in.

## Onboarding and states

First launch needs exactly two things: record the shortcut (default `⌥⇧Space`, show conflicts live in the recorder) and explain the paste model ("press `⌘V` here — nothing is read until you do"). One panel, done, no account, no tour.

Empty states worth mocking early:

```text
│ No match for "xmltojson"                                   │
│   ↵ Search tools            ⌘K all commands                │
```

```text
│ Input  {"a": }                            Result           │
│                              ✗ Expected a value            │
│                                line 1, column 7            │
│                                ⇥ Show in input             │
│                              Copy disabled — fix input     │
```

JSON errors should deep-link: activating the error moves the caret to the reported line/column in the input field.

## Performance budget

Perceived speed is the product. Targets on a mid-range M-series Mac:

- Hotkey → key-accepting panel: **≤ 150 ms** (keep the app resident via login item; cold start is not the palette path).
- Keystroke → re-ranked list: **≤ 16 ms**.
- Input attach → preview: **≤ 50 ms** debounced; tool evaluation is pure and synchronous for inputs under ~1 MB.
- Hard input cap (~10 MB) with a clear "too large for the palette — open in editor?" message rather than a stall.

## Accessibility

- Every row announces label + result hint ("Format JSON, valid result available") via `NSAccessibility`.
- Full parity: no pointer-only actions — copy controls, option toggles, error jump all keyboard-reachable (the `⌘K` menu makes this easy to audit).
- Error text and status badges carry meaning in text, not only color; contrast-checked in both appearances.
- VoiceOver rotor order = visual order; the input chip is one element with a remove action.

## Settings (kept short)

Global shortcut (recorder) · Attach clipboard on open (off) · Auto-paste result after copy (off, post-release, needs Accessibility) · Launch at login (on) · Menu bar icon (on) · Appearance (system) · Clear history / reset frecency.

## Later interactions

Once the loop is proven: auto-paste-back with Accessibility permission, a `toolchord://<tool>?input=…` URL scheme plus Shortcuts actions and a Services-menu "Send to Toolchord" (DevUtils and DevHub both ship URL schemes — launchers can then drive the palette), drag-and-drop file input onto the panel, and opt-in session history. Each is a strict addition to the same three-surface model.
