# Review findings and implementation contracts

Review baseline: `558498e` on `main`, checked 12 November 2026. The repository contains a product plan, not an app implementation. The six-tool scope, explicit paste, shared preview/editor evaluation, stable UUIDs, and on-device session state are good foundations. The following are design gaps to close before implementation; no runtime bug is claimed.

## Findings addressed

| Priority | Baseline location | Gap and consequence | Proposed resolution |
| --- | --- | --- | --- |
| High | `docs/product-plan.md:67` | “Primary result” is undefined for inspectors. Different views could copy different content. | Declare the exact copy payload per command; a focused field never changes it implicitly. |
| High | `docs/product-plan.md:11–15` | Precision and decoding goals lack boundary policies. A generic parse/reserialize implementation could round JSON numbers, collapse duplicate keys, or conflate URL/form decoding. | Add deterministic fixtures and explicit text/alphabet/unit policies below. |
| High | `docs/product-plan.md:46,102` | Stale results are mentioned, but the identity of a current result is not defined. An old completion could become copyable after input/options change or panel reopening. | Bind evaluation and copy eligibility to a full session/revision identity. |
| Medium | `docs/product-plan.md:44,97` | Hiding only recognized tokens still exposes undetected secrets in snippets. “Draft” and clearing are not fully defined. | Use metadata-only attachment summaries for all input and an explicit session lifetime. |
| Medium | `docs/product-plan.md:91,101` | Focus return reads as guaranteed; native feasibility omits Stage Manager and permission-state testing. | Make activation best effort; add native spike exit criteria. |
| Medium | `docs/product-plan.md:102` | “Same input and options” is deterministic for transforms, but not a random generator. | Keep generation as an explicit session event, separate from pure evaluation. |

## State, evaluation, and copy

Use three small boundaries: pure tool evaluation; a session coordinator for selection, edits, and generation; and Mac adapters for hotkeys, windows, pasteboard, and app activation. This is a proposed division of responsibility, not a requirement for a particular framework or package.

- An evaluation request carries `sessionID`, `revision`, `commandID`, complete options, and the input snapshot. Increment revision immediately on input, command, or option changes; changing a generated value also increments it. `noInput` and an attached empty string are distinct.
- Results distinguish `needsInput`, `pending`, `success(primaryText, fields, warnings)`, `invalid(location, message)`, `unsupported`, and `tooLarge`. A successful empty string is copyable. Do not use nonempty text as the validity test.
- Set copy ineligible synchronously before scheduling new work. Publish a completion only if its entire identity is still current. Dismissal retires the session ID; cancelling a task alone is insufficient because cancellation is cooperative.
- Copy uses the exact primary text of the visible successful snapshot. Recheck identity on the serialized UI/session context immediately before writing; do not launch another transform on the copy path. Prevent duplicate submissions. A failed write retains the panel and reports failure; do not promise restoration of the previous clipboard if an OS write partially fails.
- Run potentially expensive work away from the UI thread. Proposed starting limits: 1 MiB UTF-8 input, 4 MiB result, and 128 levels of JSON nesting. Reject rather than truncate; enforce limits before allocating expanded output where possible. These are product budgets to validate, not format-standard limits. Disable copy of a partial/truncated preview.
- Generate a UUID once on first selection per session. Cache it across preview/editor/back/filter changes; only Regenerate replaces it. Transforms remain deterministic. Inject time when testing expiry presentation rather than baking the wall clock into expected output.
- A draft includes query, payload, options, editor changes, selected command, generated values, result/error, and pending work. Back preserves it. Dismissal, copy-and-close, external app switching, screen lock, and quit retire it. Clear input invalidates results immediately. Do not persist or log payloads, derived text, or queries; a query can itself contain a secret. Clearing references is not a guarantee of forensic memory erasure.

## First-release tool contracts

These policies deliberately narrow general-purpose standards for a text-only palette. Format citations establish the relevant semantics; the limits, defaults, and copy targets are Toolchord decisions.

### JSON

Format/minify change insignificant whitespace only, preserving string escapes, numeric tokens, member order, and duplicate names. Validate the grammar independently of formatting; do not serialize through floating-point values or a dictionary. Accept scalar roots. Report duplicate-name interoperability risk without dropping data. Use two spaces and LF by default; no trailing LF. Reject comments, trailing commas, and a leading BOM in v1 with a specific error. Locations use one-based lines and Unicode-scalar columns, treating CRLF as one line break. Primary copy is transformed JSON, or unchanged input for Validate. [RFC 8259, §§2,4,6,8](https://www.rfc-editor.org/rfc/rfc8259.html)

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

These are an acceptance corpus for the future implementation, not tests that have been run against a native app. Literal strings below use JSON escape notation where necessary. Establish these expectations before writing tool code; add implementation tests from them later.

| Case | Input / action | Required result |
| --- | --- | --- |
| JSON precision and spelling | Minify `{"n":9007199254740993, "e":1e+02, "z":-0}` | `{"n":9007199254740993,"e":1e+02,"z":-0}` |
| JSON duplicates / string whitespace | Minify `{"a":1, "a":2, "s":"a  b"}` | `{"a":1,"a":2,"s":"a  b"}`; duplicate warning, no member loss |
| JSON scalar | Format `true` | `true`, successful and copyable |
| JSON syntax location | Two-line fixture below | Invalid at line 2, column 8; no copy |
| Base64 UTF-8 | Encode `✓` in Standard | `4pyT`; decoding returns `✓` |
| Base64 alphabet/padding | Encode `ÿ` in Standard / URL-safe | `w78=` / `w78`; URL-safe decode accepts both `w78` and `w78=` |
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

For structured copy targets, compare parsed structure and order unless canonical formatting is specified. For JSON format/minify and component transforms, compare exact output text. Also verify every tool offline and every error transition after a previously successful result.

## Native spike exit criteria

Build only the panel shell plus JSON/UUID first. Do not select minimum macOS version or distribution from documentation alone. Record the chosen deployment target, tested OS/hardware, shortcut mechanism, permission requirements, and observed limitations in the spike result.

| Area | Required observation |
| --- | --- |
| Invocation | Recorded hotkey and menu-bar launch work; an unsuccessful registration is recoverable. Repeated invocation focuses the existing panel rather than creating another session/window. |
| Placement | Target the display containing the source app's key window when available; otherwise use the pointer display. Clamp to visible bounds; handle display removal. Validate how reliably AppKit can identify the source display without extra permissions. |
| Spaces / Stage Manager | First typed character lands in search in ordinary, full-screen, and Stage Manager sessions; the panel does not move the user's workspace unexpectedly. |
| Focus | Copy success returns to the invoking editor when the OS permits; origin exit or denied activation does not turn clipboard success into failure. App switching during evaluation dismisses without stealing focus. |
| Paste | Opening/navigation makes no clipboard reads. Genuine Paste works with programmatic access allowed, denied, and asking on OS versions that expose this policy. Non-text paste preserves existing input. |
| Session end | Root Escape, successful Copy & Close, app switch, and screen lock clear state and retire pending work. Field Copy, Copy without closing, and Tool Back preserve the draft. |
| Input / accessibility | IME composition gets Return/Escape first. Native editing, Full Keyboard Access, VoiceOver, large text, increased contrast, reduced motion, and light/dark appearance remain usable. |
| Responsiveness | Establish initial budgets of ≤150 ms warm invocation to usable search and ≤100 ms evaluation for a 10 KiB input on documented hardware. Measure rather than claim these targets; test limit-sized input separately and verify the UI can cancel/close. |
| Distribution | Test the selected sandbox/signing route and restart/login behavior. Confirm the core workflow's actual permissions; do not assume auto-paste or selected-text capture is required. |

Apple documents [`canJoinAllApplications`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications) for eligible floating overlays in Stage Manager and full-screen Spaces (macOS 13+), [`activate(from:options:)`](https://developer.apple.com/documentation/appkit/nsrunningapplication/activate(from:options:)) as a request rather than a guarantee (macOS 14+), and [`NSPasteboard.AccessBehavior`](https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum) as a user-paste/programmatic-access distinction (macOS 15.4+). Availability does not set Toolchord's minimum OS. Choose availability-gated APIs and verify the actual panel configuration; no native behavior has been tested by this documentation PR.
