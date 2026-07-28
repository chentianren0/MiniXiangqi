# Pre-merge review, round 4 — PR #24, `design/frame-motion-glass`

Re-reviewed at `3ef8dc9` ("Revert the grid rounding rule the last fix introduced") against round 3
at `7f8c90a`, with a full regression pass over the net diff `main…3ef8dc9`.

---

## 1. Is the revert exactly a revert?

**Yes.** Diffing the round-4 grid sentence against the round-2 baseline (the last version before
the rounding rule was introduced):

| | Round 2 (`adde759`) | Round 4 (`3ef8dc9`) |
|---|---|---|
| rule | `0.026 p`, clamped 0.80–1.60 | `0.026 p`, clamped 0.80–1.60 ✅ identical |
| floor value | **1.14 points** | **1.14 points** ✅ restored |
| ceiling | *(absent)* | "reaching the ceiling from a pitch of about 62 points upward" |
| lower bound | "so it neither disappears at the floor" *(the false rationale)* | "The lower bound binds only if a smaller pitch is ever accepted" ✅ round-3's correct replacement kept |

`1.60 / 0.026 = 61.538`, so **"about 62" is correct** — it was always the unrounded figure, as you
say. "rounded to the nearest half point and" is gone; "and at the ceiling" became "reaching the
ceiling", which is the grammar the deletion forced and changes nothing. No other token in the
sentence moved. The only addition is the R3-2 sentence, checked separately below.

### The 一/grid invariant, re-run

Swept the whole supported pitch range in 0.01 pt steps, with `s = round(clamp(0.32 p, 13, 20))`
per round 4's new numeral rounding and the reverted unrounded grid:

```
minimum ratio 一 ÷ grid = 1.1218  at p = 45.31       — holds everywhere (floor 1.10)
```

That reproduces draft §4.8's stated worst case — "**一's stroke ÷ grid ≥ 1.10** (actual: 1.16 /
1.53, **worst case 1.12 at `p ≈ 45`**)" — to two decimal places, from the contract's own formulas
rather than from the draft's table.

The round-3 device table, re-run:

| Width | `p` | `s` | 一 semibold | grid | ratio | round 3 |
|---|---|---|---|---|---|---|
| **375 pt** | 49.00 | 16 | 1.510 | 1.274 | **1.186 ✅** | 1.007 ❌ |
| **390 pt** | 51.14 | 16 | 1.510 | 1.330 | **1.136 ✅** | 1.007 ❌ |
| **393 pt** | 51.57 | 17 | 1.605 | 1.341 | **1.197 ✅** | 1.070 ❌ |
| **402 pt** | 52.86 | 17 | 1.605 | 1.374 | **1.168 ✅** | 1.070 ❌ |

All four pass. The failing band `p ∈ [48.08, 54.68]` no longer exists.

And the stated anchor is true again at the floor: `0.0731 × 14 = 1.0234` pt against
`0.026 × 44 = 1.1440` pt — "about 1.02 points against a 1.14-point grid line", and 一 at regular
**is** fainter than the grid, which is what makes semibold a floor rather than a preference.

### Every stated frame number, re-derived from the contract's own formulas

With both rounding rules now present (numeral: nearest point; strip: nearest point):

```
p =  44.000 (floor)        0.32p = 14.080 → s = 14   h = 15.9380 → 16   block 308 × 340   grid 1.1440
p =  49.000 (375 pt)       0.32p = 15.680 → s = 16   h = 18.1120 → 18   block 343 × 379   grid 1.2740
p = 102.857 (720 pt cap)   0.32p = 32.914 → s = 20   h = 25.9686 → 26   block 720 × 772   grid 1.6000
```

**14 pt, 16 pt and 308 × 340 now all derive exactly from the stated formulas** — the first time in
four rounds that has been true. Both clamp ceilings bind at the 720 pt cap as intended; the grid
ceiling engages at `p ≈ 61.5`, the numeral ceiling at `p = 62.5`, which is the co-termination draft
§4.5.1 reason 2 relies on.

**Order-of-operations check on the new numeral rule.** The contract says "rounded to the nearest
point **and** clamped to between 13 and 20"; the draft says clamp then round. Both bounds are
integers, so the two orders agree at every input. No ambiguity. ✅

---

## 2. Are the seven should-fixes confined to their findings?

**Yes, all seven.** Each was checked against the exact correction I named.

**R3-2 — recorded, not overreached.**

> "The grid is very close in weight to the finest game-state marker — the check ring is `0.025 p`
> against the grid's `0.026 p` — so the two are told apart by shape and by ink strength rather
> than by weight: markers are drawn in active or record ink and the grid is not."

Verified: `0.025 p` is #19's thinnest marker stroke, `0.025 / 0.026 = 0.96`, and the check ring is
active ink (≥ 4.5:1) against the grid's ≥ 3:1, so ink strength does separate that specific pair.
It records the number and names the separation mechanism without claiming the draft's `1.25 ×`
invariant holds and without touching either value. Exactly the scope I asked for. ✅

**R3-3 — gate 11** now reads "confirming that the surface's material and border change while its
position and size never do", matching the sentence this branch corrected in round 3 word for
word. ✅

**R3-4 — numeral rounding** stated; 14 now derives. ✅

**600 ms** — "an **Undo** of a decision cycle must complete within 600 ms, which two plies at 240
plus their overhead satisfy with room to spare." Re-verified: `2 × 240 + 60 = 540 ≤ 600`, 60 ms
spare, and one ply at 240 ≤ the accepted 250 ms one-ply ceiling. ✅

**Compose beat** — "260 ms after the player's own move has finished animating, **including the
captured piece's removal where there is one** — the arrival, not the tap that committed it, since
the AI must not leave before the player's move has finished being shown." The 40 ms ambiguity is
closed by the parenthetical, and the round-3 reason I found confusing ("a capture's animation
outlasts the beat") is replaced by a cleaner one. ✅

**Springs** — "any spring that survives — one animating a non-motion property — loses its
overshoot rather than its duration". This is now draft clause (c) exactly, and it no longer
collides with clause (a): the only spring in the design (the invalid-drop return) animates
position and is caught by (a), so it never reaches this clause. ✅

**Leading feedback, generalised** —

> "**Feedback that reports an event fires when the event completes**, within one frame of it: a
> move sounds when the piece lands, not when it lifts. **Feedback that answers a touch leads its
> animation** — selection, an illegal tap, refused input, and a failed save all respond at the
> touch rather than at the end of whatever is drawn in reply."

Checked against every row of draft §3.10.4. All four "answers a touch" rows fire at `t = 0` in the
draft — selection at the lift, the illegal tap at the mark's entry, refused input at the status
beat, the save failure at the capsule's entry — and the reporting rows fire at arrival. The 将军
sound's `t(d) + 120` also fits, since that is when the check treatment finishes appearing.
Gate 8 rewritten to match the two clauses exactly. ✅

---

## 3. Regression pass over rounds 1–3

Net diff is **52 insertions / 6 deletions** in `interaction-design.md` and **11 insertions** in
`testing.md` — against round 1's 55/4 and 11. No scope creep across four rounds. Re-read every
added line; re-verified every number.

| Previously passed | Round 4 |
|---|---|
| B1 numerals 4.5:1 / 7:1, record-ink gate disapplied | unchanged ✅ |
| B2 semibold / bold, 1.02 vs 1.14 anchor | **restored to true** by the revert ✅ |
| B3 seven distances, "chosen proportion", 600 ms | improved (adds "Undo") ✅ |
| B4 compose beat on the arrival | improved (names the removal) ✅ |
| B5 check pulse removed; gate 7 inverted; `:154`/`:166` reconciled | unchanged ✅ |
| B6 leading feedback | improved (generalised) ✅ |
| N1 readability duty restored | unchanged ✅ |
| N2 "ordinary play" defined | unchanged ✅ |
| board block, "together or not at all", #23 claim cut, cost recorded, durations split, accessibility-table sentence | unchanged ✅ |
| travel law 180/195/200/210/220/230/240; flip 339.4 → 340 inside 300–400 | re-verified ✅ |
| gates 1–11 | 8 and 11 improved; the rest unchanged ✅ |

**No regression found.** Every number the contract states re-derives from the formulas the
contract states.

---

## 4. What remains open — none of it blocking

Recording these so they are not lost, not to hold the merge. I agree with your policy: on this
branch each of these costs more to fix now than it costs to carry.

**should-fix, for a later pass**

- **Round-1 4.8** — the tint list reads exhaustive while omitting the Play destination's accepted
  "direct **Resume Game** action", which the draft's §5.7 table tints.
- **Round-1 4.7** — the compose beat still falls outside "a move, a capture, an Undo", so no rule
  covers a tap during it; the draft classifies it as committing and calls it "the most likely
  moment for a stray tap".

**nits**

- The Reduce Motion body still does not name the illegal-tap case, though "as the accepted rule
  requires of **every pulse**" covers it by its own words, #19 states the behaviour normatively,
  and gate 7 tests it. Adequately closed in substance.
- "Feedback that answers a touch" omits the drag-committed move, which the draft fires at release
  ("the hand already arrived"). Defensible either way: the move completes under the finger, so
  "when the event completes" is satisfiable correctly.
- The 4.5:1 reason is size-dependent ("14 points at the floor") and the numerals reach 20 pt at the
  cap; the draft's position is that the gate does not relax with board size.
- "against **the board surface**" where the grid sentence says "the style's own board surface".
- The Increase Contrast weight pair (`.bold` / `.heavy`) is not carried over.
- The font family is not named, but `interaction-design.md:72` already establishes the system font
  for piece characters and the numeral bullet says "the system font cascade", so the weights are
  anchored. The draft's "no bundled font" prohibition is what is missing.
- The `0.08 p` term's stated reason is loose — it is clearance *beyond* the margin, not what keeps
  numerals off it. It does correctly pin the baseline.
- "within 500 ms of the player's move" is less precise than the beat anchor two clauses earlier;
  "a fifth of a second"; "a velocity ceiling shared with move travel"; Reduce Bright Effects and
  the light/dark/increased-contrast asset variants dropped from draft §5.6; the threefold notice's
  stacked placement.

---

## Verdict

**MERGE.**

The revert is exactly a revert: the rounding rule is deleted, 1.14 is back, "about 62" is correct
because it was always the unrounded figure, and nothing else in that sentence moved. The invariant
that broke in round 3 now holds across the entire supported pitch range with a minimum of **1.1218
at `p = 45.31`**, which independently reproduces the draft's stated worst case of 1.12 at `p ≈ 45`;
all four device widths that failed — 375, 390, 393 and 402 pt — pass at 1.19, 1.14, 1.20 and 1.17.

All seven should-fixes are confined to the findings they answer, and two of them make the document
better than my proposed corrections: the numeral rounding rule means **14 pt, 16 pt and 308 × 340
now all derive from the contract's own formulas for the first time**, and generalising the leading
feedback rule from selection to every touch-answering response closes the round-2 limb without a
new exception list.

Nothing previously passed has regressed. The net diff is 52/6 and 11 lines — the same shape as
round 1, after four rounds and six blocking findings, which is the sign that the fixes stayed
inside their findings this time.
