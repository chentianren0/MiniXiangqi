# Numeric audit of the accepted contract set

Workspace-only research evidence. Not part of any repository, not a contract, and authorises nothing.

Scope: every number, ratio, duration and dimension in the eight documents in `MiniXiangqi/docs/`,
plus `MiniXiangqi/fixtures/rules/` and its README, at merge `60fc044` (PR #25), which is the state
after the five design pull requests of 2026-07-27/28 (#19 board visual system, #20 core/Settings/
structure, #21 engine packaging, #22 rules interpretations, #24 board frame, motion and Liquid Glass).

Throughout, **executed** means I ran it, **cited** means I read it in a named source, and
**reasoned** means neither.

---

## 0. Method and what was executed

Executed:

- Replayed all 16 fixtures through `pyffish` built from the `fs-chase` fork worktree
  (`sf.version() == (0, 0, 89)`), asserting move-by-move legality, the exact `result_fen`
  (including the halfmove and fullmove fields), each `legal_moves` set, each `rejected_moves`
  entry, each `applied` probe, `in_check`, and the occurrence count of the final position and of
  the `boundary.prefix_len` prefix.
- Read the fork's variant definitions (`fs-chase/src/variant.cpp`, `variant.h`) for the
  minixiangqi palace regions, `stalemateValue`, `flyingGeneral`, `perpetualCheckIllegal`,
  `nMoveRule`, `nFoldRule`, `soldierPromotionRank` and `chasingRule` defaults.
- Hashed and sized the pinned NNUE at
  `MiniXiangqi/.git/minixiangqi-control/nnue/minixiangqi-12c45d5da817.nnue`.
- Recomputed every derived figure in `interaction-design.md` (board metrics, marker geometry,
  motion timings, layout budget, WCAG luminance bands) in Python.

Cited:

- Apple *Human Interface Guidelines*, **Accessibility → Mobility**, "Offer sufficiently sized
  controls" table: iOS/iPadOS default control size **44x44 pt**, minimum **28x28 pt**; macOS
  default **28x28 pt**, minimum **20x20 pt**. Retrieved via `DocumentationSearch` on the pinned
  toolchain, 2026-07-28.
- Apple *HIG*, **Windows → macOS window anatomy** and **Toolbars → macOS**: these describe the
  window frame and toolbar but publish **no** numeric title-bar height. Searched; not found. This
  matters for one figure below, and "not found" is the honest answer rather than a guess.

---

## 1. Derivations that hold — stated so the values can be disagreed with exactly

These are recomputed and correct. Listing them is the other half of the audit: a reviewer should
know which numbers survived.

| Claim | Location | Recomputed | Verdict |
|---|---|---|---|
| Board core `7 p` = 308 pt at `p = 44` | interaction-design:134 | 6 cells + 2 × 0.5 p = 7 p; 7 × 44 = 308 | exact |
| Disc Ø `0.80 p` = 35.2 pt | :135 | 35.2 | exact |
| Symbol `0.50 p` = 22 pt | :136 | 22 | exact |
| Marker band `0.42 p`–`0.50 p` = 18.5–22 pt | :137 | 18.48–22.0 | exact to the stated precision |
| Grid `0.026 p` = 1.14 pt at floor; ceiling from "about 62 pt" | :147 | 1.144; 1.60/0.026 = 61.54 | exact |
| Numeral `0.32 p` → 14 pt at floor | :153 | 14.08 → 14 | exact |
| Strip `0.08 p + 0.887 s` → 16 pt; block 308 × 340 | :154 | 3.52 + 12.418 = 15.938 → 16; 308 + 2×16 = 340 | exact |
| Hiding the strips returns 32 pt | :157 | 2 × 16 | exact |
| Capture ring: 12 dashes of 18° with 12° gaps | :246 | 12 × 30° = 360° | exact |
| Capture ring inner edge (0.50 − 0.055) | :246 | 0.4725 centre-line, inner edge 0.445 ≥ 0.42 | clears |
| Strengthened capture ring, 0.07 p inward from 0.50 | :251 | inner edge 0.430 ≥ 0.42 | clears, by 0.01 p |
| Last-move bracket clears a capture ring on its own cell | :247 | nearest approach of the arm to the point centre = √(0.32²+0.45²) − 0.0225 = 0.530 p > 0.50 p | clears |
| Adjacent cells' brackets stay separate | :247 | 2 × 0.05 − 2 × 0.0225 = 0.055 p clear | holds |
| Focus ring band 0.44–0.48 p | :253 | 0.92/2 ∓ 0.04/2 | exact |
| Drag hysteresis cannot double-strengthen | :251 | needs d_A + d_B ≤ 1.0 against a ≥ 1.0 point spacing | holds (equality only on the connecting segment) |
| Move travel = √distance remapped onto 180–240 | :420 | 180.0, **197.15**, 200.50, 210.30, **221.39**, 231.17, 240.0; every value rounds to the stated one at 5 ms granularity, max deviation 2.15 ms | holds |
| The seven distances a 7×7 board admits | :420 | {1, 2, √5, 3, 4, 5, 6} — the horse's leap is the only non-integer, since Xiangqi has no diagonal slide | exactly seven |
| Board flip 340 ms from corner travel and the move-travel velocity ceiling | :422 | 6√2 = 8.4853 cells ÷ (6 cells / 240 ms) = **339.41 ms** | derived, not chosen — the strongest derivation in the document |
| macOS budget 550 − 308 = "more than 200 points" | :482 | 242 pt, of which the strips take 32, leaving 210 | holds |
| 44 pt floor is iOS/iPadOS default control size; macOS's is smaller | :480 | HIG: iOS 44x44 default, macOS 28x28 default | **cited and correct** |
| Starting position gives exactly 19 legal moves | xiangqi-rules:96, mx-move-001 | **executed**: engine returns exactly the 19 asserted moves; 9 soldier + 10 cannon slides; chariots, horses and king have none | exact |
| Red fill band in 现代 is "narrow" | interaction-design:100 | white symbol at 4.5:1 caps L at 0.1833; fills differing 3:1 with black at 0 floors L at 0.1000 — a band of grey-equivalent **#59 to #77** | correct, and now exact |
| "the Red must be somewhat lighter than the deep red of a physical set" | :100 | #8B0000 has L = 0.0555, below the 0.1000 floor → excluded; #B22222 (L = 0.1072) and #C0392B (L = 0.1431) are inside | correct |
| Black fill "very dark" | :100 | L ≤ 0.0278 when Red sits at its lightest — grey-equivalent #2E; L ≤ 0 (pure black) when Red sits at its darkest | correct |
| Pinned network 4,333,499 bytes, SHA-256 `12c45d…09ce` | engine-integration:149 | **executed**: byte length and SHA-256 both match the file on disk exactly | exact |
| Filename prefix `minixiangqiaxf-12c45d5da817` | :134 | first 12 hex of the recorded SHA-256 | exact |
| `nMoveRule = 0` must be set **explicitly** | xiangqi-rules:58 | **executed**: `variant.h:124` default is `nMoveRule = 50`, and `minixiangqi_variant()` does not override it | correct and necessary |
| `nFoldRule = 3` | engine-integration:124 | `variant.h:125` default is already 3 | correct (redundant, harmless) |
| Built-in `minixiangqi` "has no chasing rule" | engine-integration:128 | `variant.h:130` default `NO_CHASING`; only `xiangqi_variant()` sets `AXF_CHASING` | correct |
| Palace `c1`–`e3` / `c5`–`e7` | xiangqi-rules:35 | `mobilityRegion` = ranks 1–3 × files C–E and ranks 5–7 × files C–E | byte-for-byte correct |
| "a soldier move does not reset" the halfmove field | xiangqi-rules:37 | **executed**: mx-chs-003 has four black soldier moves and reaches halfmove 8; `nMoveRuleTypes` is `PAWN`, and Mini Xiangqi soldiers are `SOLDIER` | correct |
| Sixteen fixtures | xiangqi-rules:94 | counted: 6 move + 3 end + 1 rep + 2 chk + 4 chs = 16, and 16 files exist | exact |
| "Six groups, 53 functions" | core-interface:18 | counted: 5 + 4 + 20 + 9 + 4 + 11 = 53 across six headings | exact |
| Seven persistent preferences; "four are presentation or device capability"; "the two that affect a game" | game-data:151,153 | 7 = 2 + 1 + 4 | exact |
| Three draw reasons | game-data:51 | `threefold-repetition`, `mutual-perpetual-check`, `mutual-perpetual-chase` (stalemate is a loss here) | exact |
| Import limits are mutually non-vacuous | game-data:62 | 10,000 plies ≈ 68 KiB of JSON, so the ply limit binds well inside 1 MiB; both limits do work | consistent |
| `^[a-g][1-7][a-g][1-7]$` | core-interface:206 | matches a 7×7 board exactly | exact |
| 4 GiB Hash cap = 4096 MiB; 256 MiB floor is reachable | engine-integration:103–107 | the floor first becomes satisfiable at `available` = 384 MiB (the 128 MiB reserve branch); the 20% branch takes over above 640 MiB | consistent, no dead zone |
| SQLite floor 3.37.0 for `STRICT` | game-data:146 | `STRICT` tables were introduced in 3.37.0 | correct |

**The fixture set is numerically clean.** All 16 replay legally; all 16 `result_fen` strings match
the engine byte for byte including the fifth and sixth FEN fields; all six asserted `legal_moves`
sets match exactly (0, 0, 7, 19, 12, 15, 6, 3, 3 moves); every `rejected_moves` entry is in fact
illegal; all three `applied` probes match; all 16 `in_check` values match; every
repetition fixture's final position is its **third** occurrence and every `boundary.prefix_len`
prefix is its **second**. I found no numeric defect anywhere in `fixtures/rules/`.

---

## 2. Findings

Ordered most severe first. Each gives the disagreeing places quoted, which one I believe, the
severity, and the exact correction.

---

### F1 — "under half a second" is contradicted by the accepted 600 ms Undo ceiling

**Severity: contradiction.**

`interaction-design.md:416`:

> "an Undo transition must therefore complete within **250 ms for one ply and 600 ms for a decision
> cycle**"

`interaction-design.md:426`:

> "A *committing* transition — a move, a capture, **an Undo** — runs to completion, and input
> arriving during it is **discarded rather than queued** … **The accepted durations bound that wait
> to under half a second.**"

600 ms is not under half a second. The two sentences are ten lines apart in the same section, and
the second explicitly names an Undo as a committing transition, so there is no reading under which
the bound holds. The maximum committing-transition duration the contract accepts is: move ≤ 240 ms,
capture ≈ 250 ms, one-ply Undo ≤ 250 ms, **decision-cycle Undo ≤ 600 ms**.

This is load-bearing rather than rhetorical: the sentence is the justification for discarding input
rather than queueing it. A player who taps during a decision-cycle Undo can have input silently
dropped for 600 ms, which is 20% longer than the figure the contract offers as the reason that is
acceptable.

**Which is right:** 416. The 600 ms ceiling is derived (it is what two 240 ms plies plus overhead
must fit inside); "under half a second" is a summary written against the older text, which is
visible in the history — commit `adde759` rewrote the Undo sentence but left the interruption
paragraph untouched.

**Correction:** in `interaction-design.md:426` replace

> "The accepted durations bound that wait to under half a second."

with

> "The accepted durations bound that wait to 600 ms, and to 250 ms for anything but a
> decision-cycle Undo."

---

### F2 — The `0.08 p` numeral clear space is measured from the wrong edge, by exactly the quantity the same sentence says it protects

**Severity: contradiction.**

`interaction-design.md:151`:

> "**The file numerals** occupy a strip above and below the board core, **outside the half-cell
> margin**"

`interaction-design.md:154`:

> "Strip height is `0.08 p + 0.887 s` … The `0.08 p` term is clear space **between the board's outer
> line and the tallest numeral**, so no numeral ever encroaches on the half-cell margin the
> outermost points' markers occupy."

The board's outer line runs through the outermost points. The board core extends `0.50 p` beyond it
(the half-cell margin), and the strip begins there. So the clear space between the outer line and
the nearest numeral is `0.50 p + 0.08 p = 0.58 p` — **25.5 pt at the floor**, not `0.08 p` = 3.5 pt.

The bullet is self-refuting: if `0.08 p` really were measured from the outer line, the numerals
would sit at 3.5 pt from it and would therefore be *inside* the half-cell margin, which is exactly
what the second half of the same sentence says can never happen.

The board-block arithmetic settles it independently. 308 × 340 requires each 16 pt strip to lie
**entirely outside** the 308 pt core, and the core already includes the margin (`:134`, `:38`).

**Which is right:** the geometry — the `0.08 p` is measured from the board core's edge.

**Correction:** in `interaction-design.md:154` replace "between the board's outer line and the
tallest numeral" with "between the **board core's edge** and the tallest numeral — `0.58 p`, or
25.5 points at the floor, from the outer grid line".

---

### F3 — 现代 cannot be "valid on a dark board as well as a light one"; the two readings of its boundary give disjoint board ranges

**Severity: contradiction.** This one is settled by computation, not by taste.

`interaction-design.md:97` (a requirement):

> "**The disc's boundary — its ring or edge stroke — reaches at least 3:1 against the style's own
> board surface**, measured against that base surface rather than against a grid line, and at a
> point away from any board marking."

`interaction-design.md:83` (现代's construction):

> "each disc is filled with a single strong colour, Red or Black, **with a white ring inset within
> the disc** and the symbol in white."

`interaction-design.md:100` (the conclusion drawn):

> "Because the style's **white inset ring, not its fill, is what separates the piece from the
> board**, the style stays valid on a **dark board as well as a light one**."

An *inset* ring is by construction not at the disc's boundary and is not adjacent to the board, so
it cannot be what the `:97` requirement measures. Take either reading and compute:

- **Boundary = the fill's edge** (the geometrically correct reading). The white symbol caps the fill
  at relative luminance 0.1833; 3:1 against the board then requires board
  L ≥ 3(L_fill + 0.05) − 0.05, i.e. **L ≥ 0.400 at the darkest permitted fill and L ≥ 0.650 at the
  lightest** — grey equivalents **#AA to #D3**. 现代 needs a *light* board and cannot have a dark one.
- **Boundary = the white inset ring** (the reading `:100` asserts). White against the board at 3:1
  requires board **L ≤ 0.300** — grey equivalent **#95 or darker**. 现代 needs a *darkish* board and
  cannot have a light one.

The two admissible ranges — L ≥ 0.400 and L ≤ 0.300 — **do not overlap**. Under neither reading is
the style valid in both directions, which is what `:100` claims. The claim is not merely unproven;
it is false under each of its own readings.

**Which is right:** `:97` and `:83`, which are the requirement and the construction. `:100` is
commentary drawn from them and is the sentence that is wrong.

**Correction:** replace the final clause of `interaction-design.md:100` with a statement of the
implied bound, for example:

> "Because the inset ring sits inside the disc, what the boundary rule measures is 现代's fill against
> its board surface. With the fill capped at relative luminance 0.183 by the white symbol, that
> forces the style's board surface to relative luminance **0.40 or lighter-still**, so 现代 is a
> light-board style. A dark-board variant would have to move the ring to the disc's edge, which is
> a different style."

This also gives `testing.md:156` ("Measure each style's three contrast requirements") something a
tester can actually measure — at present a tester measuring 现代's "disc boundary" does not know
which stroke to put the probe on.

---

### F4 — The `0.02 p` air gap does not exist at the size the same sentence says to measure at, and "the disc at its largest" is the wrong disc

**Severity: contradiction.**

`interaction-design.md:141`:

> "A piece style's own rings and edge strokes live at or inside `0.40 p`. On an occupied point, no
> game-state marker's ink falls inside `0.42 p` and none touches the disc face, **measured against
> the disc at its largest — a selected disc is scaled, and the rule holds at that size too**. The
> `0.02 p` air gap this leaves is what keeps a marker legible against 传统's heavier Black ring…"

Two arithmetic problems in one sentence:

1. The selected disc is scaled ×1.05 (`:244`), so its decoration reaches 0.40 × 1.05 = **0.4200 p**
   — exactly the marker floor. The air gap at that size is **0.000 p**, not `0.02 p`. The `0.02 p`
   figure is the at-rest value only.
2. "the disc at its largest" is not the selected disc. The **dragged** disc is ×1.10 (`:251`) →
   radius **0.4400 p**, which is 0.02 p *past* the marker floor. The parenthetical names ×1.05 as
   the largest case and is wrong by construction; the dragged case is saved only by the separate
   exemption at `:142` ("A dragged piece is the one exception"), which this sentence does not
   invoke.

In practice nothing breaks — the only marker that shares a point with a ×1.05 disc is the selection
ring, whose inner edge at lift is 0.44625 p, leaving 0.02625 p of real air — but the stated
derivation does not produce the stated number, and `testing.md:178` sends a tester to measure
"against the disc at its largest", where they will find zero clearance and no dragged-disc
exemption in the sentence they were given.

**Correction:** in `interaction-design.md:141` replace the clause with

> "…measured against a disc on a point at its largest, which is the ×1.05 selection lift; a dragged
> disc reaches `0.44 p` at ×1.10 but has detached from the grid and is exempt under the next rule.
> The `0.02 p` air gap this leaves **at rest** closes to zero under the selection lift, and what
> keeps a marker clear there is the selection ring's own inner edge at `0.44625 p`."

Mirror the same wording into `testing.md:178`.

---

### F5 — The check pulse's stated peak is unreachable at the stated centre-line radii

**Severity: contradiction (arithmetic), resolvable only by adding one number.**

`interaction-design.md:248`:

> "two concentric solid rings of stroke `0.025 p` at **centre-line radii `0.4325 p` and `0.4875 p`**
> … the pulse **thickens each ring to at most `0.0325 p` growing only into the gap between them**,
> so neither `0.42 p` nor `0.50 p` is crossed and at least `0.015 p` of gap survives."

At rest the bands are 0.42000–0.44500 and 0.47500–0.50000: both structural limits are touched
exactly, which is what the text says. But "thickens a ring" at a *fixed centre-line* is symmetric,
and symmetric growth to 0.0325 p gives:

| | inner ring | outer ring |
|---|---|---|
| peak at fixed centre-line | 0.41625 – 0.44875 | 0.47125 – 0.50375 |

which crosses **both** `0.42 p` and `0.50 p` — precisely what the sentence promises cannot happen.

The construction that does satisfy every stated consequence is **edge-anchored** growth: the inner
ring grows outward from a pinned 0.42000 and the outer ring grows inward from a pinned 0.50000,
which moves their centre-lines to **0.43625 p** and **0.48375 p** and leaves a surviving gap of
**exactly 0.01500 p** — reproducing the document's own "at least `0.015 p`" figure to five places.
That the document's stated consequence is recoverable only from this construction is strong evidence
it is what was intended; the contract simply never states the peak centre-lines, and "thickens"
implies the wrong one.

**Correction:** in `interaction-design.md:248`, after the rest radii, add:

> "The pulse is edge-anchored rather than centred: at its peak the inner ring runs `0.42000 p` to
> `0.45250 p` (centre-line `0.43625 p`) and the outer ring `0.46750 p` to `0.50000 p` (centre-line
> `0.48375 p`), leaving exactly `0.015 p` of gap."

And in `testing.md:179` replace "growing only into the gap between them" with "each ring's outer
limit (`0.42 p` inner, `0.50 p` outer) pinned, so the centre-lines move to `0.43625 p` and
`0.48375 p` at the peak".

---

### F6 — The 500 ms AI-activity threshold guarantees no minimum indicator duration, and is anchored on a different clock from the 260 ms floor

**Severity: gap (two of them, in one sentence).**

`interaction-design.md:424`:

> "Its piece departs at the later of two instants: when the search returns, and **260 ms after the
> player's own move has finished animating**, including the captured piece's removal where there is
> one … If the search has not returned **within 500 ms of the player's move**, the turn status shows
> AI activity; below that threshold nothing appears, **because an indicator that flashes for a fifth
> of a second is noise**."

**(a) The threshold delivers nothing it is asked for.** The AI's piece departs at
max(search_return, floor). For any search returning at t just past the threshold T, the indicator is
visible for max(t, floor) − T, whose infimum over t ≥ T is max(0, floor − T). With T = 500 ms and a
floor of 440 ms after the tap for a one-step move (180 ms travel + 260 ms), floor − T is **negative**:
a search returning at 501 ms produces an indicator visible for **1 ms**. The rule is written to
prevent a 200 ms flash and instead admits an arbitrarily short one.

To actually guarantee the "fifth of a second" the sentence appeals to, the threshold would have to
sit **60 ms after the player's move arrives** (260 − 200), not 500 ms after it — or, keeping 500 ms,
the indicator needs a minimum on-screen duration, which no document states.

**(b) Two clocks.** The floor is measured from the move's **arrival**; the threshold from "the
player's move", which elsewhere in this document means the committing input. They differ by the
travel duration, 180–240 ms, and by up to ~250 ms after a capture. Commit `adde759` deliberately
re-anchored the floor onto the arrival ("The compose beat was anchored on the move committing …
It now anchors on the arrival") and did not re-anchor the threshold in the same sentence.

Worked consequence of (b): a 6-cell capture (≈250 ms) followed by an instant search gives an
earliest AI departure of 250 + 260 = **510 ms after the tap**, while the indicator is scheduled for
**500 ms after the tap** — a 10 ms flash on the very move the compose beat exists to make feel
deliberate.

**Correction:** state the anchor and add a minimum. Suggested:

> "If the search has not returned within **500 ms of the player's move arriving**, the turn status
> shows AI activity, and once shown it remains for at least **200 ms** even if the search returns
> immediately after."

`testing.md:169` should then read "…AI activity appears only once the search passes the accepted
threshold measured from the player's move arriving, and, once shown, is never visible for less than
its accepted minimum."

---

### F7 — The 44 pt pitch floor does not, by itself, guarantee a 44 pt touch target

**Severity: gap.**

`interaction-design.md:480`:

> "Within that, **a point of the grid is never smaller than 44 points** on every platform. On iOS
> and iPadOS that is the platform's default control size."

The cited HIG figure (Accessibility → Mobility) is a **control size** — the tappable area. What the
contract actually fixes at 44 pt is the **cell pitch**. The thing drawn at a point is the disc,
Ø `0.80 p` = **35.2 pt** at the floor (`:135`), which is below the 44 pt default (though above the
28 pt minimum). No document anywhere states that a point's hit region is the full `1 p × 1 p` cell.

Nothing in the metrics is wrong; what is missing is one sentence, without which the whole
justification for the 44 pt floor does not connect to anything a user touches. `testing.md:58`
inherits the gap: it verifies "a grid point stays at or above 44 points", i.e. the pitch, and never
the target.

**Correction:** add to `interaction-design.md` Board metrics:

> "A point's hit region is its full `1 p × 1 p` cell, not its disc, so the 44 pt pitch floor is a
> 44 × 44 pt target on every platform even though the disc it contains is 35.2 pt."

and change `testing.md:58` to "Verify the cell pitch stays at or above 44 points and that a point's
hit region is the whole cell."

---

### F8 — The drag's drop region is unstated, and cannot equal its strengthening region; 36% of every cell has no strengthened target

**Severity: gap.**

`interaction-design.md:251`:

> "While the drag is **within `0.45 p`** of a legal point, that point strengthens … Strengthening
> **releases beyond `0.55 p`**"

`interaction-design.md:231`:

> "Dropping on a legal destination commits the move; dropping elsewhere returns the piece to its
> origin."

"Dropping on a legal destination" is never given a radius. If the drop region is the point's cell
(the natural reading, and the one F7 needs), then a drop can commit from up to `0.707 p` from the
point at a cell corner, while strengthening reaches only `0.45 p`. The area of a `1 p` cell within
`0.45 p` of its point is π(0.45)² = **0.6362 p²**, so **36.4% of every cell can commit a move that
was never previewed as strengthened** — and, symmetrically, an invalid drop can look identical to a
valid one right up to the release.

**Correction:** state the drop region explicitly and reconcile it with the feedback radii. The
cheapest fix that keeps both consistent is:

> "A drop commits to the point whose cell contains the release position, and only while that point
> is strengthened; releasing over a cell whose point is not strengthened returns the piece to its
> origin."

with the strengthening radius then raised to `0.50 p` engage / `0.60 p` release, or the drop region
narrowed to the strengthening region. Either choice is the product owner's; what is not optional is
that one number governs both.

---

### F9 — `ai_movetime_ms` must be range-checked at import, but no range is ever specified

**Severity: gap.**

`game-data.md:40`:

> "`ai_movetime_ms` is stored beside `ai_level` so a later retuning of a level's time does not
> reinterpret existing archives; **import checks both for presence and range**, not the current
> pairing."

No document states the range. The three accepted values are 1000, 3000 and 5000
(`engine-integration.md:97–99`, `product.md:37`, `testing.md:122`), but the whole point of the field
is that they may be retuned, so "the accepted values" cannot be the range. `core-interface.md`
carries `ai_movetime_ms` through `MxqGameConfig` and requires
`request->movetime_ms` to equal the session's frozen value (`:130`) without bounding either.
`testing.md:113` ("Test every import limit boundary") therefore has a boundary it cannot test.

**Correction:** fix the range in `game-data.md`'s accepted vocabulary section. A defensible choice,
which the product owner should confirm rather than a designer: **100 ≤ `ai_movetime_ms` ≤ 60000**,
integer milliseconds — comfortably wider than any plausible retuning of the three levels, and
narrow enough that a corrupt or hostile value cannot ask the engine for an unbounded search.

---

### F10 — "cell" carries two incompatible meanings, and the last-move brackets depend on the second

**Severity: ambiguity.**

`interaction-design.md:120`:

> "a 7-by-7 board is 7-by-7 **points**: a **6-by-6 grid of cells** with 49 intersections"

`interaction-design.md:142`:

> "A marker belonging to a point is contained within **that point's `1 p` by `1 p` cell**"

`interaction-design.md:247`:

> "Four L-shaped corner brackets on both the origin **cell** and the destination **cell**: arm
> `0.13 p`, stroke `0.045 p`, **inset `0.05 p` from each cell corner**"

The first "cell" is a square *between* four points; the second and third are a square *centred on*
a point. They are offset from each other by half a pitch in both axes, and the document introduces
the first meaning 22 lines before it silently switches to the second.

The consequence is not cosmetic: an implementer reading `:247` with the `:120` meaning would draw
the last-move brackets around the wrong square entirely — offset diagonally by `0.5 p` — and every
containment argument in `:142` and `:262` would move with them. The point-centred reading is the
correct one, and the document proves it itself at `:262` ("the brackets occupy the cell's corners
and the rings pass through its edge midpoints" — a `0.50 p` radius ring touches the edge midpoints
of a point-centred `1 p` square, and nothing else).

**Correction:** keep "cell" for the point-centred square, since eleven metrics depend on it, and
rename the other. In `interaction-design.md:120` replace "a 6-by-6 grid of cells" with "a 6-by-6
grid of **squares**", and add to Board metrics:

> "Throughout this document a **cell** is the `1 p × 1 p` square centred on a point, not one of the
> 36 squares between four points."

`interaction-design.md:227` ("Tapping an illegal board **square**") should then read "point".

---

### F11 — The macOS worked example does not name its layout shape, and enumerates chrome that only the other shape has

**Severity: ambiguity, plus one unsourced figure.**

`interaction-design.md:482`:

> "A built-in Retina display running at **1024 by 663 points** — the largest-text setting on a
> current Mac — leaves a window of **1024 by 582 points** once the menu bar and the Dock are
> subtracted, and **550 points of content height** below a standard title bar. At the 44-point floor
> the board core is 308 points square, so **more than 200 points of height remain for the turn
> status, the controls, the file numerals, and their spacing**."

The arithmetic is fine: 663 − 582 = 81 pt of menu bar plus Dock, 582 − 550 = 32 pt of title bar,
550 − 308 = 242 pt remaining, of which the strips take 32, leaving 210. And 1024 × 663 is a real
scaled mode (the 15-inch MacBook Air's 2880 × 1864 panel gives 1024 × 663 at its largest-text step;
the 13-inch gives 1024 × 666 and the 14-inch Pro 1024 × 665, so the figure is machine-specific).

Two problems:

1. **The layout shape is not named, and it changes the answer.** "turn status above the board, play
   controls below it" is the **stacked** shape (`:477`). But `:478` assigns "ordinary Mac windows"
   to **side by side**, where the turn status, move list, metadata and controls sit in a panel
   *beside* the board and consume width, not height. A 1024 pt-wide window is not obviously narrow.
   So the worked example computes a vertical budget for chrome that, on the very configuration it
   names, may not be vertical at all. Whichever way it resolves, the paragraph should say which
   shape it is checking — and if it is side by side, the binding constraint is the **width** left
   after the panel, which the paragraph never computes.
2. **The 32 pt title bar is our number, not Apple's.** I searched the HIG (Windows → macOS window
   anatomy; Toolbars → macOS) and **Apple publishes no title-bar height**. The 32 pt implied by
   582 − 550 is an unsourced assumption sitting inside the only worked layout budget in the contract.
   That should be said plainly rather than left to look like a platform constant.

**Correction:** in `interaction-design.md:482`, name the shape ("in the stacked shape, which this
window is narrow enough to select" — or redo the example for side by side and compute the width
budget), and append: "Apple publishes no title-bar height; the 32 points subtracted here are our
own measured value on the pinned toolchain and must be re-measured before the minimum window size
is fixed."

---

### F12 — 14-point **bold** digits are large-scale text, so the stated reason for taking 4.5:1 is wrong

**Severity: ambiguity (the requirement is right; the rationale is not).**

`interaction-design.md:155–156`:

> "The Chinese numerals are therefore set **semibold** and the digits **bold**."
>
> "Numerals reach at least **4.5:1** … They are text at **14 points at the floor, below the size at
> which a 3:1 ratio would suffice**, so the record-ink gate that governs the last-move brackets does
> not apply to them."

WCAG defines large-scale text as **at least 18 point, or 14 point bold**. The digits are set bold at
14 points, so they are *exactly* at the large-scale threshold, where 3:1 does suffice. The Chinese
numerals at semibold arguably are not. The requirement (4.5:1, and 7:1 under Increase Contrast) is
strictly stronger and is fine; it is the justification that does not survive the weight decision
made one bullet earlier — and commit `adde759` introduced both bullets in the same change.

**Correction:** in `interaction-design.md:156` replace the causal clause with a chosen one:

> "They are 14-point text at the floor, at the boundary of large-scale text for the bold digits and
> below it for the semibold numerals. Rather than split the gate by weight, both sets take the
> stricter 4.5:1, so the record-ink gate that governs the last-move brackets does not apply to
> either."

---

### F13 — A one-ply Undo of a long capture consumes its entire 250 ms budget, which the neighbouring rationale describes as roomy

**Severity: ambiguity.**

`interaction-design.md:411–412`:

> "An ordinary move travels smoothly to its destination in approximately **180–240 ms**."
>
> "A capture … targets an overall duration of approximately **250 ms**."

`interaction-design.md:416`, `:420`:

> "an Undo transition must therefore complete within **250 ms for one ply**…"
>
> "…two plies at **240** plus their overhead satisfy [600 ms] **with room to spare**."

Reversing a six-cell capture needs 240 ms of travel plus a coordinated restoration of the captured
piece, whose forward counterpart is accepted at ≈250 ms overall. That leaves **0–10 ms** of
overhead against the one-ply ceiling. The decision-cycle framing at `:420` implies a much more
generous per-ply budget (600 − 480 = 120 ms across two plies, i.e. 60 ms each), so the two
sentences describe budgets that differ by roughly a factor of six.

Separately, `:412`'s fixed ≈250 ms capture total does not scale with distance while `:411`'s travel
does, so the removal tail implicitly shrinks from ~70 ms at one cell to ~10 ms at six.

**Correction:** state the one-ply ceiling as a function of the ply rather than a constant. For
example, in `:416`: "an Undo transition must complete within **the reversed ply's own travel
duration plus 40 ms**, capped at 280 ms for one ply and 600 ms for a decision cycle" — and in `:412`
say whether the ≈250 ms is a one-cell figure or a maximum.

---

### F14 — "32 members per object" sits beside a 10,000-element array with no statement that arrays are excluded

**Severity: ambiguity.**

`game-data.md:62`:

> "Import limits: at most 1 MiB per file, **10 000 plies**, JSON nesting depth 4, **32 members per
> object**, 256-byte strings…"

`moves` may carry 10,000 elements. In JSON an array is not an object, so the limits do not in fact
conflict — but they are listed as one flat sequence, and an implementer applying "32 members" to
array elements would reject every archive longer than 32 plies. The largest object in the format has
13 members (`content`), so the 32 is comfortable; nothing signals that the 10,000 is governed by a
different limit.

**Correction:** in `game-data.md:62` write "**32 members per JSON object** (arrays are bounded
instead by the ply limit)".

---

### F15 — Every pulse is removed under Reduce Motion except the one that is converted, which has no duration

**Severity: ambiguity.**

`interaction-design.md:418`:

> "With Reduce Motion, the animation of lifts, springs, **pulses**, and long-distance travel is
> **removed** in favor of a brief crossfade or immediate state update."

`interaction-design.md:428`:

> "The check pulse is **removed rather than converted, as the accepted rule requires of every
> pulse**"

`interaction-design.md:250`:

> "With a piece selected, its legal-destination markers **pulse once** … Under Reduce Motion they
> **change state once instead of pulsing — a single step to a stronger appearance, held briefly and
> then restored**"

The illegal-tap pulse is converted, not removed, so "every pulse" at `:428` is false. And "held
briefly" is the only timing in the entire motion section without a number, in a document that fixes
180/195/200/210/220/230/240, 250, 260, 340, 500, 600 and 120 ms to the millisecond.

**Correction:** at `:428` write "as the accepted rule requires of every pulse that carries no
information on its own — the illegal-tap response is the exception, since removing it would remove
the answer to the tap", and give `:250` a number, e.g. "held for **400 ms** and then restored".

---

### F16 — The numeral strip's background is undefined, so the numerals' 4.5:1 and 7:1 are not yet measurable

**Severity: ambiguity.**

`interaction-design.md:156` requires numerals to reach "at least **4.5:1** against **the board
surface**, and 7:1 under Increase Contrast", but `:151` puts the strips **outside the board core**,
and `:80` defines the board surface as what a piece style paints *beneath the discs*. Whether the
strip carries the style's board surface, or the app's own background, is never said. `testing.md:166`
asks a tester to measure "against the board surface" in a strip that may not have one.

**Correction:** add to `interaction-design.md:151`: "Each strip is filled with the style's own board
surface, so it is part of the board block visually as well as geometrically, and the numerals'
contrast is measured against that fill."

---

## 3. Numbers I could not settle, and why

- **`interaction-design.md:155`, "about a quarter more ink" and "a residual difference of about a
  tenth".** These are measurements on the pinned toolchain that I cannot reproduce without the same
  font rendering. The internal logic is sound (Chinese carries more ink → set it one weight *lighter*
  → semibold against bold), and the 1.02 pt stroke of 一 against a 1.14 pt grid line is a real
  anchor. The document already flags re-measurement on iOS/iPadOS as required.
- **`engine-integration.md:49`, "the fork's 22 tests", "1,786-history differential", "53 parity
  splits"; `:53`, "29,500 legal samples over 11.2 million cycles".** Reported measurements from the
  fork work; out of scope to re-run here. The one cross-checkable figure in that paragraph — "all
  **16** approved fixtures pass identically" — matches the fixture count exactly.
- **`interaction-design.md:482`, the 81 pt of menu bar plus Dock.** Depends on the Dock size and
  magnification setting, which the document does not state. Not falsifiable as written.
- **`0.887`** in the strip-height formula. It is presumably an ideographic-height ratio for the
  pinned font cascade; the document does not say what it measures, so a later font change cannot be
  known to invalidate it. Worth naming its source in one clause.

## 4. Two things that are *not* defects, recorded so they are not re-raised

- **`mx-chs-001` and `mx-chs-004` do not pass against built-in `minixiangqi`.** Executed:
  `is_optional_game_end` returns a draw where the fixtures assert a chase loss. This is the
  contract's own accepted position (`engine-integration.md:128`), not a numeric inconsistency, and
  `mx-chs-003`'s pass on that variant is coincidental — the soldier is treated as chaseable but the
  variant has no chasing rule at all. Confirmed at `variant.h:130` (`NO_CHASING` default) and
  `variant.h:118` (`soldierPromotionRank = RANK_1`, which is why Mini Xiangqi soldiers are
  internally promoted from the start, exactly as `mx-chs-003`'s rationale states).
- **The pinned network's filename on disk is `minixiangqi-12c45d5da817.nnue`, not the contract's
  `minixiangqiaxf-12c45d5da817.nnue`.** That is the rename the contract *requires* at bundling
  (`engine-integration.md:134`, "Only the filename changes"), not a mismatch. Byte length and
  SHA-256 both verified identical.
