# Perpetual-check and perpetual-chase edge cases — normative-first design (Agent A)

## Scope, method, and evidence base

This draft resolves the six deferred edge-case questions named in `MiniXiangqi/docs/xiangqi-rules.md`
**Need to discuss**: protection, interruption, discovered and pinned attacks, mutual and mixed
sequences, the terminal boundary, and target/attacker classes. It proposes contract wording and a
fixture tranche continuing the accepted series. Nothing here changes a repository.

Method, in this order, deliberately:

1. The rules were derived from the selected public source (the PyChess Mini Xiangqi page, five
   perpetual bullets) and from the purpose the Asian Xiangqi Federation tradition gives those rules,
   **before** `Position::chased()` was read. §2 records that derivation as written.
2. Fairy-Stockfish's AXF implementation was then read (§3) and probed empirically (§4).
3. Each question is then answered with an adopted rule, its justification, what AXF actually does,
   and an ADOPT-ENGINE / PATCH-REQUIRED / CONTRACT-ONLY classification (§5).

Where the derivation and the engine disagreed, §5 says which won and why. Two derivations in §2 were
wrong and the engine was right; they are flagged rather than quietly corrected.

Evidence base (same revisions as the freeze draft):

- **FS** — `Fairy-Stockfish` at `c19b5f6c66894fdb0e88d0dd100e3885f744760a` (read-only).
- **PC** — `pychess-variants` at `961fd6dd60ce76d3baced1a77df49ca58edcb315` (read-only).
- Rules snapshot: `discussion-drafts/evidence/pychess-minixiangqi-rules-2026-07-26.html`
  (SHA-256 `a79b6636…`), whose perpetual section is byte-equal in content to
  `pychess-variants/static/docs/minixiangqi.md:20-26`.
- Runtime: the prebuilt `pyffish` 0.0.89 at `discussion-drafts/evidence/pyffish-build/`
  (`Fairy-Stockfish 260726 LB`), driven by the scratch child
  `[minixiangqiaxf:minixiangqi] chasingRule = axf, nMoveRule = 0`
  (`discussion-drafts/fixtures-draft/minixiangqiaxf-validation.ini`, unmodified).
- Scratch harness written for this pass: `discussion-drafts/a-probe.py`, `a-drive.py`,
  `a-drive2.py`, `a-search.py`, `a-c*.py`. `a-drive2.py` additionally registers a research-only
  discriminator child `minixiangqiaxfnochk` (`perpetualCheckIllegal = false`) used solely to
  separate a check verdict from a chase verdict. It is not a proposed app variant.

Normative stance is unchanged: fixture expectations come from the contract and the public source.
Engine returns are observations. Where this draft recommends adopting engine behaviour it is because
the behaviour is argued to be correct against the source, not because the engine produces it.

---

## 1. Proven source facts — the normative text

**Proven source facts** (`pychess-variants/static/docs/minixiangqi.md:20-26`, identical in the
retained HTML snapshot, section "Additional Rules - Perpetual checks and chases"):

1. "A player making perpetual checks with one piece or several pieces can be ruled to have lost
   unless he or she stops such checking."
2. "The side that perpetually chases any one unprotected piece with one or more pieces, excluding
   generals and soldiers, will be ruled to have lost unless he or she stops such chasing."
3. "If one side perpetually checks and the other side perpetually chases, the checking side has to
   stop or be ruled to have lost."
4. "When neither side violates the rules and both persist in not making an alternate move, the game
   can be ruled as a draw."
5. "When both sides violate the same rule at the same time and both persist in not making an
   alternate move, the game can be ruled as a draw."

- The same five bullets are the full-size Xiangqi text (`pychess-variants/static/docs/xiangqi.md:86-92`);
  the same guide names AXF as the Asian Xiangqi Federation (`xiangqi.md:22-24`) and gives consensus
  piece values R 9, C 4.5, H 4, P 1–2 (`xiangqi.md:160-170`).
- The source says nothing about pins, discovery, X-rays, interruption patterns, or how long a
  violation must persist. Every answer below is an interpretation, and each is labelled as such.

**Inference — the four textual hooks that do the work.**

- *"with one piece or several pieces" / "with one or more pieces"*: the **attacking piece may
  change** during a violation. Identity of the attacker is explicitly not part of the rule.
- *"any one unprotected piece"*: the **target is one specific piece**, singular and the same one.
  Alternating between two victims is not this rule.
- *"unless he or she stops"*: the rule is an **obligation to vary**, discharged by a single
  non-violating move. The burden is on the aggressor and nowhere else.
- *"excluding generals and soldiers"*: the phrase sits between "any one unprotected piece" and
  "with one or more pieces". English attachment is genuinely ambiguous and, read as low attachment,
  it modifies **the chasing pieces**, not the target. The accepted contract already reads it as a
  target exclusion. The reading adopted here is that it removes those two piece types **from the
  rule in both roles**, which is the only reading that makes both the accepted contract line and the
  sentence's word order true at once, and which matches AXF practice that a general or a soldier
  neither chases nor is chased.

---

## 2. Derivation from the source, written before reading `chased()`

The purpose of both rules is the same: a player may not extract a result — win by attrition or force
a draw — from an endlessly repeated forcing sequence in which the opponent never gets a free move.
Every rule below is therefore stated so that it can be decided by a deterministic procedure over the
move history, because a rule the facade cannot evaluate is not a rule.

**D1 Protection.** A chase is a *threat to win material*. A defender neutralises the threat only if,
after the chaser actually captures the target, that defender can *legally recapture on the target's
square*. Therefore a defender does not count when: it is absolutely pinned; its recapture would
expose its own king, including by flying general; or its recapture is otherwise illegal. A king
counts as a defender exactly when the king's capture on that square would be legal. A cannon defends
only through exactly one screen, so a cannon does not defend the piece adjacent to it. Because the
test is applied *after* the capture, the chaser's vacated origin square must be treated as empty.
Additionally, protection does not save a target that is worth more than the chaser: capturing a
defended rook with a horse still wins material, so it is still a chase. Conversely, when the target
attacks the chaser back on equal terms, the position offers an exchange rather than a threat and is
not a chase.

**D2 Interruption.** "Unless he or she stops" means one non-violating move discharges the
obligation. Adjudication is over the *repetition span*: the plies from the first occurrence of the
repeated position to its third. A side commits perpetual check over that span iff **every** move it
made in the span gave check; it commits perpetual chase iff **every** move it made in the span left
one and the same enemy piece chased. Anything else — an idle move, a move that attacks a different
piece, a move that lets the threat lapse — breaks the violation and the repetition is neutral. A
check by the *other* side does not excuse the aggressor: only the aggressor's own moves are counted.

**D3 Discovered and pinned attacks.** A chase is defined by the state the move produces, not by which
piece moved; a discovered attack forces the opponent exactly as a direct one does, so it counts. An
attack by an absolutely pinned piece is not a threat at all — the capture is illegal — so it does not
count. Check is a property of the position, so a discovered check is a check for every purpose,
including precedence.

**D4 Mutual and mixed.** The two classes are *perpetual check* and *perpetual chase*. "The same rule"
in bullet 5 means the same class. Both check → draw; both chase → draw. Bullet 3 makes check the
graver violation: check beats chase, and the checking side loses. A side whose moves are neither all
checks nor all chases of one piece has committed neither violation, so it is not liable; under the
source's text a "one check, one chase" alternation is not a violation, although full AXF practice
forbids it (§6.1).

**D5 Terminal boundary.** What must persist across the three occurrences is: the same violating
side; the same class; and, for chase, the same *target piece* — followed through its own moves, not
its square. The attacking piece and the attacking square need not persist.

**D6 Target and attacker classes.** Kings and soldiers are outside the chase rule in both roles.
Attacking a piece of strictly greater value is a chase whether or not the target is protected;
attacking a piece of like value that attacks back is an exchange offer, not a chase.

*Two predictions made here turned out to be wrong about the engine and are corrected in §5.1: the
engine's king-as-defender test is palace-aware and flying-general-aware already.*

---

## 3. Proven source facts — what AXF actually does in Fairy-Stockfish

`Position::chased()` (`Fairy-Stockfish/src/position.cpp:2973-3090`) is evaluated after every move and
cached per state (`position.cpp:598`). It returns a bitboard of the squares of `sideToMove` (the side
that just *received* the move) that the mover chased.

- **Pins used by the classifier.** `pins = blockers_for_king(sideToMove)` (`position.cpp:2978`), plus
  a flying-general pin: the victim's single non-king piece standing on the file of the chaser's king
  together with its own king is marked pinned (`position.cpp:2979-2984`).
- **Target exclusion.** `attacks &= ~(pieces(sideToMove, KING, SOLDIER) ^ promoted_soldiers(sideToMove))`
  (`position.cpp:2989`). With `soldierPromotionRank = 1` (`variant.h:118`) every Mini Xiangqi soldier
  is "promoted", so only kings are excluded — the already-confirmed patch #1.
- **Value rule.** `if (attackerType == HORSE || attackerType == CANNON) b |= attacks & pieces(sideToMove, ROOK)`
  (`position.cpp:2991-2992`): a horse or cannon attacking a rook is chased *unconditionally*, before
  the symmetry and protection tests. (`ELEPHANT`/`FERS` cases at 2993-2994 are dead in this variant.)
- **Symmetric-attack exclusion.** `attacks &= ~pieces(sideToMove, attackerType) | pins`
  (`position.cpp:3010`): attacks on an enemy piece of the *same type* are dropped unless that piece
  is pinned. A blocked-horse special case keeps genuinely one-sided horse attacks
  (`position.cpp:2999-3008`).
- **Protection test.** `roots = attackers_to(s, pieces() ^ attackerSq, sideToMove) & ~pins`
  (`position.cpp:3015`); the square is chased when `!roots`, or when the only root is the king and
  that king's recapture would face the enemy king (`position.cpp:3016`). The occupancy passed in
  removes the *attacker* from the board, so cannon screens and rook lines are evaluated as they will
  stand after the capture.
- **Palace awareness.** `attackers_to` gates every piece type by its mobility region —
  `if (board_bb(c, pt) & s)` (`position.cpp:963`), where `board_bb(c, pt)` applies
  `var->mobilityRegion` (`position.h:430-433`), i.e. the palace for kings (`variant.cpp:1237-1238`).
  A king therefore does not count as a root for a square outside its own palace. Confirmed
  empirically by the mx-chs-007 / mx-chs-008 differential (§4).
- **Attacker exclusion.** Direct attacks are skipped entirely when the moved piece is a king or a
  soldier: `if (movedPiece != KING && movedPiece != SOLDIER)` (`position.cpp:3026`). Kings and
  soldiers can still *discover* a chase for another piece, because the discovery loop is not gated on
  the moved piece type.
- **Novelty filter.** For a rook or cannon mover, attacks along the move's own line are discarded as
  pre-existing: `directAttacks &= ~line_bb(from, to)` (`position.cpp:3030-3031`). Discovered attacks
  are explicitly differenced against the pre-move occupancy (`position.cpp:3044-3046`). A chase is
  therefore only registered when the move *creates* the threat.
- **Discovered attacks** are first-class (`position.cpp:3036-3048`), including attacks created by
  moving a piece *onto* a square to become a cannon screen (`position.cpp:3039`).
- **Two extra chase sources**: newly pinning a defender turns the pieces it defended into chased
  pieces (`position.cpp:3054-3068`), and creating a discovered-check battery makes the pieces that
  battery attacks chased (`position.cpp:3070-3086`).
- **No attacker-legality test.** Nothing in the direct or discovered path checks whether the chasing
  piece could legally make the capture; `blockers_for_king(~sideToMove)` is consulted only in the
  fake-roots branch (`position.cpp:3065`).

Repetition adjudication (`position.cpp:2648-2718`):

- The walk starts at the current position and steps back two plies at a time until the current key is
  met for the second time going backwards, i.e. the **third total occurrence** (`position.cpp:2701-2702`).
- `perpetualThem` / `perpetualUs` are ANDed over every position in that span
  (`position.cpp:2657-2658, 2697, 2715`): perpetual check requires a check after *every* move of the
  side in the whole span.
- `chaseThem` / `chaseUs` are **intersected** over the span, and each intersection step first maps the
  bitboard back through the victim's own move — `undo_move_board(b, m)` replaces `to_sq(m)` by
  `from_sq(m)` (`bitboard.h:200-202`), used at `position.cpp:2659-2660, 2695, 2716`. The intersection
  therefore tracks *one and the same piece* through its flight, and is non-empty only if some single
  piece was chased after every move of that side in the whole span.
- Result order: perpetual check first, then chase, then the plain n-fold value; a mutual violation of
  either class yields `VALUE_DRAW` (`position.cpp:2704-2707`).

---

## 4. Empirical observations

All runs use the AXF child; values are from the side to move at the final ply
(`-32000` = the side to move loses, `+32000` = the side to move wins, `0` = draw). Every scripted
move was verified legal at its turn and every boundary prefix one cycle earlier was verified not yet
ended. Scripts: `a-c2.py`, `a-c3.py`, `a-c4.py`, `a-c8.py`, `a-c11.py`, `a-c12.py`, `a-c14.py`.

| probe | position / shape | engine |
|---|---|---|
| pinned defender | `4k2/7/c3r2/7/1R5/7/2K1R2` | violation |
| control (mx-chs-002, unpinned defender) | `4k2/7/c3r2/7/1R5/7/2K4` | draw |
| cannon "defender" with no screen | `4k2/7/c3c2/7/1R5/7/2K4` | violation |
| king defender, recapture square outside palace | `7/7/1ck4/7/7/7/R3K2` | violation |
| king defender, recapture square inside palace | `7/3k3/3c3/6R/7/7/2K4` | draw |
| king defender, recapture blocked by flying general | `4R2/7/2kc3/7/7/7/3K3` | violation |
| same, White king off the file | `4R2/7/2kc3/7/7/7/4K2` | draw |
| king defender, recapture square covered by a second attacker | `7/3k3/3c3/6R/4N2/7/2K4` | **draw** (under-detection) |
| horse chases *protected* rook | `4k2/3N3/r3r2/7/7/7/3K3` | violation |
| horse chases *protected* cannon | `4k2/3N3/c3r2/7/7/7/3K3` | draw |
| rook chases rook (mutual attack) | `4k2/7/r6/7/1R5/7/2K4` | draw |
| soldier as chaser | `4k2/7/1c5/2P4/7/7/3K3` | draw |
| king as chaser | `4k2/7/7/7/2c4/3K3/7` | draw |
| one chase, one idle in the cycle | `3k3/7/c6/7/1R5/7/2K4` | draw |
| six-ply cycle, all three moves chase | `3k3/7/c6/7/2R4/7/4K2` | violation |
| same six-ply cycle, one move blocked | `3k3/7/c6/2P4/2R4/7/4K2` | draw |
| idle cycle **then** chase cycle (3rd occurrence) | chs-001 start | draw |
| chase cycle **then** idle cycle (3rd occurrence) | chs-001 start | draw |
| idle cycle then two chase cycles (4th occurrence) | chs-001 start | violation |
| alternating targets (two cannons) | `3k3/7/c5c/7/R6/7/2K4` | draw |
| alternating attackers, one target | `R6/7/c3k2/7/1R5/7/3K3` | violation |
| one check, one chase by the same side | `3k3/7/c6/R6/7/7/4K2` | draw |
| pure discovered chase (both mover's moves) | `4k2/7/R1Nc3/7/7/7/2KR3` | violation |
| chase by an absolutely pinned rook | `3rk2/7/7/3R3/1c5/7/3K3` | **violation** (over-detection) |
| mutual perpetual chase | `2k2r1/7/1cN1R2/7/2r1nC1/7/1R2K2` | draw |
| — its White half alone | `2k4/7/1cN1R2/7/4n2/7/1R2K2` | Red loses |
| — its Black half alone | `2k2r1/7/2N4/7/2r1nC1/7/4K2` | Black loses |

Two negative searches (`a-c7.py`, `a-c13.py`), random positions with 2–4 non-king pieces per side,
DFS over 4-ply cycles in which every move of both sides gives check: **42,073 in-check candidate
positions, zero cycles found.** A third search (`a-c10.py`), 1,301 candidate positions for a 4-ply
cycle in which every White move checks and every Black move is a chase, also found none; that search
could not reach the material level such a construction needs (see §6.2).

---

## 5. The six questions

### 5.1 Protection — ADOPT-ENGINE (one narrow under-detection accepted or optionally patched)

**Adopted rule (liftable prose).**

> A chased piece is **protected** when, in the position that would arise if the chasing piece
> captured it, some piece of its own side could legally capture on that square. The test is applied
> to the position after the capture: the chasing piece's origin square is empty, so lines opened and
> cannon screens removed by the capture are taken into account. In particular:
> a defender that is pinned against its own king, or whose recapture would expose its own king or
> place the two kings on an otherwise empty file, does not protect; a king protects a square only
> when that square is inside its own palace and its capture there would be legal; a cannon protects a
> square only through exactly one screen, and therefore never protects the piece next to it.
> Protection does not exempt a target that is stronger than the piece attacking it: a horse or a
> cannon attacking a chariot chases it whether or not it is protected, because the capture wins
> material even after recapture. Conversely, an attack on an enemy piece of the same kind that
> attacks the attacker in return offers an exchange and is not a chase, unless that piece is pinned
> and so could not take part in the exchange.

**Justification.** The source word is "unprotected", and a defender that cannot legally recapture
protects nothing — this is the classical *false root* concept of the AXF tradition. The value clause
follows from the rule's purpose: bullet 2 exists to stop a player forcing an opponent to keep running
from a losing material threat, and a horse attacking a defended chariot is exactly that threat
(values `xiangqi.md:160-170`). The exchange clause follows for the mirror reason: when the target can
capture the attacker on equal terms, the opponent has a way out that costs nothing and no one is
being ground down.

**What AXF does.** Exactly this, with one gap. Pins, flying-general pins, palace confinement, cannon
screens, the post-capture occupancy, the value rule and the same-type exchange exclusion are all
implemented (`position.cpp:2989-3018`, `position.cpp:963`), and all were confirmed empirically (§4).
The gap: the king-as-sole-root exception at `position.cpp:3016` tests only the flying-general reason
for an illegal king recapture. When the target square is also attacked by a *second* enemy piece, the
king cannot legally recapture there either, but the engine still treats it as protected and rules the
repetition neutral (probe row 8 of §4).

**Classification: ADOPT-ENGINE.** The gap is an *under*-detection: a real violation degrades to a
claimable draw, never to a wrong loss, and it needs the chasing side to have a second piece covering
the flight square while the victim's king is the only defender. That is a defensible place to accept
the maintainer's acknowledged incompleteness. If the product wants it closed, the minimal patch
semantics are: *at `position.cpp:3016`, treat a king-only root as no root whenever the king's capture
on that square would be illegal — extend the existing flying-general test to "the square is attacked
by any enemy piece other than the chaser, with the chaser removed from the occupancy".* Recorded as
**PATCH-OPTIONAL, low priority**; it is not required for the fixtures proposed here.

**Fixtures.** `mx-chs-005`, `mx-chs-006`, `mx-chs-007`, `mx-chs-008`, `mx-chs-009`, `mx-chs-010`,
`mx-chs-011`, `mx-chs-012`, `mx-chs-013` (§7).

**Not constructible, with reasoning.** "A defender that is itself the chased piece's attacker with an
illegal recapture" cannot be built as a perpetual: for the recapture to be illegal the target must be
pinned, and a pinned piece can only move along its pin line, so it cannot flee and return through the
two squares a chase shuttle needs while remaining pinned. The engine's `| pins` clause at
`position.cpp:3010` covers the rule anyway; the case is pinned by argument, not by fixture.

### 5.2 Interruption — ADOPT-ENGINE

**Adopted rule (liftable prose).**

> A perpetual violation is judged over the **repetition span**: the plies from the first occurrence of
> the repeated position to its third occurrence. Within that span, a side commits perpetual check
> only if every one of its own moves in the span gave check, and perpetual chase only if after every
> one of its own moves in the span one and the same enemy piece stood chased. One move by that side
> that does not renew its own violation — an idle move, a move that threatens a different piece, or a
> move after which the threat lapses — ends the violation, and the repetition is then neutral and
> merely claimable. Interruptions by the other side are irrelevant: a check or a threat by the
> opponent neither creates nor excuses a violation. A side that interrupts its own sequence and then
> resumes it is liable again as soon as three occurrences of a position are spanned entirely by
> violating moves.

**Justification.** Bullet 2's "unless he or she stops such chasing" makes a single alternate move a
complete discharge, and bullets 4 and 5 make "both persist in not making an alternate move" the
condition for the draw. The span formulation is the only reading that is simultaneously deterministic
over history, symmetric between the two sides, and consistent with the accepted three-occurrence
adjudication point. It also reproduces the AXF convention that *one chase, one idle* is permitted.

**What AXF does.** Exactly this: the AND for check and the intersection for chase run over the whole
walk back to the third-most-recent occurrence (`position.cpp:2657-2660, 2695-2697, 2715-2716`), so a
single non-violating move anywhere in the span clears the flag. Confirmed in both orders (idle-then-
chase and chase-then-idle both give a neutral draw) and confirmed that the violation reappears at the
fourth occurrence once the span is clean again (§4).

**Classification: ADOPT-ENGINE.** The rule is also independently checkable app-side for check.

**Fixtures.** `mx-chs-014`, `mx-chs-015`, `mx-chs-016`, `mx-chs-017` (§7).

### 5.3 Discovered and pinned attacks — split: ADOPT-ENGINE / PATCH-REQUIRED / CONTRACT-ONLY

**Adopted rule (liftable prose).**

> A chase is judged by what the move produces, not by which piece moved. A move that uncovers another
> piece's attack on an enemy piece, or that creates the screen a cannon needs, chases that piece
> exactly as a direct attack does. Only a threat that the move newly creates counts: renewing an
> attack that already existed before the move is not a chase, so approaching a target along a line on
> which the attack already stood is not a chase.
> An attack by a piece that could not legally make the capture — because moving it would expose its
> own king or bring the two kings face to face — is not a threat and is not a chase.
> For the precedence of check over chase, a check is a check however it is delivered; a discovered
> check counts in full.

**Justification.** The forcing effect on the opponent is identical for direct and discovered attacks,
and "with one piece or several pieces" already tells us the rule cares about the resulting threat and
not about the mover. The novelty requirement follows from the same place: if the threat already
existed, the move did not chase anything, and the opponent's obligation to react did not come from
that move. The pinned-attacker clause follows from the rule being about a *threat*: a piece that
cannot legally capture threatens nothing, and ruling a loss against a player whose piece could never
have executed the capture would be plainly wrong to any player.

**What AXF does.**

- Discovered chases: implemented and first-class, including screen-creating moves
  (`position.cpp:3036-3048`), with the novelty difference against the pre-move occupancy
  (`position.cpp:3046`) and the same-line filter for direct rook/cannon moves
  (`position.cpp:3030-3031`). A pure discovered-chase perpetual — every move of the chasing side is a
  discovery, no direct attacks at all — is constructible and the engine rules it a violation (§4;
  fixture `mx-chs-018`). **ADOPT-ENGINE.**
- Discovered check: check state is a property of the position, so this is satisfied by construction
  and needs no engine behaviour at all. **CONTRACT-ONLY.**
- Pinned attacker: **the engine counts it.** `addChased` never tests whether the attacker could
  legally capture; the chaser's own `blockers_for_king` is used only in the fake-roots branch
  (`position.cpp:3065`). Probe `mx-chs-019`: an absolutely pinned White rook shuttling along its pin
  line "attacks" a black cannon that shuttles in front of it, and the engine rules Red lost, although
  that rook could never capture anything. **PATCH-REQUIRED.**

**Minimal patch semantics (pinned attacker).** In `Position::chased()`, when the attacking square is
in `blockers_for_king(~sideToMove)`, keep only those attacks whose target square lies on the ray
between the chaser's own king and the pinner — that is, only captures that would still block the
check. Applies to both the direct and the discovered path, and reuses state the engine already
computes. No configuration can express this.

**Risk if deferred.** The violation only lands if the chasing side chooses to move its pinned piece
on *every* move of a whole three-occurrence span, so an engine opponent will never walk into it and a
human rarely will. But the outcome when it does land is a **wrong loss**, which is the failure mode
this project has said it will not ship. Recommended as the second-priority fork patch after the
soldier exclusion; the product may defer it with the risk recorded.

**Fixtures.** `mx-chs-018` (discovered chase, engine agrees), `mx-chs-019` (pinned attacker, engine
diverges — the fixture asserts the normative draw and will fail until the patch lands, exactly as
`mx-chs-003` does for soldiers).

### 5.4 Mutual and mixed sequences — CONTRACT-ONLY definition, ADOPT-ENGINE precedence, one reporting gap

**Adopted rule (liftable prose).**

> There are exactly two classes of perpetual violation: perpetual check and perpetual chase. Two
> sides commit the **same class** when, over the same repetition span, each of them independently
> satisfies the test for that class; the targets and the pieces involved need not correspond in any
> way. When both sides commit perpetual check, or both commit perpetual chase, the game is a draw.
> When one side perpetually checks and the other perpetually chases, the checking side is the side
> required to vary and loses. Perpetual check therefore outranks perpetual chase in every mixed
> combination, including when the checking side is also chasing. A side whose moves in the span are
> not all checks, and are not all chases of one and the same piece, has committed no violation, even
> if every one of its moves was forcing in some way; a sequence alternating check and chase is
> therefore not a violation under this contract.

**Justification.** Bullets 3 and 5 give precedence and the mutual draw directly. "The same rule"
maps onto "the same class" because those are the only two rules stated. The alternation ruling is the
literal reading of bullets 1 and 2, which require the checking or chasing to be what the player is
persistently doing.

**What AXF does.** The result expression evaluates perpetual check before chase and returns
`VALUE_DRAW` when both sides carry the same flag (`position.cpp:2704-2707`) — precedence and the
mutual draw are structural, not incidental. The alternating check/chase case is a draw in the engine
too (fixture `mx-chk-003`, verified check-per-ply as `T F F F T F F F`), because `perpetualUs` fails
the AND on the chasing ply and the chase intersection is empty on the checking ply. **ADOPT-ENGINE
for precedence and for the alternation ruling; CONTRACT-ONLY for the definition of "same class".**

**One real reporting gap.** `is_optional_game_end` returns `(True, 0)` for a *neutral* threefold and
for a *mutual* violation alike. The accepted contract makes those two outcomes different — a neutral
third occurrence is claim-gated, a mutual violation is a draw with its own reason identifier — so the
value alone cannot drive the facade. Three ways out, in order of preference:

1. **Mutual perpetual check: CONTRACT-ONLY.** The facade already has check state for every ply of the
   history, so it can decide "every move by each side in the span gave check" itself, with no engine
   help. Adopt this.
2. **Mutual perpetual chase: PATCH-REQUIRED (small, read-only).** The facade cannot re-derive the
   chase classification without duplicating `chased()`. The minimal patch is to expose the branch
   that fired alongside the value (or to expose `st->chased`), changing no adjudication. This is a
   read-only accessor, the cheapest possible kind of divergence.
3. If the product prefers zero further patches, treat a mutual perpetual chase as a claimable
   threefold repetition. This is textually defensible — bullets 4 and 5 use the *identical* modality,
   "the game **can be ruled** as a draw", for the neutral case and the mutual case, and reserve
   "**will be ruled** to have lost" for unilateral violations — but it contradicts the accepted
   contract line that only neutral repetition is claim-gated, so it needs an explicit contract change
   rather than a silent one.

**Fixtures.** `mx-chs-020` (mutual perpetual chase → draw) with its two differential halves
`mx-chs-021` and `mx-chs-022`, which together prove that both chases are individually detected and
that the mutual branch is what turns the pair into a draw; and `mx-chk-003` for the alternation
ruling. **This closes one of the two fixtures the
freeze draft deferred as non-constructible.** Mutual perpetual *check* and the mixed check/chase
fixture remain unbuilt; see §6.2 and §6.3.

### 5.5 The terminal boundary — ADOPT-ENGINE

**Adopted rule (liftable prose).**

> A violation is sustained across the three occurrences when, for the whole span, the violating side
> is the same, the class is the same, and — for a chase — the target is the same *piece*, followed
> through its own moves rather than by the square it stands on. The attacking piece may change from
> move to move, and the squares of attacker and target may change every move. Chasing two different
> pieces alternately is not a perpetual chase of either, and is a neutral repetition.

**Justification.** "Any one unprotected piece" fixes the target and only the target; "with one piece
or several pieces" explicitly frees the attacker. Identifying the target by piece rather than by
square is forced by the ordinary case, in which the chased piece is fleeing — `mx-chs-001` would
otherwise not be a violation at all.

**What AXF does.** Precisely this: the chase intersection is carried backwards through the victim's
own moves by `undo_move_board` (`bitboard.h:200-202`, used at `position.cpp:2659-2660, 2695, 2716`),
which is exactly "same piece, any square"; nothing anywhere records the attacker's identity.
Confirmed by the alternating-attacker probe (violation) and the alternating-target probe (draw), §4.

**Classification: ADOPT-ENGINE.**

**Fixtures.** `mx-chs-023` (alternating targets → neutral), `mx-chs-024` (alternating attackers, one
target → violation), plus `mx-chs-016` / `mx-chs-017` from §5.2 for the span boundary.

### 5.6 Target and attacker classes — ADOPT-ENGINE except the already-confirmed soldier patch

**Adopted rule (liftable prose).**

> Kings and soldiers take no part in the perpetual-chase rule in either role: neither may be the
> chased piece, and neither chases anything by its own move. A king or a soldier that moves may still
> uncover another piece's threat, and that threat is a chase by the piece that makes it.
> A horse or a cannon that attacks a chariot chases it whether or not it is protected. An attack on
> an enemy piece of the same kind, which can capture the attacker in return, is an offer of exchange
> and is not a chase. No other value comparison is part of this contract: the chariot is the only
> piece the rules treat as strictly stronger than the horse and the cannon, and the horse and the
> cannon are treated as equals.

**Justification.** The exclusion phrase is taken to remove both piece types from the rule entirely
(§1). Independently: a general is confined to nine squares and a soldier moves one step, so treating
either as a perpetual aggressor punishes a player who cannot in practice sustain a threat by design;
and the accepted contract already excludes both as targets, so a two-role exclusion is the reading
that keeps the contract internally consistent. The value clauses are argued in §5.1.

**What AXF does.** Attacker exclusion for kings and soldiers is exact (`position.cpp:3026`), with
discovery still allowed for those movers — matching the adopted rule clause for clause; confirmed by
the soldier-chaser and king-chaser probes (§4). The chariot value rule and the same-type exchange
exclusion are `position.cpp:2991-2992` and `3010`, confirmed by the horse-versus-protected-rook and
rook-versus-rook probes. The one mismatch is the *target* exclusion for soldiers, already established
as fork patch #1 and already pinned by `mx-chs-003`; nothing here changes it.

**Classification: ADOPT-ENGINE** for attacker classes and for the value rules; the soldier target
exclusion remains **PATCH-REQUIRED** (unchanged, already confirmed).

**Fixtures.** `mx-chs-025` (soldier as chaser → neutral), `mx-chs-026` (king as chaser → neutral),
plus `mx-chs-011` / `mx-chs-012` for the value rule.

---

## 6. What could not be resolved

### 6.1 One check, one chase (`一将一捉`) — flagged, not settled

The adopted contract (§5.4) rules a same-side alternation of check and chase to be no violation,
because neither bullet 1 nor bullet 2 is satisfied. Full AXF/CXA practice, as commonly summarised,
*forbids* that alternation while permitting one check with one idle move. The selected public source
says nothing either way, and the engine agrees with the permissive reading.

Adopting the permissive reading errs toward a claimable draw rather than a loss, which is the safe
direction, and costs nothing. **What would settle it**: the text of the AXF or Chinese Xiangqi
Association competition rules on 一将一捉. We do not have that text in the workspace, and acquiring it
is a network action outside this pass. Recorded so that a later reading of that text is a contract
amendment against a known position rather than a discovery.

### 6.2 Mutual perpetual check — no fixture; strong evidence of non-constructibility

The freeze draft deferred this as non-constructible. That judgement survives scrutiny, and the
reasoning can now be made sharper than "no minimal construction was found".

Every move of such a cycle must both parry the incoming check and give check, and no move may be a
capture (material must be constant for the position to repeat). That leaves king moves and
interposition/screen moves. For a **king move** to give check it must discover one, and on this board:

- a discovered *rook* check along a file is impossible, because the only files that can carry a check
  from one palace band to the other are c, d and e — the same files both kings occupy — and whenever
  the two kings share a file the flying-general rule forces at least one piece to stand between them,
  which is exactly the piece that would block the discovery;
- a discovered check along a *rank* is impossible, because the palace bands are disjoint (ranks 1–3
  against 5–7) and no rank contains both kings;
- a discovered *horse* check is impossible, because the leg square the king would vacate must lie in
  its own palace, and a horse whose leg is in one palace attacks no square in the other;
- the one mechanism that does work — a king stepping off a shared file and thereby dropping a cannon's
  screen count from two to one — works in one direction only, so it cannot supply a check on both of
  that king's moves in a cycle.

That leaves cycles in which *both* sides parry every check with a non-king move that itself checks.
Searches over 42,073 random in-check positions with 2–4 non-king pieces per side found no 4-ply cycle
of any kind in which all four moves check. This is strong evidence, not a proof: longer cycles and
larger material were not searched.

**Recommendation.** Keep the rule (mutual perpetual check → draw) as accepted and unfixtured, and let
`mx-chs-020` carry the mutual-violation branch. Note that the rule remains fully checkable app-side
(§5.4 option 1), so it does not depend on an unfixtured engine behaviour.

### 6.3 Mixed check-over-chase — no fixture; the recipe is now known

The freeze draft said this case "appears to require a discovered-chase component that is outside this
set's scope". The discovered-chase component is now demonstrated to work (`mx-chs-018`), so that
scoping reason no longer holds — but the construction is still not built.

The structural obstruction, stated precisely: the chased side's moves are forced parries. If it
parries with king moves, its king ends up off the line the checker is on and its chase target is
always on the wrong line at the wrong ply, so the chase never repeats on both plies of a cycle; this
was worked through for rank-shuttle, file-shuttle and cannon-screen variants and fails in each. The
construction that should work is the block-and-rediscover pattern that made `mx-chs-020` work: the
checking side alternates between two checking lines, and the checked side's single blocking piece
shuttles between the two blocking squares in such a way that each of its moves also unblocks one of
two of its own lines aimed at one fixed enemy piece. That needs roughly five non-king pieces per
side — above what the random search reached (`a-c10.py`: 1,301 candidates at ≤3 per side, no hits).

**Blocker**: a targeted constructive search at ≥4 non-king pieces per side, or hand construction of
the pattern above. **Impact if it stays unbuilt**: low. The user-visible outcome of the mixed case is
identical to unilateral perpetual check (the checker loses), which `mx-chk-001` and `mx-chk-002`
already pin, and precedence is structural in the engine (`position.cpp:2704-2705`) and trivially
enforceable in the facade.

### 6.4 Residual uncertainties worth stating

- The engine's flying-general pin marking (`position.cpp:2979-2984`) does not check that the pieces on
  the file actually stand *between* the kings, so it can mark a victim piece pinned when a chaser
  piece also stands on that file. This over-approximates pins, which makes defenders vanish (more
  chases detected) and same-type targets stay chaseable. No probe here triggered it; a fixture would
  need a three-piece file arrangement. Not resolved.
- The fake-roots branch (`position.cpp:3054-3068`) marks a piece chased when a *newly pinned* defender
  had been defending it, without re-checking whether other defenders remain. That over-detects when
  the target has two defenders. Not probed; flagged.
- The novelty filter for a rook or cannon mover discards attacks along `line_bb(from, to)`
  (`position.cpp:3030-3031`) rather than comparing before/after attack sets. In this variant the
  approximation appears sound (moving along a line toward a target means the attack already stood),
  but a construction where a rook's move along a rank newly attacks a square on that same rank —
  possible only if the mover jumped over nothing, hence impossible for a rook — would break it. Stated
  as believed-sound, not proven.

---

## 7. Proposed fixture tranche

Schema and identifier vocabulary as in `MiniXiangqi/fixtures/rules/README.md`. All are
`"area": "chs"` except `mx-chk-003` (`"area": "chk"`); all are `"variant": "minixiangqi"` with
`legal_moves`/`rejected_moves`/`applied` all `null`.
Every move below was verified legal at its turn, every `result_fen` and `in_check` value was produced
by replay, and every `boundary.prefix_len` was verified not yet ended (`a-c14.py`). "engine" is the
AXF child's verdict, recorded as an observation only.

| id | start_fen | moves | plies | boundary | expected game_state | engine |
|---|---|---|---|---|---|---|
| mx-chs-005 | `4k2/7/c3r2/7/1R5/7/2K1R2 w - - 0 1` | `b3a3 a5b5 a3b3 b5a5` ×2 | 8 | 4 | black-wins / perpetual-chase @3 | agrees |
| mx-chs-006 | `4k2/7/c3c2/7/1R5/7/2K4 w - - 0 1` | `b3a3 a5b5 a3b3 b5a5` ×2 | 8 | 4 | black-wins / perpetual-chase @3 | agrees |
| mx-chs-007 | `7/7/1ck4/7/7/7/R3K2 w - - 0 1` | `a1b1 b5a5 b1a1 a5b5` ×2 | 8 | 4 | black-wins / perpetual-chase @3 | agrees |
| mx-chs-008 | `7/3k3/3c3/6R/7/7/2K4 w - - 0 1` | `g4g5 d5d4 g5g4 d4d5` ×2 | 8 | 4 | claimable-draw / threefold-repetition @3 | agrees |
| mx-chs-009 | `4R2/7/2kc3/7/7/7/3K3 w - - 0 1` | `e7d7 d5e5 d7e7 e5d5` ×2 | 8 | 4 | black-wins / perpetual-chase @3 | agrees |
| mx-chs-010 | `4R2/7/2kc3/7/7/7/4K2 w - - 0 1` | `e7d7 d5e5 d7e7 e5d5` ×2 | 8 | 4 | claimable-draw / threefold-repetition @3 | agrees |
| mx-chs-011 | `4k2/3N3/r3r2/7/7/7/3K3 w - - 0 1` | `d6c4 a5b5 c4d6 b5a5` ×2 | 8 | 4 | black-wins / perpetual-chase @3 | agrees |
| mx-chs-012 | `4k2/3N3/c3r2/7/7/7/3K3 w - - 0 1` | `d6c4 a5b5 c4d6 b5a5` ×2 | 8 | 4 | claimable-draw / threefold-repetition @3 | agrees |
| mx-chs-013 | `4k2/7/r6/7/1R5/7/2K4 w - - 0 1` | `b3a3 a5b5 a3b3 b5a5` ×2 | 8 | 4 | claimable-draw / threefold-repetition @3 | agrees |
| mx-chs-014 | `3k3/7/c6/7/1R5/7/2K4 w - - 0 1` | `b3a3 a5a6 a3b3 a6a5` ×2 | 8 | 4 | claimable-draw / threefold-repetition @3 | agrees |
| mx-chs-015 | `3k3/7/c6/7/2R4/7/4K2 w - - 0 1` | `c3a3 a5b5 a3b3 b5c5 b3c3 c5a5` ×2 | 12 | 6 | black-wins / perpetual-chase @3 | agrees |
| mx-chs-016 | `4k2/7/c6/7/1R5/7/2K4 w - - 0 1` | `c1c2 e7e6 c2c1 e6e7 b3a3 a5b5 a3b3 b5a5` | 8 | 4 | claimable-draw / threefold-repetition @3 | agrees |
| mx-chs-017 | `4k2/7/c6/7/1R5/7/2K4 w - - 0 1` | `c1c2 e7e6 c2c1 e6e7` + `b3a3 a5b5 a3b3 b5a5` ×2 | 12 | 4 | black-wins / perpetual-chase @4 | agrees |
| mx-chs-018 | `4k2/7/R1Nc3/7/7/7/2KR3 w - - 0 1` | `c5d3 e7e6 d3c5 e6e7` ×2 | 8 | 4 | black-wins / perpetual-chase @3 | agrees |
| mx-chs-019 | `3rk2/7/7/3R3/1c5/7/3K3 w - - 0 1` | `d4d3 b3b4 d3d4 b4b3` ×2 | 8 | 4 | claimable-draw / threefold-repetition @3 | **diverges** (rules Red lost) |
| mx-chs-020 | `2k2r1/7/1cN1R2/7/2r1nC1/7/1R2K2 w - - 0 1` | `c5b3 e3f5 b3c5 f5e3` ×2 | 8 | 4 | draw / mutual-perpetual-chase @3 | value agrees (0); reason not observable — see §5.4 |
| mx-chs-021 | `2k4/7/1cN1R2/7/4n2/7/1R2K2 w - - 0 1` | `c5b3 e3f5 b3c5 f5e3` ×2 | 8 | 4 | black-wins / perpetual-chase @3 | agrees |
| mx-chs-022 | `2k2r1/7/2N4/7/2r1nC1/7/4K2 w - - 0 1` | `c5b3 e3f5 b3c5 f5e3` ×2 | 8 | 4 | red-wins / perpetual-chase @3 | agrees |
| mx-chs-023 | `3k3/7/c5c/7/R6/7/2K4 w - - 0 1` | `a3g3 d7d6 g3a3 d6d7` ×2 | 8 | 4 | claimable-draw / threefold-repetition @3 | agrees |
| mx-chs-024 | `R6/7/c3k2/7/1R5/7/3K3 w - - 0 1` | `b3a3 a5b5 a7b7 b5a5 b7a7 a5b5 a3b3 b5a5` ×2 | 16 | 8 | black-wins / perpetual-chase @3 | agrees |
| mx-chs-025 | `4k2/7/1c5/2P4/7/7/3K3 w - - 0 1` | `c4b4 b5c5 b4c4 c5b5` ×2 | 8 | 4 | claimable-draw / threefold-repetition @3 | agrees |
| mx-chs-026 | `4k2/7/7/7/2c4/3K3/7 w - - 0 1` | `d2c2 c3d3 c2d2 d3c3` ×2 | 8 | 4 | claimable-draw / threefold-repetition @3 | agrees |
| mx-chk-003 | `3k3/7/c6/R6/7/7/4K2 w - - 0 1` | `a4d4 d7c7 d4a4 c7d7` ×2 | 8 | 4 | claimable-draw / threefold-repetition @3 | agrees |

`result_fen` for every fixture is its `start_fen` piece placement with side to move `w`, halfmove
counter equal to the ply count, and fullmove number `1 + plies/2` — verified individually; e.g.
`mx-chs-005` → `4k2/7/c3r2/7/1R5/7/2K1R2 w - - 8 5`, `mx-chs-015` → `3k3/7/c6/7/2R4/7/4K2 w - - 12 7`,
`mx-chs-024` → `R6/7/c3k2/7/1R5/7/3K3 w - - 16 9`, `mx-chk-003` → `3k3/7/c6/R6/7/7/4K2 w - - 8 5`.
`in_check` is `false` in all twenty-three.

Rationales (one line each, for the fixture files):

- **005** The black rook on e5 defends both flight squares but is pinned by the white rook on e1, so
  it could not legally recapture; a false root does not protect and the chase is a violation.
- **006** Same shape as `mx-chs-002` with a cannon on e5 instead of a rook: a cannon protects only
  through exactly one screen and there is none, so the target is unprotected.
- **007** The black king on c5 stands next to b5 but may not leave its palace, so it could not
  recapture there; a king protects only squares inside its own palace.
- **008** The black king on d6 can legally recapture on d5, which is inside its palace, so the target
  is protected on that flight square and the sequence is a neutral repetition. Differential partner of
  `mx-chs-007`.
- **009** The black king on c6 is the only defender of d5, but recapturing there would place it on the
  white king's file with nothing between, so the recapture is illegal and the target is unprotected.
- **010** Identical to `mx-chs-009` with the white king off the d-file, so the king's recapture is
  legal, the target is protected, and the repetition is neutral.
- **011** A horse attacking a chariot wins material even after recapture, so a protected chariot is
  still chased.
- **012** The same horse shuttle against a protected cannon wins nothing after recapture, so it is not
  a chase. Differential partner of `mx-chs-011`.
- **013** The two rooks attack each other on equal terms; an offer of exchange is not a chase.
- **014** The white rook chases on one move of the cycle and makes an idle move on the other, so the
  chase is not perpetual and the repetition is neutral.
- **015** A six-ply cycle in which every white move renews the attack on the same fleeing cannon is a
  violation; the length of the cycle is not part of the rule.
- **016** The three occurrences are spanned by a cycle in which white made two king moves that chased
  nothing, so the violation is not sustained across the span and the repetition is neutral.
- **017** After the same idle interlude, two further chasing cycles produce a fourth occurrence whose
  whole span consists of chasing moves; interrupting and resuming delays the violation but does not
  cancel it.
- **018** Every white move is a discovered attack — the horse alternately unblocks the rook on a5 and
  the rook on d1 — and never a direct one; a discovered chase is a chase.
- **019** The white rook is absolutely pinned on the d-file and could never capture the cannon, so its
  "attack" is not a threat and the repetition is neutral. *Expected to fail against the current
  Fairy-Stockfish AXF classifier, which does not test attacker legality.*
- **020** Both sides chase one unprotected enemy piece with every move — white the cannon on b5, black
  the cannon on f3, each by alternating discovered attacks — so both violate the same rule and the
  game is a draw.
- **021** The white half of `mx-chs-020` alone: a unilateral perpetual chase, Red loses.
- **022** The black half of `mx-chs-020` alone: a unilateral perpetual chase, Black loses. With
  `mx-chs-021` this proves the draw in `mx-chs-020` comes from both violations, not from the absence
  of either.
- **023** The white rook alternates between two different unprotected cannons; the rule requires the
  same one piece to be chased, so this is a neutral repetition.
- **024** Two white rooks alternate as the attacker while the same black cannon is chased after every
  white move; the chasing piece may change, so the violation stands.
- **025** A soldier does not chase: soldiers take no part in the chase rule in either role.
- **026** A king does not chase: generals take no part in the chase rule in either role.
- **chk-003** Red checks on one move of each cycle and chases the unprotected cannon on the other, so
  its moves are neither all checks nor all chases of one piece; an alternation of the two classes is
  no violation and the repetition is neutral.

Suggested review order if the tranche is split: 005/006/007/008/009/010 (protection),
014/016/017 (interruption and span), 018/019 (discovery and pins), 020/021/022 and chk-003 (mutual
and mixed), 023/024 (boundary), 011/012/013/025/026 (classes), 015 (cycle length).

---

## 8. Summary of classifications and fork impact

| question | adopted rule | classification |
|---|---|---|
| 1 protection | legal-recapture test, palace- and flying-general-aware, cannon screens, post-capture occupancy, value clause, exchange clause | ADOPT-ENGINE (one under-detection accepted; PATCH-OPTIONAL) |
| 2 interruption | all-moves-in-the-span test; one alternate move discharges; resume re-arms | ADOPT-ENGINE |
| 3 discovered / pinned | discovered chases count and must be newly created; pinned attackers do not chase; discovered check is a check | ADOPT-ENGINE / **PATCH-REQUIRED** / CONTRACT-ONLY |
| 4 mutual and mixed | same class = same of the two classes; check outranks chase; alternation is no violation | ADOPT-ENGINE (precedence) + CONTRACT-ONLY (definition) + PATCH-REQUIRED (mutual-chase reason reporting) |
| 5 terminal boundary | same side, same class, same target piece tracked through its moves; attacker and squares free | ADOPT-ENGINE |
| 6 target and attacker classes | kings and soldiers excluded in both roles; chariot-value clause; same-type exchange clause | ADOPT-ENGINE (soldier *target* patch unchanged) |

Fork patch list after this pass, in priority order:

1. **Soldier chase-target exclusion** — already confirmed, unchanged (`position.cpp:2989`).
2. **Pinned-attacker legality** — new, §5.3. Prevents a wrong loss.
3. **Mutual-violation reason reporting** — new, §5.4, read-only accessor; alternatively a contract
   change that claim-gates mutual chases.
4. **King-root recapture legality beyond flying general** — optional, §5.1. Prevents a missed
   violation only.

Items 2–4 are all small and local to the chase path; none requires new history semantics. Item 3
touches no adjudication at all.

---

## 9. Reproduction

```
cd /Users/tianren/coding/minixiangqi/discussion-drafts
python3 a-drive.py a-c2.py     # protection probes
python3 a-drive.py a-c3.py     # protection, interruption, discovery, boundary probes
python3 a-drive.py a-c4.py     # symmetry and value probes
python3 a-drive.py a-c8.py     # mutual perpetual chase and its two halves
python3 a-drive.py a-c11.py    # span semantics
python3 a-drive.py a-c12.py    # delayed violation after an interruption
python3 a-drive.py a-c14.py    # fixture legality, result FENs, boundary prefixes
python3 a-drive.py a-c15.py    # mx-chk-003 legality, result FEN, per-ply check flags
python3 a-drive2.py a-c9.py    # discriminator child sanity check
python3 a-drive.py a-c7.py     # mutual perpetual check search (long; negative)
python3 a-drive2.py a-c10.py   # mixed check/chase search (long; negative)
```

Requires only the workspace pyffish build and Python 3.14. `validate.py` and the approved fixture
JSONs were not modified.
