// swift-tools-version: 6.2

import PackageDescription

// Each engine is built with the defines and flags of its own build at the
// pinned revision, for Apple silicon: popcount and NEON, no SSE.

// Everything that includes a Fairy-Stockfish header must agree on these:
// LARGEBOARDS changes the width of a Bitboard and registers built-in xiangqi.
// Without PRECOMPUTED_MAGICS the engine searches for its large-board magic
// numbers at start-up, which takes over a minute.
let fairyStockfishDefines: [CXXSetting] = [
    .define("LARGEBOARDS"),
    .define("PRECOMPUTED_MAGICS"),
    .define("NNUE_EMBEDDING_OFF"),
    .define("IS_64BIT"),
    .define("USE_POPCNT"),
    .define("USE_NEON"),
]

let rapfiDefines: [CXXSetting] = [
    .define("MULTI_THREADING"),
    .define("USE_NEON"),
]

// The core has always shipped built this way, whatever the app's
// configuration: optimised, and with assertions off, because the facade's
// assertions mark caller errors it also answers with a status.
let release: [CXXSetting] = [.define("NDEBUG")]

// Optimised in every configuration, and silent: the snapshots are upstream's,
// and their warnings are upstream's to fix.
let engineFlags = ["-O3", "-w"]

// The engines are C++17 and the facade is C++20; the engines' headers do
// arithmetic on mixed enums, which C++20 deprecates.
let engineHeadersUnderCxx20: [String] = [
    "-Wno-deprecated-enum-enum-conversion",
    "-Wno-deprecated-anon-enum-enum-conversion",
]

let package = Package(
    name: "MiniXiangqiCore",
    platforms: [.iOS("27.2"), .macOS("27.2")],
    products: [
        .library(name: "MiniXiangqiCore", targets: ["MiniXiangqiCore"]),
    ],
    targets: [
        .target(
            name: "FairyStockfish",
            path: "engines/fairy-stockfish",
            exclude: ["README.md", "upstream/AUTHORS", "upstream/Copying.txt", "upstream/README.md",
                      "upstream/Top CPU Contributors.txt", "upstream/src/incbin/UNLICENCE"],
            sources: ["upstream/src"],
            publicHeadersPath: "upstream/src",
            cxxSettings: fairyStockfishDefines + release + [
                .unsafeFlags(["-std=c++17", "-fno-exceptions"] + engineFlags),
            ]
        ),
        // The slice declares namespace Stockfish, as Fairy-Stockfish does, so
        // it is renamed wholesale. The jieqi bridge is compiled here to share
        // the rename, and catches allocation failures, so this target keeps
        // exceptions on.
        .target(
            name: "PikafishJieqi",
            path: "engines/pikafish",
            exclude: ["README.md", "upstream/AUTHORS", "upstream/Copying.txt", "upstream/README.md",
                      "upstream/Top CPU Contributors.txt"],
            sources: ["upstream/src", "mxq_pikafish_link_closure.cpp", "mxq_jieqi_bridge.cpp"],
            cxxSettings: release + [
                .define("Stockfish", to: "PikafishJieqi"),
                .define("NO_PREFETCH"),
                .define("IS_64BIT"),
                .define("USE_POPCNT"),
                .headerSearchPath("upstream/src"),
                .headerSearchPath("../../include"),
                .unsafeFlags(["-std=c++17", "-O3"]),
            ]
        ),
        // Rapfi with the lz4 it decompresses its weights with. Floating-point
        // contraction stays off, as in the fork: the network's value head
        // finishes in float, and a fused multiply-add there changes the search.
        .target(
            name: "Rapfi",
            path: "engines/rapfi",
            exclude: ["README.md", "upstream/AUTHORS", "upstream/Copying.txt", "upstream/Readme.md",
                      "upstream/Rapfi/external/cpptoml/LICENSE", "upstream/Rapfi/external/lz4/LICENSE"],
            sources: ["upstream/Rapfi"],
            publicHeadersPath: "upstream/Rapfi",
            cSettings: [.define("NDEBUG"), .unsafeFlags(engineFlags)],
            cxxSettings: rapfiDefines + release + [
                .headerSearchPath("upstream/Rapfi/external/cpptoml/include"),
                .headerSearchPath("upstream/Rapfi/external/simde/include"),
                .headerSearchPath("upstream/Rapfi/external/lz4/include"),
                .unsafeFlags(["-std=c++17", "-ffp-contract=off"] + engineFlags),
            ]
        ),
        // The facade: the C interface in include/mxq.h, over the engines.
        .target(
            name: "MiniXiangqiCore",
            dependencies: ["FairyStockfish", "PikafishJieqi", "Rapfi"],
            path: ".",
            exclude: ["README.md", "assets", "engines", "tests"],
            sources: ["src", "include"],
            publicHeadersPath: "include",
            cxxSettings: fairyStockfishDefines + rapfiDefines + release + [
                .headerSearchPath("engines/rapfi/upstream/Rapfi/external/cpptoml/include"),
                .headerSearchPath("engines/rapfi/upstream/Rapfi/external/simde/include"),
                .headerSearchPath("engines/rapfi/upstream/Rapfi/external/lz4/include"),
                .unsafeFlags(engineHeadersUnderCxx20),
            ],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "MiniXiangqiCoreTests",
            dependencies: ["MiniXiangqiCore"],
            path: "tests",
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
    ],
    cxxLanguageStandard: .cxx20
)
