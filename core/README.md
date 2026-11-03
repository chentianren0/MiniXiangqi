# Core

The C++ core behind the app: rules, notation, the Jieqi deal, engine preparation and search, behind the C interface in `include/mxq.h`. It is stateless: the app keeps the games, in SwiftData. It is a local Swift package, `Package.swift`, which Xcode builds with the app; the app imports it as `MiniXiangqiCore` with Swift's C++ interoperability.

- `src/` and `include/` — the facade, the `MiniXiangqiCore` target.
- `engines/` — the three engine snapshots, one target each: Fairy-Stockfish for Mini Xiangqi and Xiangqi, the Pikafish rules slice for Jieqi, and Rapfi with its lz4 for Gomoku and Renju. Each README names the fork, the pinned revision and the patches. Nothing under an `upstream/` directory is edited here; a change to an engine lands in its fork and arrives as a new snapshot.
- `assets/` — the variant configuration and the networks. The app's "Seal the engine assets" build phase compresses and seals them into the bundle, and the app opens them into its caches at launch; `MiniXiangqi/Core/EngineAssets.swift` says why.
- `tests/` — the package's Swift Testing suite, over the fixtures in [`fixtures/rules`](../fixtures/rules/) and the engines' edge cases.

Run the tests with `swift test` here, or open `Package.swift` in Xcode and run its tests.
