import Testing
@testable import ToolchordCore

@Suite struct InputDetectorTests {
    private func kinds(_ text: String) -> Set<InputKind> { InputDetector.profile(for: text).kinds }
    private func label(_ text: String) -> String { InputDetector.profile(for: text).label }

    @Test func noInputAndBlankInputAreDistinct() {
        let none = InputDetector.profile(for: .none)
        #expect(!none.isAttached)
        let empty = InputDetector.profile(for: .text(""))
        #expect(empty.isAttached && empty.isBlank)
        #expect(empty.byteCount == 0)
        #expect(InputDetector.profile(for: "  \n ").isBlank)
    }

    @Test(arguments: [
        (#"{"a":1}"#, InputKind.json, "JSON"),
        ("[1, 2]", .json, "JSON"),
        ("{ broken", .json, "JSON"),
        ("<r><a/></r>", .xml, "XML"),
        ("eyJhbGciOiJub25lIn0.eyJleHAiOjB9.", .jwt, "JWT"),
        ("https://example.test/a?b=1", .url, "URL"),
        ("a=1&b=2", .queryString, "Query string"),
        ("0f8fad5b-d9cb-469f-a165-70867728950e", .uuid, "UUID"),
        ("1700000000", .unixTime, "Unix time"),
        ("1700000000000", .unixTime, "Unix time"),
        ("2024-01-01T12:00:00Z", .dateTime, "Date"),
        ("2024-01-01 12:00:00+01:00", .dateTime, "Date"),
        ("#ff8800", .hexColor, "Color"),
        ("rgb(1, 2, 3)", .color, "Color"),
        ("SGVsbG8gd29ybGQ=", .base64, "Base64"),
        ("8J-YgA_xyzAB", .base64URL, "Base64URL"),
        ("0xff", .number, "Number"),
        ("deadbeef", .hex, "Hex"),
        ("hello%20world", .percentEncoded, "URL-encoded text"),
        ("caf&eacute; &amp; more", .htmlEntities, "HTML entities"),
        (#""line\nbreak""#, .jsonStringLiteral, "JSON string"),
        ("Hello, World!", .words, "Text"),
        ("userName", .words, "Text"),
    ] as [(String, InputKind, String)])
    func detectsKind(text: String, kind: InputKind, expectedLabel: String) {
        #expect(kinds(text).contains(kind), "\(text) should be \(kind)")
        #expect(label(text) == expectedLabel, "\(text)")
    }

    @Test func plainWordsAreNotBase64() {
        #expect(!kinds("password").contains(.base64))
        #expect(!kinds("localhost").contains(.base64))
        #expect(!kinds("abcd").contains(.base64))
    }

    @Test func shortNumbersAreNotTimestamps() {
        #expect(kinds("255").contains(.number))
        #expect(!kinds("255").contains(.unixTime))
    }

    @Test func dottedNamesAreNotJWTs() {
        #expect(!kinds("www.example.com").contains(.jwt))
        #expect(!kinds("mail.example.com").contains(.jwt))
        #expect(!kinds("1.2.3").contains(.jwt))
    }

    @Test func codeIsNotWords() {
        #expect(!kinds("if (a) { b }").contains(.words))
        #expect(!kinds("a < b").contains(.words))
    }

    @Test func plainTextFlag() {
        #expect(InputDetector.profile(for: "Hello, World").isPlainText)
        #expect(InputDetector.profile(for: "line one\nline two").isPlainText)
        #expect(!InputDetector.profile(for: #"{"a":1}"#).isPlainText)
        #expect(!InputDetector.profile(for: "1700000000").isPlainText)
        #expect(!InputDetector.profile(for: "").isPlainText)
        #expect(!InputProfile.none.isPlainText)
    }

    @Test func countsLinesAndBytes() {
        let profile = InputDetector.profile(for: "a\r\nb\nc\rd")
        #expect(profile.lineCount == 4)
        #expect(profile.kinds.contains(.multiline))
        #expect(InputDetector.profile(for: "é").byteCount == 2)
    }

    @Test func largeInputIsDetectedQuickly() {
        let big = "[" + String(repeating: "1,", count: 400_000) + "1]"
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = InputDetector.profile(for: big) }
        #expect(InputDetector.profile(for: big).kinds.contains(.json))
        #expect(elapsed < .seconds(2))
    }
}
