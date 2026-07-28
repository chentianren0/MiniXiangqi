# 4. The board frame: coordinates, grid, and typography

> These two sections continue `board-visual-language-design.fable-partial.md`
> and use its conventions: `p` is the cell pitch, statements are marked
> **Accepted** (already in `MiniXiangqi/docs/`), **Documented** (Apple, cited by
> page and section), or **Proposed** (mine, exact so it can be disagreed with
> exactly). §1's geometric table, §1's marker-ink gates, and §2's marker
> geometry are taken as given; §3 (motion) belongs to another writer and nothing
> here specifies a duration or a curve.
>
> Every Apple citation below was retrieved through the Xcode documentation tool
> on 2026-07-27 in this session. Where Apple publishes nothing — how Liquid
> Glass actually renders under Reduce Transparency, what a numeral strip should
> measure — I say so and own the value.
>
> Two typographic facts in §4.3 are **measured**, not asserted: they were
> obtained this session by rendering the glyphs through the real system-font
> cascade with the project toolchain (Xcode 27.0, build `27A5228h`) on this Mac.
> Method and raw numbers are given inline so they can be re-run and disagreed
> with.

**What §1 left open.** §1's table names a "file-numeral strip (top and bottom,
outside the core), see §4.1", 16 pt at `p = 44` and 14 pt at `p = 28`, and
points at a section that was never written. This is that section. The
proposal below **reproduces both of §1's numbers exactly** from a single
formula, so §1 does not need editing.

**What the contract already decides** (`interaction-design.md § Board geometry
and notation`, `§ User-visible notation`, `§ Layout shapes`) — I design inside
all of it:

- 7×7 **points** on a 6×6 line grid; the outer points sit on the border lines.
- Palace diagonals corner point to corner point, **at the same stroke weight as
  the grid**, so the palace reads as part of the board.
- No river. No starting-point ticks.
- A **half-cell margin** beyond the outer points; **coordinates sit outside
  that margin**.
- Notation is **traditional**: files numbered from each player's own right, so
  the two sides number oppositely; **Red writes 一二三四五六七 and Black writes
  1234567, and that applies to every number in a move**.
- **File numbers in the outer margin; ranks carry no labels**; the margin
  follows the board's orientation so the numbering beside a player is that
  player's own.
- Pitch floors: `p ≥ 44 pt` on iOS/iPadOS, `p ≥ 28 pt` on macOS.

---

## 4.1 The file-numeral strip — exact geometry

### 4.1.1 Two strips, and one band of clearance nobody has budgeted yet

*Proposed.* The board draws **two strips**, one above the top rank and one
below the bottom rank, each spanning the full width of the plate. §4.2 argues
that two is the right reading of the contract; this subsection sizes them.

Start with a collision the accepted margin does not cover. §1 fixes the
half-cell margin at `0.5 p` from an outer point, and §2's largest marker — the
S6 double check ring — has its **outer edge at `0.56 p`**. A checked general is
always on its own back rank (the palace is `c1`–`e3` for Red and `c5`–`e7` for
Black, `xiangqi-rules.md § Starting position, coordinates, and notation`), so
that ring **overhangs the core boundary by `0.06 p`** — 2.6 pt at the iOS
floor, 1.7 pt at the macOS floor — and it overhangs it *into the strip*, on
both edges, in every game that ends in check or checkmate. It never overhangs
the left or right edge, because a general is never on file `a` or `g`.

The margin is accepted at `0.5 p` and I am not proposing to change it. Instead
the strip's first band is reserved:

> **The marker-overhang band.** The topmost `0.08 p` of each strip carries no
> ink. No numeral ink may fall within **`0.58 p`** of any board point —
> the check ring's `0.56 p` plus §1's `0.02 p` air-gap constant.

At `p = 44` that band is 3.5 pt; at `p = 28`, 2.2 pt. It costs almost nothing
and it is the difference between a clean frame and a check ring touching a
numeral in the screenshot of the most important moment in the app.

### 4.1.2 Type size, strip height, baseline

*Proposed.* Three numbers, and everything else follows.

| Quantity | Rule | At `p = 44` | At `p = 28` |
|---|---|---|---|
| Numeral type size `s` | `clamp(0.32 p, 13 pt, 20 pt)`, rounded to whole points | **14 pt** | **13 pt** (floor binds) |
| Strip height `h` | `0.08 p + 0.887 s`, rounded up to whole points | **16 pt** | **14 pt** |
| Baseline, below the core boundary | `0.08 p + 0.7925 s` | 14.6 pt | 12.5 pt |
| Baseline, below the outer board line | `0.58 p + 0.7925 s` | 36.6 pt | 26.5 pt |

`0.887` and `0.7925` are not invented: they are the **measured ink band** of the
Chinese numerals in the system font (§4.3.1). `0.7925 em` is how far the
tallest of 一二三四五六七 rises above its baseline (六, at semibold); `0.887 em`
is its full ink height, top to bottom. So `h` is exactly "overhang band +
tallest numeral", with nothing spare and nothing missing.

**Both of §1's numbers fall out of this.** `0.08 × 44 + 0.887 × 14 = 15.94 →
16`. `0.08 × 28 + 0.887 × 13 = 13.77 → 14`. That the two independent
constraints — §1's placeholder and a formula derived from measured glyph
metrics — agree to within 0.1 pt at both floors is the strongest evidence I
have that these are the right values.

**Why the size is not simply proportional to `p`.** Numerals are text and text
has an absolute floor: 11 pt on iOS/iPadOS, 10 pt on macOS (HIG "Accessibility
› Vision", *Use recommended defaults for custom type sizes*; the identical
table appears in HIG "Typography › Ensuring legibility"). A pure `0.32 p` ramp
would put the macOS-floor numeral at 9.0 pt, below Apple's minimum. The clamp
floor of **13 pt** is chosen deliberately: it is exactly the macOS default text
size (HIG "Typography › macOS built-in text styles": Body, Regular, 13 pt), so
at the macOS floor the board's numerals are the same size as the Mac's ordinary
body text and no smaller.

**Why it is capped at 20 pt.** The ceiling engages at `p = 62.5`. Above that
the board keeps growing and the numerals hold. That is the correct behaviour
for a reference mark: at `p = 44` a numeral is 64 % of the piece symbol's
`0.50 p`; at a capped-large board it is 39 %. The frame recedes as the board
grows, which is what a frame is for. An uncapped strip on a maximised Mac
window would put 33 pt numerals around the board, and the board would look
labelled rather than ruled.

**Horizontal placement.** Each numeral is **centred on its file's line**, not
on a cell — it names a file, and files are lines. The outermost numerals sit
centred on the outer board lines, `0.5 p` inside the plate's left and right
edges; a Chinese numeral is full-width (`0.9925 s` measured, §4.3.1), so its
half-width is `≈ 0.5 s` — 7.0 pt at `p = 44` against a 22 pt margin, 6.5 pt at
`p = 28` against 14 pt. The numerals never approach the plate's side edges at
any supported pitch.

**Both strips are the same rectangle.** `h` is sized to the *Chinese* ink band
even in the strip that shows Arabic digits, whose ink band is only `0.722 em`.
This is deliberate: the two strips are then geometrically identical, so
flipping the board changes glyph content and order and **moves nothing**. The
cost is `0.165 s` (2.3 pt at `s = 14`) of unused space at the bottom of
whichever strip currently shows digits — invisible, and cheaper than a flip
that resizes the frame.

### 4.1.3 The board block, at both floors and capped large

*Proposed.* The plate — the drawn board surface — is **core plus both strips**:
`7 p` wide by `7 p + 2 h` tall. The board surface extends under the strips, as
it does on a printed board where the numerals are inside the border, so there
is exactly one background to measure numeral contrast against.

In the unclamped band (`40.6 ≤ p ≤ 62.5`) this collapses to a single constant:
`h = 0.3638 p`, so **block height = 7.728 p**.

| | `p` | Core | Strip `h` | **Board block (w × h)** |
|---|---|---|---|---|
| macOS floor | 28 | 196 | 14 | **196 × 224** |
| iOS/iPadOS floor | 44 | 308 | 16 | **308 × 340** |
| 375 pt-wide iPhone, width-bound | 49 | 343 | 19 | **343 × 381** |
| Numeral clamp engages | 62.5 | 437.5 | 23 | **437.5 × 483.5** |
| If the survey's 720 pt cap (D8) is approved | 102.9 | 720 | 26 | **720 × 772** |

**The block is not square, and the accepted layout rule has to be read
accordingly.** `§ Layout shapes` says "The board is square and is sized to the
largest square fitting both the available width and the height left after the
surrounding chrome." Read *the board* there as the **7 p core** — which is
square, and which is what `§ Board geometry and notation`'s "The grid is
square" is about — and the fitting rule becomes:

> `p = min( W / 7 , (H − 2h) / 7 )`, solved with `h` from §4.1.2.

That is a proposal about how to read an accepted sentence, and it should be
written back into the contract rather than left to each implementer.

**Fit check at the floors.** On a 375 × 812 pt iPhone (the narrowest width the
stacked layout should be verified against — the contract's own **Need to
discuss** asks the owner to name it), usable width after 16 pt side margins is
343 pt, so `p = 49.0`, above the 44 pt floor and **width-bound, not
height-bound**. Vertical budget: 812 − 59 top safe − 34 bottom safe = 719;
less a 49 pt tab bar, a two-line turn status (≈ 52), a control cluster (≈ 64)
and three 12 pt gutters leaves **518 pt** for a block that needs **381**. The
two strips cost 38 pt of that; there is 137 pt of slack. **The strips are
affordable at the tightest supported size.** At the macOS floor the block is
196 × 224, which no plausible window fails.

---

## 4.2 Which strip shows which numeral system

### 4.2.1 Confirming the two-strip reading — and tightening the sentence

*Accepted, with an ambiguity.* The contract says: "File numbers are shown in
the outer margin… Because the two sides number the files oppositely, the margin
follows the board's orientation so that the numbering beside a player is always
that player's own."

The singular "the margin" admits a one-strip reading: only the near player's
numbering is drawn. **I confirm the two-strip reading, and I think the sentence
should be tightened so nobody has to guess.** Four reasons:

1. "the numbering beside a player is always that player's own" is a promise
   made to *a player*, generically. With one strip the far player has no
   numbering beside them at all. The sentence is then vacuous rather than
   satisfied.
2. **The move list contains both sides' moves in both numeral systems.** A
   learner reading `马8进7` in the list needs Black's numbering visible on the
   board to locate file 8 — and there is no file 8, which is exactly the moment
   the strip has to teach them that Black's `8`… does not exist on a 7-file
   board, so they misread the move. One strip makes half the move list
   unreadable against the board.
3. **Free Play has one person playing both sides**, with a flip control they
   may or may not use. They need both keys regardless of orientation.
4. Xiangqi diagrams in books print both edges' numbering. The stated goal is
   that "a learner should be able to carry what they read here into any Xiangqi
   book"; a board that labels one edge does not match the book.

*Proposed* replacement for that contract sentence, exact:

> File numbers are shown in a strip outside the margin at the top and at the
> bottom of the board. Ranks carry no labels, as they do not on a Xiangqi
> board. Each strip carries the numbering of the player on its own side, in
> that player's own numeral system, so the numbering beside a player is always
> their own and both systems are always readable. Flipping the board exchanges
> the two strips' contents and reverses the direction of each.

### 4.2.2 The flip table, and two invariants

*Proposed, derived from accepted rules.* Files run `a`–`g` from Red's left
(`xiangqi-rules.md`). A player at the bottom of the screen faces up it, so
their right hand is the screen's right; a player at the top faces down it, so
their right is the screen's left. Each side numbers from its own right. Red's
numerals are Chinese and Black's Arabic — that is fixed to the **side**, never
to the position on screen.

| Orientation | Bottom strip (near player) | Top strip (far player) |
|---|---|---|
| **Red at bottom** (human-vs-AI with 我先手; Free Play default) | Red's, Chinese. Left→right: **七 六 五 四 三 二 一** | Black's, Arabic. Left→right: **1 2 3 4 5 6 7** |
| **Black at bottom** (人机 with AI 先手; after a flip) | Black's, Arabic. Left→right: **7 6 5 4 3 2 1** | Red's, Chinese. Left→right: **一 二 三 四 五 六 七** |

Two things a reviewer can check on any screenshot without knowing the position:

- **Sum-to-eight.** For every screen column, the top strip's number plus the
  bottom strip's number is **8**. (File `a` is Red's 七 and Black's 1; `d` is
  4 to both.) One glance verifies the whole frame.
- **Script follows side, not screen.** The Chinese strip is always on Red's
  side. If Red's pieces are at the bottom, 一二三四五六七 is at the bottom.

**A flip moves no rectangle.** Both strips have identical geometry (§4.1.2), so
a flip changes only which glyphs are in which strip and in which order. The
strip frames, the plate, and the core are unchanged. Whatever motion §3
specifies for the accepted 300–400 ms flip, the frame contributes no layout
change to it.

**Human-vs-AI shows the AI's numbering too.** The far strip is the AI's side,
and the AI's moves appear in the move list in the AI's numeral system. Hiding
the far strip would make the AI's moves the only ones a learner cannot check
against the board.

---

## 4.3 Typography

### 4.3.1 What the system font actually does — measured, not assumed

The survey's §12.1 recorded that Apple publishes **no HIG page and no framework
page** on the system's Chinese typeface — HIG "Typography › Using system fonts"
enumerates SF Pro, SF Compact, SF Arabic, SF Armenian, SF Georgian, SF Hebrew,
SF Mono and New York, with no Chinese variant — and that this is a
device-verification question rather than a documentation question. So I
measured it.

**Method.** Glyphs were run through `CTLineCreateWithAttributedString` with
`NSFont.systemFont(ofSize:weight:)` as the base font, so the real system
cascade selects the CJK face exactly as it will at runtime; advances and ink
bounding boxes came from `CTFontGetAdvancesForGlyphs` and
`CTFontGetBoundingRectsForGlyphs`. Optical weight was measured separately by
rasterising each glyph at 100 pt into an 8-bit grey context and summing
coverage, normalised to one em². Toolchain: Xcode 27.0 build `27A5228h`, on
this Mac, 2026-07-27. **These are macOS numbers; the iOS and iPadOS equivalents
are a required device check before any of this is implemented.**

**Result 1 — the cascade splits the two numeral systems across two families.**

| | Family resolved | Advance at 16 pt | Ascent | Descent |
|---|---|---|---|---|
| 一二三四五六七 | `.PingFangUITextSC-{Regular,Semibold,Bold}` | 15.88 pt (`0.9925 em`, identical for all seven) | 15.47 | 3.38 |
| 1234567 | `.SFNS-{Regular,Semibold,Bold}` | 7.11–9.98 pt regular; 7.59–10.42 semibold (proportional) | 15.47 | 3.38 |

**Ascent and descent are identical between the two families at every weight
tested.** That is the whole answer to "Chinese and Arabic must sit on a shared
baseline": they already do, structurally, for free, because the CJK UI face is
metric-matched to SF. No per-script vertical adjustment, no custom line box.

**Result 2 — and they are optically centred on that shared baseline too.**
At 16 pt semibold, 一's ink occupies `y ∈ [4.95, 6.46]` above the baseline —
optical centre **5.71** — while a digit occupies `[0.00, 11.27]` — optical
centre **5.64**. The difference is **0.07 pt at 16 pt** (`0.004 em`),
invisible. Across the full Chinese set the optical centres run 5.26 (四) to
5.73 (七), a spread of `0.029 em`, or 0.4 pt at `s = 14`. That residual is a
property of Chinese numerals, not something a designer can or should correct.

**Result 3 — the optical-weight problem is real, and it is the opposite of what
it looks like.** Ink area as a fraction of em² (higher = visually heavier):

| Weight | 一 | mean of 一…七 | mean of 1…7 | CJK / Latin |
|---|---|---|---|---|
| regular | 0.0668 | 0.1787 | 0.1361 | 1.31 |
| medium | 0.0802 | 0.2121 | 0.1605 | 1.32 |
| semibold | 0.0848 | 0.2242 | 0.1779 | 1.26 |
| bold | 0.0969 | 0.2553 | 0.2013 | 1.27 |
| heavy | 0.1117 | 0.2927 | 0.2344 | 1.25 |

Read that carefully, because the intuition in the brief — "一 is a single
horizontal stroke next to a 1" — is right about 一 and wrong about the set:

- **At the same nominal weight the Chinese set is ~26 % heavier than the Arabic
  set, not lighter.** Chinese numerals are full-width and fill their em;
  digits are ~0.6 em wide. The advance width dominates the stroke weight.
- **But 一 alone is the lightest mark on the board frame by a wide margin.** At
  semibold it is 0.0848 against the lightest digit's 0.1155 — 27 % lighter than
  `1` and 52 % lighter than the average digit.
- **And 四 is the heaviest**, 0.3821 at semibold, 68 % heavier than the heaviest
  digit. The Chinese set spans 4.5× top to bottom; the Arabic set spans 2.0×.
  The Chinese strip is intrinsically uneven and no font choice fixes that.

### 4.3.2 Family, weight, size — and why the two weights differ

*Proposed.*

> **Family:** the system font, requested as `Font.system(size:weight:)` — never
> a named family, and no bundled font. Documented: HIG "Typography › Using
> system fonts", developer note: "You can use the constants defined in
> `Font.Design` to access all system fonts — don't embed system fonts in your
> app or game." The cascade resolves the Chinese numerals to the CJK UI face
> (measured: `.PingFangUITextSC-*` on macOS) with matched metrics, so one
> request covers both scripts.
>
> **Size:** `s` from §4.1.2 — 14 pt at the iOS floor, 13 pt at the macOS floor,
> capped at 20 pt.
>
> **Weight:** Chinese numerals `.semibold`; **Arabic numerals `.bold`** — one
> step heavier.

The asymmetry is the point, and it is the *smaller* of two competing
corrections. Two constraints pull in opposite directions:

**(a) 一 must never be fainter than a grid line.** 一's entire ink is one
horizontal bar whose height *is* its stroke weight: measured `0.0731 em` at
regular, `0.0944 em` at semibold, `0.1081 em` at bold. Against §4.5's grid
stroke, at the proposed size `s`:

| `p` | `s` | 一's bar at `.semibold` | Grid stroke | Ratio |
|---|---|---|---|---|
| 28 | 13 | 1.23 pt | 0.80 pt | 1.53 |
| 44 | 14 | 1.32 pt | 1.14 pt | 1.16 |
| ≈ 45.3 (worst case) | 14 | 1.32 pt | 1.18 pt | **1.12** |
| 62.5 | 20 | 1.89 pt | 1.60 pt | 1.18 |
| 102.9 | 20 | 1.89 pt | 1.60 pt (capped) | 1.18 |

At `.regular` this fails outright at the iOS floor (bar 1.02 pt against a
1.14 pt grid line — the numeral would be *fainter than the lines it labels*).
So the Chinese numerals cannot be lighter than `.semibold`. **That constraint
is what sets the Chinese weight**, and it is why §4.5's grid stroke is capped
at the same pitch as `s`: both freeze at `p ≈ 62`, so the invariant holds by
construction at every supported pitch rather than by luck.

**(b) The two strips should read as one system.** With Chinese fixed at
`.semibold` (0.2242), the closest Arabic weight is `.heavy` (0.2344, 4.5 %
apart); `.bold` (0.2013) leaves the Arabic strip **10 % lighter**. I choose
`.bold` and accept the 10 %, because:

- HIG "Typography › Ensuring legibility" says plainly: "In general, avoid light
  font weights. For example, if you're using system-provided fonts, prefer
  Regular, Medium, Semibold, or Bold font weights" — `.heavy` is outside the
  endorsed set, and Increase Contrast then has nowhere to go.
- **The two strips are `7 p` apart, at opposite ends of the board.** They are
  never seen adjacent, so their relative density is the weakest perceptual
  comparison in the whole design. A 10 % ink difference across 308 pt of board
  is not a comparison anyone makes.
- Where the two systems *are* adjacent is the move list, where `炮二平五` sits
  above `马8进7` and the digits sit *inside* a CJK string. There the same
  one-step-heavier rule applies for the same measured reason, and `.bold`
  digits among `.semibold` characters is the standard mixed-script answer.

**Under Increase Contrast:** Chinese → `.bold` (0.2553), Arabic → `.heavy`
(0.2344), an 8 % gap, and 一's bar rises to `0.1081 s`. Both stay within the
endorsed weight range at the level below and step to its top at the level
above.

**Residuals I want named rather than hidden.** 一 remains the faintest mark on
the frame at every size; its 12 % margin over the grid stroke at `p ≈ 45` is
the tightest number in this section, and if the owner raises the grid weight or
lowers the numeral size the invariant must be re-derived. 四 remains the
densest; on the 高对比 board surface it will read as a small block, which is
correct — it is the file it names, and no other numeral looks like it.

**One measurement was inconclusive.** `NSFont.monospacedDigitSystemFont`
returned advances identical to the proportional face for `1`, `4` and `7`
(7.59 / 10.42 / 9.15 at 16 pt semibold), which means the tabular-figure feature
is applied at layout time and is not visible in raw glyph advances. **I could
not confirm whether SF's digits are tabular by default at these weights.** The
strip does not depend on it — each numeral is centred on its own file, never
set as a run — but the move list will, and that check belongs to whoever
specifies the move list.

### 4.3.3 Colour and the contrast gate

*Proposed, expressed like §1's marker-ink gates.*

§1 defines a **marker ink** per style at two strengths (active ≥ 4.5:1, record
≥ 3:1) against that style's board surface. The frame gets a third, parallel
name:

> **Frame ink.** Each style defines one **frame ink** per appearance, used at
> two strengths against that style's own board surface:
>
> - **Numeral strength** — the file numerals: contrast **≥ 4.5:1**, both
>   appearances. Under Increase Contrast, **≥ 7:1**.
> - **Rule strength** — the grid lines and the palace diagonals: contrast
>   **≥ 3:1**. Under Increase Contrast, **≥ 4.5:1**.

Why 4.5:1 and not 3:1 for the numerals: they are text at 13–20 pt, and HIG
"Accessibility › Vision" gives the governing table — "Up to 17 pts | All |
4.5:1"; the 3:1 relaxation applies only at 18 pt and above, or to bold text.
At the capped size of 20 pt the 3:1 row would technically apply, but the gate
does not relax with board size: one number, checkable at every pitch.

**The numerals use the frame ink, not a system label colour.** The board
surface is a custom fill owned by each piece style, and `.secondary` /
`secondaryLabel` carries no contrast guarantee against a custom fill — its
guarantee is against system backgrounds. Using it would silently break the
4.5:1 gate on the 传统 parchment surface. Using the frame ink also ties the
numerals to the grid as one visual system, which is what a printed board does.

**The numerals are darker than the grid.** Same hue, higher strength. That is
the printed-board relationship and it also means the numerals never compete
with the grid for the same perceptual weight.

**No hue.** Like §1's markers, the frame carries no Red or Black role colour,
in either strip. The Chinese strip is *not* red. Tying the numeral colour to
the side would put a saturated red row at the board's edge competing with the
Red pieces, and it would make the frame fail Differentiate Without Color's
spirit for no gain — the script already carries the side, unmistakably and
without hue.

---

## 4.4 Dynamic Type — taking a position on D19

*Proposed.* The survey's **D19** says "Board does not scale; controls do, and
restack at accessibility sizes", and its §7.4 adds that "the coordinate labels
are hidden" at accessibility sizes. **I confirm the first half and reverse the
second.**

**The board core does not track Dynamic Type.** Grid, discs and piece symbols
are sized by `p`. Grounding: HIG "Typography › Conveying hierarchy" —
"Prioritize important content when responding to text-size changes… they don't
always want to increase the size of every word on the screen. For example, when
people increase text size to read the content in a tabbed window, they don't
expect the tab titles to increase in size. Similarly, in a game, people are
often more interested in a character's dialog than in transient hit-damage
values." A board is a spatial diagram whose proportions carry meaning; scaling
the glyph without the pitch would break the `0.50 p` symbol against the
`0.84 p` disc, and scaling both is just "make the board bigger", which the
layout already does whenever there is room. At the 44 pt floor the symbol is
22 pt, twice Apple's 11 pt iOS minimum, so this is not a legibility deviation.

**The numeral strip takes exactly one step.** The numerals are interface text
*about* the board, not board content, and HIG "Typography › Supporting Dynamic
Type" is direct: "Make sure your app's layout adapts to all font sizes." So:

> At `dynamicTypeSize.isAccessibilitySize` on iOS and iPadOS, the clamp on `s`
> becomes `clamp(0.32 p, 17 pt, 24 pt)`. The board core absorbs the extra strip
> height; nothing else changes; **the numerals are never hidden, at any type
> size.**

The cost is trivial. At `p = 44`: `s` 14 → 17, `h` 16 → 19, block height
340 → **346 pt** — 6 pt, on a screen with 137 pt of slack (§4.1.3). The floor
of 17 pt is Apple's own iOS default body size.

macOS is unaffected: HIG "Typography › macOS" states flatly, "macOS doesn't
support Dynamic Type."

**Why hiding is the wrong answer.** The survey hides the labels at accessibility
sizes on the grounds that "VoiceOver already speaks coordinates". But a
low-vision user running `.accessibility5` is typically *not* a VoiceOver user —
they are exactly the person the printed numeral serves, and the app would
remove it at the setting that says "I need larger text". The contract's own
**Need to discuss** asks whether file numbers may be hidden *at all*, so hiding
them silently as a side effect of a type setting would also pre-empt an open
owner decision.

**At the narrowest supported iPhone, at accessibility sizes, something must
give — and it is not the strip.** With the status element wrapped to three
lines and the control cluster restacked vertically, the vertical budget falls
to roughly 314 pt against a block that needs 346 pt at `p = 44`. Solving for
`p` yields ≈ 39 pt, below the accepted 44 pt interaction floor. Per
`§ Layout shapes` — "the board may not be driven below the sizes above, and
neither may the chrome be driven below what its own controls require" — the
resolution is the chrome's: **the Play control cluster collapses to a single
button opening a menu or sheet.** The strips are never the thing that yields,
because they are the part of the frame the large-text user is reading.

---

## 4.5 Grid stroke, palace diagonals, and rendering

### 4.5.1 Stroke weight

*Proposed.*

> **Grid stroke = `clamp(0.026 p, 0.80 pt, 1.60 pt)`.**
> **Palace diagonals: identical** (accepted — "at the same stroke weight as the
> grid").
> Under Increase Contrast both are multiplied by **1.30**.

| | `p = 28` | `p = 44` | `p ≥ 61.5` |
|---|---|---|---|
| Grid and diagonals | **0.80 pt** (floor binds) | **1.14 pt** | **1.60 pt** (ceiling) |
| Under Increase Contrast | 1.04 pt | 1.49 pt | 2.08 pt |

Three constraints fix this value:

1. **§1's structural rule: markers must stay distinguishable from the grid.**
   §2's thinnest marker stroke is the S6 check ring at `0.04 p`. Stated as a
   checkable invariant:

   > **The thinnest marker stroke is at least `1.25 ×` the grid stroke at every
   > supported pitch.**

   At `0.026 p` the ratio is **1.54** through the proportional range and
   **1.40** at the macOS floor where the 0.80 pt floor binds — comfortable
   everywhere. Any future change to a marker stroke, or to the grid, must
   re-check this one number. Under Increase Contrast the marker strokes must
   grow by at least the same 1.30 factor, or the invariant breaks.

2. **The 一 invariant** of §4.3.2 — the ceiling at 1.60 pt exists so that the
   grid stops growing at the same pitch (`p ≈ 62`) at which `s` stops growing.
   Without the ceiling, a capped-large board would have 2.9 pt grid lines and a
   1.9 pt 一, and the board's faintest numeral would be fainter than its rules.
   The ceiling is also right on its own terms: a printed board's lines are thin
   whatever the board's size, and a board whose lines thicken as the window
   grows changes character rather than scale.

3. **The 0.80 pt floor** protects 1× external displays on the Mac, where
   `0.026 × 28 = 0.73 pt` would fall below three quarters of a device pixel.
   At 2× rendering 0.80 pt is 1.6 physical pixels — a clean antialiased
   hairline. The floor binds only below `p ≈ 30.8`, i.e. essentially only at
   the macOS floor itself.

### 4.5.2 Contrast

*Proposed.* Grid and diagonals are **rule strength** frame ink: **≥ 3:1**
against the style's own board surface, raised to **≥ 4.5:1** under Increase
Contrast (§4.3.3). This is deliberately the same 3:1 gate the accepted contract
already puts on the disc's boundary — "The disc's boundary… reaches at least
3:1 against the style's own board surface" — so a reviewer measures the whole
board against two numbers and no more.

Note the measurement instruction the contract already implies: the disc-boundary
3:1 is measured "at a point away from any board marking", which means the grid
must not be so heavy that finding such a point along the board's edge becomes
awkward. That is a second, independent argument for a thin grid.

### 4.5.3 Rendering

*Proposed, and this one is a real implementation trap.*

> **Point positions are computed in continuous coordinates and are never
> snapped to the device pixel grid.** Crispness comes from ≥ 2× rendering, not
> from snapping.

Snapping seven line positions to whole device pixels would perturb the pitch by
up to half a pixel per line, and the error accumulates across the six cells —
a visibly uneven grid on a board where evenness is the whole point. At 2× a
1.14 pt line is 2.3 physical pixels and reads crisp; at the 0.80 pt floor it is
1.6 pixels and still reads as a line.

> **The palace diagonals are drawn at the same nominal weight and with the same
> rasterisation, which makes them optically slightly lighter than the orthogonal
> grid.** This is correct and should not be compensated.

A 45° stroke of nominal width `w` spreads its ink across more pixels than an
orthogonal stroke of the same width, so it reads perhaps 5–10 % lighter. The
accepted contract asks for the same *stroke weight* so that "the palace reads
as part of the board rather than as decoration" — and a palace that is a shade
quieter than the grid is exactly that. Boosting the diagonals to match
optically would make the palace the most prominent thing on an empty board.

---

## 4.6 The outer boundary and the plate

*Proposed.* **The outermost grid lines are drawn at exactly the interior
weight. There is no double border line, and no separate drawn frame.**

Many physical Xiangqi boards use a doubled outer border, so this needs an
argument rather than a preference:

1. **The geometry has no room for it.** A second border line is conventionally
   drawn a small distance outside the first — call it `0.1 p` here. That places
   it at `0.6 p` from every edge point, which is `0.04 p` outside the S6 check
   ring's `0.56 p` outer edge and `0.10 p` outside the S3 capture ring's
   tangent at `0.50 p`. On the back rank — where the generals live and where
   check happens — every edge disc would then sit at the centre of a set of
   near-concentric arcs and lines: style ring, capture or check ring, board
   line, border line. §1's separation rule (style rings ≤ `0.42 p`, marker
   rings ≥ `0.44 p`, `0.02 p` air gap) exists precisely to keep that band
   legible, and a border line is neither a style ring nor a marker ring.
2. **The outer line carries pieces.** On a 9×10 board the doubled border is a
   frame around the play area; on a 7-point board it is a frame *through* the
   play area, under twelve of the twenty-four starting pieces.
3. **The board is small and the border is expensive.** At `p = 28` a doubled
   border adds two more lines within 3 pt of each other at the board's tightest
   size.
4. **The half-cell margin already terminates the board.** On a printed board
   the doubled border does the work of saying "the board ends here"; here the
   plate's own edge does it.

**The plate.** *Proposed:* the board block is drawn as a rounded rectangle,
corner radius **`0.25 p`** (11.0 pt at `p = 44`, 7.0 pt at `p = 28`), filled
with the style's board surface, **with no stroke in the default appearance**.
Under Increase Contrast it gains a **hairline edge at rule strength (≥ 3:1
against the app background)**, so that when contrast is requested the board's
extent is guaranteed to be visible even if a style's board surface happens to
sit close to the app background. That is the whole of the "does a frame exist"
answer: none by default, one hairline when asked for.

---

## 4.7 Where this supersedes the survey

`apple-ui-design-survey.md` §1.3.6 and §1.3.7 predate three accepted decisions —
traditional notation, the three piece styles, and the two symbol sets — and are
superseded as follows. Everything else in the survey stands.

| Survey | Status |
|---|---|
| §1.3.6 / **D5**: coordinates in `a`–`g` and `1`–`7`; "Traditional Chinese file numerals… keep them out of the MVP" | **Reversed by the contract.** Notation is traditional; files only; Chinese for Red and Arabic for Black. |
| §1.3.6: coordinates "on the bottom and leading edges" | **Superseded.** Rank labels do not exist, so there is no leading-edge strip; there are two file strips, top and bottom. |
| §1.3.6: "Style `.caption` in `.secondary`, scaling with Dynamic Type up to about 1.5×" | **Superseded** by §4.1.2 / §4.3.2 / §4.4: sized in `p` with clamps, frame ink rather than a system label colour, and one Dynamic-Type step rather than a continuous ramp. |
| §7.4: "the coordinate labels are hidden" at accessibility sizes | **Reversed** (§4.4). |
| §1.3.7: grid "1 pt, dark, ≥ 3:1", "1.5 pt" under Increase Contrast | **Superseded** by `clamp(0.026 p, 0.80, 1.60)` and a ×1.30 rule. The survey's single appearance table also predates the three accepted styles, each of which owns its own board surface, so one table can no longer be written. |
| §1.3.7: the board "uses flat fills and, at most, a single hairline border" | **Refined** (§4.6): no stroke by default; a hairline only under Increase Contrast. |
| **D4** (coordinates shown by default, following the flip, no Settings toggle) | **Stands.** Whether they may be hidden at all remains the contract's open question. |

Also worth recording: the survey's §12.1 named the CJK font family as
unverified. §4.3.1 verifies it **on macOS only**. iOS and iPadOS remain
unverified and are a required device check.

---

## 4.8 The frame at the floors — one table

| Quantity | Rule | `p = 44` (iOS/iPadOS floor) | `p = 28` (macOS floor) |
|---|---|---|---|
| Numeral size `s` | `clamp(0.32 p, 13, 20)` pt | 14 pt | 13 pt |
| Chinese weight / Arabic weight | fixed | `.semibold` / `.bold` | `.semibold` / `.bold` |
| Strip height `h` | `0.08 p + 0.887 s` | 16 pt | 14 pt |
| Marker-overhang band | `0.08 p` | 3.5 pt | 2.2 pt |
| Baseline below the outer board line | `0.58 p + 0.7925 s` | 36.6 pt | 26.5 pt |
| 一's stroke (the frame's faintest ink) | `0.0944 s` | 1.32 pt | 1.23 pt |
| Grid and palace diagonals | `clamp(0.026 p, 0.80, 1.60)` pt | 1.14 pt | 0.80 pt |
| Grid, Increase Contrast | ×1.30 | 1.49 pt | 1.04 pt |
| Plate corner radius | `0.25 p` | 11.0 pt | 7.0 pt |
| Palace diagonal length | `2 √2 p` | 124.5 pt | 79.2 pt |
| **Board block** | `7 p × (7 p + 2 h)` | **308 × 340** | **196 × 224** |
| Block at accessibility type sizes | `s → 17` | 308 × 346 | n/a (macOS) |

Two ratios hold at every pitch and are the frame's acceptance tests: **thinnest
marker ÷ grid ≥ 1.25** (actual: 1.54 / 1.40) and **一's stroke ÷ grid ≥ 1.10**
(actual: 1.16 / 1.53, worst case 1.12 at `p ≈ 45`).

---

# 5. Liquid Glass boundaries

## 5.1 What is accepted, and what Apple actually says

**Accepted** (`interaction-design.md § Platform visual language`,
`§ Motion and visual effects`):

- "On Apple platforms, Liquid Glass is a required part of the visual and
  interaction direction. Use it for functional interface layers such as
  navigation, controls, toolbars, and contextual actions."
- "Preserve board readability and interaction clarity when translucent or
  material surfaces overlap or surround game content."
- "Visual effects must not make controls, state, focus, or text harder to
  perceive."
- "Liquid Glass belongs primarily to functional layers around the board;
  board-state markers must remain direct and readable rather than becoming
  translucent decoration."
- Open (`§ Need to discuss`): "Define how Liquid Glass behaves with contrast,
  Reduce Transparency, and different platform appearances."

**Documented** — HIG "Materials › Liquid Glass":

- "Liquid Glass forms a distinct functional layer for controls and navigation
  elements — like tab bars and sidebars — that floats above the content layer,
  establishing a clear visual hierarchy between functional elements and
  content."
- "**Don't use Liquid Glass in the content layer.** … including it in the
  content layer can result in unnecessary complexity and a confusing visual
  hierarchy. Instead, use Standard materials for elements in the content layer,
  such as app backgrounds. An exception to this is for controls in the content
  layer with a transient interactive element like Sliders and Toggles."
- "**Use Liquid Glass effects sparingly.** … If you apply Liquid Glass effects
  to a custom control, do so sparingly… Limit these effects to the most
  important functional elements in your app."
- Regular variant: "Use the regular variant when background content might create
  legibility issues, or when components have a significant amount of text, such
  as alerts, sidebars, or popovers." Clear variant: "Use this variant for
  components that float above media backgrounds — such as photos and videos";
  over bright content, "consider adding a dark dimming layer of 35% opacity".
- "The appearance of these variants can differ in response to certain system
  settings, like if people choose a preferred look for Liquid Glass in their
  device's settings, or turn on accessibility settings that reduce transparency
  or increase contrast in the interface." — **that is the entire published
  statement about accessibility behaviour. Apple does not say how.** §5.6 owns
  the values.

SwiftUI: `glassEffect(_:in:)` defaults to `.regular` in a `Capsule`;
`GlassEffectContainer` "combines multiple Liquid Glass shapes into a single
shape" and "SwiftUI renders the effects together, improving rendering
performance"; "Creating too many Liquid Glass effect containers and applying
too many effects to views outside of containers can degrade performance. Limit
the use of Liquid Glass effects onscreen at the same time" (SwiftUI "Applying
Liquid Glass to custom views › Optimize performance"); and for larger
components, "use a rounded rectangle if you're applying the effect to larger
components that would look odd as a `Capsule`".

## 5.2 The inclusion list — exhaustive

*Proposed.* Liquid Glass appears in these places and nowhere else in the app.

**System-supplied, automatic — nothing to specify, but listed so a reviewer can
account for every glass surface in a screenshot:**

1. The adaptive navigation container: tab bar (iPhone, narrow widths) or
   sidebar (Mac, wide iPad).
2. The navigation bar (iOS, iPadOS) and the window toolbar (macOS).
3. The macOS and iPadOS menu bar and its menus.
4. System presentations: alerts and confirmation dialogs (**开始新对局？**,
   **无法保存对局**, **无法启动 AI 对手**, **删除这盘棋？**), sheets (including
   the Help sheet), popovers, context menus, the file picker, the share sheet.
5. History row swipe actions.

**Custom — two containers, and never more than two on screen at once:**

6. **The Play control cluster.** One `GlassEffectContainer` holding the play
   controls (悔棋 / 判和 / 认输 / 翻转棋盘) as `.glass` buttons.
7. **The replay transport bar.** One `GlassEffectContainer` holding the five
   transport controls and the speed control.

**Custom, board-adjacent — one card slot, shared:**

8. **The natural-result card** and **the claimable-threefold notice**, which are
   the same object in two states and occupy the same slot. `.regular` glass, in
   a rounded rectangle (§5.5).

That is **three custom glass surfaces in the whole app**, of which at most two
are ever visible simultaneously, and in ordinary play exactly one. That
satisfies both "sparingly" and the performance note without needing an
argument.

## 5.3 The exclusion list — exhaustive, and stated as a rule

*Proposed.* The list matters less than the rule, because a list invites "it
isn't on the list, so it's allowed".

> **The rule.** The **board block** — the plate, everything drawn on it, and
> everything drawn about it — is content. No Liquid Glass, no standard
> material, no translucency of any kind. Its background is a flat fill owned by
> the piece style.
>
> **The rectangle.** No glass surface's bounds may intersect the board block's
> bounds (`7 p × (7 p + 2 h)`, §4.1.3). That includes the half-cell margin and
> both numeral strips. The board block never scrolls under a bar and is never
> partially covered by a card, a sheet edge, a toolbar or a tab bar.

Enumerated, so a reviewer can tick them off: the board surface; the plate edge;
grid lines; palace diagonals; the half-cell margin; both file-numeral strips and
every numeral in them; piece discs; each style's disc rings and resting shadows;
piece symbols, characters or icons; the lift shadow; and every marker in §2 —
selection ring, legal-destination dots, capture rings, last-move brackets, check
rings, the illegal-tap crossed circle, the drag-origin marker, the pointer hover
fill, the keyboard focus square.

Also excluded, though outside the board block:

- **The turn-status element**, its side-to-move line, its 你 / AI label, its
  将军 token, and its AI-activity indicator (§5.5.3). It is status, present
  nearly all the time; a glass surface that is almost always visible is not
  "sparing", and status must be maximally legible.
- **The transient save-failure capsule** (§2's S8). Opaque fill. It is a
  message, not a control, it lasts about three seconds, and a glass morph on a
  three-second toast is the definition of gratuitous.
- **The move list rows**, **History row content**, **Settings row content**,
  **Help body text and Help diagrams**, and the **pre-start board preview**.
  All content layer.

**How to check a screenshot, in three steps.** (1) Crop the board block; no
pixel of it may be translucent, blurred, or lensed. (2) Every remaining
translucent surface must be identifiable as one of the eight numbered items in
§5.2. (3) Count tinted glass: zero during ordinary play, at most one anywhere
(§5.7).

## 5.4 Where the boundary falls, in each accepted layout

*Proposed.* Both accepted shapes (`§ Layout shapes`) put the boundary in one
place: **around the board block's rectangle.** Clearances are stated in absolute
points, not multiples of `p`, because they belong to the interface, not to the
diagram — the diagram scales, the interface does not.

**Stacked** (iPhone portrait; narrow windows, including iPad portrait), top to
bottom:

```
[ navigation bar ]         system glass
[ turn status ]            no material — text and an activity view on the app background
   ≥ 12 pt
[ BOARD BLOCK ]            content. 7p wide × 7p + 2h tall. No glass may touch this rectangle.
   ≥ 12 pt
[ control cluster ]        one GlassEffectContainer
   (or, after a natural result, the result card in this slot — §5.5)
[ tab bar ]                system glass
```

**Side by side** (iPad landscape, wide iPad windows, ordinary Mac windows),
leading to trailing:

```
[ sidebar ]   |   [ BOARD BLOCK ]   |   [ panel: turn status · move list · metadata · controls ]
 system glass  ≥20  content, centred  ≥20   move list scrolls (system scroll edge effect);
                                            controls are one GlassEffectContainer;
                                            the result card takes the panel's top slot
```

The 12 pt figure is Apple's: HIG "Accessibility › Mobility" — "In general, it
works well to add about 12 points of padding around elements that include a
bezel." A glass container has a bezel; the board is what must not be crowded by
it. The 20 pt gutter in side-by-side is wider because the panel is a full
column and the grouping has to read at a glance (HIG "Layout › Visual
hierarchy": "Make controls easier to use by providing enough space around them
and grouping them in logical sections").

**May glass ever overlap the half-cell margin or the numeral strips? No.** Not
partially, not at a corner, not during a transition. Three reasons:

1. The margin is not decorative padding. It is the clearance that keeps edge
   discs from being clipped (accepted) and, per §4.1.1, the S6 check ring
   already overhangs it into the strip. A glass edge lensing that region would
   distort the outer rank's discs and the check ring at the exact moment they
   carry the most information.
2. The numerals are the frame's smallest text, at 13–14 pt at the floors, held
   to 4.5:1. Glass adjusts the luminosity of what is behind it; a numeral
   partly under a glass edge has no measurable contrast value, so the gate
   §4.3.3 states would become uncheckable.
3. The accepted result contract requires "the final board remains fully
   visible". Making that a rectangle test rather than a judgement call is the
   only way a reviewer can verify it from a screenshot.

**The deliberate deviation, named.** HIG "Layout › Best practices" says "Extend
content to fill the screen or window… Controls and navigation components like
sidebars and tab bars appear on top of content rather than on the same plane, so
it's important for your layout to take this into account." The system expects
content under the bars. **We satisfy that with the app background, not with the
board:** the flat app background extends edge to edge and under every bar, and
the board block is inset out from under all of them. That is what "take this
into account" means for a fixed-size diagram that must stay measurable. The
Play screen also does not scroll, so it has no scroll edge effect; the move
list and the History list do scroll and take the system effect automatically.

## 5.5 The three board-adjacent surfaces

### 5.5.1 The natural-result card

**Accepted:** "the final board remains fully visible and a non-dismissible
result card appears near it"; title 红方获胜 / 黑方获胜 / 和棋 plus a reason
line; actions 悔棋 and 结束对局 before confirmation, then the card changes to
已记录到历史 with 回放 and 完成; it "cannot be dismissed by tapping outside it".

*Proposed:*

| | |
|---|---|
| **Material** | `.regular` Liquid Glass. Never `.clear`. |
| **Shape** | Rounded rectangle, corner radius 20 pt — `glassEffect(.regular, in: .rect(cornerRadius: 20))`, not the default `Capsule`. |
| **Container** | Its own `GlassEffectContainer`, holding the card and its buttons, so the buttons blend into the card's shape rather than floating as separate lenses. |
| **Placement, Stacked** | The control-cluster slot, below the board. **It replaces the cluster** rather than joining it. |
| **Placement, Side by side** | The panel's top slot, above the move list. |
| **Buttons** | 悔棋 and 回放 use `.glass`; 结束对局 (before confirmation) and 完成 (after) use `.glassProminent` — exactly one prominent button per state. |

Why `.regular`: the card is alert-shaped and text-bearing, which is precisely
the documented case — "Use the regular variant when… components have a
significant amount of text, such as alerts, sidebars, or popovers." Why never
`.clear`: there is no media background to show through, and clear over bright
content wants "a dark dimming layer of 35% opacity" (HIG "Materials › Liquid
Glass"; SwiftUI `Glass/clear`: "ensure content remains legible by adding a
dimming layer"), which would darken the board the contract requires to stay
visible.

Why it replaces the control cluster: the card offers 悔棋, and the cluster
offers 悔棋. Two Undo buttons on one screen is a bug, and removing the cluster
also keeps the custom-glass count at one during the app's most important moment.

Why not an alert: HIG "Alerts › Best practices" — "Avoid using an alert merely
to provide information" — and, decisively, an alert covers the board, which the
contract forbids.

**How the card keeps the board fully visible when there is no room.**
`§ Layout shapes` says the board may not be driven below its pitch floor, and
the contract's own **Need to discuss** flags this exact collision: "Resolve how
the non-dismissible result card… fit the stacked layout's remaining space, given
that the card requires the board to stay visible and the chrome has its own
floor." *Proposed resolution*, by extending the contract's own reasoning:

> `§ Layout shapes` already exempts the pre-start preview — "a pre-start board
> is a noninteractive preview with no touch targets, so it carries no size
> floor… The floor exists to protect interaction, and a preview has none to
> protect." **A board showing a natural result has no board interaction to
> protect either, and neither does a replay board.** So read-only boards take a
> *legibility* floor in place of the interaction floor: **`p ≥ 24 pt`**, at
> which the disc is 20 pt and the piece symbol is 12 pt, above Apple's 11 pt
> iOS minimum. At `p = 24` the board block is 168 × 196 pt.

On a 375 pt iPhone that frees **185 pt** — the difference between the
width-bound block at `p = 49` (381 pt tall) and the read-only floor block at
`p = 24` (196 pt tall) — on top of the 137 pt of slack §4.1.3 already found,
without ever hiding a single point of the board. It resolves an open contract
question rather than deferring it. The pre-start preview keeps its accepted
exemption from any floor at all.

### 5.5.2 The claimable-threefold notice

**Accepted:** "the notice says **局面已三次重复，可以和棋结束。** and offers
**继续对局** and **以和棋结束**"; after 继续对局, "the same still-valid claim is
exposed through a non-blocking **可判和** affordance instead of repeatedly
presenting the same blocking notice."

*Proposed:*

- **Same object as the result card**: same `.regular` glass, same rounded
  rectangle, same slot, same clearances. It is a board-adjacent, action-bearing
  card, and inventing a second surface for it would double the material
  vocabulary for no gain.
- **Dismissible, unlike the result card** — 继续对局 removes it and the slot
  returns to the control cluster.
- **No tinted button** (§5.7). Claiming or declining a draw is a game decision,
  and a prominent button is the interface recommending one. Both actions are
  `.glass`. This is a rare case where the "one prominent action" convention
  should be actively declined, and it should be recorded as such.
- **可判和 is not a new surface.** After 继续对局, the cluster's existing 判和
  button becomes enabled and carries a non-colour availability mark. The
  accepted requirement is a "non-blocking affordance", and the cheapest correct
  one is a control that already exists changing state — which also keeps the
  glass count unchanged.

### 5.5.3 The AI-thinking indicator

**Accepted:** "AI thinking is shown as activity attached to the AI's turn; it
does not replace or compete with the side-to-move line"; "Turn ownership,
activity, and input availability must not be communicated by color alone";
maximum thinking times are 1 / 3 / 5 seconds (`product.md`).

*Proposed:*

| | |
|---|---|
| **Material** | **None.** Not glass, not a standard material. Text and an activity view drawn directly on the app background. |
| **Placement** | Inside the turn-status element, on that element's trailing side, on the same row as the 轮到黑方 · AI line. Stacked: above the board. Side by side: the panel's top. |
| **Form** | A small indeterminate circular `ProgressView`. |
| **Board** | Not dimmed, not blurred, not overlaid — consistent with §2's S9 and with the result contract's one rule: the board is never obscured. |

Why no material: it is present for one to five seconds of **every AI turn**, so
it is on screen for a large fraction of the game. A glass surface that is
almost always visible fails "sparingly" by inspection. It is also status, and
HIG "Feedback › Best practices" is direct: "Consider integrating status feedback
into your interface. When status feedback is available near the items it
describes, people get important information without having to take action or
leave their current context."

Why indeterminate rather than a progress bar: the AI's time is *bounded* at
1 / 3 / 5 s but not *predictable* — it returns early whenever the search
finishes. A determinate bar would promise a duration and then jump, which is
worse than no promise. The bounded time is also why an indeterminate spinner is
acceptable here at all: the user is never watching it for long.

Non-colour channels, as the contract requires: the spinner's motion, its
presence or absence, and the 你 / AI label — three channels, none of them hue.

## 5.6 Behaviour under the accessibility settings and in dark appearance

**Documented, and then a gap I own.** Apple states that Liquid Glass variant
appearance "can differ in response to… accessibility settings that reduce
transparency or increase contrast" — and nothing more. The semantics of the
settings themselves *are* documented: `EnvironmentValues.accessibilityReduceTransparency`
— "If this property's value is true, UI (mainly window) backgrounds should not
be semi-transparent; they should be opaque"; and Accessibility "Testing system
accessibility features in your app › All platforms" — Reduce Transparency
"improves contrast and legibility by reducing transparency and blur effects on
certain backgrounds", Increase Contrast "raises color contrast between app
foreground and background colors". **How Liquid Glass renders under either is
not published. Every value in the "custom" columns below is mine and must be
verified on device.**

> **The rule that governs the whole table: layout must not reflow.** Only the
> background and border of a surface change. Frame, corner radius, spacing,
> button order and text all stay put, so that turning an accessibility setting
> on never moves anything and never changes the board block's size.

| Condition | System glass (items 1–5) | Custom containers (6, 7) | Result card / threefold notice (8) | Board block |
|---|---|---|---|---|
| **Light, default** | system | `.regular` glass | `.regular` glass | flat style surface; grid `0.026 p`; numerals ≥ 4.5:1 |
| **Dark, default** | system; adapts automatically | `.regular` glass; adapts | `.regular` glass; adapts | the style's dark board surface; same gates |
| **Reduce Transparency** | system handles | opaque fill (`secondarySystemBackground` equivalent) + hairline separator; identical shape, radius, spacing | same | **unchanged** — nothing on it was ever translucent |
| **Increase Contrast** | system handles | keep the glass; container border to 1.5 pt at primary strength; any tint switches to its high-contrast asset variant | same | grid ×1.30 and ≥ 4.5:1; numerals ≥ 7:1; plate gains a hairline edge at ≥ 3:1 against the app background; §2's record ink promotes to active |
| **Both** | system handles | opaque fill **and** the 1.5 pt border | same | as Increase Contrast |
| **Differentiate Without Color** | no change | no change | no change | **pixel-identical** — §1's vocabulary is luminance and shape only |

Implementation shape: read `@Environment(\.accessibilityReduceTransparency)`
and `@Environment(\.colorSchemeContrast)` and branch **the background modifier
only**, never the layout. Colour changes come from asset-catalog high-contrast
variants rather than runtime arithmetic.

**One consequence worth stating explicitly.** The board is not glass, but it
sits next to glass, and HIG "Color › Best practices" warns: "Even if your app
ships in a single appearance mode, provide both light and dark colors to support
Liquid Glass adaptivity in these contexts." So **every board colour — each
style's surface, its frame ink, its marker ink — needs light, dark, and
increased-contrast variants in the asset catalog even though the board itself
never becomes translucent**, because the card beside it samples what is behind
and around it.

**Test matrix**, per HIG "Dark Mode › Best practices" ("Test your content to
make sure that it remains comfortably legible in both appearance modes. For
example, in Dark Mode with Increase Contrast and Reduce Transparency turned on
(both separately and together), you may find places where dark text is less
legible…"): light, dark, each with Increase Contrast, each with Reduce
Transparency, and each with both — twelve states across the three board styles,
on the Play screen in ordinary play and with the result card up.

## 5.7 Tint discipline

**Documented.** HIG "Color › Liquid Glass color": "Apply color sparingly to the
Liquid Glass material, and to symbols or text on the material. If you apply
color, reserve it for elements that truly benefit from emphasis, such as status
indicators or primary actions. To emphasize primary actions, apply color to the
background rather than to symbols or text… **Refrain from adding color to the
background of multiple controls.**" HIG "Buttons › Style": "Keep the number of
prominent buttons to one or two per view."

*Proposed:* **at most one tinted glass element visible at a time, and during
ordinary play, zero.**

| Screen state | The one tinted element |
|---|---|
| Play start (active-game metadata, Resume, two mode entries) | **继续对局** (Resume), when an active game exists; otherwise none |
| Pre-start, human-vs-AI **and** Free Play | **开始对局** |
| **Ordinary play** | **none** |
| Threefold notice showing | **none** — see §5.5.2 |
| Result card, before confirmation | **结束对局** |
| Result card, after confirmation | **完成** |
| History replay | none — the transport controls are peers |
| History list | none; swipe actions use the accepted system blue 共享 and red 删除 |
| Settings, Help | none |
| System alerts and confirmations | the system's own default button; the destructive one uses the destructive role, never a red tinted glass background |

**Zero during play is the interesting one, and it is not minimalism for its own
sake.** The Red pieces carry a saturated role colour that means *a side*. Any
tinted control on the same screen competes with that meaning, and HIG "Buttons ›
Style" warns from the other direction too: "Avoid applying a similar color to
button labels and content layer backgrounds." Reserving tint away from the play
screen keeps saturated colour on the board meaning exactly one thing. There is
also no candidate: during play the most likely next action is a *move*, which
is not a control, so there is nothing for a prominent button to point at.

## 5.8 The contract-wording problem

The survey's **C1** is right that "Liquid Glass is a **required** part of the
visual and interaction direction" reads as a mandate to maximise the material,
against Apple's "sparingly" and "don't use it in the content layer" — even
though the sentence that follows already scopes it to functional layers. The
survey proposed rewording plus pasting an exclusion list into the contract. I
agree with the diagnosis and would change the remedy: **a list invites
"it isn't on the list, so it's allowed", and it goes stale the first time a new
element is added.** State the rule and the discipline instead.

*Proposed replacement* for the first bullet of `interaction-design.md
§ Platform visual language`, exact:

> - On Apple platforms, Liquid Glass is the material for the functional layer —
>   navigation, toolbars, controls, and contextual actions — and is not applied
>   to the content layer. Most of it arrives automatically from standard system
>   components. Custom glass surfaces are added sparingly, only for the most
>   important functional elements, and each one is named in this document. The
>   board and everything drawn on it — surface, grid, palace diagonals, margin,
>   file numerals, discs, symbols, and every game-state marker — is content and
>   never uses Liquid Glass; no glass surface overlaps the board.

What that keeps: Liquid Glass is still non-optional — it is *the* material, with
no alternative offered, which is what "required" was protecting. What it removes:
the reading that more glass is better compliance. What it adds: three things the
current sentence leaves to be re-litigated per screen — the content-layer
prohibition, the naming discipline (a new custom glass surface is a contract
change, not an implementation choice), and the non-overlap rule that makes the
accepted "board readability" and "final board fully visible" requirements
checkable from a screenshot.

The adjacent bullet, "Preserve board readability and interaction clarity when
translucent or material surfaces overlap or surround game content", should then
lose "overlap": under the rule above nothing overlaps the board, and leaving the
word in preserves the ambiguity the change is meant to remove. *Proposed:*
"Preserve board readability and interaction clarity where material surfaces
surround game content."

## 5.9 Where this supersedes the survey

| Survey | Status |
|---|---|
| §4.3.1 inclusion list (six items, "two custom glass containers") | **Refined.** Same shape, but the menu bar and the Help sheet are named explicitly, the result card and threefold notice are stated to be one shared slot rather than two surfaces, and the count is given as "three custom surfaces, at most two on screen, one during play". |
| §4.3.2 exclusion list | **Superseded** by §5.3's rule-plus-rectangle. The survey's list also predates the three piece styles, the numeral strips, and §2's twelve markers, so it is now incomplete on its face. |
| §4.3.3 / **D9** result card: "regular Liquid Glass… placed so it never overlaps the board" | **Stands**, with the shape, container, button assignment, and the read-only-floor resolution added (§5.5.1). The survey's `结束对话` is a typo for `结束对局`. |
| §4.3.4 accessibility table | **Extended** to add the board block, dark appearance, Differentiate Without Color, and the explicit no-reflow rule. |
| §4.3.5 tint discipline | **Sharpened**: zero tinted elements during ordinary play, and an explicit refusal to tint either action on the threefold notice. |
| **C1** contract rewording | **Diagnosis accepted, remedy changed** (§5.8): state the rule and the naming discipline in the contract rather than pasting an exclusion list into it. |

---

# Open for the owner

1. **One strip or two?** §4.2.1 reads the accepted sentence as two and proposes
   replacement wording. Two costs `2h` — 32 pt of vertical budget at the iOS
   floor, of which there is 137 pt of slack on a 375 pt iPhone. If the owner
   wants one, the move list becomes half-unreadable against the board and §4.2's
   sum-to-eight check disappears.
2. **May file numbers be hidden at all?** The contract's own open question.
   §4.4 argues they must not be hidden as a side effect of Dynamic Type; a
   deliberate Settings toggle is a separate question, and `product.md` keeps
   Settings deliberately small.
3. **Arabic numerals at `.bold` or `.heavy`?** `.bold` keeps both scripts inside
   HIG's endorsed weight range and leaves Increase Contrast somewhere to go, at
   the price of a measured 10 % optical-density gap between the two strips.
   `.heavy` closes the gap to 4.5 % and costs both. §4.3.2. This is a
   look-at-it-on-device decision.
4. **Does the read-only legibility floor (`p ≥ 24 pt`) extend the accepted
   layout floors correctly?** §5.5.1 derives it from the contract's own
   pre-start exemption and uses it to resolve an open contract question. It
   changes what a result screen and a replay screen may look like on a small
   phone.
5. **Board maximum size.** §4.1 clamps the numerals at `p = 62.5` and the grid
   at `p ≈ 61.5` independently of whether the survey's D8 (cap the board edge at
   720 pt) is approved. If D8 is rejected, those clamps become the only thing
   stopping an unbounded board from looking wrong, and they should be stated in
   the contract rather than left here.
6. **The threefold notice takes no prominent action.** §5.5.2 declines the usual
   one-prominent-button convention on the grounds that the app must not
   recommend claiming or declining a draw. That is a product judgement, not a
   design one.
7. **The result card replaces the Play control cluster.** §5.5.1. It removes
   判和, 认输 and 翻转棋盘 from reach while the card is up; 翻转棋盘 in
   particular is something a player might want on the final position.
8. **Two contract rewordings** are proposed verbatim and need approval before
   they go anywhere: the file-numeral sentence (§4.2.1) and the Liquid Glass
   bullet plus its neighbour (§5.8).
9. **Required device verification before any of §4.3 is implemented.** The font
   measurements are macOS only, on one OS build. iOS and iPadOS must be checked
   for the same three facts: that the cascade resolves the Chinese numerals to a
   CJK UI face with SF-matched ascent and descent, that the optical centres
   still agree within a fraction of a point, and that the ink-density ordering
   still puts `.semibold` Chinese near `.bold` Arabic. If any of those differs,
   §4.3.2's weight pair changes.
10. **Liquid Glass under Reduce Transparency and Increase Contrast is unverified
    by anyone.** Apple publishes only that appearance "can differ". §5.6's
    values are mine. They need a look on real hardware in all twelve states of
    the test matrix before they are written into a contract.
