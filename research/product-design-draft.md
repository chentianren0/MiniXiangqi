# MiniXiangqi product interaction — discussion draft

This draft assumes the settled product: a native SwiftUI app for iOS, iPadOS, and macOS; fully offline; English and Simplified Chinese; PyChess Mini Xiangqi rules as the authority; human versus on-device AI and local two-player; one active game plus unlimited local history; auto-save, replay, optional undo, and time controls; no online play. It intentionally proposes the smallest coherent first experience.

## Questions to resolve next

These are the remaining choices most likely to change the state model or core interaction:

1. **What kind of time control ships first?** The baseline below uses a simple per-player countdown with no increment and pauses it while the app is inactive. Increment, per-move limits, or clocks that continue in the background require different timing and restoration behavior.
2. **Does the first AI have one strength or selectable levels?** One well-calibrated strength keeps setup lean; levels require an engine contract, labels, persistence, and response-time expectations.
3. **In local two-player, should the board stay fixed or rotate for each turn?** The baseline stays fixed. Automatic rotation better supports a passed phone, but changes animation, coordinate labels, and turn handoff.
4. **Can users delete history?** “Unlimited” should mean the app imposes no count limit. Choosing immutable history versus delete-one/delete-all changes persistence operations and confirmation UI.

## Baseline flow

### Home and top-level navigation

The three destinations are **Home**, **Games**, and **Settings**.

- With no active game, Home has one primary action: **New Game**.
- With an active game, Home leads with **Resume Game** and shows whose turn it is, the opponent type, and remaining time when clocks are enabled. **New Game** remains secondary.
- Games shows the active game first, when present, followed by history in reverse chronological order.
- Settings is intentionally small: **Language** (`System`, `English`, `简体中文`), **Default Time Control**, and **Allow Undo by Default**. Language changes apply throughout the app without requiring network access.

There is no account, lobby, matchmaking, cloud status, social surface, or network-error state.

### Starting a game

New-game setup is one screen:

- **Opponent:** `Computer` or `Two Players`
- For Computer only, **Play as:** `Red`, `Black`, or `Random`
- **Time:** `No Limit`, `5 minutes`, `10 minutes`, or `15 minutes` per player
- **Allow Undo:** on or off
- Primary action: **Start Game**

The baseline ships with one AI strength, no player-name fields, no advanced-rule choices, and no custom timer editor. The selected time control and undo policy are fixed when the game starts and stored with the game.

New Game setup may be opened and edited while another game remains active. Its selections are only a draft: the current game is untouched unless the user taps **Start Game** and confirms its replacement. Cancelling that confirmation leaves the configured setup in place.

PyChess Mini Xiangqi defines legal positions, legal moves, turn order, and rule-based game endings. The app should present those results rather than creating a parallel interpretation of the rules.

### The active game

The game screen contains the board, clear turn ownership, clocks when enabled, **Undo** when allowed, and **End Game**. Leaving the screen is not abandonment: the game remains active and can be resumed from Home or Games.

Auto-save happens after every accepted move and whenever lifecycle state changes. There is no Save button. On relaunch, the user returns to Home with **Resume Game** available.

For the baseline time control, each player has the selected total time, no increment, and expiration ends the game. Clocks pause while the app is not active so an interruption or terminated process cannot silently consume time.

When undo is allowed:

- Against the AI, Undo returns to the position before the human’s previous move, normally removing the human move and the AI reply.
- In local two-player, Undo removes one move.
- Undo may continue back to the initial position while the game is active.

Undone moves do not appear in the saved replay. If undo is disabled, the action is absent rather than shown as a permanently disabled control.

When a game reaches a canonical result or a clock expires, it immediately leaves the active slot and is saved to history. A compact result sheet states the outcome and offers **Review Game**, **New Game**, and **Done**.

Choosing **End Game** uses:

> **End this game?**  
> This game will be saved in Games as Ended Early.

Actions are **Keep Playing** and **End Game**. Ending early does not invent a winner.

### One-active-game conflict

If the user taps **Start Game** after configuring a new game while another game is active, show:

> **Replace Current Game?**  
> Only one game can be active at a time. Starting this game will end the current game and save it in Games as Ended Early.

Actions:

- **Resume Current Game** — keeps the current game active and opens it. Retain the configured replacement as an in-memory draft when practical.
- **End Current Game and Start New** — archives the current game as Ended Early, then starts the configured replacement.
- **Cancel** — dismisses the confirmation and returns to setup with every selection intact.

The active game remains intact until the second action is confirmed. The explanatory prompt is the only confirmation; a second warning would add friction without protecting additional data.

### Games, history, and replay

History includes every normally completed game and every game ended early, with no app-defined count limit. A row shows the opponent type, result or **Ended Early**, date, and time control. Selecting a row opens its replay at the final recorded position.

Replay is read-only and follows the saved main line:

- previous and next move;
- jump to the initial or final position;
- current move number and side to move;
- final result or **Ended Early** status.

An ended-early replay stops at its last accepted move. Replay does not resume a game, branch into analysis, invoke the AI, or change history. Search, tags, annotations, sharing, and import/export are outside the initial interaction.

### Local two-player

The baseline uses a fixed board orientation, with Red on the same side throughout. A prominent turn label and piece-selection state make handoff clear. The two players share the same device and clock controls; there are no profiles or name-entry steps.

**Meaningful alternative:** rotate the board after each completed move, with a short handoff state before revealing the next player’s orientation. This is better for passing an iPhone back and forth, but slower on a shared iPad or Mac and potentially disorienting.

## Platform adaptation

- **iPhone:** use the system SwiftUI bottom `TabView` and its native Liquid Glass treatment for Home, Games, and Settings. Do not recreate glass with custom materials. The game and replay remain within the selected tab’s navigation flow; the board scales to the available width.
- **iPad:** retain the same destinations and state, adapting regular-width Games to a history list and replay detail where space permits. During play, extra width can place status and controls beside the board rather than enlarging the board without bound.
- **macOS:** present Home, Games, and Settings in a native sidebar with the selected content in the detail area. Game and replay support resizable windows and keep the board’s aspect ratio. The macOS Settings command should open the same settings content rather than create a second settings model.

Navigation changes presentation, not product behavior. An active game, its auto-save rules, history, replay controls, localization, and canonical rule handling remain consistent across all three platforms and stay entirely on device.
