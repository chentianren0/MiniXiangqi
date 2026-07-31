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

**Play has pages of its own.** Its root is the [Play home](#the-play-home), where what to play is chosen; each mode's pre-start state and the board are pages over it, reached by choosing and left by a back control in the toolbar, which names the page it returns to as the platform's own does. Leaving the board for the home ends nothing — the game stays active and the home's own card is the way back into it — and it is how a player reaches the mode entries while a game is going. A launch with a game to resume opens **at the board**, not at the home: the accepted resume-at-launch behaviour is that the app opens where the player left it, and a home the player has to walk through is not that.

## Platform visual language

Each platform uses its own current native visual system rather than an imitation of another platform's.

- On Apple platforms, Liquid Glass is the required material for functional interface layers — navigation, controls, toolbars, and contextual actions — and is not used in the content layer. It is required *of* those layers rather than maximised across the app; Apple's own guidance is to use it sparingly, and the board is content.
- On Windows, the WinUI 3 Fluent design system fills the same role: system materials, controls, and navigation patterns rather than recreated Apple styling.
- Preserve board readability and interaction clarity where translucent or material surfaces surround game content. They surround it and never overlap it, per the boundary below.
- Prefer platform-native behavior and adaptation over fixed imitations of one platform’s layout.
- Visual effects must not make controls, state, focus, or text harder to perceive.
- The board, pieces, and game-state markers form one shared visual identity across platforms; only the surrounding functional chrome is platform-specific.

**Where glass may appear.** Custom glass belongs to the functional layer — the play controls, the result notice, and the replay transport — and is used sparingly rather than maximised. System-provided glass in the tab bar or sidebar, navigation bar and toolbar, alerts, sheets, context menus and History swipe actions is additional and automatic.

**Where it may not.** No **resident** surface may intersect the **board block**: the board core, which already includes the half-cell margin, together with the file-numeral strips. A **transient** surface may cover the board — a sheet the player asked for is expected to hide what is behind it while it is up, because they requested it and they dismiss it. The natural-result notice is a transient the player did not ask for, and it is dismissible for exactly that reason: it may stand in front of the board because the player can put it away, and the position it describes is underneath it undimmed the moment they do. Nothing in the content layer takes glass — the board surface, grid, palace diagonals, numerals, discs, symbols, and every game-state marker are drawn directly. The board's own background is a flat fill rather than a system material, because a translucent board would let whatever is behind the window shift the colour a player reads a piece by.

**Announcements and confirmations take different surfaces.** An announcement is the app's own: the result notice stands on custom glass over the board and can be put away, because it reports what has already happened and the player decides when to stop looking at it. A confirmation of a consequential act — the draw claim, **认输**, **保存并继续**, and the **无法保存对局** retry — is a system alert, presented wherever the platform puts one and blocking until it is answered, because the act itself does not happen until the player answers.

**The AI-thinking indicator carries no material at all.** It is present for a large share of every human-versus-AI game, and a persistent glass surface beside the board would be exactly the "gratuitous" application the guidance warns against.

**No tinted glass appears during play.** Saturated colour on the play screen then means one thing: which side a piece belongs to. Tint is reserved for a moment with a single obvious next action — **回到对局** on the Play home while a game is going, **开始对局** in either pre-start state, **结束对局** on the result notice before confirmation, the concluding action the play-control cluster carries once a finished game's notice is closed, **完成** after it — and at most one tinted element is ever visible. The mode entries are not among them: they are a list of things to choose between, and neither of them is the answer. A system alert's own default action is tinted by the platform and stands above the page, so the at-most-one rule is counted in the app's own layer and never through a modal. Destructive actions use the system's destructive role rather than a red tint, so red keeps one meaning.

| Setting | System surfaces | Custom glass surfaces |
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

The user chooses among three accepted piece styles, since a learner and an experienced player want different things from the same board. A style is a Settings preference and changes presentation only, never game content, archives, or the canonical notation. The three below are the contract the visual system is held to; the *control* that chooses among them is deferred until a second style is drawn, per the Settings scope in [product.md](product.md), and until then the board is 传统.

A style covers the disc, its resting shadow, and **the board surface beneath it**, so each is one coherent look rather than pieces borrowed onto an unrelated board. What is drawn *on* the disc is the separate piece-symbols choice below, and every symbol set must work with every style.

- **传统** — the default. Both sides use the same warm light disc face, as a physical set does, with the symbols themselves in the Red and Black role colours. The Black disc additionally carries a heavier ring, so a second non-colour channel is always present. A soft resting shadow seats the disc on a warm low-chroma board surface.
- **现代** — each disc is filled with a single strong colour, Red or Black, with a white ring inset within the disc and the symbol in white. It is flat, with no resting shadow, on a clean neutral board surface.
- **高对比度** — Red is a filled disc with the symbol reversed out of it; Black is an outlined disc on a neutral face with a heavier ring. Structure and luminance carry the side as strongly as possible, for low-vision use. It is flat, so edges stay crisp, on a board surface tuned for maximum separation from both discs.

Each style therefore defines its own resting shadow, and there is no separate shadow setting. A resting shadow is presentation only: no style may rely on it to satisfy a contrast requirement, every requirement below must hold with the shadow removed, and resting shadows are reduced under Increase Contrast.

The lift shadow is different in kind and belongs to the motion language rather than to a style. A piece raised by selection or drag casts a larger, softer shadow in every style, because it communicates that the piece is held; it is never suppressed by a style choice, and Reduce Motion substitutes an immediate change for the animated lift rather than removing the state.

Every style must satisfy these, verifiable rather than aesthetic. They must hold **jointly**, not one at a time.

- **The sides stay distinguishable when hue is removed.** Each style names the channel that carries the side once the symbols no longer do, which is the case whenever icon symbols are selected, and that channel is structural or luminance-based rather than hue-based:
  - by disc fill, in 现代 — the two fills reach at least 3:1 against each other;
  - by ring weight, in 传统 — the heavier ring is at least twice the width of the lighter, and each ring reaches at least 3:1 against its own disc face;
  - by construction, in 高对比度 — filled against outlined is itself structural and needs no further threshold.
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

**The set is drawn for this project. It is original work, and this repository owns it.** Adopting an existing set was weighed first, because the sentence above names adoption as the fallback and several international sets are freely licensed. The survey that decided it found the pool empty: the sets in the East-Asian pictorial language are swept into AGPLv3+ by a catch-all licence line that is demonstrably wrong for at least one of them — a set traceable to CC BY-SA 3.0 Commons art, relabelled twice on the way down — so they are better described as *provenance-unknown* than as copyleft; two more plausibly derive from proprietary commercial art; and one family fails the size gate outright. The one set that is both legally clean and legible is the culturally wrong one, and correcting it would have replaced most of its glyphs anyway. Drawing five icons is also the only option that can satisfy the *first* requirement above, which asks for icons drawn to our own discs, grid, and marker weights.

**The five, and what each depicts.** A general's helmet, front view: a domed cap with a crest, standing on a band that flares below it. A chariot as a two-wheeled war cart in side view: a canopy overhanging the cart bed, and one wheel emerging beneath it. A horse's head in profile. A cannon as a barrel on a plain wedge, its muzzle raised. A soldier as an arrowhead over a flared base.

**The separation rule, which is how the chariot-cannon gate is met rather than hoped for.** Three independent channels carry the pair, so it survives losing any one of them:

- **The wheel belongs to exactly one piece.** The chariot carries the only circle in the set and the cannon carries no wheel at all. Every surveyed set that wheels both pieces loses the pair at our symbol size, and every set that does not, holds it; the wheel-less cannon is an established variant of the convention rather than a departure from it.
- **The two envelopes differ in axis.** The cart is upright, the cannon is wide. An envelope is a property of the bounding box, so it survives being made small when internal detail does not.
- **The cannon is directional and the cart is not.** The cannon's mass sits at one end under a raised muzzle; the cart is drawn symmetric about its wheel, with no draw-pole, because a draw-pole would have made it directional too.

**Two rules of execution, from the same evidence.** Icons are **solid silhouettes, never outline art** — line work at the symbol size turns to a grey smudge, which is how the one outlined set in the survey failed the gate on execution rather than on concept. And **internal detail is at least 2 points at the smallest supported board size, or it is not drawn**: spokes, mane hatching, and an eye all fall below that, so the wheel has one hub and no spokes and the horse has neither eye nor mane. Each icon is a single ink with knocked-out holes, so it recolours to the piece's role colour exactly as a character does and the 4.5:1 symbol-contrast requirement above is satisfied the same way.

**The reference sets, credited as references.** pychess-variants' `2dintl` and `eventintl` and its janggi `intlblue` and `intlwooden`, and the `euro` set below, were studied for what reads well at a small size and for which forms the convention actually uses. No path, outline, or file from any of them is copied, traced, or derived from; what was taken is the knowledge that a horse head in profile is universal, that an arrowhead over a base is the most legible glyph there is, and that giving both long-range pieces a wheel is what kills the pair.

**The fallback, named.** If the drawn set cannot hold the gate, the recorded fallback is pychess-variants' `euro` set — upstream `euro_xiangqi_js` from Sebastian Pipping's `xiangqi-setup` — under **CC BY 4.0**, by **Jasmin Scharrer and Sebastian Pipping**. Invoking it obliges us to credit both authors by name, name the licence and link it, and state that the work was modified, since adopting it means stripping its baked-in disc and converting its light detail overlays into holes. It is recorded here as the one candidate that passes both gates; it is not what ships, and its forms — a crenellated tower for 车, a Latin cross on the general — are the reason.

## Board geometry and notation

Mini Xiangqi is played on the intersections of a line grid, so a 7-by-7 board is 7-by-7 **points**: a 6-by-6 grid of cells with 49 intersections, the outer points sitting on the border lines. The board is never drawn as a checkerboard of squares, which would be wrong to anyone who knows the game and would teach a beginner the wrong mental model.

- Each palace is a 3-by-3 block of points. Its two diagonals are drawn corner point to corner point across that block, crossing at the palace centre, at the same stroke weight as the grid so the palace reads as part of the board rather than as decoration.
- There is no river: the grid is unbroken from rank 1 to rank 7. This is a distinguishing feature of the variant and is not replaced by a decorative band. Help calls it out.
- Starting points are not marked. On a 7-point board the traditional soldier and cannon ticks would sit adjacent to almost every intersection and compete with the legal-move and last-move markers, which carry live information, and the fixed starting position is visible at the start of every game anyway.
- The grid is square, and the board reserves a half-cell margin beyond the outer points so that edge discs are never clipped. Coordinates sit outside that margin.

### Board metrics

Every board dimension is a multiple of the **cell pitch** `p`, the distance between two adjacent points, so the board scales from its smallest supported size to a large window without any dimension being re-tuned and without the relationships between them changing. The accepted floor is `p ≥ 44 pt` on every interactive board, fixed under [Layout shapes](#layout-shapes) below. A pre-start preview is not interactive and carries no floor.

The board core is `7 p` square: seven points, plus the half-cell margin on each side that keeps an edge disc from being clipped.

Three rules govern the space around a point. They are what allow one marker vocabulary to work on every piece style at every board size, and they are stated as relationships because relationships are what a reviewer can check.

- **Style decoration stays inside the disc; markers stay outside it.** On an occupied point, no game-state marker's ink touches the disc face, measured against the disc at its largest — a selected disc is scaled, and the rule holds at that size too. The air gap this leaves is what keeps a marker legible against 传统's heavier Black ring, 现代's white inset ring, and 高对比度's outlined disc alike, and it is why the choice of characters or icons never affects a marker. Three markers are outside the rule because no disc is present to clear: the legal-destination dot and the drag-origin marker, which belong to empty points, and the pointer hover fill, which is drawn beneath the pieces.
- **Every marker stays inside its own cell.** A marker belonging to a point is contained within that point's `1 p` by `1 p` cell, at rest and throughout every animation, including the selection lift and any strengthening during a drag. Markers on adjacent points therefore cannot collide, in any position, without the pairing having to be checked case by case. The accepted half-cell margin is the same distance, so the outermost points' markers are contained by the margin and never reach the coordinates outside it. Where a marker would grow beyond the cell it grows inward instead. A dragged piece is the one exception, and only while it is dragged: it has detached from the grid and follows the touch across the board, so it belongs to no point.
- **Markers are never drawn in the Red or Black role colours**, which belong to the sides. Each style defines one **marker ink** per appearance, used at two strengths: **active ink**, at a contrast of at least 4.5:1, for selection, legal destinations, captures, check, and focus; and **record ink**, the same hue at reduced strength and at least 3:1, for the last move and the drag origin. Both are measured against that style's own board surface and against the pointer hover fill composited over it, with shadows excluded. Increase Contrast promotes record ink to active-ink values. Because every game-state marker is carried by luminance and shape rather than by hue, the board under Differentiate Without Color is identical to the board without it; the keyboard focus ring, which carries hue, is a platform affordance and never a game state.

**The exact dimensions are not fixed here.** Disc diameter, symbol size, every stroke width and radius, the grid weight, and the numeral strips' geometry are settled against a rendered board on real hardware, within the rules above and the contrast gates they carry. Fixing them in prose before anyone has seen them produced numbers that were internally consistent and unverifiable, which is worse than an honest gap.

### User-visible notation

The board edges and the move list render in the notation the **记谱法** preference selects; this section defines traditional Xiangqi notation, and [WXF rendering](#wxf-rendering) below defines the alternative. **Where nobody has chosen, the default follows the interface language: the traditional rendering under 中文, the WXF rendering under English.** Traditional notation is what Xiangqi instruction in Chinese actually uses, and a learner reading the Chinese interface should be able to carry what they read here into any Xiangqi book, video, or lesson; a reader of the English interface is by definition the reader the WXF rendering is for — one who has learned the game in the international notation rather than in Chinese — and opening them on a list of characters they cannot read teaches neither notation. The rule is *Chinese, or else WXF*, stated that way round so that a third interface language arrives with its answer already given: somebody not reading Chinese is not reading a Chinese move list either. **It is a default and never a migration.** The 记谱法 preference overrides either, and a player who has chosen a reading keeps it whichever language they read the interface in, including where their choice is the other language's default. *(Owner decision, 2026-07-30, replacing this section's previous traditional-everywhere default; recorded in [issue #80](https://github.com/ppppvz/MiniXiangqi/issues/80).)* This is presentation only, whichever is selected: the canonical coordinate notation frozen in [xiangqi-rules.md](xiangqi-rules.md) remains what archives, fixtures, and the core interface store and exchange.

- Files are numbered from each player's own right, so the two sides number them in opposite directions. Red writes its numbers as Chinese numerals and Black as Arabic numerals, and that applies to every number in a move, not only to the file. One word stands outside the rule: the ordinal that numbers four or more on a file continues 前, 中 and 后 rather than counting anything, and is written in Chinese for both sides.
- A move names the piece, its file, a direction, and a value. The directions are 进 forward, 退 back, and 平 across. The piece is named by its own side's character form from the table above.
- For the chariot, cannon, soldier, and general, 进 and 退 are followed by the number of ranks moved, and 平 is followed by the destination file. For the horse, whose move is not along a line, the value after 进 or 退 is the destination file.
- When two pieces of the same type stand on one file, the move opens with 前 or 后 **before** the piece name and omits the file — 前炮退二, not 炮前退二 — except when a second file is doubled, the last rule below. 后 names the piece nearer its own side and 前 the one nearer the opponent, a sense that is relative to the moving side and therefore unaffected by which way the board is facing.
- Three of a type on one file take 前, 中, and 后; four or more are numbered from the front — 一兵, 二兵, and so on, in Chinese numerals for both sides, because the ordinal is the positional word continued past three rather than a number in the move: Black writes 一卒进1, not 1卒进1. Both open the move and omit the file exactly as the two-piece form does. Neither is a curiosity here: five sideways-capable soldiers a side make each reachable.
- When more than one of the mover's files carries two or more of the same type — reachable only for soldiers, as 2-2 or 3-2 — the leading word alone no longer says which piece moved, so the origin file returns after the piece name: 前兵六进一, 后卒3进1. Pieces alone on their file keep the plain form, and this can never combine with the numbered form, which needs four on a single file. Of the forms beyond the rulebook's own 前, 中 and 后 — the sport's rulebook stops at three — the numbered series follows the computer standard's explicit clause, and the returned file is this contract's reading of established practice rather than a transcription of a normative source, recorded as such the way [xiangqi-rules.md](xiangqi-rules.md) records its adjudication readings.
- File numbers are shown in the outer margin. Ranks carry no labels, as they do not on a Xiangqi board. Because the two sides number the files oppositely, the margin follows the board's orientation so that the numbering beside a player is always that player's own.
- Traditional notation names pieces by their characters, so a user who selects icon symbols still reads a character-based move list under this notation. What that user is offered instead is the WXF rendering below, selected independently of the symbols: an icon reader who wants a letter-and-digit list has one, and a character learner keeps this one whichever symbols the board draws.

### WXF rendering

The alternative the **记谱法** preference offers, for a reader who has learned Xiangqi in the international notation rather than in Chinese. It is presentation exactly as the traditional rendering is, and it identifies pieces exactly as the traditional rendering does — in the mover's own frame, with the front of a file the end nearer the opponent, and with the identification applied whenever more than one of a type stands on a file rather than only when a move would otherwise be ambiguous — so a player who changes the preference sees the same move identified the same way in different clothes.

- **The shape.** A move is `[piece][origin][direction][value]`, with no spaces. The pieces are **K, R, H, C and P** — general, chariot, horse, cannon and soldier — one letter per type for both sides alike. Files are numbered **1 to 7 from each player's own right, in Arabic numerals for both sides**, which is where this rendering parts company with the traditional one's Chinese numerals for Red. The directions are **`+` advance, `-` retreat (an ASCII hyphen), and `=` traverse**.
- **The value.** If the move stays on its file, the number of ranks moved; otherwise the destination file. Stated as geometry rather than as a list of piece types, it covers the traverse and the horse without naming either.
- **Two of a type on one file.** The file digit is replaced by **`+` for the front piece or `-` for the rear, written after the piece letter** — `R+=3`, `P-+1`. Applied whenever two stand on the file, whether or not the other piece could make the same move. Reachable for chariots, horses, cannons and soldiers alike.
- **Three to five on one file** — soldiers only, since no other type has more than two. The piece letter is replaced by **the piece's index on its own file, counted 1 from the front**, and the origin file is kept: `15=4`, `25=4`, `35=4`, `45=4`, `55=4`. No letter ever appears beside an index.
- **Two files each carrying two or more** — soldiers only, as 2-2 or 3-2, and two such files is this board's maximum. Every soldier on one of those files takes the indexed form, counting from **its own file's** front and keeping the origin file: `13=4` and `23=4` beside `17=6` and `27=6`. A pair is promoted to the indexed form because a bare marker no longer says which file moved. Soldiers not on such a file keep the plain form.
- **The frame.** Everything is relative to the mover; front means nearer the opponent; index 1 is the frontmost.
- **No event markers.** No capture, check, mate, or result marker ever: a capture renders exactly as the quiet move would, identical to the traditional rendering's behaviour. So `+` in a move is only ever a direction or a front marker.
- **The numeral strips follow the preference.** The strips exist so a player can map the move list to the board, so with WXF selected both edges render Arabic numerals and with 中文 selected they are as defined above. Each side still numbers from its own right: Red's edge changes script, and nothing changes direction. This holds of the language-resolved default exactly as it holds of a chosen preference, because the strips follow the preference's answer and never a rule of their own: an English first launch draws both edges in Arabic numerals beside its WXF list, and a Chinese one draws Red's in Chinese numerals beside its 中文 list.

Equivalently, as one condition: the indexed form whenever the type has three or more on the mover's file or two files carrying two or more; the marker form when exactly two stand on the file and it is the type's only doubled file; the plain form otherwise.

**There is no single WXF notation to transcribe, so the clauses above include recorded readings** in the same sense as the returned-file clause of the traditional rendering and as [xiangqi-rules.md](xiangqi-rules.md)'s adjudication readings. The federation's current rulebook and the federation's own long-standing notation page — the only WXF text that covers four and five on a file and two doubled files at all — contradict each other on marker order and on the traverse symbol, and the tandem cases have five mutually incompatible published readings. Two principles settled each choice: **one grammar**, whose four slots never migrate their meanings between clauses, and **the reader's WXF**, meaning that where the current rulebook stands alone against the federation's notation page, the computer standard, Wikipedia and both implementations, this contract follows the form the reader will have learned everywhere else. The readings, recorded:

1. **The marker follows the piece letter**, against the current rulebook's own marker-first examples, and with the notation page, the computer standard's explicit sentence on the point, Wikipedia and both implementations.
2. **`=` for the traverse**, from the current rulebook, against the notation page's dot — so the table takes its traverse symbol from one document and its tandem shapes from another, which their publisher never combined.
3. **The indexed forms at three or more and on doubled files**, generalising the rulebook's own three-soldier digits; the notation page's doubled `++`/`--` markers and the computer standard's cross-file letter series are both rejected as alien to every reader and implementation.
4. **The marker is unconditional**, on the rulebook's plain wording and on the traditional rendering's own behaviour, against one implementation's refinement of emitting it only where a move would otherwise be ambiguous, which no document authorises.
5. **The traverse value is the destination file**, implied by every example in every source and stated by none.
6. **Files 1 to 7.** Every source assumes nine files; the substitution to this board is this contract's.
7. **K and P against this interface's own prose**, which says General and Soldier. The letters are the standard's mnemonics, attested by both federation documents; G and S are attested by no WXF document and G collides with *guard* in the computer ecosystem's own set. Recorded as a tension and deliberately not reconciled: either substitution would break with every WXF-conformant reader and tool.

## Board and game interaction

The board is the primary content during play. Its interaction design must cover:

- Color choice and the accepted board-orientation behavior below.
- Selection, legal destinations, the last move, check, and game result states.
- Move input, cancellation, repeated undo, and AI-thinking states.
- Clear prevention or explanation of unavailable actions.
- Replay controls and navigation through a history game.
- Help that explains both game concepts and interface behavior in context.

### The Play home

**The Play destination's root is an independent page for choosing what to play, and there is no board anywhere on it.** *(Owner direction, 2026-07-30.)* It replaces the start state this section previously described — the mode entries standing over a noninteractive preview board — which is withdrawn. The reason is the owner's: what the player is doing on this page is choosing what to play, a preview of a board they have not chosen yet answers no question they are asking, and a page that is a chooser rather than a board is the one that can hold a second game later. Standard 9×10 Xiangqi is a recorded brainstorm rather than a decision (issue #34), and nothing here is built for it; what the home owes it is only that it would fit.

- **A game is a section, and its ways to play are the rows in it.** Mini Xiangqi's section offers **人机对弈** and **自由对弈**. Selecting either opens that mode's pre-start state. A second game, if there is ever one, is a second section beside this one rather than a rearrangement of it.
- **The section carries no header while there is one game.** A header naming the only game on a screen that is only that game labels the obvious; a second game is what would give the sections something to tell apart. This is the same rule the [History library](#history-library) applies to its own two sections, where a library with nothing pinned reads as one plain list.
- **With an active game the page also carries that game.** A **当前对局** card shows the accepted metadata line described under [Saving the active game before choosing a new mode](#saving-the-active-game-before-choosing-a-new-mode) — the same header, over the same line — and a prominent **回到对局** that opens the board on the game exactly as it was left. Every fact on the line is read from the game the core is holding and none of it is re-derived.
- **A game already filed is not an active game**, and the card does not describe one. Its record is immutable History and the active-game reference was cleared by the terminal commit that made it; what stands on the board afterwards is the result where it was reached, which is presentation. Leaving that board for the home lets it go.
- The mode entries remain interactive whenever a game is active, and selecting one presents the accepted confirmation rather than opening anything. That flow is defined in full below.

### Starting and configuring a game

- A game is created by **开始对局** and by nothing else. Neither mode's first move creates one, and an untouched board persists nothing.
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
- There are exactly two applicable errors, and they are different messages under different titles. Insufficient memory — including an allocation that failed at a sufficient budget — is the accepted **无法启动 AI 对手** notice below. A creation the store would not persist is **无法开始对局** / **保存这盘新对局时出错。请重试。**, with **取消** and **重试**; it cannot borrow the **无法保存对局** wording, whose message promises that the current game is unchanged, because there is no current game to keep.

The Free Play pre-start state is also not an active game:

- It shows the same noninteractive initial-board preview with Red at the bottom and no side-to-move status.
- It explains **你将控制红黑双方，红方先行。**
- It shows **开始对局** without a **本局设置** group, side selector, AI controls, or pre-start board-flip control.
- **开始对局** commits the active Free Play game, makes the board interactive, and then shows the Red side-to-move status.
- While creation is in progress, **开始对局** cannot be invoked again. Leaving invalidates the attempt and prevents a late completion from creating a game.
- A creation failure retains the pre-start page, presents an error, and re-enables **开始对局**. It creates no new Free Play game or further persistent change; an older game already archived through **保存并继续** remains in History.

Settings has a **人机对弈默认设置** group with **默认先后手** and **默认 AI 等级**. Its footer explains that these values initialize future human-versus-AI setup and do not change an active game. A new installation selects **我先手** and **标准**.

**Where the concluding actions go.** A finished game's **开始新对局** — on the play-control cluster and, as **保存并开始新对局**, on the result notice — files the game and opens **that game's own mode's pre-start state**. It does not deal the next game: with an opponent to choose, the side and the level are chosen for each game rather than inherited from the last one, and a pre-start page is not a confirmation standing between the press and the new game. **完成**, on the recorded notice, returns to the Play home, where what to play is chosen again.

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

Game states use four shape families, and no state borrows another's geometry: **small circles at a point** for things about a point, **rings around a disc** for things about a piece, **corner marks on a cell** for the last move, and **the turn-status element** for things about the game. Within each family every member has a distinct shape — filled against hollow, solid against dashed, single against double — so no two game states are confusable at any supported size, on any piece style, in either appearance, with either symbol set. The pointer hover fill and the keyboard focus ring sit outside these families and are deliberately rectangular: they report where an input device is, never what the game is doing.

- **Selected piece.** The disc lifts and casts the lift shadow, and a solid ring is drawn around it in active ink, attached to the piece. Lift and shadow may not carry selection alone — shadows weaken under Increase Contrast, and a small scale change is not absolutely readable — so the ring is what makes the state certain.
- **Legal empty destination.** A filled dot in active ink, centred on the point and covering the grid crossing. Deliberately small: a chariot on an open board offers a dozen of these at once, and they must read as an available path rather than as clutter.
- **Legal capture.** A dashed ring in active ink around the enemy disc, reaching the cell boundary. The target does not lift; only the piece the player holds lifts. Solid ring against dashed ring is the shape distinction the accepted piece-style requirement asks for, and in any case the two never appear on one disc — one rings the player's piece, the other an opponent's.
- **Last move.** Four L-shaped corner brackets in record ink on both the origin cell and the destination cell, inset from each cell corner so that two adjacent cells' brackets stay visibly separate — a one-step move puts them side by side. Angular where every other marker is circular, so they are unmistakable at any size. They always mark the move that produced the position on screen: an Undo moves them to the move that is now last, replay moves them as it steps, and no brackets appear at an initial position. The AI's move uses these same brackets rather than a second marker.
- **General in check.** A double ring in active ink around the checked general, shown whenever that side is in check and the general is not held. It pulses once as it appears and never again; the pulse animates stroke weight rather than scale, which would carry the ring out of its cell.
- **A held general in check.** The selection ring and the check rings occupy the same band and cannot both be drawn. While a checked general is held — selected or dragged — the check rings hide; they return the moment it is released, including when a drag is abandoned. During play a **将军** token in the turn status carries the state through that gap, so check is never invisible while the general is in the player's hand. In replay no piece is ever held, so the rings alone carry it there.
- **Illegal tap.** No board mark. With a piece selected, its legal-destination markers pulse once: the question a learner is asking is where this piece may go, and answering it teaches more than marking the rejected point. Under Reduce Motion they change state once instead of pulsing, so the answer still arrives without animation and without depending on haptics a Mac does not have. With nothing selected, the turn status gives the acknowledgment beat described below. Either way the platform's lightest selection-weight feedback fires where the hardware provides it, never the warning pattern, and the selection is retained.
- **Dragged piece.** The disc detaches, scales up with the strongest lift shadow, and follows the touch or pointer directly. On touch platforms it is offset above the touch point so that a fingertip never covers it; under a pointer there is no offset. The origin keeps a hollow dot in record ink — the vacated twin of the filled destination dot, unambiguous against it because an origin is never itself a legal destination. A legal point near the drag strengthens, and releases again as the drag moves away, with enough hysteresis between the two distances that it cannot flicker along a cell boundary.
- **Pointer hover.** The point under the pointer takes a faint rounded-square fill in marker ink at low opacity, drawn beneath the pieces. It reports where the pointer is, not what is legal. A hover never previews a piece's legal destinations: selection already answers that question in one click, and a preview offered before any selection sits at the edge of the hints and analysis the target MVP excludes.
- **Keyboard focus.** The focused point takes a rounded-square outline in the platform's focus colour, clearing even a selected disc at full lift and staying inside the cell. It is the one marker that carries hue, because matching the platform's own focus ring is worth more here than vocabulary purity, and its rectangular shape distinguishes it regardless. It is also the only marker permitted to cross another: it is a platform affordance drawn above the board, and it never carries game state by itself.

Two states deliberately have no board marker at all.

- **A failed save on the user's own action** — a move or an Undo — is reported by a transient capsule anchored to the turn-status element, reading **无法保存这一步，请重试。**, with the system warning pattern reserved for genuine failures. It is distinguished from illegal-tap feedback structurally — a different surface, a different shape, a different feedback pattern — rather than by inventing a second board mark. The board shows nothing because the position did not change. When the failed save is the AI's reply no capsule appears and the board shows nothing at all, because the retry is the app's to perform and not the user's. This capsule is for a single ply; a failed draw claim, resignation, or result confirmation uses the accepted **无法保存对局** retry presentation instead.
- **Unavailable input** is answered by an acknowledgment beat on the turn-status element: its background rises to full emphasis and falls back, in opacity only, with no movement, plus the same lightest feedback as an illegal tap. The reason input is unavailable is always already on screen, so the beat points at it rather than repeating it. The board is never dimmed while the AI is thinking or after a result is confirmed: a board with nothing wrong with it should look like a board, and the pause while the AI thinks is exactly when a learner wants to study the position. In replay the board is a read-only document, and a tap on it does nothing at all.

**Layering**, from the board upward: the style's board surface; the grid and palace diagonals; the pointer hover fill; last-move brackets; destination dots and the drag origin; resting discs with their style resting shadows; rings around resting discs; the held or dragged disc with its lift shadow and attached selection ring; the keyboard focus ring. Rings are drawn above resting discs so that no disc can clip one.

Because every marker is contained by its own cell, only markers on the *same* point can ever meet, and those cases are closed: a destination dot or a capture ring coexists with last-move brackets without touching them, since the brackets occupy the cell's corners and the rings pass through its edge midpoints; a capture ring never surrounds a checked general, because no position a player can reach offers a general as a legal capture target; last-move brackets never fall on a checked general's cell, because the move that produced the position was the opponent's, so its origin is now empty and its destination holds the opponent's own piece; and a held general in check is resolved by the rule above.

**The exact geometry is not fixed here** — stroke widths, radii, the dash pattern, the lift and drag scales, and the strengthening distances are settled against a rendered board, within the containment and air-gap rules above.

### Play controls

A small, calm cluster of controls sits together during play, so that it stays reachable under a thumb and never competes with the board for width. What bounds it is that judgement rather than a count: the controls must not crowd the screen or read strangely, which is settled against a rendered screen rather than fixed as a number in prose. The accepted compositions are:

- **Human versus AI** — **悔棋**, **判和**, **认输**. There is no board-flip control here: the accepted orientation behaviour already places the human's own side at the bottom, and moving one's own side to the top is disorienting rather than useful when the player controls one side.
- **Free Play** — **悔棋**, **判和**, **翻转棋盘**. It cannot resign, having no opponent to resign to, and it is the mode the accepted orientation behaviour gives a flip control.
- **Replay** — the transport controls and **翻转棋盘**. Replay offers no move input, so no play control applies.

While a game is finished there is no draw left to judge, so that slot carries the concluding action instead — **悔棋**, the concluding action, and **翻转棋盘** in Free Play — for as long as the game is finished.

**认输** presents a confirmation, since it ends the game against the player and cannot be undone:

- Title: **认输？**
- Message: **认输后本局将记为你落败。**
- Actions: **取消** and **认输**.

Confirming records a human loss and moves the game to immutable History. Cancelling changes nothing. Resignation stays a separate confirmed action and is never folded into the natural-result notice.

### Turn status

A persistent status element near the board is one coherent description of the current play state:

- Its primary line always identifies the side to move, using the localized equivalent of **轮到红方** or **轮到黑方**.
- In human-versus-AI play, a secondary label identifies that side's controller as **你** or **AI**. AI thinking is shown as activity attached to the AI's turn; it does not replace or compete with the side-to-move line. The controller label belongs to a turn and stops when the turn does: a finished game is nobody's to move, and the secondary line then carries the result's reason instead.
- **The AI activity slot is a small system activity indicator beside the AI controller label.** It appears only once a search has run long enough to be worth showing — an indicator that arrives and leaves inside a third of a second reads as a flicker rather than as thinking — it never replaces the side-to-move line, it carries no material at all, and it is gone when the reply lands. *(Issue #71 decision, 2026-07-30.)*
- The same slot carries the stalled state when the engine could not be prepared mid-game and the player answered **稍后**: **AI 暂时无法启动** with **重试** beside it. See [Insufficient memory for AI play](#insufficient-memory-for-ai-play).
- Free Play omits a human/AI controller label because the same person controls both sides.
- While the side to move is in check, a **将军** token accompanies the side-to-move line for as long as that remains true. Replay has no side-to-move line and therefore no token; there the board's own check treatment carries it, which is sound because replay never holds a piece.
- The element carries the two transient board-state messages that are not facts about the position: the save-failure capsule, and the acknowledgment beat that answers input the game cannot accept. Both are defined under [Game-state markers](#game-state-markers). In Free Play the element's **可判和** line is half of the standing draw-claim offer, alongside the enabled **判和** control; how the pair fits the stacked layout remains open below.
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

**Mid-game, the same situation keeps its name and gains a guarantee.** When the app returns from suspension owing a search and preparation fails, the alert keeps the title **无法启动 AI 对手** — the situation is the same one, memory is not available right now, and a second title would name a distinction the reader cannot act on — but its message adds the one thing the pre-start case has no need of: **当前可用内存不足。对局已保存，可以稍后继续。请尝试关闭一些其他 App，然后重试。** Its actions are **稍后** and **重试**, not **取消** and **重试**, because there is nothing to cancel. After **稍后** the stalled state lives where things about the game live — the turn status's AI activity slot, with an inline **重试** — and every retry re-probes fresh. Undo remains available throughout and is itself a way out: removing the human's last move returns the game to their decision point, where no search is owed and the stalled state has nothing left to be about. *(Issue #71 decision, 2026-07-30.)*

The notice's repeated-failure behavior beyond "every retry re-probes" and its accessibility announcement remain to be designed.

### Saving the active game before choosing a new mode

The [Play home](#the-play-home) shows the active game's metadata under a **当前对局** header and a direct **回到对局** action beside it. The metadata identifies at least the mode, the human's side when applicable, and the move count. It shows the side to move for an ongoing game, the result and reason for a terminal game, and claim availability when applicable. The three state classes are exclusive and each takes one shape: an ongoing game is **进行中** and whose turn it is; a claimable repetition is **进行中** and **可判和**, the standing offer taking the side-to-move slot; a terminal game is its result and the reason for it, in the same longer register the History row uses.

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

Archiving and clearing the active game must commit atomically before navigation. On success, the selected mode's pre-start state opens, and no new game exists until **开始对局** succeeds. If the user leaves that pre-start state, the archived game remains in History and no active game is created. The archive is the one operation on this path that is **not** driven from the UI thread — [core-interface.md](core-interface.md)'s threading contract keeps `mxq_store_archive_and_clear` outside the main-actor exception the active game's own commits run under — so the confirmation's answer is not the same instant as the archive's.

If persistence fails, the old active game remains unchanged, the selected pre-start state does not open, and no new game is created. The exceptional error uses:

- Title: **无法保存对局**
- Message: **当前对局仍然保留。请重试。**
- Actions: **取消** and **重试**.

The requested destination remains temporary only while this confirmation or retry flow exists. Cancelling the error discards it; retrying repeats the same atomic archive operation.

### Undo and result confirmation

- Free Play removes one move per Undo action and can repeat back to the initial position.
- In human-versus-AI play, Undo while the AI is thinking cancels the search and removes the human move that triggered it.
- After the AI has replied, one Undo action removes the AI reply and the preceding human move, returning to the previous human decision point. The action can be repeated by complete decision cycles. How many plies a decision is, is the core's answer and never a count taken above it.
- **A decision cycle rewinds as one gesture**: both discs travel back together in a single transition, and whatever either of them took reappears as they go. It is one action, so it is one travel and one arrival; drawn as two reversals in sequence it would be two, and the second would have to be stopped from being read as a separate Undo. Where the reply took the very piece that invited it, the two reversals share a square, and the restored piece belongs to the one carrying that piece home rather than to both.
- If a human move itself reaches a natural terminal state, Undo removes that human move while the result presentation remains unconfirmed.
- If the AI moved first, its opening move alone cannot be undone.
- Redo is not available. A new move after Undo permanently replaces the discarded continuation.
- A natural result remains undoable while its result presentation awaits confirmation. Undo dismisses that presentation and resumes the game.
- After result confirmation, resignation confirmation, or **保存并继续**, the History record is immutable and cannot be undone.
- Undo is disabled at the earliest valid boundary and while a prior Undo transition is still being applied.

### Natural result presentation

- When a natural terminal result is reached, a result notice appears in front of the board. Nothing else changes: the final board stays exactly as the last move left it, undimmed, with the notice the only thing added to it.
- The notice title is the localized equivalent of **红方获胜**, **黑方获胜**, or **和棋**. A second line explains the result reason. Human-versus-AI play may also show relevant player metadata without replacing the result.
- **Before confirmation, both actions save, and the default one only saves.** **保存** confirms the result, files the game in History, and leaves the board standing exactly at the result it reached. **保存并开始新对局** does that and resets the board in the same press. **保存** is the notice's default and the tinted one: when a game ends, keeping the game that was just played is wanted far more often than being dealt the next one, and a notice whose one prominent action clears the board away is a notice arguing with its own reader. *(Owner decision, 2026-07-29, from playing on it.)*
- **悔棋 is not on the notice.** It is a play control, and it stays in the play-control cluster, where it is available for exactly as long as the result is unconfirmed — including after the notice has been closed, because closing saves nothing. Offering one action in front of the board and again behind it taught nothing about either. Undo itself is unchanged: it follows the mode-specific behavior above, takes the notice with it, and resumes the active game. *(Owner decision, 2026-07-29.)*
- **保存 is the act this section used to call 结束对局.** Confirming the result and filing it is the same act under either name; the name changed because the notice now offers two actions that both file, and *ending the game* does not say which of them the reader is looking at. **结束对局** is retired as this notice's label.
- The notice is dismissible — by its own close control, by the platform's cancel key, or by a tap on the board — and it does not present itself again for the same result. Closing it decides nothing about the game: the result is still carried by the turn status, and the concluding action is still carried by the play-control cluster, where it holds the draw claim's slot for as long as the game is finished. The squares a result is worth studying are usually the ones a notice standing over the board would cover, which is why it can be put away.
- A terminal game whose notice was closed without concluding is still archived with its actual winner or draw and its exact termination reason by the save-and-continue flow above, so dismissing the notice never loses the record.
- Resignation remains a separate confirmed action rather than being folded into the natural-result notice.
- After **保存**, the final board remains visible, the record becomes immutable History, and the notice changes to **已记录到历史** where it stands. That is the whole of the change on screen: result, save, recorded, in one place, with the position that produced the result still under it.
- The recorded state offers **回放**, which opens the newly created History record from its initial position, and **完成**, which returns to the Play home.
- **A game already filed is never filed again.** A claimed draw arrives at its notice already recorded, and so does a result the player has saved; the concluding action on either of them resets the board and commits nothing further.
- The target MVP does not add a Play Again action to this notice.
- The play-control cluster's concluding action stays **开始新对局**, and no confirmation stands between it and the new game: it files the finished game and resets the board, which is exactly what the notice's second action does under a name that says so.
- On macOS the two actions sit side by side, with the default one trailing, where this platform puts a default action. **iOS keeps them side by side too**, which is what the stacked layout's arrival was to decide: photographed on an iPhone in both languages, **保存并开始新对局** and the longer English *Save and New Game* both sit beside **保存** without crowding the notice or reaching the screen's edges. The permission to stack them is therefore unused rather than withdrawn — it stands for a size that has not been met. *(Stage 6.)*

### Claimable threefold repetition

- In both human-versus-AI play and Free Play, a neutral threefold repetition does not automatically end the game.
- The claim is the player's to invoke. **判和** presents the blocking notice, which says **局面已三次重复，可以和棋结束。** and offers **继续对局** and **以和棋结束**.
- **以和棋结束** confirms an immutable draw record in History. Until History exists it presents the claimed draw through the result notice instead, without **悔棋**: the claim is the player's own confirmed act, and it is the one finish that cannot be walked back.
- After **继续对局**, the same still-valid claim is exposed through a non-blocking **可判和** affordance instead of repeatedly presenting the same blocking notice. In Free Play the standing offer is the enabled **判和** control together with the turn status's **可判和** line, and nothing blocks the board.
- **The notice never presents itself unbidden, in either mode.** It is the confirmation of the player's own act — **判和** — and a confirmation that presents itself inverts the accepted announcement/confirmation grammar under [Platform visual language](#platform-visual-language): announcements self-present and are dismissible; confirmations follow an act and block until answered. So human-versus-AI play uses exactly what Free Play already accepted — the enabled **判和** control and the turn status's **可判和** line — even though there the repetition can arrive on a move the player did not choose. One vocabulary across both modes, and the claim stays the player's to invoke. *(Issue #71 decision, 2026-07-30.)*
- Claiming while the AI is thinking is legal exactly when the core reports the claim available. Where it is, the search is cancelled before the terminal commit: a search outstanding over a game that has just ended answers to nothing.

### History replay

- Replay entered from History or from the just-recorded result begins at the game's initial position.
- The board is read-only. Replay does not offer move input, Undo, or starting a new game from the displayed position.
- Controls provide jump to beginning, one move back, play or pause, one move forward, and jump to end. They are icon-only and carry their words as accessibility labels: five labelled buttons do not fit beside a board, and a transport is the one place a glyph is the familiar form. The end controls take the media transport's own symbols and the single steps take chevrons, because a step is not a scan.
- The move list highlights the currently displayed move and allows the user to jump to a selected move. The highlight is a filled shape and a heavier weight, never colour alone.
- Replay shows the record's own metadata — the same line the History row carries — and its progress through the game as *shown ply / recorded plies*. That pair is the accepted separate move-progress and playback state; there is no side-to-move line, because a finished game is not anybody's turn.
- The accepted history orientation and visible Flip Board control remain available.
- Pin, Share, and Delete are managed from the History list rather than from replay.
- **A step travels; a jump cuts.** *(Owner decision, 2026-07-29.)* One ply forward or back is shown with the same distance-scaled travel a played move uses — a step back reverses it exactly as an Undo does, restoring what the move took — and its landing performs the same meaning-chosen sound a played landing performs, under the same single sound setting: a replayed landing is a landing, and gets no rule of its own. A jump of more than one ply, and a step asked for while one is still travelling, are presentational cuts instead — nobody asking for the twentieth position wants to watch nineteen moves go past — and a cut has no landing, so it is silent.
- Autoplay starts only after a user action and waits for each move animation to finish before advancing.
- **Autoplay runs at one speed.** The 0.5×/1×/2× set was accepted before a replay screen existed; a speed control is three more controls on a transport that has five already, plus a preference to carry, and nobody has yet watched a game back and wished it faster. The set is not withdrawn — it is deferred until someone wants it, and the transport has room for it. Manual move navigation, flipping the board, or the app moving to the background pauses playback. Playback stops at the final position.
- With Reduce Motion, replay uses the accepted crossfade or immediate board update while preserving the same order and playback controls.

### History library

- Pinned records appear before unpinned records. Each group orders the most recently recorded or imported first. **That order is the core's**, and the list never re-sorts it: the two groups are the pinned prefix of what the store returned and the rest of it.
- The two groups are **rendered as two sections**, **已置顶** and **其他对局**, rather than as a per-row pin badge. Pinned-ness is ordering rather than decoration, and rendering it as ordering keeps a glyph off a row that is already carrying five facts and gives pin and unpin a visible confirmation for free — the row moves between the sections, and a pin the store refused is a row that did not move. With nothing pinned there is one unheaded section and the list reads as a plain list of games.
- Each entry shows its date, mode, result or end reason, and move count. Human-versus-AI entries also show the human side; imported records have a visible imported marker.
- **The row is two lines.** The first is when the game ended. The second is the accepted metadata composition applied to a filed game — `模式 · [执子] · 结果 · [结束原因] · 步数` — which is the save-and-continue confirmation's own vocabulary rather than a second one invented here. The second line never truncates: every token in it is contract-required row content, so it wraps.
- Two segments are left out where the line would otherwise say one thing twice. **执子** is absent in Free Play, where the turn status omits a controller label for the same reason. **结束原因** is absent where the result word already carries it, which is exactly the ended-early record: `outcome = none` holds exactly when `end_reason = ended-early`, so the row shows **提前结束** in the result slot and says it once. A resignation keeps its reason, because **红方获胜** alone does not say whether the loser was mated or resigned.
- **The date is the game's own end**, in the reader's locale, calendar and time zone: the system's *today* or *yesterday* word plus the time for those two days, and a numeric date with a four-digit year plus the time otherwise. The time is always present, because it is what tells two games played on one day apart, and **no date or time pattern is ever written by the app** — whether the clock reads 14:32 or 2:32 PM belongs to the locale and to the reader's own system setting.
- **The move count is the integer, a space, and the unit** — `42 步`. It counts plies, which is what 步 means; the English *moves* takes the ordinary-English sense and Help owes the definition.
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
- The record remains in the list until the user confirms. When **删除前确认** is disabled, either deletion gesture permanently deletes immediately. **Every** Delete entry point is gated identically — the swipe action, the complete swipe, the context menu, and the screen-reader custom action — because they are the same operation and the confirmation is about the operation rather than about the gesture.
- There is no deletion Undo and no Recently Deleted collection. If persistence fails, the record remains and the app presents the same "could not do it, nothing changed, try again" alert the rest of the app uses: title **无法删除这盘棋**, message **这盘棋仍然保留在历史里。请重试。**, actions **取消** and **重试**.
- **A pin or unpin the store refuses is not an alert.** It is the accepted non-blocking treatment for a reversible, low-stakes action, and the two sections are what report it: the row does not move.
- **An empty History says so quietly** — **还没有历史对局**, with **对局结束后会保存到这里。** beneath it — and offers nothing else to do. A library that cannot be read says *that* instead, in the failure-screen family, rather than showing an empty list it has no evidence for.
- Import selects one game file at a time. A valid import creates an immutable History record and leaves the active game unchanged.
- An exact duplicate does not create a second record and offers a way to view the existing record. A stable-identity conflict with different game content is rejected with an explanation.
- **Import lives on this destination and nowhere else** — a toolbar item, **导入…** — because this is the screen the result lands on. The picker allows exactly one file and filters to the declared game type, which is where the one-file-at-a-time rule is kept rather than where it is enforced by refusal. The app reads the bytes inside the security scope the picker grants and keeps no bookmark and no reference afterwards, which is the right posture for input the repository calls untrusted. It checks the file's size before reading it and declines a file over the accepted 1 MiB bound without allocating for it; the bound itself is the core's, and the core is still what enforces it. The empty state gains no import button: it says what it says and offers nothing else to do, and the toolbar item is above it either way.
- **A successful import says nothing.** The row appears at the head of the unpinned group — its History-added time is now — the list scrolls it into view, and it carries a brief highlight that decays. The answer is the row, and an alert about something already on screen would be an alert that trains people to dismiss alerts. Under Reduce Motion the scroll arrives immediately; the highlight is colour and is unchanged.
- **Everything else an import can answer is an alert**, because every one of them is a thing that did not happen. The classes are the ones the core's own taxonomy distinguishes, and the file's own diagnostic text is never shown:
  - a **duplicate** — a success that deliberately does not meet the expectation a first import sets — with title **这盘棋已经在历史里**, message **文件里的对局和历史中的一盘完全相同，所以没有重复添加。**, and actions **查看**, which opens the existing record's replay, and **好**;
  - an **identity conflict**, with title **这个文件和历史中的一盘棋冲突** and message **它和历史中的一盘棋是同一局，但内容不同。历史没有改变。如果要用这个文件，请先删除历史中的那一盘。**, and **好**. The message names the only route forward rather than offering it as a button: deleting the existing record is permanent, and it should be reached deliberately;
  - a file **created by a newer version**, with title **这个文件由更新版本的 Mini Xiangqi 创建** and message **当前版本无法读取它。请更新 Mini Xiangqi 后再试。历史没有改变。**, and **好**. This is the one message the data contract requires to be distinct, and no word in it means corrupt;
  - a file that **cannot be read** — every other refusal the archive domain has, from a wrong file to a damaged one to an oversized one — with title **无法读取这个对局文件** and message **文件的内容无效或过大，无法导入。历史没有改变。请确认文件完整，或者向对方要一份新的。**, and **好**;
  - a **damaged record already under this file's identity**, with title **历史中有一盘损坏的棋** and message **这个文件对应的历史记录已损坏，无法比较或导入。如果要用这个文件，请先删除历史中的那一盘。**, and **好**. This is the one import answer that is about the library rather than about the file, and the only one that may say 损坏 — the record's own bytes no longer decode or no longer match the hash recorded for them, so the comparison an import has to make cannot be made. It offers no retry, because a retry would find the same damage; its route out is the conflict's, and it says so for the same reason;
  - a file that was fine but **could not be saved**, with title **无法保存导入的对局**, message **对局文件没有问题，但保存到历史时出错。历史没有改变。请重试。**, and **取消** and **重试** — the same "could not do it, nothing changed, try again" shape the rest of the app uses.
- Each of those messages says 历史没有改变 explicitly, because no persistent change is the guarantee the core makes and a reader has no other way to know it held.
- **共享 exports through the platform's own sharing**, over a file rather than over data alone: the services an offline team actually moves a game with — AirDrop, Mail, Messages — appear only for a file. The filename is built from the game's own end in a fixed, machine-ordered form (`minixiangqi-2026-07-28-1432.mxq`), which is a deliberate and narrow exception to the localization rule: a displayed date belongs to the reader, and a filename belongs to the file. It is the game's end and not the export event because the export event is regenerated every time, and the same game would otherwise arrive under a different name on every share.
- Bulk deletion, search, filters, tags, and editing a History game are absent from the target MVP.
- Trackpad swipes use the same leading and trailing behavior where supported. Pointer context menus, keyboard commands, and screen-reader custom actions — VoiceOver on Apple platforms, Narrator on Windows — expose equivalent Pin or Unpin, Share, and Delete operations without adding permanent row buttons. On Windows, the context menu is the primary path to these actions.
- Action meaning is carried by icon and text as well as color.

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

**Move travel scales with distance, inside the accepted band.** A chariot crossing the board and a general stepping one point are not the same event, so travel time rises with distance within the band accepted above. The mapping is a chosen proportion, not a derived quantity, and it must respect the accepted ceiling on an Undo of a decision cycle.

**The AI's move has a floor, not a delay.** Its piece departs at the later of two instants: when the search returns, and a short fixed interval after the player's own move has finished animating — the arrival, not the tap that committed it, since the AI must not leave before the player's move has finished being shown. A search of a second or more is unaffected; only a near-instant reply waits, so the AI never appears to twitch rather than move. AI activity appears in the turn status only once a search has run long enough for an indicator to be worth showing.

**Interruption divides in two.** A *presentational* transition — a lift, a hover, a marker appearing — re-targets freely toward whatever the player just did. A *committing* transition — a move, a capture, an Undo — runs to completion, and input arriving during it is **discarded rather than queued**, so a player never watches a stack of actions replay. Board flipping is the one action deferred rather than discarded: it changes nothing about the game, so it is applied when the running transition ends.

**Reduce Motion is one rule.** Anything that animates position, scale, or rotation becomes a brief crossfade; anything that animates opacity, colour, stroke weight, or shadow is unchanged, because none of those is motion; any spring that survives loses its overshoot rather than its duration; and the order in which things happen is untouched. The check pulse is removed rather than converted, as the accepted rule requires of every pulse: check is a persistent treatment plus a pulse, so the ring and the 将军 token still say everything the pulse said. Every state survives — a held piece still reads as raised, a checked general still carries its rings, the legal destinations still answer an illegal tap — they simply arrive without travel.

**Feedback that reports an event fires when the event completes**: a move sounds when the piece lands, not when it lifts. **Feedback that answers a touch leads its animation** — selection, an illegal tap, refused input, and a failed save all respond at the touch rather than at the end of whatever is drawn in reply, because the touch is what the player is waiting to feel answered.

Exact durations, easing, scale factors, shadow, opacity, and feedback strength are settled on physical iPhone, iPad, and Mac hardware, within the bands accepted above. Board-state markers are drawn directly and never become translucent decoration; where Liquid Glass may appear is fixed under Platform visual language.

## Sound and haptics

Sound and haptics are part of the intended experience. They must reinforce meaningful actions and game events and must never be the only way information is conveyed.

Both are user-controllable through separate Settings toggles, per the Settings scope in [product.md](product.md). Haptics are available only where the hardware provides them; on a device without them the toggle is unavailable rather than silently ineffective, and no substitute effect is invented.

**The two toggles are presented together, and each is a plain switch.** They are one group of the Settings destination, with no group header — **声音** above **触感** — and neither is nested under or conditioned on the other, because they are independent preferences of equal standing: sound off leaves a landing felt, and haptics off leaves it heard. Each takes effect at the next event rather than at the next launch. **Settings itself is silent**: sound is an event of the board, and a screen that clicked back at every switch would be the app talking about itself.

**On macOS the haptics toggle is offered.** The hardware question there belongs to the trackpad rather than to the machine — a Mac may have a Force Touch trackpad built in, attached, or neither, and that can change while the app is running — and the system haptic performer already honours each machine's own trackpad, doing nothing where there is none. So "unavailable rather than silently ineffective" is satisfied by the platform itself, and a toggle the app greyed out by guessing at hardware would be a worse answer than the system's own. (Issue #64, Stage 5 design.)

**On iOS and iPadOS the switch is offered where the engine is there and is absent where it is not.** The question is asked of the device rather than inferred from it: Core Haptics' own `supportsHaptics` capability, which is the answer Apple's guidance says to read before playing haptics and which names iPad among the devices that do not support haptic feedback. A list of model names would be a guess that goes stale on the next device, and a feedback generator on a device with no engine does nothing at all rather than failing, so nothing later in the app can discover the answer — it has to be asked before the switch is drawn. Where the answer is no the row is **removed rather than greyed out**: this is not a state the device can leave, so a permanently disabled switch would be a control that can never be reached, and explaining it would mean a third footer on a screen that deliberately carries two, because a footer under every group is a screen nobody reads. iOS's own Settings does the same thing, showing no haptic rows at all on a device without the engine. The group survives losing the row: it has no header to strand, and the two switches were never conditioned on each other, so 声音 standing alone means exactly what it meant standing above 触感. *(Settled at Stage 6, against iOS.)*

**On iPhone and iPad the ring/silent switch silences the board, and the haptics it does not touch.** The sounds play through the `ambient` audio session category, whose own definition is this section's first sentence written by somebody else — the category for an app in which sound playback is nonprimary, one that also works with the sound turned off — and which both the silent switch and the lock screen silence. Somebody who has silenced their phone has already said what they want from the room they are in, and a board that knocked anyway would be overruling them in order to say something it has also said on the board; obeying costs nothing, because no sound here is the only channel for anything. The category **mixes** as well: a learner's own music, lesson or podcast keeps playing, where the platform's default category would have stopped it the moment the board appeared, and a board that silences a podcast to make room for one tock has its priorities backwards. The felt half does not pass through the audio session at all, so a silenced phone still lands a move in the hand — the two channels staying independent, exactly as their two switches are — unless the system's own Play Haptics in Silent Mode setting says otherwise, which is the platform's answer to give and not ours. macOS has no such switch and its sounds follow the system volume, as they always have. *(Settled at Stage 6, against iOS.)*

Haptic strength follows the meaning of the event, not its frequency. In particular, tapping an illegal square is a normal part of learning how the pieces move rather than a failure, so it uses the platform's lightest selection-weight feedback and never the system warning pattern. The warning pattern is reserved for genuine failures such as an action that could not be saved, and overusing it would both punish the learner and dilute its meaning. The two must remain distinguishable from each other, as their visual responses already are: an illegal tap answers on the board by strengthening the legal destinations, while a failed save appears only at the turn status.

### Board play

**The board plays one sound per landing, and chooses it by what the landing means.** A real set has one dominant sound — a piece meeting the board — so that is the sound the app is built around, and the rest are variations on it rather than additions to it. The four:

- **A plain landing** is a quiet, wooden, percussive knock. Every committing arrival makes it, an Undo's return included: taking a move back is a piece landing on a point, and the board already shows the reversal.
- **A capture** is the same knock, lower and slightly weightier. A take is a landing with mass.
- **A check** is the plain knock plus one brighter, quieter accent transient, sounding with the check rings' pulse.
- **A conclusion** is a soft, low, settling gesture. It **replaces** the landing sound rather than joining it, and it is one neutral sound for every result: which result it was is said on screen, in the notice and in the turn status. A draw the player claims ends the game without any piece moving, so its conclusion sounds at the moment the claim is confirmed.

Where a landing answers to more than one of these, the higher meaning is the only one heard: **conclusion, then capture, then check, then the plain landing**. A capturing check therefore sounds like a capture — the take is the louder fact, and the check already has the rings, the **将军** token, and the status line saying it.

**Sound character is percussive, dark, and short**: a landing's sound is an impact rather than a tone, nothing melodic is used — a sequence of pitches reads as interface decoration rather than as a board — and the overall level stays under the system alert sound at the same volume, quiet enough to sit beneath the landing haptic rather than compete with it. The samples are generated in-repo from a checked-in script rather than sourced, so the sound is tuned by parameter and regenerated, and the app carries no third-party audio. Exact spectra, decay times, and levels are settled by ear against the running app, as motion's exact durations are settled against running hardware.

**Silence is a decision too.** Nothing sounds for an illegal tap, refused input, a selection or a lift, a board flip, or the acknowledgment beat. Those are answered on the board and by the platform's lightest haptic: an exploratory tap is how the moves are learned, and a noise in reply would read as a reprimand.

**The haptic set is separate and is not derived from the sound set.** Every landing takes the alignment pattern, whatever the landing meant; the touch answers take the lightest pattern. A result changes what is heard and not what is felt.

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

Every string pair, the symbolic key it is stored under, and the localization process live in [copy.md](copy.md), which is the string of record: the strings quoted throughout this document describe behavior, and where a quotation and a row disagree, the row is the copy.

The app follows the language the operating system selects for it and offers no interface-language control of its own, per the Settings scope in [product.md](product.md). On Apple platforms the system's per-app language setting is the place a user changes it; on Windows the app follows the system's language preference list.

The interface must be designed for localization. User-facing text must not be embedded in visual assets, and layouts must tolerate different text lengths. Terminology for Xiangqi pieces, rules, results, and controls must be consistent within each supported language.

Piece characters are game content and are excluded from localization, as defined under Piece representation. Their English names localize wherever they appear as text.

## Orientation and layout

### Orientation

- **iPhone runs in portrait only.** Apple's guidance permits an experience that runs in a single orientation, and relies on people simply trying both and settling on the one that works; the app therefore never asks the user to rotate the device and shows no message about orientation.
- **iPad supports every orientation**, because iPadOS expects an app to adapt to rotation and to being windowed at arbitrary sizes, and an app that declines rotation opts out of that behaviour.
- macOS has no orientation; the window's proportions select the layout in the same way a device orientation does.
- Locking iPhone to portrait has a cost worth naming: a user whose device is fixed in a mount, or whose grip or dexterity favours landscape, cannot compensate by rotating. The square board makes portrait the orientation that serves the game best, and the accessibility obligation is met through the input alternatives already accepted rather than through rotation.
- Windows devices that rotate follow the same space-driven layout rules; the platform's orientation behaviour is settled when the Windows frontend is designed.

### Layout shapes

Two arrangements cover every device and window size, chosen by the available **space** rather than by device identity, so a resized Mac window and a multitasking iPad behave the same way as each other.

- **Stacked**, used by iPhone portrait, by iPad portrait, and by any window that is narrow for its height — a half-screen Mac window included: turn status above the board, play controls below it, and the board centred between them.
- **Side by side**, used by iPad landscape, wide iPad window sizes, and Mac windows with width to spare, which is most of them: the board on one side with a panel beside it carrying the turn status, the move list, game metadata, and controls that do not need to sit under the thumb.

**The rule is which arrangement gives the board more.** Both shapes fit the same square into the same rectangle and differ only in what they take out of it first: side by side takes the panel's width, stacked takes the chrome's height. Whichever leaves the larger board is the one used, and a tie goes to side by side, which costs the board nothing and shows the move list for free. A shape that cannot be drawn at all — the panel on a phone, the chrome's height at the minimum Mac window — loses to the shape that can. *(Settled at Stage 6, against iPhone and iPad screens.)*

**It is the available space and not a width threshold, and that is a correction.** This section said *width* before any iOS screen existed, and one width cannot express it: the two shapes' costs are on different axes. The accepted macOS minimum window is bound by its **height**, and takes side by side at 616 points of content; an iPad in portrait is bound by nothing, and takes stacked at 834. A single threshold would have to be both below 616 and above 834. What the width wording was reaching for — *the space decides, never the device* — is unchanged and is what the rule above states.

Every shape this section already named comes back unchanged. On an iPad Pro 11-inch in portrait the stacked board reaches the 102-point maximum while the panel beside it would have held the board to 75; the same device in landscape goes side by side at 88, where the height is what bounds the board and the panel costs it nothing. On the smallest Mac window the stacked shape cannot reach the 44-point floor at all, so side by side stands there.

**One outcome does change, and it is a Mac's.** A Mac window that is tall and narrow now stacks, which a width threshold never let it do: the first such window is 616 by 535 points of content, and a half-screen tile on a laptop — where the app's own minimum holds the width at 616 while the height runs to the full screen — is the everyday case. There the stacked board is close to twice the pitch the panel beside it would leave. That is the rule working rather than a case it failed to consider: the space decides, and a window with height to spare and no width to spare has decided. Near the boundary the win is as small as one point of pitch, paid for with the resident move list; that is the rule's weakest moment, and it is pinned by a test at the exact size the answer changes rather than smoothed over with a second number. *(Stage 6, photographed on macOS.)*

The board is square and is sized to the largest square fitting **both** the available width and the height left after the surrounding chrome, so it never overflows a short window. Within that, a point of the grid is never smaller than 44 points on **every** platform. On iOS and iPadOS that is the platform's default control size. macOS shares it rather than taking the smaller figure a pointer would allow, because the marker vocabulary in [Board metrics](#board-metrics) has one worst case instead of two, and because its finest distinctions — the air gap between a disc and its markers, and the gap between the two check rings — are fractions of a point at a smaller pitch.

That floor is affordable on the most constrained configuration measured so far. A built-in Retina display running at 1024 by 663 points — the largest-text setting on a current Mac — leaves a window of 1024 by 582 points once the menu bar and the Dock are subtracted, and 550 points of content height below a standard title bar. At the 44-point floor the board core is 308 points square. Whether every accepted state fits that budget on every supported device is a question for a running frontend rather than for arithmetic in prose; two attempts to settle it here were wrong.

**The board has a maximum.** Its core stops growing at a pitch of 102 points, for a core of 714 — the largest whole-point pitch inside the 720-point bound, which divides by seven to 102.857. The six points a fractional pitch would buy are not worth every dimension derived from the pitch landing between points. Beyond that the two palaces drift far enough apart on a large display to cost more in eye movement than the extra size returns, and a disc passes 81 points, which no physical set resembles. Surplus space goes to the surrounding layout rather than to the board, and the half-cell margin stays functional space rather than a spacer to inflate.

When space is short the surrounding chrome tightens before the board does. That preference has a floor: the board may not be driven below the sizes above, and neither may the chrome be driven below what its own controls require. Each platform therefore defines a minimum window size that keeps both above their floors, and the window stops resizing there rather than either becoming unusable.

**The play content's floor is 616 by 388 points**, which is the sum of what the two floors ask for and nothing else: the board block at its 44-point floor is 308 by 340, the air around it is 24 points a side, and the panel beside it is 260. A window one step narrower clips the board against the panel, and one step shorter carries it up behind the title bar; both were photographed with the floor lifted before the number was accepted.

**macOS stops at 760 by 492 points**, which is that floor plus the navigation container: 144 points of sidebar beside it and 52 of toolbar above it, both measured on the running app rather than derived. The 616 by 388 the play content gets inside that window is unchanged, which is the point — the destination structure was added around the layout rather than out of it. The number moved when the navigation arrived and is expected to move again if the container's presentation changes.

**That floor belongs to the platform with a resizable window, so it is macOS's alone.** A minimum size is a thing that stops a resize, and iOS and iPadOS have no resize to stop: the screen is the size it is, and a multitasking iPad is sized by the system rather than by the app. A 616-point minimum on a 440-point phone would not widen anything — it would only declare content wider than the screen, which is what the stacked shape exists to avoid. *(Stage 6.)*

**The file numerals are present at every macOS window size**, including the smallest. The move list speaks of 兵四进一 and the strips are what ground 四 on the board, so a size where the game can be played but not read about is not a size worth having. They cost about a tenth of the board block's height at the floor and proportionally less as the board grows, and at the minimum window they cost nothing at all, because that window is bound by its width.

**The panel's sections begin on one edge**, 16 points in from the panel's own, and its material runs to the top of the window rather than stopping below the title bar: the title bar draws its own treatment over whatever lies beneath it, and beneath it lies the panel rather than bare window.

One exception: a pre-start board is a noninteractive preview with no touch targets, so it carries no size floor and yields space to the setup controls whenever they need it. The floor exists to protect interaction, and a preview has none to protect.

Navigation uses one adaptive container, and the container is the platform's own rather than a presentation the app selects: a tab bar on iPhone, a tab bar on iPad carrying the platform's own control for expanding it into a sidebar, and a sidebar on a Mac at every window size. An iPad in a narrow window therefore gets the same navigation as an iPhone, and the app decides none of it by device identity because it decides none of it at all.

**That also settles whether the user may switch between the two presentations**: the switch is offered where the platform offers it — on iPad — and nowhere else, which is a better answer than one the app invented, and the app adds no control of its own. It is the layout shapes that follow the space; the navigation follows the platform, and the two are not the same rule. *(Stage 6, from the running app.)*

### The move list during play

- Where the side-by-side layout applies, the move list is permanently visible in the panel. Its permanence is a property of that shape and not of a platform: a Mac window narrow enough to stack reaches the list the way every stacked screen does, on demand.
- In the stacked layout during ordinary play it is not shown by default and is reached on demand, so neither the board nor the controls give up space to something consulted occasionally.
- **What reaches it is a toolbar item over a sheet.** The item sits in the same toolbar the page's own back control is in — the platform's place for something about this page that is not on it — and the sheet opens at half height, because the other half is the board the list is being consulted about. It is dismissible by the platform's own means and by a **完成**; it is a transient the player asked for, which is exactly the surface [Platform visual language](#platform-visual-language) already allows to cover the board. The list inside it is the same list the panel carries, and it stays a record rather than becoming a control: during play no move is selectable, as in the panel. *(Stage 6.)*
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

- Fix the minimum window size for iPadOS windowing, which the board and chrome floors together determine. The app declares none today: iPadOS sizes a multitasking window itself, the shape rule answers whatever size it hands over, and what remains open is whether there is a size below which the app should decline rather than adapt.
- Fix the exact sizes at which the **navigation** presentation changes. They are the platform container's own today and are stated nowhere the app can see, so a screenshot is the only way to know where a tab bar becomes a sidebar. The layout shape's own crossover is no longer part of this question: the rule above decides it, and a test pins the point where its answer changes.
- Fix what size a macOS window opens at when there is nothing to restore. The minimum is settled and the opening size is not: today a window whose content is flexible in both directions opens at the whole visible area of whatever display it lands on, and the scene's declared default size does not change that on the current toolchain.
- Resolve how the retained draw-claim affordance and the accessibility text sizes fit the stacked layout's remaining space, given that the chrome has its own floor. The result notice's own answer is settled above — it fits, in both languages, with the board behind it still worth looking at — and the stacked chrome yields to the board rather than the other way round, so what remains open is what happens at the largest accessibility sizes, which no screenshot has been taken at yet.
- Define what the side-by-side panel contains beyond the turn status, move list, game metadata, and controls, and how that metadata relates to the Play destination's own active-game metadata. What the stacked layout does with the panel's contents is settled: the turn status goes above the board, the play controls below it, and the move list is reached on demand.
- Fix each piece style's concrete values — role colours and disc fills, ring weights, grid stroke, its own board surface, and its marker ink at both accepted strengths — within the constraints the accepted styles and board metrics impose.
- Define board themes beyond the three accepted piece styles, if any are wanted.
- Define the 将军 token's form, the remaining transient announcements, the turn status's VoiceOver behavior, and its placement within the side-by-side panel. The AI activity treatment is settled above.
- Define the insufficient-memory notice's repeated-failure behavior beyond a fresh probe per retry, and its accessibility announcement. Its presentation, in both the pre-start and the mid-game case, is settled above.
- Define help entry points, content organization, and illustrations within the accepted read-only rules-reference scope.
- Confirm the accepted motion timings and the compose-beat floor on physical iPhone, iPad, and Mac hardware, and refine easing and feedback strength there. A change to an accepted duration is a contract change rather than a tuning pass.
- Confirm the numeral-strip measurements on iOS and iPadOS, which were taken on macOS, and define the exact accessibility text size at which the strips are hidden.
- Define the sound events outside board play — whether the History and Help surfaces sound at all; Settings is settled under [Sound and haptics](#sound-and-haptics) and is silent — and the per-platform differences behind the accepted sound toggle. What an iOS device does with a board sound under the silent switch is no longer among them: it is settled under [Sound and haptics](#sound-and-haptics), where the board obeys the switch. Board play's four sounds, their precedence, their character, and the events that stay silent are defined there too, and their samples are tuned by ear against the running app.
- Define the haptic events outside board play. Board play's haptic set is defined under [Sound and haptics](#sound-and-haptics), and each half now follows its own accepted preference wherever it would fire. Where and how the two toggles are presented is settled there too, both Apple platforms' answers to the hardware question included; Windows has a third answer to give and it is deliberately not given yet.
- Define accessibility acceptance criteria and the board’s VoiceOver interaction model.
- Define the Windows navigation presentation, Fluent material usage, accessibility equivalents (Narrator, high contrast), and touch behavior when Windows implementation begins.
- Define the loading states. The AI-thinking state is settled under [Turn status](#turn-status). History's empty state, its unreadable-library state, and its destructive-action confirmation are settled above; History's own loading state is deliberately nothing, because a local paged read of a library that cannot exceed a few thousand rows does not reach the threshold at which an indicator helps.
