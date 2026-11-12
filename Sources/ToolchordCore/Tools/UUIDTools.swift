import Foundation

/// UUID v4, UUID v7, and ULID generators.
///
/// Each value is created once by `makeSeed` (system randomness) and kept by
/// the session until Regenerate; evaluation only formats the seed.
public enum UUIDTools {
    public static let commands: [ToolCommand] = [
        ToolCommand(
            id: "uuid.v4",
            title: "Generate UUID",
            summary: "Random version 4 identifier",
            group: .uuid,
            icon: .glyph("#"),
            aliases: ["guid", "uuid v4", "uuid4", "random uuid", "new uuid", "random id"],
            input: .none,
            copyNoun: "UUID",
            makeSeed: { _ in UUID().uuidString.lowercased() },
            regenerateTitle: "Regenerate UUID",
            evaluate: { evaluateUUID($0, version: 4) }
        ),
        ToolCommand(
            id: "uuid.v7",
            title: "Generate UUID v7",
            summary: "Time-ordered identifier",
            group: .uuid,
            icon: .glyph("#"),
            aliases: ["uuid7", "uuid v7", "time ordered uuid", "sortable uuid"],
            input: .none,
            copyNoun: "UUID",
            makeSeed: { context in
                var generator = SystemRandomNumberGenerator()
                return makeUUIDv7(
                    milliseconds: milliseconds(of: context.now),
                    randA: UInt16.random(in: 0...0x0FFF, using: &generator),
                    randB: UInt64.random(in: 0...0x3FFF_FFFF_FFFF_FFFF, using: &generator)
                )
            },
            regenerateTitle: "Regenerate UUID",
            evaluate: { evaluateUUID($0, version: 7) }
        ),
        ToolCommand(
            id: "uuid.ulid",
            title: "Generate ULID",
            summary: "Sortable 26-character identifier",
            group: .uuid,
            icon: .glyph("#"),
            aliases: ["ulid", "sortable id"],
            input: .none,
            copyNoun: "ULID",
            makeSeed: { context in
                var generator = SystemRandomNumberGenerator()
                let randomness = (0..<10).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
                return makeULID(milliseconds: milliseconds(of: context.now), randomness: randomness)
            },
            regenerateTitle: "Regenerate ULID",
            evaluate: evaluateULID
        ),
    ]

    static let missingSeed = ToolResult.needsInput("Select this command again to generate a value.")

    // MARK: - UUID

    static func evaluateUUID(_ request: ToolRequest, version: UInt8) -> ToolResult {
        guard let seed = request.seed, let bytes = parseCanonicalUUID(seed),
              bytes[6] >> 4 == version, bytes[8] & 0xC0 == 0x80 else {
            return missingSeed
        }
        let upper = seed.uppercased()
        var fields: [ResultField] = []
        if version == 7 {
            let milliseconds = bytes[0..<6].reduce(Int64(0)) { $0 << 8 | Int64($1) }
            fields.append(ResultField(id: "timestamp", label: "Timestamp", value: TimeMath.format(milliseconds, suffix: "Z")))
        }
        fields.append(ResultField(id: "upper", label: "Uppercase", value: upper))
        fields.append(ResultField(id: "compact", label: "No hyphens", value: seed.replacingOccurrences(of: "-", with: "")))
        if version == 4 {
            fields.append(ResultField(id: "braced", label: "Braced", value: "{\(upper)}"))
        }
        return .success(ToolOutput(primaryText: seed, status: "UUID v\(version)", fields: fields))
    }

    /// The 16 bytes of a canonical lowercase hyphenated UUID, or `nil`.
    static func parseCanonicalUUID(_ text: String) -> [UInt8]? {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count == 36 else { return nil }
        var bytes: [UInt8] = []
        var high: UInt8?
        for (index, scalar) in scalars.enumerated() {
            if [8, 13, 18, 23].contains(index) {
                guard scalar == "-" else { return nil }
                continue
            }
            let nibble: UInt8
            switch scalar {
            case "0"..."9": nibble = UInt8(scalar.value - 48)
            case "a"..."f": nibble = UInt8(scalar.value - 87)
            default: return nil
            }
            if let value = high {
                bytes.append(value << 4 | nibble)
                high = nil
            } else {
                high = nibble
            }
        }
        return bytes.count == 16 ? bytes : nil
    }

    /// RFC 9562 §5.7: 48-bit Unix milliseconds, version 7, 12-bit `rand_a`,
    /// variant `10`, 62-bit `rand_b`. Extra high bits of the inputs are ignored.
    static func makeUUIDv7(milliseconds: UInt64, randA: UInt16, randB: UInt64) -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let time = milliseconds & 0xFFFF_FFFF_FFFF
        for index in 0..<6 {
            bytes[index] = UInt8(truncatingIfNeeded: time >> (40 - 8 * index))
        }
        let a = randA & 0x0FFF
        bytes[6] = 0x70 | UInt8(truncatingIfNeeded: a >> 8)
        bytes[7] = UInt8(truncatingIfNeeded: a)
        let b = randB & 0x3FFF_FFFF_FFFF_FFFF
        bytes[8] = 0x80 | UInt8(truncatingIfNeeded: b >> 56)
        for index in 9..<16 {
            bytes[index] = UInt8(truncatingIfNeeded: b >> (8 * (15 - index)))
        }
        return format(bytes)
    }

    static func format(_ bytes: [UInt8]) -> String {
        let hex = bytes.map { String(format: "%02x", $0) }
        return [hex[0..<4], hex[4..<6], hex[6..<8], hex[8..<10], hex[10..<16]]
            .map { $0.joined() }
            .joined(separator: "-")
    }

    static func milliseconds(of date: Date) -> UInt64 {
        UInt64(max(0, (date.timeIntervalSince1970 * 1000).rounded(.down)))
    }

    // MARK: - ULID

    static let crockford = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ".unicodeScalars)

    /// github.com/ulid/spec: 48-bit milliseconds then 80 random bits, as 26
    /// Crockford base32 characters (the first carries 3 bits).
    static func makeULID(milliseconds: UInt64, randomness: [UInt8]) -> String {
        precondition(randomness.count == 10, "A ULID needs 10 random bytes")
        let time = milliseconds & 0xFFFF_FFFF_FFFF
        let bytes = (0..<6).map { UInt8(truncatingIfNeeded: time >> (40 - 8 * $0)) } + randomness
        // 128 bits padded with two leading zero bits form 26 five-bit groups.
        func bit(_ position: Int) -> Int {
            guard position >= 0 else { return 0 }
            return Int(bytes[position / 8] >> (7 - position % 8)) & 1
        }
        var scalars = String.UnicodeScalarView()
        for group in 0..<26 {
            var value = 0
            for offset in 0..<5 {
                value = value << 1 | bit(group * 5 - 2 + offset)
            }
            scalars.append(crockford[value])
        }
        return String(scalars)
    }

    static func evaluateULID(_ request: ToolRequest) -> ToolResult {
        guard let seed = request.seed else { return missingSeed }
        let scalars = Array(seed.unicodeScalars)
        guard scalars.count == 26, let first = scalars.first, ("0"..."7").contains(first),
              scalars.allSatisfy(crockford.contains) else {
            return missingSeed
        }
        let milliseconds = scalars.prefix(10).reduce(Int64(0)) { value, scalar in
            value << 5 | Int64(crockford.firstIndex(of: scalar)!)
        }
        return .success(ToolOutput(
            primaryText: seed,
            status: "ULID",
            fields: [
                ResultField(id: "timestamp", label: "Timestamp", value: TimeMath.format(milliseconds, suffix: "Z")),
                ResultField(id: "lower", label: "Lowercase", value: seed.lowercased()),
            ]
        ))
    }
}
