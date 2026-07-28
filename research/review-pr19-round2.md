# Pre-merge review, round 2 — PR #19 `design/board-visual-system`, commit `028e82d`

> **Status: Workspace-only review report. Non-normative.**
>
> Follow-up to `discussion-drafts/review-pr19.md`. Nothing in the product repository was
> modified; no remote write, comment, review, or merge. Read-only `gh` under the
> project-scoped identity (`ppppvz`).
>
> Reproduction: `discussion-drafts/rv19-geom2.py` (all of §1–§3, recomputed at `p = 44`
> from the new text's own primitives, not from the previous round's numbers).
> `discussion-drafts/rv19-rules.py` re-used unchanged for §4.
>
> Branch tip is now `028e82d`; the PR is three commits and two files.

---

## Summary

**All four blocking findings are fixed.** I recomputed each rather than reading the new
prose, and each lands exactly on the numbers the text claims. The should-fix list was
largely worked through, several items more thoroughly than I asked for.

**One regression was introduced by the bracket fix** — and it is partly my fault: my
round-1 correction was arithmetically wrong and would have caused an actual overlap. The
author chose a safer number than I recommended. Details in §5.

---

## 1. Blocking item 1 — the air-gap rule and the keyboard focus ring. **FIXED**

### 1.1 The focus ring's new band (verified, item (a))

> "a rounded-square outline, `0.92 p` square with stroke `0.04 p` and a `0.14 p` corner
> radius … **Its band runs `0.44 p` to `0.48 p`, so it clears even a selected disc at full
> lift and stays inside the cell.**"

Recomputed: half-side `0.46 p`, half-stroke `0.02 p` → band **`[0.44000, 0.48000] p`** at
the four edge midpoints. The stated band is exact.

| Test | Result |
|---|---|
| vs air-gap floor `0.42 p` | **passes by 0.880 pt** (was −0.440 pt) |
| vs disc at rest (`0.40 p`) | clearance **1.760 pt** |
| vs **lifted** disc, ×1.05 (`0.42 p`) | clearance **0.880 pt** — exactly the `0.02 p` air gap |
| containment, square half-extent `0.48 p ≤ 0.50 p` | **passes**, 0.880 pt slack |
| corner radius `0.14 ≤ 0.46` half-side | valid rounded rect |
| max radial reach at the corners | `0.61255 p`, inside the cell corner at `0.70711 p` |
| adjacent point: focus `0.48` + capture `0.50` = `0.98 p` | no collision |

The prompt's round-1 question — does any non-scaling marker still clear the lifted disc? —
now answers **yes for every marker**. The fix is exactly the geometry I recommended, and
the arithmetic holds.

Side effects of the move, all benign and all inside the ring's stated crossing exemption:

| Pairing | Before | After |
|---|---|---|
| focus × check **inner** ring | covered it entirely (1.100 pt) | overlaps 0.220 pt |
| focus × check **outer** ring | disjoint 0.220 pt | overlaps 0.220 pt |
| focus × capture ring | 1.100 pt | 1.540 pt |
| focus × selection ring (lifted) | 1.045 pt | 1.386 pt — the selection band `[0.44625, 0.47775]` now sits wholly inside `[0.44, 0.48]` |

The last row means that at the four edge midpoints a keyboard-selected piece's selection
ring is fully under the focus stroke. It is a local crossing (the square's distance from
centre rises to `0.5657 p` at the corners), it is explicitly permitted, and the check-ring
case improved much more than this one worsened. **nit**, no action needed.

### 1.2 The rescoped rule is now true for all eleven markers (verified, item (c))

> "On an occupied point, no game-state marker's ink falls inside `0.42 p` and none touches
> the disc face, **measured against the disc at its largest** — a selected disc is scaled,
> and the rule holds at that size too. … **Three markers are outside the rule** because no
> disc is present to clear: the legal-destination dot and the drag-origin marker, which
> belong to empty points, and the pointer hover fill, which is drawn beneath the pieces."

Recomputed inner ink for every marker that can sit on an occupied point, including both
animated extremes:

```
selection ring (rest)        0.42500   PASS
selection ring (x1.05)       0.44625   PASS
capture ring                 0.44500   PASS
capture ring, thickened      0.43000   PASS
check inner (rest)           0.42000   PASS  (boundary, by construction)
check inner (pulse peak)     0.42000   PASS  (inner edge pinned)
check outer (rest)           0.47500   PASS
check outer (pulse peak)     0.46750   PASS
keyboard focus ring          0.44000   PASS
```

Plus the three named exemptions. **Eight pass, three exempt, none fail.** The "measured
against the disc at its largest" clause is correct: the largest disc that occupies a point
is the selected disc at ×1.05 (`0.42 p`); the ×1.10 dragged disc occupies no point, which
the containment bullet's new exemption establishes independently. The capture target never
lifts ("The target does not lift"), so the thickened capture ring's `0.43 p` inner edge is
measured against a `0.40 p` disc — 1.32 pt of gap.

### 1.3 `testing.md` states the same rule. **verified — near-verbatim**

| | `interaction-design.md` | `testing.md:146` |
|---|---|---|
| style decoration | "at or inside `0.40 p`" | "no piece style draws decoration beyond `0.40 p`" ✓ |
| marker floor | "On an occupied point, no game-state marker's ink falls inside `0.42 p`" | "on an occupied point no game-state marker's ink falls inside `0.42 p`" ✓ |
| measurement | "measured against the disc at its largest" | "measured against the disc at its largest" ✓ |
| exemptions | destination dot, drag-origin marker, hover fill | "with the legal-destination dot, the drag-origin marker, and the pointer hover fill outside that rule" ✓ |
| containment | "at rest and throughout every animation" | "at rest or at any moment of its animation, including the selection lift, a drag's target strengthening, and the check pulse" ✓ |
| drag exemption | "A dragged piece is the one exception, and only while it is dragged" | "A dragged piece is exempt from containment only while it is dragged" ✓ |

The one asymmetry — `interaction-design` adds "and none touches the disc face", which
`testing.md` omits — is not a gap: on an occupied point the disc is at most `0.42 p`, so
"no ink inside `0.42 p`" already implies it.

**nit** — the exemption sentence's lead-in is illogical for its own third item: "Three
markers are outside the rule **because no disc is present to clear**: … and the pointer
hover fill, **which is drawn beneath the pieces**." A disc very much *is* present under a
hovered occupied point; the fill's reason is z-order, not absence. Recommend: *"Three
markers are outside the rule: the legal-destination dot and the drag-origin marker, because
they belong to empty points, and the pointer hover fill, because it is drawn beneath the
pieces."*

---

## 2. Blocking item 2 — the check pulse bound. **FIXED**

> "because the rings sit exactly on both structural limits at rest, the pulse thickens each
> ring **to at most `0.0325 p` growing only into the gap between them**, so neither `0.42 p`
> nor `0.50 p` is crossed and **at least `0.015 p` of gap survives**."

Recomputed at the peak (item (b)):

```
rest : inner [0.42000, 0.44500]   outer [0.47500, 0.50000]   gap 1.3200 pt
peak : inner [0.42000, 0.45250]   outer [0.46750, 0.50000]   gap 0.6600 pt
0.42 crossed?  False        0.50 crossed?  False
surviving gap = 0.015000 p  ->  EXACTLY the stated bound
```

Both structural limits hold at the peak, and the surviving gap is exactly `0.015 p`, not
merely "at least". `testing.md:147` gates the identical numbers. **The arithmetic is
correct and the rule is now satisfiable.**

Two observations, neither requiring action:

- **nit** — at the peak the visible gap is 0.66 pt (≈1.3 device px at 2×), so for the
  duration of the pulse the pair reads close to a single thick ring before settling back to
  1.32 pt. That is an acceptable consequence of a one-shot pulse, and the alternative
  (pulsing only the outer ring) would be less symmetric.
- **nit** — because each ring grows from a pinned edge, the centre-lines shift during the
  pulse (inner `0.43250 → 0.43625`, outer `0.48750 → 0.48375`). The rings appear to lean
  toward each other very slightly. Worth knowing at implementation time; not worth a
  sentence in the contract.

---

## 3. Blocking item 3 — the save-failure copy. **FIXED**

### 3.1 No contradiction remains (item (d))

> "**A failed save on the user's own action** — a move or an Undo — is reported by a
> transient capsule … reading **无法保存这一步，请重试。** … **When the failed save is the
> AI's reply no capsule appears** and the board shows nothing at all, because the retry is
> the app's to perform and not the user's, as Move input above requires. **This capsule is
> for a single ply**; a failed draw claim, resignation, or result confirmation uses the
> accepted **无法保存对局** retry presentation instead"

Checked against every accepted bullet that touches a failed save:

| Accepted bullet | Status |
|---|---|
| `Move input`:199 — "A legal move or an Undo whose immediate save fails … brief non-blocking feedback distinct from illegal-move feedback … the user may simply try again" | **consistent** — the capsule *is* that feedback, and 请重试 matches "may simply try again" |
| `Move input`:200 — "When the failed save is the AI's reply … the app requests a new AI move **rather than asking the user to retry a move that is not theirs**" | **consistent** — no capsule, explicitly cross-referenced |
| `Move input`:201 — "A failed draw claim, resignation, or result confirmation uses the accepted **无法保存对局** retry presentation" | **consistent** — named and routed |
| `Saving the active game…`:288 — 保存并继续 archive failure uses 无法保存对局 | **not contradicted** — that is a navigation flow with its own accepted modal, outside "board-state messages" |
| `Sound and haptics`:397 — warning pattern "reserved for genuine failures such as an action that could not be saved" | **consistent** — "with the system warning pattern reserved for genuine failures" |

### 3.2 The three branches are jointly exhaustive for board-state save failures

Enumerated from the accepted contract, every persistence event that can fail while a board
is on screen: a human move; an Undo (one ply in Free Play, a decision cycle in
human-vs-AI); the AI's reply; a draw claim (以和棋结束); a resignation; a result
confirmation (结束对局). Branch 1 covers the first two, branch 2 the third, branch 3 the
last three. Game creation and 保存并继续 are pre-start and navigation flows with their own
accepted error presentations. **Exhaustive.**

`testing.md:152` gates all three branches by name. That gate did not exist before.

**nit** — "This capsule is for a single ply" is inexact for the human-vs-AI Undo, which
removes a full decision cycle (two plies). The scope statement that matters — "a move or an
Undo" — is correct; only the gloss is loose. Recommend "for a move or an Undo" instead of
"for a single ply", or leave it.

---

## 4. Blocking item 4 — illegal tap under Reduce Motion. **FIXED**

> "**Under Reduce Motion they change state once instead of pulsing** — a single step to a
> stronger appearance, held briefly and then restored — so the answer still arrives,
> **without animation and without depending on haptics that a Mac does not have**. … Either
> way the platform's lightest selection-weight feedback fires **where the hardware provides
> it**"

This closes the hole exactly. The Mac-with-Reduce-Motion path now has a visual response,
and the haptic clause is no longer stated as unconditional — which also reconciles it with
`Sound and haptics`' "on a device without them the toggle is unavailable … and no substitute
effect is invented."

I checked the other half of the state too: with **nothing** selected the response is the
turn-status beat, which is "in opacity only, with no movement" — an opacity change is
precisely the "brief crossfade" that `Motion` prescribes as the Reduce Motion substitute, so
that path survives Reduce Motion unchanged. **Both branches now deliver a visual response
under Reduce Motion with no haptics.**

`testing.md:151` gates it and names the Mac case explicitly.

**nit** — "a stronger appearance" is undefined. The obvious reading is the drag-strengthening
step already specified (dot Ø `0.22 p → 0.33 p`), which is contained and defined. One clause
would remove the ambiguity; it is a first-version value, so it can wait.

---

## 5. The bracket inset — fixed as asked, with one regression, and my round-1 number was wrong

### 5.1 What I got wrong

My round-1 correction read: *"inset `0.06 p` (elbow `(0.44, 0.44)`, max extent `0.4625 p`,
adjacent gap `0.075 p` = 3.3 pt)."* I checked the adjacent-bracket gap and the containment
bound and did **not** re-check the bracket-to-ring clearance, which moves in the opposite
direction. Recomputed:

```
inset 0.06 p ->  nearest bracket ink 0.499036 p  ->  vs capture ring outer 0.50:  -0.0424 pt   OVERLAP
inset 0.05 p ->  nearest bracket ink 0.512850 p  ->  vs capture ring outer 0.50:  +0.5654 pt   disjoint
```

**My recommendation would have made the last-move brackets overlap the capture ring.** The
author took `0.05 p` instead and preserved disjointness. That was the right call and it
should be recorded as such.

### 5.2 What `0.05 p` achieves, and what it costs (item (e))

| Quantity | inset `0.03 p` | inset `0.05 p` |
|---|---|---|
| elbow | `(0.47, 0.47)` | `(0.45, 0.45)` |
| max ink extent (containment, limit `0.50`) | `0.49250 p` — 0.330 pt slack | `0.47250 p` — **1.210 pt slack** ✓ |
| adjacent cells' facing arms, ink gap | 0.660 pt | **2.420 pt** ✓ |
| diagonal-neighbour brackets | 0.933 pt | **3.422 pt** ✓ |
| nearest bracket ink radius | `0.54053 p` | `0.51285 p` |
| **vs capture ring outer edge `0.50 p`** | **1.783 pt** | **0.565 pt** ← regression |
| vs selection ring lifted `0.47775 p` | 2.762 pt | 1.544 pt (composition unreachable) |
| vs grown destination dot `0.165 p` | 16.523 pt | 15.305 pt |

**Containment holds and disjointness holds** — the two things you asked me to check. The
document's claim, "a destination dot or a capture ring coexists with last-move brackets
**without touching them**," remains literally true.

### 5.3 The regression. **should-fix**

The bracket-to-capture-ring clearance falls from 1.783 pt to **0.565 pt at the floor** —
about 1.1 device px at 2×, between a 1.98 pt bracket stroke and a 2.42 pt ring stroke. The
composition is routine: the opponent moves a piece to a square, so brackets sit on that
cell; you then select a piece that can capture it, so a capture ring rings that same disc.

The reason I would fix it rather than accept it is the PR's own standard. The stated
justification for raising the macOS floor is that below 44 pt "the vocabulary's finest
distinctions — the disc-to-marker air gap, and the gap between the two check rings — fall
to fractions of a point." Those two distinctions are **0.88 pt** and **1.32 pt** at the
floor. A 0.565 pt clearance is smaller than either, i.e. below the design's own worst
protected case, at the pitch the floor was raised to guarantee.

The fix is one number, and it should be the **arm**, not the inset — the two parameters
trade against different constraints, which is the trap I fell into. Holding inset `0.05 p`
and stroke `0.045 p`:

```
arm 0.16 p -> clearance 0.565 pt   (arm 7.04 pt)
arm 0.15 p -> clearance 0.807 pt   (arm 6.60 pt)
arm 0.14 p -> clearance 1.053 pt   (arm 6.16 pt)
arm 0.13 p -> clearance 1.306 pt   (arm 5.72 pt)   <- recommended
arm 0.12 p -> clearance 1.563 pt   (arm 5.28 pt)
```

**Correction: arm `0.16 p → 0.13 p`.** That keeps the adjacent-bracket gap at 2.420 pt,
containment slack at 1.210 pt, and lifts the ring clearance to 1.306 pt — above both the air
gap and the check-ring gap. The arm is still 5.72 pt at the floor, an unambiguous L. No
other number changes, and the sentence "The inset is what keeps two adjacent cells' brackets
visibly separate" stays true.

I would not block on this: nothing overlaps, no statement in the document is false, and the
two marks differ in ink strength (record vs active) and in shape (angular vs circular arc).
But it is one number and the section is open.

---

## 6. Butt caps (item (f)). **FIXED, and the proportions are right**

> "Strokes use rounded caps, **except the capture ring's dashes, which use butt caps** so
> that the specified gaps are the gaps a player actually sees."

Recomputed at centre-line `0.47250 p`:

```
12 x (18 deg + 12 deg) = 360 deg          closes exactly
visible dash  0.148440 p = 6.5314 pt      (round caps would have given 8.951 pt)
visible gap   0.098960 p = 4.3542 pt      (round caps would have given 1.934 pt)
duty cycle    60.0 % ink                  (round caps: 82.2 %)
```

Answering the question directly: **no, the gaps are not too wide and the dashes are not too
short.** Twelve 6.53 pt dashes separated by 4.35 pt gaps around a 2.97 pt-wide annulus at
the *smallest supported* pitch is a clearly-read dashed ring, and the ratio is the designed
60/40. Every larger board only improves it.

Containment is unaffected: a butt cap's end face on an arc is radial, so the stroke's
farthest point is still the outer edge at exactly `0.50 p`.

**nit, unaddressed from round 1** — the dash **phase** is still unspecified. Two adjacent
capture rings are exactly tangent; if both phase a dash onto the line of centres, two
`0.055 p` strokes meet and read as one `0.11 p` blob. With butt caps this is now more likely
to look like a deliberate join than with round caps. One clause fixes it: *"a gap is centred
on each cardinal direction."*

---

## 7. The remaining round-1 fixes, verified

| Round-1 finding | Verdict |
|---|---|
| §1.3 dragged ring `0.5005 p`; scale declared adjustable | **Fixed both ways.** Containment now exempts a dragged piece explicitly, and `Motion` now reads "The lift and drag scale factors are **not** among them: the marker geometry is derived from them, so changing one is a change to Board metrics." |
| §1.8 shape families / non-confusability | **Fixed.** The false "each shape has exactly one member" is replaced by a true per-family claim ("filled against hollow, solid against dashed, single against double"), and the two rectangular markers are placed outside the families with a stated reason. Verified against the actual membership: circles = filled dot vs hollow dot ✓; rings = solid vs dashed vs double ✓; corner marks = one ✓. |
| §2.2 capture/check exclusion reasoning | **Fixed.** Now "because no position a player can reach offers a general as a legal capture target — one in which a general could be taken is already illegal." That is the true reason, correctly attributed to reachability rather than to the movement rules. My engine counterexample (`3k3/7/7/7/3R3/7/3K3 w` → `d3d7`) no longer falsifies it. |
| §2.3 replay brackets | **Fixed.** "They always mark **the move that produced the position on screen** … **replay moves them as it steps**." Re-verified claim (b) under the new wording: the move that produced any displayed position belongs to the side not to move; its origin is empty and its destination holds the mover's piece; the checked general belongs to the side to move. True for normal play, all four Undo forms, and replay in both directions. The closing paragraph's derivation now matches. |
| §4.4 stale `Motion` bullets | **Fixed.** "a **dashed** ring"; "Check uses a **non-color-only treatment on the checked general**" — both "persistent" and "king-square" gone, and the check bullet itself now reads "shown whenever that side is in check **and the general is not held**", removing the self-contradiction. `Sound and haptics` now names the actual visual difference. |
| §4.5 Differentiate Without Color | **Fixed.** Scoped to game-state markers with the focus ring excepted, in both files. |
| §4.6 可判和 stranded | **Fixed.** "the two **transient** board-state messages … The placement of the persistent **可判和** affordance remains open below and is not settled by this." |
| §4.7 将军 token in replay | **Fixed** in `interaction-design` (both the Turn status bullet and the held-general bullet). See §8 for the stale gate. |
| §4.8 marker-ink reference surface | **Fixed.** "against that style's own board surface **and against the pointer hover fill composited over it** … with shadows excluded" — matching `Piece styles`' existing shadows-removed convention, and mirrored in `testing.md:148`. |
| §4.9 preview vs the pitch floor | **Fixed, and more than I asked.** "`p ≥ 44 pt` on every **interactive** board … A pre-start preview is not interactive and carries no floor, so **it shows no game-state markers** and its symbol size is governed by legibility rather than by this system." That also disposes of the round-1 symbol-legibility consequence. |
| §3.2 / §3.3 macOS claims | **Fixed.** "the most constrained configuration **measured so far**", the unsupported "never forces the window to fill the screen" deleted, and replaced by "verifying that it does … is a required check rather than an assumption." |

---

## 8. Newly broken, or newly stale (item (g))

Beyond §5.3, three things:

1. **`testing.md:154` is now contradicted by `interaction-design.md`. should-fix, one line.**
   > `testing.md`: "Verify the **将军** token is present **for exactly as long as the side to
   > move is in check**"
   > `interaction-design.md`: "**Replay has no side-to-move line and therefore no token**"

   The gate was written before the replay exemption existed. A tester applying it literally
   fails a correct replay. **Correction:** "…present during play for as long as the side to
   move is in check, and absent in replay, where the check rings carry it alone."

2. **`testing.md:155` gates only half of the new brackets rule. should-fix, one line.**
   > `testing.md`: "Verify last-move brackets follow the game's current last move **through
   > Undo**"
   > `interaction-design.md`: "…an Undo moves them … **replay moves them as it steps** …"

   **Correction:** add "and through replay navigation in both directions".

3. **The closing paragraph's containment sentence is now narrower than the rule it cites.
   nit.** `Board metrics` gained "A dragged piece is the one exception," but `Game-state
   markers` still opens its composition argument with the unqualified "Because every marker
   is contained by its own cell, only markers on the *same* point can ever meet." A reader
   arriving at that paragraph does not have the exception in view. One subordinate clause
   fixes it.

Nothing else regressed. I re-checked the anchors (`#board-metrics`, `#game-state-markers`,
`#layout-shapes` — plus the two new links from `Motion` into `#board-metrics` and
`#game-state-markers`; all five resolve, no duplicate slugs), the metrics table, the
adjacent-point matrix, and the same-point matrix. No new collision anywhere.

---

## 9. Round-1 should-fix items **not** addressed, and whether any blocks

None of these blocks. Ranked by how much I would want them.

| # | Item | Why it does not block |
|---|---|---|
| 1 | **§6.4 — the drag drop target.** "follows the touch or pointer **directly**" vs "offset `0.5 p` above the touch point"; nothing says whether the drop target and the `0.45 p` strengthening test are measured from the finger or from the offset disc; a `0.5 p` offset carries the disc past the margin on the top rank. | The most substantive omission, and the one likeliest to produce divergent iOS/iPadOS implementations. But it is pre-existing text this PR did not touch, and `Move input` already fixes the commit rule ("Dropping on a legal destination commits the move"). Best handled with the motion work. |
| 2 | **§6.3 — one beat, two meanings.** An illegal tap with nothing selected produces the identical signal as a tap while the AI is thinking, though only the latter is "unavailable input". | A design conflation, not a contradiction; `testing.md` encodes both consistently. |
| 3 | **§2.4 — brackets during the Undo reversal animation** (250 ms / ply, 600 ms / cycle). | Old and new bracket sets coexist mid-transition; a transient. |
| 4 | **§2.5 — Free-Play voice.** "the enemy disc"; "one rings **the player's** piece, the other **an opponent's**"; "only the piece **the player holds** lifts". In Free Play "the same person controls both sides". | Wording; the underlying claim ("the side-to-move's piece" vs "a piece of the other side") is sound and I verified it. |
| 5 | **§5.3 — typography narrowed.** The old open item covered "the visual system for them and for typography"; the new one covers only the numeral strips. Move-list, turn-status, result-card, and metadata typography are now in neither the accepted text nor `Need to discuss`. | An ownership gap in an open list, not in accepted behaviour. |
| 6 | **§5.1 — two routing gaps.** The haptic binding for unavailable input is assigned while "Define the haptic events behind the accepted haptics toggle" is open; the silent replay tap sits against accepted line 148, "Clear prevention or explanation of unavailable actions". | Both are legitimate proposals stated as accepted; the owner may simply be content with them. Worth one sentence each acknowledging the route. |
| 7 | **§1.7 dash phase**; **§1.10** marker-band table row (`0.42–0.50 p` is true only of the ring markers), outermost rings exactly tangent to the coordinate strip, bracket elbow on the palace diagonal; **§4.10** three terms for the numeral strip, line 143's "must cover", line 199's missing cross-reference; **§6.2** the result state not listed among the deliberately-unmarked states, the 将军 token after a confirmed result, the hover fill in replay; **§3.2** the measured Mac model and Dock configuration still unnamed. | Nits. |

---

## Verdict

**MERGE**

All four blocking findings are fixed, and each was verified by recomputation rather than by
reading the prose: the focus ring's band is exactly `[0.44, 0.48] p` and clears the lifted
disc by 0.880 pt; the check pulse peaks at inner `[0.42, 0.4525]` / outer `[0.4675, 0.50]`
with exactly `0.015 p` of gap and neither limit crossed; the air-gap rule is now true for
all eight in-scope markers with three named exemptions, stated identically in both files;
the save-failure branches are non-contradictory and jointly exhaustive; and the illegal-tap
response survives Reduce Motion with no haptics on both of its branches. The bracket inset,
butt caps, dragged-piece exemption, reachability argument, replay brackets, 将军 token,
ink reference surface, preview exemption, and the `Motion` and macOS wording are all fixed
as described.

Three one-line changes I would land in the same PR, none of them blocking:

1. **Bracket arm `0.16 p → 0.13 p`** (§5.3), restoring 1.306 pt of clearance to the capture
   ring while keeping the 2.420 pt adjacent-bracket gap the inset change bought. This is the
   only finding of substance in round 2, and it exists because my round-1 number was wrong.
2. **`testing.md:154`** — exempt replay from the 将军 token's lifetime, which
   `interaction-design.md` now does and the gate does not.
3. **`testing.md:155`** — extend the brackets gate to replay navigation, matching the new
   "the move that produced the position on screen" rule.

Everything else outstanding is a nit or belongs to the still-open motion, typography, and
haptics work.
