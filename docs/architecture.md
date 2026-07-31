# Architecture

This document is for engineers and reviewers working on Mini Xiangqi. It defines the system's stable boundaries: the shared core, the native frontends, dependency direction, state ownership, concurrency, and error propagation. It does not define Xiangqi rules, detailed UI/UX, persistence schemas, engine search policy, implementation progress, or work tracking.

> **Status: Accepted direction and boundaries.** The shared-core-plus-native-frontends structure, the core's responsibilities, the C boundary, the dependency direction, the error-handling contract, and the build and CI policy below are accepted. The concrete C surface — handles, signatures, error taxonomy, and threading — is the accepted contract in [core-interface.md](core-interface.md). The repository layout, the relocation of the Xcode project, the placement of Settings preferences, and the core test-runner decision below are also accepted. Items under **Need to discuss** are non-normative.

## Goals and constraints

- One product runs on iOS, iPadOS, macOS, and Windows with identical game behavior and persisted meaning.
- Everything correctness-critical is implemented exactly once, in a shared core, and validated by one test suite.
- Each platform's frontend is native — SwiftUI on Apple platforms, WinUI 3 on Windows — and owns only presentation and platform services.
- All gameplay works offline. Nothing may depend on networking or cloud services.
- The application has one main window per platform.

## System structure

### Shared core

The core is a C++ library exposing a stable C interface. Fairy-Stockfish is already C++ and must build on every platform, so C++ is the one language the project cannot avoid; the core concentrates the remaining correctness-critical logic beside it rather than duplicating that logic per platform. The core embeds the pinned `ppppvz/Fairy-Stockfish` fork as an in-process library and owns:

- **Rules facade** — legal-move generation, move application, check state, and authoritative result adjudication, including repetition, claimable draws, perpetual check, and perpetual chase. The facade is deterministic over position and history. It is validated by the approved conformance fixtures in [xiangqi-rules.md](xiangqi-rules.md); agreement with unvalidated engine behavior is never its authority. The core exposes it two ways: inside a **game session**, which composes it with the game's frozen configuration — mode, resolved human side, AI level and thinking time — because undo, resign, and search eligibility are mode-aware; and session-free over an initial position plus complete move history, which is the fixture-harness and import-validation surface.
- **Search facade** — engine sessions that receive an app-approved position and history and return a proposed move or typed failure, with the option profiles, cancellation, and lifecycle defined in [engine-integration.md](engine-integration.md). Search output never mutates game state, and adjudication never derives from search scores.
- **Game archive codec** — encoding, decoding, and validation of the versioned portable game format defined in [game-data.md](game-data.md).
- **Library store** — the SQLite-backed game library: the single active game, autosave, History records, pin metadata, import, export, deletion, and their transactional invariants.

The rules facade and search facade are two contracts over one pinned engine implementation. Sharing the implementation is an efficiency choice; the fixtures remain the independent authority, and when an approved fixture exposes an engine mismatch, the fork receives a focused change rather than the contract bending to the engine.

### Native frontends

Each frontend renders state, collects user intentions, and calls core operations. Frontends own:

- presentation, navigation, animation, sound, and haptics;
- localization resources and accessibility integration;
- platform services: storage location, file pickers, share/export surfaces, memory probes, and lifecycle events;
- transient UI state such as selection, pre-start drafts, and confirmation flows;
- the persistent Settings preferences, held in each platform's own preference system as fixed in [game-data.md](game-data.md). The core never reads one: the two that affect a game are passed as arguments to game creation, where they are frozen into the game.

Frontends must not reimplement rules, result classification, archive parsing, or library invariants, and must not reach around the core to its storage or the engine.

## Dependency direction

Dependencies point inward:

1. Frontends depend only on the core's C interface, through a thin idiomatic binding per platform (Swift; C# P/Invoke).
2. The core depends on Fairy-Stockfish and SQLite as internal, replaceable components; neither is visible through the C interface.
3. The core never depends on UI frameworks, platform services, or frontend code. Platform-specific values it needs — storage paths, memory budgets, processor counts — are passed in by the frontend.

## Concurrency and lifecycle

- Search runs off the frontend's main/UI thread. Every search is identified by the game and position revision that requested it.
- Undo, game completion, active-game replacement, leaving the relevant state, and the platform's suspension signal cancel outstanding work. Cancellation is cooperative. A result is rejected whenever its revision is stale, and independently whenever its request has been superseded: most cancellations follow a mutation and are caught by staleness, but a suspension cancels without mutating anything, so the revision still matches and the superseded request is the only thing that rejects it. Neither check alone covers both.
- Core callbacks deliver results to the frontend, which re-enters its main actor or dispatcher before touching UI state. Callbacks never mutate frontend state directly.
- The C boundary documents, per function, which thread may call it and which thread delivers callbacks. The core is responsible for its own internal synchronization.
- The frontend can deterministically shut the core down — engine, store, and outstanding work — without relying on process termination.

## Error handling

- Expected failures cross the C boundary as typed error codes with retrievable detail, never as crashes, `exit()`, or silently wrong results.
- Invalid imports, persistence failures, unavailable engine resources, and engine failures must not terminate the app or partially replace a committed game. The last committed state always survives.
- Frontends translate typed errors into the user-facing presentation defined in [interaction-design.md](interaction-design.md), whose strings are of record in [copy.md](copy.md), and retain diagnostic detail without recording private game data unnecessarily.

## Repository layout and build

The target layout is one repository:

```text
MiniXiangqi/
├── core/       # shared C++ core, its tests, and pinned third-party inputs
├── apple/      # Xcode project and SwiftUI frontend
├── windows/    # WinUI 3 frontend
├── fixtures/   # approved rules conformance fixtures
├── .github/    # the CI workflows and their scripts
└── docs/
```

`fixtures/` stays at the root rather than under `core/`: it is the independent authority the core is validated against, not an implementation detail of the core it validates.

- The Apple frontend's Xcode project sits under `apple/`. It was relocated there while it was still the generated scaffold. Every reference inside the project is relative to the project directory, so moving the project and its sources together changed nothing about the build.
- Core tests must run on every development platform without a frontend, and they standardize on **one shared C++ test runner** rather than per-platform harnesses. The approved rules fixtures are the project's independent authority, so they must be executed by one harness producing identical results everywhere; two harnesses would make a discrepancy between them possible. Platform binding tests — the Swift and C# layers over the C interface — stay in each platform's native framework, because what they test is the binding rather than the core.
- Builds ran on developer machines alone while the project was Apple-only, since CI setup would otherwise have blocked the first work and no Windows machine was reachable from it. Both halves of that have changed: a Windows development machine now builds and runs the core suites, and GitHub Actions CI covers a macOS runner and **two** Windows runners, `x64` and `ARM64`, in `.github/workflows/core-suites.yml`, so no platform is reproducible only on one machine and no architecture is promised without having been run. Developer-machine runs remain the evidence a change is validated by; CI is the second place each platform builds. `ARM64` is CI's alone — the owner's ARM64 machine runs the product rather than developing it — and the workflow is therefore the only place that architecture is ever compiled.
- CI must not receive undocumented inputs: pinned revisions and asset hashes come from the repository's manifests. It remains a convenience rather than a merge gate; what it guarantees is that every platform is buildable somewhere other than one developer's machine. **The Windows distribution is the one thing CI does not merely reproduce but produces**: the zip internal testers are given is built by `.github/workflows/windows-frontend.yml`, per architecture, and exists nowhere else. That does not make CI a gate — a red run still blocks nothing — but it does mean an artifact rather than a log is now among its outputs, and what may travel in one is a decision rather than a default. The rule is the next bullet's.
- **A public repository's CI artifacts are public.** Any logged-in GitHub account can download them, so an artifact is a distribution channel and is governed as one. The NNUE network is therefore excluded from the distribution zip and named in it instead, with the byte length and SHA-256 the manifest already carries; the person who has the bytes places them after unpacking. Everything else in the zip is either this repository's own or a redistributable the attribution note beside it names.
- The NNUE network is the one build input CI cannot take from this repository, because [engine-integration.md](engine-integration.md) keeps its bytes out of version control in any form. It comes instead from `ppppvz/minixiangqi-assets`, a private repository holding that one file, cloned with a read-only deploy key held as an Actions secret; the build then verifies it against the manifest's byte length and SHA-256 before staging it. Naming that repository here and in `.github/scripts/fetch-network.sh` is what keeps the rule above true — the key is a secret, the address is not, and an input CI receives has to be readable in the repository that receives it. The script also accepts a download location in a second secret, as the generic alternative for bytes kept elsewhere. Where neither is configured, the one suite that needs a network does not run and the run says so by name; every other suite still does, with the engine compiled and the rules facade answering.

## Need to discuss

> The following questions are non-normative and are not implementation requirements.

- Whether the Windows distribution should become an MSIX package. The zip answers the MVP, and MSIX brings an installer, an update story, package identity — which would make the WinRT app-memory events this document's engine counterpart discusses meaningful — and a signing certificate to obtain and keep. It is worth reconsidering after the zip has been in internal testers' hands, not before.
- Whether the core's flag sets should move into `pinned-inputs.json`'s `engine_flags` and `sqlite_defines` for Windows, as they have not on any platform. The packaging build now exists and pinned the frontend's half of the toolchain, which is what the entry that used to stand here waited for; it did not establish the core's compile flags, because it publishes a frontend over a prebuilt core rather than choosing how the core is compiled. Establishing those means deciding that the core build *is* part of the packaging build, which is a different question from the one just answered.
