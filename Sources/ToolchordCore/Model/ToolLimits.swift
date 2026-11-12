import Foundation

/// Bounds that keep evaluation responsive. Exceeding any limit produces
/// ``ToolResult/tooLarge(_:)`` with no partial result.
public struct ToolLimits: Sendable, Hashable {
    public var maxInputBytes: Int
    public var maxOutputBytes: Int
    /// Maximum nesting of JSON arrays/objects or XML elements.
    public var maxNestingDepth: Int

    public init(maxInputBytes: Int = 1 << 20, maxOutputBytes: Int = 4 << 20, maxNestingDepth: Int = 128) {
        self.maxInputBytes = maxInputBytes
        self.maxOutputBytes = maxOutputBytes
        self.maxNestingDepth = maxNestingDepth
    }

    public static let standard = ToolLimits()

    public var inputLimitMessage: String {
        "Input is larger than \(ByteCountText.string(maxInputBytes)). Toolchord handles up to \(ByteCountText.string(maxInputBytes)) of text."
    }

    public var outputLimitMessage: String {
        "The result would be larger than \(ByteCountText.string(maxOutputBytes))."
    }

    public var nestingLimitMessage: String {
        "Nesting is deeper than \(maxNestingDepth) levels."
    }

    /// Returns ``ToolResult/tooLarge(_:)`` when `text` exceeds the output limit.
    public func checkOutput(_ text: String) -> ToolResult? {
        text.utf8.count > maxOutputBytes ? .tooLarge(outputLimitMessage) : nil
    }
}

public enum ByteCountText {
    /// Binary units, as used by the limits: "1 MiB", "57 bytes", "1 byte".
    public static func string(_ count: Int) -> String {
        if count == 1 { return "1 byte" }
        if count < 1024 { return "\(count) bytes" }
        let units = ["KiB", "MiB", "GiB"]
        var value = Double(count)
        var unit = -1
        while value >= 1024, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        let rounded = (value * 10).rounded() / 10
        let number = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        return "\(number) \(units[unit])"
    }
}
