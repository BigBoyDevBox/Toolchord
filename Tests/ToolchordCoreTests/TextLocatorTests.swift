import Testing
@testable import ToolchordCore

@Suite struct TextLocatorTests {
    @Test func countsScalarsAndLineBreaks() {
        #expect(TextLocator.location(ofUTF8Offset: 0, in: "abc") == TextLocation(line: 1, column: 1))
        #expect(TextLocator.location(ofUTF8Offset: 2, in: "abc") == TextLocation(line: 1, column: 3))
        // "é" is two UTF-8 bytes but one scalar.
        #expect(TextLocator.location(ofUTF8Offset: 2, in: "éx") == TextLocation(line: 1, column: 2))
        #expect(TextLocator.location(ofUTF8Offset: 3, in: "éx") == TextLocation(line: 1, column: 3))
        #expect(TextLocator.location(ofUTF8Offset: 4, in: "{\n  \"") == TextLocation(line: 2, column: 3))
        // CRLF counts as one line break.
        #expect(TextLocator.location(ofUTF8Offset: 5, in: "a\r\nbc") == TextLocation(line: 2, column: 3))
        #expect(TextLocator.location(ofUTF8Offset: 3, in: "a\rbc") == TextLocation(line: 2, column: 2))
    }
}
