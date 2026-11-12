# Review synthesis and reconciliation

Review baseline: `main` at `558498e`, plus open proposals #1–#9, checked 12 November 2026. This is a review artifact for combining the parallel proposals, not a new product spec. It records the technical claims that were checked, the conflicts between proposals, and a merge order.

## Verified technical claims

Every Apple API claim in the proposals was checked against Apple's documentation. All are accurate.

| Claim | Source |
| --- | --- |
| `NSPasteboard.detectedPatterns(for:)`, `detectedValues(for:)`, `detectedMetadata(for:)`; macOS 15.4+ | [Apple](https://developer.apple.com/documentation/appkit/nspasteboard/detectedpatterns(for:)) |
| `NSPasteboard.AccessBehavior`; macOS 15.4+; cases `.default`, `.ask`, `.alwaysAllow`, `.alwaysDeny` | [Apple](https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum) |
| Detection types include `.links`, `.probableWebURL`, `.probableWebSearch`, `.emailAddresses`, `.number`, `.moneyAmounts`, `.phoneNumbers`, `.postalAddresses`, `.calendarEvents`, `.flightNumbers`, `.shipmentTrackingNumbers` | [Apple](https://developer.apple.com/documentation/appkit/nspasteboard-detection-patterns) |
| `NSPanel`; `NSWindow.StyleMask.nonactivatingPanel` | [Apple](https://developer.apple.com/documentation/appkit/nspanel) |
| `NSWindow.CollectionBehavior.canJoinAllApplications` macOS 13+; `.fullScreenAuxiliary` macOS 10.7+; `.canJoinAllSpaces` macOS 10.5+ | [Apple](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications) |
| `NSRunningApplication.activate(from:options:)` macOS 14+ | [Apple](https://developer.apple.com/documentation/appkit/nsrunningapplication/activate(from:options:)) |
| `SMAppService` macOS 13+ | [Apple](https://developer.apple.com/documentation/servicemanagement/smappservice) |
| `CIQRCodeGenerator` is a Core Image filter available on macOS | [Apple](https://developer.apple.com/documentation/coreimage/ciqrcodegenerator) |
| Carbon `RegisterEventHotKey` is the global-hotkey API that needs no Accessibility permission; deprecated-adjacent with no replacement | [KeyboardShortcuts source](https://github.com/sindresorhus/KeyboardShortcuts/blob/main/Sources/KeyboardShortcuts/HotKey.swift) |
| KeyboardShortcuts (sindresorhus) wraps Carbon hotkey registration and ships a recorder | [GitHub](https://github.com/sindresorhus/KeyboardShortcuts) |
| `org.nspasteboard.ConcealedType` is a community convention (nspasteboard.org), not an Apple API | [nspasteboard.org](https://nspasteboard.org) |

### One overclaim to correct

The palette UX (#2), plan review (#3), and implementation notes (#9) say `org.nspasteboard.ConcealedType` makes "clipboard managers and Universal Clipboard skip" a result. nspasteboard.org defines the marker as confidential content and asks apps to avoid recording it or to encrypt it; it does not promise Universal Clipboard handling. Clipboard managers that honor the convention (Maccy, Paste, Alfred, Raycast) skip it. Reword to "clipboard managers that honor the convention skip it" and treat Universal Clipboard behavior as untested.

## Conflicting proposals

Four proposals edit `docs/product-plan.md` (#3, #4, #6, #8). The table records each conflict and a recommended resolution. Recommendations favor the option that is testable and does not silently lose user work.

| Topic | Proposals | Recommendation |
| --- | --- | --- |
| App switch while panel open | #3, #4, and #6: dismiss and discard the draft. #8: hide and keep the draft in memory. | Keep the draft but hide the panel (#8). A brief detour should not lose work; clear on root Escape, Copy & Close, screen lock, and quit. Add an acceptance check that a hidden draft reappears. |
| Attachment snippet | #3 and #8: show a short snippet for ordinary text. #2, #6, and #7: omit raw snippets for every type. | Omit snippets (#2/#6/#7). Detection cannot reliably identify secrets; the attachment chip should show type and byte count only. |
| Focus return after Copy & Close | #3 and #8: return focus unconditionally. #6: request activation; macOS may refuse. | Best effort (#6). Activation is a request, not a guarantee. A refused activation must not invalidate a successful copy. |
| Base64 non-UTF-8 output | #3: hex view and Save to file. #6: reject with an error; binary export deferred. | Defer binary export (#6) for the first release. Add a hex view only if the benchmark shows users hit non-text payloads. |
| Timestamp unit | #3 and #8: infer seconds vs milliseconds from magnitude. #6: default to seconds; do not infer from digit count. | Infer as a visible default, not a hidden rule. Show the selected unit and let the user override it; never silently reinterpret a value. |
| URL scope | #3 and #8: parse full URL components. #6: encode/decode/inspect query only. | Add the full URL inspector after the first release. It reuses the same inspector UI and is a natural extension. |
| UUID extensions | #3: ULID and nanoid on the same row. #8: copy formats and batch count. #6: UUID v4 only. | Ship UUID v4 first (#6). Add copy formats and batch count (#8) before new identifier types; ULID/nanoid are a separate generator row later. |
| Invocation while open | #6: repeated invocation focuses the existing panel. #8: toggles it closed. | Toggle closed (#8), matching Spotlight and Raycast. Record the choice in the acceptance checks. |

## Overlapping documents

| Area | Proposals | Suggested combination |
| --- | --- | --- |
| Research and catalog | #1 (landscape + criteria + tiers), #4 (roadmap rewrite), #5 (research + README) | #1 and #4 both add `docs/tool-catalog.md`; they are competing versions, not stacked. Combine them into one file: keep #1's landscape and selection criteria, and #4's roadmap as the growth plan. Keep #5's `research.md` as a distinct source-linked review. Reconcile the README links from #4 and #5. |
| UX | #2 (interaction spec), #7 (shortcut UX + prototype) | #7 is the more concrete and includes the prototype. Merge #7 first, then fold #2's unique material (direct answers, ranking rules, onboarding) into it. |
| Implementation | #6 (contracts + fixtures), #9 (notes + risks) | #6's contracts and fixtures are the acceptance corpus. Merge #6 first, then keep #9's mechanism notes and risk register as the companion. |

## Merge order

1. Choose one catalog document from #1 and #4, then merge #5 (README + research) and reconcile the README links.
2. Merge #7 (UX + prototype), then fold in #2.
3. Merge #6 (contracts), then fold in #9.
4. Reconcile #3, #4, #6, and #8 into one product plan using the conflict table above.

## Prototype check

The JSON kernel in #7's prototype was run against #6's expected-result fixtures in Node. It passes the lexical-preservation, duplicate-key, scalar-root, and minify cases. Two notes:

- The prototype's error messages are browser `JSON.parse` wording, not the line/column format #6 requires. #7 already says the wording is illustrative; the native kernel must produce the contract's locations.
- Search ranking is order-sensitive: `json format` does not match **Format JSON**. Consider a word-order-insensitive alias match if the benchmark shows users typing commands out of order.

## Open decisions

- Minimum macOS version and distribution route (App Store vs direct + Sparkle). All proposals defer this to the native spike; it constrains hotkey, pasteboard, and auto-paste entitlements.
- Whether to adopt the "hide and keep draft" app-switch behavior; it needs an acceptance check.
- Whether to include a hex view for non-UTF-8 Base64 output.
- Whether the shortcut toggles closed on a repeated invocation.
