# Architecture

This document is for engineers and reviewers working on Mini Xiangqi. It defines the system's stable boundaries: the shared core, the native frontends, dependency direction, state ownership, concurrency, and error propagation. It does not define Xiangqi rules, detailed UI/UX, persistence schemas, engine search policy, implementation progress, or work tracking.

> **Status: Accepted direction and boundaries.** The shared-core-plus-native-frontends structure, the core's responsibilities, the C boundary, the dependency direction, the error-handling contract, and the build and CI policy below are accepted. The concrete C surface — handles, signatures, error taxonomy, and threading — is the accepted contract in [core-interface.md](core-interface.md). The repository restructuring steps remain draft until reviewed. Items under **Need to discuss** are non-normative.

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
- transient UI state such as selection, pre-start drafts, and confirmation flows.

Frontends must not reimplement rules, result classification, archive parsing, or library invariants, and must not reach around the core to its storage or the engine.

## Dependency direction

Dependencies point inward:

1. Frontends depend only on the core's C interface, through a thin idiomatic binding per platform (Swift; C# P/Invoke).
2. The core depends on Fairy-Stockfish and SQLite as internal, replaceable components; neither is visible through the C interface.
3. The core never depends on UI frameworks, platform services, or frontend code. Platform-specific values it needs — storage paths, memory budgets, processor counts — are passed in by the frontend.

## Concurrency and lifecycle

- Search runs off the frontend's main/UI thread. Every search is identified by the game and position revision that requested it.
- Undo, game completion, active-game replacement, leaving the relevant state, and app backgrounding cancel outstanding work. Cancellation is cooperative, and a result is rejected whenever its revision is stale — cancellation alone is not trusted.
- Core callbacks deliver results to the frontend, which re-enters its main actor or dispatcher before touching UI state. Callbacks never mutate frontend state directly.
- The C boundary documents, per function, which thread may call it and which thread delivers callbacks. The core is responsible for its own internal synchronization.
- The frontend can deterministically shut the core down — engine, store, and outstanding work — without relying on process termination.

## Error handling

- Expected failures cross the C boundary as typed error codes with retrievable detail, never as crashes, `exit()`, or silently wrong results.
- Invalid imports, persistence failures, unavailable engine resources, and engine failures must not terminate the app or partially replace a committed game. The last committed state always survives.
- Frontends translate typed errors into the user-facing copy defined in [interaction-design.md](interaction-design.md), and retain diagnostic detail without recording private game data unnecessarily.

## Repository layout and build

The target layout is one repository:

```text
MiniXiangqi/
├── core/       # shared C++ core, its tests, and pinned third-party inputs
├── apple/      # Xcode project and SwiftUI frontend
├── windows/    # WinUI 3 frontend
└── docs/
```

- Relocating the existing Xcode project under `apple/` is an implementation step subject to the protected-settings review in `AGENTS.md`; this document records only the target.
- Core tests must run on every development platform without a frontend.
- Long or large builds — engine binaries, core artifacts, multi-platform test runs — are recommended to run on GitHub Actions CI rather than only on developer machines. CI is a convenience, not a required gate, and must not receive undocumented inputs: pinned revisions and asset hashes come from the repository's manifests.

## Need to discuss

> The following questions are non-normative and are not implementation requirements.

- Windows toolchain pinning for the core and frontend, and the CI matrix that builds all platforms.
- Whether core tests standardize on one framework or per-platform runners.
