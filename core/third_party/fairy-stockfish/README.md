# Vendored Fairy-Stockfish

The pinned `ppppvz/Fairy-Stockfish` fork, vendored as a **copied source snapshot**
and compiled into the static library `mxq::fairy-stockfish`, which `mxq_core`
links `PRIVATE`.

| | |
|---|---|
| Repository | `https://github.com/ppppvz/Fairy-Stockfish` |
| Revision | `d3b4ba2e198fe25891a1c3af8ff90b5710c2539e` |
| Committed | 2026-08-01T19:33:35-07:00 |
| Upstream base | `c19b5f6c66894fdb0e88d0dd100e3885f744760a` |
| License | GPLv3 — [`upstream/Copying.txt`](upstream/Copying.txt) |

Both the revision and the repository are recorded in
[`pinned-inputs.json`](../../../pinned-inputs.json) under `fork`, which is the
single source of truth; the table above repeats it for a reader who is already
in this directory.

## Layout

```text
core/third_party/fairy-stockfish/
├── CMakeLists.txt    # ours: builds the snapshot as mxq::fairy-stockfish
├── README.md         # ours: this file
├── SOURCES.sha256    # ours: per-file SHA-256 of everything under upstream/
└── upstream/         # a verbatim copy of the pinned revision, never edited here
```

Nothing under `upstream/` is modified. Every source change to the engine belongs
to the fork repository and arrives here only as a new snapshot at a new pinned
revision, which is what keeps the manifest's ordered patch list an accurate
description of the bytes the core compiles.

## Why a copied snapshot

The two accepted requirements are that a build is reproducible from the pinned
inputs and that the core embeds the engine as an **in-process library**
([`docs/architecture.md`](../../../docs/architecture.md),
[`docs/engine-integration.md`](../../../docs/engine-integration.md)). All three
candidate mechanisms embed the engine in-process; they differ in what
reproducibility costs.

- **A submodule** pins by commit, but the pin then lives in two places — the
  gitlink and `pinned-inputs.json` — which can disagree with each other while
  both look authoritative. It also makes a checkout insufficient: the build
  needs network access and the fork's remote to still exist and still carry that
  commit. The product must build offline, and a GPLv3 corresponding-source offer
  is far weaker when the corresponding source is a URL rather than bytes we hold.
- **A subtree merge** would graft the fork's entire history into the product
  repository. The fork owns its history; interleaving it with the product's
  makes both harder to read for no gain here.
- **A copied snapshot** is self-contained, works offline, carries the GPLv3
  sources we are obliged to be able to supply, and leaves exactly one place —
  the manifest — where the revision is recorded. Its one real cost is that
  "which revision is this?" is not answerable from git metadata, which
  `SOURCES.sha256` and the manifest together answer instead.

### Verifying the snapshot

The snapshot is exactly `git archive` of the pinned revision, restricted to the
paths below. Re-cutting it from a fork checkout must produce byte-identical
output:

```sh
git archive --format=tar d3b4ba2e198fe25891a1c3af8ff90b5710c2539e \
    AUTHORS Copying.txt README.md 'Top CPU Contributors.txt' src \
  | tar -x -C upstream
rm -f upstream/src/main.cpp upstream/src/pyffish.cpp upstream/src/ffishjs.cpp \
      upstream/src/Makefile upstream/src/Makefile_js upstream/src/variants.ini
```

`SOURCES.sha256` records the SHA-256 of every file under `upstream/`, and is
checked with:

```sh
cd upstream && shasum -a 256 -c ../SOURCES.sha256
```

## What is excluded, and why

| Excluded | Reason |
|---|---|
| `src/main.cpp` | The engine's own `main()`. The core is a library; a second `main` symbol has no business in it. |
| `src/pyffish.cpp`, `setup.py`, `pyffish.pyi`, `MANIFEST.in` | The Python bindings. They `#include <Python.h>` and would make CPython a build dependency of the core. |
| `src/ffishjs.cpp`, `src/Makefile_js` | The JavaScript/WebAssembly bindings, which depend on Emscripten. |
| `src/Makefile` | The fork's build system. This snapshot is built by `CMakeLists.txt` here; keeping a second, unused build description invites the two to drift. Its flag choices are cited in that file rather than carried. |
| `src/variants.ini` | The fork's sample variant configuration. The product's own configuration is [`core/assets/minixiangqi-variants.ini`](../../assets/minixiangqi-variants.ini); shipping two `.ini` files, only one of which is loaded, is a trap. |
| `tests/`, `.github/`, `appveyor.yml`, `test.py` | The fork's own test suite and CI. They belong to the fork repository, which owns running them. |

The remainder of `src/` is kept as a unit. Nothing in it pulls in a UI framework
or a network dependency. The platform headers it reaches for are `<windows.h>`
in three places — `misc.cpp`, for large-page allocation and thread affinity;
`syzygy/tbprobe.cpp`, for memory-mapped tablebase files; and
`thread_win32_osx.h`, for the MSVC thread creation that gives search threads
their 64 MiB stack — plus `<pthread.h>` and `<process.h>` in that same header,
which do the same job on the other platforms. There is no socket, HTTP or TLS
code anywhere in the snapshot.

Two files are protocol handlers over standard input and output rather than
engine logic — `uci.cpp` (`UCI::loop`) and `xboard.cpp` — and neither is a UI or
a network dependency. They stay because the engine's option table, move parsing
and variant initialisation live alongside them in `uci.cpp` and `ucioption.cpp`,
and separating them would mean editing fork sources, which is the fork
repository's decision to make and not ours. **The core never calls `UCI::loop`.**
That matters for one specific reason: `UCI::loop` reads the environment variable
`FAIRY_STOCKFISH_VARIANT_PATH` and loads a variant file from it
(`upstream/src/uci.cpp:319-323`). Because the core does not go through that
function, no environment variable can substitute a variant configuration behind
the app's back.

## The fork's static-library target

[`docs/engine-integration.md`](../../../docs/engine-integration.md) requires the
**fork** to expose a static-library target for every supported platform, which
the core links. That change landed at `86dad87e`, and `pinned-inputs.json`
records the artifact and its build command under `fork.static_library`.

The core does not consume that artifact. Several architectures come out of one
build system here — `arm64` and `arm64e` on the Apple platforms, `x64` and
`arm64` on Windows — and producing them from the fork's Makefile means driving it
once per `ARCH` and joining the results, a second build system to keep correct
alongside the one the core already has. What it does instead: `CMakeLists.txt` in
this directory is a **core-owned** build of the snapshot. It compiles the same
sources with the same defines the fork's own `make ARCH=… nnue=no` would use,
each one cited back to a line of the fork's `Makefile` at the pinned revision.
Which `ARCH` profile each target gets is decided there too, and Windows on
`arm64` is the one place the answer is not the obvious one: it takes the fork's
portable `general-64` profile rather than `apple-silicon`, because `USE_POPCNT`
and prefetch select x86 headers under `_MSC_VER` and the fork's NEON code is
written in GCC and Clang vector-extension syntax that MSVC does not provide. The
file carries the compiler's own error text for both.

If the core ever switches to consuming the fork's own artifact:

1. Replace this directory's `CMakeLists.txt` with one that drives the fork's
   target and consumes its artifact, rather than restating the source list and
   the flag set. The alias it defines must stay `mxq::fairy-stockfish`, because
   that is what `core/CMakeLists.txt` links.
2. Fill in `fork.static_library.artifact_name` and
   `fork.static_library.build_command` in `pinned-inputs.json` and set
   `established` to `true`.
3. Move the flag set out of this file and into
   `build_flags.platforms.<platform>.engine_defines` and `engine_flags`, which
   are recorded as unestablished today precisely because no build had produced
   them. Builds now produce them for macOS/arm64 and for Windows on both
   architectures, and they are still not recorded there. A Windows packaging
   build exists as of 2026-07-31 and did not change that: it publishes the
   frontend over a core somebody else already built and chooses none of these
   flags, so filling those fields from a developer build's command line would
   record the wrong build's answer. Establishing them means first deciding that
   the core build *is* part of the packaging build, which is a separate
   question — `docs/architecture.md` carries it as an open one.

Until then, the source list here has to be maintained by hand whenever the
snapshot is re-cut. `CMakeLists.txt` fails configuration with an explicit message
if a listed source is missing, so a re-cut that drops a file is a build error
rather than a link error.

## Build switch

The engine is compiled only when `MXQ_ENABLE_RULES_FACADE` is `ON`:

```sh
cmake -S core -B core/.build -G Ninja -DMXQ_ENABLE_RULES_FACADE=ON
cmake --build core/.build
```

With the option `OFF`, which is the default, `core/CMakeLists.txt` does not add
this directory at all: the scaffold configures and builds exactly as it did
before the snapshot arrived, and no one pays for a multi-minute engine
compilation to work on the rest of the core.
