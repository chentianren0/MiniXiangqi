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

The implemented C functions are still only the ones the contract marks callable
from any thread without a core instance — the status and blob helpers,
`mxq_core_version`, `mxq_rules_start_fen`, `mxq_archive_supported_versions`, and
`mxq_engine_plan`, whose arithmetic the contract defines precisely so that every
budget boundary is testable without an engine. The rest of `mxq.h` is declared
and deliberately not stubbed: the accepted error taxonomy has no
not-implemented code, and inventing one to return would be inventing contract
vocabulary. Until the rules facade's own entry points exist — `mxq_core_init`,
`mxq_rules_evaluate`, `mxq_rules_legal_moves` — every fixture reports
`NOT IMPLEMENTED`, with or without the engine.
