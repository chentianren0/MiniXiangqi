# Perpetual-check and perpetual-chase edge cases — reconciliation of designs A and B

This document adjudicates the two blind designs
`discussion-drafts/rules-edge-cases-design-a.md` (normative-first) and
`discussion-drafts/rules-edge-cases-design-b.md` (implementation-first), verifies every claimed
engine defect against the **current** fork, and produces one recommended rule per open question, one
merged fixture slate, and the short list of decisions that need the product owner.

Nothing here changes a repository. `MiniXiangqi/`, `Fairy-Stockfish/` and `pychess-variants/` were
read only.

---

## 0. Evidence base and method

**Engine actually tested.** Both designs were written against Fairy-Stockfish `c19b5f6c`; design B
read the source at fork HEAD `77d602e0` but ran a **pre-patch** binary. Neither design's numbers were
produced by the engine we are going to ship. So the fork was copied to
`discussion-drafts/r-scratch/` and rebuilt from `77d602e0`:

```
pyffish (0, 0, 89)  Fairy-Stockfish 270726 LB
```

and driven through the **target** variant, which is the first time
`promotedSoldiersChaseable = false` has been exercised in this analysis:

```ini
[minixiangqitarget:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
```

**Baseline.** All sixteen approved fixtures in `MiniXiangqi/fixtures/rules/` replay clean against
this build and this variant — legality, `result_fen`, `in_check`, `game_state`, and the `boundary`
prefix (`discussion-drafts/r-approved.py`). In particular `mx-chs-003` (soldier not a chase target)
now passes without a divergence note. The merged patch does what it says.

**Everything below was re-run, not inherited.** All 49 fixtures proposed across the two designs were
replayed against this build (`discussion-drafts/r-allfix.py`). Every one behaves exactly as its
author reported. The only divergences from the engine are the four patch-gating fixtures, which are
exactly the claimed defects.

Scripts written for this pass, all under `discussion-drafts/`, prefix `r-`:
`r-harness.py` / `r_harness.py` (shared driver), `r-approved.py` (approved-fixture replay),
`r-claims.py` (defect reproductions), `r-claims2.py` (parity, tightened repro, per-ply check states),
`r-allfix.py` (all 49 proposed fixtures), `r-p4search.py` / `r-p4b.py` (reachability search for the
one unproven claim).

**Normative source**, quoted verbatim where it does work below
(`pychess-variants/static/docs/minixiangqi.md:20-24`, identical in the retained HTML snapshot):

> * A player making perpetual checks with one piece or several pieces can be ruled to have lost unless he or she stops such checking.
> * The side that perpetually chases any one unprotected piece with one or more pieces, excluding generals and soldiers, will be ruled to have lost unless he or she stops such chasing.
> * If one side perpetually checks and the other side perpetually chases, the checking side has to stop or be ruled to have lost.
> * When neither side violates the rules and both persist in not making an alternate move, the game can be ruled as a draw.
> * When both sides violate the same rule at the same time and both persist in not making an alternate move, the game can be ruled as a draw.

---

## 1. Headline adjudication

**The two designs agree on far more than they disagree on.** Every rule *statement* in A §5 and B §2–7
is compatible with the other's, with three exceptions, all settled here against the source:

| # | Disagreement | Settled |
|---|---|---|
| 1 | **Is mutual perpetual check constructible on 7×7?** A: no, with a case analysis and a 42,073-position negative search. B: yes, six pieces. | **B is right; A is wrong.** Verified: `3c3/7/2k3C/3n3/4N2/7/3K3 w`, `e3d5 d4f5 d5e3 f5d4` ×2 — the side to move is in check at all nine plies (`TTTTTTTTT`) and the engine returns `(True, 0)` under both the AXF child and the built-in variant. A's case analysis only ruled out *king*-move discoveries and then relied on a search it correctly labelled "strong evidence, not a proof". |
| 2 | **Is a check-over-chase (mixed) fixture constructible?** A: not built, "recipe now known". B: yes, five pieces. | **B is right.** Verified: `3k3/7/1r3N1/7/7/2K4/3C3 w`, `f5d6 b5d5 d6f5 d5b5` ×2 → Red (the checker) loses, with the cannon-deleted control proving Black's chase is real. |
| 3 | **Does the engine's "novelty" filter mean "this attack did not exist before"?** A §5.3/§6.4: yes, "believed sound". B §1.2: no — a moved rook or cannon re-enters as *its own* discovery candidate. | **B is right.** `position.cpp:3044` intersects `PseudoAttacks[WHITE][ROOK][from]` with `pieces(~sideToMove, CANNON, ROOK)`; for a rook or cannon move `to` is always on `PseudoAttacks[ROOK][from]` and the moved piece now stands on `to`, so it is always a candidate. Its along-the-line attacks, discarded by `~line_bb(from, to)` at `:3037`, are then re-admitted by the exact before/after test at `:3050-3052`. Empirically decisive: `mx-chs-030` vs `mx-chs-031` differ only in whether the entry move approaches *along* the file or *across* onto it, and the engine treats only the second as a chase. |

**A did not miss the flying-general pin defect entirely** — A §6.4 flags exactly that code path
(`position.cpp:2979-2984` does not check that the pieces on the file stand *between* the kings) and
says "No probe here triggered it… Not resolved." B constructed the witness. That is a difference in
thoroughness, not a conflict.

**Two claims are B's alone and both are real:** the chase-window parity defect (§3.3) and the
discovered-check exemption gap (§3.5). **One claim is A's alone and it is real:** the mutual-chase
outcome is not reportable from the engine's return value (§3.4).

---

## 2. Proven facts — what the current engine does

All line numbers are fork HEAD `77d602e0`.

- `Position::chased()` (`position.cpp:2973-3096`) runs after every move (`position.cpp:598`) and
  returns the set of **victim** squares (`sideToMove`) that the **chaser**'s (`~sideToMove`) last
  move put under a chasing attack.
- **Exempt targets** (`position.cpp:2988-2990`): `chaseExempt = kings ∪ soldiers`, minus promoted
  soldiers when `promotedSoldiersChaseable`. Mini Xiangqi's `soldierPromotionRank` is the inherited
  default `1` (`variant.h:118`, `position.h:891-894`), so *every* soldier is "promoted" from move one
  and the property is what makes the exemption real. It is applied in `addChased`
  (`position.cpp:2995`) and in the fake-roots path (`position.cpp:3066`) but **not** in the
  discovered-check path (`position.cpp:3081-3091`) — scoped that way by the fork's own doc line
  (`variants.ini:260`).
- **Value ordering** (`position.cpp:2997-2998`): a horse or cannon attacking a **rook** is chased
  unconditionally, before any protection test.
- **Symmetric-attack exclusion** (`position.cpp:3016`): targets of the same type as the attacker are
  dropped unless they are in `pins`.
- **Protection** (`position.cpp:3021-3022`): `roots = attackers_to(s, pieces() ^ attackerSq, victim) & ~pins`;
  chased when there is no root, or when the only root is the victim's king and that king's recapture
  would face the two kings on an open file. Occupancy has the attacker removed, so X-ray/battery
  defence counts and cannon screens are evaluated post-capture. `attackers_to` gates every piece type
  by its mobility region (`position.cpp:963`, `position.h:430-433`), so a king defends only inside its
  own palace (`variant.cpp:1237-1238`).
- **Attacker exclusion** (`position.cpp:3032`): a king or soldier mover creates no direct attack, but
  the discovery loop is not gated on the mover, so a king or soldier move can still uncover a chase.
- **Repetition aggregation** (`position.cpp:2648-2718`): the walk fires at the third occurrence
  counting the first (`:2701-2702`); perpetual check outranks chase unconditionally (`:2704-2707`);
  the chase bitboards are carried back through the *victim's* own moves by `undo_move_board`
  (`bitboard.h:200-202`), so a chased piece is tracked as a **piece**, not as a square.

---

## 3. The claimed defects, verified

Every reproduction below was run on the current build with the target variant.
`is_optional_game_end` returns a **side-to-move-relative** value; the loser column translates it.

### 3.1 Pinned attacker chases — CONFIRMED. Claimed by both. Wrong terminal loss.

**Proven fact.** Neither the direct path nor the discovered path tests whether the chasing piece can
legally make the capture. `blockers_for_king(~sideToMove)` appears only in the fake-roots branch
(`position.cpp:3071`).

**Reproduction** (A's; B's `2r1k2/7/7/2R4/4c2/7/2K4 w`, `c4c3 e3e4 c3c4 e4e3` ×2 is the same bug):

```
FEN   3rk2/7/7/3R3/1c5/7/3K3 w - - 0 1
moves d4d3 b3b4 d3d4 b4b3 d4d3 b3b4 d3d4 b4b3
ply 4 -> (False, -)      ply 8 -> (True, -32000)  Red loses
```

White's rook on d4/d3 is absolutely pinned by the black rook on d7 against the white king on d1. It
"attacks" the black cannon on b3/b4 along the rank, but `Rxb3` and `Rxb4` are illegal at every ply of
the game. Red loses a game on a threat that can never be executed. A Mini Xiangqi player would call
this plainly wrong. **PATCH-REQUIRED.**

Minimal semantics (B's, and it is exact):

> When the chasing piece — the mover for a direct attack, or the discovering piece for a discovered
> attack — is a blocker for its own king, restrict its chasing attacks to the line between its own
> king and itself.

A pinned rook or cannon may capture only along the pin line; a pinned horse can never capture legally,
and the same expression yields that because a horse's attack set never meets the line through its own
square.

### 3.2 Flying-general false pin — CONFIRMED, with a tightened reproduction. Claimed by B. Wrong terminal loss.

**Proven fact.** `position.cpp:2981-2983` computes the flying-general pin from
`file_bb(file_of(square<KING>(~sideToMove))) & pieces(sideToMove)` — the **victim's** pieces only. A
**chaser** piece standing between the kings is invisible to it, so a victim piece that is
demonstrably free is marked pinned, which both voids its defensive value and bypasses the
symmetric-attack exclusion at `position.cpp:3016`.

B's witness uses a white **horse** on c3 as the blocker; that horse also defends a4, so a reviewer
could argue White's chase is materially real and the fixture's "draw" expectation is arguable. This
pass tightened it to a blocker that defends nothing:

```
FEN   2k4/7/R6/2r4/7/2P4/2K4 w - - 0 1        (white soldier c2 blocks the c-file)
moves a5a4 c4c5 a4a5 c5c4 a5a4 c4c5 a4a5 c5c4
ply 4 -> (False, -)      ply 8 -> (True, -32000)  Red loses
control, white king on d1 instead of c1  ->  (True, 0)  draw
```

Both rooks are undefended and attack each other on equal terms — the exact shape the engine correctly
rules a non-chase when the kings are off a shared file. The black rook is not pinned: its legal moves
after `a5a4` are `c4a4 c4b4 c4c2 c4c3 c4c5 c4c6 c4d4 c4e4 c4f4 c4g4`. Red still loses.
**PATCH-REQUIRED.**

Minimal semantics:

> The flying-general pin applies only when the two kings share a file and the piece under
> consideration is the only piece **of either colour** standing between them.

i.e. compute the between-squares occupancy over `pieces()`, not over `pieces(sideToMove)`.

### 3.3 Chase window is one move too wide for one parity — CONFIRMED. Claimed by B alone. Wrong result.

**Proven fact.** In `is_optional_game_end`, `chaseThem` is updated **before** the repetition test
(`position.cpp:2694-2695`) and `chaseUs` **after** it (`position.cpp:2716`). At the firing occurrence
`T_k`, `chaseUs` spans the violating side's moves at `T_1 … T_{k-1}` — exactly the moves strictly
inside the three-occurrence window — while `chaseThem` additionally intersects `chased(T_k)`, the
chase set of the move that *created* the first occurrence, which lies outside the window. The
`i != st->pliesFromNull` guard (`position.cpp:2694`) hides this only when the recorded history begins
exactly at that occurrence, which is true of every fixture in the approved set and false of every
real game.

**The decisive reproduction is a parity differential on one position with one entry move.** Same
start FEN, same non-chasing entry move `a1a3`, same four chasing White moves at plies 3/5/7/9:

```
FEN   4k2/7/c6/7/7/7/R1K4 w - - 0 1
  9 plies: a1a3 a5b5 a3b3 b5a5 b3a3 a5b5 a3b3 b5a5 b3a3
           occurrences at plies 1/5/9 (Black to move) -> (True, 0)       DRAW
 10 plies: the same, plus a5b5
           occurrences at plies 2/6/10 (White to move) -> (True, -32000) Red loses
```

The four White moves being judged are identical in both. The engine's answer flips purely on which
parity the adjudication lands on. B's own pair confirms the mechanism from the other direction: with a
*chasing* entry move `b3a3` the 9-ply case becomes `(True, 32000)`, Red loses.

Direction of the error: `chaseThem` is an intersection, so the extra term can only shrink it. The
common effect is a **missed** violation (draw instead of a loss). The dangerous corner is a mutual
chase in which `chaseThem` is wrongly emptied while `chaseUs` survives — that converts a
`mutual-perpetual-chase` draw into a unilateral loss for the wrong side. **PATCH-REQUIRED**, on the
ground that no rule can make the same four moves a violation for one colour and not the other.

Minimal semantics: defer the final `chaseThem` intersection past the repetition test, mirroring how
`chaseUs` is already updated after it, and drop the now-unnecessary `i != pliesFromNull` special case.

### 3.4 Mutual perpetual chase is not reportable — CONFIRMED. Claimed by A alone. Unreportable outcome.

**Proven fact.** `is_optional_game_end` returns `(True, 0)` for a neutral threefold, for a mutual
perpetual check, and for a mutual perpetual chase alike (`position.cpp:2704-2707` collapses all three
onto `VALUE_DRAW`). Measured:

| history | value | check state per ply |
|---|---|---|
| neutral threefold (king shuffle) | `(True, 0)` | `fffffffff` |
| mutual perpetual chase (`mx-mix-002`) | `(True, 0)` | `fffffffff` |
| mutual perpetual check (`mx-mix-001`) | `(True, 0)` | `TTTTTTTTT` |

The accepted contract reserves `mutual-perpetual-check` and `mutual-perpetual-chase` as distinct
reason identifiers and makes unilateral violations auto-terminal while only neutral repetition is
claim-gated. The facade therefore has to tell these three apart.

**How far the facade can get without the engine** — this is more precise than either design stated:

- value `±MATE` and the losing side gave check at every one of its moves in the span → `perpetual-check`;
- value `±MATE` otherwise → `perpetual-chase` (exact, because check outranks chase, so a check-based
  loss can never be reported as a chase-based one);
- value `0` and both sides checked at every one of their moves in the span → `mutual-perpetual-check`;
- value `0` otherwise → **ambiguous**: neutral threefold or `mutual-perpetual-chase`, indistinguishable.

So only `mutual-perpetual-chase` is unreportable, and it is unreportable in a way the facade cannot
work around without reimplementing `chased()`. **PATCH-REQUIRED (read-only accessor)** or an explicit
contract change; see the product-owner decision in §7.

A's option 3 — treat a mutual perpetual chase as a claimable threefold — is textually defensible
(bullets 4 and 5 use the identical modality "can be ruled as a draw", while unilateral violations get
"will be ruled to have lost") but it contradicts the accepted line that only neutral repetition is
claim-gated, so it is a contract change, not a silent adoption.

### 3.5 Discovered-check path ignores the exempt-target mask — code gap CONFIRMED, reachability NOT established. Claimed by B alone.

**Proven fact.** The discovered-check block (`position.cpp:3081-3091`) applies neither `chaseExempt`
nor any attacker-type restriction, and the fork's merged property is documented as not covering it
(`variants.ini:260`). A discovered-check battery can therefore put the victim's **soldier** into the
chased set, and the "attacker" credited there may itself be a chaser soldier or king. That contradicts
both halves of the accepted rule "kings and soldiers are excluded as perpetual-chase targets".

B did not construct a sustained example and neither did this pass. A targeted search was run with a
clean oracle: give the victim only a king and soldiers, so any AXF chase verdict against that side
must have come from this unmasked path; require that no ply is a check (which isolates the chase
branch from perpetual check) and that the built-in variant, which has no chasing rule, returns a
draw. Result: see §6. **The claim is a real code gap of unproven reachability**, not a demonstrated
wrong result.

### 3.6 King as sole root: only the flying-general reason is modelled — CONFIRMED as a divergence. Claimed by A (PATCH-OPTIONAL) and B (ADOPT-with-documentation). Under-detection only.

**Proven fact.** `position.cpp:3022` models exactly one reason a king cannot recapture. Both designs
found the same hole from different geometries and both reproduce:

```
A: 7/3k3/3c3/6R/4N2/7/2K4 w   g4g5 d5d4 g5g4 d4d5 ×2   -> (True, 0) draw
B: 2k4/4R2/2c4/1N5/7/7/3K3 w   e6e5 c5c6 e5e6 c6c5 ×2   -> (True, 0) draw
   control without the horse                             -> (True, 0) draw
   control with the flying general instead (2K4)         -> (True, -32000) Red loses
```

Strictly the target is unprotected — the king's recapture is illegal because a second enemy piece
covers the square — so under the source's word "unprotected" this should be a chase. The engine rules
it a neutral, claimable repetition. The failure direction is benign: a violation degrades to a draw
the user may decline, never to a wrong loss. **Recommend ADOPT** with the limitation written into the
contract and pinned by a fixture, which is B's position; A's PATCH-OPTIONAL is the same finding with a
different risk appetite. See §7 for the decision.

### 3.7 Fake roots over-approximate — flagged by both, patch requested by neither

`position.cpp:3056-3074` marks a piece chased when a newly pinned defender had been defending it,
with no value ordering, no symmetry exclusion, no attacker-type filter, and **no check that the newly
pinned piece was the only defender**. Neither design constructed a sustained case; neither asks for a
patch. Recorded as an adopted limitation in the contract, not a patch claim.

---

## 4. Recommended rules

Each rule is stated in prose suitable for lifting into `docs/xiangqi-rules.md`.

### Q1 Protection — MIXED (definition ADOPT-ENGINE; flying-general pin PATCH-REQUIRED)

> A chased piece is **protected** when, in the position that would arise if the chasing piece captured
> it, some piece of its own side could legally capture on that square; otherwise it is **unprotected**.
> The test is applied with the chasing piece removed from the board, so a defender whose line to the
> square runs through the chasing piece counts, and a cannon protects a square only through exactly one
> screen and therefore never protects the piece immediately next to it. Soldiers protect normally:
> their exclusion from the chase rule applies to being chased and to chasing, not to defending. A
> defender that is pinned against its own king, or that is pinned by the flying-general rule, does not
> protect. A king protects a square only when that square lies inside its own palace and its capture
> there would not leave the two kings facing each other on an otherwise empty file. A piece is pinned
> by the flying-general rule only when the two kings stand on the same file and it is the only piece,
> **of either colour**, standing between them. Where a king's recapture would be illegal for some other
> reason — for example because a second enemy piece also covers the square — this contract nevertheless
> treats the chased piece as protected; this is a deliberate simplification, pinned by `mx-chs-011`.

Both designs derive the same definition from the same reading of "unprotected", and the engine
implements it including X-ray defence, cannon screens, palace confinement and pinned defenders. The
only part that needs a fork change is the flying-general pin's blindness to chaser pieces.

### Q2 Interruption — ADOPT-ENGINE

> A perpetual violation is judged over the **span** running from the first of three occurrences of the
> repeated position to the position now on the board. Within that span a side commits perpetual check
> only if the other side is in check at every one of its turns, and perpetual chase only if every one
> of that side's own moves renews the attack on one and the same enemy piece. A single move by that
> side that does not renew its violation ends it, and the repetition is then adjudicated as neutral
> unless the other side is itself violating. Interruptions by the opponent are irrelevant: a check or a
> threat by the other side neither creates nor excuses a violation. A side that interrupts its own
> sequence and later resumes becomes liable again as soon as three occurrences of a position are
> spanned entirely by violating moves; those three occurrences need not be the first three, so a
> violation may attach at a fourth or later occurrence of the same position.

The last sentence is the one thing neither design stated explicitly and it is directly observable:
`mx-chs-022` reaches a neutral claimable draw at its third occurrence (ply 8) and the perpetual-chase
loss at its fourth (ply 12).

### Q3 Discovered and pinned attacks — MIXED (discovered ADOPT-ENGINE; pinned attacker PATCH-REQUIRED)

> A chase is judged by the threat the move produces, not by which piece moved. A move that opens
> another piece's line or horse leg onto an enemy piece, or that supplies the screen a cannon needs,
> chases that piece exactly as a direct attack does, and the chasing piece is the piece that makes the
> threat, not the piece that moved. Only a threat the move renews counts: a move renews the attack when
> the chasing piece, from the square it occupies **after** the move, attacks the chased piece and did
> not attack it from that same square before the move. A chasing piece that steps away from a target
> and still attacks it from its new square therefore renews the chase, while a piece that merely
> advances along a line on which its attack already stood does not. A check is a check however it is
> delivered, and a discovered check counts in full. An attack by a piece that could not legally make
> the capture — in particular a piece absolutely pinned against its own king, when the capture square
> lies off its pin line — is not a threat and is not a chase.

The renewal sentence is B's; A's prose ("renewing an attack that already existed before the move is
not a chase") is wrong about the engine and is not adopted. The distinction is exactly the one
`mx-chs-030` / `mx-chs-031` isolate.

### Q4 Mutual and mixed sequences — MIXED (precedence and mutual draw ADOPT-ENGINE; class definition CONTRACT-ONLY; mutual-chase reason PATCH-REQUIRED)

> There are exactly two classes of perpetual violation: perpetual check and perpetual chase. Two sides
> commit the **same class** when, over the same span, each independently satisfies that class's test;
> their targets and the pieces involved need not correspond in any way. Both sides committing perpetual
> check is a draw with reason `mutual-perpetual-check`; both committing perpetual chase, with neither
> perpetually checking, is a draw with reason `mutual-perpetual-chase`. If one side commits perpetual
> check, that side loses regardless of what the other side is doing, including a simultaneous perpetual
> chase: perpetual check outranks perpetual chase without exception. A side whose moves in the span are
> neither all checks nor all chases of one and the same piece has committed neither violation; a
> sequence alternating check and chase is therefore not a violation under this contract.

### Q5 Terminal boundary — MIXED (semantics ADOPT-ENGINE; window parity PATCH-REQUIRED)

> A violation is sustained across three occurrences when, for the whole span, the violating side is the
> same, the class is the same, and — for a chase — one and the same enemy piece has its attack renewed
> by every move the violating side makes **strictly after** the first of the three occurrences. The
> chased piece is identified as a piece and followed through its own moves, so it may change square;
> the chasing piece and the attacked square may change from move to move. Moves made before the first
> of the three occurrences are not part of the test, and the test must span the same moves whichever
> side is to move at the moment of adjudication. Chasing two different pieces alternately is a
> perpetual chase of neither.

### Q6 Target and attacker classes — MIXED (ADOPT-ENGINE; soldier target patch landed; discovered-check mask PATCH-RECOMMENDED)

> Kings and soldiers take no part in the perpetual-chase rule as targets or as chasing pieces: neither
> may be the chased piece, and a move by a king or a soldier never creates a chase. A king's or a
> soldier's move may still open another piece's line or horse leg, and the resulting threat is a chase
> by that other piece. Kings and soldiers protect normally. A piece of the same type as the chasing
> piece is not a chase target, because the attack is mutual and the target can answer it — unless that
> piece is pinned and therefore cannot answer. Independently of protection, an attack by a horse or a
> cannon on a chariot is always a chase, because the capture wins material even after the recapture. No
> other value relation overrides protection in Mini Xiangqi: the chariot is the only piece these rules
> treat as strictly stronger than the horse and the cannon, and the horse and the cannon are treated as
> equals.

Note for the contract: the source phrase "with one or more pieces, excluding generals and soldiers"
(`minixiangqi.md:21`) is grammatically ambiguous between the chasing pieces and the chased piece. The
engine implements **both** readings and both are standard AXF practice; the accepted contract states
only the target reading, and the attacker reading should be added. The horse-or-cannon-versus-chariot
clause is an addition the retained source does not literally support; the contract should record the
reasoning rather than imply the source says it.

---

## 5. Merged fixture slate

Identifiers continue the accepted series (`mx-chs-005…`, `mx-chk-003…`). One new area `mx-mix-*` is
proposed, defined as **cross-class and both-sides outcomes**: mutual violations, check-over-chase
precedence, and mixed-class sequences. This needs a one-line addition to
`fixtures/rules/README.md`. Filing a mutual-check fixture under `mx-chk-*` would misfile it under a
unilateral heading.

Both designs assigned overlapping identifiers to different fixtures; the mapping column records where
each came from so the two drafts stay traceable. `M8(a,b,c,d)` means the four-move cycle written
twice: eight plies, three occurrences at plies 0/4/8, boundary `prefix_len = 4`.

Status legend: **V** = constructed-and-validated on the current build (legality, result FEN, check
state, asserted outcome, and boundary prefix all verified); **V(div)** = validated as a construction,
and the asserted outcome is the contract's, which the current engine does **not** produce — these are
the patch-gating fixtures.

### 5.1 Protection (Q1) — `mx-chs-005` … `mx-chs-013`

| id | title | start FEN | moves | expected | from | status |
|---|---|---|---|---|---|---|
| `mx-chs-005` | a pinned defender does not protect | `4k2/7/c3r2/7/1R5/7/2K1R2 w - - 0 1` | M8(b3a3,a5b5,a3b3,b5a5) | black-wins / perpetual-chase @3 | A005 = B005 | V |
| `mx-chs-006` | chase base for the c-file protection family | `3k3/4R2/2c4/7/7/7/2K4 w - - 0 1` | M8(e6e5,c5c6,e5e6,c6c5) | black-wins / perpetual-chase @3 | B006 | V |
| `mx-chs-007` | an X-ray defender behind the attacker protects | `3k3/4R2/2c3r/7/7/7/2K4 w - - 0 1` | M8(e6e5,c5c6,e5e6,c6c5) | claimable-draw / threefold-repetition @3 | B007 | V |
| `mx-chs-008` | a soldier is a valid defender | `3k3/1p2R2/2c4/7/7/7/2K4 w - - 0 1` | M8(e6e5,c5c6,e5e6,c6c5) | claimable-draw / threefold-repetition @3 | B010 | V |
| `mx-chs-009` | king sole defender; the flying general voids the recapture | `2k4/4R2/2c4/7/7/7/2K4 w - - 0 1` | M8(e6e5,c5c6,e5e6,c6c5) | black-wins / perpetual-chase @3 | B008 | V |
| `mx-chs-010` | king sole defender; the recapture is legal | `2k4/4R2/2c4/7/7/7/3K3 w - - 0 1` | M8(e6e5,c5c6,e5e6,c6c5) | claimable-draw / threefold-repetition @3 | B009 | V |
| `mx-chs-011` | adopted limit: a king recapture illegal for a non-flying-general reason still counts as protection | `2k4/4R2/2c4/1N5/7/7/3K3 w - - 0 1` | M8(e6e5,c5c6,e5e6,c6c5) | claimable-draw / threefold-repetition @3 | B023, A §5.1 | V |
| `mx-chs-012` | a king protects only inside its own palace | `7/7/1ck4/7/7/7/R3K2 w - - 0 1` | M8(a1b1,b5a5,b1a1,a5b5) | black-wins / perpetual-chase @3 | A007 | V |
| `mx-chs-013` | a cannon protects only through exactly one screen | `4k2/7/c3c2/7/1R5/7/2K4 w - - 0 1` | M8(b3a3,a5b5,a3b3,b5a5) | black-wins / perpetual-chase @3 | A006 | V |

`mx-chs-006` … `mx-chs-011` are one differential chain on a single geometry: 006→007 adds the black
chariot g5; 006→008 adds the black soldier b6; 006→009 moves the black king d7→c7; 009→010 moves the
white king c1→d1; 010→011 adds the white horse b4. `mx-chs-013` is the differential partner of the
already-approved `mx-chs-002` (rook defender instead of screenless cannon). `mx-chs-012`'s positive
half is `mx-chs-010`; they are not a one-piece differential and the fixture rationale should say so.

### 5.2 Target, attacker and value classes (Q6) — `mx-chs-014` … `mx-chs-019`

| id | title | start FEN | moves | expected | from | status |
|---|---|---|---|---|---|---|
| `mx-chs-014` | a horse chasing a **protected chariot** is a chase | `3k3/7/3r2r/N6/7/7/4K2 w - - 0 1` | M8(a4c3,d5c5,c3a4,c5d5) | black-wins / perpetual-chase @3 | B011 (≈A011) | V |
| `mx-chs-015` | a horse chasing a **protected cannon** is not | `3k3/7/3c2r/N6/7/7/4K2 w - - 0 1` | M8(a4c3,d5c5,c3a4,c5d5) | claimable-draw / threefold-repetition @3 | B012 (≈A012) | V |
| `mx-chs-016` | chariot versus chariot is a mutual attack, not a chase | `3k3/7/3r3/R6/7/7/2K4 w - - 0 1` | M8(a4a5,d5d4,a5a4,d4d5) | claimable-draw / threefold-repetition @3 | B013 (≈A013) | V |
| `mx-chs-017` | …unless the same-type target is pinned | `3k3/7/3r3/R6/7/7/2KR3 w - - 0 1` | M8(a4a5,d5d4,a5a4,d4d5) | black-wins / perpetual-chase @3 | B014 | V |
| `mx-chs-018` | a soldier's move never chases | `4k2/7/7/c6/1P5/7/2K4 w - - 0 1` | M8(b3a3,a4b4,a3b3,b4a4) | claimable-draw / threefold-repetition @3 | B015 (≈A025) | V |
| `mx-chs-019` | a king's move never chases | `4k2/7/7/7/2c4/2K4/7 w - - 0 1` | M8(c2d2,c3d3,d2c2,d3c3) | claimable-draw / threefold-repetition @3 | B016 (≈A026) | V |

`mx-chs-018` and `mx-chs-019` are meaningful negatives: in both, the moving soldier/king genuinely
attacks the target square, so only the attacker-class rule produces the draw. `mx-chs-017` also
discharges A's "defender that is itself the chased piece's attacker" case, which A proposed to settle
by argument rather than fixture.

### 5.3 Persistence, interruption and the boundary (Q2, Q5) — `mx-chs-020` … `mx-chs-025`

| id | title | start FEN | moves | expected | from | status |
|---|---|---|---|---|---|---|
| `mx-chs-020` | one chasing move and one idle move per cycle is not perpetual | `3k3/7/c6/7/1R5/7/2K4 w - - 0 1` | M8(b3a3,a5a6,a3b3,a6a5) | claimable-draw / threefold-repetition @3 | A014 | V |
| `mx-chs-021` | an interruption inside the span makes the third occurrence neutral | `4k2/7/c6/7/1R5/7/2K4 w - - 0 1` | `c1c2 e7e6 c2c1 e6e7 b3a3 a5b5 a3b3 b5a5` | claimable-draw / threefold-repetition @3; boundary 4 | A016 | V |
| `mx-chs-022` | resuming re-arms: the violation attaches at the **fourth** occurrence | `4k2/7/c6/7/1R5/7/2K4 w - - 0 1` | `c1c2 e7e6 c2c1 e6e7` + M8(b3a3,a5b5,a3b3,b5a5) (12 plies) | black-wins / perpetual-chase @4; boundary 8 = "third occurrence, neutral claimable draw only" | A017 | V |
| `mx-chs-023` | cycle length is not part of the rule (six-ply cycle) | `3k3/7/c6/7/2R4/7/4K2 w - - 0 1` | `c3a3 a5b5 a3b3 b5c5 b3c3 c5a5` ×2 (12 plies) | black-wins / perpetual-chase @3; boundary 6 | A015 | V |
| `mx-chs-024` | chasing two different pieces alternately is a chase of neither | `3k3/7/c5c/7/R6/7/2K4 w - - 0 1` | M8(a3g3,d7d6,g3a3,d6d7) | claimable-draw / threefold-repetition @3 | A023 (≈B018) | V |
| `mx-chs-025` | the chasing piece may change while one target is tracked through its own moves | `R6/7/c3k2/7/1R5/7/3K3 w - - 0 1` | `b3a3 a5b5 a7b7 b5a5 b7a7 a5b5 a3b3 b5a5` ×2 (16 plies) | black-wins / perpetual-chase @3; boundary 8 | A024 | V |

`mx-chs-022` is the only fixture in the whole tranche whose `at_occurrence` is not 3, and it is the
one that pins "the three occurrences need not be the first three". Its `boundary` deserves the
explicit note that the prefix is already a *claimable draw* — not merely "not yet terminal".

### 5.4 Discovery and renewal (Q3) — `mx-chs-026`, `mx-chs-027`

| id | title | start FEN | moves | expected | from | status |
|---|---|---|---|---|---|---|
| `mx-chs-026` | pure discovered chase: every chasing move is a discovery and the target never moves | `4k2/7/R1Nc3/7/7/7/2KR3 w - - 0 1` | M8(c5d3,e7e6,d3c5,e6e7) | black-wins / perpetual-chase @3 | A018 (≈B017) | V |
| `mx-chs-027` | renewal from a new square: a chasing piece that steps away and still attacks the target renews the chase | `3k3/7/1r3N1/7/7/2K4/7 w - - 0 1` | M8(f5d6,b5d5,d6f5,d5b5) | red-wins / perpetual-chase @3 | B024 | V |

`mx-chs-026` uses A's version (target is a cannon) rather than B's (target is a horse) because A's
avoids any appearance of a same-type-exclusion interaction; the white horse never attacks d5 directly,
and the two white chariots alternate as the discovered attacker.

`mx-chs-027` is the single fixture whose result depends on the renewal interpretation adopted in Q3;
it is also the deletion control that proves the chase component of `mx-mix-004`. See the
product-owner decision in §7.

### 5.5 Patch-gating fixtures — `mx-chs-028` … `mx-chs-032`

| id | title | start FEN | moves | expected | engine now | patch | from | status |
|---|---|---|---|---|---|---|---|---|
| `mx-chs-028` | an absolutely pinned chariot's threat is not a chase | `3rk2/7/7/3R3/1c5/7/3K3 w - - 0 1` | M8(d4d3,b3b4,d3d4,b4b3) | claimable-draw / threefold-repetition @3 | `(True,-32000)` Red loses | pinned-attacker | A019 = B019 | V(div) |
| `mx-chs-029` | no flying-general pin exists when a piece of **either** colour blocks the file | `2k4/7/R6/2r4/7/2P4/2K4 w - - 0 1` | M8(a5a4,c4c5,a4a5,c5c4) | claimable-draw / threefold-repetition @3 | `(True,-32000)` Red loses | flying-general pin | B020, tightened here | V(div) |
| `mx-chs-030` | the chase test must not reach behind the first of the three occurrences | `4k2/7/c6/7/7/7/R1K4 w - - 0 1` | `a1a3` + `a5b5 a3b3 b5a5 b3a3` ×2 (9 plies) | black-wins / perpetual-chase @3; boundary 5 | `(True,0)` draw | chase window | B021 | V(div) |
| `mx-chs-031` | matched control: the same wheel entered by a chasing move | `4k2/7/c6/7/1R5/7/2K4 w - - 0 1` | `b3a3` + `a5b5 a3b3 b5a5 b3a3` ×2 (9 plies) | black-wins / perpetual-chase @3; boundary 5 | agrees | B022 | V |
| `mx-chs-032` | matched control at the other parity: identical start and entry move to `mx-chs-030` | `4k2/7/c6/7/7/7/R1K4 w - - 0 1` | `a1a3` + `a5b5 a3b3 b5a5 b3a3` ×2 + `a5b5` (10 plies) | black-wins / perpetual-chase @3 (occurrences at plies 2/6/10); boundary 6 | agrees | new in this pass | V |

`mx-chs-029` replaces B's original blocker (a white horse on c3, which also defends a4 and so leaves
the "draw" expectation arguable) with a white soldier on c2, which defends nothing. Both rooks are
undefended and the exclusion is unambiguous.

`mx-chs-030`, `mx-chs-031` and `mx-chs-032` must be reviewed as a trio: 030 and 031 have identical
wheels and differ only in the entry move; 030 and 032 have an identical start, an identical entry
move and identical judged moves, and differ only in the parity at which adjudication lands.

### 5.6 Mutual-chase attribution controls — `mx-chs-033`, `mx-chs-034`

| id | title | start FEN | moves | expected | from | status |
|---|---|---|---|---|---|---|
| `mx-chs-033` | the White half of the mutual chase alone | `2k4/7/1cN1R2/7/4n2/7/1R2K2 w - - 0 1` | M8(c5b3,e3f5,b3c5,f5e3) | black-wins / perpetual-chase @3 | A021 | V |
| `mx-chs-034` | the Black half of the mutual chase alone | `2k2r1/7/2N4/7/2r1nC1/7/4K2 w - - 0 1` | M8(c5b3,e3f5,b3c5,f5e3) | red-wins / perpetual-chase @3 | A022 | V |

### 5.7 Perpetual check — `mx-chk-003`, `mx-chk-004`

| id | title | start FEN | moves | in_check | expected | from | status |
|---|---|---|---|---|---|---|---|
| `mx-chk-003` | perpetual check by a cannon battery the checking move itself completes | `7/7/2k3C/3n3/4N2/7/3K3 w - - 0 1` | M8(e3d5,d4f5,d5e3,f5d4) | false | black-wins / perpetual-check @3 | B | V |
| `mx-chk-004` | perpetual **discovered** check | `3c3/7/2k4/3n3/4N2/7/3K3 w - - 0 1` | M8(e3d5,d4f5,d5e3,f5d4) | true | red-wins / perpetual-check @3 | B | V |

Both are new mechanisms not covered by the approved `mx-chk-001` / `mx-chk-002` rook wheel, and both
hold under the built-in variant as well as the AXF child.

### 5.8 Cross-class and both-sides outcomes — `mx-mix-001` … `mx-mix-004` (new area)

| id | title | start FEN | moves | in_check | expected | from | status |
|---|---|---|---|---|---|---|---|
| `mx-mix-001` | mutual perpetual check is a draw | `3c3/7/2k3C/3n3/4N2/7/3K3 w - - 0 1` | M8(e3d5,d4f5,d5e3,f5d4) | true | draw / mutual-perpetual-check @3 | B | V |
| `mx-mix-002` | mutual perpetual chase is a draw | `2k2r1/7/1cN1R2/7/2r1nC1/7/1R2K2 w - - 0 1` | M8(c5b3,e3f5,b3c5,f5e3) | false | draw / mutual-perpetual-chase @3 | A020 | V (value agrees; the reason is not reportable from the engine — §3.4) |
| `mx-mix-003` | a side alternating check and chase commits neither violation | `3k3/7/c6/R6/7/7/4K2 w - - 0 1` | M8(a4d4,d7c7,d4a4,c7d7) | false | claimable-draw / threefold-repetition @3 | A chk-003 (≈B mix-003) | V |
| `mx-mix-004` | perpetual check outranks a simultaneous perpetual chase by the checked side | `3k3/7/1r3N1/7/7/2K4/3C3 w - - 0 1` | M8(f5d6,b5d5,d6f5,d5b5) | false | black-wins / perpetual-check @3 | B | V |

`mx-chk-003`, `mx-chk-004` and `mx-mix-001` are the same six-piece skeleton with one cannon, the
other cannon, or both — reviewing them as a trio makes the mutual attribution checkable by hand.
`mx-mix-002` must be reviewed with `mx-chs-033` and `mx-chs-034`, and `mx-mix-004` with `mx-chs-027`,
for the same reason. A's mutual-chase construction is preferred over B's because A also proposed both
halves as fixtures rather than as probes.

`mx-mix-003` was verified to alternate as claimed: the check flags across the nine plies are
`f T f f f T f f f`, i.e. Red checks on one move of each cycle and chases on the other.

**Both fixtures the freeze draft deferred as non-constructible are now built.** `docs/xiangqi-rules.md`
line 102 ("Neither yielded a minimal construction on the 7-by-7 board, and the mixed case appears to
require a discovered-chase component that is outside this set's scope") is superseded and should be
struck when the tranche lands.

### 5.9 Totals

36 new fixtures: `mx-chs-005` … `mx-chs-034` (30), `mx-chk-003` … `mx-chk-004` (2),
`mx-mix-001` … `mx-mix-004` (4). Of these, 32 are validated with the current engine agreeing and 4
(`mx-chs-028` … `mx-chs-030`, plus `mx-mix-002`'s reason) encode the contract against the engine.

Suggested review batches: protection (005–013); classes and values (014–019); persistence and
boundary (020–025); discovery and renewal (026–027); patch-gating (028–032); mutual and mixed
(033–034, chk-003/004, mix-001–004).

---

## 6. What is not constructible, or not constructed

| item | status | evidence |
|---|---|---|
| Mutual perpetual check | **Constructible.** A's non-constructibility argument is refuted. | `mx-mix-001`, six pieces, verified in check at all nine plies |
| Check-over-chase precedence | **Constructible.** | `mx-mix-004`, five pieces, with `mx-chs-027` as the chase control |
| "A defender that is itself the chased piece's attacker with an illegal recapture" (A §5.1) | **Not needed.** A argued non-constructibility from a premise that is false — a sustained chase does not require the target to move (`mx-chs-026`) and a pinned piece can shuttle along its pin line (`mx-chs-028`). The rule is covered by `mx-chs-017`. | — |
| A witness for the discovered-check exemption gap (§3.5) | **Not constructed.** | see below |
| A witness for the fake-roots over-approximation (§3.7) | **Not constructed** by either design or by this pass. | — |

**Search bound for the discovered-check gap.** `discussion-drafts/r-p4b.py` samples random positions
in which the victim has only a king and one or two soldiers, enumerates four-ply cycles that restore
the position, doubles them to three occurrences, and reports a hit only when (a) no ply is a check,
which isolates the chase branch from perpetual check, and (b) the built-in variant — which has no
chasing rule — returns a draw while the AXF target variant returns a decisive value. Under those
conditions any hit is necessarily a soldier entering the chased set through the unmasked path.
An earlier run without the check filter produced five hits that were all perpetual **check**, not
chase, which is why the filter matters.

RESULT_PLACEHOLDER

---

## 7. Decisions that need the product owner

Everything not listed here is decided above. These five are genuinely two-sided and each changes
user-visible behaviour.

### D1 — Patch the chase-window parity defect (§3.3)?

**Recommendation: yes, patch.** The other two confirmed defects produce false losses and the product's
own stance settles them. This one produces a *missed* violation, which is the benign direction, so a
reasonable person could defer it. The reason not to: the defect makes the same four moves a violation
for one colour and not for the other, and in a two-player game an asymmetry that depends on nothing
but adjudication parity cannot be explained to a user. It also has a non-benign corner, converting a
`mutual-perpetual-chase` draw into a unilateral loss for the wrong side. The change is local to the
repetition loop.

### D2 — How should `mutual-perpetual-chase` be reported (§3.4)?

**Recommendation: take the read-only engine accessor.** Options:

1. Expose the branch that fired alongside the value (or expose `st->chased`). Changes no adjudication
   at all — the cheapest possible fork divergence, and it lets the facade emit the reserved reason.
2. Amend the contract to claim-gate mutual perpetual chases as ordinary threefold repetitions and
   retire the `mutual-perpetual-chase` reason. Textually defensible against the source's "can be ruled
   as a draw", but it contradicts the accepted line that only neutral repetition is claim-gated, and
   it makes an archived game lose information.
3. Ship the ambiguity. Not viable: the fixture `mx-mix-002` cannot be satisfied.

Option 1 preserves the accepted contract exactly. Note that `mutual-perpetual-check` needs no engine
help — the facade can derive it from check state — so this decision is about one outcome only.

### D3 — Adopt the engine's renewal test (§3.5 of design B, Q3 here)?

**Recommendation: adopt the engine's test** — "the chasing piece attacks the target from the square it
now occupies, and did not attack it from that square before the move". The alternative, "the threat
did not exist anywhere before", would make a chaser who steps sideways while keeping an undefended
piece under attack innocent, which reads worse to a player than the engine's answer, and it would
require a patch. The retained source does not settle it. This decides `mx-chs-027` and nothing else in
the slate; `mx-mix-004`'s *result* is unchanged either way, because check outranks chase.

### D4 — One check, one chase (一将一捉) (§Q4)?

**Recommendation: adopt the permissive reading** — a side alternating check and chase commits neither
violation, pinned by `mx-mix-003`. Both designs reached this independently and both flagged it as the
recommendation most likely to be wrong: full AXF/CXA competition practice is commonly summarised as
forbidding that alternation. The retained public source enumerates exactly two violation classes and
defines each as a persistent single behaviour, the engine agrees, and the fallback is a claimable draw
rather than a wrong terminal result. Record it in the contract as an explicit interpretation, with the
note that an authoritative AXF or CXA text on 长将兼长捉 would reopen it as a contract amendment
rather than a discovery.

### D5 — Patch the king-as-sole-root recapture test (§3.6)?

**Recommendation: no — adopt, document, and pin with `mx-chs-011`.** The engine models only the
flying-general reason a king cannot recapture, so a chase whose target's only defender is a king that
is in truth unable to recapture degrades to a claimable draw. Strictly this diverges from the source's
"unprotected". It is under-detection only, it is one of the maintainer's acknowledged
approximations, and the contract can state the limit precisely. Patching it is cheap in code (one
extra `attackers_to` in a branch that is rarely taken) but it is a fourth divergence to carry, and it
buys a stricter loss where today the user gets a declinable draw.

### D6 — Patch the discovered-check exemption gap (§3.5)?

**Recommendation: yes, one line, low priority** — `discoveryAttacks &= ~chaseExempt;` before both uses
at `position.cpp:3083` and `:3085`. This is not a new patch so much as the completion of the one
already merged: the accepted contract line "kings and soldiers are excluded as perpetual-chase
targets" is not open for redesign, and today it is enforced in two of the three classifier paths. The
marginal maintenance cost inside a function the fork already patches is close to zero. Against
patching: no witness has been constructed, so the gap may be unreachable, and an unreachable patch is
pure cost. RESULT_D6_PLACEHOLDER

---

## 8. Consolidated fork patch list

| # | patch | source location | why | severity | status |
|---|---|---|---|---|---|
| P0 | `promotedSoldiersChaseable`, set `false` in the app variant | `position.cpp:2988-2990` | soldiers are not chase targets | — | **landed** (`77d602e0`); verified: all sixteen approved fixtures pass |
| P1 | pinned chaser's attacks restricted to its pin line | `position.cpp:3032-3054` | removes a false terminal loss on an unexecutable threat | wrong result | confirmed, `mx-chs-028` |
| P2 | flying-general pin must consider pieces of **both** colours between the kings | `position.cpp:2981-2983` | removes a false terminal loss on a pin that does not exist | wrong result | confirmed, `mx-chs-029` |
| P3 | `chaseThem` must span only the moves strictly inside the three-occurrence window | `position.cpp:2694-2695`, `:2716` | removes a parity-dependent missed violation | wrong result | confirmed, `mx-chs-030` / `mx-chs-031` / `mx-chs-032` |
| P4 | expose the branch that fired (or `st->chased`) alongside the optional-end value | `position.cpp:2704-2707` | makes `mutual-perpetual-chase` reportable; changes no adjudication | unreportable outcome | confirmed, `mx-mix-002` |
| P5 | apply `chaseExempt` in the discovered-check path | `position.cpp:3081-3091` | completes the soldier/king exemption | wrong result if reachable | code gap confirmed; reachability open |
| — | king-as-sole-root recapture legality beyond the flying general | `position.cpp:3022` | would convert an under-detected chase into a loss | under-detection | **recommended not to patch**; adopt and pin with `mx-chs-011` |
| — | fake-roots over-approximation | `position.cpp:3056-3074` | over-detects when the target has a second defender | unknown | **recommended not to patch**; document the limitation |

P1–P3 are all local to the chase path; none changes history semantics. P4 touches no adjudication.

---

## 9. Reproduction

```
cd /Users/tianren/coding/minixiangqi/discussion-drafts
# build (about four minutes) — the fork checkout itself is untouched
mkdir -p r-scratch && cp -R ../Fairy-Stockfish/src r-scratch/ && cd r-scratch && rm -f src/*.o
SRCS=( src/*.cpp src/syzygy/*.cpp src/nnue/*.cpp src/nnue/features/*.cpp ); SRCS=( ${SRCS:#*ffishjs*} )
g++ -std=c++17 -O2 -DNDEBUG -bundle -undefined dynamic_lookup -fPIC \
  -I/opt/homebrew/opt/python@3.14/Frameworks/Python.framework/Versions/3.14/include/python3.14 \
  -DLARGEBOARDS -DALLVARS -DPRECOMPUTED_MAGICS -DNNUE_EMBEDDING_OFF -DIS_64BIT -DUSE_POPCNT \
  $SRCS -o pyffish.cpython-314-darwin.so
cd ..
python3 r-approved.py      # the sixteen approved fixtures against the target variant
python3 r-claims.py        # every claimed defect
python3 r-claims2.py       # parity differential, tightened P2 repro, per-ply check states
python3 r-allfix.py        # all 49 fixtures proposed by A and B
python3 r-p4b.py 40000     # reachability search for the discovered-check gap (long)
```

`r-harness.py` (and its importable copy `r_harness.py`) registers the target variant with
`promotedSoldiersChaseable = false`. `-DNDEBUG` is required. `is_optional_game_end` returns a
side-to-move-relative value and its value element is uninitialised when the flag is false.
