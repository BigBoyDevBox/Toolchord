# Shortcut UX proposal

The [product plan](product-plan.md) already has the right shape: one panel, a preview, an expanded editor, and Copy & Close. This proposal resolves interaction details and adds a [clickable prototype](prototype/index.html). It is a design study for a native Mac app; the HTML is not a proposed app runtime.

## One panel, three levels of attention

**Find.** Open a compact panel with search focused and six or fewer visible command rows. Display verb-first commands, short aliases, and a quiet footer of key hints. No dashboard, permanent category sidebar, or recent payloads. Keep the top edge and search field in place when expanding. Start around 680 points wide, constrained to the current screen's visible frame; these dimensions are proposed, not a platform requirement.

**Inspect.** An explicit paste attaches a payload below search and opens a preview beside the command list. Typed search remains separate. The attachment reads `Pasted input · JSON · 42 bytes`, or just `Text · N bytes` if uncertain. Omit raw excerpts for every type: detection cannot reliably identify secrets. The selected preview and expanded input intentionally display content. Clear removes the attachment immediately; a secondary **Use as search text** action resolves accidentally pasted command names without retyping.

**Edit.** Return opens the selected tool in the same panel, with input and output in columns. Focus the input editor for transforms; focus the first result control for a no-input generator. Inspectors use labeled fields instead of forcing everything into a code block. Escape returns to search with the entire draft intact. On narrow displays, stack input and result and keep the footer visible. Allow scrolling within long editors, not a panel that grows offscreen.

The fast path is **shortcut → paste → inspect → ⌘Return**. Return is optional for a successful preview. The footer always names what will be copied. Never run an invisible clipboard transform merely because detection found a match.

## Search and payload rules

- Typing edits the command query. Pasting while search is focused attaches/replaces the payload, retaining the query. Pasting in the multiline editor inserts normally. Pasting with neither field focused follows the focused control's native behavior; do not globally intercept paste.
- Offer Edit → Paste and a labeled Paste action using the same user-initiated native path. Invoking or navigating the panel never reads the clipboard. A failed/non-text paste shows a message and preserves the current payload; do not coerce files or images into text.
- Match exact command names and aliases first, then name/alias prefixes, then fuzzy matches. Explicit queries outrank detection: `uuid` must find Generate UUID even when JSON is attached. Aliases include `pretty print`, `epoch`, and `guid`.
- With an empty query, compatible input actions precede other tools in a fixed order. A JSON-looking but malformed value should still surface JSON tools and their parse error. Detection suggests a tool family, never establishes validity.
- A changed query selects its highest-ranked match. When replacing the payload, preserve selection by command ID if it still matches the query; otherwise select the first match. A completed preview cannot reorder results or move selection. No adaptive ranking in v1.
- Zero matches shows **No tools found**, keeps the payload, and offers **Clear search**. Removing input disables input-dependent results but leaves generators usable. A valid empty string is distinct from no attached input.

## Keys and focus

| Context | Key | Result |
| --- | --- | --- |
| Anywhere outside Toolchord | Recorded hotkey | Open search, recording the source app. Propose `⌥⇧Space` only if registration succeeds. Menu-bar launch remains available. |
| Search | ↑ / ↓ | Select a command and evaluate its preview. Keep focus in search. |
| Search | Return | Open selected tool. Never copy implicitly. |
| Multiline input | Return / arrows / ⌘A | Native newline, caret movement, and select-all behavior. |
| Any tool view | ⌘Return | Copy the explicitly labeled, current successful primary result and close. Disabled while pending/invalid. |
| Panel | ⌘K | Open a small contextual Actions menu: copy without closing, clear input, use payload as search, and regenerate where applicable. Each action is also discoverable by mouse. |
| Actions menu | Escape | Close only the menu and restore its trigger's focus. |
| Expanded tool | Escape | Back to command list, restore query focus and selected command. |
| Root list | Escape | Dismiss and clear the full session. |
| Any control | Tab / Shift-Tab | Follow visible control order. Arrow interception applies only in search/list navigation. |

Respect input-method composition: Return commits marked text and Escape cancels composition before either performs panel navigation. Use native controls and VoiceOver labels. Announce completion/error once after evaluation settles, not every caret move. Selection, validity, and warnings must be understandable without color. Native keyboard/VoiceOver behavior requires testing in the Mac spike; the browser prototype does not establish it.

The proposed `⌃⌘Space` conflicts with macOS Character Viewer. Let users record their choice and explain an actual registration failure without claiming that every system conflict is detectable. [Apple shortcuts](https://support.apple.com/en-us/102650)

## Name the copy target

The footer target is determined by command and explicit options, never by whichever field currently has focus. Normal `⌘C` copies selected text using native editor behavior. Individual field Copy buttons and **Copy without closing** preserve the session.

| Command | Primary result / footer |
| --- | --- |
| JSON format / minify | Transformed JSON text · **Copy JSON & Close** |
| JSON validate | Original validated JSON text · **Copy input & Close**; validation is not normalization |
| Base64 encode / decode | Encoded text / decoded UTF-8 text · **Copy encoded text & Close** / **Copy decoded text & Close** |
| URL component encode / decode | Transformed component · **Copy component & Close** |
| Inspect URL query | Ordered JSON array of `{ "name": string, "value": string }` pairs · **Copy parameters & Close**; repeated and empty pairs remain distinct |
| Inspect JWT | Decoded claims object as JSON · **Copy claims & Close**; header and each claim have their own Copy controls; **Signature unverified** remains adjacent |
| Unix → ISO 8601 | UTC RFC 3339 text with milliseconds · **Copy UTC time & Close**; local display is secondary |
| ISO 8601 → Unix | Number in the explicitly selected seconds/milliseconds unit · **Copy seconds & Close** / **Copy milliseconds & Close** |
| Generate UUID | Displayed lowercase UUID v4 · **Copy UUID & Close** |

Use a visible Seconds/Milliseconds selector for timestamp input; default to Seconds and label it even for a digit-only value. Do not use digit count as a correctness guarantee. UUID generation occurs once when first selected within the session, then only on Regenerate; filtering away and back must not change it.

## Draft lifetime and completion

A session draft includes query, payload, edits, selected command, options, generated values, result, errors, and pending work. Back navigation and a menu preserve it. Root Escape, successful Copy & Close, external app switching, screen lock, and app termination end it. Clear input invalidates the result immediately. Store only preferences such as hotkey, appearance, and indentation; no payload history or restoration on relaunch.

Copy success closes the panel. A failed write leaves it open with an actionable error. Request focus return to the app recorded at invocation only on deliberate completion/dismissal; it is best effort because macOS can refuse activation. External app switching ends the session and must never trigger focus restoration. If the origin app has exited, leave the current focus alone. [Apple activation behavior](https://developer.apple.com/documentation/appkit/nsrunningapplication/activate(from:options:))

## Prototype and review script

Open `docs/prototype/index.html` directly in a browser. It has no dependencies, requests, persistence, or system clipboard writes. Copy and dismissal are simulations and say so. It supports JSON format/minify/validate and UUID generation; the other four tools are specified above, not implemented in this study. JSON formatting preserves lexical tokens; browser error wording is illustrative. Global invocation, Mac paste permissions, focus return, full-screen Spaces, and VoiceOver still need a native prototype.

1. Load the JSON sample, inspect the preview, and simulate Copy JSON & Close without opening the editor.
2. Reopen, type `pretty`, and press Return. Edit the JSON, then Escape; the query and edited payload survive.
3. Load invalid JSON. Copy must be disabled and the error must replace the previous result.
4. Load JSON, then search `guid`. UUID is selected despite the input; it remains stable until Regenerate.
5. Paste `format json` into search, choose Actions → Use as search text, and find the command.
6. Reset to no input, open Generate UUID, then check keyboard navigation and the narrow stacked layout.

Design precedents: [Raycast search](https://manual.raycast.com/search-bar), [contextual actions](https://manual.raycast.com/action-panel), and [Alfred hotkey arguments](https://www.alfredapp.com/help/workflows/triggers/hotkey/). The specific ranking, copy labels, session rules, and layout here are proposals, not claims about those products.
