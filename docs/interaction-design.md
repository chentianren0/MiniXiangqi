# Interaction Design

This document is for product designers, UI engineers, accessibility reviewers, artists, audio designers, and testers who shape or evaluate the Mini Xiangqi experience. It owns UI and UX behavior, navigation, Liquid Glass usage, board presentation, help, animation and motion, visual effects, sound, haptics, accessibility, localization, and platform adaptation. It does not own product feature scope, Xiangqi rules, persistence formats, engine behavior, implementation progress, or scheduling.

> **Status: Living target-MVP interaction contract**
>
> Sections outside **Need to discuss** describe accepted intended interaction direction. They do not imply that the experience has been implemented. **Need to discuss** is explicitly non-normative. Progress and delivery work belong in GitHub Issues, not in this document.

## Experience goals

- Make the board and current game state immediately understandable.
- Keep primary play actions easy to reach without obscuring the board.
- Provide a coherent experience across iOS, iPadOS, and macOS while respecting each platform’s interaction conventions.
- Treat accessibility as part of the design, not as a later visual adjustment.

## Navigation

The primary destinations are:

- **Play** for starting or resuming a game.
- **History** for reviewing and managing history records.
- **Settings** for user preferences.

The navigation presentation must adapt appropriately to iPhone, iPad, and Mac. Platform adaptation may change presentation, but it must not create different product capabilities without an explicit product decision.

## Liquid Glass

Liquid Glass is a required part of the visual and interaction direction.

- Use Liquid Glass for functional interface layers such as navigation, controls, toolbars, and contextual actions.
- Preserve board readability and interaction clarity when glass surfaces overlap or surround game content.
- Prefer platform-native behavior and adaptation over fixed imitations of one platform’s layout.
- Visual effects must not make controls, state, focus, or text harder to perceive.

## Board and game interaction

The board is the primary content during play. Its interaction design must cover:

- Color choice and the accepted board-orientation behavior below.
- Selection, legal destinations, the last move, check, and game result states.
- Move input, cancellation, repeated undo, and AI-thinking states.
- Clear prevention or explanation of unavailable actions.
- Replay controls and navigation through a history game.
- Help that explains both game concepts and interface behavior in context.

### Board orientation

- In human-versus-computer play, the human player's side is displayed at the bottom. Choosing Black flips the board automatically; choosing Random first resolves the human side and then applies the corresponding orientation.
- In Free Play, Red is at the bottom by default. A visible **Flip Board** control allows the player to change orientation at any time.
- Human-versus-computer history replay defaults to the original human player's perspective. Free Play and imported history default to Red at the bottom. History replay provides the same visible orientation control.
- Flipping the board changes presentation only. It does not change the side to move, game state, move history, or stored coordinates.
- Piece text and symbols remain upright and readable in either orientation.
- Board flipping uses a visible control rather than a hidden rotation gesture. The control has a localized accessibility label and an equivalent keyboard command where keyboard input is supported.

### Move input

- Tap-to-move and drag-to-move are both supported and commit through the same legal-move boundary.
- Tapping a movable piece controlled by the human selects it and reveals all of its legal destinations.
- Tapping a legal destination commits the move immediately. Ordinary legal moves do not require confirmation.
- Tapping another movable piece controlled by the human switches the selection directly.
- Tapping the selected piece again, or tapping outside the board, cancels the selection.
- Tapping an illegal board square does not move the piece or cancel the current selection. It provides brief, non-blocking feedback.
- Dragging a movable piece beyond the gesture threshold selects it and reveals its legal destinations. Dropping on a legal destination commits the move; dropping elsewhere returns the piece to its origin.
- iPhone and iPad use touch interaction. Mac supports the equivalent click-to-move and pointer-drag behavior.
- Keyboard and VoiceOver use an equivalent select-piece, inspect-destinations, and select-destination flow rather than requiring a drag gesture.
- When input is unavailable, including while the computer is thinking or after a result is confirmed, the board rejects the interaction before visually moving a piece.

### Turn status

A persistent status element near the board is one coherent description of the current play state:

- Its primary line always identifies the side to move, using the localized equivalent of **轮到红方** or **轮到黑方**.
- In human-versus-computer play, a secondary label identifies that side's controller as **你** or **电脑**. Computer thinking is shown as activity attached to the computer's turn; it does not replace or compete with the side-to-move line.
- Free Play omits a human/computer controller label because the same person controls both sides.
- The design does not add a separate, unrelated instruction such as “please move” or “your turn.”
- Board input is accepted only when the committed game state permits the user to move. It is disabled while the computer is thinking.
- History replay uses a separate move-progress and playback state rather than describing the position as a human or computer turn.

Turn ownership, activity, and input availability must not be communicated by color alone. The element is driven by committed game and engine state, and a resolved Random side choice is visible in game metadata.

### Insufficient memory for computer play

- Before an AI engine is initialized, the app calculates the accepted Hash budget. A budget below 256 MiB does not start the computer opponent.
- The app presents a notice asking the user to close other apps and retry.
- Retrying obtains a fresh `os_proc_available_memory()` value and recalculates the budget; the prior value is not cached.
- This low-memory path does not substitute a smaller Hash or perform a special automatic cleanup pass to manufacture the minimum budget.
- Any active game remains saved and unchanged while the computer opponent is unavailable.
- The notice may suggest closing other apps, but it does not promise that iOS will terminate them or that a retry will succeed.

The notice's exact copy, actions, presentation, repeated-failure behavior, and accessibility announcement remain to be designed.

### Replacing an unfinished game

The Play destination shows the active game's metadata and a direct **Resume Game** action. The metadata identifies at least the mode, the human's side when applicable, the side to move, and the move count.

Starting a new game while another is active uses one fixed confirmation for every old-mode and new-mode combination:

- Title: **End Unfinished Game?**
- Message: **Starting a new game will end the game shown above and save it to History.**
- Actions: **Cancel** and **End & Start New Game**.

The sheet shows the existing game's metadata. Its wording does not interpolate mode-specific combinations and does not use an ambiguous phrase such as “current play.” Confirming records the old game as ended early without a competitive result, then starts the requested game atomically.

### Undo and result confirmation

- Free Play removes one move per Undo action and can repeat back to the initial position.
- In human-versus-computer play, Undo while the computer is thinking cancels the search and removes the human move that triggered it.
- After the computer has replied, one Undo action removes the computer reply and the preceding human move, returning to the previous human decision point. The action can be repeated by complete decision cycles.
- If a human move itself reaches a natural terminal state, Undo removes that human move while the result presentation remains unconfirmed.
- If the computer moved first, its opening move alone cannot be undone.
- Redo is not available. A new move after Undo permanently replaces the discarded continuation.
- A natural result remains undoable while its result presentation awaits confirmation. Undo dismisses that presentation and resumes the game.
- After result confirmation, resignation confirmation, or **End & Start New Game**, the History record is immutable and cannot be undone.
- Undo is disabled at the earliest valid boundary and while a prior Undo transition is still being applied.

### Natural result presentation

- When a natural terminal result is reached, the final board remains fully visible and a non-dismissible result card appears near it.
- The card title is the localized equivalent of **红方获胜**, **黑方获胜**, or **和棋**. A second line explains the result reason. Human-versus-computer play may also show relevant player metadata without replacing the result.
- Before confirmation, the actions are **悔棋** and **结束对局**. Undo follows the mode-specific behavior above, dismisses the result card, and resumes the active game.
- The result card cannot be dismissed by tapping outside it. Resignation remains a separate confirmed action rather than being folded into the natural-result card.
- After **结束对局**, the final board remains visible, the record becomes immutable History, and the card changes to **已记录到历史**.
- The recorded state offers **回放**, which opens the newly created History record from its initial position, and **完成**, which returns to the Play start state.
- The target MVP does not add a Play Again action to this card.

### Claimable threefold repetition

- In both human-versus-computer play and Free Play, a neutral threefold repetition does not automatically end the game.
- When the draw first becomes available, the notice says **局面已三次重复，可以和棋结束。** and offers **继续对局** and **以和棋结束**.
- **以和棋结束** confirms an immutable draw record in History.
- After **继续对局**, the same still-valid claim is exposed through a non-blocking **可判和** affordance instead of repeatedly presenting the same blocking notice.

### History replay

- Replay entered from History or from the just-recorded result begins at the game's initial position.
- The board is read-only. Replay does not offer move input, Undo, or starting a new game from the displayed position.
- Controls provide jump to beginning, one move back, play or pause, one move forward, and jump to end.
- The move list highlights the currently displayed move and allows the user to jump to a selected move.
- The accepted history orientation and visible Flip Board control remain available.
- Delete and export are available through the replay toolbar or an equivalent More menu; their destructive confirmations and error flows remain to be designed.
- Autoplay starts only after a user action and waits for each move animation to finish before advancing.
- Autoplay offers session-only speeds of 0.5×, 1×, and 2×. Manual move navigation, flipping the board, or the app moving to the background pauses playback. Playback stops at the final position.
- With Reduce Motion, replay uses the accepted crossfade or immediate board update while preserving the same order and playback controls.

### History library

- History records are listed with the most recently recorded or imported first.
- Each entry shows its date, mode, result or end reason, and move count. Human-versus-computer entries also show the human side; imported records have a visible imported marker.
- Selecting an entry opens its read-only replay.
- Record content is read-only, but a complete record can be deleted individually after confirmation.
- Export operates on one selected History record and produces one game file.
- Import selects one game file at a time. A valid import creates an immutable History record and leaves the active game unchanged.
- An exact duplicate does not create a second record and offers a way to view the existing record. A stable-identity conflict with different game content is rejected with an explanation.
- Bulk deletion, search, filters, tags, and editing a History game are absent from the target MVP.

The exact list layout, date and move-count formatting, row actions, confirmation copy, file-picker presentation, success feedback, and recoverable error flows remain to be designed.

## Motion and visual effects

Animation, motion, and visual effects are part of the intended experience. They must communicate state changes and preserve the user’s understanding of the position. Reduced-motion preferences and interruption behavior must be designed alongside the default experience.

The first implementation uses a restrained, tactile motion language:

- Selecting a piece uses a brief, approximately 120–160 ms lift, scale, and shadow transition without continuous movement.
- Empty legal destinations use a small dot; capturable destinations use a ring around the target piece. The two states differ by shape and do not rely on color alone.
- During a drag, the piece follows the pointer or touch, its origin retains a subtle marker, and a nearby legal target strengthens its feedback.
- An ordinary move travels smoothly to its destination in approximately 180–240 ms.
- A capture coordinates a brief scale-and-fade removal with the moving piece's arrival and targets an overall duration of approximately 250 ms.
- An invalid drop returns the piece smoothly to its origin and gives the attempted destination brief feedback without an alert or forceful shake.
- A computer move uses the same move language and leaves persistent origin and destination markers so the player can identify the completed move.
- Check uses a persistent, non-color-only king-square treatment plus one brief pulse. It does not flash continuously.
- Undo visually reverses the affected move or decision cycle and restores a captured piece when needed. Board input and another Undo remain unavailable until the transition completes.
- Board flipping uses an approximately 300–400 ms coordinated re-layout while piece text and symbols remain upright.
- With Reduce Motion, lifts, springs, pulses, and long-distance travel are removed in favor of a brief crossfade or immediate state update.

The exact durations, easing curves, scale, shadow, opacity, and feedback strength are first-version values subject to adjustment after testing on physical iPhone, iPad, and Mac hardware. Liquid Glass belongs primarily to functional layers around the board; board-state markers must remain direct and readable rather than becoming translucent decoration.

## Sound and haptics

Sound and haptics are part of the intended experience. They must reinforce meaningful actions and game events, remain optional where platform conventions expect user control, and avoid being the only way information is conveyed.

## Accessibility

The interaction design must consider:

- VoiceOver and meaningful labels, values, actions, and reading order.
- Keyboard interaction and focus behavior where supported.
- Sufficient contrast and state cues that do not rely only on color.
- Dynamic Type and text legibility.
- Reduce Motion, Reduce Transparency, and other relevant platform settings.
- Alternatives for information otherwise communicated through sound, haptics, or animation.

## Localization

The interface must be designed for localization. User-facing text must not be embedded in visual assets, and layouts must tolerate different text lengths. Terminology for Xiangqi pieces, rules, results, and controls must be consistent within each supported language.

## Platform adaptation

- iOS should support touch-first play and compact layouts.
- iPadOS should use the available space without requiring a separate product model.
- macOS should support pointer and keyboard conventions while retaining the same game behavior.
- The application does not support multiple main windows.

## Need to discuss

> The items below are questions, not requirements or implementation authorization.

- Define the navigation presentation on each device class and window size.
- Define the visual system for the board, pieces, coordinates, colors, typography, and themes.
- Define the exact visual treatment for selection, legal destinations, captures, illegal-square feedback, and unavailable input.
- Define turn-status placement, symbols, exact computer-activity treatment, transient announcements, and VoiceOver behavior.
- Define the exact History-list layout and the detailed import, export, duplicate, conflict, and delete confirmations and error flows.
- Define the insufficient-memory notice copy, actions, presentation, repeated-failure behavior, and accessibility announcement.
- Define the scope, placement, and teaching sequence of help content.
- Refine first-version motion timings, easing, interruption behavior, and feedback strength through physical-device testing.
- Define sound events, sound design, volume or mute controls, and platform differences.
- Define haptic events and behavior on devices without haptic support.
- Define accessibility acceptance criteria and the board’s VoiceOver interaction model.
- Define supported languages, Xiangqi terminology, and localization review.
- Define how Liquid Glass behaves with contrast, Reduce Transparency, and different platform appearances.
- Define empty, loading, AI-thinking, error, corrupted-import, and destructive-action states.
