# Architecture

This document defines the system's stable boundaries: the shared core, the native frontends, dependency direction, state ownership, concurrency, error propagation, and the repository's layout and build policy. It does not define Xiangqi rules, UI and interaction behavior, persistence schemas, or engine search policy.

> **Status: binding.** The concrete C surface — handles, signatures, error taxonomy, and threading — is in [core-interface.md](core-interface.md); this document fixes the boundaries that surface sits on.

## Goals and constraints

- One product runs on iOS, iPadOS, macOS, and Windows with identical game behavior and persisted meaning.
- Everything correctness-critical is implemented exactly once, in a shared core, and validated by one test suite.
- Each platform's frontend is native — SwiftUI on Apple platforms, WinUI 3 on Windows — and owns only presentation and platform services.
- All gameplay works offline. Nothing may depend on networking or cloud services.
- The application has one main window per platform.

## Shared core

The core is a C++ library exposing a stable C interface, embedding the pinned `ppppvz/Fairy-Stockfish` fork as an in-process library. C++ is not a choice that can be revisited: Fairy-Stockfish is C++ and must build on every platform, so the core concentrates the remaining correctness-critical logic beside it rather than duplicating that logic per platform. The core owns:

- **Rules facade** — legal-move generation, move application, check state, and authoritative result adjudication, including repetition, claimable draws, perpetual check, and perpetual chase. The facade is deterministic over position and history. It is validated by the approved conformance fixtures required by [xiangqi-rules.md](xiangqi-rules.md); agreement with unvalidated engine behavior is never its authority. The core exposes it two ways: inside a **game session**, which composes it with the game's frozen configuration — mode, resolved human side, AI level and thinking time — because undo, resign, and search eligibility are mode-aware; and session-free over an initial position plus complete move history, which is the fixture-harness and import-validation surface.
- **Search facade** — engine sessions that receive an app-approved position and history and return a proposed move or typed failure, with the option profiles, cancellation, and lifecycle defined in [engine-integration.md](engine-integration.md). Search output never mutates game state, and adjudication never derives from search scores.
- **Game archive codec** — encoding, decoding, and validation of the versioned portable game format defined in [game-data.md](game-data.md).
- **Library store** — the SQLite-backed game library: the single active game, autosave, History records, pin metadata, import, export, deletion, and their transactional invariants.

The rules facade and the search facade are two contracts over one pinned engine implementation. Sharing the implementation is an efficiency choice; the fixtures remain the independent authority, and when an approved fixture exposes an engine mismatch, the fork receives a focused change rather than the contract bending to the engine.

## Native frontends

Each frontend renders state, collects user intentions, and calls core operations. Frontends own:

- presentation, navigation, animation, sound, and haptics;
- localization resources and accessibility integration;
- platform services: storage location, file pickers, share and export surfaces, memory probes, and lifecycle events;
- transient UI state such as selection, pre-start drafts, and confirmation flows;
- the persistent Settings preferences, held in each platform's own preference system as fixed in [game-data.md](game-data.md). The core never reads one: the two that affect a game are passed as arguments to game creation, where they are frozen into the game.

Frontends must not reimplement rules, result classification, archive parsing, or library invariants, and must not reach around the core to its storage or the engine.

## Dependency direction

Dependencies point inward:

1. Frontends depend only on the core's C interface, through a thin idiomatic binding per platform — Swift on Apple platforms, C# P/Invoke on Windows.
2. The core depends on Fairy-Stockfish and SQLite as internal, replaceable components; neither is visible through the C interface.
3. The core never depends on UI frameworks, platform services, or frontend code. Platform-specific values it needs — storage paths, memory budgets, processor counts — are passed in by the frontend.

## Concurrency and lifecycle

- Search runs off the frontend's main or UI thread. Every search is identified by the game and position revision that requested it.
- Undo, game completion, active-game replacement, leaving the relevant state, and the platform's suspension signal cancel outstanding work. Cancellation is cooperative.
- A result is rejected whenever its revision is stale, and independently whenever its request has been superseded. Both checks are required: most cancellations follow a mutation and are caught by staleness, but a suspension cancels without mutating anything, so the revision still matches and the superseded request is the only thing that rejects it.
- Core callbacks deliver results to the frontend, which re-enters its main actor or dispatcher before touching UI state. Callbacks never mutate frontend state directly.
- The C boundary documents, per function, which thread may call it and which thread delivers callbacks. The core is responsible for its own internal synchronization.
- The frontend can deterministically shut the core down — engine, store, and outstanding work — without relying on process termination.

## Error handling

- Expected failures cross the C boundary as typed error codes with retrievable detail, never as crashes, `exit()`, or silently wrong results.
- Invalid imports, persistence failures, unavailable engine resources, and engine failures must not terminate the app or partially replace a committed game. The last committed state always survives.
- Frontends translate typed errors into the user-facing presentation defined in [interaction-design.md](interaction-design.md), whose strings are of record in [copy.md](copy.md), and retain diagnostic detail without recording private game data unnecessarily.

## Repository layout

```text
MiniXiangqi/
├── core/       # shared C++ core, its tests, and pinned third-party inputs
├── apple/      # Xcode project and SwiftUI frontend
├── windows/    # WinUI 3 frontend
├── fixtures/   # approved conformance fixtures
├── .github/    # the CI workflows and their scripts
└── docs/
```

`fixtures/` stays at the root rather than under `core/`: it is the independent authority the core is validated against, not an implementation detail of the core it validates.

The Apple frontend's Xcode project sits under `apple/`, and every reference inside the project is relative to the project directory.

## Testing and CI policy

- Core tests run on every development platform without a frontend, through **one shared C++ test runner** rather than per-platform harnesses. The approved fixtures are the project's independent authority, so they must be executed by one harness producing identical results everywhere; two harnesses would make a discrepancy between them possible.
- Platform binding tests — the Swift and C# layers over the C interface — stay in each platform's native framework, because what they test is the binding rather than the core.
- GitHub Actions covers a macOS runner and **two** Windows runners, `x64` and `ARM64`, in `.github/workflows/core-suites.yml`. `ARM64` is compiled nowhere else.
- Developer-machine runs remain the evidence a change is validated by; CI is the second place each platform builds, and it is not a merge gate.
- CI must not receive undocumented inputs: pinned revisions and asset hashes come from the repository's manifests. Every build input CI needs is in this repository, both NNUE networks included, so **CI takes no secrets at all**, every suite runs on every runner, and a pull request from a fork gets the same run as a branch's.
- The Windows distributions are the one thing CI does not merely reproduce but produces: the zip anybody is given and the unsigned MSIX submitted to the Microsoft Store are both built per architecture by `.github/workflows/windows-frontend.yml` and exist nowhere else. Neither needs a secret — the zip because every input is in this repository, the package because the Store signs what it accepts.
- **A public repository's CI artifacts are public.** Any logged-in GitHub account can download them, so an artifact is a distribution channel and is governed as one. Everything in the distribution zip is either this repository's own — the app, the core, the variant configuration, the sounds, and the Mini Xiangqi network — or a redistributable the attribution note beside it names, including the GPL Xiangqi network. The Store package is the same payload under a different deployment shape and is governed by the same sentence; being unsigned, it carries no key material.
