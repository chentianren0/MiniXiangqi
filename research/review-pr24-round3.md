# Pre-merge review, round 3 — PR #24, `design/frame-motion-glass`

Re-reviewed at `7f8c90a` ("Remove the check pulse under Reduce Motion, as the accepted rule
says") against round 2 at `adde759`, using the same two source drafts and the accepted contracts
on `main` at `d357c4a`.

---

## The three-way check you asked for: B5

**All three constraints are satisfied. B5 is resolved.**

New text:

> "The check pulse is removed rather than converted, as the accepted rule requires of every
> pulse: check is a persistent treatment plus a pulse, so the double ring and the 将军 token
> still say everything the pulse said, and the rings simply arrive by crossfade. Removing it is
> the point — a repeating attention-grabbing animation is precisely what this setting exists to
> spare the people who enable it."

| Constraint | Text it must satisfy | Verdict |
|---|---|---|
| Accepted bullet `:418` | "the animation of lifts, springs, **pulses**, and long-distance travel **is removed** in favor of a brief crossfade or immediate state update" | ✅ The pulse is now removed, and the sentence cites the accepted rule by name — "as the accepted rule requires of every pulse". |
| #19's check treatment | "A double ring… **shown whenever that side is in check**… The pair **pulses once in stroke weight** as it appears" | ✅ The persistent double ring is what #19 makes persistent; the pulse is only its entrance. "The rings simply arrive by crossfade" matches draft E1 exactly — "The persistent double ring crossfades in over 120 ms and stays." The 将军 token is accepted `Turn status`. |
| Accepted illegal-tap behaviour | #19: "**Under Reduce Motion they change state once instead of pulsing** — a single step to a stronger appearance, held briefly and then restored" | ✅ in the gate, ⚠️ in the body — see below. |

**The second limb is closed.** `testing.md` gate 7 now reads "…confirm specifically that the
check pulse is removed while the check rings, the 将军 token, **and the illegal-tap response**
all still deliver their states **without animation**", which is the same requirement as the
untouched accepted gate at `:166` ("a single non-animated state change of the legal
destinations"). Both gates can now pass. ✅

Two residuals, neither blocking:

- **should-fix.** The body's general clause still says "anything that animates opacity… is
  unchanged", and the illegal-tap pulse is an opacity/appearance pulse. Only the *gate* names it.
  "as the accepted rule requires of every pulse" implies it, and #19 states it normatively, so
  an implementer is not actually left free — but the rule should name it where the rule is read.
  Correction: "…as the accepted rule requires of every pulse — the check pulse, and equally the
  illegal-tap response, which becomes a single non-animated state change of the legal
  destinations rather than a pulse."
- **should-fix, carried from round 2.** "springs lose their overshoot rather than their duration"
  still overrides `:418`'s "the animation of lifts, **springs**… is removed", in the same
  sentence group that now correctly defers to `:418` on pulses. The clause is also inert: the
  only spring is the invalid-drop return, which animates position and is already caught by clause
  (a). Delete it.
- **nit.** "the double ring and the 将军 token still say everything the pulse said" — in replay
  there is no token (#19: "Replay has no side-to-move line and therefore no token; there the
  board's own check treatment carries it"), so one carrier, not two. Harmless, since the rings
  are persistent and #19 already says so.

---

## Everything else you listed — verified

| Item | Round-3 text | ✓ |
|---|---|---|
| N1 readability duty | "**Preserve board readability and interaction clarity** where translucent or material surfaces surround game content. They surround it and never overlap it, per the boundary below." | ✅ the draft's §5.8 sentence verbatim, plus a cross-reference |
| N2 "ordinary play" | "— ordinary play meaning an active game on the play screen with neither the result card nor the threefold notice presented" | ✅ gate 9's "exactly one" is now runnable; the notice state falls under "at most two", where notice + control cluster = 2 |
| #23 claim | "Hiding them returns 32 points of height at the floor. Whether that is enough… is settled by the layout bounds, not here." | ✅ cut as recommended; body and gate 3 now agree |
| cost of hiding | "…a reader cannot relate a move in the list to a file on the board without counting, which is a loss for the same user the larger type was for." | ✅ round-1 finding 4.6 closed |
| accessibility table sentence | "what changes is the surface's own material and border, never its position or size" | ✅ round-1 finding 4.10 closed |
| strip-height rounding | "rounded to the nearest point" | ✅ and better than "round up" would have been — see below |
| `0.08 p` term | "clear space between the board's outer line and the tallest numeral" | ✅ in effect, ⚠️ in wording — see below |

**Strip height, re-verified.** "Nearest point" makes the stated numbers robust to the numeral
rounding rule still being absent, which "rounded up" would not have been:

```
s = 14.08 (unrounded) → h = 16.009 → 16 → block 308 × 340   ✅
s = 14    (rounded)   → h = 15.938 → 16 → block 308 × 340   ✅
```

Both land on the stated 16 and 340. Round-1 finding 1.2 is closed for the strip and the block.

**The `0.08 p` term now pins the baseline**, which was the real content of round-1 finding 1.3:
ink begins `0.08 p` below the strip's top edge and is `0.887 s` tall, which exactly fills the
rest, so the vertical placement is determined and numeral ink begins `0.58 p` from any board
point — the draft's value. ✅

- **nit.** The stated reason is loose. The strips already sit "outside the half-cell margin", so
  nothing about the `0.08 p` term is what keeps numerals off the margin; it is clearance *beyond*
  the margin, and the clear space from the board's outer line to the numeral is `0.58 p`, not
  `0.08 p`. Correction: "The `0.08 p` term is clear space at the top of each strip, beyond the
  half-cell margin the outermost points' markers occupy, so numeral ink never begins closer than
  `0.58 p` to any board point."

---

## 🔴 R3-1 — BLOCKING. The new grid rounding rule breaks the anchor that round 2 installed

> "**The grid** is stroked at `0.026 p`, **rounded to the nearest half point** and clamped to
> between 0.80 and 1.60 points — **1.0 point at the floor**, and at the ceiling from a pitch of
> **about 62 points** upward…"

Half-point rounding is in **neither draft and no owner decision**. Draft §4.5.1 gives
`clamp(0.026 p, 0.80 pt, 1.60 pt)` with **1.14 pt at `p = 44`** in two separate tables (§4.5.1
and §4.8), §4.3.2's numeral invariant is computed against 1.14 / 1.18 / 1.60, and §4.5.3
explicitly rejects snapping: "Point positions are computed in continuous coordinates and are
**never snapped** to the device pixel grid. Crispness comes from ≥ 2× rendering, not from
snapping." §4.5.1 also treats 0.80 pt as a legitimate fractional value ("At 2× rendering 0.80 pt
is 1.6 physical pixels — a clean antialiased hairline").

Five things break. Each is recomputed.

### (a) It contradicts the same document six lines below

> "…1.**0** point at the floor…"
> …three bullets later…
> "at regular weight the single stroke of 一 measures about 1.02 points against a **1.14-point
> grid line**"

### (b) It falsifies the semibold anchor at the floor

```
一 at regular, s = 14        = 1.0234 pt
grid, unrounded (round 2)   = 1.1440 pt  → 一 fainter than the grid ✅ the stated reason holds
grid, half-point (round 3)  = 1.0000 pt  → 一 THICKER than the grid ❌ the stated reason is false
```

The sentence "so the numeral labelling the board would be fainter than the lines it labels" is
the whole justification for semibold, installed in round 2 at my request and confirmed by you as
the reason. Under the new grid value it is untrue by 2 %.

### (c) It makes the semibold numeral *actually* fail on the reference iPhone

Worse than (b): at semibold, the draft's invariant "**一's stroke ÷ grid ≥ 1.10**" (§4.8, "actual:
1.16 / 1.53, worst case 1.12 at `p ≈ 45`") **fails outright over a wide band** once the stroke
jumps from 1.0 to 1.5 pt at `p = 48.08`:

```
invariant fails for p ∈ [48.08, 54.68]   — it holds at every pitch under the unrounded rule
```

Mapped onto devices by the draft's own method (`p = (W − 32)/7`, §4.1.3):

| Width | `p` | `s` | 一 semibold | grid, new | ratio | grid, unrounded | ratio |
|---|---|---|---|---|---|---|---|
| **375 pt** (the width #23 verifies against) | 49.00 | 16 | 1.510 | **1.50** | **1.007 ❌** | 1.274 | 1.186 ✅ |
| 390 pt | 51.14 | 16 | 1.510 | **1.50** | **1.007 ❌** | 1.330 | 1.136 ✅ |
| 393 pt | 51.57 | 17 | 1.605 | **1.50** | **1.070 ❌** | 1.341 | 1.197 ✅ |
| 402 pt | 52.86 | 17 | 1.605 | **1.50** | **1.070 ❌** | 1.374 | 1.168 ✅ |
| 428–440 pt | 56.6–58.3 | 18–19 | 1.70–1.79 | 1.50 | 1.13–1.20 ✅ | 1.47–1.52 | 1.15–1.18 ✅ |

Worst case under the new rule is **0.944 at `p = 48.1`** — the Chinese numeral is measurably
fainter than the grid line it labels, which is exactly the failure semibold exists to prevent,
now occurring on the narrower half of the current iPhone range including the reference device.
The draft warned about precisely this: "**if the owner raises the grid weight** or lowers the
numeral size **the invariant must be re-derived**."

### (d) The rounding is arithmetically incompatible with its own clamp bounds

Neither 0.80 nor 1.60 is a multiple of 0.5, so the clamp bounds are unreachable or reached
somewhere other than stated, depending on the order of operations the contract does not specify:

```
round then clamp → achievable values {0.80, 1.0, 1.5, 1.60}; 1.60 first reached at p = 67.31
clamp then round → achievable values {1.0, 1.5};             1.60 NEVER reached
```

### (e) The stated ceiling pitch is wrong

"at the ceiling from a pitch of **about 62 points** upward". `1.60 / 0.026 = 61.54`, so ~62 is
correct for the **unrounded** rule and wrong for the rule that was written: 67.31 under
round-then-clamp, never under clamp-then-round. That figure is the tell that the rounding was
added without recomputing what depends on it.

It also breaks the draft's structural reason for the ceiling — "the ceiling at 1.60 pt exists so
that **the grid stops growing at the same pitch (`p ≈ 62`) at which `s` stops growing**" — which
is what keeps the numeral invariant true by construction rather than by luck.

Severity: **blocking**.

Correction — restore the unrounded rule and keep the corrected rationale this commit got right:

> "**The grid** is stroked at `0.026 p`, clamped to between 0.80 and 1.60 points — 1.14 points at
> the floor, reaching the ceiling at a pitch of about 62 points, the same pitch at which the
> numeral size stops growing, so the lines never coarsen as the board grows and the numerals are
> never overtaken by them. The lower bound binds only if a smaller pitch is ever accepted. The
> stroke is not rounded or snapped to the pixel grid; crispness comes from 2× rendering. The
> palace diagonals match it exactly, as the accepted geometry requires. Both reach at least 3:1
> against the style's own board surface."

---

## R3-2 — should-fix. The grid weight against #19's marker strokes, now checkable for the first time

This PR fixes the grid at `0.026 p`; #19 fixed every marker stroke. The ratio can now be computed
and two markers come out **thinner than the grid line they are drawn across**:

| Marker (#19) | Stroke | ÷ grid `0.026 p` |
|---|---|---|
| **check double ring** | `0.025 p` | **0.96** |
| **selection ring** | `0.030 p` | **1.15** |
| keyboard focus | `0.040 p` | 1.54 |
| last-move bracket, drag-origin dot | `0.045 p` | 1.73 |
| capture ring | `0.055 p` | 2.12 |

The draft states this as a checkable invariant — "**The thinnest marker stroke is at least
`1.25 ×` the grid stroke at every supported pitch**… At `0.026 p` the ratio is **1.54**" — but it
computed 1.54 against the pre-acceptance check ring of `0.04 p`, which #19 replaced with
`0.025 p`. Under the accepted geometry the real number is 0.96, and the draft's own instruction
applies: "Any future change to a marker stroke, or to the grid, **must re-check this one
number**."

This is **not a contract violation**: no accepted rule requires a stroke-weight ratio, and #19's
distinguishability rests on shape families and on markers being active ink (≥ 4.5:1) against the
grid's rule strength (≥ 3:1), so a check ring is darker even where it is thinner. But the PR
should not close the grid-stroke question while leaving the number unrecorded and the draft's
invariant silently failing.

Correction: add one sentence — "The check rings are the one marker drawn thinner than the grid,
at `0.025 p` against `0.026 p`; they are distinguished by being a double ring in active ink
rather than by weight."

---

## R3-3 — should-fix. Gate 11 was not updated with the sentence it tests

The contract sentence was corrected in this commit; the gate that tests it was not:

> contract (fixed): "…what changes is the surface's own **material and border**, never its
> position or size."
> `testing.md` gate 11 (unchanged): "…confirming **the background is substituted** and the layout
> never reflows."

Round-1 finding 4.10 is closed; **6.11 is not**, and the two now disagree inside the same PR.

Correction: "…confirming that only the surface's own material or border changes, that under dark
appearance the material simply adapts, and that the layout never reflows in any of the four."

---

## R3-4 — should-fix, carried. The numeral-size rounding rule is still absent

> "Numeral size is `0.32 p`, clamped to between 13 and 20 points: **14 points at the floor**."

`0.32 × 44 = 14.08`. The strip and the block are now robust to this (both 14 and 14.08 give
h = 16 under "nearest point"), so the consequence is contained — but the stated 14 still does not
follow from the stated formula. Draft §4.1.2: "`clamp(0.32 p, 13 pt, 20 pt)`, **rounded to whole
points**." Four words.

---

## Regression check on everything previously passed

Re-verified at `7f8c90a`, unchanged and still correct:

- B1 numerals at 4.5:1 / 7:1 with the record-ink gate disapplied. ✅
- B2 semibold / bold named — **the weights are still right; only the grid value under them
  broke** (R3-1). The quoted "1.02 points" is still correct: `0.0731 × 14 = 1.0234`. ✅
- B3 travel law: seven distances enumerated with the horse's leap in the right place, "chosen
  proportion rather than a derived one", `2 × 240 + 60 = 540 ≤ 600`. ✅
  (Carried should-fix: the word "Undo" is still missing from "a decision cycle must complete
  within 600 ms"; gate 4 has it right.)
- B4 compose beat on the arrival, capture named, gate 5 matching. ✅
  (Carried should-fix: "has finished animating — the arrival" still equates two instants that
  differ by 40 ms for a capture; and the 500 ms sentence still says "of the player's move".)
- B6 selection exception. ✅ (Carried should-fix: illegal tap, refused input and save failure
  also lead their animations.)
- Board block definition, "together or not at all", the motion paragraph's Liquid Glass
  cross-reference, the durations/first-version-values split, gates 2, 3, 4, 5, 6, 8, 9, 10. ✅

No other regression found. The round-3 commit touched eight places; seven are improvements.

---

## Verdict

**DO NOT MERGE.**

The B5 inversion is correct and satisfies all three constraints at once — the accepted bullet at
`:418`, #19's check treatment, and the accepted illegal-tap behaviour — and the two `testing.md`
gates that could not both pass now can. Every other item on your list verifies, and the strip
height, the `0.08 p` term and the "ordinary play" definition are each better than the correction
I proposed.

One thing blocks, and it is again a fix that reached past its finding. I asked for the grid
sentence's **false rationale** to go; the commit removed it and also added a half-point rounding
rule that appears in neither draft and no owner decision. That rule moves the floor stroke from
1.14 to 1.0 pt, contradicting the "1.14-point grid line" six lines below it; falsifies the
semibold anchor at the floor, where 一's regular-weight bar of 1.0234 pt is now *thicker* than the
grid rather than fainter; and — the real damage — makes the semibold numeral fail the draft's
`≥ 1.10` invariant outright for `p ∈ [48.08, 54.68]`, which is 375, 390, 393 and 402 pt iPhones
including the one #23 verifies the stacked layout against, worst case 0.944. It also cannot reach
either of its own clamp bounds, and its stated ceiling pitch of "about 62" is the unrounded
figure, not the rounded one.

Deleting five words — "rounded to the nearest half point and" — and restoring "1.14" fixes all of
it. R3-2, R3-3 and R3-4, plus the carried should-fixes above, are not merge-blocking.
