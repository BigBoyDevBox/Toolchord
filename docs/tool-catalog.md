# Tool catalog and competitive research

Research companion to the [product plan](product-plan.md). Surveys what comparable tools ship, which of those fit a shortcut palette, and a suggested order for growing the catalog after the first release.

## Competitive landscape

| Product | Form | Catalog | Input model | What to take from it |
| --- | --- | --- | --- | --- |
| [IT Tools](https://it-tools.tech/) | Web, self-hostable | ~90 tools in 10 categories | Per-tool pages, paste or type | Breadth benchmark. Its catalog shows which utilities developers reach for; most map onto three shapes: transform (input → output), inspector (input → fields), generator (no input → output). |
| [DevUtils](https://devutils.com/) | Native app, $9 | 47+ tools | Clipboard smart detection picks a tool; full-window UI | The reference for content detection (`1611241901` → Unix Time, `aGVsbG8=` → Base64). Ships Alfred, Raycast, and Terminal integrations. Its weakness for a palette: detection routes to a tool window, so there is always an extra step before the result. |
| [Boop](https://boop.okat.best/) | Native app, free, [open source (MIT)](https://github.com/IvanMathy/Boop) | ~60 built-in scripts plus user scripts in JavaScript | Persistent scratchpad; `⌘B` picks a script that transforms the text | The canonical native precedent and a useful codebase to study. Proves a small pure-function core scales across dozens of tools. No global hotkey, no preview, results replace the buffer rather than copy out — a different loop than a palette. |
| [DevHub](https://wangchujiang.com/DevHub/) | Native menu bar, free + IAP | 100+ tools | Menu bar grid, URL scheme for automation | Shows demand for breadth and for `x-callback` style hooks into launchers and scripts. |
| [Devly](https://devly.techfixpro.net/) | Menu bar popover, $4.99 | 60+ tools | Popover with quick switcher; optional CLI | Recent App Store entrant that hit #1 paid in Developer Tools — evidence of demand. Pure SwiftUI and sandboxed, which is a useful feasibility data point. |
| [Anvil](https://anvilmac.com/en/events/command-center/) | Menu bar | Clipboard actions | Detection plus action list | Already cited in the plan; closest in spirit to ranked actions on a payload. |
| [CyberChef](https://gchq.github.io/CyberChef/) | Web | ~300 operations | Chained "recipes" | Depth reference. Recipe chaining is a possible far-future model, not a first-release fit. |
| [Raycast](https://www.raycast.com/) / Alfred | Launcher + extensions | Store extensions per tool | Search-first, results go to clipboard | The actual competition for the hotkey slot. Raycast covers Base64, timestamps, and JWTs via free extensions, but each tool is a separate command with form fields, and there is no single "paste anything, get the right result" surface. Toolchord's edge has to be detection, instant preview, and copy-first output. |
| macOS built-ins | Spotlight, Shortcuts, `pbpaste`/`uuidgen` | A handful | Varies | Spotlight converts units and evaluates arithmetic already. Worth not duplicating poorly. |

Two gaps in the current plan's landscape paragraph: Boop is the most-studied native precedent and its source answers many implementation questions, and Raycast is the incumbent for the shortcut itself rather than for any single tool.

## What fits a palette

A tool belongs in the palette when it meets all of these:

- **One step.** Input and options map to a single result (string, short list of fields, or generated value) with no multi-field setup.
- **Pure function.** Deterministic output from input and options, so the same core evaluation drives preview and tool views identically.
- **Offline.** No network dependency; lookups that need WHOIS, DNS, or vendor databases conflict with the offline promise.
- **Keyboard-viable.** Every option reachable without a pointer, at palette size.
- **Frequent.** Reached for weekly in ordinary dev work. Niche tools dilute search ranking more than they help.

Tools that fail these tests (text diff, regex tester, SQL formatter, subnet calculators) are not excluded — they need a roomier editor or a reference layout, so they belong later, once the compact loop is proven.

## Suggested catalog order

Tier 0 is the planned first release. Tiers after that are suggestions to revisit against the benchmark results, not commitments.

### Tier 0 — first release (as planned)

JSON · Base64 · URL · JWT · Timestamp · UUID

Covers all three shapes (transform, inspector, generator) and the top of every catalog surveyed. Right call.

### Tier 1 — same interactions, small implementations

These reuse the exact input/result/copy machinery from the first release and are mostly `Foundation`/`CryptoKit` work. Strong candidates for the first catalog expansion:

| Tool | Why |
| --- | --- |
| **Number base converter** (bin/oct/dec/hex) | In every catalog surveyed; single-field UX; trivially native. |
| **Hash text** (SHA-256/512, SHA-1, MD5) | Already named for post-release; `CryptoKit` makes it nearly free. Plan it early. |
| **ULID and nanoid generators** | Same UI as UUID. DevUtils and Devly both ship them; UUID's options row is a natural home. |
| **HTML entity encode/decode** | High-frequency web task; single transform. |
| **Case convert + slugify** | Already named for post-release; pure string transforms. |
| **Hex ↔ text/bytes view** | Complements Base64's "decoded bytes are not UTF-8" path — show hex instead of an error. |
| **Line tools** (sort, dedupe, join, trim) | Cheap, composable, and exercises multi-line output copy. |
| **Backslash escape/unescape** | JSON string escaping; common when embedding payloads. |
| **QR code generator** | `CIQRCodeGenerator` is built into Core Image — no dependency, real utility. |
| **Full URL parser** | Extends the planned query-param table with scheme/host/port/path rows; same inspector UI. |

### Tier 2 — same core, more UI or a dependency

| Tool | Notes |
| --- | --- |
| **JSON ↔ YAML ↔ TOML** | Named in the plan; pulls in a parser dependency (Yams). |
| **JSON ↔ CSV, query string ↔ JSON** | Structural transforms; medium complexity. |
| **Cron explainer** | Parses `*/15 9-17 * * 1-5` into a field grid; compact inspector UI. In IT Tools and DevUtils. |
| **Color converter** (HEX/RGB/HSL + contrast) | Compact UI; contrast ratio is a nice inspector addition. |
| **JSONPath query** | Devly ships this and it differentiates: paste JSON, get matching nodes. Consider a `jq`-lite subset. |
| **Text diff, regex tester** | Named in the plan; want the roomier editor first. |
| **Markdown preview, SQL/XML formatter** | Formatters are easy; previews want rendering surface. |
| **cURL → request/code** | Parses a pasted curl command into method/headers/body fields, optionally to fetch/`URLSession` code. |
| **UUID/ULID inspector** | Decode timestamp and variant from v1/v6/v7 identifiers — natural pair for the generator. |
| **Certificate decoder (X.509), HMAC** | DevUtils ships both; moderate value, moderate work. |
| **Lorem ipsum, token/password generator** | Generators are cheap once the no-input path exists. |

### Tier 3 — poor palette fit or against scope

Reference material rather than transforms (HTTP status codes, git/cron cheatsheets, MIME tables), anything needing network (IP/MAC vendor lookup, WHOIS), slow or sensitive crypto (bcrypt, RSA keygen, BIP39), media tools beyond QR (camera recorder, SVG placeholder), and locale-heavy validators (IBAN, phone numbers). Revisit only if users ask.

## Signature candidates

Cheap additions that differentiate the palette rather than match catalogs:

- **Live "now" values.** The Timestamp row can render the current time and epoch live while the panel is open — copyable without typing anything.
- **JWT expiry countdown.** "expires in 14m" / "expired 3d ago" reads faster than a raw `exp` claim.
- **Auto-detection as ranking, not routing.** Every competitor routes to a tool on detection; keeping the user on the ranked list with a preview is the differentiator — worth protecting in the UX.
- **Copy the field you came for.** Query-param values, JWT claims, and URL components copied individually without leaving the panel covers the most common multi-value flows.

## Sources

- IT Tools tool list: [src/tools/index.ts](https://github.com/CorentinTh/it-tools/blob/main/src/tools/index.ts)
- DevUtils catalog and smart detection: [devutils.com](https://devutils.com/)
- Boop scripts and architecture: [github.com/IvanMathy/Boop](https://github.com/IvanMathy/Boop)
- DevHub: [wangchujiang.com/DevHub](https://wangchujiang.com/DevHub/)
- Devly: [devly.techfixpro.net](https://devly.techfixpro.net/) and [App Store listing](https://apps.apple.com/us/app/devly/id6759269801)
