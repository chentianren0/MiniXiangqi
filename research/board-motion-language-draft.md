# 3. The motion language

> Retrieval note, matching "How to read this document": every Apple citation
> below was retrieved through
> the Xcode documentation tool on 2026-07-27 in this session. Where Apple
> publishes no value — which is the case for every per-interaction duration in
> this section — I say so in §3.12 and own the number.

Relationship to `discussion-drafts/apple-ui-design-survey.md` §5: that section is
the direct predecessor of this one and I reuse its verified ground, but it
predates four accepted decisions and one geometric result from §2. §3.11 lists
every place I supersede it and why.

---

## 3.1 Design position — three rules the whole table obeys

**Rule A. Motion reports; it never decorates.** Every animated transition in the
board layer exists because a state changed and the user must be able to say
*which* state and *why*. Nothing on this board eases, springs, or pulses to look
alive. Grounding: "Add motion purposefully, supporting the experience without
overshadowing it. Don't add motion for the sake of adding motion. Gratuitous or
excessive animation can distract people and may make them feel disconnected or
physically uncomfortable" (HIG "Motion › Best practices"); and, for the two
interactions this app repeats hundreds of times per game, "In apps, generally
avoid adding motion to UI interactions that occur frequently" (HIG "Motion ›
Providing feedback").

**Rule B. Timing is a function of the board, never of the screen.** Every
duration below is derived from distance measured in cell pitches `p`, not in
points. A move of three cells takes the same time on a 720 pt iPad board and a
196 pt Mac board; the small board simply moves fewer points per second. The
alternative — constant screen velocity — would make the same chariot move take
2.5× longer on iPad than on a minimum Mac window, which is the wrong invariant
for a game whose identity is the position, not the pixels.

**Rule C. The board layer uses eased curves; springs appear exactly once.**
Spring animations in SwiftUI are specified by a *perceptual* duration, which the
documentation defines as "approximately equal to the settling duration"
(`Animation.spring(duration:bounce:blendDuration:)`) — approximately, not
exactly. That is a poor fit for a motion language with two hard budgets: the
accepted 250 ms one-ply and 600 ms decision-cycle Undo ceilings. Eased curves
have exact durations and compose arithmetically. The one place a spring is
right is the invalid-drop return (§3.3), where the physical metaphor *is* the
point and no budget depends on it.

Everything in §3.3 is proposed. Everything it must fit inside — the 120–160 ms
select band, the 180–240 ms travel band, the ~250 ms capture target, the 250/600
Undo ceilings, the 300–400 ms flip band, one-pulse-never-flashing, and the
Reduce Motion substitution — is accepted (`interaction-design.md § Motion and
visual effects`).

**One platform note.** Every number in this section is platform-independent and
belongs to the shared board identity the contract requires
(`§ Platform visual language`). Only the API names are Apple-specific; the WinUI
mapping is a separate exercise and changes no value here.

---

## 3.2 Travel time as a function of distance

### 3.2.1 The problem, stated with the actual numbers

The accepted contract says "An ordinary move travels smoothly to its destination
in approximately 180–240 ms" — one band for every move. On this board the moves
that band has to cover are, per `xiangqi-rules.md § Movement`:

| Piece | Move | Displacement |
|---|---|---|
| King | one square orthogonally, inside the palace | `1 p` |
| Soldier | one square forward or sideways | `1 p` |
| Horse | Xiangqi horse move (one orthogonal, one diagonal) | `√5 p ≈ 2.236 p` |
| Chariot | any number of unobstructed squares orthogonally | `1 p` … `6 p` |
| Cannon | as chariot when quiet; over one screen when capturing | `1 p` … `6 p` |

So the ratio between the longest and shortest legal move is exactly **6:1**, and
the accepted duration band spans only **1.33:1** (240/180). A single fixed
duration inside that band would give a one-cell soldier step a velocity of
`5 p/s` and a six-cell chariot sweep a velocity of `30 p/s` — the same 200 ms
event, six times the speed. That is not a rendering nicety: a learner watching a
chariot cross the board in 200 ms cannot follow which file it travelled along,
and a soldier taking 200 ms to move one cell feels like the app is thinking.

### 3.2.2 The proposed rule: constant peak acceleration, remapped onto the band

**Proposed.** Travel duration follows a square-root law in distance, affinely
remapped so that its endpoints land exactly on the accepted band's endpoints:

```
t(d) = 180 ms + 60 ms × (√d − 1) / (√6 − 1)          d in units of p, 1 ≤ d ≤ 6
```

Why `√d`. Under constant acceleration, `d = ½at²`, so `t ∝ √d`. A square-root
law is therefore what an object of constant *effort* does: throw something twice
as far and it takes √2 as long, not twice as long. That is the physical
behaviour a wooden piece being placed by a hand has, and it is the only law in
the family that gives a chariot visibly more speed without giving it visibly
more time.

Why the remap. A pure `t = 180√d` gives `t(6) = 441 ms`, which is outside the
accepted band and — decisively — outside the Undo budget (§3.2.4). The remap
preserves the law's *shape* (sublinear, diminishing returns) and its *ordering*
while compressing its range from 2.45:1 to 1.33:1.

### 3.2.3 The whole law is seven numbers

Only seven displacements occur on a 7×7 Mini Xiangqi board, so the runtime
implementation is a lookup table, not a square root:

| `d` | Occurs for | `t(d)` | Velocity | At `p = 44` | At `p = 28` |
|---|---|---|---|---|---|
| 1 | king, soldier, one-cell chariot/cannon | **180 ms** | 5.6 p/s | 244 pt/s | 156 pt/s |
| 2 | chariot, cannon | **195 ms** | 10.3 p/s | 451 pt/s | 287 pt/s |
| √5 ≈ 2.236 | horse | **200 ms** | 11.2 p/s | 492 pt/s | 313 pt/s |
| 3 | chariot, cannon | **210 ms** | 14.3 p/s | 629 pt/s | 400 pt/s |
| 4 | chariot, cannon | **220 ms** | 18.2 p/s | 800 pt/s | 509 pt/s |
| 5 | chariot, cannon | **230 ms** | 21.7 p/s | 957 pt/s | 609 pt/s |
| 6 | chariot, cannon | **240 ms** | 25.0 p/s | 1100 pt/s | 700 pt/s |

Values are the formula rounded to the nearest 5 ms. **The extremes on a 7×7
board:** the slowest thing that ever moves is a soldier or king at `5.6 p/s`;
the fastest is a chariot crossing the whole board at `25.0 p/s`, **4.5× faster**.
That ratio is the entire visible payoff of this section, and it is the number to
judge on device: too small and the law is invisible, too large and the chariot
looks flung.

### 3.2.4 Why the band cannot simply be widened

**Accepted, and it binds.** "an Undo transition must therefore complete within
250 ms for one ply and 600 ms for a decision cycle." A decision cycle is two
plies. Two plies plus a gap short enough to still be one gesture must fit in
600 ms. With the undo travel law of §3.3 (`150 ms … 200 ms`) the worst case is
`200 + 60 + 200 = 460 ms`. If forward travel were allowed to reach the physical
law's 441 ms, undo travel scaled from it would reach roughly 370 ms and the
worst decision cycle would be `370 + 60 + 370 = 800 ms` — 200 ms over an
accepted ceiling.

So the contract's own 180–240 band is not arbitrary: **it is the widest band
consistent with the accepted Undo budget.** That is the argument for keeping it
and taking the compressed curve rather than asking to widen it. If the owner
ever does want the uncompressed physical law, the Undo ceilings must move first,
and they should not: repeated Undo is an accepted capability and the ceilings
are what make walking a game back tolerable.

### 3.2.5 Paths

**Proposed.** Every travelling disc follows a **straight line** from origin
point to destination point, including the horse and the capturing cannon.

- The **horse**'s literal move is an L. Animating the L would take longer for the
  same displacement and would be the only two-segment path in the app. The
  straight line is what a hand does.
- The **cannon** jumping its screen is the one case where a curved path would
  teach something — an arc would say "over". I am not proposing it, because it
  would be the only non-straight path on the board, and because the rule belongs
  to Help, which the contract already scopes as the education surface. This is
  listed as an owner choice, not a closed one (§ Open for the owner).

---

## 3.3 The complete timing table

### 3.3.1 Curves, named exactly

Four curves cover the whole table. Three are stock; one is mine.

| Name here | SwiftUI | Control points | Used for |
|---|---|---|---|
| **out** | `.easeOut(duration:)` | `UnitCurve.easeOut` = (0, 0), (0.58, 1) | anything entering or being picked up |
| **in** | `.easeIn(duration:)` | `UnitCurve.easeIn` = (0.42, 0), (1, 1) | anything leaving or being removed |
| **through** | `.easeInOut(duration:)` | `UnitCurve.easeInOut` = (0.42, 0), (0.58, 1) | the board flip, the check pulse |
| **arrive** | `.timingCurve(0.36, 0, 0.16, 1, duration:)` | (0.36, 0), (0.16, 1) | **all move travel** |

The control points for the three stock curves are Apple's, quoted from
`UnitCurve.easeOut` / `.easeIn` / `.easeInOut`; their default duration when
unspecified is 0.35 s (`Animation.easeInOut`: "The `easeInOut` animation has a
default duration of 0.35 seconds"), which is why every row below states a
duration explicitly.

**arrive** is mine, not Apple's. It is `easeInOut` biased toward the end: the
same unhurried departure, a much longer deceleration (end control point at
x = 0.16 instead of 0.58). The reason is informational, not aesthetic — the
moment of a move that carries the information is *which point it landed on*, so
the curve should spend its time near the destination. `.easeInOut` is the
documented fallback if a reviewer wants stock curves only; the difference is
perceptible but the design does not break without it.

### 3.3.2 The table

`t(d)` is §3.2.3. All times in milliseconds. "RM" is the Reduce Motion
substitute, mechanically derived by the single rule in §3.8 — the column is
printed so a reader can check that the rule really does derive every row.

| # | Transition | Duration | Curve | What animates | RM |
|---|---|---|---|---|---|
| M1 | **Select** (tap a movable piece) | **140** | out | disc scale 1.00→1.05; resting shadow → lift shadow; S1 ring opacity 0→1 | 120 crossfade to the selected appearance; end state identical |
| M2 | **Deselect** | **110** | in | the inverse of M1 | 110 crossfade |
| M3 | **Selection replaced** (tap a second movable piece) | **110** out-going / **140** in-coming, overlapping, both from current values | in / out | as M2 and M1 | two crossfades, overlapping |
| M4 | **Legal-destination markers in** (S2 dots, S3 rings) | **110**, no stagger | out | dot opacity 0→1 **and** scale 0.70→1.00; ring opacity only | unchanged for rings; dots lose the scale, keep the 110 opacity |
| M5 | **Legal-destination markers out** (deselect) | **90** | in | opacity only | unchanged |
| M6 | **Legal-destination markers out** (selection replaced) | **60** | in | opacity only | unchanged |
| M7 | **Drag pick-up** (threshold crossed) | **120** | out | scale →1.10; lift shadow → drag shadow; touch-platform offset 0→`0.5 p` upward; S10 origin hollow dot opacity 0→1 | scale, shadow and offset applied **immediately** (exception E2/E5); origin dot fades 120 |
| M8 | **Drag follow** | **0** — no animation | — | disc position set directly from touch/pointer each frame | unchanged (exception E2) |
| M9 | **Target strengthening** (drag within `0.45 p` of a legal point) | **90** in, **90** out | out / out | S2 dot Ø `0.22 p`→`0.33 p`, or S3 stroke `0.06 p`→`0.08 p` | dot: crossfade 90 between the two sizes; ring: unchanged |
| M10 | **Drop-commit settle** (release over a legal point) | **120** | out | disc position release-point→point centre; scale 1.10→1.00; offset→0; drag shadow → resting shadow | 120 crossfade |
| M11 | **Invalid-drop return** | `t(d)` from release point to origin | `.spring(duration: t(d), bounce: 0.12)` | disc position, scale 1.10→1.00, shadow | `.easeOut(duration: 120)`, bounce 0 (rule clause c) |
| M12 | **Ordinary move travel** (tap-committed, or AI) | `t(d)` = **180–240** | arrive | disc position | 120 crossfade origin↔destination |
| M13 | **Capture removal** | **160**, beginning at `t(d) − 120` | in | captured disc scale 1.00→0.82, opacity 1→0 | folded into M12's single 120 crossfade; no scale |
| M14 | **Last-move brackets out** (previous ply) | **100**, starting at travel `t = 0` | in | opacity | unchanged |
| M15 | **Last-move brackets in** (this ply) | **140**, starting at arrival `t = t(d)` | out | opacity | unchanged |
| M16 | **Check treatment appears** | **120**, starting at arrival | out | S6 double-ring opacity 0→1 | unchanged |
| M17 | **Check pulse** (once, §3.5) | **420**, starting at arrival `+ 120` | through, symmetric | both rings' stroke `0.04 p`→`0.056 p`→`0.04 p` | **removed entirely** (exception E1) |
| M18 | **Check treatment clears** | **90** | in | opacity | unchanged |
| M19 | **Illegal-tap / invalid-drop mark** (S7, §3.6) | **90** in · **260** hold · **130** out = **480** | out / — / in | opacity 0→1→0; entry scale 0.88→1.00 | loses only the entry scale; 480 total unchanged (exception E4) |
| M20 | **Turn-status acknowledgment beat** (S9) | **70** up · **70** down = **140** | out / in | status background emphasis, opacity only | unchanged (exception E3) |
| M21 | **AI compose beat** (§3.4) | **260** floor, `max(t_ready, t_commit + 260)` | — | nothing | unchanged (exception E6) |
| M22 | **AI activity indicator in** | **160**, only if the search has not returned by `t_commit + 500` | out | opacity | unchanged |
| M23 | **Undo, one ply** | `t_undo(d)` = **150–200** | arrive | reverse travel; captured disc restored over **140** from `t = 0`; previous brackets restored over **140** from `t = 0` | 120 crossfade |
| M24 | **Undo, one decision cycle** | `t_undo(d₁)` + **60** gap + `t_undo(d₂)` ≤ **460** | arrive | AI ply reversed, then human ply | two 120 crossfades + the 60 gap = ≤ 300 (exception E7) |
| M25 | **Board flip** | **340** | through | every disc's position to its mirrored point; markers travel with their points; glyph rotation is 0 throughout | 120 crossfade between orientations |
| M26 | **File-numeral strip swaps ends** | **120** out · **100** blank · **120** in, inside M25 | in / — / out | opacity | one 120 crossfade |
| M27 | **Pointer hover fill in / out** (S11) | **90** / **120** | out / in | opacity | unchanged |
| M28 | **Keyboard focus cursor moves** (S12) | **90** | out | square position | 90 crossfade; snaps if a new target arrives within 45 (§3.7) |
| M29 | **Save-failure capsule** (S8) | **160** in · **3000** hold · **220** out | out / — / in | opacity, no translation | unchanged |
| M30 | **Replay step, manual** | `t(d)` | arrive | as M12/M13 | 120 crossfade |
| M31 | **Autoplay inter-move gap** | **400** at 1×; ×0.5 at 2×; ×2 at 0.5× | — | nothing | unchanged |

`t_undo(d) = 150 ms + 50 ms × (√d − 1)/(√6 − 1)`, rounded to the nearest 5 ms:
**150 / 165 / 165 / 175 / 185 / 195 / 200 ms** for `d` = 1 / 2 / √5 / 3 / 4 / 5 /
6. (A two-cell slide and a horse move round to the same value; they differ by
2.8 ms before rounding.)

Autoplay speed multiplies **every** duration in the table, not only the gap
(2× halves them, 0.5× doubles them) — otherwise the pacing changes but the
motion does not, and 2× replay would show the same 240 ms chariot with a shorter
pause, which reads as stuttering rather than as fast.

Not in this table, because they are chrome rather than board layer: the result
card, the threefold-repetition notice, the save-and-continue confirmation, and
navigation. Those belong to whichever section owns the surrounding Liquid Glass
layers.

### 3.3.3 Four rows that need their arithmetic shown

**Capture (M12 + M13) totals 220–280 ms, median 250.** Removal begins 120 ms
before arrival and runs 160 ms, so the whole event ends 40 ms after the mover
lands: `t(d) + 40`. That is 220 ms for a one-cell capture, 250 ms for a
three-cell capture, 280 ms for a chariot crossing the board. The accepted target
is "approximately 250 ms overall" — this lands on it at the median move and
brackets it by ±30 ms, which I read as inside "approximately". The removal must
start *before* arrival: if it started at arrival the two discs would already be
concentric and the fade would read as the *mover* disappearing.

**Drag-committed moves do not use the 180–240 band at all.** The transit already
happened under the finger; what remains is a `≤ 1.21 p` settle (up to `0.707 p`
of drop tolerance — a release at the far corner of the destination cell — plus
the `0.5 p` touch offset), which is M10's fixed 120 ms. The accepted band governs tap-committed moves, AI moves, undo, and
replay — everything where *the board* moves the piece rather than the hand. A
drag capture is correspondingly shorter than 250 ms: 160 ms of removal
concurrent with the 120 ms settle. Flagged as an interpretation of the accepted
text rather than a reading it forces.

**The board flip's 340 ms is derived, not chosen.** The longest disc travel in a
flip is corner to opposite corner: `√(6² + 6²) p = 6√2 p = 8.485 p`. The fastest
any disc ever moves under §3.2 is `25.0 p/s` (a six-cell chariot). Setting the
flip so that no disc ever exceeds that ceiling gives `8.485 / 25.0 = 0.339 s`.
Rounded: **340 ms**, which lands comfortably inside the accepted 300–400 ms band
without having been aimed at it. The rule is worth keeping as a rule: *nothing
on this board ever moves faster than the fastest legal move.*

**Undo has 50 ms and 140 ms of headroom.** One ply: `t_undo(6) = 200 ms` against
a 250 ms ceiling. One decision cycle: `200 + 60 + 200 = 460 ms` against 600 ms.
Undo is deliberately faster than the equivalent forward move (150–200 against
180–240) because an undo is a correction, not a decision — and because the
ceilings demand it. The 60 ms gap between the two plies of a cycle is not
padding: without it a learner cannot see that *two* moves came back, which is
the whole teaching content of "Undo returns you to the previous decision point".
Both plies animating simultaneously would fit in 200 ms and was rejected for
exactly that reason.

---

## 3.4 The AI move — the compose beat and the full move animation

*(This is the section §2.2 S5 forward-references.)*

### 3.4.1 Why a beat exists at all

**Accepted:** "An AI move uses the same move language and leaves persistent
origin and destination markers so the player can identify the completed move."
The markers are the record for a player who looked away. The beat is for the
player who did not.

Three reasons, in order of weight:

1. **Attribution.** With **快速** at roughly one second the beat is invisible.
   But the search can return in 40 ms — a shallow position, a forced recapture,
   a book-like reply. At 40 ms the human's move animation and the AI's abut, and
   what the eye sees is one continuous four-cell event performed by nobody in
   particular. The beat is the punctuation that separates *your* ply from *its*
   ply.
2. **The turn status must be readable as a state.** The status flips to
   **轮到黑方 · AI** the instant the human's move commits. If the reply lands
   40 ms later it flips back before anyone read it, and the accepted status
   element — the app's single coherent description of the play state — has
   described a state that never visibly existed.
3. **The last-move brackets must be seen once.** The human's own brackets appear
   at their arrival (M15, 140 ms). The AI's departure erases them (M14). Without
   a floor, a fast reply erases the human's record before the fade-in finishes.

**What the beat is not.** It is not a simulated think, and it must never be
described as one. The app does not manufacture deliberation it did not perform.
It is a minimum separation between two committed plies, and it adds nothing at
all to a search that already took longer than the floor.

### 3.4.2 The rule

Let `t_commit` be the instant the human's move animation completes and board
input closes; let `t_ready` be the instant the search returns a move.

> **Proposed.** The AI's move begins travelling at
> `max(t_ready, t_commit + 260 ms)`.

The beat is therefore a **floor, not an added delay**:

| Search returns at | AI departs at | Beat actually experienced |
|---|---|---|
| 40 ms | `t_commit + 260` | 220 ms |
| 260 ms | `t_commit + 260` | 0 |
| 1 s (**快速** ceiling) | `t_ready` | 0 |
| 3 s (**标准**) | `t_ready` | 0 |
| 5 s (**深思**) | `t_ready` | 0 |

The worst case added latency in the whole app is 260 ms, and it occurs only when
the engine was faster than a human can register a turn change.

**Why 260 ms.** Apple publishes no such value (§3.12). I derive it inside the
app rather than asserting it: the beat must exceed the status acknowledgment
beat (M20, 140 ms) so that the status change cannot be mistaken *for* a beat,
and it must exceed the last-move brackets' fade-in (M15, 140 ms) so the human's
record is fully drawn before the AI's move erases it. 140 ms plus a margin that
survives a dropped frame or two gives 260 ms. It is the single number in this
section I would most expect device testing to move, and the direction it should
move is down, not up.

### 3.4.3 What happens during the beat

Nothing moves. That is the point.

- The status shows **轮到黑方 · AI** with its activity treatment.
- The human's last-move brackets stay visible for the whole beat; they clear at
  the AI's *departure*, not at the beat's start.
- The board is **not** dimmed. §2.2 S9 already settled this: the position is
  exactly what a learner wants to study during the pause.
- No board element animates. The beat is silence, not a placeholder animation.

### 3.4.4 The activity indicator, and the 500 ms threshold

**Proposed** (the contract leaves this open: "Define the turn status's exact AI
activity treatment"). The activity indicator attached to the AI's turn appears
**only if the search has not returned by `t_commit + 500 ms`**, fades in over
160 ms, and persists until the reply. So a 40 ms search shows no indicator at
all; a 3 s search shows one for about 2.5 s.

An indicator that flashes on and off inside 300 ms is worse than none: it reads
as a glitch and it trains the eye to ignore the element. HIG "Progress
indicators › Best practices" pushes the same way — "Keep progress indicators
moving so people know something is continuing to happen. People tend to
associate a stationary indicator with a stalled process" — an indicator whose
whole life is shorter than its own fade is the degenerate case of that.

### 3.4.5 The AI's move animation itself

Identical to a human tap-committed move — same `t(d)`, same **arrive** curve,
same M13 capture coordination, same M14/M15 brackets, same M16/M17 check
treatment. That is accepted and I add nothing to it. The AI move differs from a
human move in exactly two ways: the beat that precedes it, and the fact that it
carries a sound but no haptic (§3.10.4).

### 3.4.6 Two edge cases the beat creates

**The AI moves first (AI 先手).** There is no preceding human move, so
`t_commit` is the instant the board becomes interactive after successful game
creation. The floor still applies: the opening move never lands sooner than
260 ms after the board appears. Without this the game begins with a piece
already in flight.

**Undo during the beat.** The beat is a window in which a returned-but-unplayed
AI move exists. Accepted: "Undo while the AI is thinking cancels the search and
removes the human move that triggered it." Extending that to the beat: an Undo
arriving between `t_ready` and the AI's departure **discards the returned move**
and runs the Undo. The AI must not get to play a move the user has already
undone, and the user must not have to wait out a beat to undo.

---

## 3.5 The check pulse

*(This is the section §2.2 S6 forward-references.)*

### 3.5.1 The pulse cannot be a scale pulse — the arithmetic

The survey proposed "ring scale 1.0 → 1.10 → 1.0 over 400 ms". Against §2.2's
S6 geometry that collides. From §2:

- S6 outer ring: centre-line radius `0.54 p`, stroke `0.04 p` → outer edge at
  `0.56 p`.
- Nearest neighbouring disc edge: `1.00 p − 0.42 p = 0.58 p`.
- Headroom: **`0.02 p`**, which is 0.88 pt at `p = 44` and 0.56 pt at `p = 28`.

The maximum collision-free scale is therefore `0.58 / 0.56 = 1.0357`. The
survey's ×1.10 puts the outer edge at `0.616 p`, overlapping the neighbouring
disc by `0.036 p` — 1.6 pt at the iOS floor, plainly visible. And a scale pulse
capped at ×1.035 is not a pulse; it is a rounding error.

This is a genuine cross-section finding: **§2's marker geometry forbids a scale
pulse on the check rings.** Either the pulse changes kind, or S6's radii change.
I propose the former, because S6's radii are load-bearing for the whole
collision analysis in §2.4 and the pulse is not.

### 3.5.2 The proposed pulse

> **Proposed.** One pulse, 420 ms, at fixed radii: both S6 rings' stroke goes
> `0.04 p → 0.056 p → 0.04 p`, growing symmetrically inward and outward from
> their centre-line radii, with **through** easing on each half. Nothing
> translates and nothing scales.

Timing: the rings fade in over 120 ms starting at the checking move's arrival
(M16); the pulse begins at `arrival + 120` and ends at `arrival + 540`.

Collision check at peak stroke `0.056 p`:

| Boundary | At rest | At pulse peak | Limit | Clearance at peak |
|---|---|---|---|---|
| Outer ring, outer edge | `0.560 p` | `0.568 p` | `0.58 p` (neighbour disc) | `0.012 p` = 0.53 pt @44, 0.34 pt @28 |
| Inner ring, inner edge | `0.440 p` | `0.432 p` | `0.42 p` (own disc) | `0.012 p` = 0.53 pt @44, 0.34 pt @28 |
| Gap between the two rings | `0.040 p` | `0.024 p` | must stay > 0 | 1.06 pt @44, 0.67 pt @28 |

Symmetric by construction, which is why `0.056 p` and not more: it is the
largest stroke that leaves equal clearance at both boundaries. **Named risk:**
0.34 pt at the macOS floor is well under a point, and survives only because the
rings are anti-aliased at 2×. §2.6 already flags that S6 bottoms out near one
device pixel at `p = 28`; the pulse consumes most of what is left. If device
testing says the pulse is invisible at the macOS floor, the honest fix is to
suppress the pulse below some pitch rather than to enlarge it into a collision.

### 3.5.3 Why once, and why the pulse never survives a ply

**Accepted:** "Check uses a persistent, non-color-only king-square treatment
plus one brief pulse. It does not flash continuously." Grounding beyond the
contract: HIG "Accessibility › Cognitive" — "Be cautious with fast-moving and
blinking animations. When you use these effects in excess, it can be
distracting, cause dizziness, and in some cases even result in epileptic
episodes."

The pulse is bound to the *transition into check*, not to the state of being in
check. So:

- Check appears → rings in, one pulse.
- Check persists across a ply (the checked side plays a move that does not
  resolve it — impossible under the accepted rules, but the same rule covers
  Free Play's ability to reach it) → no second pulse.
- Check resolved → rings out over 90 ms (M18), no pulse.
- Check appears again later → rings in, one pulse. The pulse counts transitions,
  not turns.
- A new ply begins while a pulse is running → the pulse is cancelled at its
  current stroke value and relaxes to `0.04 p` over 90 ms. A pulse never
  survives into a ply it does not belong to (§3.7).

---

## 3.6 The illegal-tap mark

*(This is the section §2.2 S7 forward-references, and it fixes the ≈ 480 ms it
promises.)*

> **Proposed life cycle: 90 ms in · 260 ms hold · 130 ms out = 480 ms exactly.**

| Phase | Duration | Curve | Animates |
|---|---|---|---|
| In | 90 | out | opacity 0→1; whole mark scale 0.88→1.00 about the tapped point |
| Hold | 260 | — | nothing |
| Out | 130 | in | opacity 1→0; no scale |

The entry scale is small (0.88, i.e. 12 %) and exists so the mark reads as
*arriving at the point you touched* rather than as a layer switching on. The
exit has no scale: a mark that shrinks away invites a second look at the moment
it should be releasing attention.

**Two extensions to §2's S7, proposed here because they are timing questions:**

1. **The invalid drop uses the same mark.** The accepted contract requires that
   an invalid drop "gives the attempted destination brief feedback"; §2 defined
   exactly one mark for "you asked for something illegal *here*". Reusing it
   means the app has one answer to that question regardless of whether it was
   asked by tap or by drop, which is the correct number of answers. The mark
   appears at the attempted destination at the instant of release, concurrent
   with the M11 return.
2. **Only one mark exists at a time.**
   - Same point tapped again while alive → the life cycle restarts at full
     opacity, skipping the 90 ms in. (A re-entry fade would read as a flicker.)
   - Different point tapped while alive → the old mark leaves over **60 ms**
     while the new one enters over its normal 90 ms. They overlap for 60 ms,
     which is correct: two different questions were asked.

The mark's total lifetime is deliberately not shortened under Reduce Motion
(exception E4): 480 ms is how long the mark needs to be *read*, and reading time
is content, not motion.

---

## 3.7 Interruption

The contract is the authority here and it says two things in one sentence, both
inside the Undo bullet: "Board input and another Undo remain unavailable until
the transition completes, and a new action does not interrupt a running
transition."

The survey (§5.3.1, conflicts C2 and C3) proposed overriding this with
snap-to-end for every transition. **I supersede that proposal** — see §3.11 —
and propose instead a distinction that satisfies the contract's letter while
giving back almost everything snap-to-end was trying to recover.

### 3.7.1 The distinction

> **A transition is either committing or presentational.**
>
> A **committing** transition is one whose end state is a new committed game
> position: move travel (M12), capture (M13), the AI's move, and Undo (M23,
> M24). While one runs, the core has already mutated and the board is catching
> up.
>
> A **presentational** transition changes no committed state: everything else in
> §3.3.2.

> **Rule I — presentational transitions are always interruptible, and
> interruption re-targets rather than snaps.** A new request starts immediately,
> from wherever the running transition currently is, and runs its own full
> duration. No queue, no snap, no completion handler in the path.
>
> **Rule II — committing transitions run to completion, and board input is
> refused while one runs.** Refused input is **discarded, never queued**, and
> the refusal is acknowledged by the M20 status beat plus the lightest haptic.

Rule I is what HIG asks for — "Let people cancel motion. As much as possible,
don't make people wait for an animation to complete before they can do anything,
especially if they have to experience the animation more than once" (HIG "Motion
› Providing feedback") — and it is also what SwiftUI does natively: changing an
animated state value mid-flight re-targets from the current value rather than
restarting. The design requirement is only that nothing in the presentational
path waits on `withAnimation(_:completionCriteria:_:completion:)`.

Rule II is the contract, and I think the contract is right for a game: two
overlapping position changes on one board is a correctness hazard, not an
aesthetic one. **Discarding rather than queueing** is the important detail — a
queued tap that arrives during a 240 ms travel would commit a move against a
position the user was not looking at. The mitigation for the wait is the
durations themselves: no committing transition exceeds **280 ms** and no
committing sequence exceeds **460 ms**.

### 3.7.2 Per case

| Situation | Behaviour |
|---|---|
| **Tap a second piece while the first is still lifting** | Presentational. The first deselects from its current scale and shadow (M2 timing, current values), the second selects (M1). Their marker sets cross-fade with the shortened M6/M4 pair so both destination sets are visible together for only 60 ms. |
| **Drag begins while markers are still fading in** | Presentational. The pick-up (M7) takes over from wherever M1/M4 reached. |
| **Tap or drag during a move's travel or capture** | Committing. Discarded. M20 beat + lightest haptic. |
| **Tap during the AI's move** | Committing. Discarded + acknowledged. |
| **Tap during the AI's compose beat** | Committing (the position is the AI's to change). Discarded + acknowledged. This matters: the beat is a period of apparent stillness, so it is the most likely moment for a stray tap, and it must be answered rather than swallowed. |
| **Tap while the AI's check pulse is still running** | **Accepted immediately.** The pulse is presentational. Input reopens at `t(d) + 40 ms` — the end of the capture removal, or of the travel if there was no capture — **not** at the end of the pulse (`t(d) + 540`) or of the brackets fade-in. The user is never held for a decoration. |
| **Undo while an Undo is running** | Contract: unavailable. Discarded + acknowledged. |
| **Undo during a move's travel** | Discarded + acknowledged. It becomes available again 40 ms after arrival. |
| **Undo during the compose beat** | **Accepted**, and it discards the AI's returned-but-unplayed move (§3.4.6). This is the one committing-phase input that is not discarded, because the contract explicitly grants it. |
| **Flip the board during a committing transition** | **Deferred**, not discarded: the flip runs when the transition completes, at most 280 ms later. A flip has no position semantics, so a late flip is exactly the flip that was asked for, and discarding it would read as a broken control. This is the only queued action in the design. |
| **Flip during a presentational transition** | Runs immediately. A selected piece keeps its lift, its ring, and its markers, and all of them travel with the board. Selection is not cancelled: "Flipping the board changes presentation only." |
| **Flip during a drag** | Deferred until the drag ends. Mirroring the board under a held piece would move the piece's own origin out from under the finger. On touch the control is unreachable mid-drag anyway; on macOS a keyboard command can reach it. |
| **Illegal mark while another is alive** | §3.6: restart on the same point, 60 ms handover on a different point. |
| **Check pulse when a new ply begins** | Cancelled at its current value; rings relax to `0.04 p` over 90 ms. |
| **Focus cursor key-repeat faster than the 90 ms move** | Re-targets. If a new target arrives within 45 ms (half the duration), it snaps instead, so a held arrow key never leaves the cursor trailing the focus. |
| **Manual replay navigation during autoplay** | Autoplay pauses (accepted). The manual step begins when the running step's committing part completes, ≤ 280 ms later. I supersede the survey's C3 proposal to cut the running step short. |
| **App backgrounds or the scene deactivates mid-transition** | Every running transition jumps to its end state immediately; nothing resumes on return. |

### 3.7.3 The number to judge

Repeated Undo with input blocked runs at one decision cycle per
`460 ms + input latency` — roughly **2.2 cycles per second**, or about 4.4 plies
per second. Walking a 40-ply game back to the start takes about 9 seconds of
blocked input. That is the felt cost of Rule II, stated plainly so the owner can
weigh it against the correctness argument. If it is judged too slow, the honest
lever is not snap-to-end but a dedicated "return to start" action, which is a
product question and not in the target MVP.

---

## 3.8 Reduce Motion, as one rule

**Accepted:** "With Reduce Motion, the animation of lifts, springs, pulses, and
long-distance travel is removed in favor of a brief crossfade or immediate state
update. The states themselves remain: a held piece still reads as raised, it
simply arrives at that appearance without an animated transition."

### 3.8.1 The rule

> **Every row of §3.3.2 keeps its end state and its ordering, and loses its
> path.** For each row:
>
> **(a)** if the animated property is **position, scale, or rotation**, the
> transition becomes a cross-fade between the before and after appearances over
> `min(duration, 120 ms)`;
> **(b)** if the animated property is **opacity, colour, stroke weight, or
> shadow**, the row runs **unchanged**;
> **(c)** springs become their `bounce: 0` eased equivalents;
> **(d)** durations, ordering, sequencing, and gaps are otherwise untouched.

That single rule produces the RM column of §3.3.2 row by row, which is why the
column is printed: it is a check, not a second specification.

**Documented grounding, which is unusually good here.** Apple's own Reduce
Motion techniques include "Replacing transitions in x-, y-, and z-axes with
fades to avoid motion" and "Tightening animation springs to reduce bounce
effects" (HIG "Accessibility › Cognitive") — clauses (a) and (c) verbatim. The
framework agrees: `TransitionProperties.hasMotion` is documented as "Whether the
transition includes motion. When this behavior is included in a transition, that
transition will be replaced by opacity when Reduce Motion is enabled" — i.e.
SwiftUI's built-in substitution *is* clause (a). And
`EnvironmentValues.accessibilityPrefersCrossFadeTransitions` — "A Boolean value
that indicates whether the Reduce Motion and the Prefer Cross-Fade Transitions
settings are in an enabled state… UI should avoid Slide animations and prefer
Cross-Fade transitions instead" — is the query to read, not
`accessibilityReduceMotion`, because it also honours Prefer Cross-Fade
Transitions and, per its own documentation, "On macOS, this value returns solely
whether the Reduce Motion setting is in an enabled state." **Proposed: the board
layer reads `accessibilityPrefersCrossFadeTransitions`.**

The 120 ms cap is mine. It is short enough that a crossfade never becomes its
own event and long enough that the eye can follow which point changed.

### 3.8.2 The seven exceptions the rule needs

**E1 — The check pulse is removed entirely, not converted.** The contract names
pulses among what is removed. The persistent double ring crossfades in over
120 ms and stays. Clause (b) would have kept the pulse (stroke weight), so this
exception is required, not cosmetic.

**E2 — The 1:1 drag follow and the `0.5 p` touch offset are kept exactly.**
Gesture tracking is not animation; HIG lists "Tracking animations directly with
people's gestures" as a Reduce Motion *technique*, not as something Reduce
Motion removes. Removing the follow would break the gesture, and removing the
offset would put the piece back under the fingertip.

**E3 — The turn-status acknowledgment beat is kept at its full 140 ms.**
Clause (b) already covers it, but it must be written down, because a reader
scanning the contract for "pulses" would delete it — and it is the only visual
answer to a refused tap. Deleting it would leave the app silently ignoring
input, against HIG "Feedback › Best practices": "Show people when a command
can't be carried out and help them understand why."

**E4 — The illegal mark keeps its full 480 ms.** It loses only its 0.88 → 1.00
entry scale (clause (a) applied to that one component). Its hold time is reading
time, which is content.

**E5 — The lift and drag scale states and the lift shadow are applied
immediately and are never removed.** Accepted twice over: the shadow "is never
suppressed by a style choice, and Reduce Motion substitutes an immediate change
for the animated lift rather than removing the state."

**E6 — The AI compose beat is unchanged.** A delay is not motion. `max(t_ready,
t_commit + 260 ms)` is identical under Reduce Motion, and it matters *more*
there: with the plies reduced to crossfades, the beat is the only thing
separating them.

**E7 — Undo of a decision cycle stays two crossfades separated by the 60 ms
gap.** Never one crossfade to the final position. The user must still be able to
count that two plies came back. This is the accepted replay clause — "preserving
the same order and playback controls" — generalised to the whole board, and it
is why clause (d) exists.

### 3.8.3 What Reduce Motion does not change

No marker's geometry, ink, contrast, or z-order. No sound. No haptic. No
duration in the sound/haptic synchronisation table of §3.10 — the instants move
with their transitions but the pairings do not change. And nothing appears or
disappears that would not otherwise: the correct Reduce Motion board shows
exactly the same twelve states as the default board.

---

## 3.9 Reduce Transparency, Increase Contrast, and two settings the survey missed

### 3.9.1 The shape of the answer

Reduce Motion changes **durations and paths**. The other three settings change
**what a transition interpolates to**, and change no duration anywhere.

> **Reduce Transparency, Increase Contrast, and Reduce Bright Effects alter the
> endpoint values of transitions in §3.3.2. They do not alter a single duration,
> curve, ordering, or gap.**

That is a testable invariant and I recommend it as one: the timing table must be
byte-identical under all three.

### 3.9.2 Reduce Transparency

**Documented:** `EnvironmentValues.accessibilityReduceTransparency` — "Whether
the system preference for Reduce Transparency is enabled." HIG "Materials ›
Liquid Glass" notes that Liquid Glass variants' "appearance… can differ in
response to certain system settings, like… accessibility settings that reduce
transparency or increase contrast in the interface" — appearance, not timing.

**Accepted:** Liquid Glass "belongs primarily to functional layers around the
board; board-state markers must remain direct and readable rather than becoming
translucent decoration." So the board layer carries no material, and Reduce
Transparency has **no effect on any row of §3.3.2**.

It touches motion in exactly one place, and only in the value domain: the S8
save-failure capsule (M29) is anchored to the status element and may use a
material. Under Reduce Transparency it goes opaque. Its 160 / 3000 / 220 ms life
cycle is unchanged.

A note against a plausible misreading: the Reduce Motion crossfade substitute
(§3.8) is an opacity animation of opaque content over an opaque board surface.
It is not translucency in the Reduce Transparency sense, and the two settings do
not interact.

### 3.9.3 Increase Contrast — and the dependency §1 named

§1 of this document states that "under Increase Contrast shadows weaken", and
builds the case for the S1 selection ring on it. This is where that is paid for.

**Proposed shadow values** (the motion language owns the lift shadow; the styles
own only the resting shadow):

| | Offset | Blur radius | Opacity | At `p = 44` |
|---|---|---|---|---|
| Lift (selection, M1) | `(0, 0.06 p)` | `0.14 p` | 0.28 | (0, 2.6), r 6.2 pt, 28 % |
| Drag (M7) | `(0, 0.10 p)` | `0.22 p` | 0.34 | (0, 4.4), r 9.7 pt, 34 % |

**Under Increase Contrast:** shadow opacity × **0.5**, blur radius × **0.7**.
The lift shadow becomes r 4.3 pt at 14 %; the drag shadow r 6.8 pt at 17 %. Both
remain present — the contract forbids suppressing the lift shadow — but neither
is any longer a reliable carrier of "held".

**Therefore, and this is the compensating change §1 depends on:** under Increase
Contrast the S1 selection ring's stroke goes from `0.05 p` to **`0.065 p`**
(2.2 → 2.9 pt at `p = 44`; 1.4 → 1.8 pt at `p = 28`), and §1's record ink
promotes to active-ink values, so the last-move brackets and the drag-origin
marker strengthen at the same time.

The ring must grow **outward only**, or it breaks §1's separation rule. §1 fixes
a marker ring's inner edge at `≥ 0.44 p`, so the extra stroke cannot be taken
symmetrically about the centre-line. Proposed: the centre-line moves from
`0.4625 p` to **`0.4725 p`** as the stroke grows, pinning the inner edge at
exactly `0.44 p` and putting the outer edge at `0.505 p`. Under the ×1.05 lift
that reaches `0.530 p` — still clear of the neighbouring disc at `0.58 p`. No
geometry breaks.

> **A discrepancy in §2.2 that this exposes, for §2 to reconcile.** S1 is stated
> as "stroke `0.05 p`, centre-line radius `0.4625 p` (inner edge `0.44 p`, outer
> `0.485 p`)". Those three numbers are not simultaneously consistent: stroke
> `0.05 p` about `0.4625 p` gives edges at `0.4375 p` and `0.4875 p`, and the
> inner edge then violates §1's `≥ 0.44 p` rule by `0.0025 p`. The stated edges
> are produced by **stroke `0.045 p`** about `0.4625 p`. Either the stroke is
> `0.045 p`, or the centre-line is `0.465 p`. This section assumes the stated
> *edges* are the intent and treats `0.44 p` as the pinned inner boundary.

Durations are untouched: M1 is 140 ms whether or not Increase Contrast is on; it
simply interpolates to a different shadow and a different stroke.

**Documented grounding, and its limit.** HIG "Accessibility › Vision" gives the
contrast table this document uses throughout (4.5:1 up to 17 pt, 3:1 at 18 pt,
3:1 bold at any size) and the instruction: "If your app doesn't provide this
minimum contrast by default, ensure it at least provides a higher contrast color
scheme when the system setting Increase Contrast is turned on." The query is
`EnvironmentValues.colorSchemeContrast` against `ColorSchemeContrast.increased`.

**But Apple publishes no rule that shadows weaken under Increase Contrast.** I
searched for it and found nothing. The requirement comes from our own accepted
contract — "resting shadows are reduced under Increase Contrast" — plus the
inference that a soft drop shadow is by construction a low-contrast edge and
therefore exactly the kind of separation cue Increase Contrast exists to
replace. §1 should carry that attribution rather than implying Apple states it.

### 3.9.4 Reduce Bright Effects — a setting the survey missed

**Documented:** `EnvironmentValues.accessibilityReduceHighlightingEffects` —
"Whether the system preference for Reduce Bright Effects is enabled. If this
property's value is true, controls, such as buttons, should be drawn in such a
way that minimizes highlighting and flashing of onscreen elements."

Two rows of §3.3.2 are highlighting-and-flashing by construction, so this
setting bites:

- **M17, the check pulse:** peak stroke capped at `0.048 p` instead of
  `0.056 p`, halving the excursion.
- **M20, the status acknowledgment beat:** peak background emphasis halved.

Nothing else changes, and neither duration changes. This is a small addition but
it is the setting most directly aimed at the two effects this section had to
argue hardest for, and leaving it unhandled would be an obvious review finding.

### 3.9.5 Differentiate Without Color, and Bold Text

**Neither changes any row.** §2.6 already establishes that the board's carrier is
luminance and shape rather than hue, so the correct result for
`accessibilityDifferentiateWithoutColor` is a pixel-identical board and an
unchanged timing table. `legibilityWeight` (Bold Text) affects the disc glyph's
weight, which §1 owns, and no transition in §3.3.2 animates glyph weight.

---

## 3.10 Haptics and sound: the synchronisation points

### 3.10.1 The one rule

> **Every event has exactly one instant at which it is *done*, and both channels
> fire at that instant, within one display frame of the visual change.**

A selection is done at the touch — the piece is selected the moment you touch
it, and the 140 ms lift is the picture catching up. A move is done when the
piece *lands*, not when it departs, because that is when a wooden piece makes a
noise and when the board's new state becomes readable. An illegal tap is done at
the touch. A result is done when the card appears.

That single rule produces the whole table in §3.10.4 and it satisfies Apple's
two governing statements:

- "Prefer using haptics to complement other feedback in your app or game. When
  visual, auditory, and tactile feedback are in harmony — as they generally are
  in the physical world — the user experience is more coherent and can seem more
  natural. For example, you generally want to match the intensity and sharpness
  of a haptic with the intensity and sharpness of the animation it accompanies.
  You can also synchronize sound with haptics." (HIG "Playing haptics › Best
  practices")
- "The source of the feedback must be clear to the user. For example, the
  feedback must match a visual change in the user interface, or must be in
  response to a user action. Feedback should never come as a surprise."
  (Apple Pencil, "Playing haptic feedback in your app › Use feedback
  intentionally")

**The latency budget** is mine: both channels must fire within **one frame** of
the visual instant — 16.7 ms at 60 Hz, 8.3 ms at 120 Hz. Apple's own guidance on
perceptible delay is about continuous interaction ("a delay of 50 milliseconds
(ms) between the finger changing direction and the icon changing direction may
be noticeable when looking for it" — Xcode, "Understanding user interface
responsiveness"), so 50 ms is the outer bound at which the pairing visibly
decouples; one frame is the target.

### 3.10.2 Haptics — the survey's five, with three changes

I **adopt** the survey's §6.3.3 structure, its implementation route
(`sensoryFeedback(_:trigger:)`, which per its documented per-symbol platform
notes no-ops off the supported platforms and therefore needs no capability
branch for correctness), and its refusal to add haptics for Undo, flip,
navigation, replay, or autoplay. Three changes:

**Change 1 — required by the contract, not by me.** The survey maps "Illegal
square, or save failure" to `.warning`. The accepted contract now says the
opposite: "tapping an illegal square is a normal part of learning how the pieces
move rather than a failure, so it uses the platform's lightest selection-weight
feedback and never the system warning pattern. The warning pattern is reserved
for genuine failures such as an action that could not be saved." The row must
split into `.selection` for the illegal tap and `.warning` for the save failure.
The survey predates that decision.

**Change 2 — my improvement: macOS gets exactly one haptic.** The survey states
"iPad and Mac get none." That is correct for `.selection`, `.impact`,
`.success`, and `.warning`, each documented "Only plays feedback on iOS and
watchOS". But `SensoryFeedback.alignment` is documented as "Indicates the
alignment of a dragged item… For example, use this pattern in a drawing app when
the user drags a shape into alignment with another shape. **Only plays feedback
on iOS and macOS.**" That is our target-strengthening moment (M9) exactly: a
dragged item entering alignment with a target. So a Mac with a Force Touch
trackpad gets one haptic, for the interaction where a pointer user most lacks
physical feedback, using the pattern for its documented meaning.

It fires on iOS too, since the same symbol supports it. A chariot dragged along
its own file passes up to six legal points, so this is the one haptic that can
repeat within a gesture. §2's `0.45 p` / `0.55 p` hysteresis prevents flicker;
I add a **120 ms minimum interval** between consecutive alignment ticks. HIG:
"Avoid overusing haptics. Sometimes a haptic can feel just right when it happens
occasionally, but become tiresome when it plays frequently." This is the haptic
most likely to need tuning or removal on device, and I name it as such.

**Change 3 — my improvement: the AI's move carries a sound but no haptic.** The
survey does not distinguish. The distinction follows from the Apple Pencil rule
above: haptic feedback must be "in response to a user action". The AI's move is
not the user's action, and a tap in the hand for something the opponent did
misattributes agency. The resolution of the apparent tension with the accepted
"an AI move uses the same move language" is that the two channels are about
different things: **sound is about the board** — a piece hit it, which is true
whoever moved it — **and haptics are about the hand.**

### 3.10.3 Sound — the survey's six, with two changes

I **adopt** the survey's §6.3.1 audio-session analysis in full (`.ambient` on
iOS/iPadOS, no session on macOS, never touch system volume, lazy activation,
`.notifyOthersOnDeactivation`), its six events, its decision that wins and losses
share one cue, and its decision that autoplay is silent — and I add the timing
reason for the last: at 2× every duration in §3.3.2 halves, so a click every
90–120 ms is a rattle.

**Change A — split event #5.** The survey uses one 无效 thud for both the
illegal tap and the save failure. The accepted contract requires the two to
"remain distinguishable from each other, as their visual feedback already is."
They now differ visually (board ✕ versus status capsule) and haptically
(`.selection` versus `.warning`), so a shared sound is arguably survivable — but
a user looking away with haptics off would hear the same thing for "you are
learning" and "your game did not save". **Proposed: split into #5a 无效** (soft
muted thud, ~80 ms, deliberately not an alarm) **and #5b 失败** (the same thud
with a short falling second body, ~200 ms). This is a sound-design cost, so it
is listed as an owner call rather than asserted.

**Change B — the survey does not say *when* each sound plays.** That is the
substance of this subsection; §3.10.4 adds it. In particular the survey's #3
将军 is "layered on top of 1 or 2" with no offset. **Proposed: +120 ms after
#1/#2**, so the ear hears "landed, *then* check" as cause and consequence rather
than as a chord. That instant is also exactly when the check rings finish
appearing and the pulse begins (M16 → M17), so the two channels stay locked.

### 3.10.4 The synchronisation table

| Event | Haptic | Sound | Fires at | Rows |
|---|---|---|---|---|
| Piece selected (tap, or drag threshold crossed) | `.selection` | — | **t = 0** of the lift — the moment the tap is recognised, before the lift is visible | M1, M7 |
| Dragged piece enters a legal point's `0.45 p` radius | `.alignment` *(iOS + macOS)* | — | the frame the threshold is crossed; ≥ 120 ms since the last | M9 |
| Move commits, no capture | `.impact(flexibility: .solid, intensity: 0.5)` | **#1 落子** | **arrival**, `t = t(d)` | M12 |
| Capture commits | `.impact(flexibility: .rigid, intensity: 0.8)` | **#2 吃子** | **arrival**, `t = t(d)` | M12, M13 |
| The move gives check | — | **#3 将军**, layered | `t(d) + 120` — as the rings finish appearing and the pulse begins | M16, M17 |
| Drag-committed move | as above by kind | as above by kind | **release**, `t = 0` of the settle — the hand already arrived | M10 |
| Illegal tap, or invalid drop | `.selection` | **#5a 无效** | **t = 0** of the mark's entry | M11, M19 |
| Unavailable input refused | `.selection` | **none** | **t = 0** of the status beat | M20 |
| Save failure | `.warning` | **#5b 失败** | **t = 0** of the capsule's entry | M29 |
| Natural terminal result | `.success` | **#4 对局结束** | the instant the result card begins to appear, after the final move's animation completes | — |
| Threefold repetition first claimable | — | **#6 判和可用** | the instant the affordance appears | — |
| AI move (any kind) | **none** — see Change 3 | #1 / #2 / #3 as above | as above | M12, M13 |
| Undo, board flip, replay step, autoplay, navigation | none | none | — | — |

Two consequences worth stating because they are testable:

1. **The selection haptic leads its animation by up to 140 ms and this is
   correct.** The state committed at the touch; the lift is the picture catching
   up. Firing it at the end of the lift would put a tap in the hand 140 ms after
   the finger left, which reads as lag.
2. **Neither Settings toggle changes a single duration.** A silent game and a
   haptics-off game have byte-identical motion. The toggles gate emission, never
   timing — otherwise a tester's two runs would not be comparable.

Every row of the survey's §6.3.5 never-sole-carrier table still holds under
these changes, with the illegal-tap row's haptic corrected from `.warning` to
`.selection` and one row added for the alignment tick (whose visual carrier is
the M9 target strengthening).

---

## 3.11 Where this supersedes the survey

| Survey §5 / §6 | Superseded by | Why |
|---|---|---|
| Ordinary move: flat **200 ms** | §3.2 distance law, 180–240 ms over seven values | A 6:1 range of legal moves cannot share one duration; the law is derived from constant acceleration and clamped by the accepted band |
| Interruption: **snap-to-end for everything** (§5.3.1, C2, C3) | §3.7 committing / presentational split | The contract's "a new action does not interrupt a running transition" is the authority; the durations here reduce the wait snap-to-end was buying to ≤ 460 ms |
| Check pulse: **ring scale 1.0 → 1.10 → 1.0 over 400 ms** | §3.5 stroke pulse `0.04 p → 0.056 p → 0.04 p` over 420 ms | ×1.10 overlaps the neighbouring disc by `0.036 p`; §2's S6 geometry caps a scale pulse at ×1.0357, which is invisible |
| Illegal mark: 80 · 240 · 200 = **520 ms** | §3.6: 90 · 260 · 130 = **480 ms** | §2.2 S7 promises ≈ 480 ms; and a 200 ms fade-out on a 480 ms mark spends 40 % of its life leaving |
| AI move preceded by an unconditional **150 ms settle** | §3.4 **260 ms floor**, `max(t_ready, t_commit + 260)` | A settle adds delay to every reply including slow ones; a floor adds delay only when the search beat perception |
| Illegal square → `.warning` haptic | `.selection` | Accepted contract, which post-dates the survey |
| "iPad and Mac get **none**" | macOS and iOS get `.alignment` on target strengthening | `SensoryFeedback.alignment` is documented "Only plays feedback on iOS and macOS", and its documented use case is a dragged item reaching alignment |
| One shared 无效 sound for illegal tap and save failure | #5a 无效 / #5b 失败 (owner call) | Accepted contract requires the two to remain distinguishable |
| Board flip **320 ms** | **340 ms** | Derived so no disc exceeds the fastest legal move's `25.0 p/s` over the `6√2 p` corner-to-corner path |
| Undo: 220 ms / 520 ms | 150–200 ms / ≤ 460 ms | Derived from the accepted 250 / 600 ceilings with real headroom |
| Invalid drop: `spring(duration: 0.18, bounce: 0.15)` | `spring(duration: t(d), bounce: 0.12)` | The return distance varies up to `6 p`; and 0.15 is `.snappy`'s documented base bounce, which the contract's "no forceful shake" argues for staying just under |
| Reduce Motion via `accessibilityReduceMotion` | `accessibilityPrefersCrossFadeTransitions` | It is the documented query for "avoid Slide animations and prefer Cross-Fade transitions", it also honours Prefer Cross-Fade Transitions, and on macOS it reduces to the Reduce Motion setting anyway |
| No handling of Reduce Bright Effects | §3.9.4 | `accessibilityReduceHighlightingEffects` is documented and aims squarely at the check pulse and the status beat |

Everything else in survey §5 and §6 that is not listed here I adopt unchanged.

---

## 3.12 What Apple does not publish

Stated plainly, because this document's method requires the distinction.

**3.12.1 Per-interaction durations. All of them.** Apple publishes curves,
springs, and APIs, and exactly three numeric anchors, none of which is an
interaction duration:

- `Animation.easeIn` / `.easeOut` / `.easeInOut` "has a default duration of 0.35
  seconds";
- `Animation.timingCurve(_:_:_:_:duration:)` defaults to `duration: 0.35`;
- the spring family — `.spring`, `.smooth`, `.snappy`, `.bouncy`, and their
  `Spring` counterparts — all default to `duration: 0.5` with documented base
  bounces of 0, 0, 0.15, and 0.3 respectively, where `duration` is "the
  perceptual duration… approximately equal to the settling duration".

**Every millisecond in §3.3.2 is mine**, as is the travel law, the 260 ms
compose floor, the 500 ms activity-indicator threshold, the 120 ms Reduce Motion
crossfade cap, the 120 ms alignment-haptic interval, and the one-frame
sound/haptic latency budget. The accepted contract already anticipates this —
"first-version values subject to adjustment after testing on physical iPhone,
iPad, and Mac hardware" — so this is a known gap, not a surprise. What is
grounded is the *shape*: eased curves for board geometry, opacity substitution
under Reduce Motion, one pulse, haptics paired to their animation, and sound
synchronised to haptics.

**3.12.2 Whether shadows weaken under Increase Contrast.** No HIG page and no
framework page states it. §3.9.3's ×0.5 opacity and ×0.7 radius derive from our
own accepted contract's "resting shadows are reduced under Increase Contrast"
plus the inference that a soft shadow is a low-contrast edge. §1 leans on this;
it should carry the attribution.

**3.12.3 What a game's motion should feel like.** HIG "Motion" is written for
apps and for visionOS comfort. Its game-facing content is one sentence — "when a
game displays a succinct animation that's precisely tied to a successful action,
players can instantly get the message without being distracted from their
gameplay" (HIG "Motion › Providing feedback") — which supports Rule A of §3.1
and says nothing about board games specifically.

**3.12.4 Whether the alignment haptic actually plays on a given Mac.**
`NSHapticFeedbackManager` "provides access to the haptic feedback management
attributes on a system with a Force Touch trackpad" — so a Mac with a mouse, or
an external non-Force-Touch trackpad, gets nothing. `SensoryFeedback` no-ops
silently in that case, which is the correct behaviour, but it means the macOS
haptic is best-effort and must never be the sole carrier. It is not: M9's
visual strengthening carries it.

**3.12.5 Sound design.** Unchanged from the survey's §12.9 — HIG "Playing audio"
covers categories, silence, volume, and routing, and says nothing about what a
game's effects should sound like. The timbres and lengths are design proposals.

---

## Open for the owner

These are the choices in §3 that need the product owner rather than a designer.
Everything else in this section is a designer's call and can be settled by
device testing.

1. **The travel law's visible ratio.** §3.2 gives a chariot 4.5× the velocity of
   a soldier. That is a felt characterisation of the pieces, not a rendering
   detail — it says the chariot is *fast*. Approving the law means approving
   that reading. The alternative (a fixed duration) is defensible and simpler.

2. **Whether the compose beat exists.** §3.4 adds up to 260 ms of latency to a
   fast AI reply, deliberately. A player who wants the machine to answer as fast
   as it can will notice. This is a product judgement about whether the app is
   teaching (beat) or sparring (no beat).

3. **Repeated Undo at ~2.2 decision cycles per second.** §3.7.3. The contract's
   input block is what produces it. The survey wanted to remove the block; I
   recommend keeping it. Walking a 40-ply game back takes about 9 seconds. If
   that is unacceptable, the answer is a product decision — a "return to start"
   action — not a motion change.

4. **Whether the capturing cannon's path curves.** §3.2.5 proposes a straight
   line for every piece. An arc for the cannon would teach the jump, at the cost
   of the only non-straight path in the app. This is a teaching-scope question,
   which is product's.

5. **Whether to split the 无效 sound.** §3.10.3 Change A proposes #5a 无效 and
   #5b 失败 so that a user with haptics off and eyes away can still tell "you
   are learning" from "your game did not save". It costs one more sound to
   design and license.

6. **Whether the alignment haptic ships at all.** §3.10.2 Change 2 is the one
   haptic that repeats within a gesture and the only one that plays on macOS. It
   is a real improvement to pointer drag-to-move and a real risk of feeling
   noisy. It should be built, tested on device, and then approved or cut — not
   approved on paper.

7. **The 3.0 s hold on the save-failure capsule** (M29), inherited from §2.2 S8.
   It is the longest transient in the app and the only one that competes with
   the board for three full seconds. Product owns how loud a recoverable failure
   should be.

8. **The macOS floor and the check pulse.** §3.5.2 shows the pulse leaves
   0.34 pt of clearance at `p = 28`. §2.6 already warns that S6 has nothing
   spare there. If the pulse proves invisible at the Mac minimum, the choice is
   between suppressing the pulse below a pitch threshold and revisiting S6's
   radii — the second reopens §2.4's collision analysis, so it is worth deciding
   before implementation rather than after.
