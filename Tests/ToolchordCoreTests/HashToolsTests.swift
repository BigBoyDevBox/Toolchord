import Foundation
import Testing
@testable import ToolchordCore

@Suite struct HashToolsTests {
    private func run(_ id: String, _ text: String) throws -> ToolOutput {
        let command = try #require(HashTools.commands.first { $0.id == id })
        let result = command.run(ToolRequest(input: .text(text)))
        return try #require(result.output, "Expected success, got \(result)")
    }

    // Expected digests are the published FIPS 180 / RFC 1321 test vectors for "abc".
    @Test func knownDigestsOfABC() throws {
        #expect(try run("hash.sha256", "abc").primaryText == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(try run("hash.sha512", "abc").primaryText == "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
        #expect(try run("hash.sha1", "abc").primaryText == "a9993e364706816aba3e25717850c26c9cd0d89d")
        #expect(try run("hash.md5", "abc").primaryText == "900150983cd24fb0d6963f7d28e17f72")
    }

    @Test func emptyInputIsHashed() throws {
        #expect(try run("hash.sha256", "").primaryText == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(try run("hash.md5", "").primaryText == "d41d8cd98f00b204e9800998ecf8427e")
    }

    @Test func hashesUTF8Bytes() throws {
        // SHA-256 of the UTF-8 bytes E2 9C 93 ("✓"), computed with `shasum -a 256`.
        #expect(try run("hash.sha256", "✓").primaryText == "1dabba21cdad44541f6b15796f8d22978fc7ea10c46aeceeeeb66c23b3ac7604")
    }

    @Test func legacyAlgorithmsWarn() throws {
        #expect(try run("hash.md5", "x").warnings.isEmpty == false)
        #expect(try run("hash.sha1", "x").warnings.isEmpty == false)
        #expect(try run("hash.sha256", "x").warnings.isEmpty)
    }

    @Test func missingInputAsksForText() throws {
        let command = try #require(HashTools.commands.first)
        if case .needsInput = command.run(ToolRequest(input: .none)) {} else {
            Issue.record("Expected needsInput")
        }
    }

    @Test func cancellationStopsWork() {
        let data = Data(repeating: 0x61, count: 512 * 1024)
        #expect(HashTools.hexDigest(of: data, algorithm: .sha256, cancellation: CancellationCheck { true }) == nil)
    }
}
