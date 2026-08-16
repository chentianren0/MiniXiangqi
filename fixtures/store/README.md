# Store Round-Trip Fixtures

This directory holds the approved, executable fixtures for a **store-attached session's round trip**: create a game, play it, close the core, reopen it, resume — and find the same game. Beside it, in `terminal/`, are the fixtures for the four ways that game **ends**. The fixtures and [docs/game-data.md](../../docs/game-data.md) form one contract and are reviewed together, exactly as the archive corpus and that document do.

Normative stance: every expected value comes from the accepted contracts — the autosave rule ("the core commits explicitly after every accepted move and undo"; "a move or undo whose commit fails does not happen"), the undo rule (one ply in Free Play, human decision cycles in human-versus-AI), the state-derived classification of an ending, the two shapes of the archive, and the frozen configuration — never from what the core currently happens to do. A scenario the core disagrees with is a core defect until the contract says otherwise.

## Layout

```text
fixtures/store/
├── <stem>.json           one round-trip scenario: a configuration, a move line, and what must be true of it
└── terminal/<stem>.json  one ending: the same, plus the call that ends the game and the record it must leave
```

Each runner walks every `*.json` in its own directory, so a new scenario is a new file and never new runner code.

## What runs them

`core/tests/mxq_session_tests.cpp`, registered with CTest as `store_sessions`:

```sh
cmake -S core -B core/.build -G Ninja -DMXQ_ENABLE_RULES_FACADE=ON
cmake --build core/.build
ctest --test-dir core/.build --output-on-failure
```

It takes `--fixtures <dir>` and honours `$MXQ_STORE_FIXTURES_DIR`, and it needs the archive corpus beside it (`--archives`, `$MXQ_ARCHIVE_FIXTURES_DIR`) for the goldens a scenario names.

A session answers every one of its queries by replaying its move line through the rules facade, so without `-DMXQ_ENABLE_RULES_FACADE=ON` the `mxq_game_` functions are not in the library at all — absent rather than stubbed, like `mxq_archive_validate`. The runner then reports every session expectation as NOT IMPLEMENTED, never counted as a pass, and still runs what needs no engine: the core's own SHA-256, against the published test vectors.

A scenario of a placement game is skipped in a build without the second engine, which is a different absence and says so: the closing NOT IMPLEMENTED banner speaks for the rules facade alone, so a run that skipped only a placement scenario does not claim the session surface was missing from a build that had it.

## What each scenario asserts

Every scenario runs the same round trip, and the file states only what differs:

1. **Create.** A store-attached active game exists; the frozen configuration and the identity read back exactly as supplied and minted.
2. **Play.** Each move is applied and committed inside its own call, and the position revision advances once per accepted mutation.
3. **The stated status.** State, end reason, occurrence, and the five affordances — claim, undo (with its ply count), resign, and whether a search is owed — are compared against the scenario's `status` block.
4. **The position, against the session-free facade.** `mxq_game_position` and `mxq_game_position_at` are compared with `mxq_rules_evaluate` over the same `(start_fen, moves)` prefix, which is the surface [`fixtures/rules/`](../rules/README.md) already gates. The FEN is deliberately not transcribed into these files: a second copy of it here would be a second authority, and the one that matters is the one the conformance corpus pins.
5. **The archive bytes**, when the scenario names a golden: the session's `mxq_archive_encode` output is compared **byte for byte** with that file in [`../archive/valid/`](../archive/README.md), then probed, validated, and encoded again to the same bytes.
6. **Close and reopen.** The core is shut down and initialised again on the same store; `mxq_game_resume_active` produces a session whose identity, configuration, move history, position, status, and archive bytes are identical to the ones before the close.
7. **Undo, to the start and past it.** Each Undo must remove exactly the plies the scenario's `undo` list states; when the list is exhausted, Undo must be refused with `MXQ_ERR_STATE_UNDO_UNAVAILABLE`, and the game must be exactly as long as the undos left it.

### Scenario

```json
{
  "title": "…",
  "why": "…",
  "config": { "game": "minixiangqi", "mode": "human-vs-ai", "human_side": "black",
              "ai_level": "deep", "ai_movetime_ms": 5000,
              "first_mover_choice": "random" },
  "moves": ["b1b3", "b7b5"],
  "archive": "human-vs-ai-active.mxq",
  "status": { "state": "ongoing", "reason": null, "at_occurrence": 0,
              "claim_available": false, "undo_available": true, "undo_plies": 1,
              "resign_available": true, "search_expected": true },
  "undo": [1]
}
```

`config` is `MxqGameConfig` in the serialised vocabulary of `game-data.md`; Free Play and nearby play omit the four human-versus-AI members exactly as the archive does, and a `nearby` scenario states `local_side` instead — the one configuration member the archive never carries, so the only thing that can restore it after a reopen is the store's own column. `game` is required in every scenario and is the archive's `rules_id` — one of `minixiangqi`, `xiangqi`, `gomoku-15`, `renju` — because a scenario that did not say would be played under whichever game the runner happened to pick, which is the one thing a many-game corpus must not do. A scenario of a game the build does not carry is reported as not evaluated rather than failed. `start_fen` is optional and is the position the game begins from; a scenario that omits it begins from its game's frozen start, exactly as the empty member does on the other side of the interface. `status` is `MxqGameStatus`, with `null` spelling `MXQ_END_REASON_NONE`; it states no side to move, because the position is already compared against the session-free facade and the runner asserts instead that the status and the position name the same one. `archive` is optional and names a file in `../archive/valid/`. `undo` lists the plies each successive Undo must remove — `[2, 2]` is two human decision cycles — and an empty list means Undo was never available, which is every nearby scenario: a retraction there is the two players' agreement rather than one device's decision.

The move lines are ones the rules corpus already proves legal under the scenario's own game, so a scenario cannot fail for a reason that belongs to another contract.

Every game is covered on at least one side, and both move classes on both. `xiangqi-free-play-two-moves.json` is the round trip on the 9-by-10 board and `terminal/xiangqi-free-play-ended-early.json` is an ending on it; `renju-free-play-two-moves.json` is the round trip on a placement board, whose plies place a stone rather than move a piece and whose frozen start is an empty 15-by-15 field, and `terminal/gomoku-15-five-in-a-row.json` is the end only a placement game's rules reach. A core that carried a single starting position, a single ruleset, a single move grammar, or a single `rules_id` in the row it writes would pass every Mini Xiangqi scenario unchanged and fail exactly those four.

`xiangqi-custom-scene.json` is the one scenario that begins somewhere its game's rules had to be asked about: a composed position with Black to move, so ply 0 is Black's, the fullmove number advances on it, and the whole round trip — replay, commit, resume, encode — runs from a start no constant in the core spells. A build that substituted the frozen array anywhere along it would fail this scenario's first move, and pass every other scenario here unchanged.

All three modes are covered on both sides too. `nearby-two-moves.json` is the round trip of a game two devices play — its local side must survive a close and a reopen although no byte of the archive carries it, and its Undo must be refused — and `terminal/nearby-resignation.json`, `terminal/nearby-agreed-draw.json` and `terminal/nearby-mutual-resignation.json` are the three endings the protocol's explicit ends reduce to.

## The cases that are code rather than data

Some of what a session promises is not a property of a game but of the interface around it, and those live in the runner as named cases:

| case | what it pins |
|---|---|
| a second active game | `mxq_game_create` with one already active is `MXQ_ERR_STATE_ACTIVE_GAME_EXISTS`, and the existing game is untouched |
| the start ladder | a composed start is asked three questions in order — structure and counters, setup legality, startability — each answering in its own status and the earlier rung winning; a nearby game refuses one outright; and the scene the ladder exists for is created with its own side moving first |
| resuming nothing | no active game is `*out_exists = 0` and `MXQ_OK` — absence is not an error |
| refused moves | a malformed move, an illegal move and a move after a result leave the game and the store exactly as they were |
| a failed commit | with the database locked by another connection, `apply_move` and `undo` fail in the store domain and the game stays at its pre-mutation committed state, byte for byte; the same call succeeds once the lock is released |
| concurrent use | a second thread inside one session is refused with `MXQ_ERR_ARG_CONCURRENT_USE` rather than serialised |
| tombstones | after `mxq_core_shutdown`, every function on an outstanding handle answers `MXQ_ERR_ARG_INVALID_HANDLE`, and releasing it is still safe |
| SHA-256 | the core's own implementation against the published NIST vectors, before anything trusts a content hash |

The failed-commit case takes the database's write lock from a second SQLite connection, so the failure is a real one arriving through the store's own path rather than through a seam that exists only in tests. There is no test-only hook in the core.

## The endings, in `terminal/`

`core/tests/mxq_history_tests.cpp`, registered with CTest as `store_history`, runs these. It takes the same `--fixtures` and `--archives` options and reads its scenarios from the `terminal/` subdirectory.

Each scenario states the game and the one call that ends it, and the runner drives that ending end to end:

1. **Play.** The scenario's line is created and applied, and the state it reaches is compared with the `end.state` the scenario names — the state the classification is derived from.
2. **End.** The named call — `claim_draw`, `resign`, `confirm_result` or `archive_and_clear` — returns a record identifier and bumps the library revision.
3. **The session afterwards.** Every mutation returns `MXQ_ERR_STATE_SESSION_ARCHIVED`; every query still answers, with every derived affordance at 0; `mxq_archive_encode` produces the finished document, which is compared **byte for byte** with the golden the scenario names and is not the document the active game held.
4. **The library afterwards.** No active game, no active summary, exactly one History record, whose every summary field is checked against the scenario and the frozen configuration, and which the page returns.
5. **Another game.** One may now be created, and filed in its turn, with a record identifier strictly greater than the first.
6. **Across a relaunch.** The core is shut down and initialised again: `mxq_game_resume_active` reports absence, and the record reads back identically.
7. **Opened for replay.** `mxq_store_history_open` yields a detached read-only session with the same identity, the same line, the record's own bytes — which `mxq_archive_validate` accepts — and a refusal of `MXQ_ERR_STATE_SESSION_READ_ONLY` for every mutation.

### Terminal scenario

```json
{
  "title": "…",
  "why": "…",
  "config": { "game": "minixiangqi", "mode": "free-play" },
  "moves": ["b1b3", "b7b5"],
  "end": { "action": "archive_and_clear", "archive": "free-play-ended-early.mxq",
           "outcome": "none", "end_reason": "ended-early", "state": "ongoing" }
}
```

`action` is one of `claim_draw`, `resign`, `confirm_result`, `archive_and_clear`, `commit_nearby_end`. `outcome` and `end_reason` are the committed classification in the serialised vocabulary, and `state` is the live state the position is in when the ending is performed — which for a resignation, an ended-early record and every declared nearby ending is deliberately not terminal.

`commit_nearby_end` takes two more members, which are the two arguments beyond the handle that `mxq_game_commit_nearby_end` takes: `reason`, one of `resignation`, `mutual-resignation`, `agreed-draw`, and — for the one that names a side — `resigning_side`. The caller states which end the two players reached, because the reconciled session is the authority for that and the board is not; the core still derives the outcome from it, so no scenario ever asserts a result.

Every terminal scenario drives the atomicity case: with the database locked by a second connection, each ending fails in the store domain, the game stays active and byte-for-byte unchanged with no History record and no revision bump, and the same call succeeds once the lock is released.

| case | what it pins |
|---|---|
| an empty library | counting, paging and the revision of a library with nothing in it — the one case that needs no engine |
| a failed ending | all four endings, under a real write lock: unchanged, unarchived, retryable |
| nothing to archive | `archive_and_clear` with no active game is `MXQ_ERR_STATE_ACTIVE_GAME_MISSING`; a second one on an archived session is `MXQ_ERR_STATE_SESSION_ARCHIVED` |
| refusals | each ending refuses where its own rule does not hold, and changes nothing when it does |
| ordering | pinned first, newest first, and a same-millisecond tie broken by `record_id` |
| pagination | an exact page, a roomy one, one overlapping the end, one past it, `limit` 0, and a buffer below the limit |
| revisions | every committed mutation bumps the counter, a refused one does not, and a deleted `record_id` is never issued again |
| the active summary | the summary and live state of the active game, and one active game across an archiving |
| corruption | a content hash that disagrees with its bytes, and a library reference to a row that is not there |
| aliasing | a second `resume_active` while a session is attached |

## Consumption

Sessions and the endings are gated by these fixtures on every platform. What they do not cover — import and export — arrives with the PR that implements it, and brings its own scenarios rather than stretching these.
