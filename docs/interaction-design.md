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

## Piece representation

Xiangqi pieces are Chinese characters, and this is a teaching application, so the board presents the real characters rather than a translated substitute.

- The accepted piece characters give every piece type a distinct Red and Black form, so wherever the characters are shown the sides are distinguishable by glyph rather than by colour alone:

  | Piece | Red | Black |
  |---|---|---|
  | General | 帅 | 将 |
  | Chariot | 俥 | 车 |
  | Horse | 傌 | 马 |
  | Cannon | 炮 | 砲 |
  | Soldier | 兵 | 卒 |

  Mini Xiangqi has no advisors or elephants, so no characters are defined for them.
- With Chinese characters selected, four pairs differ in whole shape. The cannon pair differs only in its radical, 火 against 石, so it is the weakest of the five at board size and the piece style must carry additional non-colour distinction for it. 砲 is chosen over the equally attested 包 because it is the classical counterpart to 炮 and is the form the normative source itself uses in prose, though that source's summary table gives 包.
- Piece characters are game content, not interface text: they are identical in every supported language and are never translated on the board.
- On macOS every one of these characters resolves through the system font to a single Chinese family, at the matching weight from regular through heavy, with a uniform advance width — so pieces render at one consistent size without per-character adjustment. The equivalent confirmation on iOS and iPadOS is a required device check.
- When the icon symbol set is selected, both sides show the same symbol, so the symbol no longer distinguishes them and the piece style becomes the only non-colour carrier of side. Every accepted style must therefore satisfy the requirement below on its own, without help from the symbols.
- English piece names are General, Chariot, Horse, Cannon, and Soldier. They appear in help, accessibility announcements, and any descriptive text, never as board labels.

### Piece styles

The user chooses among three accepted piece styles, since a learner and an experienced player want different things from the same board. A style is a Settings preference and changes presentation only, never game content, archives, or the canonical notation.

A style covers the disc, its resting shadow, and **the board surface beneath it**, so each is one coherent look rather than pieces borrowed onto an unrelated board. What is drawn *on* the disc is the separate piece-symbols choice below, and every symbol set must work with every style.

- **传统** — the default. Both sides use the same warm light disc face, as a physical set does, with the symbols themselves in the Red and Black role colours. The Black disc additionally carries a heavier ring, so a second non-colour channel is always present. A soft resting shadow seats the disc on a warm low-chroma board surface.
- **现代** — each disc is filled with a single strong colour, Red or Black, with a white ring inset within the disc and the symbol in white. It is flat, with no resting shadow, on a clean neutral board surface.
- **高对比** — Red is a filled disc with the symbol reversed out of it; Black is an outlined disc on a neutral face with a heavier ring. Structure and luminance carry the side as strongly as possible, for low-vision use. It is flat, so edges stay crisp, on a board surface tuned for maximum separation from both discs.

Each style therefore defines its own resting shadow, and there is no separate shadow setting. A resting shadow is presentation only: no style may rely on it to satisfy a contrast requirement, every requirement below must hold with the shadow removed, and resting shadows are reduced under Increase Contrast.

The lift shadow is different in kind and belongs to the motion language rather than to a style. A piece raised by selection or drag casts a larger, softer shadow in every style, because it communicates that the piece is held; it is never suppressed by a style choice, and Reduce Motion substitutes an immediate change for the animated lift rather than removing the state.

Every style must satisfy these, verifiable rather than aesthetic. They must hold **jointly**, not one at a time.

- **The sides stay distinguishable when hue is removed.** Each style names the channel that carries the side once the symbols no longer do, which is the case whenever icon symbols are selected, and that channel is structural or luminance-based rather than hue-based:
  - by disc fill, in 现代 — the two fills reach at least 3:1 against each other;
  - by ring weight, in 传统 — the heavier ring is at least twice the width of the lighter, and each ring reaches at least 3:1 against its own disc face;
  - by construction, in 高对比 — filled against outlined is itself structural and needs no further threshold.
- **The symbol reaches at least 4.5:1 against its own disc face**, whether it is a character or an icon.
- **The disc's boundary — its ring or edge stroke — reaches at least 3:1 against the style's own board surface**, measured against that base surface rather than against a grid line, and at a point away from any board marking. The requirement is on the boundary rather than on the fill: a light disc on a light board is a legitimate traditional look, and what separates it is its edge.
- All of the above hold with resting shadows removed, in light and dark appearance, under Increase Contrast, and with either symbol set selected.

These requirements constrain each other, and 现代 is the tight case: a white symbol needs a fill dark enough to reach 4.5:1, while the two fills must still differ by 3:1. Together those bound the Red fill within a narrow luminance band and force the Black fill very dark, so the Red must be somewhat lighter than the deep red of a physical set. Because the style's white inset ring, not its fill, is what separates the piece from the board, the style stays valid on a dark board as well as a light one.

The exact colour values, ring weights, and board surfaces are part of the open visual-system work; this section fixes the constraints they must satisfy, not the values.

### Piece symbols

What appears on the disc is chosen separately from the style, because the two are independent: a learner may want icons on the traditional board, or characters on the modern one. The symbols choice is a Settings preference, changes presentation only, and composes with every style.

- **汉字** — the default. The accepted Red and Black characters above.
- **图标** — a pictorial symbol per piece type, for readers who do not know the characters.

Icons replace the Latin-initial labels considered earlier. Initials are an arbitrary mapping that must itself be learned, they derive from chess pieces that do not move the same way, and they no longer match the app's own move notation now that it is traditional; a drawn horse explains itself.

- Both sides show the **same** icon for a piece type, so an icon never carries the side. Side distinction rests entirely on the piece style, exactly as it must whenever the symbols stop differing, and every style already carries that requirement.
- Icons are drawn to match the discs, grid, and markers rather than imported from an unrelated visual language. Established international Xiangqi symbol sets, several of which are freely licensed, are the reference for what reads well; adopting one directly is the fallback if a custom set cannot meet the readability requirement.
- Every icon is distinguishable from every other at the smallest supported board size. Chariot against cannon is the demanding pair, since both are long-range pieces with similar conventional forms, and the set is not acceptable until those two are unmistakable.
- Icons are game presentation, not interface text: they do not change with the interface language.

## Board geometry and notation

Mini Xiangqi is played on the intersections of a line grid, so a 7-by-7 board is 7-by-7 **points**: a 6-by-6 grid of cells with 49 intersections, the outer points sitting on the border lines. The board is never drawn as a checkerboard of squares, which would be wrong to anyone who knows the game and would teach a beginner the wrong mental model.

- Each palace is a 3-by-3 block of points. Its two diagonals are drawn corner point to corner point across that block, crossing at the palace centre, at the same stroke weight as the grid so the palace reads as part of the board rather than as decoration.
- There is no river: the grid is unbroken from rank 1 to rank 7. This is a distinguishing feature of the variant and is not replaced by a decorative band. Help calls it out.
- Starting points are not marked. On a 7-point board the traditional soldier and cannon ticks would sit adjacent to almost every intersection and compete with the legal-move and last-move markers, which carry live information, and the fixed starting position is visible at the start of every game anyway.
- The grid is square, and the board reserves a half-cell margin beyond the outer points so that edge discs are never clipped. Coordinates sit outside that margin.

### User-visible notation

The board edges and the move list use traditional Xiangqi notation, which is what Xiangqi instruction actually uses; a learner should be able to carry what they read here into any Xiangqi book, video, or lesson. This is presentation only: the canonical coordinate notation frozen in [xiangqi-rules.md](xiangqi-rules.md) remains what archives, fixtures, and the core interface store and exchange.

- Files are numbered from each player's own right, so the two sides number them in opposite directions. Red writes its numbers as Chinese numerals and Black as Arabic numerals, and that applies to every number in a move, not only to the file.
- A move names the piece, its file, a direction, and a value. The directions are 进 forward, 退 back, and 平 across. The piece is named by its own side's character form from the table above.
- For the chariot, cannon, soldier, and general, 进 and 退 are followed by the number of ranks moved, and 平 is followed by the destination file. For the horse, whose move is not along a line, the value after 进 or 退 is the destination file.
- When two pieces of the same type stand on one file, the move opens with 前 or 后 **before** the piece name and omits the file entirely — 前炮退二, not 炮前退二. 后 names the piece nearer its own side and 前 the one nearer the opponent, a sense that is relative to the moving side and therefore unaffected by which way the board is facing.
- File numbers are shown in the outer margin. Ranks carry no labels, as they do not on a Xiangqi board. Because the two sides number the files oppositely, the margin follows the board's orientation so that the numbering beside a player is always that player's own.
- A user who selects icon symbols still reads a character-based move list, since traditional notation names pieces by their characters. Whether that user is offered anything further is an open question below.

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
- A legal move or an Undo whose immediate save fails does not happen: the board and game remain exactly at the pre-action state, brief non-blocking feedback distinct from illegal-move feedback indicates the change could not be saved, and the user may simply try again. There is no modal dialog and no accepted-but-unsaved change.
- When the failed save is the AI's reply, the game remains at the last committed position with the AI still to move, and the app requests a new AI move rather than asking the user to retry a move that is not theirs.
- A failed draw claim, resignation, or result confirmation uses the accepted **无法保存对局** retry presentation and leaves the game active and unchanged.
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
- Empty legal destinations use a small dot; capturable destinations use a ring around the target piece. The two states differ by shape and do not rely on color alone. Because a piece style may itself ring a disc, the capture ring must stay clearly distinguishable from any ring belonging to the piece style, in every style.
- During a drag, the piece follows the pointer or touch, its origin retains a subtle marker, and a nearby legal target strengthens its feedback.
- An ordinary move travels smoothly to its destination in approximately 180–240 ms.
- A capture coordinates a brief scale-and-fade removal with the moving piece's arrival and targets an overall duration of approximately 250 ms.
- An invalid drop returns the piece smoothly to its origin and gives the attempted destination brief feedback without an alert or forceful shake.
- An AI move uses the same move language and leaves persistent origin and destination markers so the player can identify the completed move.
- Check uses a persistent, non-color-only king-square treatment plus one brief pulse. It does not flash continuously.
- Undo visually reverses the affected move or decision cycle and restores a captured piece when needed. Board input and another Undo remain unavailable until the transition completes, and a new action does not interrupt a running transition. Because repeated Undo is an accepted capability, an Undo transition must therefore complete within 250 ms for one ply and 600 ms for a decision cycle, so that walking a game back does not accumulate noticeable waiting.
- Board flipping uses an approximately 300–400 ms coordinated re-layout while piece text and symbols remain upright.
- With Reduce Motion, the animation of lifts, springs, pulses, and long-distance travel is removed in favor of a brief crossfade or immediate state update. The states themselves remain: a held piece still reads as raised, it simply arrives at that appearance without an animated transition.

The exact durations, easing curves, scale, shadow, opacity, and feedback strength are first-version values subject to adjustment after testing on physical iPhone, iPad, and Mac hardware. Liquid Glass belongs primarily to functional layers around the board; board-state markers must remain direct and readable rather than becoming translucent decoration.

## Sound and haptics

Sound and haptics are part of the intended experience. They must reinforce meaningful actions and game events and must never be the only way information is conveyed.

Both are user-controllable through separate Settings toggles, per the Settings scope in [product.md](product.md). Haptics are available only where the hardware provides them; on a device without them the toggle is unavailable rather than silently ineffective, and no substitute effect is invented.

Haptic strength follows the meaning of the event, not its frequency. In particular, tapping an illegal square is a normal part of learning how the pieces move rather than a failure, so it uses the platform's lightest selection-weight feedback and never the system warning pattern. The warning pattern is reserved for genuine failures such as an action that could not be saved, and overusing it would both punish the learner and dilute its meaning. The two must remain distinguishable from each other, as their visual feedback already is.

## Accessibility

The interaction design must consider:

- VoiceOver and meaningful labels, values, actions, and reading order.
- Keyboard interaction and focus behavior where supported.
- Sufficient contrast and state cues that do not rely only on color.
- Dynamic Type and text legibility.
- Reduce Motion, Reduce Transparency, and other relevant platform settings.
- Alternatives for information otherwise communicated through sound, haptics, or animation.

## Localization

The supported languages are Simplified Chinese and English. Simplified Chinese is the source language: the accepted user-facing copy in this document is normative, and its English counterparts are translations of it.

The interface must be designed for localization. User-facing text must not be embedded in visual assets, and layouts must tolerate different text lengths. Terminology for Xiangqi pieces, rules, results, and controls must be consistent within each supported language.

Piece characters are game content and are excluded from localization, as defined under Piece representation. Their English names localize wherever they appear as text.

## Orientation and layout

### Orientation

- **iPhone runs in portrait only.** Apple's guidance permits an experience that runs in a single orientation, and relies on people simply trying both and settling on the one that works; the app therefore never asks the user to rotate the device and shows no message about orientation.
- **iPad supports every orientation**, because iPadOS expects an app to adapt to rotation and to multitasking sizes, and a rotation-locked iPad app behaves poorly in Split View and Stage Manager.
- macOS has no orientation; the window's proportions select the layout in the same way a device orientation does.

### Layout shapes

Two arrangements cover every device and window size, chosen by available width rather than by device identity, so a resized Mac window and a multitasking iPad behave the same way as each other.

- **Stacked**, used by iPhone portrait and by narrow windows including iPad portrait: turn status above the board, play controls below it, and the board centred between them at the largest size the width allows.
- **Side by side**, used by iPad landscape, wide iPad multitasking sizes, and ordinary Mac windows: the board on one side with a panel beside it carrying the move list, game metadata, and controls that do not need to sit under the thumb.

The board is always square, and it is sized so that one point of the grid is never smaller than the platform's minimum touch target. On the narrowest supported iPhone the stacked layout still leaves the grid comfortably above that minimum, so the board is never the element that shrinks: when space is short, the surrounding chrome yields first.

Navigation uses one adaptive container across the three Apple platforms, presenting as a tab bar on iPhone and as a sidebar on iPad and Mac, rather than a separate navigation structure per device.

### The move list during play

- Where the side-by-side layout applies, the move list is permanently visible in the panel.
- In the stacked layout it is not shown by default and is reached on demand, so neither the board nor the controls give up space to something consulted occasionally.
- Replay presents the move list as already accepted, in whichever arrangement the current layout provides.

### Captured pieces

Captured pieces are not displayed. Each side begins with twelve pieces, so what remains on the board is directly countable at a glance and a separate captured display would restate visible information while competing with the board for space.

## Platform adaptation

- iOS should support touch-first play and compact layouts.
- iPadOS should use the available space without requiring a separate product model.
- macOS should support pointer and keyboard conventions while retaining the same game behavior.
- Windows should follow WinUI 3 and Fluent conventions: pointer and keyboard first, native navigation patterns, context menus, and standard window behavior, with touch equivalents on touch-capable devices.
- Where a platform lacks an interaction idiom used elsewhere — for example, list swipe actions on Windows — the same operations must be exposed through that platform's conventional equivalents, such as context menus, hover controls, and keyboard commands, without changing product capabilities.
- The application does not support multiple main windows.

## Need to discuss

> The items below are questions, not requirements or implementation authorization.

- Define the exact width at which the layout changes between stacked and side by side, the minimum macOS window size, and how the on-demand move list is presented in the stacked layout.
- Define what the side-by-side panel contains beyond the move list, game metadata, and controls, and what the stacked layout does with the controls that panel would otherwise hold.
- Fix each piece style's concrete values — role colours and disc fills, ring weights, grid stroke, and its own board surface — within the constraints the accepted styles impose.
- Design the icon set, and decide whether it is drawn for this project or adopted from an existing freely licensed international set.
- Define how traditional notation renders the cases this contract leaves open, including three or more same-type pieces sharing a file, which the five sideways-capable soldiers make reachable.
- Decide what a user reading icon symbols is offered for the move list, which remains character-based, and approve the table of positions and expected move strings that serves as the notation's test oracle.
- Decide whether file numbers may be hidden, and define the visual system for them and for typography.
- Define board themes beyond the three accepted piece styles, if any are wanted.
- Define the exact visual treatment for selection, legal destinations, captures, illegal-square feedback, save-failure feedback, and unavailable input.
- Define turn-status placement, symbols, exact AI activity treatment, transient announcements, and VoiceOver behavior.
- Define the exact History-list layout, date and move-count formatting, and detailed import, duplicate, conflict, and error flows.
- Define the insufficient-memory notice presentation, repeated-failure behavior, and accessibility announcement.
- Define help entry points, content organization, and illustrations within the accepted read-only rules-reference scope.
- Refine first-version motion timings, easing, interruption behavior, and feedback strength through physical-device testing.
- Define the sound events, sound design, and platform differences behind the accepted sound toggle.
- Define the haptic events behind the accepted haptics toggle.
- Define accessibility acceptance criteria and the board’s VoiceOver interaction model.
- Approve the English counterparts of every accepted Chinese string in this document. The accepted copy is Chinese and exact; no English equivalent has been approved, so an English build is not yet fully specified.
- Define the English Xiangqi terminology beyond the accepted piece names, and the localization review process.
- Decide whether the piece-style and piece-symbol names are user-facing interface strings or internal design names, and approve their wording if they are user-facing.
- Define how Liquid Glass behaves with contrast, Reduce Transparency, and different platform appearances.
- Define the Windows navigation presentation, Fluent material usage, accessibility equivalents (Narrator, high contrast), and touch behavior when Windows implementation begins.
- Define empty, loading, AI-thinking, error, corrupted-import, and destructive-action states.
