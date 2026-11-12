# Tool catalog roadmap

How the catalog should grow after the first release. The tiers come from three inputs: the public [IT Tools](https://github.com/CorentinTh/it-tools) catalog of about 90 tools, the feature list of [DevUtils](https://devutils.com/) (47+ tools, native and offline), and Raycast Store install counts, which measure demand for shortcut-native versions of these tasks. DevUtils testimonials name hashing, JSON formatting, and diff as the daily drivers; its most differentiated feature is clipboard detection, which the first release already answers with explicit paste plus detection on the attached payload.

## Selection criteria

- **Frequency.** Tasks a working developer does weekly or more. Rarity is the main reason to skip a tool, not implementation cost.
- **Palette fit.** Text in, text or a small structured result out. Nothing that needs a canvas, a file dialog, live network, or long-form reading.
- **Native and offline.** Implementable with system frameworks: Foundation, CryptoKit, Security, CoreImage, NSRegularExpression.

## Fast follow

The next release after the six first-release tools prove the interaction. Every entry reuses the existing input, preview, error, and copy interactions unchanged.

| Tool | Commands and result | Why this tier |
| --- | --- | --- |
| **Hash** | MD5, SHA-1, SHA-256, SHA-512 of pasted text, one copyable row per algorithm, hex or Base64 output | Among the most common clipboard tasks anywhere (cache keys, checksums, git objects); CryptoKit covers all four in a few lines |
| **HMAC** | Keyed digest for a secret and payload, hex or Base64 output | Webhook and API signature checks are frequent and easy to fumble by hand; shares the hash tool's UI |
| **Number base** | Convert between binary, octal, decimal, and hex; parse `0x`-style prefixes; grouped digit output | Bitmasks, colors, offsets, and permissions make hex-decimal conversion a constant need; tiny surface |
| **Case and slug** | lower, UPPER, Title, camelCase, PascalCase, snake_case, kebab-case, slugify with diacritic folding | One of the most frequent micro-edits; pure Foundation string transforms |
| **Hex ⇄ text** | Hex byte string to text and back, with byte offsets | Pairs with Base64 for protocol and debugging work; DevUtils added the same pair to recent releases |
| **Line tools** | Sort lines, deduplicate, numeric or lexicographic order, trim and join | Proven quick task in DevUtils; a few lines of code for high clipboard value |
| **Escape** | Escape and unescape backslash, quote, newline, and tab for JSON, SQL, and regex string literals | The other half of the copy-paste-into-a-literal workflow the Base64 tool serves |
| **Random string** | Crypto-random tokens with length and charset controls and an entropy estimate | Same no-input path as UUID; secrets and fixtures are frequent; SystemRandomNumberGenerator |
| **ULID and UUID v7** | Generate time-ordered IDs, decode one to its timestamp | Natural extension of the UUID tool; adoption is growing on modern backends |
| **HTML entities** | Encode and decode named and numeric entities | Frequent in web work; mirrors the Base64 interactions |
| **URL inspector** | Parse a full URL into scheme, host, port, path, query, and fragment rows, each copyable | Extends the URL tool rather than adding a command; detection already routes URLs here |
| **Color** | Hex, RGB, and HSL with a swatch and copyable forms | Weekly need for UI work; a small structured result |
| **Cron** | Parse an expression into the next five run times, local and UTC, with a plain-language summary | Backend staple that is annoying to compute mentally; small deterministic parser |

## Later

Useful once the compact interaction is validated, but each needs new UI surface, a wider pane, or a bundled parser, so they wait for a roomier tool view.

| Tool | Commands and result | Notes |
| --- | --- | --- |
| **Text diff** | Line diff between two inputs with unified output to copy | Wants a two-pane layout; compare against the expanded tool view first |
| **Regex tester** | Matches and capture groups for a pattern against sample text | NSRegularExpression; add an evaluation timeout so catastrophic patterns cannot stall the preview |
| **JSON ⇄ YAML** | Convert either direction with the first parse error and position | Needs a bundled YAML parser; the JSON kernel already exists |
| **JSON ⇄ CSV** | Flatten arrays of objects to CSV and back | Delimiter and header options; moderate frequency |
| **JSON to query and back** | Convert objects to query strings and parse them back | Generalizes the URL inspector's parameter view |
| **JSON diff** | Structural diff of two documents | Builds on the JSON kernel and the diff UI |
| **XML and TOML** | Format, minify, and convert to and from JSON | Shares the conversion kernel; moderate frequency |
| **SQL formatter** | Format a statement with dialect options | Best-effort quality; larger inputs exercise the preview cap |
| **Markdown to HTML** | Render pasted Markdown to HTML | Needs a bundled renderer for block-level Markdown |
| **Basic auth** | Build an `Authorization: Basic` header from user and password | One-way and tiny, but secret-shaped output needs the concealed clipboard treatment |
| **TOTP** | Generate a code from a pasted secret | CryptoKit HMAC plus epoch math; secret must never persist and copies concealed |
| **Certificate viewer** | Decode PEM X.509 into fields and validity dates with an expiry warning | Security.framework; answers why did this fail without the openssl incantation |
| **QR code** | Render text or a URL as a QR image to copy | CoreImage generator; first image output, so it defines how images copy |
| **String inspector** | Length, lines, words, characters, byte size, entropy | Trivial statistics that pair with password-strength checks |
| **User agent parser** | Structured browser, OS, and device fields from a UA string | Pure parsing; handy in support and debugging |

## Not for the palette

Remaining IT Tools candidates and why they stay out. Revisit only on repeated user requests.

| Candidate | Reason to skip |
| --- | --- |
| IPv4 subnet calculator, range expander, IPv6 ULA, random port | Form-heavy network math, occasional, and easy to get wrong in a compact layout |
| MAC address lookup, safelink decoding | Lookup needs the network; decoding is too rare to justify the slot |
| Device information, camera recorder, chronometer, benchmark builder | Not text transforms; a different app shape |
| Emoji picker, text to Unicode, text to NATO, ASCII art drawer | macOS owns the Character Viewer at `⌃⌘Space`; the rest are novelty conversions |
| Math evaluator, percentage, temperature, roman numerals, ETA | Spotlight and system units already cover these in fewer keystrokes |
| HTTP status codes, MIME types, git memo, regex memo, keycode info | Reference reading, not transforms; better as documentation than as a palette command |
| JSON to code, HTML ⇄ JSX, cURL to code, docker run to compose | Fragile code generation that needs review space and a dependency |
| Bcrypt, RSA key pair, generic encryption, BIP39, PDF signature check | Crypto edge cases, large or sensitive outputs, or heavy key UX; specialized tools already exist |
| Base64 file converter | File in and file out, not a paste-paste action; revisit if a drag target lands in the panel |
| Lorem ipsum, meta tag generator, IBAN, phone, email normalizer | Rare or output better served elsewhere |

## Deepen the first six before widening

Several roadmap items belong inside existing tools as options or extra rows rather than as new commands.

- **Base64:** whitespace-tolerant and lenient decoding of line-wrapped input (PEM-style), strict mode, and a hex view when the result is not valid UTF-8.
- **JWT:** display the algorithm, relative expiry such as *expires in 14m* or *expired 3d ago*, and a warning state when the expiry has passed.
- **Timestamp:** infer seconds or milliseconds from magnitude, accept RFC 2822 and RFC 3339 input, offer a live *now* value, and handle negative epochs.
- **UUID:** uppercase and hyphenless copy formats, a batch count, and the ULID and v7 variants from this roadmap.
- **JSON:** indent width, and a sort-keys option that is off by default to preserve the promise of stable key order.
- **URL:** the full-parse mode that becomes the URL inspector above.

## Sources

- [IT Tools repository and catalog](https://github.com/CorentinTh/it-tools), 90 tools across about ten categories, converters and encoders dominant
- [DevUtils](https://devutils.com/) feature list and testimonials; smart clipboard detection, offline operation, 47+ tools
- Raycast Store listings cited in the product plan: [Base64](https://www.raycast.com/DanielSinclair/base64), [Unix Timestamp](https://www.raycast.com/destiner/unix-timestamp), [JWT Decoder](https://www.raycast.com/gdsmith/jwt-decoder), each with tens of thousands of installs
