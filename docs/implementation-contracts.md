# Implementation contracts

The [product plan](product-plan.md) defines the panel and release scope. These contracts specify tool results, clipboard behavior, and native interactions. The automated tests in `Tests/` encode every fixture below.

## State, evaluation, and copy

Tool evaluation (`ToolchordCore`) is separate from session state (`ToolchordSession`) and macOS integration (`ToolchordMac`). The session owns the query, payload, selection, options, and generated values; the Mac layer handles the shortcut, panel, pasteboard, and app activation.

- A `ToolRequest` carries the input snapshot (`none` or attached text; an attached empty string is real input), resolved options, the generator seed, the clock, the time zone, limits, and a cancellation check. Evaluation is a pure function of it: no clipboard, files, network, logging, `Date()`, or randomness.
- Results are `needsInput`, `success(primaryText, status, fields, warnings)`, `invalid(message, location)`, `unsupported`, or `tooLarge`; "pending" is session state. A successful empty string is copyable. A status carries a tone, so **Signature unverified** reads as a warning rather than a success.
- Every change to input, command, options, or a generated value increments the revision and disables copy before new work is scheduled. A completion publishes only if its session ID and revision are still current. `end()` retires the session ID, so nothing started before dismissal can publish afterwards.
- Copy writes the exact primary text (or field value) of the visible successful result on the main actor that owns session state. A failed write keeps the panel open with an error notice.
- Evaluation runs on a detached task and checks cancellation in loops. Limits: 1 MiB UTF-8 input, 4 MiB output (primary text and every field), 128 levels of JSON or XML nesting. Input over the limit is not scanned by detection, not loaded into the editor, and reported as too large; tools stop producing output as soon as it would exceed the limit.
- A fresh session does no work until the panel opens (`activate()`); generators create their value on first selection and keep it across navigation and filtering until **Regenerate**.
- Paste in search goes through the field editor's `paste:` and attaches the clipboard text while keeping the query. Paste in the input editor inserts at the caret. Detection runs on the attached text after paste, bounded to a 64 KiB prefix for content scans.
- The draft (query, payload, options, edits, selection, generated values, result, pending work) survives Back and the Actions menu. Dismissal, Copy & Close, switching apps, screen lock, sleep, user switching, and quit retire it. Clearing input immediately invalidates its result. Preferences are stored separately and never include payloads, queries, or results.

## Selection and ranking

- A typed query ranks exact title or alias matches, then prefixes, then all words matched in any order (including the tool family name), then fuzzy subsequences. Detection only breaks ties, so `uuid` finds Generate UUID even with JSON attached.
- With input attached and no query, commands with affinity ≥ 30 for the detected kinds appear under **Suggested for ‹kind›** in descending affinity, followed by every other command in catalog order. General text tools suggest themselves only for plain text, so they never crowd out the tools for JSON, URLs, and other specific kinds.
- With no input and no query, up to four recently used tools come first (command IDs only).
- A changed query selects its best match. New input keeps an explicit selection unless the input has suggestions and the selection is not one of them. Arrow navigation is clamped at the ends.
- Short single-line pasted text that names a command can move into search with **Use Input as Search Text**.

## Tool contracts

Each command defines its input, diagnostics, primary copy target (named in the footer as **Copy ‹noun› & Close**), and secondary fields.

### JSON

Format, minify, and validate work lexically: validate the RFC 8259 grammar, then re-emit the original tokens, preserving string escapes, number spelling, member order, and duplicate names. Never serialize through floating-point values or dictionaries. Scalars are valid roots. Duplicate names (compared after decoding escapes) produce a warning without dropping data. Format uses the chosen indent (2 spaces by default, 4 spaces, or tab) and LF, with `"name": value`, empty containers as `{}` and `[]`, and no trailing newline. Comments, trailing commas, and a leading BOM get specific errors. Locations are one-based lines and Unicode-scalar columns, with CRLF as one break. Primary copy is the transformed JSON, or the unchanged input for Validate. [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259.html)

**Escape JSON String** emits a string literal (quotes optional), escaping `"`, `\`, control characters, U+2028, and U+2029. **Unescape JSON String** decodes a quoted literal strictly or a bare body leniently, joins surrogate pairs, and rejects unpaired surrogates.

### XML

**Validate XML** checks one XML 1.0 document's well-formedness and namespace usage with a hand-written parser, reports the first error with a location in the original input, and copies the original text on success (**Well-formed XML**). A document type declaration returns **unsupported** before any of its content is processed; nothing is ever fetched or expanded beyond the five predefined entities and character references. DTD and schema validation are out of scope. [XML 1.0](https://www.w3.org/TR/xml/#sec-well-formed) · [Namespaces in XML 1.0](https://www.w3.org/TR/xml-names/)

**Format XML** validates first, then indents only structural elements: those whose children are elements, comments, processing instructions, and literal whitespace, outside `xml:space="preserve"` (inherited; `default` resets). Every other element — mixed content, text, CDATA, references, or preserved whitespace — is copied verbatim with its entire subtree. Tags, attributes, comments, CDATA, processing instructions, and the XML declaration keep their exact spelling. The document level is treated as an indentation region: the declaration, top-level comments and processing instructions, and the root each start a line, and whitespace between them becomes a single LF. An optional BOM stays first. [XML whitespace handling](https://www.w3.org/TR/xml/#sec-white-space)

### Base64

Standard and URL-safe alphabets are separate commands, so the alphabet is always explicit. Encode UTF-8 text: Standard emits padding, Base64URL does not. Standard decoding requires correct padding; Base64URL accepts padded or unpadded input. Reject the other alphabet's characters (pointing to the right command), misplaced or excess padding, impossible lengths, and nonzero pad bits. Whitespace is rejected unless **Ignore whitespace** is on (space, tab, CR, LF only). Non-UTF-8 output is rejected with **Decoded bytes are not UTF-8 text**. [RFC 4648](https://www.rfc-editor.org/rfc/rfc4648.html)

### URL

**Encode URL Component** percent-encodes every UTF-8 byte outside the unreserved set with uppercase escapes. **Decode URL Component** decodes exactly once, keeps `+`, and rejects malformed escapes and non-UTF-8 results. **Inspect URL** never fetches anything: a URL with a scheme is split into scheme, user info, host, port, path, query, and fragment without decoding; text whose first `=` or `&` precedes any `?` is a raw query; otherwise the query follows the first `?`. Pairs split on `&` and the first `=`, skipping empty segments and keeping repeated and empty names in order; **+ is space** applies form decoding. The primary copy is an ordered JSON array of `{"name", "value"}` objects, one per line; fields hold the components and each decoded pair. [RFC 3986](https://www.rfc-editor.org/rfc/rfc3986.html) · [WHATWG form parsing](https://url.spec.whatwg.org/#urlencoded-parsing)

### JWT

Decode three-segment compact JWTs whose header and claims are JSON objects; a leading `Bearer` is removed with a note. The status is always **Signature unverified** (a warning), including for `alg: none`, which gets its own warning. Five segments are **unsupported** (encrypted). There are no keys, verification, signing, or key discovery. NumericDates (`exp`, `iat`, `nbf`, fractions and exponents allowed) get readable UTC notes; non-numeric ones get a warning note. Expiry reads **Expired 3 days ago**, **Expires in 1 hour**, or **No expiry claim** — never "valid". Primary copy is the formatted claims JSON; fields hold the expiry, header, and each claim's original JSON text. [RFC 7519](https://www.rfc-editor.org/rfc/rfc7519.html)

### Time

All calendar math uses exact integers on the proleptic Gregorian calendar for years 0001–9999 (no `DateFormatter`, which switches to the Julian calendar before 1582).

- **Convert Unix Time:** a visible Seconds/Milliseconds unit, defaulting to Seconds and never inferred from digit count. Seconds accept up to three fraction digits; milliseconds must be whole. Out-of-range values that would fit as milliseconds suggest switching the unit. Primary copy is `YYYY-MM-DDTHH:mm:ss.SSSZ`; fields add local time with its offset and zone, Unix seconds and milliseconds, and a relative description.
- **Convert Date to Unix Time:** an RFC 3339 subset requiring a time and a `Z` or numeric offset; leap seconds, offsetless and localized dates, and precision beyond milliseconds are rejected with an explanation. Primary copy is an exact decimal in the selected unit.
- **Show Current Time:** captures the instant once (Refresh with ⌘R) and copies Unix seconds, milliseconds, or UTC text. [RFC 3339](https://www.rfc-editor.org/rfc/rfc3339.html)

### Identifiers and random values

- **UUID v4** from the platform's secure generator, copied as lowercase canonical text; fields for uppercase, no hyphens, and braced. **UUID v7** follows RFC 9562 §5.7 and shows its embedded timestamp. **ULID** uses 48 timestamp bits and 80 random bits in Crockford base32. [RFC 9562](https://www.rfc-editor.org/rfc/rfc9562.html) · [ULID](https://github.com/ulid/spec)
- **Random String** maps 512 secure random bytes (the seed) onto the chosen alphabet by rejection sampling, so changing length or alphabet re-maps the same seed without bias; an Entropy field shows the bits. It is never described as a password.
- **Lorem Ipsum** is deterministic per seed (SplitMix64), opens with the classic sentence, and offers a sentence to five paragraphs.

### Text, encoding, numbers, and color

| Commands | Contract |
| --- | --- |
| Case conversion and slugs | Per line, preserving each line break. Words split at non-alphanumerics, lower→upper boundaries, and acronym boundaries (`XMLHttpRequest` → XML, Http, Request), never between letters and digits; combining marks stay in their word. Slugs transliterate to ASCII (`Straße` → `strasse`). |
| Sort, deduplicate, reverse lines | Split on LF, CR, or CRLF; join with the first break found; keep a trailing break. Sorting is stable, natural-numeric, and optionally case-sensitive; deduplication keeps first occurrences, optionally ignoring case or surrounding spaces. |
| HTML entities | Escape `& < > " '`. Unescape in one pass: the 253 HTML 4 names plus `&apos;`, decimal and hex references (bounded look-ahead), invalid code points → U+FFFD with a warning, unknown names left unchanged with a warning. |
| Hashes | SHA-256, SHA-512, SHA-1, MD5 of the UTF-8 bytes as lowercase hex; SHA-1 and MD5 carry a not-collision-resistant warning. |
| Number bases | Arbitrary precision up to 4,096 digits; `0x`/`0b`/`0o` prefixes, `_` separators, and a Read as option (Auto infers hex from `a–f`); fields show all four bases; error columns point into the original input. |
| Text ↔ hex | Lowercase bytes, optionally space-separated; decoding tolerates `0x`, spaces, line breaks, and colons, and requires UTF-8. |
| Counts | Primary copy is the character (grapheme) count; fields add words (whitespace-separated), lines, UTF-8 bytes, UTF-16 units (JavaScript length), and Unicode scalars. |
| Color | Hex (3, 4, 6, 8 digits), `rgb()`/`rgba()`, and `hsl()`/`hsla()` in comma or space syntax with exact component counts; out-of-range channels clamp as in CSS; `nan`, `inf`, and trailing text are rejected. Output in the command's notation with a swatch and all three notations as fields. |

## Fixtures

Literal strings use JSON escape notation where necessary. Structured copy targets compare parsed structure and order; formatting and component transforms compare exact text.

| Case | Input / action | Required result |
| --- | --- | --- |
| JSON precision and spelling | Minify `{"n":9007199254740993, "e":1e+02, "z":-0}` | `{"n":9007199254740993,"e":1e+02,"z":-0}` |
| JSON duplicates | Minify `{"a":1, "a":2, "s":"a  b"}` | `{"a":1,"a":2,"s":"a  b"}` and one duplicate warning |
| JSON scalar | Format `true` | `true`, copyable |
| JSON location | Format `{\n  "a": }` (and the CRLF variant) | Invalid at line 2, column 8; no copy |
| XML formatting | Format `<r xmlns:p="urn:example"><p:a id="1"/><p:b/></r>` | `<r xmlns:p="urn:example">\n  <p:a id="1"/>\n  <p:b/>\n</r>` |
| XML mixed content | Format `<p>Hello <b>world</b> !</p>` | Unchanged |
| XML preserved whitespace | Format `<r xml:space="preserve"><x><a/>  <b/><!--keep--><![CDATA[ < ]]><?keep x?></x></r>` | Unchanged |
| XML validation | Validate `<r xmlns:p="urn:example"><p:x>&amp;&#x20;</p:x></r>`, then `<r>\n  </wrong>` | Well formed and copied unchanged; then invalid at line 2, column 3 |
| XML document type | Any DOCTYPE, including `SYSTEM "https://…"`, `file:///…`, and an internal subset | Unsupported; no reads, no expansion |
| Base64 | Encode `✓` / `😀` (Standard) / `😀` (URL) | `4pyT` / `8J+YgA==` / `8J-YgA`; URL decoding also accepts `8J-YgA==` |
| Base64 rejections | Decode `Zh==` / `/w==` | Nonzero pad bits / not UTF-8 text |
| Empty output | Decode an attached empty string | Success with empty text; copy enabled |
| URL decoding | Decode `a+b%20c%252F` | `a+b c%2F` |
| URL query | Inspect `https://example.test/?a=1&a=2&empty=&flag&=x#end` | Pairs a=1, a=2, empty="", flag="", ""="x" in order |
| Query modes | Inspect `q=a+b%2Bc` / raw `q=what?yes` | URI `a+b+c`, Form `a b+c` / value `what?yes` |
| Malformed URL text | Decode `%G0`, `%`, `%FF` | Invalid, invalid, not UTF-8; never a partial copy |
| JWT | `eyJhbGciOiJub25lIn0.eyJleHAiOjAsInN1YiI6IngifQ.` at a clock after the epoch | Claims `{"exp":0,"sub":"x"}`, expiry in the past, signature unverified |
| Unix units | `0` s; `-1` s; `1700000000` s; `1700000000000` ms | `1970-01-01T00:00:00.000Z`; `1969-12-31T23:59:59.000Z`; both `2023-11-14T22:13:20.000Z` |
| Offset conversion | `2024-01-01T01:00:00+01:00` → seconds | `1704067200` |
| Identifiers | UUID v7 for 0x017F22E279B0 ms with RFC 9562 A.6 random bits; ULID for 1469918176385 ms with all-one random bits | `017f22e2-79b0-7cc3-98c4-dc0c0c07398f`; `01ARYZ6S41ZZZZZZZZZZZZZZZZ` |
| Generated values | Generate, switch tools, return, regenerate | Same value until Regenerate; v4 version nibble `4`, variant in `89ab` |
| Stale results | Delay A; submit B; complete B, then A | Only B is visible and copyable; the same across close and reopen and option changes |
| Bounded work | Input over 1 MiB / output over 4 MiB / nesting over 128 | Explicit limit error, responsive UI, no partial copy |
| Robustness | Every command × awkward inputs (empty, NUL, BOM, emoji, 500 `[` or `<a>`, 2,000 `&` or `%`, `nan`, `1e309`) | No crash, valid locations, unique field IDs |

## Native panel decisions

Observed on macOS 27.2.1 with Xcode 27.2 and Swift 6.4 on Apple silicon; deployment target macOS 14.0.

| Area | Decision and observation |
| --- | --- |
| Panel | Borderless `NSPanel` with `.nonactivatingPanel` set at initialization, `canBecomeKey`, floating level, `.canJoinAllSpaces`, `.fullScreenAuxiliary`, `.canJoinAllApplications`, and `hidesOnDeactivate = false`. Content is SwiftUI in an `NSHostingView` inside `NSGlassEffectView` (macOS 26+) or a masked `NSVisualEffectView`. |
| Shortcut | Carbon `RegisterEventHotKey` (no third-party package): no Accessibility or Input Monitoring permission, works in the sandbox. Default ⌥⇧Space with a ⌃⌥⌘Space fallback when the default is rejected; the recorder suspends the hotkey while recording and restores it if the window closes. |
| Placement | The display of the frontmost app's topmost normal window from `CGWindowListCopyWindowInfo` bounds, else the pointer's display; the frame is clamped to the visible frame, and the top edge stays put when the panel grows for an open tool. |
| Focus | The originating app stays active, so closing the panel returns focus without reactivation. Toolchord reactivates the origin only if it became active itself. Resign-key and third-app activation dismiss the panel; the Actions menu suppresses resign-key while tracking and dismisses afterwards if another app became active. |
| Keys | The panel handles ⌘↵, ⇧⌘↵, ⌘K, ⌘R, ⇧⌘⌫, ⌘,, and ⌘W, and sends ⌘X/C/V/A/Z, ⇧⌘Z, and ⌘F to the first responder, so editing works without an active main menu. While an input method has marked text, every key goes to it first. |
| Pasteboard | Read only inside the paste command. Opening, navigating, and dismissing never touch it; writes use `clearContents` and `setString`, whose result decides whether Copy & Close dismisses. |
| Distribution | App Sandbox with no other entitlements (so no network), hardened runtime, ad-hoc signed for local builds; set a team and Developer ID to notarize. `SMAppService.mainApp` login item, off by default. |
| Icon | `App/AppIcon.icon`, an Icon Composer document generated by `Scripts/make-icon.swift`; Xcode compiles the Liquid Glass icon and an `.icns` fallback for macOS 14–25. |
| Performance | Evaluation runs off the main actor with a 60 ms debounce for typing; highlighting is skipped above 256 KiB. Measured with `make benchmark` (release build, Apple M3 Pro, median of 5): every command evaluates a 10 KiB document in about 3 ms or less, well inside the 100 ms budget. At 1 MiB, formatting JSON takes 16 ms, inspecting a URL 65 ms, sorting lines 135 ms, and case conversions 200–380 ms. Warm invocation time still needs measuring by hand. |
