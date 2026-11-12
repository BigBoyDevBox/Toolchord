import Foundation

/// How well a query matches a command. Lower is better.
public enum MatchRank: Int, Sendable, Comparable {
    /// The query equals the title or an alias.
    case exact = 0
    /// The title or an alias starts with the query.
    case prefix = 1
    /// Every query word starts a word of the title, an alias, or the group name, in any order.
    case words = 2
    /// The query's letters appear in order within the title or an alias.
    case fuzzy = 3

    public static func < (lhs: MatchRank, rhs: MatchRank) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Ranks commands for a typed query. Explicit queries outrank detection:
/// detection only breaks ties between commands with the same match rank.
public enum CommandSearch {
    /// Lowercases, folds diacritics, treats `_ - / . ,` as spaces, and collapses whitespace.
    public static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
        var result = ""
        result.reserveCapacity(folded.count)
        var pendingSpace = false
        for character in folded {
            if character.isWhitespace || "_-/.,:".contains(character) {
                pendingSpace = !result.isEmpty
            } else {
                if pendingSpace { result.append(" ") }
                pendingSpace = false
                result.append(character)
            }
        }
        return result
    }

    /// The best match rank of `query` for `command`, or `nil` when it does not match.
    public static func match(_ query: String, _ command: ToolCommand) -> MatchRank? {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return .prefix }
        return match(normalizedQuery: normalizedQuery, labels: labels(for: command), allowFuzzy: true)
    }

    /// Whether `text` exactly or partially names a command, without fuzzy
    /// matching. Used to offer "Use as search text" for pasted text.
    public static func plausiblyNamesCommand(_ text: String, in commands: [ToolCommand]) -> Bool {
        let normalizedQuery = normalize(text)
        guard !normalizedQuery.isEmpty else { return false }
        return commands.contains { match(normalizedQuery: normalizedQuery, labels: labels(for: $0), allowFuzzy: false) != nil }
    }

    /// Commands matching `query`, best first. Ties keep catalog order unless
    /// input is attached, in which case higher affinity wins the tie.
    public static func search(_ query: String, in commands: [ToolCommand], profile: InputProfile = .none) -> [ToolCommand] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return commands }
        let ranked: [(command: ToolCommand, rank: MatchRank, affinity: Int, order: Int)] = commands.enumerated().compactMap { order, command in
            guard let rank = match(normalizedQuery: normalizedQuery, labels: labels(for: command), allowFuzzy: true) else { return nil }
            let affinity = profile.isAttached ? command.affinity(profile) : 0
            return (command, rank, affinity, order)
        }
        return ranked.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            if lhs.affinity != rhs.affinity { return lhs.affinity > rhs.affinity }
            return lhs.order < rhs.order
        }.map(\.command)
    }

    // MARK: - Matching

    struct Labels {
        /// Normalized title and aliases.
        var phrases: [String]
        /// Words from the title, aliases, and group name.
        var words: [String]
    }

    static func labels(for command: ToolCommand) -> Labels {
        let phrases = ([command.title] + command.aliases).map(normalize)
        var words: [String] = []
        for phrase in phrases + [normalize(command.group.name)] {
            words.append(contentsOf: phrase.split(separator: " ").map(String.init))
        }
        return Labels(phrases: phrases, words: words)
    }

    static func match(normalizedQuery query: String, labels: Labels, allowFuzzy: Bool) -> MatchRank? {
        if labels.phrases.contains(query) { return .exact }
        if labels.phrases.contains(where: { $0.hasPrefix(query) }) { return .prefix }
        let terms = query.split(separator: " ")
        if terms.allSatisfy({ term in labels.words.contains { $0.hasPrefix(term) } }) { return .words }
        guard allowFuzzy else { return nil }
        let letters = query.replacingOccurrences(of: " ", with: "")
        guard letters.count >= 2 else { return nil }
        if labels.phrases.contains(where: { isSubsequence(letters, of: $0.replacingOccurrences(of: " ", with: "")) }) {
            return .fuzzy
        }
        return nil
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var remaining = needle.makeIterator()
        var current = remaining.next()
        for character in haystack {
            guard let wanted = current else { return true }
            if character == wanted { current = remaining.next() }
        }
        return current == nil
    }
}
