# A board-first layout scheme

Workspace research note. **Not a contract, not a proposal to merge.** It answers the brief: solve for the
board first, let the arrangement fall out, and prove the result against every cell of
`layout-constraints.md`. Nothing under `MiniXiangqi/` or any worktree was modified; no Git or GitHub state
was changed. The only files written are this one and the arithmetic harnesses
`discussion-drafts/bf-solve.py` and `discussion-drafts/bf2.py`, which are scratch code in no repository.

**Every number below is computed by `bf2.py` from the measured probe data already in
`discussion-drafts/layout-probe/`** (`out8-se3-P.txt`, all twelve Dynamic Type steps × fifteen widths on
iOS 27.0; `out-mac2.txt` on macOS 27.0). I re-derived nothing about devices or chrome: the device list, the
83 pt tab container, the 54 pt inline navigation bar, the 280 pt sidebar at ≥ 1025 pt, the 25 pt iPad bottom
inset and the twelve-step element table are taken from `layout-constraints.md` §§1–2 as instructed.

One improvement to the harness is worth stating because it moves numbers: the constraint table's element
lookup rounds the layout width **down** to the nearest measured width, so an element laid out at 360 pt is
priced at its 343 pt height. `bf2.py` keeps that rule but adds the measured `idealW`: if the layout width is
at least the element's own ideal width, the element does not wrap and takes its ideal height. Both inputs are
measured. This matters at exactly one place — the result card's ideal width is **343.5 pt at AX3** — and it is
the difference between 254 pt and 206 pt.

---

## 0. The verdict, up front

`layout-constraints.md`'s headline says the accepted set

> `p ≥ 44` **∧** the final board fully visible and uncovered under the non-dismissible result card
> **∧** iPhone SE (375 × 667) supported **∧** the declared Dynamic Type range reaches AX3

is unsatisfiable, with a −86 pt shortfall.

**It is satisfiable.** On the iPhone SE at AX3 this scheme puts the board at **p = 47.71** (core 334.0), 8 %
above the floor, with the final board fully visible, uncovered, and the card resident beneath it. I reproduce
the constraint table's −86 exactly under its own assumptions, so this is not a disagreement about arithmetic;
it is that three of its assumptions are design choices rather than accepted constraints.

The three, in the order of how much they are worth:

| # | assumption in the constraint table | what this scheme does instead | worth on the SE |
|---|---|---|---|
| **M1** | the resident chrome is inset by the root layout margin, so it lays out at **343 pt** | the resident chrome is a full-bleed bar at the **scene** width, 375 pt; only the *board block* carries the margin | 48 pt on the card at AX3, 96 pt on Free Play's control row at AX3 |
| **M2** | the result card sits **below a turn status** (`turnStatus + resultCard`) | the result card **is** the turn status in its terminal form; there is no side to move in a terminal position | 64 pt at AX3, 36.5 at L |
| **M3** | the threefold-repetition notice is a **resident** custom glass surface | it is a **system alert**, like the accepted insufficient-memory notice | 246 pt at AX3 — it is the binding state until it is removed |

None of the three is free, and §3 prices each against the accepted text it touches. M3 is the one that needs a
product decision; M1 and M2 are within the layout design.

**What remains genuinely infeasible** is much smaller and much better characterised than the six cells of
`layout-constraints.md` §0:

- **R1.** The 375 × 667 iPhone SE at **AX4 and AX5**. Two-line proof, robust to every arrangement: content
  height 564, board at the floor with strips hidden 308, so the entire chrome budget is **256 pt**; the result
  card *alone*, laid out at the full 375 pt scene width, measures **285 pt at AX4** and **313 at AX5**, before
  any gap and with nothing else on screen. −29 and −57. The card is non-dismissible and may not cover the
  board, so it cannot leave the resident budget.
- **R2.** iPad **vertical thirds in portrait** — 10 of 18 device-orientations. The widest is the Pro 13 at
  1032/3 = 344 pt of scene width; after the measured 20 pt margins that is **304 pt of usable width against a
  308 pt board core**. −4 pt, by width alone, with zero chrome. No arrangement and no minimum can manufacture
  4 pt of width. (A 16 pt compact margin, if iPadOS uses one below 375 pt — **unmeasured** — would recover the
  Pro 13 and the Pro 12.9 and nothing else.)
- **R3.** iPad **horizontal thirds** — 16 of 18. The tallest is 1376/3 = 458.7 pt of scene height, but the
  shortest is 1133/3 = 248, and after chrome most give under 308 pt of content height. **Two now hold** (Pro 13
  and Pro 12.9 in portrait) where the constraint table had none, because a horizontal third is the most
  side-by-side-shaped canvas in the whole inventory and this scheme puts a panel beside the board there.
- **R4.** Six landscape **quadrants** at default text, twelve at AX3, whose usable width (500–643 pt) is below
  the side-by-side threshold and whose content height (313–391 pt) is below what a stacked board plus a turn
  status needs. These are the only failures a *third* arrangement would fix; §11 prices one.

Everything else holds: **all 18 iPad device-orientations at full screen, all 18 side halves, all 18 vertical
two-thirds, 17 of 18 top/bottom halves, every macOS window from the declared minimum to a Studio Display, and
every supported iPhone at every Dynamic Type step from xS to AX3.**

And the structural defect that round 2 called out — the rule oscillating over a 97–127 pt band — is gone by
construction, not by hysteresis: §9 proves it and runs the 820 × 550 counterexample explicitly.

---

## 1. The scheme

### 1.1 The one-paragraph version

> The board is sized before anything else is placed. Its pitch is the largest that the whole **session** can
> hold — every state the game can reach without the window changing — so the board is a constant for as long
> as the player is playing on it. The arrangement is then chosen by a test on the scene rectangle alone, and
> the chrome is placed in whatever the board leaves.

### 1.2 The rule, in full

Four stages, evaluated in this order, once per layout pass. Nothing in a later stage feeds a earlier one.

**Stage 1 — the inputs.** Three, and only three:

```
S   = the scene rectangle           (sceneW × sceneH)
T   = the Dynamic Type size         (one of twelve; on macOS, a single constant — measured)
K   = the session kind              (play-AI | play-Free | replay | prestart-AI | prestart-Free)
```

From `S` and the platform's measured chrome:

```
contentW, contentH  = S minus the system container (tab bar / top tab bar / sidebar / title bar + toolbar)
                      and the safe areas
usableW             = contentW − 2 × layoutMargin      (16 on iPhone ≤ 375 pt, 20 elsewhere — measured)
```

**Stage 2 — the arrangement.** One predicate, two operands:

```
side by side   ⟺   usableW ≥ 308 + 16 + panelMin        (644 on iOS/iPadOS, 581 on macOS)
                ∧   sceneW ≥ sceneH
```

where `308 = 7 × 44` is the board core at its floor, `16` is the gutter, and `panelMin` is **320 pt on
iOS/iPadOS and 257 on macOS** — the measured untruncated width of the terminal game-metadata line, which
`layout-constraints.md` §7.1 identifies as the panel's driver. Otherwise the arrangement is **stacked**.

Neither operand mentions the board's final size, the chrome height, the game state, the text size, or the
arrangement. Both are pure functions of the scene rectangle. §9 is the proof that this is what kills the
oscillation.

**Stage 3 — the board.** The pitch is solved against the session's **state envelope**, not against the
current state:

```
C(K,T)  =  max over every state s the session K can reach, of the stacked resident chrome of s at T
           (0 in side by side — the status, controls, list and metadata are all in the panel)

availH  =  contentH − C(K,T)
availW  =  usableW                                   in stacked
        =  usableW − 16 − panelMin                   in side by side

p       =  max { q : block(q) ≤ availH  ∧  7q ≤ availW  ∧  7q ≤ 720 }
```

with the accepted `block(q) = 7q + 2·t(q)` and `t(q) = round(0.08q + 0.887·s(q))`,
`s(q) = round(clamp(0.32q, 13, 20))`.

**Stage 3b — the strips yield.** If `p < 44` with the strips shown and `p ≥ 44` without them, the strips are
hidden and the larger pitch is taken. This generalises the accepted rule "the strips are hidden at
accessibility text sizes" from *when type grows* to *whenever room is short*, which is the rationale the
contract itself gives them ("They are the first thing to yield when type grows, because the stacked layout has
the least room exactly then"). It is a single conditional evaluated after `p`, so it introduces no cycle. It
is worth **5 iPad tiling cells at default text** and nothing at accessibility sizes, where the strips are
already hidden. §10 records it as an amendment to `:157`.

**Stage 4 — the chrome.** Everything else is placed in what the board left. In stacked: turn status above the
board, the play-control cluster or the result card below it, both full-bleed to the scene width, board
centred horizontally and vertically in the remainder. In side by side: the panel to the trailing side of the
board, 16 pt gutter, panel width = `usableW − 16 − 7p` (never less than `panelMin`, often more), board
centred vertically.

**Recomputation.** Stages 1–4 run again on a **geometry or text event** — rotation, window resize, a
multitasking configuration change, a sidebar/tab-bar switch, a Dynamic Type change, entering or leaving a
session. They never run on a **game-state event**. That is the whole content of §6.

### 1.3 Why this dissolves the circularity

Round 2's rule was `arrangement = f(board size)` and `board size = g(arrangement)`, which is a fixed-point
problem with, as it showed, more than one fixed point over a 97–127 pt band. Here the dependency graph is

```
S, T  ──►  arrangement  ──►  availW ──┐
   │                                   ├──►  p  ──►  chrome placement
   └──►  contentH, C(K,T)  ──► availH ─┘
```

a DAG. The arrangement has no inbound edge from `p`, so no iteration is possible and no fixed point has to be
searched for.

---

## 2. What "board-first" costs, measured

The obvious objection to sizing the board against the envelope rather than the current state is that the
board is smaller than it could be during ordinary play. Measured, on iPhone it is **not smaller at all**:

| iPhone | L | AX1 | AX3 |
|---|---|---|---|
| every one of the ten classes | envelope `p` = play-only `p`, **cost 0.0** | cost 0.0 | cost 0.0 |

The reason is that every iPhone board is **width-bound**: the envelope reduces the height budget, and the
height budget was not what was binding. On the SE the board sits at `p = 49.0` (core 343 = the whole usable
width) at every size from xS to AX2, and only at AX3 does height take over at 47.71.

On iPad the worst envelope cost found anywhere in the 126-cell grid is **5.14 pt of pitch**, on an iPad
10/A16/Air 11 in a landscape side half at AX3 (71.14 with the envelope, 76.29 without). Full screen, where
the board is at or near the 720 pt cap on eight of nine portrait classes, the cost is zero.

**So a board that never changes size mid-game is free on iPhone and costs at most 7 % of pitch on iPad, in
one windowed configuration, at one accessibility size.** That is the strongest single argument for the
approach and it is measured rather than asserted.

---

## 3. The three moves, named and priced

The brief says: do not resolve an over-determined system by quietly weakening a constraint. Each of these
touches accepted text or an accepted inventory. Here is what each is, what it buys, and what it costs.

### M1 — resident chrome is full-bleed to the scene width

`interaction-design.md` fixes the board's margins (`:125`, `:134`, `:142`) and never fixes the chrome's. The
constraint table priced every element at the *usable* width because that is the conservative reading. This
scheme states the opposite explicitly: **the turn status, the play-control cluster, the replay transport and
the result card span the scene width; only the board block is inset by the layout margin.**

This is the native iOS form for these elements — the control cluster and the transport are two of the three
custom **glass** surfaces `:38` names, and a glass bar on iOS spans its container. It is also what keeps the
board block, whose margins *are* fixed, unambiguous.

Measured effect, iPhone SE, at 343 pt against 375 pt of layout width:

| element | text size | at 343 | at 375 | ideal width |
|---|---|---|---|---|
| result card | AX3 | 254.0 | **206.0** | 343.5 |
| control row (Free Play) | AX3 | 238.0 | **142.0** | 515.5 |
| turn status | AX3 | 64.0 | 64.0 | 308.0 |
| result card | AX4 | 285.0 | 285.0 | 390.5 |

**Cost.** A full-bleed bar under the board is a visual change from an inset card, and on a wide iPad in the
stacked arrangement a full-bleed control row is 720 pt wide under a 720 pt board — which is fine — but on a
Pro 12.9 in portrait it is 984 pt wide under a 720 pt board, which is not. **The scheme therefore caps the
resident chrome's own width at the board block's width when the board is narrower than the container**, and
the measurement above is unaffected because on iPhone the board is always the full usable width. This cap is
a placement rule in stage 4, evaluated after `p`, so it creates no cycle — but it does mean the chrome's
layout width is `max(7p, usableW)` capped at `contentW`, and on iPhone that is the scene width. Stated so a
reviewer can measure it.

### M2 — the result card is the turn status in its terminal form

`:266`: "A persistent status element near the board is one coherent description of the current play state.
Its primary line **always identifies the side to move**." A terminal position has no side to move. `:271`
already carves out replay for exactly this reason ("Replay has no side-to-move line"). The result card's own
first line is the localized **红方获胜 / 黑方获胜 / 和棋** and its second explains the reason — that *is* one
coherent description of the current play state.

So in `result-replaces` and `result-recorded` the resident stack is the board block and the card, and nothing
else. The card keeps the turn status's other duties: it is where the save-failure retry presentation for
result confirmation is anchored, and it carries the player metadata `:340` permits.

**Cost.** `:266`'s "persistent" becomes "persistent while the game is playable". The element inventory in
`layout-constraints.md` §3 for `result-replaces` and `result-recorded` loses `turnStatus`. And a reviewer can
no longer point at one element and say "the status is always there" — they have to know the terminal case.
Worth 36.5 pt at L and 64 at AX3 on iPhone, 32 pt on macOS.

### M3 — the threefold-repetition notice is a system alert

This is the one that needs the product owner.

`:38` currently defines three custom glass surfaces, the third being "one shared slot for the natural-result
card and the threefold-repetition notice, which never coexist". This scheme takes the notice out of that slot
and presents it as a **system alert**, exactly like the accepted insufficient-memory notice (`:283`–`:285`),
with the same accepted copy and the same two actions:

> **局面已三次重复，可以和棋结束。**  ·  **继续对局**  ·  **以和棋结束**

An alert covers the scene, consumes no resident height, and leaves the state behind it unchanged.

**Why it is defensible.** The notice is a *decision*, not a *reading*: the player has just produced the third
repetition and has seen the position three times. Nothing about the decision requires the board to be legible
while the alert is up. **继续对局** returns the board untouched. **以和棋结束** ends the game and the result
card then presents the final board fully visible, which is the state the accepted visibility rule actually
protects. And the accepted retained claim (`:352`, carried by 判和 per the round-2-verified reading) means the
decision can be re-opened at any later moment with the board completely unobstructed — so the alert is not
the only chance to make it.

**Why it needs a decision.** The owner's clarification permits a **user-summoned** transient surface to cover
the board. This alert is transient but not summoned. Adopting M3 extends that clarification from
*user-summoned transient* to *transient*, i.e. to a surface the player did not ask for but can dismiss with
one tap. That is a real widening, and it is the only accepted boundary this scheme asks to move.

**What it is worth.** Everything. It is the binding state on the SE from AX1 upward. The ablation:

| variant | first Dynamic Type step at which the SE falls below `p = 44` |
|---|---|
| V0 — the constraint table's assumptions (inset 343, status + card, notice resident) | **AX2** |
| V1 — plus full-bleed chrome (M1) | AX2 |
| V2 — plus the card replacing the turn status (M2) | AX2 |
| **V3 — plus the notice as an alert (M3) = this scheme** | **AX4** |

M1 and M2 alone buy nothing, because the threefold notice is taller than everything they fix. M3 alone buys
nothing either — the card at 254 and the status at 64 fail on their own. **The three are only worth anything
together**, which is why three rounds of review found the cell infeasible: each round moved one of them.

At AX3 on the SE the four variants give `p` = 31.7 (V0, reproducing `layout-constraints.md` §6.1's figure
exactly), 32.9 (V1), 32.9 (V2), **47.71** (V3).

### M4 — the move list is a user-summoned sheet in the stacked arrangement

Not new: this was PR #23's decision, which round 2 verified as correct arithmetic and rejected only because
`:40` forbade a glass surface over the board block. **The owner's clarification now permits it.** The scheme
adopts it, extends it to replay, and states the affordance, which round 2's finding 2.5 said was missing:

> **The turn status is the affordance.** Selecting it opens the game sheet, which carries the move list, the
> game metadata, and the Help entry point. It costs no height, adds no fourth control to a cluster the
> contract caps at three, and it is the only element on the board page whose job is already "everything about
> the game that is not a fact about the position".

That also answers round-2's 4.6 (Help has no entry point once the navigation bar is gone) and its 2.3
(replay's move-list affordance). It creates one conflict to resolve: `:258`'s acknowledgment beat also lives
on the turn status, so the element both answers refused board input and accepts a tap of its own. That is
manageable — the beat answers input to the *board* — but it must be written down.

---

## 4. The two arrangements, in full

### 4.1 Stacked

Used by **every iPhone unconditionally**, by **every iPad in portrait**, by narrow or tall Mac windows, and
by any window failing either operand of the stage-2 predicate.

```
┌─────────────────────────────────────┐   contentW
│              turn status            │   full-bleed, capped at max(7p, usableW)
│                (12 pt)              │
│   ┌─────────────────────────────┐   │
│   │      numeral strip  t(p)    │   │   \
│   │                             │   │    │  board block, inset by the layout margin,
│   │      board core  7p × 7p    │   │    │  centred horizontally and vertically in
│   │                             │   │    │  whatever the chrome leaves
│   │      numeral strip  t(p)    │   │   /
│   └─────────────────────────────┘   │
│                (12 pt)              │
│   play controls  /  result card     │   full-bleed
└─────────────────────────────────────┘
```

Per state, the element below the board is:

| state | element below the board | element above |
|---|---|---|
| `play-AI`, `claim-retained` | 悔棋 · 判和 · 认输 | turn status |
| `play-Free` | 悔棋 · 判和 · 翻转棋盘 | turn status |
| `result-replaces` | result card: title, reason, 悔棋 · 结束对局 | — (M2) |
| `result-recorded` | result card: 已记录到历史, 回放 · 完成 | — (M2) |
| `replay-*` | transport (5) · 翻转棋盘 · 完成, plus the autoplay-speed control | replay status |
| `prestart-AI` | 本局设置 group + 开始对局 | — |
| `prestart-Free` | explanatory line + 开始对局 | — |
| *threefold* | unchanged — the alert covers the scene (M3) | unchanged |

Two things settled that previous rounds left open. **Replay carries 完成 in its own control row rather than a
navigation bar**, which closes round-2 finding 2.3 without the 54 pt an inline bar costs on iPhone; measured,
the seven-control transport is exactly the same height as the six-control one at all twelve text sizes on iOS
(65.5 at L, 81.5 at AX3) and on macOS (43), because the row already wraps into a grid, so the eighth control
is priced at zero and that assumption is flagged in §12. And **the autoplay speed control is in the
inventory**, closing round-2 finding 2.6; it is the 39 pt difference between `transport6` (65.5) and
`transportPlusSpeed` (104.5) at L.

Free Play's **翻转棋盘 survives the result card**, closing round-1 5.3 and round-2 4.2: the card replaces the
*game-action* controls (悔棋 · 判和 · 认输), and in Free Play the flip control is not a game action. Under M2
the card is where the turn status was, so the control row is free to keep 翻转棋盘 alone beneath it during the
result states. Measured cost on the SE at AX3: the card 206 + a control row 142 + 2 × 12 = **372** against a
budget of 564 − 308 = 256 — **that does not fit**. So the honest statement is: in Free Play the flip control
is *inside the result card* as a third action, or it lives in the game sheet. The scheme puts it in the card,
which keeps `:214`'s "at any time" true in every state and costs the card's width, not the layout's height —
the card's ideal width at L is a measured 193.5 with two actions, so a third fits inside 375 without wrapping
— **reasoned from the measured two-action card, not measured with three**; §12 records it.
### 4.2 Side by side

Used by **every iPad in landscape**, by ordinary Mac windows, and by the wide short windows the tiling
configurations produce.

```
┌───────────────────────────────────────────────────────┐
│  ┌───────────────────────┐  16  ┌──────────────────┐  │
│  │   numeral strip       │      │  turn status     │  │
│  │                       │      │  ────────────    │  │
│  │   board core 7p × 7p  │      │  move list       │  │
│  │                       │      │  (permanently    │  │
│  │   numeral strip       │      │   visible)       │  │
│  └───────────────────────┘      │  ────────────    │  │
│         centred vertically      │  metadata        │  │
│                                 │  controls        │  │
│                                 └──────────────────┘  │
└───────────────────────────────────────────────────────┘
   board = 7p, p from stage 3      panel = usableW − 16 − 7p, ≥ 320 (iOS) / 257 (macOS)
```

The panel's vertical budget is the board block's height, which is always at least 308 pt. Its contents wrap
rather than truncate, and if they exceed the panel's height the **panel** scrolls. The board never scrolls,
in either arrangement, at any size — that is what keeps "the final board remains fully visible" a checkable
statement.

In side by side the result card and the threefold decision both appear **in the panel**, in the slot the
control row occupies, so the board is untouched by either. There is no `result-alongside` state: the card
replaces the controls in the panel exactly as it does below the board in stacked. That removes
`layout-constraints.md`'s infeasible cell **I3** by construction and removes round-2's finding 4.3 (two 悔棋
controls in opposite states) — there is only ever one 悔棋 on screen.

Measured full-screen result, every supported iPad, default text:

| device | orientation | scene | container | usable W | content H | arrangement | `p` | board core | panel |
|---|---|---|---|---|---|---|---|---|---|
| mini 6 / A17 | P | 744 × 1133 | top tab bar | 704 | 1012 | stacked | 100.57 | 704 (width-bound) | — |
| mini 6 / A17 | L | 1133 × 744 | sidebar 280 | 813 | 687 | **side** | 68.14 | 477 | 320 |
| mini 5 | P | 768 × 1024 | top tab bar | 728 | 928 | stacked | 102.86 | 720 (cap) | — |
| mini 5 | L | 1024 × 768 | top tab bar | 984 | 672 | **side** | 88.86 | 622 | 346 |
| iPad 8 / 9 | P | 810 × 1080 | top tab bar | 770 | 984 | stacked | 102.86 | 720 (cap) | — |
| iPad 8 / 9 | L | 1080 × 810 | sidebar 280 | 760 | 778 | **side** | 60.57 | 424 | 320 |
| iPad 10 / A16 / Air 11″ | P | 820 × 1180 | top tab bar | 780 | 1059 | stacked | 102.86 | 720 (cap) | — |
| iPad 10 / A16 / Air 11″ | L | 1180 × 820 | sidebar 280 | 860 | 763 | **side** | 74.86 | 524 | 320 |
| Air 3 | P | 834 × 1112 | top tab bar | 794 | 1016 | stacked | 102.86 | 720 (cap) | — |
| Air 3 | L | 1112 × 834 | sidebar 280 | 792 | 802 | **side** | 65.14 | 456 | 320 |
| Pro 11″ 1st–4th | P | 834 × 1194 | top tab bar | 794 | 1073 | stacked | 102.86 | 720 (cap) | — |
| Pro 11″ 1st–4th | L | 1194 × 834 | sidebar 280 | 874 | 777 | **side** | 76.86 | 538 | 320 |
| Pro 11″ M4/M5 | P | 834 × 1210 | top tab bar | 794 | 1089 | stacked | 102.86 | 720 (cap) | — |
| Pro 11″ M4/M5 | L | 1210 × 834 | sidebar 280 | 890 | 777 | **side** | 79.14 | 554 | 320 |
| Pro 12.9″ / Air 13″ | P | 1024 × 1366 | top tab bar | 984 | 1245 | stacked | 102.86 | 720 (cap) | — |
| Pro 12.9″ / Air 13″ | L | 1366 × 1024 | sidebar 280 | 1046 | 967 | **side** | 101.43 | 710 | 320 |
| Pro 13″ M4/M5 | P | 1032 × 1376 | **sidebar 280** | 712 | 1319 | stacked | 101.71 | 712 (width-bound) | — |
| Pro 13″ M4/M5 | L | 1376 × 1032 | sidebar 280 | 1056 | 975 | **side** | 102.86 | 720 (cap) | 320 |

**Every iPad portrait stacks and every iPad landscape splits**, which is what `:477`–`:478` says and what the
product owner decided, and it comes out of a two-operand predicate rather than a table. The sentence
`layout-constraints.md` §7.3 shows reading C contradicting — "Side by side, used by iPad landscape" — is true
here on all nine classes.

`layout-constraints.md` §7.3 was right that the accepted rule is under-determined, and right that a scheme
must state a **priority order**. This one's is: **the board's floor and the panel's floor are reserved first,
against the scene; the arrangement follows from whether both fit side by side; the board then grows into
whatever that arrangement leaves.** The three readings A, B and C are all readings of "size the board, then
test the leftover", and all three are circular. This is not a fourth reading of that sentence; it replaces it.

---

## 5. Every transient surface, in each arrangement

The distinction that matters is **resident** (permanently on screen, may not intersect the board block) versus
**transient** (comes and goes, may cover the board under the owner's clarification).

| surface | kind | stacked | side by side | board height consumed |
|---|---|---|---|---|
| tab bar / top tab bar / sidebar | system, resident | measured 83 pt bottom (iPhone), 64 pt top (iPad 668–1024), 280 pt leading (≥ 1025) | same | already in `contentH` |
| turn status | custom, resident | above the board, full-bleed | in the panel | in `C(K,T)` |
| play-control cluster (glass) | custom, resident | below the board, full-bleed | in the panel | in `C(K,T)` |
| replay transport (glass) | custom, resident | below the board, full-bleed | in the panel | in `C(K,T)` |
| **result card** (glass) | custom, **resident, non-dismissible** | below the board, in the control row's place | in the panel, in the control row's place | in `C(K,T)` |
| game sheet — move list, metadata, Help | system sheet, **transient, user-summoned** | sheet from the bottom edge; **may cover the board block** | never presented — the list is resident in the panel | **0** |
| threefold decision | system alert, **transient** (M3) | centred over the scene | centred over the scene | **0** |
| insufficient-memory notice | system alert, transient | centred over the scene | centred over the scene | **0** (already established) |
| 开始新对局？ / 无法保存对局 / 删除这盘棋？ | system alerts, transient | centred over the scene | centred over the scene | **0** |
| save-failure capsule | transient, anchored | attached to the turn status, **above** the board block, never over it | attached to the turn status in the panel | 0 — it overlays the status |
| context menus, History swipe actions | system, transient | not on the board page | not on the board page | 0 |

**The invariant a reviewer measures:** at every instant, the union of every *resident* surface's frame is
disjoint from the board block. The only things that ever overlap the board block are the game sheet and the
system alerts, both transient, both dismissible with one action.

**Autoplay and the sheet.** Summoning the game sheet during replay **pauses** autoplay, for the same reason
`:363` pauses it on manual navigation: the highlight the user is watching lives in the list they just opened.
This closes round-2's nit 2.7.

---

## 6. May the board resize while a game is in progress?

**No, on a game-state event. Yes, on a geometry or text event.**

The scheme's envelope makes the first half automatic: `C(K,T)` is the maximum over every state the session can
reach, so entering any of them cannot change `p`. Concretely, on the iPhone SE at default text the envelope is
139 pt (the result card at 127 + one gap) rather than ordinary play's 127, and the board sits at `p = 49.0`
from the first move through the result card, the recorded card, the retained claim and the threefold alert.

Three reasons this is a requirement and not a preference:

1. **Every touch target is `p`-derived.** The disc is `0.80 p`, the marker band `0.42 p`–`0.50 p`, the check
   rings' surviving gap `0.015 p`. Resizing the board mid-game re-scales every one of them under the player's
   finger.
2. **The result card's own accepted rule would be delivered by a different board.** "When a natural terminal
   result is reached, the final board remains fully visible" (`:339`) is a statement about *the* final board —
   the one the last move was played on. A board that shrinks by 12 % at the instant the game ends satisfies
   the sentence and defeats it.
3. **The accepted transition budget forbids it.** `:416` gives Undo 250 ms for one ply and 600 ms for a
   decision cycle, and `:426` runs committing transitions to completion. A natural result can be undone
   (`:333`), so a board that shrank on the result and grew back on the Undo would animate a re-layout inside
   a committing transition, twice per Undo.

**What the board may do on a geometry event.** Rotate an iPad and the board resizes; that is the point of
supporting rotation. Resize a Mac window and it resizes continuously. Switch the sidebar for a tab bar — which
the HIG says is partly the user's choice — and 280 pt of width appears or disappears, the predicate is
re-evaluated, and an iPad mini in landscape moves between `p = 68.14` (sidebar: usable width 813, content
height 687, board core 477, panel 320) and `p = 82.14` (tab bar: usable width 1093, but content height 623
because the top tab bar costs 64 where the sidebar cost 0 — board core 575, panel 502). Both
are stable states; the transition between them uses the accepted 340 ms board-flip re-layout. That answers
`layout-constraints.md` §11's open question 8.

**One consequence to accept.** Because `C` is the envelope and not the current state, during ordinary play
there is unused height between the control row and the bottom of the content area — on the SE at AX3, 230 −
218 = 12 pt in the result state's favour, and at AX4 far more. The board is centred in it. The alternative —
sizing to the current state — buys at most 5.14 pt of pitch anywhere on iPad and 0.0 on iPhone (§2), and costs
board constancy. That is not a close trade.

---

## 7. Minimum size per platform

`layout-constraints.md` §2.6 measured that `UIWindowScene.sizeRestrictions` is **`nil` on iPhone**, so a
minimum cannot be declared there at all. The three platforms therefore say three different kinds of thing.

| platform | what is declared | value | what binds it |
|---|---|---|---|
| **iPhone** | nothing — no minimum can be declared | the **narrowest and shortest supported device**, iPhone SE (2nd and 3rd generation), **375 × 667 points** | verified, not declared |
| **iPadOS** | `UIWindowScene.sizeRestrictions.minimumSize`, a **scene** size containing 96–121 pt of system chrome | **375 × 656 points** | ordinary play at AX3: envelope 230 + board 308 = 538 of content, + 32 top + 83 bottom bar = **653**; +3 of slack |
| **macOS** | `NSWindow.contentMinSize`, a **content** size below the title bar and toolbar | **360 × 480 points** | stacked replay with the speed control: envelope 131 + board block 340 = **471**; +9 of slack |

### 7.1 Why the iPadOS width is 375 and not 360

This is the finding that decides the number. At **360 pt of scene width** the result card (ideal width 343.5
at AX3) does not wrap but Free Play's control row does, and the envelope at AX3 is **326 pt** rather than 230,
so the required scene height is **749** instead of 653. At 375 the card and both control rows sit on the right
side of every measured wrap threshold. 375 is also the narrowest supported iPhone width, which means the
narrow-window iPadOS case and the iPhone case are the *same* layout width and one verification covers both.

| candidate scene minimum | holds xS–AX3? | tiling cells permitted, of 126 |
|---|---|---|
| 360 × 584 | **no** — fails from AX1 | 72 |
| 360 × 642 (PR #23's, corrected for the 25 pt inset) | **no** — fails at AX3 | 66 |
| 360 × 749 | yes | 58 |
| **375 × 656** | **yes** (AX3 at `p = 44.4`) | **63** |
| 375 × 668 | yes, with 15 pt of slack (`p = 46.1` at AX3) | 63 |

### 7.2 What a declared minimum does and does not do

Round 1 finding 3.1 established that a declared minimum **bounds interactive resizing**; it is not a claim
about which multitasking configurations the system will offer, and the HIG is explicit that "apps don't
control multitasking configurations". `layout-constraints.md` §11 records that what iPadOS does when a user
picks a tile below the declared minimum is **unobserved**.

This scheme therefore does not use the minimum to exclude anything. It says instead:

> **The app supports every window the system offers.** Below the declared minimum — which the system may still
> produce, since tiling is not the app's to refuse — the board falls below its pitch floor rather than the
> layout breaking, exactly as it does above the declared Dynamic Type range. The contract names the
> configurations in which that happens.

That is the only statement that can be simultaneously true, honest, and compatible with
`testing.md:55` ("iPad adapts … including the system tiling configurations"), which three rounds of review
have found contradicted. §8.2 lists precisely which configurations degrade and by how much.

### 7.3 The macOS toolbar

Round-2 finding 3.7 was that the branch's 512 pt macOS minimum was broken by an `.expanded` toolbar on the
display the contract names as its worst case (499 < 512). At **480** it is not. Measured, on the 1024 × 663
display, every toolbar style holds:

| toolbar style | content height | arrangement | `p` | board core |
|---|---|---|---|---|
| none | 1024 × 550 | side by side | 72.00 | 504 |
| `.unifiedCompact` | 1024 × 542 | side by side | 70.86 | 496 |
| `.unified` / `.automatic` | 1024 × 516 | side by side | 67.14 | 470 |
| `.expanded` | 1024 × 499 | side by side | 64.71 | 453 |
| `.preference` | 1024 × 494 | side by side | 64.00 | 448 |

So the scheme **does not need to declare a toolbar style**, which is the first version of this design for
which that is true. It should still declare one for other reasons, but the layout no longer depends on it.

---

## 8. The proof: every cell

### 8.1 iPhone — ten classes × twelve Dynamic Type steps × three sessions

Maximum pitch. `!` marks a cell below the 44 pt floor. Content height = `H − topSafe − 83`, no navigation bar.

| screen | session | xS | S | M | L | xL | xxL | xxxL | AX1 | AX2 | AX3 | AX4 | AX5 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **375×667** | play-AI | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | **47.7** | 38.1! | 32.4! |
| | play-Free | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | **47.7** | 28.1! | 14.7! |
| | replay | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 48.6 | 38.0! |
| | prestart *(no floor)* | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 48.9 | 48.6 | 49.0 | 49.0 | 49.0 | 49.0 | 48.6 |
| 375×812 | play-AI | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 48.9 |
| | play-Free | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 49.0 | 44.6 | 31.1! |
| 390×844 | play-AI | 51.1 | … | … | 51.1 | … | … | 51.1 | 51.1 | 51.1 | 51.1 | 51.1 | 51.1 |
| | play-Free | 51.1 | … | … | 51.1 | … | … | 51.1 | 51.1 | 51.1 | 51.1 | 49.6 | 36.1! |
| 393×852 | play-AI / Free | 51.6 | … | … | 51.6 | … | … | 51.6 | 51.6 | 51.6 | 51.6 | 51.6 / 49.0 | 51.6 / 44.4 |
| 402×874 | all | 52.9 | … | … | 52.9 | … | … | 52.9 | 52.9 | 52.9 | 52.9 | 52.9 / 51.7 | 52.9 / 47.1 |
| 414×896 | all | 53.4 | … | … | 53.4 | … | … | 53.4 | 53.4 | 53.4 | 53.4 | 53.4 | 53.4 / 52.3 |
| 420×912 | all | 54.3 | … | … | 54.3 | … | … | 54.3 | 54.3 | 54.3 | 54.3 | 54.3 | 54.3 / 51.7 |
| 428×926 | all | 55.4 | … | … | 55.4 | … | … | 55.4 | 55.4 | 55.4 | 55.4 | 55.4 | 55.4 |
| 430×932 | all | 55.7 | … | … | 55.7 | … | … | 55.7 | 55.7 | 55.7 | 55.7 | 55.7 | 55.7 |
| 440×956 | all | 57.1 | … | … | 57.1 | … | … | 57.1 | 57.1 | 57.1 | 57.1 | 57.1 | 57.1 |

**Every supported iPhone holds `p ≥ 44` in every session at every Dynamic Type step from xS to AX3.**
Above the declared range: AX4 holds on nine of the ten classes and AX5 on six.

The tightest cell, worked in full — iPhone SE, human-versus-AI, AX3:

```
scene                                             375 × 667
top safe area (measured)                           20
tab container contribution (measured)              83
content height                                    564.0
usable width for the board  375 − 2 × 16           343.0

session envelope C(play-AI, AX3), all at 375 pt of layout width:
  play-AI            turn status 64.0 + controls 142.0 + 2 × 12   = 230.0   ← binding
  claim-retained     identical                                    = 230.0
  threefold-alert    identical (the alert is over the scene)      = 230.0
  result-replaces    card 206.0 + 12                              = 218.0
  result-recorded    card 206.0 + 12                              = 218.0
C(play-AI, AX3)                                                   = 230.0

board budget      564.0 − 230.0                                   = 334.0
strips hidden (AX3 is an accessibility size)  block(p) = 7p
p = min(334.0 / 7, 343.0 / 7, 720 / 7) = min(47.71, 49.00, 102.86) = 47.71
board core                                                        = 334.0
```

and the full SE column, at every step:

| size | envelope | board budget | strips | `p` | core | verdict |
|---|---|---|---|---|---|---|
| xS | 128.5 | 435.5 | shown | 49.00 | 343.0 | width-bound |
| S | 132.0 | 432.0 | shown | 49.00 | 343.0 | width-bound |
| M | 136.0 | 428.0 | shown | 49.00 | 343.0 | width-bound |
| L | 139.0 | 425.0 | shown | 49.00 | 343.0 | width-bound |
| xL | 146.5 | 417.5 | shown | 49.00 | 343.0 | width-bound |
| xxL | 154.0 | 410.0 | shown | 49.00 | 343.0 | width-bound |
| xxxL | 160.5 | 403.5 | shown | 49.00 | 343.0 | width-bound |
| AX1 | 187.0 | 377.0 | hidden | 49.00 | 343.0 | width-bound |
| AX2 | 205.0 | 359.0 | hidden | 49.00 | 343.0 | width-bound |
| **AX3** | **230.0** | **334.0** | hidden | **47.71** | 334.0 | height-bound, **+3.71 over the floor** |
| AX4 | 367.0 | 197.0 | hidden | 28.14 | 197.0 | **below the floor by 111.0** |
| AX5 | 461.0 | 103.0 | hidden | 14.71 | 103.0 | **below the floor by 205.0** |

### 8.2 iPad — all 126 tiling cells

Ordinary play (the `play-AI` envelope, which is the tallest of the play sessions at every size), gaps ignored
where the constraint table ignores them, using its measured chrome and the measured breakpoints.

| configuration | holds `p ≥ 44` at L | at AX3 | `layout-constraints.md` §8, for comparison |
|---|---|---|---|
| full screen | **18 / 18** | **18 / 18** | 18 / 18 |
| side half | **18 / 18** | **18 / 18** | 18 / 18 |
| vertical two-thirds | **18 / 18** | **18 / 18** | 18 / 18 |
| **top / bottom half** | **17 / 18** | **17 / 18** | 5 / 18 |
| **quadrant** | **9 / 18** | 3 / 18 | 5 / 18 |
| vertical third | 8 / 18 | 8 / 18 | 8 / 18 |
| **horizontal third** | **2 / 18** | **2 / 18** | **0 / 18** |
| **total** | **90 / 126** | **84 / 126** | ~72 / 126 |

The top/bottom half goes from 5 to 17 and the horizontal third from 0 to 2 for one reason: those are the
*widest and shortest* canvases in the whole inventory, and the stage-2 predicate puts a panel beside the board
there rather than stacking chrome above and below it. `layout-constraints.md` §8's "the horizontal third is
unconditionally impossible" was computed as a stacked composition; as a side-by-side one, the Pro 13″ in
portrait gives `p = 51.95` with 61.7 pt of height to spare, and the Pro 12.9″ gives `p = 47.76` once the strips
yield.

**The 36 failing cells at default text split cleanly into two kinds**, and the split is what a product
decision needs:

- **30 are board-driven and unfixable.** The content box is itself smaller than 308 pt in one axis, so a
  *bare* board block at the floor with zero chrome does not fit. 16 horizontal thirds, 10 vertical thirds,
  3 quadrants, 1 top/bottom half. No arrangement, no minimum, no chrome tightening changes them. The vertical
  third is the sharpest: the widest is 344 pt of scene width giving **304 pt of usable width against 308**.
- **6 are chrome-driven**, all landscape quadrants, listed in full because they are the only cells any further
  design work could recover:

  | device | configuration | usable W | content H | `p` | why it fails |
  |---|---|---|---|---|---|
  | mini 5 | portrait quadrant | 344.0 | 433.0 | 37.7 | width 344 < 644, so stacked; 433 − 139 = 294 < 308 |
  | Pro 12.9″ / Air 13″ | landscape quadrant | 643.0 | 391.0 | 32.0 | **643 < 644 by one point** |
  | Pro 11″ M4/M5 | landscape quadrant | 565.0 | 313.0 | 21.1 | below the threshold |
  | Pro 11″ 1st–4th | landscape quadrant | 557.0 | 313.0 | 21.1 | below the threshold |
  | Air 3 | landscape quadrant | 516.0 | 338.0 | 24.6 | below the threshold |
  | iPad 8 / 9 | landscape quadrant | 500.0 | 326.0 | 23.0 | below the threshold |

  The Pro 12.9″ row deserves a sentence: its landscape quadrant is 683 × 512, giving **643 pt of usable width
  against a 644 pt threshold**. One point. §11 prices the two ways to take it.

Full-screen and half-screen cells hold at every one of the twelve text sizes, not only the two shown; the
worst full-screen cell at AX5 is the mini 6 in landscape at `p = 68.14`, 55 % above the floor.

### 8.3 macOS

macOS has one text-size column (measured: it honours no Dynamic Type at all), so the whole platform is nine
rows.

| content rectangle | what it is | usable W | arrangement | `p` | board core | panel | verdict |
|---|---|---|---|---|---|---|---|
| 1024 × 550 | named worst-case display, no toolbar | 984 | side | 72.00 | 504.0 | 464.0 | ok |
| 1024 × 516 | same, `.unified` toolbar | 984 | side | 67.14 | 470.0 | 498.0 | ok |
| 1024 × 494 | same, `.preference` toolbar | 984 | side | 64.00 | 448.0 | 520.0 | ok |
| **820 × 550** | **round 2's oscillation counterexample** | 780 | **side** | **72.00** | **504.0** | **260.0** | **ok, single-valued** |
| 700 × 550 | round-2 1.4's "landscape stacks" case | 660 | side | 55.29 | 387.0 | 257.0 | ok |
| 621 × 512 | one point above the side-by-side threshold | 581 | side | 44.00 | 308.0 | 257.0 | ok, exactly at the floor |
| 620 × 512 | one point below it | 580 | stacked | 51.00 | 357.0 | — | ok |
| 550 × 700 | a portrait Mac window | 510 | stacked | 72.86 | 510.0 | — | ok |
| 360 × 480 | **the declared minimum**, worst session (replay + speed) | 320 | stacked | 45.29 | 317.0 | — | ok, +9 pt |

Two notes. The 621/620 pair is a **step, not an oscillation**: at 620 the layout is stacked and single-valued,
at 621 it is side by side and single-valued, and each remains so on every subsequent pass. The board is
*smaller* on the wider window (308 against 357) because at the threshold the panel takes its whole 257 pt
minimum. That is inherent to any hard threshold and §11 prices the smoothing.

### 8.4 The states, one by one

| state key (`layout-constraints.md` §3) | how this scheme handles it | worst cell |
|---|---|---|
| `play-AI` | resident: turn status + three controls | SE at AX3, `p` = 47.71 |
| `play-Free` | resident: turn status + three controls (翻转棋盘 third) | SE at AX3, `p` = 47.71 |
| `claim-retained` | identical to `play-AI`; 可判和 carried by 判和 | same |
| `result-replaces` | card replaces the *turn status* and the control row (M2) | SE at AX3, `p` = 49.0 |
| `result-recorded` | same slot, 回放 · 完成 | SE at AX3, `p` = 49.0 |
| `result-alongside` | **does not exist** — the card always replaces, never accompanies | — |
| `threefold-replaces` | **does not exist** — system alert (M3) | — |
| `threefold-alongside` | **does not exist** | — |
| `replay-transport` / `replay-t7` | resident: replay status + transport (+ 完成) | SE at AX3, `p` = 49.0 |
| `replay-speed` | resident: replay status + transport + speed control | SE at AX3, `p` = 49.0 |
| `replay-list1/3/5` | **do not exist in stacked** — the list is in the game sheet; in side by side it is resident in the panel, whose height is the board's | — |
| `prestart-AI` / `prestart-Free` | accepted preview exemption: no floor | SE at AX5, `p` = 48.6 |
| insufficient-memory notice | system alert over whichever state is behind it | 0 height |

Five of the fifteen states in the inventory cease to exist. Four of those five (`result-alongside`,
`threefold-replaces`, `threefold-alongside`, `replay-list3`) are exactly the states
`layout-constraints.md` §0 found infeasible. **The scheme does not make them fit; it removes them**, and §10
records what each removal costs in accepted text.

---

## 9. The oscillation proof

### 9.1 The structural argument

Let `L(S, T, K)` be the layout the scheme produces. Stage 2 computes

```
A(S) = [ usableW(S) ≥ 308 + 16 + panelMin ]  ∧  [ sceneW(S) ≥ sceneH(S) ]
```

`usableW(S)` is `contentW(S) − 2 × margin`, and `contentW(S)` is `sceneW` minus the system container's leading
inset, which is itself a function of `sceneW` alone (measured: 0 below 1025, 280 at and above). So **every
free variable of `A` is a component of `S` or a constant.** `A` does not read `p`, `C`, `T`, `K`, the game
state, or its own previous value.

Therefore:

1. **`A` is a total function of `S`.** For a given scene rectangle it has exactly one value, and re-evaluating
   it any number of times returns that value. Verified empirically: 4000 random scene rectangles, each
   evaluated three times, **0 non-deterministic results**.
2. **`p` cannot feed back.** `p` is computed in stage 3 from `A`'s output; there is no path from `p` to `A`.
   The dependency graph is acyclic, so there is no fixed point to iterate towards and no band in which two
   answers are both consistent.
3. **`A` is monotone in each operand.** Holding `sceneH` fixed, `A` is non-decreasing in `sceneW`; holding
   `sceneW` fixed, non-increasing in `sceneH`. So a live resize drag crosses each boundary at most once in
   each direction. Verified: sweeping macOS width from 560 to 900 at height 550 produces **exactly one
   arrangement change, at W = 621**. Sweeping the 2-D iPad grid (300–1400 × 240–1400 at 5 pt resolution,
   51 040 cells) produces 142 vertical transitions across 220 columns — at most one per column, which is the
   `sceneW ≥ sceneH` crossing, exactly as predicted.

### 9.2 The round-2 counterexample, run explicitly

Round-2 finding 1.1's worked failure was a macOS content rectangle of **820 × 550** with a 320 pt panel
minimum. Their rule cycled:

| their step | board budget | board core | width left | their verdict |
|---|---|---|---|---|
| evaluate with the stacked chrome (100) | 450 | 406.5 | 365.5 | ≥ 320 → side by side |
| now the status and controls are in the panel | 550 | 503.5 | 268.5 | < 320 → stacked |
| back in stacked | 450 | 406.5 | 365.5 | ≥ 320 → side by side … |

This scheme, same rectangle, macOS panel minimum 257:

| stage | quantity | value |
|---|---|---|
| 1 | scene / content rectangle | 820 × 550 |
| 1 | `usableW` = 820 − 2 × 20 | **780** |
| **2** | `usableW ≥ 308 + 16 + 257 = 581` ? | 780 ≥ 581 → **true** |
| **2** | `sceneW ≥ sceneH` ? | 820 ≥ 550 → **true** |
| **2** | **arrangement** | **side by side. Final. Not revisited.** |
| 3 | `C(play-AI, ·)` in side by side | **0** — status, controls, list and metadata are in the panel |
| 3 | `availH` = 550 − 0 | 550 |
| 3 | `availW` = 780 − 16 − 257 | 507 |
| 3 | `p` = max{ q : block(q) ≤ 550 ∧ 7q ≤ 507 ∧ 7q ≤ 720 } | **72.00** (height-bound; block(72) = 504 + 2 × 23 = 550) |
| 4 | board core | 504.0 |
| 4 | panel = 780 − 16 − 504 | **260.0** (≥ 257 ✓) |

**One pass. No re-entry.** The reason the cycle cannot start is that stage 2 never asks a question about the
board. Round 2's rule asked "is there width left *after the board*", which requires knowing the board, which
requires knowing the chrome, which requires knowing the arrangement. This rule asks "is this window wide
enough for a board at its floor and a panel at its floor", which is a question about the window.

For completeness, the neighbours: 819 × 550 → side, `p` = 72.00, panel 259.0. 821 × 550 → side, `p` = 72.00,
panel 261.0. The 97 pt band round 2 identified — W ∈ [775, 871] at C = 550 — is entirely inside the
side-by-side region here and contains no transition of any kind.

### 9.3 The one thing that is not proven

`A` depends on the system container's leading inset, which the HIG says is **partly the user's choice** on
iPad ("The app first launches with your choice of a sidebar or a tab bar, and then people can tap to switch
between them"). A user switching containers changes `sceneW`'s effective content width by 280 pt and can
therefore change the arrangement. That is a **user-initiated transition between two stable states**, not an
oscillation: each state is a fixed point of the layout function, and nothing the app does moves between them.
But the app must animate it, and §6 says how (the accepted 340 ms re-layout).

---

## 10. Against every accepted constraint

| accepted constraint | verdict | evidence |
|---|---|---|
| `p ≥ 44` on every interactive board | **Held** on every supported iPhone at xS–AX3, every iPad full screen / side half / two-thirds at every size, every macOS window from 360 × 480 up. **Broken** in 36 of 126 iPad tiling cells (30 unfixable by width), and above AX3 on the SE. | §8.1, §8.2, §8.3 |
| board core = 7p | **Held**, unchanged. | §1.2 stage 3 |
| board core capped at 720 pt | **Held**; the cap binds on eight of nine iPads in portrait and on the Pro 13″ in landscape. | §4.2 table |
| numeral strips 16 pt each at the floor, hidden at accessibility text sizes | **Held, and extended.** Stage 3b hides them additionally whenever they would push the board below the floor. **Amends `:157`** from a text-size rule to a room rule, keeping the contract's own rationale. Worth 5 tiling cells. | §1.2 stage 3b |
| the final board stays fully visible when the result card is shown, and may not be covered | **Held everywhere the floor is held.** The card is resident, in the control row's place, below the board in stacked and in the panel in side by side. It never overlaps the board block, at any size. | §5 |
| no glass surface may intersect the board block while **resident** | **Held.** The three custom surfaces (control cluster, replay transport, result card) are all below or beside the board block. The two things that overlap it — the game sheet and the system alerts — are transient. | §5 |
| a user-summoned transient surface may cover the board | **Used**, for the game sheet (move list, metadata, Help). | M4 |
| — the same, for a surface the user did **not** summon | **This scheme asks to extend it**, for the threefold alert. **The one accepted boundary it moves.** | M3 |
| chrome tightens before the board does; each platform declares a minimum below which neither may fall | **Held, and it is the scheme's spine.** In order, the chrome yields: the move list leaves (sheet), the threefold notice leaves (alert), the turn status leaves in the result states (M2), the chrome goes full-bleed to stop wrapping (M1), the strips yield (3b) — and only then does the board fall below the floor. iPhone declares nothing because it **cannot** (measured: `sizeRestrictions` is `nil`); it names a device instead. | §7 |
| iPad supports every orientation; iPhone is portrait only | **Held.** All 18 iPad device-orientations at full screen hold the floor at every text size. iPhone is portrait-only and, measured, is **never** side by side (widest usable width 400 against a 644 threshold). | §4.2, §8.1 |
| replay shows the move list, highlights the current move, allows jumping | **Held**, but by a sheet in stacked rather than residently. **Amends `:494`** ("replay in the stacked layout shows the move list rather than hiding it"). The accepted *requirement* at `:359` says nothing about residency. | M4 |
| three play controls, mode-dependent, as listed | **Held** in play. Replay carries the accepted five-control transport plus 翻转棋盘 plus 完成 plus the autoplay speed control — which is what `:358`, `:360` and `:363` jointly require, and which the previous two revisions were found short of. Measured, the 7-control row is the same height as the 6-control one at every text size. | §4.1 |
| Dynamic Type is a stated supported range | **Declared xS through AX3**, and held on every device at every one of those ten steps. AX4 and AX5 are outside the declared range and degrade continuously. | §8.1 |

### 10.1 What this scheme must break, and why nothing else does

Three things. Each is stated as a change to accepted text rather than assumed away.

**(a) The threefold notice stops being a resident custom surface** — `:38`'s "one shared slot for the
natural-result card and the threefold-repetition notice, which never coexist" becomes the result card's slot
alone. *Why nothing else works:* it is the tallest resident element on the tightest device from AX1 upward
(246 pt at AX3 on a 375 pt layout width, against a 256 pt total chrome budget). Keeping it resident makes the
SE fail from **AX2** regardless of every other move (§3, V0–V2). The alternatives are to drop the SE, cap the
range at AX1, or let the board fall below the floor during ordinary play — all three of which
`layout-constraints.md` §10 prices as worse.

**(b) The declared Dynamic Type range is xS–AX3, not xS–AX5.** *Why nothing else works:* at AX4 on the SE the
result card alone, at the full 375 pt scene width, is 285 pt against a 256 pt chrome budget. It is one
element, it is non-dismissible, and it may not cover the board. −29 pt with nothing else on screen and no gaps.
The only levers are the card's own copy and button layout — 29 pt is not obviously out of reach for a real
design, and §12 records that as the highest-value open measurement.

**(c) The 30 board-driven tiling cells fall below the floor.** *Why nothing else works:* a vertical third of
the widest supported iPad gives 304 pt of usable width against a 308 pt board core. A layout cannot
manufacture width. The scheme's answer is not to declare them unsupported — the app cannot refuse them — but
to say what happens: the board degrades continuously and the contract names the configurations.

Three accepted sentences additionally need amendment for consistency, all of them already identified by
round 2 and none of them a new decision: `:129` / `:503` / `:515` must scope the floor to the declared
text-size range and to windows at or above the declared minimum; `:157` becomes a room rule; `:494` allows the
replay move list to be summoned.

---

## 11. Options this scheme did not take, priced

| option | what it buys | what it costs | verdict |
|---|---|---|---|
| **Panel minimum 280 instead of 320** (metadata truncates) | +1 tiling cell at L, +1 at AX3, and 5–7 pt more pitch in every iPad landscape (mini 6 L: 68.14 → 73.90) | the terminal metadata line truncates — the very line `layout-constraints.md` §7.1 identifies as the panel's driver | **not taken**; recorded because it is a one-line change and the owner may prefer it |
| **A third, compact side-by-side arrangement** for wide short windows (panel 176–260) | the 6 chrome-driven landscape quadrants at L, 12 at AX3 | a second threshold, a third arrangement against `:475`'s "Two arrangements cover every device and window size", and a panel too narrow for the control row's measured 278 pt ideal | **not taken** |
| **Lower the side-by-side threshold by 1 pt** (643) | the Pro 12.9″ landscape quadrant, which misses by one point | an arbitrary constant with no derivation | **not taken** — but the one-point miss should be recorded so nobody re-derives 644 as 643 by accident |
| **Smooth the 620/621 macOS step** by raising the threshold until the side-by-side board is no smaller than the stacked one | no board shrinking as the window grows | the test becomes height- and text-size-dependent (still acyclic, still no oscillation, but three operands instead of two), and it makes iPad landscape **stacked** on the mini 6, iPad 8/9 and Air 3 — contradicting `:478` | **not taken**; computed and rejected |
| **A 16 pt compact layout margin below 375 pt of window width on iPad** | 2 vertical-third cells (Pro 13″, Pro 12.9″ in portrait), which miss by 4 and 7 pt | nothing in the contract; but iPad `layoutMargins` were measured at **20 at every width measured**, all of them full-screen, so this is an unmeasured guess | **not taken** — §12 records the measurement that would settle it |
| **Declare 375 × 668 rather than 375 × 656** as the iPadOS scene minimum | 12 pt of slack instead of 3 at the binding AX3 case | nothing measurable — 63 tiling cells either way | **worth taking** if the 12 pt gap assumption is not itself fixed in the contract |
| Keep a navigation bar on the board page | a conventional Back and Help affordance | 54 pt on iPhone, which costs AX3 outright (`p` = 42.4 on the SE) | **not taken**; the turn status carries the sheet and 完成 sits in the replay row |

---

## 12. What is still open, and what would close it

Carried forward from `layout-constraints.md` §11 where it still binds, plus what this scheme adds.

1. **The result card's height at AX4 on a 375 pt layout width is 285 pt against a 256 pt budget.** This is the
   single number standing between the scheme and an AX5 commitment on the SE. Closing it means measuring a
   *real* card — the reconstruction here is standard SwiftUI controls carrying the accepted copy — and, if it
   is still short, deciding whether 29 pt of card can be designed away. **Highest-value open item.**
2. **iPad chrome in a window narrower than 668 pt is still unmeasured.** The scheme uses 32 + 83 = 115 (the
   iPhone-measured bottom bar, conservative). If it is 32 + 72 = 104, the declared scene minimum drops from
   375 × 656 to 375 × 645 and two more tiling cells become permitted. Closing it needs a person dragging
   window controls in Simulator or on a device.
3. **iPad `layoutMargins` in a compact-width window.** Measured 20 at every width tested; every test was full
   screen. If it is 16 below 375 pt, two vertical-third cells recover.
4. **The 7-control replay row is priced at the 6-control row's height** because `transport6` and `transport7`
   measure identically at all twelve text sizes on both platforms. An 8-control row (adding 完成) is
   **reasoned, not measured**. It is a two-line addition to `probe8.swift`.
5. **The 12 pt inter-element gap and the count of gaps per state are still assumptions** carried from
   `layout-constraints.md` §11.5. The SE's AX3 result has 3.71 pt of pitch — 26 pt of height — of headroom, so
   raising the gap to 16 pt costs 8 pt and survives; raising it to 24 costs 24 and does not.
6. **The turn status becomes tappable** (M4). Its interaction with the accepted acknowledgment beat (`:258`)
   needs designing, and VoiceOver needs an explicit action rather than a tap on a status element.
7. **Every iOS number is from iOS 27.0, not the 26.5 the product targets.** Unchanged from
   `layout-constraints.md`.
8. **Five iPads cannot be booted on this toolchain**; their insets are transferred within a stated class.
   Unchanged.
9. **The element heights remain reconstructions** and are a floor for what the real design costs. Every "ok"
   above is therefore optimistic and every "below the floor" is conservative — the same caveat
   `layout-constraints.md` §11.4 records, and it applies to this note in exactly the same way.

---

## Appendix — reproducing this

```
cd discussion-drafts
python3 bf2.py A     # iPad full screen: arrangement, pitch, panel, per text size
python3 bf2.py B     # all 126 tiling cells, with the failure classification
python3 bf2.py C     # macOS, including the 820 x 550 counterexample and the sweep
python3 bf2.py D     # ten iPhone classes x twelve text sizes x four sessions
python3 bf2.py E     # iPadOS scene-minimum candidates
```

`bf-solve.py` holds the loaders, the accepted board formulas, the device inventory and the measured chrome
model; `bf2.py` adds the scheme's arrangement predicate, the strips-yield rule and the reports. Both read only
`layout-probe/out8-se3-P.txt` and `layout-probe/out-mac2.txt`, which are the existing measured probe outputs;
neither runs a simulator and neither writes outside `discussion-drafts/`.
