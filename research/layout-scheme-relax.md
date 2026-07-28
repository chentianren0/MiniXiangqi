# A layout scheme by relaxation — the trade-off frontier, and the smallest scheme that sits on it

Workspace research note. **Not a contract, not a proposal to merge.** It answers one question: given
`layout-constraints.md`'s measured table, which accepted constraints must give, how much does each buy, and
what is the cheapest complete scheme that survives?

Nothing under `MiniXiangqi/` or any worktree was modified. No Git or GitHub state was changed. No probe
sources were added; every number below is computed from the **existing measured** data in
`discussion-drafts/layout-probe/` (`out8-se3-P.txt`, `out-mac2.txt`) through the existing `budget8.py`
loader, re-run in this session. §12 reproduces every table.

**Inputs I did not re-derive**, per the brief: the device list, the measured chrome, the three container
presentations and their two breakpoints, the corrected 25 pt iPad bottom inset, the element heights at all
twelve Dynamic Type steps and fifteen widths, and the accepted board-block formulas. All are
`layout-constraints.md` §§1–5.

**Label discipline** is inherited. *Measured* = a probe in `layout-probe/`. *Derived* = arithmetic over
measured inputs, inputs named. *Reasoned* = an argument, flagged, with its cost priced if it is wrong. Two
claims in this note are reasoned rather than measured; both are named in §11 and both carry a **measured
fallback**, so the scheme's verdicts do not depend on them.

---

## 0. The headline, in four sentences

1. **The reported unsatisfiable set is not unsatisfiable.** `layout-constraints.md`'s headline —
   `p ≥ 44` ∧ *final board fully visible under the result card* ∧ *iPhone SE supported* ∧ *range reaches AX3*
   — is satisfiable, with **+38 pt to spare on the binding cell**, once three things that no accepted
   sentence requires are stopped: presenting a turn status beside a result card that has already said what
   the turn status would say, laying the card out at the body inset so that it wraps by half a point, and
   treating the threefold notice as a resident surface when the contract's own word for it is *blocking*.
   §3.1–§3.3 price each in points. None of the four constraints is weakened.
2. **The layout rule is under-determined for a provable reason, and the fix is not a better width.** No
   threshold on width — scene or usable — separates iPad portrait from iPad landscape, because the measured
   280 pt sidebar makes portrait usable widths run to 984 and landscape usable widths start at 760, and
   because the widest portrait *scene* (1032) is wider than the narrowest landscape scene (1024). §4.1 is
   the proof. The rule must test **two** quantities, and both must be raw geometry.
3. **What is genuinely irreducible is smaller and different from what was reported.** Of the 126 iPad tiling
   cells, **34 cannot hold a 308 pt board under any arrangement whatsoever** — the board alone does not fit —
   and 4 more are lost to the accepted "no glass intersects the board block" rule. That is the whole of the
   irreducible set. `I5` ("the horizontal third is impossible on every supported iPad in every orientation")
   is **false**: two of the eighteen hold `p ≥ 44` through AX3 under this scheme. `I6`'s thirteen failing
   top/bottom halves reduce to **one**. §5.2.
4. **The minimum relaxation set has three members**, and every one of them is a statement about a window the
   user has deliberately made too small to play in, not about a supported device at a supported text size.
   They are listed in §2.0 and priced against nine alternatives in §2.

---

## 1. Method: separate *re-composition* from *relaxation*

The three rejections all foundered on the same move — a number was adjusted to make a cell fit, and the
adjustment turned out to be an accepted sentence. So this note keeps two ledgers.

- A **re-composition** changes what the layout contains or how it is laid out. It costs no accepted
  constraint. It may still cost an accepted *sentence*, in which case the sentence and the amendment are
  quoted.
- A **relaxation** breaks an accepted constraint. Each is named, its exact yield in points and in cells is
  computed, and its user cost is stated.

The brief's accepted constraint list is the ledger's left-hand column, verbatim, and §10 walks it.

**The composition rule** is `layout-constraints.md` §5's, unchanged, so that every number here is comparable
with that note's: resident stack = `Σ(element heights) + n × 12 pt`, one gap per element. §7 shows every
conclusion survives the gap at 0, 16 and 20 as well.

---

## 2. The trade-off frontier

### 2.0 The minimum relaxation set

Exactly three, and no proper subset works.

| # | relaxation | what it buys | what it costs a user |
|---|---|---|---|
| **R1** | **The move list is never resident in the stacked layout.** It is a user-summoned sheet, in ordinary play and in replay alike, and it may cover the board. | Removes `replay-list1/3/5` from the resident budget on every device. Alone it converts `I4` — *"every supported iPhone fails a resident three-row list at some text size; the SE fails from xS"* — from a failure into a non-state. | A user in stacked replay taps once to see the move list, and the board is hidden while they read it. The accepted requirement (`:359` "highlights the currently displayed move and allows the user to jump to a selected move") is served in full. It costs `:494` ("replay in the stacked layout shows the move list"), which must be amended. |
| **R2** | **In a window too small to hold a 44 pt board at the platform's default text size, the board is a non-interactive preview** and the page says the window is too small to play in. | The only thing that answers the 38 iPad cells of §5.2 without violating `p ≥ 44`. `p ≥ 44 on every *interactive* board` (`:129`) stays literally true, by the same clause that already exempts the pre-start preview. | In 38 of 126 iPad tiling cells the user can see the game but not move a piece until the window grows. All 38 are windows the user chose; none is a device at full screen. **34 of them cannot show a 308 pt board at all**, so no scheme makes them playable. |
| **R3** | **The supported Dynamic Type range is xS through AX3, and the play/replay page clamps above it.** | Above AX3 the SE needs 605 pt (AX4) and 633 pt (AX5) of content against 564. Nothing recovers 41 and 69 points. | A user at AX4/AX5 sees the *board page* at AX3 metrics. History, Settings and Help are unclamped, so every screen that is only text still grows. The alternative — the board at 31.7 pt, a 25 pt disc — is worse for exactly that user. |

**Why no proper subset works.** Drop R1 and `replay-list3` fails on the SE at xS by 56.5 pt (`I4`, robust to
zero gaps). Drop R2 and 38 cells have no defined behaviour, 34 of them provably unfixable. Drop R3 and the
SE fails the result card by 41 pt at AX4 with every re-composition already applied.

**What is *not* in the set, and this is the point of the note:** the 44 pt floor on any supported state, the
fully-visible-board rule, the iPhone SE, the AX3 commitment, the 720 pt cap, the three-control cluster, and
the "no glass intersects the board block" rule are all **kept**.

### 2.1 The full frontier — every candidate, priced

Ranked by yield per unit of user cost. Yield is computed against **this scheme's** compositions, so it is
what each relaxation would still be worth after the re-compositions of §3 are applied; several are worth
nothing once those are in place, which is itself the finding.

| rank | candidate relaxation | yield, in points and cells | user cost | verdict |
|---|---|---|---|---|
| 1 | **R1 — move list out of the resident stacked layout** | Removes 3 states from the budget; on the SE `replay-list3` was −56.5 at xS and is gone. On the largest iPhone it removes an AX2 failure. | One tap; the board hidden while reading. | **Adopt.** Cheapest thing on the board — it costs no accepted constraint, only sentence `:494`. |
| 2 | **R3 — declared range xS…AX3, clamped above** | The only thing that answers AX4 (−41 on the SE) and AX5 (−69). | Board-page text stops growing above AX3 for the ~0.5 % of users at AX4/AX5. | **Adopt.** The contract already says "designed and verified through the AX3 accessibility size"; this makes that a *declaration* instead of an unenforced hope. |
| 3 | **R2 — non-interactive board below the floor** | Answers all 38 unfittable iPad cells. | 38/126 tiling cells become unplayable-but-viewable. | **Adopt.** It is the only candidate that answers the irreducible 34 without breaking `p ≥ 44`. |
| 4 | **Let the page scroll when the board cannot hold its floor** | Would recover **28 of R2's 38 cells** at `p = 44` — every cell whose usable width already reaches 308. | Breaks "the final board remains fully visible" (`:339`) in those windows: the card is non-dismissible, so a user could scroll it off. Does nothing for the 10 **width**-bound cells (a vertical third is 208–304 pt of usable width against a 308 pt board; no amount of scrolling widens it). | **Reject**, but record: it is strictly better than R2 for 28 cells if the owner would rather lose visibility than interactivity. That is a product choice, and it is the single cleanest fork in this note. |
| 5 | **Drop the iPhone SE (2nd/3rd gen)** | **Nothing.** Under this scheme the SE holds every state through AX3, the binding cell with +38 pt. | A currently supported device. | **Reject.** `layout-constraints.md` §10 priced this at "one Dynamic Type step"; after the re-compositions it is worth zero. |
| 6 | **Cap the declared range at AX1 or AX2** | **Nothing** on any supported device at full screen; the scheme already reaches AX3 everywhere. It would buy none of the 38 iPad cells of §5.2 either: those fail at **L**, below any accessibility size. | Five accessibility sizes. | **Reject.** Worth zero. |
| 7 | **Let `p` fall below 44 above the declared range** | Same cells as R3, at `p = 31.7` on the SE at AX3 rather than a clamp. | A 25 pt disc and a 13 pt symbol for the user least able to hit a small target; contradicts `:129`, `:480`, `:484`. | **Reject** in favour of R3, which reaches the same cells and keeps the floor. |
| 8 | **Make the result card a sheet** | Would remove the card from the resident budget entirely (−206 pt at AX3). | Directly prohibited: the card "cannot be dismissed by tapping outside it" (`:342`) and the final board "may not be covered". The owner's transient-surface clarification explicitly excludes it. | **Reject.** And unnecessary: §3.2–§3.3 recover 124 of those 206 points without touching the rule. |
| 9 | **Lower the 720 pt board cap** | Nothing. The cap is only reached at content heights above 772; it never binds a failing cell. | — | **Reject.** Worth zero; `layout-constraints.md` reaches the same conclusion. |
| 10 | **Lower the panel minimum from 320 to 280 (metadata may truncate)** | Moves the side-by-side threshold from 644 to 604 of usable width. Recovers **0** of the 126 cells at `p ≥ 44` (checked: the four quadrants that would newly qualify are 344, 365, 377 and 643 pt of usable width — the first three are far below 604 and the fourth is 1 pt short of clearing 308 for the board even at 604). | The terminal metadata line truncates. | **Reject.** Worth exactly zero cells; a 40 pt change to a threshold that no cell sits inside. |
| 11 | **Let resident controls overlay the board block** | Recovers **4** cells (mini 5 portrait quadrant, iPad 8/9 portrait quadrant, iPad Air 3 portrait quadrant, iPad Pro 12.9″ landscape quadrant) — the four where `min(usable W, content H) ≥ 308` but no resident chrome fits beside it. | Breaks the accepted `:40`, which is the contract's most reviewable sentence ("a rectangle a reviewer can measure against a screenshot"). | **Reject.** Four cells is not worth the one geometric rule a reviewer can check from a screenshot. Recorded because it is the *exact* price of `:40`. |
| 12 | **State that some tiling configurations are unsupported** | Nothing dimensional. It is a documentation change that makes `testing.md:55` and `product.md:27` true. | The HIG is explicit that "apps don't control multitasking configurations", so the app cannot prevent the user choosing one; the statement describes behaviour, it does not cause it. | **Adopt as documentation**, not as a relaxation. R2 is what actually happens; this is what the contract must say about it. |
| 13 | **Tighten the inter-element gap to 0** | 12–24 pt. | Nothing visible in the tables — §7 shows every verdict is identical at gaps 0, 12, 16 and 20. | **Reject as a lever**; keep 12 and record the insensitivity, which is what makes the whole note robust. |

**The fork worth putting in front of the owner** is row 4 against R2: in 27 iPad window configurations,
would you rather the board keep its 44 pt floor and the page scroll (so a non-dismissible result card can be
scrolled out of view), or the board shrink and stop accepting moves (so it stays visible and the floor rule
stays literally true)? Both are defensible; the arithmetic does not choose.

---

## 3. The re-compositions, and what each is worth

These cost no accepted constraint. Each is stated with the sentence it needs amended and its worth in points
on the binding cell — **iPhone SE, 375 × 667, 564 pt of content, the natural-result card, AX3**.

### 3.1 The threefold notice is a system alert, not a resident surface

The contract's own word for its first presentation is *blocking*: "instead of repeatedly presenting the same
**blocking** notice" (`:352`). A blocking notice with a title, a message and two actions is an alert, and it
is the same shape as the accepted **无法启动 AI 对手** notice, which `layout-constraints.md` §3 already
classifies as a system alert consuming **no board height**.

*Worth, measured:* with the notice resident, the SE holds `p ≥ 44` only through **AX1** (`AX2 −45.0`,
`AX3 −78.0`, with the turn status still present because the game is live and the side to move is real
information). As an alert the state leaves the resident budget entirely and the layout beneath it is
ordinary play, which holds through AX3. **Two Dynamic Type steps on the shortest supported iPhone.**

*What it costs.* `:38` must drop "and the threefold-repetition notice, which never coexist" from the shared
custom-glass slot; the app then defines three custom glass surfaces of which the third carries the result
card alone. And the notice is more interruptive than a card beside the board would have been — it dims the
whole scene, as every other alert the app already presents does. That is the real cost and it is a design
cost, not an arithmetic one.

*It also needs `:40` clarified the same way the owner clarified it for sheets:* a system alert is
transient and covers the whole scene. Unlike a sheet it is not user-summoned, so the owner's existing
clarification does not literally reach it. §10 records this as the one place where the scheme needs the
owner to extend a clarification rather than apply one.

### 3.2 The result card replaces the turn status, not only the control row

At a natural terminal result there is no side to move. The turn status's primary line "always identifies the
side to move" (`:268`); the card's title is 红方获胜 / 黑方获胜 / 和棋 and its second line explains the
reason. Two resident elements describing the same thing is exactly what `:238` warns against — "so the board
is never read for two kinds of information at once". In the terminal state the card **is** the status
element.

*Worth, measured:* turn status at AX3 = 64.0, plus one gap = **76.0 pt**. With the status kept, the SE holds
the card only through **AX1**:

```
card 206.0 + status 64.0 + 2 gaps 24.0 + board block 308.0 = 602.0   against 564   →  −38.0
card 206.0 +   —        + 1 gap  12.0 + board block 308.0 = 526.0   against 564   →  +38.0
```

*What it costs.* `:266` "A persistent status element near the board is one coherent description of the
current play state" must be scoped: the element is persistent **while the game is in play**, and the result
card takes its place when it is not. The save-failure capsule and the acknowledgment beat are anchored to
the status element; neither fires in the terminal state (a failed result confirmation uses the accepted
**无法保存对局** alert, `:317`–`:321`), so nothing is stranded.

### 3.3 The result card is laid out at the content width less 8 points, not at the body inset

Measured: the card's ideal width at AX3 is **343.5 pt**. The SE is 375 pt wide with a measured 16 pt layout
margin, giving 343 — so at the body inset the card wraps **by half a point** and costs 254 instead of 206.

| card container width | AX3 height |
|---|---|
| 308 / 320 / **343** | **254.0** |
| **359** / 375 / 404 | **206.0** |

*Worth:* **48.0 pt**. With the card at the body inset the SE holds it only through **AX2** (`AX3 −10.0`).

*What it costs.* A stated layout rule — the result card and the threefold alert are the only elements that
take an 8 pt inset rather than the 16/20 pt body inset — and one more number a reviewer must check. It is
worth saying out loud that a 0.5 pt wrap is carrying two Dynamic Type steps: that is fragile against a
change in the accepted copy, and §11 records it as a required re-measurement whenever the copy moves.

### 3.4 The numeral strips yield whenever the board would otherwise fall below its floor

`:157` already says the strips are "the first thing to yield when type grows, because the stacked layout has
the least room exactly then". This generalises the *reason* to the case it does not currently cover: a short
window. The rule becomes — the strips are shown iff the text size is not an accessibility size **and** a
board with strips still reaches 44 pt.

*Worth:* 32 pt at the floor, and it is what carries several tiling cells (worked at §5.2). It is also what
makes the macOS minimum honest, since macOS honours no Dynamic Type at all and therefore never hides the
strips under the current rule.

*What it costs.* In a short window a reader loses the file numerals and must count to relate a move in the
list to a file — the cost `:157` already names and accepts.

### 3.5 Replay's autoplay-speed control folds into the transport's menu where the row will not fit

`:363` requires autoplay to *offer* session-only speeds of 0.5×, 1× and 2×. It does not require a
permanently visible segmented control. Measured, the speed control costs **39.0 pt at L** (transport with
speed 104.5 against transport alone 65.5) and 39.0 at AX3 (120.5 against 81.5).

*Worth:* it converts two iPad cells and the macOS minimum from marginal to comfortable. It is the last rung
of the ladder before the strips, so it fires rarely.

### 3.6 The move list, the game metadata and Help are summoned from the turn-status element

This answers round 2's finding 2.5 ("in ordinary play nothing is allowed to summon the sheet") and 4.6
("Help has no entry point once the navigation bar is gone") **without a fourth control**, which is what made
those two findings hard: the three-control cluster is full in both play modes and `:266` caps it.

The status element becomes a menu button. Its menu carries 移动列表, 对局信息 and 帮助. The status is already
"one coherent description of the current play state", and everything in the menu is *about* that state.

- **Stacked:** the menu is the only route to all three.
- **Side by side:** the move list and the metadata are resident in the panel, so the menu carries 帮助 only.
- **macOS:** the system Help menu carries 帮助, which is where a Mac user looks; the panel carries the rest.
- **Replay:** the same element (the replay progress status) carries the same menu, which removes the seventh
  transport control that round 2's finding 2.6 objected to. Replay's row returns to the accepted six —
  five transport controls plus 翻转棋盘 — with the speed control inline where it fits.

*What it costs.* Discoverability: a tappable status is a real iOS idiom but it is not self-announcing. It
needs a disclosure chevron, a VoiceOver custom action, and a testing gate that a first-time user can find
the move list. Recorded as a design obligation, not as arithmetic.

### 3.7 The re-compositions together, on the binding cell

```
iPhone SE 375 × 667, no navigation bar, content height 564, usable width 343
natural-result card, AX3 (an accessibility size, so the strips are hidden)

  result card, container width 359 (content 375 − 2 × 8)         206.0   measured
  one inter-element gap                                           12.0   assumed (§7: 0/16/20 all hold)
  board block at p = 44, strips hidden                           308.0   accepted formula
                                                                ------
  required                                                       526.0
  available                                                      564.0
  slack                                                          +38.0
  and the board is not at its floor: p = 49.0, width-bound
```

For comparison, the same cell in `layout-constraints.md` §6.1 is **−86.0**. The 124 pt difference is
76 (turn status, §3.2) + 48 (the wrap, §3.3), and neither is a constraint.

---

## 4. The scheme

### 4.1 The arrangement rule

> **Side by side is used when, and only when, the usable content width is at least 644 points *and* the
> scene is at least as wide as it is tall. Otherwise the layout is stacked. The test is evaluated once, on
> the scene's own geometry, before any element is placed.**

`644 = 308 (board core at the floor) + 16 (gutter) + 320 (panel minimum)`. The threshold is therefore
exactly the width at which side by side can first hold the floor with the panel at its own minimum, which is
why it is the right number rather than a chosen one. The panel minimum is the measured untruncated width of
the terminal game-metadata line, `layout-constraints.md` §7.1.

**Why two tests, and why the second is aspect rather than width.** *Derived, from the measured sidebar.*

| | portrait | landscape |
|---|---|---|
| usable widths, full screen | 704, 712, 728, 770, 780, 794, 794, 794, **984** | **760**, 792, 813, 860, 874, 890, 984, 1046, 1056 |
| scene widths, full screen | 744 … **1032** | **1024** … 1376 |

The portrait range and the landscape range **overlap in both quantities**. A threshold on usable width
cannot separate them (984 > 760); a threshold on scene width cannot either (1032 > 1024 — iPad Pro 13″
portrait is wider than iPad mini 5 landscape). **No width rule can produce "iPad portrait stacks, iPad
landscape splits", which is the product owner's decision and the accepted `:477`/`:478`.** That is a proof,
not a preference, and it is why the three readings in `layout-constraints.md` §7.3 disagree on 16 of 18
rows: they are all trying to do with one number what needs two.

**Why the aspect test uses the *scene* rather than the content.** The sidebar takes 280 pt of leading inset
and 64 pt of top inset changes with it, so a content-based aspect test would flip when the user switches
between the sidebar and the tab bar — which the HIG says is the user's choice. Tested on all eighteen iPad
device-orientations, forcing each presentation:

| | arrangement with the tab bar | with the sidebar | flips? |
|---|---|---|---|
| every iPad, portrait | stacked | stacked | **no** |
| every iPad, landscape | side by side | side by side | **no** |

**The user's sidebar switch never changes the arrangement on any supported iPad at full screen.** It changes
the board's size — iPad 8/9 landscape goes from a 424 pt core with the sidebar to a 664 pt core with the tab
bar — and both are far above the floor. That answers `layout-constraints.md` §11 open item 8.

**Navigation is decoupled from the layout.** The container presents as a bottom bar, a top tab bar or a
sidebar according to the platform's own measured breakpoints on the **window** width (≤ 664 / 668–1024 /
≥ 1025) and the user's switch; the app then lays out inside whatever content rectangle it is given. The
dependency runs one way — window → container → content → arrangement — so there is no cycle. This replaces
`:488`'s "It follows the same width-driven rule as the layout shapes", which round 2's finding 4.1 showed
points at a rule that no longer exists.

### 4.2 Stacked, in full

Used by every iPhone at every text size and in every state (usable width tops out at 400 against a 644
threshold, so no width test ever runs on iPhone), by every iPad in portrait, and by narrow or portrait-shaped
windows on iPad and Mac.

Top to bottom:

1. **The status element** — the turn status in play, the replay progress status in replay. It is also the
   menu button of §3.6. Absent in the two result states, where the card replaces it (§3.2).
2. **The board block** — `7p` core plus the two numeral strips when they are shown, horizontally centred in
   surplus width, and the whole composition vertically centred in surplus height.
3. **One of:** the three-control play cluster; the result card; the replay transport. Never two of them.

Surplus width leaves the board **horizontally** centred, as surplus height leaves it vertically centred —
round 2's finding 1.5, which matters more here than it did there, because iPad portrait is stacked and its
surplus width runs to 280 pt.

Worked, iPhone SE at default text, ordinary play:

```
turn status 36.5 + gap 12 + board block 379.0 + gap 12 + control row 66.5 = 506.0 in 564
p = 49.0 (width-bound: 343 / 7), strips shown at 18 pt each, 58 pt of surplus height, 29 above and below
```

### 4.3 Side by side, in full

Used by every iPad in landscape, by wide iPad windows, and by Mac windows from 684 pt of content width
upward.

- **The board** on the leading side, sized to `min(720, usable width − 336, the largest block the full
  content height allows)`. Nothing sits above or below it, so it gets the whole height.
- **A 16 pt gutter.**
- **The panel** on the trailing side, taking all remaining width, never less than 320. It carries the status
  element, the move list, the game metadata and the controls, and **it scrolls vertically**. Because the
  board is not in the panel, scrolling the panel cannot move the board, so "the final board remains fully
  visible" is unconditionally true in this arrangement at every text size.
- **The result card** is pinned to the top of the panel and does not scroll; the rest of the panel scrolls
  beneath it. The controls it replaces are hidden rather than "visible but disabled", which removes round 2's
  finding 4.3 (two 悔棋 controls in opposite states).

Because the panel scrolls and the board is width-bound, **Dynamic Type costs the side-by-side layout
nothing**: the board's size is a function of width only, and width does not change with text size. Every
side-by-side cell in §5 holds through AX3 for that reason.

Worked, macOS content 820 × 550 — the case round 2 used to demonstrate the oscillation:

```
usable width 780 ≥ 644 ✓   scene 820 ≥ 550 ✓   →  side by side
board core = min(720, 780 − 336, height-limited 498) = 444   p = 63.43
panel = 780 − 444 − 16 = 320
```

### 4.4 Where every transient surface goes

| surface | stacked | side by side | may it cover the board? |
|---|---|---|---|
| move list + metadata | sheet, summoned from the status menu | **resident in the panel** | stacked: yes — user-summoned, per the owner's clarification |
| Help | sheet, from the status menu | sheet, from the status menu; on macOS, the system Help menu | yes, same clause |
| threefold repetition (first presentation) | **system alert** | system alert | yes — §10 records that this needs the owner's clarification extended from sheets to system alerts |
| retained 可判和 | carried by the 判和 control (accepted, `:352`) | same | n/a — resident, beside the board |
| insufficient memory | system alert | system alert | yes, already accepted |
| 认输 confirmation, 保存并继续 confirmation, 无法保存对局, 删除这盘棋 | system alerts | system alerts | yes, already accepted |
| save-failure capsule (**无法保存这一步，请重试。**) | anchored to the status element (accepted, `:257`) | same | no |
| natural-result card | **resident**, replacing the status and the control cluster, below the board | **resident**, pinned at the top of the panel | **no — never** |

The three custom glass surfaces are therefore the play control cluster, the replay transport, and the result
card. During ordinary play exactly one is on screen, which is what `:38` requires.

### 4.5 The tightening ladder — Dynamic Type at every step, and every window size

Applied in this order. Every rung is a pure function of the geometry and the requested text size; no rung's
output is any rung's input. Each rung yields strictly more room than the last, so the ladder terminates and
cannot cycle.

| rung | what yields | why it is first |
|---|---|---|
| 0 | Nothing. The board takes the largest `p` that fits, capped at 720/7. | — |
| 1 | **The numeral strips.** Hidden at accessibility text sizes always, and at any text size where a board with strips would fall below 44. | `:157`, accepted: "They are the first thing to yield when type grows." Returns 32 pt at the floor. |
| 2 | **Replay's autoplay-speed control** folds into the transport's menu. | It is the only resident element that has a natural non-resident home. Returns 39 pt. |
| 3 | **The requested text size**, clamped to the largest supported step that still holds the floor, **never below the platform default (L)** — the board page never renders smaller text than the system's own default. | Chrome is monotone in text size, so "the largest step that fits" is well defined and computed once. The L floor costs exactly one cell (iPad Air 3 portrait quadrant, which would hold at S), and it is the right cost: a board page in type smaller than the system default is not a state worth having. |
| 4 | **The board's interactivity** (R2). Below the floor at L, the board is a non-interactive preview and the page says so. | The accepted floor is scoped to interactive boards (`:129`), and this is the clause that already exempts the pre-start preview. |

At full screen on every supported device, rungs 2, 3 and 4 never fire and rung 1 fires only where `:157`
already says it does. §5 is the proof.

### 4.6 Minimum sizes per platform

| platform | what can be declared | this scheme's value | what holds there |
|---|---|---|---|
| **iPhone** | *nothing* — `UIWindowScene.sizeRestrictions` is measured `nil` on iPhone | — | The floor is a **device** statement: the narrowest and shortest supported iPhone is the **iPhone SE (2nd and 3rd generation), 375 × 667 points**, and every state holds `p ≥ 44` there through AX3. |
| **iPadOS** | a **scene** size, containing 96–121 pt of system chrome | **360 × 600 points** | Every resident state at `p ≥ 44` through **xxxL** with the numerals shown; AX1–AX3 through rungs 1–3. Alternative 360 × 584 holds the same range with +2 pt instead of +18 on ordinary play. 360 × 698 would hold AX3 *at the minimum* with no clamping at all. |
| **macOS** | a **content** size, below the title bar and toolbar | **360 × 480 points** | Every resident state at `p ≥ 44` with the numerals shown and the speed control inline: play +40, result +21, replay +9. The pre-start page is 4 pt over and simply shrinks its preview, which carries no floor (`:486`). |

**The macOS toolbar stops being load-bearing.** On the display the contract names as its worst case, the
binding state (`result`) needs 459 pt of content:

| toolbar | content height | slack |
|---|---|---|
| none | 550 | **+91** |
| `.unifiedCompact` | 542 | +83 |
| `.unified` / `.automatic` | 516 | **+57** |
| `.expanded` | 499 | +40 |
| `.preference` | 494 | +35 |

Round 2's finding 3.7 was that a standard unified toolbar left 13 pt, which "is not a budget". Under this
scheme every toolbar style clears the binding state by at least 35 pt, so the contract can say "the Mac
window carries whatever toolbar the design wants" and mean it.

**A 360 × 698 iPadOS scene minimum no longer excludes the iPad mini.** `layout-constraints.md` §8.1's
sharpest product finding — *"supporting the result card at AX3 in a minimum-size window and supporting the
iPad mini are mutually exclusive"*, because the card needed a 765 pt scene and the mini is 744 pt tall in
landscape — dissolves: this scheme needs **698**, and 698 < 744. The two are compatible. The scheme still
recommends 600 and lets the ladder handle AX1–AX3, because a smaller minimum leaves the user more window
sizes, but the owner now has the option.

### 4.7 The control inventories, unchanged in count

| state | controls |
|---|---|
| play, human versus AI | 悔棋 · 判和 · 认输 |
| play, Free Play | 悔棋 · 判和 · 翻转棋盘 |
| replay | jump to start · one back · play/pause · one forward · jump to end · 翻转棋盘, with the autoplay speed inline where the row fits and in the play control's menu where it does not |
| natural result, before confirmation | 悔棋 · 结束对局 (on the card) |
| natural result, recorded | 回放 · 完成 (on the card) |

Three during play, never more (`:266`), and the move list's summoning affordance is the status element, not
a fourth control.

---

## 5. The proof — every cell of the constraint table

### 5.1 iPhone — 10 point-size classes × 7 states × 10 supported text steps

*Derived* from `out8-se3-P.txt` element heights and the measured content heights of
`layout-constraints.md` §2.2. Each cell is the highest supported text step at which the state holds
`p ≥ 44`, and the pitch there.

| screen | play-AI | play-Free (icon flip) | play-Free (labelled flip) | result card | recorded card | result + separate flip | replay |
|---|---|---|---|---|---|---|---|
| **375 × 667 SE 2/3** | **AX3** @48 | **AX3** @48 | AX2 @49 | **AX3** @49 | **AX3** @49 | AX1 @44 | **AX3** @49 |
| 375 × 812 | AX3 @49 | AX3 @49 | AX3 @49 | AX3 @49 | AX3 @49 | AX3 @49 | AX3 @49 |
| 390 × 844 | AX3 @51 | AX3 @51 | AX3 @51 | AX3 @51 | AX3 @51 | AX3 @51 | AX3 @51 |
| 393 × 852 | AX3 @52 | AX3 @52 | AX3 @52 | AX3 @52 | AX3 @52 | AX3 @52 | AX3 @52 |
| 402 × 874 | AX3 @53 | AX3 @53 | AX3 @53 | AX3 @53 | AX3 @53 | AX3 @53 | AX3 @53 |
| 414 × 896 | AX3 @53 | AX3 @53 | AX3 @53 | AX3 @53 | AX3 @53 | AX3 @53 | AX3 @53 |
| 420 × 912 | AX3 @54 | AX3 @54 | AX3 @54 | AX3 @54 | AX3 @54 | AX3 @54 | AX3 @54 |
| 428 × 926 | AX3 @55 | AX3 @55 | AX3 @55 | AX3 @55 | AX3 @55 | AX3 @55 | AX3 @55 |
| 430 × 932 | AX3 @56 | AX3 @56 | AX3 @56 | AX3 @56 | AX3 @56 | AX3 @56 | AX3 @56 |
| 440 × 956 | AX3 @57 | AX3 @57 | AX3 @57 | AX3 @57 | AX3 @57 | AX3 @57 | AX3 @57 |

**Every supported iPhone holds every state through AX3.** The two shaded columns are the scheme's two
reasoned claims (§11): if 翻转棋盘 keeps a four-character label rather than becoming an icon with the
accessibility label `:218` already requires, Free Play's ordinary play on the SE stops at **AX2**; and if the
flip control must remain visible as a separate button while the result card is up, Free Play's result state
on the SE stops at **AX1**. Both are one device, one mode; both are stated as fallbacks rather than hidden.

The SE column in full, pitch at each step:

| state | xS | S | M | L | xL | xxL | xxxL | AX1 | AX2 | AX3 |
|---|---|---|---|---|---|---|---|---|---|---|
| play-AI | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | **47.7** |
| play-Free (icon flip) | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | **47.7** |
| result card | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | **49.0** |
| recorded card | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 |
| replay | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 |
| pre-start (no floor) | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 48.9 | 48.6 | 49.0 | 49.0 | 49.0 |

The board is **above** its floor everywhere, not at it — 49.0 is `343 / 7`, the width bound. Round 2's
finding on gate G4 ("a tester verifying *at its pitch floor* verifies a state the layout does not produce")
therefore applies to this scheme too, and the gate must read "at or above its pitch floor".

### 5.2 iPad — all 126 cells

9 point-size classes × 2 orientations × 7 window configurations, each evaluated at the worst of
{ordinary play, result card, recorded card, replay} across all ten supported text steps. Container
presentation from the measured breakpoints; iPad margins 20; bottom inset 25 (0 on home-button iPads);
a narrow window's bottom bar taken at 83, which is the iPhone figure and conservative (§11).

| configuration | holds `p ≥ 44` **through AX3** | holds at L or above | non-interactive (R2) | prior note, ordinary play at default text only |
|---|---|---|---|---|
| full screen | **18** / 18 | 18 | 0 | 18/18 |
| side half | **18** / 18 | 18 | 0 | 18/18 |
| vertical two-thirds | **18** / 18 | 18 | 0 | 18/18 |
| **top / bottom half** | **17** / 18 | 17 | 1 | **5/18** |
| vertical third | **8** / 18 | 8 | 10 | 8/18 |
| **quadrant** | **3** / 18 | 7 | 11 | **5/18** |
| **horizontal third** | **2** / 18 | 2 | 16 | **0/18** |
| **total** | **84** / 126 | **88** | **38** | 90/126 at default text, ordinary play only |

The four cells that hold at L or above but not through AX3 are all portrait quadrants: iPad mini 6 (L),
iPad 10 / A16 / Air 11″ (xxxL), iPad Pro 11″ 1st–4th (xxxL), iPad Pro 11″ M4/M5 (AX1). In each, rung 3
clamps the board page's text and the board keeps its floor.

The comparison column is not like for like — the prior note's 90 counts one state at one text size, this
note's 84 counts four states across ten text sizes — but the three bolded rows are the finding:

- **`I5` is false.** "The horizontal third is unconditionally impossible on every supported iPad in every
  orientation" was computed with the tile stacked. A horizontal third is short and very wide, so this
  scheme makes it side by side, and the board gets the entire content height:
  ```
  iPad Pro 13″ portrait, horizontal third: scene 1032 × 458.7
  window width 1032 ≥ 1025 → sidebar: content 752 wide, 401.7 tall; usable 712
  712 ≥ 644 ✓ and 1032 ≥ 458.7 ✓ → side by side
  board core = min(720, 712 − 336 = 376, height-limited 401.7) → p = 52.0, core 364
  panel = 712 − 364 − 16 = 332 ≥ 320 ✓
  ```
  iPad Pro 12.9″ / Air 13″ portrait holds it too, at `p = 47.8`, via rung 1 (the strips hide, turning a
  height-limited 43.26 into 47.76). The other sixteen fail because the tile is 160–287 pt of content height
  against a 308 pt board — irreducibly.
- **`I6`'s top/bottom halves collapse from 13 failures to 1.** Same mechanism. `layout-constraints.md`'s
  closest miss, iPad Air 3 portrait at **−7.0**, becomes `p = 59.4`: side by side removes 127 pt of chrome
  from above and below the board in one move. The single survivor is iPad mini 5 landscape, 1024 × 384,
  which has 288 pt of content height and cannot hold 308 by any means.
- **Quadrants go from 5 to 8**, and three more hold at some text size below AX3.

**The 38 cells that take R2, and why each is irreducible.** *Derived.* `ceiling` is `min(usable width,
content height) / 7` — the pitch a board would get with **no** chrome, **no** panel and **no** margins to
spare, i.e. an upper bound no arrangement can beat.

| device | orientation | configuration | scene | usable W | content H | ceiling | binder |
|---|---|---|---|---|---|---|---|
| mini 6 / A17 | P | vertical third | 248 × 1133 | 208 | 1018 | 29.7 | width |
| mini 6 / A17 | P | horizontal third | 744 × 377.7 | 704 | 256.7 | 36.7 | height |
| mini 6 / A17 | L | horizontal third | 1133 × 248 | 813 | 191 | 27.3 | height |
| mini 6 / A17 | L | quadrant | 566.5 × 372 | 526.5 | 257 | 36.7 | height |
| mini 5 | P | vertical third | 256 × 1024 | 216 | 909 | 30.9 | width |
| mini 5 | P | horizontal third | 768 × 341.3 | 728 | 245.3 | 35.0 | height |
| mini 5 | P | quadrant | 384 × 512 | 344 | 397 | **49.1** | *no-overlap rule* |
| mini 5 | L | **top/bottom half** | 1024 × 384 | 984 | 288 | 41.1 | height |
| mini 5 | L | vertical third | 341.3 × 768 | 301.3 | 653 | 43.0 | width |
| mini 5 | L | horizontal third | 1024 × 256 | 984 | 160 | 22.9 | height |
| mini 5 | L | quadrant | 512 × 384 | 472 | 269 | 38.4 | height |
| iPad 8 / 9 | P | vertical third | 270 × 1080 | 230 | 965 | 32.9 | width |
| iPad 8 / 9 | P | horizontal third | 810 × 360 | 770 | 264 | 37.7 | height |
| iPad 8 / 9 | P | quadrant | 405 × 540 | 365 | 425 | **52.1** | *no-overlap rule* |
| iPad 8 / 9 | L | horizontal third | 1080 × 270 | 760 | 238 | 34.0 | height |
| iPad 8 / 9 | L | quadrant | 540 × 405 | 500 | 290 | 41.4 | height |
| iPad 10 / A16 / Air 11″ | P | vertical third | 273.3 × 1180 | 233.3 | 1065 | 33.3 | width |
| iPad 10 / A16 / Air 11″ | P | horizontal third | 820 × 393.3 | 780 | 272.3 | 38.9 | height |
| iPad 10 / A16 / Air 11″ | L | horizontal third | 1180 × 273.3 | 860 | 216.3 | 30.9 | height |
| iPad 10 / A16 / Air 11″ | L | quadrant | 590 × 410 | 550 | 295 | 42.1 | height |
| Air 3 | P | vertical third | 278 × 1112 | 238 | 997 | 34.0 | width |
| Air 3 | P | horizontal third | 834 × 370.7 | 794 | 274.7 | 39.2 | height |
| Air 3 | P | quadrant | 417 × 556 | 377 | 441 | **53.9** | *no-overlap rule* |
| Air 3 | L | horizontal third | 1112 × 278 | 792 | 246 | 35.1 | height |
| Air 3 | L | quadrant | 556 × 417 | 516 | 302 | 43.1 | height |
| Pro 11″ 1st–4th | P | vertical third | 278 × 1194 | 238 | 1079 | 34.0 | width |
| Pro 11″ 1st–4th | P | horizontal third | 834 × 398 | 794 | 277 | 39.6 | height |
| Pro 11″ 1st–4th | L | horizontal third | 1194 × 278 | 874 | 221 | 31.6 | height |
| Pro 11″ 1st–4th | L | quadrant | 597 × 417 | 557 | 302 | 43.1 | height |
| Pro 11″ M4/M5 | P | vertical third | 278 × 1210 | 238 | 1095 | 34.0 | width |
| Pro 11″ M4/M5 | P | horizontal third | 834 × 403.3 | 794 | 282.3 | 40.3 | height |
| Pro 11″ M4/M5 | L | horizontal third | 1210 × 278 | 890 | 221 | 31.6 | height |
| Pro 11″ M4/M5 | L | quadrant | 605 × 417 | 565 | 302 | 43.1 | height |
| Pro 12.9″ / Air 13″ | P | vertical third | 341.3 × 1366 | 301.3 | 1251 | 43.0 | width |
| Pro 12.9″ / Air 13″ | L | horizontal third | 1366 × 341.3 | 1046 | 284.3 | 40.6 | height |
| Pro 12.9″ / Air 13″ | L | quadrant | 683 × 512 | **643** | 391 | **55.9** | *no-overlap rule, by 1 pt* |
| Pro 13″ M4/M5 | P | vertical third | 344 × 1376 | 304 | 1261 | 43.4 | width |
| Pro 13″ M4/M5 | L | horizontal third | 1376 × 344 | 1056 | 287 | 41.0 | height |

**34 of the 38 have a ceiling below 44**: the board alone does not fit, so no arrangement, no chrome
inventory, no text-size policy and no declared minimum recovers them. Ten are **width**-bound (usable width
below 308) and 24 are **height**-bound. A minimum cannot manufacture height, and it cannot manufacture width
either — the nine portrait vertical thirds are 208–304 pt of usable width against a 308 pt board, and even
at a zero layout margin seven of the nine are still short. Letting the page scroll would recover the 28
cells whose usable width already reaches 308, and none of the other 10.

**The four exceptions are worth reading carefully**, because they are the exact price of the accepted
"no glass surface may intersect the board block" rule. Each has room for the board *or* for the resident
chrome, but not for both side by side and not for both stacked. iPad Pro 12.9″ landscape in a quadrant misses
the side-by-side threshold by **one point** of usable width (643 against 644) — and even if it cleared it,
`643 − 336 = 307` leaves the board one point short of 308, so the threshold is not merely coincidentally
right there, it is exactly right.

### 5.3 macOS — the whole window range

macOS has one text-size column (measured: macOS honours no Dynamic Type), and the strips are therefore
always shown unless rung 1 fires on height.

| content size | arrangement | pitch | board core | strips | verdict |
|---|---|---|---|---|---|
| 360 × 480 (**declared minimum**) | stacked | 45.71 play / 44.14 result | 320 / 309 | shown | OK |
| 400 × 500 | stacked | 49.29 (result) | 345 | shown | OK |
| 600 × 550 | stacked | 55.86 (result) | 391 | shown | OK |
| 683 × 550 | stacked | 55.86 | 391 | shown | OK |
| **684 × 550** | **side by side** | 44.00 | 308 | shown | OK — the threshold |
| 700 × 550 | side by side | 46.29 | 324 | shown | OK |
| 780 × 550 | side by side | 57.71 | 404 | shown | OK |
| **820 × 550** | side by side | **63.43** | 444 | shown | OK — round 2's counterexample |
| 1024 × 582 (the contract's worst-case display) | side by side | 76.29 | 534 | shown | OK |
| 1024 × 516 (same display, `.unified` toolbar) | side by side | 67.14 | 470 | shown | OK |
| 1200 × 900 | side by side | 102.86 | **720 (cap)** | shown | OK |
| 1600 × 1200 | side by side | 102.86 | **720 (cap)** | shown | OK |

**The discontinuity at the threshold is real and must be stated, not hidden.** At 683 pt of content width
the board is 391 pt; at 684 it is 308. Making the window one point wider makes the board 83 points smaller,
because the window has just bought a 320 pt panel with a permanently visible move list. That is a visible
step, it is not an oscillation (§6), and the board never falls below its floor on either side of it. The
alternative — choose whichever arrangement gives the larger board — was tested and **rejected**: it makes
iPad mini landscape stacked (stacked 72.4 against side-by-side 68.1), contradicting the accepted "Side by
side, used by iPad landscape" and losing the resident move list on the device the panel exists for.

---

## 6. The oscillation proof

**Claim.** The arrangement, the pitch, the strip visibility, the transport form and the text-size clamp are
each a **function** of `(scene width, scene height, content width, content height, requested text size,
state)`. None of those six inputs is an output of the layout. Therefore the layout has no fixed-point
equation to solve, one evaluation pass produces the final answer, and a second pass produces the same answer.

**Why the previous rule oscillated.** Round 2's rule was *"size the board to the height that remains after
the chrome; if width is left over, split"*. "The chrome that remains" is 127 pt in stacked and 0 in side by
side, because the status and controls move into the panel. So the predicate's input depended on the
predicate's output, and any window whose leftover fell in the resulting 115 pt band flipped forever.

**This rule never computes a leftover.** It compares one measured width against a constant and one measured
width against one measured height.

**The worked counterexample, macOS content 820 × 550, run five times:**

| pass | inputs | test | arrangement | board core | panel |
|---|---|---|---|---|---|
| 1 | usable W 780, scene 820 × 550 | 780 ≥ 644 ✓, 820 ≥ 550 ✓ | side by side | 444.0 | 320.0 |
| 2 | *unchanged* | same | side by side | 444.0 | 320.0 |
| 3 | *unchanged* | same | side by side | 444.0 | 320.0 |
| 4 | *unchanged* | same | side by side | 444.0 | 320.0 |
| 5 | *unchanged* | same | side by side | 444.0 | 320.0 |

Round 2's band at content height 550 was `W ∈ [775, 871]`. Under this rule every width in that band is side
by side on the first pass and stays there; the arrangement changes exactly once across the whole macOS range,
at content width 684, and only because the window crossed a constant.

**Three further stability checks.**

1. **Rung 1 (strips) cannot cycle.** Let `p₁` be the largest pitch with strips and `p₀` the largest without;
   `p₀ ≥ p₁` always, since removing the strips only removes a height requirement. The rule is "show iff
   `p₁ ≥ 44`", evaluated on `p₁`, and the chosen pitch is `p₁` when shown and `p₀` when hidden. Hiding the
   strips can never make `p₁` re-qualify, because `p₁` does not depend on whether they are shown.
2. **Rung 3 (the text clamp) cannot cycle.** Chrome is monotone non-decreasing in text size (verified across
   all twelve steps for every element in `out8-se3-P.txt`), so "the largest step whose chrome leaves room for
   a 308 pt block" is a well-defined maximum over a prefix, computed once from the geometry. Clamping the
   text does not change the geometry.
3. **Rung 4 (interactivity) cannot cycle.** Interactivity is an output of the pitch and changes no element's
   height: the control cluster is present either way, so that the user can still undo, claim, resign or
   leave.

**One thing that *does* change, and is not oscillation.** The navigation container's presentation is the
platform's and partly the user's. Switching it changes the content rectangle, which changes the board's
size. Tested on all eighteen iPad device-orientations at full screen, it **never** changes the arrangement
(§4.1), and both presentations hold `p ≥ 44` everywhere. It is a user action with a visible, stable result.

---

## 7. Sensitivity — which conclusions depend on my assumptions

The 12 pt inter-element gap and the count of gaps per state are this note's, inherited from
`layout-constraints.md` §5. On the binding cell (iPhone SE, all states, all supported steps):

| gap | result card holds through | Free Play (icon flip) holds through |
|---|---|---|
| 0 | **AX3** | **AX3** |
| **12 (used throughout)** | **AX3** | **AX3** |
| 16 | **AX3** | **AX3** |
| 20 | **AX3** (`p = 48`) | **AX3** (`p = 45`) |

Every verdict in §5 is identical at all four. At a 20 pt gap the margin narrows to 1 pt of pitch on Free
Play, which is the one place a real design that is looser than standard components would first bite.

The three re-compositions of §3.1–§3.3, each removed on its own and all three together:

| variant | result card on the SE | Free Play on the SE |
|---|---|---|
| **the scheme** | **AX3**, +38 pt | **AX3** |
| card at the body inset (343 not 359) | AX2, −10 at AX3 | AX3 |
| turn status kept beside the card | AX1, −38 at AX3 | AX3 |
| threefold notice resident | — | AX1 |
| labelled flip control | AX3 | AX2 |
| all of the above together | **AX1** | **AX2** |

"All of the above together" is essentially `layout-constraints.md`'s original composition, and it reproduces
that note's conclusion. The disagreement between the two notes is entirely in the composition, not in the
measurements, and this table is where a reviewer should look first.

---

## 8. Every accepted constraint, checked

| accepted constraint (the brief's list) | verdict | where |
|---|---|---|
| Cell pitch ≥ 44 pt on every **interactive** board | **Held**, on every supported device at every supported text step, and in 88 of 126 iPad tiling cells. In the other 38 the board is non-interactive (R2), so the constraint is satisfied by its own scoping clause. | §5.1, §5.2 |
| Board core = 7p | Held; unchanged. | §4.2 |
| Board core capped at 720 pt | Held; reached on Mac windows from 1200 pt of content width and never binding on a failing cell. | §5.3 |
| Numeral strips 16 pt each at the floor | Held. | §3.4 |
| Strips hidden at accessibility text sizes | Held, **and extended**: also hidden at any text size where a board with strips would fall below 44. Additive, never contradictory. | §3.4 |
| The final board stays fully visible when the result card is shown, and may not be covered | **Held unconditionally.** Stacked: the card is below the board and replaces the status and the control cluster. Side by side: the card is pinned to the top of a panel that is beside the board, and scrolling the panel cannot move the board. No sheet and no alert is ever presented over the result state. | §4.2, §4.3, §4.4 |
| No glass surface may intersect the board block while it is **resident** | Held. The three custom surfaces — control cluster, replay transport, result card — are all outside the block in both arrangements. | §4.4 |
| A user-summoned transient surface may cover the board | Used, exactly once: the move-list/metadata/Help sheet in the stacked layout. | §4.4 |
| Chrome tightens before the board does; each platform declares a minimum below which neither may fall | Held, and made ordinal: the ladder of §4.5 states *which* chrome tightens *first*, which the contract has never done. Minimums at §4.6. | §4.5, §4.6 |
| iPad supports every orientation; iPhone is portrait only | Held. iPhone is stacked unconditionally (usable width ≤ 400 against a 644 threshold), so no width test ever runs there. Every iPad orientation is evaluated in §5.2. | §4.1, §5.2 |
| Replay shows the move list, highlights the current move, allows jumping to a selected one | Held in capability; **residency is relaxed** in the stacked layout (R1). Side by side keeps it resident in the panel. | §2.0 R1 |
| Three play controls, mode-dependent, as listed | Held, exactly three, in both modes, with no fourth control added for the move list. | §4.7 |
| Dynamic Type is a stated supported range | Held, and now actually *stated*: xS through AX3, clamped above (R3), with the ladder describing every step below it. | §2.0 R3, §4.5 |

### 8.1 Accepted **sentences** this scheme requires amended

Distinguished from the constraints above, because these are document text rather than the brief's list.

| sentence | required amendment | why |
|---|---|---|
| `:38` "one shared slot for the natural-result card **and the threefold-repetition notice**" | the slot carries the result card; the threefold notice is a system alert | §3.1 |
| `:40` "No glass surface may intersect the board block" | extend the owner's transient-surface clarification from user-summoned sheets to **system alerts**, which are transient and cover the whole scene but are not summoned | §3.1, §10 |
| `:266` "A **persistent** status element" | persistent while the game is in play; the result card takes its place in the terminal states | §3.2 |
| `:494` "replay in the stacked layout **shows the move list**" | the move list is summoned on demand in the stacked layout, in play and in replay alike | R1 |
| `:488` navigation "follows **the same width-driven rule as the layout shapes**" | navigation follows the platform container's own breakpoints and the user's switch; the layout follows the content rectangle it is given | §4.1 |
| `:471` "Windows devices that rotate follow the same **width-driven** layout rules" | "the same layout rules" | §4.1 |
| `:475` "chosen by available width" | chosen by available width **and by the scene's proportions**; §4.1 proves width alone cannot do it | §4.1 |
| `:214` 翻转棋盘 "at any time" | either it is an icon control on the card's header (the scheme's choice, unmeasured) or it is scoped to "at any time while the game is in play" (the measured fallback, costing the SE two steps in one mode) | §11 |
| `product.md:27` / `testing.md:55` "including the system tiling configurations" | name what happens in the 38 configurations of §5.2; the app cannot decline them | R2 |
| the pre-existing gate `testing.md:56` "selected by available width … at the same width" | "reach the same arrangement at the same **size**" | §4.1 |

---

## 9. What this scheme must break, and why nothing avoids it

Three things, and only three. Each is R1, R2 or R3, and for each the alternatives were computed rather than
asserted.

**R1 — the move list is not resident in stacked replay.** The alternative is a resident list. Measured, one
resident row costs 32.5 at L and **156.0 at AX3**; three rows cost 298.5 and 712.5. On the SE a resident
three-row list fails at **xS** by 56.5 pt and is robust to zero gaps; even the largest supported iPhone fails
from AX2. There is no arrangement of the accepted elements in which a 375 × 667 iPhone shows a 308 pt board,
a transport and three move rows. The only alternatives are to drop the SE (which buys one step, and this
scheme needs none), or to shrink the board (which breaks the floor).

**R2 — the board goes non-interactive below the floor.** 34 of the 38 cells have `min(usable width, content
height) < 308`: the board alone does not fit, before a single control, gap or margin is counted. Scrolling
recovers the 28 whose usable width already reaches 308, at the cost of the fully-visible rule; nothing
recovers the other 10, which are width-bound. A declared scene minimum does not help, both because a
minimum cannot manufacture space and because the HIG states apps do not control which configuration the
user picks.

**R3 — the declared range stops at AX3.** At AX4 the SE result card needs `285 + 12 + 308 = 605` against
564; at AX5, `313 + 12 + 308 = 633`. Setting every gap to zero leaves −29 and −57. Presenting the card at
the full 375 pt of screen width does not help — measured, the card is 285 at 375 as well, and only reaches
229 at 404, which the SE does not have. The only alternatives are to shrink the board (the floor) or to
scroll (the fully-visible rule).

**What this scheme does *not* have to break**, against the three previous attempts: the 44 pt floor on any
supported device at any supported text size; the fully-visible board under the result card, anywhere; the
iPhone SE; the AX3 commitment; the 720 pt cap; the three-control cluster; and `:40`.

---

## 10. The one thing the owner still has to decide

`:40` currently forbids any glass surface from intersecting the board block. The owner has clarified that a
**user-summoned transient** surface — a sheet — may cover the board. This scheme needs one more step: a
**system alert** covers the whole scene and is transient, but the user did not summon it. Four accepted
notices are alerts already (insufficient memory, 无法保存对局, the 保存并继续 confirmation, 删除这盘棋), so
the behaviour is not new; what is new is that this scheme moves the threefold-repetition notice into that
class, and it is worth two Dynamic Type steps on the shortest supported iPhone.

If the owner declines, the fallback is exact and does not break the scheme: the threefold notice stays a
resident custom surface, and **the declared range on a 375 × 667 iPhone is AX1 in the repetition state**
(measured: AX1 +13, AX2 −45, AX3 −78). Every other state and every other device is unaffected.

The second decision is row 4 of §2.1 against R2: scroll, or stop accepting moves, in 27 iPad window
configurations. Neither is free and the arithmetic does not choose.

---

## 11. What is reasoned rather than measured, and what would close it

1. **The Free Play flip control as an icon.** `:218` requires the control to carry "a localized
   accessibility label", which is what an icon-only control needs and a labelled one does not, so an icon is
   contract-supported — but I budgeted it at the **measured AI control row**, not at a measured icon row.
   *Closing it:* one probe run measuring `悔棋 · 判和 · [icon]` at twelve sizes and fifteen widths.
   *Fallback if it is wrong:* Free Play's ordinary play on the SE holds through AX2 rather than AX3 —
   measured, `controlRowFree` at AX3 and 343 pt is 238.0 against the AI row's 142.0.
2. **The flip control while the result card is up in Free Play.** The scheme places it as an icon in the
   card's header, which is assumed to add no height. *Closing it:* the same probe run, measuring the card
   with a header icon. *Fallback:* as a separate visible button below the card it is **−52 pt at AX3 and
   −22 at AX2 on the SE**, so Free Play's result state there holds through AX1. Both fallbacks are in the
   §5.1 table as their own columns, so the proof does not rest on either claim.
3. **The result card's 0.5 pt wrap.** The whole 48 pt saving of §3.3 rests on the card's ideal width being
   343.5 against 359 pt of container. Any change to the accepted card copy can move that, and the change
   would be silent. *Closing it:* re-measure whenever the copy moves, and state the 359 in the contract so
   that a later reader knows it is load-bearing.
4. **The iPad bottom bar in a narrow window is the iPhone's 83 pt.** `layout-constraints.md` §11 item 1 is
   unclosed; a hosted-window proxy reported 72. Using 83 makes every narrow-window verdict here
   **conservative**: with 72 the declared iPadOS minimum falls by 11 pt and two of §5.2's marginal cells
   improve. No verdict flips the other way.
5. **Five iPads cannot be booted on this toolchain**, so their insets are transferred within a stated class.
   Inherited unchanged.
6. **Every iOS number is from iOS 27.0, not the 26.5 the product targets.** Inherited unchanged.
7. **The element heights are standard SwiftUI controls carrying the accepted copy** — a floor for what the
   real design costs. Every "holds" here is therefore optimistic and every "cannot" is conservative, which
   is why §7's gap sweep matters: at a 20 pt gap the scheme still holds AX3 everywhere with 1 pt of pitch to
   spare on its tightest state.
8. **Whether iPadOS clamps, overlaps or omits a tile below the declared minimum is unobserved.** This
   scheme does not depend on the answer: R2 covers the case where the app is given a window it cannot play
   in, whatever the system does with the declaration.

---

## 12. Reproducing this

No new files were created. Everything is computed from the existing measured probe output through the
existing loader:

```
cd discussion-drafts/layout-probe
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer   # not needed for the arithmetic
python3 - <<'EOF'
from budget8 import load, loadmac, h, strip, SZ
ios = load('out8-se3-P.txt'); mac = loadmac('out-mac2.txt')
GAP, PANEL, GUTTER, SBS_W, CAP = 12.0, 320.0, 16.0, 644.0, 720.0
SUPPORTED = ['xS','S','M','L','xL','xxL','xxxL','AX1','AX2','AX3']
ACC = {'AX1','AX2','AX3','AX4','AX5'}

def p_with(A, Wb):                      # largest pitch with the numeral strips
    lo, hi = 1.0, 400.0
    for _ in range(300):
        m = (lo + hi) / 2
        if 7*m + 2*strip(m) <= A and 7*m <= Wb and 7*m <= CAP: lo = m
        else: hi = m
    return lo

def p_no(A, Wb):                        # largest pitch without them
    return max(0.0, min(A/7.0, Wb/7.0, CAP/7.0))

def board(A, Wb, accessibility):        # rung 1
    if not accessibility:
        p1 = p_with(A, Wb)
        if p1 >= 44.0: return p1, True
    return p_no(A, Wb), False

def arrangement(usableW, sceneW, sceneH):          # section 4.1, evaluated once
    return (usableW >= SBS_W) and (sceneW >= sceneH)

# stacked chrome: the result states carry the card alone, at the content width less 8 pt each side
STATES = {'play-AI':   [('turnStatus','body'), ('controlRowAI','body')],
          'result':    [('resultCard','card')],
          'recorded':  [('resultCardRecorded','card')],
          'replay':    [('turnStatus','body'), ('transportPlusSpeed','body')],   # rung 2 falls back to transport6
          }
EOF
```

The four tables were produced by driving that core over: the ten iPhone classes of
`layout-constraints.md` §1.2 with content height `H − topInset − 83`; the nine iPad classes × two
orientations × the seven HIG window configurations, with container chrome
`(32, 83, lead 0)` below 667 pt of window width, `(96, bottomSafe, lead 0)` from 668 to 1024, and
`(32, bottomSafe, lead 280)` from 1025; and macOS content rectangles from 348 × 460 to 1600 × 1200 with
margins 20 and no Dynamic Type axis.

---

## 13. Summary for the reviewer in a hurry

- The reported unsatisfiable set is satisfiable. The binding cell — iPhone SE, natural-result card, AX3 —
  goes from **−86** to **+38**, and the board sits at `p = 49.0`, not at its floor. Nothing was weakened to
  get there; three elements were re-composed and the arithmetic is at §3.7.
- `I1`, `I2`, `I3` and `I4` dissolve. `I5` is **false as stated** — two of eighteen horizontal thirds hold
  through AX3. `I6` reduces from thirteen failures to one.
- What survives is smaller and sharper: **34 iPad window configurations cannot show a 308 pt board at all**,
  and 4 more are the exact price of the accepted `:40`.
- The minimum relaxation set is three: the move list is not resident in stacked replay; the board is
  non-interactive in a window too small to hold its floor; the declared Dynamic Type range is xS through
  AX3. Nine further candidates were priced and eight are worth **zero cells** once the re-compositions are
  in place, including dropping the iPhone SE and lowering the panel minimum.
- The arrangement rule is `usable width ≥ 644 ∧ scene width ≥ scene height`, evaluated once on raw geometry.
  It cannot oscillate because neither input is an output; macOS 820 × 550 is side by side on every pass,
  with a 444 pt board and a 320 pt panel.
- **No width rule can express the owner's iPad decision.** Portrait usable widths reach 984 and landscape
  usable widths start at 760; the widest portrait scene is 1032 and the narrowest landscape scene is 1024.
  That is why the previous rule was under-determined, and it is not fixable by choosing a better number.
- Minimums: iPhone **375 × 667** as a device statement (nothing can be declared); iPadOS scene
  **360 × 600**; macOS content **360 × 480**. The macOS toolbar stops being load-bearing — every style
  clears the binding state by at least 35 pt — and a 360 × 698 iPadOS scene would hold AX3 without clamping
  while still being 46 pt shorter than an iPad mini in landscape, which dissolves the "mutually exclusive"
  finding.
- Two claims are reasoned rather than measured, both about 翻转棋盘, and both carry measured fallbacks that
  cost one device two Dynamic Type steps in one mode. Neither is load-bearing for any other verdict.
