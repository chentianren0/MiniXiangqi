# Verification — `board-visual-language-design.fable-partial.md` §§1–2.6

> **Status: Workspace-only verification report. Non-normative.**
>
> Adversarial check of the abandoned partial draft at
> `/Users/tianren/coding/minixiangqi/discussion-drafts/board-visual-language-design.fable-partial.md`
> (sections 1 through 2.6) against the accepted contract in
> `/Users/tianren/coding/minixiangqi/MiniXiangqi/docs/interaction-design.md`,
> `docs/xiangqi-rules.md`, `docs/product.md`, `docs/game-data.md`, and the approved
> fixtures in `MiniXiangqi/fixtures/rules/`. Nothing in the product repository was
> read-modified; no remote operation was performed.
>
> Reproduction scripts (workspace-only scratch):
> `discussion-drafts/v-geom.py` (all arithmetic and collision geometry),
> `discussion-drafts/v-rules.py` and `discussion-drafts/v-line.py`
> (engine probes against the prebuilt `pyffish` in `discussion-drafts/r-scratch/`).

**Conventions used here.** `p` = cell pitch. All radii are measured from a point's
centre. A stroke of width `w` on a centre-line radius `r` occupies the band
`[r − w/2, r + w/2]`; the draft uses this convention for S1, S3 and S6 and states
it explicitly for those three. Floors are `p = 44` (iOS/iPadOS) and `p = 28`
(macOS), per `interaction-design.md § Layout shapes`.

**Summary of severity counts:** 6 blocking, 17 should-fix, 11 nits.

---

## 1. Arithmetic

### 1.1 What is arithmetically correct (verified, no action needed)

Recomputed at both floors; every one of these matches the draft:

| Draft value | Recomputed p=44 | Recomputed p=28 | Verdict |
|---|---|---|---|
| Disc `0.84 p` → 37.0 / 23.5 | 36.960 | 23.520 | correct |
| Symbol `0.50 p` → 22.0 / 14.0 | 22.000 | 14.000 | correct |
| Board core `7 p` → 308 / 196 | 308.000 | 196.000 | correct |
| Disc edge 0.42 p, cell boundary 0.50 p, neighbour disc edge 0.58 p, cell corner 0.707 p | — | — | all correct |
| Working band `0.16 p` → 7.0 / 4.5 | 7.040 | 4.480 | correct |
| `0.02 p` air gap → 0.9 / 0.56 pt | 0.880 | 0.560 | correct |
| S1 stroke 0.05 p → 2.2 / 1.4 | 2.200 | 1.400 | correct |
| S2 dot Ø 0.22 p → 9.7 / 6.2 | 9.680 | 6.160 | correct |
| S3 stroke 0.06 p → 2.6 / 1.7 | 2.640 | 1.680 | correct |
| S3 band = 0.44 p … 0.50 p (outer edge exactly at the cell boundary) | — | — | correct |
| S4 arm 0.16 p / stroke 0.045 p → 7.0 / 2.0 and 4.5 / 1.3 | 7.040 / 1.980 | 4.480 / 1.260 | correct |
| S6 bands `[0.44, 0.48]` and `[0.52, 0.56]`, inter-ring gap 0.04 p → 1.8 / 1.1 | 1.760 | 1.120 | correct |
| S7 circle Ø 0.44 p → 19.4 / 12.3 | 19.360 | 12.320 | correct |
| S10 origin ring → 9.7 / 2.0 and 6.2 / 1.3 | 9.680 / 1.980 | 6.160 / 1.260 | correct |
| S12 square 0.94 p, stroke 0.06 p → 41.4 / 2.6 and 26.3 / 1.7 | 41.360 / 2.640 | 26.320 / 1.680 | correct |
| S1 lifted outer edge "≈ 0.51 p" | (0.4625 + 0.025) × 1.05 = **0.511875 p** | — | correct |
| S1 lifted centre-line "≈ 0.486 p" (§2.4) | 0.4625 × 1.05 = **0.485625 p** | — | correct |
| S10 hysteresis "0.1 p" (0.45 → 0.55) | — | — | correct |
| S10 strengthened dot "a 1.5× step" (0.22 → 0.33) | — | — | correct |

**S3 dash arithmetic — the draft is right, contrary to what a quick read suggests.**
`12 × (18° + 12°) = 360°` exactly. At centre-line radius `0.47 p`:
dash arc `= 0.47 × 18π/180 = 0.147655 p` → **6.497 / 4.134 pt**, matching the
draft's "≈ 6.5 pt / 4.1 pt" (§2.2) and "6.5 … / 4.1 …" (§2.3);
gap arc `= 0.47 × 12π/180 = 0.098437 p` → **4.331 / 2.756 pt**, matching §2.3's
"4.3 pt" and "2.7 pt". §2.2 and §2.3 are mutually consistent and both are correct.
(But see finding 1.6 — round caps are not accounted for.)

**S2 + S4 nearest approach (§2.4) — true, and understated.** Bracket corner vertex
at `(0.47, 0.47) p`, arm inner endpoint at `(0.31, 0.47) p`, nearest centre-line
radius `0.5630 p`, nearest ink radius `0.5405 p`; minus the dot's `0.11 p` edge gives
a nearest approach of **0.4305 p**, not merely "> 0.3 p". Correct but loose.

---

### 1.2 Findings

**Finding 1.1 — The justification for the keystone number (0.84 p) is false. BLOCKING.**

> Draft (§1): "At 0.86 p the check ring's outer edge collides with the neighbouring
> disc at the macOS floor."

Untrue, twice over.

*First*, the arithmetic. With a `0.86 p` disc the disc edge is at `0.43 p` and the
nearest neighbouring disc edge at `1.00 − 0.43 = 0.57 p`. The draft's own S6 outer
edge is `0.54 + 0.02 = 0.56 p`. `0.56 < 0.57` — there is **no collision**; there is
`0.01 p` of clearance (0.44 pt at p=44, 0.28 pt at p=28).

*Second*, the appeal to "at the macOS floor" is a category error. Every quantity in
this chain is expressed in `p`, so containment is scale-invariant: if `0.56 p` fitted
inside `0.57 p` at one pitch it fits at every pitch. A pitch-dependent collision is
impossible in a purely `p`-relative system.

**The correct derivation of 0.84 p, which the draft should use instead.** The binding
constraint is on the *inside*, not the outside. §1's own separation rule puts the
innermost marker edge at `0.44 p` and demands a `≥ 0.02 p` air gap, which forces the
disc radius `≤ 0.42 p`, i.e. **diameter ≤ 0.84 p**. That derivation is exact, is
scale-invariant, and yields the same number. At `0.86 p` the air gap would collapse to
`0.01 p` = 0.28 pt at the macOS floor (0.56 device px at 2×) — sub-pixel, which is the
real reason to reject it. *Correction: replace the sentence with the inner-gap
derivation and drop "at the macOS floor".*

**Finding 1.2 — S1's stated ring edges do not follow from its stated stroke, and the
correct edges break §1's own separation rule. SHOULD-FIX.**

> Draft (§2.2 S1): "stroke `0.05 p`, centre-line radius `0.4625 p` (inner edge
> `0.44 p`, outer `0.485 p`)"

`0.4625 ∓ 0.025` = **`0.4375 p` and `0.4875 p`**, not `0.44 / 0.485`. The quoted pair
is what you get from a stroke of `0.045 p` (`0.4625 ∓ 0.0225`), so the two halves of
the sentence describe different rings.

This is not cosmetic. §1's structural rule is "A marker's rings live outside it
(`≥ 0.44 p`), leaving an air gap of at least `0.02 p`." With the stated `0.05 p`
stroke the S1 inner edge is `0.4375 p` and the air gap is **`0.0175 p` = 0.49 pt at
the macOS floor** — the rule is violated by the first marker defined under it, and the
gap falls below §2.3's own "≈ 0.6 pt" floor (0.98 device px at 2×, i.e. under one
pixel). *Correction: either set the stroke to `0.045 p` (edges `0.44 / 0.485`,
air gap exactly `0.02 p`), or move the centre-line to `0.465 p` (edges `0.44 / 0.49`).
Do not leave both numbers.*

**Finding 1.3 — §2.3's blanket claim "every distinguishing gap stays at or above
≈ 0.6 pt" is false in at least five places. BLOCKING.**

Recomputed at `p = 28`:

| Gap | Value | pt at p=28 | Passes "≈ 0.6 pt"? |
|---|---|---|---|
| S3 dash gap (arc only) | 0.098437 p | 2.756 | yes |
| S6 inter-ring gap | 0.040000 p | 1.120 | yes |
| §1's nominal `0.02 p` air gap | 0.020000 p | 0.560 | **marginal — 0.56 < 0.6** |
| S1's *actual* air gap (finding 1.2) | 0.017500 p | 0.490 | **no** |
| S1-under-lift to S6 outer ring (§2.4's "clear gap") | 0.008125 p | **0.227** | **no** |
| Brackets on two adjacent cells (finding 2.4) | 0.015000 p | 0.420 | **no** |
| S1 at rest to an adjacent cell's S3 ring (finding 2.2) | 0.012500 p | 0.350 | **no** |

The companion claim "Every stroke stays above 1 pt at the macOS floor" **is** true for
every stroke the table lists (smallest: S6 at 1.12 pt). *Correction: keep the stroke
claim; replace the gap claim with a per-gap table, and treat the three sub-0.6 pt
gaps as design defects, not as rounding.*

**Finding 1.4 — the file-numeral strip row is unverifiable and breaks the document's
own `p`-relative rule. SHOULD-FIX.**

> Draft (§1 table): "File-numeral strip (top and bottom, outside the core) | see §4.1
> | 16 each | 14 each"

§4.1 does not exist — the document ends at §2.6. Separately, `16 / 44 = 0.364 p` while
`14 / 28 = 0.500 p`, so the strip is a fixed point value, contradicting §1's premise
that "Every marker dimension is expressed in `p` so the vocabulary scales losslessly."
Its placement is at least contract-consistent (`interaction-design.md § Board geometry
and notation`: "File numbers are shown in the outer margin"; "Coordinates sit outside
that margin"). *Correction: either give the strip in `p` or state explicitly that it
is the one fixed-pt dimension and say why.*

**Finding 1.5 — dangling forward references throughout §§1–2.2. NIT (structural).**

§3.4, §3.5, §3.6, §4.1 and §6 are all cited and none exist. Six load-bearing values
(the compose beat, the check pulse, the ✕'s 480 ms, the numeral strip, and the
"where I think the contract is wrong" list) are therefore unverifiable. This is
expected of an abandoned draft but must be closed before review.

**Finding 1.6 — round caps are specified and then ignored in every dash/gap number.
SHOULD-FIX.**

> Draft (§2.2 preamble): "All strokes use rounded caps."

A round cap extends each dash by `w/2` at both ends and eats the same from each gap.
With `w = 0.06 p` the S3 pattern actually renders as:

- visible dash `0.147655 + 0.06 = 0.207655 p` → **9.14 / 5.81 pt** (not 6.5 / 4.1)
- visible gap `0.098437 − 0.06 = 0.038437 p` → **1.69 / 1.08 pt** (not 4.3 / 2.7)

The gap shrinks by 61 %. §2.6's disambiguation argument leans on this number —
"the dash gaps are ≥ 2.7 pt at the macOS floor" — and the true figure is **1.08 pt**.
Still above 1 pt, so the conclusion survives, but the stated evidence does not.
*Correction: quote cap-adjusted dash and gap lengths, or specify butt caps for S3.*

**Finding 1.7 — S7's ✕ does not fit inside its own circle. SHOULD-FIX.**

> Draft (§2.2 S7): "circle Ø `0.44 p`, stroke `0.045 p`, with an ✕ of arm length
> `0.20 p` inside"

Circle band `= [0.1975, 0.2425] p`. An arm of length `0.20 p` from the centre reaches
`0.20 p`, which is already past the circle's inner edge at `0.1975 p`; with the
specified round cap the ink reaches `0.2225 p`, i.e. past the circle's centre-line.
The ✕ welds to the circle rather than sitting inside it. Maximum clear arm length is
`0.175 p` (tip ink at `0.1975 p`, tangent) — use `≤ 0.165 p` for a visible gap.
"Arm length" is also undefined (from centre, or total across); under the other reading
the ✕ is 0.20 p across inside a 0.44 p circle, which is a different mark.
*Correction: define "arm length" and set it to ≤ 0.165 p.*

**Finding 1.8 — S10's measurement convention silently differs from S1/S3/S6. NIT.**

§2.6 says "S2 vs S10-origin (filled vs hollow, same Ø) … the hollow's void is 3.6 pt".
That is `(0.22 − 2 × 0.045) × 28 = 3.64 pt`, i.e. `Ø 0.22 p` is read as the **outer**
diameter. S1, S3 and S6 are all specified by **centre-line** radius. Under the
centre-line reading S10's void would be 4.90 pt and its outer diameter `0.265 p`,
which breaks the "same Ø as S2" claim. The arithmetic is right for one reading only.
*Correction: state the convention once, in §2.2's preamble.*

**Finding 1.9 — "The 2 % of disc the board gives up". NIT.**
0.86 → 0.84 is 2.3 % of diameter but **4.6 % of area**. Harmless, but the visible
quantity is area.

**Finding 1.10 — "at 2× rendering is a full pixel" assumes Retina on macOS. NIT.**
macOS still drives 1× external displays, where `0.02 p` at the 28 pt floor is
**0.56 device px** and the seam disappears entirely. The claim should be scoped to
2× or the 1× case should be conceded.

**Finding 1.11 — the maximum simultaneous load is over-counted. NIT.**
> Draft (§2.4): "dots (S2, up to ~12) and capture rings (S3, up to ~4)"

No Mini Xiangqi piece has more than 12 destinations in total: a chariot on an open
7×7 reaches 6 + 6 = 12 squares, and a cannon's captures lie on the same two lines.
So dots + rings ≤ 12, never 16. Harmless as an upper bound, wrong as a worst case.

**Finding 1.12 — the macOS floor is *not* "the worst legal case everywhere".
SHOULD-FIX.**
> Draft (§2.3): "The macOS floor is the worst legal case everywhere in this table."

`interaction-design.md § Layout shapes` states an explicit exception: "a pre-start
board is a noninteractive preview with no touch targets, so it carries no size floor
and yields space to the setup controls whenever they need it." In the preview the
`0.50 p` symbol falls below Apple's minimum text size once `p < 22 pt` (iOS) or
`p < 20 pt` (macOS). No marker is drawn in the preview, so the marker table is safe —
but §1's symbol-legibility argument is not. *Correction: scope the symbol argument to
interactive boards and give the preview a separate symbol floor.*

---

## 2. Geometric collision proofs

### 2.1 The structural error behind most of this section

§2.4 proves *same-cell* pairings and never once checks **adjacent-cell** pairings.
That omission is fatal, because the containment test §1 actually performs — "does the
marker stay inside the neighbouring *disc* edge at `0.58 p`?" — is the wrong test. Two
adjacent cells' markers share the `0.16 p` band between the discs. For markers on
neighbouring points never to overlap, each marker's outer ink radius must be
`≤ 0.50 p` (half the pitch). Measured:

| Marker | Outer ink radius | ≤ 0.50 p? |
|---|---|---|
| S2 dot | 0.11 p | yes |
| S10 origin ring | 0.11 p | yes |
| S1 selection ring, at rest | 0.4875 p | yes (0.0125 p spare) |
| **S1 selection ring, under the ×1.05 lift** | **0.511875 p** | **no** |
| S3 capture ring | 0.50 p | exactly tangent |
| S12 focus square (at the four edge midpoints) | 0.50 p | exactly tangent |
| **S6 outer check ring** | **0.56 p** | **no — 0.06 p into the neighbour's cell** |
| S4 bracket (outermost) | ≈ 0.4925 p perpendicular | yes (0.0075 p spare) |

So two of the vocabulary's three ring markers escape their own cell, and two more sit
exactly on the boundary. Everything in §2.2 below follows from that.

**Finding 2.1 — S6's outer ring collides with an adjacent cell's S3 capture ring, in
one of the most common positions in the game. BLOCKING.**

S6 outer band is `[0.52, 0.56] p` from the general. A neighbouring cell's S3 ring
occupies `[0.44, 0.50] p` about *that* point, i.e. `[0.50, 0.56] p` from the general
along the line of centres. Overlap = **0.06 p** — 2.64 pt at p=44, 1.68 pt at p=28,
wider than either stroke. As circles: centres 1.0 p apart, radii 0.54 and 0.47,
sum 1.01 > 1.0, so they genuinely intersect.

Reachable, and not exotic — it is *capture the checker*, the first evasion any learner
tries. Verified against the engine:

```
FEN  3k3/r2P3/7/7/7/7/3K3 b - - 0 1
     Black general d7; Red soldier d6 (giving check); Black chariot a6; Red general d1
legal moves (all evasions): a6d6, d7c7, d7e7      # d7d6 is illegal: flying generals
```

Black is in check → S6 double ring on d7. Selecting the chariot on a6 shows the S3
capture ring on d6, the cell immediately below. The rings intersect.
*Correction: cap the S6 outer ring at `0.50 p` (e.g. centre-lines `0.455 p` and
`0.48 p` at stroke `0.03 p`, or collapse S6 to a single ring plus an inner keyline),
or state that adjacent-cell ring overlap is accepted and design the crossing.*

**Finding 2.2 — the S1 selection ring under the ×1.05 lift overlaps an adjacent cell's
S3 capture ring. BLOCKING.**

S1 lifted outer edge `= 0.4875 × 1.05 = 0.511875 p`; the neighbouring S3 ring's near
edge is at `1.00 − 0.50 = 0.50 p`. Overlap **0.011875 p** (0.52 pt at p=44, 0.33 pt at
p=28). Even *at rest* the clearance is only `0.0125 p` = **0.35 pt at the macOS floor**,
below §2.3's own ≈ 0.6 pt floor.

This is the single most frequent composition in the app: select a piece that can
capture something standing next to it. Verified trivially —
`3k3/7/7/3p3/3P3/7/3K3 w - - 0 1`, Red legal moves include `d3d4`; selecting the Red
soldier on d3 lifts S1 there while S3 rings the Black soldier on d4.

§2.2 S1 explicitly checks the lifted ring against "the neighbouring disc edge at
`0.58 p`" and stops there — the neighbouring *marker* at `0.50 p` is never considered.
*Correction: bound the lifted S1 ring by `0.50 p`, i.e. centre-line ≤ `0.4524 p` at
stroke `0.045 p`; or do not scale the ring with the disc.*

**Finding 2.3 — §2.4's "S3 + S4 geometrically disjoint" is CORRECT. (verified)**

Bracket corner vertex `(0.47, 0.47) p`, arms running inward 0.16 p, stroke 0.045 p.
Nearest bracket ink to the point centre = `hypot(0.31, 0.47) − 0.0225 = 0.5405 p`.
S3's outer edge is `0.50 p`. Disjoint, with **0.0405 p** clearance (1.78 / 1.14 pt).
The claim also survives the alternative reading in which the arms lie on the cell
boundary rather than 0.03 p inside it (nearest ink `0.566 p`). No action.

The draft's parenthetical "(from `0.707 p` inward by `0.16 p` along the edges)" omits
the `0.03 p` inset and is therefore not the geometry it just specified — cosmetic.

**Finding 2.4 — brackets on two adjacent cells nearly merge, and the inset is
ambiguous. SHOULD-FIX.**

Under the natural reading (whole bracket inset `0.03 p` inward from the cell
boundary), a cell's right-hand arms sit at `x = +0.47 p` and the neighbouring cell's
left-hand arms at `x = +0.53 p`: two parallel strokes of `0.045 p` with a
**`0.015 p` = 0.42 pt** ink gap at the macOS floor, overlapping in `y`. Under the other
reading (arms lying on the cell boundary) the two cells' arms are **coincident**.

Adjacent origin/destination is not an edge case: every general move and every
non-sideways soldier step produces it, and soldiers are five of each side's twelve
pieces. *Correction: fix the inset convention and either increase the inset to
`≥ 0.05 p` or specify what two adjacent bracket sets do.*

**Finding 2.5 — S4's corner vertex lands exactly on a palace diagonal. NIT.**

The bracket elbow is at `(±0.47, ±0.47) p`, i.e. on the 45° line through the point.
On the eight palace points that carry a diagonal, the diagonal runs straight through
the elbow. §2.6 argues S4 is unconfusable because "the palace diagonals … are
full-cell diagonals … not corner Ls" — true in isolation, but they are superimposed
here. Worth one sentence.

**Finding 2.6 — the S1 + S6 composition rule's "clear gap" is 0.23 pt. BLOCKING.**

> Draft (§2.4): "the selection ring (attached, 0.4625 p → ≈ 0.486 p under lift) sits
> inside it with a clear gap."

The `0.486 p` figure is the *centre-line* under lift; the outer **edge** is
`0.511875 p`. The outer check ring's inner edge is `0.52 p`. Gap =
**0.008125 p = 0.357 pt at p=44 and 0.227 pt at p=28** (0.45 device px at 2×). It is
not a clear gap; the two rings will read as one thick ring at the macOS floor.

Worse, this defeats S1's stated purpose. Unselected, a checked general shows rings at
centre-lines 0.46 / 0.54 with a 0.04 p gap. Selected with the inner check ring hidden,
it shows rings at 0.486 / 0.54 with a 0.008 p gap — geometrically the *same* double
ring, differing only in that the gap has closed and the inner stroke is 31 % thicker.
Since §2.2 S1 asserts "scale and shadow alone must never carry selection", the one
composition where that matters most is the one where the ring stops carrying it.
*Correction: with the general selected, hide **both** check rings and re-express check
some other way, or shrink the lifted S1 ring (finding 2.2) so the gap is ≥ 0.03 p.*

**Finding 2.7 — "S11/S12 + anything … no shared geometry" is false three times.
SHOULD-FIX.**

S12's `0.94 p` square with a `0.06 p` stroke occupies, at each of the four edge
midpoints, exactly the band `[0.44, 0.50] p` — **byte-for-byte the S3 capture ring's
band**. The inscribed circle and the square coincide at four tangent points, both
0.06 p wide there.

- **S12 + S3**: keyboard focus on a capturable enemy piece. Identical annulus.
- **S12 + S6**: keyboard focus on your checked general. The S6 outer ring at 0.54 p
  crosses the square boundary where `cos θ = 0.47/0.54`, i.e. at **θ = ±29.5°** from
  each side normal — **8 crossings**.
- **S12 + S1**: keyboard-selecting a piece. S1's lifted outer edge `0.5119 p` crosses
  the square outline.
- **S12 + S11**: pointer hovering the focused point. S11's fill half-extent is
  `0.45 p`, past S12's inner edge at `0.44 p`. (Harmless — S11 is layer 2, S12 layer 6
  — but it is shared geometry.)

All four are ordinary macOS/iPad Full Keyboard Access states.
*Correction: shrink S12 to `0.88 p` (band `[0.41, 0.47]`) so it clears both the disc
and every ring, and replace §2.4's one-line dismissal with the actual analysis.*

**Finding 2.8 — the z-order's "the geometry already guarantees no overlap" is false.
BLOCKING.**

Findings 2.1, 2.2, 2.6 and 2.7 are all overlaps. Two more, from §2.2 itself:

- **Layer 7's lift shadow** is defined as "cast on everything below", which includes
  every layer-6 ring on neighbouring cells. That is an intended overlap, so the
  sentence is simply wrong as written.
- **The dragged disc** is at scale ×1.10 (radius `0.462 p`) *and* offset `0.5 p` above
  the touch on touch platforms, so it is centred on a cell boundary and covers parts
  of two cells' markers by construction.

The *conclusion* the z-order draws (rings above discs so a neighbouring disc cannot
clip a ring) is sound; the justification is not. *Correction: state that z-order is
the only guarantee, because geometry is not one.*

**Finding 2.9 — S7 lands inside the disc face, contradicting §1's separation rule and
§2.6's symbol-independence argument. BLOCKING.**

S7's circle has radius `0.22 p`, entirely inside the disc's `0.42 p`. §2.4 says the ✕
"may momentarily overlay a bracket cell or **an occupied point**, which is correct".
§2.6 then concludes: "markers never touch the disc face, so 汉字 versus 图标 changes
nothing in this section." Both cannot hold. An illegal tap on an occupied point is
routine — tapping an enemy piece that is not a legal capture is exactly the learner's
question S7 exists to answer.

S7 also violates §1's own rule that "A marker's rings live outside it (`≥ 0.44 p`)".
*Correction: either exempt S7 from the separation rule explicitly and re-scope §2.6's
symbol-independence claim to the resting vocabulary, or enlarge S7 so it rings the
disc rather than covering it.*

**Finding 2.10 — S10's "target strengthening" breaks two stated invariants.
SHOULD-FIX.**

> Draft (§2.2 S10): "its S3 ring's stroke thickens to `0.08 p`"

At centre-line `0.47 p` a `0.08 p` stroke gives the band `[0.43, 0.51] p`. That
(a) puts the outer edge **past the cell boundary**, destroying "Two adjacent
capturable pieces' rings meet tangentially … and never overlap"; and (b) puts the
inner edge at `0.43 p`, i.e. `0.01 p` from the disc — violating the `≥ 0.44 p` /
`0.02 p` separation rule. *Correction: thicken inward only (centre-line to `0.46 p`,
band `[0.42, 0.50]`) — or better, thicken outward is impossible here, so grow the
dash length instead.*

**Finding 2.11 — S3's dash phase is unspecified, and two tangent rings can meet
dash-to-dash. NIT.**
Two adjacent capture rings are tangent at the cell boundary (verified: outer edges
`0.50 + 0.50 = 1.00 p`). If both rings phase a dash onto the connecting line, the two
0.06 p strokes touch and read as one 0.12 p blob. *Correction: fix the dash phase
(e.g. a gap centred on each cardinal direction).*

**Finding 2.12 — the drag offset is not reconciled with the drop target. SHOULD-FIX.**
S10 says the disc "follow[s] the touch or pointer 1:1" and then that it is "offset
`0.5 p` above the touch point" — those are different statements. Nothing says whether
the drop target, or the "within `0.45 p`" strengthening test, is measured from the
finger or from the offset disc. A `0.5 p` upward offset also pushes the disc into (or
past) the half-cell margin when dragging along the top rank.
`interaction-design.md § Move input` fixes only that "Dropping on a legal destination
commits the move" — which point that is remains open, and this is exactly the kind of
gap that produces two different implementations on iOS and iPadOS.

---

## 3. Rules claims

Method: the accepted rules contract (`docs/xiangqi-rules.md`), the approved fixtures
(`fixtures/rules/`, sixteen fixtures; `mx-end-003` pins flying-general rejection,
`mx-move-006` pins a check position whose legal set is exactly its evasions), the
archive contract (`docs/game-data.md`), plus engine probes with the workspace's
prebuilt `pyffish` on the built-in `minixiangqi` variant. Engine output is corroborating
evidence only; the reasoning below stands on the contract.

### 3.1 Claim (a) — "S3 + S6 cannot occur"

> Draft (§2.4): "**S3 + S6** — a capture ring around a checked general: **cannot
> occur.** A general is never a legal capture target (a position where the general
> could be taken is already illegal under the accepted movement rules), so the dashed
> ring and the double ring never share a disc."

**Verdict: the conclusion is TRUE. The stated reason is weaker than the real one, and
one clause of it is engine-falsifiable. SHOULD-FIX (reasoning), not blocking.**

The conclusion holds for a reason the draft does not give and that survives more
routes: **S6 is drawn on the side-to-move's own general, and S3 is drawn on an enemy
piece.** Only the side to move can be in check in any position reachable by legal play
(a move leaving your own general attacked is illegal), so the checked general always
belongs to the mover, while a capture target never does. The two therefore cannot
share a disc even if a general were capturable. This argument is immune to Free Play
(the side to move still owns the checked general), to Undo, to discovered check, and
to replay in both directions.

Routes checked exhaustively:

| Route | Result |
|---|---|
| Normal play | safe — checked general is the mover's; S3 targets are the opponent's |
| Free Play (one person, both sides) | safe — "side to move" is still well defined; moves still commit through the legal-move boundary (`interaction-design.md § Move input`) |
| After Undo (Free Play one ply; human-vs-AI one decision cycle; Undo during AI search) | safe — every reachable position is legal |
| Discovered check | safe — the discovering piece is the opponent's |
| A move by the checked side's own general | cannot leave that side in check |
| Flying generals | never yields a one-sided check (see 3.3) |
| History replay, stepping both directions | safe — all positions legal |
| Pre-start preview | noninteractive; no selection, so no S3 at all |
| Imported archives | `game-data.md`: "the initial position must be exactly the frozen starting FEN in version 1, every move must be legal in sequence" — no illegal position can enter |

**The clause that is wrong.** "a position where the general could be taken is already
illegal under the accepted movement rules" conflates *legality of the position* with
*generation of the move*. The move generator will happily produce it:

```
FEN  3k3/7/7/7/3R3/7/3K3 w - - 0 1     # Rd3 attacks kd7; RED to move (illegal position)
legal moves include d3d7                # capturing the general
```

The general is excluded by *reachability*, not by the movement rules. This matters:
the "cannot occur" invariant is only as strong as the guarantee that no illegal
position ever reaches the renderer. `game-data.md`'s **Need to discuss** already
anticipates the day that guarantee changes ("When a later archive version permits
initial positions other than the frozen start, define the setup-legality predicate
(one king per side inside its palace, piece-count bounds, **the side not to move never
attacked** including through the facing-kings rule)"). *Correction: restate the claim
as "S6 marks the side-to-move's general and S3 marks enemy pieces, so they cannot
share a disc" and add "this depends on every rendered position being legal, which
archive version 1 guarantees by freezing the start FEN".*

### 3.2 Claim (b) — "S4 + S6 cannot occur"

> Draft (§2.4): "**S4 + S6** — brackets on the checked general's cell: **cannot
> occur.** The checked side is the side to move; the last move was the opponent's; its
> origin is now empty and its destination holds the opponent's piece, so neither cell
> is the checked general's. This holds in Free Play and after Undo by the same
> argument, and for discovered check (the moved piece's cells are still the
> opponent's)."

**Verdict: FALSIFIED as written. BLOCKING.**

The argument is sound *given* a definition of "the last move" that the draft never
states — and the definition it does state produces a counterexample. §2.2 S4 says the
brackets are "**Persistent until the next ply replaces them**." An Undo is not a next
ply. Read literally, the brackets of the move you just took back stay on the board.

**Concrete construction, reachable in three plies from the frozen starting position
`rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1` (engine-verified):**

```
1. a2b2   d6d5
2. b1b7                  # Red cannon b1 x b7, screened by b2, checking kd7 through c7

P = rCnkncr/p1p1p1p/3p3/7/7/1PPPP1P/R1NKNCR b - - 0 2
    Black to move, IN CHECK. Legal moves: a7b7, d7d6 (exactly the evasions).

2. ...    d7d6           # Black escapes with a GENERAL move
Q = rCn1ncr/p1pkp1p/3p3/7/7/1PPPP1P/R1NKNCR w - - 1 3

Undo  →  back at P.
```

At `P`: Black is in check with its general on **d7** → S6 double ring on d7. The move
just undone was `d7d6`, whose **origin cell is d7** → under the draft's own
persistence rule, S4 brackets are still on d7 and d6. **S4 and S6 share the d7 cell.**

Every Undo variant the contract defines reaches it:

- Free Play — "removes one move per Undo action" → exactly the construction above.
- Human-vs-AI, Undo during search — "cancels the search and removes the human move
  that triggered it" → the human's general move is the removed ply; same result.
- Human-vs-AI, Undo after the AI replied — removes the AI reply *and* the preceding
  human move; if that human move was the general's check evasion, same result.
- Undo of a human move that reached a natural terminal state (contract:
  "Undo removes that human move while the result presentation remains unconfirmed") —
  if the mating move was a general step that discovered check, the general returns to
  the bracketed origin cell; if the human is in check there, same result.

The construction is not exotic. General-move check evasions appear three plies from
the opening: the search found three distinct 3-ply lines, all with `d7d6` as the only
general evasion.

**Under the *intended* reading — "brackets always show the current last move" — the
claim is TRUE**, by exactly the argument the draft gives, and it survives every route
I tested: normal play, Free Play, all four Undo forms, discovered check, a move by the
checked side's own general, replay stepping backwards and forwards (at every step the
board shows the position after ply *k* with ply *k*'s brackets), the flying-generals
rule (3.3), the pre-start preview (no last move, no check), and imports (start FEN
frozen). I could not construct a counterexample under that reading and believe none
exists.

*Correction (three separate edits):*
1. *Replace "Persistent until the next ply replaces them" with "S4 always marks the
   move that produced the currently displayed position; Undo and replay navigation
   move the brackets to the new last move, or clear them at the initial position."*
2. *Say what the brackets do during the Undo reversal animation, which
   `interaction-design.md § Motion` requires to complete within 250 ms per ply /
   600 ms per decision cycle — the old and new brackets otherwise coexist mid-transition.*
3. *Keep the impossibility claim, but derive it from the corrected persistence rule
   rather than asserting it "holds after Undo by the same argument".*

### 3.3 Claim (c) — "Two generals both in check: impossible position"

> Draft (§2.4): "**Two generals both in check**: impossible position; no rule needed."

**Verdict: TRUE for every position the app can display. SHOULD-FIX the justification.**

Two independent reasons:

1. **King safety.** After any legal move by side X, X's general is not attacked, so at
   most one general is attacked in any position reachable by legal play.
2. **The flying-generals rule is the only mutual attack, and creating it is always
   illegal for the mover.** `xiangqi-rules.md`: "The two kings may not face each other
   on an otherwise empty file; **they attack each other** through that file." Whoever
   clears or enters the file leaves their own general attacked. Engine-verified:

   ```
   FEN  3k3/7/7/3R3/7/7/3K3 w - - 0 1      # Kd1, kd7, Rd4 between them
   legal: d1c1 d1d2 d1e1 d4d2 d4d3 d4d5 d4d6 d4d7
   → every chariot move that would leave the d-file is absent.
   ```
   This is the behaviour `mx-end-003` pins ("rejection of moves that would leave the
   kings facing on an empty file").

The claim is safe *because* archive version 1 freezes the start FEN and validates every
move (`game-data.md § Accepted import limits and validation order`). "No rule needed"
is therefore true today but is an inherited assumption, not a self-evident one: the
same document reserves `derived` provenance for "a future start-from-position feature"
and defers the setup-legality predicate to **Need to discuss**. *Correction: say
"impossible in every position this app can display, because archive version 1 freezes
the initial position to the legal start and validates every move".*

### 3.4 A rules-adjacent wording problem the draft inherits

§2.2 and §2.6 are written entirely in human-versus-AI voice — "the **enemy** disc",
"**your** lifted piece", "a resting **enemy** piece", "selecting **your** checked
general". In Free Play "the same person controls both sides"
(`interaction-design.md § Turn status`), so there is no enemy and no *your*. The
geometry is unaffected; §2.6's disambiguator "S1 rings your lifted piece, S3 rings a
resting enemy piece" needs restating as "S1 rings the side-to-move's selected piece,
S3 rings a piece of the other side". **SHOULD-FIX.**

---

## 4. Contract consistency, ownership, and Apple citations

### 4.1 Contradictions of the accepted contract

**Finding 4.1 — two states are labelled "accepted" that the contract does not accept.
BLOCKING.**

`grep -c` over `interaction-design.md`: **"bracket" → 0 occurrences; "将军" → 0.**

- > §2.2 S4 heading: "*(accepted: corner brackets; geometry proposed)*"
  > §2.1: "The accepted contract already fixes several members (… **corner brackets
  > for the last move** …)"

  What the contract actually accepts is shape-neutral: "An AI move … leaves persistent
  origin and destination markers so the player can identify the completed move"
  (§ Motion), and "the last move" as a state the board interaction "must cover"
  (§ Board and game interaction). Corner brackets are a *proposal*. The contract's
  **Need to discuss** does not even list the last-move treatment among the open visual
  items, so mislabelling it as accepted would freeze an unreviewed shape.

- > §2.2 S6 heading: "*(accepted: persistent non-colour king-square treatment plus one
  > brief pulse, **and a token in the turn status**)*"
  > §2.1: "… check on the general **and in the status** …"

  The contract's only sentence on check is "Check uses a persistent, non-color-only
  king-square treatment plus one brief pulse. It does not flash continuously."
  (§ Motion, line 336). The turn-status contract enumerates the element's contents —
  side-to-move line, human/AI controller label, AI activity — and adds "The design
  does not add a separate, unrelated instruction". A 将军 token is a **proposal**, and
  the string 将军 appears nowhere in the accepted copy.

*Correction: demote both to "proposed"; every downstream argument that leans on them
(S6's "three channels", S1+S6's "the 将军 status token — which never hides — carries
the state") then needs its own justification.*

**Finding 4.2 — §1's "pixel-identical board" under Differentiate Without Color is
contradicted by S12 in the same draft. SHOULD-FIX.**

> §1: "Because the carrier is luminance and shape, never hue, the vocabulary passes
> Differentiate Without Color with zero conditional code — the correct result for that
> setting is a pixel-identical board."
> §2.2 S12: "in the platform focus colour (**the one marker that is deliberately
> hue-carried** …)"

Also, "the board" is not hue-free at all: 传统 puts the symbols in the Red and Black
role colours and 现代 fills the discs with them (`interaction-design.md § Piece
styles`). The claim is true of the *marker vocabulary minus S12*, and should say so.

**Finding 4.3 — the contract's contrast pair is misdescribed. SHOULD-FIX.**

> §1: "The two thresholds deliberately mirror the contract's own pair (symbol 4.5:1,
> disc boundary 3:1)"

The contract's two ratios are measured against **different surfaces**: "The symbol
reaches at least 4.5:1 against **its own disc face**" and "The disc's boundary … reaches
at least 3:1 against **the style's own board surface**". The draft's marker inks are
both measured against the board surface. The mirroring is rhetorical, not structural,
and a reviewer told to "measure every board element against one of two familiar gates"
will apply the wrong reference surface.

Related: several markers are *not* drawn on the board surface — S7's crossed circle
sits on a disc face (finding 2.9), and any marker may fall on S11's hover fill. Against
what is "active ink ≥ 4.5:1" then measured? **SHOULD-FIX.**

**Finding 4.4 — S8's proposed copy is wrong for one of the two accepted save-failure
cases. SHOULD-FIX.**

> §2.2 S8: proposed copy **无法保存这一步，请重试。**

The contract distinguishes two cases: (i) a *human* move or Undo whose save fails —
"the user may simply try again"; and (ii) "**When the failed save is the AI's reply**,
the game remains at the last committed position with the AI still to move, and the app
requests a new AI move **rather than asking the user to retry a move that is not
theirs**." One string that says 请重试 covers case (i) and directly contradicts case (ii).

**Finding 4.5 — S1's suppression claim overstates the contract. NIT.**

> §2.2 S1: "the lift shadow belongs to motion and may not be suppressed — accepted"

Contract: "it is never suppressed **by a style choice**, and Reduce Motion substitutes
an immediate change for the animated lift rather than removing the state." Also, the
contract reduces **resting** shadows under Increase Contrast; §2.2 S1's premise
"under Increase Contrast shadows weaken" extends that to the lift shadow without
saying so.

**Finding 4.6 — "the two floors" reads the contract's floor as the pitch. NIT
(interpretation, probably right).**
Contract: "a point of the grid is never smaller than 44 points on iOS and iPadOS …
nor smaller than 28 points on macOS". The draft equates that with the cell pitch `p`,
which is the natural reading (a point's tappable region is one pitch square) but is an
interpretation and should be stated as one — the whole vocabulary is denominated in it.

**Finding 4.7 — S11's translucent board marker sits against a contract preference.
NIT.**
Contract: "board-state markers must remain direct and readable rather than becoming
translucent decoration." S11 is "marker ink at **low opacity**". Defensible (it marks
the pointer, not a game state, and the draft says so) but should be argued explicitly.

**Finding 4.8 — the labelled board is not square. NIT.**
Contract: "The board is square and is sized to the largest square fitting both the
available width and the height". §1's `7 p` core is square, but with a numeral strip
top and bottom the drawn assembly is `7 p × (7 p + 2·strip)`. Consistent if "the
board" means the core, which the contract's "Coordinates sit outside that margin"
supports — but say so, because the floor derivation depends on which one is sized.

### 4.2 Decisions the draft takes that belong to another owner

Each of these is a legitimate proposal; the defect is that the draft states them
without routing them.

1. **Per-style "marker ink" values and their two strengths (§1).** The contract puts
   "Fix each piece style's concrete values — role colours and disc fills, ring weights,
   grid stroke, and its own board surface" in **Need to discuss**. The draft adds a new
   per-style, per-appearance value to that open set. (The draft does flag the
   `≤ 0.42 p` / `≥ 0.44 p` separation rule as something that "must be written into each
   style's value work" — good; the ink needs the same treatment.)
2. **Turn-status composition (§2.1 family 4, §2.2 S6/S8/S9).** A 将军 token, a
   save-failure capsule anchored to the status, and an "acknowledgment beat" on its
   background all add content to an element whose contents the contract enumerates and
   whose remaining design it defers ("Define the turn status's exact AI activity
   treatment, transient announcements, and VoiceOver behavior, and its placement within
   the side-by-side panel").
3. **New accepted-copy-shaped Chinese string (§2.2 S8).** Simplified Chinese is the
   source language and "the accepted user-facing copy in this document is normative".
   Proposing 无法保存这一步，请重试。 is a copy decision, not a geometry decision.
4. **Haptic event assignment (§2.2 S9).** Reusing the lightest selection tick for
   unavailable input is a new binding; the contract assigns the lightest tick only to
   the illegal-square case and defers the rest ("Define the haptic events behind the
   accepted haptics toggle").
5. **Silent no-op on replay taps (§2.2 S9).** "taps on it do nothing at all — no beat,
   no tick". The contract lists "Clear prevention or explanation of unavailable
   actions" among what the board's interaction design must cover, and defers
   "unavailable input" treatment to **Need to discuss**. Reasonable proposal, owner's
   call.
6. **Dynamic Type (§1).** The symbol is pinned at `0.50 p` and never scales. Piece
   characters are "game content, not interface text", which supports the choice, but
   Accessibility explicitly lists "Dynamic Type and text legibility" and the criteria
   are deferred ("Define accessibility acceptance criteria").
7. **VoiceOver behaviour used as a premise (§2.2 S5, S6).** "Authorship is carried by …
   the VoiceOver move announcement"; the status token "gives VoiceOver a stable place
   to re-read the fact". The board's VoiceOver interaction model is undecided
   (**Need to discuss**). Worse, S5's authorship fallback fails where it is most
   needed: in history replay the contract requires "a separate move-progress and
   playback state **rather than describing the position as a human or AI turn**", so
   the turn status carries no authorship there at all, and S5's "there is only ever one
   last move" leaves replay with no authorship channel. **SHOULD-FIX.**
8. **Glyph weight (§1).** "semibold, promoted to bold under Increase Contrast" is a
   typography decision inside the deferred "define the visual system for them and for
   typography"; note also that the contract's macOS observation is about "a uniform
   advance width" at "the matching weight", and a weight promotion can change metrics.

### 4.3 Apple documentation claims — each verified against the live documentation

Retrieved this session via `mcp__xcode__DocumentationSearch` (Xcode 27 beta
documentation set).

**A1 — HIG "Game controls › Touch controls", 44/28 pt.**
> Draft (§1): "The 44/28 pair matches Apple's own touch guidance: 'Make sure
> frequently used controls are a minimum size of 44x44 pt, and less important
> controls, such as menus, are a minimum size of 28x28 pt' (HIG 'Game controls ›
> Touch controls')."

**VERIFIED as a quotation; MISAPPLIED as an argument. SHOULD-FIX.**
Apple's sentence, in full: *"**Make sure controls are large enough.** Make sure
frequently used controls are a minimum size of 44x44 pt, and less important controls,
such as menus, are a minimum size of 28x28 pt to accommodate people's fingers."*
The quote is exact (the draft truncates "to accommodate people's fingers"). But both
numbers in that sentence are **iOS and iPadOS** — the section opens "For iOS and
iPadOS games…" — and they contrast *frequently used* against *less important* controls
on the same platform. The project's 44/28 pair contrasts *iOS* against *macOS*. The
numbers coincide; the guidance does not. Apple's actual per-platform table, in HIG
"Accessibility › Mobility", gives **macOS: default 28×28 pt, minimum 20×20 pt** — so
the project's macOS floor of 28 pt matches Apple's macOS *default control size*, which
is a better and genuinely available citation. *Correction: cite
"Accessibility › Mobility" for the macOS 28 and keep "Game controls › Touch controls"
for the iOS 44.*

**A2 — HIG "Typography › Ensuring legibility", 11 pt iOS / 10 pt macOS.**
**VERIFIED.** The page states: *"**Use font sizes that most people can read easily.**
… Follow the recommended default and minimum text sizes for each platform — for both
custom and system fonts …"* followed by a table giving **iOS, iPadOS: default 17 pt,
minimum 11 pt; macOS: default 13 pt, minimum 10 pt**. The section title and both
numbers are correct as cited. (The same table also appears in "Accessibility › Vision"
and in "Designing for games › Look stunning on every display".)

**A3 — HIG "Accessibility › Vision", contrast table.**
> Draft (§1): "(HIG 'Accessibility › Vision': 4.5:1 up to 17 pt, 3:1 at 18 pt+, 3:1
> bold at all sizes)"

**VERIFIED, with one word of drift. NIT.** The page states: *"**Strive to meet color
contrast minimum standards.** … Accessibility Inspector uses the following values from
WCAG Level AA as guidance …"* with the table **Up to 17 pts / All / 4.5:1**;
**18 pts / All / 3:1**; **All / Bold / 3:1**. Apple's row reads "18 pts", not
"18 pt+"; and the draft omits that these are WCAG Level AA values used by Accessibility
Inspector as *guidance*, not an Apple-authored threshold. The draft's use of the table
(noting that the accepted 4.5:1 for the symbol is stricter and therefore governs) is
correct.

**A4 — HIG "Accessibility › Vision", shape in addition to colour.**
> Draft (§2.1): "'Offer visual indicators, like distinct shapes or icons, in addition
> to color to help people perceive differences in function and changes in state'"

**VERIFIED — exact, word for word,** under *"**Convey information with more than color
alone.**"* on the "Accessibility › Vision" page.

**A5 — HIG "Motion › Best practices", gratuitous animation.**
> Draft (§2.2 S6): "('Gratuitous or excessive animation can distract people and may
> make them feel disconnected or physically uncomfortable')"

**VERIFIED — exact,** under *"**Add motion purposefully, supporting the experience
without overshadowing it.** Don't add motion for the sake of adding motion. Gratuitous
or excessive animation can distract people and may make them feel disconnected or
physically uncomfortable."* on "Motion › Best practices".

**A6 — HIG "Feedback › Best practices", can't-be-carried-out.**
> Draft (§2.2 S9): "'Show people when a command can't be carried out and help them
> understand why' — HIG 'Feedback › Best practices' *(carried from the survey's
> retrieval)*"

**VERIFIED — exact** (Apple uses a typographic apostrophe): *"**Show people when a
command can't be carried out and help them understand why.** For example, if people
request directions without specifying a destination, Maps tells them that it can't
provide directions to and from the same location."* on "Feedback › Best practices".
The "carried from the survey" hedge was unnecessary — the citation stands.

**No fabricated citations found.** All six Apple claims resolve to real pages with the
stated section headings; five are exact quotations and the sixth (A1) is an exact
quotation put to an argument the source does not support.

---

## 5. Assumptions only the product owner can settle

Listed in the order a reviewer would need to answer them; each is a real fork in the
design, not a wording question.

1. **Is the disc `0.84 p`?** Everything in §§1–2.6 is derived from it. The number is
   defensible, but only via the inner-air-gap derivation (finding 1.1), and it costs
   4.6 % of disc area against the survey's 0.86 p.
2. **May markers cross the cell boundary onto a neighbouring point?** This is the
   single decision that determines whether S6's double ring and the lifted S1 ring
   survive in their proposed form (findings 2.1, 2.2). "No" forces every ring to
   `≤ 0.50 p`; "yes" requires a designed crossing.
3. **Is check allowed to be hidden while the general is selected or dragged?** §2.4
   proposes hiding the inner ring on selection and both rings during a drag; the
   contract calls the treatment "persistent".
4. **Does the turn status carry a check token?** Not accepted (finding 4.1). Three of
   the draft's arguments depend on it existing.
5. **Are corner brackets the last-move shape?** Not accepted (finding 4.1). The
   adjacent-cell behaviour (finding 2.4) is a consequence of choosing them.
6. **What do the last-move markers do on Undo and on replay navigation?** Unspecified;
   the literal reading of §2.2 S4 falsifies §2.4's S4+S6 impossibility (finding 3.2).
7. **Is the illegal-tap mark allowed to cover a disc face?** §2.4 says yes, §2.6
   assumes no (finding 2.9).
8. **What is the drag drop target — the finger, or the offset disc?** (finding 2.12).
9. **Is the pre-start preview allowed to shrink the piece characters below Apple's
   minimum text size?** The contract removes the preview's floor; `0.50 p` symbols
   pass 11 pt only while `p ≥ 22 pt` (finding 1.12).
10. **The per-style marker inks, their two contrast strengths, and the reference
    surface they are measured against** — this belongs to the open piece-style value
    work, and the reference surface is currently ambiguous (finding 4.3).
11. **The save-failure copy**, and whether one string can serve both the human-move and
    AI-reply cases (finding 4.4).
12. **Whether replay taps are wholly silent** (finding 4.2 item 5) and how authorship of
    a replayed move is conveyed at all, given S5 has no fallback there (finding 4.2
    item 7).
