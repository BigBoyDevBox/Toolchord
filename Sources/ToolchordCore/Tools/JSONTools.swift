import Foundation

public enum JSONTools {
    public static let commands: [ToolCommand] = [
        ToolCommand(
            id: "json.format", title: "Format JSON", summary: "Indent without changing values",
            group: .json, icon: .glyph("{ }"),
            aliases: ["pretty print", "prettify", "beautify", "indent json", "pretty json", "json pretty"],
            options: [.choice("indent", "Indent", [.init("2", "2 spaces"), .init("4", "4 spaces"), .init("tab", "Tab")], default: "2")],
            copyNoun: "JSON", affinity: { $0.has(.json) ? 100 : 0 },
            evaluate: { request in
                let indent = request.options.choice("indent", default: "2")
                return process(request, style: .indented(indent == "tab" ? "\t" : indent == "4" ? "    " : "  "))
            }
        ),
        ToolCommand(
            id: "json.minify", title: "Minify JSON", summary: "Remove insignificant whitespace",
            group: .json, icon: .glyph("{…}"),
            aliases: ["compact json", "compress json", "uglify json", "single line json"],
            copyNoun: "JSON", affinity: { $0.has(.json) ? 85 : 0 },
            evaluate: { process($0, style: .minified) }
        ),
        ToolCommand(
            id: "json.validate", title: "Validate JSON", summary: "Check syntax and keep the input",
            group: .json, icon: .symbol("checkmark.seal"),
            aliases: ["check json", "lint json", "json syntax", "json validator"],
            copyNoun: "input", affinity: { $0.has(.json) ? 70 : 0 },
            evaluate: { process($0, style: .original) }
        ),
        ToolCommand(
            id: "json.escapeString", title: "Escape JSON String", summary: "Quote text as a JSON string literal",
            group: .json, icon: .glyph("\\\""),
            aliases: ["escape string", "json escape", "stringify", "backslash escape", "escape quotes"],
            options: [.toggle("quotes", "Include quotes", default: true)], copyNoun: "string", affinity: { $0.isPlainText ? 32 : 0 },
            evaluate: { request in
                stringResult(request, escaping: true)
            }
        ),
        ToolCommand(
            id: "json.unescapeString", title: "Unescape JSON String", summary: "Decode backslash escapes",
            group: .json, icon: .glyph("\\\""),
            aliases: ["unescape string", "json unescape", "unstringify", "backslash unescape", "decode escapes"],
            copyNoun: "text", affinity: { $0.has(.jsonStringLiteral) ? 90 : $0.has(.escapedText) ? 75 : 0 },
            evaluate: { stringResult($0, escaping: false) }
        ),
    ]

    static func process(_ request: ToolRequest, style: JSONText.Style) -> ToolResult {
        switch JSONText.process(request.input.text ?? "", style: style, limits: request.limits, cancellation: request.cancellation) {
        case .success(let value):
            return .success(ToolOutput(primaryText: value.text, status: "Valid JSON", syntax: .json, warnings: value.warnings))
        case .failure(let failure): return result(failure)
        }
    }

    static func result(_ failure: JSONText.Failure) -> ToolResult {
        switch failure {
        case .invalid(let diagnostic): .invalid(diagnostic)
        case .tooLarge(let message): .tooLarge(message)
        case .cancelled: .cancelled
        }
    }

    static func stringResult(_ request: ToolRequest, escaping: Bool) -> ToolResult {
        do {
            let quoted = request.options.flag("quotes", default: true)
            let text = request.input.text ?? ""
            let output = try escaping
                ? JSONStringCodec.quote(text, includeQuotes: quoted, limits: request.limits, cancellation: request.cancellation)
                : JSONStringCodec.unescape(text, limits: request.limits, cancellation: request.cancellation)
            return .success(ToolOutput(primaryText: output, status: escaping ? "Escaped" : "Unescaped", syntax: escaping && quoted ? .json : .plain))
        } catch let failure as JSONText.Failure {
            return result(failure)
        } catch {
            return .invalid(ToolDiagnostic("Unable to process the string."))
        }
    }
}
