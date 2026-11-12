import Foundation
import Testing
@testable import ToolchordCore

/// Invariants every command must satisfy, and a robustness sweep that runs
/// every command against awkward inputs.
@Suite struct CatalogTests {
    private let catalog = ToolCatalog.commands

    @Test func identifiersAreUniqueAndNamespaced() {
        let ids = catalog.map(\.id)
        #expect(Set(ids).count == ids.count)
        for command in catalog {
            #expect(command.id.contains("."), "\(command.id) needs a group prefix")
            #expect(ToolCatalog.command(id: command.id)?.title == command.title)
        }
    }

    @Test func metadataIsComplete() {
        for command in catalog {
            #expect(!command.title.isEmpty)
            #expect(!command.summary.isEmpty, "\(command.id) summary")
            #expect(command.summary.count <= 48, "\(command.id) summary is too long for the preview header")
            #expect(!command.aliases.isEmpty, "\(command.id) aliases")
            #expect(!command.copyAndCloseTitle(options: ToolOptions()).contains("  "))
            for option in command.options {
                #expect(option.accepts(option.defaultValue), "\(command.id).\(option.id) default")
                if case .choice(let choices, _) = option.kind {
                    #expect(Set(choices.map(\.id)).count == choices.count)
                }
            }
        }
    }

    @Test func generatorsDeclareSeedsAndRegeneration() {
        for command in catalog where command.isGenerator {
            #expect(command.makeSeed != nil, "\(command.id) makeSeed")
            #expect(command.regenerateTitle != nil, "\(command.id) regenerateTitle")
            let seed = command.makeSeed!(SeedContext())
            let result = command.run(ToolRequest(input: .none, seed: seed))
            #expect(result.isSuccess, "\(command.id) should succeed with its own seed: \(result)")
        }
    }

    @Test func textCommandsAskForInputWhenNothingIsAttached() {
        for command in catalog where !command.isGenerator {
            if case .needsInput = command.run(ToolRequest(input: .none)) {} else {
                Issue.record("\(command.id) should need input")
            }
        }
    }

    @Test func affinityStaysInRange() {
        let samples = [#"{"a":1}"#, "<a/>", "Hello, World", "1700000000", "#ff8800", "a\nb", "", "eyJhbGciOiJub25lIn0.eyJleHAiOjB9."]
        for command in catalog {
            for sample in samples {
                let affinity = command.affinity(InputDetector.profile(for: sample))
                #expect((0...100).contains(affinity), "\(command.id) affinity \(affinity) for \(sample)")
            }
        }
    }

    static let awkwardInputs: [String] = [
        "",
        " ",
        "\n",
        "\r\n\r\n",
        "\u{0}",
        "\u{FEFF}",
        "😀👍🏽🇨🇭",
        "e\u{301}",
        String(repeating: "a", count: 10_000),
        String(repeating: "[", count: 500),
        String(repeating: "<a>", count: 500),
        String(repeating: "&", count: 2_000),
        String(repeating: "%", count: 2_000),
        String(repeating: "\\", count: 2_001),
        "{\"a\":",
        "<a b='1' c=\"2\">",
        "-",
        "-0",
        "0x",
        "#",
        "rgb(",
        ".",
        "..",
        "a.b.c",
        "=&=&",
        "?#",
        "\u{2028}\u{2029}",
        "\t\t",
        "1e309",
        "-9999999999999999999999999",
        "rgb(nan, nan, nan)",
        "rgb(inf, -inf, 1e999)",
        "hsl(nan, 100%, 50%)",
        "hsl(inf, nan%, 50%)",
        "rgba(0, 0, 0, nan)",
        "#ff8800nan",
    ]

    @Test(arguments: awkwardInputs)
    func everyCommandHandlesAwkwardInput(_ input: String) {
        for command in catalog {
            let seed = command.makeSeed?(SeedContext())
            let result = command.run(ToolRequest(input: .text(input), seed: seed, timeZone: TimeZone(identifier: "UTC")!))
            if let output = result.output {
                #expect(output.primaryText.utf8.count <= ToolLimits.standard.maxOutputBytes)
                #expect(Set(output.fields.map(\.id)).count == output.fields.count, "\(command.id) field ids")
            }
            if case .invalid(let diagnostic) = result {
                #expect(!diagnostic.message.isEmpty)
                if let location = diagnostic.location {
                    #expect(location.line >= 1 && location.column >= 1, "\(command.id) location")
                }
            }
        }
    }

    @Test func everyCommandFinishesOnLargeInput() {
        let line = #"{"id": 12345, "name": "Example ünïcödé", "tags": ["a", "b"], "url": "https://example.test/?q=1"}"#
        let large = Array(repeating: line, count: 4_000).joined(separator: "\n")
        #expect(large.utf8.count < ToolLimits.standard.maxInputBytes)
        let clock = ContinuousClock()
        for command in catalog {
            let seed = command.makeSeed?(SeedContext())
            let elapsed = clock.measure {
                _ = command.run(ToolRequest(input: .text(large), seed: seed))
            }
            // Debug builds are much slower than release; this guards against
            // quadratic behavior, not absolute speed.
            #expect(elapsed < .seconds(10), "\(command.id) took \(elapsed)")
        }
    }

    @Test func oversizedInputIsRejectedWithoutWork() {
        let tooBig = String(repeating: "a", count: ToolLimits.standard.maxInputBytes + 1)
        for command in catalog where !command.isGenerator {
            #expect(command.run(ToolRequest(input: .text(tooBig))) == .tooLarge(ToolLimits.standard.inputLimitMessage), "\(command.id)")
        }
    }
}
