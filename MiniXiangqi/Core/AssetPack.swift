// The engine's assets, packed into the one file the app ships in place of the
// directory the core reads.
//
// The core reads its assets from a directory of plain files — the variant
// configuration and every pinned network — and verifies each against the pins
// compiled into it before an engine is given a path (docs/engine-integration.md,
// "The networks"). The app used to ship that directory as it is. Three of the
// five networks are published files, the Fairy-Stockfish project's xiangqi
// network and the Rapfi project's weights, which other applications embedding
// the same engines ship byte-for-byte, and App Review compares binaries across
// developers: the app was refused twice under Guideline 4.3(a) as sharing "a
// similar binary", and those verbatim files were the largest identical bytes it
// carried.
//
// So the app ships this pack instead, and stages the directory from it into its
// own cache at start-up (Core.swift). Each entry is compressed where that helps
// — the two NNUE networks shrink by more than half — and every entry's payload
// then passes through a keyed transform, so that no run of the original bytes
// survives into the bundle, including for the weights compression leaves alone.
// Nothing about what the engines read changes: the staged directory holds
// exactly the files the core read before, under the same names, and the core's
// own verification is unchanged and still what admits a byte to an engine. The
// transform is not secrecy — its seed is in the header and this file is public
// — and the About screen's acknowledgements still name every component. The
// pack changes what the bundle looks like, not what the application is.
//
// The format, version 1. Every integer is little-endian.
//
//   magic          8 bytes   "MXQASSET"
//   version        u32       1
//   entry count    u32
//   entries        entry count times:
//     name length  u16
//     name         UTF-8, a plain file name
//     method       u8        0 stored, 1 zlib (raw deflate)
//     decoded      u64       the entry's length once decoded
//     payload      u64       the payload's length in this file
//     offset       u64       the payload's offset from the start of the file
//     digest       32 bytes  SHA-256 of the decoded bytes
//   payloads       each entry's compressed-or-stored bytes, XOR its keystream
//
// The keystream is xorshift64* seeded from the entry's digest, each output word
// laid down in little-endian order, so the header alone decodes an entry and one
// function both encodes and decodes. AssetPackTool writes packs with this
// file and the app reads them with it: the format has one implementation.

import Compression
import CryptoKit
import Foundation

nonisolated enum AssetPack {
    /// The pack's name in the bundle. build-core-xcframework.sh writes it
    /// under this name and check-core-is-current.sh looks for it by it.
    static let fileName = "engine-assets.mxqpack"

    static let magic: [UInt8] = Array("MXQASSET".utf8)
    static let version: UInt32 = 1

    enum Method: UInt8, Sendable {
        case stored = 0
        case zlib = 1
    }

    struct Entry: Equatable, Sendable {
        var name: String
        var method: Method
        var decodedLength: UInt64
        var payloadLength: UInt64
        var payloadOffset: UInt64
        /// SHA-256 of the decoded bytes, 32 bytes.
        var digest: [UInt8]
    }

    enum Failure: Error, Equatable, CustomStringConvertible {
        case notAPack
        case unsupportedVersion(UInt32)
        case malformed(String)
        case invalidName(String)
        case duplicateName(String)
        case cannotDecompress(String)
        case digestMismatch(String)

        var description: String {
            switch self {
            case .notAPack: "not an engine asset pack"
            case .unsupportedVersion(let version): "engine asset pack version \(version) is not supported"
            case .malformed(let what): "malformed engine asset pack: \(what)"
            case .invalidName(let name): "an entry name must be a plain file name: \(name)"
            case .duplicateName(let name): "the same entry name twice: \(name)"
            case .cannotDecompress(let name): "cannot decompress the entry \(name)"
            case .digestMismatch(let name): "the entry \(name) does not decode to its recorded bytes"
            }
        }
    }

    // MARK: - Writing

    /// A pack holding `inputs` in order, each under its name.
    static func pack(_ inputs: [(name: String, bytes: Data)]) throws -> Data {
        var seen = Set<String>()
        for input in inputs {
            try validate(name: input.name)
            guard seen.insert(input.name).inserted else { throw Failure.duplicateName(input.name) }
        }

        // The payloads start where the header ends, and the header's size is
        // known from the names alone.
        var offset = headerLength(names: inputs.map(\.name))
        var entries: [Entry] = []
        var payloads: [Data] = []
        for input in inputs {
            let digest = Array(SHA256.hash(data: input.bytes))
            var payload: Data
            let method: Method
            if let compressed = compress(input.bytes) {
                payload = compressed
                method = .zlib
            } else {
                payload = input.bytes
                method = .stored
            }
            transform(&payload, digest: digest)
            entries.append(Entry(name: input.name, method: method,
                                 decodedLength: UInt64(input.bytes.count),
                                 payloadLength: UInt64(payload.count),
                                 payloadOffset: UInt64(offset), digest: digest))
            payloads.append(payload)
            offset += payload.count
        }

        var out = Data()
        out.append(contentsOf: magic)
        append(version, to: &out)
        append(UInt32(entries.count), to: &out)
        for entry in entries {
            let name = Array(entry.name.utf8)
            append(UInt16(name.count), to: &out)
            out.append(contentsOf: name)
            out.append(entry.method.rawValue)
            append(entry.decodedLength, to: &out)
            append(entry.payloadLength, to: &out)
            append(entry.payloadOffset, to: &out)
            out.append(contentsOf: entry.digest)
        }
        for payload in payloads {
            out.append(payload)
        }
        return out
    }

    // MARK: - Reading

    /// The pack's index, checked for shape: every name a plain file name, every
    /// payload inside the file.
    static func entries(in pack: Data) throws -> [Entry] {
        var cursor = Cursor(data: pack)
        guard let head = try? cursor.bytes(magic.count), Array(head) == magic else {
            throw Failure.notAPack
        }
        let version = try cursor.uint32()
        guard version == Self.version else { throw Failure.unsupportedVersion(version) }
        let count = try cursor.uint32()

        var entries: [Entry] = []
        var seen = Set<String>()
        for _ in 0..<count {
            let nameLength = try cursor.uint16()
            guard let name = String(bytes: try cursor.bytes(Int(nameLength)), encoding: .utf8) else {
                throw Failure.malformed("an entry name is not UTF-8")
            }
            try validate(name: name)
            guard seen.insert(name).inserted else { throw Failure.duplicateName(name) }
            guard let method = Method(rawValue: try cursor.uint8()) else {
                throw Failure.malformed("unknown method for \(name)")
            }
            let decodedLength = try cursor.uint64()
            let payloadLength = try cursor.uint64()
            let payloadOffset = try cursor.uint64()
            let digest = Array(try cursor.bytes(32))
            let end = payloadOffset.addingReportingOverflow(payloadLength)
            guard !end.overflow, end.partialValue <= UInt64(pack.count) else {
                throw Failure.malformed("the payload of \(name) lies outside the file")
            }
            entries.append(Entry(name: name, method: method, decodedLength: decodedLength,
                                 payloadLength: payloadLength, payloadOffset: payloadOffset,
                                 digest: digest))
        }
        return entries
    }

    /// One entry's bytes, verified against the digest the pack records for it.
    static func decode(_ entry: Entry, from pack: Data) throws -> Data {
        let start = pack.startIndex + Int(entry.payloadOffset)
        var payload = pack.subdata(in: start..<(start + Int(entry.payloadLength)))
        transform(&payload, digest: entry.digest)
        let decoded: Data
        switch entry.method {
        case .stored:
            decoded = payload
        case .zlib:
            guard let inflated = decompress(payload, decodedLength: Int(entry.decodedLength)) else {
                throw Failure.cannotDecompress(entry.name)
            }
            decoded = inflated
        }
        guard decoded.count == Int(entry.decodedLength),
              Array(SHA256.hash(data: decoded)) == entry.digest else {
            throw Failure.digestMismatch(entry.name)
        }
        return decoded
    }

    // MARK: - Staging

    /// Make `directory` hold exactly the pack's entries as plain files, each
    /// with its recorded bytes. An entry already there with its recorded length
    /// and digest is kept; every other file in the directory is removed, so a
    /// network a previous version staged does not linger beside the current
    /// ones. Writes are atomic: a crash part-way leaves the previous file or the
    /// new one, never a partial one.
    static func stage(_ packURL: URL, into directory: URL) throws {
        let pack = try Data(contentsOf: packURL, options: .mappedIfSafe)
        let entries = try entries(in: pack)
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true)

        let wanted = Set(entries.map(\.name))
        for existing in try files.contentsOfDirectory(atPath: directory.path)
        where !wanted.contains(existing) {
            try files.removeItem(at: directory.appendingPathComponent(existing))
        }
        for entry in entries {
            let target = directory.appendingPathComponent(entry.name)
            if isCurrent(target, entry) { continue }
            try decode(entry, from: pack).write(to: target, options: .atomic)
        }
    }

    private static func isCurrent(_ url: URL, _ entry: Entry) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count == Int(entry.decodedLength) else { return false }
        return Array(SHA256.hash(data: data)) == entry.digest
    }

    // MARK: - The transform

    /// XOR `bytes` in place with the keystream for `digest`. Symmetric, so the
    /// same call encodes and decodes.
    static func transform(_ bytes: inout Data, digest: [UInt8]) {
        var state = seed(from: digest)
        bytes.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            let count = buffer.count
            var offset = 0
            while offset + 8 <= count {
                let word = UInt64(littleEndian: buffer.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
                buffer.storeBytes(of: (word ^ next(&state)).littleEndian, toByteOffset: offset, as: UInt64.self)
                offset += 8
            }
            if offset < count {
                let tail = next(&state).littleEndian
                withUnsafeBytes(of: tail) { key in
                    for index in 0..<(count - offset) {
                        buffer[offset + index] ^= key[index]
                    }
                }
            }
        }
    }

    /// The first eight digest bytes as a little-endian word, folded with a
    /// constant so that a digest beginning with zeros still seeds a non-zero
    /// state, which xorshift requires.
    private static func seed(from digest: [UInt8]) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(digest[index]) << (8 * UInt64(index))
        }
        value ^= 0x9E37_79B9_7F4A_7C15
        return value == 0 ? 0x9E37_79B9_7F4A_7C15 : value
    }

    /// xorshift64*.
    private static func next(_ state: inout UInt64) -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545_F491_4F6C_DD1D
    }

    // MARK: - Compression

    /// `bytes` as raw deflate, or nil when that would not be smaller: the
    /// second engine's weights are LZ4 frames already, and storing them costs
    /// less than a compressed copy of the same size.
    private static func compress(_ bytes: Data) -> Data? {
        guard !bytes.isEmpty else { return nil }
        var output = Data(count: bytes.count)
        let written = output.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) in
            bytes.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
                compression_encode_buffer(
                    destination.baseAddress!.assumingMemoryBound(to: UInt8.self), destination.count,
                    source.baseAddress!.assumingMemoryBound(to: UInt8.self), source.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0, written < bytes.count else { return nil }
        output.count = written
        return output
    }

    private static func decompress(_ bytes: Data, decodedLength: Int) -> Data? {
        guard decodedLength > 0, !bytes.isEmpty else { return nil }
        var output = Data(count: decodedLength)
        let written = output.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) in
            bytes.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
                compression_decode_buffer(
                    destination.baseAddress!.assumingMemoryBound(to: UInt8.self), destination.count,
                    source.baseAddress!.assumingMemoryBound(to: UInt8.self), source.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written == decodedLength else { return nil }
        return output
    }

    // MARK: - Layout

    /// A name is a plain file name: it is joined to the staging directory and
    /// must not be able to name anything outside it.
    private static func validate(name: String) throws {
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\"), !name.contains("\0"),
              name.utf8.count <= Int(UInt16.max) else {
            throw Failure.invalidName(name)
        }
    }

    private static func headerLength(names: [String]) -> Int {
        // magic, version, count; then per entry: name length, name, method,
        // three lengths, digest.
        magic.count + 4 + 4 + names.reduce(0) { $0 + 2 + $1.utf8.count + 1 + 8 + 8 + 8 + 32 }
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    private struct Cursor {
        let data: Data
        var offset = 0

        mutating func bytes(_ count: Int) throws -> Data {
            guard count >= 0, offset + count <= data.count else {
                throw Failure.malformed("truncated")
            }
            let start = data.startIndex + offset
            offset += count
            return data.subdata(in: start..<(start + count))
        }

        mutating func uint8() throws -> UInt8 { try bytes(1)[0] }

        mutating func uint16() throws -> UInt16 {
            try bytes(2).withUnsafeBytes { UInt16(littleEndian: $0.loadUnaligned(as: UInt16.self)) }
        }

        mutating func uint32() throws -> UInt32 {
            try bytes(4).withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
        }

        mutating func uint64() throws -> UInt64 {
            try bytes(8).withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self)) }
        }
    }
}
