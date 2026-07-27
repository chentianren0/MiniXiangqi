# Interaction Design

This document is for product designers, UI engineers, accessibility reviewers, artists, audio designers, and testers who shape or evaluate the Mini Xiangqi experience. It owns UI and UX behavior, navigation, platform visual language, board presentation, help, animation and motion, visual effects, sound, haptics, accessibility, localization, and platform adaptation. It does not own product feature scope, Xiangqi rules, persistence formats, engine behavior, implementation progress, or scheduling.

> **Status: Living target-MVP interaction contract**
>
> Sections outside **Need to discuss** describe accepted intended interaction direction. They do not imply that the experience has been implemented. **Need to discuss** is explicitly non-normative. Progress and delivery work belong in GitHub Issues, not in this document.

## Experience goals

- Make the board and current game state immediately understandable.
- Keep primary play actions easy to reach without obscuring the board.
- Provide a coherent experience across iOS, iPadOS, macOS, and Windows while respecting each platform’s interaction conventions.
- Support learning through play: the interface should make legal moves, rules consequences, and results easy to understand for someone still learning Mini Xiangqi.
- Treat accessibility as part of the design, not as a later visual adjustment.

## Navigation

The primary destinations are:

- **Play** for starting or resuming a game.
- **History** for reviewing and managing history records.
- **Settings** for user preferences.

The navigation presentation must adapt appropriately to iPhone, iPad, Mac, and Windows. Platform adaptation may change presentation, but it must not create different product capabilities without an explicit product decision.

## Platform visual language

Each platform uses its own current native visual system rather than an imitation of another platform's.

- On Apple platforms, Liquid Glass is a required part of the visual and interaction direction. Use it for functional interface layers such as navigation, controls, toolbars, and contextual actions.
- On Windows, the WinUI 3 Fluent design system fills the same role: system materials, controls, and navigation patterns rather than recreated Apple styling.
- Preserve board readability and interaction clarity when translucent or material surfaces overlap or surround game content.
- Prefer platform-native behavior and adaptation over fixed imitations of one platform’s layout.
- Visual effects must not make controls, state, focus, or text harder to perceive.
- The board, pieces, and game-state markers form one shared visual identity across platforms; only the surrounding functional chrome is platform-specific.

## Board and game interaction

The board is the primary content during play. Its interaction design must cover:

- Color choice and the accepted board-orientation behavior below.
- Selection, legal destinations, the last move, check, and game result states.
- Move input, cancellation, repeated undo, and AI-thinking states.
- Clear prevention or explanation of unavailable actions.
- Replay controls and navigation through a history game.
- Help that explains both game concepts and interface behavior in context.

### Starting and configuring a game

- With no active game, selecting **Human versus AI** or **Free Play** opens that mode's pre-start state on the board page.
- With any active game, selecting either new mode immediately presents the one save-and-continue confirmation described below. This includes an ongoing game, a claimable but unclaimed neutral repetition, and an unconfirmed natural terminal result.
- Cancelling leaves the active game unchanged and does not enter the selected mode.
- **保存并继续** first archives the active game according to its factual current state, then opens the selected mode's pre-start state. It does not create the new game.

The human-versus-AI pre-start state is not an active game:

- It shows the initial board as a noninteractive preview and does not show a side-to-move status.
- A **本局设置** control group offers **我先手**, **AI 先手**, and **随机**, plus **AI 等级**.
- The controls are initialized afresh from the persistent Settings defaults whenever the page is entered.
- Their values exist only as an in-memory draft. They are not autosaved, do not change the Settings defaults, and are discarded as soon as the user leaves the page.
- **随机** remains unresolved and previews Red at the bottom. Successful game creation flips the board only if Random resolves to **AI 先手**.
- **快速**, **标准**, and **深思** identify maximum AI thinking times of approximately 1, 3, and 5 seconds per move. **标准** is the default on a new installation.
- **开始对局** creates no active game unless the required AI resources are available and the game can be persisted successfully. A Random first-mover choice is resolved only as part of successful game creation; if the resolved first mover is AI, search then begins.
- While creation is in progress, **开始对局** cannot be invoked again. Leaving invalidates the attempt, creates no game, and prevents a late completion from committing after the draft is discarded.
- Failed AI availability or active-game persistence keeps the page and draft available for retry, shows the applicable error, and re-enables **开始对局**. Leaving still discards the draft.

The Free Play pre-start state is also not an active game:

- It shows the same noninteractive initial-board preview with Red at the bottom and no side-to-move status.
- It explains **你将控制红黑双方，红方先行。**
- It shows **开始对局** without a **本局设置** group, side selector, AI controls, or pre-start board-flip control.
- **开始对局** commits the active Free Play game, makes the board interactive, and then shows the Red side-to-move status.
- While creation is in progress, **开始对局** cannot be invoked again. Leaving invalidates the attempt and prevents a late completion from creating a game.
- A creation failure retains the pre-start page, presents an error, and re-enables **开始对局**. It creates no new Free Play game or further persistent change; an older game already archived through **保存并继续** remains in History.

Settings has a **人机对弈默认设置** group with **默认先后手** and **默认 AI 等级**. Its footer explains that these values initialize future human-versus-AI setup and do not change an active game. A new installation selects **我先手** and **标准**.

### Board orientation

- In human-versus-AI play, the human player's side is displayed at the bottom. Choosing **我先手** previews and resolves Red; choosing **AI 先手** previews and resolves Black; choosing **随机** resolves the human side only when the game is created and then applies the corresponding orientation.
- In Free Play, Red is at the bottom by default. Once the game starts, a visible **Flip Board** control allows the player to change orientation at any time.
- Human-versus-AI history replay defaults to the original human player's perspective. Free Play and imported history default to Red at the bottom. History replay provides the same visible orientation control.
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
- iPhone and iPad use touch interaction. Mac and Windows support the equivalent click-to-move and pointer-drag behavior, and Windows touch devices support the touch interaction.
- Keyboard and VoiceOver use an equivalent select-piece, inspect-destinations, and select-destination flow rather than requiring a drag gesture.
- When input is unavailable, including while the AI is thinking or after a result is confirmed, the board rejects the interaction before visually moving a piece.

### Turn status

A persistent status element near the board is one coherent description of the current play state:

- Its primary line always identifies the side to move, using the localized equivalent of **轮到红方** or **轮到黑方**.
- In human-versus-AI play, a secondary label identifies that side's controller as **你** or **AI**. AI thinking is shown as activity attached to the AI's turn; it does not replace or compete with the side-to-move line.
- Free Play omits a human/AI controller label because the same person controls both sides.
- The design does not add a separate, unrelated instruction such as “please move” or “your turn.”
- Board input is accepted only when the committed game state permits the user to move. It is disabled while the AI is thinking.
- History replay uses a separate move-progress and playback state rather than describing the position as a human or AI turn.

Turn ownership, activity, and input availability must not be communicated by color alone. The element is driven by committed game and engine state, and a resolved Random side choice is visible in game metadata.

### Insufficient memory for AI play

- Before an AI engine is initialized, the app calculates the accepted Hash budget. A budget below 256 MiB does not start the AI opponent.
- The app presents a notice with:
  - Title: **无法启动 AI 对手**
  - Message: **当前可用内存不足。请尝试关闭一些其他 App，然后重试。**
  - Actions: **取消** and **重试**.
- **取消** dismisses the notice without creating or changing an active game. In pre-start setup, the in-memory draft remains while the user stays on that page.
- Retrying obtains a fresh value from the platform memory probe and recalculates the budget; the prior value is not cached.
- This low-memory path does not substitute a smaller Hash or perform a special automatic cleanup pass to manufacture the minimum budget.
- Any active game being resumed remains saved and unchanged while the AI opponent is unavailable.
- The notice may suggest closing other apps, but it does not promise that the operating system will terminate them or that a retry will succeed.

The notice's exact presentation, repeated-failure behavior, and accessibility announcement remain to be designed.

### Saving the active game before choosing a new mode

The Play destination shows the active game's metadata and a direct **Resume Game** action. The metadata identifies at least the mode, the human's side when applicable, and the move count. It shows the side to move for an ongoing game, the result and reason for a terminal game, and claim availability when applicable.

Both mode entries remain interactive whenever an active game exists. Selecting **Human versus AI** or **Free Play** temporarily remembers that destination in memory and immediately uses one fixed confirmation for every old-mode, new-mode, and active-game-state combination:

- Title: **开始新对局？**
- Metadata header: **当前对局**
- Message: **这盘对局将按当前状态保存到历史。**
- Actions: **取消** and **保存并继续**.

Only the metadata changes; the title, message, and actions do not interpolate mode-specific or state-specific wording. Example metadata lines include **人机对弈 · 你执红**, **自由对弈**, **进行中 · 轮到黑方 · 42 步**, **红方获胜 · 将死 · 42 步**, and **进行中 · 可判和 · 42 步**. The metadata reports facts and does not ask the user to classify the result.

**保存并继续** applies the classification automatically:

- An ordinary ongoing game is archived as ended early without a competitive result.
- A neutral threefold repetition that is only claimable and has not been claimed is still ongoing, so it is archived as ended early rather than as a draw.
- An unconfirmed natural terminal game keeps its actual winner or draw and its exact termination reason.

The confirmation does not add **悔棋** or **判和** actions. **取消** discards the temporarily selected destination and leaves the active game completely unchanged; the user can resume it and use the board's normal Undo or draw-claim controls.

Archiving and clearing the active game must commit atomically before navigation. On success, the selected mode's pre-start state opens, and no new game exists until **开始对局** succeeds. If the user leaves that pre-start state, the archived game remains in History and no active game is created.

If persistence fails, the old active game remains unchanged, the selected pre-start state does not open, and no new game is created. The exceptional error uses:

- Title: **无法保存对局**
- Message: **当前对局仍然保留。请重试。**
- Actions: **取消** and **重试**.

The requested destination remains temporary only while this confirmation or retry flow exists. Cancelling the error discards it; retrying repeats the same atomic archive operation.

### Undo and result confirmation

- Free Play removes one move per Undo action and can repeat back to the initial position.
- In human-versus-AI play, Undo while the AI is thinking cancels the search and removes the human move that triggered it.
- After the AI has replied, one Undo action removes the AI reply and the preceding human move, returning to the previous human decision point. The action can be repeated by complete decision cycles.
- If a human move itself reaches a natural terminal state, Undo removes that human move while the result presentation remains unconfirmed.
- If the AI moved first, its opening move alone cannot be undone.
- Redo is not available. A new move after Undo permanently replaces the discarded continuation.
- A natural result remains undoable while its result presentation awaits confirmation. Undo dismisses that presentation and resumes the game.
- After result confirmation, resignation confirmation, or **保存并继续**, the History record is immutable and cannot be undone.
- Undo is disabled at the earliest valid boundary and while a prior Undo transition is still being applied.

### Natural result presentation

- When a natural terminal result is reached, the final board remains fully visible and a non-dismissible result card appears near it.
- The card title is the localized equivalent of **红方获胜**, **黑方获胜**, or **和棋**. A second line explains the result reason. Human-versus-AI play may also show relevant player metadata without replacing the result.
- Before confirmation, the actions are **悔棋** and **结束对局**. Undo follows the mode-specific behavior above, dismisses the result card, and resumes the active game.
- The result card cannot be dismissed by tapping outside it. Resignation remains a separate confirmed action rather than being folded into the natural-result card.
- After **结束对局**, the final board remains visible, the record becomes immutable History, and the card changes to **已记录到历史**.
- The recorded state offers **回放**, which opens the newly created History record from its initial position, and **完成**, which returns to the Play start state.
- The target MVP does not add a Play Again action to this card.

### Claimable threefold repetition

- In both human-versus-AI play and Free Play, a neutral threefold repetition does not automatically end the game.
- When the draw first becomes available, the notice says **局面已三次重复，可以和棋结束。** and offers **继续对局** and **以和棋结束**.
- **以和棋结束** confirms an immutable draw record in History.
- After **继续对局**, the same still-valid claim is exposed through a non-blocking **可判和** affordance instead of repeatedly presenting the same blocking notice.

### History replay

- Replay entered from History or from the just-recorded result begins at the game's initial position.
- The board is read-only. Replay does not offer move input, Undo, or starting a new game from the displayed position.
- Controls provide jump to beginning, one move back, play or pause, one move forward, and jump to end.
- The move list highlights the currently displayed move and allows the user to jump to a selected move.
- The accepted history orientation and visible Flip Board control remain available.
- Pin, Share, and Delete are managed from the History list rather than from replay.
- Autoplay starts only after a user action and waits for each move animation to finish before advancing.
- Autoplay offers session-only speeds of 0.5×, 1×, and 2×. Manual move navigation, flipping the board, or the app moving to the background pauses playback. Playback stops at the final position.
- With Reduce Motion, replay uses the accepted crossfade or immediate board update while preserving the same order and playback controls.

### History library

- Pinned records appear before unpinned records. Each group orders the most recently recorded or imported first.
- Each entry shows its date, mode, result or end reason, and move count. Human-versus-AI entries also show the human side; imported records have a visible imported marker.
- Selecting an entry opens its read-only replay.
- Record content is read-only. Pinning changes only local library organization.
- A partial right-to-left swipe reveals icon-and-text actions on the trailing side. From left to right, they are blue **共享** and red **删除**, with Delete nearest the trailing edge.
- A complete right-to-left swipe invokes Delete.
- A left-to-right swipe reveals **置顶** or **取消置顶**. A complete swipe invokes that reversible action immediately.
- History has no Move action because the target MVP has no folders or tags.
- **共享** exports the selected History record as one game file.
- **删除前确认** is a Settings toggle and is enabled by default. When enabled, either the visible Delete action or a complete swipe presents:
  - Title: **删除这盘棋？**
  - Message: **删除后无法恢复。**
  - Actions: **取消** and **删除**.
- The record remains in the list until the user confirms. When **删除前确认** is disabled, either deletion gesture permanently deletes immediately.
- There is no deletion Undo and no Recently Deleted collection. If persistence fails, the record remains and the app presents an error.
- Import selects one game file at a time. A valid import creates an immutable History record and leaves the active game unchanged.
- An exact duplicate does not create a second record and offers a way to view the existing record. A stable-identity conflict with different game content is rejected with an explanation.
- Bulk deletion, search, filters, tags, and editing a History game are absent from the target MVP.
- Trackpad swipes use the same leading and trailing behavior where supported. Pointer context menus, keyboard commands, and screen-reader custom actions — VoiceOver on Apple platforms, Narrator on Windows — expose equivalent Pin or Unpin, Share, and Delete operations without adding permanent row buttons. On Windows, the context menu is the primary path to these actions.
- Action meaning is carried by icon and text as well as color.

The exact list layout, date and move-count formatting, file-picker presentation, import feedback, conflict feedback, and recoverable error copy remain to be designed.

## Help

Help is the target MVP's education surface and is deliberately small:

- Help is a read-only Mini Xiangqi rules reference covering the board, the pieces and their movement, check and checkmate, stalemate, repetition and the claimable draw, perpetual check, and perpetual chase, plus a short explanation of the app's own controls.
- Help is reachable from Settings and from the game screen without abandoning or pausing state: opening help never modifies the active game, and returning restores the exact prior context.
- Help content is static reference material. It does not analyze the current position, suggest moves, or offer interactive lessons or drills.
- Help text follows the same localization requirements as the rest of the interface.

The exact entry points, content organization, and illustrations remain to be designed.

## Motion and visual effects

Animation, motion, and visual effects are part of the intended experience. They must communicate state changes and preserve the user’s understanding of the position. Reduced-motion preferences and interruption behavior must be designed alongside the default experience.

The first implementation uses a restrained, tactile motion language:

- Selecting a piece uses a brief, approximately 120–160 ms lift, scale, and shadow transition without continuous movement.
- Empty legal destinations use a small dot; capturable destinations use a ring around the target piece. The two states differ by shape and do not rely on color alone.
- During a drag, the piece follows the pointer or touch, its origin retains a subtle marker, and a nearby legal target strengthens its feedback.
- An ordinary move travels smoothly to its destination in approximately 180–240 ms.
- A capture coordinates a brief scale-and-fade removal with the moving piece's arrival and targets an overall duration of approximately 250 ms.
- An invalid drop returns the piece smoothly to its origin and gives the attempted destination brief feedback without an alert or forceful shake.
- An AI move uses the same move language and leaves persistent origin and destination markers so the player can identify the completed move.
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
- Windows should follow WinUI 3 and Fluent conventions: pointer and keyboard first, native navigation patterns, context menus, and standard window behavior, with touch equivalents on touch-capable devices.
- Where a platform lacks an interaction idiom used elsewhere — for example, list swipe actions on Windows — the same operations must be exposed through that platform's conventional equivalents, such as context menus, hover controls, and keyboard commands, without changing product capabilities.
- The application does not support multiple main windows.

## Need to discuss

> The items below are questions, not requirements or implementation authorization.

- Define the navigation presentation on each device class and window size.
- Define the visual system for the board, pieces, coordinates, colors, typography, and themes.
- Define the exact visual treatment for selection, legal destinations, captures, illegal-square feedback, and unavailable input.
- Define turn-status placement, symbols, exact AI activity treatment, transient announcements, and VoiceOver behavior.
- Define the exact History-list layout, date and move-count formatting, and detailed import, duplicate, conflict, and error flows.
- Define the insufficient-memory notice presentation, repeated-failure behavior, and accessibility announcement.
- Define help entry points, content organization, and illustrations within the accepted read-only rules-reference scope.
- Refine first-version motion timings, easing, interruption behavior, and feedback strength through physical-device testing.
- Define sound events, sound design, volume or mute controls, and platform differences.
- Define haptic events and behavior on devices without haptic support.
- Define accessibility acceptance criteria and the board’s VoiceOver interaction model.
- Define supported languages, Xiangqi terminology, and localization review.
- Define how Liquid Glass behaves with contrast, Reduce Transparency, and different platform appearances.
- Define the Windows navigation presentation, Fluent material usage, accessibility equivalents (Narrator, high contrast), and touch behavior when Windows implementation begins.
- Define empty, loading, AI-thinking, error, corrupted-import, and destructive-action states.
