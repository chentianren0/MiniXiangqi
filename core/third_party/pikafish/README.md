# Vendored Pikafish, the jieqi rules slice

The pinned `chentianren0/Pikafish` fork's jieqi branch, vendored as a **copied
source snapshot of three translation units and their header closure** and
compiled into the static library `mxq::pikafish`. It is the rules authority for
jieqi — xiangqi played with the pieces face down — as
[`core/third_party/fairy-stockfish/`](../fairy-stockfish/README.md) is the rules
authority for Mini Xiangqi and Xiangqi, and
[`core/third_party/rapfi/`](../rapfi/README.md) is for the placement games.

| | |
|---|---|
| Repository | `https://github.com/chentianren0/Pikafish` |
| Branch | `jieqi-mxq` |
| Revision | `b0595bb2d6b14cad000278af1f5bbaba524a5870` |
| Committed | 2026-08-16T12:40:09-07:00 |
| Upstream base | `9b963f727983a1d9308e0dca48b39c802b8e75a2` (`official-pikafish/Pikafish`, branch `jieqi`) |
| License | GPLv3 — [`upstream/Copying.txt`](upstream/Copying.txt) |

Both the revision and the repository are recorded in
[`pinned-inputs.json`](../../../pinned-inputs.json) under `jieqi_fork`, which is
the single source of truth; the table above repeats it for a reader who is
already in this directory.

**The vendored sources are the patched ones.** The pinned revision is the
upstream jieqi branch plus one fork change, `report-the-rule`, which adds an
optional out-parameter to `Position::rule_judge` naming which rule produced its
value. It touches `src/position.cpp`, `src/position.h` and `src/types.h`, all
three of which are in this snapshot, so what the core compiles is the patched
engine and not the upstream one.

## Layout

```text
core/third_party/pikafish/
├── CMakeLists.txt                   # ours: builds the slice as mxq::pikafish
├── README.md                        # ours: this file
├── SOURCES.sha256                   # ours: per-file SHA-256 of everything under upstream/
├── mxq_pikafish_link_closure.cpp    # ours: the three definitions the slice does not carry
└── upstream/                        # a verbatim copy of the pinned revision, never edited here
```

Nothing under `upstream/` is modified. Every source change to the engine belongs
to the fork repository and arrives here only as a new snapshot at a new pinned
revision, which is what keeps the manifest's patch list an accurate description
of the bytes the core compiles. The reasoning for a copied snapshot over a
submodule or a subtree merge is written out once, for every engine, in
[`../fairy-stockfish/README.md`](../fairy-stockfish/README.md#why-a-copied-snapshot),
and applies here unchanged.

## What is vendored: three translation units and their header closure

This snapshot is a **selection**, and that is the difference from the other two
engines' snapshots, which take their fork's source tree whole and drop a short
list of files from it. Here the fork's twenty-two engine translation units —
thirty-four counting the bundled zstd — become three:

| Vendored | What it is |
|---|---|
| `src/position.cpp` | The position: FEN, `do_move`/`undo_move`, legality, check and the repetition and chase adjudication `rule_judge` reports. |
| `src/movegen.cpp` | The move generator, including `MoveList<LEGAL>`. |
| `src/bitboard.cpp` | The attack tables `Bitboards::init` fills. |

plus the thirty-one headers those three reach, transitively, which
`SOURCES.sha256` lists in full. Nothing else compiles: no search, no evaluation,
no NNUE translation unit, no UCI or protocol handling, no thread pool, no
transposition table, no benchmark, and no `main()`. The slice is thread-free and
evaluation-free, and it is bootstrapped with `Bitboards::init()` followed by
`Position::init()`.

The header closure is wider than the code that runs, and deliberately so.
`position.h` includes `nnue/features/half_ka_v2_hm.h` for the accumulator field
it declares, which pulls the NNUE architecture and layer headers in behind it.
Those headers are here because a header the slice includes has to be present;
none of their code is instantiated, and no `nnue/*.cpp` is in the snapshot.

### `src/external/` is not vendored at all

The fork bundles zstd — thirty-five files under `src/external/` — to decompress
its network files. Exactly one non-external file reaches it, `src/misc.cpp` at
line 37, and `misc.cpp` is not in this slice. So the compression library is
absent rather than excluded-but-present, and there is no third-party licence
obligation from it in this snapshot.

### What is excluded, and why

| Excluded | Reason |
|---|---|
| `src/search.cpp`, `src/movepick.cpp`, `src/evaluate.cpp`, `src/thread.cpp`, `src/tt.cpp`, `src/timeman.cpp`, `src/engine.cpp`, `src/score.cpp`, `src/benchmark.cpp`, `src/tune.cpp` | The search and evaluation half. The core has an engine for playing xiangqi already; what it does not have is a rules authority for jieqi, and that is all this vendoring is for. |
| `src/nnue/*.cpp` | NNUE evaluation. Nothing here evaluates a position, so no network is loaded, bundled or pinned for this engine — which is the one respect in which this vendoring is simpler than either of the others. |
| `src/uci.cpp`, `src/ucioption.cpp` | The UCI protocol and the option table. The core drives engines through C++ APIs and never through a text protocol. |
| `src/main.cpp` | The engine's own `main()`. The core is a library; a second `main` symbol has no business in it. |
| `src/misc.cpp`, `src/memory.cpp` | Large-page allocation, the command line, the logger, and the zstd call above. The slice needs one function out of `misc.cpp` and it is supplied instead — see below. |
| `src/external/` | zstd, reached only from `misc.cpp`. |
| `src/Makefile` | The fork's build system. This snapshot is built by `CMakeLists.txt` here; keeping a second, unused build description invites the two to drift. Its flag choices are cited in that file rather than carried. |
| `scripts/`, `tests/`, `.github/`, `CITATION.cff`, `CONTRIBUTING.md`, `.clang-format` | The fork's tooling, test suite and CI. They belong to the fork repository, which owns running them. |

### The three definitions the slice references and does not carry

Taking three of a program's translation units leaves references into the ones
not taken. Exactly three survive, they were read off the compiled objects rather
than predicted, and
[`mxq_pikafish_link_closure.cpp`](mxq_pikafish_link_closure.cpp) defines them:

| Symbol | Declared in | The fork defines it in |
|---|---|---|
| `prefetch(const void*)` | `upstream/src/misc.h` | `src/misc.cpp` |
| `UCIEngine::square(Square)` | `upstream/src/uci.h` | `src/uci.cpp` |
| `TranspositionTable::first_entry(Key) const` | `upstream/src/tt.h` | `src/tt.cpp` |

None of the three is a placeholder, and that file says why each body is the
right one for a slice with no search. They are defined in this target rather
than left for a consumer, so that the archive shipped inside
`MiniXiangqiCore.xcframework` is complete: an archive with undefined symbols
links correctly only for as long as nothing pulls its members in wholesale.

Two consequences bind every future consumer. A consumer must never define one
of these three symbols itself: the failure is silent, not a duplicate-symbol
error — the archive member holding our body is simply never pulled in and the
consumer's body wins — so a different body belongs in
[`mxq_pikafish_link_closure.cpp`](mxq_pikafish_link_closure.cpp) or nowhere.
And a consumer that speaks this engine's types needs the renamed namespace and
this directory's include path, which `mxq_core` deliberately withholds through
`$<LINK_ONLY:...>` so that the Fairy-Stockfish bridge can never bind here. The
shape that follows is the one the core's jieqi bridge takes: a small library of
its own, `mxq_jieqi_bridge`, that links `mxq::pikafish` normally and is itself
held by `mxq_core` behind `LINK_ONLY` — never the removal of `LINK_ONLY`, which
would put this engine's rename on translation units that speak to the other
one.

The price of them is stated plainly, because it is the price of leaving
`upstream/` verbatim. A three-line patch to `position.cpp` would remove all
three references, and it is deliberately not applied: a patch is a fork change,
it belongs to the fork repository, and carrying one here would make the snapshot
something other than a copy.

### Verifying the snapshot

The snapshot is `git archive` of the pinned revision restricted to the paths
below — the four attribution files, then the three translation units, then the
header closure. Re-cutting it from a fork checkout must produce byte-identical
output:

```sh
git archive --format=tar b0595bb2d6b14cad000278af1f5bbaba524a5870 \
    AUTHORS Copying.txt README.md 'Top CPU Contributors.txt' \
    src/bitboard.cpp src/bitboard.h src/engine.h src/history.h src/magics.h \
    src/memory.h src/misc.h src/movegen.cpp src/movegen.h src/numa.h \
    src/position.cpp src/position.h src/score.h src/search.h src/thread.h \
    src/thread_win32_osx.h src/timeman.h src/tt.h src/tune.h src/types.h \
    src/uci.h src/ucioption.h \
    src/nnue/network.h src/nnue/nnue_accumulator.h src/nnue/nnue_architecture.h \
    src/nnue/nnue_common.h src/nnue/nnue_feature_transformer.h \
    src/nnue/nnue_misc.h src/nnue/simd.h \
    src/nnue/features/half_ka_v2_hm.h \
    src/nnue/layers/affine_transform.h src/nnue/layers/affine_transform_sparse_input.h \
    src/nnue/layers/clipped_relu.h src/nnue/layers/sqr_clipped_relu.h \
  | tar -x -C upstream
```

`SOURCES.sha256` records the SHA-256 of every file under `upstream/`, and is
checked with:

```sh
cd upstream && shasum -a 256 -c ../SOURCES.sha256
```

The path list above is the closure as the compiler computes it, not as anyone
remembers it. Regenerate it after a fork revision that adds an `#include` with:

```sh
cd upstream/src && c++ -std=c++17 -MM position.cpp movegen.cpp bitboard.cpp
```

`CMakeLists.txt` stops configuration with an explicit message if one of the
three translation units is missing, so a re-cut that drops a source is a
configuration error rather than a link error. A missing **header** is a compile
error naming the file, which is loud enough on its own.

## The namespace rename

The Pikafish target is compiled with `-DStockfish=PikafishJieqi`, applied
`PUBLIC` so that every consumer agrees with the library. This is not a
precaution; it is what makes two Stockfish-family engines in one binary
possible at all, and `CMakeLists.txt` carries the full reasoning beside the
line that does it. In short: both engines declare the same namespace and the
same class and function names, two static archives with identical strong
symbols link without complaint, and link order then decides which engine's body
runs. The failure mode is silent wrong-engine binding rather than a link error.

The rename moves symbol names and nothing else. Each of the three objects
compiled with and without the define has the same section sizes and the same
`__text` bytes.

`core/tests/mxq_pikafish_tests.cpp` is the standing proof: it initialises both
engines' tables in one process and asks each for an answer only it can give.

## The fork's static-library target

The fork exposes none, and none is asked of it. The other two engines' contracts
require their forks to publish a static-library target because the core embeds
whole engines there; here the core embeds three files, and a library target
built from the fork's full source list would be the wrong artifact. What this
directory's `CMakeLists.txt` is instead is a **core-owned** build of the
snapshot, compiling the three sources with the fork's own flags, each cited back
to a line of its `src/Makefile` at the pinned revision.

## Build switch, and what consumes this

The slice is compiled only when `MXQ_ENABLE_RULES_FACADE` is `ON`:

```sh
cmake -S core -B core/.build -G Ninja -DMXQ_ENABLE_RULES_FACADE=ON
cmake --build core/.build
```

It shares the first engine's switch rather than taking one of its own, which is
a departure from the second engine's precedent and is argued at that switch's
declaration in [`../../CMakeLists.txt`](../../CMakeLists.txt).

`mxq_core` links this library, so it travels into
`MiniXiangqiCore.xcframework`. What calls it is `core/src/mxq_jieqi_bridge.cpp`,
the core's one translation unit that speaks this engine's types: it composes the
engine's own position dialect from the record `docs/jieqi-rules.md` freezes,
applies each ply as a move and a flip, and translates the legal moves, the check
state and the adjudication back. Everything above it speaks `mxq_` types and
never learns which engine answered. The smoke-test runner beside it drives both
embedded engines in one process and is the standing proof of the rename.
