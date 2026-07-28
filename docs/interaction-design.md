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

- On Apple platforms, Liquid Glass is the required material for functional interface layers — navigation, controls, toolbars, and contextual actions — and is not used in the content layer. It is required *of* those layers rather than maximised across the app; Apple's own guidance is to use it sparingly, and the board is content.
- On Windows, the WinUI 3 Fluent design system fills the same role: system materials, controls, and navigation patterns rather than recreated Apple styling.
- Preserve board readability and interaction clarity where translucent or material surfaces surround game content. They surround it and never overlap it, per the boundary below.
- Prefer platform-native behavior and adaptation over fixed imitations of one platform’s layout.
- Visual effects must not make controls, state, focus, or text harder to perceive.
- The board, pieces, and game-state markers form one shared visual identity across platforms; only the surrounding functional chrome is platform-specific.

**Where glass may appear, exactly.** The app defines **three** custom glass surfaces: the play control cluster, the replay transport, and one shared slot for the natural-result card and the threefold-repetition notice, which never coexist. At most two are on screen at once, and **during ordinary play exactly one is** — ordinary play meaning an active game on the play screen with neither the result card nor the threefold notice presented, which is the state the app spends nearly all its time in. System-provided glass — the tab bar or sidebar, navigation bar and toolbar, alerts, sheets, context menus, and History swipe actions — is additional and automatic.

**Where it may not.** No glass surface may intersect the **board block**: the board core, which already includes the half-cell margin, together with the file-numeral strips. That is a rectangle a reviewer can measure against a screenshot rather than a principle they have to interpret. Nothing in the content layer takes glass — the board surface, grid, palace diagonals, numerals, discs, symbols, and every game-state marker are drawn directly. The board's own background is a flat fill rather than a system material, because a translucent board would let whatever is behind the window shift the colour a player reads a piece by.

**The AI-thinking indicator carries no material at all.** It is present for a large share of every human-versus-AI game, and a persistent glass surface beside the board would be exactly the "gratuitous" application the guidance warns against.

**No tinted glass appears during play.** Saturated colour on the play screen then means one thing: which side a piece belongs to. Tint is reserved for a moment with a single obvious next action — **开始对局** in either pre-start state, **结束对局** on the result card before confirmation, **完成** after it — and at most one tinted element is ever visible. Destructive actions use the system's destructive role rather than a red tint, so red keeps one meaning.

| Setting | System surfaces | The three custom surfaces |
|---|---|---|
| Reduce Transparency | automatic | replace the material with an opaque fill and a hairline separator |
| Increase Contrast | automatic | keep the material, raise the container's border |
| Both | automatic | opaque fill **and** the raised border |
| Dark appearance | automatic | no change; the material adapts |

In every row the geometry, corner radius, and spacing are unchanged, so nothing reflows: what changes is the surface's own material and border, never its position or size. Apple publishes no specification for how Liquid Glass renders under Reduce Transparency, so these are our values rather than a documented behaviour.

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

### Board metrics

Every board dimension is a multiple of the **cell pitch** `p`, the distance between two adjacent points. Nothing on the board is a fixed point value, so the board scales from its smallest supported size to a large window without any dimension being re-tuned and without the relationships between them changing. The accepted floor is `p ≥ 44 pt` on every interactive board, fixed under [Layout shapes](#layout-shapes) below. A pre-start preview is not interactive and carries no floor, so it shows no game-state markers and its symbol size is governed by legibility rather than by this system.

| Quantity | Value | At the floor |
|---|---|---|
| Cell pitch | `p` | 44 pt |
| Board core — 7 points plus a half-cell margin on each side | `7 p` square | 308 pt |
| Piece disc | Ø `0.80 p` | 35.2 pt |
| Piece symbol — character em, or icon bounding box | `0.50 p` | 22 pt |
| Marker band, as a radius from a point's centre | `0.42 p` to `0.50 p` | 18.5 to 22 pt |

Three rules govern the space around a point, and together they are what allow one marker vocabulary to work on every piece style, at every board size, without a per-case exception.

- **Style decoration stays inside the disc; markers stay outside it.** A piece style's own rings and edge strokes live at or inside `0.40 p`. On an occupied point, no game-state marker's ink falls inside `0.42 p` and none touches the disc face, measured against the disc at its largest — a selected disc is scaled, and the rule holds at that size too. The `0.02 p` air gap this leaves is what keeps a marker legible against 传统's heavier Black ring, 现代's white inset ring, and 高对比's outlined disc alike, and it is why the choice of characters or icons never affects a marker. Three markers are outside the rule because no disc is present to clear: the legal-destination dot and the drag-origin marker, which belong to empty points, and the pointer hover fill, which is drawn beneath the pieces.
- **Every marker stays inside its own cell.** A marker belonging to a point is contained within that point's `1 p` by `1 p` cell — for a circular marker, a radius of at most `0.50 p` — at rest and throughout every animation, including the selection lift and any strengthening during a drag. Markers on adjacent points therefore cannot collide, in any position, without the pairing having to be checked case by case. The accepted half-cell margin is the same `0.50 p`, so the outermost points' markers are contained by the margin and never reach the coordinates outside it. Where a marker would grow beyond the cell it grows inward instead. A dragged piece is the one exception, and only while it is dragged: it has detached from the grid and follows the touch or pointer across the board, so it belongs to no point and is drawn above everything.
- **Markers are never drawn in the Red or Black role colours**, which belong to the sides. Each style defines one **marker ink** per appearance, used at two strengths: **active ink**, at a contrast of at least 4.5:1, for selection, legal destinations, captures, check, and focus; and **record ink**, the same hue at reduced strength and at least 3:1, for the last move and the drag origin. Both are measured against that style's own board surface and against the pointer hover fill composited over it, since a marker may be drawn on either, and in both cases with shadows excluded. Increase Contrast promotes record ink to active-ink values. Because every game-state marker is carried by luminance and shape rather than by hue, the board under Differentiate Without Color is identical to the board without it; the keyboard focus ring, which carries hue, is a platform affordance and never a game state.

The exact marker-ink values belong to each style's colour work, as the piece-style requirements above do; the contrast figures are what those values must satisfy.

**The grid** is stroked at `0.026 p`, clamped to between 0.80 and 1.60 points — 1.14 points at the floor, reaching the ceiling from a pitch of about 62 points upward, so the lines never coarsen as the board grows. The lower bound binds only if a smaller pitch is ever accepted. The palace diagonals match it exactly, as the accepted geometry requires. Both reach at least 3:1 against the style's own board surface. The grid is very close in weight to the finest game-state marker — the check ring is `0.025 p` against the grid's `0.026 p` — so the two are told apart by shape and by ink strength rather than by weight: markers are drawn in active or record ink and the grid is not.

**The outer boundary is a single line at grid weight.** Many physical boards double it; here there is no room, because the half-cell margin is fully committed to containing the outermost points' markers, and a second line inside it would sit within the marker band.

**The file numerals** occupy a strip above and below the board core, outside the half-cell margin, one strip per side. Each strip shows the numerals of the player it faces — Chinese for Red, Arabic for Black — and follows the board's orientation, so the numbers beside a player are always their own. Both strips appear together or not at all.

- Numeral size is `0.32 p`, rounded to the nearest point and clamped to between 13 and 20: 14 points at the floor.
- Strip height is `0.08 p + 0.887 s`, where `s` is that size, rounded to the nearest point: 16 points at the floor, giving a board block of 308 by 340 points there. The `0.08 p` term is clear space between the board's outer line and the tallest numeral, so no numeral ever encroaches on the half-cell margin the outermost points' markers occupy.
- The two numeral sets sit on a shared baseline, and measurement of the system font cascade on the pinned toolchain confirms their optical centres agree closely enough to need no per-set adjustment. They do **not** match in weight: at equal weight the Chinese numerals carry about a quarter more ink than the digits, because their advances are full-width. The Chinese numerals are therefore set **semibold** and the digits **bold**. The anchor matters as much as the relationship: at regular weight the single stroke of 一 measures about 1.02 points against a 1.14-point grid line, so the numeral labelling the board would be fainter than the lines it labels. A residual difference of about a tenth remains, which is below what a reader notices in two separated strips.
- Numerals reach at least **4.5:1** against the board surface, and 7:1 under Increase Contrast. They are text at 14 points at the floor, below the size at which a 3:1 ratio would suffice, so the record-ink gate that governs the last-move brackets does not apply to them.
- **The strips are hidden at accessibility text sizes.** They are the first thing to yield when type grows, because the stacked layout has the least room exactly then; the board keeps its floor and the chrome keeps its own. Hiding them returns 32 points of height at the floor. Whether that is enough for every supported device at the largest text sizes is settled by the layout bounds, not here. The cost is real and accepted: without the strips a reader cannot relate a move in the list to a file on the board without counting, which is a loss for the same user the larger type was for.

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
- Tapping an illegal board square does not move the piece or cancel the current selection. It provides the brief, non-blocking feedback defined under [Game-state markers](#game-state-markers).
- A legal move or an Undo whose immediate save fails does not happen: the board and game remain exactly at the pre-action state, brief non-blocking feedback distinct from illegal-move feedback indicates the change could not be saved, and the user may simply try again. There is no modal dialog and no accepted-but-unsaved change.
- When the failed save is the AI's reply, the game remains at the last committed position with the AI still to move, and the app requests a new AI move rather than asking the user to retry a move that is not theirs.
- A failed draw claim, resignation, or result confirmation uses the accepted **无法保存对局** retry presentation and leaves the game active and unchanged.
- Dragging a movable piece beyond the gesture threshold selects it and reveals its legal destinations. Dropping on a legal destination commits the move; dropping elsewhere returns the piece to its origin.
- iPhone and iPad use touch interaction. Mac and Windows support the equivalent click-to-move and pointer-drag behavior, and Windows touch devices support the touch interaction.
- Keyboard and VoiceOver use an equivalent select-piece, inspect-destinations, and select-destination flow rather than requiring a drag gesture.
- When input is unavailable, including while the AI is thinking or after a result is confirmed, the board rejects the interaction before visually moving a piece.

### Game-state markers

The board shows the position and the states of the position, and nothing else. Anything the interface must say that is not a fact about the position — that a save failed, that input is unavailable right now — is said by the turn-status element instead, so the board is never read for two kinds of information at once.

Game states use four shape families, and no state borrows another's geometry: **small circles at a point** for things about a point, **rings around a disc** for things about a piece, **corner marks on a cell** for the last move, and **the turn-status element** for things about the game. Within each family every member has a distinct shape — filled against hollow, solid against dashed, single against double — so no two game states are confusable at any supported size, on any piece style, in either appearance, with either symbol set. The pointer hover fill and the keyboard focus ring sit outside these families and are deliberately rectangular: they report where an input device is, never what the game is doing, and their shape is what says so.

All radii are measured from the point's centre. Strokes use rounded caps, except the capture ring's dashes, which use butt caps so that the specified gaps are the gaps a player actually sees.

- **Selected piece.** The disc lifts to ×1.05 and casts the lift shadow, and a solid ring is drawn around it: stroke `0.030 p`, centre-line radius `0.440 p`, active ink, attached to the piece so that it scales with the lift. Lift and shadow may not carry selection alone — shadows weaken under Increase Contrast, and a five per cent size change is not absolutely readable — so the ring is what makes the state certain.
- **Legal empty destination.** A filled dot, Ø `0.22 p`, active ink, centred on the point and covering the grid crossing. Deliberately small: a chariot on an open board offers a dozen of these at once, and at this size twelve dots read as an available path rather than as clutter.
- **Legal capture.** A dashed ring around the enemy disc: stroke `0.055 p`, outer edge exactly at the cell boundary `0.50 p`, twelve dashes of 18 degrees separated by 12-degree gaps. Fixing the dash count rather than a dash length keeps the pattern identical at every pitch. The target does not lift; only the piece the player holds lifts. Solid ring against dashed ring is the shape distinction the accepted piece-style requirement asks for, and in any case the two never appear on one disc — one rings the player's piece, the other an opponent's.
- **Last move.** Four L-shaped corner brackets on both the origin cell and the destination cell: arm `0.13 p`, stroke `0.045 p`, inset `0.05 p` from each cell corner, record ink. The inset keeps two adjacent cells' brackets visibly separate, which matters because a one-step move puts them side by side; the arm length is what keeps the brackets clear of a capture ring on their own cell. Angular where every other marker is circular, so they are unmistakable at any size. They always mark the move that produced the position on screen: an Undo moves them to the move that is now last rather than leaving them behind, replay moves them as it steps, and no brackets are shown at an initial position. The AI's move uses these same brackets rather than a second marker — there is only ever one last move, and whose it was is carried by the turn status and the accessibility announcement.
- **General in check.** A double ring around the checked general: two concentric solid rings of stroke `0.025 p` at centre-line radii `0.4325 p` and `0.4875 p`, active ink, shown whenever that side is in check and the general is not held. The pair pulses once in stroke weight as it appears and never again. A pulse in scale is not available here, because it would carry the outer ring out of the cell; and because the rings sit exactly on both structural limits at rest, the pulse thickens each ring to at most `0.0325 p` growing only into the gap between them, so neither `0.42 p` nor `0.50 p` is crossed and at least `0.015 p` of gap survives.
- **A held general in check.** The selection ring and the check rings occupy the same band and cannot both be drawn. While a checked general is held — selected or dragged — the check rings hide; they return the moment it is released, including when a drag is abandoned. During play a **将军** token in the turn status carries the state through that gap, so check is never invisible while the general is in the player's hand. In replay no piece is ever held, so the rings alone carry it there.
- **Illegal tap.** No board mark. With a piece selected, its legal-destination markers pulse once: the question a learner is asking is where this piece may go, and answering it teaches more than marking the rejected point. Under Reduce Motion they change state once instead of pulsing — a single step to a stronger appearance, held briefly and then restored — so the answer still arrives, without animation and without depending on haptics that a Mac does not have. With nothing selected, the turn status gives the acknowledgment beat described below. Either way the platform's lightest selection-weight feedback fires where the hardware provides it, never the warning pattern, and the selection is retained so that the correction is one tap away.
- **Dragged piece.** The disc detaches at ×1.10 with the strongest lift shadow and follows the touch or pointer directly. On touch platforms it is offset `0.5 p` above the touch point so that a fingertip never covers it; under a pointer there is no offset. The origin keeps a hollow dot — ring Ø `0.22 p`, stroke `0.045 p`, record ink — the vacated twin of the filled destination dot, unambiguous against it because an origin is never itself a legal destination. While the drag is within `0.45 p` of a legal point, that point strengthens: a destination dot grows to Ø `0.33 p`, a capture ring thickens to `0.07 p` inward from its fixed outer edge. Strengthening releases beyond `0.55 p`, and the hysteresis between the two distances prevents flicker along a cell boundary.
- **Pointer hover.** The point under the pointer takes a faint rounded-square fill, `0.90 p` square with a `0.12 p` corner radius, in marker ink at low opacity, drawn beneath the pieces. It reports where the pointer is, not what is legal.
- **Keyboard focus.** The focused point takes a rounded-square outline, `0.92 p` square with stroke `0.04 p` and a `0.14 p` corner radius, in the platform's focus colour. Its band runs `0.44 p` to `0.48 p`, so it clears even a selected disc at full lift and stays inside the cell. It is the one marker that carries hue, because matching the platform's own focus ring is worth more here than vocabulary purity, and its rectangular shape distinguishes it regardless. It is also the only marker permitted to cross another: it is a platform affordance drawn above the board, and it never carries game state by itself.

Two states deliberately have no board marker at all.

- **A failed save on the user's own action** — a move or an Undo — is reported by a transient capsule anchored to the turn-status element, reading **无法保存这一步，请重试。**, with the system warning pattern reserved for genuine failures. It is distinguished from illegal-tap feedback structurally — a different surface, a different shape, a different feedback pattern — rather than by inventing a second board mark. The board shows nothing because the position did not change. When the failed save is the AI's reply no capsule appears and the board shows nothing at all, because the retry is the app's to perform and not the user's, as Move input above requires. This capsule is for a single ply; a failed draw claim, resignation, or result confirmation uses the accepted **无法保存对局** retry presentation instead, because those end the game and require a decision rather than a notice.
- **Unavailable input** is answered by an acknowledgment beat on the turn-status element: its background rises to full emphasis and falls back, in opacity only, with no movement, plus the same lightest feedback as an illegal tap. The reason input is unavailable is always already on screen, so the beat points at it rather than repeating it. The board is never dimmed while the AI is thinking or after a result is confirmed: a board with nothing wrong with it should look like a board, and the pause while the AI thinks is exactly when a learner wants to study the position. In replay the board is a read-only document, and a tap on it does nothing at all — no beat and no feedback — because any response would imply an interactivity that deliberately does not exist there.

**Layering**, from the board upward: the style's board surface; the grid and palace diagonals; the pointer hover fill; last-move brackets; destination dots and the drag origin; resting discs with their style resting shadows; rings around resting discs; the held or dragged disc with its lift shadow and attached selection ring; the keyboard focus ring. Rings are drawn above resting discs so that no disc can clip one.

Because every marker is contained by its own cell, only markers on the *same* point can ever meet, and those cases are closed: a destination dot or a capture ring coexists with last-move brackets without touching them, since the brackets occupy the cell's corners and the rings pass through its edge midpoints; a capture ring never surrounds a checked general, because no position a player can reach offers a general as a legal capture target — one in which a general could be taken is already illegal; last-move brackets never fall on a checked general's cell, because the move that produced the position was the opponent's, so its origin is now empty and its destination holds the opponent's own piece; and a held general in check is resolved by the rule above.

### Turn status

A persistent status element near the board is one coherent description of the current play state:

- Its primary line always identifies the side to move, using the localized equivalent of **轮到红方** or **轮到黑方**.
- In human-versus-AI play, a secondary label identifies that side's controller as **你** or **AI**. AI thinking is shown as activity attached to the AI's turn; it does not replace or compete with the side-to-move line.
- Free Play omits a human/AI controller label because the same person controls both sides.
- While the side to move is in check, a **将军** token accompanies the side-to-move line for as long as that remains true. Replay has no side-to-move line and therefore no token; there the board's own check treatment carries it, which is sound because replay never holds a piece.
- The element carries the two transient board-state messages that are not facts about the position: the save-failure capsule, and the acknowledgment beat that answers input the game cannot accept. Both are defined under [Game-state markers](#game-state-markers). The placement of the persistent **可判和** affordance remains open below and is not settled by this.
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
- Empty legal destinations use a small dot; capturable destinations use a dashed ring around the target piece. The two states differ by shape and do not rely on color alone. Because a piece style may itself ring a disc, the capture ring must stay clearly distinguishable from any ring belonging to the piece style, in every style; the separation rule in [Board metrics](#board-metrics) is what guarantees it.
- During a drag, the piece follows the pointer or touch, its origin retains a subtle marker, and a nearby legal target strengthens its feedback.
- An ordinary move travels smoothly to its destination in approximately 180–240 ms.
- A capture coordinates a brief scale-and-fade removal with the moving piece's arrival and targets an overall duration of approximately 250 ms.
- An invalid drop returns the piece smoothly to its origin and gives the same brief feedback as an illegal tap, without an alert or forceful shake.
- An AI move uses the same move language and leaves persistent origin and destination markers so the player can identify the completed move.
- Check uses a non-color-only treatment on the checked general plus one brief pulse, defined under [Game-state markers](#game-state-markers). It does not flash continuously.
- Undo visually reverses the affected move or decision cycle and restores a captured piece when needed. Board input and another Undo remain unavailable until the transition completes, and a new action does not interrupt a running transition. Because repeated Undo is an accepted capability, an Undo transition must therefore complete within 250 ms for one ply and 600 ms for a decision cycle, so that walking a game back does not accumulate noticeable waiting.
- Board flipping uses an approximately 300–400 ms coordinated re-layout while piece text and symbols remain upright.
- With Reduce Motion, the animation of lifts, springs, pulses, and long-distance travel is removed in favor of a brief crossfade or immediate state update. The states themselves remain: a held piece still reads as raised, it simply arrives at that appearance without an animated transition.

**Move travel scales with distance, inside the accepted band.** A one-step move takes 180 ms; the seven distances a 7-by-7 board admits — one, two, the horse's leap, three, four, five, and six cells — take 180, 195, 200, 210, 220, 230, and 240 ms, following the square root of distance remapped onto the accepted band. Distance is the right variable because a chariot crossing the board and a general stepping one point are not the same event, but the mapping onto 180–240 is a chosen proportion rather than a derived one. What *is* derived is the constraint it must respect: an Undo of a decision cycle must complete within 600 ms, which two plies at 240 plus their overhead satisfy with room to spare.

**Board flipping takes 340 ms**, derived from the distance a corner piece travels and a velocity ceiling shared with move travel rather than chosen for feel.

**The AI's move has a floor, not a delay.** Its piece departs at the later of two instants: when the search returns, and 260 ms after the player's own move has finished animating, including the captured piece's removal where there is one — the arrival, not the tap that committed it, since the AI must not leave before the player's move has finished being shown. A search that takes a second or more is unaffected; only a near-instant reply waits, so the AI never appears to twitch rather than move. If the search has not returned within 500 ms of the player's move, the turn status shows AI activity; below that threshold nothing appears, because an indicator that flashes for a fifth of a second is noise.

**Interruption divides in two.** A *presentational* transition — a lift, a hover, a marker appearing — re-targets freely toward whatever the player just did. A *committing* transition — a move, a capture, an Undo — runs to completion, and input arriving during it is **discarded rather than queued**, so a player never watches a stack of actions replay. The accepted durations bound that wait to under half a second. Board flipping is the one action deferred rather than discarded: it changes nothing about the game, so it is applied when the running transition ends.

**Reduce Motion is one rule.** Anything that animates position, scale, or rotation becomes a crossfade of at most 120 ms; anything that animates opacity, colour, stroke weight, or shadow is unchanged, because none of those is motion; any spring that survives — one animating a non-motion property — loses its overshoot rather than its duration; and the order in which things happen is untouched. The check pulse is removed rather than converted, as the accepted rule requires of every pulse: check is a persistent treatment plus a pulse, so the double ring and the 将军 token still say everything the pulse said, and the rings simply arrive by crossfade. Removing it is the point — a repeating attention-grabbing animation is precisely what this setting exists to spare the people who enable it. Every state survives — a held piece still reads as raised, a checked general still carries its rings, the legal destinations still answer an illegal tap — they simply arrive without travel.

**Feedback that reports an event fires when the event completes**, within one frame of it: a move sounds when the piece lands, not when it lifts. **Feedback that answers a touch leads its animation** — selection, an illegal tap, refused input, and a failed save all respond at the touch rather than at the end of whatever is drawn in reply, because the touch is what the player is waiting to feel answered.

Easing curves, shadow, opacity, and feedback strength are first-version values subject to adjustment after testing on physical iPhone, iPad, and Mac hardware; the durations fixed above are accepted rather than provisional. The lift and drag scale factors are not among them: the marker geometry is derived from them, so changing one is a change to [Board metrics](#board-metrics). Board-state markers are drawn directly and never become translucent decoration; where Liquid Glass may appear is fixed under Platform visual language.

## Sound and haptics

Sound and haptics are part of the intended experience. They must reinforce meaningful actions and game events and must never be the only way information is conveyed.

Both are user-controllable through separate Settings toggles, per the Settings scope in [product.md](product.md). Haptics are available only where the hardware provides them; on a device without them the toggle is unavailable rather than silently ineffective, and no substitute effect is invented.

Haptic strength follows the meaning of the event, not its frequency. In particular, tapping an illegal square is a normal part of learning how the pieces move rather than a failure, so it uses the platform's lightest selection-weight feedback and never the system warning pattern. The warning pattern is reserved for genuine failures such as an action that could not be saved, and overusing it would both punish the learner and dilute its meaning. The two must remain distinguishable from each other, as their visual responses already are: an illegal tap answers on the board by strengthening the legal destinations, while a failed save appears only at the turn status.

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

The app follows the language the operating system selects for it and offers no interface-language control of its own, per the Settings scope in [product.md](product.md). On Apple platforms the system's per-app language setting is the place a user changes it; on Windows the app follows the system's language preference list.

The interface must be designed for localization. User-facing text must not be embedded in visual assets, and layouts must tolerate different text lengths. Terminology for Xiangqi pieces, rules, results, and controls must be consistent within each supported language.

Piece characters are game content and are excluded from localization, as defined under Piece representation. Their English names localize wherever they appear as text.

## Orientation and layout

### Orientation

- **iPhone runs in portrait only.** Apple's guidance permits an experience that runs in a single orientation, and relies on people simply trying both and settling on the one that works; the app therefore never asks the user to rotate the device and shows no message about orientation.
- **iPad supports every orientation**, because iPadOS expects an app to adapt to rotation and to being windowed at arbitrary sizes, and an app that declines rotation opts out of that behaviour.
- macOS has no orientation; the window's proportions select the layout in the same way a device orientation does.
- Locking iPhone to portrait has a cost worth naming: a user whose device is fixed in a mount, or whose grip or dexterity favours landscape, cannot compensate by rotating. The square board makes portrait the orientation that serves the game best, and the accessibility obligation is met through the input alternatives already accepted rather than through rotation.
- Windows devices that rotate follow the same width-driven layout rules; the platform's orientation behaviour is settled when the Windows frontend is designed.

### Layout shapes

Two arrangements cover every device and window size, chosen by available width rather than by device identity, so a resized Mac window and a multitasking iPad behave the same way as each other.

- **Stacked**, used by iPhone portrait and by narrow windows including iPad portrait: turn status above the board, play controls below it, and the board centred between them.
- **Side by side**, used by iPad landscape, wide iPad window sizes, and ordinary Mac windows: the board on one side with a panel beside it carrying the turn status, the move list, game metadata, and controls that do not need to sit under the thumb.

The board is square and is sized to the largest square fitting **both** the available width and the height left after the surrounding chrome, so it never overflows a short window. Within that, a point of the grid is never smaller than 44 points on **every** platform. On iOS and iPadOS that is the platform's default control size. macOS shares it rather than taking the smaller figure a pointer would allow, because the marker vocabulary in [Board metrics](#board-metrics) has one worst case instead of two, and because its finest distinctions — the air gap between a disc and its markers, and the gap between the two check rings — are fractions of a point at a smaller pitch.

That floor is affordable on the most constrained configuration measured so far. A built-in Retina display running at 1024 by 663 points — the largest-text setting on a current Mac — leaves a window of 1024 by 582 points once the menu bar and the Dock are subtracted, and 550 points of content height below a standard title bar. At the 44-point floor the board core is 308 points square, so more than 200 points of height remain for the turn status, the controls, the file numerals, and their spacing. The exact minimum window follows from the chrome inventory that remains open below and must fit this budget; verifying that it does, on this configuration and on the smallest display any tester actually uses, is a required check rather than an assumption.

When space is short the surrounding chrome tightens before the board does. That preference has a floor: the board may not be driven below the sizes above, and neither may the chrome be driven below what its own controls require. Each platform therefore defines a minimum window size that keeps both above their floors, and the window stops resizing there rather than either becoming unusable.

One exception: a pre-start board is a noninteractive preview with no touch targets, so it carries no size floor and yields space to the setup controls whenever they need it. The floor exists to protect interaction, and a preview has none to protect.

Navigation uses one adaptive container, presenting as a tab bar at narrow widths and as a sidebar at wide ones. It follows the same width-driven rule as the layout shapes rather than device identity, so an iPad in a narrow window gets the same navigation as an iPhone.

### The move list during play

- Where the side-by-side layout applies, the move list is permanently visible in the panel.
- In the stacked layout during ordinary play it is not shown by default and is reached on demand, so neither the board nor the controls give up space to something consulted occasionally.
- Replay is the exception: its accepted behaviour requires the move list to highlight the current move and to allow jumping to a selected one, so replay in the stacked layout shows the move list rather than hiding it, and the surrounding chrome is what tightens to make room.

### Captured pieces

Captured pieces are not displayed. Each side begins with twelve pieces, so what remains on the board is directly countable at a glance and a separate captured display would restate visible information while competing with the board for space.

## Platform adaptation

- iOS should support touch-first play, in the layout shapes accepted above.
- iPadOS should use the available space without requiring a separate product model, through those same shapes.
- macOS should support pointer and keyboard conventions while retaining the same game behavior.
- Windows should follow WinUI 3 and Fluent conventions: pointer and keyboard first, native navigation patterns, context menus, and standard window behavior, with touch equivalents on touch-capable devices.
- Where a platform lacks an interaction idiom used elsewhere — for example, list swipe actions on Windows — the same operations must be exposed through that platform's conventional equivalents, such as context menus, hover controls, and keyboard commands, without changing product capabilities.
- The application does not support multiple main windows.

## Need to discuss

> The items below are questions, not requirements or implementation authorization.

- Define the exact widths at which the layout shape and the navigation presentation change, whether the navigation offers the user a switch between tab bar and sidebar where the platform supports one, and how the on-demand move list is presented in the stacked layout.
- Fix the minimum window size for macOS and for iPadOS windowing, which the board and chrome floors together determine, and name the narrowest supported iPhone the stacked layout is verified against.
- Resolve how the non-dismissible result card, the retained draw-claim affordance, and accessibility text sizes fit the stacked layout's remaining space, given that the card requires the board to stay visible and the chrome has its own floor.
- Define what the side-by-side panel contains beyond the turn status, move list, game metadata, and controls, how that metadata relates to the Play destination's own active-game metadata, and what the stacked layout does with the controls that panel would otherwise hold.
- Fix each piece style's concrete values — role colours and disc fills, ring weights, grid stroke, its own board surface, and its marker ink at both accepted strengths — within the constraints the accepted styles and board metrics impose.
- Design the icon set, and decide whether it is drawn for this project or adopted from an existing freely licensed international set.
- Define how traditional notation renders the cases this contract leaves open, including three or more same-type pieces sharing a file, which the five sideways-capable soldiers make reachable.
- Decide what a user reading icon symbols is offered for the move list, which remains character-based, and approve the table of positions and expected move strings that serves as the notation's test oracle.
- Define board themes beyond the three accepted piece styles, if any are wanted.
- Decide whether a pointer previews a piece's legal destinations on hover, before any selection. It would teach, and it sits directly beside the accepted exclusion of move hints and analysis, so it is a scope question rather than a visual one.
- Define the turn status's exact AI activity treatment, the 将军 token's form, remaining transient announcements, and VoiceOver behavior, and its placement within the side-by-side panel.
- Define the exact History-list layout, date and move-count formatting, and detailed import, duplicate, conflict, and error flows.
- Define the insufficient-memory notice presentation, repeated-failure behavior, and accessibility announcement.
- Define what a player sees when the engine cannot be re-prepared mid-game, after the app was suspended and the AI is due to move. The accepted **无法启动 AI 对手** notice assumes a game that has not started, so neither its wording nor its **取消** action fits; the game itself remains active, saved, and resumable throughout.
- Define help entry points, content organization, and illustrations within the accepted read-only rules-reference scope.
- Confirm the accepted motion timings and the compose-beat floor on physical iPhone, iPad, and Mac hardware, and refine easing and feedback strength there. A change to an accepted duration is a contract change rather than a tuning pass.
- Confirm the numeral-strip measurements on iOS and iPadOS, which were taken on macOS, and define the exact accessibility text size at which the strips are hidden.
- Define the sound events, sound design, and platform differences behind the accepted sound toggle.
- Define the haptic events behind the accepted haptics toggle.
- Define accessibility acceptance criteria and the board’s VoiceOver interaction model.
- Approve the English counterparts of every accepted Chinese string in this document. The accepted copy is Chinese and exact; no English equivalent has been approved, so an English build is not yet fully specified.
- Define the English Xiangqi terminology beyond the accepted piece names, and the localization review process.
- Decide whether the piece-style and piece-symbol names are user-facing interface strings or internal design names, and approve their wording if they are user-facing.
- Define the Windows navigation presentation, Fluent material usage, accessibility equivalents (Narrator, high contrast), and touch behavior when Windows implementation begins.
- Define empty, loading, AI-thinking, error, corrupted-import, and destructive-action states.
