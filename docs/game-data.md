# Game Data

This document defines the local-data contract: the library store, the versioned game archive, saving, import, and export. It does not define the rules of either game, screen flows, or engine internals.

One version is defined: **2**, for both the archive format and the store schema. It is the only shape this build writes, reads, verifies or tests, and there is no migration into it — see [Versions](#versions).

> **Status: binding.**

## Storage model

The shared core owns persistence through an embedded SQLite library store, behind the repository boundary defined in [architecture.md](architecture.md). One implementation carries the transactional invariants — the single active game, atomic archive-and-clear, import validation, and duplicate detection — identically on Apple platforms and Windows, and one test suite validates them. Frontends never touch the database directly. The running game is a core-owned session; what each frontend language holds are plain presentation value types projected from it, per the C interface in [core-interface.md](core-interface.md).

- The frontend supplies the store's location at startup: the app's Application Support directory on Apple platforms and the app's local application-data directory on Windows.
- The pinned SQLite version ships inside the core on every platform; the core does not depend on a system-provided SQLite.
- The conceptual model has one logical `GameLibrary` with an optional reference to the single active game, and one `StoredGame` per active or History game.
- `StoredGame` carries queryable summary fields — stable identity, which of the two games it is, dates, play mode, participants, result summary, imported provenance, and pinned state — plus a versioned archive blob containing the complete replayable game record.
- A library holds records of both games. Which game a record is of is `rules_id`, and it is a summary column as well as archive content, so a mixed History list is labelled and ordered without decoding a blob per row.
- The core enforces the single-library and single-active-game invariants even where the schema cannot express them as constraints.

## Versioned game archive

The archive is independent of the database schema and is also the export and import interchange format, so it must be portable across platforms and app versions. It contains enough information to reproduce and validate a game, including:

- archive format version;
- game identity and creation metadata;
- the game and the rules interpretation it was played under;
- initial position;
- ordered main-line moves;
- configuration needed to interpret the players and game;
- terminal information when the game is completed.

Callers must not decode or modify the archive outside the core's codec.

### Archive format, version 2

- An archive is one canonical-JSON document per game, file extension `.mxq`, Apple UTI `com.chentianren.minixiangqi.game` conforming to `public.json`, internal MIME type `application/vnd.minixiangqi.game+json`. JSON has no inclusion, reference, or execution mechanism, satisfying the untrusted-input rules structurally, and files stay human-inspectable.
- The in-band type check is the `archive_format` member, exactly `minixiangqi-game`; the extension and UTI are hints only. It names the file format, which both games share — which game a file records is `content.rules_id`. `archive_version` is a single monotonically increasing integer, `2` for this specification.
- The document has an envelope — `archive_format`, `archive_version`, `content`, `game_id`, `origin` — and a `content` object carrying everything that defines the game. The split exists so identity and content compare independently, which is what duplicate and conflict handling require.
- `content` members: `rules_id` (`minixiangqi` or `xiangqi`, the ruleset identity of [xiangqi-rules.md](xiangqi-rules.md), not an engine variant), `rules_version`, `start_fen` (exactly that game's frozen starting FEN), `moves` (the ordered retained main line in canonical notation; index 0 is Red's first move), `mode`, and for human-versus-AI games `human_side`, `ai_level`, `ai_movetime_ms`, and `first_mover_choice`; then `started_at`, and — present exactly when the game is completed, which every exported file is — `outcome`, `end_reason`, and `ended_at`. The active game's stored content omits those three members. Timestamps are RFC 3339 UTC instants in the exact fixed-width form `YYYY-MM-DDTHH:MM:SS.sssZ`.
- Canonical form: UTF-8, one line, members in codepoint order, no insignificant whitespace, integers only, `null` forbidden, minimal string escaping. The core is the only writer, and the canonical bytes are what content equality hashes. Three of these clauses decide what a document *means* — UTF-8, integers only, and `null` forbidden — and reading enforces them; the other four — one line, members in codepoint order, no insignificant whitespace, and minimal string escaping — describe the writer's output and are re-established by the canonicalization stage of the validation order below rather than demanded of an incoming file, so a file spelling an equivalent document differently is canonicalized rather than refused.
- No move count is serialized (it is the length of `moves`); no engine, fork, or NNUE identifier is serialized — a game's meaning derives from the rules contract (`rules_id` + `rules_version`), never from the engine build that played it. `ai_movetime_ms` is stored beside `ai_level` so a later retuning of a level's time does not reinterpret existing archives; import checks both for presence and range, not the current pairing. `first_mover_choice` is retained because it cannot be reconstructed later.
- `origin` (`app_version`, `exported_at`) describes the export event: regenerated on every export, never hashed, never compared, never trusted, and never used to set the local imported marker. A stored document is not an export and has no export event, so there `exported_at` records the committed change that produced the document — creation, the accepted move or undo that last rewrote it, or the archiving that ended the game, whose instant is also its `ended_at` and its History-added time, because they are one committed event — and `app_version` is the product version of the core that wrote it, the only writer an archive has. That makes a stored game's bytes a pure function of its committed state: the same game encodes identically twice and again after a resume, which is what lets the store's blob and `mxq_archive_encode`'s output be compared rather than merely assumed equal.
- `rules_id` decides how the rest of `content` is read: `start_fen` is checked against that game's starting position and `moves` against that game's board, so `a9a10` is a move in a `xiangqi` document and malformed in a `minixiangqi` one. One member decides both, so a document naming one game and opening from the other's board is refused rather than replayed.
- Version 2 deliberately excludes: pin state and every other local library field, per-move timing, comments and annotations, discarded lines, and any engine diagnostics.

### Serialized identifier vocabulary

Closed sets; unknown values are rejected at import.

- `mode`: `human-vs-ai`, `free-play`. `human_side`: `red`, `black` (the resolved side). `ai_level`: `fast`, `standard`, `deep`. `first_mover_choice`: `human-first`, `ai-first`, `random`.
- `outcome`: `red-wins`, `black-wins`, `draw`, `none`. This is deliberately not the fixture state set: live states (`ongoing`, `claimable-draw`) can never be a committed outcome, and `none` — no competitive result — has no rules analogue. The three overlapping spellings stay identical to the fixture vocabulary.
- `rules_id`: `minixiangqi`, `xiangqi`.
- `end_reason`: the rule reasons `checkmate`, `stalemate`, `perpetual-check`, `perpetual-chase`, `threefold-repetition`, `mutual-perpetual-check`, `mutual-perpetual-chase`, `fifty-move-rule`, plus the user-scoped `resignation` and `ended-early`. `fifty-move-rule` is Xiangqi's alone: Mini Xiangqi has no move-count rule, so a record of it can never carry that reason.
- Cross-field rules, enforced at import and as store constraints: `outcome = none` exactly when `end_reason = ended-early`; `outcome = draw` exactly when the reason is one of the four draw reasons; `resignation` only in `human-vs-ai`, with the outcome the win for the side opposite `human_side`; `fifty-move-rule` only with `rules_id = xiangqi`. No claimed-versus-automatic flag exists: in both rulesets `threefold-repetition` is always a user claim and every other rule reason is automatic, so the reason determines the mechanism.
- Provenance is local library metadata, never an archive field: `locally-played`, `imported`, with `derived` reserved (and rejected by version 2) for a future start-from-position feature. Provenance describes how a record entered this library: re-importing one's own exported file after deleting the original yields a record marked `imported`.

### Content equivalence and duplicate detection

- Content identity is SHA-256 over the canonical bytes of the `content` object alone. `game_id` is the stable identity: a version 7 UUID in canonical lowercase text, generated by the core at game creation, frozen forever, never regenerated on import or export, and never derived from content — a content-derived identity would erase the accepted identity-conflict behavior. Generation goes through the core's one clock and identity provider; under the test-only `MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY` core flag ([core-interface.md](core-interface.md)) it yields the deterministic version-7-shaped sequence documented in `mxq.h`, so persistence fixtures can be byte-stable — production identifiers are always real version 7 UUIDs.
- Duplicate: same `game_id`, same `archive_version`, same content hash and bytes → the existing record is returned. Conflict: same `game_id` with differing content, or with a differing stored archive version (cross-version content comparison is undefined and rejected conservatively) → the file is rejected without persistent change.
- Pin state, History-added time, provenance, and the entire `origin` object never affect equality.

### Import limits and validation order

Import limits: at most 1 MiB per file, 10 000 plies, JSON nesting depth 4, 32 members per object, 256-byte strings, and a validation time budget of two seconds on the slowest supported device. These bound the import surface only; live local play is not length-limited, and a locally produced game exceeding the import bounds remains fully playable and replayable — only re-import of its export would be refused.

Validation runs in order, and nothing touches the database until the final stage: transport and size; strict UTF-8 and JSON syntax under the structural limits (duplicate member names, `null`, and non-integer numbers rejected); envelope and explicit version dispatch, rejecting unknown members within a known version and unsupported versions with a distinct created-by-a-newer-version message that is never presented as corruption; field validity against the closed vocabularies and cross-field rules; rules-level validation through the rules facade — the initial position must be exactly the frozen starting FEN of the game `rules_id` names, every move must be legal in sequence, and the recorded terminal pair must agree with the replayed adjudication (`threefold-repetition` requires the facade to report claim eligibility, not a terminal state; `resignation` and `ended-early` require a non-terminal final position, because an unconfirmed natural result is always recorded as its actual result, and a resignation's winner must be the side opposite `human_side`); then canonicalization and hashing; then the single write transaction performing duplicate and conflict comparison and, only for a new game, one insert.

One refusal belongs to import rather than to the format, and is asked after those stages rather than among them: a document that records no end is the shape a stored *active* game has, and a successful import creates an immutable History record or nothing at all, so a file carrying no terminal trio is refused as malformed. It is asked last because the ordered stages decide whether the bytes are a version 2 archive and this decides whether that archive is a game an import may file; asking it earlier would mask a rejection class the corpus names, and the class a file is refused under must not depend on which entry point asked. The store's own constraint — a record can only enter the library as imported once it is complete — is a second line of defense rather than the thing that reports it, because a database error is the wrong voice for a file problem.

The ruleset the file names is dispatched on as explicitly as the archive version is: a `rules_id` outside the closed pair is malformed, while a well-formed `rules_version` the importing build does not implement is refused as an unsupported version rather than replayed — a game's meaning derives from that pair, and a build that replayed a foreign interpretation would either reject a legal move or, worse, reproduce a different result and present the disagreement as corruption of the file.

## Saving and starting another mode

- The core commits explicitly after every accepted move, undo, game completion, import, deletion, and other durable state change. There is no deferred or framework-managed autosave; the explicit transaction is the commit mechanism.
- A committed move is the recovery boundary after app exit or interruption.
- A move or undo whose commit fails does not happen: the active game remains exactly at its pre-mutation committed state, and the failure surfaces through the brief save-failure feedback defined in [interaction-design.md](interaction-design.md). No accepted-but-unsaved change ever exists.
- A draw claim, resignation, or result confirmation whose committing transaction fails leaves the game active and unchanged and uses the accepted archive-failure retry presentation; the History record exists only if the transaction committed.

### Save-before-mode behavior

- The same operation accepts any active game, including an ordinary ongoing game, a claimable but unclaimed neutral repetition, or an unconfirmed natural terminal result.
- The requested Human-versus-AI or Free Play destination is transient in-memory state and is not part of the game archive or the store.
- **保存并继续** places the active game in History and clears the library's active-game reference in one atomic transaction.
- The operation derives the saved classification from the committed game state:
  - an ordinary ongoing game is recorded with an ended-early reason and no competitive result;
  - a claimable neutral repetition that has not been claimed remains an ongoing game and is therefore recorded as ended early, not as a draw;
  - an unconfirmed natural terminal state retains its actual result and exact termination reason.
- The selected mode's pre-start state begins only after that commit succeeds. Creating the later game is a separate operation triggered by **开始对局**.
- A failed archive operation leaves the previously committed active game intact, creates no new game, and does not continue to the selected mode. The requested destination may remain only as transient retry state and is discarded when the flow is cancelled.

### Pre-start state behavior

- Neither mode's pre-start state is written to the store or a game archive. Neither creates a `StoredGame` or changes the active-game reference.
- Leaving either pre-start state discards it. If it was entered after archiving an older game, that older game remains immutable History and is not restored.
- Human-versus-AI Settings defaults and the per-game setup draft are separate state. Entering setup creates a fresh in-memory draft from the current Settings defaults; reopening after leaving creates another fresh draft from the then-current defaults.
- A Random first-mover choice remains unresolved in the draft. Only successful **开始对局** creation commits the resolved human side, AI level identifier, and exact thinking-time value as durable active-game configuration.
- AI availability or active-game persistence failure creates no active game and changes no persistent game-library state. The unresolved draft may remain only while the setup page remains open.
- Free Play has no configurable draft fields. Its in-memory pre-start state retains only the pending mode until **开始对局** commits the new active game.
- A failed creation in either mode leaves no active game, retains the corresponding in-memory pre-start state for retry, and changes no persistent game-library state.
- Each creation attempt is single-flight and bound to the identity or revision of the pre-start session that initiated it. Duplicate Start actions are ignored or disabled, and leaving invalidates the session so a late result cannot commit a game.

## Active games, history, and undo

There is at most one active game. History games have immutable game content: replay is read-only, and editing their move line is not supported. Pinning or unpinning changes only mutable library metadata. A history record may be explicitly and permanently deleted.

Undo changes the active game's retained main line and is saved immediately. The archive does not preserve discarded moves, an undo count, hidden branches, or redo state.

- Free Play removes one ply per Undo action and supports repeated Undo to the initial position.
- Human-versus-AI Undo cancels an outstanding reply search and removes the triggering human move, or removes the completed AI reply together with the preceding human move. Repeated Undo proceeds by human decision cycles.
- If a human move itself produces an unconfirmed natural terminal state, Undo removes that human move.
- An unconfirmed natural terminal state remains the active game and can be undone. Confirming its result, or successfully using **保存并继续** to enter another mode, moves it to immutable History with its actual result and termination reason.
- A claimable neutral threefold repetition also remains an active game. Continuing does not create a History record; claiming the draw commits an immutable draw record, while **保存并继续** without claiming records an ended-early game with no competitive result.
- Confirmed resignation records a human loss and moves the game to immutable History.
- Saving an ordinary ongoing game before entering another mode records it in immutable History with an ended-early reason and no competitive result.
- A new move after Undo permanently replaces the discarded continuation.

## Import and export

Export produces a portable, versioned game archive rather than a copy of the database. Import is a core operation and must never partially commit a game. Exported files must round-trip across all supported platforms.

- One exported file contains one immutable History game.
- Import processes one game file at a time. A successful import creates an immutable History record and never creates or replaces the active game.
- Imported and locally recorded History games have read-only game content. Pin or Unpin and permanent deletion remain distinct core operations.
- History sorts pinned records before unpinned records. Each group sorts by a local History-added time, with the most recently completed or imported first. The original game dates remain separate metadata.
- History retains queryable summaries for the accepted list metadata: date, mode, result or end reason, move count, human side when applicable, and imported provenance.
- If a validated import has the same stable identity and the same game content as an existing record, the core returns that existing record instead of inserting a duplicate.
- If a validated import has the same stable identity but different game content, the core rejects the file as an identity conflict without changing persistent state.

The **Confirm Before Deleting** preference is local app state, defaults to enabled, and is not part of immutable game content. Once the accepted UI policy authorizes deletion, the core removes the whole History record. The app has no deletion Undo, soft-deleted record, or Recently Deleted collection. A failed deletion leaves the existing record intact.

Imported files are untrusted input. Before saving, the importer must:

- enforce file-size and structural limits;
- reject unsupported versions and malformed fields;
- decode without executing embedded content or resolving network references;
- validate the initial position, ordered moves, and terminal claim through the rules facade;
- reject inconsistent or incomplete records with a user-facing error;
- create no persistent objects until validation succeeds.

Imported games are local data. Importing must not contact a server.

## Library store schema, version 2

- The store is one database file named `library.sqlite3` in the frontend-supplied store directory, whose leading directories the core creates as needed; write-ahead logging keeps its journal beside it (`library.sqlite3-wal`, `library.sqlite3-shm`). The connection regime — WAL, `synchronous=FULL`, `foreign_keys=ON` — is applied and read back at open rather than assumed.
- Three `STRICT` tables: `meta` (non-authoritative bookkeeping; nothing reads it to decide anything), `game` (one row per stored game, of either game), and `library` (exactly one row, enforced by constraint and a permanence trigger, holding the single nullable active-game reference). There is one active game across both games, not one per game.
- A `game` row is the active game exactly when its committed outcome is null, and a History record otherwise. The canonical `content` bytes live in the row as the archive blob, beside its content hash and derived summary columns — `rules_id`, mode, sides, level, move count in plies, outcome, end reason, and timestamps as epoch-millisecond integers — that exist only to answer the History list and must be exactly recomputable from the blob. There is no per-move table: every accepted move rewrites the one row in one transaction.
- The stable identity is unique; the game axis, result well-formedness (the cross-field vocabulary rules, `fifty-move-rule` belonging to Xiangqi among them), the mode-to-configuration relationship, and time ordering are check constraints; History content immutability — everything except pin state — and the archive-and-clear ordering are trigger-enforced; the single active game is structural through the one reference column. What SQL cannot express — legality of the move line, derived-column agreement, ended-early never recording a naturally terminal position — is core logic gated by tests.
- The accepted History ordering — pinned first, then newest History-added time within each group, with `record_id` descending as the tie-break — is served by one partial index that excludes the active game structurally. `record_id` is never reused (`AUTOINCREMENT`), so the tie-break is strict recency and a stale id held across a deletion dangles rather than resolving to a later game.
- SQLite ships vendored in the core, pinned to a stable amalgamation and hash-recorded in the repository's pinned-input manifest, with a floor of 3.37.0 for `STRICT`; updates are explicit reviewed changes, never silent. It is compiled with the hardened option set and without extension loading; connections run write-ahead logging with full synchronous durability and foreign keys on. The store is one process, one connection, one serialized writer; every operation is one transaction.
- Local preferences are not in schema version 2 and are not planned for a later one: they live with each platform, per the placement below. Should that ever be revisited, a key-value table remains a purely additive change.

## Settings placement

The seven persistent preferences accepted in [product.md](product.md) — the default first-mover choice, the default AI level, **Confirm Before Deleting**, the sound and haptics toggles, the piece symbols, and the notation — live in **each platform's own preference system**, not in the shared store.

- The core's ownership rule is that what is correctness-critical exists exactly once. No preference is: four are presentation or device capability; **Confirm Before Deleting** gates a permanent deletion but does not perform it, and the core's own deletion invariants — including that a failed deletion leaves the record intact — hold whatever the preference says; and the two that affect a game are read only when one is created.
- The core therefore never reads a preference. The frontend holds the pre-start draft in memory and passes its resolved values as arguments to game creation, where they are frozen into the game, so every value the core acts on is one the frontend supplied explicitly at that call.
- Each platform gains its system's own defaults registration, change observation, and settings integration rather than the core reimplementing them.
- Divergence between platforms is bounded by this document's serialized vocabularies and by the defaults fixed in [product.md](product.md), and there is no sync between installations for a difference to propagate through.
- Preferences themselves are outside the game archive and outside export and import, so a file moved between platforms never carries them. The archive does record `first_mover_choice` and `ai_level`, but as the created game's own frozen configuration rather than as the preference that suggested it; changing the preference afterwards leaves the archived game untouched.

## Versions

**Version 2 is the only version.** It is the only archive format and the only store schema this build defines, writes, verifies or reads, on either axis. There is no migration, no dispatch slot waiting for one, and nothing anywhere that names an earlier shape: a store or a document recording any other version is refused by the same version check that any other nonconforming input meets, and nothing about the refusal knows what an earlier version was.

The two axes stay independent and both are dispatched on explicitly. A store whose recorded schema version is newer than this build's is refused with the distinct newer-build answer the contract requires; any other recorded version is refused as one this build has no path to. An archive whose `archive_version` is newer is refused with the created-by-a-newer-version message, never as corruption; any other version is refused as unsupported. Stored archives are never rewritten.

The user-visible compatibility promise: a game file exported by a build can be imported by that build and by every later build that still defines its version; a file a build cannot read says so and imports nothing; a file is never partially imported. A later archive version must either define a lossless projection of version-2 content for duplicate comparison or accept that same-game exports across versions compare as identity conflicts.

An archive version that permits initial positions other than a game's frozen start must define a setup-legality predicate — one general per side inside its palace, piece-count bounds, and the side not to move never attacked, including through the facing-generals rule — and reject illegal setups at import.

## Local-only boundary

The app does not use cloud synchronization, remote storage, or network backup on any platform. Its data model must not assume multiple devices or concurrent writers. Normal operating-system device backups are outside the app's synchronization design.
