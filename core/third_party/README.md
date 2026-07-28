# Vendored third-party inputs

Nothing is vendored here yet. This directory is the slot, and `core/CMakeLists.txt`
already looks in it, so vendoring either input is an addition rather than a
rearrangement.

The core depends on Fairy-Stockfish and SQLite as internal, replaceable
components, and neither is visible through `mxq.h` — `core/CMakeLists.txt` links
both `PRIVATE` for exactly that reason, per
[`docs/architecture.md`](../../docs/architecture.md).

## Where each one goes

| Input | Directory | Target the directory must define |
|---|---|---|
| The pinned `ppppvz/Fairy-Stockfish` fork | `core/third_party/fairy-stockfish/` | `mxq::fairy-stockfish` |
| The SQLite amalgamation | `core/third_party/sqlite/` | `mxq::sqlite` |

Each directory carries its own `CMakeLists.txt` defining that alias. The loop at
the end of the library section of `core/CMakeLists.txt` adds the subdirectory and
links the alias into `mxq_core` when — and only when — the `CMakeLists.txt` is
present, so an unvendored tree still configures and builds.

## What each one must satisfy

Both are pinned by [`pinned-inputs.json`](../../pinned-inputs.json) at the
repository root, which is the single source of truth for the fork's repository
and revision, the ordered patch list, the per-platform build flags, the variant
configuration, the network, and the SQLite version. The build must verify every
hash in that manifest before packaging and fail on a mismatch rather than ship
unverified bytes; that verification belongs in the packaging step, alongside
whichever target copies the assets into the bundle, and does not exist yet.

- **Fairy-Stockfish.** The fork must expose a **static library** target, which
  the core links; its Makefile currently produces an executable and a Python
  module, neither of which the core can consume. That target is an accepted but
  unlanded fork change, recorded in the manifest under
  `fork.patches_pending/static-library-target`. Its implementation, tests, and
  upstream maintenance belong to the fork repository, not here.
- **SQLite.** Vendored as the amalgamation, compiled with the hardened option
  set and without extension loading, per
  [`docs/game-data.md`](../../docs/game-data.md), with a floor of 3.37.0 for
  `STRICT` tables. The concrete define list is not yet established and the
  manifest records it as empty rather than guessed.

## Assets

The bundled variant configuration and the NNUE network are packaging inputs
rather than build inputs, and neither belongs in this directory. The repository
never contains the network's bytes in any form; they enter a build from a
workspace- or CI-provided location, verified against the byte length and SHA-256
in the manifest.
