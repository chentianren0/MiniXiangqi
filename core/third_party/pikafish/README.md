# Pikafish, Jieqi rules slice

- Upstream: https://github.com/official-pikafish/Pikafish, branch `jieqi`, base `9b963f727983a1d9308e0dca48b39c802b8e75a2`
- Fork: https://github.com/chentianren0/Pikafish, branch `jieqi-mxq`, pinned at `709ba1792d87be01e69975472936bc309ed54082`, committed 2026-08-16
- Included: `src/position.cpp`, `src/movegen.cpp`, `src/bitboard.cpp` and the headers they reach. Excluded: search, evaluation, NNUE code, UCI, `misc.cpp`, `memory.cpp`, the bundled zstd, the Makefile, tests and CI.
- `mxq_pikafish_link_closure.cpp` supplies the three definitions the slice references but does not carry. A consumer must never define them itself: its body would silently win.
- The target is compiled with `-DStockfish=PikafishJieqi`, applied `PUBLIC`, and `mxq_core` links the slice behind `$<LINK_ONLY:>`, because Fairy-Stockfish declares the same namespace and symbols; without it link order picks which engine runs.
- Patches in the pinned revision, oldest first:
  - `report-the-rule`: `Position::rule_judge` can report which rule produced its value.
  - `raise-max-moves`: `MAX_MOVES` goes from 128 to 256, since a Jieqi position can have up to 175 legal moves.
  - `renew-chase-per-attacker`: chases are tracked per chasing and chased pair, so a chase by a new attacker counts.
