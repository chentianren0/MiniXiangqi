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
├── assets/           # minixiangqi-variants.ini, the bundled variant configuration
├── third_party/      # where the pinned fork and SQLite are vendored
├── tools/            # temporary: the engine probe, deleted when the facade lands
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
compile and nothing else in the core needs it, so it is opt-in.

This CMake project is standalone and is deliberately not wired into the Xcode
project under [`apple/`](../apple/) yet.

## State

The boundary exists, and the pinned Fairy-Stockfish fork is vendored under
[`third_party/fairy-stockfish/`](third_party/fairy-stockfish/) and builds as a
static library the core links privately. The target variant `minixiangqiaxf`
loads from [`assets/minixiangqi-variants.ini`](assets/minixiangqi-variants.ini).

Implemented so far: the status and blob helpers and the pure queries that need
no core instance (`mxq_core_version`, `mxq_rules_start_fen`,
`mxq_archive_supported_versions`, `mxq_engine_plan`); core lifecycle, with the
SQLite library store opened at `mxq_core_init` and the clock and identity
provider the deterministic-identity flag configures; the session-free rules
facade (`mxq_rules_validate_fen`, `mxq_rules_evaluate`, `mxq_rules_legal_moves`);
the archive codec's read and write sides over the core's own canonical-JSON
reader; store-attached sessions with their per-mutation commits; the four
archiving paths that end a game; the History read surface; and the interchange
pair with its import preview.

The rest of `mxq.h` — the search facade — is declared and deliberately not
stubbed: the accepted error taxonomy has no not-implemented code, and inventing
one to return would be inventing contract vocabulary.

Six CTest targets: `rules_fixtures` over [`fixtures/rules/`](../fixtures/rules/),
`store_foundation`, `archive_fixtures` over
[`fixtures/archive/`](../fixtures/archive/), `store_sessions` and `store_history`
over [`fixtures/store/`](../fixtures/store/), and `store_interchange`, which
re-runs the archive corpus through the import pipeline. Everything that replays a
move line through the engine — `mxq_rules_evaluate` and its relatives,
`mxq_archive_validate`, every `mxq_game_` function, and `mxq_store_import` —
exists only in a build configured with `-DMXQ_ENABLE_RULES_FACADE=ON`; without it
they are absent from the library rather than stubbed, and the expectations that
need them report `NOT IMPLEMENTED`, which is never counted as a pass.
