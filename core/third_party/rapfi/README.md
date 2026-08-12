# Vendored Rapfi

The pinned `chentianren0/rapfi` fork, vendored as a **copied source snapshot**
and compiled into the static library `mxq::rapfi`, which `mxq_core` links
`PRIVATE`. It is the engine behind the core's second search facade — the
placement games, Gomoku and Renju — as
[`core/third_party/fairy-stockfish/`](../fairy-stockfish/README.md) is the engine
behind the first.

| | |
|---|---|
| Repository | `https://github.com/chentianren0/rapfi` |
| Revision | `265b7d66c7b57bbd8689c8dfd1efb4133e02b5ed` |
| Upstream base | `3c94c2a976f24a0dd1c5517623e9ab6fffe66bd7` (`dhbloo/rapfi`) |
| License | GPLv3 — [`upstream/Copying.txt`](upstream/Copying.txt) |

Both the revision and the repository are recorded in
[`pinned-inputs.json`](../../../pinned-inputs.json) under `gomoku_fork`, which is
the single source of truth; the table above repeats it for a reader who is
already in this directory.

## Layout

```text
core/third_party/rapfi/
├── CMakeLists.txt    # ours: builds the snapshot as mxq::rapfi
├── README.md         # ours: this file
├── SOURCES.sha256    # ours: per-file SHA-256 of everything under upstream/
└── upstream/         # a verbatim copy of the pinned revision, never edited here
```

Nothing under `upstream/` is modified. Every source change to the engine belongs
to the fork repository and arrives here only as a new snapshot at a new pinned
revision, which is what keeps the manifest's ordered patch list an accurate
description of the bytes the core compiles. The reasoning for a copied snapshot
over a submodule or a subtree merge is written out once, for both engines, in
[`../fairy-stockfish/README.md`](../fairy-stockfish/README.md#why-a-copied-snapshot),
and applies here unchanged.

### Verifying the snapshot

The snapshot is `git archive` of the pinned revision restricted to the paths
below, with the exclusions after it applied. Re-cutting it from a fork checkout
must produce byte-identical output:

```sh
git archive --format=tar 265b7d66c7b57bbd8689c8dfd1efb4133e02b5ed \
    AUTHORS Copying.txt Readme.md Rapfi \
  | tar -x -C upstream

rm -f upstream/Rapfi/main.cpp upstream/Rapfi/command/gomocup.cpp
rm -f upstream/Rapfi/command/database.cpp upstream/Rapfi/command/dataprep.cpp \
      upstream/Rapfi/command/opengen.cpp upstream/Rapfi/command/selfplay.cpp \
      upstream/Rapfi/command/tuning.cpp
rm -rf upstream/Rapfi/tuning
rm -f upstream/Rapfi/CMakeLists.txt upstream/Rapfi/CMakePresets.json
rm -rf upstream/Rapfi/emscripten
rm -f upstream/Rapfi/eval/onnxevaluator.cpp upstream/Rapfi/eval/onnxevaluator.h
rm -rf upstream/Rapfi/external/cxxopts upstream/Rapfi/external/flat.hpp \
       upstream/Rapfi/external/libnpy upstream/Rapfi/external/thread-pool \
       upstream/Rapfi/external/zip
find upstream/Rapfi/external -name CMakeLists.txt -delete
```

`SOURCES.sha256` records the SHA-256 of every file under `upstream/`, and is
checked with:

```sh
cd upstream && shasum -a 256 -c ../SOURCES.sha256
```

## What is excluded, and why

| Excluded | Reason |
|---|---|
| `Rapfi/main.cpp` | The engine's own `main()`. The core is a library; a second `main` symbol has no business in it. |
| `Rapfi/command/gomocup.cpp` | The whole piskvork/Yixin stdin protocol, in namespace `Command::GomocupProtocol`. Nothing outside that file refers to the namespace, and the core drives the engine through its C++ API instead. |
| `Rapfi/command/{database,dataprep,opengen,selfplay,tuning}.cpp`, `Rapfi/tuning/` | The command modules: offline tooling — training-data preparation, self-play, opening generation, tuning, database maintenance — that a playing embedding never calls. They are also what reaches four of the fork's externals. |
| `Rapfi/CMakeLists.txt`, `Rapfi/CMakePresets.json`, `Rapfi/external/*/CMakeLists.txt` | The fork's build system. This snapshot is built by `CMakeLists.txt` here; keeping a second, unused build description invites the two to drift. Its option and flag choices are cited in that file rather than carried. |
| `Rapfi/emscripten/` | The WebAssembly shell, which depends on Emscripten. |
| `Rapfi/eval/onnxevaluator.{cpp,h}` | The ONNX Runtime evaluator. It is opt-in behind `USE_ORT_EVALUATOR`, off by default in the fork, and would make onnxruntime a build dependency of the core. |
| `Rapfi/external/{cxxopts,flat.hpp,libnpy,thread-pool,zip}` | Reached only from inside a `COMMAND_MODULES` guard, which this build does not define. Excluding the modules excludes these with them. |
| `Gomocalc/`, `Trainer/`, `Networks/`, `.github/`, `Logo.png` | The web front end, the PyTorch training pipeline, the weights submodule and the fork's CI. The weights the core uses are committed at [`core/assets/`](../../assets/) and pinned by byte length and SHA-256, per the same rule the first engine's networks follow. |

The remainder of `Rapfi/` is kept as a unit. Nothing in it pulls in a UI
framework or a network dependency, and the source investigation on issue #164
established that none of the categories that make an engine unusable inside an
app bundle is present: no `dlopen`, no `fork`/`exec`/`popen`/`system`, no
`getenv`, no JIT, no `mprotect`, and no hand-written assembly.

Three externals survive, and one of them is required rather than convenient:
**lz4**, because every NNUE weight file is an LZ4 frame and
`Compressor::Type::LZ4_DEFAULT` is how the engine opens one. **cpptoml** parses
the engine's configuration format, and **simde** is included unconditionally by
`eval/simd/vec.h` even on NEON builds, where it maps the x86 intrinsic spellings
onto NEON.

`Rapfi/command/command.cpp` is kept and carries `CommandLine::binaryDirectory`,
which it derives from `argv[0]` and `getcwd()`. **The core never uses it.** Weight
and configuration paths reach the engine as absolute paths, so no working
directory and no executable location can substitute an asset behind the app's
back. `command/benchmark.cpp` is kept as well; it is the fork's own non-protocol
driver and the nearest thing the tree has to a worked example of embedding, and
nothing calls it here.

### One attribution note

**simde carries no `LICENSE` file in the fork's tree** — only SPDX headers, which
say MIT — so this snapshot has none to copy. The third-party notices prepared
before distribution must therefore carry simde's MIT text from its own
repository rather than from these bytes. cpptoml (MIT) and lz4 with xxhash
(BSD-2) each ship their licence file, at
[`upstream/Rapfi/external/cpptoml/LICENSE`](upstream/Rapfi/external/cpptoml/LICENSE)
and [`upstream/Rapfi/external/lz4/LICENSE`](upstream/Rapfi/external/lz4/LICENSE).

## The fork's static-library target

The fork exposes `rapfi_engine`, behind its `BUILD_ENGINE_LIBRARY` option, which
`pinned-inputs.json` records under `gomoku_fork.static_library`. The core does not
consume that artifact, for the same reason it does not consume Fairy-Stockfish's:
several architectures come out of one build system here, and the fork's build
produces one per invocation. `CMakeLists.txt` in this directory is a
**core-owned** build of the snapshot instead, compiling the fork's own library
source list — the source list here and the fork's `CORE_SOURCES` at the pinned
revision are the same set — with the fork's own options, each cited back to a
line of its `CMakeLists.txt`.

The source list here has to be maintained by hand whenever the snapshot is
re-cut. `CMakeLists.txt` fails configuration with an explicit message if a listed
source is missing, so a re-cut that drops a file is a build error rather than a
link error.

## Build switch

The engine is compiled only when `MXQ_ENABLE_GOMOKU_FACADE` is `ON`:

```sh
cmake -S core -B core/.build -G Ninja -DMXQ_ENABLE_GOMOKU_FACADE=ON
cmake --build core/.build
```

With the option `OFF`, which is the default, `core/CMakeLists.txt` does not add
this directory at all, exactly as it does not add the Fairy-Stockfish one unless
asked: neither engine is something to pay a multi-minute compile for while
working on the rest of the core.
