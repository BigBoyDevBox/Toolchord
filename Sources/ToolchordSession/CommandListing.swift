import Foundation
import ToolchordCore

/// The command list shown under search: titled sections plus a flat order
/// for arrow-key navigation.
public struct CommandListing: Sendable, Equatable {
    public struct Section: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let commandIDs: [String]
    }

    public let sections: [Section]

    public init(sections: [Section]) {
        self.sections = sections.filter { !$0.commandIDs.isEmpty }
    }

    /// Command IDs in visible order.
    public var orderedIDs: [String] { sections.flatMap(\.commandIDs) }
    public var isEmpty: Bool { sections.isEmpty }
    public var first: String? { sections.first?.commandIDs.first }

    public func contains(_ id: String) -> Bool {
        sections.contains { $0.commandIDs.contains(id) }
    }

    /// Minimum affinity for a command to appear under "Suggested".
    public static let suggestionThreshold = 30

    /// Builds the listing for a query and the attached input.
    ///
    /// - A typed query shows matches only, best first; detection breaks ties.
    /// - With input and no query, suggested commands come first by descending
    ///   affinity (stable), followed by every other command in catalog order.
    /// - With no input and no query, recently used commands come first.
    public static func make(
        query: String,
        profile: InputProfile,
        catalog: [ToolCommand],
        recentIDs: [String]
    ) -> CommandListing {
        if !CommandSearch.normalize(query).isEmpty {
            let results = CommandSearch.search(query, in: catalog, profile: profile)
            return CommandListing(sections: [Section(id: "results", title: "Results", commandIDs: results.map(\.id))])
        }

        if profile.isAttached && !profile.isBlank {
            struct Candidate {
                let order: Int
                let id: String
                let affinity: Int
            }
            var candidates: [Candidate] = []
            for (order, command) in catalog.enumerated() {
                let affinity = command.affinity(profile)
                if affinity >= suggestionThreshold {
                    candidates.append(Candidate(order: order, id: command.id, affinity: affinity))
                }
            }
            candidates.sort { lhs, rhs in
                lhs.affinity != rhs.affinity ? lhs.affinity > rhs.affinity : lhs.order < rhs.order
            }
            let suggested = candidates.map(\.id)
            let suggestedSet = Set(suggested)
            let others = catalog.map(\.id).filter { !suggestedSet.contains($0) }
            if suggested.isEmpty {
                return CommandListing(sections: [Section(id: "all", title: "All tools", commandIDs: others)])
            }
            return CommandListing(sections: [
                Section(id: "suggested", title: "Suggested for \(profile.label)", commandIDs: suggested),
                Section(id: "all", title: "Other tools", commandIDs: others),
            ])
        }

        let known = Set(catalog.map(\.id))
        let recents = recentIDs.filter { known.contains($0) }
        let recentSet = Set(recents)
        let others = catalog.map(\.id).filter { !recentSet.contains($0) }
        return CommandListing(sections: [
            Section(id: "recent", title: "Recent", commandIDs: recents),
            Section(id: "all", title: recents.isEmpty ? "Tools" : "All tools", commandIDs: others),
        ])
    }
}
