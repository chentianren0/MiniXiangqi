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
- Two people playing locally on the same device.
- In human-versus-computer games, the player can choose a color.
- The computer opponent has configurable difficulty levels.
- A chess clock is not part of the target MVP.
- One-step undo is part of the target MVP.

## Games and history

- There can be only one active game.
- The active game is saved automatically and can be resumed after the application exits and reopens.
- Before starting another game, the user must end the active game.
- An ended game becomes a history game.
- History games can be replayed, deleted, and exported.
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

- Define the exact color-selection options and default for human-versus-computer games.
- Define the number, names, and user-facing meaning of AI difficulty levels.
- Define the exact undo behavior for each play mode, including undo while the AI is thinking.
- Define how an active game is ended or replaced and which confirmations are required.
- Define which game results and termination reasons appear in history.
- Define import and export product behavior, including whether imported games are always historical.
- Reconsider starting from a historical position only after estimating its implementation and interaction complexity; the current target MVP excludes it.
- Define what “fully offline” permits for platform-provided local diagnostics, backup, and other system behavior.
