# Board Visual and Motion Language — Design Proposal

> **Status: Workspace-only design draft. Non-normative.**
>
> Commissioned design for the Mini Xiangqi board's marker vocabulary, motion
> language, capacity behaviour, and Liquid Glass boundaries. Nothing here is an
> accepted contract. Accepted behaviour lives in `MiniXiangqi/docs/`; when a
> decision here is approved it must be written into
> `interaction-design.md` (and `product.md` where it changes scope) before
> implementation.

## How to read this document

Three kinds of statement appear, and they are always separated:

- **Accepted** — what `interaction-design.md`, `product.md`, and
  `xiangqi-rules.md` already decide. I design inside these and say so when I
  think one is wrong (§6).
- **Documented** — what Apple's documentation establishes, cited by page and
  section. Every citation in this draft was retrieved through the Xcode
  documentation tool on 2026-07-27 in this session, except where a line is
  explicitly marked *(carried from the survey's 2026-07-27 retrieval)*.
  Where Apple publishes nothing — per-interaction durations, exact
  Liquid Glass rendering under Reduce Transparency, iPadOS window-size
  breakpoints — I say so and own the value.
- **Proposed** — my design. Numbers are exact so they can be disagreed with
  exactly. The final section lists the decisions that genuinely need the owner.

Relationship to `discussion-drafts/apple-ui-design-survey.md`: that draft is a
useful predecessor and I reuse its verified ground where it still stands, but
several of its proposals are superseded by decisions taken since (Latin
coordinates, a single piece treatment, snap-to-end interruption, a warning
haptic for illegal taps). Where I disagree with the survey I say so inline.

**One vocabulary note.** Throughout, `p` is the **cell pitch**: the distance
between two adjacent board points. Every marker dimension is expressed in `p`
so the vocabulary scales losslessly from the macOS floor to a capped iPad
board. Accepted floors: `p ≥ 44 pt` on iOS and iPadOS, `p ≥ 28 pt` on macOS
(`interaction-design.md § Layout shapes`). The 44/28 pair matches Apple's own
touch guidance: "Make sure frequently used controls are a minimum size of
44x44 pt, and less important controls, such as menus, are a minimum size of
28x28 pt" (HIG "Game controls › Touch controls").

---

# 1. The geometric system

Everything below hangs off five numbers. They are proposed, not accepted, and
they interlock — change one and the collision analysis in §2.4 must be redone.

| Quantity | Value | At p = 44 | At p = 28 (macOS floor) |
|---|---|---|---|
| Cell pitch | `p` | 44 pt | 28 pt |
| Disc diameter | `0.84 p` | 37.0 | 23.5 |
| Symbol size (character em / icon bounding box) | `0.50 p` | 22.0 | 14.0 |
| Board core (7 points + half-cell margin each side) | `7 p` square | 308 | 196 |
| File-numeral strip (top and bottom, outside the core) | see §4.1 | 16 each | 14 each |

**Why a 0.84 p disc and not the survey's 0.86 p.** The whole marker vocabulary
lives in the annulus between the disc edge and the neighbouring disc. With a
0.84 p disc the geometry gives, measured from a point's centre:

- disc edge at `0.42 p`
- cell boundary (halfway to a neighbour) at `0.50 p`
- nearest neighbouring disc edge at `1.00 p − 0.42 p = 0.58 p`
- cell corner at `0.707 p`

That leaves a `0.16 p` working band (7.0 pt at the iOS floor, 4.5 pt at the
macOS floor) between a disc and its neighbour, which is exactly enough to fit
a selection ring, a capture ring, and a double check ring outside the disc
without any of them ever touching an adjacent disc (§2.4 proves this case by
case). At 0.86 p the check ring's outer edge collides with the neighbouring
disc at the macOS floor. The 2 % of disc the board gives up is invisible; the
collision would not be.

**Symbol size.** `0.50 p` gives a 22 pt character at the iOS floor and 14 pt at
the macOS floor — both above Apple's documented minimum text sizes (11 pt
iOS/iPadOS, 10 pt macOS; HIG "Typography › Ensuring legibility"). The glyph
weight is semibold, promoted to bold under Increase Contrast; HIG's contrast
table grants 3:1 to bold text at any size, but the accepted contract demands
4.5:1 for the symbol regardless, which is the stricter and therefore governing
number (HIG "Accessibility › Vision": 4.5:1 up to 17 pt, 3:1 at 18 pt+, 3:1
bold at all sizes).

**One structural rule that makes the vocabulary style-proof.** The three
accepted piece styles may draw rings — 传统's heavier Black ring, 现代's white
inset ring, 高对比's outlined Black disc. The vocabulary stays unambiguous on
all three surfaces because of a single separation rule:

> **A style's rings live at or inside the disc edge (≤ 0.42 p). A marker's
> rings live outside it (≥ 0.44 p), leaving an air gap of at least 0.02 p.**

0.02 p is 0.9 pt at the iOS floor and 0.56 pt at the macOS floor — thin at the
Mac minimum, but rendered at 2× it is a visible dark/light seam, and on the
Mac the marker is never the sole carrier (pointer hover and the lift also
mark the piece). This rule must be written into each style's value work so a
future style cannot accidentally place decoration in the marker band.

**Marker ink.** Markers never use the Red or Black role colours — a red
selection ring would claim a side it does not have. Each style's board surface
defines one **marker ink** per appearance (near-black on light surfaces,
near-white on dark), used at two strengths:

- **Active ink** — selection, legal dots, capture rings, check rings, the
  illegal-tap mark, the keyboard focus ring: contrast **≥ 4.5:1** against that
  style's board surface, both appearances.
- **Record ink** — last-move brackets and the drag-origin marker: the same hue
  at reduced strength, contrast **≥ 3:1**; promoted to active-ink values under
  Increase Contrast.

The two thresholds deliberately mirror the contract's own pair (symbol 4.5:1,
disc boundary 3:1), so a reviewer measures every board element against one of
two familiar gates. Because the carrier is luminance and shape, never hue, the
vocabulary passes Differentiate Without Color with zero conditional code —
the correct result for that setting is a pixel-identical board.

Exact ink values are part of each style's open colour work
(`interaction-design.md § Piece styles` fixes constraints, not values); the
gates above are the acceptance test for whatever values are chosen.

---

# 2. The marker vocabulary

## 2.1 Design position

Twelve states, one shape grammar. The grammar has four families, and no state
borrows another family's geometry:

1. **Circular marks at a point** — small: things about *a point* (legal
   destination, vacated origin).
2. **Rings around a disc** — large: things about *a piece* (selected,
   capturable, in check).
3. **Corner marks on a cell** — angular: things about *history* (the last
   move).
4. **Off-board signals** — the status element: things about *the game* (whose
   turn, check as a fact, unavailability, a failed save).

The accepted contract already fixes several members (dot on empty point, ring
on capturable piece, corner brackets for the last move, check on the general
and in the status, lightest-tick illegal feedback); this section gives every
member exact geometry and the rules for coexistence. Grounding for the
shape-first approach: "Offer visual indicators, like distinct shapes or icons,
in addition to color to help people perceive differences in function and
changes in state" (HIG "Accessibility › Vision").

## 2.2 The states, exactly

All strokes use rounded caps. "Active"/"record" ink per §1. Layer numbers
refer to the z-order in §2.5.

**S1 — Selected piece** *(accepted state; geometry proposed)*
The disc lifts: scale ×1.05, lift shadow on (every style; the lift shadow
belongs to motion and may not be suppressed — accepted). Around it, a **solid
ring**, stroke `0.05 p`, centre-line radius `0.4625 p` (inner edge `0.44 p`,
outer `0.485 p`), active ink, **attached to the piece** so it lifts and scales
with it (under the ×1.05 lift its outer edge reaches ≈ `0.51 p`, still clear
of the neighbouring disc edge at `0.58 p`). The ring exists because scale and
shadow alone must never carry selection: under Increase Contrast shadows
weaken, and a 5 % scale change is not absolutely readable. Layer 7 (ring with
the lifted disc).

**S2 — Legal empty destination** *(accepted: a dot; geometry proposed)*
A **filled dot**, Ø `0.22 p` (9.7 pt / 6.2 pt at the two floors), active ink,
centred on the point, covering the grid crossing. Layer 4. Deliberately small:
a chariot on an open board shows a dozen of these at once, and at Ø `0.22 p`
twelve dots read as an available path, not a rash.

**S3 — Legal capture** *(accepted: a ring around the target, distinguished by
shape; geometry proposed)*
A **dashed ring** around the enemy disc: stroke `0.06 p`, centre-line radius
`0.47 p`, outer edge exactly at the cell boundary `0.50 p`. **Twelve dashes**,
each 18° of arc with 12° gaps — specifying the count rather than a dash length
keeps the pattern identical at every pitch (dash ≈ 6.5 pt / 4.1 pt at the two
floors). Active ink, drawn around a disc that does **not** lift. Layer 6.
Two adjacent capturable pieces' rings meet tangentially at the cell boundary
and never overlap.

**S4 — Last move, origin and destination** *(accepted: corner brackets;
geometry proposed)*
Four **L-shaped corner brackets** per cell, on both the origin cell (now
empty) and the destination cell (under the moved disc's corner clearance):
arm length `0.16 p`, stroke `0.045 p`, inset `0.03 p` from each cell corner,
record ink. Layer 3. Persistent until the next ply replaces them. Angular
where everything else is circular, so they are unconfusable at any size.

**S5 — The AI's just-played move** *(accepted: persistent origin and
destination markers)*
**The same S4 brackets — deliberately not a separate marker.** There is only
ever one last move; after the AI replies it is the AI's, after the human moves
it is theirs. Authorship is carried by the turn status (轮到红方 · 你 implies
the previous ply was the AI's) and by the VoiceOver move announcement, not by
a second bracket style. What the AI's move gets additionally is *timing* — the
compose beat and full move animation of §3.4 — because the human may have
looked away; the brackets are the persistent record for the player who did.

**S6 — General in check** *(accepted: persistent non-colour king-square
treatment plus one brief pulse, and a token in the turn status)*
A **double ring** around the checked general: two concentric solid rings,
stroke `0.04 p` each, centre-line radii `0.46 p` and `0.54 p` (outer edge
`0.56 p`, inside the neighbouring disc edge at `0.58 p`; clear gap between the
rings `0.04 p` ≈ 1.8 pt / 1.1 pt). Active ink, layer 6, persistent for as long
as the side is in check. One pulse on appearance (§3.5), never repeated —
continuous flashing is ruled out by the contract and by HIG "Motion › Best
practices" ("Gratuitous or excessive animation can distract people and may
make them feel disconnected or physically uncomfortable").
In the status element, a **将军 token**: a small filled capsule in active ink
beside the side-to-move line, present exactly while check persists. The board
treatment alone is missable at a glance; the status token is re-findable and
gives VoiceOver a stable place to re-read the fact.
No hazard badge. The survey proposed an SF-symbol triangle on the disc; on a
37 pt disc already carrying a character, a 10 pt badge is clutter, and the
double ring + status token + announcement already give three channels.

**S7 — Illegal tap** *(accepted: brief visual feedback, lightest haptic tick,
never a warning pattern)*
A **crossed circle** at the tapped point: circle Ø `0.44 p`, stroke `0.045 p`,
with an ✕ of arm length `0.20 p` inside, active ink, layer 8 (topmost,
transient ≈ 480 ms; §3.6). It appears on the point, not the screen edge,
because the learner's question is "why not *here*" — the mark answers at the
place the question was asked. The selection is retained (accepted), so the
dots stay visible around the ✕ and the correction is one tap away.
The ✕ is inside a circle so it cannot be misread as a palace diagonal
fragment, the only other diagonal strokes on the board.

**S8 — Save-failure feedback** *(accepted: brief, non-blocking, distinct from
illegal-move feedback)*
**Not on the board.** A transient capsule anchored to the status element:
proposed copy **无法保存这一步，请重试。**, warning haptic (the accepted reserve
for genuine failures), in 160 ms, hold 3.0 s, out 220 ms, tap-to-dismiss.
Distinctness from S7 is structural — different surface (status vs board),
different geometry (text capsule vs ✕), different haptic (warning vs lightest
tick) — satisfying the accepted "distinct from illegal-move feedback" without
inventing a second board mark. The board itself shows nothing: the position
did not change, and the board only ever shows the position and its states.

**S9 — Unavailable input** *(accepted: reject before visually moving a piece;
treatment proposed)*
No board mark. A single **acknowledgment beat** on the turn-status element:
its background rises to full emphasis and falls back over 140 ms — opacity
only, no translation, no scale — plus the same lightest haptic tick as S7.
The reason input is unavailable is always already on screen (轮到黑方 · AI,
AI activity, or the result card); the beat points at it rather than repeating
it, which honours the accepted refusal of "please move"-style copy while
still answering the tap ("Show people when a command can't be carried out and
help them understand why" — HIG "Feedback › Best practices" *(carried from
the survey's retrieval)*). The board is not dimmed while the AI thinks: the
position is exactly what a learner wants to study during that pause, and the
result contract requires the final board fully visible — one rule for both.
A per-point ✕ here would lie: it would say "this square is illegal, try
another", when the truth is "no square accepts input right now."
In replay, the board is a read-only document; taps on it do nothing at all —
no beat, no tick — because feedback would imply an interactivity that
deliberately does not exist there.

**S10 — Dragged piece** *(accepted: follows the touch, origin keeps a subtle
marker, nearby legal target strengthens)*
The disc detaches at scale ×1.10 with the strongest lift shadow, layer 7,
following the touch or pointer 1:1. On touch platforms it is offset `0.5 p`
above the touch point so the fingertip never hides it; with a pointer there
is no offset. Its selection ring (S1) comes along.
The **origin marker** is a **hollow dot**: ring Ø `0.22 p`, stroke `0.045 p`,
record ink, layer 4 — the vacated twin of S2's filled dot (filled = "can go
here", hollow = "came from here"; the origin is never itself a legal
destination, so the two never claim the same point).
**Target strengthening:** while the drag position is within `0.45 p` of a
legal point, that point's S2 dot scales to Ø `0.33 p` (a 1.5× step, an
unmistakable state change rather than a wobble) or its S3 ring's stroke
thickens to `0.08 p`; the strengthening releases when the drag moves beyond
`0.55 p`. The 0.1 p hysteresis prevents flicker while sliding along a cell
boundary.

**S11 — Pointer hover** *(macOS, iPad pointer; proposed)*
A faint **rounded-square fill** under the pointer's point: `0.90 p` square,
corner radius `0.12 p`, marker ink at low opacity, layer 2, no border. It is
the only filled-area marker and the only rectangle besides S12, so it cannot
be confused with any state; it communicates "the pointer is here", not
legality. No hover-preview of legal moves in this draft — that is survey
decision D16, still the owner's, and nothing here depends on it.

**S12 — Keyboard focus cursor** *(iPad Full Keyboard Access, macOS; proposed)*
A **rounded-square outline** at the focused point: `0.94 p` square, stroke
`0.06 p`, corner radius `0.14 p`, in the platform focus colour (the one marker
that is deliberately hue-carried *in addition to* its unique rectangular
shape, matching every other focus ring on the platform). Layer 6.

## 2.3 Sizes at the floors — the legibility table

| Marker | Dimension | At p = 44 | At p = 28 |
|---|---|---|---|
| S1 selection ring | stroke 0.05 p | 2.2 pt | 1.4 pt |
| S2 dot | Ø 0.22 p | 9.7 pt | 6.2 pt |
| S3 capture ring | stroke 0.06 p; dash/gap | 2.6; 6.5 / 4.3 pt | 1.7; 4.1 / 2.7 pt |
| S4 brackets | arm 0.16 p, stroke 0.045 p | 7.0 / 2.0 pt | 4.5 / 1.3 pt |
| S6 check rings | stroke 0.04 p; inter-ring gap 0.04 p | 1.8 / 1.8 pt | 1.1 / 1.1 pt |
| S7 crossed circle | Ø 0.44 p | 19.4 pt | 12.3 pt |
| S10 origin ring | Ø 0.22 p, stroke 0.045 p | 9.7 / 2.0 pt | 6.2 / 1.3 pt |
| S12 focus square | 0.94 p, stroke 0.06 p | 41.4 / 2.6 pt | 26.3 / 1.7 pt |

Every stroke stays above 1 pt at the macOS floor; every distinguishing gap
(dash gap, inter-ring gap, disc-to-marker air gap) stays at or above ≈ 0.6 pt,
which at 2× rendering is a full pixel. The macOS floor is the worst legal
case everywhere in this table; the iOS floor is comfortable.

## 2.4 Composition — what can coexist, and where the collisions were designed out

Maximum simultaneous load, all legal at once: a selected piece (S1) with its
dots (S2, up to ~12) and capture rings (S3, up to ~4), last-move brackets on
two cells (S4), a checked general (S6), a hover fill (S11), a focus square
(S12), and a transient ✕ (S7). The vocabulary was sized for this worst case,
not the average one.

Same-cell pairings, exhaustively:

- **S2 dot + S4 brackets** (last-move cell is now a legal destination):
  dot at the centre, brackets at the corners; nearest approach `> 0.3 p`. No
  interaction.
- **S3 capture ring + S4 brackets** (capturable piece that just moved): the
  ring's circle at radius ≤ 0.50 p passes the cell-edge midpoints; the bracket
  arms occupy the corner regions (from `0.707 p` inward by `0.16 p` along the
  edges). Geometrically disjoint.
- **S3 + S6** — a capture ring around a checked general: **cannot occur.** A
  general is never a legal capture target (a position where the general could
  be taken is already illegal under the accepted movement rules), so the
  dashed ring and the double ring never share a disc.
- **S4 + S6** — brackets on the checked general's cell: **cannot occur.** The
  checked side is the side to move; the last move was the opponent's; its
  origin is now empty and its destination holds the opponent's piece, so
  neither cell is the checked general's. This holds in Free Play and after
  Undo by the same argument, and for discovered check (the moved piece's cells
  are still the opponent's).
- **S1 + S6** — selecting your checked general: the one true composition.
  Rule: while the checked general is selected, the **inner** check ring hides
  and the **outer** (0.54 p) remains; the selection ring (attached, 0.4625 p
  → ≈ 0.486 p under lift) sits inside it with a clear gap. Read: "held, and
  still in check." On deselect both check rings return. While the general is
  *dragged off its point*, both check rings hide (rings around an empty point
  would assert a piece that is not there) and the 将军 status token — which
  never hides — carries the state; the rings return on an invalid drop.
- **S7 + anything**: the ✕ is topmost and transient; it may momentarily
  overlay a bracket cell or an occupied point, which is correct — it marks
  the tap, whatever was under it.
- **S11/S12 + anything**: fills and rectangles under or around the circular
  vocabulary; no shared geometry.
- **Two generals both in check**: impossible position; no rule needed.

## 2.5 Z-order

From the board up: **0** style board surface (opaque) → **1** grid and palace
diagonals → **2** hover fill (S11) → **3** last-move brackets (S4) → **4**
dots and origin marker (S2, S10-origin) → **5** resting discs with their
style resting shadows → **6** rings around resting discs (S3 capture, S6
check, S12 focus) → **7** the lifted or dragged disc, its lift shadow cast on
everything below, and its attached S1 ring → **8** the transient ✕ (S7).
Rings sit above discs so no neighbouring disc can ever clip one; the geometry
already guarantees no overlap, the z-order makes the guarantee robust against
future style edits.

## 2.6 The unambiguity argument

Claim: **no two markers are confusable at the smallest supported size, on any
of the three board surfaces, in light or dark, with either symbol set.**

By geometry class: {small filled circle} = S2 only. {small hollow circle} =
S10-origin only. {large solid single ring} = S1 only. {large dashed ring} =
S3 only. {double ring} = S6 only. {corner Ls} = S4 only. {✕-in-circle} = S7
only. {area fill} = S11 only. {rounded-square outline} = S12 only. Every
class has exactly one member, so the only risk is *between* classes:

- **S2 vs S10-origin** (filled vs hollow, same Ø): at the macOS floor the
  hollow's void is 3.6 pt — perceptible, and the two also never mean
  alternatives to each other: the origin marker exists only mid-drag, when
  the user is holding the piece that vacated it.
- **S1 vs S3** (solid vs dashed ring): the dash gaps are ≥ 2.7 pt at the
  macOS floor; additionally the two can never co-occur on one disc (S1 rings
  your lifted piece, S3 rings a resting enemy piece), and the styles make the
  disc under them structurally different by side. Three independent
  disambiguators.
- **S3 vs S6** (dashed single vs solid double): dash presence, ring count,
  and S6's exclusivity to a general.
- **S1/S3/S6 vs style rings**: the §1 separation rule — style rings at or
  inside `0.42 p`, marker rings at `0.44 p+` with an air gap. On 高对比's
  outlined Black disc, the disc's own outline is its edge; a capture ring
  around it reads as ring-outside-ring with a visible seam, dashed against
  solid.
- **S4 vs everything**: the only angular marks. The palace diagonals are the
  sole other non-circular strokes, and they are full-cell diagonals at grid
  weight in the grid's colour, not corner Ls in record ink.
- **Style-surface independence**: every marker is drawn in that surface's
  marker ink at ≥ 4.5:1 (active) or ≥ 3:1 (record), values that are part of
  each style's palette work and gated by measurement, so the vocabulary holds
  on the warm 传统 surface, the neutral 现代 surface, and the separation-tuned
  高对比 surface, in both appearances, with shadows removed, under Increase
  Contrast (record ink promotes to active). No marker changes shape between
  styles — one grammar, three surfaces.
- **Symbol-set independence**: markers never touch the disc face, so 汉字
  versus 图标 changes nothing in this section.

The residual risks I want named rather than hidden: the `0.02 p` disc-to-ring
air gap and the S6 inter-ring gap both bottom out near 1 physical pixel at
the macOS 28 pt floor. They are legible there, but nothing is spare. If the
owner ever lowers the macOS floor below 28 pt, S6 must collapse to a single
thick ring (0.06 p at 0.50 p) and the air-gap rule must be re-derived — at
28 pt it all still works, below it the arithmetic breaks.
