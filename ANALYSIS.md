# Remaining Toolchord findings

Reviewed on 2026-11-12 against `6714272`, consolidated on 2026-11-13. File/line references refer to the review baseline. Findings implemented in open PRs are omitted. All remaining findings are optional improvements; observations that still need live validation are identified below.

### Empty search results retain a stale accessibility selection

bugs — nice-to-have

Location: `Sources/ToolchordMac/Views/SearchField.swift:51–53`.

When a query stops matching any command, the field keeps its previous accessibility value description. VoiceOver users can encounter a tool name that is no longer selected. Missing reset is source-confirmed; live announcement behavior was not exercised.

Set or clear the accessibility description on every update, including the no-selection state. Rough effort: 30 minutes.

### Bearer-prefixed JWT input misses JWT suggestions

bugs — nice-to-have

Location: `Sources/ToolchordCore/Detection/InputDetector.swift:48–55,143–151`; `Sources/ToolchordCore/Tools/JWTTools.swift:14–17`.

Developers pasting a complete Authorization value must manually search for Decode JWT, even though the decoder explicitly accepts the prefix. The detector's single-token gate excludes the space after Bearer.

Recognize a bounded Bearer-prefixed token for detection without modifying the attached input; keep the decoder's removal warning. Rough effort: 1 hour.

### BOM-bearing XML misses XML suggestions

bugs — nice-to-have

Location: `Sources/ToolchordCore/Detection/InputDetector.swift:43–46`.

Pasting U+FEFF followed by `<r/>` labels it Text and omits XML suggestions, even though XMLTools accepts an initial BOM. This affects XML copied from BOM-bearing files and was confirmed against the built module.

Ignore one initial BOM for lexical detection while retaining the original payload bytes and diagnostic offsets. Rough effort: 1 hour.

### Nonhierarchical URIs miss Inspect URL suggestions

bugs — nice-to-have

Location: `Sources/ToolchordCore/Detection/InputDetector.swift:158–170`.

URI detection requires `://`, although Inspect URL accepts `mailto:a@example.com`, `data:text/plain,Hi` and `file:/tmp/a`. Users inspecting these forms receive Text suggestions instead. Confirmed against the built module.

Align bounded scheme recognition with the inspector, retaining safeguards for drive-letter paths and ordinary prose. Rough effort: 1–2 hours.

### Padded numeric entities miss decoder suggestions

bugs — nice-to-have

Location: `Sources/ToolchordCore/Detection/InputDetector.swift:325–328`.

The detector looks ahead only 12 characters after an ampersand, while HTMLTools accepts numeric references with up to 32 digits. A valid reference such as `&#0000000000065;` decodes successfully but does not suggest Unescape HTML. This affects uncommon numeric-entity input.

Align the bounded numeric-reference lookahead with the decoder's limit, without broadening named-entity support accidentally. Rough effort: 1 hour.

### The benchmark exercises early rejection for many tools

general issues — nice-to-have

Location: `Sources/ToolchordSnapshots/main.swift:110–148`.

Maintainers see green/fast benchmark output for XML, Base64 decode, JWT, number, hex decode and color paths that mostly reject the shared JSON fixture. Real successful-path regressions can escape measurement.

Supply valid per-family fixtures and report successful and rejected-input timings separately. Keep exact byte sizes in the output. Rough effort: Half a day.

### Snapshot coverage omits accessibility and stress states

general issues — nice-to-have

Location: `Sources/ToolchordMac/Snapshots/SnapshotRenderer.swift:19–70`.

Maintainers still lack long-field, high-contrast, and constrained-height scenarios. Long copy titles and the full horizontal footer also need stress coverage at narrow widths, beyond the existing 600-point simple case. Actual footer overflow is not established. Dense-option and four-warning JWT coverage is implemented in open PRs and is excluded from this remaining work.

Add a small representative set and document manual checks for real glass, keyboard traversal, and VoiceOver. If footer crowding is reproduced, hide low-priority hints first. Offscreen snapshots cannot prove interactive behavior; attempts to inspect SwiftUI accessibility in the Swift Testing host returned an empty tree. Rough effort: Half a day.

### Multiple line scanners need an explicit shared contract

general issues — nice-to-have

Location: `Sources/ToolchordCore/Tools/LineTools.swift:174–262`; `Sources/ToolchordCore/Tools/CaseTools.swift:215–248`; `Sources/ToolchordCore/Detection/InputDetector.swift:382–399`.

Maintainers must reason independently about CR, LF, CRLF and trailing-break conventions across several scanners; detection counts a trailing break differently from Count Characters. This is not necessarily incorrect but is easy to change inconsistently.

Document the intentional counting differences and consolidate shared byte-scanning mechanics only if that simplifies the code. Add shared newline fixtures rather than a speculative abstraction. Rough effort: Half a day.

### Near-limit Markdown conversion takes about one second

performance problems, stuttering, and jank — nice-to-have

Location: `Sources/ToolchordCore/Tools/Markup/MarkdownDocument.swift:179–220`; reproducible with `make benchmark`.

Large-document users wait about 1,004 ms for Markdown-to-HTML and 937 ms for Markdown-to-text in this release benchmark. Work is off the main actor, but the Foundation parser is not interruptible, so superseded work can continue. This is already acknowledged in the implementation contracts.

Profile parser versus reconstruction cost, consider a longer debounce for large edits or a cancellable parser only if measurements justify the dependency and fidelity tradeoffs. Preserve current copy gating. Rough effort: 1–3 days for profiling and a bounded improvement; parser replacement needs separate design.

### Case transformations cancel only between large batches of lines

performance problems, stuttering, and jank — nice-to-have

Location: `Sources/ToolchordCore/Tools/CaseTools.swift:336–358,405–473`.

Large single-line payloads still finish scanning/splitting/transliterating after their results are obsolete; line-based checks do not help them. Case conversions measured about 183–317 ms at near 1 MiB, off the main actor. Repeated edits can waste CPU.

Add cancellation checkpoints during scalar/byte scanning and avoid intermediate Character arrays where practical. Measure single-line and multiline payloads independently; Foundation transliteration itself may remain non-interruptible. Rough effort: Half a day to one day.

### Inspector sizing scans entire field values on the main actor

performance problems, stuttering, and jank — nice-to-have

Location: `Sources/ToolchordMac/Views/PaletteView.swift:526–530`.

Large JWT/URL fields are traversed completely when estimating a row that shows at most four lines. This is avoidable work on view updates; an actual frame stall was not measured.

Stop after the third newline and use a bounded newline scan, caching only if profiling warrants it. Rough effort: 1 hour.

### Detection precedes editor debounce on the main actor

performance problems, stuttering, and jank — nice-to-have

Location: `Sources/ToolchordSession/PaletteSession.swift:18–22,278–282`.

Editing a near-limit payload runs the complete profiler synchronously before the 60 ms evaluation debounce. Detection alone took 33–43 ms for 1 MiB Debug samples on the review host. Release typing jank is not established, so this is a measurement opportunity rather than a confirmed frame stall.

Measure optimized typing latency, then bound or defer profiling if needed while preserving immediate stale-result copy invalidation. Rough effort: Half a day for measurement and a safe design.

### Superseded line transformations do not stop cooperatively

performance problems, stuttering, and jank — nice-to-have

Location: `Sources/ToolchordCore/Tools/LineTools.swift:34–174`.

Sorting, deduplication and reversal do not consult request cancellation, so obsolete work can keep using background CPU. Session revisions correctly prevent stale publication and copy. No material throughput regression was measured.

Add useful checkpoints around long stages and within traversals where practical; measure large-line workloads before changing the sorting algorithm. Rough effort: 2–4 hours.

### Long inspector fields have no full-value view

missing features — nice-to-have

Location: `Sources/ToolchordMac/Views/PaletteView.swift:567–570`.

People inspecting long JWT headers/claims and URL values can copy the complete value but can only read four lines inside Toolchord.

Add an accessible field expansion or read-only details popover while keeping compact default rows. Rough effort: 2–4 hours.

### Markdown fidelity limitations are invisible in the result

missing features — nice-to-have

Location: `docs/implementation-contracts.md:86`; `Sources/ToolchordCore/Tools/Markup/MarkdownDocument.swift:64–78`.

README converters can lose link/image titles, reference-style images inside links, empty structures, and formatting beyond recovery limits. These are documented parser limitations, but the app reports only “Rendered HTML”.

Surface a concise limitation note where a lossy path is detectable, then evaluate fuller source parsing against representative fixtures. Do not promise full CommonMark fidelity without coverage. Rough effort: Half a day for disclosure; fuller fidelity is a multi-day parser task.

### Pasted UUIDs have detection but no inspector

missing features — nice-to-have

Location: `Sources/ToolchordCore/Detection/InputDetector.swift:205–220`; `Sources/ToolchordCore/Tools/UUIDTools.swift:8–48`.

Developers can generate UUIDs but cannot inspect a pasted identifier's version, variant or v7 timestamp in the palette, despite UUID detection already existing.

Add a separate Inspect UUID command with strict validation, normalized forms and v7 timestamp fields. Keep generators' stable-seed behavior unchanged. Rough effort: Half a day to one day.

### Named CSS colors are unsupported despite the type comment

missing features — nice-to-have

Location: `Sources/ToolchordCore/Tools/ColorTools.swift:142–223`; `Sources/ToolchordCore/Detection/InputProfile.swift:16`.

Neither detection nor conversion accepts names such as `red` or `rebeccapurple`, although the color-kind comment claims named-color support. Web developers must look up the numeric form themselves. This is an optional feature extension; the user-facing conversion contract lists hex, RGB and HSL.

Consider a shared standard name table for detection and conversion, including transparent, with contract fixtures and no network dependency. Until then, narrow the capability comment to supported syntax. Rough effort: Half a day for support; minutes for the comment correction.

### Each result refresh resets the reading position

usability: fast, convenient, and clear — nice-to-have

Location: `Sources/ToolchordMac/Views/CodeTextView.swift:208–213`.

Users editing a long document lose their place in the output whenever evaluation succeeds because the result scrolls back to the beginning.

Preserve and clamp the scroll position for edits to the same tool/input. Reset deliberately for a newly selected tool or attached payload. Rough effort: 2–3 hours.

### Pending field Copy controls look usable but do nothing

usability: fast, convenient, and clear — nice-to-have

Location: `Sources/ToolchordMac/Views/PaletteView.swift:465–475,580`.

Previous inspector output is dimmed during reevaluation, but its field Copy buttons are not disabled. Clicking them does nothing because session gating correctly rejects stale writes. Users get no explanation for the apparently available action.

Disable field Copy controls with the pending state, preserving the existing session-level guard. Rough effort: Under an hour.

### Immediate progress badges can defeat delayed progress treatment

usability: fast, convenient, and clear — nice-to-have

Location: `Sources/ToolchordMac/Views/PaletteView.swift:735,956`.

The result spinner waits 150 ms to avoid flicker, but the status badge immediately shows a spinner and Working text on every pending transition. Rapid typing or selection can therefore still produce distracting status changes. This is source-established behavior; no frame capture was made.

Share a delayed pending-indicator policy between the badge and result pane, without delaying invalidation or copy gating. Rough effort: 1–2 hours.

### Transparency is hard to distinguish in color swatches

aesthetics and theming — nice-to-have

Location: `Sources/ToolchordMac/Views/PaletteView.swift:609–614`.

Designers inspecting translucent colors see them blended directly into the panel and cannot easily distinguish alpha from the surrounding surface.

Put a subtle checkerboard under swatches, optionally with light/dark halves. Rough effort: 1–2 hours.

### Custom surfaces have no dedicated high-contrast treatment

aesthetics and theming — nice-to-have

Location: `Sources/ToolchordMac/Views/Theme.swift:28–32,56–62`.

Users enabling Increase Contrast receive the same custom well/selection fills and syntax palette. System colors can adapt, but the custom colors do not. No measured contrast failure is claimed.

Add explicit high-contrast borders/background variants and test over real busy wallpapers as well as opaque snapshots. Rough effort: Half a day.

### Code text size is fixed

aesthetics and theming — nice-to-have

Location: `Sources/ToolchordMac/Views/Theme.swift:23`.

Users who prefer larger text cannot adjust the 12-point input/output font independently of macOS display scaling.

Offer a small set of code-font sizes or standard zoom shortcuts, persist only the preference, and validate minimum useful editor space. Rough effort: Half a day.

### Use the current result as the next tool's input

novel, delightful, or quirky ideas worth trying — nice-to-have

Location: `Sources/ToolchordMac/Panel/PanelController.swift:309–374`.

Decode Base64 → format JSON or HTML → clean plaintext currently requires copy and paste, replacing the user's clipboard along the way.

Add an explicit session-local “Use result as input” action that attaches the ready primary output and returns to search, preserving revision/copy gating and requiring no saved history. Rough effort: Half a day for a prototype; 1–2 days with reversible draft handling.

Preserve a clear way back to the original draft if a chain is introduced; draft ownership and undo behavior need an explicit design before implementation.

### Optional examples could teach unfamiliar tools

novel, delightful, or quirky ideas worth trying — nice-to-have

Reproduction: Open an unfamiliar tool with no input; the empty state asks for a paste but gives no example of accepted syntax.

First-time users of time offsets, number prefixes, colors and encoding tools must guess syntax or consult docs.

Add a clearly labeled “Try an example” action for selected tools, using deterministic public synthetic fixtures and an explicit user action that explains it replaces the current input. Keep ordinary opening free of injected sample data. Rough effort: Half a day for a small curated set and session tests.

### Explain ambiguous automatic suggestions briefly

novel, delightful, or quirky ideas worth trying — nice-to-have

Location: `Sources/ToolchordMac/Views/PaletteView.swift:163–170`; `Sources/ToolchordSession/CommandListing.swift`.

Curious users cannot see why ambiguous input was labeled Base64, hex or a timestamp. A detection label can be mistaken for validation.

Prototype a short metadata tooltip explaining the lexical hint without displaying pasted secrets or claiming validity. Keep it out of the fast keyboard path and validate demand before adding persistent UI. Rough effort: Half a day.
