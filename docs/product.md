# Product

This document is for product designers, engineers, testers, and reviewers who need the agreed target scope for Mini Xiangqi. It owns the product definition and target-MVP feature boundaries. It does not own implementation progress, project scheduling, Xiangqi rules, data schemas, engine design, or detailed UI and interaction behavior.

> **Status: Living target-MVP contract**
>
> Sections outside **Need to discuss** describe accepted intended product behavior. They do not imply that a feature has been implemented. **Need to discuss** is explicitly non-normative. Progress and delivery work belong in GitHub Issues, not in this document.

## Product identity and distribution

- The product name is **Mini Xiangqi**.
- The product exists for Mini Xiangqi education inside a small internal group. Education in the target MVP means learning through play: complete games against the AI or in Free Play, supported by in-app help that explains the pieces, rules, and results. Structured lessons, practice drills, and AI hints are not part of the target MVP.
- The application is licensed under GPLv3, matching its Fairy-Stockfish dependency.
- Distribution is internal only: TestFlight internal testing on Apple platforms and direct internal installation on Windows. There is no public App Store, Microsoft Store, or other public release plan.
- The application is fully offline and must not require an Internet connection.

## Target platforms

- iOS 26.5 or later.
- iPadOS 26.5 or later.
- macOS 26.5 or later.
- macOS targets Apple silicon. `x86_64` is not supported on macOS.
- Windows 11, and Windows 10 version 1809 or later, on `x64` and `ARM64`.
- Each platform uses a native frontend — SwiftUI on Apple platforms and WinUI 3 on Windows — over one shared core, as defined in [architecture.md](architecture.md). Product behavior and persisted meaning are identical across platforms; presentation follows each platform's conventions.
- Apple platforms are implemented and distributed first; Windows follows on the same shared core and product contract.
- The application has one main window; multiple main windows are not supported.

## Target-MVP play modes

- Human versus AI.
- **Free Play**, where one person controls both Red and Black. It is not presented as a local two-player mode.
- Human-versus-AI setup offers **我先手** (I Move First), **AI 先手** (AI Moves First), and **随机** (Random). Because Red moves first, the resolved choice determines the human player's Red or Black side, which is retained in game metadata.
- On a new installation, the Settings default is **我先手**. The user may change the persistent default to **AI 先手** or **随机**.
- Human-versus-AI setup copies the Settings defaults into a temporary per-game draft. Changes to that draft apply only to the game being prepared and never change the Settings defaults.
- The AI offers three difficulty levels that differ only in maximum thinking time: **快速** at 1 second per move, **标准** at 3 seconds per move, and **深思** at 5 seconds per move. **标准** is the new-install default.
- A chess clock is not part of the target MVP.
- Repeated undo is part of the target MVP. Redo is not.
- Resign is available only in human-versus-AI games. After confirmation, resignation records a loss for the human player.
- In-app help provides a Mini Xiangqi rules reference covering the board, pieces, movement, and game results. Help is read-only reference content; it does not analyze the current game or suggest moves.

## Games and history

- There can be only one active game.
- The active game is saved automatically and can be resumed after the application exits and reopens.
- Before starting another game, the user must save the active game to History.
- Selecting Human versus AI or Free Play while any game is active immediately presents the same confirmation with the active game's factual metadata. The mode entries remain interactive for both an ongoing game and an unconfirmed natural terminal result.
- Cancelling leaves the active game unchanged. **保存并继续** atomically saves it to History according to its current state, clears it as the active game, and then opens the selected mode's transient pre-start state.
- An ordinary ongoing game is saved as ended early without a competitive result. This includes a neutral threefold repetition that is merely claimable and has not been claimed.
- An unconfirmed natural terminal result is saved with its actual result and termination reason rather than being reclassified as ended early.
- Human versus AI shows its per-game choices. Free Play shows that one person controls both sides and that Red moves first, without adding configurable setup fields.
- Only **开始对局** creates the selected game. Leaving either pre-start state creates no game and does not restore an old game that the user already saved to History.
- Ending an unfinished active game to start another records it in History as ended early without a competitive result; it is not treated as resignation.
- A natural terminal result remains active and undoable until the user confirms it or chooses **保存并继续**; after either operation, it becomes immutable History with its factual result and termination reason.
- In both human-versus-AI play and Free Play, a neutral threefold repetition makes a draw available but does not automatically end the active game. The user may continue playing or end the game as a draw.
- A History record's game content cannot be edited. Pinning is mutable library organization rather than an edit to the game, and the complete record can be deleted individually.
- Pinned History records appear first. Within the pinned and unpinned groups, the most recently recorded or imported games appear first.
- Each History entry identifies at least its date, mode, result or end reason, and move count; human-versus-AI entries also identify the human side, and imported entries are visibly marked.
- The History list provides Pin or Unpin, Share, and Delete. Share exports one game file.
- History games can be replayed manually or with user-started autoplay.
- **Confirm Before Deleting** is enabled by default in Settings and may be disabled by the user. A completed deletion is permanent: the target MVP has neither deletion Undo nor Recently Deleted.
- Import accepts one compatible game file at a time and creates an immutable History record without replacing or otherwise changing the active game.
- Importing an exact duplicate does not create another record and offers access to the existing record. A file with the same stable identity but different game content is rejected as a conflict.
- Bulk deletion, History search, filters, and tags are not part of the target MVP.
- Starting a new game from a selected historical position is not part of the target MVP.

## Product navigation

The primary destinations are:

- **Play**
- **History**
- **Settings**

Settings holds the persistent user preferences the target MVP accepts:

- the default first-mover choice for human-versus-AI setup;
- the default AI level;
- **Confirm Before Deleting**, enabled by default;
- a sound toggle and a separate haptics toggle, the latter offered only where the hardware supports haptics;
- **Western piece labels**, off by default, which shows English piece initials on the board instead of Chinese characters.

Settings stores no game data, and changing a default never alters an active game.

Detailed navigation behavior and presentation belong in `interaction-design.md`.

## Target-MVP exclusions

- Network-dependent features.
- Public distribution.
- Chess clocks.
- Multiple main windows.
- Structured lessons, practice drills, and AI hints.
- Starting a new game from a selected historical position.
- Editing History game content.
- Bulk History deletion, search, filters, and tags.
- History folders, Move, deletion Undo, and Recently Deleted.

## Need to discuss

> The items below are questions, not requirements or implementation authorization.

- Reconsider starting from a historical position only after estimating its implementation and interaction complexity; the current target MVP excludes it. It may later serve the education purpose by letting a teacher set up a position.
- Define what “fully offline” permits for platform-provided local diagnostics, backup, and other system behavior.
- Decide whether the app needs its own interface-language control on any platform, given that Apple platforms already provide a per-app language setting.
- Define the exact Windows internal-distribution mechanism, packaging format, and minimum tested Windows configuration before Windows implementation begins.
