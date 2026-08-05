# Vendored third-party inputs

The core depends on Fairy-Stockfish and SQLite as internal, replaceable
components, and neither is visible through `mxq.h` — `core/CMakeLists.txt` links
both `PRIVATE` for exactly that reason, per
[`docs/architecture.md`](../../docs/architecture.md).

## What is here

| Input | Directory | Target the directory defines | State |
|---|---|---|---|
| The pinned `chentianren0/Fairy-Stockfish` fork | `core/third_party/fairy-stockfish/` | `mxq::fairy-stockfish` | Vendored — see its [README](fairy-stockfish/README.md) |
| The SQLite amalgamation | `core/third_party/sqlite/` | `mxq::sqlite` | Vendored — see its [README](sqlite/README.md) |

Each directory carries its own `CMakeLists.txt` defining that alias. The loop at
the end of the library section of `core/CMakeLists.txt` adds the subdirectory and
links the alias into `mxq_core` when the `CMakeLists.txt` is present, so an
unvendored tree still configures and builds.

The Fairy-Stockfish directory is additionally gated on `MXQ_ENABLE_RULES_FACADE`,
which is `OFF` by default: the engine is a multi-minute compile and nothing else
in the core needs it, so the default configuration does not add the subdirectory
at all.

```sh
cmake -S core -B core/.build -G Ninja                                # no engine
cmake -S core -B core/.build -G Ninja -DMXQ_ENABLE_RULES_FACADE=ON   # engine
```

## What each one must satisfy

Both are pinned by [`pinned-inputs.json`](../../pinned-inputs.json) at the
repository root, which is the single source of truth for the fork's repository
and revision, the ordered patch list, the per-platform build flags, the variant
configuration, the network, and the SQLite version. The build must verify every
hash in that manifest before packaging and fail on a mismatch rather than ship
unverified bytes. That verification belongs beside whichever target copies the
assets into the bundle, and that is where it is: `core/CMakeLists.txt` stages the
variant configuration and the network only after checking both against the
manifest, and the Windows packaging build — `windows/package-zip.ps1`, the first
one on any platform — ships that verified staging rather than making a second
uncontrolled copy of it.

- **Fairy-Stockfish.** Vendored as a copied source snapshot of the pinned
  revision, built by a core-owned `CMakeLists.txt`. The contract requires the
  **fork** to expose a static-library target, which landed at `86dad87e`. The
  core does not consume its artifact — it needs two architectures from one build
  system — and what it does instead, with what would change if it switched, is
  written down in
  [`fairy-stockfish/README.md`](fairy-stockfish/README.md). Its implementation,
  tests, and upstream maintenance belong to the fork repository, not here.
- **SQLite.** Vendored as the amalgamation, compiled with the hardened option
  set and without extension loading, per
  [`docs/game-data.md`](../../docs/game-data.md), with a floor of 3.37.0 for
  `STRICT` tables. The concrete define list is decided and annotated in
  [`sqlite/CMakeLists.txt`](sqlite/CMakeLists.txt) and recorded in the
  manifest's `sqlite_defines` arrays; the connection-level pragmas the same
  contract requires are applied and verified at open in
  `core/src/mxq_store.cpp`.

## Assets

The bundled variant configuration and the NNUE networks are packaging inputs
rather than build inputs, and none of them belongs in this directory. They live
in [`core/assets/`](../assets/) — the variant configuration, and one network for
each variant the core runs — and every consumer verifies a network against the
byte length and SHA-256 the manifest pins for that variant before staging it.
