// The command build-core-xcframework.sh packs the engine assets with.
//
// Compiled from this file and MiniXiangqi/Core/AssetPack.swift, so that
// the format has one implementation: the one the app decodes with. It lives
// outside the Xcode project's folders deliberately — MiniXiangqi is a
// file-system-synchronized group, and a second main.swift inside it would be a
// second entry point in the app.
//
//   asset-pack-tool pack <output> (<name> <path>)...
//   asset-pack-tool list <pack>
//
// pack writes the pack atomically, then reads it back and decodes every entry
// against its recorded digest, so a pack this command reports as written is one
// the app can stage. list prints the index, for a human checking what a build
// bundled.

import Foundation

let usage = """
    usage: asset-pack-tool pack <output> (<name> <path>)...
           asset-pack-tool list <pack>
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func describe(_ entry: AssetPack.Entry) -> String {
    let method = entry.method == .zlib ? "zlib" : "stored"
    return "\(entry.name): \(entry.decodedLength) bytes, \(method) as \(entry.payloadLength)"
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail(usage) }

switch command {
case "pack":
    let rest = Array(arguments.dropFirst())
    guard rest.count >= 3, (rest.count - 1) % 2 == 0 else { fail(usage) }
    let output = URL(fileURLWithPath: rest[0])
    var inputs: [(name: String, bytes: Data)] = []
    var index = 1
    while index < rest.count {
        let name = rest[index]
        let path = rest[index + 1]
        guard let bytes = FileManager.default.contents(atPath: path) else {
            fail("cannot read \(path) for the entry \(name)")
        }
        inputs.append((name: name, bytes: bytes))
        index += 2
    }
    do {
        let pack = try AssetPack.pack(inputs)
        try pack.write(to: output, options: .atomic)
        // Read back what was written rather than what was about to be: the
        // file on disk is what ships.
        let written = try Data(contentsOf: output)
        let entries = try AssetPack.entries(in: written)
        guard entries.count == inputs.count else {
            fail("wrote \(inputs.count) entries and read back \(entries.count)")
        }
        for (entry, input) in zip(entries, inputs) {
            guard entry.name == input.name else {
                fail("wrote the entry \(input.name) and read back \(entry.name)")
            }
            guard try AssetPack.decode(entry, from: written) == input.bytes else {
                fail("the entry \(entry.name) does not decode to its input")
            }
            print(describe(entry))
        }
        print("packed \(entries.count) entries into \(output.path), \(written.count) bytes")
    } catch {
        fail("\(error)")
    }

case "list":
    guard arguments.count == 2 else { fail(usage) }
    do {
        let pack = try Data(contentsOf: URL(fileURLWithPath: arguments[1]), options: .mappedIfSafe)
        for entry in try AssetPack.entries(in: pack) {
            print(describe(entry))
        }
    } catch {
        fail("\(error)")
    }

default:
    fail(usage)
}
