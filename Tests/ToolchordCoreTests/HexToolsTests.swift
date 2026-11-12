import Foundation
import Testing
@testable import ToolchordCore

@Suite struct HexToolsTests {
    func run(_ id: String, _ text: String, options: [String: String] = [:]) throws -> ToolResult {
        let command = try #require(HexTools.commands.first { $0.id == id })
        return command.run(ToolRequest(input: .text(text), options: ToolOptions(options)))
    }

    @Test func fixtures() throws {
        #expect(try run("hex.encode", "Hi ✓").output?.primaryText == "486920e29c93")
        #expect(try run("hex.encode", "Hi ✓", options: ["separator": "space"]).output?.primaryText == "48 69 20 e2 9c 93")
        for (input, expected) in [("48 69 20 E2 9C 93", "Hi ✓"), ("0x4869", "Hi"), ("48:69", "Hi"),
                                  ("\u{00A0} 0X48\t69\r\n\u{00A0}", "Hi"), ("", ""), (" \t\r\n", ""), ("0x", "")] {
            #expect(try run("hex.decode", input).output?.primaryText == expected)
        }
        #expect(try run("hex.encode", "Hi ✓").output?.status == "6 bytes")
        #expect(try run("hex.decode", "48:69").output?.status == "Decoded · 2 bytes")
        #expect(try run("hex.encode", "a").output?.status == "1 byte")
        #expect(try run("hex.encode", "").output?.primaryText == "")
    }

    @Test func diagnostics() throws {
        #expect(try run("hex.decode", "486") == .invalid(ToolDiagnostic("Hex text has an odd number of digits.", at: .init(line: 1, column: 4))))
        #expect(try run("hex.decode", "4g") == .invalid(ToolDiagnostic("Invalid hex digit “g”.", at: .init(line: 1, column: 2))))
        #expect(try run("hex.decode", "ff") == .invalid(ToolDiagnostic("Decoded bytes are not UTF-8 text.")))
        #expect(try run("hex.decode", "\r\n 0X48:\r\n😀") == .invalid(ToolDiagnostic("Invalid hex digit “😀”.", at: .init(line: 3, column: 1))))
        #expect(try run("hex.decode", "0x0x48") == .invalid(ToolDiagnostic("Invalid hex digit “x”.", at: .init(line: 1, column: 4))))
        #expect(try run("hex.decode", "c080") == .invalid(ToolDiagnostic("Decoded bytes are not UTF-8 text.")))
    }

    @Test func roundTripsAndLimits() throws {
        let original = String(repeating: "Grüezi ✓😀 日本語\0\n", count: 1000)
        for separator in ["none", "space"] {
            let encoded = try #require(run("hex.encode", original, options: ["separator": separator]).output?.primaryText)
            #expect(try run("hex.decode", encoded).output?.primaryText == original)
        }
        for command in HexTools.commands {
            if case .needsInput = command.run(ToolRequest(input: .none)) {} else { Issue.record("Expected needsInput") }
            #expect(command.run(ToolRequest(input: .text(""), cancellation: .init { true })) == .cancelled)
            let input = command.id == "hex.encode" ? "ab" : "6162"
            let limits = ToolLimits(maxOutputBytes: 1)
            #expect(command.run(ToolRequest(input: .text(input), limits: limits)) == .tooLarge(limits.outputLimitMessage))
            let expected = command.id == "hex.encode" ? "6162" : "ab"
            #expect(command.run(ToolRequest(input: .text(input), limits: .init(maxOutputBytes: expected.count))).output?.primaryText == expected)
        }
        let command = try #require(HexTools.commands.first { $0.id == "hex.encode" })
        #expect(command.run(ToolRequest(input: .text("ab"), options: .init(["separator": "space"]), limits: .init(maxOutputBytes: 4))) == .tooLarge(ToolLimits(maxOutputBytes: 4).outputLimitMessage))
    }
}
