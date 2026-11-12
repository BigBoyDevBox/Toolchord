// Developer tool for design review and performance checks.
//
//   toolchord-snapshots [output-directory] [scenario-name ...]
//       Renders palette states to PNG files (default: build/snapshots).
//   toolchord-snapshots --benchmark
//       Times every command on 10 KiB and 1 MiB inputs (use a release build).
import AppKit
import ToolchordCore
import ToolchordMac

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.first == "--benchmark" {
    runBenchmark()
    exit(0)
}

let directory = URL(fileURLWithPath: arguments.first ?? "build/snapshots", isDirectory: true)
let names = Set(arguments.dropFirst())

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)

Task { @MainActor in
    do {
        let urls = try await SnapshotRenderer.renderAll(to: directory, only: names)
        for url in urls { print(url.path) }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Snapshot failed: \(error)\n".utf8))
        exit(1)
    }
}
application.run()

// MARK: - Benchmark

/// A JSON array of records about `bytes` long: valid JSON, multi-line, with
/// numbers, strings, URLs, and non-ASCII text, so every command does real work.
func makeDocument(bytes: Int) -> String {
    let record = #"  {"id": 12345, "name": "Example ünïcödé", "tags": ["a", "b"], "url": "https://example.test/?q=1&r=2", "ok": true}"#
    var lines: [String] = []
    var size = 2
    while size < bytes {
        lines.append(record)
        size += record.utf8.count + 2
    }
    return "[\n" + lines.joined(separator: ",\n") + "\n]"
}

/// A Markdown document about `bytes` long: headings, lists, emphasis, links,
/// code, a table, and a block quote.
func makeMarkdown(bytes: Int) -> String {
    let section = """
    ## Section heading

    Some *emphasis*, **strong text**, `inline code`, and a [link](https://example.test/?q=1&r=2) with ünïcödé.
    A soft-wrapped second line.

    - First item
    - Second item with **bold**
      - Nested item
    1. One
    2. Two

    > A quoted paragraph.

    | Name | Value |
    |:-----|------:|
    | a    | 1     |

    ```swift
    let x = 1 < 2
    ```


    """
    return String(repeating: section, count: max(1, bytes / section.utf8.count))
}

/// An HTML document about `bytes` long with the same structure.
func makeHTML(bytes: Int) -> String {
    let section = """
    <h2>Section heading</h2>
    <p>Some <em>emphasis</em>, <strong>strong text</strong>, <code>inline code</code>, and a <a href="https://example.test/?q=1&amp;r=2">link</a> with &uuml;n&iuml;c&ouml;d&eacute;.<br>
    A second line.</p>
    <ul><li>First item</li><li>Second item<ul><li>Nested item</li></ul></li></ul>
    <ol><li>One</li><li>Two</li></ol>
    <blockquote><p>A quoted paragraph.</p></blockquote>
    <table><tr><th>Name</th><th>Value</th></tr><tr><td>a</td><td>1</td></tr></table>
    <pre>let x = 1 &lt; 2</pre>
    <script>var ignored = "<p>";</script>

    """
    return "<!DOCTYPE html><html><body>\n" + String(repeating: section, count: max(1, bytes / section.utf8.count)) + "</body></html>"
}

func median(_ values: [Duration]) -> Duration {
    values.sorted()[values.count / 2]
}

func milliseconds(_ duration: Duration) -> String {
    let ms = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    return String(format: "%8.2f", ms)
}

func runBenchmark() {
    let small = makeDocument(bytes: 10 * 1024)
    let large = makeDocument(bytes: 1_000_000)
    // Markup converters get documents in their own format.
    let documents: [String: (small: String, large: String)] = [
        ToolGroup.markdown.id: (makeMarkdown(bytes: 10 * 1024), makeMarkdown(bytes: 1_000_000)),
        "html.plaintext": (makeHTML(bytes: 10 * 1024), makeHTML(bytes: 1_000_000)),
    ]
    let clock = ContinuousClock()
    print("Median of 5 runs, milliseconds. 10 KiB = \(small.utf8.count) bytes, 1 MiB = \(large.utf8.count) bytes (JSON; Markdown and HTML for their converters).")
    print("command                      10 KiB     1 MiB   result (1 MiB)")
    var worstSmall: (String, Duration) = ("", .zero)
    for command in ToolCatalog.commands {
        let seed = command.makeSeed?(SeedContext())
        func time(_ text: String) -> (Duration, ToolResult) {
            var durations: [Duration] = []
            var last = ToolResult.cancelled
            for _ in 0..<5 {
                durations.append(clock.measure { last = command.run(ToolRequest(input: .text(text), seed: seed)) })
            }
            return (median(durations), last)
        }
        let inputs = documents[command.id] ?? documents[command.group.id] ?? (small, large)
        let (smallTime, _) = time(inputs.small)
        let (largeTime, largeResult) = time(inputs.large)
        if smallTime > worstSmall.1 { worstSmall = (command.id, smallTime) }
        let outcome: String
        switch largeResult {
        case .success: outcome = "success"
        case .invalid: outcome = "invalid"
        case .tooLarge: outcome = "too large"
        case .unsupported: outcome = "unsupported"
        case .needsInput: outcome = "needs input"
        }
        print("\(command.id.padding(toLength: 24, withPad: " ", startingAt: 0)) \(milliseconds(smallTime))  \(milliseconds(largeTime))   \(outcome)")
    }
    print("Slowest at 10 KiB: \(worstSmall.0) (\(milliseconds(worstSmall.1)) ms)")
}
