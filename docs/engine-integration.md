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
- **A static library target**, per the build requirement below. Landed, and the one change in this list the core does not consume: it compiles the vendored snapshot itself, on every platform.
- **Correction of two adjudication defects that produce false terminal losses** — a chaser counted as chasing while pinned, and a flying-general pin test that counts only the victim's own pieces on the shared file, so a chaser standing between the two generals is invisible to it and a demonstrably free piece is marked pinned. Both are wrong-result defects rather than judgement calls.
- **Completion of the chase-target exemption in the discovered-check classifier path**, so the accepted exclusion of generals and soldiers holds in every path rather than in two of three.
- **A read-only accessor reporting which repetition branch fired**, so the reserved `mutual-perpetual-chase` reason can be recorded. It changes no adjudication.
- **Correction of the repetition window's parity asymmetry**, which evaluates one side over a wider span than the other. In a unilateral chase this costs one ply of detection. In a mutual perpetual chase it is terminal: the draw the contract requires is adjudicated as a unilateral loss, and which of two equally violating sides loses depends only on which of them made the move that entered the position. It lands with a fixture pinning that corner specifically — a mutual chase entered by a quiet move from each side in turn, with the one-ply-later continuation as its control — without which the wrong-winner case is untested and would return silently if the change were ever lost in an upstream merge.
- **An explicit 8 MiB stack for search threads on MSVC.** The fork's thread header already asks for 8 MiB on Apple, on MinGW and on any build that selects pthreads, because deep searches need more than 1 MiB; the branch MSVC takes was the plain `std::thread` default case, which cannot be asked for a stack size at all, so every search thread on Windows ran on the 1 MiB the linker reserves. That is not enough under the defines this core compiles with: `LARGEBOARDS` makes `MAX_MOVES` 8192, so the move array inside every `MovePicker` is 64 KiB and search nests one per ply. A stack overflow on Windows is an uncatchable process kill, which is exactly what [architecture.md](architecture.md) forbids crossing the core boundary — the engine's failures must arrive as reported errors. The change creates the thread with `_beginthreadex` and the same 8 MiB, reserved rather than committed, and is scoped so that only MSVC reaches it; no other platform's behavior changes, and neither search nor adjudication changes on any platform. A linker `/STACK` setting on our own test executables was considered and rejected: it would steady our suites while leaving any host process that embeds the core on the 1 MiB default, which is the case that matters.

Every change must keep the fork's own suite passing and every approved fixture passing.

Preserving other variants' adjudication exactly is the preferred bar and the first patch met it, but it is not absolute, and two corrections are accepted exceptions: the repetition-window parity correction and the pinned-chaser correction. Both remove defects rather than change rules, and both reach built-in `xiangqi` because it is the only built-in variant that sets a chasing rule. It is not a rules difference that a variant property could express — the repetition window is the same rule in every chasing variant — so gating it would mean carrying a second code path whose only purpose is to preserve the defect for variants this product does not ship. The measurements: the fork's 22 tests pass on both builds, all 16 approved fixtures pass identically, and a broad 1,786-history differential shows no difference at all. A targeted sweep for the asymmetry itself finds 53 parity splits in built-in `xiangqi`, every one of them removed by the correction, and every one changing a `draw` into the verdict the unpatched engine already reaches one ply later. The pinned-chaser correction reaches built-in `xiangqi` as well, in the other direction: it turns a false terminal loss into the draw the position actually is, as when a pinned horse is credited with a chase it cannot deliver. Measured across roughly 235,000 adjudications, every difference between the unpatched and patched engines was attributed to one of these two corrections by single-hunk revert controls, and no variant without a chasing rule differs at all. The change is provably inert for any variant that does not set a chasing rule — which is every variant in the fork except `xiangqi`, the two variants that inherit from it, and our own.

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

**On macOS and Windows, a memory-pressure notification is not a suspension, and the two are kept apart.** Both take the same cancel-and-release path, whole rather than shrinking Hash in place. But a suspension has a counterpart — the app comes back, and the platform says so — while nothing will ever tell a desktop app that pressure has passed, and the app was never away: it is still in front of the person playing. So a memory-pressure release there is followed immediately by the ordinary question of whether a search is owed, asked again from a fresh probe. Under real pressure that produces the accepted insufficient-memory presentation, which is an answer the player can act on; treated as a suspension it would produce a machine that had quietly stopped playing and would never start again.

**iOS and iPadOS take the same path, and the platform's own probe is why that is a decision rather than an oversight.** The shared path is: cancel, release the table whole, then ask again from a fresh probe whether a search is owed. On the desktop that re-ask is safe because the probe reads a machine under pressure and answers smaller. **On iOS it is not the same kind of probe.** `os_proc_available_memory()` reports how much *this process* may still allocate before its own per-process limit — a number that does not fall because the system is pressured, and one that **rises** the moment the transposition table is released. So on iOS the immediate re-ask can hand back a Hash the size of the one just given up, which is exactly the re-allocation this document previously said the platform must not do.

**It ships that way, and the owner's deferral is why** (2026-07-30, recorded in issue #80): a wait, a smaller retry trigger, or a pressure design of the platform's own is deferred past the MVP. Deferring it leaves the shared path running rather than switching anything off — there is no iOS-specific behaviour to fall back to, because none was ever written, and `Suspension` and `Opponent` are unchanged. What makes that acceptable is the accepted worst case, which this document already carries and which does not move: the system reclaims the app. The app loses nothing when it does, because autosave has already committed and resume-at-launch stands; an in-flight search costs at most five seconds, and the position it was thinking about is committed and unchanged.

**On Windows the desktop rule has no pressure signal to hang on, and the MVP ships without one.** *(Decided with the Windows flows, 2026-07-30.)* The paragraph above assumes a memory-pressure notification, and macOS has one — a dispatch memory-pressure source, which the Apple frontend watches. Windows offers no equivalent to a foreground desktop process. `CreateMemoryResourceNotification` is a **machine-wide** low-memory object a thread waits on, and Microsoft's own documentation declines to state its thresholds; the WinRT `MemoryManager` app-memory events report a per-app limit that exists for a packaged app running under one and not for an unpackaged desktop process at all. Neither is the signal this rule was written for: the first says the machine is short rather than that this process is, and the second does not fire here.

**So Windows observes no mid-game memory-pressure signal, and what that costs is already bounded.** Three bounds, all of them in place rather than promised:

- The Hash a game holds was sized against the machine as it stood when that game was created. Every human-versus-AI preparation takes a fresh `GlobalMemoryStatusEx` probe and applies the accepted arithmetic — the reserve, the physical-memory cap, the 4 GiB cap, the 256 MiB minimum — so a game started on a busy machine gets a small table or no AI at all, which is the accepted insufficient-memory presentation and an answer the player can act on.
- The game on disk is whole at every instant, because the core commits each move inside its own call. The accepted worst case is the operating system reclaiming the app, and the app loses nothing when it does — the same worst case the iOS deferral rests on, and milder here: a desktop Windows process under pressure is paged, not killed.
- An in-flight search costs at most five seconds, and the position it was thinking about is committed and unchanged.

**Acting on the signal that does exist would be worse than not acting.** Taking a machine-wide notification with undocumented thresholds as this rule's trigger means releasing the table and then immediately re-asking from a fresh probe — and on a machine that is short but not short *for this process*, that re-ask produces the **无法启动 AI 对手** alert in the middle of a game that was playing perfectly well. The rule's own justification for the immediate re-ask is that under real pressure it "produces an answer the player can act on"; an alert raised by another process's allocation is not that answer, and a false one costs more than the release saves.

**What would reopen it is evidence from a Windows machine**, not a preference: a mid-game allocation failure, or a stall traceable to memory, that a pressure release would have avoided. A packaging build would also change the survey's second half, since the WinRT app-memory events become meaningful for an app with package identity.

**Of the three desktop triggers, one stands on Windows, one is decided above, and one is owed.** Memory pressure is the clause above. **Termination stands only for the termination the app is told about**: closing the window performs the core's own shutdown once, which cancels every search, joins the engine thread and closes the store in one call, exactly as the ordering below requires. A **logoff or shutdown** does not come through that path — Windows announces it with `WM_QUERYENDSESSION` and `WM_ENDSESSION` and then kills what has not left — and neither does a **system sleep**, which Windows announces with `WM_POWERBROADCAST` and `PBT_APMSUSPEND`. **Both are owed rather than decided**, and they are one item rather than two: each is a precisely defined Windows message where the pressure signal was not, each needs a window handle and a message hook — the part of the frontend no headless run can exercise — and each costs exactly what the bullets above bound, because the game on disk is whole at every instant and an in-flight search is worth at most five seconds. Recorded here so that nothing reads this section as claiming the Windows frontend implements the whole rule.

On that signal, any running search is cancelled **and the transposition table released**, returning the engine to the uninitialized state. The reason is the Hash budget itself: it is bounded only by 4 GiB and the device's memory, so a suspended app can be holding gigabytes it is not using — precisely the profile the operating system reclaims first. Losing the app costs the user their place; losing an in-flight search costs at most five seconds, and the position it was thinking about is committed and unchanged.

- The committed game is never affected. The active game is already persisted, and a search result is never what commits a move.
- A result arriving from a search cancelled this way is discarded because **its request is no longer the current one** — the cancellation itself is what rejects it. The position-revision check does not cover this case: no mutation occurred, so the revision is unchanged and a late result would match it.
- If the signal arrives during an in-flight game creation, the attempt is invalidated exactly as leaving the pre-start state invalidates it: anything prepared is released, no game is created, and a late completion cannot commit.
- **Re-preparation happens when a search is next owed, not on return to the foreground.** A search is owed exactly when the resumed state is an active human-versus-AI game whose committed status reports the AI to move and a search expected. Replay, Free Play, a confirmed result, a game awaiting the user's move, and having no active game all require no engine, so none of them re-prepares one.
- Re-preparation obtains a fresh memory probe and can fail, most plausibly because memory conditions changed while the app was away. It reports the same insufficient-memory error as any other preparation. The game remains active, saved, and resumable, with the AI unable to move until preparation succeeds. What the user sees in that mid-game case is settled in [interaction-design.md](interaction-design.md) § Insufficient memory for AI play: the same title, a message that adds the saved-game guarantee, and **稍后** / **重试** in place of **取消** / **重试**.
- Every one of these paths cancels and releases whole. None shrinks Hash in place: a partially reduced transposition table is not a state this contract defines.
- Teardown is deterministic and does not depend on process termination: cancellation, then engine release, then the store's outstanding work. It must not block the thread delivering the platform's lifecycle event.
- At termination the frontend performs that order **once**, through the core's own shutdown — which cancels every search, joins the engine thread and closes the store in one call — rather than through a second, asynchronous release racing it. Two teardowns at quit buy nothing and delay the exit.

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
- The custom variant differs from its parent in exactly four settings, and this list is complete: `nMoveRule = 0` disabling the inherited move-count rule, `nFoldRule = 3`, `chasingRule = axf`, and `promotedSoldiersChaseable = false`. It preserves illegal-perpetual-check adjudication, which the parent already sets. The last of the four is not optional and is easy to omit: Mini Xiangqi soldiers move sideways from the start, so the engine treats every one of them as internally promoted and, at the property's default, as a chase target — a variant built without it returns a loss on the approved fixture `mx-chs-003` where the rules require a draw.
- The target behavior follows the selected PyChess Mini Xiangqi rules: neutral threefold repetition is a draw; a unilateral perpetual checker or chaser loses; a mutual same-class violation draws; checking takes precedence over chasing; and kings and soldiers are excluded as chase targets.
- Mini Xiangqi soldiers move sideways from the start while remaining excluded as chase targets.
- AXF configuration alone does not satisfy the approved soldier-exclusion fixture `fixtures/rules/mx-chs-003`: the engine classifies every sideways-capable Mini Xiangqi soldier as a chase target, so the target variant requires a focused source change in the Fairy-Stockfish fork. The Fairy-Stockfish repository owns that change and its fork-specific tests; this repository records the required behavior and the pinned artifact it consumes.
- Built-in `minixiangqi`, which has no chasing rule, does not satisfy the unilateral-chase fixtures `mx-chs-001` and `mx-chs-004`. That is the accepted baseline limitation motivating the AXF-derived target, not a defect to fix.

### Accepted variant packaging

- The target variant's identifier is **`minixiangqiaxf`**, defined in a bundled configuration file named `minixiangqi-variants.ini`. The name is distinct from built-in `minixiangqi` so that the two can be selected unambiguously in the same build, which the fixture harness requires in order to run a variant and its control side by side.
- The variant keeps built-in `minixiangqi`'s board geometry and piece set exactly; it differs only in adjudication. That is what keeps the pinned network structurally valid for it.
- **The bundled network's filename must begin with the variant identifier.** `EvalFile` is not simply a path the engine opens: the engine restricts NNUE to the matching variant by requiring the file's basename to start with the variant name (or with a `nnueAlias` that an `.ini` variant cannot set). A basename that does not match does not produce an error, and does not change the `Use NNUE` option either — it clears the engine's *internal* NNUE flag, so the option still reads true while the engine plays on classical evaluation. The pinned network is therefore named **`minixiangqiaxf-ad52b8658c9e.nnue`**, and is committed under that name, so staging is a copy rather than a rename and no build has a chance to get it wrong.
- Because that failure is silent, the core's preflight must assert the engine's **effective NNUE state** after configuration, not merely that the file exists and parses. A preflight that checks only file presence would pass in exactly the case this rule exists to prevent.
- The fork's patch boundary is the set of focused source changes this contract and [xiangqi-rules.md](xiangqi-rules.md) require, each recorded in the pinned manifest by revision. Their implementation, tests, and upstream maintenance belong to the fork repository.

Engine search may evaluate a neutral threefold repetition as draw-valued, but that evaluation does not automatically commit the app-visible game or History record. The rules facade must expose claim eligibility to the accepted product flow.

The core's rules facade is the authoritative runtime rules component, as accepted in [architecture.md](architecture.md) and [xiangqi-rules.md](xiangqi-rules.md). Engine search and the rules facade must be validated against the same approved history fixtures.

## Packaging and NNUE

### Accepted NNUE handling policy

*(Rewritten 2026-07-31, with the project's own network. What stood here was written for a network of unestablished origin and made establishing it — or replacing it — a mandatory gate for any distribution beyond internal testing. The network was replaced; the gate is passed rather than waived, and this says what the passed state is. The two staging rules below are unchanged, because they never guarded licensing: they guard packaging mistakes, which a network of any provenance can suffer.)*

- **The network is this project's own, and it is in this repository**, at `core/assets/`, beside the variant configuration it is loaded with. Origin and redistribution licence are settled by ownership: the weights were trained by this project, so they are ours to publish, and they are covered by this project's own licence rather than by somebody else's terms.
- **The provenance is a public pipeline rather than a claim.** `ppppvz/minixiangqi-nnue` at the revision `pinned-inputs.json` records generates its own training data with the shipping fork revision and the pinned variant configuration — the game this app actually plays, adjudication included — and generation 0 was trained from the engine's own classical evaluation, with no other network as a teacher, a seed, or an input at any stage. `pinned-inputs.json`'s `network.provenance` carries the repository, the revision, and the acceptance summary; the pipeline's own `docs/results.md` carries the evidence.
- **It was accepted against measured gates**, recorded in issue #95: it beats the classical evaluation at each of the app's three thinking times — +417 / +335 / +338 Elo at 1000 / 3000 / 5000 ms, SPRT accepted at all three — and plays more sensibly by the same referee over the same games, 2.00 blunders per 100 moves against classical's 2.58.
- **It is materially weaker than the community-trained network this project previously bundled**: about 300 Elo below it at the app's settings, and far above having no network at all. That trade was made deliberately and by the owner. What the levels promise is a single strongest configuration differing only in thinking time, which is unchanged; what changes is that the opponent behind it is one whose origin can be stated.
- The bundled network is pinned by exact byte length and SHA-256 in a machine-readable manifest, and every consumer verifies both before staging a byte: `core/CMakeLists.txt` for the core's own asset directory and both frontends' staging, `apple/build-core-xcframework.sh` for the app's resources, `windows/package-zip.ps1` for the distribution zip. A mismatch fails the build rather than shipping unverified bytes. That the file is version-controlled does not retire the check — it is what catches a build pointed at other bytes, and a damaged four-megabyte binary is invisible without it.
- **`MXQ_NNUE_SOURCE` remains, as an override rather than as the way a build finds the network.** Its default is the committed file. Pointing it elsewhere is how a candidate network is tried before it is committed; replacing the network for good is the bytes and the manifest, and nothing else.
- The selected network is 4,333,479 bytes, SHA-256 `ad52b8658c9ebf968bd6fd2d319541bc2f73dca3d790e2b9ac22eaa31c2e8c0a`, committed and bundled as `minixiangqiaxf-ad52b8658c9e.nnue` for the reason given under variant packaging.

### Accepted network failure policy

The network is bundled and hash-verified at build time on every build that bundles it, so a verification failure at runtime means a damaged installation rather than a configuration the user chose. In that case **the AI does not start**, and the frontend reports it through the accepted engine-unavailable path.

There is no fallback to the engine's classical evaluation. The accepted levels are defined as sharing one strongest configuration and differing only in thinking time; substituting a different evaluation would silently make the opponent a different opponent, which the user would have no way to detect. Free Play, History, replay, import, and export are unaffected, and reinstalling restores the AI.

The core preflights the network against the engine's observable load state before any search, so this is detected during preparation and the engine's own fatal verification path is never reached.

### Every build bundles the network, including the Windows zip

*(Restored 2026-07-31, with the project's own network. Between the CI-built zip and the network swap, this section recorded an accepted exception: the Windows distribution deliberately omitted the network, because a CI artifact on a public repository is a distribution beyond internal testing and the bytes were not ours to publish. The bytes are now ours, so the exception has nothing left to except and is deleted rather than kept as history.)*

- **The Windows zip carries the network**, in `assets/` beside the variant configuration, and is the complete application. There is no second, more complete package: the artifact CI publishes is the whole thing.
- **The clauses above therefore cover every distribution again.** An absent or mismatched network is damage in all of them, reinstalling is what fixes it, and no distribution has a case in which absence is expected.
- **The frontend's messages, written for damage, are right again.** The Windows-zip case is what made them awkward — they described damage to somebody whose network was missing on purpose — and it is gone. The owed string pair recorded here is withdrawn rather than deferred: there is no case left for it to describe.

### Accepted pinned-input manifest

One machine-readable manifest, `pinned-inputs.json`, at the root of this repository, is the single source of truth for every input a reproducible build consumes:

- the fork's repository, revision, and the ordered list of focused patches applied at that revision;
- the build flags and defines the app build uses for each supported platform;
- the bundled variant configuration's filename and SHA-256;
- the bundled network's filename, in-repository path, exact byte length, SHA-256, and provenance — the pipeline repository and revision that produced it, and the acceptance summary that admitted it;
- the vendored SQLite amalgamation's version and SHA-256.

The build verifies every hash before packaging and fails on a mismatch rather than shipping unverified bytes. The fork repository owns how its patches are implemented and how its own artifacts are built; this manifest records which revision and which inputs the app consumes, so that an app build is reproducible without reading the fork's history.

### Accepted library build requirement

The core links the pinned revision as a static library on every supported platform, and never as an executable or a Python module — which is what the fork's Makefile otherwise produces, and neither of which the core can consume.

**How that library is produced is a build decision, not a contract requirement, and it is not the fork's target.** The core compiles the vendored source snapshot through its own CMake, on macOS and on Windows alike; nothing in either build consumes an artifact the fork built. The reason is the same on both platforms and predates either: the app needs several architectures out of one build system, and the fork's Makefile is a second one — `make lib` at the pinned revision takes an `ARCH` and produces one. So the fork's static-library target exists, as `pinned-inputs.json` records, and satisfies the fork's side of this contract; whether the core ever switches to consuming its artifact is a separate decision, and `core/third_party/fairy-stockfish/README.md` records what would change. This paragraph replaces an earlier requirement that the fork's artifact "is what the core links against", which no build has ever done and which the first Windows build made visibly dead rather than merely unexercised.

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

- Confirm each platform's memory probe against the accepted budget boundaries on real hardware; the APIs are fixed above, their measured behavior is not. On iOS and iPadOS the probe is exercised by the unit suite on a Simulator, which says it answers plausibly rather than that it answers the right number on an 8 GB device; the device measurement is still owed.
- Wire the two Windows messages the backgrounding clause above records as owed: system sleep (`WM_POWERBROADCAST` / `PBT_APMSUSPEND`) and the end of a session (`WM_QUERYENDSESSION` / `WM_ENDSESSION`, the logoff and shutdown the window's own close never sees). Both are precisely defined where the pressure signal was not, and both need a window handle and a message hook, so they belong with work that has a window rather than with the headless core.
- Revisit Windows mid-game memory pressure if a Windows machine produces the evidence the clause above names — a mid-game allocation failure or a memory-traceable stall a pressure release would have avoided. The signal survey, and why acting on the one Windows offers would be worse than not acting, are recorded above rather than left to be redone.
- Revisit iOS and iPadOS memory pressure after the MVP, if the shared path proves not to be enough. It is what ships, by the owner's deferral above; what would reopen it is evidence from a device — a warning followed by a re-ask that re-allocates, and then a jetsam kill a smaller retry trigger would have avoided — and not a preference.
- Fix the manifest's concrete field names and schema version when the first build consumes it.
- Decide whether a diagnostics surface later exposes bounded hash-utilization and nodes-per-second values, which are recorded as diagnostics rather than strength today.
