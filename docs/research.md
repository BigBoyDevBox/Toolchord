# Developer utility research and tool priorities

Research checked **12 November 2026** using publisher websites, documentation, and source catalogs.

## Positioning

Native execution, offline processing, clipboard detection, and command search already exist in competing products. Toolchord’s hypothesis is that a preview beside the command list and a single **Copy & Close** action will shorten the path from invoking the palette to resuming work. [Product plan](product-plan.md)

| Product | What the primary source establishes | Implication for Toolchord |
| --- | --- | --- |
| [IT Tools](https://it-tools.tech/) · [source catalog](https://github.com/CorentinTh/it-tools/blob/main/src/tools/index.ts) | A broad web toolbox spanning formats, encodings, text, dates, crypto, and network helpers. | Use the catalog to find jobs that fit a brief interruption. |
| [DevUtils](https://devutils.com/) | Advertises a native offline Mac toolbox, clipboard detection, formatters, generators, inspectors, and launcher integrations. | Compare the full workflow, including reaching and copying an inspector field. |
| [Devly](https://devly.techfixpro.net/) | Advertises a native menu-bar toolbox, a global hotkey, Quick Switch, and per-action shortcuts. | Compare the steps from global hotkey to the result on the clipboard. |
| [Anvil Command Center](https://anvilmac.com/en/events/command-center/) | Describes searchable tools, clipboard actions, and generators in one palette. | Compare how quickly users find the desired result and its copy action. |
| [Boop](https://boop.okat.best/) | A Mac text scratchpad with transformations and custom scripts. | Preserve a comfortable multiline editor for tasks that need more room. |
| [DevToys](https://devtoys.app/) | Lists offline utilities including an XML formatter and XML/XSD tester, plus configurable clipboard detection. | Formatting and checking XML are established toolbox tasks. A pasted XML document fits the same input and result views as JSON. |
| [CyberChef](https://gchq.github.io/CyberChef/) | Combines operations into recipes with separate input and output. | Revisit chaining if users routinely run the same sequence of tools. |
| [Raycast search](https://manual.raycast.com/search-bar) · [actions](https://manual.raycast.com/action-panel) · [Alfred hotkeys](https://www.alfredapp.com/help/workflows/triggers/hotkey/) | Raycast exposes search and contextual actions. Alfred hotkeys can pass an argument to a workflow. | Show key hints and keep command search separate from pasted input. |

On 12 November 2026, Raycast listings reported about 44,000 Base64 installs, 33,000 Unix Timestamp installs, and 19,000 JWT Decoder installs. These cumulative figures suggest interest among Raycast users. Observe actual tasks to choose what to build next. [Base64](https://www.raycast.com/DanielSinclair/base64) · [Unix Timestamp](https://www.raycast.com/destiner/unix-timestamp) · [JWT Decoder](https://www.raycast.com/gdsmith/jwt-decoder)

## Tool selection

Favor jobs that work offline with pasted text, a recognizable result, and few options. Give each command its own searchable name while grouping related commands into one tool.

| Release | Tool / commands | Job and reason | Constraint |
| --- | --- | --- | --- |
| First | JSON format, minify, validate | Inspect an API response while preserving its data. | Preserve numbers, key order, and duplicate keys. Show precise parse errors. |
| First | Format XML, Validate XML | Read markup or locate a syntax error. | Check XML 1.0 well-formedness and preserve mixed content and whitespace under `xml:space="preserve"`. |
| First | Base64 and Base64URL encode and decode | Inspect encoded text from APIs and logs. | Make the alphabet and padding policy explicit. Report non-text bytes. |
| First | URL component encode and decode, query inspection | Read an escaped value or copy one repeated parameter. | Distinguish component encoding, raw query decoding, and form decoding. |
| First | JWT header, claims, and expiry inspection | Read a claim or check when a token expires. | Label the signature as unverified. |
| First | Unix seconds or milliseconds ↔ ISO 8601 | Compare log and API timestamps. | Show units, time zones, and offsets. |
| First | UUID v4 generation | Get an ID with a single command. | Keep the displayed value stable until explicit regeneration. |
| Candidates for the same panel | SHA-256, hex and text conversion, number-base conversion, case and slug conversion, line sorting and deduplication, HTML entities, string escaping, full URL inspection | Short transforms and inspectors that can reuse the existing copy behavior. | Choose from tasks observed during use. |
| Candidates that need a larger editor or separate evaluation | JSON ↔ YAML, JSON ↔ CSV, text or JSON diff, regex, JSONPath, SQL formatting, XML schema validation, XSLT, XML conversion | Tasks with more input, options, or result context. | Define data preservation, execution limits, and the role of bundled parsers before adding a command. |
| Specialist candidates | HMAC, cron explanation, color conversion, QR generation, certificate inspection, UUID v7 and ULID | Tasks with extra input, a new result type, or a narrower audience. | Use observed workflows to decide which warrant dedicated controls. |

Validate XML reports a location for malformed documents. Format XML indents structural markup and leaves whitespace-sensitive content intact. Both actions reject `DOCTYPE` declarations with a distinct unsupported-input message and run locally with external entity resolution disabled. [XML well-formedness](https://www.w3.org/TR/xml/#sec-well-formed) · [XML whitespace handling](https://www.w3.org/TR/xml/#sec-white-space) · [Apple external entity policy](https://developer.apple.com/documentation/foundation/xmlparser/externalentityresolvingpolicy-swift.enum/never)

## Validation before catalog expansion

Run a formative comparison with developers who use web utilities, native toolboxes, or launcher extensions. Use the same non-sensitive fixtures across products and include representative tasks from the participants’ work.

1. **JSON.** Format a minified response and return to the source editor with the result on the clipboard.
2. **XML.** Format a compact document, preserve whitespace-sensitive text, then locate a mismatched tag using Validate XML.
3. **Base64.** Decode non-ASCII text, then confirm that malformed input prevents copying the previous result.
4. **JWT.** Find the expiry and copy one claim. Ask the participant what the signature status means.
5. **UUID.** Generate and copy a UUID from an empty panel.
6. **Discovery.** Find `epoch`, `pretty print`, and `GUID` using search.

Compare Toolchord with each participant’s usual workflow and with DevUtils or Devly for tasks those apps support. Vary the test order and record first-use discovery separately from repeated use. For transformations, start with the input on the clipboard. Measure from invocation until the correct output is on the clipboard and focus has returned. For field-copy tasks, stop when the correct field reaches the clipboard. Record keystrokes, errors, wrong copy targets, and focus failures along with the app and macOS versions, fixtures, and sample size.

Use task completion, repeated-use preference, and failure reports to decide which interactions need refinement. Choose catalog additions after observing where users still reach for another tool.
