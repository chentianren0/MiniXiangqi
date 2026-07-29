# Core C Interface

This document is for engineers and reviewers implementing or consuming the shared core. It defines the core's complete C-visible surface: the module and function inventory, handle model, data-passing conventions, error taxonomy, threading contract, and versioning policy. It does not define Xiangqi rules, persistence schemas, archive serialization, engine search policy, or UI behavior, which belong to the other contracts in this directory, nor implementation progress or work tracking, which belong in GitHub Issues.

> **Status: Accepted interface contract, version 1 shape.** The inventory, handle model, conventions, error taxonomy, threading contract, and versioning policy below are accepted as the implementation contract. Changes, including signature corrections discovered during implementation, go through ordinary reviewed contract changes. Items under **Need to discuss** are non-normative.

## Design principles

- One prefix, one header: functions `mxq_<module>_<verb>`, types `Mxq<Noun>`, constants `MXQ_<SNAKE>`, all declared in a single public `mxq.h` so both bindings — the Swift module map and the ClangSharp-generated C# declarations — are generated from one input.
- Exactly three opaque handle types: `MxqCore` (the singleton-enforced core), `MxqGame` (a game session), `MxqBlob` (an immutable byte buffer). Everything else crossing the boundary is a plain-old-data value struct copied into caller storage.
- Every value struct begins with `uint32_t struct_size`; structs grow append-only behind that guard. Enums carry explicit `int32_t` values and grow append-only. Booleans are `uint8_t` 0/1. Strings are UTF-8 and, where bounded by the frozen notation, carried by value in fixed-capacity arrays (`MxqMove.text[8]`, FEN capacity 96) so every struct is trivially copyable, blittable in C#, and `Sendable` in Swift.
- The caller never frees core memory. Outputs are copies into caller storage; the only pointer into core memory is `mxq_blob_bytes`, valid until `mxq_blob_release`.
- Every fallible function returns `MxqStatus` and takes an optional `MxqError *err` out-parameter for detail. There is no thread-local last-error.
- Moves use the frozen canonical notation `<from><to>` and positions the frozen 6-field FEN, per [xiangqi-rules.md](xiangqi-rules.md). Every rules query is defined over an initial position plus complete move history, never a bare FEN, because repetition and violation state derive from history.

## Modules and functions

Six groups, 53 functions.

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
MxqStatus mxq_core_init(const MxqCoreConfig *config, MxqCore **out_core, MxqError *err);
MxqStatus mxq_core_cancel_all(MxqCore *core, MxqError *err);  /* backgrounding */
MxqStatus mxq_core_shutdown(MxqCore *core, MxqError *err);    /* deterministic teardown */
```

`MxqCoreConfig` carries the frontend-supplied store directory, asset directory, caller `MXQ_API_VERSION`, and flags. `MxqVersion` reports the four independent version axes: the C API version, the archive format versions (current and minimum readable), the store schema version, and the engine profile identifiers — core revision, pinned fork revision, variant identifier, and NNUE SHA-256. The engine-profile fields are load-bearing, not diagnostics: conformance depends on a fork build, so every test report and saved diagnostic must be able to name the build that produced it.

`MxqCore` is handle-shaped but singleton-enforced: a second `mxq_core_init` before shutdown returns `MXQ_ERR_STATE_ALREADY_INITIALIZED`, because the embedded engine's process-global state admits one instance. The handle keeps teardown explicit and the signatures stable if that constraint ever lifts.

One config flag exists: `MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY`, a test affordance and never product behavior. The core has exactly one clock and identity provider — everything that needs an instant or a fresh `game_id` asks it — and under this flag it becomes deterministic, resetting at `mxq_core_init`, so store round-trip fixtures and archive golden files can be byte-stable across runs and machines. The exact deterministic sequences (a fixed epoch advancing one second per read; version-7-shaped identifiers from a counter) are documented normatively on the flag in `mxq.h`. Without the flag the provider reads the real clock and generates real version 7 UUIDs; the flag changes identity and time generation only — no rule, no schema, no store behavior.

### Rules facade — `mxq_game_` (sessions) and `mxq_rules_` (session-free)

A session composes the rules facade with the game's frozen configuration — `MxqPlayMode`, resolved `human_side`, `first_mover_choice`, `ai_level`, exact `ai_movetime_ms` (the enums `MxqPlayMode`, `MxqColor`, `MxqAiLevel`, and the first-mover choice correspond one-to-one to the serialized vocabulary in [game-data.md](game-data.md)) — because undo, resign, search eligibility, and the archive all depend on it. Sessions are **store-attached** when created or resumed (`mxq_game_create`, `mxq_game_resume_active`) and **detached read-only** when opened for replay or import preview (`mxq_store_history_open`, `mxq_game_open_archive`).

Attached sessions distinguish two mutation classes:

- **Ordinary mutations** — `mxq_game_apply_move`, `mxq_game_undo` — update the active game and commit the updated state inside the call before returning. There is no separate save operation.
- **Terminal commits** — `mxq_game_claim_draw`, `mxq_game_resign`, `mxq_game_confirm_result` — end the game: each performs one atomic transaction that commits the outcome, inserts the immutable History record, and clears the active-game reference, returning the new record id. Claim commits the draw with reason `threefold-repetition` and is legal only in the claimable state; resign commits the loss for the human side with reason `resignation` and is legal only in human-versus-AI play; confirm-result commits an unconfirmed natural terminal state as its actual result. After a terminal commit the session is archived — further mutations return `MXQ_ERR_STATE_SESSION_ARCHIVED` — and the caller still releases the handle. `mxq_store_archive_and_clear` is the fourth, state-derived archiving path for save-before-mode, and the only one that may record `ended-early`.

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
MxqStatus mxq_rules_start_fen(char *out, size_t cap, size_t *out_len, MxqError *err);
MxqStatus mxq_rules_validate_fen(MxqCore *core, const char *fen, MxqError *err);
MxqStatus mxq_rules_evaluate(MxqCore *core, const char *start_fen,
                             const char *const *moves, size_t move_count,
                             MxqPosition *out_position, MxqGameStatus *out_status,
                             size_t *out_first_illegal_index, MxqError *err);
MxqStatus mxq_rules_legal_moves(MxqCore *core, const char *start_fen,
                                const char *const *moves, size_t move_count,
                                MxqMove *out, size_t cap, size_t *out_count, MxqError *err);
```

Core value types:

- `MxqPosition` — 6-field FEN by value, side to move, `in_check`, `ply_count`, and `position_revision`, a per-session monotonic counter bumped by every accepted mutation. The revision is the staleness authority: an in-flight search result whose revision no longer matches is rejected even if no one cancelled it.
- `MxqGameStatus` — the live game state and derived affordances: `state` (`MXQ_GAME_ONGOING`, `MXQ_GAME_CLAIMABLE_DRAW`, `MXQ_GAME_RED_WINS`, `MXQ_GAME_BLACK_WINS`, `MXQ_GAME_DRAW` — exactly the fixture state identifiers), `reason` (`MxqEndReason`), `at_occurrence` for repetition-based outcomes, and `claim_available`, `undo_available`, `undo_plies`, `resign_available`, `search_expected` flags so frontends never re-derive rules policy.
- `MxqEndReason` — the fixture reason identifiers `CHECKMATE`, `STALEMATE`, `THREEFOLD_REPETITION`, `PERPETUAL_CHECK`, `PERPETUAL_CHASE`, the reserved mutual-violation reasons `MUTUAL_PERPETUAL_CHECK`, `MUTUAL_PERPETUAL_CHASE`, and the user-scoped `RESIGNATION`, `ENDED_EARLY`, plus `NONE`.
- Stored records use a distinct committed-outcome enum `MxqOutcome` — `RED_WINS`, `BLACK_WINS`, `DRAW`, `NONE` — matching the archive's serialized outcome vocabulary in [game-data.md](game-data.md). Live states (`ONGOING`, `CLAIMABLE_DRAW`) are never a committed outcome, and `NONE` (ended early) is never a live state; conflating the two vocabularies in one enum is the bug this split prevents.

`mxq_rules_evaluate` and `mxq_rules_legal_moves` take `(start_fen, moves[])` and are exactly the surface the approved conformance fixtures replay through; a fixture's every assertion maps onto their outputs.

### Search facade — `mxq_engine_` (preparation) and `mxq_search_`

```c
MxqStatus mxq_engine_plan(const MxqEngineBudget *budget, MxqEnginePlan *out, MxqError *err);
MxqStatus mxq_engine_prepare(MxqCore *core, const MxqEngineBudget *budget,
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

- `mxq_engine_plan` is a pure function of the frontend-supplied probe values implementing the accepted Hash-budget arithmetic, so every budget boundary in [testing.md](testing.md) is testable without an engine. `mxq_engine_prepare` recomputes the same plan, refuses below the 256 MiB minimum with `MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY` without initializing anything, and otherwise applies threads, Hash, the pinned variant configuration, and the NNUE — preflighting the network against the engine's observable load state so the engine's own fatal verification path is never reached.
- `mxq_search_start` does not retain the session: it snapshots the initial FEN, complete move list, `game_id`, `position_revision`, and the session's frozen `movetime` (the request's `movetime_ms` must equal it) before returning a ticket. Delivery applies the rejection ladder in order — cancelled → stale → malformed → illegal under the rules facade — and only a move surviving all four arrives as `MXQ_SEARCH_MOVE`. Stale rejection is enforced twice by design: the core compares `(game_id, position_revision)` before delivery, and the frontend compares again before applying, because neither check alone covers both race directions. Because every accepted mutation bumps the revision, an un-cancelled in-flight search that followed a mutation is neutralized by staleness. Cancellation is nonetheless a correctness requirement, not only a promptness optimization: a cancellation that follows no mutation — the platform suspension path in [engine-integration.md](engine-integration.md) — leaves the revision matching, so the cancelled rung is the only one that rejects the late result.
- `MxqSearchResult` is an inert value struct carrying outcome, the move, and bounded diagnostics (score, depth, nodes, elapsed, profile identifier). Applying the move is a separate explicit `mxq_game_apply_move`; no path exists from search output to committed state.
- The completion callback runs on the core's engine thread. Poll/wait are equivalent consumers for deterministic tests and binding fallback; the result is retained under its ticket until the next search or shutdown.

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

`MxqArchiveInfo` carries format version, the stable game identity, timestamps, mode, human side, `MxqOutcome`, `MxqEndReason`, and move count.

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

- `mxq_store_archive_and_clear` is the accepted atomic archive-and-clear in one transaction. On success the passed session is marked archived; later mutations on it return `MXQ_ERR_STATE_SESSION_ARCHIVED`; the caller still releases the handle.
- `mxq_store_history_page` returns records in the accepted order — pinned first, newest within each group, deterministic tie-break — as a core guarantee; frontends never re-sort.
- `mxq_store_active_summary` serves the Play destination and the save-and-continue confirmation without materializing a session.
- `out_library_revision` is a monotonic counter bumped by every committed store mutation: the accepted answer to library-change observation is return values plus this cheap staleness check, with no notification mechanism in the MVP.
- `mxq_store_import` returns `MXQ_IMPORT_EXISTING` with the existing record for an exact duplicate — success, not an error — and typed failures for every rejection class defined by the import pipeline in [game-data.md](game-data.md).

## Error taxonomy

`MxqStatus` codes are grouped in 1000-blocks; `mxq_status_domain` returns the block. Frontends select presentation family by domain and copy by exact code, and must tolerate unknown codes within a known domain (`default:` arm required).

| Domain | Block | Contents |
|---|---|---|
| `MXQ_DOMAIN_ARGUMENT` | 1000 | null pointers, invalid handles, `struct_size`/API-version mismatch, buffer-too-small (routine, carries the required size), encoding, range, wrong-thread, concurrent-use, reentrancy |
| `MXQ_DOMAIN_STATE` | 2000 | not/already initialized, shutting down, active game exists / missing, session read-only / archived, game over, undo/claim/resign unavailable, search in progress, engine not ready |
| `MXQ_DOMAIN_RULES` | 3000 | illegal move (distinct from) malformed move, invalid FEN (distinct from) illegal position, invalid history with first-illegal index |
| `MXQ_DOMAIN_STORE` | 4000 | I/O, corruption, busy, full, not found, identity conflict, migration failed, schema too new |
| `MXQ_DOMAIN_ARCHIVE` | 5000 | malformed, unsupported version, too large, inconsistent replay, terminal-claim mismatch |
| `MXQ_DOMAIN_ENGINE` | 6000 | insufficient memory, asset missing / mismatch, variant load failure, Hash allocation failure (reserved; reachable only after the fork change), no move, illegal result, faulted |
| `MXQ_DOMAIN_RESOURCE` | 7000 | core allocation failure, documented limit exceeded |
| `MXQ_DOMAIN_INTERNAL` | 9000 | invariant violations; reportable bugs |

Rules for the taxonomy:

- Malformed versus illegal is always distinguished: a string that is not `^[a-g][1-7][a-g][1-7]$` is malformed (a caller bug from the UI, expected data from an import); a well-formed move that is not legal is the ordinary illegal-move outcome with its accepted brief feedback.
- In version 1, `mxq_rules_validate_fen` applies the frozen structural encoding only; the illegal-position code is reserved for the future setup-legality predicate that [game-data.md](game-data.md) leaves open, and fixture positions are validated structurally plus by replay.
- Programming errors — the argument domain except buffer-too-small, plus not/already-initialized and read-only-session violations — assert in debug builds, return their code in release builds, and never change state. Everything else is ordinary control flow and must leave the last committed state intact.
- `MxqError` detail strings are short English diagnostics, never localized copy, never private game data; the raw subsystem code (SQLite result, FEN validation cause) rides along for diagnostics only and is never branched on.
- Accepted user-visible flows map by domain: any store-domain failure from `mxq_store_archive_and_clear` **or a terminal commit** drives the accepted 无法保存对局 retry flow, with the game remaining active and unchanged; `MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY` drives the accepted low-memory retry flow with a fresh probe per retry; a store-domain failure from `mxq_game_apply_move` or `mxq_game_undo` leaves the game exactly at the pre-mutation state and drives the accepted brief save-failure feedback in [interaction-design.md](interaction-design.md) — when the failed commit is an AI reply, the frontend requests a new search from the unchanged position instead; import failures map onto the import pipeline's user-visible classes, and the import time budget exhausts as a resource-domain limit.

## Threading contract

The core creates exactly one internal thread — the engine thread, sole caller of every engine entry point. Store operations execute on the calling thread under one internal mutex over one connection.

| Group | Callable from | Blocking |
|---|---|---|
| status/blob helpers, `mxq_core_version`, `mxq_engine_plan`, `mxq_rules_start_fen`, `mxq_archive_supported_versions` | any thread, including callbacks | no |
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
- **The search callback must copy and return.** It runs on the engine thread; inside it, only the status/blob helpers are legal — anything else returns `MXQ_ERR_ARG_REENTRANT` — and it must not block, because the engine thread is the resource it would deadlock. Its whole job is to hand the result to the frontend's dispatcher, which the architecture contract already requires before any UI mutation.
- **Engine reconfiguration serializes behind search.** `mxq_engine_prepare`/`teardown` run on the engine thread and return `MXQ_ERR_STATE_SEARCH_IN_PROGRESS` rather than stalling if a search is outstanding.
- **Backgrounding and termination.** `mxq_core_cancel_all` cancels cooperatively; callbacks still fire with the cancelled outcome. Termination mid-search loses nothing (the last accepted move was committed; search output never commits). Termination mid-transaction recovers to the last committed state through the store's journal. `mxq_core_shutdown` cancels all work, joins the engine thread, closes the store, and invalidates outstanding handles, which afterwards return `MXQ_ERR_ARG_INVALID_HANDLE` instead of touching freed memory.

## Versioning and bindings

- `MXQ_API_VERSION` (major/minor/patch) is compiled into the header, reported by `mxq_core_version`, and checked at `mxq_core_init`. Within a major version: no removals, renames, signature changes, enum renumbering, struct-field changes, or thread-rule tightening; additions are new functions, appended enum constants, and appended struct fields behind `struct_size`. The compatibility promise is source-level across the repository's own two frontends, which ship in lockstep.
- The C API version, archive format version, store schema version, and engine profile are four independent axes and are never conflated.
- Swift consumes `mxq.h` through a module map; sessions and the store wrap naturally in actors whose isolation enforces the single-owner rule at compile time, with blocking calls on a dedicated serial executor rather than the cooperative pool, and the search callback bridged by the standard non-capturing trampoline into a continuation.
- Windows consumes the same header through C# `[LibraryImport]` P/Invoke with ClangSharp-generated declarations and an `[UnmanagedCallersOnly]` static callback; every struct is blittable by construction. A C++/WinRT component was considered and rejected: it adds a second ABI and a projection layer while buying idioms that are a few lines over P/Invoke.

## Need to discuss

> The following questions are non-normative and are not implementation requirements.

- Whether `mxq_engine_query` should expose additional bounded diagnostics (hash utilization, NPS) for a future internal diagnostics surface.
- Concrete capacity constants (`MXQ_DETAIL_CAP`, page sizes, legal-move array headroom) to finalize against measured worst cases during implementation.
