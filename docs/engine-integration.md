# Engine Integration

This document is for Mini Xiangqi app engineers, engine integrators, build engineers, and reviewers. It is owned by the Xcode app repository and defines how the app may package, call, constrain, and validate an external Fairy-Stockfish engine. It does not define Fairy-Stockfish internals, fork maintenance, source-level patch design, upstream synchronization, implementation progress, or work tracking; those subjects belong in the Fairy-Stockfish repository.

> **Status: Draft app-side engine proposal.** The adapter, packaging, memory-pressure lifecycle, and runtime rules authority remain under discussion. Sections explicitly labeled accepted are normative; other material remains a proposal. Items under **Need to discuss** are non-normative.

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
- The three accepted user-facing Chinese levels are:
  - **快速**: `go movetime 1000`.
  - **标准**: `go movetime 3000`; this is the new-install default.
  - **深思**: `go movetime 5000`.
- The selected level identifier and exact `movetime` are frozen with a created game. Setup changes never alter the persistent Settings default, and an active game's level cannot be changed.
- `Threads` is initialized from `ProcessInfo.processInfo.activeProcessorCount`, so the engine uses the active processor count reported by the current device rather than a hard-coded count.
- Every level shares one adaptive Hash allocation policy. The target cap is 4 GiB, represented as 4096 MiB at the UCI boundary; the applied value may be lower when the safety budget requires it.
- When calculating the allocation, let `available` be a fresh value from `os_proc_available_memory()`. Reserve the greater of 20% of `available` or 128 MiB, define usable available memory as `max(0, available - reserve)`, then take the byte budget as the minimum of 4 GiB, 50% of `ProcessInfo.processInfo.physicalMemory`, and that usable amount.
- Convert the byte budget to MiB and round down to a 64 MiB multiple. UCI Hash remains an integer count of MiB; rounding to whole GiB would discard too much usable capacity.
- The minimum accepted Hash is 256 MiB. If the rounded budget is below 256 MiB, including when `os_proc_available_memory()` returns zero, the adapter does not initialize the AI engine and reports insufficient memory.
- The insufficient-memory path asks the user to close other apps and retry. Each retry obtains a fresh available-memory value and recalculates the budget. It does not use a smaller Hash or perform a special automatic cleanup pass as an alternative.
- Engine, variant, NNUE, and option identifiers are versioned with the internal profile so a saved diagnostic record can identify the configuration that produced a move.

Search speed statistics such as nodes per second, depth, and hash utilization are diagnostic signals, not substitutes for measured playing strength. The accepted 4 GiB cap and adaptive safety budget must still be checked against memory, energy, thermal, and response-time requirements on supported devices.

`UCI_Elo` is calibrated from chess results and must not be displayed as Mini Xiangqi Elo without independent Mini Xiangqi calibration. The accepted levels are relative app profiles rather than calibrated Mini Xiangqi ratings. Whole-game results, response time, energy, and thermal measurements may justify a later explicit product revision, but diagnostic NPS or depth alone does not silently retune them.

## Variant and chase behavior

### Accepted target rule-integration decisions

- Built-in `minixiangqi` is limited to research, adapter, ordinary-movement, and search-integration baselines. It is not the final target-MVP rule configuration.
- The target uses a pinned custom variant derived from `minixiangqi` with AXF chasing adjudication.
- The custom variant disables the inherited move-count rule with `nMoveRule = 0`, uses `nFoldRule = 3`, and preserves illegal-perpetual-check adjudication.
- The target behavior follows the selected PyChess Mini Xiangqi rules: neutral threefold repetition is a draw; a unilateral perpetual checker or chaser loses; a mutual same-class violation draws; checking takes precedence over chasing; and kings and soldiers are excluded as chase targets.
- Mini Xiangqi soldiers move sideways from the start while remaining excluded as chase targets.
- If the pinned AXF configuration cannot satisfy the soldier exclusion or another approved observable fixture, the Fairy-Stockfish repository owns the required source change and fork-specific tests. The app repository records the required behavior and the pinned artifact it consumes.

Engine search may evaluate a neutral threefold repetition as draw-valued, but that evaluation does not automatically commit the app-visible game or History record. The rules boundary must expose claim eligibility to the accepted product flow.

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
- Define the exact ordering and cleanup contract between pre-start engine preparation, Random resolution, active-game persistence, and initial search.
- Define user-visible recovery if the Hash allocation itself fails despite a calculated budget of at least 256 MiB.
- Approve the minimized soldier and chase fixtures that would justify a fork patch.
- Decide the custom variant's final identifier, bundled configuration filename, network alias strategy, and focused fork patch boundary.
- Establish the research NNUE's provenance and license or select a replacement, then approve the distribution asset's packaging name, compatibility checks, and fallback policy.
- Define the pinned-manifest format shared between the app and Fairy-Stockfish repositories.
