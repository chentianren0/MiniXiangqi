# Store session fixtures

Each file is a game scenario for the 3.x library store: a configuration and a move line, and what must hold after playing it. `core/tests/mxq_session_tests.cpp` runs the files at this level: it creates the game, plays it, checks its status and its position against the rules facade, compares the encoded archive with the named golden in `../archive/valid/`, closes and reopens the store, resumes, and undoes to the start. `core/tests/mxq_history_tests.cpp` runs the files in `terminal/`, which end the game and check the History record it leaves.

A scenario has `title`, `why`, `config` (`game`, `mode`, and for `human-vs-ai` the side, level, move time and first-mover choice), `moves`, and optionally `archive`, the golden its bytes must match. Then:

- at this level: `status` (`state`, `reason`, `at_occurrence`, `claim_available`, `undo_available`, `undo_plies`, `resign_available`, `search_expected`) and `undo`, the plies each successive undo removes;
- in `terminal/`: `end`, with `action` (`claim_draw`, `resign`, `confirm_result`, `archive_and_clear` or `commit_nearby_end`), the `archive` golden, the committed `outcome` and `end_reason`, and `state`, the live state when the game ends. `commit_nearby_end` also takes `reason` and, for a resignation, `resigning_side`.
