import Foundation

/// A user-visible setting that affects one command's result, such as the
/// Base64 whitespace policy or the Unix time unit.
public struct ToolOption: Sendable, Hashable, Identifiable {
    public struct Choice: Sendable, Hashable, Identifiable {
        public let id: String
        public let label: String

        public init(_ id: String, _ label: String) {
            self.id = id
            self.label = label
        }
    }

    public enum Kind: Sendable, Hashable {
        /// One of several labeled values, shown as a segmented control.
        case choice([Choice], defaultID: String)
        /// An on/off setting, shown as a checkbox.
        case toggle(defaultValue: Bool)
    }

    public let id: String
    public let label: String
    public let kind: Kind

    public init(id: String, label: String, kind: Kind) {
        self.id = id
        self.label = label
        self.kind = kind
    }

    public static func choice(_ id: String, _ label: String, _ choices: [Choice], default defaultID: String) -> ToolOption {
        precondition(choices.contains { $0.id == defaultID }, "Default choice \(defaultID) is not offered by option \(id)")
        return ToolOption(id: id, label: label, kind: .choice(choices, defaultID: defaultID))
    }

    public static func toggle(_ id: String, _ label: String, default defaultValue: Bool = false) -> ToolOption {
        ToolOption(id: id, label: label, kind: .toggle(defaultValue: defaultValue))
    }

    /// The stored representation of this option's default value.
    public var defaultValue: String {
        switch kind {
        case .choice(_, let defaultID): defaultID
        case .toggle(let value): value ? "true" : "false"
        }
    }

    /// Whether `value` is a valid stored representation for this option.
    public func accepts(_ value: String) -> Bool {
        switch kind {
        case .choice(let choices, _): choices.contains { $0.id == value }
        case .toggle: value == "true" || value == "false"
        }
    }
}

/// The option values for one evaluation. Values are stored as strings: a
/// choice ID, or `"true"`/`"false"` for toggles.
///
/// Evaluation always receives *resolved* options: every declared option is
/// present and valid. Use ``resolved(for:)`` to fill defaults.
public struct ToolOptions: Sendable, Hashable {
    public private(set) var values: [String: String]

    public init(_ values: [String: String] = [:]) {
        self.values = values
    }

    /// The selected choice ID for `id`, or `fallback` when absent.
    public func choice(_ id: String, default fallback: String) -> String {
        values[id] ?? fallback
    }

    /// The value of toggle `id`, or `fallback` when absent.
    public func flag(_ id: String, default fallback: Bool = false) -> Bool {
        guard let value = values[id] else { return fallback }
        return value == "true"
    }

    public mutating func set(_ id: String, choice: String) {
        values[id] = choice
    }

    public mutating func set(_ id: String, flag: Bool) {
        values[id] = flag ? "true" : "false"
    }

    /// Returns options containing exactly the declared options: unknown keys
    /// are dropped and missing or invalid values are replaced with defaults.
    public func resolved(for declared: [ToolOption]) -> ToolOptions {
        var result: [String: String] = [:]
        for option in declared {
            if let value = values[option.id], option.accepts(value) {
                result[option.id] = value
            } else {
                result[option.id] = option.defaultValue
            }
        }
        return ToolOptions(result)
    }
}
