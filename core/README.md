# Shared core

The C++ core and its tests, behind the stable C interface defined in
[`docs/core-interface.md`](../docs/core-interface.md).

It owns the rules facade, the search facade over the pinned Fairy-Stockfish fork,
the game-archive codec, and the SQLite library store — everything correctness-critical,
implemented once and validated by one test suite, per [`docs/architecture.md`](../docs/architecture.md).

Its tests run on every development platform without a frontend, through one shared
C++ test runner. The rules facade is gated by the approved fixtures in
[`fixtures/`](../fixtures/), which are its authority rather than engine behaviour.

Pinned third-party inputs — the fork revision and its patches, build flags, the variant
configuration, the network, and the vendored SQLite amalgamation — are recorded in the
repository's pinned-input manifest, and every hash it records is verified before packaging.

## Layout

```text
core/
├── include/mxq.h     # the complete public C interface; the single input both
│                     # bindings are generated from
├── src/              # the C++ implementation behind it
├── tests/            # the one shared C++ test runner
├── assets/           # what the engine is configured with: the bundled variant
│                     # configuration and one NNUE network per variant the core
│                     # runs, every one of them pinned by hash in the manifest
├── third_party/      # where the pinned fork and SQLite are vendored
└── CMakeLists.txt
```

## Building

```sh
cmake -S core -B core/.build -G Ninja
cmake --build core/.build
ctest --test-dir core/.build --output-on-failure
```

The runner takes `--fixtures <dir>` and `--junit <file>`, and honours
`$MXQ_FIXTURES_DIR`. It reports `PASS`, `FAIL`, `NOT IMPLEMENTED` or `ERROR` per
fixture and fails the run only on `FAIL` or `ERROR`.

That default configuration does **not** compile the vendored engine. Add
`-DMXQ_ENABLE_RULES_FACADE=ON` to build and link it; the engine is a multi-minute
compile and nothing else in the core needs it, so it is opt-in. Engine-dependent
tests also need the NNUE networks, and they need no argument: both are in
`assets/` beside the variant configuration, and configuration verifies each
one's byte length and SHA-256 against `pinned-inputs.json` before staging it.
`-DMXQ_NNUE_SOURCE=<path>` and `-DMXQ_XIANGQI_NNUE_SOURCE=<path>` override those
defaults, which is how a candidate network is tried before it is committed. A
missing or mismatched network stages nothing and the search suite FAILS with the
reason rather than skipping.

Run both configurations. `Debug` and `Release` are not the same test run: the
programming errors in `docs/core-interface.md`'s error taxonomy assert in a
debug build and return their code in a release build, so expectations about
those codes are stated under `#if defined(NDEBUG)` and only a release run
evaluates them, while only a debug run exercises the assertions themselves.

```sh
cmake -S core -B core/.build-debug -G Ninja -DCMAKE_BUILD_TYPE=Debug \
  -DMXQ_ENABLE_RULES_FACADE=ON
cmake -S core -B core/.build-release -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DMXQ_ENABLE_RULES_FACADE=ON
```

This CMake project is standalone and is deliberately not wired into the Xcode
project under [`apple/`](../apple/) yet.

## State

The boundary exists, and the pinned Fairy-Stockfish fork is vendored under
[`third_party/fairy-stockfish/`](third_party/fairy-stockfish/) and builds as a
static library the core links privately. The target variant `minixiangqiaxf`
loads from [`assets/minixiangqi-variants.ini`](assets/minixiangqi-variants.ini).

All of `mxq.h` is implemented: the status and blob helpers and the pure queries
that need no core instance (`mxq_core_version`, `mxq_core_game_profile`,
`mxq_rules_start_fen`, `mxq_archive_supported_versions`, `mxq_engine_plan`);
core lifecycle, with the SQLite library store opened at `mxq_core_init` and
the clock and identity provider the deterministic-identity flag configures;
the session-free rules facade (`mxq_rules_validate_fen`, `mxq_rules_evaluate`,
`mxq_rules_legal_moves`); the archive codec's read and write sides over the
core's own canonical-JSON reader; store-attached sessions with their
per-mutation commits; the four archiving paths that end a game; the History
read surface; the interchange pair with its import preview; and the search
facade — `mxq_engine_prepare`/`teardown`/`query` and the `mxq_search_` group
over the core's one engine thread.

Seven CTest targets: `rules_fixtures` over [`fixtures/rules/`](../fixtures/rules/),
`archive_fixtures` over [`fixtures/archive/`](../fixtures/archive/),
`store_foundation`, `store_sessions`, and `store_history` over scratch stores
(with [`fixtures/store/`](../fixtures/store/) holding their declarative
expectations), `store_interchange`, which re-runs the archive corpus through
the import pipeline, and `engine_search`, which drives real searches over real
sessions. Everything that replays a move line through the engine —
`mxq_rules_evaluate` and its relatives, `mxq_archive_validate`, every
`mxq_game_` function, `mxq_store_import`, and everything in the `mxq_engine_`
and `mxq_search_` groups that drives the engine — exists only in a build configured
with `-DMXQ_ENABLE_RULES_FACADE=ON`; without it they are absent from the library
rather than stubbed, and the expectations that need them report
`NOT IMPLEMENTED`, which is never counted as a pass.
