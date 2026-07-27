# Product

This document is for product designers, engineers, testers, and reviewers who need the agreed target scope for Mini Xiangqi. It owns the product definition and target-MVP feature boundaries. It does not own implementation progress, project scheduling, Xiangqi rules, data schemas, engine design, or detailed UI and interaction behavior.

> **Status: Living target-MVP contract**
>
> Sections outside **Need to discuss** describe accepted intended product behavior. They do not imply that a feature has been implemented. **Need to discuss** is explicitly non-normative. Progress and delivery work belong in GitHub Issues, not in this document.

## Product identity and distribution

- The product name is **Mini Xiangqi**.
- The application is licensed under GPLv3.
- Distribution is limited to internal TestFlight testing for the target MVP. It is not a public release.
- The application is fully offline and must not require an Internet connection.

## Target platforms

- iOS 26.5 or later.
- iPadOS 26.5 or later.
- macOS 26.5 or later.
- macOS targets Apple silicon. `x86_64` is not supported.
- The application has one main window; multiple main windows are not supported.

## Target-MVP play modes

- Human versus computer.
- **Free Play**, where one person controls both Red and Black. It is not presented as a local two-player mode.
- In human-versus-computer games, Settings offers **Red**, **Black**, and **Random** for the human player's side. A Random choice is resolved when the game is created and the result is shown in the game metadata.
- The computer opponent has configurable difficulty levels.
- A chess clock is not part of the target MVP.
- Repeated undo is part of the target MVP. Redo is not.
- Resign is available only in human-versus-computer games. After confirmation, resignation records a loss for the human player.

## Games and history

- There can be only one active game.
- The active game is saved automatically and can be resumed after the application exits and reopens.
- Before starting another game, the user must end the active game.
- Ending an unfinished active game to start another records it in History as ended early without a competitive result; it is not treated as resignation.
- A naturally completed or otherwise confirmed ended game becomes an immutable history game.
- In both human-versus-computer play and Free Play, a neutral threefold repetition makes a draw available but does not automatically end the active game. The user may continue playing or end the game as a draw.
- History games can be replayed manually or with user-started autoplay, deleted, and exported.
- Importing compatible game records is part of the target MVP.
- Starting a new game from a selected historical position is not part of the target MVP.

## Product navigation

The primary destinations are:

- **Play**
- **History**
- **Settings**

Detailed navigation behavior and presentation belong in `interaction-design.md`.

## Target-MVP exclusions

- Network-dependent features.
- Public distribution.
- Chess clocks.
- Multiple main windows.
- Starting a new game from a selected historical position.

## Need to discuss

> The items below are questions, not requirements or implementation authorization.

- Define the number, names, and user-facing meaning of AI difficulty levels.
- Define the default side choice for new human-versus-computer installations.
- Define import and export product behavior, including whether imported games are always historical.
- Reconsider starting from a historical position only after estimating its implementation and interaction complexity; the current target MVP excludes it.
- Define what “fully offline” permits for platform-provided local diagnostics, backup, and other system behavior.
