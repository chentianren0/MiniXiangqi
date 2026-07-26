# Engine Integration

This document is for Mini Xiangqi app engineers, engine integrators, build engineers, and reviewers. It is owned by the Xcode app repository and defines how the app may package, call, constrain, and validate an external Fairy-Stockfish engine. It does not define Fairy-Stockfish internals, fork maintenance, source-level patch design, upstream synchronization, implementation progress, or work tracking; those subjects belong in the Fairy-Stockfish repository.

> **Status: Draft app-side engine proposal.** The adapter, packaging, AI profiles, and exact runtime rules authority remain under discussion. Nothing in this document is normative until its status or an individual section is explicitly marked accepted. Items under **Need to discuss** are non-normative.

## Scope and ownership

- The app owns the adapter API, packaged engine artifacts, option profiles, lifecycle integration, cancellation, validation, and user-facing failure behavior.
- The `ppppvz/Fairy-Stockfish` fork owns any Fairy-Stockfish source changes, fork-specific tests, build implementation, and upstream maintenance.
- The official Fairy-Stockfish repository is reference-only unless the user separately authorizes a contribution.
- Engine source revisions, patches, build inputs, variant configuration, networks, and hashes must be pinned reproducibly.

## Adapter boundary

The app provides a position and the history required by the selected engine behavior. The engine returns a proposed move and bounded diagnostic information. Engine callbacks must not mutate SwiftUI views, live domain state, or SwiftData models directly.

The adapter must provide:

- initialization and verified capability discovery;
- variant and evaluation configuration;
- asynchronous search with explicit resource limits;
- cooperative cancellation and deterministic teardown;
- request identity and position-revision identity;
- a proposed move result or typed failure;
- rejection of a result that is cancelled, stale, malformed, or illegal under the selected rules boundary.

The concrete Swift/C/C++ or Objective-C++ interface has not been selected.

## Search lifecycle

- Search runs away from the main actor.
- Undo, game completion, active-game replacement, and a newer search request cancel affected work.
- Cancellation does not make a late callback trustworthy; every result is checked against the current game and position revision.
- Engine failure must not corrupt or partially advance the committed game.
- The app must be able to shut down the engine without relying on process termination.

## AI difficulty profiles

User-facing levels use localized names rather than an unverified Mini Xiangqi Elo claim. A versioned internal profile may combine:

- Fairy-Stockfish `Skill Level`;
- a node budget;
- a wall-time cap;
- thread and hash limits;
- engine, variant, and evaluation identifiers.

`UCI_Elo` is calibrated from chess results and must not be displayed as Mini Xiangqi Elo without independent calibration. Exact level names and profile values require measurement on the supported devices after the variant and evaluation network are fixed.

## Variant and chase behavior

- Built-in `minixiangqi` is a baseline for adapter, movement, and search integration.
- A configuration-only AXF child is an experimental candidate for long-check and long-chase fixtures.
- The app-side contract requires Mini Xiangqi soldiers to move sideways from the start while remaining excluded as chase targets under the selected public rules.
- If approved fixtures show that no pinned engine configuration satisfies that observable behavior, the Fairy-Stockfish repository must own the source analysis, patch design, and fork-specific tests. This document records only the app-facing requirement and the pinned artifact it consumes.

## Packaging and NNUE

- App builds must use pinned GPLv3-compatible source inputs and reproducible Apple-platform settings.
- Packaged binaries and networks require recorded origin, revision, license, byte length, and cryptographic hash.
- Network compatibility must be validated for the exact variant and build.
- Missing, corrupted, incompatible, or rejected evaluation assets must produce a contained error or an explicitly approved fallback; they must not terminate the app.
- Third-party notices and corresponding-source obligations must be prepared before a build containing the engine or network is distributed through TestFlight.

## Need to discuss

> The following questions are non-normative and are not implementation requirements.

- Decide the authoritative runtime rules component and the adapter's legal-move/result handoff.
- If adjudication is outside the engine, decide how search receives equivalent repetition and chase semantics so it does not prefer a line the product later rules as losing.
- Select the Swift-to-engine bridge and Apple-platform packaging format.
- Define backgrounding, suspension, teardown, and memory-pressure behavior.
- Approve named AI levels and calibrated node/time profiles.
- Decide whether the MVP uses built-in Mini Xiangqi, an AXF child, or a focused fork variant.
- Approve the minimized soldier and chase fixtures that would justify a fork patch.
- Establish the NNUE provenance, license, packaging name, compatibility checks, and fallback policy.
- Define the pinned-manifest format shared between the app and Fairy-Stockfish repositories.
