import Foundation

/// A lexical guess about attached text. Detection orders suggestions; it never
/// decides validity. Commands still validate their input and report errors.
public enum InputKind: String, Sendable, Hashable, CaseIterable {
    case jwt
    case json
    /// An HTML document or fragment (also reported as ``xml`` when it starts with `<`).
    case html
    case xml
    case url
    case queryString
    case uuid
    case dateTime
    case unixTime
    /// Any CSS color: `#rgb`, `rgb()`, `hsl()`, or a named color.
    case color
    /// A `#`-prefixed hex color (also reported as ``color``).
    case hexColor
    case base64URL
    case base64
    case hex
    case number
    case percentEncoded
    case htmlEntities
    case jsonStringLiteral
    case escapedText
    /// Text with Markdown structure: headings, lists, fences, links, emphasis.
    case markdown
    /// Text containing characters typical of rich-text copies: invisible
    /// formatting characters, unusual spaces, or typographic quotes and dashes.
    /// Never the primary kind.
    case specialCharacters
    /// Short single-line text made of words or an identifier, such as
    /// `user name` or `userName` — a candidate for case conversion.
    case words
    case multiline
    case text

    public var displayName: String {
        switch self {
        case .jwt: "JWT"
        case .json: "JSON"
        case .html: "HTML"
        case .xml: "XML"
        case .url: "URL"
        case .queryString: "Query string"
        case .uuid: "UUID"
        case .dateTime: "Date"
        case .unixTime: "Unix time"
        case .color, .hexColor: "Color"
        case .base64URL: "Base64URL"
        case .base64: "Base64"
        case .hex: "Hex"
        case .number: "Number"
        case .percentEncoded: "URL-encoded text"
        case .htmlEntities: "HTML entities"
        case .jsonStringLiteral: "JSON string"
        case .escapedText: "Escaped text"
        case .markdown: "Markdown"
        case .specialCharacters: "Text"
        case .words: "Text"
        case .multiline: "Text"
        case .text: "Text"
        }
    }
}

/// Facts about the attached payload that commands use to rank themselves.
public struct InputProfile: Sendable, Hashable {
    /// Whether any input is attached. An attached empty string is attached.
    public var isAttached: Bool
    public var kinds: Set<InputKind>
    /// The most specific kind, used for the attachment label.
    public var primaryKind: InputKind
    public var byteCount: Int
    /// Number of lines; an empty string has one line.
    public var lineCount: Int
    /// Attached text that is empty or only whitespace.
    public var isBlank: Bool

    public init(isAttached: Bool, kinds: Set<InputKind>, primaryKind: InputKind, byteCount: Int, lineCount: Int, isBlank: Bool) {
        self.isAttached = isAttached
        self.kinds = kinds
        self.primaryKind = primaryKind
        self.byteCount = byteCount
        self.lineCount = lineCount
        self.isBlank = isBlank
    }

    /// No input attached.
    public static let none = InputProfile(isAttached: false, kinds: [], primaryKind: .text, byteCount: 0, lineCount: 0, isBlank: true)

    public func has(_ kind: InputKind) -> Bool { kinds.contains(kind) }

    /// The label for the attachment row, such as "JSON" or "Text".
    public var label: String { primaryKind.displayName }

    /// Attached text with no more specific kind (prose, words, or lines).
    /// General text tools suggest themselves only for plain text, so they
    /// never crowd out the specific tools for JSON, URLs, and so on.
    public var isPlainText: Bool {
        isAttached && !isBlank && [.text, .words, .multiline, .markdown].contains(primaryKind)
    }
}
