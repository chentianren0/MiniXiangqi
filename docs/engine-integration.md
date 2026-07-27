# Engine Integration

This document is for Mini Xiangqi engineers, engine integrators, build engineers, and reviewers. It defines how the shared core packages, calls, constrains, and validates the embedded Fairy-Stockfish engine, and the app-visible policies built on it. It does not define Fairy-Stockfish internals, fork maintenance, source-level patch design, upstream synchronization, implementation progress, or work tracking; those subjects belong in the Fairy-Stockfish repository.

> **Status: Partially accepted engine contract.** The search-facade placement, AI profiles, rule-integration decisions, NNUE handling policy, and Apple memory entitlements below are accepted. The concrete interface, packaging mechanics, and memory-pressure lifecycle remain draft. Items under **Need to discuss** are non-normative.

## Scope and ownership

- The shared core owns the search facade, packaged engine artifacts, option profiles, lifecycle integration, cancellation, and validation, as placed by [architecture.md](architecture.md). Frontends own the user-facing failure presentation.
- The `ppppvz/Fairy-Stockfish` fork owns any Fairy-Stockfish source changes, fork-specific tests, build implementation, and upstream maintenance.
- The official Fairy-Stockfish repository is reference-only unless the user separately authorizes a contribution.
- Engine source revisions, patches, build inputs, variant configuration, networks, and hashes must be pinned reproducibly.

## Search facade boundary

The core's search facade receives an app-approved position and the history required by the selected engine behavior. It returns a proposed move and bounded diagnostic information. Engine callbacks must not mutate frontend state or the library store directly.

The facade must provide:

- initialization and verified capability discovery;
- variant and evaluation configuration;
- asynchronous search with explicit resource limits;
- cooperative cancellation and deterministic teardown;
- request identity and position-revision identity;
- a proposed move result or typed failure;
- rejection of a result that is cancelled, stale, malformed, or illegal under the rules facade.

The engine runs in-process inside the core, behind the core's C interface; frontends never speak UCI or reach the engine directly.

## Search lifecycle

- Search runs away from the frontend's main/UI thread.
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
- `Threads` is initialized from the active processor count the platform reports at engine initialization — `ProcessInfo.processInfo.activeProcessorCount` on Apple platforms and the Windows equivalent — rather than a hard-coded count.
- Every level shares one adaptive Hash allocation policy. The target cap is 4 GiB, represented as 4096 MiB at the UCI boundary; the applied value may be lower when the safety budget requires it.
- The frontend supplies a fresh available-memory value from a platform memory probe at each calculation. On iOS and iPadOS the probe is `os_proc_available_memory()`, which reflects the process's remaining limit. On macOS and Windows, where no comparable per-process limit applies, the probe reports the system's available physical memory.
- When calculating the allocation, let `available` be that fresh probe value. Reserve the greater of 20% of `available` or 128 MiB, define usable available memory as `max(0, available - reserve)`, then take the byte budget as the minimum of 4 GiB, 50% of the device's physical memory, and that usable amount.
- Convert the byte budget to MiB and round down to a 64 MiB multiple. UCI Hash remains an integer count of MiB; rounding to whole GiB would discard too much usable capacity.
- The minimum accepted Hash is 256 MiB. If the rounded budget is below 256 MiB, including when the probe reports zero, the facade does not initialize the AI engine and reports insufficient memory.
- The insufficient-memory path asks the user to close other apps and retry. Each retry obtains a fresh available-memory value and recalculates the budget. It does not use a smaller Hash or perform a special automatic cleanup pass as an alternative.
- Engine, variant, NNUE, and option identifiers are versioned with the internal profile so a saved diagnostic record can identify the configuration that produced a move.

Search speed statistics such as nodes per second, depth, and hash utilization are diagnostic signals, not substitutes for measured playing strength. The accepted 4 GiB cap and adaptive safety budget must still be checked against memory, energy, thermal, and response-time requirements on supported devices.

`UCI_Elo` is calibrated from chess results and must not be displayed as Mini Xiangqi Elo without independent Mini Xiangqi calibration. The accepted levels are relative app profiles rather than calibrated Mini Xiangqi ratings. Whole-game results, response time, energy, and thermal measurements may justify a later explicit product revision, but diagnostic NPS or depth alone does not silently retune them.

## Variant and chase behavior

### Accepted target rule-integration decisions

- Built-in `minixiangqi` is limited to research, search-facade, ordinary-movement, and search-integration baselines. It is not the final target-MVP rule configuration.
- The target uses a pinned custom variant derived from `minixiangqi` with AXF chasing adjudication.
- The custom variant disables the inherited move-count rule with `nMoveRule = 0`, uses `nFoldRule = 3`, and preserves illegal-perpetual-check adjudication.
- The target behavior follows the selected PyChess Mini Xiangqi rules: neutral threefold repetition is a draw; a unilateral perpetual checker or chaser loses; a mutual same-class violation draws; checking takes precedence over chasing; and kings and soldiers are excluded as chase targets.
- Mini Xiangqi soldiers move sideways from the start while remaining excluded as chase targets.
- If the pinned AXF configuration cannot satisfy the soldier exclusion or another approved observable fixture, the Fairy-Stockfish repository owns the required source change and fork-specific tests. The app repository records the required behavior and the pinned artifact it consumes.

Engine search may evaluate a neutral threefold repetition as draw-valued, but that evaluation does not automatically commit the app-visible game or History record. The rules facade must expose claim eligibility to the accepted product flow.

The core's rules facade is the authoritative runtime rules component, as accepted in [architecture.md](architecture.md) and [xiangqi-rules.md](xiangqi-rules.md). Engine search and the rules facade must be validated against the same approved history fixtures.

## Packaging and NNUE

### Accepted NNUE handling policy

- The repository never contains NNUE bytes. The network file is not committed to version control in any form; it enters builds from a workspace- or CI-provided location.
- Bundling the pinned network into internal builds is accepted. The product is an internal education app distributed only to internal testers, and the user has approved using and bundling the existing network on that basis.
- The bundled network is pinned by exact byte length and SHA-256 in a machine-readable manifest, and the build verifies the hash before packaging. A hash mismatch fails the build rather than shipping unverified bytes.
- The selected network is `minixiangqi-12c45d5da817.nnue`: 4,333,499 bytes, SHA-256 `12c45d5da817e7948cc22f2f295a0781dabd379be472006360c36676f1cc09ce`. Its structural loading with the current local `minixiangqi` engine has been verified.
- The file's known trainer string is not sufficient provenance or licensing evidence. Establishing origin, training revision, and redistribution license — or replacing the network — becomes a mandatory gate only if distribution ever expands beyond internal testing; no such expansion is planned.

### Build and packaging requirements

- App builds must use pinned GPLv3-compatible source inputs and reproducible platform settings.
- Packaged engine binaries require recorded origin, revision, license, byte length, and cryptographic hash.
- Network compatibility must be validated for the exact variant and build.
- Missing, corrupted, incompatible, or rejected evaluation assets must produce a contained error or an explicitly approved fallback; they must not terminate the app.
- Third-party notices and corresponding-source availability for GPLv3 inputs must be prepared before any build containing the engine is distributed to internal testers.
- Long or large engine and core builds are recommended to run on GitHub Actions CI with pinned inputs, per [architecture.md](architecture.md).

## Accepted Apple memory entitlements

- The shared multiplatform app target enables `com.apple.developer.kernel.increased-memory-limit` and `com.apple.developer.kernel.extended-virtual-addressing`. Their intended benefit is on iOS and iPadOS; macOS and Windows behavior must not depend on them. The app must still work when an increased memory limit is unavailable.
- Extended virtual addressing is not treated as additional physical memory or permission to consume all available memory. Hash and other engine allocations remain explicitly bounded and subject to device measurement.

## Need to discuss

> The following questions are non-normative and are not implementation requirements.

- Define the search facade's exact C-interface functions and the legal-move/result handoff with the rules facade.
- Define backgrounding, suspension, teardown, and memory-pressure behavior on each platform.
- Define the exact ordering and cleanup contract between pre-start engine preparation, Random resolution, active-game persistence, and initial search.
- Define user-visible recovery if the Hash allocation itself fails despite a calculated budget of at least 256 MiB.
- Select the exact Windows memory-probe API and verify the probe behavior on macOS.
- Approve the minimized soldier and chase fixtures that would justify a fork patch.
- Decide the custom variant's final identifier, bundled configuration filename, network alias strategy, and focused fork patch boundary.
- Approve the bundled network's packaging name, load-verification checks, and fallback policy for each platform's build.
- Define the pinned-manifest format shared between the app and Fairy-Stockfish repositories.
