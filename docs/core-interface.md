# Core C Interface

This document defines the core's complete C-visible surface: the module and function inventory, handle model, data-passing conventions, error taxonomy, threading contract, versioning policy, and capacity constants. It does not define the rules of either game, persistence schemas, archive serialization, engine search policy, or UI behavior.

The core plays two games, and `MxqGameKind` is the axis that names which: `MXQ_GAME_KIND_MINI_XIANGQI` and `MXQ_GAME_KIND_XIANGQI`. Every rules question is asked of one game, and no function infers it from a position — the two boards differ in size today, but the ruleset is not a property of the board. A game outside the closed vocabulary is a programming error and returns `MXQ_ERR_ARG_RANGE`.

> **Status: binding.** Signature corrections go through ordinary reviewed contract changes.

## Design principles

- One prefix, one header: functions `mxq_<module>_<verb>`, types `Mxq<Noun>`, constants `MXQ_<SNAKE>`, all declared in a single public `mxq.h` so both bindings — the Swift module map and the ClangSharp-generated C# declarations — are generated from one input.
- Exactly three opaque handle types: `MxqCore` (the singleton-enforced core), `MxqGame` (a game session), `MxqBlob` (an immutable byte buffer). Everything else crossing the boundary is a plain-old-data value struct copied into caller storage.
- Every value struct begins with `uint32_t struct_size`; structs grow append-only behind that guard. Enums carry explicit `int32_t` values and grow append-only. Booleans are `uint8_t` 0/1. Strings are UTF-8 and, where bounded by the frozen notation, carried by value in fixed-capacity arrays (`MxqMove.text[8]`, FEN capacity 96) so every struct is trivially copyable, blittable in C#, and `Sendable` in Swift. Both capacities are the wider game's and are fixed rather than per-game, so one struct has one layout: the longest move either game spells is `a9a10` at five characters, and the longest starting FEN is Xiangqi's at 68 bytes.
- The caller never frees core memory. Outputs are copies into caller storage; the only pointer into core memory is `mxq_blob_bytes`, valid until `mxq_blob_release`.
- Every fallible function returns `MxqStatus` and takes an optional `MxqError *err` out-parameter for detail. There is no thread-local last-error.
- Moves use the frozen canonical notation `<from><to>` and positions the frozen 6-field FEN, per [xiangqi-rules.md](xiangqi-rules.md). Every rules query is defined over an initial position plus complete move history, never a bare FEN, because repetition and violation state derive from history.

## Modules and functions

Six groups, 56 functions.

### Common prelude

```c
MxqStatus   mxq_status_domain(MxqStatus status);
const char *mxq_status_name(MxqStatus status);      /* immortal literal */
const uint8_t *mxq_blob_bytes(const MxqBlob *blob);
size_t         mxq_blob_len(const MxqBlob *blob);
void           mxq_blob_release(MxqBlob *blob);     /* NULL-safe */
```

### Core lifecycle — `mxq_core_`

```c
MxqStatus mxq_core_version(MxqVersion *out, MxqError *err);   /* callable before init */
MxqStatus mxq_core_game_profile(MxqGameKind game, MxqGameProfile *out,
                                MxqError *err);               /* callable before init */
MxqStatus mxq_core_init(const MxqCoreConfig *config, MxqCore **out_core, MxqError *err);
MxqStatus mxq_core_cancel_all(MxqCore *core, MxqError *err);  /* backgrounding */
MxqStatus mxq_core_shutdown(MxqCore *core, MxqError *err);    /* deterministic teardown */
```

`MxqCoreConfig` carries the frontend-supplied store directory, asset directory, caller `MXQ_API_VERSION`, and flags. `MxqVersion` reports the four independent version axes — the C API version, the archive format versions (current and minimum readable), the store schema version — and the two build revisions, core and pinned fork. `MxqGameProfile` reports what one game binds: its pinned engine variant identifier and that variant's NNUE SHA-256. Those are per game and so are not in `MxqVersion`: there are two of each and one field cannot carry both. All of it is load-bearing rather than diagnostic — conformance depends on a fork build, so every test report and saved diagnostic must be able to name the build and the variant that produced it.

`MxqCore` is handle-shaped but singleton-enforced: a second `mxq_core_init` before shutdown returns `MXQ_ERR_STATE_ALREADY_INITIALIZED`, because the embedded engine's process-global state admits one instance. The handle keeps teardown explicit and the signatures stable if that constraint ever lifts.

One config flag exists: `MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY`, a test affordance and never product behavior. The core has exactly one clock and identity provider — everything that needs an instant or a fresh `game_id` asks it — and under this flag it becomes deterministic, resetting at `mxq_core_init`, so store round-trip fixtures and archive golden files can be byte-stable across runs and machines. The exact deterministic sequences (a fixed epoch advancing one second per read; version-7-shaped identifiers from a counter) are documented normatively on the flag in `mxq.h`. Without the flag the provider reads the real clock and generates real version 7 UUIDs; the flag changes identity and time generation only — no rule, no schema, no store behavior.

### Rules facade — `mxq_game_` (sessions) and `mxq_rules_` (session-free)

A session composes the rules facade with the game's frozen configuration — `MxqPlayMode`, resolved `human_side`, `first_mover_choice`, `ai_level`, exact `ai_movetime_ms`, and `local_side` (the enums `MxqPlayMode`, `MxqColor`, `MxqAiLevel`, and the first-mover choice correspond one-to-one to the serialized vocabulary in [game-data.md](game-data.md), which is where all but the last of them are also archive content) — because undo, resign, search eligibility, and the archive all depend on it. Sessions are **store-attached** when created or resumed (`mxq_game_create`, `mxq_game_resume_active`) and **detached read-only** when opened for replay or import preview (`mxq_store_history_open`, `mxq_game_open_archive`).

Attached sessions distinguish two mutation classes:

- **Ordinary mutations** — `mxq_game_apply_move`, `mxq_game_undo` — update the active game and commit the updated state inside the call before returning. There is no separate save operation.
- **Terminal commits** — `mxq_game_claim_draw`, `mxq_game_resign`, `mxq_game_confirm_result`, `mxq_game_commit_nearby_end` — end the game: each performs one atomic transaction that commits the outcome, inserts the immutable History record, and clears the active-game reference, returning the new record id. Claim commits the draw with reason `threefold-repetition` and is legal only in the claimable state; resign commits the loss for the human side with reason `resignation` and is legal only in human-versus-AI play and only while the game has no result of its own — exactly when `resign_available` reads 1, so that the affordance and the refusal are one rule; confirm-result commits an unconfirmed natural terminal state as its actual result, and a position with no such result is `MXQ_ERR_STATE_CONFIRM_UNAVAILABLE`, the third member of the `*_UNAVAILABLE` family beside the undo, claim and resign refusals. `mxq_game_commit_nearby_end` is nearby play's own, and the one commit whose classification the caller supplies rather than the board: it takes the explicit end the reconciled session reached — `RESIGNATION` with the side that resigned, `MUTUAL_RESIGNATION`, or `AGREED_DRAW` — because no position decides any of the three, and derives the outcome from it so that no caller asserts a result. It is legal only on a nearby session and only over a position with no result of its own, an end the rules decided outranking one the players declared; the two refusals are `MXQ_ERR_STATE_RESIGN_UNAVAILABLE` and `MXQ_ERR_STATE_GAME_OVER`. After a terminal commit the session is archived — further mutations return `MXQ_ERR_STATE_SESSION_ARCHIVED`, queries keep answering with every derived affordance at 0, and `mxq_archive_encode` produces the finished document the History record holds — and the caller still releases the handle. `mxq_store_archive_and_clear` is the fifth, state-derived archiving path for save-before-mode, and the only one that may record `ended-early`; with no active game to archive it returns `MXQ_ERR_STATE_ACTIVE_GAME_MISSING`, because the one required pointer it takes is the active game itself.

```c
/* lifecycle */
MxqStatus mxq_game_create(MxqCore *core, const MxqGameConfig *config,
                          MxqGame **out_game, MxqError *err);
MxqStatus mxq_game_resume_active(MxqCore *core, MxqGame **out_game,
                                 uint8_t *out_exists, MxqError *err);
MxqStatus mxq_game_open_archive(MxqCore *core, const uint8_t *bytes, size_t len,
                                MxqGame **out_game, MxqError *err);
void      mxq_game_release(MxqGame *game);

/* queries */
MxqStatus mxq_game_id(const MxqGame *game, char *out, size_t cap,
                      size_t *out_len, MxqError *err);        /* the frozen v7 UUID */
MxqStatus mxq_game_position(const MxqGame *game, MxqPosition *out, MxqError *err);
MxqStatus mxq_game_status(const MxqGame *game, MxqGameStatus *out, MxqError *err);
MxqStatus mxq_game_config(const MxqGame *game, MxqGameConfig *out, MxqError *err);
MxqStatus mxq_game_legal_moves(const MxqGame *game, MxqMove *out, size_t cap,
                               size_t *out_count, MxqError *err);
MxqStatus mxq_game_legal_moves_from(const MxqGame *game, const char *from_square,
                                    MxqMove *out, size_t cap, size_t *out_count, MxqError *err);
MxqStatus mxq_game_move_history(const MxqGame *game, MxqMove *out, size_t cap,
                                size_t *out_count, MxqError *err);
MxqStatus mxq_game_position_at(const MxqGame *game, uint32_t ply,
                               MxqPosition *out, MxqError *err);   /* replay scrubbing */

/* ordinary mutations — each commits the updated active game before returning */
MxqStatus mxq_game_apply_move(MxqGame *game, const char *move,
                              MxqPosition *out_after, MxqGameStatus *out_status, MxqError *err);
MxqStatus mxq_game_undo(MxqGame *game, uint32_t *out_plies_removed, MxqError *err);
                              /* out_plies_removed is 1 or 2 per the decision-cycle rule */

/* terminal commits — one atomic transaction: outcome + History record + cleared active reference */
MxqStatus mxq_game_claim_draw(MxqGame *game, uint64_t *out_record_id, MxqError *err);
MxqStatus mxq_game_resign(MxqGame *game, uint64_t *out_record_id, MxqError *err);
MxqStatus mxq_game_confirm_result(MxqGame *game, uint64_t *out_record_id, MxqError *err);

/* session-free rules facade — the fixture-harness and import-validation surface */
MxqStatus mxq_rules_start_fen(MxqGameKind game, char *out, size_t cap,
                              size_t *out_len, MxqError *err);
MxqStatus mxq_rules_validate_fen(MxqCore *core, MxqGameKind game,
                                 const char *fen, MxqError *err);
MxqStatus mxq_rules_evaluate(MxqCore *core, MxqGameKind game, const char *start_fen,
                             const char *const *moves, size_t move_count,
                             MxqPosition *out_position, MxqGameStatus *out_status,
                             size_t *out_first_illegal_index, MxqError *err);
MxqStatus mxq_rules_legal_moves(MxqCore *core, MxqGameKind game, const char *start_fen,
                                const char *const *moves, size_t move_count,
                                MxqMove *out, size_t cap, size_t *out_count, MxqError *err);
```

Core value types:

- `MxqPosition` — 6-field FEN by value, side to move, `in_check`, `ply_count`, and `position_revision`, a per-session monotonic counter bumped by every accepted mutation. The revision is the staleness authority: an in-flight search result whose revision no longer matches is rejected even if no one cancelled it.
- `MxqGameStatus` — the live game state and derived affordances: `state` (`MXQ_GAME_ONGOING`, `MXQ_GAME_CLAIMABLE_DRAW`, `MXQ_GAME_RED_WINS`, `MXQ_GAME_BLACK_WINS`, `MXQ_GAME_DRAW` — exactly the fixture state identifiers), `reason` (`MxqEndReason`), `at_occurrence` for repetition-based outcomes, and `claim_available`, `undo_available`, `undo_plies`, `resign_available`, `search_expected` flags so frontends never re-derive rules policy.
- `MxqEndReason` — the fixture reason identifiers `CHECKMATE`, `STALEMATE`, `THREEFOLD_REPETITION`, `PERPETUAL_CHECK`, `PERPETUAL_CHASE`, the mutual-violation reasons `MUTUAL_PERPETUAL_CHECK`, `MUTUAL_PERPETUAL_CHASE`, the move-count draw `FIFTY_MOVE_RULE`, the user-scoped `RESIGNATION` and `ENDED_EARLY`, the two ends two players declare to each other, `AGREED_DRAW` and `MUTUAL_RESIGNATION`, plus `NONE`. `FIFTY_MOVE_RULE` is Xiangqi's alone; Mini Xiangqi has no move-count rule, so it can never arise there. The last two are `MXQ_PLAY_MODE_NEARBY`'s alone, and both are draws.
- `MxqGameConfig` — the game's frozen configuration, and `game` is part of it: the play mode, the resolved human side, the AI level and its exact frozen movetime, the first-mover choice, and which of the two games is being played. Every later question about that session is asked under it. One member of it is not archive content and never will be: `local_side`, the side this device's player took, meaningful exactly in `MXQ_PLAY_MODE_NEARBY`. The archive is device-portable, so the store holds that as library metadata beside pin state and provenance, restores it on resume from its own column, and reports it through `MxqRecordSummary.local_side`.
- Stored records use a distinct committed-outcome enum `MxqOutcome` — `RED_WINS`, `BLACK_WINS`, `DRAW`, `NONE` — matching the archive's serialized outcome vocabulary in [game-data.md](game-data.md). Live states (`ONGOING`, `CLAIMABLE_DRAW`) are never a committed outcome, and `NONE` (ended early) is never a live state; conflating the two vocabularies in one enum is the bug this split prevents.

`mxq_game_id` reports the session's stable identity — the version 7 UUID frozen at creation. A session must be able to state it: the staleness comparison `MxqSearchResult` prescribes is against `(game_id, position_revision)`, and a detached replay or import-preview session has no other route to the value.

`mxq_rules_evaluate` and `mxq_rules_legal_moves` take `(game, start_fen, moves[])` and are exactly the surface the approved conformance fixtures replay through; a fixture's every assertion maps onto their outputs, and its declared ruleset is what the harness passes as `game`.

### Search facade — `mxq_engine_` (preparation) and `mxq_search_`

```c
MxqStatus mxq_engine_plan(const MxqEngineBudget *budget, MxqEnginePlan *out, MxqError *err);
MxqStatus mxq_engine_prepare(MxqCore *core, MxqGameKind game,
                             const MxqEngineBudget *budget,
                             MxqEnginePlan *out_applied, MxqError *err);
MxqStatus mxq_engine_teardown(MxqCore *core, MxqError *err);
MxqStatus mxq_engine_query(MxqCore *core, MxqEngineState *out_state,
                           char *out_profile_id, size_t cap, size_t *out_len, MxqError *err);

MxqStatus mxq_search_start(MxqCore *core, const MxqGame *game,
                           const MxqSearchRequest *request,
                           MxqSearchCallback callback, void *user_data,
                           uint64_t *out_ticket, MxqError *err);
MxqStatus mxq_search_cancel(MxqCore *core, uint64_t ticket, MxqError *err);
MxqStatus mxq_search_cancel_all(MxqCore *core, MxqError *err);
MxqStatus mxq_search_poll(MxqCore *core, uint64_t ticket,
                          MxqSearchResult *out, uint8_t *out_ready, MxqError *err);
MxqStatus mxq_search_wait(MxqCore *core, uint64_t ticket, uint32_t timeout_ms,
                          MxqSearchResult *out, uint8_t *out_ready, MxqError *err);
```

- `mxq_engine_plan` is a pure function of the frontend-supplied probe values implementing the accepted Hash-budget arithmetic, so every budget boundary in [testing.md](testing.md) is testable without an engine. `mxq_engine_prepare` recomputes the same plan, refuses below the 256 MiB minimum with `MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY` without initializing anything, and otherwise applies threads, Hash, and the requested game's pinned variant configuration and NNUE — preflighting the network against the engine's observable load state so the engine's own fatal verification path is never reached. The engine is prepared for exactly one game at a time, because the tables a search reads are that game's variant's; preparing for the other game is an ordinary second call, and `mxq_search_start` on a session of a game the engine is not prepared for returns `MXQ_ERR_STATE_ENGINE_NOT_READY` rather than searching under the wrong board.
- `mxq_engine_query` reports engine state and the profile identifier, and nothing else. Hash utilization and nodes per second have no consumer; the per-search diagnostics a saved record needs ride `MxqSearchResult`.
- `mxq_search_start` does not retain the session: it snapshots the initial FEN, complete move list, `game_id`, `position_revision`, and the session's frozen `movetime` before returning a ticket.
- **`MxqSearchRequest.movetime_ms` is a cross-check, not an input.** The core already holds the only legal value, so the field carries no information; it exists because the two values are computed by different components — the frontend derives `movetime` from the AI level the player chose, and the session holds what was frozen at creation. Requiring them to agree catches the one bug that would otherwise be silent and permanent: a level changed after creation, so a move is thought for a time the archive does not record. A disagreement refuses with `MXQ_ERR_ARG_RANGE` and does not assert, because it reports two independently-built components disagreeing rather than a caller that could not have got here honestly. A Free Play session freezes no `movetime` and owes no search, so it has no value for the request to equal and never passes.
- Delivery applies the rejection ladder in order — cancelled → stale → malformed → illegal under the rules facade — and only a move surviving all four arrives as `MXQ_SEARCH_MOVE`. Stale rejection is enforced twice by design: the core compares `(game_id, position_revision)` before delivery, and the frontend compares again before applying, because neither check alone covers both race directions. Because every accepted mutation bumps the revision, an un-cancelled in-flight search that followed a mutation is neutralized by staleness. Cancellation is nonetheless a correctness requirement, not only a promptness optimization: a cancellation that follows no mutation — the platform suspension path in [engine-integration.md](engine-integration.md) — leaves the revision matching, so the cancelled rung is the only one that rejects the late result.
- `MxqSearchResult` is an inert value struct carrying outcome, the move, and bounded diagnostics (score, depth, nodes, elapsed, profile identifier). Applying the move is a separate explicit `mxq_game_apply_move`; no path exists from search output to committed state.
- The completion callback runs on the core's engine thread. Poll and wait are equivalent consumers for deterministic tests and binding fallback; the result is retained under its ticket until the next search or shutdown.

### Archive codec boundary — `mxq_archive_`

Serialization content is owned by [game-data.md](game-data.md); this boundary moves opaque bytes plus the decoded summary the store indexes.

```c
MxqStatus mxq_archive_probe(MxqCore *core, const uint8_t *bytes, size_t len,
                            MxqArchiveInfo *out, MxqError *err);     /* structural only */
MxqStatus mxq_archive_validate(MxqCore *core, const uint8_t *bytes, size_t len,
                               MxqArchiveInfo *out, MxqError *err);  /* full rules replay */
MxqStatus mxq_archive_encode(MxqCore *core, const MxqGame *game,
                             MxqBlob **out_blob, MxqError *err);
                             /* classification derives from committed state, never from the caller */
MxqStatus mxq_archive_supported_versions(uint32_t *out_min_readable,
                                         uint32_t *out_current, MxqError *err);
```

`MxqArchiveInfo` carries format version, the game the file's `rules_id` names, the stable game identity, timestamps, mode, human side, `MxqOutcome`, `MxqEndReason`, and move count. It carries no local side, because no archive does.

### Library store — `mxq_store_`

```c
/* active game */
MxqStatus mxq_store_active_exists(MxqCore *core, uint8_t *out_exists, MxqError *err);
MxqStatus mxq_store_active_summary(MxqCore *core, MxqRecordSummary *out,
                                   MxqGameStatus *out_status, uint8_t *out_exists, MxqError *err);
MxqStatus mxq_store_archive_and_clear(MxqCore *core, MxqGame *active,
                                      uint64_t *out_record_id, MxqError *err);

/* history */
MxqStatus mxq_store_history_count(MxqCore *core, uint32_t *out_count,
                                  uint64_t *out_library_revision, MxqError *err);
MxqStatus mxq_store_history_page(MxqCore *core, uint32_t offset, uint32_t limit,
                                 MxqRecordSummary *out, size_t cap, size_t *out_count,
                                 uint64_t *out_library_revision, MxqError *err);
MxqStatus mxq_store_history_get(MxqCore *core, uint64_t record_id,
                                MxqRecordSummary *out, MxqError *err);
MxqStatus mxq_store_history_open(MxqCore *core, uint64_t record_id,
                                 MxqGame **out_replay, MxqError *err);   /* detached, read-only */
MxqStatus mxq_store_history_set_pinned(MxqCore *core, uint64_t record_id,
                                       uint8_t pinned, MxqError *err);
MxqStatus mxq_store_history_delete(MxqCore *core, uint64_t record_id, MxqError *err);

/* interchange */
MxqStatus mxq_store_export(MxqCore *core, uint64_t record_id, MxqBlob **out_blob, MxqError *err);
MxqStatus mxq_store_import(MxqCore *core, const uint8_t *bytes, size_t len,
                           MxqImportOutcome *out_outcome, uint64_t *out_record_id,
                           MxqRecordSummary *out_summary, MxqError *err);
```

- `mxq_store_archive_and_clear` is the atomic archive-and-clear in one transaction. On success the passed session is marked archived; later mutations on it return `MXQ_ERR_STATE_SESSION_ARCHIVED`; the caller still releases the handle.
- `mxq_store_history_page` returns records in the accepted order — pinned first, newest within each group, `record_id` descending as the tie-break — as a core guarantee; frontends never re-sort. Its buffer rule is not `mxq_game_legal_moves`': there the count is the answer and an undersized buffer is a routine way to ask for it, while here the caller named the page size itself, so `cap` below `limit` is a caller bug — `MXQ_ERR_ARG_BUFFER_TOO_SMALL` with `required_size` set to `limit`, and nothing written. `*out_count` is the number written.
- `mxq_store_history_get`, `_open`, `_set_pinned` and `_delete` address History records only: the active game's `record_id` is `MXQ_ERR_STORE_NOT_FOUND` from all four, as an identifier that was never issued is. `mxq_store_history_open` yields a detached read-only session whose queries all answer and whose derived affordances all read 0.
- `mxq_store_active_summary` serves the Play destination and the save-and-continue confirmation without materializing a session. It reports the summary columns and, derived by replaying the stored line, the same live state a session would report; no state flag is persisted.
- A library reference naming a row that is not there is `MXQ_ERR_STORE_CORRUPT` rather than an answer of "no active game", from `mxq_store_active_exists`, `mxq_store_active_summary` and `mxq_game_resume_active` alike; and there is at most one session per active game, so a second `mxq_game_resume_active` while one is attached is `MXQ_ERR_ARG_CONCURRENT_USE`.
- `out_library_revision` is a monotonic counter bumped by every committed store mutation: library-change observation is return values plus this cheap staleness check, with no notification mechanism.
- `mxq_store_import` returns `MXQ_IMPORT_EXISTING` with the existing record for an exact duplicate — success, not an error — and typed failures for every rejection class defined by the import pipeline in [game-data.md](game-data.md).

## Error taxonomy

`MxqStatus` codes are grouped in 1000-blocks; `mxq_status_domain` returns the block. Frontends select presentation family by domain and copy by exact code, and must tolerate unknown codes within a known domain (`default:` arm required).

| Domain | Block | Contents |
|---|---|---|
| `MXQ_DOMAIN_ARGUMENT` | 1000 | null pointers, invalid handles, `struct_size`/API-version mismatch, buffer-too-small (routine, carries the required size), encoding, range, wrong-thread, concurrent-use, reentrancy |
| `MXQ_DOMAIN_STATE` | 2000 | not/already initialized, shutting down, active game exists / missing, session read-only / archived, game over, undo/claim/resign/confirm unavailable, search in progress, engine not ready |
| `MXQ_DOMAIN_RULES` | 3000 | illegal move (distinct from) malformed move, invalid FEN (distinct from) illegal position, invalid history with first-illegal index |
| `MXQ_DOMAIN_STORE` | 4000 | I/O, corruption, busy, full, not found, identity conflict, migration failed, schema too new |
| `MXQ_DOMAIN_ARCHIVE` | 5000 | malformed, unsupported version, too large, inconsistent replay, terminal-claim mismatch |
| `MXQ_DOMAIN_ENGINE` | 6000 | insufficient memory, asset missing / mismatch, variant load failure, Hash allocation failure (reserved; reachable only after the fork change), no move, illegal result, faulted |
| `MXQ_DOMAIN_RESOURCE` | 7000 | core allocation failure, documented limit exceeded |
| `MXQ_DOMAIN_INTERNAL` | 9000 | invariant violations; reportable bugs |

Rules for the taxonomy:

- Malformed versus illegal is always distinguished, and against the board of the game being asked: a move is two squares of that board, each a file letter and a rank in decimal without a leading zero — `^([a-g][1-7]){2}$` in Mini Xiangqi and `^([a-i](10|[1-9])){2}$` in Xiangqi. Anything else is malformed (a caller bug from the UI, expected data from an import); a well-formed move that is not legal is the ordinary illegal-move outcome with its accepted brief feedback. The grammar lives in one place in the core and is parameterized by game, because three hand-kept copies of one regular expression agree exactly until a second board exists.
- `mxq_rules_validate_fen` applies the frozen structural encoding of the game it is asked about and nothing else; a position of the other game's board fails it, which is what makes the game a question rather than a hint. The illegal-position code is reserved for the setup-legality predicate [game-data.md](game-data.md) requires of any archive version permitting other initial positions, and fixture positions are validated structurally plus by replay.
- **Programming errors assert in debug builds, return their code in release builds, and never change state.** What makes a status a programming error is not its domain but its reachability: a caller that had every fact it needed and still made the call could not have reached it except by its own defect. That is: a null required pointer; a handle this core never issued; a `struct_size` this build cannot interpret; an incompatible `MXQ_API_VERSION`; a value outside a closed vocabulary the frontend itself owns — a square its own board does not have, a game configuration of neither accepted shape, a `pinned` that is not 0 or 1; a second `mxq_core_init`; a core handle that is not the live instance; and a mutation on a detached read-only session. Four argument-domain statuses are deliberately **not** programming errors and never assert, because each is an answer the core promises rather than a caller it catches: `MXQ_ERR_ARG_BUFFER_TOO_SMALL`, the routine way to ask for a size; `MXQ_ERR_ARG_INVALID_HANDLE` from a session handle outstanding across `mxq_core_shutdown`, which the shutdown rule below requires it to answer; `MXQ_ERR_ARG_CONCURRENT_USE`, which reports a race the core detected rather than aborting on a timing accident; and `MXQ_ERR_ARG_REENTRANT`, which the body of a callback must be able to receive. `MXQ_ERR_ARG_RANGE` splits on the same test rather than by code: the closed-vocabulary ranges above assert, while `mxq_game_position_at`'s ply beyond the retained line does not — a scrubber may legitimately probe an end — and neither does `mxq_search_start`'s `movetime_ms` cross-check. Everything else is ordinary control flow and must leave the last committed state intact.
- The two halves of that rule are load-bearing for the test suite as well as the frontend: an expectation about a code that asserts is observable only in a build where `NDEBUG` is defined, so the suite states those expectations under `#if defined(NDEBUG)` and both configurations are run. Neither configuration dominates the other. A release run is the only one that evaluates those expectations at all; a debug run is where the assertions stand guard over every call site the suite does not deliberately point at one. The guarded sites themselves are exercised in neither: the guard compiles the call out.
- `MxqError` detail strings are short English diagnostics, never localized copy, never private game data; the raw subsystem code (SQLite result, FEN validation cause) rides along for diagnostics only and is never branched on.
- User-visible flows map by domain: any store-domain failure from `mxq_store_archive_and_clear` **or a terminal commit** drives the accepted 无法保存对局 retry flow, with the game remaining active and unchanged; `MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY` drives the accepted low-memory retry flow with a fresh probe per retry; a store-domain failure from `mxq_game_apply_move` or `mxq_game_undo` leaves the game exactly at the pre-mutation state and drives the accepted brief save-failure feedback in [interaction-design.md](interaction-design.md) — when the failed commit is an AI reply, the frontend requests a new search from the unchanged position instead; import failures map onto the import pipeline's user-visible classes, and the import time budget exhausts as a resource-domain limit.

## Threading contract

The core creates exactly one internal thread — the engine thread, sole caller of every engine entry point. Store operations execute on the calling thread under one internal mutex over one connection.

| Group | Callable from | Blocking |
|---|---|---|
| status/blob helpers, `mxq_core_version`, `mxq_core_game_profile`, `mxq_engine_plan`, `mxq_rules_start_fen`, `mxq_archive_supported_versions` | any thread, including callbacks | no |
| `mxq_core_init`, `mxq_core_shutdown` | UI or setup thread; never a callback | yes |
| `mxq_core_cancel_all` | any thread except a callback | until the engine quiesces |
| session lifecycle (`mxq_game_create`, `mxq_game_resume_active`, `mxq_game_open_archive`) | any non-UI thread except a callback | yes — store or decode work |
| `mxq_game_release` | session owner | no |
| session queries | session owner | no |
| session mutations and terminal commits (attached) | session owner, off the UI thread | yes — commits inside the call |
| session mutations (detached) | session owner | no |
| `mxq_rules_*` evaluation | any thread except a callback | no |
| `mxq_engine_prepare` / `mxq_engine_teardown` | any non-UI thread except a callback; work executes marshalled on the engine thread | yes |
| `mxq_engine_query`, `mxq_search_start` / `cancel` / `cancel_all` / `poll` | any thread except a callback | no |
| `mxq_search_wait` | any non-UI thread except a callback | bounded by timeout |
| `mxq_archive_probe` / `validate` / `encode` | any thread except a callback | CPU-bound; keep off the UI thread |
| `mxq_store_*` | any thread except a callback, off the UI thread | yes |

Every function that takes an `MxqGame *` — including `mxq_search_start`, `mxq_archive_encode`, and `mxq_store_archive_and_clear` — counts as being inside that session for the single-owner rule and must be driven from the session's owning context; the table's thread class then applies within that ownership.

- **Sessions are single-owner.** A session may move between threads but only one thread may be inside it at a time; a detected race returns `MXQ_ERR_ARG_CONCURRENT_USE` rather than silently serializing, because with one main window and one active game a concurrent session call is a frontend bug and picking an order would hide it. Distinct sessions are independent.
- **The one documented exception to "off the UI thread": the active game's own calls, and the History surface.** The store-attached active game's lifecycle and commits — `mxq_game_create`, `mxq_game_resume_active`, `mxq_game_apply_move`, `mxq_game_undo`, and the terminal commits — may be driven synchronously from the UI thread. One such commit per human move is invisible within a frame and does not justify restructuring the input gate around asynchrony. Every other row above stands, and the off-main-actor structure is held in reserve.
- The same exception extends to the calls the History destination makes — `mxq_store_history_count`, `mxq_store_history_page`, `mxq_store_history_set_pinned`, `mxq_store_history_delete`, and `mxq_store_history_open` — and to `mxq_store_active_summary`, which the Play home reads instead of holding a session, because each is at most what the exception already covers. The two reads commit nothing and do not fsync; the pin and the delete are one commit per user action. `mxq_store_history_open` and `mxq_store_active_summary` are the two whose cost is not bounded by the same argument: each decodes an archive and replays every ply, so it rises with the game's own length. Import, export, and `mxq_store_archive_and_clear` are outside the exception and stay off the UI thread. Nothing about the exception is a property of the interface: the frontend types the store surface as a `Sendable` value over the core handle, so moving it back off the main actor is a change of call site rather than of design.
- **The search callback must copy and return.** It runs on the engine thread. The calls legal inside it are exactly the first row of the table above — the status and blob helpers, and the five pure queries that take no core instance: `mxq_core_version`, `mxq_core_game_profile`, `mxq_engine_plan`, `mxq_rules_start_fen`, `mxq_archive_supported_versions`. Every other function that can report returns `MXQ_ERR_ARG_REENTRANT`, and the refusal comes before the handle is judged, so a callback that passes a null or foreign handle is told it is in a callback rather than told about the handle. `mxq_game_release` is the one call with nothing to report with — it returns void — and is forbidden inside a callback by the single-owner rule instead, the callback not being the session's owner. It must not block, because the engine thread is the resource it would deadlock. Its whole job is to hand the result to the frontend's dispatcher, which the architecture contract already requires before any UI mutation.
- **Engine reconfiguration serializes behind search.** `mxq_engine_prepare` and `mxq_engine_teardown` run on the engine thread and return `MXQ_ERR_STATE_SEARCH_IN_PROGRESS` rather than stalling if a search is outstanding.
- **Backgrounding and termination.** `mxq_core_cancel_all` cancels cooperatively; callbacks still fire with the cancelled outcome. Termination mid-search loses nothing (the last accepted move was committed; search output never commits). Termination mid-transaction recovers to the last committed state through the store's journal. `mxq_core_shutdown` cancels all work, joins the engine thread, closes the store, and invalidates outstanding handles, which afterwards return `MXQ_ERR_ARG_INVALID_HANDLE` — a session handle — or `MXQ_ERR_STATE_NOT_INITIALIZED` — the core handle, which is not the live instance any more — instead of touching freed memory. The two are not symmetric, and the taxonomy's rule says why: a tombstoned session handle is an answer the core owes the owner who still holds it, while a core handle that is not the live instance is a programming error and asserts in a debug build like the rest of them.
- **"Afterwards" is exact and is the whole promise:** it covers every call that *begins* after shutdown returns. A call already in flight on another thread when shutdown starts is outside it, and races the shutting-down gate, the live-instance reset, and a session's retained move line. **The caller quiesces its own threads before shutting the core down; the core does not defend against one that does not.** Closing that gap needs a lifecycle lock held for the duration of every gated call rather than only at its gate, which is a change to the threading spine.

## Versioning and bindings

- `MXQ_API_VERSION` (major/minor/patch) is compiled into the header, reported by `mxq_core_version`, and checked at `mxq_core_init`. The header ships at 2.1.0. The major moved with the game axis: four rules functions and `mxq_engine_prepare` gained the game as a parameter, and the two per-game engine-profile fields left `MxqVersion` for `MxqGameProfile`. Nothing carried a game before, so there was no shape those five could have grown into behind `struct_size`. Within a major version: no removals, renames, signature changes, enum renumbering, struct-field changes, or thread-rule tightening; additions are new functions, appended enum constants, appended struct fields behind `struct_size`, and a reserved field claimed by a real one of its own width — the layout does not move, and a reserved field was never a value a caller could read. The compatibility promise is source-level across the repository's own two frontends, which ship in lockstep.
- The C API version, archive format version, store schema version, and engine profile are four independent axes and are never conflated.
- Swift consumes `mxq.h` through a module map; sessions and the store wrap in actors whose isolation enforces the single-owner rule at compile time, with blocking calls on a dedicated serial executor rather than the cooperative pool, and the search callback bridged by the standard non-capturing trampoline into a continuation.
- Windows consumes the same header through C# P/Invoke with ClangSharp-generated declarations and an `[UnmanagedCallersOnly]` static callback; every struct is blittable by construction, and the generated assembly carries `[assembly: DisableRuntimeMarshalling]` so that none of them can quietly acquire a marshalling stub.
- **The generated declarations are `[DllImport]`, not `[LibraryImport]`.** ClangSharp has no `LibraryImport` mode — through 21.1.8.4 its library-name option is the string to use in the `DllImport` attribute, and it emits `extern` methods, which `[LibraryImport]`'s `static partial` shape cannot be spelled as. Generation is what stops fifty-five signatures, fourteen value structs and every capacity constant from being transcribed by hand. Nothing observable is lost: with runtime marshalling disabled and every parameter blittable, the two attributes produce the same call, and the difference is only whether the stub is generated at compile time or at first call. Hand-written platform P/Invokes in the frontend, which no generator writes, do use `[LibraryImport]`, and there it is load-bearing rather than stylistic: under `DisableRuntimeMarshalling` a `DllImport` cannot honour `SetLastError`, while `LibraryImport`'s generated stub reads the error explicitly. Revisit if ClangSharp gains the mode.

## Capacity constants

- **`MXQ_DETAIL_CAP` is 128.** No fixed diagnostic in the core may exceed it, so the cap carries every path-free diagnostic whole. What it truncates is the diagnostics that embed a caller-supplied filesystem path, which is unbounded by nature: those are composed diagnosis-first so that the fact the caller can act on survives and the path is what loses. `MxqError.detail` is a bounded English diagnostic, never localized copy and never a channel — the status is the contract — so truncation costs nothing a caller may branch on.
- **There is no page-size constant.** `mxq_store_history_page` takes the page size as `limit` from the caller, and its buffer rule already makes an undersized `cap` a caller bug with `required_size` set. A constant here would be a second authority over a number the interface already makes the caller name.
- **There is no legal-move capacity constant.** The buffer protocol is the answer: `out` NULL with `cap` 0 asks for the count, and `MXQ_ERR_ARG_BUFFER_TOO_SMALL` carries `required_size`, so a caller can always size correctly in two calls and never has to guess. For a binding that would rather use one fixed array, the bound is derived per game, because the board is what it is derived from.

  **Mini Xiangqi: 83.** The full starting complement, with 2 chariots at 12 moves each, 2 cannons at 12, 2 horses at 8, 5 soldiers at 3, and a wazir general at 4, before any blocking is taken into account. A chariot's and a cannon's rays together span 12 squares on a 7×7 board, and a cannon cannot exceed that — in each direction it reaches the empty squares before the first blocker and at most one capture beyond a screen, and the screen and its target lie inside the same ray. The highest count actually found in a position the core accepts is **77**, at `4C2/2kP1P1/2P4/3N1P1/2N4/1C1K1P1/R5R w - - 0 1` — Red's full complement against a bare general — and that position is pinned by an assertion in the session suite, so a rules change that swells legal-move counts toward the ceiling cannot do it silently.

  **Xiangqi: 119.** The same derivation on a 9×10 board, where a chariot's or a cannon's rays span 8 + 9 = 17: 2 chariots at 17, 2 cannons at 17, 2 horses at 8, 2 elephants at 4, 2 advisors at 4, 5 soldiers at 3, and a general at 4. No measured position is pinned for it; the derived bound is what the buffer argument rests on.

  So a fixed `MxqMove[128]` is provably sufficient for both games. A fixed `MxqMove[64]` is provably insufficient for Mini Xiangqi, where the pinned 77-move position exceeds it outright; for Xiangqi it is not provably sufficient, the bound above being 119 with no position measured against it. No constant in `mxq.h` claims otherwise. A frontend that sizes one array for both sizes it for 119.
