# Shared-core C interface, error taxonomy, and threading contract

## Scope and evidence base

This draft proposes the shared core's C-visible interface: the module and function inventory, data-passing conventions, error taxonomy, threading contract, versioning policy, and how each frontend consumes it. It answers the open items recorded in `MiniXiangqi/docs/architecture.md` **Need to discuss** (exact C interface shape; internal threading model; error-code taxonomy) and `MiniXiangqi/docs/engine-integration.md` **Need to discuss** (the search facade's exact C-interface functions and the legal-move/result handoff).

Nothing here changes a repository. This is a workspace-only proposal.

**Boundary with the parallel archive/schema draft.** This document owns the C-level function, handle, error, and threading shape of every facade, including how store and archive operations are invoked and how their failures surface. It does **not** own the SQLite DDL, the archive serialization fields, the file format or extension, or equivalence and migration semantics. Wherever a persistent artifact appears here it is an **opaque byte buffer plus a version tag**; every such point is marked `[archive-contract]` and cross-references the companion draft.

Evidence was read from these clean local revisions:

- **FS** — `Fairy-Stockfish` at `c19b5f6c66894fdb0e88d0dd100e3885f744760a`.
- **APP** — `MiniXiangqi` docs and fixtures as of `docs/architecture.md`, `docs/engine-integration.md`, `docs/game-data.md`, `docs/xiangqi-rules.md`, `docs/product.md`, `docs/interaction-design.md`, `docs/testing.md`, and `fixtures/rules/README.md` on `main`.

Style follows the existing drafts: **Proven source facts** are cited to `file:line` or a named document section; everything else is labelled **Proposal** or **Inference**.

---

## 1. Proven source facts

### 1.1 Accepted contract facts the interface must satisfy

| # | Fact | Citation |
|---|---|---|
| C1 | The core is a C++ library exposing a **stable C interface**; frontends depend only on that interface through a thin per-platform binding (Swift; C# P/Invoke). | `docs/architecture.md:19`, `:43` |
| C2 | The core owns four facades: rules, search, game archive codec, library store. Fairy-Stockfish and SQLite are **internal and invisible** through the C interface. | `docs/architecture.md:21-24`, `:44` |
| C3 | Platform-specific values — storage paths, memory budgets, processor counts — are **passed in by the frontend**. | `docs/architecture.md:45` |
| C4 | Search runs off the frontend's main/UI thread. Every search is identified by **the game and position revision that requested it**. | `docs/architecture.md:49` |
| C5 | Undo, game completion, active-game replacement, leaving the relevant state, and backgrounding cancel outstanding work. Cancellation is cooperative, and **a result is rejected whenever its revision is stale — cancellation alone is not trusted**. | `docs/architecture.md:50` |
| C6 | Core callbacks deliver results to the frontend, which **re-enters its main actor or dispatcher before touching UI state**. Callbacks never mutate frontend state directly. | `docs/architecture.md:51` |
| C7 | The C boundary **documents, per function, which thread may call it and which thread delivers callbacks**. The core is responsible for its own internal synchronization. | `docs/architecture.md:52` |
| C8 | The frontend can **deterministically shut the core down** — engine, store, and outstanding work — without relying on process termination. | `docs/architecture.md:53` |
| C9 | Expected failures cross the C boundary as **typed error codes with retrievable detail, never as crashes, `exit()`, or silently wrong results**. | `docs/architecture.md:57` |
| C10 | Invalid imports, persistence failures, unavailable engine resources, and engine failures must not terminate the app or partially replace a committed game. **The last committed state always survives.** | `docs/architecture.md:58` |
| C11 | Search output **never mutates game state**, and adjudication never derives from search scores. | `docs/architecture.md:22`; `docs/xiangqi-rules.md:75`; `MiniXiangqi/AGENTS.md` "Product and architecture guardrails" |
| C12 | The search facade must provide: init and verified capability discovery; variant/evaluation configuration; asynchronous search with explicit resource limits; cooperative cancellation and deterministic teardown; **request identity and position-revision identity**; a proposed move or typed failure; and rejection of a result that is cancelled, stale, malformed, or **illegal under the rules facade**. | `docs/engine-integration.md:18-26` |
| C13 | All AI levels share one engine configuration and differ **only in `go movetime`**: 1000 / 3000 / 5000 ms. The level identifier and exact `movetime` are **frozen with a created game** and cannot change afterwards. | `docs/engine-integration.md:43-50` |
| C14 | `Threads` is initialized from the platform-reported active processor count at engine initialization. Hash uses one adaptive policy: `reserve = max(20% of available, 128 MiB)`, `usable = max(0, available - reserve)`, `budget = min(4 GiB, 50% of physical, usable)`, rounded **down to a 64 MiB multiple**; minimum accepted Hash is **256 MiB**. Below that the facade **does not initialize the AI engine and reports insufficient memory**; each retry re-probes. | `docs/engine-integration.md:51-57` |
| C15 | Engine, variant, NNUE, and option identifiers are **versioned with the internal profile** so a saved diagnostic record can identify the configuration that produced a move. | `docs/engine-integration.md:58` |
| C16 | The canonical machine notation for a move is `<from><to>`, e.g. `b1b4`; **no suffix exists**. This notation is canonical for fixtures, game archives, **and the shared core interface**. | `docs/xiangqi-rules.md:36` |
| C17 | The starting position is FEN `rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1`. A position record is a 6-field FEN; fields 3 and 4 are always `-`. Two position records denote the same position exactly when placement and side to move are equal. | `docs/xiangqi-rules.md:33`, `:37-38` |
| C18 | Fixture game states are exactly `ongoing`, `claimable-draw`, `red-wins`, `black-wins`, `draw`; reasons are `checkmate`, `stalemate`, `threefold-repetition`, `perpetual-check`, `perpetual-chase`, with `at_occurrence` for repetition-based outcomes. Results are named **by rule outcome, never by the side to move at detection**. | `docs/xiangqi-rules.md:79`; `fixtures/rules/README.md:33` |
| C19 | Neutral threefold repetition is **claim-gated**: eligibility does not commit a result; the user may continue or claim. A **unilateral perpetual violation is auto-terminal** at the third sustained occurrence and is presented through the standard natural-result flow. | `docs/xiangqi-rules.md:61-62` |
| C20 | Repetition and violation state derive from the game's **complete move history**. A bare position carries no prior occurrences. | `docs/xiangqi-rules.md:60` |
| C21 | Each fixture is `start_fen` + complete `moves` history + assertions on `in_check`, `result_fen`, exact `legal_moves`, `rejected_moves`, single-move `applied` probes, `game_state`, and a `boundary` prefix. The rules facade is gated by these on every platform. | `fixtures/rules/README.md:26-39` |
| C22 | The core **commits explicitly after every accepted move, undo, game completion, import, deletion, and other durable state change**. There is no deferred autosave. A committed move is the recovery boundary after exit or interruption. | `docs/game-data.md:35-36` |
| C23 | There is at most one active game. **保存并继续** places the active game in History and clears the active-game reference **in one atomic transaction**; the destination mode opens only after that commit succeeds. A failed archive leaves the previous active game intact and creates no new game. | `docs/game-data.md:42`, `:47-48`; `docs/interaction-design.md:150-158` |
| C24 | Import processes **one game at a time**, never creates or replaces the active game, and must create no persistent objects until validation succeeds — including validating the initial position, ordered moves, and terminal claim **through the rules facade**. | `docs/game-data.md:83`, `:92-99` |
| C25 | Same stable identity + same content → the core **returns the existing record** rather than inserting a duplicate. Same identity + different content → **rejected as an identity conflict** without changing persistent state. | `docs/game-data.md:87-88` |
| C26 | Undo is mode-aware: Free Play removes one ply; human-versus-AI Undo cancels an outstanding reply search and removes the triggering human move, **or** removes the completed AI reply together with the preceding human move. If the AI moved first, its opening move alone cannot be undone. | `docs/game-data.md:67-68`; `docs/interaction-design.md:162-166` |
| C27 | Resign is available **only** in human-versus-AI games; after confirmation it records a human loss. | `docs/product.md:38`; `docs/game-data.md:72` |
| C28 | A failed archive-and-clear presents **无法保存对局 / 当前对局仍然保留。请重试。** with **取消** and **重试**; Retry repeats the same atomic operation. | `docs/interaction-design.md:152-158` |
| C29 | A Hash budget below 256 MiB presents **无法启动 AI 对手 / 当前可用内存不足…** with **取消** and **重试**; Retry re-probes; no smaller Hash and no special cleanup pass. | `docs/interaction-design.md:114-127` |
| C30 | C-interface changes must verify **both platform bindings against the documented threading and error contract**. | `docs/testing.md:48` |
| C31 | The frontend supplies the store's location at startup. The pinned SQLite ships inside the core. | `docs/game-data.md:13-14` |
| C32 | `StoredGame` carries queryable summary fields — stable identity, dates, play mode, participants, result summary, imported provenance, pinned state — **plus a versioned archive blob**. | `docs/game-data.md:16` |
| C33 | The application has one main window per platform. | `docs/architecture.md:13`; `docs/product.md:26` |

### 1.2 Fairy-Stockfish threading facts (read-only, FS `c19b5f6c…`)

These ground the search facade's cancellation and delivery model in fact.

1. **Engine state is process-global, not per-instance.** `ThreadPool Threads` (`Fairy-Stockfish/src/thread.cpp:33`), `TranspositionTable TT` (`src/tt.cpp:31`), `UCI::OptionsMap Options` (`src/ucioption.cpp:39`), `VariantMap variants` (`src/variant.cpp:32`), and `Search::LimitsType Limits` (`src/search.cpp:44`) are all single global objects. **Inference:** the process can host exactly one engine and exactly one search at a time. The C interface must therefore not promise concurrent search sessions.

2. **Starting a search is asynchronous and returns immediately.** `ThreadPool::start_thinking()` (`src/thread.cpp:181-239`) first blocks on `main()->wait_for_search_finished()` (`src/thread.cpp:184`), clears `stop`/`abort` (`:186`), builds the root move list from `MoveList<LEGAL>` (`:192-195`), copies the root position into every thread (`:229-236`), and finally wakes the main search thread with `main()->start_searching()` (`:238`). The header comment states it "returns immediately" (`src/thread.cpp:178-179`). `UCI::go()` does nothing else (`src/uci.cpp:174`).

3. **Cancellation is a single atomic flag, polled cooperatively.** `ThreadPool::stop` is `std::atomic_bool` (`src/thread.h:118`). The UCI loop sets it for both `stop` and `quit` (`src/uci.cpp:335-337`). It is read at every non-root node with relaxed ordering (`src/search.cpp:722`), and a search that observes it discards its result rather than updating the best move, PV, or TT (`src/search.cpp:1394-1396`). The main thread additionally calls `check_time()` at every node (`src/search.cpp:708-709`), which does real work only once per 1024 calls (`src/search.cpp:1957-1961`) and raises `Threads.stop` when `Limits.movetime` has elapsed (`src/search.cpp:1983-1986`).

4. **Result delivery happens on the engine's main search thread, after full quiescence.** `MainThread::search()` sets `Threads.stop = true` (`src/search.cpp:240`), waits for every helper thread with `Threads.wait_for_search_finished()` (`src/search.cpp:243`), selects the reporting thread, and then prints `bestmove` (`src/search.cpp:305-308`). **Inference:** the natural in-process replacement for that `sync_cout` is a core-owned completion sink invoked at exactly that point — after the pool has quiesced but while still on the engine's main thread.

5. **The delivered move may come from a helper thread, not the main thread.** `bestThread = Threads.get_best_thread()` is used when `MultiPV == 1`, no depth limit is set, and skill limiting is disabled (`src/search.cpp:252-256`). The accepted profile is exactly that case: `MultiPV = 1`, movetime-only limits, `Skill Level = 20`, `UCI_LimitStrength = false` (`docs/engine-integration.md:44`, `:45`), and `Skill::enabled()` is `level < 20` (`src/search.cpp:99`). **Inference:** the facade must read the result through the pool's own selection, not from a specific thread object.

6. **Reconfiguring the engine blocks on the running search.** `TranspositionTable::resize()` begins with `Threads.main()->wait_for_search_finished()` (`src/tt.cpp:65`) and `ThreadPool::set()` does the same (`src/thread.cpp:142`) before recreating threads and resizing the TT (`src/thread.cpp:157`). Both are wired to option changes (`src/ucioption.cpp:62-64`). **Inference:** `Hash` and `Threads` can only be applied while no search is running; the facade must serialize configuration against search.

7. **Two unmodified engine paths call `exit(EXIT_FAILURE)` and would kill the app.**
   - `TranspositionTable::resize()` exits when the TT allocation fails (`src/tt.cpp:71-77`, exit at `:76`).
   - `Eval::NNUE::verify()` exits when the configured net was not loaded (`src/evaluate.cpp:145-162`, exit at `:162`), and it is invoked **from inside the search thread** at `src/search.cpp:191`.
   - On Windows, `aligned_large_pages_free()` exits when `VirtualFree` fails (`src/misc.cpp:474-481`).
   This directly contradicts C9/C10.

8. **The NNUE load state is externally observable, so NNUE can be preflighted without `verify()`.** `Eval::eval_file_loaded` is an exported symbol (`Fairy-Stockfish/src/evaluate.h:39`, defined `src/evaluate.cpp:67`), and `verify()`'s own failure test is `useNNUE && eval_file.find(eval_file_loaded) == string::npos` (`src/evaluate.cpp:145`). **Inference:** the core can reproduce that test itself before ever issuing `go`, and never let `verify()` reach its `exit()`. This closes the NNUE case of the patch trigger anticipated in `discussion-drafts/axf-evaluation-plan.md:152` **without** a fork change. The TT case (fact 7a) is not closable that way.

9. **Move parsing already rejects illegal moves.** `UCI::to_move()` enumerates `MoveList<LEGAL>` and returns `MOVE_NONE` when the string does not match a legal move (`src/uci.cpp:565-582`, return at `:581`). **Inference:** malformed and illegal move strings collapse into one engine-level outcome; the C interface must separate them (`MXQ_ERR_RULES_MALFORMED_MOVE` vs `MXQ_ERR_RULES_ILLEGAL_MOVE`) itself.

10. **FEN validation is structural and has a typed result.** `FEN::validate_fen()` returns a `FenValidation` enum with `FEN_OK = 1` and 14 negative causes including `FEN_TOUCHING_KINGS`, `FEN_INVALID_NB_PARTS`, `FEN_INVALID_CHAR` (`src/apiutil.h:445-462`, function at `:993`). As recorded in `discussion-drafts/fen-notation-fixtures-draft.md` §9, it accepts kings-facing FENs that move-level legality treats as in-check.

11. **A search started in a position with no legal move returns `MOVE_NONE`.** `MainThread::search()` pushes `MOVE_NONE` into `rootMoves` when the legal set is empty (`src/search.cpp:193-195`) and still prints a `bestmove` (`src/search.cpp:305`). **Inference:** the facade must refuse to start a search in a terminal position rather than interpret a null best move.

12. **Optional-game-end value elements are meaningless when the flag is false**, and repetition adjudication is history-dependent (`discussion-drafts/fen-notation-fixtures-draft.md` §7 and open flag 5, citing `Fairy-Stockfish/src/pyffish.cpp:339-354` and `src/position.cpp:2651-2707`). **Inference:** every rules query in the C interface must be defined over `(start FEN, complete move list)`, never over a bare FEN.

---

## 2. Proposal — interface inventory

### 2.0 Naming and shape

**Proposal.** One prefix, `mxq`, in three consistent forms:

| Kind | Form | Example |
|---|---|---|
| Functions | `mxq_<module>_<verb>` (lower snake) | `mxq_game_apply_move` |
| Types | `Mxq<Noun>` (upper camel) | `MxqSearchResult` |
| Enum constants / macros | `MXQ_<SCREAMING_SNAKE>` | `MXQ_ERR_RULES_ILLEGAL_MOVE` |

Rationale: `sqlite3_`/`SDL_`-style prefixing is the least surprising to both bindings; Swift's C importer keeps `mxq_*` functions verbatim and strips the shared `MXQ_` prefix from enum cases when the enum is declared with `NS_ENUM`-compatible shape; ClangSharp maps the same header to idiomatic C# without renaming rules.

Everything lives in **one public header**, `mxq.h`. A single header keeps the ABI surface auditable, keeps ClangSharp/`swift-format` generation to one input, and matches the fact that all five facades share the status enum and buffer conventions.

**Six C-visible groups: a common prelude plus the five named modules. 52 functions total.**

| Group | Prefix | Functions |
|---|---|---|
| Common prelude | `mxq_status_`, `mxq_blob_` | 5 |
| Core lifecycle | `mxq_core_` | 4 |
| Rules facade | `mxq_game_`, `mxq_rules_` | 19 |
| Search facade | `mxq_engine_`, `mxq_search_` | 9 |
| Archive codec boundary | `mxq_archive_` | 4 |
| Library store | `mxq_store_` | 11 |

### 2.1 Common prelude

```c
#define MXQ_API_VERSION_MAJOR 1
#define MXQ_API_VERSION_MINOR 0
#define MXQ_API_VERSION_PATCH 0
#define MXQ_API_VERSION ((MXQ_API_VERSION_MAJOR << 16) | (MXQ_API_VERSION_MINOR << 8) | MXQ_API_VERSION_PATCH)

/* Frozen notation capacities. Move strings are exactly "<from><to>" (C16);
   a 7x7 six-field FEN never exceeds 71 bytes (C17). Both padded and asserted. */
#define MXQ_MOVE_CAP        8
#define MXQ_FEN_CAP        96
#define MXQ_UUID_CAP       37   /* 36 chars + NUL; textual form owned by [archive-contract] */
#define MXQ_PROFILE_ID_CAP 64
#define MXQ_DETAIL_CAP    192

typedef int32_t MxqStatus;      /* MXQ_OK == 0; see §4 */

typedef struct MxqError {
    uint32_t  struct_size;      /* = sizeof(MxqError) */
    MxqStatus code;
    int32_t   subsystem_code;   /* raw SQLite / FenValidation / errno code, diagnostics only */
    char      detail[MXQ_DETAIL_CAP];  /* UTF-8, NUL-terminated, no private game data */
} MxqError;

typedef struct MxqCore MxqCore;   /* opaque */
typedef struct MxqGame MxqGame;   /* opaque */
typedef struct MxqBlob MxqBlob;   /* opaque, immutable byte buffer */

MxqStatus   mxq_status_domain(MxqStatus status);
const char *mxq_status_name(MxqStatus status);      /* immortal ASCII literal; never freed */

const uint8_t *mxq_blob_bytes(const MxqBlob *blob); /* NULL only for NULL blob */
size_t         mxq_blob_len(const MxqBlob *blob);
void           mxq_blob_release(MxqBlob *blob);     /* NULL-safe, never fails */
```

### 2.2 Core lifecycle — `mxq_core_`

```c
typedef struct MxqCoreConfig {
    uint32_t    struct_size;
    uint32_t    api_version;        /* caller passes MXQ_API_VERSION */
    const char *store_directory;    /* UTF-8 absolute path; core owns the filename inside it (C31) */
    const char *asset_directory;    /* UTF-8 absolute path; variant config + NNUE (C3) */
    uint32_t    flags;              /* MXQ_CORE_FLAG_NONE | MXQ_CORE_FLAG_EPHEMERAL_STORE (tests) */
} MxqCoreConfig;

typedef struct MxqVersion {
    uint32_t struct_size;
    uint32_t api_version;
    char     core_revision[MXQ_PROFILE_ID_CAP];   /* app-repo revision that built the core */
    char     engine_revision[MXQ_PROFILE_ID_CAP]; /* pinned Fairy-Stockfish fork revision */
    char     variant_id[MXQ_PROFILE_ID_CAP];      /* pinned custom variant identifier */
    char     nnue_sha256[65];                     /* C15 */
    uint32_t archive_version_current;             /* [archive-contract] */
    uint32_t archive_version_min_readable;        /* [archive-contract] */
    uint32_t store_schema_version;                /* [archive-contract] */
} MxqVersion;

MxqStatus mxq_core_version(MxqVersion *out, MxqError *err);            /* callable before init */
MxqStatus mxq_core_init(const MxqCoreConfig *config, MxqCore **out_core, MxqError *err);
MxqStatus mxq_core_cancel_all(MxqCore *core, MxqError *err);           /* backgrounding (C5) */
MxqStatus mxq_core_shutdown(MxqCore *core, MxqError *err);             /* deterministic (C8) */
```

`MxqCore` is handle-shaped but **singleton-enforced**: a second `mxq_core_init` before shutdown returns `MXQ_ERR_STATE_ALREADY_INITIALIZED`, because FS's globals (§1.2 fact 1) make a second instance impossible. Handle shape is kept anyway so tests can hold the core explicitly and so a future out-of-process engine does not force a signature change.

### 2.3 Rules facade — `mxq_game_` (session) and `mxq_rules_` (session-free)

```c
typedef enum MxqColor    { MXQ_COLOR_RED = 0, MXQ_COLOR_BLACK = 1 } MxqColor;
typedef enum MxqPlayMode { MXQ_MODE_HUMAN_VS_AI = 0, MXQ_MODE_FREE_PLAY = 1 } MxqPlayMode;
typedef enum MxqAiLevel  { MXQ_AI_FAST = 0, MXQ_AI_STANDARD = 1, MXQ_AI_DEEP = 2 } MxqAiLevel;

/* Exactly the fixture state identifiers (C18). */
typedef enum MxqGameState {
    MXQ_GAME_ONGOING        = 0,
    MXQ_GAME_CLAIMABLE_DRAW = 1,
    MXQ_GAME_RED_WINS       = 2,
    MXQ_GAME_BLACK_WINS     = 3,
    MXQ_GAME_DRAW           = 4
} MxqGameState;

/* First five are the fixture reasons (C18); last two are the product's
   non-rule terminations (C27, docs/product.md:52). Their *serialized*
   identifiers are [archive-contract]. */
typedef enum MxqEndReason {
    MXQ_REASON_NONE = 0,
    MXQ_REASON_CHECKMATE,
    MXQ_REASON_STALEMATE,
    MXQ_REASON_THREEFOLD_REPETITION,
    MXQ_REASON_PERPETUAL_CHECK,
    MXQ_REASON_PERPETUAL_CHASE,
    MXQ_REASON_RESIGNATION,
    MXQ_REASON_ENDED_EARLY
} MxqEndReason;

typedef struct MxqMove { char text[MXQ_MOVE_CAP]; } MxqMove;   /* "b1b4\0", padded */

typedef struct MxqPosition {
    uint32_t struct_size;
    char     fen[MXQ_FEN_CAP];      /* 6-field FEN, frozen encoding (C17) */
    MxqColor side_to_move;
    uint8_t  in_check;              /* 0/1 */
    uint32_t ply_count;             /* plies played from the session's initial position */
    uint32_t position_revision;     /* monotonic per session; bumped by every accepted mutation (C4) */
} MxqPosition;

typedef struct MxqGameStatus {
    uint32_t     struct_size;
    MxqGameState state;
    MxqEndReason reason;            /* MXQ_REASON_NONE iff state == ONGOING */
    uint32_t     at_occurrence;     /* repetition-based outcomes only, else 0 (C18) */
    uint8_t      claim_available;   /* == (state == CLAIMABLE_DRAW) (C19) */
    uint8_t      undo_available;
    uint32_t     undo_plies;        /* plies the next undo would remove: 0, 1, or 2 (C26) */
    uint8_t      resign_available;  /* human-vs-AI only (C27) */
    uint8_t      search_expected;   /* the side to move is the AI and no search is outstanding */
} MxqGameStatus;

typedef struct MxqGameConfig {
    uint32_t    struct_size;
    MxqPlayMode mode;
    MxqColor    human_color;        /* ignored in Free Play */
    MxqAiLevel  ai_level;           /* ignored in Free Play */
    uint32_t    ai_movetime_ms;     /* frozen exact value: 1000 / 3000 / 5000 (C13) */
} MxqGameConfig;

/* --- lifecycle (4) --- */
MxqStatus mxq_game_create(MxqCore *core, const MxqGameConfig *config,
                          MxqGame **out_game, MxqError *err);
MxqStatus mxq_game_resume_active(MxqCore *core, MxqGame **out_game,
                                 uint8_t *out_exists, MxqError *err);
MxqStatus mxq_game_open_archive(MxqCore *core, const uint8_t *bytes, size_t len,
                                MxqGame **out_game, MxqError *err);  /* [archive-contract] */
void      mxq_game_release(MxqGame *game);                            /* NULL-safe, never fails */

/* --- queries (7) --- */
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

/* --- mutations (4); on a store-attached session each commits before returning (C22) --- */
MxqStatus mxq_game_apply_move(MxqGame *game, const char *move,
                              MxqPosition *out_after, MxqGameStatus *out_status, MxqError *err);
MxqStatus mxq_game_undo(MxqGame *game, uint32_t *out_plies_removed, MxqError *err);
MxqStatus mxq_game_claim_draw(MxqGame *game, MxqError *err);
MxqStatus mxq_game_resign(MxqGame *game, MxqError *err);

/* --- session-free rules facade (4): the fixture-harness and import-validation surface --- */
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

`mxq_rules_evaluate` + `mxq_rules_legal_moves` are exactly what a fixture needs (C21): `in_check` and `result_fen` come from `MxqPosition`; `game_state`/`reason`/`at_occurrence` from `MxqGameStatus`; `legal_moves` from the enumeration; `rejected_moves` by set membership; `applied` probes by appending one move and re-evaluating; `boundary` by truncating the move list to `prefix_len`. They take `(start_fen, moves[])` and never a bare FEN, per §1.2 fact 12 / C20.

Both take `MxqCore*` because the pinned variant must be loaded; neither touches the store, the engine threads, or any session.

### 2.4 Search facade — `mxq_engine_` (preflight) and `mxq_search_`

```c
typedef struct MxqEngineBudget {
    uint32_t struct_size;
    uint64_t available_memory_bytes;   /* fresh platform probe, supplied per call (C14, C29) */
    uint64_t physical_memory_bytes;
    uint32_t active_processor_count;
} MxqEngineBudget;

typedef struct MxqEnginePlan {
    uint32_t struct_size;
    uint64_t reserve_bytes;      /* max(20% of available, 128 MiB) */
    uint64_t usable_bytes;       /* max(0, available - reserve) */
    uint64_t budget_bytes;       /* min(4 GiB, 50% physical, usable) */
    uint32_t hash_mib;           /* budget rounded down to 64 MiB; 0 when below the minimum */
    uint32_t threads;
    uint8_t  sufficient;         /* hash_mib >= 256 */
} MxqEnginePlan;

typedef enum MxqEngineState {
    MXQ_ENGINE_UNPREPARED = 0,
    MXQ_ENGINE_READY      = 1,
    MXQ_ENGINE_SEARCHING  = 2,
    MXQ_ENGINE_FAULTED    = 3
} MxqEngineState;

/* Pure function of its inputs: no engine, no core state. Exists so every budget
   boundary required by docs/testing.md:110 is testable without an engine. */
MxqStatus mxq_engine_plan(const MxqEngineBudget *budget, MxqEnginePlan *out, MxqError *err);

MxqStatus mxq_engine_prepare(MxqCore *core, const MxqEngineBudget *budget,
                             MxqEnginePlan *out_applied, MxqError *err);
MxqStatus mxq_engine_teardown(MxqCore *core, MxqError *err);
MxqStatus mxq_engine_query(MxqCore *core, MxqEngineState *out_state,
                           char *out_profile_id, size_t cap, size_t *out_len, MxqError *err);

typedef struct MxqSearchRequest {
    uint32_t struct_size;
    uint64_t game_id;             /* identity of the requesting game (C4) */
    uint32_t position_revision;   /* identity of the requesting position (C4) */
    uint32_t movetime_ms;         /* must equal the session's frozen value (C13) */
} MxqSearchRequest;

typedef enum MxqSearchOutcome {
    MXQ_SEARCH_MOVE      = 0,   /* legal, validated, current */
    MXQ_SEARCH_CANCELLED = 1,
    MXQ_SEARCH_STALE     = 2,   /* completed, but the session moved on (C5) */
    MXQ_SEARCH_FAILED    = 3
} MxqSearchOutcome;

typedef struct MxqSearchResult {
    uint32_t         struct_size;
    uint64_t         ticket;
    uint64_t         game_id;
    uint32_t         position_revision;
    MxqSearchOutcome outcome;
    MxqMove          move;            /* valid iff outcome == MXQ_SEARCH_MOVE */
    MxqStatus        failure;         /* MXQ_OK unless outcome == MXQ_SEARCH_FAILED */
    /* bounded diagnostics only; never an adjudication input (C11) */
    int32_t          score_cp;
    int32_t          mate_in;         /* 0 = none */
    uint32_t         depth;
    uint64_t         nodes;
    uint32_t         elapsed_ms;
    char             profile_id[MXQ_PROFILE_ID_CAP];   /* C15 */
} MxqSearchResult;

typedef void (*MxqSearchCallback)(const MxqSearchResult *result, void *user_data);

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

`mxq_search_start` takes `const MxqGame*` but **does not retain it**. It copies `(initial FEN, complete move list, game_id, position_revision, movetime_ms)` into the request before returning, so the session handle never crosses a thread boundary and never outlives the caller's ownership. Passing the complete history — not a FEN — is required by C20 and §1.2 fact 12.

`mxq_search_wait` exists so `docs/testing.md:104` cancellation and stale-result validation is deterministic without timers.

### 2.5 Archive codec boundary — `mxq_archive_`

The archive's contents, field set, wire format, and file extension are `[archive-contract]`. This module exposes only the C-level boundary: opaque bytes in, opaque bytes out, plus the minimum decoded summary the store must index and the History list must render (C32; `docs/product.md:57`).

```c
typedef struct MxqArchiveInfo {
    uint32_t     struct_size;
    uint32_t     format_version;                 /* the version tag; meaning is [archive-contract] */
    char         game_uuid[MXQ_UUID_CAP];        /* stable identity (C25) */
    int64_t      created_unix_ms;
    MxqPlayMode  mode;
    MxqColor     human_color;
    uint8_t      has_human_color;
    MxqGameState result;
    MxqEndReason reason;
    uint32_t     move_count;
} MxqArchiveInfo;

/* Structural decode only: version dispatch, size/structure limits, field shapes.
   Does NOT replay the move line. */
MxqStatus mxq_archive_probe(MxqCore *core, const uint8_t *bytes, size_t len,
                            MxqArchiveInfo *out, MxqError *err);

/* Full validation: probe, then replay the initial position and every move through
   the rules facade and check the terminal claim (C24). */
MxqStatus mxq_archive_validate(MxqCore *core, const uint8_t *bytes, size_t len,
                               MxqArchiveInfo *out, MxqError *err);

/* Encode a session at its current committed state, with the classification the
   caller has already derived from that state (C23). */
MxqStatus mxq_archive_encode(MxqCore *core, const MxqGame *game,
                             MxqEndReason ended_early_reason,
                             MxqBlob **out_blob, MxqError *err);

MxqStatus mxq_archive_supported_versions(uint32_t *out_min_readable,
                                         uint32_t *out_current, MxqError *err);
```

### 2.6 Library store — `mxq_store_`

```c
typedef struct MxqRecordSummary {
    uint32_t     struct_size;
    uint64_t     record_id;                   /* store-local; not the archive identity */
    char         game_uuid[MXQ_UUID_CAP];
    int64_t      history_added_unix_ms;       /* the sort key (docs/game-data.md:86) */
    int64_t      created_unix_ms;
    MxqPlayMode  mode;
    MxqColor     human_color;
    uint8_t      has_human_color;
    MxqGameState result;
    MxqEndReason reason;
    uint32_t     move_count;
    uint8_t      pinned;
    uint8_t      imported;
} MxqRecordSummary;

typedef enum MxqImportOutcome {
    MXQ_IMPORT_CREATED  = 0,
    MXQ_IMPORT_EXISTING = 1     /* same identity + same content: existing record returned (C25) */
} MxqImportOutcome;

/* --- active game (3) --- */
MxqStatus mxq_store_active_exists(MxqCore *core, uint8_t *out_exists, MxqError *err);
MxqStatus mxq_store_active_summary(MxqCore *core, MxqRecordSummary *out,
                                   MxqGameStatus *out_status, uint8_t *out_exists, MxqError *err);
MxqStatus mxq_store_archive_and_clear(MxqCore *core, MxqGame *active,
                                      uint64_t *out_record_id, MxqError *err);

/* --- history (6) --- */
MxqStatus mxq_store_history_count(MxqCore *core, uint32_t *out_count,
                                  uint64_t *out_library_revision, MxqError *err);
MxqStatus mxq_store_history_page(MxqCore *core, uint32_t offset, uint32_t limit,
                                 MxqRecordSummary *out, size_t cap, size_t *out_count,
                                 uint64_t *out_library_revision, MxqError *err);
MxqStatus mxq_store_history_get(MxqCore *core, uint64_t record_id,
                                MxqRecordSummary *out, MxqError *err);
MxqStatus mxq_store_history_open(MxqCore *core, uint64_t record_id,
                                 MxqGame **out_replay, MxqError *err);  /* detached, read-only */
MxqStatus mxq_store_history_set_pinned(MxqCore *core, uint64_t record_id,
                                       uint8_t pinned, MxqError *err);
MxqStatus mxq_store_history_delete(MxqCore *core, uint64_t record_id, MxqError *err);

/* --- interchange (2) --- */
MxqStatus mxq_store_export(MxqCore *core, uint64_t record_id,
                           MxqBlob **out_blob, MxqError *err);
MxqStatus mxq_store_import(MxqCore *core, const uint8_t *bytes, size_t len,
                           MxqImportOutcome *out_outcome, uint64_t *out_record_id,
                           MxqRecordSummary *out_summary, MxqError *err);
```

`mxq_store_active_summary` exists so the Play destination can render the active game's metadata and the save-and-continue confirmation (`docs/interaction-design.md:131`, `:140`) **without** materializing a session — it returns the persisted summary plus the derived `MxqGameStatus`.

`mxq_store_archive_and_clear` performs the one atomic transaction of C23: encode → insert History record → clear the active-game reference → commit. On success the passed session is marked archived; every subsequent mutation on it returns `MXQ_ERR_STATE_SESSION_ARCHIVED`, and the caller still owns the handle and must release it.

`out_library_revision` is a monotonic counter bumped by every committed store mutation. It is the minimal answer to `docs/architecture.md:83` / `docs/game-data.md:125` ("how frontends observe library changes") that does not commit the project to a notification mechanism: return values only, plus a cheap staleness check. See decision 7 in §8.

---

## 3. Proposal — data-passing conventions

### 3.1 Strings and the frozen notation

- Every `const char *` in and every `char *` out is **UTF-8, NUL-terminated**. The core rejects invalid UTF-8 with `MXQ_ERR_ARG_ENCODING`.
- Move strings use only the canonical `<from><to>` form (C16): exactly four ASCII characters matching `^[a-g][1-7][a-g][1-7]$`. Anything else is `MXQ_ERR_RULES_MALFORMED_MOVE` — a *different* code from `MXQ_ERR_RULES_ILLEGAL_MOVE`, because §1.2 fact 9 shows the engine collapses both into `MOVE_NONE` and the frontends need to distinguish a bug from a user's illegal tap.
- FEN strings are the frozen six-field encoding (C17). The core never emits an abbreviated FEN and never accepts one.
- Because both are bounded and short, they are carried **by value inside structs** (`MxqMove.text[8]`, `MxqPosition.fen[96]`) rather than as pointers. This makes every value struct trivially copyable, `Sendable` in Swift without unsafe annotation, and blittable in C#, and removes all string lifetime questions from the hot path.

### 3.2 Handles versus value structs

Exactly three opaque handle types: `MxqCore`, `MxqGame`, `MxqBlob`. Everything else is a POD value struct copied across the boundary.

Every value struct begins with `uint32_t struct_size`. Callers set it on input structs; the core sets it on output structs; a mismatch against every known historical size yields `MXQ_ERR_ARG_STRUCT_SIZE`. This is the standard sized-struct pattern and is what makes additive struct growth safe (§7).

### 3.3 Buffer ownership

**One rule: the caller never calls `free()` on core memory.** Three concrete forms:

1. **Fixed-size out-params.** `MxqPosition *out`, `MxqGameStatus *out`, `uint64_t *out_ticket`. Caller-owned storage; the core writes into it. Nothing to free.
2. **Caller-provided arrays with required-size reporting.** `(T *out, size_t cap, size_t *out_count)`. If `cap` is too small the core writes the required count to `*out_count`, writes nothing to `out`, and returns `MXQ_ERR_ARG_BUFFER_TOO_SMALL`. Passing `out == NULL, cap == 0` is the legal "how big?" query. `*out_count` is always written on success and on truncation. For strings the same shape uses `(char *out, size_t cap, size_t *out_len)` where `*out_len` **includes** the terminating NUL.
3. **Opaque immutable blobs.** `MxqBlob *` for archive bytes, whose size is unbounded and not knowable without doing the work. Created by `mxq_archive_encode` and `mxq_store_export`; read with `mxq_blob_bytes`/`mxq_blob_len`; released with `mxq_blob_release`. A blob is immutable and refcount-free: exactly one owner, the creator's caller.

`mxq_blob_bytes` is the **only** function that returns a pointer into core memory. That pointer is valid until `mxq_blob_release`, is `const`, points at immutable bytes, and is therefore readable from **any** thread during that window. Everything else the core returns is a copy into caller storage, so no other returned pointer has thread affinity at all.

`mxq_status_name` returns an immortal ASCII literal compiled into the library. It is safe to call from any thread at any time, including before `mxq_core_init` and inside a callback.

Practical caps for the array form, from the frozen rules: the start position has 19 legal moves (`discussion-drafts/fen-notation-fixtures-draft.md` §2), so `MXQ_MAX_LEGAL_MOVES = 128` is generous headroom and the frontends can use a fixed stack array and never hit form 2's truncation path in practice.

### 3.4 Booleans and enums

C99 `_Bool` has no guaranteed ABI width across the MSVC and Clang toolchains this project must span, so every boolean crossing the boundary is `uint8_t` with values 0 and 1. Every enum is given an explicit `int32_t` underlying width by assigning explicit values and never relying on the compiler's choice.

---

## 4. Proposal — error taxonomy

### 4.1 Representation

`MxqStatus` is a plain `int32_t` enum. `MXQ_OK == 0`. Non-zero codes are grouped into 1000-blocks by domain, and `mxq_status_domain(s)` returns `(s / 1000) * 1000`, so a frontend can switch on the domain to pick a *presentation family* and on the exact code to pick copy.

Detail travels in an optional `MxqError *err` out-parameter present on every fallible function. `err` may be `NULL` when the caller does not want detail. This deliberately avoids a `errno`-style thread-local last-error: a thread-local would be wrong the moment a Swift `async` function resumed on a different cooperative-pool thread than the one that made the call, and it would be unusable from inside the search callback. The `MxqError` out-param is fully reentrant and thread-agnostic.

`MxqError.detail` carries a short English diagnostic string — never localized copy, never private game data (`docs/architecture.md:59`). `MxqError.subsystem_code` carries the raw underlying code (SQLite result code, `FenValidation` value per §1.2 fact 10, `errno`) for diagnostics only; frontends must never branch on it.

### 4.2 Domains and codes

```c
#define MXQ_OK 0

#define MXQ_DOMAIN_ARGUMENT 1000   /* contract violations — see §4.3 */
#define MXQ_DOMAIN_STATE    2000   /* lifecycle / availability — expected */
#define MXQ_DOMAIN_RULES    3000   /* rules-illegal input — expected */
#define MXQ_DOMAIN_STORE    4000   /* persistence — runtime */
#define MXQ_DOMAIN_ARCHIVE  5000   /* untrusted archive input — runtime */
#define MXQ_DOMAIN_ENGINE   6000   /* engine — runtime */
#define MXQ_DOMAIN_RESOURCE 7000   /* memory / limits — runtime */
#define MXQ_DOMAIN_INTERNAL 9000   /* should never happen — runtime, reportable */
```

| Code | Meaning | Class |
|---|---|---|
| `MXQ_ERR_ARG_NULL` 1001 | required pointer was `NULL` | programming |
| `MXQ_ERR_ARG_INVALID_HANDLE` 1002 | unknown, released, or wrong-type handle | programming |
| `MXQ_ERR_ARG_STRUCT_SIZE` 1003 | `struct_size` unrecognized | programming |
| `MXQ_ERR_ARG_API_VERSION` 1004 | `MxqCoreConfig.api_version` not supported by this build | programming |
| `MXQ_ERR_ARG_BUFFER_TOO_SMALL` 1005 | **recoverable**; `*out_count`/`*out_len` holds the requirement | routine |
| `MXQ_ERR_ARG_ENCODING` 1006 | not valid UTF-8 | programming |
| `MXQ_ERR_ARG_RANGE` 1007 | numeric argument outside its documented range | programming |
| `MXQ_ERR_ARG_WRONG_THREAD` 1008 | called from a thread the contract forbids (§5) | programming |
| `MXQ_ERR_ARG_CONCURRENT_USE` 1009 | two threads used one session concurrently | programming |
| `MXQ_ERR_ARG_REENTRANT` 1010 | called from inside a core callback (§5.7) | programming |
| `MXQ_ERR_STATE_NOT_INITIALIZED` 2001 | core not initialized | programming |
| `MXQ_ERR_STATE_ALREADY_INITIALIZED` 2002 | second `mxq_core_init` | programming |
| `MXQ_ERR_STATE_SHUTTING_DOWN` 2003 | call raced `mxq_core_shutdown` | runtime |
| `MXQ_ERR_STATE_ACTIVE_GAME_EXISTS` 2004 | `mxq_game_create` while an active game exists (C23) | expected |
| `MXQ_ERR_STATE_NO_ACTIVE_GAME` 2005 | archive-and-clear with no active game | expected |
| `MXQ_ERR_STATE_SESSION_READ_ONLY` 2006 | mutation on a replay/import session | programming |
| `MXQ_ERR_STATE_SESSION_ARCHIVED` 2007 | mutation after archive-and-clear | expected |
| `MXQ_ERR_STATE_GAME_OVER` 2008 | move or search request in a terminal state (§1.2 fact 11) | expected |
| `MXQ_ERR_STATE_UNDO_UNAVAILABLE` 2009 | undo at the earliest valid boundary (C26) | expected |
| `MXQ_ERR_STATE_CLAIM_UNAVAILABLE` 2010 | claim while `state != CLAIMABLE_DRAW` (C19) | expected |
| `MXQ_ERR_STATE_RESIGN_UNAVAILABLE` 2011 | resign in Free Play (C27) | expected |
| `MXQ_ERR_STATE_SEARCH_IN_PROGRESS` 2012 | second search, or reconfigure during search (§1.2 fact 6) | expected |
| `MXQ_ERR_STATE_ENGINE_NOT_READY` 2013 | search before a successful `mxq_engine_prepare` | expected |
| `MXQ_ERR_RULES_ILLEGAL_MOVE` 3001 | well-formed move, not legal here | expected |
| `MXQ_ERR_RULES_MALFORMED_MOVE` 3002 | not `^[a-g][1-7][a-g][1-7]$` | programming (from UI); expected (from import) |
| `MXQ_ERR_RULES_INVALID_FEN` 3003 | fails the frozen 6-field encoding or structural validation | expected |
| `MXQ_ERR_RULES_ILLEGAL_POSITION` 3004 | structurally valid but not a legal Mini Xiangqi position | expected |
| `MXQ_ERR_RULES_HISTORY_INVALID` 3005 | a supplied history move was illegal at its turn; index in `*out_first_illegal_index` | expected |
| `MXQ_ERR_STORE_IO` 4001 | filesystem or SQLite I/O failure | runtime |
| `MXQ_ERR_STORE_CORRUPT` 4002 | database integrity failure | runtime |
| `MXQ_ERR_STORE_BUSY` 4003 | lock contention after the core's own retry budget | runtime |
| `MXQ_ERR_STORE_FULL` 4004 | out of disk space / quota | runtime |
| `MXQ_ERR_STORE_NOT_FOUND` 4005 | no such `record_id` | expected |
| `MXQ_ERR_STORE_IDENTITY_CONFLICT` 4006 | same identity, different content (C25) | expected |
| `MXQ_ERR_STORE_MIGRATION_FAILED` 4007 | schema migration failed; store left at its prior version | runtime |
| `MXQ_ERR_STORE_SCHEMA_TOO_NEW` 4008 | store written by a newer build | runtime |
| `MXQ_ERR_ARCHIVE_MALFORMED` 5001 | structural decode failure | expected |
| `MXQ_ERR_ARCHIVE_UNSUPPORTED_VERSION` 5002 | version outside `[min_readable, current]` | expected |
| `MXQ_ERR_ARCHIVE_TOO_LARGE` 5003 | exceeds the file-size or structural limits (`docs/game-data.md:94`) | expected |
| `MXQ_ERR_ARCHIVE_INCONSISTENT` 5004 | decodes, but fails rules replay | expected |
| `MXQ_ERR_ARCHIVE_TERMINAL_MISMATCH` 5005 | claimed terminal state disagrees with the replayed adjudication | expected |
| `MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY` 6001 | rounded budget below 256 MiB (C14) | expected |
| `MXQ_ERR_ENGINE_ASSET_MISSING` 6002 | variant config or NNUE not found | runtime |
| `MXQ_ERR_ENGINE_ASSET_MISMATCH` 6003 | NNUE hash/length mismatch, or the net did not load (§1.2 fact 8) | runtime |
| `MXQ_ERR_ENGINE_VARIANT_LOAD_FAILED` 6004 | pinned variant configuration rejected | runtime |
| `MXQ_ERR_ENGINE_HASH_ALLOC_FAILED` 6005 | Hash allocation failed despite a sufficient budget — **see §6, gap G1** | runtime |
| `MXQ_ERR_ENGINE_NO_MOVE` 6006 | engine produced no move in a non-terminal position | runtime |
| `MXQ_ERR_ENGINE_ILLEGAL_RESULT` 6007 | proposed move rejected by the rules facade (C12) | runtime |
| `MXQ_ERR_ENGINE_FAULTED` 6008 | engine in a state the core cannot trust; requires teardown | runtime |
| `MXQ_ERR_RESOURCE_OOM` 7001 | core allocation failed | runtime |
| `MXQ_ERR_RESOURCE_LIMIT` 7002 | a documented internal limit was exceeded | runtime |
| `MXQ_ERR_INTERNAL` 9001 | invariant violated inside the core | runtime |

### 4.3 Programming errors versus runtime errors

**Programming errors** are contract violations that a correct frontend never produces: `MXQ_DOMAIN_ARGUMENT` (except `MXQ_ERR_ARG_BUFFER_TOO_SMALL`), plus `MXQ_ERR_STATE_NOT_INITIALIZED`, `MXQ_ERR_STATE_ALREADY_INITIALIZED`, and `MXQ_ERR_STATE_SESSION_READ_ONLY`.

Treatment: **assert in debug builds, return the code in release builds, and change no state in either.** C9 forbids crashes crossing the boundary, so release must not abort — but a silent wrong result would be worse than a loud one during development, and the two bindings are the only callers. Frontends should treat any programming-error code as a bug report path, not as user-facing copy.

**Runtime and expected errors** are everything else. They are ordinary control flow, must be handled, and must leave the last committed state intact (C10).

`MXQ_ERR_ARG_BUFFER_TOO_SMALL` is deliberately in the argument domain but is **not** a programming error: it is the second half of the two-call size protocol.

### 4.4 Mapping to the accepted user-visible flows

| Trigger | Codes | Accepted UI |
|---|---|---|
| `mxq_store_archive_and_clear` fails | any `MXQ_DOMAIN_STORE` code | **无法保存对局 / 当前对局仍然保留。请重试。** with **取消** and **重试**; Retry re-invokes the identical call (C28). The core guarantees the old active game is intact, so Retry is safe by construction. |
| `mxq_engine_prepare` returns `MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY` | 6001 | **无法启动 AI 对手 / 当前可用内存不足。请尝试关闭一些其他 App，然后重试。** with **取消** and **重试**; Retry calls `mxq_engine_prepare` again with a **fresh** `MxqEngineBudget` (C29). The core never caches the probe. |
| `mxq_game_create` fails after a successful archive-and-clear | store or engine domain | Pre-start page retained, error shown, **开始对局** re-enabled, draft preserved, no persistent change (`docs/interaction-design.md:66`, `:75`). |
| `mxq_store_import` fails | `MXQ_DOMAIN_ARCHIVE`, or `MXQ_ERR_STORE_IDENTITY_CONFLICT` | Rejected with an explanation; no persistent state change (C24, C25). |
| `mxq_store_import` returns `MXQ_IMPORT_EXISTING` | `MXQ_OK` | **Not an error.** Offer access to the existing record (C25, `docs/product.md:62`). |
| `mxq_store_history_delete` fails | `MXQ_DOMAIN_STORE` | Record remains in the list; error presented (`docs/interaction-design.md:217`). |
| `mxq_game_apply_move` returns `MXQ_ERR_RULES_ILLEGAL_MOVE` | 3001 | Brief non-blocking feedback; selection is not cancelled (`docs/interaction-design.md:95`). Not an alert. |
| Search result with `outcome != MXQ_SEARCH_MOVE` | see `MxqSearchResult.failure` | `CANCELLED`/`STALE` are silent — the frontend simply discards. `FAILED` surfaces per the engine-domain code. Never commits a move (C11). |

---

## 5. Proposal — threading contract

### 5.1 Thread classes

The contract names four thread classes. Every function's documentation comment states which it may be called from.

- **UI thread** — the frontend's main actor / dispatcher thread.
- **Any thread** — genuinely free.
- **Session owner** — whichever single thread currently owns a given `MxqGame` (§5.3).
- **Not from a core callback** — see §5.7.

Internally the core owns exactly two threads it creates itself:

- the **engine thread**, which is the sole caller of every Fairy-Stockfish entry point;
- the **store thread** is **not** created — store calls execute on the calling thread under an internal mutex (§5.5).

### 5.2 Per-function thread rules

| Function group | Callable from | Blocking |
|---|---|---|
| `mxq_status_*`, `mxq_blob_*`, `mxq_core_version`, `mxq_engine_plan`, `mxq_rules_start_fen` | any thread, including a callback | no |
| `mxq_core_init`, `mxq_core_shutdown` | UI thread or a dedicated setup thread; **not** from a callback | yes — `init` opens/migrates the store; `shutdown` joins the engine thread |
| `mxq_core_cancel_all` | any thread except a callback | brief; returns after the stop flag is raised and the engine has quiesced |
| `mxq_game_*` queries | session owner | no — microseconds |
| `mxq_game_*` mutations on an **attached** session | session owner, **off the UI thread** | yes — includes a synchronous store commit (C22) |
| `mxq_game_*` mutations on a **detached** session | session owner | no |
| `mxq_rules_*` | any thread except a callback | no |
| `mxq_engine_prepare`, `mxq_engine_teardown` | any thread except a callback, **off the UI thread** | yes — TT allocation and zeroing (§1.2 fact 6) |
| `mxq_search_start`, `mxq_search_cancel`, `mxq_search_cancel_all`, `mxq_search_poll` | any thread except a callback | no — all are enqueue/flag operations |
| `mxq_search_wait` | any thread except a callback and the UI thread | yes, bounded by `timeout_ms` |
| `mxq_archive_*` | any thread except a callback | `validate`/`encode` are CPU-bound; keep off the UI thread |
| `mxq_store_*` | any thread except a callback, **off the UI thread** | yes |

### 5.3 Session concurrency model

**Proposal: `MxqGame` is single-owner, with concurrent misuse detected rather than silently serialized.**

A session may be *moved* between threads freely (there is no thread-local state inside it), but only one thread may be inside a session function at a time. The core holds a per-session `std::atomic_flag`; if a second thread enters while the flag is set, the call returns `MXQ_ERR_ARG_CONCURRENT_USE` and asserts in debug builds.

Rationale, and why not a full internal mutex:

- The product has one main window (C33) and at most one active game (C23), so genuine concurrent access to a single session is always a frontend bug.
- A mutex would make an `undo` racing an `apply_move` *safe* but still *wrong* — the ordering is the semantics, and silently picking one order hides the bug until it produces a wrong committed game.
- Rules operations are microsecond-scale; there is no throughput argument for fine-grained locking.
- `docs/architecture.md:52` requires the boundary to document per-function thread rules and makes the core responsible for *its own internal* synchronization. The engine thread and the store connection are internal and **are** internally synchronized (§5.4, §5.5). A session is the caller's object.

Different sessions are fully independent: a History replay session and the active-game session can be driven from different threads simultaneously (they share only the store mutex, and replay sessions never take it).

### 5.4 Search delivery, cancellation, and stale rejection

**Proposal: one core-owned engine thread; completion delivered by callback on that engine thread; `mxq_search_poll`/`mxq_search_wait` supported as a callback-free alternative.**

Shape:

1. `mxq_search_start` validates the request against the session, snapshots `(initial FEN, moves[], game_id, position_revision, movetime_ms)`, allocates a monotonic `ticket`, and posts the job to the engine thread. It returns immediately with the ticket. It returns `MXQ_ERR_STATE_SEARCH_IN_PROGRESS` if a search is outstanding — the engine is process-global and single-search (§1.2 fact 1).
2. The engine thread reconstructs the position from FEN + history (never from a bare FEN — C20), issues the equivalent of `go movetime <n>`, and blocks until the pool quiesces. This mirrors `MainThread::search()`'s own `Threads.stop = true; Threads.wait_for_search_finished()` sequence (`src/search.cpp:240-243`).
3. The engine thread reads the selected best move through the pool's own selection (§1.2 fact 5), then — before delivering anything — applies the C12 rejection ladder in order: **cancelled → stale → malformed → illegal under the rules facade**. Only a move that survives all four is delivered as `MXQ_SEARCH_MOVE`.
4. The engine thread materializes a complete `MxqSearchResult` POD and invokes the callback with it. The callback runs **on the engine thread**, after the search has fully quiesced, with no engine lock held.

Why the callback fires on the engine thread rather than on a separate dispatch thread: the result is already fully materialized by step 4, so an extra hop buys nothing but latency and one more thread; and FS's own delivery point is exactly there (`src/search.cpp:305`), so the shape is a faithful in-process substitution for the `bestmove` line rather than an invented layer. C6 already requires the frontend to re-enter its own dispatcher before touching UI state, so no frontend can be correct by accident regardless of which core thread calls it.

Why a callback rather than polling as the primary: the accepted profiles are 1–5 s (C13) and the UI shows an AI-thinking state throughout (`docs/interaction-design.md:106`); polling would add a timer per game with no benefit. `mxq_search_poll` and `mxq_search_wait` remain in the surface because they cost almost nothing (the result is already materialized and retained under its ticket until the next `mxq_search_start` or `mxq_core_shutdown`), they make `docs/testing.md:104` cancellation/stale tests deterministic, and they give the Windows binding an escape hatch if `[UnmanagedCallersOnly]` proves awkward.

**Cancellation** is cooperative and exactly FS's own mechanism: `mxq_search_cancel` sets the engine's atomic stop flag (`src/thread.h:118`; the same flag the UCI `stop` command sets at `src/uci.cpp:337`). The search observes it at every node (`src/search.cpp:722`) and at the once-per-1024-nodes time check (`src/search.cpp:708-709`, `:1957-1961`), and discards rather than commits its in-flight result (`src/search.cpp:1394-1396`). `mxq_search_cancel` returns as soon as the flag is set; the callback still fires, with `outcome = MXQ_SEARCH_CANCELLED`.

**Stale rejection is enforced twice, by design.** C5 says cancellation alone is not trusted. The core compares the completing job's `(game_id, position_revision)` against the current session before delivery and marks a mismatch `MXQ_SEARCH_STALE`; the frontend compares again against its own view before applying. Neither check is sufficient alone: the core's check can race a frontend-side undo that has not yet reached the core, and the frontend's check cannot see a search the core already invalidated.

**Search never commits.** `MxqSearchResult` is an inert value struct. Applying the move is a separate, explicit `mxq_game_apply_move` by the frontend on the session-owner thread. There is no path by which a search result reaches the store (C11).

### 5.5 Store threading

**Proposal: store operations are synchronous, callable from any non-UI thread, and internally serialized by a single mutex over a single SQLite connection.**

- One connection, one mutex, `PRAGMA journal_mode = WAL` is a `[archive-contract]`/schema decision but does not change this contract: the C functions block until the transaction commits or fails.
- Every mutation is one transaction. `mxq_store_archive_and_clear` is the atomic archive-and-clear of C23 in a single transaction.
- The functions are documented **"may block; must not be called from the UI thread"**. Both frontends have first-class background execution (Swift actors/`Task`, .NET `Task.Run`), so this costs a wrapper, not a design.

Why synchronous rather than async-with-callbacks: the accepted flows are user-initiated, one-at-a-time, and small (one game archive is kilobytes); an async C store API would double the surface, introduce a second callback thread, and make the atomicity of C23 harder to reason about. The accepted retry flows (C28) read naturally as "await → get typed error → show 重试 → await again". Decision 4 in §8 records the alternative.

Because a mutation on a store-attached session commits inside the call (C22), **`mxq_game_apply_move`, `mxq_game_undo`, `mxq_game_claim_draw`, and `mxq_game_resign` can return storage errors and can block.** That is a direct consequence of "there is no deferred autosave" and "a committed move is the recovery boundary" (`docs/game-data.md:35-36`) and must be visible in the signature contract, not hidden.

### 5.6 Engine configuration and search serialization

`mxq_engine_prepare` must not run concurrently with a search: `TT.resize()` and `Threads.set()` both begin by blocking on `wait_for_search_finished()` (§1.2 fact 6), so a naive concurrent call would silently stall the caller for up to `movetime`. The core therefore executes `prepare`/`teardown` **on the engine thread**, ordered behind any queued search, and returns `MXQ_ERR_STATE_SEARCH_IN_PROGRESS` immediately if a search is outstanding, rather than blocking.

`mxq_engine_prepare` performs, in order: compute the plan (identical arithmetic to `mxq_engine_plan`) → if `!sufficient`, return `MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY` and touch **nothing** (C14/C29 require that the engine is not initialized at all) → set `Threads` → set `Hash` → load the pinned variant configuration → load the NNUE → **preflight the net by reproducing `verify()`'s own predicate against `Eval::eval_file_loaded`** (§1.2 fact 8) and return `MXQ_ERR_ENGINE_ASSET_MISMATCH` on failure, so `verify()`'s `exit()` at `src/evaluate.cpp:162` is never reached from `src/search.cpp:191`.

### 5.7 Reentrancy

Inside an `MxqSearchCallback`, the **only** legal calls are `mxq_status_*` and `mxq_blob_*`. Every other `mxq_*` function returns `MXQ_ERR_ARG_REENTRANT` (and asserts in debug builds) when invoked on the engine thread from inside a callback.

This is not conservatism: `mxq_search_start` posts to the engine thread and `ThreadPool::start_thinking` itself begins with `main()->wait_for_search_finished()` (`src/thread.cpp:184`), so a callback that started another search would deadlock the engine thread against itself. The callback's only job is to copy the result and hand it to the frontend's dispatcher — which is what C6 already requires.

The core detects the condition with a thread-local "in callback" depth counter on the engine thread, so the check is free on every other thread.

### 5.8 Backgrounding, mid-search and mid-transaction termination

- **Backgrounding.** The frontend calls `mxq_core_cancel_all`, which raises the engine stop flag and returns once the engine has quiesced. Outstanding search callbacks still fire, with `MXQ_SEARCH_CANCELLED`. No game state changes (C5, C11).
- **Mid-search termination.** Nothing is lost: search output never commits (C11), and the last accepted move was already committed by `mxq_game_apply_move` (C22). On relaunch the game resumes at the last committed move (`docs/game-data.md:36`).
- **Mid-transaction termination.** SQLite's own journal recovery restores the last committed state; a partially applied archive-and-clear is impossible because it is one transaction (C23). This is exactly C10's "the last committed state always survives".
- **Deterministic shutdown.** `mxq_core_shutdown` cancels all searches, joins the engine thread, closes the store connection, and invalidates every outstanding handle. Calling any function on an invalidated handle afterwards returns `MXQ_ERR_ARG_INVALID_HANDLE` rather than dereferencing freed memory (the core keeps a generation-tagged handle table). It must not be called from a callback, and it must not be called while another thread is inside a store call — the core enforces the latter by waiting for the store mutex. This satisfies C8.

---

## 6. Contradictions and gaps

Recorded rather than silently resolved.

**G1 — Hash allocation failure is fatal in the unmodified engine.** `docs/engine-integration.md:111` asks for "user-visible recovery if the Hash allocation itself fails despite a calculated budget of at least 256 MiB", and `docs/testing.md:111` requires testing "allocation failure". But `TranspositionTable::resize()` calls `exit(EXIT_FAILURE)` when `aligned_large_pages_alloc` returns NULL (`Fairy-Stockfish/src/tt.cpp:71-77`), and `on_hash_size` is wired straight to it (`src/ucioption.cpp:62`). No C signature can express a recoverable `MXQ_ERR_ENGINE_HASH_ALLOC_FAILED` without a focused fork change that makes `resize()` return a failure instead of exiting. This is a **new patch trigger**: `discussion-drafts/axf-evaluation-plan.md:152` and `:254` name only the NNUE `exit()` path. (The Windows-only `aligned_large_pages_free` exit at `src/misc.cpp:474-481` is a second, smaller instance of the same class.) The interface reserves code 6005 for it; the code is unreachable until the fork change lands.

**G2 — the NNUE `exit()` is preflightable, so it is *not* a patch trigger.** `axf-evaluation-plan.md:152` says the NNUE `exit()` becomes a patch trigger "if the wrapper cannot fully preflight the bundled asset before `go`". `Eval::eval_file_loaded` is exported (`Fairy-Stockfish/src/evaluate.h:39`) and `verify()`'s failure predicate is a pure string test over it (`src/evaluate.cpp:145`), so the core **can** preflight (§5.6). This narrows the fork's scope and should be recorded before the fork boundary is decided.

**G3 — the session must carry mode and participants, but `architecture.md` describes the rules facade as position-and-history only.** `docs/architecture.md:21` says the rules facade "is deterministic over position and history". But undo is mode-and-controller-aware (C26) and resign is mode-gated (C27), so the object the frontend drives must also hold `mode`, `human_color`, `ai_level`, and the frozen `movetime` — which `docs/game-data.md:55` requires to be durable configuration anyway, and which the archive must carry (`docs/game-data.md:28`). This draft resolves it by making `MxqGame` a **game session** that composes the rules facade with `MxqGameConfig`, and keeping the pure rules facade available session-free as `mxq_rules_*`. `architecture.md` needs one clarifying sentence; the current text can be read as forbidding this.

**G4 — "the running game uses plain value types in each frontend language" is ambiguous about who owns the game.** `docs/game-data.md:9` can be read as the frontend owning the running game with the core only persisting it. That reading is not implementable: repetition and perpetual-violation adjudication are history-dependent (C20, §1.2 fact 12), so a frontend-owned game would have to re-send the complete history on every query, and the "single active game" and "commit after every move" invariants (C22, C23) would live on the wrong side of the boundary. This draft reads the sentence as *presentation* value types projecting a core-owned session. The wording should be clarified.

**G5 — the boundary between a session mutation and its store commit is undefined.** `docs/game-data.md:35` requires an explicit commit after every accepted move, undo, and game completion, but no document says whether the frontend or the core issues it. This draft resolves it by making sessions **store-attached from birth** (`mxq_game_create`, `mxq_game_resume_active`) or **detached and read-only** (`mxq_game_open_archive`, `mxq_store_history_open`), with attached mutations committing inside the call. The consequence — rules mutations can return storage errors and can block — is a real contract change that should be confirmed, not assumed.

**G6 — Hash recalculation cadence across games is unspecified.** `docs/engine-integration.md:53` says the frontend supplies a fresh probe "at each calculation" and `:56-57` places the decision at engine initialization. It does not say whether a *second* human-versus-AI game in the same launch re-probes and re-applies Hash, or reuses the engine prepared for the first. Reusing it is cheaper and avoids a TT re-zero; re-probing matches the spirit of `:57`. The interface supports both (`mxq_engine_prepare` is idempotent-with-new-values), but the product contract should state which the app does.

**G7 — pre-start ordering is still an open contract item that this interface assumes.** `docs/engine-integration.md:110` leaves "the exact ordering and cleanup contract between pre-start engine preparation, Random resolution, active-game persistence, and initial search" open. §2.4/§2.6 assume: `mxq_engine_prepare` → resolve Random in the frontend → `mxq_game_create` (which commits) → `mxq_search_start` if the AI moves first. This matches `docs/interaction-design.md:64` and `docs/game-data.md:55`, but it is an assumption, not an accepted contract.

**G8 — "how frontends observe library changes" is open on two Need-to-discuss lists.** `docs/architecture.md:83` and `docs/game-data.md:125` both leave it unresolved. This draft answers it minimally (return values plus `out_library_revision`) without committing to a notification mechanism. Flagged as still open; see decision 7.

**G9 — `mx-chs-003` conformance requires a fork change, so the rules facade cannot ship on stock Fairy-Stockfish.** Already accepted at `docs/engine-integration.md:73`. The interface consequence is that `MxqVersion.engine_revision` and `MxqVersion.variant_id` are not optional diagnostics — they are the only way a test report or a saved diagnostic record can prove which build produced a result (C15). Recorded so the fields are not trimmed as "nice to have".

**G10 — no document states whether facing-kings FENs are rejected at load.** `docs/game-data.md:122` lists it as open, and `fen-notation-fixtures-draft.md` open flag 6 records that `FEN::validate_fen` accepts them (§1.2 fact 10). The interface reserves `MXQ_ERR_RULES_ILLEGAL_POSITION` (3004) as distinct from `MXQ_ERR_RULES_INVALID_FEN` (3003) so either answer is expressible, but which one `mxq_rules_validate_fen` and `mxq_archive_validate` apply is not decided here.

---

## 7. Proposal — API versioning and evolution

**Versioning.** Three numbers compiled into the header (`MXQ_API_VERSION_MAJOR/MINOR/PATCH`) and reported at runtime by `mxq_core_version`. `mxq_core_init` compares the caller's compiled-in `MXQ_API_VERSION` against the library's and returns `MXQ_ERR_ARG_API_VERSION` on an unsupported major. `MxqVersion` additionally reports the core revision, engine revision, variant id, NNUE hash, archive versions, and store schema version (C15) — four independent version axes that must not be conflated:

| Axis | Owner | Compatibility question |
|---|---|---|
| C API version | this document | can this binding call this library? |
| Archive format version | `[archive-contract]` | can this build read that file? |
| Store schema version | `[archive-contract]` | can this build open that database? |
| Engine/variant/NNUE profile | `docs/engine-integration.md` | which configuration produced this move? |

**Stability promised to the two frontends.** Both frontends are built from the same repository at the same revision, so the promise is a **source-compatibility** promise across a major version, not a shipped-binary ABI promise across releases. Within a major version:

- no function is removed or renamed, and no signature changes;
- no enum constant's numeric value changes, and no constant is removed;
- no struct field is removed, reordered, or retyped;
- no documented thread rule is tightened;
- an error code's *domain* never changes, and a function never starts returning a code from a domain it did not previously document.

**How additions happen.**

- **New functions** — append to the header; minor bump.
- **New enum constants** — append at the end of the owning 1000-block, never renumber. Frontends must have a `default:` arm; a `switch` over `MxqStatus` that assumes exhaustiveness is a bug. (Swift imports C enums as non-frozen when declared with `enum` + explicit values, which forces `@unknown default` — an advantage worth keeping.)
- **New struct fields** — append only, and guard with `struct_size`. The core writes a new field only when the caller's `struct_size` is large enough; a caller compiled against an older header sees the old prefix and is unaffected. This is why every struct carries `struct_size` from day one.
- **Breaking change** — major bump, and the old major is not maintained; the two frontends move in lockstep because they ship from one repository.

**Deprecation.** Within a major version a function may be marked deprecated in the header and must keep working. Removal waits for the next major.

---

## 8. Proposal — consumption sketches

These prove the shape works on both platforms. They are not a binding frontend design.

### 8.1 Swift (iOS, iPadOS, macOS)

The core ships as a static library plus `mxq.h` exposed through a module map, so Swift imports it directly with no bridging header and no hand-written shim. All the value structs are C structs of scalars and fixed-size `CChar` tuples, which Swift imports as trivially copyable structs; the fixed `char` arrays arrive as tuples and are converted with `withUnsafeBytes` + `String(cString:)` in one small helper per type. Because they contain no pointers, the Swift-side value types are naturally `Sendable`.

The three opaque handles arrive as `OpaquePointer?`. Each is wrapped in a `final class` that owns the release call in `deinit`, and the class is confined to an actor rather than marked `@unchecked Sendable` at large. Under Swift 6 strict concurrency this is the clean formulation: an `actor GameSession` holds the `MxqGame` handle and exposes `async` methods, and the actor's isolation *is* the single-owner rule from §5.3 — the compiler enforces at compile time exactly what the core would otherwise catch at runtime with `MXQ_ERR_ARG_CONCURRENT_USE`.

Two blocking-call details matter. First, `mxq_game_apply_move` and every `mxq_store_*` call block on SQLite (§5.5), and blocking a thread of Swift's cooperative pool is discouraged because the pool sizes itself to the core count. The right construction is a custom actor executor: give `GameSession` and `LibraryStore` an `unownedExecutor` backed by a dedicated `DispatchSerialQueue`, so their `async` methods hop to a real serial queue that is allowed to block, and the cooperative pool is never starved. Second, `mxq_core_init` and `mxq_engine_prepare` are start-up-scale blocking calls and belong on the same kind of dedicated queue, not on the main actor.

The search callback is a C function pointer, so the Swift closure must be non-capturing. The standard trampoline applies: box the continuation or the delivery closure in a class, pass `Unmanaged.passRetained(box).toOpaque()` as `user_data`, and in the C trampoline take `Unmanaged.fromOpaque(userData).takeRetainedValue()`, copy the `MxqSearchResult` into a Swift value struct, and hand it off. Because §5.7 forbids calling back into the core from the callback, the trampoline's entire body is "copy, then resume a `CheckedContinuation` or enqueue onto the owning actor" — which is exactly what C6 already demands. The natural surface is `func search(_ request: SearchRequest) async throws -> SearchResult` built on `withCheckedThrowingContinuation`, with cancellation wired through `withTaskCancellationHandler` calling `mxq_search_cancel`.

`MxqError` maps to a Swift `struct CoreError: Error` carrying the code, domain, subsystem code, and detail string, with a computed `isProgrammingError` so a debug build can `assertionFailure` on the argument domain per §4.3.

### 8.2 Windows (WinUI 3 / C#)

Two options, and they are not close.

**P/Invoke (recommended).** The WinUI 3 frontend is C#, and `docs/architecture.md:43` already names "C# P/Invoke" as the accepted binding direction. With .NET 8+ the `[LibraryImport]` source generator emits the marshalling stubs at compile time, so there is no runtime IL stub and no `DllImportGenerator` overhead. Every struct in §2 is blittable by construction — scalars plus fixed-size `char` buffers declared as `fixed byte fen[96]` in an `unsafe struct` — so `[StructLayout(LayoutKind.Sequential)]` with no marshalling attributes is sufficient and the CLR passes them by direct memory copy. The declarations do not need to be hand-maintained: ClangSharpPInvokeGenerator consumes the same `mxq.h` that Swift's module map consumes, so both bindings are generated from one source of truth, which is what `docs/testing.md:48` ("verify both platform bindings against the documented threading and error contract") is easiest to satisfy against.

The search callback uses `[UnmanagedCallersOnly]`, which produces a raw function pointer with no delegate wrapper and no marshalling stub, at the cost of two rules: the method must be `static`, and it must not let an exception escape into native code. Both are satisfied by the same "copy and hand off" body the Swift trampoline uses. The `user_data` pointer holds a `GCHandle` to the managed completion object, allocated before `mxq_search_start` and freed in the callback. Blocking calls go on `Task.Run`; `mxq_search_start` wraps into a `TaskCompletionSource<SearchResult>` with a `CancellationToken` registration calling `mxq_search_cancel`.

**C++/WinRT component.** A WinRT wrapper around the C core, projected into C#. It would give idiomatic `IAsyncOperation<T>` and WinRT events for free, and would let a future non-C# consumer use the same component. But it adds a second ABI, a `.winmd`, a C++/WinRT build leg, and a hand-written projection layer for a surface of 52 functions — and the async idiom it buys is a dozen lines of `TaskCompletionSource` on the P/Invoke path. It also puts a second marshalling boundary between the frontend and the error detail the frontend must present.

**Recommendation: P/Invoke with `LibraryImport` and ClangSharp-generated declarations.** It matches the accepted direction in `architecture.md:43`, keeps one ABI, and keeps both bindings generated from one header. Revisit only if a non-.NET Windows consumer appears, which the target MVP excludes.

---

## 9. Decision shortlist

Only the choices that materially change the contract.

1. **API prefix and header layout.** Options: `mxq_` in one `mxq.h`; `mxq_` split per module; a longer prefix such as `minixiangqi_`.
   **Recommend: `mxq_` in one `mxq.h`.** One header keeps the ABI auditable and gives ClangSharp and the Swift module map a single input; three characters is enough to avoid collisions in both bindings.

2. **Search result delivery.** Options: (a) callback on the core's engine thread; (b) callback on a separate core dispatch thread; (c) polling only.
   **Recommend (a), with `mxq_search_poll`/`mxq_search_wait` also provided.** It is a faithful in-process substitution for FS's own `bestmove` delivery point (`src/search.cpp:305`, after `wait_for_search_finished()` at `:243`), costs no extra thread, and C6 already forces the frontend to re-enter its own dispatcher regardless. The poll/wait pair costs nothing extra and makes cancellation and stale-result tests deterministic.

3. **Session concurrency model.** Options: single-owner with concurrent-use detection; fully internally synchronized; unsynchronized and undefined.
   **Recommend single-owner with detection.** With one main window and one active game, concurrent session access is always a frontend bug; a mutex would make it safe but still wrong, and would hide the bug. Swift actors and a C# `SemaphoreSlim` express single-owner naturally.

4. **Store call style.** Options: synchronous and internally serialized; asynchronous with completion callbacks.
   **Recommend synchronous.** Atomicity is far easier to reason about, both frontends have first-class background execution, and the accepted retry flows (C28) read naturally as await/error/retry. The cost is one documented rule: never call `mxq_store_*` or an attached-session mutation from the UI thread.

5. **Error representation.** Options: `int32_t` enum in 1000-blocks plus an optional `MxqError` out-param; a thread-local last-error; a packed `domain<<16 | ordinal` bitfield.
   **Recommend the enum plus `MxqError` out-param.** A thread-local breaks under Swift's cooperative pool and is unusable inside the search callback; a packed bitfield is harder to read in a debugger and in logs for no gain. 1000-blocks give a trivial `mxq_status_domain`.

6. **Where the store commit happens for a session mutation (gap G5).** Options: sessions are store-attached and mutations commit inside the call; the frontend issues an explicit `mxq_store_save(game)` after each mutation.
   **Recommend store-attached with in-call commit.** `docs/game-data.md:35-36` requires an explicit commit after *every* accepted move with the committed move as the recovery boundary; an explicit frontend save re-opens exactly the window that rule closes. Accept the consequence that rules mutations can block and can return storage errors.

7. **How frontends observe library changes (gap G8).** Options: return values only; return values plus a monotonic `library_revision`; a registered change-notification callback.
   **Recommend return values plus `library_revision`.** It costs one `uint64_t` on two functions, lets the History list detect staleness cheaply, and does not commit the project to a notification mechanism with its own thread and reentrancy rules. Revisit if a second surface ever observes the library concurrently — the target MVP has one main window.

8. **Whether `MxqCore` is a handle or an implicit singleton.** Options: opaque handle, singleton-enforced; no handle, global functions.
   **Recommend the handle, singleton-enforced.** FS's globals make a second instance impossible today, but a handle costs one parameter, makes test teardown explicit, and avoids a signature break if the engine ever moves out of process.

9. **Reserving `MXQ_ERR_ENGINE_HASH_ALLOC_FAILED` before the fork change exists (gap G1).** Options: reserve the code now and leave it unreachable; omit it until the fork change lands.
   **Recommend reserving it now.** The code is free, `docs/testing.md:111` already requires an allocation-failure test, and reserving it keeps the enum append-only when the fork change lands.
