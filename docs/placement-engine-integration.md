# Placement Engine Integration

This document defines how the shared core packages, calls, constrains, and validates the embedded Rapfi engine — the engine the placement games are played on — and the app-visible policies built on it. It does not define Rapfi internals, fork maintenance, source-level patch design, or upstream synchronization; those belong in the Rapfi fork repository. Mini Xiangqi's and Xiangqi's engine is [engine-integration.md](engine-integration.md)'s subject, and the two documents are counterparts: what the two engines share is stated once, there, and bound here by reference.

> **Status: binding.** The concrete search-facade C surface is in [core-interface.md](core-interface.md), which is one surface over every engine the core embeds and over the ones that search alike.

## Scope and ownership

- The shared core owns the second search facade, the packaged engine and its networks, the search profile, lifecycle integration, cancellation, and validation, as placed by [architecture.md](architecture.md). Frontends own the user-facing failure presentation.
- The `chentianren0/rapfi` fork owns any Rapfi source changes, fork-specific tests, build implementation, and upstream maintenance.
- The `dhbloo/rapfi` repository and the `dhbloo/rapfi-networks` weights repository are reference-only unless the user separately authorizes a contribution.
- Engine source revision, patches, build inputs, networks, and hashes must be pinned reproducibly.
- **The games this engine plays are `gomoku-15` and `renju`, and the set is closed.** Both are 15×15, and the size is not a parameter: each pinned network declares in its own header the board sizes it covers, and the renju pair covers 15 alone.
- **This document owns what the placement games' `rules_version` means.** Their accepted interpretation is the pinned engine's own, so what would change it is a deliberate change to that engine altering a legal move or a user-visible result — never a revision bump that alters neither, never search configuration, and never prose. The recorded value is `1`, as [game-data.md](game-data.md) records it for every game the app carries.

## Search facade boundary

Which engine plays a game is not visible through the C interface, and neither is that there is more than one; that boundary and the facade's obligations are [core-interface.md](core-interface.md)'s and [engine-integration.md](engine-integration.md)'s, and they bind here unchanged. What this engine adds:

- **One engine instance per process, and both games serialise through one bridge.** The engine's search state, transposition table, configuration and evaluator are process-global, so two instances are not expressible. Preparation and release are the only things that change that configuration, both run on the facade's engine thread with no search outstanding, and both take one mutex, so nothing observes the engine mid-reconfiguration. A search changes the engine's own search state and deliberately holds no mutex while it does.
- **A rules switch is a reconfiguration and takes the reconfiguration's exclusion.** The engine is brought up again for the new rule and the transposition table is flushed whole, because an entry keyed under one rule's tables means something else under the other's.
- **A short table is the same answer as no table.** The engine's own halving degradation is refused: the memory policy computes a budget from a fresh probe and refuses below its minimum rather than playing with less.
- **The rules side is an adapter, and the pinned engine is these games' rules authority.** Every rules answer is the engine's own — a forbidden point from its search-independent query, a completed five from the per-rule pattern the board already maintains. Nothing above the bridge re-derives a rule, and this project holds no conformance corpus over these games: the corpus the movement games carry exists because this project owns their rules, and it does not own these. What stands in its place is an adapter test set proving the wiring, and nothing more.
- **A rules answer needs no prepared engine.** The tables a rules query reads are constants of the rule, so a game is played, undone and replayed whether or not an engine stands.
- **These games begin from the empty board and from no other position.** A board with stones on it is a position reached by play rather than one to begin from, and these games' rules define no setup-legality predicate, so the frozen start is the whole of what they begin from — which is the start policy [game-data.md](game-data.md) states for a game that defines none.

### Failure containment

- The engine reports failure by throwing, and [architecture.md](architecture.md) forbids an exception or a process exit crossing the core's boundary, so every entry point contains one and returns a typed failure instead.
- **One bound on that is accepted rather than claimed away.** The engine's worker threads carry no handler of their own and a starting search dispatches work onto them, so an allocation failure there terminates the process, uncatchable by construction. That is the same practical posture as the first engine, which is compiled without exceptions at all and whose allocation failure terminates too. A guard inside the fork's thread loop is a possible focused change if evidence asks for one.
- **The unmodified engine** terminates the process when transposition-table allocation fails, and on Windows when freeing large-page memory fails — a path both the transposition table and the loaded NNUE weights are released through. Recoverable allocation is therefore a required focused change in the fork and is carried at the pinned revision; recoverable release is owed, below.
- **The engine writes its messages and its errors to standard output, and a library must not write to a host application's.** That stream is redirected for the length of any call that can produce one, and the engine's message mode is set to none besides.

### The fork change set

The pinned fork carries only focused changes this contract requires, each recorded in the manifest:

- **Recoverable Hash allocation**, replacing the process exit on transposition-table allocation failure with a failure the embedding observes, and leaving the engine's behaviour unchanged when the allocation succeeds.
- **A static library target.** It is the one change in this list the core does not consume: the core compiles the vendored snapshot itself, on every platform that carries this engine.

One change is owed and deliberately not yet carried:

- **Recoverable large-page release**, the second half of the same hazard. The engine's Windows large-page free path exits the process when the release fails, and it is reached by the transposition table, through every resize and through its destructor, and by the NNUE weights, whose large-page deleter frees them when an evaluator is dropped. The branch is Windows-only and no build this repository produces compiles this engine for Windows, so it is unreachable here; the manifest records it as pending with its trigger. **The trigger is exact: any Windows build of this engine lands the fork change first.**

No applied change touches rules behaviour, so none owes a rules fixture. A fork change that ever does touch rules behaviour lands together with the test that pins it.

## Vendoring

- The pinned revision reaches the core as a **copied source snapshot**, compiled by a core-owned build description, and never as an artifact the fork built.
- **Nothing in the snapshot is edited here.** Every engine source change belongs to the fork and arrives as a new snapshot at a new pinned revision, which is what keeps the manifest's ordered patch list a description of the bytes the core compiles.
- The snapshot excludes the engine's own `main`, its stdin protocol, and the offline command-module implementations — database maintenance, training-data preparation, opening generation, self-play and tuning: the core is a library and drives the engine through its C++ API, so a second entry point and a training toolchain have no business in it. The command directory's remaining sources compile, none of them reached by a search. The excluded set and the recipe that reproduces the snapshot are recorded beside it.
- **The engine's configuration is the one compiled into it**, handed to it from memory. No configuration file is searched for and none is read: the engine's own resolution order reaches the working directory and a directory derived from the executable path, and inside an app bundle either would let a file left there replace the engine's configuration, weights included.
- **Every asset path the engine is given is absolute and already verified**, so no working directory and no executable location can substitute an asset behind the app's back.
- Third-party notices and corresponding-source availability for the GPLv3 engine and for every library vendored inside it must be prepared before any build containing it is distributed. Where a vendored library ships no licence text of its own, the notices carry that text from its own repository.

## Search lifecycle

The lifecycle contract is one for both engines and is [engine-integration.md](engine-integration.md) § Search lifecycle's: where search runs, what cancels it, the rejection of a stale or superseded result, backgrounding and teardown and their ordering, the preparation ordering at game creation, and the hint's own rules — its thinking time, its lazy preparation in Free Play, its inertness, and the refusal while a search is outstanding. All of it binds here unchanged. What is this engine's own:

- **The accepted levels are the shared ones**, defined in [engine-integration.md](engine-integration.md) § AI difficulty profiles and differing only in maximum thinking time. On this engine the one strongest configuration they share is alpha-beta search, the engine's strength knob at its maximum, one principal variation, no node or depth limit, and no pondering.
- **A level's thinking time is a turn time, and there is no match clock.** The engine keeps its own small reserve inside that time and returns before it elapses.
- **The trivial-opening probe stays on**, so the engine's prepared openings answer where it has one. It is not what makes the first move instant: a board with no stone on it offers a search no candidate, and the centre point comes back whatever the probe is set to. Either way an instant reply is inside a level's maximum thinking time, which is the whole of what a level promises.
- **A hint is an ordinary search under the prepared game's rules.** Its board presentation is the placement grammar's own, fixed in [interaction-design.md](interaction-design.md).

## Memory

**There is one memory policy in this core, and this engine is a second consumer of it rather than a second copy.** The adaptive arithmetic, the 4 GiB cap, the 256 MiB minimum, the fresh probe at every preparation, and the insufficient-memory presentation are [engine-integration.md](engine-integration.md) § AI difficulty profiles', and they bind here unchanged. These consequences are this facade's:

- **Preparing either engine releases the other first.** The plan is computed once from one probe and sizes one transposition table; leaving the other engine holding its own would put two tables on a device the plan sized for one. Releasing before configuring is also what makes a failed preparation leave nothing prepared.
- **The thread count and the table size are the plan's**, and a preparation that cannot meet them reports the accepted engine failure rather than settling for less.

## Packaging and networks

**One weight set per game, all in this repository**, at `core/assets/`, committed and version-controlled. There is no fetch and no separate location: a build reads them from the checkout.

Each file is pinned by exact byte length and SHA-256 in the manifest, keyed by the `rules_id` it is for, and **nothing stages or loads a byte it has not verified against that game's own pins** — the core's asset staging, the core's engine bridge before the engine is given a path, the Apple packaging script, and the Apple staleness check. That the files are version-controlled does not retire the check: it is what catches a build pointed at other bytes, and damaged weights are invisible without it.

- **`gomoku-15` takes one file, which serves both sides.**
- **`renju` takes one file per side.** Renju is not symmetric — its forbidden-move rules apply to Black alone — so the two sides are trained and stored apart, and the pair moves together.
- **The weights are not this project's own and are not retrained here.** They are CC0, dedicated by their trainers; they impose no notice or source obligation of their own, and each manifest entry records where the dedication is stated and which revision the bytes were taken from.
- **No measured acceptance gate applies to them, and none is claimed.** The accepted levels describe one configuration and one set of thinking times; a strength claim about these networks requires its own measurement.
- **A file's name carries no meaning to this engine**, which reads the rule and the board size out of the file's own header. A file under a name no pin covers is therefore a file this build cannot verify, and an unverifiable file is refused rather than guessed at.

### The preflight

These gates run at preparation, in this order, and each is fatal:

1. **Selection** — the files this game's pins name, in the asset directory the frontend supplied. A missing one is a damaged installation and is refused here.
2. **Bytes** — every selected file's length and SHA-256 against its own pins, before the engine is given a path. A weight file carries a structural header the engine checks and no content hash at all, so the manifest pins are the whole of the integrity check.
3. **The effective evaluator** — after the whole configuration and never instead of it. A weight set that does not cover the rule or the board size raises an error the engine's own evaluator maker swallows, leaving the engine playing on classical evaluation with nothing reported anywhere. This gate asks the engine which evaluator it actually holds for this rule at this size and refuses when the answer is none. **Effective NNUE off is fatal at preparation**, never downgraded to a warning and never allowed to reach a search.

On any refusal the engine is unwound whole to the released posture: a partial configuration is not a state this contract defines.

**There is no fallback to classical evaluation.** The accepted levels are defined as sharing one strongest configuration and differing only in thinking time; substituting a different evaluation would silently make the opponent a different opponent, which the user would have no way to detect. Free Play, History, replay, import, and export are unaffected, and reinstalling restores the AI.

### Bundling in every distribution

- **A distribution carries the weights for every game it can play, and carries no other.** A weight set it cannot use is dead weight it must still license and hash-verify, and a game it can select without one is a game it would play on classical evaluation.
- **A build that does not compile this engine carries no placement game.** The games' vocabulary is closed in [game-data.md](game-data.md), and a document naming a game the build cannot play meets the same refusal any other unknown `rules_id` meets.
- An absent or mismatched weight file is damage in every distribution, reinstalling is what fixes it, and no distribution has a case in which absence is expected.

### The pinned-input manifest

`pinned-inputs.json` is the single source of truth for this engine's inputs as it is for every other engine's, and records them separately from each — separate engines have separate revisions, separate patch lists, and separate networks where they have networks at all, and nothing about one describes another:

- the fork's repository, the pinned revision, the upstream base it derives from, and the ordered list of focused patches applied at that revision;
- what this contract asks of the fork and the pinned revision does not carry, each with the reason it is deferred and the trigger that ends the deferral;
- the vendored snapshot's method, its paths, its exclusions, and its per-file hashes;
- for each game, that game's weight files: each file's role, filename, in-repository path, exact byte length, SHA-256, licence, and provenance.

The build verifies every hash before packaging and fails on a mismatch rather than shipping unverified bytes.

## Readiness

**Readiness is the core's own answer compared, never a frontend's reconstruction.** The rule, and why no caller may compose an identifier of its own, are [core-interface.md](core-interface.md)'s.

What is this engine's own is what its identifier carries: this engine's pinned revision, the prepared game's rule, and that game's network. So a move produced here is attributed to this engine's build and to no other's, in a saved diagnostic record as much as in a readiness comparison.
