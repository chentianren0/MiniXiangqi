# Vendored SQLite

The SQLite amalgamation, vendored as a verbatim copy and compiled into the
static library `mxq::sqlite`, which `mxq_core` links `PRIVATE`. It backs the
library store defined in [`docs/game-data.md`](../../../docs/game-data.md);
nothing above the C interface in `mxq.h` can see it.

| | |
|---|---|
| Version | 3.53.4 |
| Source id | `2026-07-24 19:02:57 bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc` |
| Downloaded from | `https://sqlite.org/2026/sqlite-amalgamation-3530400.zip` |
| Archive SHA-256 | `1e71ddf93849c6a6ecf58b827c0692073d2dd7ee40196158068f7b29f422e87d` (computed from the downloaded bytes) |
| Archive SHA3-256 | `628a44cfe82c66aed1ccbbe85a562d2e33ebe64b3288981ed76285612227934e` (matches the hash published on sqlite.org/download.html) |
| License | Public domain — SQLite dedicates its code to the public domain ([sqlite.org/copyright.html](https://sqlite.org/copyright.html)); there is no license text to carry |

The version and both hashes are recorded in
[`pinned-inputs.json`](../../../pinned-inputs.json) under `sqlite`, which is
the single source of truth; the table above repeats it for a reader who is
already in this directory. The floor is 3.37.0, fixed by
[`docs/game-data.md`](../../../docs/game-data.md) for `STRICT` tables; 3.53.4
was the newest stable release when the store landed, per the same contract's
"newest stable amalgamation at core landing" rule. Updates are explicit
reviewed changes, never silent.

## Layout

```text
core/third_party/sqlite/
├── CMakeLists.txt    # ours: builds the amalgamation as mxq::sqlite
├── README.md         # ours: this file
├── SOURCES.sha256    # ours: per-file SHA-256 of everything under upstream/
└── upstream/         # sqlite3.c and sqlite3.h from the archive, never edited here
```

Nothing under `upstream/` is modified. A newer SQLite arrives as a new
amalgamation at a new pinned version, updating `SOURCES.sha256` and
`pinned-inputs.json` in the same change.

## Why the amalgamation

SQLite's own recommended way to embed it: the entire library as one
translation unit, which is also the form the project tests most heavily.
It is self-contained, works offline, and pins by bytes rather than by a
repository reference — the same properties the Fairy-Stockfish snapshot next
door was chosen for. `docs/game-data.md` requires that the pinned SQLite ships
inside the core on every platform and that the core never depends on a
system-provided SQLite, which rules out the operating system's copy: the
system library's version, thread mode, and option set vary by OS release, and
none of them are pinned by this repository.

### Verifying the snapshot

```sh
cd upstream && shasum -a 256 -c ../SOURCES.sha256
```

To re-verify against the origin: download the archive URL above, check its
SHA-256 against the table (and its SHA3-256 against sqlite.org's download
page), and compare its `sqlite3.c` and `sqlite3.h` byte-for-byte with
`upstream/`.

## What is excluded, and why

The amalgamation archive contains four files; two are vendored.

| Excluded | Reason |
|---|---|
| `shell.c` | The `sqlite3` command-line shell, with its own `main()`. The core is a library; a second `main` symbol has no business in it. |
| `sqlite3ext.h` | The header for building loadable extensions. The store is compiled with `SQLITE_OMIT_LOAD_EXTENSION` per `docs/game-data.md`, so the extension mechanism this header exists for is exactly what the build removes. |

## Compile-time options

The hardened option set `docs/game-data.md` requires is applied in
`CMakeLists.txt` here, each define annotated with the contract line it
implements, and recorded per platform in `pinned-inputs.json` under
`build_flags.<platform>.sqlite_defines`. The defines are policy, identical on
every platform; they are not architecture tuning. The connection-level
requirements — write-ahead logging, `synchronous=FULL`, `foreign_keys=ON` —
are applied and verified at open in `core/src/mxq_store.cpp`, with the
matching compiled defaults set here as defence in depth.
