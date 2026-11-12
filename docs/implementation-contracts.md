# Implementation contracts

The [product plan](product-plan.md) defines the panel and release scope. These contracts specify the tool results, clipboard behavior, and native interactions that the first release needs to support.

## State, evaluation, and copy

Keep deterministic tool evaluation separate from session state and macOS integration. The session owns selection, edits, and generated values. The macOS integration handles the shortcut, panel, pasteboard, and app activation.

- An evaluation request carries `sessionID`, `revision`, `commandID`, complete options, and the input snapshot. Increment the revision immediately when input, command, options, or a generated value change. `noInput` and an attached empty string are distinct.
- Results distinguish `needsInput`, `pending`, `success(primaryText, fields, warnings)`, `invalid(location, message)`, `unsupported`, and `tooLarge`. A successful empty string is copyable. Do not use nonempty text as the validity test.
- Disable copy before scheduling new work. Publish a completion only if its entire identity is still current. Dismissal retires the session ID so cooperative cancellation cannot publish a result after close and reopen.
- Copy uses the exact primary text of the visible successful snapshot. Recheck the identity immediately before writing on the same serialized context that owns session state. Prevent duplicate writes. A failed write keeps the panel open and reports the error.
- Run potentially expensive work away from the UI thread. Start with proposed limits of 1 MiB UTF-8 input, 4 MiB output, and 128 levels of JSON or XML nesting. Enforce limits before allocating expanded output where possible. A limit error disables copy and gives no partial result.
- Generate a UUID on first selection per session. Keep it when switching views, tools, or filters. **Regenerate** replaces it. Provide a fixed clock for tests that depend on expiry presentation.
- Route attachment and editor paste through the same native paste command. In search, consume the provided text as an attachment and leave the query intact. In the editor, insert it through the text control. The attachment row shows its source, detected type when available, and UTF-8 byte count. Run detection on the attached text after paste.
- A draft includes the query, payload, options, edits, selection, generated values, result, and pending work. Back preserves it. Dismissal, Copy & Close, external app switching, screen lock, and quit retire it. Clearing input immediately invalidates its result. Keep the draft in memory for the panel session and persist preferences separately.

## First-release tool contracts

Each command defines its input, diagnostics, and primary copy target.

### JSON

Format/minify change insignificant whitespace only, preserving string escapes, numeric tokens, member order, and duplicate names. Validate the grammar independently of formatting; do not serialize through floating-point values or a dictionary. Accept scalar roots. Report duplicate-name interoperability risk without dropping data. Use two spaces and LF by default; no trailing LF. Reject comments, trailing commas, and a leading BOM in v1 with a specific error. Locations use one-based lines and Unicode-scalar columns, treating CRLF as one line break. Primary copy is transformed JSON, or unchanged input for Validate. [RFC 8259, §§2,4,6,8](https://www.rfc-editor.org/rfc/rfc8259.html)

### XML

**Validate XML** checks well-formedness and namespace usage for one pasted XML 1.0 document. Show **Well-formed XML** on success and make the original text the primary copy result. Report the first syntax error with a one-based line and column in the original input. DTD and schema validation are outside the first release. [XML 1.0, §§2.1,5.1](https://www.w3.org/TR/xml/#sec-well-formed) · [Namespaces in XML 1.0](https://www.w3.org/TR/xml-names/)

Both XML commands accept the pasted Unicode text directly. Reject a document type declaration as unsupported before processing its entities. Allow predefined XML entities and numeric character references. Keep parsing local to the pasted text, with external entity resolution disabled and schema locations and XInclude elements treated as ordinary markup. [XML 1.0, §§2.8,4](https://www.w3.org/TR/xml/#sec-prolog-dtd) · [Apple XMLParser entity resolution](https://developer.apple.com/documentation/foundation/xmlparser/externalentityresolvingpolicy-swift.enum/never)

**Format XML** validates first, then uses two spaces and LF for indentation in elements whose direct content consists of child markup and optional indentation whitespace. Preserve mixed-content regions and whitespace wherever `xml:space="preserve"` is in effect, including inherited settings. Keep text outside the indentation regions and preserve reference spelling, namespace prefixes and declarations, attributes, comments, CDATA sections, processing instructions, and the XML declaration. Use the formatted text as the primary copy result. [XML 1.0, §§2.4–2.11](https://www.w3.org/TR/xml/#sec-white-space)

### Base64

Encode UTF-8 text with an explicitly selected alphabet: Standard emits required padding; URL-safe emits unpadded output. Decode Standard with required padding where needed; URL-safe accepts correctly padded or unpadded input. Reject mixed alphabets, misplaced padding, impossible lengths, and nonzero pad bits. Reject whitespace by default; an explicit Ignore ASCII whitespace option may remove space, tab, CR, and LF only. Reject non-UTF-8 decoded bytes with **Decoded bytes are not UTF-8 text**; binary export is deferred. Copy the encoded or decoded text, including valid empty output. These strictness choices are product policy. [RFC 4648, §§3–5,10](https://www.rfc-editor.org/rfc/rfc4648.html)

### URL

Separate Encode component, Decode component, and Inspect query. Encode UTF-8 bytes outside the unreserved set using uppercase escapes; do not advertise this as encoding an entire URL. Decode once, rejecting malformed escapes/non-UTF-8 text. Query inspection splits on literal `&` and the first literal `=` before decoding; preserve repeated keys, empty names/values, and order. Split a full URL's raw query before its fragment, without fetching it. Skip empty separator-only segments, while retaining explicit empty-name pairs. Bare `flag` displays as an empty value. Keep raw `+` in default URI mode; Form mode explicitly maps it to space. Copy an ordered JSON array of name/value strings, not a dictionary. [RFC 3986, §§2–3](https://www.rfc-editor.org/rfc/rfc3986.html) · [WHATWG form parsing](https://url.spec.whatwg.org/#urlencoded-parsing)

### JWT

Inspect the common three-segment compact JWT form with JSON-object header and claims. Label all decoded views **Signature unverified**, including `alg: none`; do not infer trust from decoding or expiry. No keys, signature verification, signing, or remote key discovery in v1. Recognize a five-segment encrypted token as unsupported rather than inventing claims. Interpret numeric `exp`, `iat`, and `nbf` as NumericDate seconds, including fractions. Missing `exp` means **No expiry claim**; a nonnumeric value gets a field warning. Say **Expiry is in the past**, never **Token valid**. Primary copy is the decoded claims JSON; header and individual claims have explicit field-copy actions. [RFC 7519, §§2,4,7](https://www.rfc-editor.org/rfc/rfc7519.html)

### Timestamps

Default a visible unit selector to Seconds; Milliseconds is explicit. Do not infer correctness from digit count. Support signed values at millisecond precision; reject extra fractional precision rather than silently rounding. Date input is an RFC 3339 subset requiring a numeric offset or `Z`; reject offsetless/localized dates and leap-second notation in v1 with an explanation. UTC output is `YYYY-MM-DDTHH:mm:ss.SSSZ`; local display includes its offset. Primary copy is UTC text for Unix → date, or an exact decimal in the selected unit for date → Unix. Bound supported dates to years 0001–9999, reporting range failures. [RFC 3339](https://www.rfc-editor.org/rfc/rfc3339.html)

### UUID

Use platform-provided secure random generation for UUID v4. Copy lowercase canonical hyphenated text. Test version and variant bits and stability within a session, not an expected random value. Do not claim a generator creates a password or an authentication token. [RFC 9562, §§4,5.4](https://www.rfc-editor.org/rfc/rfc9562.html)

## Independent expected-result fixtures

Use these expected results to test the tool implementation. Literal strings use JSON escape notation where necessary.

| Case | Input / action | Required result |
| --- | --- | --- |
| JSON precision and spelling | Minify `{"n":9007199254740993, "e":1e+02, "z":-0}` | `{"n":9007199254740993,"e":1e+02,"z":-0}` |
| JSON duplicates / string whitespace | Minify `{"a":1, "a":2, "s":"a  b"}` | `{"a":1,"a":2,"s":"a  b"}`; duplicate warning, no member loss |
| JSON scalar | Format `true` | `true`, successful and copyable |
| JSON syntax location | Two-line fixture below | Invalid at line 2, column 8; no copy |
| XML formatting | Format `<r xmlns:p="urn:example"><p:a id="1"/><p:b/></r>` | `<r xmlns:p="urn:example">\n  <p:a id="1"/>\n  <p:b/>\n</r>` |
| XML mixed content | Format `<p>Hello <b>world</b> !</p>` | Original text, including the spaces on both sides of the child element |
| XML whitespace and markup | Format `<r xml:space="preserve"><x><a/>  <b/><!--keep--><![CDATA[ < ]]><?keep x?></x></r>` | Original text, including inherited whitespace, the comment, CDATA, and processing instruction |
| XML validation and location | Validate `<r xmlns:p="urn:example"><p:x>&amp;&#x20;</p:x></r>`, then `<r>\n  </wrong>` | The first input is well formed and copies unchanged. The second reports a line and column on line 2 and disables copy. |
| XML document type | Format or validate `<!DOCTYPE r SYSTEM "https://example.test/r.dtd"><r/>`, the same declaration with `file:///example.dtd`, and `<!DOCTYPE r [<!ENTITY x "text">]><r>&x;</r>` | Unsupported `DOCTYPE` diagnostic. The parser performs no network or file reads and expands no custom entity. |
| Base64 UTF-8 | Encode `✓` in Standard | `4pyT`; decoding returns `✓` |
| Base64 alphabet and padding | Encode `😀` in Standard and URL-safe modes | Standard emits `8J+YgA==`. URL-safe emits `8J-YgA` and accepts `8J-YgA==` as well. |
| Base64 canonical/non-text | Decode `Zh==` / `/w==` in Standard | First rejected for nonzero pad bits; second rejected as non-UTF-8 text |
| Empty output | Decode attached empty string | Success with empty primary text; copy enabled |
| URL decoding | Decode component `a+b%20c%252F` | `a+b c%2F`; exactly one decoding pass |
| URL query | Inspect `https://example.test/?a=1&a=2&empty=&flag&=x#end` | `[{"name":"a","value":"1"},{"name":"a","value":"2"},{"name":"empty","value":""},{"name":"flag","value":""},{"name":"","value":"x"}]` |
| Query mode | Inspect `q=a+b%2Bc` | URI: value `a+b+c`; Form: value `a b+c` |
| Malformed URL text | Decode `%G0`, `%`, `%FF` | Invalid, invalid, non-UTF-8 error; never a partial copy |
| JWT no authenticity | Inspect `eyJhbGciOiJub25lIn0.eyJleHAiOjAsInN1YiI6IngifQ.` with test clock after epoch | Claims `{"exp":0,"sub":"x"}`, expiry in past, signature unverified |
| Unix units | `0` s; `-1` s; `1700000000` s; `1700000000000` ms | `1970-01-01T00:00:00.000Z`; `1969-12-31T23:59:59.000Z`; last two both `2023-11-14T22:13:20.000Z` |
| Offset conversion | `2024-01-01T01:00:00+01:00` → Unix seconds | `1704067200` |
| UUID shape | Generate, switch tools, return, regenerate | Same value until explicit regeneration; version nibble `4`, variant nibble in `8,9,a,b` |
| Stale result | Delay A; submit B; complete B then A | Only B is visible/copyable; repeat across close/reopen and option changes |
| Bounded work | Input exceeds 1 MiB / formatted result exceeds 4 MiB / nesting exceeds 128 | Explicit limit error, responsive UI, no partial copy |

Syntax-location fixture (the second line begins with two spaces):

```text
{
  "a": }
```

For structured copy targets, compare parsed structure and order unless canonical formatting is specified. Compare exact text for JSON and XML formatting and component transforms. Verify every tool offline and exercise each error after a previously successful result.

## Native panel prototype

Start with the panel shell, then exercise JSON and UUID to prove both input paths. Record the tested OS and hardware, deployment target, distribution route, shortcut mechanism, and observed permissions and limitations.

- Try `NSPanel` with `.nonactivatingPanel` and `.accessory` activation policy. Test eligible floating window behavior in Stage Manager and full-screen Spaces, including `.canJoinAllApplications` on macOS 13 and later. Test actual keyboard focus and observe app activation separately from the panel resigning key status. [Apple NSPanel](https://developer.apple.com/documentation/appkit/nspanel) · [Accessory activation policy](https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/accessory) · [Window collection behavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications)
- Evaluate the Carbon-backed KeyboardShortcuts package as a candidate for registration and shortcut recording. Verify the chosen method in the signed build. If login launch is offered, test an opt-in registration with `SMAppService` where available. [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) · [Apple login registration](https://developer.apple.com/documentation/servicemanagement/smappservice/register())
- Capture the frontmost app on invocation. After a successful copy, request focus return if needed and leave the copy successful if the origin app exits or the system refuses activation. Use the pasteboard write API’s success result to decide whether to dismiss the panel. [Apple frontmost application](https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication) · [Apple app activation](https://developer.apple.com/documentation/appkit/nsrunningapplication/activate(from:options:)) · [Apple pasteboard write result](https://developer.apple.com/documentation/appkit/nspasteboard/writeobjects(_:))

### Exit criteria

| Area | Required observation |
| --- | --- |
| Invocation | The recorded hotkey and menu-bar launch work. An unsuccessful registration is recoverable. Repeated invocation focuses the existing panel and preserves its session. |
| Placement | Target the display containing the source app's key window when available, falling back to the pointer display. Clamp the panel to visible bounds and handle display removal. Validate how reliably AppKit can identify the source display without extra permissions. |
| Spaces / Stage Manager | The first typed character lands in search in ordinary, full-screen, and Stage Manager sessions. The panel opens on the user’s current workspace. |
| Focus | Copy & Close returns to the invoking app when the OS permits. A successful copy stays successful if the origin exits or activation is refused. App switching during evaluation dismisses the panel and leaves focus where the user moved it. |
| Paste | Native Paste works with programmatic access allowed, denied, and asking on OS versions that expose this policy. Opening and navigating the panel leave the pasteboard untouched. Non-text paste preserves existing input. [Apple pasteboard access behavior](https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum) |
| Session end | Root Escape, successful Copy & Close, app switch, and screen lock clear state and retire pending work. Field Copy and Back preserve the draft. |
| Input / accessibility | IME composition gets Return/Escape first. Native editing, Full Keyboard Access, VoiceOver, large text, increased contrast, reduced motion, and light/dark appearance remain usable. |
| Responsiveness | Establish initial budgets of ≤150 ms warm invocation to usable search and ≤100 ms evaluation for a 10 KiB input on documented hardware. Measure rather than claim these targets; test limit-sized input separately and verify the UI can cancel/close. |
| Distribution | Test the selected sandbox and signing configuration, including restart and login behavior. Confirm the actual permissions required for shortcut registration, paste, and copy. |
