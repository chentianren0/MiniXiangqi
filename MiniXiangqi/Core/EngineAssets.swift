// The engine assets the core reads: the variant configuration and the networks
// under core/assets.
//
// Three of the networks are published files that other apps embedding the same
// engines ship byte for byte, and App Review compares binaries across
// developers, so the bundle must not carry them as they are. The build phase
// "Seal the engine assets" compiles this file with SEAL_ENGINE_ASSETS and runs
// it over core/assets: each file is compressed with LZFSE and sealed with
// AES-GCM under a key derived from the bundle identifier. That is not secrecy,
// since the derivation is here; it changes the bytes the bundle carries and
// authenticates what the app opens. At launch the app opens them into its
// caches and hands the core that directory.

import Compression
import CryptoKit
import Foundation

nonisolated enum EngineAssets {
    /// The folder of sealed assets in the bundle's resources.
    static let folder = "EngineAssets"

    static func key(bundleIdentifier: String) -> SymmetricKey {
        SymmetricKey(data: SHA256.hash(data: Data(bundleIdentifier.utf8)))
    }

    static func seal(_ data: Data, key: SymmetricKey) throws -> Data {
        guard let sealed = try AES.GCM.seal(filter(.compress, data), using: key).combined else {
            throw CocoaError(.coderInvalidValue)
        }
        return sealed
    }

    static func open(_ sealed: Data, key: SymmetricKey) throws -> Data {
        try filter(.decompress, AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key))
    }

    private static func filter(_ operation: FilterOperation, _ data: Data) throws -> Data {
        var output = Data()
        let filter = try OutputFilter(operation, using: .lzfse) { output.append($0 ?? Data()) }
        try filter.write(data)
        try filter.finalize()
        return output
    }

    /// The opened assets in the app's caches, opened from the bundle first when
    /// the caches do not hold this bundle's whole set. The set is named by the
    /// sealed files' authentication tags, so a bundle with different assets
    /// opens afresh, and the system may purge the caches at any time.
    static func directory(in bundle: Bundle = .main) throws -> URL {
        guard let identifier = bundle.bundleIdentifier,
              let resources = bundle.resourceURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        let files = FileManager.default
        let sealed = try files.contentsOfDirectory(
            at: resources.appending(path: folder, directoryHint: .isDirectory),
            includingPropertiesForKeys: nil
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }

        var tags = Data()
        for url in sealed {
            tags.append(try Data(contentsOf: url, options: .alwaysMapped).suffix(16))
        }
        let name = folder + "-" + SHA256.hash(data: tags).prefix(8)
            .map { String(format: "%02x", $0) }.joined()
        let caches = files.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let opened = caches.appending(path: name, directoryHint: .isDirectory)
        if let present = try? files.contentsOfDirectory(atPath: opened.path),
           Set(present) == Set(sealed.map(\.lastPathComponent)) {
            return opened
        }

        for stale in try files.contentsOfDirectory(atPath: caches.path) where stale.hasPrefix(folder) {
            try files.removeItem(at: caches.appending(path: stale))
        }
        let partial = caches.appending(path: name + ".partial", directoryHint: .isDirectory)
        try files.createDirectory(at: partial, withIntermediateDirectories: true)
        let key = key(bundleIdentifier: identifier)
        for url in sealed {
            try open(Data(contentsOf: url, options: .alwaysMapped), key: key)
                .write(to: partial.appending(path: url.lastPathComponent))
        }
        try files.moveItem(at: partial, to: opened)
        return opened
    }
}

#if SEAL_ENGINE_ASSETS
/// Run by the build phase, whose declared inputs after this file are the
/// assets and whose first declared output is the folder they are sealed into.
@main
enum SealEngineAssets {
    static func main() throws {
        let environment = ProcessInfo.processInfo.environment
        let count = Int(environment["SCRIPT_INPUT_FILE_COUNT"] ?? "") ?? 0
        let inputs = (1..<max(count, 1)).compactMap { environment["SCRIPT_INPUT_FILE_\($0)"] }
        let output = URL(filePath: environment["SCRIPT_OUTPUT_FILE_0"] ?? "", directoryHint: .isDirectory)
        let key = EngineAssets.key(bundleIdentifier: environment["PRODUCT_BUNDLE_IDENTIFIER"] ?? "")
        let files = FileManager.default
        try? files.removeItem(at: output)
        try files.createDirectory(at: output, withIntermediateDirectories: true)
        for input in inputs.map({ URL(filePath: $0) }) {
            let sealed = try EngineAssets.seal(Data(contentsOf: input), key: key)
            try sealed.write(to: output.appending(path: input.lastPathComponent))
        }
    }
}
#endif
