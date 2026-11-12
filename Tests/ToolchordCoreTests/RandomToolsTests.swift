import Foundation
import Testing
@testable import ToolchordCore

@Suite struct RandomToolsTests {
    private func command(_ id: String) throws -> ToolCommand {
        try #require(RandomTools.commands.first { $0.id == id })
    }

    private func string(seed: String, options: [String: String]) throws -> ToolOutput {
        let result = try command("random.string").run(ToolRequest(input: .none, options: ToolOptions(options), seed: seed))
        return try #require(result.output, "Expected success, got \(result)")
    }

    private func hexSeed(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    @Test func zeroBytesMapToTheFirstCharacter() throws {
        let zeros = hexSeed(Array(repeating: 0, count: 512))
        #expect(try string(seed: zeros, options: ["length": "16", "characters": "alnum"]).primaryText == "AAAAAAAAAAAAAAAA")
        #expect(try string(seed: zeros, options: ["length": "32", "characters": "hex"]).primaryText == String(repeating: "0", count: 32))
    }

    @Test func biasedBytesAreRejected() throws {
        // 255 ≥ 248 (the largest multiple of 62 below 256), so it is skipped.
        let seed = hexSeed([0xFF] + Array(repeating: 0x01, count: 511))
        #expect(try string(seed: seed, options: ["length": "16", "characters": "alnum"]).primaryText == "BBBBBBBBBBBBBBBB")
    }

    @Test func symbolsAlphabetAndEntropy() throws {
        let seed = try command("random.string").makeSeed!(SeedContext())
        let output = try string(seed: seed, options: ["length": "64", "characters": "symbols"])
        #expect(output.primaryText.unicodeScalars.count == 64)
        #expect(output.primaryText.unicodeScalars.allSatisfy(RandomTools.symbols.contains))
        #expect(output.fields.first { $0.id == "entropy" }?.value == "415 bits")
        #expect(output.status == "64 characters")
        #expect(!output.status.lowercased().contains("password"))
    }

    @Test func defaultOptionsGiveThirtyTwoAlphanumerics() throws {
        let seed = try command("random.string").makeSeed!(SeedContext())
        let result = try command("random.string").run(ToolRequest(input: .none, seed: seed))
        let text = try #require(result.output?.primaryText)
        #expect(text.unicodeScalars.count == 32)
        #expect(text.unicodeScalars.allSatisfy(RandomTools.alphanumerics.contains))
        #expect(result.output?.fields.first?.value == "190 bits")
    }

    @Test func changingOptionsRemapsTheSameSeed() throws {
        let seed = try command("random.string").makeSeed!(SeedContext())
        let short = try string(seed: seed, options: ["length": "16"]).primaryText
        let long = try string(seed: seed, options: ["length": "64"]).primaryText
        #expect(long.hasPrefix(short))
    }

    @Test func seedsAreSecureLengthAndDistinct() throws {
        let make = try #require(try command("random.string").makeSeed)
        let seeds = (0..<20).map { _ in make(SeedContext()) }
        #expect(Set(seeds).count == 20)
        #expect(seeds.allSatisfy { $0.utf8.count == 1024 })
    }

    @Test func missingSeedAsksToRegenerate() throws {
        for id in ["random.string", "random.lorem"] {
            if case .needsInput = try command(id).run(ToolRequest(input: .none, seed: nil)) {} else { Issue.record("Expected needsInput for \(id)") }
            if case .needsInput = try command(id).run(ToolRequest(input: .none, seed: "zz")) {} else { Issue.record("Expected needsInput for \(id)") }
        }
    }

    @Test func loremSentenceIsTheClassicOpening() throws {
        let result = try command("random.lorem").run(ToolRequest(input: .none, options: ToolOptions(["length": "sentence"]), seed: "42"))
        #expect(result.output?.primaryText == "Lorem ipsum dolor sit amet, consectetur adipiscing elit.")
        #expect(result.output?.status == "8 words")
    }

    @Test func loremIsDeterministicPerSeed() throws {
        let lorem = try command("random.lorem")
        let request = ToolRequest(input: .none, options: ToolOptions(["length": "five"]), seed: "12345")
        let first = try #require(lorem.run(request).output?.primaryText)
        #expect(lorem.run(request).output?.primaryText == first)
        let paragraphs = first.components(separatedBy: "\n\n")
        #expect(paragraphs.count == 5)
        #expect(paragraphs[0].hasPrefix("Lorem ipsum dolor sit amet, consectetur adipiscing elit. "))
        #expect(!first.hasSuffix(" ") && !first.hasSuffix("\n"))
        let other = lorem.run(ToolRequest(input: .none, options: ToolOptions(["length": "five"]), seed: "54321")).output?.primaryText
        #expect(other != first)
    }

    @Test func loremSentencesFollowTheShape() throws {
        let text = RandomTools.lorem(paragraphs: 3, seed: 7)
        for paragraph in text.components(separatedBy: "\n\n") {
            let sentences = paragraph.split(separator: ".").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            #expect((4...7).contains(sentences.count))
            for sentence in sentences.dropFirst() {
                let words = sentence.split(separator: " ")
                #expect((6...14).contains(words.count))
                #expect(words[0].first?.isUppercase == true)
                #expect(sentence.filter { $0 == "," }.count <= 1)
            }
        }
    }
}
