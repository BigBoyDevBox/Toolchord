import Foundation

/// XML formatting and well-formedness checks without external entity resolution.
public enum XMLTools {
    public static let commands: [ToolCommand] = [
        ToolCommand(
            id: "xml.format", title: "Format XML", summary: "Indent markup, keep text intact",
            group: .xml, icon: .glyph("</>"),
            aliases: ["pretty print xml", "beautify xml", "indent xml", "prettify xml", "xml pretty"],
            options: [.choice("indent", "Indent", [.init("2", "2 spaces"), .init("4", "4 spaces"), .init("tab", "Tab")], default: "2")],
            copyNoun: "XML", affinity: { $0.has(.xml) ? ($0.has(.html) ? 45 : 100) : 0 },
            evaluate: { evaluate($0, format: true) }
        ),
        ToolCommand(
            id: "xml.validate", title: "Validate XML", summary: "Check well-formedness, keep the input",
            group: .xml, icon: .symbol("checkmark.seal"),
            aliases: ["check xml", "well formed", "well-formed", "xml syntax", "lint xml", "xml validator"],
            copyNoun: "input", affinity: { $0.has(.xml) ? ($0.has(.html) ? 40 : 75) : 0 },
            evaluate: { evaluate($0, format: false) }
        ),
    ]

    static func evaluate(_ request: ToolRequest, format: Bool) -> ToolResult {
        guard let text = request.input.text else { return .needsInput("Paste XML to continue.") }
        do {
            var parser = try XMLSourceParser(text, request: request)
            try parser.parse()
            let output: String
            if format {
                let choice = request.options.choice("indent", default: "2")
                output = try parser.formatted(indent: choice == "tab" ? "\t" : choice == "4" ? "    " : "  ")
            } else {
                guard parser.bytes.count <= request.limits.maxOutputBytes else {
                    return .tooLarge(request.limits.outputLimitMessage)
                }
                output = text
            }
            return .success(ToolOutput(primaryText: output, status: "Well-formed XML", syntax: .xml))
        } catch let failure as XMLSourceFailure {
            return failure.result
        } catch {
            return .invalid(ToolDiagnostic("Unable to parse XML.", at: TextLocator.location(ofUTF8Offset: 0, in: text)))
        }
    }
}
