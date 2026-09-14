// The engine asset pack, held to what it promises: an entry decodes to its
// bytes, no run of them survives into the pack, damage is refused rather than
// decoded, and staging makes a directory hold exactly the pack's entries.
//
// AssetPack.swift says why the bundle carries a pack at all. What is held here
// is the format's contract, on small inputs of its own: one that compresses and
// one that does not, because the pack treats the two differently and the app's
// networks are one of each.

import CryptoKit
import Foundation
import Testing
@testable import MiniXiangqi

@Suite("The engine asset pack")
struct AssetPackTests {

    /// Compresses well: a short repeating pattern.
    static let pattern = Data((0..<20_000).map { UInt8($0 % 251) })

    /// Does not compress: random bytes, which is what an LZ4 frame looks like
    /// to a second compressor.
    static let random: Data = {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<20_000).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }()

    static let inputs: [(name: String, bytes: Data)] = [
        ("pattern.nnue", pattern),
        ("random.bin.lz4", random),
    ]

    @Test("Every entry decodes to its bytes, compressed only where that is smaller")
    func everyEntryDecodesToItsBytes() throws {
        let pack = try AssetPack.pack(Self.inputs)
        let entries = try AssetPack.entries(in: pack)
        #expect(entries.map(\.name) == ["pattern.nnue", "random.bin.lz4"])
        #expect(entries[0].method == .zlib)
        #expect(entries[1].method == .stored)
        #expect(entries[0].payloadLength < entries[0].decodedLength)
        #expect(entries[1].payloadLength == entries[1].decodedLength)
        #expect(try AssetPack.decode(entries[0], from: pack) == Self.pattern)
        #expect(try AssetPack.decode(entries[1], from: pack) == Self.random)
        #expect(entries[0].digest == Array(SHA256.hash(data: Self.pattern)))
        #expect(entries[1].digest == Array(SHA256.hash(data: Self.random)))
    }

    @Test("No run of an input survives into the pack")
    func noRunOfAnInputSurvives() throws {
        let pack = try AssetPack.pack(Self.inputs)
        for input in [Self.pattern, Self.random] {
            var offset = 0
            while offset + 32 <= input.count {
                #expect(pack.range(of: input.subdata(in: offset..<(offset + 32))) == nil,
                        "a 32-byte run of an input at \(offset) appears in the pack")
                offset += 256
            }
        }
    }

    @Test("A damaged payload is refused, not decoded")
    func aDamagedPayloadIsRefused() throws {
        var pack = try AssetPack.pack(Self.inputs)
        let entry = try AssetPack.entries(in: pack)[1]
        pack[Int(entry.payloadOffset) + 100] ^= 0xFF
        #expect(throws: AssetPack.Failure.digestMismatch("random.bin.lz4")) {
            try AssetPack.decode(entry, from: pack)
        }
    }

    @Test("A name that could name something outside the directory is refused")
    func namesArePlainFileNames() {
        #expect(throws: AssetPack.Failure.invalidName("../escape")) {
            try AssetPack.pack([("../escape", Self.random)])
        }
        #expect(throws: AssetPack.Failure.notAPack) {
            try AssetPack.entries(in: Data("not a pack at all".utf8))
        }
    }

    @Test("Staging makes the directory hold exactly the pack's entries")
    func stagingHoldsExactlyTheEntries() throws {
        let files = FileManager.default
        let scratch = files.temporaryDirectory
            .appendingPathComponent("AssetPackTests-\(UUID().uuidString)", isDirectory: true)
        let directory = scratch.appendingPathComponent("staged", isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: scratch) }

        let packURL = scratch.appendingPathComponent("test.mxqpack")
        try AssetPack.pack(Self.inputs).write(to: packURL)
        // A network from a previous version, and a damaged copy of a current one.
        try Data("stale".utf8).write(to: directory.appendingPathComponent("previous.nnue"))
        try Data("wrong".utf8).write(to: directory.appendingPathComponent("pattern.nnue"))

        try AssetPack.stage(packURL, into: directory)

        #expect(Set(try files.contentsOfDirectory(atPath: directory.path))
                == ["pattern.nnue", "random.bin.lz4"])
        #expect(try Data(contentsOf: directory.appendingPathComponent("pattern.nnue")) == Self.pattern)
        #expect(try Data(contentsOf: directory.appendingPathComponent("random.bin.lz4")) == Self.random)

        // Staged again, a file that is already right is left alone.
        let staged = directory.appendingPathComponent("random.bin.lz4").path
        let before = try files.attributesOfItem(atPath: staged)[.modificationDate] as? Date
        try AssetPack.stage(packURL, into: directory)
        let after = try files.attributesOfItem(atPath: staged)[.modificationDate] as? Date
        #expect(before != nil && before == after)
    }
}
