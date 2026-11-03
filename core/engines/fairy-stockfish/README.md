# Fairy-Stockfish

- Upstream: https://github.com/fairy-stockfish/Fairy-Stockfish, base `c19b5f6c66894fdb0e88d0dd100e3885f744760a`
- Fork: https://github.com/chentianren0/Fairy-Stockfish, pinned at `d3b4ba2e198fe25891a1c3af8ff90b5710c2539e`, committed 2026-08-01
- Included: `AUTHORS`, `Copying.txt`, the README, and `src/` minus `main.cpp`, `pyffish.cpp`, `ffishjs.cpp`, `Makefile`, `Makefile_js` and the sample `variants.ini`. Excluded besides: tests, CI and the Python packaging. The core never calls `UCI::loop`, which loads a variant file named by the `FAIRY_STOCKFISH_VARIANT_PATH` environment variable.
- Patches in the pinned revision, oldest first:
  - `soldier-chase-target-exclusion`: Mini Xiangqi soldiers, promoted from the start, are not perpetual-chase targets.
  - `recoverable-hash-allocation`: a failed transposition-table allocation or free returns an error instead of exiting the process.
  - `static-library-target`: a static library target; the core builds the snapshot as a target of `core/Package.swift` instead.
  - `adjudication-defect-corrections`: a pinned chaser no longer counts as chasing, and the flying-general pin test counts both sides' pieces.
  - `chase-target-exemption-in-discovered-check-classifier`: generals and soldiers are exempt as chase targets on the discovered-check path too.
  - `optional-game-end-rule-accessor`: `Position::is_optional_game_end` reports which rule produced the end.
  - `repetition-window-parity-correction`: both sides' repetition windows have the same span, so a mutual perpetual chase is no longer a loss.
  - `msvc-thread-stack-size`: MSVC search threads get the explicit stack the other builds already had.
  - `search-thread-stack-reservation-64mib`: search threads reserve a 64 MiB stack instead of 8 MiB.
