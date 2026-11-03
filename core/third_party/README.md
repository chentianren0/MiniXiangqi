# Vendored third-party code

The core compiles three engine forks and SQLite from source snapshots kept here, each linked privately into `mxq_core`. `pinned-inputs.json` at the repository root records every revision, patch list, network and hash; each directory's README sums up what was taken from where.

- `fairy-stockfish/`: rules and search for Mini Xiangqi and Xiangqi.
- `pikafish/`: the Jieqi rules only, without search or evaluation.
- `rapfi/`: rules and search for Gomoku and Renju.
- `sqlite/`: the 3.x library store, which #282 removes.

Nothing under any `upstream/` directory is edited here. A change to an engine lands in its fork and arrives as a new snapshot, with `SOURCES.sha256` regenerated (`cd upstream && shasum -a 256 -c ../SOURCES.sha256` checks it).
