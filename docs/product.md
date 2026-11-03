# Product

The product decisions behind Star River. Rules live in the rules docs and file formats in [game-data.md](game-data.md).

## The app

- The name is **Star River** in English and **闲敲棋子** in Chinese; neither is a translation of the other.
- It runs on iPhone, iPad and Mac on Apple silicon, in one main window. iPhone is portrait only.
- It carries five games: **Xiangqi**, **Mini Xiangqi**, **Jieqi**, **Gomoku** and **Renju**.
- The top-level destinations are **Play**, **History** and **Settings**.
- It works offline. Only Online Play needs the Internet, and it uses Game Center; the app runs no server and no account system of its own.
- It is licensed under GPLv3, and the App Store listing links the source.

## Modes

- **Human versus AI**, in every game but Jieqi, which has no AI.
  - First mover: **I Move First**, **AI Moves First** or **Random**. The choice decides which side the player takes.
  - Levels: **Fast**, **Standard** and **Deep**, differing only in thinking time (1, 3 and 5 seconds a move).
  - Setup starts from the Settings defaults; changing them for one game does not change Settings.
- **Free Play**: one person moves both sides.
- **Custom Scene** (自定排局), Xiangqi only: compose a position, pick who moves first, and play it as Free Play.
- **Nearby Play**: two people, two iPhones or iPads, no Internet.
- **Online Play**: two friends at any distance over Game Center, on iPhone, iPad and Mac. A Game Center invitation or a party code brings them together; there is no matchmaking with strangers.
- A **hint** shows the engine's suggested move on request, in Human versus AI and Free Play only, and not in Jieqi. It plays nothing and is not recorded.
- **Resign** is available in Human versus AI, Nearby Play and Online Play, after a confirmation.

## Playing a game

- Captured pieces are not displayed during play, Jieqi excepted.
- Undo can be repeated during a live game. There is no redo. A natural result stays undoable until the player confirms it.
- There is one active game across all games. It is saved automatically and resumes after the app reopens.
- Starting another game first asks to save the active one to History. An unfinished game is saved as ended early, not as a loss; a game with a result is saved with that result.
- A threefold repetition makes a draw available but does not end the game.

## History

- Every finished or ended game becomes a History record. Its moves cannot be edited.
- Pinned records come first, then the most recent. Imported records are visibly marked.
- Records can be pinned, replayed by hand or with autoplay, shared as a game file, and deleted.
- Deleting asks first unless **Confirm Before Deleting** is off. Deletion is permanent.
- Import takes one game file at a time and never touches the active game. An exact duplicate opens the existing record; a file with the same identity but different content is rejected.

## Settings

- Default first mover (**I Move First** on a new install) and default AI level (**Standard**).
- **Confirm Before Deleting** (on by default) and **Confirm Before Placing** (off by default; Gomoku and Renju only).
- Sound, and haptics where the hardware has them.
- Piece symbols: Chinese characters (default) or icons. No piece style is offered; only Traditional is drawn.
- Notation: traditional Chinese or WXF, defaulting to the interface language.
- No language setting: the app follows the system's per-app language.
- Settings stores no game data, and changing a default never alters an active game.

## Not in the product

- No in-app help or rules reference.
- No game clock, no accounts of our own, no lessons or drills, no multiple main windows.
- No starting from a position in History, no bulk delete, search, folders or tags in History, and no undo of a deletion.
