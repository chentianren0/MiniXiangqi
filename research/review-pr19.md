# Pre-merge review — PR #19 `design/board-visual-system`

> **Status: Workspace-only review report. Non-normative.**
>
> Independent adversarial review of `ppppvz/MiniXiangqi` PR #19, standing in for human
> review. Nothing in the product repository was modified; no remote write, comment,
> review, or merge was performed. Read-only `gh` access used the project-scoped identity
> (`gh api user --jq .login` → `ppppvz`).
>
> Reproduction scripts (workspace-only scratch):
> `discussion-drafts/rv19-geom.py` — every number in §1, recomputed from the diff's own
> primitives at `p = 44`.
> `discussion-drafts/rv19-rules.py` — §2, engine probes against the prebuilt `pyffish`
> in `discussion-drafts/r-scratch/` on the built-in `minixiangqi` variant.
> `discussion-drafts/screen-metrics.swift` — §3, re-run this session under
> `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` (Xcode 27.0, build
> `27A5228h`, matching `AGENTS.md`).
>
> **Conventions.** `p` = cell pitch. All radii from a point's centre. A stroke of width
> `w` on centre-line `r` occupies `[r − w/2, r + w/2]`. The single floor is `p = 44`.
> "Containment" for a circular marker means outer ink radius `≤ 0.50 p`; for a square
> marker it means the square fits the `1 p × 1 p` cell (its half-diagonal may exceed
> `0.50 p` without leaving the cell — an error worth stating, because it is easy to make).

---

## 0. Scope correction, and the six prior blocking defects

### 0.1 The PR is larger than described. **should-fix (process)**

The review brief describes "one commit, one file." The branch tip is **`5286480`, two
commits, two files**:

```
36a647c  Accept the board's metric system and game-state markers   docs/interaction-design.md  +57 −7
5286480  Update the validation contract for the board's visual system  docs/testing.md  +8 −1
```

`docs/testing.md` is an accepted contract and its new lines are normative validation
gates. They are reviewed here, and two of this report's blocking findings are visible
only because that file was read. **Correction: none needed to the PR; the brief was
wrong. But do not merge on the strength of a review that only read the first commit.**

### 0.2 Each prior blocking defect, checked

The prior review (`discussion-drafts/verify-board-visual-language-geometry.md`) labels
**nine** findings BLOCKING while its own summary line says "6 blocking" — a pre-existing
inconsistency in that document, not in this PR. All nine are checked below.

| Prior finding | Status in this PR | Evidence |
|---|---|---|
| 1.1 — false pitch-dependent justification for the `0.84 p` disc | **Fixed.** The false sentence is gone; `0.80 p` now follows structurally from disc `≤ 0.40 p` + `0.02 p` gap + band base `0.42 p`. | diff, `Board metrics` |
| 1.3 — blanket "every gap ≥ 0.6 pt" false in five places | **Fixed by deletion.** No blanket gap claim survives. | diff |
| 2.1 — check ring overruns an adjacent capture ring by `0.06 p` | **Fixed.** Both outer edges now exactly `0.50 p`; adjacent rings are exactly tangent, sum `1.00000 p`. | rv19-geom |
| 2.2 — lifted selection ring overruns an adjacent capture ring | **Fixed.** Lifted outer edge `0.477750 p`; clearance to the neighbour's `0.50 p` near edge is `0.02225 p` = **0.979 pt**. | rv19-geom |
| 2.6 — selection + check "clear gap" is 0.23 pt | **Fixed** by hiding the check rings while the general is held. | diff |
| 2.8 — z-order's "geometry already guarantees no overlap" is false | **Mostly fixed** — the false justification is replaced by the sound one ("Rings are drawn above resting discs so that no disc can clip one"). Residue at §1.9. | diff |
| 2.9 — the illegal-tap mark sits on the disc face | **Fixed** by deleting the marker: "**Illegal tap.** No board mark." See §6.1 for the cost. | diff |
| 3.2 — brackets + check falsified through Undo | **Fixed.** "They always mark the game's current last move: an Undo moves them to the move that is now last." Replay half missing (§2.3). | diff |
| 4.1 — brackets and 将军 stated as accepted without contract basis | **Accepted as fixed** on the PR body's statement that the owner confirmed both before writing. Not independently verifiable by me. | PR body |

**All nine prior blocking defects are addressed, and the adjacent-cell collision class is
genuinely closed by construction.** That is real work and it holds up. The blocking
findings below are all in different places.

---

## 1. Geometry, recomputed from scratch

Every value below is from `rv19-geom.py`, derived only from the diff's own primitives.
The bands at `p = 44`:

| Marker | Band (units of `p`) | pt at `p = 44` |
|---|---|---|
| Selection ring, at rest | `[0.42500, 0.45500]` | `[18.700, 20.020]` |
| Selection ring, ×1.05 lift | `[0.44625, 0.47775]` | `[19.635, 21.021]` |
| Selection ring, ×1.10 drag | `[0.46750, 0.50050]` | `[20.570, 22.022]` |
| Capture ring | `[0.44500, 0.50000]` | `[19.580, 22.000]` |
| Capture ring, thickened `0.07 p` | `[0.43000, 0.50000]` | `[18.920, 22.000]` |
| Check ring, inner | `[0.42000, 0.44500]` | `[18.480, 19.580]` |
| Check ring, outer | `[0.47500, 0.50000]` | `[20.900, 22.000]` |
| Destination dot, grown | `[0, 0.16500]` | `[0, 7.260]` |
| Drag-origin hollow dot | `[0.08750, 0.13250]` | `[3.850, 5.830]` |
| Hover fill (square half-extent) | `[0, 0.45000]` | `[0, 19.800]` |
| Focus ring (square, at edge midpoints) | `[0.41000, 0.47000]` | `[18.040, 20.680]` |
| Last-move bracket, max extent / nearest ink | `0.49250` / `0.54053` | `21.670` / `23.783` |

**The metrics table's "At the floor" column is arithmetically correct.**
`7 × 44 = 308`; `0.80 × 44 = 35.2`; `0.50 × 44 = 22`; `0.42 × 44 = 18.48` (stated 18.5);
and the board core's derivation checks out — 7 points span 6 cells (`6 p`) plus `0.5 p`
margin each side = `7 p`. No correction needed.

### 1.1 The air-gap rule is false as written for four of the eleven markers, and `testing.md` now makes it a gate the design cannot pass. **BLOCKING**

> `interaction-design.md`: "A piece style's own rings and edge strokes live at or inside
> `0.40 p`. **Every game-state marker lives at `0.42 p` or beyond.** … and **a marker may
> not touch the disc face**"

> `testing.md` (added by this PR): "Verify the accepted board-metric rules at the smallest
> supported size and at a large one: no piece style draws decoration beyond `0.40 p`, **no
> marker's ink falls inside `0.42 p`**, and no marker leaves its own `1 p` cell at rest or
> at any moment of its animation, including the selection lift, a drag's target
> strengthening, and the check pulse."

Recomputed inner ink radii:

| Marker | Inner ink | `≥ 0.42 p`? |
|---|---|---|
| Legal-destination dot | `0.00000 p` | **no** |
| Drag-origin hollow dot | `0.08750 p` | **no** |
| Pointer hover fill | `0.00000 p` | **no** |
| Keyboard focus ring | `0.41000 p` | **no** |

Three of these are harmless in substance — the dots sit on empty points and the hover
fill is drawn beneath the pieces — but the rule is stated without qualification, and the
new `testing.md` line converts it into a pass/fail gate that the accepted vocabulary
fails four times over. A tester following `testing.md` literally must fail the board.

**The fourth is a substantive violation.** The keyboard focus ring's inner edge is
`0.41 p`. The prompt's question — does a non-scaling marker still clear the *lifted*
disc? — resolves against it:

- at rest, disc edge `0.40 p`, focus inner edge `0.41 p` → air gap **`0.01 p` = 0.44 pt**,
  half the required `0.02 p`;
- under the ×1.05 selection lift, disc edge `0.42 p` > focus inner edge `0.41 p` →
  **overlap `0.01 p` = 0.44 pt**. The focus ring, which the layering puts on top, covers
  the outer rim of the lifted disc at the four edge midpoints.

That rim is not decoration. `Piece styles` makes it load-bearing — "The disc's boundary —
its ring or edge stroke — reaches at least 3:1 against the style's own board surface" —
and in 传统 the Black disc's "heavier ring" is the *only* non-colour carrier of side when
icon symbols are selected. The one marker that clips it is the keyboard affordance, used
by exactly the people who depend on that channel. The document's granted exemption is
narrow and does not cover this: "It is also the only marker permitted to cross **another**
[marker]" — a disc is not a marker.

This also inherits an arithmetic error from the prior review, which recommended
"shrink S12 to `0.88 p` (band `[0.41, 0.47]`) so it clears both the disc and every ring."
It clears neither: `0.41 < 0.42` (disc band) and `[0.41, 0.47] ∩ [0.445, 0.50] ≠ ∅`
(capture ring). The PR adopted the number without rechecking it.

**Correction (three edits).**
1. Rewrite the rule to what it means: *"On an occupied point, no game-state marker's ink
   falls inside `0.42 p`, and none touches the disc face. Markers that belong to an empty
   point — the legal-destination dot and the drag origin — and the pointer hover fill,
   which is drawn beneath the pieces, are outside this rule."*
2. Move the focus ring to a `0.92 p` square with stroke `0.04 p` (band `[0.44, 0.48]`):
   contained (`0.48 ≤ 0.50`), clears the lifted disc by `0.02 p`, keeps the same visual
   weight. Or state an explicit exemption in both this section and the focus-ring bullet.
3. Amend the `testing.md` line to match, or it will fail a correct implementation.

### 1.2 The check pulse is unbounded, and the two structural rules are jointly unsatisfiable for it. **BLOCKING**

> "two concentric solid rings of stroke `0.025 p` at centre-line radii `0.4325 p` and
> `0.4875 p` … **The pair pulses once in stroke weight as it appears** and never again. A
> pulse in scale is not available here, because it would carry the outer ring out of the
> cell."

The section rules out a scale pulse on containment grounds, substitutes a stroke-weight
pulse, and then never bounds it. The two rings sit *exactly* on both limits at rest —
inner edge `0.42000 p`, outer edge `0.50000 p` — so there is no slack in either direction:

| Pulse stroke | Inner ring | Outer ring | Inter-ring gap |
|---|---|---|---|
| `0.025 p` (rest) | `[0.4200, 0.4450]` ok | `[0.4750, 0.5000]` ok | 1.320 pt |
| `0.030 p` | `[0.4175, 0.4475]` **breaks 0.42** | `[0.4725, 0.5025]` **breaks 0.50** | 1.100 pt |
| `0.040 p` | `[0.4125, 0.4525]` **breaks 0.42** | `[0.4675, 0.5075]` **breaks 0.50** | 0.660 pt |

The containment rule has an escape clause ("Where a marker would grow beyond the cell it
grows inward instead"), which saves the outer ring. **The air-gap rule has no escape
clause**, so any symmetric thickening of the inner ring violates it — and the only
alternative, growing outward only, eats the `0.03 p` inter-ring gap that is the entire
reason the marker is a *double* ring. `testing.md` names "the check pulse" explicitly as a
gate, so this is not theoretical.

**Correction.** Add to the check-ring bullet: *"The pulse thickens each ring to at most
`0.0325 p`, growing only into the gap between them, so the pair never crosses `0.42 p` or
`0.50 p` and at least `0.015 p` of gap survives."* (At `0.0325 p`: inner `[0.42, 0.4525]`,
outer `[0.47125, 0.50]`, gap `0.01875 p` = 0.825 pt.)

### 1.3 Containment: everything else passes, with one arithmetic exception at ×1.10. **should-fix**

Containment at rest and under every stated animation:

| Marker | Outer ink | `≤ 0.50 p`? | Slack |
|---|---|---|---|
| Selection ring, rest | `0.455000` | yes | +1.980 pt |
| Selection ring, ×1.05 | `0.477750` | yes | +0.979 pt |
| **Selection ring, ×1.10 (drag)** | **`0.500500`** | **no** | **−0.022 pt** |
| Capture ring | `0.500000` | tangent | 0 |
| Capture ring, thickened to `0.07 p` | `0.500000` | tangent | 0 |
| Check outer ring | `0.500000` | tangent | 0 |
| Destination dot, grown to Ø `0.33 p` | `0.165000` | yes | +14.740 pt |
| Hover fill (square) | half-extent `0.45` | yes | +2.200 pt |
| Focus ring (square) | half-extent `0.47` | yes | +1.320 pt |
| Last-move bracket | `0.492500` | yes | +0.330 pt |

The `×1.10` row: the Layering line says the topmost object is "the held **or dragged**
disc with its lift shadow **and attached selection ring**", and the selection ring is
"attached to the piece so that it scales with the lift". At `×1.10` its outer edge is
`0.455 × 1.10 = 0.500500 p`. **The maximum lift the containment rule permits is
`0.50 / 0.455 = ×1.0989`.** The violation is 0.022 pt — physically nothing — but it is a
literal failure of the section's keystone rule and of the new `testing.md` gate ("no
marker leaves its own `1 p` cell at rest or at any moment of its animation"), and it is
compounded by the fact that a *dragged* disc is detached and centred between points, so
"its own cell" does not exist for it at all.

Related and worse in kind: `Motion and visual effects` still says "The exact durations,
easing curves, **scale**, shadow, opacity, and feedback strength are first-version values
subject to adjustment after testing on physical iPhone, iPad, and Mac hardware." Scale is
now load-bearing for a structural invariant and cannot be freely adjusted.

**Correction:** state that the dragged disc is detached and carries no ring (and delete
"and attached selection ring" from the Layering line, or scope it to the *held* disc), and
add to `Motion`: *"The lift and drag scales are bounded by the containment rule in Board
metrics; the selection ring's attachment caps any lift at `×1.098`."*

### 1.4 Same-point pairs — the full matrix

| Pair | Result | Reachable? |
|---|---|---|
| Selection + destination dot | disjoint by 12.375 pt | **no** — a piece's own point is never its destination |
| Selection + capture ring | overlaps **1.386 pt** | **no** — selection marks the side-to-move's piece, capture marks the other side's |
| Selection + check rings | overlaps 0.121 pt (outer) | **no** — rings hide while held (§0.2, prior 2.6) |
| Capture ring + check outer ring | overlaps **1.100 pt** | **no** — see §2.2; this is the one load-bearing impossibility |
| Capture ring + brackets | disjoint by **1.783 pt** | yes, routine — safe |
| Destination dot + brackets | disjoint by 16.523 pt | yes, routine — safe |
| Brackets + check rings | disjoint by 1.783 pt | claimed impossible (§2.3) — **and geometrically harmless either way** |
| Focus ring + selection ring (lifted) | overlaps 1.045 pt | yes |
| Focus ring + capture ring | overlaps 1.100 pt | yes |
| Focus ring + check inner ring | overlaps 1.100 pt — **covers it entirely** at the four edge midpoints | yes |
| Focus ring + check outer ring | disjoint by only **0.220 pt** | yes |
| Hover fill + capture ring | fill edge `0.45 p` lies **inside** the capture band | yes |
| Hover fill + check rings | fill edge `0.45 p` lands **inside the `0.03 p` inter-ring gap**, 0.220 pt from the inner ring | yes |
| Destination dot + drag origin | overlaps | **no** — "an origin is never itself a legal destination" |

Two observations worth a sentence in the document:

- The focus ring's blanket exemption ("the only marker permitted to cross another") is
  load-bearing for **four** pairings, not an edge case. In one of them it wholly obscures
  the inner check ring at four points — and the check marker's meaning is carried by its
  *doubleness*. **should-fix**: say so, or route the focus ring outside `0.50 p`… which is
  impossible, so say so.
- The hover fill's edge bisects the check rings' `0.03 p` gap on a hovered checked
  general. **nit**, but it is the one gap the design spent the disc's `0.04 p` to buy.

### 1.5 Adjacent-cell containment holds — and this is the PR's real achievement

Summing outer radii for every adjacent pair (centres `1.0 p` apart), only these reach
`1.0 p` at all, and none exceeds it except the `×1.10` case from §1.3:

```
capture + capture      1.00000 p   exactly tangent
capture + check outer  1.00000 p   exactly tangent
check outer + check outer 1.00000 p exactly tangent
```

Diagonal neighbours' brackets clear by `0.02121 p` = 0.933 pt. The containment rule does
what the PR body claims it does.

### 1.6 Adjacent cells' last-move brackets still nearly merge. **should-fix**

> "arm `0.16 p`, stroke `0.045 p`, inset `0.03 p` from each cell corner"

Elbow at `(0.47, 0.47) p`; ink max extent `0.49250 p`. Two adjacent cells' facing arms
therefore leave an ink gap of `2 × (0.50 − 0.4925) = 0.01500 p` = **0.660 pt at `p = 44`** —
two `1.98 pt` strokes separated by 0.66 pt (1.3 device px at 2×), overlapping in the other
axis. The prior review raised this (finding 2.4) and recommended "increase the inset to
`≥ 0.05 p` or specify what two adjacent bracket sets do." **Neither was done**; the gap
improved from 0.42 pt to 0.66 pt purely because the floor rose, and the geometry is
byte-identical to the abandoned draft's.

This is not an edge case: brackets are drawn on **both** the origin and destination cell,
and every general move and every non-sideways soldier step makes those cells adjacent.
Five of each side's twelve pieces are soldiers.

**Correction:** inset `0.06 p` (elbow `(0.44, 0.44)`, max extent `0.4625 p`, adjacent gap
`0.075 p` = **3.3 pt**), or state explicitly what two adjacent bracket sets do.

### 1.7 The dash geometry closes, but the rounded caps eat 55 % of the gap. **should-fix**

`12 × (18° + 12°) = 360°` — **closes exactly.** At centre-line `0.47250 p` (= `20.790 pt`):

| | units of `p` | pt at `p = 44` |
|---|---|---|
| dash arc, nominal | `0.148440` | **6.531** |
| gap arc, nominal | `0.098960` | **4.354** |
| dash, with round caps (`+w` = `+0.055 p`) | `0.203440` | **8.951** |
| gap, with round caps (`−w`) | `0.043960` | **1.934** |

Duty cycle goes from the designed **60 % ink to 82 % ink**. The gap survives — 1.93 pt,
3.9 device px at 2× — so the marker still reads as dashed, but only just, and the document
states "All strokes use rounded caps" without ever reconciling it with the dash pattern.
This was prior finding 1.6 (should-fix); not fixed. Radial extent is unaffected: a cap's
farthest reach is `0.4725 + 0.0275 = 0.50000 p`, exactly the outer edge, so containment
holds.

Related **nit**, also unfixed (prior 2.11): the dash **phase** is unspecified. Two adjacent
capture rings are exactly tangent; if both phase a dash onto the line of centres, two
`0.055 p` strokes touch and read as one `0.11 p` blob. Fix the phase (e.g. a gap centred on
each cardinal direction).

**Correction:** quote cap-adjusted figures, or specify butt caps for the capture ring only,
and fix the phase.

### 1.8 "Four shape families … each shape has exactly one member … no two markers are confusable" is false three times. **should-fix**

> "Markers use four shape families … **small circles at a point** …, **rings around a
> disc** …, **corner marks on a cell** …, and **the turn-status element** …. **Each shape
> has exactly one member, so no two markers are confusable at any supported size**"

- **The hover fill and the keyboard focus ring are rounded squares and belong to none of
  the four families.** There are at least five.
- Small circles has **two** members (filled destination dot Ø `0.22 p`, hollow drag-origin
  dot Ø `0.22 p`) — identical in size, distinguished only by fill. The document concedes
  this and argues from context, not shape: "unambiguous against it because an origin is
  never itself a legal destination."
- Rings around a disc has **three** (solid selection, dashed capture, double check).
- The two rounded squares are the most confusable pair in the vocabulary: `0.90 p` vs
  `0.88 p` — a difference of `0.02 p` = **0.88 pt** — and they co-occur when a pointer
  hovers the focused point.

**Correction:** name five families, or drop the count and keep only the per-pair argument
the section already makes elsewhere; and delete "so no two markers are confusable," which
does not follow and is not true.

### 1.9 The closing containment claim still ignores the detached disc. **should-fix**

> "**Because every marker is contained by its own cell, only markers on the *same* point
> can ever meet**, and those cases are closed"

The dragged disc is "offset `0.5 p` above the touch point" — i.e. centred **on a cell
boundary by construction** — at `×1.10` (radius `0.44 p`), with "the strongest lift
shadow", and by the Layering line with its selection ring attached. It covers parts of two
to four cells' markers in every touch drag. The lift shadow is likewise cast over
neighbours. This is intended behaviour, but it is a counterexample to the sentence as
written. (Prior finding 2.8 was fixed where it mattered most — the z-order justification —
but this residue remains.)

**Correction:** *"Because every marker is contained by its own cell, only markers on the
same point can ever meet. The dragged disc is the one object that leaves its cell; the
layering above is what governs it."*

### 1.10 Smaller items

- **nit** — The metrics table row "Marker band, as a radius from a point's centre |
  `0.42 p` to `0.50 p`" is descriptive of the ring markers only. Five of the eleven markers
  fall outside it (both dots, hover fill, focus ring inside; brackets reach `0.54053 p`
  radially, legitimately, because the cell is square). Say "ring markers".
- **nit** — At an outermost point the capture and check rings reach exactly `0.50 p`,
  i.e. exactly the half-cell margin. "contained by the margin and **never reach the
  coordinates**" is true only in the closed sense; clearance is zero.
- **nit** — the bracket elbow at `(±0.47, ±0.47) p` lies on the 45° line, so on the eight
  palace points carrying a diagonal the diagonal runs straight through the elbow (prior
  2.5, unfixed).

---

## 2. The rules claims

Method: `docs/xiangqi-rules.md`, the sixteen approved fixtures in `fixtures/rules/`
(`mx-end-003` pins flying-general rejection, `mx-move-006` pins a check position whose
legal set is exactly its evasions), `docs/game-data.md`, plus engine probes with the
prebuilt `pyffish` on the built-in `minixiangqi` variant. Engine output corroborates; the
reasoning stands on the contract.

Random-walk sweep from the frozen start FEN: **17,078 reachable positions, 551 check
events, zero violations of either claim, and no position with both generals in check.**

### 2.1 Both impossibility claims are TRUE. No counterexample exists.

I could not construct one and do not believe one exists, under normal play, Free Play,
all four Undo forms, discovered check, replay stepping in both directions, the
flying-generals rule, the pre-start preview, or imports.

The underlying invariant, which the document does not state, is: **in any position
reachable by legal play, the checked general belongs to the side to move, and the last
move belongs to the other side.** A move that leaves your own general attacked is illegal,
so at most one general is ever attacked; `mx-end-003` and `game-data.md`'s import
validation ("the initial position must be exactly the frozen starting FEN in version 1,
every move must be legal in sequence") keep every rendered position legal.

### 2.2 Claim (a)'s stated reason is engine-falsifiable and weaker than the true one. **should-fix**

> "a capture ring never surrounds a checked general, **because a general is never a legal
> capture target**"

The conclusion holds. The reason does not survive contact with the move generator, which
produces general-captures whenever it is handed an illegal position:

```
FEN  3k3/7/7/7/3R3/7/3K3 w - - 0 1     # Rd3 attacks kd7, Red to move — illegal position
     'd3d7' in legal_moves  ->  True   # capturing the general
```

A general is excluded by **reachability**, not by the movement rules. `docs/xiangqi-rules.md`
contains no rule forbidding the capture of a general; it relies on king safety, which is a
property of legal *play*, not of move generation.

This matters because the geometry behind this claim is severe — capture ring `[0.445, 0.50]`
against check outer ring `[0.475, 0.50]` **overlap by 1.100 pt**, sharing an outer edge
exactly — so the claim is the only thing preventing a real rendering defect. It should rest
on the strongest available argument. (Flying generals do not weaken it further: probed at
`3k3/7/7/7/3K3/7/7 w`, the engine offers only `d3c3`, `d3e3` — a general can never capture a
general, and the palaces never come within one square of each other.)

**Correction:** *"a capture ring never surrounds a checked general: check marks the side to
move's own general, and a capture ring marks a piece of the other side. This depends on
every rendered position being legal, which archive version 1 guarantees by freezing the
start FEN and validating every move."* Note that `game-data.md`'s **Need to discuss**
already anticipates a future start-from-position feature and defers the setup-legality
predicate — the reformulated argument survives that; the current one does not.

### 2.3 Claim (b)'s new wording closes the Undo hole, but leaves replay open. **should-fix**

> "**They always mark the game's current last move**: an Undo moves them to the move that
> is now last rather than leaving them behind, and no brackets are shown at an initial
> position."
>
> "last-move brackets never fall on a checked general's cell, because the last move was
> the opponent's and neither of its cells holds that general"

**The Undo hole is closed.** Re-running the prior review's construction: after
`1. a2b2 d6d5 2. b1b7 d7d6`, Undo returns to `P = rCn1ncr/p1p1p1p/…` where Black is in
check on d7. Under the new rule the current last move is `b1b7`, cells b1 and b7 — neither
is d7. The old "persistent until the next ply replaces them" reading is gone. Verified
across all four Undo forms the contract defines (Free Play one ply; human-vs-AI decision
cycle; Undo during AI search; Undo of a terminal-reaching human move).

**Replay is not covered.** "the game's current last move" admits two readings once you are
at ply *k* of *N*: the move that produced the *displayed* position (correct), or the last
move of the *game* (ply *N*). The Undo clause implies the first, but the brackets bullet
never mentions replay, and `History replay` was not amended. Under the second reading the
claim is falsifiable: brackets frozen on the mating move's cells while the check rings sit
on a general standing on one of those cells earlier in the game. The prior review's
recommended wording covered both — "Undo **and replay navigation** move the brackets to
the new last move" — and only the Undo half was adopted.

Note for calibration: unlike claim (a), this claim is **not load-bearing geometrically**.
Nearest bracket ink is `0.54053 p` and the check rings stop at `0.50 p`, so even a
counterexample clears by **1.783 pt**. It is a correctness-of-statement issue.

**Correction:** *"They always mark the move that produced the position currently on the
board. Undo and replay navigation move them to the new last move; no brackets are shown at
an initial position."*

### 2.4 The brackets' behaviour during the Undo reversal is still unstated. **should-fix**

`Motion` requires an Undo transition to complete "within 250 ms for one ply and 600 ms for
a decision cycle." During that window the old and new bracket sets otherwise coexist, and
a decision-cycle Undo moves them two plies. The prior review asked for this explicitly; it
was not added.

### 2.5 Free-Play voice. **should-fix** (unfixed from prior 3.4)

> "A dashed ring around **the enemy disc**"; "one rings **the player's** piece, the other
> **an opponent's**"; "only the piece **the player holds** lifts"

In Free Play "the same person controls both sides" (`Turn status`), so there is no enemy
and no *the player*. The geometry is unaffected; the disambiguating argument needs
restating as "the side-to-move's piece" against "a piece of the other side."

---

## 3. The macOS floor and its evidence

Re-run this session (Xcode 27.0, build `27A5228h`; `sysctl hw.model` → `Mac17,4`; single
built-in Retina display, 2880 × 1864 native):

```
frame        : 1024 x 663 pt   (backing scale 2.0x -> 2048 x 1326 px)
visibleFrame : 1024 x 582 pt   at origin (0, 55)
lost to top  : 26 pt   lost to bottom : 55 pt
title bar height: 32 pt (standard titled window)
```

### 3.1 The arithmetic is correct

`663 − 26 − 55 = 582` ✓. `582 − 32 = 550` ✓ — and note the document is *more* accurate
than the script's own summary line, which hardcodes a 28 pt title bar and prints 554; the
measured title bar is 32 pt and the document used it. `550 − 308 = 242`, so "more than 200
points of height remain" ✓. **No arithmetic correction needed.**

### 3.2 "the most constrained configuration the target MVP supports" is unsupported. **should-fix**

> "That floor is affordable on **the most constrained configuration the target MVP
> supports**. A built-in Retina display running at 1024 by 663 points — **the largest-text
> setting on a current Mac** —"

Three problems.

1. **One machine.** `Mac17,4` is a 14-inch M5 MacBook Pro. Its most-scaled mode is
   1024 × 663 pt. A 13-inch MacBook Air (2560 × 1600) most-scaled gives 1024 × **640** pt —
   23 pt less, and macOS 26 supports such machines against this repository's macOS 26.5
   deployment target. The document neither names the measured model nor fixes the supported
   Mac set anywhere in the repository, so "the most constrained" is an extrapolation from
   n = 1. (At 640 pt the budget is still 219 pt, so the *conclusion* survives — but the
   claim as stated is not what was measured.)
2. **One Dock configuration.** The 55 pt "lost to bottom" is this machine's Dock, at its
   current size, at the bottom, not auto-hidden. That is a user setting, not a platform
   constant, and `visibleFrame` reports whatever it is.
3. **Not obviously the tightest configuration overall.** The claim is unqualified ("the
   target MVP"), but the MVP also ships iPhone portrait and iPadOS windowing, whose floors
   `Need to discuss` still defers ("name the narrowest supported iPhone the stacked layout
   is verified against").

**Correction:** scope it — *"On the tightest configuration measured — a 14-inch built-in
Retina display at its largest-text setting, 1024 by 663 points, with a bottom Dock — …"* —
and drop "the most constrained configuration the target MVP supports."

### 3.3 "The floor therefore never forces the window to fill the screen" is overstated, and the paragraph concedes it in the next sentence. **should-fix**

> "…so more than 200 points of height remain for the turn status, the controls, the file
> numerals, and their spacing. **The floor therefore never forces the window to fill the
> screen.** The exact minimum window follows from the chrome inventory that remains open
> below, and must fit this budget."

The measurement supports exactly one proposition: **242 pt of content height remains after
a 308 pt board core.** Whether that is *enough* is the open item, two lines later in the
same paragraph and again in `Need to discuss` ("Fix the minimum window size for macOS and
for iPadOS windowing, which the board and chrome floors together determine"; "Resolve how
the non-dismissible result card, the retained draw-claim affordance, and accessibility text
sizes fit the stacked layout's remaining space"). The "therefore" asserts the conclusion the
next sentence defers.

The file-numeral strips make this concrete: their geometry is explicitly open ("Define the
**numeral strips' geometry**, typography, and contrast requirement"), and they are counted
inside the 242 pt. At `0.5 p` each (22 pt), both strips cost 44 pt and 198 pt remains —
below the paragraph's own "more than 200" headline, though the headline is about the
budget before the numerals, so it is not falsified. It is simply not yet known to be
affordable.

**Correction:** replace the "therefore" sentence with *"The floor therefore leaves 242
points of content height for the turn status, the controls, the file numerals, and their
spacing. The exact minimum window follows from the chrome inventory that remains open
below, and must fit within that."*

### 3.4 "the sizes above" is now singular. **nit**

`Layout shapes`: "the board may not be driven below **the sizes above**" — there is now one
size. Same for `testing.md`'s "each platform's minimum window size" (correct as written, it
is about *window* size, but it sits one clause after the newly-unified pitch floor and reads
ambiguously).

---

## 4. Contract consistency

`docs/`, `README.md`, `AGENTS.md`, `CLAUDE.md`, and `fixtures/` were swept for every
spelling of the old floor, of the affected states, and of the anchors.

### 4.1 The 28 pt floor is fully removed. **verified clean**

Zero surviving references anywhere. `docs/testing.md:57` was correctly updated in the
second commit (that is what it is for). Every remaining literal `28` in the repository is
the Xcode build number `27A5228h`, `128 MiB` in `engine-integration.md`, or GPL boilerplate
in `LICENSE`. No document assumes two floors.

### 4.2 The anchors are correct. **verified clean**

All four in-document anchor links resolve under GitHub's heading-anchor rules:

| Line | Link | Target heading | Slug |
|---|---|---|---|
| 112 | `[Layout shapes](#layout-shapes)` | line 428 `### Layout shapes` | `layout-shapes` ✓ |
| 198, 241 | `[Game-state markers](#game-state-markers)` | line 207 `### Game-state markers` | `game-state-markers` ✓ |
| 435 | `[Board metrics](#board-metrics)` | line 110 `### Board metrics` | `board-metrics` ✓ |

No duplicate slugs anywhere in the file, so no `-1` suffixing. GitHub preserves the hyphen
in `Game-state markers`. No other document links into `interaction-design.md` with an anchor.

### 4.3 The new save-failure copy contradicts an accepted bullet twelve lines above it. **BLOCKING**

> New, line 226: "**A failed save** is reported by a transient capsule anchored to the
> turn-status element, reading **无法保存这一步，请重试。**"
>
> Accepted, unchanged, line 200: "**When the failed save is the AI's reply**, the game
> remains at the last committed position with the AI still to move, and the app requests a
> new AI move **rather than asking the user to retry a move that is not theirs**."

The new bullet is unqualified — "A failed save" — and the string literally asks the user to
retry (请重试). Line 200 forbids exactly that for the AI-reply case. An implementer cannot
satisfy both, and this is normative user-facing copy: `Localization` states "the accepted
user-facing copy in this document is normative." The prior review raised this (finding 4.4);
it was not addressed.

Consequences beyond the contradiction:

- The item removed from `Need to discuss` — "Define the exact visual treatment for
  selection, legal destinations, captures, illegal-square feedback, **save-failure
  feedback**, and unavailable input" — is therefore **not** fully resolved, so its removal
  is premature for that sub-item.
- The document now carries two save-failure presentations, the new capsule and the accepted
  **无法保存对局** / **当前对局仍然保留。请重试。** alert (line 288, also pinned in
  `core-interface.md:210` and `testing.md:72`), with no statement of how they relate.
- `testing.md` pins every character of the 无法保存对局 dialog but has **no gate at all**
  for the new string. **should-fix.**

**Correction:** scope the capsule — *"A save failure on the user's own action (a move, an
Undo) is reported by a transient capsule … reading 无法保存这一步，请重试。 When the failed
save is the AI's reply the board shows nothing and no capsule appears; the app requests a
new AI move."* — and add the matching `testing.md` line.

### 4.4 `Motion and visual effects` was left stale in three places. **should-fix**

Only one bullet (invalid drop) was updated. The rest now disagree with the new section:

- Line 384: "**Check uses a persistent, non-color-only king-square treatment** plus one
  brief pulse." Three problems: the new rule hides the treatment while the general is held;
  "king-**square**" contradicts `Board geometry and notation`'s "The board is never drawn as
  a checkerboard of squares"; and "king" is the term the rest of the document replaced with
  "general". The new section is itself self-contradictory on the same point —
  "**persistent** for as long as that side is in check" immediately followed by "the check
  rings **hide**".
- Line 378: "capturable destinations use **a ring** around the target piece" — the new
  bullet makes it a *dashed* ring, and the dashed/solid distinction is the whole shape
  argument.
- Line 389: "The exact durations, easing curves, **scale**, shadow, opacity, and feedback
  strength are first-version values subject to adjustment" — see §1.3; scale is now
  structural.

Also `Sound and haptics` line 397: "The two must remain distinguishable from each other, **as
their visual feedback already is**." After this PR neither an illegal tap nor a failed save
draws a board mark; the visual distinction was re-derived structurally in the new section but
line 397 still asserts the old one. **should-fix.**

### 4.5 The Differentiate Without Color claim contradicts the focus-ring bullet, and `testing.md` now gates it. **should-fix**

> Line 126: "**Because every marker is carried by luminance and shape rather than by hue**,
> the board under Differentiate Without Color is identical to the board without it."
>
> Line 222: "It is **the one marker that carries hue**, because matching the platform's own
> focus ring is worth more here than vocabulary purity"
>
> `testing.md`: "Verify the board renders identically with Differentiate Without Color
> enabled and disabled."

Prior finding 4.2, unfixed and now encoded as a gate. **Correction:** "…every marker except
the keyboard focus ring, a platform affordance that never carries game state…".

### 4.6 "The board shows the position … and nothing else" strands the draw-claim affordance. **should-fix**

> Line 209: "The board shows the position and the states of the position, and nothing else.
> Anything the interface must say that is not a fact about the position … is said by the
> turn-status element instead"
>
> Line 241: "The element carries **the two** board-state messages that are not facts about
> the position: the transient save-failure capsule, and the acknowledgment beat"
>
> Accepted, line 321: "the same still-valid claim is exposed through a non-blocking
> **可判和** affordance"

The new principle excludes 可判和 from the board; line 241's "the two" reads exhaustively
and excludes it from the turn status. Its placement was already open ("Resolve how the
non-dismissible result card, the retained draw-claim affordance … fit the stacked layout's
remaining space"), and this PR silently narrows the remaining options without saying so.

**Correction:** say "the two *transient* board-state messages", and add one clause noting
that the persistent 可判和 affordance's placement remains open.

### 4.7 The 将军 token has no anchor in replay or after a result. **should-fix**

> Line 240: "While the side to move is in check, a **将军** token **accompanies the
> side-to-move line**"
>
> Accepted, line 244: "History replay uses a separate move-progress and playback state
> **rather than describing the position as a human or AI turn**."

In replay there is no side-to-move line, so a replayed check position has no token, and the
accessibility argument for it — "gives a screen-reader user one stable place to re-read the
fact" — lapses exactly where the move list is being stepped. The same gap exists after a
confirmed result. In replay the general is never held, so the rings are always visible and
nothing breaks *visually*; the omission is in the stated lifetime ("for exactly as long as
check persists") and in the accessibility channel. `testing.md` now gates that lifetime.

### 4.8 The marker-ink reference surface is wrong for several routine states. **should-fix**

> "**active ink**, at a contrast of at least 4.5:1 **against that style's board surface**"

Markers are frequently not drawn on the bare board surface: over the pointer hover fill
(which the layering puts beneath them), over 传统's "soft resting shadow", and under the
lift shadow, which `Piece styles` says every held piece casts and which the Layering line
puts above the ring layer. Prior finding 4.3, unfixed. **Correction:** state the measurement
surface, or require the ratio to hold against the board surface *and* against the hover fill
composited over it.

### 4.9 `Board metrics` states the floor without the accepted exception. **should-fix**

> Line 112: "**The accepted floor is `p ≥ 44 pt` on every platform**, fixed under [Layout
> shapes](#layout-shapes) below."
>
> Line 441: "One exception: a pre-start board is a noninteractive preview with no touch
> targets, so **it carries no size floor**"

Flat contradiction on the cross-reference. Downstream (prior finding 1.12, unfixed): at the
accepted `0.50 p` symbol, the preview's characters fall below Apple's iOS/macOS minimum text
size (11 pt / 10 pt, HIG *Typography › Ensuring legibility*) as soon as `p < 22 pt`, which
the preview permits. `testing.md:58` still requires the preview to "shrink as needed so the
setup controls always fit."

**Correction:** "…on every interactive board; the pre-start preview's exemption is below,"
plus a separate symbol floor for the preview.

### 4.10 Everything else checks out. **verified clean**

`Piece styles`, `Piece symbols`, `Accessibility`, and `Move input` are consistent with the
new text. `Natural result presentation`'s "the final board remains fully visible" agrees
with "The board is never dimmed … after a result is confirmed." `Motion`'s "An AI move …
leaves persistent origin and destination markers" agrees with the brackets. The
`0.50 p` symbol em fits inside the `0.80 p` disc (half-diagonal `0.354 p` < `0.40 p`).

**nit** — three terms for one element: "file numbers" (138, 476), "file numerals" (437),
"the numeral strips" (476).
**nit** — line 143 still says the board's design "must cover" states the new section now
covers normatively; line 199 was not given the cross-reference its neighbour line 198 got.

---

## 5. Document-status discipline

`MiniXiangqi/AGENTS.md`: "In a living target contract, content outside `Need to discuss` is
accepted intended behavior"; "`Need to discuss` is always non-normative and does not
authorize implementation choices." Corner brackets and the 将军 token are taken as
legitimately accepted per the PR body's owner confirmation.

### 5.1 Newly accepted, not shown to be decided

| Newly accepted | Why it needs routing |
|---|---|
| **无法保存这一步，请重试。** | New normative Chinese copy. `Localization`: "the accepted user-facing copy in this document is normative." Not among the two items the PR body says were confirmed. See §4.3. **blocking** for the contradiction; **should-fix** for the provenance. |
| "the same lightest feedback as an illegal tap" for unavailable input | A new haptic binding while "Define the haptic events behind the accepted haptics toggle" is open. `Sound and haptics` assigns the lightest tick only to the illegal-square case. **should-fix** |
| "In replay … a tap on it does nothing at all — no beat and no feedback" | Sits directly against accepted line 148, "Clear prevention or explanation of unavailable actions." Defensible, but it is a decision, not a derivation. **should-fix** |
| "All strokes use rounded caps" | Materially changes the capture ring's duty cycle (§1.7) and belongs with the open style/motion value work. **nit** |
| Piece symbol pinned at `0.50 p`, never scaling | A Dynamic Type decision while `Accessibility` lists "Dynamic Type and text legibility" and "Define accessibility acceptance criteria" is open. Defensible (characters are game content) but unrouted. **nit** |
| Keyboard focus ring geometry and "the platform's focus colour" | `Accessibility` still says only "must consider"; neither Increase Contrast nor Differentiate Without Color appears in that section even though this PR makes both normative. **should-fix** |

### 5.2 Removed from `Need to discuss` but not fully resolved. **should-fix**

- "Define the exact visual treatment for selection, legal destinations, captures,
  illegal-square feedback, **save-failure feedback**, and unavailable input" — the
  save-failure sub-item is contradictory for the AI-reply case (§4.3). Everything else in
  that item is genuinely closed.

### 5.3 Narrowed without saying so. **should-fix**

- Old: "Decide whether file numbers may be hidden, and **define the visual system for them
  and for typography**."
- New: "Decide whether file numbers may be hidden, and define **the numeral strips'**
  geometry, typography, and contrast requirement, together with the grid and palace-diagonal
  stroke weight…"

Typography for the move list, the turn status, the result card, and game metadata was in the
old item and is in neither the new item nor the accepted text. It is now unowned.

### 5.4 Correctly handled

The new item "Decide whether a pointer previews a piece's legal destinations on hover" is
correctly distinguished from the accepted hover *fill* — the fill reports position, the
preview would report legality. "the 将军 token's form" was correctly added and "transient
announcements" correctly narrowed to "remaining transient announcements". The `Need to
discuss` preamble is intact.

---

## 6. Completeness

### 6.1 Illegal-tap feedback disappears entirely under Reduce Motion where haptics are unavailable. **BLOCKING**

> "**Illegal tap.** **No board mark.** With a piece selected, **its legal-destination
> markers pulse once** … Either way **the platform's lightest selection-weight feedback
> fires**"
>
> Accepted, `Motion`: "With Reduce Motion, the animation of lifts, springs, **pulses**, and
> long-distance travel is **removed** in favor of a brief crossfade or immediate state
> update. **The states themselves remain**"
>
> Accepted, `Sound and haptics`: "Haptics are available only where the hardware provides
> them; on a device without them **the toggle is unavailable** rather than silently
> ineffective, and **no substitute effect is invented**." … "[Sound and haptics] **must
> never be the only way information is conveyed**."

The designed response is a pulse plus a haptic. Reduce Motion removes the pulse, and unlike
every other pulse in the vocabulary there is no underlying state left behind — the pulse
*is* the entire response, because the PR deliberately removed the board mark. On a Mac
(no haptics; no substitute permitted) with Reduce Motion enabled, **an illegal tap produces
no visual, haptic, or state feedback whatsoever.** With nothing selected the turn-status
beat survives (it is opacity-only, "with no movement"), but the selected-piece case — the
learner's most common interaction, and the one the design is explicitly optimising for —
degrades to silence.

`Accessibility` requires "Alternatives for information otherwise communicated through sound,
haptics, or animation." There is none here.

**Correction:** give the destination markers a non-animated Reduce Motion form of the same
response — e.g. *"Under Reduce Motion the legal-destination markers change state once rather
than pulsing (record ink to active ink, or a one-step size change held briefly), so the
answer is delivered without animation."* — and add a `testing.md` gate for it.

### 6.2 States the contract requires with no marker and no stated home

| State | Required by | Status after this PR |
|---|---|---|
| Claimable draw / 可判和 | accepted line 321; "claim availability when applicable" in Play metadata | No board marker, and now excluded from both the board and the turn status's enumerated "two" messages. §4.6. **should-fix** |
| Game result | accepted line 146: the design "must cover … game result states" | No board marker; handled off-board by the result card. Consistent with the new principle, but the section never says so, while it does say so for the two failure states. **nit** — add it to "Two states deliberately have no board marker." |
| Check during replay | 将军 token's stated lifetime | Rings show; token has no anchor. §4.7. **should-fix** |
| Last move during replay navigation | `History replay` controls | Bracket behaviour ambiguous. §2.3. **should-fix** |
| Pointer hover during replay | `Pointer hover` is unconditional | "a tap on it does nothing at all" governs taps only; whether the hover fill draws on a read-only board is unstated. **nit** |
| Pre-start preview at `p < 44` | accepted line 441 | Contradicts the metrics floor; symbol falls below the platform text minimum. §4.9. **should-fix** |
| Board during an Undo reversal | `Motion`'s 250/600 ms budgets | Brackets unspecified mid-transition. §2.4. **should-fix** |

### 6.3 One signal, two meanings. **should-fix**

> "**Illegal tap** … With nothing selected, the turn status gives **the acknowledgment beat
> described below**."
>
> "**Unavailable input** is answered by an acknowledgment beat on the turn-status element"

A tap on an empty point with nothing selected (input *is* available; the tap simply means
nothing) produces the identical signal to a tap while the AI is thinking (input is *not*
available). The section's own opening principle is that the board should not "be read for
two kinds of information at once"; this does the same to the turn status. `testing.md` now
encodes both. **Correction:** distinguish them, or state explicitly that one beat covers
both and why.

### 6.4 The drag's drop target is still undefined. **should-fix** (unfixed from prior 2.12)

> "follows the touch or pointer **directly**. On touch platforms it is **offset `0.5 p`
> above the touch point** … While the drag is **within `0.45 p` of a legal point**, that
> point strengthens"

"Directly" and "offset `0.5 p`" are different statements, and nothing says whether the
`0.45 p` proximity test and the drop target are measured from the finger or from the offset
disc. With a `0.5 p` offset the disc visually covers the point one row *above* the one the
finger is on, so the two readings differ by a whole cell. A `0.5 p` upward offset also
carries the disc into or past the half-cell margin when dragging along the top rank.
`Move input` fixes only that "Dropping on a legal destination commits the move." This is the
gap that produces two different implementations on iOS and iPadOS.

---

## Summary of findings

**Blocking (4)**

1. §1.1 — The air-gap rule "Every game-state marker lives at `0.42 p` or beyond" is false
   for four of the eleven markers, and the new `testing.md` gate "no marker's ink falls
   inside `0.42 p`" cannot be passed. Substantively, the keyboard focus ring's inner edge
   (`0.41 p`) overlaps the ×1.05 lifted disc (`0.42 p`) by 0.44 pt, clipping the disc
   boundary that `Piece styles` makes load-bearing.
2. §1.2 — The check pulse's magnitude is unspecified, and the two rings sit exactly on both
   structural limits, so any symmetric pulse violates one of them. `testing.md` names the
   check pulse as a gate.
3. §4.3 — **无法保存这一步，请重试。** contradicts the accepted rule that the app never asks
   the user to retry a failed AI reply.
4. §6.1 — Illegal-tap feedback vanishes completely under Reduce Motion on hardware without
   haptics, violating "must never be the only way information is conveyed."

**Should-fix (20)** — §0.1 PR scope misdescribed; §1.3 dragged ring `0.5005 p` and scale
declared adjustable; §1.4 focus-ring exemption load-bearing in four pairings; §1.6 adjacent
brackets 0.66 pt apart; §1.7 round caps cut the dash gap to 1.93 pt; §1.8 shape-family count
and non-confusability false; §1.9 detached disc contradicts the containment sentence; §2.2
capture/check impossibility rests on an engine-falsifiable reason; §2.3 replay brackets;
§2.4 brackets during Undo reversal; §2.5 Free-Play voice; §3.2 "most constrained
configuration"; §3.3 "never forces the window to fill the screen"; §4.4 three stale `Motion`
bullets plus `Sound and haptics`; §4.5 Differentiate Without Color vs the hue-carrying focus
ring; §4.6 可判和 stranded; §4.7 将军 token in replay; §4.8 marker-ink reference surface;
§4.9 floor stated without the preview exception; §5.2/§5.3 premature removal and silent
narrowing in `Need to discuss`; §6.3 one beat, two meanings; §6.4 drag drop target.

**Nits (9)** — §1.10 (three), §3.4 "the sizes above", §4.10 three terms for the numeral
strip and two un-updated lines, §5.1 rounded caps and Dynamic Type, §6.2 result state not
listed among the deliberately unmarked states, §1.7 dash phase.

---

## Verdict

**DO NOT MERGE**

The core of this PR is sound and it genuinely fixes every blocking defect the prior review
found. The four blocking items are all cheap. The shortest set of changes that would make it
mergeable:

1. **Restate the air-gap rule** so it binds only markers on an occupied point, and either
   move the keyboard focus ring to a `0.92 p` square with `0.04 p` stroke (band
   `[0.44, 0.48]`) or grant it an explicit, written exemption. Amend the matching
   `testing.md` line.
2. **Bound the check pulse** — thicken each ring to at most `0.0325 p`, growing only into
   the gap between them.
3. **Scope the save-failure capsule** to the user's own actions and state what, if anything,
   appears when the AI reply's save fails. Add the `testing.md` gate for the new string.
4. **Give the illegal-tap response a Reduce Motion form** that is not an animation.

Everything else in the should-fix list can follow in a subsequent change, but §1.6
(0.66 pt between adjacent bracket sets), §2.3 (replay brackets), §3.3 (the overstated
affordability conclusion), and §4.4 (`Motion`'s "persistent king-square treatment") are
cheap enough that they are better done now, while the section is open.
