import Foundation
import Testing
@testable import ToolchordCore

@Suite struct ColorToolsTests {
    private func run(_ id: String, _ text: String) throws -> ToolOutput {
        let command = try #require(ColorTools.commands.first { $0.id == id })
        let result = command.run(ToolRequest(input: .text(text)))
        return try #require(result.output, "Expected success, got \(result)")
    }

    private func runResult(_ id: String, _ text: String) throws -> ToolResult {
        let command = try #require(ColorTools.commands.first { $0.id == id })
        return command.run(ToolRequest(input: .text(text)))
    }

    // MARK: - Fixtures from BRIEF.md

    @Test func fixture_rgb_from_hex() throws {
        #expect(try run("color.rgb", "#ff8800").primaryText == "rgb(255, 136, 0)")
    }

    @Test func fixture_hsl_from_hex() throws {
        #expect(try run("color.hsl", "#ff8800").primaryText == "hsl(32, 100%, 50%)")
    }

    @Test func fixture_hex_uppercase() throws {
        #expect(try run("color.hex", "#FF8800").primaryText == "#ff8800")
    }

    @Test func fixture_hex_short() throws {
        #expect(try run("color.hex", "#f80").primaryText == "#ff8800")
    }

    @Test func fixture_rgb_with_alpha_hex() throws {
        #expect(try run("color.rgb", "#ff880080").primaryText == "rgba(255, 136, 0, 0.502)")
    }

    @Test func fixture_hex_from_rgb_space_syntax() throws {
        #expect(try run("color.hex", "rgb(255 136 0 / 50%)").primaryText == "#ff880080")
    }

    @Test func fixture_hex_from_rgba() throws {
        #expect(try run("color.hex", "rgba(255, 136, 0, 0.5)").primaryText == "#ff880080")
    }

    @Test func fixture_hex_from_hsl_comma() throws {
        #expect(try run("color.hex", "hsl(0, 100%, 50%)").primaryText == "#ff0000")
    }

    @Test func fixture_hex_from_hsl_space_deg() throws {
        #expect(try run("color.hex", "hsl(120deg 100% 25%)").primaryText == "#008000")
    }

    @Test func fixture_hex_from_rgb_percent() throws {
        #expect(try run("color.hex", "rgb(100%, 0%, 0%)").primaryText == "#ff0000")
    }

    @Test func fixture_rgb_clamping() throws {
        #expect(try run("color.rgb", "rgb(300, -5, 0)").primaryText == "rgb(255, 0, 0)")
    }

    @Test func fixture_hsl_black() throws {
        #expect(try run("color.hsl", "rgb(0, 0, 0)").primaryText == "hsl(0, 0%, 0%)")
    }

    @Test func fixture_hsl_white() throws {
        #expect(try run("color.hsl", "#ffffff").primaryText == "hsl(0, 0%, 100%)")
    }

    @Test func fixture_hex_negative_hue() throws {
        #expect(try run("color.hex", "hsl(-120, 100%, 50%)").primaryText == "#0000ff")
    }

    @Test func fixture_invalid_hex_ggg() throws {
        let result = try runResult("color.hex", "#ggg")
        #expect(result.isSuccess == false)
        if case .invalid = result {} else {
            Issue.record("Expected invalid, got \(result)")
        }
    }

    @Test func fixture_invalid_banana() throws {
        let result = try runResult("color.hex", "banana")
        #expect(result.isSuccess == false)
        if case .invalid = result {} else {
            Issue.record("Expected invalid, got \(result)")
        }
    }

    @Test func fixture_swatch() throws {
        let output = try run("color.rgb", "#ff8800")
        let swatch = try #require(output.swatch)
        #expect(swatch.red == 1.0)
        #expect(abs(swatch.green - 136.0 / 255.0) < 0.0001)
        #expect(swatch.blue == 0.0)
        #expect(swatch.alpha == 1.0)
    }

    // MARK: - Empty input

    @Test func emptyInputIsInvalid() throws {
        let result = try runResult("color.hex", "")
        #expect(result.isSuccess == false)
        if case .invalid = result {} else {
            Issue.record("Expected invalid for empty input, got \(result)")
        }
    }

    @Test func whitespaceOnlyIsInvalid() throws {
        let result = try runResult("color.rgb", "   ")
        #expect(result.isSuccess == false)
    }

    // MARK: - No input

    @Test func noInputIsInvalid() throws {
        let command = try #require(ColorTools.commands.first { $0.id == "color.hex" })
        let result = command.run(ToolRequest(input: .none))
        // ToolCommand.run returns .needsInput when input is .none
        if case .needsInput = result {} else {
            Issue.record("Expected needsInput for no input, got \(result)")
        }
    }

    // MARK: - Hex parsing

    @Test func hex4WithAlpha() throws {
        // #f80f → #ff8800ff (alpha = 0xff/255 = 1.0, so no alpha in output)
        #expect(try run("color.hex", "#f80f").primaryText == "#ff8800")
    }

    @Test func hex4WithPartialAlpha() throws {
        // #f808 → #ff8800 + alpha 0x88/255 ≈ 0.533
        let output = try run("color.hex", "#f808")
        #expect(output.primaryText == "#ff880088")
    }

    @Test func hexCaseInsensitive() throws {
        #expect(try run("color.hex", "#Ff88Aa").primaryText == "#ff88aa")
    }

    @Test func invalidHexLength() throws {
        // #ff88 is actually valid as #rgba (4-digit hex with alpha)
        // Test a truly invalid length like 5 digits
        let result = try runResult("color.hex", "#ff880")
        #expect(result.isSuccess == false)
    }

    // MARK: - RGB parsing

    @Test func rgbDecimal() throws {
        #expect(try run("color.rgb", "rgb(1.0, 2.0, 3.0)").primaryText == "rgb(1, 2, 3)")
    }

    @Test func rgbSpaceSyntax() throws {
        #expect(try run("color.rgb", "rgb(255 136 0)").primaryText == "rgb(255, 136, 0)")
    }

    @Test func rgbaSpaceSyntaxWithAlpha() throws {
        #expect(try run("color.rgb", "rgba(255 136 0 / 0.5)").primaryText == "rgba(255, 136, 0, 0.5)")
    }

    @Test func rgbCaseInsensitive() throws {
        #expect(try run("color.rgb", "RGB(255, 0, 0)").primaryText == "rgb(255, 0, 0)")
    }

    @Test func rgbAlphaPercent() throws {
        #expect(try run("color.rgb", "rgb(0 0 0 / 100%)").primaryText == "rgb(0, 0, 0)")
    }

    // MARK: - HSL parsing

    @Test func hslSpaceSyntax() throws {
        #expect(try run("color.hsl", "hsl(120 100% 50%)").primaryText == "hsl(120, 100%, 50%)")
    }

    @Test func hslaWithAlpha() throws {
        let output = try run("color.hsl", "hsla(0, 100%, 50%, 0.5)")
        #expect(output.primaryText == "hsla(0, 100%, 50%, 0.5)")
    }

    @Test func hslDegSuffix() throws {
        #expect(try run("color.hsl", "hsl(180deg, 100%, 50%)").primaryText == "hsl(180, 100%, 50%)")
    }

    @Test func hslHueWrap() throws {
        // 480 deg wraps to 120
        #expect(try run("color.hex", "hsl(480, 100%, 50%)").primaryText == "#00ff00")
    }

    // MARK: - Fields

    @Test func allFieldsPresent() throws {
        let output = try run("color.hex", "#ff8800")
        let fieldIds = output.fields.map { $0.id }
        #expect(fieldIds == ["hex", "rgb", "hsl"])
        let fieldLabels = output.fields.map { $0.label }
        #expect(fieldLabels == ["Hex", "RGB", "HSL"])
    }

    @Test func fieldValues() throws {
        let output = try run("color.hex", "#ff8800")
        let hexField = try #require(output.fields.first { $0.id == "hex" })
        let rgbField = try #require(output.fields.first { $0.id == "rgb" })
        let hslField = try #require(output.fields.first { $0.id == "hsl" })
        #expect(hexField.value == "#ff8800")
        #expect(rgbField.value == "rgb(255, 136, 0)")
        #expect(hslField.value == "hsl(32, 100%, 50%)")
    }

    // MARK: - Status

    @Test func statusIsSrgb() throws {
        #expect(try run("color.hex", "#ff8800").status == "sRGB")
        #expect(try run("color.rgb", "#ff8800").status == "sRGB")
        #expect(try run("color.hsl", "#ff8800").status == "sRGB")
    }

    // MARK: - Swatch

    @Test func swatchOnAllCommands() throws {
        #expect(try run("color.hex", "#ff8800").swatch != nil)
        #expect(try run("color.rgb", "#ff8800").swatch != nil)
        #expect(try run("color.hsl", "#ff8800").swatch != nil)
    }

    @Test func swatchWithAlpha() throws {
        let output = try run("color.hex", "#ff880080")
        let swatch = try #require(output.swatch)
        #expect(swatch.alpha < 1.0)
        #expect(abs(swatch.alpha - 0.502) < 0.01)
    }

    // MARK: - Affinity

    @Test func affinityHexCommand() throws {
        let cmd = try #require(ColorTools.commands.first { $0.id == "color.hex" })
        let hexProfile = InputProfile(isAttached: true, kinds: [.hexColor, .color], primaryKind: .hexColor, byteCount: 7, lineCount: 1, isBlank: false)
        let colorProfile = InputProfile(isAttached: true, kinds: [.color], primaryKind: .color, byteCount: 15, lineCount: 1, isBlank: false)
        let noProfile = InputProfile(isAttached: true, kinds: [.text], primaryKind: .text, byteCount: 5, lineCount: 1, isBlank: false)

        #expect(cmd.affinity(hexProfile) == 40)
        #expect(cmd.affinity(colorProfile) == 90)
        #expect(cmd.affinity(noProfile) == 0)
    }

    @Test func affinityRgbCommand() throws {
        let cmd = try #require(ColorTools.commands.first { $0.id == "color.rgb" })
        let hexProfile = InputProfile(isAttached: true, kinds: [.hexColor, .color], primaryKind: .hexColor, byteCount: 7, lineCount: 1, isBlank: false)
        let colorProfile = InputProfile(isAttached: true, kinds: [.color], primaryKind: .color, byteCount: 15, lineCount: 1, isBlank: false)
        let noProfile = InputProfile(isAttached: true, kinds: [.text], primaryKind: .text, byteCount: 5, lineCount: 1, isBlank: false)

        #expect(cmd.affinity(hexProfile) == 95)
        #expect(cmd.affinity(colorProfile) == 85)
        #expect(cmd.affinity(noProfile) == 0)
    }

    @Test func affinityHslCommand() throws {
        let cmd = try #require(ColorTools.commands.first { $0.id == "color.hsl" })
        let colorProfile = InputProfile(isAttached: true, kinds: [.color], primaryKind: .color, byteCount: 15, lineCount: 1, isBlank: false)
        let noProfile = InputProfile(isAttached: true, kinds: [.text], primaryKind: .text, byteCount: 5, lineCount: 1, isBlank: false)

        #expect(cmd.affinity(colorProfile) == 80)
        #expect(cmd.affinity(noProfile) == 0)
    }

    // MARK: - Edge cases

    @Test func hslFractionalValues() throws {
        // HSL output is computed from unquantized channels, so HSL input round-trips.
        #expect(try run("color.hsl", "hsl(210.5, 33.3%, 40%)").primaryText == "hsl(210.5, 33.3%, 40%)")
        // Review P2: 8-bit rounding used to erase hue and saturation here.
        #expect(try run("color.hsl", "hsl(30 1% 1%)").primaryText == "hsl(30, 1%, 1%)")
        // Hex input is exact in 8 bits, so it is unaffected.
        #expect(try run("color.hsl", "#ff8800").primaryText == "hsl(32, 100%, 50%)")
    }

    @Test func rgbZero() throws {
        #expect(try run("color.rgb", "#000000").primaryText == "rgb(0, 0, 0)")
    }

    @Test func rgbFull() throws {
        #expect(try run("color.rgb", "#ffffff").primaryText == "rgb(255, 255, 255)")
    }

    @Test func hslCyan() throws {
        // Cyan: hsl(180, 100%, 50%) → #00ffff
        #expect(try run("color.hex", "hsl(180, 100%, 50%)").primaryText == "#00ffff")
    }

    @Test func hslMagenta() throws {
        // Magenta: hsl(300, 100%, 50%) → #ff00ff
        #expect(try run("color.hex", "hsl(300, 100%, 50%)").primaryText == "#ff00ff")
    }

    @Test func hslYellow() throws {
        // Yellow: hsl(60, 100%, 50%) → #ffff00
        #expect(try run("color.hex", "hsl(60, 100%, 50%)").primaryText == "#ffff00")
    }

    @Test func gray50Percent() throws {
        // hsl(0, 0%, 50%) → #808080
        #expect(try run("color.hex", "hsl(0, 0%, 50%)").primaryText == "#808080")
    }

    @Test func alphaRounding() throws {
        // 50% alpha = 0.5 → 0x80 = 128/255 ≈ 0.502
        let output = try run("color.rgb", "rgb(0 0 0 / 50%)")
        #expect(output.primaryText == "rgba(0, 0, 0, 0.5)")
    }

    @Test func hslFromRgbWithAlpha() throws {
        let output = try run("color.hsl", "rgba(255, 0, 0, 0.5)")
        #expect(output.primaryText == "hsla(0, 100%, 50%, 0.5)")
    }

    @Test func commandMetadata() throws {
        let hexCmd = try #require(ColorTools.commands.first { $0.id == "color.hex" })
        #expect(hexCmd.title == "Convert Color to Hex")
        #expect(hexCmd.summary == "Hex notation for any CSS color")
        #expect(hexCmd.copyNoun(ToolOptions()) == "hex color")

        let rgbCmd = try #require(ColorTools.commands.first { $0.id == "color.rgb" })
        #expect(rgbCmd.title == "Convert Color to RGB")
        #expect(rgbCmd.copyNoun(ToolOptions()) == "RGB color")

        let hslCmd = try #require(ColorTools.commands.first { $0.id == "color.hsl" })
        #expect(hslCmd.title == "Convert Color to HSL")
        #expect(hslCmd.copyNoun(ToolOptions()) == "HSL color")
    }

    @Test func allCommandsInColorGroup() throws {
        for cmd in ColorTools.commands {
            #expect(cmd.group.id == "color")
        }
    }

    @Test func allCommandsHavePaintpaletteIcon() throws {
        for cmd in ColorTools.commands {
            #expect(cmd.icon == CommandIcon.symbol("paintpalette"))
        }
    }

    @Test func noOptions() throws {
        for cmd in ColorTools.commands {
            #expect(cmd.options.isEmpty)
        }
    }
}

@Suite struct ColorParserStrictnessTests {
    private func result(_ id: String, _ text: String) throws -> ToolResult {
        let command = try #require(ColorTools.commands.first { $0.id == id })
        return command.run(ToolRequest(input: .text(text)))
    }

    @Test(arguments: ["rgb)(", "rgb(", "rgb()", "rgba(255,0,0,bogus)", "rgb(255,0,0,0.5,garbage)", "rgb(255,0,0)garbage",
                      "rgb(255 0 0 / 50% / 1)", "rgb(255, 0)", "hsl(0 100%)", "rgb(255, 0 0)", "rgb((255,0,0))", "hsl(0, 100%, 50%, x)"])
    func malformedColorsAreRejected(_ text: String) throws {
        if case .invalid = try result("color.hex", text) {} else { Issue.record("\(text) should be invalid") }
    }

    @Test func validVariantsStillParse() throws {
        #expect(try result("color.hex", "rgba(255, 0, 0, 0.5)").output?.primaryText == "#ff000080")
        #expect(try result("color.hex", "RGB(255 0 0)").output?.primaryText == "#ff0000")
        #expect(try result("color.hex", "hsl(0 100% 50% / 1)").output?.primaryText == "#ff0000")
    }
}
