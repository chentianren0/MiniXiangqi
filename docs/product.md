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

- Human versus AI.
- **Free Play**, where one person controls both Red and Black. It is not presented as a local two-player mode.
- Human-versus-AI setup offers **我先手** (I Move First), **AI 先手** (AI Moves First), and **随机** (Random). Because Red moves first, the resolved choice determines the human player's Red or Black side, which is retained in game metadata.
- On a new installation, the Settings default is **我先手**. The user may change the persistent default to **AI 先手** or **随机**.
- Human-versus-AI setup copies the Settings defaults into a temporary per-game draft. Changes to that draft apply only to the game being prepared and never change the Settings defaults.
- The AI offers three difficulty levels that differ only in maximum thinking time: **快速** at 1 second per move, **标准** at 3 seconds per move, and **深思** at 5 seconds per move. **标准** is the new-install default.
- A chess clock is not part of the target MVP.
- Repeated undo is part of the target MVP. Redo is not.
- Resign is available only in human-versus-AI games. After confirmation, resignation records a loss for the human player.

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

Detailed navigation behavior and presentation belong in `interaction-design.md`.

## Target-MVP exclusions

- Network-dependent features.
- Public distribution.
- Chess clocks.
- Multiple main windows.
- Starting a new game from a selected historical position.
- Editing History game content.
- Bulk History deletion, search, filters, and tags.
- History folders, Move, deletion Undo, and Recently Deleted.

## Need to discuss

> The items below are questions, not requirements or implementation authorization.

- Reconsider starting from a historical position only after estimating its implementation and interaction complexity; the current target MVP excludes it.
- Define what “fully offline” permits for platform-provided local diagnostics, backup, and other system behavior.
- Reconsider the target-platform scope before implementation architecture is finalized. One possible direction is to expand the current Apple-only target to Apple platforms plus Windows, use a native frontend on each platform, and share only code that is appropriate to share. This is an open question and does not change the current target-platform contract.
