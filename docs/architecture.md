# App Architecture

This document is for engineers and reviewers working on the Mini Xiangqi app. It is owned by the Mini Xiangqi app repository and defines the intended stable boundaries inside the Xcode project. It does not define Xiangqi rules, Fairy-Stockfish fork changes, detailed UI/UX, implementation progress, or work tracking.

> **Status: Draft architecture proposal.** This records recommended boundaries for discussion, not current implementation or implementation authorization. Nothing in this document is normative until its status or an individual section is explicitly marked accepted. Items under **Need to discuss** are non-normative.

## Goals and constraints

- One shared SwiftUI app supports iOS, iPadOS, and macOS.
- The app has one unique main window; multiple game windows are not supported.
- All gameplay works offline. The app must not depend on networking or cloud services.
- Platform-specific presentation may differ, but game behavior and persisted meaning must remain shared.

## Boundaries

### Presentation

SwiftUI views render state and send user intentions to application-level operations. Views must not own rule decisions, persistence transactions, or engine processes.

### Domain state

The current game is represented by pure Swift value types. Domain state contains positions, moves, participants, and game status without depending on SwiftUI, SwiftData, or the engine implementation.

The authoritative rules implementation has not been selected. Application code should depend on an explicit rules boundary for move validation, legal-move generation, and result adjudication rather than assuming that either the app or Fairy-Stockfish owns all rules.

### Persistence

A repository boundary owns loading, saving, replacing, importing, exporting, and deleting games. SwiftData models and `ModelContext` stay behind that boundary and must not become the live domain model. The persistent contract is described in [game-data.md](game-data.md).

### Engine integration

The app owns an engine adapter that translates domain requests into engine requests and returns domain-level results. It also owns engine lifecycle, cancellation, and failure handling. Variant implementation and changes within the Fairy-Stockfish fork belong in that repository, not in this document.

## Dependency direction

Dependencies point inward:

1. SwiftUI presentation depends on application operations and domain values.
2. Application operations coordinate the domain, rules boundary, persistence repository, and engine adapter.
3. SwiftData and Fairy-Stockfish are replaceable infrastructure behind their respective boundaries.
4. Pure domain types do not import UI, persistence, or engine frameworks.

Cross-platform targets should share these layers. Platform-specific code should be limited to system presentation and capabilities such as file selection, sound, haptics, and accessibility integration.

## Asynchronous engine work

- Every search is associated with the game and position revision that requested it.
- Starting a replacement search, undoing a move, ending a game, or leaving the relevant game state cancels outstanding work.
- Cancellation is cooperative; a result must still be rejected if its revision is stale.
- Engine callbacks must not mutate SwiftUI or SwiftData state directly.
- UI-facing state changes occur on the appropriate actor after validation.

## Error handling

Expected failures are returned as typed errors across boundaries. Invalid imports, persistence failures, unavailable engine resources, and engine failures must not terminate the app or partially replace a valid game.

The app should preserve the last committed game state, present an actionable user-facing explanation where appropriate, and retain diagnostic detail without recording private game data unnecessarily.

## Need to discuss

> The following questions are non-normative and are not implementation requirements.

- Which component provides the authoritative offline rules adjudication?
- What is the exact protocol between domain state and the rules provider?
- Should the engine run in-process, behind a C/C++ bridge, or behind another isolation boundary?
- Which failures should be recoverable automatically, and which require user action?
- Which platform-specific capabilities need dedicated adapters rather than conditional presentation code?
