import CryptoKit
import Foundation

/// SHA-256, SHA-512, SHA-1, and MD5 digests of the UTF-8 text.
///
/// This module is the reference for tool conventions: one public `commands`
/// array, internal helpers, pure evaluation from ``ToolRequest``, and
/// cancellation checks in loops over input.
public enum HashTools {
    public static let commands: [ToolCommand] = [
        command(
            id: "hash.sha256",
            title: "Hash with SHA-256",
            summary: "Hex digest of the UTF-8 text",
            aliases: ["sha256", "sha-256", "sha 256", "checksum", "digest", "hash"],
            algorithm: .sha256
        ),
        command(
            id: "hash.sha512",
            title: "Hash with SHA-512",
            summary: "Hex digest of the UTF-8 text",
            aliases: ["sha512", "sha-512", "sha 512"],
            algorithm: .sha512
        ),
        command(
            id: "hash.sha1",
            title: "Hash with SHA-1",
            summary: "Legacy digest; not collision resistant",
            aliases: ["sha1", "sha-1", "sha 1"],
            algorithm: .sha1
        ),
        command(
            id: "hash.md5",
            title: "Hash with MD5",
            summary: "Legacy checksum; not for security",
            aliases: ["md5", "md5sum", "md5 checksum"],
            algorithm: .md5
        ),
    ]

    enum Algorithm: Sendable {
        case sha256, sha512, sha1, md5

        var name: String {
            switch self {
            case .sha256: "SHA-256"
            case .sha512: "SHA-512"
            case .sha1: "SHA-1"
            case .md5: "MD5"
            }
        }

        var isLegacy: Bool { self == .sha1 || self == .md5 }
    }

    private static func command(id: String, title: String, summary: String, aliases: [String], algorithm: Algorithm) -> ToolCommand {
        ToolCommand(
            id: id,
            title: title,
            summary: summary,
            group: .hash,
            icon: .glyph("#"),
            aliases: aliases,
            copyNoun: "hash",
            evaluate: { request in evaluate(request, algorithm: algorithm) }
        )
    }

    static func evaluate(_ request: ToolRequest, algorithm: Algorithm) -> ToolResult {
        guard let text = request.input.text else { return .needsInput("Paste text to hash.") }
        guard let digest = hexDigest(of: Data(text.utf8), algorithm: algorithm, cancellation: request.cancellation) else {
            return .cancelled
        }
        let byteCount = text.utf8.count
        var warnings: [String] = []
        if algorithm.isLegacy {
            warnings.append("\(algorithm.name) is not collision resistant. Use it only for checksums and legacy compatibility.")
        }
        return .success(ToolOutput(
            primaryText: digest,
            status: "\(algorithm.name) · \(ByteCountText.string(byteCount)) hashed",
            warnings: warnings
        ))
    }

    /// Lowercase hex digest, or `nil` when cancelled. Hashes in chunks so
    /// large input can be cancelled.
    static func hexDigest(of data: Data, algorithm: Algorithm, cancellation: CancellationCheck = .never) -> String? {
        func run<H: HashFunction>(_ hasher: inout H) -> String? {
            let chunk = 64 * 1024
            var offset = 0
            while offset < data.count {
                if cancellation.isCancelled { return nil }
                let end = min(offset + chunk, data.count)
                hasher.update(data: data[offset..<end])
                offset = end
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
        switch algorithm {
        case .sha256:
            var hasher = SHA256()
            return run(&hasher)
        case .sha512:
            var hasher = SHA512()
            return run(&hasher)
        case .sha1:
            var hasher = Insecure.SHA1()
            return run(&hasher)
        case .md5:
            var hasher = Insecure.MD5()
            return run(&hasher)
        }
    }
}
