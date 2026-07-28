# Apple UI Design Survey — Mini Xiangqi

> **Status: Workspace-only research draft. Non-normative.**
>
> Nothing here is an accepted contract. This document surveys the Apple-platform
> interface design space so the product owner and lead can make the remaining
> visual, motion, sound, interaction, and accessibility decisions. Accepted
> behaviour lives in `MiniXiangqi/docs/`; when a decision here is approved it
> must be written into `interaction-design.md` (and, where it changes scope,
> `product.md`) before implementation.

## How to read this document

Every area is split three ways:

- **Already accepted** — what the contracts in `MiniXiangqi/docs/` already decide, with the section cited. Not open for redesign here.
- **Proven Apple guidance** — what Apple's own documentation says, cited by document title and section so a reader can find it again.
- **Proposal** — my concrete recommendation for each remaining open decision.

Where Apple's guidance is genuinely silent or ambiguous for our case, the
**Proposal** says so rather than inventing a rule. Section 12 lists every point I
could not ground in Apple documentation, with the exact blocker.

## Sources and method

**Contracts read in full:** `docs/interaction-design.md`, `docs/product.md`,
`docs/xiangqi-rules.md`, `docs/architecture.md`, `docs/game-data.md`,
`docs/testing.md`, plus the frontend-visible surface of `docs/core-interface.md`
(`MxqGameStatus`, `mxq_game_legal_moves`, `MxqPosition.in_check`,
`position_revision`).

**Apple documentation** was searched through the Xcode documentation tool on
2026-07-27. Pages cited below were returned by that tool and quoted from its
output. Citations name the document and its section, e.g.
`HIG "Materials › Liquid Glass"` or `SwiftUI Animation.timingCurve(_:_:_:_:duration:)`.

**Board facts used throughout** (from `xiangqi-rules.md § Board and pieces`,
`§ Starting position, coordinates, and notation`): 7×7, no river, no advisors or
elephants; king, chariots, horses, cannons, soldiers; 3×3 palace per side
(Red `c1`–`e3`, Black `c5`–`e7`); files `a`–`g` from Red's left, ranks `1`–`7`
from Red's back rank; starting FEN
`rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1`, which places 12 pieces per
side (2 chariots, 2 horses, 2 cannons, 1 king, 5 soldiers) on 49 points — about
49% occupancy at the start. The board is dense and small; every layout number
below is driven by that.

---

# 1. The board and pieces

## 1.1 Already accepted

- The board is the primary content during play, and its design must cover colour choice, orientation, state markers, and replay (`interaction-design.md § Board and game interaction`).
- "The board, pieces, and game-state markers form one shared visual identity across platforms; only the surrounding functional chrome is platform-specific." (`§ Platform visual language`)
- "Piece text and symbols remain upright and readable in either orientation." (`§ Board orientation`)
- Turn ownership, activity, and input availability "must not be communicated by color alone" (`§ Turn status`); state cues generally must not rely only on colour (`§ Accessibility`).
- "User-facing text must not be embedded in visual assets" (`§ Localization`). This is decisive: a piece glyph is user-facing text, so the pieces cannot be bitmap or vector artwork with baked-in characters.
- Squares are named `a1`–`g7`; the machine move notation is origin-destination; "Any friendlier user-visible move notation is a later interaction-design decision and is presentation only" (`xiangqi-rules.md § Starting position, coordinates, and notation`).
- Open (`interaction-design.md § Need to discuss`): "Define the visual system for the board, pieces, coordinates, colors, typography, and themes."

## 1.2 Proven Apple guidance

- **Colour is never the only channel.** "Convey information with more than color alone. Some people have trouble differentiating between certain colors and shades… Offer visual indicators, like distinct shapes or icons, in addition to color to help people perceive differences in function and changes in state." (HIG "Accessibility › Vision")
- **Contrast minimums.** HIG "Accessibility › Vision" reproduces the WCAG Level AA values the Accessibility Inspector checks against: 4.5:1 up to 17 pt at all weights; 3:1 at 18 pt; 3:1 for bold at all sizes. "If your app doesn't provide this minimum contrast by default, ensure it at least provides a higher contrast color scheme when the system setting Increase Contrast is turned on. If your app supports Dark Mode, make sure to check the minimum contrast in both light and dark appearances."
- **Light, dark, and increased contrast are three contexts, not two.** "Make sure all your app's colors work well in light, dark, and increased contrast contexts… If you define a custom color, make sure to supply light and dark variants, and an increased contrast option for each variant that provides a significantly higher amount of visual differentiation. Even if your app ships in a single appearance mode, provide both light and dark colors to support Liquid Glass adaptivity in these contexts." (HIG "Color › Best practices")
- **Do not hard-code system colour values**; use `Color` and the dynamic system colours, and don't repurpose their semantics (HIG "Color › System colors").
- **High-contrast variants are an asset-catalog feature.** "You can also specify high-contrast versions of your colors by selecting the High Contrast checkbox." (Xcode "Specifying your app's color scheme › Specify accent color variations")
- **Dark Mode needs testing with the accessibility settings on.** "In Dark Mode with Increase Contrast and Reduce Transparency turned on (both separately and together), you may find places where dark text is less legible when it's on a dark background." (HIG "Dark Mode › Best practices")
- **Target sizes.** HIG "Designing for games › Look stunning on every display" gives default/minimum button sizes per platform: iOS and iPadOS 44×44 pt default, 28×28 pt minimum; macOS 28×28 pt default, 20×20 pt minimum. The same page gives minimum text sizes: 11 pt on iOS/iPadOS, 10 pt on macOS.
- **Text, not artwork, for characters.** "Include text in your design only when it's essential for conveying meaning… If you need to display individual characters in your icon, be sure to localize them." (HIG "Icons › Best practices")
- **Nothing found** on Chinese/CJK typography — see §12.

## 1.3 Proposal

### 1.3.1 Geometry — draw intersections, not squares

Xiangqi is played on the intersections of the line grid, and Mini Xiangqi's "7×7"
means 7×7 **points**. Drawn correctly the board is a **6×6 grid of cells with 49
intersections**, the outer ring of points sitting on the border lines.

- **Recommend: intersections.** A square-checkerboard rendering would be
  immediately wrong to anyone who knows the game and would teach beginners the
  wrong mental model, which the education purpose (`product.md § Product identity
  and distribution`) makes a real cost.
- **Palace diagonals.** Each palace is a 3×3 block of points = a 2×2 block of
  cells. Draw the two diagonals corner point to corner point across that block
  (`c1`↔`e3` and `e1`↔`c3` for Red; `c5`↔`e7` and `e5`↔`c7` for Black), crossing at
  the palace centre point (`d2` / `d6`). The diagonals are drawn at the same
  stroke weight as the grid, so the palace reads as part of the grid rather than
  as decoration.
- **No river.** The grid is unbroken from rank 1 to rank 7. This is a
  distinguishing feature of the variant and should not be "fixed" with a decorative
  band; the Help section should call it out (§8).
- **Soldier start marks.** Full Xiangqi boards mark soldier and cannon starting
  points with corner ticks. Mini Xiangqi's soldiers start on `a2 c2 d2 e2 g2` and
  cannons on `b1 f1`. **Recommend: no start marks.** On a 7-point board these
  ticks sit adjacent to almost everything and would compete with the legal-move
  dots and last-move brackets, which carry live information. Traditional feel is
  worth less here than an uncluttered marker vocabulary.
- **Proportions.** The grid is square. The board view is `7 × pitch` on a side:
  6 cells plus a half-cell margin at each edge so edge discs are not clipped.
  Coordinates live outside that in a further margin.

### 1.3.2 Cell pitch — the number every layout is built on

Hit target = one full cell (`pitch × pitch`) centred on the point. Disc diameter
= `0.86 × pitch`.

| Context | Available edge | Pitch | Verdict |
|---|---|---|---|
| iPhone portrait, narrowest plausible supported width (375 pt) minus 2×16 pt margins | 343 pt | **49.0 pt** | comfortably above the 44 pt floor |
| iPhone landscape, ~310 pt usable height after bars | 310 pt | **44.3 pt** | exactly at the floor — this is the binding case |
| Mac, proposed 640 pt minimum content width | 340 pt board | **48.6 pt** | above the floor, and far above the 28 pt Mac default |

So: **a 7×7 board with 44 pt targets fits every supported form factor**, and
iPhone landscape is the case that forces the layout (§3). Below `pitch = 44` on
touch platforms the layout must give the board more room rather than shrink it.

### 1.3.3 Pieces — character discs, rendered as text

**Recommend traditional Chinese character discs**, not a modernized abstract
treatment (silhouettes, letters, or invented icons). Reasons: the education
purpose is learning real Mini Xiangqi; the characters are the game's identity;
and the accepted rule that user-facing text is never baked into assets means the
glyph must be a text view anyway, which gives us free light/dark/contrast
correctness and free scaling.

**Construction of one piece:**

- a `Circle` fill (the disc face),
- a `Circle` stroke (the ring),
- a `Text` with the piece glyph, `.font(.system(size: pitch * 0.52, weight: .semibold))`,
- combined into a single accessibility element (§7).

No images, no glyph rasterisation, no per-piece asset.

### 1.3.4 Which characters — and why this is a real decision

Mini Xiangqi has five piece types per side. Chinese Xiangqi conventionally uses
**different characters for the two sides** for most pieces. Three candidate sets:

| Piece | (A) Fully differentiated | (B) Mixed (mainland set convention) | (C) Simplified, collapsed |
|---|---|---|---|
| King | 帥 / 將 | 帅 / 将 | 帅 / 将 |
| Chariot | 俥 / 車 | 俥 / 車 | 车 / 车 |
| Horse | 傌 / 馬 | 傌 / 馬 | 马 / 马 |
| Cannon | 炮 / 砲 | 炮 / 砲 | 炮 / 炮 |
| Soldier | 兵 / 卒 | 兵 / 卒 | 兵 / 卒 |

**Set (C) must be rejected on Apple guidance**, not on taste: with 车/车 and
马/马 the side of a chariot or a horse is carried by colour alone, which HIG
"Accessibility › Vision" rules out ("Convey information with more than color
alone"). That is the one part of this decision I can ground.

**Recommend set (B)**: simplified where simplification does not destroy the
distinction (帅/将), the conventional differentiated forms where they carry the
side (俥/車, 傌/馬, 炮/砲, 兵/卒). This matches the surrounding simplified-Chinese
interface copy while keeping every piece type distinguishable by glyph alone.

**Flagged honestly:** the choice among (A) and (B) is a Chinese-language and
Xiangqi-convention judgement, not an Apple-guidelines question. I cannot ground
it in Apple documentation and the owner should settle it (decision D2).

### 1.3.5 Distinguishing Red from Black without colour

Two independent non-colour channels, both always on:

1. **Glyph** — differentiated per side for all five types (§1.3.4).
2. **Disc structure** — Red = **solid**: face filled with the Red role colour at
   full strength, glyph reversed out in the on-colour, 1 pt ring. Black =
   **outlined**: face uses a neutral elevated surface, glyph and a heavier
   2-stroke ring in the Black role colour.

This survives greyscale, survives Increase Contrast, and survives a colour-blind
viewer, because the difference is luminance and structure rather than hue. Under
`accessibilityDifferentiateWithoutColor` **nothing needs to change** — which is
the point: a passing Differentiate Without Color test is evidence the default
design is already correct (§7.7).

Role colours: two custom Color Sets, `PieceRed` and `PieceBlack`, each with
Any/Dark appearances and a High Contrast variant for both (Xcode "Specifying your
app's color scheme"). Neither is the app accent colour — the accent colour belongs
to controls, and HIG "Color › Best practices" warns against using the same colour
to mean different things.

Contrast targets, checkable with the Accessibility Inspector: glyph vs. disc face
**≥ 4.5:1** (the design exceeds the 3:1 that would apply to bold text at this
size); disc vs. board surface **≥ 3:1**.

### 1.3.6 Coordinates

**Recommend: shown by default on all device classes**, in the outer margin, on
the bottom and leading edges of the current orientation, following the flip so
that a coordinate always sits beside the file/rank it names.

- Notation **`a`–`g` and `1`–`7`**, matching the accepted square names exactly.
  This means the printed label, the VoiceOver utterance, the History/replay move
  list, and the stored move all use one vocabulary. Traditional Chinese file
  numerals are a plausible later education feature but would introduce a second
  notation the app would then have to teach; keep them out of the MVP.
- Style `.caption` in `.secondary`, scaling with Dynamic Type up to about 1.5×
  and then holding, so the margin cannot eat the board.
- No Settings toggle. `product.md` keeps Settings deliberately small, and
  coordinates that are always present are a better teaching aid than coordinates
  a learner has to discover.

### 1.3.7 Appearance

| | Light | Dark | Increase Contrast (either) |
|---|---|---|---|
| Board surface | warm low-chroma parchment | desaturated dark slate, **not** black | pushed further from the disc luminance in both directions |
| Grid lines and palace diagonals | 1 pt, dark, ≥ 3:1 on the surface | 1 pt, light, ≥ 3:1 | 1.5 pt and raised contrast |
| Disc rings | 1 pt (Red) / 2 pt (Black) | same | +0.5 pt each |
| Glyph weight | `.semibold` | `.semibold` | `.bold` |
| Coordinates | `.secondary` | `.secondary` | `.primary` |

The board never uses Liquid Glass (§4). It uses flat fills and, at most, a single
hairline border — HIG "Materials › Liquid Glass" is explicit: "Don't use Liquid
Glass in the content layer… Instead, use Standard materials for elements in the
content layer, such as app backgrounds."

Test matrix per HIG "Dark Mode › Best practices": light, dark, light+Increase
Contrast, dark+Increase Contrast, and each of those with Reduce Transparency —
both separately and together.

---

# 2. State treatments

## 2.1 Already accepted

From `interaction-design.md § Motion and visual effects` and `§ Move input`:

- Selecting a piece uses "a brief, approximately 120–160 ms lift, scale, and shadow transition without continuous movement."
- "Empty legal destinations use a small dot; capturable destinations use a ring around the target piece. The two states differ by shape and do not rely on color alone."
- During a drag "the piece follows the pointer or touch, its origin retains a subtle marker, and a nearby legal target strengthens its feedback."
- An AI move "leaves persistent origin and destination markers so the player can identify the completed move."
- "Check uses a persistent, non-color-only king-square treatment plus one brief pulse. It does not flash continuously."
- "Tapping an illegal board square does not move the piece or cancel the current selection. It provides brief, non-blocking feedback."
- A failed save gives "brief non-blocking feedback distinct from illegal-move feedback"; there is no modal dialog and no accepted-but-unsaved change.
- "When input is unavailable, including while the AI is thinking or after a result is confirmed, the board rejects the interaction before visually moving a piece."
- An invalid drop "returns the piece smoothly to its origin and gives the attempted destination brief feedback without an alert or forceful shake."

Open (`§ Need to discuss`): "Define the exact visual treatment for selection,
legal destinations, captures, illegal-square feedback, save-failure feedback, and
unavailable input."

## 2.2 Proven Apple guidance

- "Offer visual indicators, like distinct shapes or icons, in addition to color to help people perceive differences in function and changes in state." (HIG "Accessibility › Vision")
- "Show people when a command can't be carried out and help them understand why." (HIG "Feedback › Best practices")
- "Make sure all feedback is accessible. When you use multiple ways to provide feedback, you reach more people… when you provide feedback using color, text, sound, and haptics, people can receive it whether they silence their device, look away from the screen, or use VoiceOver." (HIG "Feedback › Best practices")
- "Avoid using an alert merely to provide information. People don't appreciate an interruption from an alert that's informative, but not actionable." (HIG "Alerts › Best practices")
- "Be cautious with fast-moving and blinking animations. When you use these effects in excess, it can be distracting, cause dizziness, and in some cases even result in epileptic episodes." (HIG "Accessibility › Cognitive")
- The design system exposes `accessibilityDifferentiateWithoutColor`: "If this is true, UI should not convey information using color alone and instead should use shapes or glyphs to convey information." (SwiftUI `EnvironmentValues.accessibilityDifferentiateWithoutColor`)

## 2.3 Proposal — one marker vocabulary, six distinct shapes

The whole board-state language is six shapes. No two share a shape, so none of
them depends on colour to be told apart.

| State | Shape | Geometry | Where |
|---|---|---|---|
| **Selected piece** | ring **around the disc**, plus scale | 2 pt stroke, outer Ø `1.0 × pitch`; disc scales to 1.06 with an elevation shadow | on the piece |
| **Legal empty destination** | **filled dot** | Ø `0.28 × pitch` | centred on an empty point |
| **Legal capture** | **dashed ring around the target piece** | 3 pt dashed stroke, outer Ø `1.06 × pitch` | around an enemy disc |
| **Last move origin and destination** | **corner brackets** | four L-shaped ticks at the cell corners, 2 pt, length `0.22 × pitch` | on both points, persistent |
| **King in check** | **double ring + hazard badge** | two concentric 2 pt rings around the king disc, plus a small `exclamationmark.triangle.fill` at the disc's trailing-top | on the king, persistent |
| **Illegal square** | **crossed circle**, transient | `xmark.circle` at `0.5 × pitch`, ~0.5 s total | on the tapped point |

Notes on the choices:

- **Dot vs. dashed ring** is the accepted shape distinction, hardened: solid/small/on-an-empty-point vs. hollow/large/dashed/encircling-a-piece. The dash also separates the capture ring from the *selection* ring, which is solid — so three ring-like things are still three distinct things in greyscale.
- **Corner brackets for the last move** deliberately avoid a filled tint. A tint on the destination point would sit under a disc and be invisible; brackets read on an empty origin and around an occupied destination equally well, and they do not collide with the dot/ring vocabulary.
- **Check** must be perceivable without colour and without motion, hence a structural double ring plus an SF Symbol badge, with the single brief pulse (accepted) as an attention cue rather than the carrier. Continuous flashing is ruled out by our contract and by HIG "Accessibility › Cognitive".
- **Dragged piece**: scales to 1.12 with a larger shadow and follows the touch or pointer. On touch, offset the disc 24 pt toward the top of the screen so a fingertip does not cover it; on pointer, no offset. The origin keeps a hollow dot at `0.28 × pitch`. When the drag is within half a cell of a legal target, that target's dot or ring thickens by 50%.

### 2.3.1 Check indication in the status element — a decision, not just a treatment

The board treatment alone is missable, especially at a glance or on a large
display. The accepted turn status is deliberately minimal: a primary side-to-move
line plus, in human-versus-AI, a `你`/`AI` controller label, and "The design does
not add a separate, unrelated instruction such as 'please move' or 'your turn.'"

**Recommend adding one persistent state token — `将军` — to the status element**
whenever `MxqPosition.in_check` is true, rendered as a small emphasized capsule
beside the controller label, not as a new sentence. This is not an instruction; it
is a fact about the position, which is what the status element is for. It also
gives VoiceOver a stable, re-readable place to find it. This is **decision D10**.

### 2.3.2 Unavailable input — a pulse, not silence

The contract says the board rejects the interaction *before visually moving a
piece*, and forbids a "your turn" instruction. Taken literally that produces a
completely silent rejection, which HIG "Feedback › Best practices" argues
against: "Show people when a command can't be carried out and help them
understand why."

**Recommend: a single 150 ms emphasis pulse of the status element** (a brief
opacity/scale beat on the existing turn-status capsule) when the board is touched
while input is unavailable. No new copy, no board mark, no alert. The reason
already lives in the status element (`轮到黑方 · AI`, `AI 思考中`, or the result
card); the pulse just points at it. Under Reduce Motion the pulse becomes a
120 ms opacity beat with no scale. This is **decision D11**.

The board itself stays at full opacity while input is unavailable. Dimming the
board would fight the accepted requirement that the final board "remains fully
visible" after a result and would make the position harder to study while the AI
thinks — which is exactly when a learner wants to look at it.

### 2.3.3 Save-failure feedback — a second, distinct channel

The contract requires save-failure feedback "distinct from illegal-move
feedback". Keeping them on different surfaces is the cleanest way to guarantee
that:

- **Illegal square → a mark on the board** (crossed circle at the tapped point).
- **Save failure → a transient message beside the status element**, in 150 ms,
  held 2.5 s, out 250 ms, dismissible by tapping it.

`core-interface-design-decisions.md` item A1 records that this flow has no
accepted copy and needs a product decision. **Proposed copy: `无法保存这一步，请重试。`**
for a failed move or Undo commit. It is a statement of fact plus the one useful
instruction, matching the register of the accepted `当前对局仍然保留。请重试。`.
This is **decision D12**. The already-accepted `无法保存对局` alert stays as-is for
the archive-and-clear, claim, resign, and result-confirmation paths.

---

# 3. Layout and navigation per device class

## 3.1 Already accepted

- Three primary destinations: **Play**, **History**, **Settings** (`product.md § Product navigation`; `interaction-design.md § Navigation`).
- "The navigation presentation must adapt appropriately to iPhone, iPad, Mac, and Windows. Platform adaptation may change presentation, but it must not create different product capabilities without an explicit product decision." (`§ Navigation`)
- The application has one main window; multiple main windows are not supported (`product.md § Target platforms`; `interaction-design.md § Platform adaptation`).
- "iOS should support touch-first play and compact layouts. iPadOS should use the available space without requiring a separate product model. macOS should support pointer and keyboard conventions while retaining the same game behavior." (`§ Platform adaptation`)
- The Play destination "shows the active game's metadata and a direct **Resume Game** action" (`§ Saving the active game before choosing a new mode`).
- "A persistent status element near the board is one coherent description of the current play state." (`§ Turn status`)
- Replay provides jump-to-beginning, one back, play/pause, one forward, jump-to-end, plus a move list that highlights the current move and allows jumping (`§ History replay`).
- The result card appears "near" the board and the final board "remains fully visible" (`§ Natural result presentation`).
- Board flipping uses a visible control with a localized accessibility label "and an equivalent keyboard command where keyboard input is supported" (`§ Board orientation`).
- Open (`§ Need to discuss`): "Define the navigation presentation on each device class and window size."

## 3.2 Proven Apple guidance

- **Prefer a tab bar.** "Prefer a tab bar for navigation. A tab bar provides access to the sections of your app that people use most." (HIG "Tab bars › iPadOS"); "Consider using a tab bar first. A tab bar provides more space to feature content, and offers enough flexibility to navigate between many apps' main areas." (HIG "Sidebars › iOS, iPadOS")
- **One control adapts across all three platforms.** `sidebarAdaptable`: "iPadOS displays a top tab bar that can adapt into a sidebar. iOS displays a bottom tab bar. macOS and tvOS always show a sidebar." (SwiftUI `TabViewStyle.sidebarAdaptable`)
- **Default placement is settable.** `defaultAdaptableTabBarPlacement(_:)` "Specifies the default placement for the tabs in a tab view using the adaptable sidebar style." (SwiftUI "Navigation › Configuring a tab bar")
- **iPad windows resize freely and need a plan.** "People can freely resize windows down to a minimum width and height, similar to window behavior in macOS… As someone resizes a window, defer switching to a compact view for as long as possible. Design for a full-screen view first… Test your layout at common system-provided sizes… Window controls provide the option to arrange windows to fill halves, thirds, and quadrants of the screen." (HIG "Layout › iPadOS")
- **Set a minimum.** "Since people can resize your app's window, set a minimum size for your window with `UISceneSizeRestrictions`." (UIKit "Multitasking on iPad, Mac, and Apple Vision Pro › Adapting to different window sizes")
- **macOS resizability API.** `windowResizability(_:)`, with `contentMinSize` retaining the minimum size restriction (visionOS/macOS "Positioning and sizing windows › Specify window resizability").
- **Mac conventions.** "Use the menu bar to give people easy access to all the commands they need to do things in your app… Handle keyboard shortcuts to help people accelerate actions and use keyboard-only work styles." (HIG "Designing for macOS › Best practices"); "Make every toolbar item available as a command in the menu bar. Because people can customize the toolbar or hide it, it can't be the only place that presents a command." (HIG "Toolbars › macOS")
- **iPad has a menu bar too.** "Menu bar menus on iPad are similar to those on Mac, appearing in the same order and with familiar sets of menu items." (HIG "The menu bar")
- **List top-level destinations in the View menu.** "Regardless of whether you use a split view or a segmented control instead of a tab bar in your iPad app, be sure to give people quick access to top-level items by listing them in the macOS View menu." (HIG "Mac Catalyst › Navigation")
- **Toolbar and tab bar can share the top on iPad.** "In iPadOS, a toolbar and a Tab bar can coexist in the same horizontal space at the top of the view." (HIG "Toolbars › iPadOS")

## 3.3 Proposal

### 3.3.1 One navigation container for all three platforms

```
TabView(selection:)                       // 3 Tabs: 对局 / 历史 / 设置
    .tabViewStyle(.sidebarAdaptable)
    .defaultAdaptableTabBarPlacement(.tabBar)   // iPad launches as a top tab bar
```

- **iPhone** → bottom tab bar (system behaviour). Do not adopt tab-bar minimize-on-scroll on the Play screen; the Play screen does not scroll.
- **iPad** → top tab bar by default, user-switchable to a sidebar. **Recommend `.tabBar` as the default** because a sidebar for three items costs ~220 pt of width that the board wants, and HIG "Tab bars › iPadOS" prefers a tab bar. The sidebar remains one tap away for anyone who prefers it. This is **decision D7**.
- **Mac** → sidebar (the style's fixed behaviour), which is also the Mac convention per HIG "Mac Catalyst › Navigation".

Each tab hosts its own `NavigationStack`. On Play the stack root is the **start
state** (active-game metadata + Resume + the two mode entries), with
`navigationDestination` cases for the pre-start state and the board. On relaunch
with an active game, do **not** auto-push the board: the contract gives Resume as
an explicit action, and auto-pushing would strand a user who wanted History.

Tab symbols are candidates pending an SF Symbols app check (§12):
`checkerboard.rectangle` / `square.grid.3x3` for 对局, `clock.arrow.circlepath`
for 历史, `gearshape` for 设置.

### 3.3.2 Play screen layouts

**iPhone portrait** — one vertical column:

```
[ status element ]                 44–56 pt, two lines at large type
[ board ]                          square, width-bound, centred in remaining space
[ control cluster ]                悔棋 判和 认输 翻转棋盘   (Liquid Glass, §4)
[ tab bar ]                        system
```

**iPhone landscape** — this is the pitch-critical case, so the board takes the
full height and everything else moves to a trailing column:

```
[ board (height-bound, square) ] | [ status ]
                                 | [ controls, stacked ]
```

**iPad, regular width** — board centred and height- or width-bound, whichever is
smaller; status above; controls in a bottom-centred cluster below ~900 pt width
and in a trailing column above it. In **replay**, the trailing column becomes the
move list.

**iPad, compact multitasking width** — below about 430 pt of scene width, fall
back to the iPhone portrait layout. Per HIG "Layout › iPadOS", defer this switch
as long as possible; validate at halves, thirds, and quadrants on multiple iPad
sizes.

**Mac** — sidebar + content. Content is status above, board centred, controls in a
trailing column (there is always room), move list replacing the controls column
in replay. Every control also exists in the menu bar.

### 3.3.3 Window minimums, defaults, and the very-large case

Derived from the 44 pt pitch floor and a 340 pt minimum board:

| | Minimum | Default |
|---|---|---|
| iPad scene (`UISceneSizeRestrictions`) | **390 × 560 pt** | full screen |
| Mac window content (`windowResizability(.contentMinSize)`) | **640 × 520 pt** | **1040 × 760 pt** |

**Very wide window:** the board does **not** grow without limit. **Recommend
capping the board's edge at 720 pt** (pitch ≈ 103 pt) and giving all surplus width
to the trailing pane — controls and game metadata during play, the move list
during replay. An uncapped board on a 6K display would put the two sides of the
position an uncomfortable distance apart and would make a 300 pt-wide chariot
disc look absurd. This is **decision D8**.

**Very tall window:** the board stays capped and vertically centred; surplus
height goes to the bottom or trailing pane. Do not inflate the board's outer
margins to fill vertical space — the margin is a functional half-cell plus
coordinates, not a spacer.

### 3.3.4 Menu bar (macOS and iPad)

| Menu | Items |
|---|---|
| 对局 | 新对局（人机对弈） ⌘N · 新对局（自由对弈） ⌘⇧N · 继续对局 · — · 悔棋 ⌘Z · 判和 · 认输 · 结束对局 |
| 编辑 | **Redo removed or permanently disabled** (see D24) |
| 显示 | 对局 ⌘1 · 历史 ⌘2 · 设置 ⌘3 · — · 翻转棋盘 ⌘⇧F · 显示坐标 |
| 回放 | 播放/暂停 Space · 上一步 ← · 下一步 → · 回到开始 ⌘← · 跳到结尾 ⌘→ · 速度 0.5×/1×/2× |
| 帮助 | Mini Xiangqi 帮助 (`CommandGroupPlacement.help`) |

Every Play toolbar item appears here (HIG "Toolbars › macOS"), and the three
destinations appear under 显示 (HIG "Mac Catalyst › Navigation"). `⌘⇧F` rather
than `F` for flip leaves plain letter keys free for the coordinate-entry path in
§7.6.

---

# 4. Liquid Glass application

## 4.1 Already accepted

- "On Apple platforms, Liquid Glass is a required part of the visual and interaction direction. Use it for functional interface layers such as navigation, controls, toolbars, and contextual actions." (`interaction-design.md § Platform visual language`)
- "Preserve board readability and interaction clarity when translucent or material surfaces overlap or surround game content." (same)
- "Visual effects must not make controls, state, focus, or text harder to perceive." (same)
- "Liquid Glass belongs primarily to functional layers around the board; board-state markers must remain direct and readable rather than becoming translucent decoration." (`§ Motion and visual effects`)
- Open (`§ Need to discuss`): "Define how Liquid Glass behaves with contrast, Reduce Transparency, and different platform appearances."

## 4.2 Proven Apple guidance

- **What it is for.** "Liquid Glass forms a distinct functional layer for controls and navigation elements — like tab bars and sidebars — that floats above the content layer, establishing a clear visual hierarchy between functional elements and content." (HIG "Materials › Liquid Glass")
- **Where it must not go.** "**Don't use Liquid Glass in the content layer.** Liquid Glass works best when it provides a clear distinction between interactive elements and content, and including it in the content layer can result in unnecessary complexity and a confusing visual hierarchy. Instead, use Standard materials for elements in the content layer, such as app backgrounds. An exception to this is for controls in the content layer with a transient interactive element like Sliders and Toggles." (same)
- **Sparingly.** "**Use Liquid Glass effects sparingly.** Standard components from system frameworks pick up the appearance and behavior of this material automatically. If you apply Liquid Glass effects to a custom control, do so sparingly… Limit these effects to the most important functional elements in your app." (same)
- **Which variant.** "Use the regular variant when background content might create legibility issues, or when components have a significant amount of text, such as alerts, sidebars, or popovers." Clear is "for components that float above media backgrounds — such as photos and videos"; over bright content it needs "a dark dimming layer of 35% opacity." (same)
- **Accessibility settings change it.** "The appearance of these variants can differ in response to certain system settings, like if people choose a preferred look for Liquid Glass in their device's settings, or turn on accessibility settings that reduce transparency or increase contrast in the interface." (same)
- **Colour discipline.** "Apply color sparingly to the Liquid Glass material… reserve it for elements that truly benefit from emphasis, such as status indicators or primary actions… **Refrain from adding color to the background of multiple controls.**" (HIG "Color › Liquid Glass color")
- **Performance.** "Creating too many Liquid Glass effect containers and applying too many effects to views outside of containers can degrade performance. Limit the use of Liquid Glass effects onscreen at the same time." (SwiftUI "Applying Liquid Glass to custom views › Optimize performance")
- **Reduce Transparency semantics.** "If this property's value is true, UI (mainly window) backgrounds should not be semi-transparent; they should be opaque." (SwiftUI `EnvironmentValues.accessibilityReduceTransparency`); the setting "improves contrast and legibility by reducing transparency and blur effects on certain backgrounds" (Accessibility "Testing system accessibility features in your app › All platforms").
- **APIs.** `glassEffect(_:in:)`, `GlassEffectContainer`, `Glass.regular` / `.clear` / `.interactive()`, `PrimitiveButtonStyle.glass` and `.glassProminent`, `NSGlassEffectView` / `NSGlassEffectContainerView` on AppKit.

## 4.3 Proposal

### 4.3.1 The complete inclusion list

Liquid Glass appears in exactly these places, and nowhere else:

1. **Tab bar / sidebar** — system-provided, automatic.
2. **Navigation bar and macOS toolbar** — system-provided, automatic.
3. **The Play screen's control cluster** — one `GlassEffectContainer` holding
   悔棋 / 判和 / 认输 / 翻转棋盘 as `.glass` buttons.
4. **The replay transport bar** — one `GlassEffectContainer` holding the five
   transport controls and the speed picker.
5. **System presentations** — alerts, confirmation dialogs, sheets, context
   menus, and History swipe actions, all automatic.
6. **The natural-result card and the threefold notice** — regular variant only
   (§4.3.3).

That is **two** custom glass containers in the whole app, which satisfies both
"sparingly" and the performance note.

### 4.3.2 The complete exclusion list

Liquid Glass must **not** be applied to: the board surface; grid lines; palace
diagonals; coordinate labels; piece discs, rings, or glyphs; the selection ring;
legal-destination dots; capture rings; last-move brackets; the check treatment;
the turn-status text; the History row content; or any Help diagram.

All of these are content-layer elements, and HIG "Materials › Liquid Glass" is
unambiguous about the content layer. This is the concrete form of our contract's
"board-state markers must remain direct and readable rather than becoming
translucent decoration". The board's own background uses a flat fill, not even a
standard material — a translucent board would let whatever is behind the window
influence the perceived colour of the pieces.

### 4.3.3 The result card

Apple's guidance points two ways and both readings converge on the same answer:

- The card behaves like an alert (title, message, two actions, non-dismissible by
  tapping outside), and the regular variant is explicitly "for… components [that]
  have a significant amount of text, such as alerts, sidebars, or popovers".
- But it must not obscure the board, which the contract requires to remain fully
  visible.

**Recommend: regular Liquid Glass for the card body, placed so it never overlaps
the board** — below the board on iPhone portrait, trailing on iPhone landscape,
iPad, and Mac. Never the clear variant (there is no media background to show
through, and clear would need a dimming layer that would darken the board). The
card's buttons use `.glass`, with `结束对话`… precisely: `结束对局` on the
pre-confirmation card and `完成` on the recorded card use `.glassProminent`; the
others use `.glass`. This is **decision D9**.

This also keeps the card out of the alert vocabulary, which matters: HIG "Alerts ›
Best practices" says "Avoid using an alert merely to provide information", and an
alert would necessarily cover the board.

### 4.3.4 Behaviour under the accessibility settings

| Setting | System components | Our two custom containers |
|---|---|---|
| **Reduce Transparency** | handled automatically | replace the glass with an opaque fill (`Color(.secondarySystemBackground)` equivalent) plus a hairline separator; keep the same geometry, corner radius, and spacing so nothing reflows |
| **Increase Contrast** | handled automatically | keep the glass but raise the container's border to 1.5 pt at `.primary` strength, and switch tints to their High Contrast variants |
| **Both** | handled | opaque fill **and** the stronger border |
| **Dark appearance** | handled | no change needed; glass adapts |

Implement by reading `@Environment(\.accessibilityReduceTransparency)` and
`@Environment(\.colorSchemeContrast)` and branching the container's background
only — never the layout.

### 4.3.5 Tint discipline

**At most one tinted glass element is visible at a time**, per HIG "Color › Liquid
Glass color". Concretely: `开始对局` in either pre-start state; `结束对局` on the
result card before confirmation; `完成` after. Everything else — including 悔棋,
判和, 认输, and 翻转棋盘 — is monochrome glass. Destructive actions (删除 in
History, 认输) use the system destructive role rather than a red tinted glass
background, so red stays reserved for one meaning.

---

# 5. Motion

## 5.1 Already accepted

`interaction-design.md § Motion and visual effects` accepts the whole first-version
motion language, quoted in §2.1 above, and adds:

- "An ordinary move travels smoothly to its destination in approximately 180–240 ms."
- "A capture coordinates a brief scale-and-fade removal with the moving piece's arrival and targets an overall duration of approximately 250 ms."
- "Undo visually reverses the affected move or decision cycle and restores a captured piece when needed. Board input and another Undo remain unavailable until the transition completes."
- "Board flipping uses an approximately 300–400 ms coordinated re-layout while piece text and symbols remain upright."
- "With Reduce Motion, lifts, springs, pulses, and long-distance travel are removed in favor of a brief crossfade or immediate state update."
- "The exact durations, easing curves, scale, shadow, opacity, and feedback strength are first-version values subject to adjustment after testing on physical iPhone, iPad, and Mac hardware."
- Replay: "Autoplay starts only after a user action and waits for each move animation to finish before advancing"; speeds 0.5×, 1×, 2×; "With Reduce Motion, replay uses the accepted crossfade or immediate board update while preserving the same order and playback controls." (`§ History replay`)

## 5.2 Proven Apple guidance

- "Add motion purposefully, supporting the experience without overshadowing it. Don't add motion for the sake of adding motion." (HIG "Motion › Best practices")
- "Make motion optional. Not everyone can or wants to experience the motion in your app or game, so it's essential to avoid using it as the only way to communicate important information." (same)
- "Aim for brevity and precision in feedback animations. When animated feedback is brief and precise, it tends to feel lightweight and unobtrusive, and it can often convey information more effectively than prominent animation." (HIG "Motion › Providing feedback")
- "**Let people cancel motion.** As much as possible, don't make people wait for an animation to complete before they can do anything, especially if they have to experience the animation more than once." (same)
- Reduce Motion techniques: "Tightening animation springs to reduce bounce effects · Tracking animations directly with people's gestures · Avoiding animating depth changes in z-axis layers · **Replacing transitions in x-, y-, and z-axes with fades to avoid motion** · Avoiding animating into and out of blurs." (HIG "Accessibility › Cognitive")
- `EnvironmentValues.accessibilityReduceMotion` — "Whether the system preference for Reduce Motion is enabled." (SwiftUI "Accessible appearance › Minimizing motion")
- **Curve defaults.** `easeInOut` is "the default curve for most animations" (UIKit `UIView.AnimationCurve`); `CAMediaTimingFunctionName.default` is "the system default timing function. Use this function to ensure that the timing of your animations matches that of most system animations."
- **The only documented duration anchor found:** SwiftUI `Animation.timingCurve(_:_:_:_:duration:)` defaults to `duration: 0.35`. Apple publishes curves and APIs but **no per-interaction duration table** — see §12.

## 5.3 Proposal — the full timing table

All values are ours, provisional by the contract's own terms, and all fall inside
the accepted ranges where the contract states one.

| Interaction | Duration | Curve | Reduce Motion substitute |
|---|---|---|---|
| Select piece (ring + lift) | **140 ms** | `easeOut` | ring crossfades in over 100 ms; no scale, no shadow change |
| Reveal legal targets | **120 ms**, no stagger | `easeOut` | 100 ms crossfade (identical) |
| Deselect | **100 ms** | `easeIn` | 80 ms crossfade |
| Ordinary move, tap-committed | **200 ms** travel | `easeInOut` | 120 ms crossfade at origin and destination; the disc does not travel |
| Ordinary move, drag-committed | **120 ms** snap from release point to point centre | `easeOut` | immediate snap |
| Capture | **240 ms** total: mover travels 200 ms; captured disc scales 1.0→0.85 and fades to 0 over 160 ms beginning at t=80 ms | mover `easeInOut`, removal `easeIn` | captured disc disappears at the end of the 120 ms crossfade; no scale |
| Invalid drop (return to origin) | **180 ms** | `spring(duration: 0.18, bounce: 0.15)` | immediate return, no spring |
| Illegal-square mark | in 80 ms · hold 240 ms · out 200 ms | `easeOut` / `easeIn` | same timing, opacity only, no scale |
| Save-failure message | in 150 ms · hold 2.5 s · out 250 ms | `easeOut` / `easeIn` | same, opacity only |
| Unavailable-input pulse | **150 ms** | `easeInOut` | 120 ms opacity beat, no scale |
| AI move | identical to the ordinary-move / capture rows, preceded by a **150 ms settle** after the search returns | same | same substitutes |
| Check treatment appears | **120 ms**, then persists | `easeOut` | 120 ms crossfade, persists |
| Check pulse (once only) | ring scale 1.0→1.10→1.0 over **400 ms** | `easeInOut` | **omitted entirely** |
| Undo, one ply | **220 ms** reverse travel | `easeInOut` | 140 ms crossfade to the restored position |
| Undo, one decision cycle (2 plies) | AI ply 220 ms · 80 ms gap · human ply 220 ms ≈ **520 ms** | `easeInOut` | one 140 ms crossfade to the restored position |
| Board flip | **320 ms** coordinated re-layout; each disc travels a straight path to its mirrored point; glyphs never rotate | `easeInOut` | 160 ms crossfade between orientations |
| Result card in | **250 ms**, fade + 12 pt rise | `spring(duration: 0.25, bounce: 0.1)` | 200 ms fade only, no translation |
| Result card → recorded state | **200 ms** content crossfade | `easeInOut` | unchanged (already a fade) |
| Threefold notice in | as result card | as result card | as result card |
| Replay step, manual | **200 ms**, same as an ordinary move | `easeInOut` | 120 ms crossfade |
| Autoplay | move animation at the selected rate (2× halves, 0.5× doubles every duration above), plus a **400 ms** inter-move gap at 1× | as above | crossfade substitute; identical order, gaps, and controls |

### 5.3.1 Interruption

The contract disables board input during an Undo transition, and autoplay waits
for each animation. HIG "Motion › Providing feedback" pushes the other way: "Let
people cancel motion… especially if they have to experience the animation more
than once." Repeated Undo is exactly that case.

**Recommend a rule that satisfies both:** a running board animation is never
queued behind and never blocks a *new* request. A second Undo (or a manual replay
step during autoplay) **snaps the running animation to its end state immediately**
and starts the next one. Input remains disabled only for the sub-frame during
which the core is applying the mutation, not for the animation's duration. This
preserves the contract's real intent — no two overlapping mutations, no
half-applied state — while removing the wait. It is a felt-behaviour change, so it
needs the owner: see conflicts **C2** and **C3**.

### 5.3.2 Reduce Motion, stated as one rule

Under `accessibilityReduceMotion`: **no board element ever translates.** Every
positional change becomes a crossfade between the before and after states, at the
durations in the table. Scale, spring, shadow-elevation, and the check pulse are
removed. Order, sequencing, and every control stay identical — which is what the
contract already requires for replay, generalised to the whole board.

This matches HIG "Accessibility › Cognitive" directly: "Replacing transitions in
x-, y-, and z-axes with fades to avoid motion" and "Tightening animation springs
to reduce bounce effects."

---

# 6. Sound and haptics

## 6.1 Already accepted

- "Sound and haptics are part of the intended experience. They must reinforce meaningful actions and game events, **remain optional where platform conventions expect user control**, and **avoid being the only way information is conveyed**." (`interaction-design.md § Sound and haptics`)
- Accessibility requires "Alternatives for information otherwise communicated through sound, haptics, or animation." (`§ Accessibility`)
- Testing already requires: "Verify that sound, haptics, color, motion, and visual effects are never the sole carrier of required information" and "Verify unavailable hardware and muted-audio behavior." (`testing.md § UI, accessibility, sound, and haptics`)
- Open (`§ Need to discuss`): "Define sound events, sound design, volume or mute controls, and platform differences." and "Define haptic events and behavior on devices without haptic support."

## 6.2 Proven Apple guidance

- **Silent mode.** "People switch a device to silent when they want to avoid being interrupted by unexpected sounds… In this scenario, they also want to silence nonessential sounds, such as keyboard clicks, **sound effects, game soundtracks**, and other audible feedback. When a device is in silent mode, it plays only the audio that people explicitly initiate, like media playback, alarms, and audio/video messaging." (HIG "Playing audio")
- **Category table** (HIG "Playing audio › Best practices"): *Ambient* — "Sound isn't essential, and it doesn't silence other audio… Responds to the silence switch. Mixes with other sounds. Doesn't play in the background." *Solo ambient* — responds to the silence switch, doesn't mix. *Playback* — "Doesn't respond to the silence switch."
- `AVAudioSession.Category.ambient`: "The category for an app in which sound playback is nonprimary — that is, your app also works with the sound turned off… audio from other apps mixes with your audio. Screen locking and the Silent switch (on iPhone, the Ring/Silent switch) silence your audio."
- **Don't touch system volume.** "Adjust levels automatically when necessary — don't adjust the overall volume. Your app can adjust relative, independent volume levels… but the system volume always governs the final output." (HIG "Playing audio › Best practices")
- **macOS has no audio session.** "Apple platforms, other than macOS which primarily leaves control to an app, provide an audio experience that the operating system manages." (AVFoundation "Configuring your app for media playback › Configure the audio session")
- **Notify others on deactivation** via `AVAudioSession.SetActiveOptions.notifyOthersOnDeactivation` (HIG "Playing audio › Best practices": "Let other apps know when your app finishes playing temporary audio").
- **Haptic hardware is not universal.** "Before you create and configure a haptic engine, check the hardware capabilities to see what type of feedback the device supports. **Some devices don't support haptic feedback, including iPad, iPod touch, and Apple Vision Pro.**" — check `CHHapticEngine.capabilitiesForHardware().supportsHaptics`. (Core Haptics "Preparing your app to play haptics › Check for device compatibility")
- **The simple API is a documented no-op off iPhone.** SwiftUI `SensoryFeedback.selection`, `.impact`, `.impact(flexibility:intensity:)`, and `.success` each state "Only plays feedback on iOS and watchOS."
- **macOS haptics are trackpad-only.** `NSHapticFeedbackManager` "provides access to the haptic feedback management attributes on a system with a Force Touch trackpad." (AppKit "Sound, Speech, and Haptics › Haptics")
- **Haptics must be optional and consistent.** "Use haptics consistently throughout your app or game… **Make haptics optional.** Let people turn off or mute haptics, and make sure people can still enjoy your app or game without them." "In most apps, prefer playing short haptics that complement discrete events." "Prefer using haptics to complement other feedback in your app or game." (HIG "Playing haptics › Best practices")
- **Pair sound with haptics and with visuals.** "If your interface conveys information through audio cues — such as a success chime, error sound, or game feedback — consider pairing that sound with matching haptics for people who can't perceive the audio… **Augment audio cues with visual cues.**" (HIG "Accessibility › Hearing")

## 6.3 Proposal

### 6.3.1 Audio session

- **iOS / iPadOS: `.ambient`.** The app is fully playable with sound off, so
  `ambient` is exactly the documented fit; it respects the Ring/Silent switch and
  mixes, so a user's music keeps playing during a game.
- Activate the session lazily, the first time a sound is about to play; deactivate
  with `.notifyOthersOnDeactivation` when the Play or replay screen is left.
- **macOS: no session.** Play through `AVAudioPlayer` at the app's own relative
  level; the system output volume governs. Never modify system volume.
- No background audio mode, no Now Playing integration, no remote-command
  handling — the app never plays audio it did not initiate, so HIG's "Respond to
  audio controls only when it makes sense" resolves to "not at all".

### 6.3.2 Sound events — six, and no more

| # | Event | Character | Length |
|---|---|---|---|
| 1 | 落子 — a move commits (human or AI) | crisp wood-on-board click | ~60 ms |
| 2 | 吃子 — a capture commits | the same click with a lower, fuller body — **distinguishable by timbre, not just volume** | ~110 ms |
| 3 | 将军 — the move gives check | short two-note cue, layered on top of 1 or 2 | ~250 ms |
| 4 | 对局结束 — a natural terminal result is reached | one short resolving cue, **the same for win, loss, and draw** | ~600 ms |
| 5 | 无效 — illegal square, or a save failure | soft muted thud, deliberately not an alarm | ~80 ms |
| 6 | 判和可用 — a threefold repetition first becomes claimable | one soft tone | ~180 ms |

Deliberately silent: selection, deselection, drag pickup and drop, undo, board
flip, navigation, replay stepping, and **autoplay** (a machine-gun of clicks at 2×
would be unpleasant, and the accepted contract already animates each move —
**decision D26**).

The AI's move uses the *same* sounds as a human move (#1/#2), so a move reads as
one physical event regardless of who made it. This matches the accepted rule that
"An AI move uses the same move language".

Wins and losses share cue #4 because this is a teaching app for a small internal
group; a distinct "you lost" sting would add discouragement without adding
information the result card does not already give.

### 6.3.3 Haptic events — five, iPhone only

Implemented with SwiftUI `sensoryFeedback(_:trigger:)`, which is documented to do
nothing on iPadOS, macOS, and visionOS — so the calls are safe unconditionally and
no capability branch is needed for correctness. Where Core Haptics is used
directly (none is proposed for the MVP), gate on
`CHHapticEngine.capabilitiesForHardware().supportsHaptics`.

| Event | Feedback |
|---|---|
| Piece selected | `.selection` |
| Move commits | `.impact(flexibility: .solid, intensity: 0.5)` |
| Capture commits | `.impact(flexibility: .rigid, intensity: 0.8)` |
| Illegal square, or save failure | `.warning` |
| Natural terminal result reached | `.success` |

Nothing for undo, flip, navigation, replay, or autoplay — HIG "Playing haptics ›
Best practices": "Avoid overusing haptics. Sometimes a haptic can feel just right
when it happens occasionally, but become tiresome when it plays frequently."

**Per-platform statement for the record:** iPhone gets all five. **iPad and Mac get
none** — this is the documented hardware reality, not a scoping shortcut, and no
substitute (a louder sound, a bigger animation) should be introduced to
"compensate", because every one of these events already has a visual carrier.
Mac trackpad alignment feedback (`NSHapticFeedbackManager`) is not used: there is
no drag-to-align interaction that warrants it.

### 6.3.4 User controls

**Recommend a new Settings group `声音与触感` with two toggles:**

- **音效** — on by default.
- **触感反馈** — on by default; the row is **hidden entirely** on devices where
  haptics are unavailable, rather than shown disabled.

No volume slider: "the system volume always governs the final output."

This is a **product-scope addition** — `product.md` currently lists only the
人机对弈默认设置 group and 删除前确认 — so it needs the owner's approval and a
`product.md` update, not just an `interaction-design.md` update. See **decision
D15** and conflict **C7**.

### 6.3.5 The never-sole-carrier guarantee, stated as a checkable table

| Event | Sound | Haptic | Visual | VoiceOver |
|---|---|---|---|---|
| Move commits | #1 | impact | move animation + last-move brackets | move announcement |
| Capture | #2 | impact (rigid) | capture animation + brackets | announcement includes 吃 |
| Check | #3 | — | king double ring + badge + `将军` in the status | announcement + king point value |
| Result reached | #4 | success | result card | focus moves to the card |
| Illegal square | #5 | warning | crossed circle on the point | announcement |
| Save failure | #5 | warning | transient message by the status | high-priority announcement |
| Claim available | #6 | — | `可判和` affordance | affordance is an element with a label |

Every row has at least two non-audio channels. This table is directly testable
and is proposed as acceptance criterion A16/A18 in §7.8.

---

# 7. Accessibility

## 7.1 Already accepted

- The interaction design must consider VoiceOver labels/values/actions/reading order, keyboard interaction and focus, non-colour state cues, Dynamic Type, Reduce Motion and Reduce Transparency, and alternatives for information carried by sound, haptics, or animation (`interaction-design.md § Accessibility`).
- "Keyboard and VoiceOver use an equivalent select-piece, inspect-destinations, and select-destination flow **rather than requiring a drag gesture**." (`§ Move input`)
- Board flipping "has a localized accessibility label and an equivalent keyboard command where keyboard input is supported." (`§ Board orientation`)
- History actions: "Pointer context menus, keyboard commands, and screen-reader custom actions — VoiceOver on Apple platforms… expose equivalent Pin or Unpin, Share, and Delete operations without adding permanent row buttons." (`§ History library`)
- Turn ownership, activity, and input availability must not be colour-only (`§ Turn status`).
- Testing already requires "an end-to-end nonvisual board interaction" and tests of Increase Contrast, Differentiate Without Color, Reduce Motion, and Reduce Transparency (`testing.md § UI, accessibility, sound, and haptics`).
- Open (`§ Need to discuss`): "Define accessibility acceptance criteria and the board's VoiceOver interaction model."

## 7.2 Proven Apple guidance

- **Grouping and order.** "Specify how elements are grouped, ordered, or linked. Proximity, alignment, and other visible contextual cues help sighted people perceive the relationships between elements. Examine your app for places where relationships among elements are visual only. Then, describe these relationships to VoiceOver." "VoiceOver reads elements in the same order people read content in their active language and locale." (HIG "VoiceOver › Navigation")
- **Announce changes.** "Inform VoiceOver when visible content or layout changes occur. People may find an unexpected content or layout change confusing… It's crucial to report visible changes so VoiceOver and other assistive technologies can help people update their understanding of the content." (same)
- **Rotors are the documented answer to "too many elements".** "Support the VoiceOver rotor when possible. People can use an interface element called the VoiceOver rotor to navigate a document or webpage by headings, links, and other content types. You can help people navigate content in your app by identifying these elements to the rotor." (same); "An accessibility rotor is a shortcut that enables users to quickly navigate to specific elements of the user interface" (SwiftUI "Accessible navigation").
- **Announcement priorities.** "When `low` is specified, announcements are queued and spoken when other speech utterances have completed. When `default` is specified, announcements will interrupt existing speech, but are interruptible if a new speech utterance is started. When `high` is specified, announcements will interrupt other speech and cannot be interrupted once started." (Foundation `AnnouncementPriorityAttribute`)
- **Notification kinds.** `AccessibilityNotification.Announcement`, `.LayoutChanged`, `.ScreenChanged` — the latter two optionally "include a parameter that contains the accessibility element for VoiceOver to move to after processing the notification." (Accessibility `AccessibilityNotification`)
- **Extra detail without bloating the label.** `accessibilityCustomContent(_:_:importance:)` — "add information you want accessibility users to be able to access about this element, beyond the basics of label, value, and hint… High-importance information gets read out immediately, while default-importance information must be explicitly asked for by the user."
- **Containers and actions.** `accessibilityElement(children: .contain)` — "Any child accessibility elements become children of the new accessibility element." `accessibilityAction(named:)`, `accessibilityActions(_:)`, `accessibilityActions(category:_:)`, `accessibilitySortPriority(_:)`, `accessibilityRespondsToUserInteraction(_:)`, `accessibilityFocused(_:equals:)`.
- **Dynamic Type.** "Make sure your app's layout adapts to all font sizes… turn on Larger Accessibility Text Sizes… and confirm that your app remains comfortably readable." "Keep text truncation to a minimum as font size increases." "Consider adjusting your layout at large font sizes… consider using a stacked layout where text appears above secondary items." "Maintain a consistent information hierarchy regardless of the current font size." (HIG "Typography › Supporting Dynamic Type"); `DynamicTypeSize.isAccessibilitySize`.
- **Prioritise.** "Prioritize important content when responding to text-size changes. Not all content is equally important… they don't always want to increase the size of every word on the screen." (HIG "Typography › Conveying hierarchy")
- **Keyboard.** "Support Full Keyboard Access when possible. Available in iOS, iPadOS, macOS, and visionOS, Full Keyboard Access lets people navigate and activate windows, menus, controls, and system features using only the keyboard." "Respect standard keyboard shortcuts." And, importantly for a grid: "**avoid supporting keyboard navigation for controls**, such as buttons, segmented controls, and switches. Instead, let people use Full Keyboard Access to activate controls." (HIG "Keyboards › Best practices")
- **Focus APIs.** `focusable(_:interactions:)`, `focusSection()`, `KeyPress` / `onKeyPress`, `FocusState` (SwiftUI "Focus").
- **Pointer effects.** iPadOS defines highlight, lift, and hover. "By default, iPadOS applies magnetism to elements that use the lift effect… and the highlight effect… but not to elements that use hover. Because an element that supports hover doesn't transform the default pointer shape, adding magnetism could be jarring and might make people feel that they've lost control of the pointer." (HIG "Pointing devices › Pointer magnetism", "› Pointer shape and content effects")
- **Contrast and colour** — as quoted in §1.2; plus `EnvironmentValues.accessibilityDifferentiateWithoutColor` and `ColorSchemeContrast`.

## 7.3 The board's VoiceOver model

### 7.3.1 Structure

- The board is a **container**: `.accessibilityElement(children: .contain)`, label `棋盘`, value `7 行 7 列`.
- **Each of the 49 points is its own element.** Not a merged blob (which would be unnavigable) and not grouped by rank (which would hide individual squares). Apple has no grid-specific rule; this follows from the grouping principle in HIG "VoiceOver › Navigation" — the relationship between a coordinate and its occupant is exactly the "visual only" relationship that must be described.
- **Reading order follows the on-screen orientation**: rank by rank from the top of the current view to the bottom, each rank leading→trailing. With Red at the bottom that is `a7…g7`, `a6…g6`, …, `a1…g1`. **Flipping the board flips the reading order**, so spoken order and visual order never disagree. This is **decision D18**.

### 7.3.2 What each square says

`<coordinate>，<side><piece>` for an occupied point, `<coordinate>，空` for an empty one:

- `d1，红帅`
- `c7，黑马`
- `e4，空`

**Value** carries live state, so it re-announces when it changes:

| Condition | Value |
|---|---|
| this piece is selected | `已选中` |
| a piece is selected and this empty point is legal | `可移动到` |
| a piece is selected and this enemy piece is capturable | `可吃子` |
| this is the king of a side currently in check | `被将军` |
| otherwise | (none) |

**Traits.** A point that the user can act on right now gets `.isButton`; the
selected point also gets `.isSelected`. Points that are not currently actionable
get `accessibilityRespondsToUserInteraction(false)` so Full Keyboard Access and
Switch Control skip them — but they remain readable by exploration, because
reading the position is the point of the board.

**Custom content** (`accessibilityCustomContent`, default importance, so it is
available on request and never bloats the label):

- `上一步起点` / `上一步终点` where applicable
- `本方棋子` / `对方棋子`
- on a selected piece: `合法走法 5 个`

### 7.3.3 Making a move without dragging

Exactly the accepted tap flow, with no gesture beyond VoiceOver's own activate:

1. **Activate an own movable piece** → it is selected; its value becomes `已选中`;
   one `Announcement` at default priority: `已选中 c1 红马，5 个合法走法`. The
   legal destinations are *not* read out in full — a chariot can have a dozen, and
   a wall of coordinates is worse than useless. They are reachable instantly
   through the rotor below.
2. **Activate a point whose value is `可移动到` or `可吃子`** → the move commits.
3. **Activate the selected piece again**, or use the container action `取消选择` →
   deselection. Activating an illegal point does nothing to the selection
   (accepted behaviour) and announces `不能走到这里` at default priority.

### 7.3.4 Custom rotors — the single biggest win

Scrubbing 49 elements to find 5 legal destinations is the difference between a
playable and an unplayable board. Four **named custom rotors** on the board
container (no system rotor is replaced):

| Rotor | Entries |
|---|---|
| **合法走法** | while a piece is selected: exactly the destinations reported by `mxq_game_legal_moves_from`, in reading order. Empty otherwise. |
| **我方棋子** | the human's remaining pieces (in Free Play: the side to move's pieces) |
| **对方棋子** | the opposing pieces |
| **上一步** | two entries — the last move's origin and destination |

This is **decision D17**, and it is the one accessibility item I would not
compromise on.

### 7.3.5 Container actions

On the board container, via `accessibilityActions`: `悔棋`, `翻转棋盘`,
`取消选择`, and **`朗读当前局面`** — a compact spoken summary
(`轮到红方，你执红。红方 11 子，黑方 10 子。上一步：黑马 c7 到 d5，吃 红兵。`).
The last one is cheap to build from `MxqGameStatus` and is a genuine education aid
for a sighted user with low vision as much as for a VoiceOver user.

### 7.3.6 Announcements

| Occasion | Mechanism | Priority | Text shape |
|---|---|---|---|
| AI move commits | `Announcement` | default | `AI 黑马 c7 到 d5，吃 红兵，将军` |
| Human move commits | `Announcement` | low | `红马 c1 到 d3` |
| AI starts thinking | `Announcement`, queued | low | `AI 思考中` — **once**, never repeated |
| Illegal square | `Announcement` | default | `不能走到这里` |
| Save failure | `Announcement` | **high** | the same copy as the visible message (D12) |
| Threefold becomes claimable | `Announcement` | default | `局面已三次重复，可以和棋结束` (matches the accepted notice) |
| Natural result reached | `ScreenChanged`, argument = the result card's title element | — | focus moves to the card, which reads `红方获胜，将死` |
| Board flipped | `LayoutChanged` | — | reading order has changed, so VoiceOver must be told |

Rationale for the priorities is the documented semantics: `high` "cannot be
interrupted once started", which is right for a save failure the user must not
miss and wrong for a repeated illegal tap; `low` "queued and spoken when other
speech utterances have completed", which is right for the user's own move, whose
result they can already feel.

Check is announced *as part of* the move announcement **and** encoded persistently
in the king point's value, so it survives re-reading — a transient announcement
alone would make check audible-only-once, which is the sound-and-haptics
never-sole-carrier failure mode in a different guise.

## 7.4 Dynamic Type

- **All UI text uses text styles.** Status element `.headline` + `.subheadline`; control labels `.body`; History rows `.body` + `.footnote`; Help body `.body`; coordinates `.caption`.
- **The board does not scale with Dynamic Type.** It is a spatial diagram sized to the available area; the glyphs scale with the *board*, not with the text setting. Justification: HIG "Typography › Conveying hierarchy" — "Prioritize important content when responding to text-size changes… they don't always want to increase the size of every word on the screen." At the 44 pt pitch floor the glyph is ~23 pt, more than double the 11 pt iOS minimum, so legibility is not the concern. This is a deliberate, recorded deviation — see conflict **C8** and **decision D19**.
- **At `dynamicTypeSize.isAccessibilitySize`:** the Play control cluster restacks from a horizontal row of symbol+label buttons to a vertical stack; the status element wraps to two lines; the coordinate labels are hidden (VoiceOver already speaks coordinates, and at those sizes they would consume a quarter of the board's edge). The board shrinks to make room but **never below a 44 pt pitch**; if the remaining space would force that, the control cluster collapses to a single `更多` button opening a sheet.
- **Everywhere else** (History, Settings, Help, all confirmations) the layout is standard SwiftUI `List`/`Form` content and scales without special handling. Verify no truncation at `.accessibility5` (criterion A9).

## 7.5 Increase Contrast

`@Environment(\.colorSchemeContrast) == .increased` drives:

| Element | Change |
|---|---|
| Grid lines and palace diagonals | 1 → 1.5 pt, High Contrast colour variant |
| Piece rings | +0.5 pt each |
| Piece glyph | `.semibold` → `.bold` |
| Board surface | High Contrast variant, pushed further from the disc luminance |
| Dots, capture rings, brackets, check rings | stroke +0.5 pt |
| Coordinates | `.secondary` → `.primary` |
| Custom glass container | stronger border (§4.3.4) |

All colour changes come from asset-catalog High Contrast variants rather than
runtime maths, per Xcode "Specifying your app's color scheme".

## 7.6 Keyboard, on iPad and Mac

**Board navigation.** The board is **one focusable view** carrying an internal
cursor, not 49 focusable views. HIG "Keyboards › Best practices" says plainly to
avoid per-control keyboard navigation on iPadOS and let Full Keyboard Access
handle activation; 49 tab stops would also make Tab traversal of the screen
useless. Wrap it in `focusSection()` and handle keys with `onKeyPress`:

| Key | Action |
|---|---|
| ← ↑ → ↓ | move the cursor one point, in screen directions (so it follows the flip) |
| Space / Return | select the piece under the cursor, or commit a move to it |
| Esc | deselect |
| Home / End | first / last point of the current rank |
| `a`–`g` then `1`–`7` | jump the cursor directly to that square; two such pairs in a row commit a move (e.g. `c1` `d3`) |

The direct-coordinate path is a small addition with an outsized payoff for a
teaching app: it is fast, it reinforces the coordinate vocabulary, and it is the
same vocabulary VoiceOver speaks and the archive stores.

The cursor draws a **focus ring** at the point — a 2 pt ring in the system focus
colour, distinct in shape from the selection ring (which sits on the disc) and
from the capture ring (dashed).

**Shortcuts** are listed in §3.3.4. Two rules: respect the standard set (HIG
"Keyboards › Best practices"), and **⌘Z is 悔棋 while Redo does not exist** —
`product.md § Target-MVP play modes` states "Redo is not." The Edit menu's Redo
item must be removed rather than left present-and-dead (**decision D24**).

**Full Keyboard Access** must be verified on for iPad and Mac (criterion A14).

## 7.7 Pointer, and Differentiate Without Color

**Pointer.** Board points use a **hover** effect: the cell under the pointer takes
a faint fill and the pointer keeps its default shape. Deliberately **not** lift or
highlight, because HIG "Pointing devices › Pointer magnetism" documents that
magnetism applies to those two and not to hover — and magnetism across 49
adjacent targets would feel sticky and imprecise. Controls and toolbar items get
the system effects automatically.

**Hover preview.** When nothing is selected, hovering an own movable piece shows
its legal destinations at half strength (thinner dots, no ring thickening).
This is a real teaching feature and is *not* an AI hint — it reports legality,
which the accepted design already reveals on selection, and never an evaluation,
which `product.md § Target-MVP exclusions` rules out. Still user-visible, so:
**decision D16**.

**Differentiate Without Color.** The design's answer is that the flag should
change **nothing**. Side is carried by glyph and by solid-vs-outlined disc;
markers are carried by shape; History swipe actions already carry "icon and text
as well as color" (accepted). Reading
`@Environment(\.accessibilityDifferentiateWithoutColor)` and *adding* something
would be an admission that the default is colour-dependent. **The correct outcome
is that turning the setting on produces a pixel-identical board** — and that is a
sharper test than any additive treatment. Stated as criterion A11.

## 7.8 Acceptance criteria a tester can check

**VoiceOver**

- **A1.** With VoiceOver on and Red at the bottom, swiping right through the board container reads exactly 49 elements in the order `a7`…`g7`, `a6`…`g6`, …, `a1`…`g1`, each beginning with its coordinate.
- **A2.** Every occupied point announces side and piece; every empty point announces `空`.
- **A3.** Activating an own movable piece changes its value to `已选中` and posts exactly one announcement containing the legal-move count.
- **A4.** With a piece selected, the `合法走法` rotor contains exactly the destinations the core reports for that piece, and nothing else. With nothing selected, it is empty.
- **A5.** A complete human-versus-AI game — start, ten moves including a capture and a check, checkmate, result confirmation — can be played with VoiceOver on and the screen curtain enabled, using no drag gesture.
- **A6.** Each AI move produces exactly one announcement naming origin, destination, the captured piece if any, and check if any.
- **A7.** When a natural result is reached, VoiceOver focus moves to the result card and speaks the result and its reason.
- **A8.** The king's point value contains `被将军` for as long as that side is in check, and is re-spoken on re-reading (not only at the moment check occurs).
- **A9.** Flipping the board posts a layout-changed notification and the subsequent reading order is `a1`…`g1` first.

**Visual accessibility**

- **A10.** At `.accessibility5` on the smallest supported iPhone, no Play-screen text is truncated, every control's label is fully readable, and the board pitch is ≥ 44 pt.
- **A11.** With Increase Contrast on, in both light and dark, glyph-vs-disc contrast measures ≥ 4.5:1 and grid-line-vs-surface ≥ 3:1 (Accessibility Inspector or a WCAG calculator).
- **A12.** With Differentiate Without Color on, the board is pixel-identical to the same position with it off; and with the display in greyscale a tester can name the side of every piece and tell a legal-empty destination from a legal capture.
- **A13.** With Reduce Transparency on, no board or control surface is translucent anywhere on the Play, History, or Settings screens.
- **A14.** With Reduce Motion on, no piece translates across the board in any interaction — move, capture, undo, flip, replay, autoplay — and replay order, gaps, and controls are unchanged.

**Input**

- **A15.** With Full Keyboard Access on (iPad) and with a hardware keyboard (Mac), a complete game can be played with the keyboard alone; the board cursor's focus ring is visible at all times.
- **A16.** Every command in the Play controls appears in the menu bar on Mac and iPad with the same label, and Redo is absent or permanently disabled.

**Sound and haptics**

- **A17.** With the Ring/Silent switch set to silent on iPhone, the app produces no sound, remains fully playable, and every event that had a sound still has a visible counterpart (§6.3.5 table).
- **A18.** On an iPad and on a Mac, no haptic is attempted and no capability error is logged; the experience is otherwise identical to iPhone.
- **A19.** Turning off 音效 and 触感反馈 removes all sound and haptics; every row of the §6.3.5 table still has at least one visible and one VoiceOver channel.
- **A20.** Music playing from another app continues uninterrupted through an entire game on iPhone and iPad.

---

# 8. Help and education surface

## 8.1 Already accepted

`interaction-design.md § Help` and `product.md § Target-MVP play modes`:

- "Help is a read-only Mini Xiangqi rules reference covering the board, the pieces and their movement, check and checkmate, stalemate, repetition and the claimable draw, perpetual check, and perpetual chase, plus a short explanation of the app's own controls."
- "Help is reachable from Settings and from the game screen without abandoning or pausing state: opening help never modifies the active game, and returning restores the exact prior context."
- "Help content is static reference material. It does not analyze the current position, suggest moves, or offer interactive lessons or drills."
- "Help text follows the same localization requirements as the rest of the interface."
- Excluded: structured lessons, practice drills, AI hints (`product.md § Target-MVP exclusions`).
- Open: "Define help entry points, content organization, and illustrations within the accepted read-only rules-reference scope."

## 8.2 Proven Apple guidance

- "Let your app's tasks inform the types of help people might need… directly relate the help you provide to the precise action or task people are doing right now and make it easy for people to dismiss or avoid the help if they don't need it." (HIG "Offering help › Best practices")
- "Use relevant and consistent language and images in your help content… be sure the terms and descriptions you use are consistent with the platform. For example, don't write copy that tells people to click a button on an iPhone or tap a menu item on a Mac." (same)
- "Avoid bloating your help content by explaining how standard components or patterns work. Instead, describe the specific action or task that a standard element performs in your app or game… preferring animation or graphics to educate instead of a lengthy description." (same)
- **macOS help-button placement.** "Include no more than one help button per window." "Use a help button within a view, not in the window frame. For example, avoid placing a help button in a toolbar or status bar." (HIG "Buttons › Help buttons")
- **Menu placement.** `CommandGroupPlacement.help` — "Placement for commands that present documentation and helpful information to people." (SwiftUI)
- "Prefer dismissing views with an explicit action." (HIG "Accessibility › Cognitive")

## 8.3 Proposal

### 8.3.1 Presentation

**One sheet on every Apple platform**, containing its own `NavigationStack`
(a two-column split inside the sheet at regular width). A sheet structurally
guarantees the accepted requirement that "returning restores the exact prior
context", because the underlying screen is never torn down; and it stays inside
the single-main-window boundary (`product.md`), which a separate Help window
would not. Dismissal is an explicit `完成` button — no swipe-only dismissal, per
HIG "Accessibility › Cognitive".

### 8.3.2 Structure — seven topics, in learning order

The topic list maps one-to-one onto the accepted coverage list, so nothing is
added and nothing is dropped:

| # | Topic | Contents |
|---|---|---|
| 1 | **棋盘** | 7×7 points (not squares), the unbroken grid with **no river**, the two 3×3 palaces, coordinates `a`–`g` / `1`–`7`, who sits at the bottom and why |
| 2 | **棋子与走法** | one subsection per type — 帅/将, 俥/車, 傌/馬, 炮/砲, 兵/卒 — each showing the character pair, the movement rule, and a diagram. Explicitly notes that **Mini Xiangqi has no advisors and no elephants**, and that soldiers move and capture sideways **from the start of the game** |
| 3 | **将军与将死** | check, legal evasion, checkmate — and the **facing-kings** rule, which belongs here because it is a king-safety rule |
| 4 | **困毙** | no legal move is a **loss** for the side that cannot move. Given its own topic because it differs from international chess and is the single rule a transferring player is most likely to get wrong |
| 5 | **重复局面与判和** | threefold repetition, the third occurrence counting the first time the position stood on the board, that the draw is **claimable and not automatic**, and the `可判和` affordance |
| 6 | **长将与长捉** | perpetual check loses for the checker; perpetual chase of an unprotected target loses for the chaser; **kings and soldiers are excluded as chase targets**; check outranks chase; mutual same-class violations are a draw |
| 7 | **界面说明** | tap and drag to move; what the dot, the dashed ring, the brackets, and the check treatment mean; undo; flip; that a new game saves the current one to History; replay; share and import |

Topic 6's wording must track `xiangqi-rules.md`; note that the mutual and mixed
cases there are accepted at the rule level but their fixtures are deferred, so
Help should state the rule without implying the app has been proved to adjudicate
every construction.

### 8.3.3 Illustrations — yes, and how

A rule **can** be illustrated with a position without leaving the accepted scope,
because a fixed diagram is reference content, not analysis of the user's game.
HIG "Offering help › Best practices" actively prefers graphics to long prose.

**Recommend: every rule page embeds a static board diagram rendered by the same
board view used in play**, driven by a fixed FEN plus optional markers, with:

- `.allowsHitTesting(false)` and no gesture recognisers,
- a single combined accessibility element whose label is a prose description of what the diagram shows,
- the diagram FENs authored in a Help resource file, **never** read from the live game.

Four benefits, all of which fall out of decisions already made: one visual
identity across the app (accepted); no bitmap assets, hence no text baked into
artwork (accepted); automatic light/dark/Increase Contrast/Reduce Transparency
correctness; and no separate illustration pipeline to maintain.

**Boundary to state explicitly:** Help diagram FENs are illustrations. They are
**not** rules fixtures and must not live in or be confused with
`fixtures/rules/`, whose identifiers, schema, and immutability rules are owned by
`xiangqi-rules.md`.

Diagrams are static images of a position, not animations — the accepted scope
says static reference material, and an animated "watch the horse move" would
edge toward a lesson.

### 8.3.4 Entry points — three, one destination

1. **Settings → 帮助** row (accepted).
2. **Play screen** — a `questionmark.circle` toolbar item on iOS and iPadOS.
3. **Menu bar → 帮助 › Mini Xiangqi 帮助** on macOS and iPadOS
   (`CommandGroupPlacement.help`, `⌘⇧/`).

**On macOS, entry point 2 is the menu, not a toolbar button.** HIG "Buttons ›
Help buttons" says to avoid placing a help button in a toolbar or status bar on
the Mac. The contract's requirement is that help be "reachable from the game
screen"; the 帮助 menu satisfies that without leaving the game screen. See
conflict **C5**.

**Context landing.** Opening help *from the game screen* lands on topic 7
(界面说明); opening *from Settings* lands on the topic list. This follows "directly
relate the help you provide to the precise action or task people are doing right
now" while keeping one Help surface. **Decision D21.**

### 8.3.5 Out of scope for the MVP

No search inside Help, no glossary, no printable rules, no per-piece animation, no
"try it" board, and no link from a result card to the rule that produced it. Each
of those is defensible later; none is needed for a seven-topic reference.

---

# 9. Localization

## 9.1 Already accepted

- "The interface must be designed for localization. User-facing text must not be embedded in visual assets, and layouts must tolerate different text lengths. Terminology for Xiangqi pieces, rules, results, and controls must be consistent within each supported language." (`interaction-design.md § Localization`)
- The accepted UI copy is written in simplified Chinese throughout (`§ Starting and configuring a game`, `§ Saving the active game…`, `§ Natural result presentation`, `§ Claimable threefold repetition`, `§ History library`, `§ Insufficient memory for AI play`).
- The serialized result vocabulary is fixed and closed: `outcome` ∈ {`red-wins`, `black-wins`, `draw`, `none`} and `end_reason` ∈ {`checkmate`, `stalemate`, `perpetual-check`, `perpetual-chase`, `threefold-repetition`, `mutual-perpetual-check`, `mutual-perpetual-chase`, `resignation`, `ended-early`} (`game-data.md § Accepted serialized identifier vocabulary`).
- Open: "Define supported languages, Xiangqi terminology, and localization review." (`interaction-design.md § Need to discuss`); "Define localization languages and the localization review process." (`testing.md § Need to discuss`)

## 9.2 Proven Apple guidance

- **Pseudolanguages for testing expansion.** Xcode ships Double-Length ("Doubles the length of localizable strings to test whether views adjust their size and position"), Right-to-Left, Accented ("to test whether views adjust to languages that have high and low ascenders"), Bounded String ("Wraps strings to identify places where localized strings may appear truncated"), and Tall ("Simulates languages that require significantly more vertical space"). (Xcode "Preparing your interface for localization › Run your app using pseudolanguages")
- **String catalogs** are the current mechanism (Xcode "Supporting multiple languages in your app", "Localizing and varying text with a string catalog").
- **Don't flip universal marks.** "Don't flip logos or universal signs and marks. Displaying a flipped logo confuses people… People expect universal symbols and marks like the checkmark to have a consistent appearance, so avoid flipping them." (HIG "Right to left › Interface icons")
- **Paragraph alignment follows the language, not the context.** "Align a paragraph based on its language, not on the current context." (HIG "Right to left › Text alignment")
- **Layout adaptability includes locale.** "Locale-based internationalization features like left-to-right/right-to-left layout direction, date/time/number formatting, font variation, and **text length**." (HIG "Layout › Adaptability")
- **System fonts.** HIG "Typography › Using system fonts" lists SF Pro, SF Compact, SF Arabic, SF Armenian, SF Georgian, SF Hebrew, SF Mono, and New York. **No Chinese variant appears** — see §12.
- Typesetting language automatically accounts for the preferred languages' metrics (SwiftUI `TypesettingLanguage.automatic`).

## 9.3 Proposal

### 9.3.1 Supported languages

**Recommend: Simplified Chinese (`zh-Hans`) only for the MVP**, as the development
language and base localization.

Reasons: distribution is internal TestFlight to a small group
(`product.md § Product identity and distribution`); every accepted string is
already written in Chinese; and a half-finished English localization is worse
than a single-language app, because it produces mixed-language screens.

**But build with a String Catalog from day one**, with every user-facing string —
including piece names used in VoiceOver labels, result reasons, and Help body
text — as a catalog entry. Adding `en` or `zh-Hant` then becomes additive and
testable rather than a rewrite.

**Consequence the owner should confirm:** a device set to English will show
Chinese. That is normal for an internal single-language app but it is a visible
choice. **Decision D22.**

### 9.3.2 Piece characters and how they behave

Per §1.3.4, recommend the differentiated set 帅/将, 俥/車, 傌/馬, 炮/砲, 兵/卒,
rendered as **text**, never artwork.

Behaviour rules:

- The glyphs are **game content, not interface copy**. They do **not** change with the interface language: a future English localization still shows 俥 and 車 on the board, because those characters *are* the pieces. What an English localization would translate is the *spoken and written names* — the VoiceOver label `红车`, the Help headings, the move list — not the glyph.
- The glyphs must therefore live in a **separate, non-localizable** resource from the localizable strings, so a translator cannot accidentally "translate" a piece face.
- Each piece needs **two** strings: the glyph (fixed) and the spoken name (localizable). VoiceOver reads the spoken name, not the glyph, so that `帅` is announced as `帅` in Chinese and could later be announced as "red king" in English.
- Piece glyphs remain upright in both orientations (accepted) and are never mirrored.

### 9.3.3 Result copy — fix the table now

The result card, the History row, the save-and-continue confirmation's metadata,
and any future export description must all use one wording per serialized
identifier. Proposed table (owner sign-off needed — the **identifiers** are
accepted and must not change; the **strings** are proposals):

| `outcome` | Card title |
|---|---|
| `red-wins` | 红方获胜 |
| `black-wins` | 黑方获胜 |
| `draw` | 和棋 |
| `none` | 提前结束 |

| `end_reason` | Reason line |
|---|---|
| `checkmate` | 将死 |
| `stalemate` | 困毙 |
| `perpetual-check` | 长将 |
| `perpetual-chase` | 长捉 |
| `threefold-repetition` | 三次重复判和 |
| `mutual-perpetual-check` | 双方长将 |
| `mutual-perpetual-chase` | 双方长捉 |
| `resignation` | 认输 |
| `ended-early` | 提前结束 |

This is **decision D23**. Note that `mutual-perpetual-check` and
`mutual-perpetual-chase` are reserved identifiers whose fixtures are deferred
(`xiangqi-rules.md § Conformance fixtures`); the strings should exist so the UI is
total, but the owner should know they are not yet reachable.

### 9.3.4 What text expansion means for the layouts proposed above

| Layout element | Chinese today | Roughly, in English | Design response |
|---|---|---|---|
| Play control cluster: 悔棋 / 判和 / 认输 / 翻转棋盘 | 2–4 characters each | Undo / Claim Draw / Resign / Flip Board — about 3× the width | symbol + label buttons that drop to **symbol-only with an accessibility label** below a width threshold, and restack vertically at accessibility text sizes |
| Turn status: `轮到红方 · 你` | ~7 characters | "Red to move · You" — about 2.5× | reserve **two lines** in the layout from the start; never single-line-with-truncation |
| History row: `人机对弈 · 你执红 · 红方获胜 · 将死 · 42 步` | one line | three lines at large sizes | design the row as **title line + metadata line** from the start, not one dense line |
| Save-and-continue alert copy | short | ~2.5× | alert width is system-controlled; HIG "Alerts › iOS, iPadOS" warns "avoid displaying an alert that scrolls" — verify at Double-Length **and** `.accessibility5` together |
| Pre-start controls: 我先手 / AI 先手 / 随机, 快速 / 标准 / 深思 | 2–3 characters | "I Move First" / "AI Moves First" / "Random" — about 4× | use a `Picker` in a `Form`, which reflows natively, rather than a fixed segmented control |
| Coordinates `a`–`g`, `1`–`7` | locale-independent | unchanged | a further argument for Latin coordinates over Chinese numerals (D5) |
| Help topic titles | 2–5 characters | 2–4 words | list rows wrap natively; no fixed-height rows |

**Testing:** run Double-Length, Accented, Bounded String, and Tall pseudolanguages
across Play (all three states), History (with and without swipe actions revealed),
Settings, Help, and every accepted confirmation. This complements, and does not
replace, the `.accessibility5` pass.

### 9.3.5 Right-to-left — one rule to write down now

No RTL language is targeted, but the rule must be recorded before someone adds
one:

- **All layout uses leading/trailing**, never left/right. This is free discipline today.
- **The board never mirrors.** Board orientation is a rule of the game — files run `a`–`g` from Red's left — not a reading direction. Mirroring it under an RTL interface would produce an illegal-looking position and would break the coordinate vocabulary shared with the archive. This is the same category as HIG "Right to left › Interface icons": "Don't flip logos or universal signs and marks."
- **The flip control still works**, because that is a *player-perspective* flip, which is a game concept, not a layout-direction concept.

**Decision D25**, recorded now precisely because it is cheap now and expensive later.

---

# 10. Decision list

Each item changes what the user sees or hears. Implementation detail is excluded.
Recommendations are one line; the "affects" line says what breaks or shifts if the
owner chooses otherwise.

| # | Decision | Recommendation | Affects |
|---|---|---|---|
| **D1** | Piece rendering style | Traditional Chinese **character discs**, rendered as text | What a piece looks like on every screen, in Help, and in every future screenshot |
| **D2** | Which piece characters | Differentiated per side: **帅/将, 俥/車, 傌/馬, 炮/砲, 兵/卒** | Whether a chariot's or horse's side is readable without colour |
| **D3** | Board geometry | Draw as **intersections** (6×6 line grid, 49 points), diagonals corner-to-corner across each palace | Whether the board reads as Xiangqi at all |
| **D4** | Coordinates shown | **Yes, always**, in the outer margin, following the flip, no Settings toggle | Board margins, and whether spoken and printed square names agree |
| **D5** | Coordinate notation | **`a`–`g` / `1`–`7`**, matching the stored and spoken vocabulary | The notation a learner acquires; a second notation would have to be taught |
| **D6** | Side visual channels | **Red = solid disc, Black = outlined disc**, in addition to the glyph | Greyscale and colour-blind legibility of the whole board |
| **D7** | iPad default navigation placement | **Top tab bar** (sidebar remains one tap away) | How much width the board gets on first launch |
| **D8** | Board maximum size | **Cap the board edge at 720 pt**; surplus goes to a side pane | What a maximised Mac window looks like |
| **D9** | Result-card material and placement | **Regular Liquid Glass, never overlapping the board** | The most important moment in the app |
| **D10** | Check in the status element | Add a persistent **`将军`** token beside the turn line | Whether check can be missed at a glance |
| **D11** | Feedback when input is unavailable | **One 150 ms pulse of the status element**; no new copy, no board mark | What happens when a user taps during AI thinking |
| **D12** | Per-move save-failure copy | **`无法保存这一步，请重试。`**, shown transiently beside the status | An error path that currently has no accepted copy at all |
| **D13** | Sound events | **Six** events; none during autoplay | Whether, and how often, the app makes noise |
| **D14** | Haptic events | **Five**, iPhone only; nothing on iPad or Mac, and no substitute | iPhone feel; explicit non-parity across devices |
| **D15** | Settings gains 音效 and 触感反馈 | **Yes**, both default on, haptics row hidden where unsupported | Product scope: two new Settings rows and a `product.md` change |
| **D16** | Hover preview of legal destinations | **On**, iPad and Mac, half strength, only when nothing is selected | Whether the app teaches on hover; sits next to the "no AI hints" exclusion |
| **D17** | Custom VoiceOver rotors | **All four**: 合法走法, 我方棋子, 对方棋子, 上一步 | Whether a blind player can play at a reasonable pace |
| **D18** | VoiceOver reading order | **Follows the on-screen flip** | Whether spoken order and visual order agree |
| **D19** | Dynamic Type and the board | **Board does not scale**; controls do, and restack at accessibility sizes | The largest-text layout, and a recorded deviation from HIG's default advice |
| **D20** | Help structure and illustrations | **One sheet, seven topics, static FEN diagrams drawn by the play board view** | The entire MVP education surface |
| **D21** | Help context landing | From the game screen → **界面说明**; from Settings → the topic list | How fast a confused player finds the answer |
| **D22** | Supported languages | **`zh-Hans` only**, String Catalog from day one | What a device set to English displays |
| **D23** | Result wording table | **Fix now**: 将死 / 困毙 / 长将 / 长捉 / 三次重复判和 / 认输 / 提前结束 | The result card, History rows, and any future export description |
| **D24** | Undo shortcut and Redo | **⌘Z is 悔棋; Redo removed from the Edit menu** | Mac and iPad menu correctness; a dead Redo item is a bug report waiting to happen |
| **D25** | Board and RTL | **The board never mirrors** under an RTL interface language | Correctness if a language is ever added |
| **D26** | Autoplay sound | **Silent** | Replay comfort at 2× |

---

# 11. Where our contracts and Apple guidance conflict

Resolve these before implementation. Severity is my estimate of how much rework a
late resolution would cost.

**C1 — "Liquid Glass is required" invites over-application.** *(Low severity,
contract-wording fix.)*
`interaction-design.md § Platform visual language` says "Liquid Glass is a
required part of the visual and interaction direction." HIG "Materials › Liquid
Glass" says "Use Liquid Glass effects sparingly" and "Don't use Liquid Glass in
the content layer." Our contract already scopes it to functional layers, so the
substance agrees — but the word "required" reads as a mandate to maximise it.
**Resolution:** reword to "Liquid Glass is the required material for the functional
layers — navigation, toolbars, controls, and contextual actions — and must not be
applied to the content layer," and paste the §4.3.2 exclusion list into the
contract so it is not re-litigated per screen.

**C2 — Board input is blocked for the duration of an Undo animation.** *(Medium
severity, felt behaviour.)*
`interaction-design.md § Motion and visual effects`: "Board input and another Undo
remain unavailable until the transition completes." HIG "Motion › Providing
feedback": "Let people cancel motion. As much as possible, don't make people wait
for an animation to complete before they can do anything, **especially if they
have to experience the animation more than once**." Repeated undo is precisely
that case, and the accepted human-versus-AI undo is a two-ply, ~520 ms animation.
**Resolution (§5.3.1):** keep the no-overlapping-mutations rule, but make a second
Undo request snap the running animation to its end state and start immediately,
so the block lasts a frame rather than half a second. Needs owner approval because
it changes how repeated undo feels.

**C3 — Autoplay waits for each animation.** *(Low severity, same shape as C2.)*
`§ History replay`: "Autoplay… waits for each move animation to finish before
advancing." Same HIG line applies. The accepted pause-on-manual-navigation already
gives an escape; **resolution:** manual navigation during autoplay should also cut
the running animation short rather than queueing behind it.

**C4 — Sound and haptics must be optional, but Settings has no place for them.**
*(Medium severity, cross-document scope gap.)*
`interaction-design.md § Sound and haptics` requires they "remain optional where
platform conventions expect user control," and HIG "Playing haptics › Best
practices" states flatly "Make haptics optional. Let people turn off or mute
haptics." But `product.md`, which owns scope, lists only the 人机对弈默认设置 group
and 删除前确认. Honouring the guidance therefore requires a **product-scope
change**, not just an interaction-design change. **Resolution:** approve D15 and
update `product.md` and `interaction-design.md` in the same change.

**C5 — Help must be reachable from the game screen; macOS discourages a toolbar
help button.** *(Low severity, resolved by placement.)*
`§ Help` requires reachability "from the game screen"; HIG "Buttons › Help
buttons" says "Use a help button within a view, not in the window frame… avoid
placing a help button in a toolbar or status bar." **Resolution:** on macOS satisfy
the requirement through the 帮助 menu and `⌘⇧/` rather than a toolbar item; keep
the toolbar item on iOS and iPadOS, where that guidance does not apply. Read the
contract's phrase as "reachable without leaving the game screen." No contract
change needed, but the reading should be recorded.

**C6 — Silent rejection of unavailable input vs. "show people when a command can't
be carried out."** *(Medium severity, needs a decision.)*
`§ Move input` requires the board to reject interaction "before visually moving a
piece," and `§ Turn status` forbids adding "please move"-style copy. Read
literally that is zero feedback. HIG "Feedback › Best practices": "Show people
when a command can't be carried out and help them understand why." **Resolution:**
D11's status-element pulse — feedback with no new copy and no new board marker.

**C7 — The board ignores Dynamic Type.** *(Medium severity, deliberate
deviation.)*
HIG "Typography › Supporting Dynamic Type": "Make sure your app's layout adapts to
all font sizes" and "Increase the size of meaningful interface icons as font size
increases." Our board is sized to the available area, not to the text setting.
The counter-guidance exists — HIG "Typography › Conveying hierarchy": "Prioritize
important content when responding to text-size changes… they don't always want to
increase the size of every word on the screen" — and the glyph at the 44 pt pitch
floor is ~23 pt, twice the platform minimum. **Resolution:** approve D19 as a
recorded, justified deviation rather than letting it be discovered in review.

**C8 — "Text must not be embedded in visual assets" forecloses a commissioned
piece set.** *(Low severity, but worth surfacing early.)*
`§ Localization` already rules out bitmap or vector pieces with baked-in
characters. This is not a conflict with Apple — HIG "Icons › Best practices" agrees
("If you need to display individual characters in your icon, be sure to localize
them") — but it is a constraint a visual designer would otherwise discover after
commissioning artwork. **Resolution:** state in the contract that pieces are
composed at runtime from shapes plus a text glyph.

**Checked and found not to conflict:**

- The **non-dismissible result card** vs. HIG "Alerts › Best practices" ("Avoid using an alert merely to provide information") — the card is actionable (悔棋 / 结束对局), and HIG "Accessibility › Cognitive" positively prefers "dismissing views with an explicit action."
- **Single main window** vs. HIG "Designing for macOS › Best practices" ("Let people resize, hide, show, and move your windows") — the single-window rule constrains window *count*, not resizing or full screen. It does rule out a separate Help window, which is why §8 recommends a sheet.
- **Board flipping via a visible control rather than a gesture** (`§ Board orientation`) vs. HIG "Accessibility › Cognitive" ("Prefer system gestures and behaviors people are already familiar with over creating custom gestures people must learn") — these agree; a hidden rotation gesture is exactly what the HIG warns against.

---

# 12. What I could not ground in Apple documentation

Stated plainly, with the exact blocker in each case.

**12.1 Chinese and CJK typography.** The documentation tool returned **no HIG page
and no framework page** on the system's Chinese typeface or on CJK typographic
guidance. HIG "Typography › Using system fonts" enumerates SF Pro, SF Compact, SF
Arabic, SF Armenian, SF Georgian, SF Hebrew, SF Mono, and New York — with no
Chinese variant listed. Consequently the following are **unverified**: the font
family that will render the piece glyphs; CJK line-height and leading behaviour at
our sizes; and, critically, **whether the variant glyphs 俥, 傌, and 砲 are present
in the system font at `.regular`, `.semibold`, and `.bold`**. *Blocker:* this is a
device-verification question, not a documentation question. Render the ten glyphs
at all three weights on a physical iPhone, iPad, and Mac before D2 is locked. If
any glyph falls back to a substitute font it will visibly differ in weight and
width from its siblings, which would undermine the whole solid/outlined disc
system.

**12.2 Per-interaction motion durations.** Apple documents curves and APIs but
publishes **no per-interaction duration table**. The only numeric anchors found
are SwiftUI `Animation.timingCurve(_:_:_:_:duration:)` defaulting to `0.35` s and
`UIView.AnimationCurve.easeInOut` being "the default curve for most animations."
Every millisecond in §5.3 is ours. The accepted contract already anticipates this
("first-version values subject to adjustment after testing on physical iPhone,
iPad, and Mac hardware"), so this is a known gap rather than a surprise.

**12.3 Exact minimum window and scene sizes.** Apple documents the *mechanisms* —
`UISceneSizeRestrictions`, `windowResizability(.contentMinSize)`,
`NSWindow.contentMinSize` — and the *principle* ("set a minimum size for your
window"), but no values. The 390 × 560 pt iPad and 640 × 520 pt Mac minimums in
§3.3.3 are derived from the 44 pt target floor, not cited.

**12.4 iPadOS multitasking width breakpoints.** HIG "Layout › iPadOS" says windows
resize "down to a minimum width and height, similar to window behavior in macOS"
and to test at halves, thirds, and quadrants, but the search returned **no numeric
breakpoint** for iPadOS 26. The ~430 pt compact-fallback threshold in §3.3.2 is a
proposal to be validated on device against the actual third-width and
quarter-width sizes.

**12.5 SF Symbol availability.** HIG "SF Symbols" documents usage, custom symbols,
and the prohibition on symbols in app icons, but symbol *existence* must be
checked in the SF Symbols app. Every symbol name in this document —
`checkerboard.rectangle`, `square.grid.3x3`, `clock.arrow.circlepath`,
`gearshape`, `questionmark.circle`, `xmark.circle`,
`exclamationmark.triangle.fill` — is a **candidate**, not a verified name.

**12.6 Liquid Glass appearance under Increase Contrast, precisely.** HIG "Materials
› Liquid Glass" states only that variant appearance "can differ in response to
certain system settings, like… accessibility settings that reduce transparency or
increase contrast in the interface." It does not say *how*. The §4.3.4 rule —
system components self-handle; our two custom containers go opaque under Reduce
Transparency and gain a stronger border under Increase Contrast — is a reasonable
reading of that sentence plus `accessibilityReduceTransparency`'s documented
semantics, not a documented behaviour. Verify visually on device.

**12.7 Grid content and VoiceOver granularity.** Apple documents the mechanisms
(`accessibilityElement(children:)`, rotors, custom content, sort priority) and the
grouping principle, but has **no grid-specific rule** stating whether a 7×7 board
should be 1, 7, or 49 elements. The 49-element model in §7.3 is a design choice
justified by those mechanisms and by the requirement that a user be able to read
any individual square; it is not a cited rule.

**12.8 Chinese Xiangqi glyph convention.** Which of the three character sets in
§1.3.4 is idiomatic for a simplified-Chinese audience is a domain and language
question with no Apple guidance. What *is* grounded is the negative: set (C) is
ruled out because it makes side colour-only, which HIG "Accessibility › Vision"
forbids. The choice between (A) and (B) belongs to the owner.

**12.9 Sound design.** HIG "Playing audio" covers categories, silence, volume, and
routing — all cited in §6 — but says nothing about what a game's sound effects
should *sound like*. The timbres and lengths in §6.3.2 are design proposals, and
the "distinguishable by timbre, not just volume" requirement is derived from the
never-sole-carrier rule rather than quoted.

---

## Appendix — quick reference for reviewers

**Numbers that constrain everything else**

- Cell pitch floor: **44 pt** on touch (HIG "Designing for games"), **28 pt** on Mac.
- Board minimum edge: **340 pt** (7 × 44 + margins).
- Board maximum edge: **720 pt** (proposed cap, D8).
- iPhone portrait at 375 pt width → pitch **49.0 pt**. iPhone landscape at ~310 pt usable height → pitch **44.3 pt** — the binding case.
- iPad scene minimum: **390 × 560 pt**. Mac content minimum: **640 × 520 pt**; default **1040 × 760 pt**.
- Contrast targets: glyph vs. disc **≥ 4.5:1**; grid vs. surface **≥ 3:1**.

**The six board marker shapes** — selection ring (solid, on the disc) · legal-empty
dot (small, filled) · legal-capture ring (large, dashed) · last-move corner
brackets · check double ring + hazard badge · illegal-square crossed circle.

**The two custom Liquid Glass containers** — the Play control cluster, and the
replay transport bar. Everything else is a system component or is content.

**The six sounds** — 落子 · 吃子 · 将军 · 对局结束 · 无效 · 判和可用. **The five
haptics** (iPhone only) — selection · move · capture · warning · success.

**The four rotors** — 合法走法 · 我方棋子 · 对方棋子 · 上一步.

**The seven Help topics** — 棋盘 · 棋子与走法 · 将军与将死 · 困毙 · 重复局面与判和 ·
长将与长捉 · 界面说明.
