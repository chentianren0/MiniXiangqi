# Pre-merge review, round 2 — PR #24, `design/frame-motion-glass`

Re-reviewed at `adde759` ("Fix pre-merge review findings in the frame and motion contract")
against round 1 at `7485f8d`, using the same two source drafts and the accepted contracts on
`main` at `d357c4a`.

Every number re-verified by computation.

---

## Round-1 blocking findings

| # | Finding | Round-2 status |
|---|---|---|
| B1 | numerals on the 3:1 record-ink gate | ✅ **resolved** |
| B2 | "one weight step more" with no anchor | ✅ **resolved** |
| B3 | "600 ms is what caps a single ply at 240" | ✅ **resolved** |
| B4 | compose beat anchored on the committing tap | ✅ **resolved** |
| B5 | Reduce Motion rule keeps the check pulse | 🔴 **REGRESSED — now worse** |
| B6 | sound/haptics "never at the start of the animation" | ✅ **resolved** (one limb remains, should-fix) |

### B1 — resolved

> "Numerals reach at least **4.5:1** against the board surface, and 7:1 under Increase Contrast.
> They are text at 14 points at the floor, below the size at which a 3:1 ratio would suffice, so
> the record-ink gate that governs the last-move brackets does not apply to them."

Matches draft §4.3.3 exactly, including the 7:1 Increase Contrast value and the explicit
disapplication of the record-ink gate. The draft's separate requirement that "the numerals are
darker than the grid" now follows arithmetically (4.5:1 numerals against 3:1 grid). Gate 2
rewritten to test both numbers. ✅

Two residual nits, neither blocking:

- The stated *reason* is size-dependent and expires at the top of the range. At the 720 pt cap
  the numerals are 20 pt, above the 18 pt row where 3:1 applies, and the digits are bold, which
  qualifies for 3:1 at any size. The draft anticipated this: "At the capped size of 20 pt the
  3:1 row would technically apply, but **the gate does not relax with board size**: one number,
  checkable at every pitch." Add that clause so nobody relaxes the gate on a large board.
- "against **the board surface**" here, versus "against **the style's own board surface**" in
  the grid sentence three lines above and in accepted `Board metrics`. Use the accepted phrase.

### B2 — resolved

> "The Chinese numerals are therefore set **semibold** and the digits **bold**. The anchor
> matters as much as the relationship: at regular weight the single stroke of 一 measures about
> 1.02 points against a 1.14-point grid line… A residual difference of about a tenth remains."

Re-verified: `0.0731 × 14 = 1.0234` pt against `0.026 × 44 = 1.144` pt; residual
`1 − 0.2013/0.2242 = 10.2 %`. Both figures are correct and correctly attributed. This also
resolves round-1 finding 2.3 ("read as equals"). ✅

Two residuals, neither blocking:

- The **Increase Contrast weight pair** is not carried over (draft §4.3.2: "Chinese → `.bold`,
  Arabic → `.heavy`"). The contract raises the numerals' *contrast* under Increase Contrast but
  says nothing about weight. Probably sufficient; worth a sentence.
- The **font source** is still unnamed. "Semibold" and "bold" mean nothing without it, and every
  measured constant in this block — `0.887`, `0.0731`, the 26 % ratio, and the free shared
  baseline — is a property of the system cascade. Draft §4.3.2: "the system font, requested as
  `Font.system(size:weight:)` — **never a named family, and no bundled font**." One clause.

### B3 — resolved

> "…the seven distances a 7-by-7 board admits — one, two, the horse's leap, three, four, five,
> and six cells — take 180, 195, 200, 210, 220, 230, and 240 ms, following the square root of
> distance remapped onto the accepted band… **the mapping onto 180–240 is a chosen proportion
> rather than a derived one.** What *is* derived is the constraint it must respect: a decision
> cycle must complete within 600 ms, which two plies at 240 plus their overhead satisfy with
> room to spare."

The false causal claim is gone, the law is correctly characterised as a remap, the seven
distances are enumerated in the right order (the horse's √5 between two and three), and the
600 ms ceiling is correctly demoted to a satisfied constraint. Re-verified:
`2 × 240 + 60 = 540 ≤ 600`, 60 ms spare — "room to spare" is true. ✅

One should-fix: **the word "Undo" is missing.** The accepted ceiling is on Undo
("an **Undo** transition must therefore complete within 250 ms for one ply and 600 ms for a
decision cycle"), and a *forward* decision cycle contains an AI search of up to five seconds, so
"a decision cycle must complete within 600 ms" is false read generally. The rewritten gate 4
gets this right — "that a **decision-cycle Undo** completes within 600 ms" — so the gate is now
more accurate than the contract it tests. Correction: "an Undo of a decision cycle must complete
within 600 ms, which two plies even at the forward band's 240 plus their gap satisfy with room
to spare."

### B4 — resolved

> "…and 260 ms after the player's own move has finished animating — the arrival, not the tap
> that committed it, since a capture's animation outlasts the beat and the AI must not leave
> before the player's piece has landed."

Correct anchor, with the capture case named. ✅

Two should-fixes:

- "**has finished animating — the arrival**" equates two instants that differ for a capture. The
  arrival is `t(d)`; the capture removal runs to `t(d) + 40`, which is where the draft closes
  board input ("Input reopens at `t(d) + 40 ms` — the end of the capture removal"). Pick one:
  "…after the player's own move has finished animating, which for a capture includes the
  captured piece's removal."
- **The next sentence was not updated** and still carries the ambiguity this finding was about:
  "If the search has not returned within 500 ms of **the player's move**…". Same paragraph, same
  anchor problem, four words apart from the fix. Make it "within 500 ms of the same instant".

### B5 — 🔴 REGRESSED. This is now the reason not to merge.

Round 1 found that the new "one rule" *implicitly* keeps the check pulse under Reduce Motion,
against the accepted bullet that removes pulses. Round 2 has made the keeping **explicit,
justified, and gated**:

> "The check pulse is the exception that proves the rule: it animates stroke weight, not motion,
> and it is **the only announcement that a general has come under attack**, so it is **required
> rather than cosmetic** and **survives Reduce Motion intact**."

> `testing.md` gate 7: "…and **confirm specifically that the check pulse survives it**."

Four things are wrong with this, and each is checkable:

**1. It contradicts an accepted, unedited bullet ten lines above it in the same section.**

> `interaction-design.md:418` (accepted, untouched): "With Reduce Motion, the animation of lifts,
> springs, **pulses**, and long-distance travel **is removed** in favor of a brief crossfade or
> immediate state update."
>
> `interaction-design.md:428` (new): "…the check pulse… **survives Reduce Motion intact**."

Accepted `Game-state markers` (#19) confirms the check treatment is a **pulse** and that it is a
**stroke-weight** pulse: "The pair **pulses once in stroke weight** as it appears and never
again." So the one pulse the board has is the one the accepted bullet removes, and the new
sentence keeps it.

**2. It inverts the draft, while borrowing the draft's words for the opposite conclusion.**

> Motion draft §3.8.2: "**E1 — The check pulse is removed entirely, not converted.** The
> contract names pulses among what is removed. Clause (b) would have kept the pulse (stroke
> weight), so **this exception is required, not cosmetic**."

The draft's phrase "required, not cosmetic" describes the *exception* — the act of removing the
pulse. The contract now uses "required rather than cosmetic" to describe *the pulse*, reaching
the opposite conclusion with the same words. The draft's substitute is also dropped: "The
persistent double ring crossfades in over 120 ms and stays."

**3. The supporting claim is factually false, and the same paragraph disproves it.**

"it is **the only** announcement that a general has come under attack." Accepted text names at
least three carriers, none of which is the pulse:

- `Game-state markers`: "A double ring around the checked general… **shown whenever that side is
  in check**" — persistent, and it is the announcement; the pulse is the double ring's entrance.
- `Turn status`: "While the side to move is in check, a **将军** token accompanies the
  side-to-move line **for as long as that remains true**."
- `Motion and visual effects`, the accepted bullet: "Check uses a non-color-only treatment on the
  checked general **plus** one brief pulse" — treatment plus pulse, not pulse alone.
- And the new paragraph's own next clause: "a checked general **still carries its rings**."

**4. It aims a retained animation at the user Reduce Motion exists to protect.** The draft's
grounding, quoted from HIG "Accessibility › Cognitive": "Be cautious with fast-moving and
blinking animations. When you use these effects in excess, it can be distracting, cause
dizziness, and in some cases even result in epileptic episodes."

Severity: **blocking**. A fix commit has converted an implicit contradiction into an explicit
one, added a false justification, and added a testing gate that enforces it.

Correction — contract:

> "The check pulse is the exception the rule cannot derive. It animates stroke weight, which the
> rule would otherwise leave untouched, but the accepted contract names pulses among what Reduce
> Motion removes, so it is removed entirely rather than converted. Nothing is lost: the
> persistent double ring crossfades in over 120 ms and stays, and the **将军** token carries the
> state in the turn status alongside it."

Correction — gate 7: "…and confirm specifically that the check pulse does not run, while the
double ring and the **将军** token both remain."

#### B5, second limb — unaddressed, and still a contradiction between two gates in one file

Accepted `Game-state markers` (`interaction-design.md:250`, untouched):

> "**Illegal tap.** … its legal-destination markers pulse once… **Under Reduce Motion they
> change state once instead of pulsing** — a single step to a stronger appearance, held briefly
> and then restored."

That is an opacity/appearance animation, which the new rule leaves "unchanged", so the markers
would keep pulsing. `testing.md` on this branch now contains both:

> `:154` (new) — "…leaving opacity, colour, stroke and shadow animations… intact, and confirm
> specifically that the check pulse survives it."
> `:166` (accepted, untouched) — "Verify the illegal-tap response survives Reduce Motion as **a
> single non-animated state change** of the legal destinations."

These cannot both pass. Round 2 tightened `:154` without reconciling `:166`.

Severity: **blocking**, as part of B5.

Correction: add to the rule — "and the illegal-tap response, which becomes a single non-animated
state change of the legal destinations rather than a pulse."

#### B5, third limb — unaddressed

"springs lose their overshoot rather than their duration" still contradicts the accepted bullet's
"the animation of lifts, **springs**, pulses, and long-distance travel is removed". Severity:
**should-fix**. The only spring in the design is the invalid-drop return, whose Reduce Motion
substitute is already governed by clause (a) because it animates position; the clause can simply
go.

### B6 — resolved, with one limb remaining

> "Selection is the exception, and deliberately so — the feedback for picking a piece up leads
> its animation, because the touch is what the player is waiting to feel answered."

Gate 8 rewritten to match. ✅

Should-fix: **selection is not the only event that leads its animation.** Motion draft §3.10.1
states the underlying rule as "every event has exactly one instant at which it is *done*", and
then: "A selection is done at the touch… **An illegal tap is done at the touch.** A result is
done when the card appears." §3.10.4 accordingly fires three more at `t = 0` — the illegal
tap / invalid drop (`.selection` + 无效), refused input (`.selection` at the status beat), and
the save failure (`.warning` at the capsule's entry). By naming exactly one exception the
contract implies the other three follow the animation, which would put the illegal-tap haptic up
to 480 ms after the tap.

Correction: state the rule the way the draft does, which needs no exception list — "Every event
has one instant at which it is done, and both channels fire within one frame of it. A move is
done when the piece lands, not when it lifts; a selection and an illegal tap are done at the
touch, so their feedback leads the animation that shows them."

---

## Should-fixes taken — all verified

| Round-1 finding | Round-2 text | ✓ |
|---|---|---|
| 4.3 board block double-counts the margin | "the board core, **which already includes the half-cell margin**, together with the file-numeral strips" | ✅ now matches the accepted `Board metrics` table |
| 1.4 "both strips are always present" | "Both strips appear together or not at all." | ✅ |
| 4.4 "primarily" in the motion paragraph | "Board-state markers are drawn directly and never become translucent decoration; where Liquid Glass may appear is fixed under Platform visual language." | ✅ |
| 5.3 durations contradiction | "Easing curves, shadow, opacity, and feedback strength are first-version values…; **the durations fixed above are accepted rather than provisional**", and the open item narrowed to match | ✅ no contradiction remains |
| 6.2 "read as equal in weight" | "…that the numerals are set semibold and the digits bold, and that every numeral reaches 4.5:1… and 7:1 under Increase Contrast" | ✅ objective and runnable |
| 6.3 unexecutable gate | "…and that the layout still satisfies its accepted bounds when they are" | ✅ the 380 × 500 / 375 pt incoherence is gone |
| 6.9 "at most one" | "exactly one is present during ordinary play and system-provided glass is not counted among the three" | ✅ matches the contract — but see N2 |

### N1 — new defect: an accepted requirement was deleted rather than rescoped

Round-1 finding 4.4's first limb was fixed by **removing the requirement**, not by narrowing it:

> Before (accepted): "**Preserve board readability and interaction clarity** when translucent or
> material surfaces overlap or surround game content."
> After: "Translucent and material surfaces surround game content and never overlap it, per the
> boundary below."

The duty to preserve board readability and interaction clarity is now gone from the document.
What replaced it is a restatement of the non-overlap rule that the next paragraph already
states, so the bullet costs a line and carries nothing. The draft's proposal kept the duty and
removed only the stale word:

> Frame draft §5.8: "*Proposed:* '**Preserve board readability and interaction clarity** where
> material surfaces **surround** game content.'"

The owner confirmed rescoping *the Liquid Glass sentence*; the neighbouring readability
requirement was not part of that decision.

Severity: **should-fix**.

Correction: use the draft's sentence verbatim.

### N2 — new defect: gate 9 was tightened onto an undefined term

Gate 9 moved from "**at most** one is present during ordinary play" to "**exactly** one". That
matches the contract, which is why it was asked for — but "ordinary play" is still undefined and
the threefold notice's stacked placement is still unspecified (round-1 finding 4.9). Under "at
most one" both readings of the notice state passed; under "exactly one" a tester must decide
whether an active game showing the threefold notice is ordinary play, and if it is, a conforming
implementation fails the gate. The tightening made the undefined term load-bearing.

Severity: **should-fix**. One clause fixes both: "during ordinary play — an active game with
neither the result card nor the threefold notice showing — exactly one is."

---

## The four items left undone: my judgement, computed

**None of the four is blocking.** Reasoning, in order of how close each came.

### (i) The unreachable clamp floors — not blocking, but the *reason* is still false

Leaving the values costs nothing, as you say. What is not free is the sentence around them,
which is unchanged and still asserts something untrue:

> "clamped to between 0.80 and 1.60 points **so it neither disappears at the floor** nor
> coarsens on a large board — 1.14 points at the floor."

At the accepted floor the stroke is 1.144 pt; the 0.80 clamp binds only below `p ≈ 30.8`, which
no supported configuration reaches. The clause says the clamp does something at the floor that
it demonstrably does not do, in the same sentence that gives the floor value contradicting it.

Severity: **should-fix**. Correction: "clamped to a ceiling of 1.60 points so it does not
coarsen on a large board, with a floor of 0.80 points held in reserve against a lower pitch
floor — 1.14 points at the current floor."

### (ii) Missing rounding rules — not blocking

The stated values are themselves the specification at the floor (14 pt, 16 pt, 308 × 340), so an
implementer is not stuck; the ambiguity bites only away from the floor, where it is worth 1–2 pt
of strip height:

```
p = 44 : s rounded 14   -> h 15.938 -> 16   block 308 x 340   (the stated numbers)
p = 44 : s raw   14.08  -> h 16.009 -> 17   block 308 x 342   (also conforming)
p = 49 : s 16 / 15.68   -> h 19 / 18        block 343 x 381 / 379
```

Nothing downstream breaks: the glass non-intersection gate measures the actual block, and the
marker clearances are unaffected. But the contract asserts three numbers its own formulas do not
yield, in a document set that has been holding itself to reproducibility, and the fix is six
words.

Severity: **should-fix**. Correction: "`0.32 p`, **rounded to whole points**" and
"`0.08 p + 0.887 s`, **rounded up to whole points**" (draft §4.1.2).

### (iii) The `0.08 p` no-ink band and the baseline — not blocking, and I can now show why

I checked whether omitting the band lets numeral ink collide with anything. It does not, because
the draft's band was sized against a check ring that #19 replaced. Every marker under the
**accepted** geometry, measured vertically from the outer point:

```
check outer ring, outer edge (0.4875 + 0.025/2)      0.5000 p
check ring at pulse peak (grows inward only)         0.5000 p
capture ring, outer edge                             0.5000 p
keyboard focus square, vertical extent               0.4800 p
selection ring, outer edge under the x1.05 lift      0.4778 p
pointer hover fill / last-move brackets              0.4500 p
```

Nothing exceeds `0.50 p`, which is what accepted `Board metrics` guarantees ("a radius of at
most `0.50 p`"; "the outermost points' markers are contained by the margin and never reach the
coordinates outside it"). The draft's premise — "the S6 double check ring has its outer edge at
`0.56 p`… that ring **overhangs the core boundary by `0.06 p`**" — comes from the pre-acceptance
S6 in `board-visual-language-design.fable-partial.md:200` (stroke `0.04 p` at radii `0.46 p` and
`0.54 p`), which #19 superseded with stroke `0.025 p` at `0.4325 p` and `0.4875 p`.

Worst case if an implementer simply centres the numerals in the strip: ink begins `0.5407 p`
from the point — inside the draft's intended `0.58 p` band, and clear of every accepted marker
by `0.04 p`. So the omission is worth about 3.6 pt of vertical placement variation and no
collision.

Severity: **should-fix**, downgraded from round 1. The band is still worth stating, because
`0.08 p` is otherwise an unexplained term in a formula the contract presents as measured — but
it is now optical breathing room, not clearance, and the contract should say so rather than
inherit a justification that no longer holds.

### (iv) The unrecorded cost of hiding the strips — not blocking

An omitted trade-off, not a false statement. It becomes more visible once the fit claim is cut
(below), since the bullet would then present hiding as neither pure gain nor free.

Severity: **should-fix**. Draft §4.2.1 reason 2 is the sentence to borrow: the move list carries
both sides' numerals, so with the strips hidden a learner cannot locate a file from the list
against the board — at exactly the text size the printed numeral was serving.

### Also unaddressed and not on your list

- **Round-1 4.10 and 6.11** — the accessibility table's summary sentence, "only the background
  is substituted", is contradicted by its own table: under Increase Contrast the **border**
  changes and the background does not; under dark appearance nothing is substituted. Gate 11 is
  unchanged and repeats it. Not mentioned in either direction, so flagging it so it is not lost.
  **should-fix.**
- **Round-1 4.7** — the compose beat still falls outside "a move, a capture, an Undo", so no rule
  covers a tap during the beat, which the draft calls "the most likely moment for a stray tap".
  **should-fix.**
- **Round-1 4.8** — the tint list still reads exhaustive while omitting the accepted Play
  destination's "direct **Resume Game** action". **should-fix**, as you have it.

---

## #23 and the "makes the largest text sizes fit" claim — cut it

> "Hiding them removes 32 points of height at the floor, **which is what makes the largest text
> sizes fit**."

Yes, cut it. Four reasons, in order of weight:

1. **It asserts a resolution #23 records as open**, and #23 cannot currently supply it — its
   remaining open item is "how accessibility text sizes are accommodated once the control row
   and turn status grow", and it is itself DO NOT MERGE with the minimum window among the
   blocking findings. #24 would be resting a claim on a number that is under revision.
2. **The margin is too thin to assert.** Recomputed against the draft's own accessibility budget
   for a 375 pt iPhone (~314 pt, and that already assumes the status wrapped to three lines and
   the control cluster restacked vertically):

   ```
   strips shown  : 7.16 p + 30.16 ≤ 314  →  p ≤ 39.64  — below the 44 pt floor
   strips hidden : 7 p            ≤ 314  →  p ≤ 44.86  — 0.86 pt of pitch, 6 pt of height
   ```

   Hiding the strips does move the layout from failing to passing, so the claim is not wrong —
   but 6 pt on an unstated budget, with chrome behaviour neither PR specifies, is a finding, not
   a contract sentence.
3. **It is not owner-decided.** The owner decided that the strips hide. "And that is what makes
   the largest text sizes fit" is the author's addition, and it is the kind of connective claim
   that produced five of the six round-1 blocking findings.
4. **Gate 3 has already stopped asserting it** — it now reads "the layout still satisfies its
   accepted bounds" — so the contract body is currently making a stronger claim than the gate
   that tests it. Cutting realigns them.

Cutting costs nothing: the decision and the 32 pt figure both survive.

Proposed replacement for the last two sentences of that bullet:

> "…the board keeps its floor and the chrome keeps its own. Hiding them returns 32 points of
> height at the floor. Whether that is sufficient at the largest text sizes depends on how the
> control row and turn status are accommodated as they grow, which remains open below; the cost
> is that the move list carries both sides' numerals, and without the strips a learner cannot
> relate a move in the list to a file on the board."

---

## Verdict

**DO NOT MERGE.**

Five of six blocking findings are properly fixed, and the arithmetic in every fix re-verifies —
1.02 against 1.14 pt, the 10 % residual, `2 × 240 + 60 = 540 ≤ 600`, the seven distances with the
horse's leap in the right place. The four items you left undone are all correctly judged: none is
blocking, and (iii) is now demonstrably harmless, because the collision the band guarded against
belongs to an S6 geometry #19 replaced.

One finding blocks, and it is the one the fix commit made worse. B5 was an implicit contradiction
with the accepted Reduce Motion bullet; it is now an explicit one, carrying a justification that
the same paragraph disproves ("the only announcement that a general has come under attack" —
against the persistent double ring, the **将军** token, and the accepted bullet's own "treatment
… **plus** one brief pulse"), reusing the draft's phrase for the opposite conclusion, and gated
by a new test that requires the pulse to run for the users Reduce Motion exists to protect. Its
second limb leaves `testing.md` with two gates, at lines 154 and 166, that cannot both pass.

The correction is one sentence in the contract and one clause in gate 7, plus the illegal-tap
clause. Everything else on this list is should-fix.
