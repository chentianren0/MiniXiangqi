# Game Data

This document is for engineers and reviewers responsible for persistence, game-history compatibility, and file interchange in the Mini Xiangqi app. It is owned by the Mini Xiangqi app repository and defines a draft local-data contract. It does not define Xiangqi rules, screen flows, engine internals, implementation progress, or issue tracking.

> **Status: Draft data proposal.** This records the current SwiftData recommendation, not an implemented or approved schema. Nothing in this document is normative until its status or an individual section is explicitly marked accepted. Items under **Need to discuss** are non-normative.

## Storage model

SwiftData is the recommended local persistence framework. Persistent models remain behind a repository boundary; the running game uses pure Swift value types.

The conceptual model has:

- one logical `GameLibrary`, with an optional reference to the single active game;
- one `StoredGame` per active or completed game;
- queryable summary fields on `StoredGame`, such as stable identity, dates, play mode, participants, result summary, imported provenance, and pinned state;
- a versioned archive encoded as `Data` containing the complete replayable game record.

The repository enforces the single-library and single-active-game invariants even if the storage framework cannot express them as database constraints.

## Versioned game archive

The archive is independent of the SwiftData schema. It should contain enough information to reproduce and validate a game, including:

- archive format version;
- game identity and creation metadata;
- rules and variant version identifiers;
- initial position;
- ordered main-line moves;
- configuration needed to interpret the players and game;
- terminal information when the game is completed.

The serialization format is not yet selected. Callers must not decode or modify the archive outside the data boundary.

## Saving and replacement

- Save explicitly after every accepted move, undo, game completion, import, deletion, and other durable state change.
- Treat SwiftData autosave as a secondary safeguard, not the commit mechanism.
- A committed move is the recovery boundary after app exit or interruption.

### Accepted mode-selection replacement behavior

- Replacement accepts only an unfinished, nonterminal active game. An active game with an unconfirmed natural result must be undone or confirmed through the result flow rather than recorded as ended early.
- For either Human versus AI or Free Play, confirming replacement places the old game in History and clears `GameLibrary.activeGame` in one atomic operation.
- The selected mode's pre-start state begins only after that commit succeeds. Creating the later game is a separate operation triggered by **开始对局**.
- A failed replacement operation leaves the previously committed active game intact and does not continue to the selected mode.

### Accepted pre-start state behavior

- Neither mode's pre-start state is written to SwiftData or a game archive. Neither creates a `StoredGame` or changes `GameLibrary.activeGame`.
- Leaving either pre-start state discards it. If it was entered after ending an older game, that older game remains immutable History and is not restored.
- Human-versus-AI Settings defaults and the per-game setup draft are separate state. Entering setup creates a fresh in-memory draft from the current Settings defaults; reopening after leaving creates another fresh draft from the then-current defaults.
- A Random first-mover choice remains unresolved in the draft. Only successful **开始对局** creation commits the resolved human side, AI level identifier, and exact thinking-time value as durable active-game configuration.
- AI availability or active-game persistence failure creates no active game and changes no persistent game-library state. The unresolved draft may remain only while the setup page remains open.
- Free Play has no configurable draft fields. Its in-memory pre-start state retains only the pending mode until **开始对局** commits the new active game.
- A failed creation in either mode leaves no active game, retains the corresponding in-memory pre-start state for retry, and changes no persistent game-library state.
- Each creation attempt is single-flight and bound to the identity or revision of the pre-start session that initiated it. Duplicate Start actions are ignored or disabled, and leaving invalidates the session so a late result cannot commit a game.

## Active games, history, and undo

There is at most one active game. Completed games have immutable game content: replay is read-only, and editing their move line is not supported. Pinning or unpinning changes only mutable library metadata. A history record may be explicitly and permanently deleted.

Undo changes the active game's retained main line and is saved immediately. The archive does not preserve discarded moves, an undo count, hidden branches, or redo state.

- Free Play removes one ply per Undo action and supports repeated Undo to the initial position.
- Human-versus-AI Undo cancels an outstanding reply search and removes the triggering human move, or removes the completed AI reply together with the preceding human move. Repeated Undo proceeds by human decision cycles.
- If a human move itself produces an unconfirmed natural terminal state, Undo removes that human move.
- An unconfirmed natural terminal state remains the active game and can be undone. Confirming its result moves it to immutable History.
- A claimable neutral threefold repetition also remains an active game. Continuing does not create a History record; only claiming the draw commits an immutable draw record.
- Confirmed resignation records a human loss and moves the game to immutable History.
- Replacing an unfinished game records the old game in immutable History with an ended-early reason and no competitive result.
- A new move after Undo permanently replaces the discarded continuation.

## Import and export

The MVP supports both export and import. Export produces a portable, versioned game archive rather than a copy of the SwiftData database. Import is a repository operation and must never partially commit a game.

### Accepted MVP record behavior

- One exported file contains one immutable History game.
- Import processes one game file at a time. A successful import creates an immutable History record and never creates or replaces the active game.
- Imported and locally recorded History games have read-only game content. Pin or Unpin and permanent deletion remain distinct repository operations.
- History sorts pinned records before unpinned records. Each group sorts by a local History-added time, with the most recently completed or imported first. The original game dates remain separate metadata.
- History retains queryable summaries for the accepted list metadata: date, mode, result or end reason, move count, human side when applicable, and imported provenance.
- If a validated import has the same stable identity and the same game content as an existing record, the repository returns that existing record instead of inserting a duplicate.
- If a validated import has the same stable identity but different game content, the repository rejects the file as an identity conflict without changing persistent state.

The **Confirm Before Deleting** preference is local app state, defaults to enabled, and is not part of immutable game content. Once the accepted UI policy authorizes deletion, the repository removes the whole History record. The app has no deletion Undo, soft-deleted record, or Recently Deleted collection. A failed deletion leaves the existing record intact.

Imported files are untrusted input. Before saving, the importer must:

- enforce file-size and structural limits;
- reject unsupported versions and malformed fields;
- decode without executing embedded content or resolving network references;
- validate the initial position, ordered moves, and terminal claim through the selected rules boundary;
- reject inconsistent or incomplete records with a user-facing error;
- create no persistent objects until validation succeeds.

Imported games are local data. Importing must not contact a server.

## Migration

The app should define a SwiftData `VersionedSchema` and migration plan from the first TestFlight data model. SwiftData schema versions cover local database evolution.

Archive versions form a separate compatibility contract. Import and export code must use explicit archive-version dispatch and preserve the ability to reject versions it cannot safely interpret. A database migration must not silently change the meaning of an existing archive.

## Local-only boundary

The app does not use CloudKit, remote synchronization, or network backup. Its data model must not assume multiple-device or concurrent writers. Normal operating-system device backups are outside the app's synchronization design.

## Need to discuss

> The following questions are non-normative and are not implementation requirements.

- Which portable format and file extension should version 1 use?
- Define stable serialized identifiers for the accepted natural, resignation, and ended-early outcomes, plus any additional end reasons the archive requires.
- Which provenance fields should distinguish locally played, imported, and future derived games?
- Decide which local library metadata, including pin state, belongs in exported archives and canonical duplicate comparison.
- Define canonical game-content equivalence for duplicate detection, including which volatile archive fields do not affect equality.
- What compatibility promise should later app versions make for older exported archives?
