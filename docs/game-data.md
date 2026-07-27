# Game Data

This document is for engineers and reviewers responsible for persistence, game-history compatibility, and file interchange in Mini Xiangqi. It defines the local-data contract: the library store, the versioned game archive, saving, import, export, and migration. It does not define Xiangqi rules, screen flows, engine internals, implementation progress, or issue tracking.

> **Status: Partially accepted data contract.** The core-owned SQLite storage direction, the save-before-mode behavior, the pre-start behavior, and the MVP record behavior below are accepted. The concrete schema, archive serialization format, and identifiers remain draft. Items under **Need to discuss** are non-normative.

## Storage model

The shared core owns persistence through an embedded SQLite library store, behind the repository boundary defined in [architecture.md](architecture.md). One implementation carries the transactional invariants — the single active game, atomic archive-and-clear, import validation, and duplicate detection — identically on Apple platforms and Windows, and one test suite validates them. Frontends never touch the database directly; the running game uses plain value types in each frontend language.

SwiftData was considered for the Apple app. It was not selected because the store's correctness-critical invariants would then be implemented twice, and the design already keeps persistent models behind a repository boundary rather than binding them to SwiftUI, which removes SwiftData's main practical advantage.

- The frontend supplies the store's location at startup: the app's Application Support directory on Apple platforms and the app's local application-data directory on Windows.
- The pinned SQLite version ships inside the core on every platform; the core does not depend on a system-provided SQLite.
- The conceptual model has one logical `GameLibrary` with an optional reference to the single active game, and one `StoredGame` per active or History game.
- `StoredGame` carries queryable summary fields — stable identity, dates, play mode, participants, result summary, imported provenance, and pinned state — plus a versioned archive blob containing the complete replayable game record.
- The core enforces the single-library and single-active-game invariants even where the schema cannot express them as constraints.

## Versioned game archive

The archive is independent of the database schema and is also the export/import interchange format, so it must be portable across platforms and app versions. It contains enough information to reproduce and validate a game, including:

- archive format version;
- game identity and creation metadata;
- rules and variant version identifiers;
- initial position;
- ordered main-line moves;
- configuration needed to interpret the players and game;
- terminal information when the game is completed.

The serialization format is not yet selected. Callers must not decode or modify the archive outside the core's codec.

## Saving and starting another mode

- The core commits explicitly after every accepted move, undo, game completion, import, deletion, and other durable state change. There is no deferred or framework-managed autosave; the explicit transaction is the commit mechanism.
- A committed move is the recovery boundary after app exit or interruption.

### Accepted save-before-mode behavior

- The same operation accepts any active game, including an ordinary ongoing game, a claimable but unclaimed neutral repetition, or an unconfirmed natural terminal result.
- The requested Human-versus-AI or Free Play destination is transient in-memory state and is not part of the game archive or the store.
- **保存并继续** places the active game in History and clears the library's active-game reference in one atomic transaction.
- The operation derives the saved classification from the committed game state:
  - an ordinary ongoing game is recorded with an ended-early reason and no competitive result;
  - a claimable neutral repetition that has not been claimed remains an ongoing game and is therefore recorded as ended early, not as a draw;
  - an unconfirmed natural terminal state retains its actual result and exact termination reason.
- The selected mode's pre-start state begins only after that commit succeeds. Creating the later game is a separate operation triggered by **开始对局**.
- A failed archive operation leaves the previously committed active game intact, creates no new game, and does not continue to the selected mode. The requested destination may remain only as transient retry state and is discarded when the flow is cancelled.

### Accepted pre-start state behavior

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

The MVP supports both export and import. Export produces a portable, versioned game archive rather than a copy of the database. Import is a core operation and must never partially commit a game. Exported files must round-trip across all supported platforms.

### Accepted MVP record behavior

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

## Migration

The core owns database schema versioning and migrates the store forward from every schema shipped in an internal build.

Archive versions form a separate compatibility contract. Import and export code must use explicit archive-version dispatch and preserve the ability to reject versions it cannot safely interpret. A database migration must not silently change the meaning of an existing archive.

## Local-only boundary

The app does not use cloud synchronization, remote storage, or network backup on any platform. Its data model must not assume multiple devices or concurrent writers. Normal operating-system device backups are outside the app's synchronization design.

## Need to discuss

> The following questions are non-normative and are not implementation requirements.

- Which portable format and file extension should version 1 use?
- Define stable serialized identifiers for the accepted natural, resignation, and ended-early outcomes, plus any additional end reasons the archive requires.
- Which provenance fields should distinguish locally played, imported, and future derived games?
- Decide which local library metadata, including pin state, belongs in exported archives and canonical duplicate comparison.
- Define canonical game-content equivalence for duplicate detection, including which volatile archive fields do not affect equality.
- What compatibility promise should later app versions make for older exported archives?
- Define the concrete SQLite schema, the pinned SQLite version and update policy, and the store's concurrency limits.
- Decide how frontends learn about library changes: operation return values only, or a change-notification mechanism.
- Define where Settings preferences live on each platform: the shared store or each platform's native preference system.
