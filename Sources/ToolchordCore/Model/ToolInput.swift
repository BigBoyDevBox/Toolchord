import Foundation

/// The payload a command evaluates.
///
/// `none` (nothing attached) and an attached empty string are distinct:
/// decoding an attached empty string succeeds with empty output, while `none`
/// asks the user for input.
public enum ToolInput: Sendable, Hashable {
    case none
    case text(String)

    /// The attached text, or `nil` when nothing is attached.
    public var text: String? {
        if case .text(let value) = self { return value }
        return nil
    }
}

/// Whether a command reads the attached payload.
public enum InputRequirement: Sendable, Hashable {
    /// The command transforms or inspects attached text. An attached empty
    /// string is valid input.
    case text
    /// The command generates its result and ignores any attached payload.
    case none
}
