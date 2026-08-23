# Product

This document owns the product definition, the target platforms, and the feature boundaries. It does not own Xiangqi rules, data schemas, engine design, or detailed UI and interaction behavior.

> **Status: binding.** Every statement here is accepted product behavior.

## Product identity and distribution

- The product name is **Star River**, and **闲敲棋子** in Chinese. Each language uses its own name, and neither is a translation of the other; both are the name of the product rather than of any game inside it.
- The product exists for board-game education inside a small internal group. Education means learning through complete games of the games it carries — **Xiangqi**, **Mini Xiangqi**, **Jieqi**, **Gomoku**, and **Renju** — against the AI or in Free Play. Structured lessons and practice drills are not part of the product.
- The application is licensed under GPLv3, matching the engines it embeds.
- **Windows ships through the Microsoft Store, and the zip stays.** A package submitted to the Store is signed **by the Store**, with Microsoft's certificate, after it is accepted, so a Store submission never needs a certificate of ours. The CI-built zip per architecture remains beside it as the direct download — unpack and run, no installer, no runtime install — because it is the channel that needs no account and no store.
- On Apple platforms, distribution is TestFlight internal testing and the public App Store; the App Store listing states the application's GPLv3 licence and links the complete source.
- **Every build contains the AI networks of every game its AI plays, the Windows zip included**, so there is no file a recipient has to add. What the network this project trained plays like is measured in [engine-integration.md](engine-integration.md); the redistributed ones — built-in Xiangqi's and the placement games' — carry no strength claim of ours, per that document and [placement-engine-integration.md](placement-engine-integration.md). Jieqi carries no network at all: nothing plays it, and the engine behind its rules neither searches nor evaluates, per [jieqi-engine-integration.md](jieqi-engine-integration.md).
- The application is fully offline in everything but **Online Play**, and no other feature may require an Internet connection.
- Fully offline constrains the app, not the platform beneath it: outside **Online Play** the app reaches no Internet host and no server of any kind, and the only network it uses is the local one two devices are on together. **Online Play** reaches exactly one service, Game Center, Apple's own, which provides the accounts, the invitations, and the connection between the players; the app operates no server, relay, or account system of its own anywhere. Platform-provided backup of its store — iCloud backup, Time Machine — is permitted, and operating-system crash reporting follows the user's own system setting rather than being overridden here.

## Target platforms

- iOS 26.6 or later.
- iPadOS 26.6 or later.
- macOS 26.6 or later, on Apple silicon. `x86_64` is not supported on macOS.
- Windows 11 on `x64` and `ARM64`. Windows 10 is not a target: it left Microsoft support in October 2025, and a floor the vendor no longer patches is not a floor this product can promise.
- An architecture is a target because it has been run, not because it is expected to work. `ARM64` qualifies on hardware the owner tests on and on the CI runner that builds, exercises, and distributes it.
- Each platform uses a native frontend — SwiftUI on Apple platforms and WinUI 3 on Windows — over one shared core, as defined in [architecture.md](architecture.md). Product behavior and persisted meaning are identical across platforms; presentation follows each platform's conventions.
- The application has one main window; multiple main windows are not supported.
- iPhone runs in portrait orientation only. iPad supports every orientation, as iPadOS multitasking expects.
- Captured pieces are not displayed during play, **Jieqi excepted**, where what a capture discloses is knowledge the player keeps and [interaction-design.md](interaction-design.md) states the surface for it. Everywhere else the board itself shows what remains, and a second inventory would compete with the board.

## Play modes

- Every game a build carries offers the same modes, **Jieqi excepted**: it has no AI, so it offers **Free Play**, **Nearby Play**, and **Online Play**. **Gomoku, Renju and Jieqi are carried on Apple platforms**; the Windows frontend carries Mini Xiangqi and Xiangqi.
- Human versus AI.
- **Free Play**, where one person controls both Red and Black. It is not presented as a local two-player mode.
- **Nearby Play**, where two people play one game on two devices that reach each other without the Internet. It is offered on iPhone and iPad.
- **Online Play**, where two people play one game on two devices at any distance, over Game Center. It is offered on iPhone, iPad, and Mac, to friends alone: a Game Center invitation or a shared party code brings the two players together, and nothing matches a player with a stranger. The invitation consents to the connection, as pairing does in Nearby Play; the game itself is proposed and accepted over that connection, gated by the same alert Nearby Play uses.
- **Custom Scene**, and **自定排局** in Chinese, is Xiangqi's alone and is not a mode of its own: the player composes a position on an empty board, chooses which side moves first, and plays it out as a **Free Play** game — one person controlling both sides, with the hint, repeated undo, and the board flip, and nothing to resign to. It is offered on Apple platforms. Every other game begins from its own frozen starting position and from no other; Jieqi's own start is dealt rather than frozen, and nobody composes it either.
- Human-versus-AI setup offers **I Move First**, **AI Moves First**, and **Random**. Because the frozen start of each game this mode offers has one first mover — Red in Mini Xiangqi and Xiangqi, Black in the placement games — the resolved choice determines which side the human player takes, which is retained in game metadata.
- On a new installation, the Settings default is **I Move First**. The user may change the persistent default to **AI Moves First** or **Random**.
- Human-versus-AI setup copies the Settings defaults into a temporary per-game draft. Changes to that draft apply only to the game being prepared and never change the Settings defaults.
- The AI's difficulty levels differ only in maximum thinking time: **Fast** at 1 second per move, **Standard** at 3 seconds per move, and **Deep** at 5 seconds per move. **Standard** is the new-install default.
- **An on-demand hint** suggests the engine's move for the side to move. It is offered in human-versus-AI play and in Free Play, in every game but **Jieqi**, which no engine here plays, on the player's own turn in a live game — the human's turn against the AI, either turn in Free Play, since one person controls both sides there. The player asks for it and nothing offers it unbidden; it plays nothing, and the suggested move becomes a move only by the player making it.
- **A hint is never offered in Nearby Play or Online Play.** A suggestion engine on one side of a game between two people is not this product's play between people.
- **Nothing about a hint is recorded.** It is presentation, like flipping the board: the game, its History record, and every export are exactly what they would have been without it, and no assisted marker exists.
- A chess clock is not part of the product.
- Repeated undo is available. Redo is not.
- Resign is available in human-versus-AI play, Nearby Play, and Online Play. After confirmation, resignation records a loss for the player who resigned.
- In-app help is the read-only Mini Xiangqi rules reference. It does not analyze the current game or suggest moves; a standard-Xiangqi Help reference is not part of the current product surface.

## Games and history

- There can be only one active game across every game the app carries.
- The active game is saved automatically and can be resumed after the application exits and reopens.
- Before starting another game, the user must save the active game to History.
- Selecting any game-and-mode entry while a game is active immediately presents the same confirmation with the active game's factual metadata. Every entry remains interactive for both an ongoing game and an unconfirmed natural terminal result.
- Cancelling leaves the active game unchanged. **Save and Continue** atomically saves it to History according to its current state, clears it as the active game, and then opens the selected mode's transient pre-start state.
- An ordinary ongoing game is saved as ended early without a competitive result. This includes a neutral threefold repetition that is merely claimable and has not been claimed.
- An unconfirmed natural terminal result is saved with its actual result and termination reason rather than being reclassified as ended early.
- Every pre-start page visibly identifies the selected game. Human versus AI shows its per-game choices. Free Play shows that one person controls both sides and that Red moves first, without adding configurable setup fields.
- Only **Start Game** creates the selected game. Leaving a pre-start state creates no game and does not restore an old game that the user already saved to History.
- Ending an unfinished active game to start another records it in History as ended early without a competitive result; it is not treated as resignation.
- A natural terminal result remains active and undoable until the user confirms it or chooses **Save and Continue**; after either operation, it becomes immutable History with its factual result and termination reason.
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
- **Confirm Before Placing**, disabled by default, which turns on the placement games' pending-stone flow defined in [interaction-design.md](interaction-design.md) and applies to those games alone;
- a sound toggle and a separate haptics toggle, the latter offered only where the hardware supports haptics;
- the **piece symbols**, Chinese characters by default or pictorial icons, as defined in [interaction-design.md](interaction-design.md);
- the **notation**, traditional Chinese or WXF, defaulting to whichever the interface language reads — the traditional rendering under the Chinese interface, WXF under the English one — as defined in [interaction-design.md](interaction-design.md).

The **piece style** is not offered. The accepted styles in [interaction-design.md](interaction-design.md) remain the visual system's contract, but only **Traditional** is drawn, and a preference with one option is not a preference. The control lands when a second style does.

The piece symbols and the notation are two independent preferences rather than one: a player learning the characters may want icons on the discs while reading the Chinese move list they are learning from, and an international player wants both changed. **The piece symbols do not follow the interface language; the notation does.** The symbols keep **Chinese Characters** everywhere, because a locale-driven default there would surprise anyone comparing two machines over a board whose discs are game content rather than interface copy. The notation is the opposite case: it is a list to be *read*, and opening an English-language reader on characters they cannot read teaches them neither notation. Both remain preferences and neither is a migration: a choice once made stands whatever language the interface is in.

**The Windows frontend offers some of those preferences and hides the rest.** It offers the human-versus-AI defaults, the sound toggle, and **Confirm Before Deleting**. **Confirm Before Placing** is absent because that platform carries no placement game for the switch to be about; each of the other absences is a row that has nothing to offer *yet*. The **notation** is absent because the Windows move record is the core's own canonical coordinate text in both languages, so the preference has nothing to choose between until the proper renderings arrive with it. The **piece symbols** are absent because only **Chinese Characters** is drawn there, which is the piece style's case exactly, and the row lands when the second symbol set does. The **haptics** toggle is absent because the platform's touchpad haptics API — named in [interaction-design.md](interaction-design.md) § Sound and haptics — is experimental, gated to Windows 11 24H2 and later, and carried by rare hardware, so the switch would do nothing on nearly every machine. None of them is a preference the platform *disagrees* with: the keys and their vocabularies are shared, and a Windows launch leaves whatever an Apple frontend stored under them exactly as it found it.

Settings stores no game data, and changing a default never alters an active game. It holds no interface-language control: the app follows the language the operating system selects for it. On Apple platforms that is already a per-app setting the system provides, so our own control would duplicate it and create a second source of truth. On Windows the app follows the system's language preference list.

These preferences live in each platform's own preference system rather than in the shared core, as fixed in [game-data.md](game-data.md).

Detailed navigation behavior and presentation belong in [interaction-design.md](interaction-design.md).

## Exclusions

- Internet-dependent features beyond Online Play, and servers, relays, and account systems of our own, of every kind.
- Chess clocks.
- Multiple main windows.
- Structured lessons and practice drills.
- Starting a new game from a selected historical position.
- Editing History game content.
- Bulk History deletion, search, filters, and tags.
- History folders, Move, deletion Undo, and Recently Deleted.
