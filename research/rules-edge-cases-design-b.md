# Deferred perpetual-check / perpetual-chase edge cases — implementation-first design (Agent B)

## 0. Scope, evidence base, reproduction

This draft resolves the six deferred questions listed in `MiniXiangqi/docs/xiangqi-rules.md` **Need to discuss**. Its method is implementation-first: establish exactly what Fairy-Stockfish's AXF classifier does, verify that reading empirically, then judge each behaviour against the selected normative source and either adopt it, patch it, or push it into the app-side facade.

**Revisions read.**

- **FS** — `Fairy-Stockfish` at fork HEAD `77d602e00db0527781e6abb76802bf1757f7e6fa` (`master`, clean tree). This HEAD already contains the merged fork patch `minixiangqi/soldier-chase-exemption` (commits `232ca36b`, `ebe320a5`, merge `77d602e0`, all dated `2026-07-27`), which adds the variant property `promotedSoldiersChaseable`. Upstream base is `c19b5f6c`. **All line numbers in this draft are HEAD line numbers**; the diff versus `c19b5f6c` touches `position.cpp` only at `:2985-2990` and `:3066` (plus `parser.cpp`, `variant.h`, `variants.ini`, `test.py`), so pre-patch citations are shifted by six lines inside `chased()` and unchanged everywhere else.
- **PC** — `pychess-variants` at `961fd6dd60ce76d3baced1a77df49ca58edcb315` (read-only reference).
- **Normative source** — the retained snapshot `discussion-drafts/evidence/pychess-minixiangqi-rules-2026-07-26.html`, section *Additional Rules - Perpetual checks and chases*; identical text is tracked at `pychess-variants/static/docs/minixiangqi.md:20-26`.
- **Engine runtime** — the prebuilt `pyffish` 0.0.89 in `discussion-drafts/evidence/pyffish-build` (`Fairy-Stockfish 260726`). **This binary predates the fork patch**, so every observation below is upstream AXF behaviour, i.e. behaviour with `promotedSoldiersChaseable` at its default `true`. That is the correct baseline: the patch only makes the soldier exemption selectable and changes nothing else.

**Scratch harness (mine, workspace-only, does not touch any checkout).**

```
cd /Users/tianren/coding/minixiangqi/discussion-drafts
python3 b-exp1.py     # protection, attacker legality, discovery, window
python3 b-exp2.py     # value ordering, symmetry, attacker classes, mutual chase
python3 b-exp3.py     # window control, soldier defenders, flying-general false pin
python3 b-exp4.py     # mutual perpetual check: verification and minimisation
python3 b-fixtures.py # exact field values for every fixture proposed below
python3 b-search2.py 60000 RCN/rcn 11   # finds mutual-perpetual-check cycles (§5.3)
python3 b-search3.py  6000 RCN/rcn 5    # finds the mixed check/chase cycle (§5.5)
```

`b-search.py` is the first, slower cycle searcher, superseded by `b-search2.py`; it is kept because its zero-hit runs are part of the bound reported in §5.3.

`b-probe.py` holds the shared helpers and loads an in-memory AXF child identical in text to `fixtures-draft/minixiangqiaxf-validation.ini` (that file is read-only here and was not touched). Every claim tagged **[obs]** below is reproducible from these scripts; every claim tagged **[src]** is a source reading.

**Normative stance.** Fixture expectations below are the *adopted contract*, derived from the normative source plus the reasoning in each section. Engine agreement is recorded separately. Three proposed fixtures deliberately encode a result the current engine does **not** produce; those are the patch requests.

**Headline findings.** (1) Both fixtures the freeze draft deferred as non-constructible on 7×7 — mutual perpetual check and check-over-chase precedence — **are constructible**, in six and five pieces respectively (§5.3, §5.5); its non-constructibility reasoning was wrong and should not be relied on. (2) Three distinct, empirically demonstrated defects in the AXF adjudication produce user-visible wrong results and need fork patches (§2.4, §4.4, §6.2); two of them are false terminal **losses**. (3) Everything else in the classifier is defensible against the normative source and should be adopted as-is.

---

## 1. What the AXF adjudication actually is

This section is the operational specification the rest of the draft argues about. Everything here is **[src]** unless marked.

### 1.1 Where the chase state lives

`StateInfo::chased` is a bitboard recomputed on every move inside `set_check_info` (`position.cpp:598`), which `do_move` calls *after* flipping the side to move (`position.cpp:2096`, `position.cpp:2114`). Therefore inside `Position::chased()` (`position.cpp:2973-3096`):

- `~sideToMove` is the side that just moved — **the chaser**;
- `sideToMove` is the side to move — **the victim**;
- the returned bitboard is a set of **victim squares** that the chaser's *last move* has put under a chasing attack.

`chased()` returns `0` when there is no previous move (`position.cpp:2975-2976`).

### 1.2 `chased()` — the per-move classifier

**Pin set** (`position.cpp:2978-2984`). `pins = blockers_for_king(victim)`, plus a flying-general term: if the victim's king stands on the *chaser's king's file* and the victim has at most one non-king piece on that file, that piece is added to `pins`. The flying-general term looks only at `pieces(sideToMove)` — it never checks whether a **chaser** piece also stands on that file. That omission is a live defect; see §2.4.

**Exempt targets** (`position.cpp:2985-2990`, fork patch; `:2995`). `chaseExempt = kings ∪ soldiers`, minus promoted soldiers when `promotedSoldiersChaseable` (default `true`). Because Mini Xiangqi's `soldierPromotionRank` is the inherited default `1` (`variant.h:118`, `position.h:891-894`), **every** Mini Xiangqi soldier is "promoted" from move one, so with the default all soldiers are chaseable. The exemption is applied in `addChased` (`:2995`) and in the fake-roots path (`:3066`) but **not** in the discovered-check path (`:3081-3091`) — the fork's own documentation scopes it that way (`variants.ini:260`).

**Value ordering** (`position.cpp:2996-3000`). A horse or cannon attacking a **rook** is added unconditionally, protection irrelevant. An elephant or fers attacking rook/cannon/horse likewise (unreachable in Mini Xiangqi — no such pieces). Everything else falls through to the protection test.

**Symmetric-attack exclusion** (`position.cpp:3001-3016`). Targets of the **same piece type as the attacker** are dropped, *unless* they are in `pins`. A special branch handles the "impaired horse": when the attacker is a horse with any piece on a diagonally adjacent square, enemy horses are dropped only if they actually attack back. Note the horse branch does **not** honour the `pins` exception.

**Protection test** (`position.cpp:3017-3024`).

```
roots = attackers_to(s, pieces() ^ attackerSq, victim) & ~pins;
chased if  !roots
        || (flyingGeneral && roots == victimKingBB
            && (attacks_bb(victim, ROOK, chaserKingSq, pieces() ^ attackerSq) & s))
```

Three consequences worth naming:

1. Occupancy has the **attacker removed**, so a defender whose line to `s` runs *through* the attacker counts as protection (an X-ray / battery defender). This is correct recapture modelling.
2. **Pinned defenders never protect.**
3. The **only** modelled reason a lone king defender fails to protect is the flying general. The `ROOK` attack set used there is rank-or-file, but the square `s` in that branch is necessarily inside the victim's palace (only there can the king be a "root"), and the two palaces occupy disjoint rank bands (`variant.cpp:1237-1238`), so the two kings can never share a rank and only the file case is reachable — the implementation is equivalent to file-only flying general here.

Also note `attackers_to` gates each piece type by its mobility region (`position.cpp:963`, `position.h:430-433`) and Mini Xiangqi takes the slow path (`fastAttacks`/`fastAttacks2` are false because `kingType == WAZIR`, `variant.cpp:1239`, `variant.cpp:1995-2004`). A king therefore only "defends" squares **inside its own palace**.

**Direct attacks** (`position.cpp:3028-3039`). Only if the moved piece is neither `KING` nor `SOLDIER`. For rook/cannon movers, `directAttacks &= ~line_bb(from, to)` discards every square on the line of travel. There is no novelty filter at all for horse movers.

**Discovered attacks** (`position.cpp:3041-3054`). Candidates are chaser horses on a wazir-neighbour of `from`, chaser elephants on a fers-neighbour of `from`, chaser rooks/cannons aligned with `from`, and chaser cannons aligned with `to`. For each, only strictly new attacks count (`attacks_now & ~attacks_before`, where "before" is the pre-move occupancy), filtered by the same `addChased` rules and attributed to the discovering piece.

> **The rook/cannon mover is its own discovery candidate.** `PseudoAttacks[ROOK][from]` necessarily contains `to` for a rook or cannon move, and `pieces(~sideToMove, CANNON, ROOK)` contains the piece that just moved. So a moved rook or cannon re-enters at `position.cpp:3044` and its **along-the-line** attacks are re-admitted through the exact before/after comparison, after `line_bb` discarded them in the direct path. The two halves are complementary: off-line attacks from `to` can never have existed before (they lie on the perpendicular through `to`, which does not pass through `from`), so `~line_bb` is exact there; on-line attacks are tested exactly. A moved **horse** is *not* its own candidate (a horse move is never a wazir step), nor is a moved king or soldier. This is not cosmetic — it is the mechanism that carries the chase in `mx-chs-024` / `mx-mix-004` (§5.5), and I found it only by chasing down why a search hit adjudicated the way it did.
>
> One caveat, stated because the contract wording depends on it: the comparison is made **from the square the piece now occupies**. A rook that attacked the target from its old square and still attacks it from the new one counts as renewing, provided the attack was blocked from the new square before the move. So the engine's rule is "this move changed what this piece attacks from where it now stands", not "this attack did not exist anywhere before".

**Fake roots** (`position.cpp:3056-3074`). Victim pieces that became blockers-for-their-own-king on this move are treated as having stopped defending: every non-exempt victim piece they attack, which is attacked by any non-pinned chaser piece, is added. This path applies **no value ordering, no symmetry exclusion, no attacker-type restriction, and no check that the newly pinned piece was the only defender.**

**Discovered checks** (`position.cpp:3075-3092`). Chaser pieces that became blockers-for-the-victim's-king are treated as able to capture with tempo: everything they attack that the victim's king cannot recapture is added. This path applies **no exempt-target mask** (so the victim's soldiers, and in principle its king, can enter the chased set) and **no attacker-type restriction** (a chaser soldier or king can be the "attacker" here).

### 1.3 The repetition aggregator

`Position::is_optional_game_end` (`position.cpp:2621`) scans history in two-ply steps over `end = min(rule50, pliesFromNull)`, requiring `end >= 4` (`position.cpp:2651-2653`).

Let `T_j` denote the state `j` plies before the current one (`T_0` = now; the side to move at `T_0` is **us**, the opponent is **them**).

- `perpetualThem` starts as `checkers(T_0) && checkers(T_2)` and is `&=`'d with `checkers(T_4)`, `checkers(T_6)`, … before the repetition test (`:2657`, `:2697`).
- `perpetualUs` starts as `checkers(T_1) && checkers(T_3)` and is `&=`'d with `checkers(T_5)`, `checkers(T_7)`, … **after** the repetition test (`:2658`, `:2713-2715`).
- `chaseThem = undo_move_board(chased(T_0), move(T_1)) & chased(T_2)`, then intersected with `chased(T_4)`, `chased(T_6)`, … before the repetition test, skipping the step where `i == pliesFromNull` (`:2659`, `:2694-2695`).
- `chaseUs = undo_move_board(chased(T_1), move(T_2)) & chased(T_3)`, then intersected with `chased(T_5)`, `chased(T_7)`, … after the repetition test (`:2660`, `:2716`).
- `undo_move_board` (`bitboard.h:200-202`) rewrites `to_sq → from_sq`, i.e. it **tracks a chased piece through the victim's own moves**. Identity is by piece, not by square. (`StateInfo::move` is the move that *produced* that state, `position.cpp:1561`.)

The repetition test fires at the first `i` where the key matches and `cnt + 1 >= nFoldRule` (`:2701-2702`) — the third occurrence, counting the first. The result is (`:2704-2707`):

```
if (perpetualThem || perpetualUs)  →  only them: they lose;  only us: we lose;  both: DRAW
else if (chaseThem || chaseUs)     →  only them: they lose;  only us: we lose;  both: DRAW
else                               →  nFoldValue (draw)
```

Perpetual **check outranks chase unconditionally**: when either side is perpetually checking, the chase bitboards are never consulted.

**The window asymmetry.** Because the `return` sits between the `chaseThem` update and the `chaseUs` update, at the firing occurrence `T_k`:

- `chaseUs` spans **our** moves at `T_1, T_3, …, T_{k-1}` — exactly the moves strictly inside the three-occurrence window;
- `chaseThem` spans **their** moves at `T_0, T_2, …, T_k` — one move too many. `T_k` is the move that *created* the first occurrence and lies outside the window. The `i != pliesFromNull` guard hides this only when the game history begins exactly at the first occurrence.

This is a real, demonstrable defect, not a reading artefact: see §6.2.

---

## 2. Question 1 — Protection

### 2.1 Adopted rule (liftable prose)

> A chased piece is **protected** at the moment of the chasing move when at least one piece of the chased side, other than the chased piece itself, could capture on the chased piece's square in the position that would follow the chasing capture. In detail:
>
> - Occupancy for this test is the current position with the **chasing piece removed** from its square. A defender whose line to the square passes through the chasing piece therefore counts (battery or X-ray protection).
> - A defender that is **pinned** — absolutely pinned against its own king, or pinned by the flying-general rule — does not protect.
> - **Soldiers do protect.** Their exclusion from the rules applies to being chased, not to defending.
> - The **king** protects only squares inside its own palace, and does **not** protect when moving the king to that square would leave the two kings facing on an otherwise empty file.
> - A chased piece with no such defender is **unprotected**.
> - Independently of protection, an attack by a horse or a cannon on a **chariot** is always a chase (see §7).

### 2.2 Normative justification

The source says the loser is "the side that perpetually chases any one **unprotected** piece" (`pychess-variants/static/docs/minixiangqi.md:21`). It does not define "unprotected". The only defensible reading in a game where the point of a chase is to win material is *"the chased side cannot recapture"* — which is exactly what the engine computes: legality of the recapture (pins, flying general) and its geometry (X-ray through the attacker) are precisely the things that decide whether the chase wins material.

### 2.3 What the engine does — and it matches, with two exceptions

| case | engine | probe | result |
|---|---|---|---|
| unpinned defender covering both flight squares | protected | existing `mx-chs-002` | draw |
| defender **pinned** against its own king | not protected | `b-exp1.py` B1 | violation |
| **X-ray** defender behind the attacker | protected | `b-exp1.py` C1 vs C0 | draw vs violation |
| **soldier** defender | protected | `b-exp3.py` R1 vs C0 | draw vs violation |
| **king** sole defender, flying general voids recapture | not protected | `b-exp1.py` D1 | violation |
| **king** sole defender, recapture legal | protected | `b-exp1.py` D2 | draw |

All six **[obs]**. Each pair differs by one piece or one king square, so each isolates exactly one rule. **ADOPT-ENGINE** for all six.

Two remarks on constructibility, since the freeze draft flagged these as open:

- The differential pair D1/D2 required a construction in which the king is the sole defender at **only one** of the two chased squares. That is necessary: on a 7×7 board **no wazir king can defend both squares of a two-square target shuttle**, because two squares defended by the same wazir king are either diagonally adjacent (no Mini Xiangqi piece moves that way) or two apart on a line with the king between them (blocking the move). The D1/D2 geometry sidesteps this by leaving the other square wholly undefended.
- Both are constructible, contrary to the expectation in the freeze draft that "king defenders under flying general" would be hard. `mx-chs-008` / `mx-chs-009` below.

### 2.4 PATCH-REQUIRED — the flying-general false pin

**[src]** `position.cpp:2981-2983` computes the flying-general pin from `file_bb(chaserKingFile) & pieces(victim)` only. If a **chaser** piece also stands between the two kings on that file, the victim's piece is not pinned at all, but the engine marks it pinned — which both voids its protective value and, worse, bypasses the symmetric-attack exclusion.

**[obs]** `b-exp3.py` S1: `2k4/7/R6/2r4/2N4/7/2K4 w - - 0 1`, moves `a5a4 c4c5 a4a5 c5c4` twice. White's rook and Black's rook attack each other symmetrically — the shape the engine correctly rules a non-chase in `b-exp2.py` I1 and in the S2 control (`3K3` instead of `2K4`, draw). Here the white knight on c3 already blocks the c-file, so the black rook is demonstrably free — the harness prints its nine legal moves including `c4b4` and `c4d4`. The engine nonetheless returns `(True, -32000)`: **Red loses a game on a pin that does not exist**.

This is a false *positive* terminal loss produced by a two-line omission. **PATCH-REQUIRED.** Minimal semantics:

> The flying-general pin applies only when the two kings share a file and the **only** piece between them, of either colour, is the piece being considered.

i.e. compute the between-squares occupancy over `pieces()`, not over `pieces(sideToMove)`.

### 2.5 ADOPT with documentation — the king-defender simplification

**[src]** The `roots == kingBB` escape hatch (`position.cpp:3022`) models exactly one reason a king cannot recapture. **[obs]** `b-exp3.py`/`b-fixtures.py` `mx-chs-023`: with a white horse on b4 covering c6, Black's king on c7 cannot legally recapture on c6, so the cannon is in truth unprotected — the engine still reports a neutral draw.

This is a false *negative*: the fallback is a claimable repetition draw, i.e. a legitimate, non-terminal result the user can decline. Generalising it means running full legality on the hypothetical recapture inside a function called on every `do_move`. **ADOPT-ENGINE**, with the limitation stated in the contract and pinned by fixture `mx-chs-023` so a future engine change cannot silently alter it. This is the weakest adopt in this draft and the one a reviewer is most entitled to overturn.

---

## 3. Question 2 — Interruption

### 3.1 Adopted rule (liftable prose)

> A perpetual violation is evaluated over the whole span of moves from the **first** of the three occurrences of the repeated position to the position now on the board — not only over the repeated positions themselves.
>
> - A **perpetual chase** exists only if *every* move by the chasing side in that span **renews** the attack on the *same* chased piece. A move renews the attack when the attacking piece, from the square it occupies after the move, attacks the chased piece and did not do so from that square before the move; a move also renews it when it opens the line or leg of another piece onto the chased piece. The chased piece is followed through its own moves, so it may change square; the chasing piece and the attacking square need not stay the same.
> - A **perpetual check** exists only if the checked side is in check at *every* one of its turns in that span.
> - Any single move by the violating side that does not renew the violation ends it: the count does not "carry over", and the repetition is then adjudicated as neutral (claimable draw) unless the other side is itself violating.
> - Alternating between two different chased pieces is not a perpetual chase of either.
> - Alternating between checking and chasing is neither a perpetual check nor a perpetual chase.
> - A capture makes the position unrepeatable, so no interruption question arises across one.

### 3.2 Justification and engine behaviour

**[src]** §1.3: the chase bitboard is a running intersection over consecutive two-ply steps; a single empty `chased` set collapses it permanently. Identically for `perpetual*` and `checkersBB`.

**[obs]** Four independent constructions confirm this and, together, fully pin the rule:

| probe | shape | result |
|---|---|---|
| `b-exp1.py` C1 | chase renewed on only one of the two white moves per cycle (the other move's target is X-ray-protected) | draw |
| `b-exp1.py` F2 | chase renewed on only one of the two white moves per cycle (the other discovery is missing) | draw |
| `b-exp2.py` M2 | both white moves chase, but **different** targets | draw |
| `b-exp2.py` M1 | white checks on one move, chases on the other | draw |

Note what M1 and M2 mean in play: a side may harass forever, alternating targets or alternating check and chase, and the engine calls it a neutral repetition.

### 3.3 Judgement

The normative source says "perpetually chases **any one** unprotected piece with one or more pieces" — *one* target, *possibly several* attackers. The engine's intersection semantics is a literal implementation of that sentence, so M2 (two targets) is not merely defensible but **required** by the source. **ADOPT-ENGINE.**

M1 is different. Real Asian tournament practice does penalise mixed perpetual harassment, and the source's fourth bullet ("when neither side violates the rules…") arguably does not cover a side that violates *alternately*. I judge this **ADOPT-ENGINE anyway**: the source enumerates exactly two violation classes and defines each as a persistent single behaviour, the fallback is a claimable draw rather than a wrong terminal result, and encoding "combined perpetual" would require a new history predicate in the engine with no textual authority behind it. This should be stated in the contract as an explicit interpretation, not left implicit, and it is pinned by `mx-mix-003`.

**Uncertainty, stated plainly:** M1 is the one place where I would change my recommendation given a better source. If the product owner obtains an AXF/Chinese-rules text that names combined perpetual check-and-chase ("长将兼长捉") as a violation, this becomes PATCH-REQUIRED. Evidence that would settle it: an authoritative AXF or CXA rules article on combined perpetual moves. The pychess page alone does not settle it.

---

## 4. Question 3 — Discovered and pinned attacks

### 4.1 Adopted rule (liftable prose)

> - A **discovered attack** counts as a chase by the side that moved. The chasing piece is the piece whose line or leg was opened, not the piece that moved, and the attack must be one that piece did not already have before the move.
> - A **discovered check** is a check for every purpose of these rules; how the check arose is irrelevant.
> - An attack by a piece that **cannot legally make the capture** is not a chase. In particular, an attack by a piece absolutely pinned against its own king is not a chase unless the capture square lies on the pin line.

### 4.2 Discovered attacks — ADOPT-ENGINE

**[src]** `position.cpp:3041-3054`, described in §1.2.

**[obs]** `b-exp1.py` F1 is a *pure* discovered chase: `4k2/7/R2n3/7/3N3/7/2KR3 w - - 0 1`, moves `d3c5 e7e6 c5d3 e6e7` twice. White's horse shuttles d3↔c5 and never attacks the black horse on d5; each horse move opens a different white rook's line onto d5 (Rd1 up the d-file, then Ra5 along rank 5). Engine: `(True, -32000)`. Control F2 removes Ra5 so only one of the two moves discovers: `(True, 0)`.

This also settles a structural point that matters for the whole tranche: **a sustained chase does not require the chased piece to move**, and conversely a single shuttling rook, cannon or horse can never sustain one against a *stationary* target. Proof for a rook or cannon shuttling `x ↔ y` on line `L`: the move `x→y` contributes the off-`L` attacks from `y` (which lie on the perpendicular through `y`) plus the on-`L` attacks that open beyond `x`; the move `y→x` contributes the perpendicular through `x` plus the on-`L` attacks beyond `y`. The two perpendiculars are distinct parallel lines, and "beyond `x`" and "beyond `y`" are opposite half-lines of `L`, so the two contributions are disjoint and no fixed square is in both. For a horse the argument is a parity one: every square attacking `s` has the colour opposite to `s`, hence all attackers of `s` share a colour, hence no two of them are a horse-move apart. Discovery by a *different* piece is therefore the only mechanism that renews against a stationary target — and it works.

### 4.3 Discovered checks — ADOPT-ENGINE

**[src]** `perpetualUs` / `perpetualThem` read `StateInfo::checkersBB` only (`position.cpp:2657-2658`, `:2697`, `:2715`); nothing distinguishes direct from discovered checks.

**[obs]** `mx-chk-004` (`b-exp4.py` V3) is a genuine discovered perpetual check: Black's horse vacates d4, extending the black cannon's post-screen ray on the d-file to White's king. Engine: `(True, 32000)` under both the AXF child and the built-in variant — Black, the checker, loses. `mx-chk-003` (V2) is the mirror with White's move *creating* the screen for its own cannon: `(True, -32000)`, Red loses. Both are new mechanisms not covered by the existing `mx-chk-001/002` rook wheel.

### 4.4 PATCH-REQUIRED — attacks by an absolutely pinned attacker

**[src]** The direct-attack path never inspects the chaser's own pin state; `blockers_for_king(~sideToMove)` appears only in the fake-roots path (`position.cpp:3071`).

**[obs]** `b-exp2.py`/`b-fixtures.py` `mx-chs-019`: `2r1k2/7/7/2R4/4c2/7/2K4 w - - 0 1`, moves `c4c3 e3e4 c3c4 e4e3` twice. White's rook shuttles c3↔c4 and "attacks" the black cannon on e3/e4 — but it is absolutely pinned by the black rook on c7 against the white king on c1, so `Rxe3` and `Rxe4` are both illegal. The threat can never be executed at any point in the game, yet the engine returns `(True, -32000)`: **Red loses on a threat that does not exist.**

A Mini Xiangqi player would call this plainly wrong, and it is the same class of error as §2.4. **PATCH-REQUIRED.** Minimal semantics, cheap because the bitboard is already computed:

> When the chasing piece (the mover for direct attacks, or the discovering piece for discovered attacks) is a blocker for its own king, restrict its chasing attacks to the line between its own king and itself.

```
if (blockers_for_king(~sideToMove) & attackerSq)
    attacks &= line_bb(square<KING>(~sideToMove), attackerSq);
```

This is exact for absolute pins: a pinned rook or cannon may capture along the pin line and nowhere else, and a pinned horse can never capture legally (a horse move is never collinear with its origin), which the same expression yields since a horse's attack set never meets that line.

**Residual uncertainty:** the pychess text says only "chases … unprotected piece" and does not define a threat. I am confident on the game-rules point (an unexecutable threat is not a chase) but cannot cite it from the retained source. Evidence that would settle it: an AXF article defining 捉 as a *real* threat to capture.

---

## 5. Question 4 — Mutual and mixed sequences

### 5.1 Adopted rule (liftable prose)

> - The class of a violation is **perpetual check** or **perpetual chase**; there are exactly these two.
> - If both sides commit **perpetual check**, the game is a draw with reason `mutual-perpetual-check`.
> - If both sides commit **perpetual chase** and neither commits perpetual check, the game is a draw with reason `mutual-perpetual-chase`.
> - If one side commits perpetual check, that side loses, **regardless of anything the other side is doing** — including a simultaneous perpetual chase. Perpetual check outranks perpetual chase without exception.
> - A side that alternates between checking and chasing commits neither violation (§3).

### 5.2 Justification and engine behaviour

**[src]** The precedence is structural, not heuristic: the ternary chain at `position.cpp:2704-2707` evaluates the perpetual-check branch first and only reaches the chase branch when **neither** side is perpetually checking. This exactly implements the source's third bullet ("If one side perpetually checks and the other side perpetually chases, the checking side has to stop or be ruled to have lost", `minixiangqi.md:22`) and its fifth ("When both sides violate the same rule … draw", `minixiangqi.md:24`). **ADOPT-ENGINE.**

### 5.3 Mutual perpetual check — constructible; the freeze draft's deferral was wrong

The freeze draft (`fen-notation-fixtures-draft.md`, *Deferred fixtures*) argued mutual perpetual check is not minimally constructible on 7×7, listing capture-with-check, block-with-check and discovered-check shuttles as all failing. **That reasoning does not hold.** A randomised search over 4-ply cycles in which the side to move is in check at every state (`b-search2.py`, 420 000 sampled positions across seven material sets, 95 000 of them legal with White in check) found ten distinct cycles in five of the seven sets — it is a family, not a fluke. The smallest, after hand-minimisation to six pieces:

```
mx-mix-001   3c3/7/2k3C/3n3/4N2/7/3K3 w - - 0 1
             e3d5 d4f5 d5e3 f5d4   e3d5 d4f5 d5e3 f5d4
7  . . . c . . .
6  . . . . . . .
5  . . k . . . C     White: Kd1 Ne3 Cg5
4  . . . n . . .     Black: kc5 nd4 cd7
3  . . . . N . .
2  . . . . . . .
1  . . . K . . .
   a b c d e f g
```

The motif the search found, and which the freeze draft's case analysis missed, is a **double cannon battery in which each horse is simultaneously its own cannon's screen and the enemy cannon's disruptor**:

- White is in check: cd7 uses Black's own nd4 as its screen and bears on Kd1.
- `e3d5` parries by adding a *second* piece to the d-file (a cannon needs exactly one screen), and in the same move becomes the screen for Cg5, which now bears on kc5 — check.
- `d4f5` parries the same way on rank 5, and by vacating d4 restores cd7's post-screen ray to Kd1 — check.
- `d5e3` removes White's own extra d-file blocker, and Cg5 now checks through f5.
- `f5d4` removes Black's extra rank-5 blocker, and cd7 checks through d5.

**[obs]** The harness prints the side to move in check at all nine plies of the doubled cycle. Engine: `(True, 0)` at the third occurrence, `(False, …)` at the second. The two deletion controls make the mutual-branch attribution airtight: remove the black cannon (`mx-chk-003`) and White alone perpetually checks — `(True, -32000)`, Red loses; remove the white cannon (`mx-chk-004`) and Black alone does — `(True, 32000)`, Black loses. Both controls also hold under the **built-in** variant, so mutual perpetual check needs no AXF-specific behaviour.

### 5.4 Mutual perpetual chase — constructible

**[obs]** `b-exp2.py` L1 (`mx-mix-002`): `3k3/7/1NR4/3r3/1N2rn1/2KR3/5n1 w - - 0 1`, moves `c5c3 e3e1 c3c5 e1e3` twice. Each side owns two horses and one shuttling rook; the rook alternately unblocks each horse's leg so that a horse attack on the enemy rook is renewed every move (horse-attacks-chariot is an unconditional chase, §7). Engine: `(True, 0)`. Deletion controls: remove Black's horse f3 → `(True, -32000)` (Red alone chases, Red loses); remove White's horse b5 → `(True, 32000)` (Black alone chases, Black loses). The mutual attribution is therefore proven, not assumed.

### 5.5 Check-over-chase precedence — also constructible; the second deferred fixture is closed too

The structural difficulty here is real and worth stating, because it explains why the construction looks the way it does. If one side perpetually checks, the other is in check at every one of its turns, so **the chaser is necessarily the checked side** and every one of its moves must both parry and chase. Parrying by capture resets `rule50` and makes the position unrepeatable, so only king moves and blocks are available; and a king move can chase only by discovery, which is impossible for a wazir king shuttling between two orthogonally adjacent squares `k0,k1` against a fixed target `W` — for a slider discoverer `W` would have to lie on a line through both, i.e. on the single line containing `k0` and `k1`, and a king moving *along* that line never leaves the blocking segment; for a horse-leg discoverer `W` would have to be a diagonal neighbour of both, and two orthogonally adjacent squares share none.

**The resolution is a blocking parry that chases.** A randomised search (`b-search3.py`, 4-ply cycles where White checks on every move, Black never replies with a king move, plus an automatic one-piece deletion control) found one. Minimised to **five pieces**:

```
mx-mix-004   3k3/7/1r3N1/7/7/2K4/3C3 w - - 0 1
             f5d6 b5d5 d6f5 d5b5   f5d6 b5d5 d6f5 d5b5
7  . . . k . . .
6  . . . . . . .
5  . r . . . N .     White: Kc2 Nf5 Cd1
4  . . . . . . .     Black: kd7 rb5
3  . . . . . . .
2  . . K . . . .
1  . . . C . . .
   a b c d e f g
```

- White's cannon on d1 checks the black king on d7 whenever **exactly one** piece stands on the d-file between them. `f5d6` puts White's horse there — check. Black parries by *adding a second blocker*, `b5d5`; the cannon now has two screens and no check. `d6f5` removes White's own blocker, leaving Black's rook as the single screen — check again. `d5b5` empties the file, so the black king itself is the first piece and only a screen. White therefore checks after every White move and Black parries after every Black move: `perpetualUs` holds, `perpetualThem` does not.
- Black's rook simultaneously hunts White's horse. `b5d5` attacks d6 up the d-file (direct path; the rank-5 line of travel is discarded but the d-file attack is not). `d5b5` attacks f5 along rank 5 — discarded by `line_bb` in the direct path, and re-admitted through the **mover-as-its-own-discovery-candidate** route described in §1.2, because from b5 that attack was blocked by the rook's own former square d5. The horse is undefended on both squares, so both moves chase it, and `undo_move_board` tracks it through White's own moves.

**[obs]** Engine at the third occurrence: `(True, -32000)` — **Red, the checking side, loses**, exactly as the source's third bullet requires, even though Black is simultaneously chasing. Identical under the built-in variant, because the check branch never reads the chase bitboards.

**The chase component is proven by a control**, not asserted. Delete White's cannon (`mx-chs-024`, `3k3/7/1r3N1/7/7/2K4/7 w - - 0 1`, same eight plies): now nobody is ever in check, and the engine returns `(True, 32000)` under the AXF child versus `(True, 0)` under the built-in — an AXF-only adjudication, i.e. a chase, and **Black loses**. Removing any other piece of the original position does not change the base result, so the five-piece skeleton is minimal.

**One honest caveat.** Black's ply-4 renewal depends on the engine's renewal test being "did this move change what this piece attacks *from where it now stands*" rather than "did this attack exist anywhere before" — the rook already attacked f5 from d5. I recommend adopting the engine's test (§3.1, §9), and `mx-chs-024` is the fixture that pins it; a reviewer who prefers the stricter reading should reject `mx-chs-024` and demote `mx-mix-004`'s rationale to "White perpetually checks; Black's simultaneous activity does not disturb the result". The *result* asserted by `mx-mix-004` is unchanged either way, because perpetual check outranks chase unconditionally.

---

## 6. Question 5 — The terminal boundary

### 6.1 Adopted rule (liftable prose)

> A perpetual chase is *sustained* across the three occurrences when **one and the same chased piece** has its attack renewed (§3.1) by **every** move of the chasing side made strictly after the first of the three occurrences. The chased piece is identified as a piece, not as a square: it may move between occurrences. Neither the chasing piece nor the attacking square need be the same from move to move, and the chase may be delivered by different pieces on different moves.
>
> A perpetual check is sustained when the checked side is in check at **every** one of its turns from the first of the three occurrences onward. Which piece gives the check, and whether the check is direct or discovered, is irrelevant.
>
> Only the class of violation and the identity of the violating side determine the result. The moves made before the first of the three occurrences are not part of the test.

### 6.2 PATCH-REQUIRED — the window is one move too wide for one parity

**[src]** §1.3: `chaseThem` is intersected with the chased set of the move that *created* the first occurrence; `chaseUs` is not. The `i != pliesFromNull` guard masks the difference only when the recorded history starts exactly at that occurrence — which is true of every fixture in the current approved set and false of every real game.

**[obs]** The cleanest possible differential, `b-exp3.py` N3 versus `b-exp1.py`/`b-fixtures.py` `mx-chs-021`. Both have the same three occurrences of the same position, the same four chasing moves inside the window, and differ in exactly one earlier ply:

| id | ply-1 move | chases? | engine at ply 9 |
|---|---|---|---|
| `mx-chs-022` (N3) | `b3a3` (rook steps sideways onto the a-file, attacking a5) | yes | `(True, 32000)` — Red loses |
| `mx-chs-021` (N1) | `a1a3` (rook steps *along* the a-file to a3; it attacked a5 from a3 under the pre-move occupancy too, so neither the direct path nor the self-discovery path counts it) | no | `(True, 0)` — draw |

The wheel from occurrence 1 onward is byte-identical in both. **The same perpetual chase is a loss or a draw depending on a move that precedes the counted window.** And it is parity-dependent: `b-exp1.py` G1 shows the mirrored case in the other phase (chaser to move at detection) still yields the loss, because `chaseUs` has the correct window.

**PATCH-REQUIRED.** Minimal semantics:

> The chase-persistence test for the side that is *not* to move must span exactly the chasing moves strictly after the first of the three occurrences — the same four-move span the side-to-move test already uses.

Implementation-wise this means deferring the final `chaseThem` intersection past the repetition test, mirroring how `chaseUs` is already updated after it, and dropping the now-unnecessary `i != pliesFromNull` special case.

### 6.3 Everything else here is ADOPT-ENGINE

The "same target piece, any attacker" semantics is a literal reading of the source's "chases **any one** unprotected piece **with one or more pieces**" (`minixiangqi.md:21`); likewise "perpetual checks **with one piece or several pieces**" (`:20`). Fixtures `mx-chs-001` and `mx-chs-004` already pin that the target square may change; `mx-chs-017` pins that the attacker may change; `mx-chs-018` pins that the target may not.

---

## 7. Question 6 — Target and attacker classes

### 7.1 Adopted rule (liftable prose)

> **Targets.** Kings and soldiers are never chase targets. A piece of the **same type** as the attacking piece is not a chase target, because the attack is mutual — unless that piece is pinned and so cannot answer the attack. Any other piece is a chase target when it is unprotected (§2).
>
> **Value.** Independently of protection, a **horse or cannon attacking a chariot** is always a chase: the exchange wins material even if the chariot is defended. No other value relation overrides protection in Mini Xiangqi.
>
> **Attackers.** A move by a king or a soldier never creates a chase, whether or not it attacks an eligible target. A chase may be created by a stationary piece whose line or leg the move opened.

### 7.2 Engine behaviour and judgement

| rule | source location | probe | engine | class |
|---|---|---|---|---|
| kings never targets | `position.cpp:2988` | — | yes | ADOPT |
| soldiers never targets | `position.cpp:2985-2990` + `promotedSoldiersChaseable` | existing `mx-chs-003` | **needs the fork property set to `false`** | PATCH (landed) |
| same-type target excluded | `position.cpp:3016` | `b-exp2.py` I1 | draw | ADOPT |
| …unless pinned | `position.cpp:3016` | `b-exp2.py` I2 | violation | ADOPT |
| horse/cannon vs chariot always a chase | `position.cpp:2997-2998` | `b-exp2.py` H1 (protected chariot → violation) vs H2 (protected cannon → draw) vs `3k3/7/3c3/N6/7/7/4K2 w - - 0 1` with the same wheel (unprotected cannon → violation) | as specified | ADOPT |
| king movers never chase | `position.cpp:3032` | `b-exp2.py` K1 | draw | ADOPT |
| soldier movers never chase | `position.cpp:3032` | `b-exp2.py` J1 | draw | ADOPT |

All **[obs]**.

**On the value rule.** The source's word is "unprotected", full stop, so the horse-versus-defended-chariot case is strictly an addition. I recommend adopting it and saying so in the contract: a chariot attacked by a horse is not meaningfully protected — the defender's recapture still loses the exchange — and the alternative (delete the rule) would make the most common real Xiangqi chase motif a non-violation. This is the one place where I recommend adopting a rule the retained source does not literally support, and the contract should record the reasoning rather than pretend the source says it.

**On the attacker exclusion.** The source's phrase "with one or more pieces, excluding generals and soldiers" (`minixiangqi.md:21`) is grammatically ambiguous between the chasing pieces and the chased piece. The engine implements **both** readings, and both are standard AXF practice. The accepted contract currently states only the target reading; §9 proposes adding the attacker reading, since the engine already enforces it and fixtures `mx-chs-015` / `mx-chs-016` pin it.

### 7.3 The exemption gap in the discovered-check path — PATCH-RECOMMENDED

**[src]** The discovered-check block (`position.cpp:3081-3091`) applies neither `chaseExempt` nor any attacker-type restriction, and the fork's new property is documented as not affecting it (`variants.ini:260`). So a discovered-check battery can put a **soldier** — or in principle the victim's **king** — into the chased set, and the "attacker" there may be a chaser soldier or king. That contradicts both halves of the adopted rule.

I did **not** construct a sustained example, so I cannot say the gap is reachable across three occurrences; it may not be. But the fix is one line and closes a hole in a rule we are otherwise about to freeze:

```
discoveryAttacks &= ~chaseExempt;    // before both uses at :3083 and :3085
```

**PATCH-RECOMMENDED** (low risk, low cost, not blocking). If the reviewer prefers to keep the fork diff minimal, adopting is acceptable provided the contract records that the soldier and king exemptions are enforced everywhere except in this one classifier path.

### 7.4 The fake-roots path — documented, not patched

**[src]** `position.cpp:3056-3074` adds targets with no value ordering, no symmetry exclusion, no attacker-type filter, and — most importantly — **no check that the newly pinned piece was the target's only defender**. It is an over-approximation by construction. Renewing it on every move of a cycle requires a new pin on every move, which in turn needs the chaser to alternate pinning two different defenders of the same target; I did not construct that and consider it unlikely but not impossible. **ADOPT-ENGINE with the limitation documented**; revisit if a fixture ever exposes it.

---

## 8. Summary of classifications

| # | question | classification |
|---|---|---|
| 1 | Protection | **ADOPT-ENGINE** for the definition (X-ray, soldier defenders, pinned defenders, king + flying general); **PATCH-REQUIRED** for the flying-general false pin (§2.4); ADOPT-with-documentation for the non-flying-general illegal recapture (§2.5) |
| 2 | Interruption | **ADOPT-ENGINE** in full |
| 3 | Discovered / pinned attacks | **ADOPT-ENGINE** for discovered attacks and discovered checks; **PATCH-REQUIRED** for attacks by an absolutely pinned attacker (§4.4) |
| 4 | Mutual and mixed | **ADOPT-ENGINE** in full. Both fixtures the freeze draft deferred as non-constructible are constructed here: mutual perpetual check (`mx-mix-001`, six pieces) and check-over-chase precedence (`mx-mix-004`, five pieces) |
| 5 | Terminal boundary | **ADOPT-ENGINE** for the semantics; **PATCH-REQUIRED** for the one-move-too-wide window in one parity (§6.2) |
| 6 | Target and attacker classes | **ADOPT-ENGINE**; the soldier-target patch has landed (set `promotedSoldiersChaseable = false`); **PATCH-RECOMMENDED** for the discovered-check exemption gap (§7.3) |

### 8.1 Consolidated fork patch list

| # | patch | why | risk |
|---|---|---|---|
| P0 | (landed) `promotedSoldiersChaseable`; the app variant must set it to `false` | contract: soldiers are not chase targets | none |
| P1 | flying-general pin must consider pieces of **both** colours between the kings | removes a false terminal loss (`mx-chs-020`) | two lines, local |
| P2 | `chaseThem` must span only the chasing moves strictly inside the three-occurrence window | removes a parity-dependent missed violation (`mx-chs-021`) | small, in the repetition loop; needs care not to disturb `chaseUs` |
| P3 | a pinned chaser's attacks are restricted to its pin line | removes a false terminal loss on an unexecutable threat (`mx-chs-019`) | ~3 lines, uses an already-computed bitboard |
| P4 | apply `chaseExempt` in the discovered-check path | closes the king/soldier exemption hole | one line |

P1 and P3 remove false **losses**; P2 restores a missed loss. P1–P3 all touch behaviour a player can see and are the ones I would insist on. P4 is insurance.

---

## 9. Proposed contract wording

For `docs/xiangqi-rules.md`, replacing the **Need to discuss** bullets. Additions to the existing accepted text are marked *(new)*.

> **Chase targets and chasing pieces.** *(new: second sentence)* Kings and soldiers are excluded as perpetual-chase targets. A move by a king or a soldier never creates a chase, although a king's or soldier's move may open the line or leg of another piece and create a chase by that piece. A piece of the same type as the attacking piece is not a chase target, because such attacks are mutual, unless it is pinned and therefore cannot answer the attack. Independently of protection, an attack by a horse or a cannon on a chariot is always a chase.
>
> **Protection.** A chased piece is protected when, after the chasing capture, some other piece of the chased side could legally capture on that square. Occupancy for this test excludes the chasing piece, so a defender whose line runs through it counts. A pinned defender — pinned against its own king or by the flying-general rule — does not protect. Soldiers do protect. The king protects only squares inside its own palace, and does not protect when its recapture would leave the kings facing on an otherwise empty file. *(new)* Where a king's recapture would be illegal for any other reason, this contract treats the piece as protected; this is a deliberate simplification pinned by fixture `mx-chs-023`.
>
> **Persistence and interruption.** A violation is evaluated over the whole span of moves from the first of the three occurrences of the repeated position to the position on the board. A perpetual chase requires that every move of the chasing side in that span renews the attack on the same chased piece — followed through its own moves, so it may change square. A move renews the attack when the attacking piece, from the square it occupies after the move, attacks the chased piece and did not do so from that square before the move, or when the move opens another piece's line or leg onto the chased piece; the chasing piece and the attacked square may change from move to move. A perpetual check requires the checked side to be in check at every one of its turns in that span; direct and discovered checks count alike. A single move that does not renew the violation ends it, and the repetition is then neutral. Chasing two different pieces alternately is not a perpetual chase; alternating between checking and chasing is neither violation.
>
> **Threats.** A discovered attack is a chase by the side that moved. An attack by a piece that could not legally make the capture — in particular a piece absolutely pinned against its own king, when the capture square is off the pin line — is not a chase.
>
> **Mutual and mixed sequences.** There are exactly two violation classes, perpetual check and perpetual chase. Both sides committing the same class is a draw, with reason `mutual-perpetual-check` or `mutual-perpetual-chase`. If either side commits perpetual check, that side loses, regardless of what the other side is doing; perpetual check outranks perpetual chase without exception.

---

## 10. Proposed fixtures

Identifiers continue the existing series. I propose one **new area prefix**, `mx-mix-*`, for sequences whose outcome is a property of *both* sides' behaviour: mutual violations and check-over-chase precedence. Justification: the README's area vocabulary maps prefix to topic, the reserved reason identifiers `mutual-perpetual-check` / `mutual-perpetual-chase` are already distinct from `perpetual-check` / `perpetual-chase`, and filing a mutual-check fixture under `mx-chk-*` would misfile it under a unilateral heading. This requires a one-line addition to `fixtures/rules/README.md`.

Every start FEN below round-trips byte-identically through the engine, every move is legal at its turn, and every `boundary` prefix is confirmed not yet an optional end (`b-fixtures.py`). Columns: **state/reason** is the *adopted contract* expectation; **engine** is the observed AXF-child result at the final ply.

`M8(x,y,z,w)` abbreviates the four-move cycle `x y z w` written twice (eight plies, three occurrences at plies 0/4/8, `boundary.prefix_len = 4`).

### 10.1 Protection

| id | start_fen | moves | result_fen | state / reason | engine |
|---|---|---|---|---|---|
| `mx-chs-005` pinned defender does not protect | `4k2/7/c3r2/7/1R5/7/2K1R2 w - - 0 1` | M8(b3a3,a5b5,a3b3,b5a5) | same, `w - - 8 5` | black-wins / perpetual-chase @3 | agrees |
| `mx-chs-006` chase base for the c-file family | `3k3/4R2/2c4/7/7/7/2K4 w - - 0 1` | M8(e6e5,c5c6,e5e6,c6c5) | same, `w - - 8 5` | black-wins / perpetual-chase @3 | agrees |
| `mx-chs-007` X-ray defender through the attacker protects | `3k3/4R2/2c3r/7/7/7/2K4 w - - 0 1` | M8(e6e5,c5c6,e5e6,c6c5) | same, `w - - 8 5` | claimable-draw / threefold-repetition @3 | agrees |
| `mx-chs-008` king sole defender, flying general voids recapture | `2k4/4R2/2c4/7/7/7/2K4 w - - 0 1` | M8(e6e5,c5c6,e5e6,c6c5) | same, `w - - 8 5` | black-wins / perpetual-chase @3 | agrees |
| `mx-chs-009` king sole defender, recapture legal | `2k4/4R2/2c4/7/7/7/3K3 w - - 0 1` | M8(e6e5,c5c6,e5e6,c6c5) | same, `w - - 8 5` | claimable-draw / threefold-repetition @3 | agrees |
| `mx-chs-010` a soldier is a valid defender | `3k3/1p2R2/2c4/7/7/7/2K4 w - - 0 1` | M8(e6e5,c5c6,e5e6,c6c5) | same, `w - - 8 5` | claimable-draw / threefold-repetition @3 | agrees |
| `mx-chs-023` adopted limit: king recapture illegal for a non-flying-general reason still counts as protection | `2k4/4R2/2c4/1N5/7/7/3K3 w - - 0 1` | M8(e6e5,c5c6,e5e6,c6c5) | same, `w - - 8 5` | claimable-draw / threefold-repetition @3 | agrees |

These seven form one differential chain on a single geometry, so a reviewer can check each rule by comparing two adjacent rows: 006 → 007 adds the black chariot g5; 006 → 010 adds the black soldier b6; 006 → 008 moves the black king d7→c7; 008 → 009 moves the white king c1→d1; 009 → 023 adds the white horse b4. Nothing else changes anywhere in the chain.

### 10.2 Target, attacker and value classes

| id | start_fen | moves | state / reason | engine |
|---|---|---|---|---|
| `mx-chs-011` horse chasing a **protected chariot** is a chase | `3k3/7/3r2r/N6/7/7/4K2 w - - 0 1` | M8(a4c3,d5c5,c3a4,c5d5) | black-wins / perpetual-chase @3 | agrees |
| `mx-chs-012` horse chasing a **protected cannon** is not | `3k3/7/3c2r/N6/7/7/4K2 w - - 0 1` | M8(a4c3,d5c5,c3a4,c5d5) | claimable-draw / threefold-repetition @3 | agrees |
| `mx-chs-013` chariot vs chariot is a mutual attack, not a chase | `3k3/7/3r3/R6/7/7/2K4 w - - 0 1` | M8(a4a5,d5d4,a5a4,d4d5) | claimable-draw / threefold-repetition @3 | agrees |
| `mx-chs-014` …unless the same-type target is pinned | `3k3/7/3r3/R6/7/7/2KR3 w - - 0 1` | M8(a4a5,d5d4,a5a4,d4d5) | black-wins / perpetual-chase @3 | agrees |
| `mx-chs-015` a soldier's move never chases | `4k2/7/7/c6/1P5/7/2K4 w - - 0 1` | M8(b3a3,a4b4,a3b3,b4a4) | claimable-draw / threefold-repetition @3 | agrees |
| `mx-chs-016` a king's move never chases | `4k2/7/7/7/2c4/2K4/7 w - - 0 1` | M8(c2d2,c3d3,d2c2,d3c3) | claimable-draw / threefold-repetition @3 | agrees |

### 10.3 Discovery, interruption, and persistence

| id | start_fen | moves | state / reason | engine |
|---|---|---|---|---|
| `mx-chs-017` pure discovered chase; the target never moves and the chasing piece changes every move | `4k2/7/R2n3/7/3N3/7/2KR3 w - - 0 1` | M8(d3c5,e7e6,c5d3,e6e7) | black-wins / perpetual-chase @3 | agrees |
| `mx-chs-018` chasing two different pieces alternately is no violation | `4k2/3n3/2c4/2R4/7/7/3K3 w - - 0 1` | M8(c4d4,e7e6,d4c4,e6e7) | claimable-draw / threefold-repetition @3 | agrees |
| `mx-chs-022` chase adjudicated with the chaser **not** to move at the third occurrence | `4k2/7/c6/7/1R5/7/2K4 w - - 0 1` | `b3a3` + M8(a5b5,a3b3,b5a5,b3a3); `boundary.prefix_len = 5`; result_fen `4k2/7/c6/7/R6/7/2K4 b - - 9 5` | black-wins / perpetual-chase @3 | agrees |

### 10.4 Patch-gating fixtures (engine currently **diverges**)

| id | start_fen | moves | state / reason | engine now | patch |
|---|---|---|---|---|---|
| `mx-chs-019` an absolutely pinned chariot's "threat" is not a chase | `2r1k2/7/7/2R4/4c2/7/2K4 w - - 0 1` | M8(c4c3,e3e4,c3c4,e4e3) | claimable-draw / threefold-repetition @3 | `(True,-32000)` Red loses | **P3** |
| `mx-chs-020` no flying-general pin exists when a piece of either colour blocks the file | `2k4/7/R6/2r4/2N4/7/2K4 w - - 0 1` | M8(a5a4,c4c5,a4a5,c5c4) | claimable-draw / threefold-repetition @3 | `(True,-32000)` Red loses | **P1** |
| `mx-chs-021` the chase test must not reach behind the first occurrence | `4k2/7/c6/7/7/7/R1K4 w - - 0 1` | `a1a3` + M8(a5b5,a3b3,b5a5,b3a3); `boundary.prefix_len = 5`; result_fen `4k2/7/c6/7/R6/7/2K4 b - - 9 5` | black-wins / perpetual-chase @3 | `(True,0)` draw | **P2** |

`mx-chs-021` and `mx-chs-022` are a matched pair and must be reviewed together: identical three occurrences, identical chasing wheel, one differing earlier ply.

### 10.5 Perpetual check and cross-class outcomes

| id | start_fen | moves | in_check | state / reason | engine |
|---|---|---|---|---|---|
| `mx-chk-003` perpetual check by a cannon battery the checking move itself completes | `7/7/2k3C/3n3/4N2/7/3K3 w - - 0 1` | M8(e3d5,d4f5,d5e3,f5d4) | false | black-wins / perpetual-check @3 | agrees (also under built-in) |
| `mx-chk-004` perpetual **discovered** check | `3c3/7/2k4/3n3/4N2/7/3K3 w - - 0 1` | M8(e3d5,d4f5,d5e3,f5d4) | true | red-wins / perpetual-check @3 | agrees (also under built-in) |
| `mx-mix-001` mutual perpetual check | `3c3/7/2k3C/3n3/4N2/7/3K3 w - - 0 1` | M8(e3d5,d4f5,d5e3,f5d4) | true | draw / mutual-perpetual-check @3 | agrees (also under built-in) |
| `mx-mix-002` mutual perpetual chase | `3k3/7/1NR4/3r3/1N2rn1/2KR3/5n1 w - - 0 1` | M8(c5c3,e3e1,c3c5,e1e3) | false | draw / mutual-perpetual-chase @3 | agrees |
| `mx-mix-003` alternating check and chase by one side is neither violation | `3k3/7/2c4/2R4/7/7/4K2 w - - 0 1` | M8(c4d4,d7c7,d4c4,c7d7) | false | claimable-draw / threefold-repetition @3 | agrees |
| `mx-mix-004` check outranks chase: White perpetually checks while Black perpetually chases | `3k3/7/1r3N1/7/7/2K4/3C3 w - - 0 1` | M8(f5d6,b5d5,d6f5,d5b5) | false | black-wins / perpetual-check @3 | agrees (also under built-in) |
| `mx-chs-024` the same eight plies with White's cannon deleted: Black's chase alone | `3k3/7/1r3N1/7/7/2K4/7 w - - 0 1` | M8(f5d6,b5d5,d6f5,d5b5) | false | red-wins / perpetual-chase @3 | agrees (AXF only; built-in draws, as expected) |

`mx-chk-003`, `mx-chk-004` and `mx-mix-001` are the same six-piece skeleton with one cannon removed, present, or both present; reviewing them as a trio is what makes the mutual attribution checkable by hand. `mx-mix-004` and `mx-chs-024` are the same five-piece skeleton with and without White's cannon, and must likewise be reviewed together: `mx-chs-024` is what proves the chase in `mx-mix-004` is real rather than assumed. Likewise `mx-mix-002` should be reviewed with its two deletion controls recorded in §5.4 (those two are engine evidence, not proposed fixtures).

### 10.6 Three fixtures in full schema form

```json
{
  "id": "mx-chs-008",
  "title": "King as sole defender does not protect when the flying general voids the recapture",
  "area": "chs",
  "variant": "minixiangqi",
  "start_fen": "2k4/4R2/2c4/7/7/7/2K4 w - - 0 1",
  "moves": ["e6e5", "c5c6", "e5e6", "c6c5", "e6e5", "c5c6", "e5e6", "c6c5"],
  "assertions": {
    "in_check": false,
    "result_fen": "2k4/4R2/2c4/7/7/7/2K4 w - - 8 5",
    "legal_moves": null,
    "rejected_moves": null,
    "applied": null,
    "game_state": { "state": "black-wins", "reason": "perpetual-chase", "at_occurrence": 3 }
  },
  "boundary": { "prefix_len": 4, "expect": "second occurrence; not yet terminal" },
  "rationale": "The rook alternately attacks the black cannon on c5 (from e5, along rank 5) and on c6 (from e6, along rank 6). On c5 the cannon is undefended; on c6 only the black king on c7 defends it, and the black king cannot recapture on c6 because the white king on c1 would then face it down an otherwise empty c-file. The target is unprotected on both squares, so the chase is sustained and the chasing side loses at the third occurrence. mx-chs-009 is the same position with the white king on d1, where the recapture is legal and the repetition is neutral."
}
```

```json
{
  "id": "mx-mix-001",
  "title": "Mutual perpetual check is a draw",
  "area": "mix",
  "variant": "minixiangqi",
  "start_fen": "3c3/7/2k3C/3n3/4N2/7/3K3 w - - 0 1",
  "moves": ["e3d5", "d4f5", "d5e3", "f5d4", "e3d5", "d4f5", "d5e3", "f5d4"],
  "assertions": {
    "in_check": true,
    "result_fen": "3c3/7/2k3C/3n3/4N2/7/3K3 w - - 8 5",
    "legal_moves": null,
    "rejected_moves": null,
    "applied": null,
    "game_state": { "state": "draw", "reason": "mutual-perpetual-check", "at_occurrence": 3 }
  },
  "boundary": { "prefix_len": 4, "expect": "second occurrence; not yet terminal" },
  "rationale": "Each side owns a cannon battery whose screen is its own horse. Every move both parries the incoming check, by adding or removing a second piece on the checking line so the enemy cannon no longer has exactly one screen, and renews the outgoing check on the other line. The side to move is in check at all nine plies. Both sides commit perpetual check, so the same-class rule makes the game a draw. mx-chk-003 and mx-chk-004 are this position with one cannon deleted and show each side's perpetual check losing on its own."
}
```

```json
{
  "id": "mx-mix-004",
  "title": "Perpetual check outranks a simultaneous perpetual chase by the checked side",
  "area": "mix",
  "variant": "minixiangqi",
  "start_fen": "3k3/7/1r3N1/7/7/2K4/3C3 w - - 0 1",
  "moves": ["f5d6", "b5d5", "d6f5", "d5b5", "f5d6", "b5d5", "d6f5", "d5b5"],
  "assertions": {
    "in_check": false,
    "result_fen": "3k3/7/1r3N1/7/7/2K4/3C3 w - - 8 5",
    "legal_moves": null,
    "rejected_moves": null,
    "applied": null,
    "game_state": { "state": "black-wins", "reason": "perpetual-check", "at_occurrence": 3 }
  },
  "boundary": { "prefix_len": 4, "expect": "second occurrence; not yet terminal" },
  "rationale": "The white cannon on d1 checks the black king on d7 whenever exactly one piece stands between them on the d-file. Red's horse moving to d6 supplies that screen; Black parries by adding a second blocker with the rook on d5; Red withdraws its own blocker so Black's rook becomes the single screen and checks again; Black empties the file. Red therefore checks at every one of Black's turns. In the same moves Black's rook renews an attack on the undefended white horse, on d6 up the d-file and on f5 along rank 5. Both sides are violating, in different classes, and the checking side is the side required to stop: Red loses. mx-chs-024 is this position with the white cannon deleted and shows Black's chase losing on its own, which is what makes the chase component of this fixture real rather than assumed."
}
```

---

## 11. Open items, uncertainty, and what would settle them

1. **Renewal semantics (§1.2, §3.1, §5.5).** The engine's renewal test is "did this move change what this piece attacks *from where it now stands*", not "did this attack exist anywhere before". I recommend adopting it, and `mx-chs-024` is the single fixture whose result depends on it. This is the interpretation I am least able to ground in the retained source. Settled by: an AXF/CXA statement on whether a move that merely maintains an existing threat from a new square counts as 捉.
2. **Combined perpetual check-and-chase by one side (§3.3).** Adopted as *no violation*. This is the recommendation most likely to be wrong. Settled by: an authoritative AXF/CXA text on combined perpetual moves.
3. **Pinned-attacker threat model (§4.4).** I recommend a patch on game-rules grounds; the retained source does not define "chase" as a real threat. Settled by: an AXF definition of 捉.
4. **Reachability of the discovered-check exemption gap (§7.3) and of the fake-roots over-approximation (§7.4).** Neither constructed as a sustained pattern. I do not claim they are unreachable — the mutual-check case shows how badly such claims can go. Settled by: a targeted cycle search with a `chased()` oracle reimplemented in Python and validated against the 24 constructions in this draft.
5. **Auto-terminal versus claim-gated** remains as recorded in the freeze draft; nothing here changes it. Every fixture above states the adopted result at the third occurrence and is silent on the commit mechanism.
6. **Working-tree note.** The Fairy-Stockfish checkout moved from `c19b5f6c` to `77d602e0` (the merged soldier-chase-exemption patch) during this analysis. I made no change to it; I read it only. My pyffish binary predates the merge, so no observation in this draft is affected, but reviewers comparing line numbers against an older checkout should expect a six-line shift inside `chased()`.

## 12. Files

- This draft: `/Users/tianren/coding/minixiangqi/discussion-drafts/rules-edge-cases-design-b.md`
- Harness and experiments: `/Users/tianren/coding/minixiangqi/discussion-drafts/b-probe.py`, `b-exp1.py`, `b-exp2.py`, `b-exp3.py`, `b-exp4.py`, `b-fixtures.py`, `b-search.py`, `b-search2.py`, `b-search3.py`
