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
