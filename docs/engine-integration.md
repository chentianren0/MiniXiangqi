# Engine Integration

This document is for Mini Xiangqi engineers, engine integrators, build engineers, and reviewers. It defines how the shared core packages, calls, constrains, and validates the embedded Fairy-Stockfish engine, and the app-visible policies built on it. It does not define Fairy-Stockfish internals, fork maintenance, source-level patch design, upstream synchronization, implementation progress, or work tracking; those subjects belong in the Fairy-Stockfish repository.

> **Status: Accepted engine contract.** The search-facade placement, AI profiles, rule-integration decisions, failure-containment decisions, NNUE handling policy, Apple memory entitlements, backgrounding and teardown behavior, preparation ordering, variant packaging, network failure policy, the fork change set, the pinned-input manifest, and the library build requirement below are all accepted; the concrete search-facade C surface is the accepted contract in [core-interface.md](core-interface.md). Items under **Need to discuss** are non-normative.

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

The engine runs in-process inside the core, behind the core's C interface; frontends never speak UCI or reach the engine directly. The concrete search-facade functions, request/result types, cancellation and stale-rejection mechanics, and threading rules are the accepted contract in [core-interface.md](core-interface.md).

### Accepted failure-containment decisions

- The unmodified engine terminates the process when transposition-table allocation fails, and on Windows when freeing large-page memory fails inside the same Hash path; the accepted error contract forbids any exit crossing the core boundary. Recoverable Hash allocation and release are therefore a required focused change in the Fairy-Stockfish fork, alongside the soldier chase-target exclusion; the C interface reserves a typed error for it that is unreachable until that change lands.
- The engine's NNUE load state is observable before any search, so the core preflights the configured network itself and the engine's own fatal load-verification path is never reached. NNUE verification requires no fork change.

### Accepted fork change set

The pinned fork carries only focused changes this contract or [xiangqi-rules.md](xiangqi-rules.md) requires, each recorded in the manifest:

- **Soldier chase-target exclusion**, which the approved fixture `mx-chs-003` requires. Landed; it introduces a variant property whose default preserves every existing variant's adjudication.
- **Recoverable Hash allocation and release**, replacing the process exits on transposition-table allocation failure and on the Windows large-page free path, which the accepted error contract forbids.
- **A static library target**, per the build requirement below.
- **Correction of two adjudication defects that produce false terminal losses** — a chaser counted as chasing while pinned, and a flying-general pin test that counts only the victim's own pieces on the shared file, so a chaser standing between the two generals is invisible to it and a demonstrably free piece is marked pinned. Both are wrong-result defects rather than judgement calls.
- **Completion of the chase-target exemption in the discovered-check classifier path**, so the accepted exclusion of generals and soldiers holds in every path rather than in two of three.
- **A read-only accessor reporting which repetition branch fired**, so the reserved `mutual-perpetual-chase` reason can be recorded. It changes no adjudication.
- **Correction of the repetition window's parity asymmetry**, which evaluates one side over a wider span than the other. In a unilateral chase this costs one ply of detection. In a mutual perpetual chase it is terminal: the draw the contract requires is adjudicated as a unilateral loss, and which of two equally violating sides loses depends only on which of them made the move that entered the position.

Every change must keep the fork's own suite passing and every approved fixture passing.

Preserving other variants' adjudication exactly is the preferred bar and the first patch met it, but it is not absolute, and the parity correction is the accepted exception. It is not a rules difference that a variant property could express — the repetition window is the same rule in every chasing variant — so gating it would mean carrying a second code path whose only purpose is to preserve the defect for variants this product does not ship. The measurements: the fork's 22 tests pass on both builds, all 16 approved fixtures pass identically, and a broad 1,786-history differential shows no difference at all. A targeted sweep for the asymmetry itself finds 53 parity splits in built-in `xiangqi`, every one of them removed by the correction, and every one changing a `draw` into the verdict the unpatched engine already reaches one ply later. The change is provably inert for any variant that does not set a chasing rule, which in the fork is every variant except `xiangqi` and our own.

The two adjudication corrections rest on execution-confirmed defects rather than on the deferred definitions of protection, interruption, and discovered or pinned attacks, which [xiangqi-rules.md](xiangqi-rules.md) still leaves open, and each lands together with the fixture that pins it.

The classifier-path completion is different in kind and carries no fixture: a targeted search of 29,500 legal samples over 11.2 million cycles found **no** position where the gap changes an outcome, so it may well be unreachable. It is accepted not because a defect was demonstrated but because the accepted exclusion of kings and soldiers as chase targets should hold in every classifier path rather than in two of three, and completing it is one line inside a function the fork already patches. The parity correction is decided and listed above; [xiangqi-rules.md](xiangqi-rules.md) records the rule it restores.

## Search lifecycle

- Search runs away from the frontend's main/UI thread.
- Undo, game completion, active-game replacement, and a newer search request cancel affected work.
- Cancellation does not make a late callback trustworthy; every result is checked against the current game and position revision.
- Engine failure must not corrupt or partially advance the committed game.
- The app must be able to shut down the engine without relying on process termination.

### Accepted backgrounding and teardown behavior

The trigger is **the platform's own suspension or memory-pressure signal, not loss of focus**. On iOS and iPadOS it is scene backgrounding, and also a foreground memory-pressure warning — the last signal before the system reclaims the process, on the platform where the per-process limit, the memory entitlements and up to 4 GiB of Hash all apply. On macOS and Windows, where an unfocused window is still a running app, it is system sleep, app termination, and a memory-pressure notification; switching windows changes nothing. Releasing gigabytes of Hash every time the user clicks another window would be worse than the problem this rule exists to solve.

On that signal, any running search is cancelled **and the transposition table released**, returning the engine to the uninitialized state. The reason is the Hash budget itself: it is bounded only by 4 GiB and the device's memory, so a suspended app can be holding gigabytes it is not using — precisely the profile the operating system reclaims first. Losing the app costs the user their place; losing an in-flight search costs at most five seconds, and the position it was thinking about is committed and unchanged.

- The committed game is never affected. The active game is already persisted, and a search result is never what commits a move.
- A result arriving from a search cancelled this way is discarded because **its request is no longer the current one** — the cancellation itself is what rejects it. The position-revision check does not cover this case: no mutation occurred, so the revision is unchanged and a late result would match it.
- If the signal arrives during an in-flight game creation, the attempt is invalidated exactly as leaving the pre-start state invalidates it: anything prepared is released, no game is created, and a late completion cannot commit.
- **Re-preparation happens when a search is next owed, not on return to the foreground.** A search is owed exactly when the resumed state is an active human-versus-AI game whose committed status reports the AI to move and a search expected. Replay, Free Play, a confirmed result, a game awaiting the user's move, and having no active game all require no engine, so none of them re-prepares one.
- Re-preparation obtains a fresh memory probe and can fail, most plausibly because memory conditions changed while the app was away. It reports the same insufficient-memory error as any other preparation. The game remains active, saved, and resumable, with the AI unable to move until preparation succeeds. What the user sees in that mid-game case is not the accepted pre-start notice, whose wording and actions assume a game that has not started; it is an open interaction question below.
- Every one of these paths cancels and releases whole. None shrinks Hash in place: a partially reduced transposition table is not a state this contract defines.
- Teardown is deterministic and does not depend on process termination: cancellation, then engine release, then the store's outstanding work. It must not block the thread delivering the platform's lifecycle event.

### Accepted preparation ordering

Human-versus-AI game creation runs **prepare → resolve → create → search**, and each step is a gate on the next:

1. **Prepare** the engine from a fresh memory probe. Failure here reports insufficient memory and creates nothing.
2. **Resolve** a Random first-mover choice, as part of the same creation operation and only after preparation succeeds. Resolution is not committed anywhere until step 3 succeeds, so a resolved side never survives a failed creation and a retry draws again.
3. **Create and persist** the active game, freezing mode, resolved human side, level identifier, and exact `movetime`. Failure here releases the prepared engine and creates nothing.
4. **Search**, if the resolved first mover is the AI.

Leaving the pre-start state at any point invalidates the attempt, releases anything prepared, and prevents a late completion from committing.

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
- The serialized level identifiers are `fast`, `standard`, and `deep`, per the archive vocabulary in [game-data.md](game-data.md).
- `Threads` is initialized from the active processor count the platform reports at engine initialization — `ProcessInfo.processInfo.activeProcessorCount` on Apple platforms and the Windows equivalent — rather than a hard-coded count.
- Every level shares one adaptive Hash allocation policy. The target cap is 4 GiB, represented as 4096 MiB at the UCI boundary; the applied value may be lower when the safety budget requires it.
- The frontend supplies a fresh available-memory value from a platform memory probe at each calculation. On iOS and iPadOS the probe is `os_proc_available_memory()`, which reflects the process's remaining limit. On macOS and Windows, where no comparable per-process limit applies, the probe reports the system's available physical memory.
- When calculating the allocation, let `available` be that fresh probe value. Reserve the greater of 20% of `available` or 128 MiB, define usable available memory as `max(0, available - reserve)`, then take the byte budget as the minimum of 4 GiB, 50% of the device's physical memory, and that usable amount.
- Convert the byte budget to MiB and round down to a 64 MiB multiple. UCI Hash remains an integer count of MiB; rounding to whole GiB would discard too much usable capacity.
- The minimum accepted Hash is 256 MiB. If the rounded budget is below 256 MiB, including when the probe reports zero, the facade does not initialize the AI engine and reports insufficient memory.
- The insufficient-memory path asks the user to close other apps and retry. Each retry obtains a fresh available-memory value and recalculates the budget. It does not use a smaller Hash or perform a special automatic cleanup pass as an alternative.
- The budget is recalculated from a fresh probe, and the engine re-prepared with the resulting values, at each human-versus-AI game creation; a later game in the same launch never silently reuses an earlier game's memory decision.
- Engine, variant, NNUE, and option identifiers are versioned with the internal profile so a saved diagnostic record can identify the configuration that produced a move.
- The memory probe is `os_proc_available_memory()` on iOS and iPadOS; on macOS, `host_statistics64` with `HOST_VM_INFO64`, taking available memory as the free, inactive, and purgeable pages, with physical memory from `sysctlbyname("hw.memsize")`; and on Windows, `GlobalMemoryStatusEx`, taking `ullAvailPhys` and `ullTotalPhys`. Each probe's behavior is verified against the accepted budget boundaries on its own platform before that platform ships.
- If allocation fails even though the calculated budget was at least 256 MiB, the AI does not start and the frontend presents the accepted **无法启动 AI 对手** notice unchanged. The situation the user is in is the same one — memory is not available right now — and the same action resolves it, so a second message would name a distinction they cannot act on differently. Retry re-probes and recalculates exactly as it does for a below-minimum budget, and no smaller Hash is substituted.

Search speed statistics such as nodes per second, depth, and hash utilization are diagnostic signals, not substitutes for measured playing strength. The accepted 4 GiB cap and adaptive safety budget must still be checked against memory, energy, thermal, and response-time requirements on supported devices.

`UCI_Elo` is calibrated from chess results and must not be displayed as Mini Xiangqi Elo without independent Mini Xiangqi calibration. The accepted levels are relative app profiles rather than calibrated Mini Xiangqi ratings. Whole-game results, response time, energy, and thermal measurements may justify a later explicit product revision, but diagnostic NPS or depth alone does not silently retune them.

## Variant and chase behavior

### Accepted target rule-integration decisions

- Built-in `minixiangqi` is limited to research, search-facade, ordinary-movement, and search-integration baselines. It is not the final target-MVP rule configuration.
- The target uses a pinned custom variant derived from `minixiangqi` with AXF chasing adjudication.
- The custom variant disables the inherited move-count rule with `nMoveRule = 0`, uses `nFoldRule = 3`, and preserves illegal-perpetual-check adjudication.
- The target behavior follows the selected PyChess Mini Xiangqi rules: neutral threefold repetition is a draw; a unilateral perpetual checker or chaser loses; a mutual same-class violation draws; checking takes precedence over chasing; and kings and soldiers are excluded as chase targets.
- Mini Xiangqi soldiers move sideways from the start while remaining excluded as chase targets.
- AXF configuration alone does not satisfy the approved soldier-exclusion fixture `fixtures/rules/mx-chs-003`: the engine classifies every sideways-capable Mini Xiangqi soldier as a chase target, so the target variant requires a focused source change in the Fairy-Stockfish fork. The Fairy-Stockfish repository owns that change and its fork-specific tests; this repository records the required behavior and the pinned artifact it consumes.
- Built-in `minixiangqi`, which has no chasing rule, does not satisfy the unilateral-chase fixtures `mx-chs-001` and `mx-chs-004`. That is the accepted baseline limitation motivating the AXF-derived target, not a defect to fix.

### Accepted variant packaging

- The target variant's identifier is **`minixiangqiaxf`**, defined in a bundled configuration file named `minixiangqi-variants.ini`. The name is distinct from built-in `minixiangqi` so that the two can be selected unambiguously in the same build, which the fixture harness requires in order to run a variant and its control side by side.
- The variant keeps built-in `minixiangqi`'s board geometry and piece set exactly; it differs only in adjudication. That is what keeps the pinned network structurally valid for it.
- **The bundled network's filename must begin with the variant identifier.** `EvalFile` is not simply a path the engine opens: the engine restricts NNUE to the matching variant by requiring the file's basename to start with the variant name (or with a `nnueAlias` that an `.ini` variant cannot set). A basename that does not match does not produce an error, and does not change the `Use NNUE` option either — it clears the engine's *internal* NNUE flag, so the option still reads true while the engine plays on classical evaluation. The pinned network is therefore bundled as **`minixiangqiaxf-12c45d5da817.nnue`**. Only the filename changes; the bytes, the byte length, and the SHA-256 that pins them are unchanged, since the hash is over content.
- Because that failure is silent, the core's preflight must assert the engine's **effective NNUE state** after configuration, not merely that the file exists and parses. A preflight that checks only file presence would pass in exactly the case this rule exists to prevent.
- The fork's patch boundary is the set of focused source changes this contract and [xiangqi-rules.md](xiangqi-rules.md) require, each recorded in the pinned manifest by revision. Their implementation, tests, and upstream maintenance belong to the fork repository.

Engine search may evaluate a neutral threefold repetition as draw-valued, but that evaluation does not automatically commit the app-visible game or History record. The rules facade must expose claim eligibility to the accepted product flow.

The core's rules facade is the authoritative runtime rules component, as accepted in [architecture.md](architecture.md) and [xiangqi-rules.md](xiangqi-rules.md). Engine search and the rules facade must be validated against the same approved history fixtures.

## Packaging and NNUE

### Accepted NNUE handling policy

- The repository never contains NNUE bytes. The network file is not committed to version control in any form; it enters builds from a workspace- or CI-provided location.
- Bundling the pinned network into internal builds is accepted. The product is an internal education app distributed only to internal testers, and the user has approved using and bundling the existing network on that basis.
- The bundled network is pinned by exact byte length and SHA-256 in a machine-readable manifest, and the build verifies the hash before packaging. A hash mismatch fails the build rather than shipping unverified bytes.
- The selected network is 4,333,499 bytes, SHA-256 `12c45d5da817e7948cc22f2f295a0781dabd379be472006360c36676f1cc09ce`, bundled as `minixiangqiaxf-12c45d5da817.nnue` for the reason given under variant packaging. Its structural loading with the current local `minixiangqi` engine has been verified.
- The file's known trainer string is not sufficient provenance or licensing evidence. Establishing origin, training revision, and redistribution license — or replacing the network — becomes a mandatory gate only if distribution ever expands beyond internal testing; no such expansion is planned.

### Accepted network failure policy

The network is bundled and hash-verified at build time, so a verification failure at runtime means a damaged installation rather than a configuration the user chose. In that case **the AI does not start**, and the frontend reports it through the accepted engine-unavailable path.

There is no fallback to the engine's classical evaluation. The accepted levels are defined as sharing one strongest configuration and differing only in thinking time; substituting a different evaluation would silently make the opponent a different opponent, which the user would have no way to detect. Free Play, History, replay, import, and export are unaffected, and reinstalling restores the AI.

The core preflights the network against the engine's observable load state before any search, so this is detected during preparation and the engine's own fatal verification path is never reached.

### Accepted pinned-input manifest

One machine-readable manifest, `pinned-inputs.json`, at the root of this repository, is the single source of truth for every input a reproducible build consumes:

- the fork's repository, revision, and the ordered list of focused patches applied at that revision;
- the build flags and defines the app build uses for each supported platform;
- the bundled variant configuration's filename and SHA-256;
- the bundled network's filename, exact byte length, and SHA-256;
- the vendored SQLite amalgamation's version and SHA-256.

The build verifies every hash before packaging and fails on a mismatch rather than shipping unverified bytes. The fork repository owns how its patches are implemented and how its own artifacts are built; this manifest records which revision and which inputs the app consumes, so that an app build is reproducible without reading the fork's history.

### Accepted library build requirement

The fork must expose a **static library target** for every supported platform, which the core links. Its Makefile currently produces an executable and a Python module, neither of which the core can consume. The target's implementation belongs to the fork repository; what this contract requires is that the artifact exists, is built from the pinned revision and flags above, and is what the core links against.

### Build and packaging requirements

- App builds must use pinned GPLv3-compatible source inputs and reproducible platform settings.
- Packaged engine binaries require recorded origin, revision, license, byte length, and cryptographic hash.
- Network compatibility must be validated for the exact variant and build.
- Missing, corrupted, incompatible, or rejected evaluation assets must produce a contained error or an explicitly approved fallback; they must not terminate the app.
- Third-party notices and corresponding-source availability for GPLv3 inputs must be prepared before any build containing the engine is distributed to internal testers.
- Engine and core builds follow the build policy in [architecture.md](architecture.md): developer machines while the project is Apple-only, and CI covering a macOS runner and a Windows runner once Windows implementation begins.

## Accepted Apple memory entitlements

- The shared multiplatform app target enables `com.apple.developer.kernel.increased-memory-limit` and `com.apple.developer.kernel.extended-virtual-addressing`. Their intended benefit is on iOS and iPadOS; macOS and Windows behavior must not depend on them. The app must still work when an increased memory limit is unavailable.
- Extended virtual addressing is not treated as additional physical memory or permission to consume all available memory. Hash and other engine allocations remain explicitly bounded and subject to device measurement.

## Need to discuss

> The following questions are non-normative and are not implementation requirements.

- Define what the user sees when re-preparation fails mid-game, after the app was suspended and a search is owed. The accepted **无法启动 AI 对手** notice assumes a game that has not started, so its wording and its 取消 action do not fit; this belongs to [interaction-design.md](interaction-design.md).
- Confirm each platform's memory probe against the accepted budget boundaries on real hardware; the APIs are fixed above, their measured behavior is not.
- Fix the manifest's concrete field names and schema version when the first build consumes it.
- Decide whether a diagnostics surface later exposes bounded hash-utilization and nodes-per-second values, which are recorded as diagnostics rather than strength today.
