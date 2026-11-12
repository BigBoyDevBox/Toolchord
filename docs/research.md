# Developer utility research and tool priorities

Research checked **12 November 2026**. This is a review of first-party websites, documentation, and source catalogs, not hands-on testing. Product claims below are attributed to their publishers. Priorities and UX recommendations are Toolchord hypotheses; install counts do not establish usage frequency or willingness to switch.

## Positioning

The [current plan](product-plan.md) has a sensible six-tool scope. Keep it. Native execution, offline processing, smart detection, and command search already exist in competing products. Test whether Toolchord makes a short task easier to finish: **invoke → paste → inspect → copy → return**. A smaller, consistent palette could be useful even without the largest catalog.

| Product | What the primary source establishes | Implication for Toolchord |
| --- | --- | --- |
| [IT Tools](https://it-tools.tech/) · [source catalog](https://github.com/CorentinTh/it-tools/blob/main/src/tools/index.ts) | A broad web toolbox spanning formats, encodings, text, dates, crypto, and network helpers. | Use the catalog to discover jobs, then prioritize those that fit a brief interruption. Do not reproduce the category grid in the launch panel. |
| [DevUtils](https://devutils.com/) | Advertises a native offline Mac toolbox, clipboard detection, formatters, generators, inspectors, and launcher integrations. | Offline/native is baseline positioning. Compare the complete workflow, including reaching and copying an inspector field. |
| [Devly](https://devly.techfixpro.net/) | Advertises a native menu-bar toolbox, a global hotkey, Quick Switch, and per-action shortcuts. Its site distinguishes local tools from explicitly networked HTTP/image operations. | This is a close substitute. Benchmark it before claiming a faster shortcut flow. Keep networking out of the initial scope. |
| [Anvil Command Center](https://anvilmac.com/en/events/command-center/) | Describes searchable tools, clipboard actions, generators, and recent workflows in one command palette. | A palette alone is insufficient differentiation. Make result inspection and the completion action especially clear. |
| [Boop](https://boop.okat.best/) | A Mac text scratchpad with transformations and custom scripts. | Preserve a comfortable multiline editor for tasks that exceed a one-shot preview. Custom scripting can wait. |
| [DevToys](https://devtoys.app/) | Describes an offline cross-platform toolbox, configurable clipboard detection, extensions, and a separate CLI. | Detection is an aid, not a reason to execute a transform or overwrite the clipboard automatically. Defer extension infrastructure. |
| [CyberChef](https://gchq.github.io/CyberChef/) | Combines operations into recipes, with separate input and output and step/automatic execution. | Chaining is a valuable later workflow, but its extra state would complicate a six-tool launch. |
| [Raycast search](https://manual.raycast.com/search-bar) · [actions](https://manual.raycast.com/action-panel) · [Alfred hotkeys](https://www.alfredapp.com/help/workflows/triggers/hotkey/) | Raycast exposes search and contextual actions; Alfred separates invocation from query/clipboard arguments. | Borrow discoverable key hints and separate command search from input. Toolchord can also be a useful companion to an existing launcher. |

Raycast's listings currently report approximately 44,000 installs for [Base64](https://www.raycast.com/DanielSinclair/base64), 33,000 for [Unix Timestamp](https://www.raycast.com/destiner/unix-timestamp), and 19,000 for [JWT Decoder](https://www.raycast.com/gdsmith/jwt-decoder). These cumulative, extension-specific figures are directional evidence of interest only. They are neither comparable active-user counts nor a ranking of developers' daily tasks.

## Tool selection

Favor jobs with plain-text input/output, a recognizable result, no network dependency, and few options. Group related commands into one tool implementation, but index their verbs independently in search.

| Release | Tool / commands | Job and reason | Constraint |
| --- | --- | --- | --- |
| First | JSON: format, minify, validate | Inspect an API response without changing its data. | Preserve numbers, key order, and duplicate keys; show precise parse errors. |
| First | Base64 / Base64URL: encode, decode | Inspect encoded text from APIs and logs. | Explicit alphabet and padding policy; report non-text bytes. |
| First | URL: encode component, decode component, inspect query | Read an escaped value or copy one repeated parameter. | Distinguish component encoding, raw query decoding, and form decoding. |
| First | JWT: inspect header, claims, expiry | Answer “what does this claim say?” and “when does this expire?” | Always label decoding as unverified; no signing keys or remote key fetching. |
| First | Unix time: seconds / milliseconds ↔ ISO 8601 | Compare log and API timestamps. | Visible units, UTC/local labels, and explicit timezone offsets. |
| First | UUID v4: generate, regenerate | Get an ID without opening a document. | Stable displayed value; generation has no pasted-input requirement. |
| Next, after workflow validation | SHA-256 text hash; text case/trim/sort/deduplicate; HTML entity encode/decode; number-base conversion | Short text tasks with a clear output; useful additions without a new panel model. | State UTF-8, newline, case, numeric-range, and ordering policies. Hashing is not encryption. |
| Next, if requested in testing | JSON ↔ YAML; JSON string escape/unescape | Adjacent serialization tasks found in existing toolboxes. | Explicitly define lossy conversion and YAML types; do not silently change data. |
| Roomier editor, later | Text/JSON diff, regex tester, JSONPath, SQL/XML formatters | Inspection tasks that need context or multiple inputs. | Validate the larger editor first; bound expensive evaluation. |
| Specialist candidates, later | Cron explanation, CIDR/subnets, color conversion, QR generation, UUID v7/ULID | Common catalog categories, but different audiences and interaction needs. | Choose from observed jobs rather than catalog completeness. |
| Deferred | HTTP client, DNS/WHOIS, password/key generation, JWT signing, arbitrary scripts, clipboard history, transform pipelines | Add network, secret management, persistence, extension, or multi-step semantics. | Separate product decisions; none are required to validate the palette. |

Do not implement everything in the “Next” rows together. After the six-tool release, select at most three additions supported by observed work. Allow people to report missing commands without transmitting the text they were processing.

## Validation before catalog expansion

Recruit 5–8 developers who already use web tools, a native toolbox, or launcher extensions. This is a formative study, not a market-size estimate. Have each bring three representative, non-sensitive tasks and use fixed fixtures for comparisons.

1. **JSON response:** begin with minified JSON on the clipboard; end with correct formatted JSON on it and the source editor active.
2. **Base64:** decode non-ASCII text, then recognize a malformed input without copying a stale result.
3. **JWT:** find expiry and copy one claim; confirm the participant understands that the signature was not verified.
4. **No-input generation:** generate and copy a UUID without attaching clipboard text.
5. **Discovery:** find `epoch`, `pretty print`, and `GUID` without knowing the command names.

Compare against each participant's existing workflow and at least DevUtils or Devly; include a Raycast extension workflow for people who already use Raycast. Counterbalance order and separate first-use discovery from repeated use. Record time to a correct result, keyboard actions, errors, wrong copy targets, and focus failures. Publish versions, OS, hardware, fixtures, sample size, median/range, and anonymized observations with the result. No benchmark has been run yet.

Proposed decision gate: retain the shortcut-first direction if most participants finish the three core transform/inspection jobs correctly without instruction and prefer it for repeated use, with no stale-copy or data-corruption incidents. Treat a speed advantage as unproven until measured; investigate regressions individually rather than hiding them in an average. If users spend longer identifying the copy target than navigating, improve labels before adding tools.

## Decisions still open

- Minimum macOS version, distribution, and hotkey implementation require the native panel spike from the product plan.
- No pricing recommendation follows from this research. Switching interest, licensing preference, and maintenance expectations need direct user evidence.
- Keep the existing repository license. This proposal reuses product ideas and links, not competitor code or assets. Any later code reuse needs its own dependency/license assessment.
