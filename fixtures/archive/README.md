# Game archive fixtures

Version 7 archives (the 3.x format in `docs/game-data.md`), each paired with an expectation file of the same stem. `valid/` holds documents the codec must accept, written in canonical form and reproduced byte for byte by the encoder from a scenario in `../store/`. `rejected/` holds one document per way an import can be refused. `core/tests/mxq_archive_tests.cpp` runs both through `mxq_archive_probe` and `mxq_archive_validate`, and `core/tests/mxq_interchange_tests.cpp` runs them again through `mxq_store_import`. The size and ply limits have no files here; the runner builds those cases on both sides of each limit.

Each `<stem>.mxq` is an archive. Its `<stem>.expected.json` carries `title` or `class`, and `why`, plus:

- in `valid/`: `info`, the `MxqArchiveInfo` both entry points must return, in the archive's own vocabulary (`game`, `mode`, `human_side`, `outcome`, `end_reason`, `move_count`, `started_at_ms`, `ended_at_ms`, `game_id`, `archive_version`). `null` stands for the matching `NONE` constant.
- in `rejected/`: `probe` and `validate`, the `MxqStatus` names each entry point must return; optionally `detail_contains`, a substring the diagnostic must carry, `detail_index`, the move index the error points at, and `game`, for a game a build may not carry.

Identifiers and timestamps come from the core's deterministic identity and clock (`MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY`).
