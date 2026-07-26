# Game Data

This document is for engineers and reviewers responsible for persistence, game-history compatibility, and file interchange in the Mini Xiangqi app. It is owned by the Mini Xiangqi app repository and defines a draft local-data contract. It does not define Xiangqi rules, screen flows, engine internals, implementation progress, or issue tracking.

> **Status: Draft data proposal.** This records the current SwiftData recommendation, not an implemented or approved schema. Nothing in this document is normative until its status or an individual section is explicitly marked accepted. Items under **Need to discuss** are non-normative.

## Storage model

SwiftData is the recommended local persistence framework. Persistent models remain behind a repository boundary; the running game uses pure Swift value types.

The conceptual model has:

- one logical `GameLibrary`, with an optional reference to the single active game;
- one `StoredGame` per active or completed game;
- queryable summary fields on `StoredGame`, such as stable identity, dates, play mode, participants, and result summary;
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
- Starting a new game while one is active first ends the old game and places it in history.
- Ending the old game, creating the new game, and changing `GameLibrary.activeGame` form one atomic replacement operation.
- A failed replacement leaves the previously committed active game intact.

## Active games, history, and undo

There is at most one active game. Completed games are immutable history records: replay is read-only, and editing their move line is not supported. A history record may be explicitly deleted.

Undo changes the active game's main line and is saved immediately. The exact unit and depth of undo, whether redo exists, and the transition between a terminal active game and immutable history still need product decisions.

## Import and export

The MVP supports both export and import. Export produces a portable, versioned game archive rather than a copy of the SwiftData database. Import is a repository operation and must never partially commit a game.

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
- Which outcome and end-reason values are required, including user-ended unfinished games?
- Which provenance fields should distinguish locally played, imported, and future derived games?
- How should duplicate identities and repeated imports be handled?
- When exactly does a terminal game become immutable, and is undo available before that transition?
- Does one-step undo remove one ply or one complete human/computer turn in each play mode, and is redo available?
- Should import accept only completed history games, or also an active-game record?
- What compatibility promise should later app versions make for older exported archives?
