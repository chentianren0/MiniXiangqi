# Pre-merge review — PR #23 `design/app-shell-and-layout`

Reviewed: `git diff main...design/app-shell-and-layout` (2 files, +37 −6), commit `9343b71`, PR body,
against `docs/interaction-design.md`, `docs/product.md`, `docs/game-data.md`, `docs/core-interface.md`,
`docs/testing.md` on the branch. Apple behaviour checked against the Xcode 27 beta (`27A5228h`) SDK
documentation and simulator device tables. No repository or GitHub state was modified.

Line numbers refer to the branch copies.

**Method note on arithmetic.** Several numbers this PR fixes depend on values no contract states
(numeral-strip height, turn-status height, control-row height, result-card height, navigation-container
height, panel minimum width). Where a conclusion holds for *any* plausible value I mark it
**value-independent**; where I had to assume values I give them and mark the conclusion
**value-dependent**. That distinction is itself the finding in several places.

---

## 1. The layout arithmetic, recomputed from scratch

### 1.1 The minimum window's own paragraph contradicts itself: 192 < "more than 200"

> "At the 44-point floor the board core is 308 points square, so **more than 200 points of height remain**
> for the turn status, the controls, the file numerals, and their spacing. **The minimum window is fixed at
> 380 by 500 points of content** … It fits the budget above with 50 points to spare"
> — `interaction-design.md:464`

The first sentence establishes that the 44 pt floor is affordable *because* 550 − 308 = 242 pt ("more than
200") remain for exactly this list: turn status, controls, file numerals, spacing. Two sentences later the
same paragraph fixes a minimum that leaves 500 − 308 = **192 pt** for the identical list. The minimum window
is set below the budget the paragraph just used to justify the floor, and the text asserts the opposite by
calling it "50 points to spare". The 50 pt of spare is spare against the *screen*, not against the *content*;
against the content the change is a 50 pt **deficit** relative to the stated affordability argument.

This is value-independent: it is the document's own two numbers.

**Severity: blocking.**

**Correction.** Either raise the minimum height to at least the 550 pt figure the affordability argument
uses (which then no longer fits the worst-case Mac budget — see 1.3), or delete the "more than 200 points"
affordability claim and replace it with an explicit chrome inventory that sums to ≤ 192 pt. As written the
two sentences cannot both be true.

### 1.2 The chrome inventory omits the navigation container, which the same document mandates at this width

> "the board at its floor, the numeral strips, the turn status and the control row must all fit inside it"
> — `interaction-design.md:464`, repeated verbatim as a gate at `testing.md:62`

> "Navigation uses one adaptive container, presenting as a **tab bar at narrow widths** and as a sidebar at
> wide ones." — `interaction-design.md:472`

380 pt is a narrow width by this PR's own rule (the switch "falls near 700 points"), so at the minimum window
the navigation container is a tab bar, drawn inside the scene's content area, on both macOS and iPadOS. It is
absent from the inventory in the contract sentence and absent from the testing gate. A tab bar is not free:
its items are controls, and the same section forbids driving chrome "below what its own controls require"
(`:468`).

Value-independent: the enumeration is incomplete regardless of the tab bar's exact height.

Value-dependent illustration, using conservative values (turn status 44, two numeral strips 18 each,
control row 44, three gaps of 12, tab bar 49):

```
board floor            308
numeral strips      2 × 18 =  36
turn status                  44
control row                  44
spacing             3 × 12 =  36
navigation (tab bar)         49
                          -----
                            517  >  500
```

The minimum window fails its own requirement by roughly 17 pt before anything else is added.

**Severity: blocking.**

**Correction.** Add the navigation container to both the contract sentence and `testing.md:62`, and re-derive
the height. If the intent is that the tab bar is excluded because iOS 26 floats it over content, say so
explicitly and reconcile it with "the board … may not be covered" (`:331`).

### 1.3 The minimum was validated against the wrong worst case — three times

The 500 pt figure is justified against the *control row*. Three states in the same contract are taller:

- **The result card.** This PR's own new rule (`:331`) exists precisely because the card does not fit where the
  control row does. The card carries a title, a reason line and two actions; the control row is one row of
  three buttons. The card is therefore strictly the taller element, so a minimum validated against the
  control row cannot be the binding case. Value-independent. Value-dependent: at a ~136 pt card the minimum
  window needs roughly 609 pt of content height, which **exceeds the 550 pt worst-case Mac budget the same
  paragraph cites** — i.e. the 44 pt floor, the numeral strips and the card rule may be jointly infeasible on
  the configuration the document names as its worst case. That is the finding this PR should have surfaced.
- **Replay in the stacked layout.** `:478` requires the move list to be shown in stacked replay ("the
  surrounding chrome is what tightens to make room"), on top of the transport row, the flip control and the
  playback-progress element (`:266`). None of this is in the 500 pt inventory or in the gate.
- **Accessibility text growth**, which the PR itself leaves open (`:497`).

**Severity: blocking.**

**Correction.** State the minimum against the tallest required stacked state (board floor + numeral strips +
turn status + result card + navigation container), not the control row; add replay to the gate; or do not fix
a number at all until the open inputs are accepted (see 1.4).

### 1.4 The requirement depends on a value the same document says is not accepted

> "the board at its floor, **the numeral strips**, the turn status and the control row must all fit inside it"
> — `:464`

> "Decide whether file numbers may be hidden, and **define the numeral strips' geometry**, typography, and
> contrast requirement … all of which the accepted board metrics leave open." — `:503`, **Need to discuss**

Yes — the claim depends on an unaccepted value, and the PR does not say so. The numeral strips' height is one
of the four terms in a budget with 192 pt of room and this PR turns that budget into a hard requirement plus a
`testing.md` gate. The strips are also the one term with no floor at all: nothing prevents a later accepted
geometry from consuming 60 pt.

The document's own defence — "a later design that does not fit is the design that changes" — does not hold
here, because the minimum window is not an internal design value. It is shipped to iPadOS and macOS and
determines which window and tiling configurations the app can be used in (see item 3). A number with that
consequence should not be fixed ahead of an input that is explicitly still open.

**Severity: blocking.**

**Correction.** Either keep the minimum window as an open item until the numeral-strip geometry is accepted,
or state 380 × 500 as provisional and add it to **Need to discuss** as "confirm once the numeral strips are
defined", and remove `testing.md:62` until then.

### 1.5 The 380 pt width verdict

380 pt **is** sufficient for the board and its margins: 380 − 308 = 72 pt, i.e. 36 pt per side, more than
twice the standard 16 pt margin. The file numerals sit in the *horizontal* margins above and below the board
(files are the columns; "Ranks carry no labels", `:138`), so they cost height, not width.

The consequence is that 380 is over-provisioned while 500 is under-provisioned: at 380 × 500 the board is
height-limited, not width-limited. The document gives no derivation for 380 at all, while 500 at least
references the Mac budget.

**Severity: nit.** **Correction.** State what 380 is derived from, or derive it (e.g. 308 + 2 × 16 = 340) and
note the difference is headroom for the control row at larger text sizes.

### 1.6 The "1024 × 550 with 50 points to spare" claim

Arithmetically correct on the height axis: 550 − 500 = 50. On the width axis the spare is 644, so "50 points
to spare" is a height-only statement presented as a two-dimensional one. Given findings 1.1–1.3 the 50 pt is
in any case spare against the wrong quantity.

**Severity: nit** (subsumed by 1.1). **Correction.** Write "50 points of height to spare".

### 1.7 The 375 pt iPhone claim — the width is right, the height is missing and is what the PR actually argues from

I can establish the device list from the local toolchain. The iOS 27.0 runtime in Xcode `27A5228h` supports
iPhone 11 and iPhone SE (2nd generation) as its oldest devices; iOS 26.5 is a superset of that. Among those:

| device | points |
|---|---|
| iPhone SE (2nd/3rd generation) | **375 × 667** |
| iPhone 12 mini / 13 mini | 375 × 812 |
| iPhone 11 | 414 × 896 |

So **375 pt is the correct narrowest width**, and a 308 pt board plus margins fits it comfortably
(375 − 32 = 343 available). That part of the PR is sound.

The defect is that **375 pt is a width, and every argument this PR builds on it is a height argument**:

> "There is not enough **height** on the narrowest supported iPhone for the board at its floor, the controls,
> and the card together" — `:331`

Two supported iPhones are 375 pt wide, at 667 pt and 812 pt tall. The claim is true at 667 pt and false at
812 pt (value-dependent: at 812 pt roughly 200 pt of slack remains after the board, numerals, turn status and
control row). The contract never fixes 667 pt, so the sentence that motivates the entire result-card decision
cannot be checked against the contract.

There is also a terminology slip inside one PR: `:464` says "the narrowest iPhone the stacked layout is
**verified against**", while `:331` and `testing.md:68` say "the narrowest **supported** iPhone". The removed
open item asked to "name the narrowest **supported** iPhone". Verified-against and supported are not the same
commitment.

**Severity: blocking** (the card rationale rests on an unstated number) plus **should-fix** (terminology).

**Correction.** Write "The narrowest supported iPhone the stacked layout is verified against is the iPhone SE
(2nd/3rd generation) at 375 × 667 points", and use one term throughout.

---

## 2. The derived breakpoint

### 2.1 The panel's minimum width does not exist anywhere, so the rule is not derivable

> "The side-by-side arrangement is used whenever the board and **the panel** both clear their **own minimum
> widths** at the available height" — `:457`

I grepped every document in `docs/` and `README.md`. The board's minimum width is defined (44 pt pitch →
308 pt core, `:112`, `:117`). **The panel's minimum width is defined nowhere** — not in
`interaction-design.md`, `product.md`, `architecture.md`, `core-interface.md`, `game-data.md`, or
`testing.md`. The panel's *contents* are listed (turn status, move list, game metadata, controls) but no
width is derived from them, and `:506` still leaves the turn status's placement within the panel open.

The rule therefore only *looks* derivable. One of its two operands has no value and no derivation procedure.
Any implementer must invent the number, and two implementers will invent different ones — which is exactly the
failure mode the PR uses to reject a named breakpoint ("would silently become wrong … with nothing forcing
anyone to notice").

**Severity: blocking.**

**Correction.** Define the panel's minimum width in the same section, derived from its stated contents (e.g.
the widest of: a two-line turn status, the longest move-list row in traditional notation, the metadata line,
and the three-control row), the way the board's minimum is derived from the pitch floor. Without it the rule
is not a rule.

### 2.2 "Currently falls near 700 points" is not reproducible

> "With the panel's current contents the switch falls near 700 points, and that figure is a **measurement of
> the rule** rather than the rule itself." — `:457`

A measurement must be reproducible from stated inputs. Given board 308 pt, 700 implies a panel minimum plus
gutters of ~392 pt (panel ≈ 344 pt at a 48 pt gutter) — a number that appears nowhere. The reader cannot
recompute 700, cannot check it, and cannot tell whether it moved when the panel's contents change, which is
the sole benefit the derived rule was adopted for.

**Severity: blocking** (same root cause as 2.1). **Correction.** Show the sum, or drop the figure.

### 2.3 The 700 pt figure contradicts retained accepted text about iPad portrait

> "**Stacked**, used by iPhone portrait and by narrow windows **including iPad portrait**" — `:459`
> (unchanged accepted text)

Portrait widths of every iPad supported by the iOS 27 runtime: iPad mini 744, iPad (A16) and Air 11" 820,
iPad Pro 11" 834, Air 13" 1024, iPad Pro 13" 1032. **All exceed 700 pt.** Under the new derived rule every
iPad in portrait is side-by-side, and `:459` — which this PR left in place — says the opposite.

**Severity: blocking.**

**Correction.** Update `:459`/`:460`, either by removing "including iPad portrait" or by stating which iPad
portrait widths remain stacked and why. As it stands the section states both.

### 2.4 The rule is circular with the navigation presentation, and can oscillate

> "Navigation … follows the **same width-driven rule as the layout shapes** rather than device identity"
> — `:472`

> gate: "resizing across that point in either direction is **stable rather than oscillating**"
> — `testing.md:61`

The sidebar consumes width; the tab bar does not. The layout rule's input (available width for board + panel)
therefore depends on the navigation presentation, and the navigation presentation is defined to follow the
layout rule. That is a cycle, and it produces a real oscillation band:

1. At width *W*, evaluate with a tab bar: board + panel fit → choose side-by-side.
2. Side-by-side ⇒ sidebar. The sidebar takes *S* points. Now board + panel do **not** fit in *W* − *S*.
3. Not fitting ⇒ stacked. Stacked ⇒ tab bar. Return to step 1.

The band is `[board_min + panel_min, board_min + panel_min + S]` — non-empty for **any** non-zero sidebar
width, so this is value-independent. With the PR's own ~700 pt figure and a conventional ~220 pt sidebar the
band is roughly 700–920 pt: the entire iPad-portrait range and a large part of the ordinary Mac window range.

The contract contains nothing that breaks the cycle — no evaluation order, no hysteresis, no statement that
"available width" is measured before or after the navigation container. The new gate asserts a property the
contract does not provide, so the gate cannot pass against the contract as written.

**Severity: blocking.**

**Correction.** Break the cycle explicitly. Either (a) evaluate the layout rule against the *scene* width with
the navigation container's widest presentation always subtracted, or (b) decouple the navigation threshold
from the layout rule and give it its own stated width, or (c) specify hysteresis (switch to side-by-side at
*X*, back to stacked at *X* − *S*) and state it as the stability guarantee the gate tests.

Note that the removed open item asked to "define the exact widths at which the layout shape **and the
navigation presentation** change". The navigation half is not resolved — it is made circular.

### 2.5 The gate assumes a one-dimensional threshold the rule does not have

> "resizing across **that point** in either direction" — `testing.md:61`

The rule is a two-variable condition (width *and* available height), so its boundary is a curve, not a point.
A test written against "that point" will exercise one width at one height and miss the height axis entirely.

**Severity: should-fix.** **Correction.** "resizing across that boundary in either direction, at several
heights".

### 2.6 The rule degrades to the worse arrangement at short heights

In side-by-side the board gets nearly the full height; in stacked it loses the turn status and control row
first. So whenever the board cannot clear its floor at the available height in side-by-side, it certainly
cannot in stacked — yet the rule's "otherwise" sends it to stacked, the strictly worse option. Today this is
masked by the minimum window, but the rule should say what it does rather than rely on a number that item 1
shows to be under-set.

**Severity: nit.** **Correction.** State the fallback explicitly, or state that the minimum window makes the
case unreachable.

---

## 3. The iPadOS multitasking consequence

### 3.1 "Unavailable" is not what iPadOS 26 does with a declared minimum scene size

> "the app declares that minimum to iPadOS, so it **is available at the wider multitasking widths but not the
> narrowest**" — `:464`
>
> gate: "the **app is unavailable** at narrower iPadOS multitasking widths rather than presenting a board
> below its floor" — `testing.md:62`

From the Xcode 27 beta documentation:

- HIG *Layout: iPadOS*: "People can freely **resize windows down to a minimum width and height**, similar to
  window behavior in macOS."
- *Multitasking on iPad, Mac, and Apple Vision Pro*: "Since people can resize your app's window, **set a
  minimum size** for your window with `UISceneSizeRestrictions`."
- HIG *Multitasking: iPadOS*, note: "**Apps don't control multitasking configurations** or receive any
  indication of the ones that people choose."

A declared minimum bounds *resizing*, exactly as on macOS. The app does not become unavailable; the window
stops shrinking. And per the third quote the app has no say in which multitasking configurations exist. The
contract asserts a platform behaviour the platform does not have, and `testing.md:62` asks a tester to verify
an outcome that will not be observed.

I could not establish from the locally available SDK material what the system does when a user selects a
tiling configuration smaller than the app's declared minimum (omit the option, or clamp and overlap). That is
a device measurement, not a documented fact, and the contract should not assert either.

**Severity: blocking.**

**Correction.** "The app declares that minimum to iPadOS, so a window cannot be resized below it." Change the
gate to verify that the window stops resizing at the minimum, and record the system's tiling behaviour as a
measurement to be taken rather than as a stated outcome.

### 3.2 The 320-point Slide Over premise is stale for iPadOS 26

> "a board at its 44-point floor cannot honestly be presented in a **320-point scene**" — `:464`

320 pt is the classic Slide Over width. The iPadOS 26 HIG *Windows: iPadOS* describes exactly two
presentations — "Full screen" and "Windowed … People can freely resize app windows" — and *Multitasking:
iPadOS* describes windowed apps "with behavior similar to macOS" plus "window controls for common tiling
configurations". Slide Over is not part of the model the contract is targeting. The rationale is written
against the previous system.

**Severity: should-fix.** **Correction.** Replace the 320 pt Slide Over reference with the iPadOS 26 tiling
configurations the HIG actually names — halves, thirds and quadrants — and compute against those (see 3.3).

### 3.3 The real consequence is a height restriction that removes tiling on most of the iPad line, and the PR does not name it

The PR frames the consequence entirely as a *width* one ("not the narrowest [widths]", "a 320-point scene").
The 500 pt **height** minimum is far more restrictive. HIG *Layout: iPadOS* directs: "Window controls provide
the option to arrange windows to fill **halves, thirds, and quadrants** of the screen, so it's important to
check your layout at each of these sizes on a variety of devices."

Against a 380 × 500 minimum:

| device | orientation | half (side) | half (top/bottom) | third (vertical) | quadrant |
|---|---|---|---|---|---|
| iPad mini | portrait | 372×1133 **fail** | 744×566 ok | 248×1133 **fail** | 372×566 **fail** |
| iPad mini | landscape | 566×744 ok | 1133×372 **fail** | 377×744 **fail** | 566×372 **fail** |
| iPad / Air 11" | portrait | 410×1180 ok | 820×590 ok | 273×1180 **fail** | 410×590 ok |
| iPad / Air 11" | landscape | 590×820 ok | 1180×410 **fail** | 393×820 ok | 590×410 **fail** |
| iPad Pro 11" | landscape | 605×834 ok | 1210×417 **fail** | 403×834 ok | 605×417 **fail** |
| iPad 13" | landscape | 683×1024 ok | 1366×512 ok | 455×1024 ok | 683×512 ok |

So the declared minimum excludes: **vertical thirds in portrait on every iPad**; **quadrants on every iPad
except the 13-inch models**; **top/bottom halves in landscape on the mini, iPad, Air 11" and Pro 11"**; and
side halves in portrait on the mini (372 pt, missing 380 by 8 pt) and thirds in landscape on the mini
(377.7 pt, missing by 2.3 pt). Two of those are near-misses that a 372 pt width minimum would avoid entirely.

None of this appears in the PR, which describes the loss as affecting only "the narrowest" widths.

**Severity: blocking** (materially understated consequence of a number this PR fixes).

**Correction.** State the actual excluded configurations, and reconsider the two dimensions against them —
in particular whether 380 can be 372, and what height is genuinely required.

### 3.4 It contradicts accepted text in both `interaction-design.md` and `product.md`

> "**iPad supports every orientation**, because iPadOS expects an app to adapt to rotation and **to being
> windowed at arbitrary sizes**, and an app that declines rotation opts out of that behaviour."
> — `interaction-design.md:448`, unchanged accepted text

> "iPhone runs in portrait orientation only. **iPad supports every orientation, as iPadOS multitasking
> expects.**" — `product.md:27`

Declaring a 380 × 500 minimum is declining to be "windowed at arbitrary sizes" — the exact behaviour `:448`
identifies as the thing not to opt out of. The PR adds the opt-out three paragraphs later without touching
`:448`.

**Severity: blocking.**

### 3.5 It contradicts an existing testing gate

> "Verify iPhone stays in portrait when rotated …, while **iPad adapts to every orientation and to full-screen
> and windowed sizes including the system tiling configurations**." — `testing.md:55`, pre-existing

> "…and that the **app is unavailable at narrower iPadOS multitasking widths**" — `testing.md:62`, new

Per the table in 3.3 these two gates cannot both pass on an iPad mini, iPad, Air 11" or Pro 11". The PR added
gate 62 without reconciling gate 55.

**Severity: blocking.** **Correction.** Reconcile the two gates; state which tiling configurations are
supported and which are not.

### 3.6 This is a product-scope change and belongs in `product.md`

Yes. Which devices and window configurations the app can be used in is product scope, and `product.md` owns
"the product definition and target-MVP feature boundaries" (`product.md:3`), states the supported platforms
(`:19`–`:23`), and already carries the iPad multitasking statement (`:27`). `interaction-design.md` explicitly
"does not own product feature scope" (`interaction-design.md:3`). Restricting the app out of most iPad tiling
configurations is not an interaction detail; it is a change to `product.md:27`.

**Severity: blocking.** **Correction.** Make the decision in `product.md` (amending `:27`), and have
`interaction-design.md` reference it rather than establish it.

---

## 4. Play controls and 认输

### 4.1 Human-versus-AI having no flip control — the PR's claim is correct, but the decision is new and silent

The accepted orientation text gives a flip control to Free Play (`:185`, "Once the game starts, a visible
**Flip Board** control allows the player to change orientation at any time") and to history replay (`:186`,
"History replay provides the same visible orientation control"). The human-versus-AI bullet (`:184`) states
only that the human's side is at the bottom. `:189` governs *how* flipping is exposed where it exists, not
whether it exists. So the PR's "it is the mode the accepted orientation behaviour gives a flip control" is
**accurate** and the inventory does not contradict `:184`–`:189`.

But the accepted text is *silent* on human-versus-AI, and this PR converts silence into a decided absence — a
human-versus-AI player can never view the position from the AI's side. That was not in the confirmed decision
list.

**Severity: should-fix.** **Correction.** Say so explicitly and give the reason ("human-versus-AI has a fixed
perspective by `:184`, so no flip control is offered"), so a reader can see it was decided rather than
overlooked.

### 4.2 The replay row is six controls, and the gate says "no fourth control in any state"

> "**Replay** — the transport controls and **翻转棋盘**." — `:241`
> gate: "…and the transport plus 翻转棋盘 in replay, **with no fourth control in any state**." — `testing.md:65`

The transport is five controls (`:350`: "jump to beginning, one move back, play or pause, one move forward,
and jump to end"), so replay has six. The gate's own sentence describes a state with more than four controls
and then forbids it. Read literally the gate also forbids two other accepted elements: the autoplay speed
control (`:355`, "session-only speeds of 0.5×, 1×, and 2×") and the on-screen Help entry point (`:388`, "Help
is reachable from Settings **and from the game screen**").

**Severity: should-fix.** **Correction.** "…with no fourth control in the play-control cluster in either play
mode". Scope the constraint to the cluster, which is what `:237` actually says.

### 4.3 The replay inventory omits the accepted autoplay speed control

`:355` accepts session-only speeds of 0.5×, 1×, 2×. The PR's replay inventory is "the transport controls and
翻转棋盘" and the gate repeats it. Whether the speed control is part of "the transport" is not stated, and the
"never four" framing makes it read as excluded.

**Severity: should-fix.** **Correction.** Name the speed control in the replay row or state that it is part of
the transport.

### 4.4 The still-open move-list affordance now has no room by construction

`:477` says the stacked move list "is reached on demand", and how is still open (`:497`). Reaching it requires
an affordance, and `:237` now says three controls "never more". The PR closes a door on a question it leaves
open in the same commit.

**Severity: should-fix.** **Correction.** Note in the open item that the on-demand affordance must live
outside the three-control cluster.

### 4.5 判和 carrying the claim state is consistent with `:344`, but `:263` is left contradicting it

> "After **继续对局**, the same still-valid claim is exposed through a **non-blocking 可判和 affordance**"
> — `:344`, accepted

An enabled-and-marked 判和 control is a legitimate reading of "non-blocking 可判和 affordance", so no
contradiction there. But:

> "The placement of the persistent **可判和** affordance **remains open below** and is not settled by this."
> — `:263`, unchanged accepted text

The PR settles that placement at `:243` and **deletes the open item `:263` points to**. `:263` now asserts,
inside an accepted section, that a question is open which the same document has just answered. Per the
document's status header, sections outside **Need to discuss** are accepted, so the document now states two
incompatible things about what is accepted.

**Severity: should-fix.** **Correction.** Rewrite `:263` to point at [Play controls](#play-controls).

### 4.6 The gate's "no separate 可判和 element" is unscoped and collides with accepted metadata

> gate: "…with **no separate 可判和 element appearing**." — `testing.md:66`

可判和 remains an accepted *metadata* string in the save-and-continue confirmation (`:296`, "进行中 · 可判和 ·
42 步") and claim availability is accepted in the Play destination metadata (`:287`). A literal reading of the
gate fails those.

**Severity: nit.** **Correction.** "…no separate 可判和 control on the board page".

### 4.7 The resign confirmation: correct against `game-data.md` and `product.md`; title style diverges

Rules check — all consistent:

- `product.md:40`: "Resign is available only in human-versus-AI games. After confirmation, resignation records
  a loss for the human player." → matches "absent in Free Play and replay" and "记为你落败".
- `game-data.md:51`: "`resignation` only in `human-vs-ai`, with the outcome the win for the side opposite
  `human_side`." → matches.
- `game-data.md:107`: "Confirmed resignation records a human loss and moves the game to immutable History." →
  `:251` restates this sentence nearly verbatim. `interaction-design.md:3` says it does not own persistence;
  a verbatim restatement is a second copy of a `game-data.md` rule.
- `core-interface.md:50`: `mxq_game_resign` "commits the loss for the human side with reason `resignation` and
  is legal only in human-versus-AI play." → matches.

Style check — the two accepted user-initiated confirmations use bare action-question titles:
**开始新对局？** (`:291`) and **删除这盘棋？** (`:370`). The new title is **确认认输？**, which prefixes 确认 to
the action. No accepted title does that, and the 确认 is redundant with the dialog's own function.

The copy was a confirmed product-owner decision, so I raise this only as a consistency observation.

**Severity: nit.** **Correction (optional).** **认输？** would match the accepted pattern. If **确认认输？**
is deliberate, no change.

### 4.8 认输's and 悔棋's enabled conditions are unspecified while 判和's is specified

`:243` states 判和's disabled condition precisely. Neither `:239` nor the gates say when 认输 is unavailable
(during AI search? at an unconfirmed terminal result?) even though `core-interface.md:101` exposes
`resign_available` and `undo_available` as core-derived flags the frontend must not re-derive.

**Severity: should-fix.** **Correction.** State that 悔棋, 判和 and 认输 follow `undo_available`,
`claim_available` and `resign_available` from `MxqGameStatus`.

### 4.9 The panel sentence contradicts the three-control rationale

> "Three controls sit together during play, never more, so the cluster stays **reachable under a thumb**"
> — `:237`
> "In the side-by-side layout **these controls live in the panel**, which carries … **the controls that do not
> need to sit under a thumb**." — `:253`

The same three controls are the ones capped at three *because* they need thumb reach, and are then placed in
the container defined as holding controls that do not.

**Severity: nit.** **Correction.** Drop "that do not need to sit under the thumb" from `:253`, or say the
panel carries all controls because thumb reach does not apply at side-by-side sizes.

---

## 5. The result card decision

### 5.1 The motivating arithmetic cannot be checked, and is false on one of the two 375 pt iPhones

> "There is not enough height on the narrowest supported iPhone for the board at its floor, the controls, and
> the card together" — `:331`

Every input is unstated: the device height (see 1.7 — 667 or 812 pt, both 375 pt wide), the numeral strips
(open, `:503`), the turn status, the control row and the card. Value-dependent reconstruction on the SE
(375 × 667, content ≈ 667 − 20 status bar − 49 tab bar = 598): after the board at its floor, two 18 pt numeral
strips, a 44 pt turn status, a 44 pt control row and 36 pt of spacing, ~130 pt remain — plausibly short of a
title-plus-reason-plus-two-actions card, so the claim is *probably* true there. On a 13 mini (375 × 812) it is
comfortably false.

The decision was confirmed by the product owner; the rationale as written asserts a computation the contract
cannot support.

**Severity: should-fix.** **Correction.** Either state the numbers (device height, card height, strip height)
or drop the numeric claim and justify the rule on the accepted principles alone — the board may not be driven
below its floor (`:462`, `:468`), it may not be covered (`:330`), and chrome tightens first (`:468`).

### 5.2 The rule's premise fails at the minimum window, where the card has less room than on the iPhone

At the fixed minimum 380 × 500 the layout is stacked, so the rule applies. Value-dependent: after the
navigation container (~49), board floor (308), numeral strips (36), turn status (44) and spacing (36),
roughly **27 pt** remain for the card — and removing the 44 pt control row yields ~71 pt, still far short.
The card the rule is written to accommodate does not fit in the window this PR simultaneously declares
sufficient. See 1.3.

**Severity: blocking** (same root as 1.3, recorded here because it is the card rule's own premise).

### 5.3 Free Play: the card displaces 翻转棋盘, and "nothing is lost" is false

> "**Nothing is lost: every control the card displaces is meaningless once the game is over**" — `:331`
> Free Play's controls are "**悔棋**, **判和**, **翻转棋盘**" — `:240`

翻转棋盘 is not meaningless once the game is over — studying the final position from the other side is a
normal thing to want, and the accepted orientation contract grants it without qualification:

> "In Free Play, Red is at the bottom by default. Once the game starts, a visible **Flip Board** control
> allows the player to change orientation **at any time**." — `:185`, accepted

In the stacked layout the card removes it; in side-by-side the card leaves it "visible but disabled". Both
contradict "at any time", and both falsify the "nothing is lost" justification. 悔棋 is genuinely not lost
(the card carries it) and 判和 genuinely is meaningless (see 5.5), so the flip control is the single
counterexample — and it is in two of the three modes' rows.

**Severity: blocking.**

**Correction.** Exempt 翻转棋盘 from the displacement and the disabling: the card takes the place of the
game-action controls, and the flip control remains available in Free Play and replay, as `:185`/`:186`
require. Update `testing.md:68` accordingly.

### 5.4 Side-by-side shows two 悔棋 controls in opposite states

`:333`: "Before confirmation, the actions are **悔棋** and **结束对局**." The card carries an enabled 悔棋;
`:331` leaves the panel's control row "visible but disabled", including its own 悔棋. Same label, same panel,
simultaneously enabled and disabled. This is precisely the "second source of truth" the same PR rejects for
navigation (`:472`) and for panel metadata (`:253`).

**Severity: should-fix.** **Correction.** Hide the displaced controls in side-by-side too, or exclude 悔棋
from the disabled row while the card offers it.

### 5.5 判和's claim state does not conflict — checked and clear

A natural terminal result and an unclaimed threefold repetition cannot coexist: `game-data.md:51` records that
"in this ruleset `threefold-repetition` is always a user claim and every other rule reason is automatic", and
`:341` makes the repetition non-terminal. Reaching a natural terminal result ends the position that carried
the claim. So 判和 is legitimately meaningless behind the card, and "disabled" is correct for it.

**No finding.**

### 5.6 Recorded-to-History state, replay, and the repetition notice

- **Recorded state (回放 / 完成).** `:335`–`:336`: the card changes to **已记录到历史** and carries 回放 and
  完成. It is still "shown", so the controls remain displaced. Consistent, and correct — except that in Free
  Play this extends the loss of 翻转棋盘 past the end of the game, when reviewing the final position is the
  main remaining activity (see 5.3).
- **Replay.** No result card exists in replay, and replay has no play controls, so the rule is vacuous there.
  Consistent. But `testing.md:68` says "in the stacked layout the result card takes the place of the play
  controls while shown" without excluding replay, and stacked replay is the state with the *most* chrome
  (transport + flip + move list per `:478` + progress element per `:266`). See 1.3.
- **Threefold-repetition notice.** `:342` gives it copy and two actions but no placement, and `:344` implies
  the first presentation is blocking ("instead of repeatedly presenting the same blocking notice"). The new
  displacement rule covers only "the card", so the notice's placement in the stacked layout is undefined. If
  it is a modal alert, it covers the board, which the card is forbidden to do — an asymmetry worth stating.

**Severity: should-fix** (for the replay gate scope and the notice's placement). **Correction.** Exclude
replay from `testing.md:68`, and state whether the repetition notice is a modal alert or follows the card's
displacement rule.

---

## 6. Document-status discipline and completeness

### 6.1 Are the four removed **Need to discuss** items genuinely resolved?

| removed item | verdict |
|---|---|
| "Define the exact widths at which the layout shape **and the navigation presentation** change, whether the navigation offers the user a switch …, and how the on-demand move list is presented in the stacked layout." | **Partly. Layout widths: relocated, not resolved** — the rule depends on an undefined panel minimum (2.1). **Navigation width: not resolved — made circular** (2.4). **User switch: resolved** (6.3). **Move list: correctly retained** in the new item. |
| "Fix the minimum window size for macOS and for iPadOS windowing …, and name the narrowest supported iPhone …" | **Partly.** A number is fixed but is internally contradicted (1.1), incomplete (1.2), validated against the wrong worst case (1.3) and depends on an unaccepted input (1.4). The iPhone is named by *width* only, and "supported" was quietly changed to "verified against" (1.7). |
| "Resolve how the non-dismissible result card, the retained draw-claim affordance, and accessibility text sizes fit the stacked layout's remaining space …" | **Mostly.** Card decided (with the defects in item 5); draw-claim affordance decided (4.5) but `:263` left contradicting it; accessibility text sizes correctly retained. |
| "Define what the side-by-side panel contains **beyond** the turn status, move list, game metadata, and controls, how that metadata relates to the Play destination's own …, and **what the stacked layout does with the controls that panel would otherwise hold**." | **Partly — reworded.** `:253` restates the identical four-item list, so "what it contains beyond" is answered only by implication, never stated. The metadata relation **is** resolved. The stacked-layout half is **not**: the controls and turn status are placed and the move list is deferred, but the panel's **game metadata has no stated home in the stacked layout**. |

**Severity: should-fix.** **Correction.** State "the panel contains nothing beyond these four" if that is the
decision, and say where the metadata goes in the stacked layout (or note it is only in the Play destination
there).

### 6.2 Things newly written as accepted that were not confirmed decisions

Confirmed by the product owner: the derived breakpoint, the card replacing the controls, the resign
confirmation copy with the shorter message, the 720 pt board cap. Everything below is the author's:

| author-chosen | assessment |
|---|---|
| **Minimum window 380 × 500** | Not merely a design internal — it is a shipped constraint that removes most iPad tiling configurations (3.3) and it fails its own requirement (1.1–1.4). **Blocking.** |
| **iPadOS unavailability at narrow multitasking widths** | Misstates platform behaviour (3.1), contradicts `:448` and `product.md:27` (3.4), contradicts `testing.md:55` (3.5), belongs in `product.md` (3.6). **Blocking.** |
| **375 pt narrowest iPhone** | Value is correct; framing and terminology are not (1.7). **Should-fix.** |
| **Three-control inventory and its per-mode composition** | Consistent with `:184`–`:189` and `product.md:40`, but silently decides the human-versus-AI flip question (4.1) and collides with replay's real control count and the open move-list affordance (4.2–4.4). **Should-fix.** |
| **判和 carries the claim state** | Consistent with `:344`; leaves `:263` contradicting (4.5). **Should-fix.** |
| **No user-facing navigation switch** | See 6.3. **Should-fix.** |
| **Panel metadata restates Play metadata** | Benign and consistent with `:287`. **No finding.** |
| **"Controls remain visible but disabled" in side-by-side** | Creates a duplicated 悔棋 (5.4) and disables Free Play's flip control (5.3). **Blocking via 5.3.** |

### 6.3 "No user-facing switch" contradicts the platform guidance for the container the contract adopts

> "The user is **not offered a choice** between the two presentations: the width rule already selects the one
> that fits, and a preference would be a second source of truth" — `:472`

HIG *Layout: iPadOS*, on the adaptive tab-bar/sidebar container this section describes: "**Consider a
convertible tab bar for adaptive navigation.** … The app first launches with your choice of a sidebar or a
tab bar, and then **people can tap to switch between them**. As the view resizes, the presentation style
changes to fit the width of the view. For developer guidance, see `TabViewStyle.sidebarAdaptable`."

The user toggle is the platform's default behaviour for `sidebarAdaptable`; suppressing it is active work, and
it contradicts `:34` ("Prefer platform-native behavior and adaptation over fixed imitations"). It is also not
a "second source of truth" — the HIG's model is that the toggle picks the presentation *within* what the width
allows.

**Severity: should-fix.** **Correction.** Either adopt the platform behaviour, or keep the decision and state
that it deliberately departs from the `sidebarAdaptable` default and why.

### 6.4 The 720 pt cap's own arithmetic

> "Its core stops growing at **720 points**, a pitch of about **103** points … a piece disc approaches **80
> points**" — `:466`

720 / 7 = 102.86, so "about 103" ✓. But the disc is `0.80 p` (`:118`) = 0.80 × 102.86 = **82.3 pt**, which
*exceeds* 80 rather than approaching it. A cap of 700 pt would give a pitch of exactly 100 and a disc of
exactly 80. The 720 figure was the confirmed decision, so the prose is what should change.

**Severity: nit.** **Correction.** "a piece disc of about 82 points".

### 6.5 Do the new `testing.md` gates match the contract?

| gate | verdict |
|---|---|
| `:61` derived switch + stability | **Fails.** The contract guarantees no stability and is circular with navigation (2.4); "that point" misdescribes a 2-D boundary (2.5). |
| `:62` minimum window + iPadOS unavailability | **Fails.** Omits the navigation container (1.2); omits the card and replay (1.3); asserts a platform behaviour that does not exist (3.1); contradicts gate `:55` (3.5). |
| `:63` 720 pt cap, surplus width/height, margin | Matches the contract. Untestable in stacked (no panel) — worth scoping to side-by-side. **Nit.** |
| `:64` no navigation switch | Matches the contract; the contract itself is questionable (6.3). |
| `:65` control inventory, "no fourth control in any state" | **Fails** its own replay clause; forbids accepted autoplay speeds and the on-screen Help entry (4.2, 4.3). |
| `:66` 判和 claim state | Matches `:243`; unscoped "no separate 可判和 element" collides with accepted metadata (4.6). |
| `:67` 认输 confirmation | Matches `:245`–`:251`, `product.md:40`, `game-data.md:51`. **Good.** |
| `:68` card replaces controls | "with the final board fully visible and **unshrunk**" contradicts `:462` (the board is sized to the available space) and the contract's own "the board **at its floor**" framing — at the floor on a 375 pt iPhone the board *is* shrunk from its width-limited size. Also does not exclude replay (5.6), and asserts the side-by-side "visible but disabled" behaviour that breaks Free Play's flip control (5.3). **Fails.** |

**Correction for `:68`.** Replace "unshrunk" with "never driven below its 44-point floor", and exclude replay.

### 6.6 Cross-document duplication

`:251` restates `game-data.md:107` almost word for word, in a document that "does not own … persistence
formats" (`:3`). Harmless today because they agree, but it is a second copy that can drift.

**Severity: nit.** **Correction.** Reference `game-data.md` rather than restate it.

---

## Verdict

**DO NOT MERGE**

Blocking findings, in order of the sections above:

1. **1.1** — 500 − 308 = 192 pt, below the "more than 200 points" the same paragraph uses to justify the 44 pt
   floor. The paragraph contradicts itself.
2. **1.2** — The minimum-window chrome inventory (contract and gate) omits the navigation container, which
   `:472` requires at 380 pt.
3. **1.3** — The minimum was validated against the control row, but the result card, stacked replay and
   accessibility growth are all taller; the card's own rule proves it.
4. **1.4** — The requirement depends on the numeral-strip geometry, which `:503` still lists as open.
5. **1.7** — The card's motivating claim is a height argument resting on a height (667 pt) the contract never
   states; only a width is fixed.
6. **2.1 / 2.2** — The panel's minimum width exists in no contract, so the derived rule is not derivable and
   "near 700 points" is not reproducible.
7. **2.3** — "The switch falls near 700 points" contradicts retained text saying iPad portrait is stacked;
   every supported iPad is ≥ 744 pt wide in portrait.
8. **2.4** — The layout rule and the navigation presentation are mutually defined, producing an oscillation
   band for any non-zero sidebar width; the new gate asserts a stability the contract does not provide.
9. **3.1** — A declared minimum bounds resizing on iPadOS 26; it does not make the app unavailable.
10. **3.3** — The 500 pt height, not the width, is the binding constraint, and it excludes quadrant tiling on
    every iPad but the 13-inch models, top/bottom halves in landscape on four iPads, and vertical thirds in
    portrait on all of them. The PR names none of this.
11. **3.4 / 3.5 / 3.6** — It contradicts `interaction-design.md:448`, `product.md:27` and `testing.md:55`, and
    is a product-scope change made outside `product.md`.
12. **5.2** — At the fixed minimum window the result card does not fit even after displacing the controls.
13. **5.3** — In Free Play the card displaces 翻转棋盘 and side-by-side disables it, contradicting `:185`
    ("at any time") and falsifying the "nothing is lost" rationale.

Should-fix: 1.7 (verified-against vs supported), 2.5, 3.2 (stale Slide Over premise), 4.1, 4.2, 4.3, 4.4, 4.5
(`:263` dangling), 4.8, 5.1, 5.4, 5.6, 6.1 (panel metadata in stacked; "beyond" unanswered), 6.3, 6.5
(gates `:61`, `:62`, `:65`, `:68`).

Nits: 1.5, 1.6, 2.6, 4.6, 4.7, 4.9, 6.4, 6.6.

What is sound and should survive a revision: the resign confirmation and its consistency with `product.md:40`,
`game-data.md:51`/`:107` and `core-interface.md:50`; 判和 carrying the claim state; the 375 pt width itself;
the 720 pt cap; the card-replaces-controls decision (its rationale, not its scope, is what fails); and the
principle that a derived rule beats a named breakpoint — which needs the panel's minimum width defined before
it becomes one.
