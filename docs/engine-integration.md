# Engine Integration

This document is for Mini Xiangqi app engineers, engine integrators, build engineers, and reviewers. It is owned by the Xcode app repository and defines how the app may package, call, constrain, and validate an external Fairy-Stockfish engine. It does not define Fairy-Stockfish internals, fork maintenance, source-level patch design, upstream synchronization, implementation progress, or work tracking; those subjects belong in the Fairy-Stockfish repository.

> **Status: Draft app-side engine proposal.** The adapter, packaging, exact AI level names and timings, shared Hash size, and runtime rules authority remain under discussion. Sections explicitly labeled accepted are normative; other material remains a proposal. Items under **Need to discuss** are non-normative.

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

### Accepted search-profile policy

- User-facing levels use localized names rather than an unverified Mini Xiangqi Elo claim.
- All levels share the same strongest accepted engine configuration and differ only in their maximum thinking time, sent through `go movetime`.
- The shared configuration uses `Skill Level = 20`, `UCI_LimitStrength = false`, `MultiPV = 1`, `Ponder = false`, and NNUE evaluation.
- Search has no node or depth limit. The time boundary controls when each level must return its move.
- `Threads` is initialized from `ProcessInfo.processInfo.activeProcessorCount`, so the engine uses the active processor count reported by the current device rather than a hard-coded count.
- One bounded Hash value is shared by every level. The final value remains unresolved pending game-strength and device-resource comparison of the accepted candidates.
- Engine, variant, NNUE, and option identifiers are versioned with the internal profile so a saved diagnostic record can identify the configuration that produced a move.

Search speed statistics such as nodes per second, depth, and hash utilization are diagnostic signals, not substitutes for measured playing strength. Candidate shared configurations are selected primarily through game results under controlled paired comparisons, then checked against memory, energy, thermal, and response-time requirements on supported devices.

`UCI_Elo` is calibrated from chess results and must not be displayed as Mini Xiangqi Elo without independent Mini Xiangqi calibration. The number and names of levels and each level's exact `movetime` remain unresolved until the target variant, network, and representative-device measurements are stable.

## Variant and chase behavior

### Accepted target rule-integration decisions

- Built-in `minixiangqi` is limited to research, adapter, ordinary-movement, and search-integration baselines. It is not the final target-MVP rule configuration.
- The target uses a pinned custom variant derived from `minixiangqi` with AXF chasing adjudication.
- The custom variant disables the inherited move-count rule with `nMoveRule = 0`, uses `nFoldRule = 3`, and preserves illegal-perpetual-check adjudication.
- The target behavior follows the selected PyChess Mini Xiangqi rules: neutral threefold repetition is a draw; a unilateral perpetual checker or chaser loses; a mutual same-class violation draws; checking takes precedence over chasing; and kings and soldiers are excluded as chase targets.
- Mini Xiangqi soldiers move sideways from the start while remaining excluded as chase targets.
- If the pinned AXF configuration cannot satisfy the soldier exclusion or another approved observable fixture, the Fairy-Stockfish repository owns the required source change and fork-specific tests. The app repository records the required behavior and the pinned artifact it consumes.

The exact authoritative runtime rules component and adapter handoff remain unresolved. Whichever component commits the result, engine search and app-visible adjudication must be validated against the same approved history fixtures.

## Packaging and NNUE

- App builds must use pinned GPLv3-compatible source inputs and reproducible Apple-platform settings.
- Packaged binaries and networks require recorded origin, revision, license, byte length, and cryptographic hash.
- Network compatibility must be validated for the exact variant and build.
- Missing, corrupted, incompatible, or rejected evaluation assets must produce a contained error or an explicitly approved fallback; they must not terminate the app.
- Third-party notices and corresponding-source obligations must be prepared before a build containing the engine or network is distributed through TestFlight.

## Accepted research-stage resource decisions

These decisions apply to current local research. They do not approve the current network as the final TestFlight or other distribution asset.

- `minixiangqi-12c45d5da817.nnue` is selected and currently used for research.
- The currently inspected file is 4,333,499 bytes with SHA-256 `12c45d5da817e7948cc22f2f295a0781dabd379be472006360c36676f1cc09ce`. Its structural loading with the current local `minixiangqi` engine has been verified.
- The file's known trainer string is not sufficient provenance or licensing evidence. Origin, training revision, redistribution license, and the final packaged asset remain release gates.
- The shared multiplatform app target enables `com.apple.developer.kernel.increased-memory-limit` and `com.apple.developer.kernel.extended-virtual-addressing`. Their intended benefit is on iOS and iPadOS; macOS behavior must not depend on them. The app must still work when an increased memory limit is unavailable.
- Extended virtual addressing is not treated as additional physical memory or permission to consume all available memory. Hash and other engine allocations remain explicitly bounded and subject to device measurement.

## Need to discuss

> The following questions are non-normative and are not implementation requirements.

- Decide the authoritative runtime rules component and the adapter's legal-move/result handoff.
- If adjudication is outside the engine, decide how search receives equivalent repetition and chase semantics so it does not prefer a line the product later rules as losing.
- Select the Swift-to-engine bridge and Apple-platform packaging format.
- Define backgrounding, suspension, teardown, and memory-pressure behavior.
- Approve the AI level names and each level's exact `movetime`.
- Select the shared Hash value after controlled game-strength comparison and supported-device memory, energy, and thermal measurement.
- Approve the minimized soldier and chase fixtures that would justify a fork patch.
- Decide the custom variant's final identifier, bundled configuration filename, network alias strategy, and focused fork patch boundary.
- Establish the research NNUE's provenance and license or select a replacement, then approve the distribution asset's packaging name, compatibility checks, and fallback policy.
- Define the pinned-manifest format shared between the app and Fairy-Stockfish repositories.
