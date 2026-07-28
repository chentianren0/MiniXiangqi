# Pre-merge review — PR #24, `design/frame-motion-glass`

Reviewed at `7485f8d` against `main` at `d357c4a`, plus the open `design/app-shell-and-layout`
(#23) branch, `discussion-drafts/board-frame-and-glass-draft.md`,
`discussion-drafts/board-motion-language-draft.md`, and
`discussion-drafts/board-visual-language-design.fable-partial.md`.

Every number below was recomputed, not read. Working:

```
p = 44 (accepted floor, EVERY platform)   0.32p = 14.080   0.026p = 1.1440
p = 49 (375 pt iPhone, width-bound)       0.32p = 15.680   0.026p = 1.2740
p = 102.857 (720 pt cap, #23)             0.32p = 32.914   0.026p = 2.6743
t(d) = 180 + 60(√d−1)/(√6−1) → 180.00 197.15 200.50 210.30 221.39 231.17 240.00
                             → 180  195  200  210  220  230  240 (nearest 5 ms)
6√2 / 25.0 p·s⁻¹ = 0.33941 s → 340 ms
```

Verdict is at the end.

---

## 1. The frame arithmetic, recomputed

### What checks out

- Grid `0.026 × 44 = 1.1440` → the contract's "1.14 points at the floor" is right.
- Numeral `0.32 × 44 = 14.08` → 14 pt, and strip `0.08(44) + 0.887(14) = 15.938` → 16 pt.
- Board block `7 × 44 = 308` by `308 + 2(16) = 340`. **308 × 340 confirmed.**
- "removes 32 points of height at the floor": `2 × 16 = 32`. **Confirmed** — and consistent
  with the contract's own formula, which (unlike the draft) states no enlarged accessibility
  numeral size, so the height removed is the default strip height.
- **At the 720 pt cap** (`p = 102.857`): `0.32p = 32.91` → the numeral ceiling **binds hard**
  (20 pt, 61 % of proportionality). `0.026p = 2.674` → the grid ceiling **binds** (1.60 pt).
  Strip `0.08(102.857) + 0.887(20) = 25.97` → 26 pt; block **720 × 772**. Both ceilings
  binding at the cap is intended per draft §4.5.1 reason 2 and §4.1.2 ("the frame recedes as
  the board grows"). Strip height at the cap is sensible: 26 pt of strip for 20 pt numerals.
- **The single-line outer boundary reasoning is sound, and soundly stated.** Accepted
  `Board metrics` fixes every marker at "a radius of at most `0.50 p`" and says the half-cell
  margin "is the same `0.50 p`, so the outermost points' markers are contained by the margin".
  The margin band `(0, 0.5 p)` is therefore fully occupied, and any second border line drawn
  inside it does intersect the marker band. The contract's argument is in fact *better* than
  the draft's (§4.6 reason 1 argues from a `0.6 p` placement and near-concentric crowding).
  **No finding.**

### Finding 1.1 — the two clamp floors can never bind, and the stated reason for them is false

> "**The grid** is stroked at `0.026 p`, clamped to between 0.80 and 1.60 points **so it neither
> disappears at the floor** nor coarsens on a large board — 1.14 points at the floor."

> "Numeral size is `0.32 p`, clamped to between **13** and 20 points: 14 points at the floor."

The accepted floor is `p ≥ 44` on **every** platform (`Layout shapes`: "a point of the grid is
never smaller than 44 points on **every** platform… macOS shares it"). At `p = 44` the grid
stroke is 1.144 pt and the numeral 14.08 pt. The 0.80 pt floor binds only below `p ≈ 30.8`; the
13 pt floor only below `p ≈ 40.6`. **Neither is reachable at any supported pitch.** The clause
"so it neither disappears at the floor" is therefore false: nothing at the accepted floor is
near 0.80 pt.

Both floors are inherited from the draft's premise "`p ≥ 44 pt` on iOS/iPadOS, **`p ≥ 28 pt` on
macOS**" (draft §4 preamble), which the accepted contract superseded. The draft's own
justification for 13 pt is explicitly the macOS default body size at `p = 28`, and for 0.80 pt
explicitly "protects 1× external displays on the Mac, where `0.026 × 28 = 0.73 pt`".

Severity: **should-fix**.

Correction: either drop both floors, or keep them and delete the false justification —
"clamped to a ceiling of 1.60 points so it does not coarsen on a large board; the clamp's floor
of 0.80 points is unreachable at the accepted 44-point pitch floor and exists only against a
future lower floor." Same for the numeral: "clamped to a ceiling of 20 points".

### Finding 1.2 — no rounding rule, so 14 / 16 / 340 are not reproducible

> "Numeral size is `0.32 p`… 14 points at the floor."
> "Strip height is `0.08 p + 0.887 s`… 16 points at the floor, giving a board block of 308 by
> 340 points there."

`0.32 × 44 = 14.08`, not 14. The draft states the rule the contract dropped: "`clamp(0.32 p,
13 pt, 20 pt)`, **rounded to whole points**" and "`0.08 p + 0.887 s`, **rounded up to whole
points**". Without them the arithmetic does not land where the contract says:

| | s | h | block |
|---|---|---|---|
| s rounded to 14 (draft) | 14 | `15.938` → 16 | 308 × **340** ✅ |
| s left at 14.08 | 14.08 | `16.009` → **17** (round up) | 308 × **342** ❌ |

Severity: **should-fix**.

Correction: restore both rounding rules verbatim — "`0.32 p`, rounded to whole points" and
"`0.08 p + 0.887 s`, rounded up to whole points".

### Finding 1.3 — the strip's baseline and its no-ink band are both missing

The contract gives strip height but no vertical placement of the ink inside it. The draft gives
both: baseline at `0.08 p + 0.7925 s` below the core boundary, and the rule that the topmost
`0.08 p` of each strip carries no ink. The `0.08 p` term in the height formula *is* that band —
the contract carries the term forward with no statement of what it is for, so an implementer
who vertically centres the numerals in the strip satisfies the contract and puts ink inside the
clearance the term exists to reserve.

(Provenance note, not itself a defect: the draft sized the band because "the S6 double check
ring has its outer edge at `0.56 p`" and "overhangs the core boundary by `0.06 p`". That is the
`fable-partial` §1 S6 — stroke `0.04 p` at radii `0.46 p` / `0.54 p`. **Accepted #19 replaced
it** with "stroke `0.025 p` at centre-line radii `0.4325 p` and `0.4875 p`", outer edge exactly
`0.50 p`. Under the accepted geometry nothing overhangs into the strip at all, so the `0.08 p`
band no longer has the derivation the draft gave it. It is still needed as plain optical
clearance and still reproduces 16 pt, but the contract should not present the formula as
derived without saying from what.)

Severity: **should-fix**.

Correction: add "Numeral ink begins `0.08 p` below the board core's edge — no numeral ink falls
within `0.58 p` of any board point — and the two sets share a baseline `0.7925 s` below that."

### Finding 1.4 — "both strips are always present" contradicts the bullet four lines below it

> "…so the numbers beside a player are always their own and **both strips are always present**."
> …
> "- **The strips are hidden at accessibility text sizes.**"

Severity: **should-fix**.

Correction: "…so the numbers beside a player are always their own, and the two strips are shown
together or not at all."

### Finding 1.5 — the accessibility-size hiding rule is not platform-scoped

The draft scopes it: "At `dynamicTypeSize.isAccessibilitySize` **on iOS and iPadOS**… macOS is
unaffected: HIG 'Typography › macOS' states flatly, 'macOS doesn't support Dynamic Type.'"
The contract's bullet has no scope, and #23's minimum window (380 × 500) is a macOS/iPadOS
requirement that explicitly includes the strips.

Severity: **nit**.

Correction: "The strips are hidden at accessibility text sizes on iOS and iPadOS."

### Finding 1.6 — 32 pt is the figure at `p = 44`, not at the device the argument is about

Not a defect in the sentence as written ("at the floor"), but recorded so the number is not
reused: on the narrowest supported iPhone (375 pt, #23) the layout is width-bound at `p = 49`,
where `s` → 16 and `h` → 19, so the strips cost **38 pt**, not 32. The claim is conservative in
the right direction. **No finding.**

---

## 2. The 26 % ink claim and the weight decision

### Finding 2.1 — BLOCKING — the numerals are put on the 3:1 record-ink gate; the draft derives 4.5:1

> "Numerals meet the **record-ink contrast gate of 3:1**, promoted with it under Increase
> Contrast."

The draft (§4.3.3) defines a **third**, parallel ink name precisely to avoid this:

> "**Numeral strength** — the file numerals: contrast **≥ 4.5:1**, both appearances. Under
> Increase Contrast, **≥ 7:1**." … "Why 4.5:1 and not 3:1 for the numerals: they are text at
> 13–20 pt, and HIG 'Accessibility › Vision' gives the governing table — 'Up to 17 pts | All |
> 4.5:1'; the 3:1 relaxation applies only at 18 pt and above, or to bold text."

At the accepted 44 pt pitch floor the numerals are 14 pt. 3:1 body text at 14 pt is below
Apple's stated minimum, and "promoted with it under Increase Contrast" means 4.5:1 arrives only
when the user turns Increase Contrast on — i.e. the default appearance ships the failure. The
draft also requires the numerals to be *darker than the grid* ("Same hue, higher strength");
under the contract both are 3:1 and may be identical. Nothing here was owner-decided, and the
draft is unambiguous in the opposite direction.

Severity: **blocking**.

Correction: replace with — "The numerals are frame ink at **4.5:1** against the style's own
board surface in both appearances, raised to **7:1** under Increase Contrast — higher strength
than the grid, which they must never be fainter than. The 3:1 record-ink gate does not apply:
these are 13–20 pt text."

### Finding 2.2 — BLOCKING — "one weight step more" with no anchor permits a numeral fainter than the grid line it labels

> "The digits therefore take one weight step more than the Chinese numerals."

The draft names both weights and shows why the *base* is load-bearing, not just the step
(§4.3.2 (a)): 一's entire ink is one horizontal bar whose height is its stroke weight. Recomputed
at the accepted floor (`p = 44`, `s = 14`, grid 1.144 pt):

| Chinese weight | 一's bar | vs grid 1.144 pt |
|---|---|---|
| `.regular` (0.0731 em) | **1.023 pt** | **0.89× — the numeral is fainter than the lines it labels** |
| `.semibold` (0.0944 em) | 1.322 pt | 1.16× ✅ |
| `.bold` (0.1081 em) | 1.513 pt | 1.32× ✅ |

The draft: "At `.regular` this fails outright at the iOS floor… **That constraint is what sets
the Chinese weight.**" A `.regular` / `.medium` pair is "one weight step more" and satisfies the
contract exactly as written, and it fails. The contract also states no family ("the system font,
requested as `Font.system(size:weight:)` — never a named family, and no bundled font") and no
Increase Contrast pair (`.bold` / `.heavy`).

This is the same finding as item 5's removed **Need to discuss** entry, which claims the
numerals' *typography* is now defined. It is not.

Severity: **blocking**.

Correction: name them — "The Chinese numerals are `.semibold` and the digits `.bold`, one step
heavier; under Increase Contrast, `.bold` and `.heavy`. The system font is requested by weight
and size, never as a named family. `.semibold` is a floor, not a preference: at `.regular` the
Chinese 一's single bar is thinner than the grid stroke at the accepted pitch floor."

### Finding 2.3 — "so the two strips read as equals" over-states the draft's own measurement

> "…at equal weight the Chinese numerals carry about a quarter more ink than the digits… The
> digits therefore take one weight step more than the Chinese numerals **so the two strips read
> as equals**."

Recomputed from the draft's measured table (ink area / em²):

| Weight | CJK / Latin |
|---|---|
| regular | 1.313 | medium | 1.322 | semibold | **1.260** | bold | 1.268 | heavy | 1.249 |

"About 26 %" is the semibold row; the range across weights is 25–32 %, so "about a quarter" is
the low end but defensible. What is not defensible is "read as equals": semibold CJK (0.2242)
against bold Latin (0.2013) leaves the digits **10.2 % lighter**. The draft says so in terms:
"`.bold` (0.2013) leaves the Arabic strip **10 % lighter**. I choose `.bold` and accept the
10 %" — because `.heavy` (4.5 % gap) is outside HIG's endorsed weight range and leaves Increase
Contrast nowhere to go, and because "the two strips are `7 p` apart… never seen adjacent".
One step does not equalise them; it makes the residual acceptable.

Severity: **should-fix**.

Correction: "…so the residual difference is about a tenth rather than a quarter. The two strips
sit `7 p` apart and are never seen adjacent, which is what makes that residual acceptable;
closing it entirely would need a weight outside the endorsed range."

---

## 3. Motion arithmetic

### What checks out

- The seven durations are exactly `t(d) = 180 + 60(√d−1)/(√6−1)` rounded to 5 ms:
  180 / 195 / 200 / 210 / 220 / 230 / 240 for `d` = 1 / 2 / √5 / 3 / 4 / 5 / 6. **Confirmed.**
- The seven distances really are the only ones the board admits. `xiangqi-rules.md`: "There are
  no advisors or elephants"; king 1, soldier 1, horse √5, chariot and cannon 1–6. **Confirmed.**
- **340 ms flip**: `6√2 = 8.4853 p`; fastest legal velocity `6 p / 0.240 s = 25.0 p/s`;
  `8.4853 / 25.0 = 0.33941 s` → 340 ms, inside the accepted 300–400 band. **Confirmed.**
- Compose beat 260 ms, floor not delay; 500 ms activity threshold. Matches the draft's §3.4.

### Finding 3.1 — BLOCKING — the 600 ms ceiling does not cap a single ply at 240

> "The band cannot be widened later without reopening Undo: a decision cycle must complete
> within 600 ms, and **that ceiling is what caps a single ply at 240**."

Recomputed:

```
two forward plies at 240 + the 60 ms inter-ply gap = 540 ms  ≤ 600   (60 ms spare)
ply permitted by 600 ms with the 60 ms gap = (600 − 60)/2   = 270 ms
ply permitted by 600 ms with no gap                         = 300 ms
draft's actual worst undo cycle: 200 + 60 + 200             = 460 ms (140 ms spare)
```

The 600 ms ceiling does not bind at 240 in either reading. Three separate errors are compressed
into that clause:

1. **The accepted ceilings bound *Undo* transitions, not forward travel.** `Motion and visual
   effects`: "an **Undo** transition must therefore complete within 250 ms for one ply and
   600 ms for a decision cycle." Forward travel has no accepted ceiling except the 180–240 band
   itself, which is what is being justified — the sentence is circular.
2. **240 is not what 600 permits.** 600 permits 270 per undo ply.
3. **The real chain is the draft's, and it is a chosen coupling, not an entailment.** Draft
   §3.2.4: "If forward travel were allowed to reach the physical law's 441 ms, undo travel
   *scaled from it* would reach roughly 370 ms and the worst decision cycle would be
   `370 + 60 + 370 = 800 ms`." The 600 ms ceiling binds forward travel only through the design
   decision that undo travel is derived proportionally from it (`t_undo` = 150–200 against
   `t` = 180–240). Remove that choice and 600 says nothing about forward travel.

Severity: **blocking**. The whole PR is framed as "stated as derived wherever it could be"; a
stated derivation that fails by 60–140 ms will be relied on the next time someone asks to widen
the band.

Correction: "The band cannot be widened without reopening Undo. Undo travel is derived from it
at five sixths, so a 250 ms one-ply and a 600 ms decision-cycle Undo ceiling together hold
forward travel at 240: the uncompressed physical law would put a six-cell sweep at 441 ms, undo
at roughly 370, and a decision cycle at about 800 ms."

### Finding 3.2 — BLOCKING — "260 ms after the player's own move committed" is the wrong instant

> "Its piece departs at the later of two instants: when the search returns, and 260 ms after the
> player's own **move committed**."

The draft defines the anchor precisely: "let `t_commit` be the instant the human's move
**animation completes and board input closes**". The contract's word "committed" has an
established, different meaning in this same document — `Move input`: "Tapping a legal
destination **commits** the move immediately"; "Dropping on a legal destination **commits** the
move." That is the input instant, before travel. Consequences under the contract's own
vocabulary:

```
six-cell chariot, no capture: human travel ends at 240 ms; AI departs at 260 → beat = 20 ms
six-cell chariot with capture: event ends at t(d)+40 = 280 ms; AI departs at 260
    → the AI's committing transition starts 20 ms BEFORE the human's finishes
```

The second case directly violates the new interruption paragraph in the same PR ("A *committing*
transition — a move, a capture, an Undo — runs to completion"), and the first destroys the beat
for exactly the case the owner approved it for. The draft's three reasons for the beat
(attribution, the status being readable as a state, the human's brackets being seen once) all
require 260 ms *after the animation*, since the brackets fade in over 140 ms starting at arrival.

The same ambiguity is in the next sentence ("within 500 ms of the player's move") and in the new
testing gate ("no earlier than the compose-beat floor after the player's move").

Severity: **blocking**.

Correction: "…and 260 ms after the player's own move animation completed and board input
closed." And in the same sentence for the 500 ms threshold, and in the testing gate.

### Finding 3.3 — "following a constant-acceleration law" is not what the law is

> "A one-step move takes 180 ms and a six-cell chariot sweep 240 ms, **following a
> constant-acceleration law**; the seven distances a 7-by-7 board admits give 180, 195, 200,
> 210, 220, 230, and 240 ms."

Under constant acceleration `t ∝ √d`, so `t(6)/t(1) = √6 = 2.449`. The stated ratio is
`240/180 = 1.333`. The actual rule is an **affine remap** of the √d law onto the accepted band:
`t(d) = 180 + 60(√d−1)/(√6−1)`. The draft is explicit — "A pure `t = 180√d` gives
`t(6) = 441 ms`, which is outside the accepted band and — decisively — outside the Undo budget…
The remap preserves the law's *shape*… while compressing its range from 2.45:1 to 1.33:1."

An implementer given "constant-acceleration law" plus the two endpoints reconstructs
`t = 180√d` and produces 441 ms at `d = 6`, blowing the very ceiling the next clause invokes.
The seven values are listed, so the lookup table survives — but the characterisation is wrong
and the seven **distances** are never enumerated, so the mapping from distance to duration has
to be guessed (the horse's √5 in particular).

Severity: **should-fix**.

Correction: "…following a square-root law in distance remapped onto the accepted band, so it
keeps the shape of constant acceleration without its range. The seven distances a 7-by-7 board
admits — 1, 2, √5, 3, 4, 5 and 6 cells — give 180, 195, 200, 210, 220, 230, and 240 ms."

### Finding 3.4 — "a fifth of a second" is not the draft's figure or the draft's reason

> "…because an indicator that flashes for **a fifth of a second** is noise."

Draft §3.4.4: "An indicator that flashes on and off **inside 300 ms** is worse than none",
and the operative reason is the indicator's own 160 ms fade-in — "an indicator whose whole life
is shorter than its own fade is the degenerate case".

Severity: **nit**.

Correction: "…because an indicator whose whole life is shorter than its own fade-in reads as a
glitch."

### Finding 3.5 — "a velocity ceiling shared with move travel"

> "**Board flipping takes 340 ms**, derived from the distance a corner piece travels and a
> velocity ceiling shared with move travel."

There is no separately stated velocity ceiling. The figure is the *maximum* velocity move travel
happens to reach — the six-cell chariot's 25.0 p/s — promoted into a rule by the draft
("*nothing on this board ever moves faster than the fastest legal move*"). Worth stating as the
rule, since it is the only thing that makes 340 a derivation rather than a number inside a band.

Severity: **nit**.

Correction: "…derived from a corner piece's `6√2 p` travel and the rule that nothing on this
board moves faster than the fastest legal move, `25 p` per second."

---

## 4. Interactions with everything already accepted

### Finding 4.1 — BLOCKING — "Reduce Motion is one rule" keeps the check pulse, which the accepted contract removes

> "**Reduce Motion is one rule.** … anything that animates opacity, colour, **stroke weight**,
> or shadow **is unchanged**, because none of those is motion."

Four lines above it, unedited and accepted:

> "With Reduce Motion, the animation of lifts, springs, **pulses**, and long-distance travel **is
> removed** in favor of a brief crossfade or immediate state update."

And accepted `Game-state markers` (#19) defines check as a **stroke-weight** pulse: "The pair
**pulses once in stroke weight** as it appears… **A pulse in scale is not available here**…the
pulse thickens each ring to at most `0.0325 p`."

So the new rule, applied literally, preserves the check pulse under Reduce Motion — the exact
outcome the accepted bullet forbids. The draft anticipated this and made it an explicit
exception, in terms:

> "**E1 — The check pulse is removed entirely, not converted.** The contract names pulses among
> what is removed. **Clause (b) would have kept the pulse (stroke weight), so this exception is
> required, not cosmetic.**"

All seven of the draft's exceptions are dropped. Two more bite:

- Accepted `Game-state markers`, illegal tap: "**Under Reduce Motion they change state once
  instead of pulsing** — a single step to a stronger appearance, held briefly and then
  restored." That is an opacity/appearance animation, which the new rule leaves "unchanged", so
  the destination markers would keep pulsing. `testing.md` line 158 on `main` already gates the
  accepted behaviour: "Verify the illegal-tap response survives Reduce Motion as **a single
  non-animated state change** of the legal destinations." **The new rule and that existing gate
  cannot both pass.**
- "springs lose their overshoot rather than their duration" contradicts the accepted bullet's
  "the animation of… **springs**… is removed in favor of a brief crossfade".

Severity: **blocking**.

Correction: add the exceptions to the paragraph — "…with three exceptions the rule cannot
derive: the check pulse is removed entirely rather than kept, since the accepted contract names
pulses among what Reduce Motion removes; the illegal-tap response becomes a single non-animated
state change of the legal destinations; and the lift and drag scale states and the lift shadow
are applied immediately and never removed." And reconcile "springs lose their overshoot" with
the accepted "springs… removed", or delete the clause.

### Finding 4.2 — BLOCKING — "never at the start of the animation that shows it" breaks the selection haptic, and the new gate enforces it

> "**Sound and haptics fire at the instant the event completes**, within one frame of it,
> **never at the start of the animation that shows it**. A move sounds when the piece lands, not
> when it lifts."

The example is right; the rule is not. The draft's rule is "every event has exactly one instant
at which it is *done*" — and for several events that instant is the **start** of the animation:

> "A selection is **done at the touch** — the piece is selected the moment you touch it, and the
> 140 ms lift is the picture catching up."

Draft §3.10.4 fires `.selection` at "**t = 0** of the lift — the moment the tap is recognised,
**before the lift is visible**", the illegal-tap feedback at t = 0 of the mark's entry, and the
refused-input feedback at t = 0 of the status beat, and then states the consequence explicitly:

> "**The selection haptic leads its animation by up to 140 ms and this is correct.**… Firing it
> at the end of the lift would put a tap in the hand 140 ms after the finger left, which reads
> as lag."

The new testing gate — "Verify sound and haptics fire when the event completes rather than when
its animation begins" — would **fail a correct implementation** of the accepted selection
feedback. This is also new `Sound and haptics` content placed in the `Motion and visual effects`
section, where the `Sound and haptics` section exists two headings below.

Severity: **blocking**.

Correction: move the sentence to `Sound and haptics` and restate it as the draft has it —
"Every event has one instant at which it is done, and both channels fire at that instant, within
one frame of the matching visual change. A move is done when the piece lands, not when it lifts.
A selection is done at the touch, so its feedback leads its 140 ms lift rather than following
it." Rewrite the gate to match.

### Finding 4.3 — "board block" contradicts the accepted definition of "board core"

> "No glass surface may intersect the **board block**: **the board core, its half-cell margin,**
> and the file-numeral strips."

Accepted `Board metrics`, in the table: "**Board core** — 7 points **plus a half-cell margin on
each side** | `7 p` square | 308 pt". The core already contains the margin; listing them as two
things says the core is `6 p` and invites a reader to compute the block as `8 p` wide. The
frame section in the same PR uses the term the other way ("a board block of 308 by 340 points").
The rectangle is the same either way, but the term is now defined twice, incompatibly, and it is
the object a reviewer is told to measure.

Severity: **should-fix**.

Correction: "No glass surface may intersect the **board block**: the board core as
[Board metrics](#board-metrics) defines it — the seven points plus the half-cell margin on each
side — together with the file-numeral strips above and below it."

### Finding 4.4 — the surviving "overlap" and "primarily" sentences contradict the new absolute rule

Two accepted sentences are left unedited and now say the opposite of the new rule:

> "Preserve board readability and interaction clarity when translucent or material surfaces
> **overlap** or surround game content." (`Platform visual language`, directly under the
> rescoped bullet.)

> "Liquid Glass belongs **primarily** to functional layers around the board." (last paragraph of
> `Motion and visual effects`.)

The draft asked for the first by name:

> "The adjacent bullet… should then lose 'overlap': under the rule above nothing overlaps the
> board, and leaving the word in preserves the ambiguity the change is meant to remove.
> *Proposed:* 'Preserve board readability and interaction clarity where material surfaces
> surround game content.'"

Severity: **should-fix**.

Correction: apply the draft's replacement to the first, and change "belongs primarily to
functional layers around the board" to "belongs to the functional layers around the board".

### Finding 4.5 — the strips-hidden claim resolves, in #24, a question #23 leaves open

> "Hiding them removes 32 points of height at the floor, **which is what makes the largest text
> sizes fit**."

#23's remaining **Need to discuss** item: "Define how the on-demand move list is presented in
the stacked layout during ordinary play, and **how accessibility text sizes are accommodated
once the control row and turn status grow**."

The claim is arithmetically supportable but only on assumptions #23 does not accept. The draft's
budget at accessibility sizes on a 375 pt iPhone is "roughly 314 pt" **already assuming** "the
status element wrapped to three lines and the control cluster **restacked vertically**". Hiding
the strips leaves `7 p ≤ 314` → `p ≤ 44.86`, i.e. **0.86 pt of pitch and 6 pt of height above
the accepted floor** — and that is with a chrome behaviour neither PR specifies. The draft's own
resolution was the opposite one: "**the Play control cluster collapses to a single button
opening a menu or sheet.** The strips are never the thing that yields."

The owner reversed the *what*, which is authorized. The contract should not also assert that the
fit is now settled while #23 records it as open.

Severity: **should-fix**.

Correction: "Hiding them removes 32 points of height at the floor, which is what buys the
largest text sizes room; how the control row and turn status are accommodated at those sizes
remains open below." (And leave #23's open item standing.)

### Finding 4.6 — the cost of hiding the strips is nowhere recorded

The draft's second argument for two strips is a use-case, not an aesthetic:

> "**The move list contains both sides' moves in both numeral systems.** A learner reading
> `马8进7` in the list needs Black's numbering visible on the board to locate file 8… One strip
> makes half the move list unreadable against the board."

Hiding both strips removes both keys, at exactly the text size a low-vision learner is using —
and the draft's objection to hiding is aimed at that user: "a low-vision user running
`.accessibility5` is typically *not* a VoiceOver user — they are exactly the person the printed
numeral serves." The contract's stated rationale ("they are the first thing to yield when type
grows") records no cost and no mitigation, and accepted `Accessibility` requires "Dynamic Type
and text legibility".

Severity: **should-fix**.

Correction: name the cost and open the mitigation — "…the board keeps its floor and the chrome
keeps its own. The cost is real: the move list carries both sides' numerals, and with the strips
hidden a learner cannot locate a file from the list against the board. How that is mitigated at
those text sizes is open below."

### Finding 4.7 — the compose beat falls outside the new committing/presentational definition

> "A *committing* transition — **a move, a capture, an Undo** — runs to completion, and input
> arriving during it is **discarded rather than queued**."

The compose beat is none of those, and nothing animates during it, so under the contract it is
neither committing nor presentational. The draft closes it deliberately: "**Tap during the AI's
compose beat** | Committing (the position is the AI's to change). Discarded + acknowledged. This
matters: the beat is a period of apparent stillness, so it is the most likely moment for a stray
tap." The draft's other beat rule is also dropped — an Undo arriving between `t_ready` and the
AI's departure discards the returned-but-unplayed move, which is the extension of the accepted
"Undo while the AI is thinking cancels the search and removes the human move that triggered it."

Severity: **should-fix**.

Correction: add — "The AI's compose beat counts as committing even though nothing moves during
it, so a tap in that window is discarded and acknowledged; an Undo in it is accepted, and
discards the AI's returned but unplayed move."

### Finding 4.8 — the tint list silently drops the Play destination's Resume action

> "Tint is reserved for a moment with a single obvious next action — **开始对局** in either
> pre-start state, **结束对局** on the result card before confirmation, **完成** after it — and
> at most one tinted element is ever visible."

Reads as exhaustive. Accepted `Saving the active game…`: "The Play destination shows the active
game's metadata and a direct **Resume Game** action." The draft's §5.7 table tints it: "Play
start… **继续对局** (Resume), when an active game exists". That is the clearest single-obvious-
next-action moment in the app, and the contract's rule now forbids emphasising it.

Severity: **should-fix**.

Correction: add "…the Resume action on the Play destination when an active game exists,
**开始对局** in either pre-start state, …".

### What checks out in item 4

- **"No glass may intersect the board block" against accepted layout.** No conflict found.
  Accepted `Layout shapes` puts status above and controls below the board; accepted
  `Natural result presentation` says the card "appears **near** it" with "the final board
  remains fully visible"; #23 has the card **take the place of** the controls in stacked. All
  consistent with non-intersection.
- **Result card sharing a slot with the threefold notice.** No contradiction found. The contract
  says "one shared **slot**", not one object, so the result card's non-dismissibility and the
  notice's dismissibility both survive. A neutral threefold repetition cannot coexist with a
  natural terminal result: the repeated position is one the game has already occupied, and
  "neutral" excludes the perpetual-check and perpetual-chase adjudications that would end it.
- **Glass counts.** Side-by-side with the result card up gives card + controls ("visible but
  disabled", #23) = 2, at the "at most two" limit but inside it. During ordinary play the play
  control cluster is the one. ✅ — but see 4.9.
- **The AI-thinking indicator carrying no material** is consistent with accepted `Turn status`
  ("AI thinking is shown as activity attached to the AI's turn; it does not replace or compete
  with the side-to-move line").
- **340 ms flip** is inside the accepted 300–400 ms band. ✅
- **Capture total** `t(d) + 40` = 220 / 250 / 280 ms against the accepted "approximately 250 ms
  overall" — brackets it at the median. ✅

### Finding 4.9 — "ordinary play" is undefined, and the threefold notice sits on the boundary

"At most two are on screen at once, and **during ordinary play exactly one is**." Is an active
game showing the threefold notice "ordinary play"? If yes, the notice + the control cluster is
two and the rule fails; if no, the rule holds. The draft resolves it by making the notice
**take the slot** — "same slot… 继续对局 removes it and the slot returns to the control cluster"
— but #23 gives that displacement behaviour only to the **result card**, not to the notice, so
the merged contract does not say where the notice goes in the stacked layout.

Severity: **should-fix**.

Correction: state it — "The threefold notice occupies the same slot as the result card and
likewise displaces the play controls in the stacked layout while it is shown; **继续对局**
returns the slot to the controls."

### Finding 4.10 — the accessibility table's summary sentence contradicts its own table

> "| Increase Contrast | automatic | **keep the material, raise the container's border** |"
> "| Dark appearance | automatic | **no change; the material adapts** |"
> …
> "In every row the geometry, corner radius, and spacing are unchanged, so nothing reflows:
> **only the background is substituted.**"

The background is substituted in exactly two of the four rows. Under Increase Contrast the
*border* changes and the background does not; under dark appearance nothing is substituted at
all. The new testing gate repeats the error (see 6.11).

Severity: **should-fix**.

Correction: "In every row the geometry, corner radius, and spacing are unchanged, so nothing
reflows: only the surface's background or border is substituted."

### Finding 4.11 — the deliberate deviation from Apple's "extend content under the bars" is not named

The absolute non-intersection rule requires the board block to be inset out from under the tab
bar and toolbar, which is the opposite of SwiftUI's default and of HIG "Layout › Best
practices". The draft names it as a deviation and gives the compensating mechanism: "**We
satisfy that with the app background, not with the board:** the flat app background extends edge
to edge and under every bar, and the board block is inset out from under all of them."

Severity: **nit**.

Correction: append to the "Where it may not" paragraph — "The app background still extends edge
to edge and under every bar; it is the board block that is inset out from under them."

### Finding 4.12 — dropped without mention

- **Reduce Bright Effects** (`accessibilityReduceHighlightingEffects`), which the motion draft
  §3.9.4 identifies as aimed squarely at the two effects this design argued hardest for — the
  check pulse and the status acknowledgment beat — and calls out that "leaving it unhandled
  would be an obvious review finding".
- The frame draft §5.6's consequence that **every board colour needs light, dark and
  increased-contrast asset variants even though the board is never translucent**, "because the
  card beside it samples what is behind and around it".
- The **Differentiate Without Color** row of the draft's accessibility table (pixel-identical
  board), though accepted `Board metrics` already carries that guarantee, so this one is
  harmless.

Severity: **nit**.

---

## 5. Document-status discipline

The four owner-confirmed decisions are all present and correctly stated as decisions: strips
hidden at accessibility text sizes; the 260 ms compose-beat floor; the rescoped Liquid Glass
sentence; no tinted glass during play. ✅

Everything else in the diff is the author's. Stated as accepted, but neither owner-decided nor
supported by the drafts:

| Statement | Status | Where |
|---|---|---|
| Numerals on the record-ink 3:1 gate | **Contradicts the draft** (4.5:1 / 7:1, derived from Apple's contrast table) | 2.1 **blocking** |
| "so the two strips read as equals" | Over-claims a measured 10 % residual the draft names and accepts | 2.3 |
| "following a constant-acceleration law" | The law is an affine remap; pure √d gives 441 ms | 3.3 |
| "that ceiling is what caps a single ply at 240" | Arithmetically false | 3.1 **blocking** |
| "Reduce Motion is one rule" with no exceptions | Draft says the exception is "required, not cosmetic" | 4.1 **blocking** |
| "never at the start of the animation that shows it" | Draft: the selection haptic leads by 140 ms "and this is correct" | 4.2 **blocking** |
| "260 ms after the player's own move committed" | Draft anchors on animation completion | 3.2 **blocking** |
| the tint list as exhaustive | Draft tints Resume on the Play destination | 4.8 |
| "which is what makes the largest text sizes fit" | Asserts a resolution #23 records as open | 4.5 |
| PR body: "reproduces the placeholder the marker vocabulary had assumed" | The accepted `Board metrics` table (#19) has **no** numeral-strip row and no 16 pt figure; the placeholder is in the workspace draft `board-visual-language-design.fable-partial.md` line 57. The two "independent constraints" are the same author's two drafts. | nit, PR body only |

### Finding 5.1 — the removed numeral-strip **Need to discuss** item is not resolved

> Removed: "Decide whether file numbers may be hidden, and define the numeral strips'
> **geometry, typography, and contrast requirement**, together with the grid and
> palace-diagonal stroke weight in units of the cell pitch."

| Sub-question | Resolved? |
|---|---|
| grid and palace-diagonal stroke weight | ✅ `0.026 p` with a clamp |
| whether file numbers may be hidden | ⚠️ answers "hidden at accessibility text sizes"; says nothing about whether a user may hide them, which is what the item asks and what draft §"Open for the owner" #2 flags |
| geometry | ❌ no baseline, no no-ink band, no rounding rule (1.2, 1.3) |
| **typography** | ❌ no weights, no family, no Increase Contrast pair (2.2) |
| contrast requirement | ❌ set to 3:1 where the draft derives 4.5:1 (2.1) |

Severity: **blocking** (as the union of 2.1, 2.2, 1.2 and 1.3). Do not remove the item until the
typography and contrast are actually in the contract; or narrow it to what remains open.

### Finding 5.2 — the Liquid Glass accessibility item is resolved

> Removed: "Define how Liquid Glass behaves with contrast, Reduce Transparency, and different
> platform appearances."

The four-row table covers Reduce Transparency, Increase Contrast, both, and dark appearance for
system and custom surfaces, and says the values are ours. Windows/Fluent remains a separate
surviving item. ✅ Resolved, subject to 4.10.

### Finding 5.3 — the new motion **Need to discuss** item contradicts the paragraph above it

> New: "The durations are **accepted values, not placeholders**; a change to one is a contract
> change."

> Unedited, immediately below the new motion paragraphs: "The exact durations, easing curves,
> shadow, opacity, and feedback strength are **first-version values subject to adjustment** after
> testing on physical iPhone, iPad, and Mac hardware."

Both now stand in the same document. Since the PR's stated purpose is "recorded as accepted
values rather than placeholders", the older sentence must move.

Severity: **should-fix**.

Correction: "The easing curves, shadow, opacity, and feedback strength are first-version values
subject to adjustment after testing on physical iPhone, iPad, and Mac hardware. **The durations
are not**: they are accepted values, and changing one is a change to this contract. The lift and
drag scale factors are likewise not among them…"

---

## 6. Testing gates

Eleven gates, checked against the **contract text** rather than the PR body.

| # | Gate | Verdict |
|---|---|---|
| 1 | grid + diagonals identical, single outer boundary, 3:1 | ✅ matches; testable. The "clamp" half is untestable at any supported pitch (1.1) |
| 2 | both strips, facing, orientation, shared baseline, **read as equal in weight**, record-ink gate | ❌ see 6.2 |
| 3 | strips hidden at accessibility sizes, layout fits the minimum window on the narrowest iPhone | ❌ see 6.3 |
| 4 | seven distances, 600 ms Undo cycle, flip duration | ✅ testable; distances not enumerated in the contract (3.3) |
| 5 | AI departs no earlier than the floor "after the player's move" | ❌ inherits 3.2's wrong anchor |
| 6 | discarded not queued, presentational re-targets, flip deferred | ✅ matches and is testable |
| 7 | Reduce Motion substitution | ❌ see 6.7 |
| 8 | sound/haptics fire at completion | ❌ see 6.8 |
| 9 | three surfaces, **at most** one in play, no intersection, indicator carries no material | ⚠️ see 6.9 |
| 10 | no tinted glass in play, at most one tinted element | ✅ matches and is testable |
| 11 | four accessibility conditions, background substituted, no reflow | ❌ see 6.11 |

### 6.2 — "read as equal in weight" is not testable and is false by measurement

Subjective, and by the draft's own instrument the two strips differ by 10.2 % in ink density.
The gate either passes on opinion or fails a correct implementation. It also collides with gate
3: gate 2 says "Verify **both** numeral strips are **present**" with no scope, gate 3 says they
are hidden at accessibility sizes.

Severity: **should-fix**.

Correction: "Verify both numeral strips are present at non-accessibility text sizes, that each
faces the player whose numerals it shows, that they follow the board's orientation, that Chinese
and Arabic sit on a shared baseline, that the digits are set one weight step heavier than the
Chinese numerals, and that the numerals meet their contrast gate at 4.5:1."

### 6.3 — the gate is not executable as written

> "Verify the numeral strips are hidden at accessibility text sizes, and that the stacked layout
> then fits **within the accepted minimum window on the narrowest supported iPhone**."

#23 fixes the minimum window at **380 × 500 points of content**, "on macOS and for an iPadOS
scene alike". #23 also names the narrowest supported iPhone as **375 points wide**. 375 < 380:
the narrowest supported iPhone is *narrower than the minimum window*, and the minimum window is
not an iPhone requirement at all. A tester cannot run this.

It also references values that exist only on the unmerged `design/app-shell-and-layout` branch.

Severity: **should-fix** (and **blocking** if #24 merges before #23).

Correction: split it — "Verify the numeral strips are hidden at accessibility text sizes on iOS
and iPadOS, that the board stays at or above its 44-point pitch floor on the narrowest supported
iPhone at the largest accessibility text size, and that the stacked layout fits the accepted
minimum window as an iPadOS scene."

### 6.7 — the Reduce Motion gate enforces the defect and contradicts an existing gate

> "Verify Reduce Motion replaces position, scale and rotation with a crossfade **while leaving
> opacity, colour, stroke and shadow animations**, ordering, and every state intact."

Passing this gate requires the check pulse (stroke weight) to keep animating and the illegal-tap
destination pulse (opacity) to keep pulsing — both forbidden by accepted text, and the second
already gated the other way on `main`:

> `docs/testing.md`: "Verify the illegal-tap response survives Reduce Motion as a single
> non-animated state change of the legal destinations, and confirm it on a Mac…"

Two gates in one file that cannot both pass.

Severity: **blocking**.

Correction: "Verify Reduce Motion replaces position, scale and rotation with a crossfade of at
most 120 ms, leaves colour and shadow animations, ordering, and every state intact, **removes
the check pulse entirely rather than converting it**, and reduces the illegal-tap response to a
single non-animated state change of the legal destinations."

### 6.8 — the sound/haptics gate would fail a correct implementation

See 4.2. As written it requires the selection haptic to fire at the end of the 140 ms lift.

Severity: **blocking**.

Correction: "Verify each event's sound and haptic fire within one frame of the instant that
event is done — a move at the piece's landing, a selection at the touch that begins the lift —
and never at an arbitrary point inside the animation."

### 6.9 — two mismatches with the contract, and one gate that is an audit rather than a test

- The contract says "during ordinary play **exactly one** is"; the gate says "**at most one** is
  present during ordinary play". The PR body says "exactly one". Use the contract's word.
- "Verify **exactly three** custom glass surfaces exist" is a source-inventory audit, not a
  runtime check, and "ordinary play" is undefined (4.9). Both are still worth keeping, but the
  gate should say how: enumerate the surfaces and check each screen state against the list.
- "no glass intersects the board block" is genuinely testable from a screenshot — this is the
  best of the eleven — but only once the block's bounds are unambiguous (4.3) and only if the
  gate says whether **system** glass (tab bar, toolbar) is included. It must be; that is where
  the real risk is, since SwiftUI extends content under bars by default.

Severity: **should-fix**.

Correction: "Verify the app defines exactly the three named custom glass surfaces and no others,
that exactly one is present during ordinary play and at most two in any state, that **no glass
surface, system or custom,** intersects the board block — the board core with its half-cell
margin, and the numeral strips when shown — and that the AI-thinking indicator carries no
material."

### 6.11 — the gate asserts a behaviour the contract's own table does not have

> "…confirming **the background is substituted** and the layout never reflows."

Under Increase Contrast the contract substitutes the **border**; under dark appearance it
substitutes **nothing**. See 4.10.

Severity: **should-fix**.

Correction: "…confirming that only the surface's background or border changes, that under dark
appearance the material simply adapts, and that the layout never reflows in any of the four."

---

## Verdict

**DO NOT MERGE.**

Six blocking findings. The frame arithmetic itself is sound — 308 × 340, the clamps' behaviour
at the 720 pt cap, the seven travel durations, and the 340 ms flip all recompute exactly — but
the compressions around that arithmetic have introduced defects the source drafts explicitly
guard against: a contrast gate lowered from 4.5:1 to 3:1 for 14 pt text, a typographic rule with
no anchor that permits a numeral fainter than the grid line it labels, a stated derivation from
the 600 ms Undo ceiling that fails by 60–140 ms, a compose-beat anchor that under this
document's own vocabulary starts the AI's move before the player's capture animation ends, a
Reduce Motion rule that keeps the check pulse the accepted contract removes, and a
sound/haptics rule plus gate that would fail a correct implementation of the accepted selection
feedback. Two of the new testing gates directly contradict gates already on `main`.

None of the six is in the four decisions the owner confirmed; all six are in the author's
connective tissue around them.
