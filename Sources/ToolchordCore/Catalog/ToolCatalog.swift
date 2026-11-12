import Foundation

/// Every command in display order. Each tool module owns its commands; this
/// file only decides the order of the groups.
public enum ToolCatalog {
    public static let commands: [ToolCommand] = {
        let groups: [[ToolCommand]] = [
            JSONTools.commands,
            XMLTools.commands,
            Base64Tools.commands,
            URLTools.commands,
            JWTTools.commands,
            TimeTools.commands,
            UUIDTools.commands,
            RandomTools.commands,
            HashTools.commands,
            CaseTools.commands,
            LineTools.commands,
            HTMLTools.commands,
            NumberTools.commands,
            HexTools.commands,
            ColorTools.commands,
            TextTools.commands,
        ]
        let all = groups.flatMap { $0 }
        var seen = Set<String>()
        for command in all {
            precondition(seen.insert(command.id).inserted, "Duplicate command ID \(command.id)")
        }
        return all
    }()

    public static func command(id: String) -> ToolCommand? {
        commands.first { $0.id == id }
    }
}
