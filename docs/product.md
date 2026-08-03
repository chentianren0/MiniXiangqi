# Product

This document owns the product definition, the target platforms, and the feature boundaries. It does not own Xiangqi rules, data schemas, engine design, or detailed UI and interaction behavior.

> **Status: binding.** Every statement here is accepted product behavior.

## Product identity and distribution

- The product name is **Mini Xiangqi**.
- The product exists for Xiangqi education inside a small internal group. Education means learning through complete games of **Xiangqi** or **Mini Xiangqi**, against the AI or in Free Play. Structured lessons, practice drills, and AI hints are not part of the product.
- The application is licensed under GPLv3, matching its Fairy-Stockfish dependency.
- **Windows ships through the Microsoft Store, and the zip stays.** A package submitted to the Store is signed **by the Store**, with Microsoft's certificate, after it is accepted, so a Store submission never needs a certificate of ours. The CI-built zip per architecture remains beside it as the direct download — unpack and run, no installer, no runtime install — because it is the channel that needs no account and no store.
- On Apple platforms, distribution is TestFlight internal testing. There is no public App Store plan.
- **Every build contains both AI network files, the Windows zip included**, so there is no file a recipient has to add. What the bundled networks play like is measured in [engine-integration.md](engine-integration.md).
- The application is fully offline: gameplay and persistence have no dependency on Internet access, an account, an app-operated or third-party server, a relay, cloud storage or synchronization, telemetry, or any network fallback. Loss of network service cannot change whether a local game can start, continue, be saved, or be replayed.
- Fully offline constrains the product and its dependencies, not the platform beneath it. Platform-provided backup of its store — iCloud backup, Time Machine — is permitted, and operating-system crash reporting follows the user's own system setting rather than being overridden here. Ordinary iOS and iPadOS Release builds intended only for Internal TestFlight include the non-product Wi-Fi Aware proof lab defined in [architecture.md](architecture.md); its direct nearby diagnostic exchange is development evidence, not a product feature or dependency, and it must not be promoted to any broader distribution.

## Target platforms

- iOS 26.6 or later.
- iPadOS 26.6 or later.
- macOS 26.6 or later, on Apple silicon. `x86_64` is not supported on macOS.
- Windows 11 on `x64` and `ARM64`. Windows 10 is not a target: it left Microsoft support in October 2025, and a floor the vendor no longer patches is not a floor this product can promise.
- An architecture is a target because it has been run, not because it is expected to work. `ARM64` qualifies on hardware the owner tests on and on the CI runner that builds, exercises, and distributes it.
- Each platform uses a native frontend — SwiftUI on Apple platforms and WinUI 3 on Windows — over one shared core, as defined in [architecture.md](architecture.md). Product behavior and persisted meaning are identical across platforms; presentation follows each platform's conventions.
- The application has one main window; multiple main windows are not supported.
- iPhone runs in portrait orientation only. iPad supports every orientation, as iPadOS multitasking expects.
- Captured pieces are not displayed during play. The board itself shows what remains, and a second inventory would compete with the board in both games.

## Play modes

- Xiangqi and Mini Xiangqi each offer exactly the same two modes, yielding exactly four Play rows. An internal transport lab is not a third mode or a fifth row.
- Human versus AI.
- **Free Play**, where one person controls both Red and Black. It is not presented as a local two-player mode.
- Human-versus-AI setup offers **我先手** (I Move First), **AI 先手** (AI Moves First), and **随机** (Random). Because Red moves first, the resolved choice determines the human player's Red or Black side, which is retained in game metadata.
- On a new installation, the Settings default is **我先手**. The user may change the persistent default to **AI 先手** or **随机**.
- Human-versus-AI setup copies the Settings defaults into a temporary per-game draft. Changes to that draft apply only to the game being prepared and never change the Settings defaults.
- The AI offers three difficulty levels that differ only in maximum thinking time: **快速** at 1 second per move, **标准** at 3 seconds per move, and **深思** at 5 seconds per move. **标准** is the new-install default.
- A chess clock is not part of the product.
- Repeated undo is available. Redo is not.
- Resign is available only in human-versus-AI games. After confirmation, resignation records a loss for the human player.
- In-app help is the read-only Mini Xiangqi rules reference. It does not analyze the current game or suggest moves; a standard-Xiangqi Help reference is not part of the current product surface.

## Games and history

- There can be only one active game across Xiangqi and Mini Xiangqi.
- The active game is saved automatically and can be resumed after the application exits and reopens.
- Before starting another game, the user must save the active game to History.
- Selecting any of the four game-and-mode entries while a game is active immediately presents the same confirmation with the active game's factual metadata. Every entry remains interactive for both an ongoing game and an unconfirmed natural terminal result.
- Cancelling leaves the active game unchanged. **保存并继续** atomically saves it to History according to its current state, clears it as the active game, and then opens the selected mode's transient pre-start state.
- An ordinary ongoing game is saved as ended early without a competitive result. This includes a neutral threefold repetition that is merely claimable and has not been claimed.
- An unconfirmed natural terminal result is saved with its actual result and termination reason rather than being reclassified as ended early.
- Every pre-start page visibly identifies the selected game. Human versus AI shows its per-game choices. Free Play shows that one person controls both sides and that Red moves first, without adding configurable setup fields.
- Only **开始对局** creates the selected game. Leaving either pre-start state creates no game and does not restore an old game that the user already saved to History.
- Ending an unfinished active game to start another records it in History as ended early without a competitive result; it is not treated as resignation.
- A natural terminal result remains active and undoable until the user confirms it or chooses **保存并继续**; after either operation, it becomes immutable History with its factual result and termination reason.
- In both human-versus-AI play and Free Play, a neutral threefold repetition makes a draw available but does not automatically end the active game. The user may continue playing or end the game as a draw.
- A History record's game content cannot be edited. Pinning is mutable library organization rather than an edit to the game, and the complete record can be deleted individually.
- Pinned History records appear first. Within the pinned and unpinned groups, the most recently recorded or imported games appear first.
- Each History entry identifies at least its game, date, mode, result or end reason, and move count; human-versus-AI entries also identify the human side, and imported entries are visibly marked.
- The History list provides Pin or Unpin, Share, and Delete. Share exports one game file.
- History games can be replayed manually or with user-started autoplay.
- **Confirm Before Deleting** is enabled by default in Settings and may be disabled by the user. A completed deletion is permanent: there is neither deletion Undo nor Recently Deleted.
- Import accepts one compatible game file at a time and creates an immutable History record without replacing or otherwise changing the active game.
- Importing an exact duplicate does not create another record and offers access to the existing record. A file with the same stable identity but different game content is rejected as a conflict.

## Product navigation

The primary destinations are **Play**, **History**, and **Settings**.

Settings holds the persistent user preferences:

- the default first-mover choice for human-versus-AI setup;
- the default AI level;
- **Confirm Before Deleting**, enabled by default;
- a sound toggle and a separate haptics toggle, the latter offered only where the hardware supports haptics;
- the **piece symbols**, Chinese characters by default or pictorial icons, as defined in [interaction-design.md](interaction-design.md);
- the **notation**, traditional Chinese or WXF, defaulting to whichever the interface language reads — the traditional rendering under 中文, WXF under English — as defined in [interaction-design.md](interaction-design.md).

The **piece style** is not offered. The three accepted styles in [interaction-design.md](interaction-design.md) remain the visual system's contract, but only 传统 is drawn, and a preference with one option is not a preference. The control lands when a second style does.

The piece symbols and the notation are two independent preferences rather than one: a player learning the characters may want icons on the discs while reading the Chinese move list they are learning from, and an international player wants both changed. **The piece symbols do not follow the interface language; the notation does.** The symbols keep 汉字 everywhere, because a locale-driven default there would surprise anyone comparing two machines over a board whose discs are game content rather than interface copy. The notation is the opposite case: it is a list to be *read*, and opening an English-language reader on characters they cannot read teaches them neither notation. Both remain preferences and neither is a migration: a choice once made stands whatever language the interface is in.

**The Windows frontend offers four of those preferences and hides the other three, and each absence is a row that has nothing to offer *yet*.** It offers the two human-versus-AI defaults, the sound toggle, and **删除前确认**. The **notation** is absent because the Windows move record is the core's own canonical coordinate text in both languages, so the preference has nothing to choose between until the two proper renderings arrive with it. The **piece symbols** are absent because only 汉字 is drawn there, which is the piece style's case exactly, and the row lands when the second symbol set does. The **haptics** toggle is absent because the platform's touchpad haptics API — named in [interaction-design.md](interaction-design.md) § Sound and haptics — is experimental, gated to Windows 11 24H2 and later, and carried by rare hardware, so the switch would do nothing on nearly every machine. None of the three is a preference the platform *disagrees* with: the keys and their vocabularies are shared, and a Windows launch leaves whatever an Apple frontend stored under them exactly as it found it.

Settings stores no game data, and changing a default never alters an active game. It holds no interface-language control: the app follows the language the operating system selects for it. On Apple platforms that is already a per-app setting the system provides, so our own control would duplicate it and create a second source of truth. On Windows the app follows the system's language preference list.

These preferences live in each platform's own preference system rather than in the shared core, as fixed in [game-data.md](game-data.md).

Detailed navigation behavior and presentation belong in [interaction-design.md](interaction-design.md).

## Exclusions

- Internet-, account-, server-, relay-, cloud-, telemetry-, or fallback-dependent product features. The internal-test-only proof lab above is not a product feature.
- Chess clocks.
- Multiple main windows.
- Structured lessons, practice drills, and AI hints.
- Starting a new game from a selected historical position.
- Editing History game content.
- Bulk History deletion, search, filters, and tags.
- History folders, Move, deletion Undo, and Recently Deleted.
