# Pre-merge review — PR #22, "Accept three rule interpretations and correct a false claim"

**Reviewer:** independent pre-merge agent, standing in for human review.
**Under review:** `ppppvz/MiniXiangqi` PR #22, branch `design/rules-adjudication`, single commit `e64f176`,
`docs/xiangqi-rules.md` (+13/−4) and `docs/testing.md` (+2/−0).
**Primary source:** `discussion-drafts/rules-edge-cases-reconciliation.md`.
**Also read:** `discussion-drafts/investigate-chase-window-parity.md` (the investigation the PR calls "now running"),
the retained normative snapshot, `Fairy-Stockfish` fork HEAD `77d602e0`, `docs/engine-integration.md` on `main`, PR #21.

Nothing was written outside `discussion-drafts/`. No repository was modified; no GitHub write of any kind.

**Verdict: DO NOT MERGE.** Every factual claim in the diff that I could execute, I reproduced — the
constructibility correction is right, in both halves, with the piece counts as stated. The problems are in the
normative prose: one accepted interpretation is ambiguous in a way that inverts a draw into a loss, the safety
argument that justifies accepting the riskiest interpretation is false in the mutual case, an open question is
closed while the contract still answers a live position class two different ways, and the new open item
understates a defect I reproduced as an auto-terminal wrong decisive result.

---

## 1. Do the three interpretations match what the reconciliation established?

### 1.1 Alternating check and chase (一将一捉) — against D4

The headline sentence is faithful. D4 recommends "adopt the permissive reading — a side alternating check and
chase commits neither violation, pinned by `mx-mix-003`", and the bullet's bolded claim says exactly that. The
"record it as an interpretation, not a reading of the source, so an authoritative AXF or CXA text reopens it as
an amendment" framing is D4's, correctly transposed. No overreach in the headline.

**Finding 1.1a — the explanatory clause describes a different pattern from the one being settled.**

> "a sequence that is a check on one occurrence and a chase on the next sustains neither"

`occurrence` is a defined term in this document — line 59, "three occurrences of the same position"; line 61,
"the third neutral occurrence". Read with the document's own vocabulary, that clause covers only a sequence
whose class changes *between occurrences of the repeated position*. The case actually being settled is
alternation *between the violating side's moves inside one cycle*: the reconciliation records `mx-mix-003`'s
per-ply check flags as `f T f f f T f f f` — Red checks on one of its two moves per cycle and chases on the
other, with occurrences at plies 0/4/8. I re-executed that fixture and reproduced the same flags (§2.5 below).
So the sentence that is supposed to explain the interpretation does not describe the fixture that pins it, and
leaves the within-cycle case — the only case that arises — formally undecided.

Severity: **should-fix**.
Correction: use Q4's move-based wording, which is exact:
"A side whose moves in the span are neither all checks nor all chases of one and the same piece has committed
neither violation; a sequence alternating check and chase is therefore not a violation under this contract."

**Finding 1.1b — the stated basis rests on a premise this document keeps non-normative, and attributes it to
the source.**

> "It is accepted because the source enumerates exactly two classes and defines each as persistent"

The source does enumerate exactly two classes and does describe each as a continuing behaviour (§4 below
verifies this against the retained snapshot). But the premise that does the actual work — that a class must
hold on *every one of the side's moves across the span*, so that one non-conforming move destroys it — is not
in the source. It is Q2, `ADOPT-ENGINE`, an engine-derived reading; and in this same document Q2's subject
matter is still open and explicitly non-normative: "Define how interrupted, discovered, and pinned check/chase
sequences are adjudicated, and how a violation's target and pattern must persist across the three
occurrences." An implementer cannot evaluate "sustains neither" without the span and interruption rules that
the contract says do not authorize implementation.

Severity: **should-fix**.
Correction: either state the persistence premise normatively in the same section ("a side commits perpetual
check only if the other side is in check at every one of its turns in the span, and perpetual chase only if
every one of its own moves in the span renews the attack on one and the same enemy piece"), or attribute the
premise honestly ("because the two classes are read here as behaviours that must hold at every move of the
span, per the interruption reading recorded in the reconciliation").

### 1.2 Chase renewal — against D3, and against the engine at `position.cpp:3044` and `:3050-3052`

D3 recommends adopting the engine's test, worded as "the chasing piece attacks the target from the square it
now occupies, and did not attack it from that square before the move". The PR reproduces that sentence
verbatim in substance. **It does not, however, reproduce Q3's disambiguating sentence**, and without it the
contract line is ambiguous in exactly the case the interpretation exists to decide.

**Finding 1.2a — BLOCKING. The renewal sentence, read plainly, inverts the engine's answer for a chase that
advances along an existing attacking line.**

> "**A chase renews when the chasing piece attacks the target from the square it now occupies and did not
> attack it from that square before the move.**"

Two readings:

- *Counterfactual-occupancy reading* (the engine's): would a piece standing on the destination square have
  attacked the target **in the position as it stood before the move**? This is what `:3050-3052` computes —
  `attacks_bb(…, s, pieces()) & ~attacks_bb(…, s, (captured ? pieces() : pieces() ^ to) ^ from)`.
- *Historical reading* (the plain-English one): did **this piece**, before the move, attack the target from
  that square? The piece was not standing on its destination square before the move, so this is vacuously
  true for every move, and every move that leaves the target attacked renews.

The two readings disagree, and they disagree on a result. Executed differential, same material, same
undefended target, target attacked by the rook after **every** White move in both halves:

```
ACROSS  4k2/7/c6/7/1R5/7/2K4 w   b3a3 a5b5 a3b3 b5a5 ×2   -> (True,-32000)  Red loses
ALONG   4k2/7/c6/7/7/7/R2K3 w   a1a3 e7e6 a3a1 e6e7 ×2   -> (True,0)       DRAW
```

In the ALONG wheel the White rook shuttles a1↔a3, the black cannon never leaves a5, and the rook attacks the
undefended cannon from both squares. The engine rules a claimable draw, because neither rook move creates an
attack that did not already stand from that square — `~line_bb(from, to)` at `:3037` discards it and the exact
before/after test at `:3050-3052` does not re-admit it. Under the historical reading of the accepted sentence,
every White move renews and Red loses the game. A contract line that decides draw-versus-loss cannot be
ambiguous between those two.

The reconciliation is not ambiguous — Q3 continues: "A chasing piece that steps away from a target and still
attacks it from its new square therefore renews the chase, **while a piece that merely advances along a line
on which its attack already stood does not.**" That sentence is the whole discriminator and it was dropped.
It is also load-bearing for the slate: §1 row 3 says `mx-chs-030` and `mx-chs-031` "differ only in whether the
entry move approaches *along* the file or *across* onto it, and the engine treats only the second as a chase".

Severity: **blocking**.
Correction: append Q3's second sentence to the bullet, verbatim.

**Finding 1.2b — the contract's statement is narrower than the engine's actual test, which the reconciliation
describes as a union.** §1 row 3 establishes that the engine's classifier is the *union* of a direct-attack
path (all attacks from `to`, minus `line_bb(from, to)` for a chariot or cannon, and with **no** renewal filter
at all for a horse — `position.cpp:3036-3038`) and the discovery path's exact before/after differential. The
PR states only the second half. In practice the union and the counterfactual reading agree on the cases in the
slate, so I did not find a divergence I could execute; but the contract should not be read as pinning
`:3050-3052` alone when a horse's direct attacks are admitted unconditionally.

Severity: **nit** (subsumed by the 1.2a correction, which makes the discriminating rule explicit).

### 1.3 A general as sole defender — against D5

**The under/over direction is correct.** D5: "the engine models only the flying-general reason a king cannot
recapture, so a chase whose target's only defender is a king that is in truth unable to recapture degrades to a
claimable draw… It is under-detection only." The PR says "This under-detects", and describes the degradation
to "a neutral claimable repetition rather than a loss". Executed and confirmed (§2.6): `mx-chs-011`, where a
white horse on b4 makes the black king's recapture on c6 illegal for a reason other than the flying general,
returns `(True, 0)` — a draw — while the flying-general sibling `mx-chs-009` returns a Red loss and the clean
sibling `mx-chs-010` returns a draw. The direction of the error is under-detection, exactly as written.

**Finding 1.3a — see 3.2: the "never produces a wrong winner" clause is false in the mutual case.**

**Finding 1.3b — the interpretation is a carve-out of a definition the same document declares unresolved, and
does not say so.** The status line still reads "The exact definitions of protection … remain unresolved", and
`Need to discuss` still asks to "Define exactly what makes a chased piece protected or unprotected". The
reconciliation handles this by writing the limit *into* the Q1 protection definition and naming its fixture:
"this contract nevertheless treats the chased piece as protected; this is a deliberate simplification, pinned
by `mx-chs-011`." The PR takes the limit without the definition and without the fixture.

Severity: **should-fix**.
Correction: add "This is a stated limit on the still-unresolved definition of protection, to be pinned by the
deferred edge-case fixture for a king recapture that is illegal for a non-flying-general reason", and scope
the status line's "remain unresolved" clause with "except as settled by the accepted interpretations above".

---

## 2. Verifying the constructibility correction against the engine

**Result: both halves of the correction reproduce exactly as stated. This part of the PR is sound.**

### 2.1 Build used

No build was needed. `discussion-drafts/r-scratch/pyffish.cpython-314-darwin.so` is the reconciliation's own
build from fork HEAD `77d602e0`, and it loads and self-identifies correctly:

```
$ cd /Users/tianren/coding/minixiangqi/discussion-drafts && python3 rv22-verify.py
pyffish (0, 0, 89) Fairy-Stockfish 270726 LB by Fabian Fichter
```

Variant registered for every run below (the target app variant, per the reconciliation's §0):

```ini
[minixiangqitarget:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
```

Scripts written for this review, both under `discussion-drafts/`: `rv22-verify.py`, `rv22-renewal.py`.
`is_optional_game_end` returns a side-to-move-relative value; the `LOSER=` column translates it.

### 2.2 Claim: mutual perpetual check is constructible in six pieces

```
=== mx-mix-001 mutual perpetual check ===
  fen    : 3c3/7/2k3C/3n3/4N2/7/3K3 w - - 0 1   (6 pieces)
  moves  : e3d5 d4f5 d5e3 f5d4 e3d5 d4f5 d5e3 f5d4   (8 plies)
  legal  : all 8 plies legal in minixiangqitarget
  check  : TTTTTTTTT   (side-to-move in check, ply 0..8)
  ply 4    target=(False,-)  axf=(False,-)  builtin=(False,-)
  ply 8    target=(True,0) [DRAW]  axf=(True,0)  builtin=(True,0)
```

Six pieces, counted from the FEN. The side to move is in check at every one of the nine plies. The third
occurrence is at ply 8 and nothing fires at ply 4, so the adjudication point is right. Attribution is proved by
the sibling trio on the same skeleton — delete one cannon and the mutual draw becomes a unilateral loss for
whichever side still checks:

```
=== mx-chk-003 (white cannon only) ===  check: fTfTfTfTf   ply 8 -> (True,-32000) [LOSER=Red]
=== mx-chk-004 (black cannon only) ===  check: TfTfTfTfT   ply 8 -> (True,32000)  [LOSER=Black]
```

**Reproduced.** The PR's "mutual perpetual check in six pieces, with the side to move in check at every ply of
the cycle" is accurate.

### 2.3 Claim: check-over-chase precedence is constructible in five pieces, with a control

```
=== mx-mix-004 check-over-chase precedence ===
  fen    : 3k3/7/1r3N1/7/7/2K4/3C3 w - - 0 1   (5 pieces)
  moves  : f5d6 b5d5 d6f5 d5b5 f5d6 b5d5 d6f5 d5b5   (8 plies)
  legal  : all 8 plies legal in minixiangqitarget
  check  : fTfTfTfTf
  ply 4    target=(False,-)  axf=(False,-)  builtin=(False,-)
  ply 8    target=(True,-32000) [LOSER=Red]  axf=(True,-32000)  builtin=(True,-32000)

=== mx-chs-027 control (cannon deleted) ===
  fen    : 3k3/7/1r3N1/7/7/2K4/7 w - - 0 1   (4 pieces)
  check  : fffffffff
  ply 8    target=(True,32000) [LOSER=Black]  axf=(True,32000)  builtin=(True,0)
```

Five pieces. Red checks on every one of its moves (`fTfTfTfTf`) and loses, which is precedence. The control
proves Black's chase is real and is a chase: deleting the white cannon leaves a position with no check on any
ply in which Black loses under the AXF variants and draws under built-in `minixiangqi`, which has no chasing
rule — so the decisive value comes from the chase classifier, not from anything else.

**Reproduced.** The PR's "check-over-chase precedence in five, with a control position proving the chase
component real" is accurate.

### 2.4 Claim: the removed statement was wrong

The removed sentence said the two outcomes yielded no minimal construction. Both constructions exist, are
legal, and produce the asserted results on the engine the app will ship. The replacement's account of *why*
the old claim was wrong ("a case analysis that ruled out only general-move discoveries, together with a
negative search its own author correctly labelled strong evidence rather than proof") matches the
reconciliation's §1 row 1 verbatim in substance. **No blocking finding in item 2.**

### 2.5 Supporting run — the fixture that pins interpretation 1

```
=== mx-mix-003 alternating check and chase ===
  fen    : 3k3/7/c6/R6/7/7/4K2 w - - 0 1
  moves  : a4d4 d7c7 d4a4 c7d7 ×2
  check  : fTfffTfff
  ply 8    target=(True,0) [DRAW]  axf=(True,0)  builtin=(True,0)
```

The check flags match the reconciliation's `f T f f f T f f f` exactly. **The engine does agree with
interpretation 1**, so the PR description's "because the engine agrees" is supported (item 4 asked; the
document text itself wisely does not lean on engine agreement).

### 2.6 Supporting run — the fixtures that pin interpretation 3

```
mx-chs-009  2k4/4R2/2c4/7/7/7/2K4 w    e6e5 c5c6 e5e6 c6c5 ×2  -> (True,-32000) [LOSER=Red]
mx-chs-010  2k4/4R2/2c4/7/7/7/3K3 w    (same moves)            -> (True,0) [DRAW]
mx-chs-011  2k4/4R2/2c4/1N5/7/7/3K3 w  (same moves)            -> (True,0) [DRAW]
```

`mx-chs-011` is the interpretation: strictly the chased cannon is unprotected, because the horse on b4 makes
the king's recapture on c6 illegal; the engine draws. Under-detection confirmed.

### 2.7 Supporting run — the parity trio, used in items 1 and 5

```
mx-chs-030  4k2/7/c6/7/7/7/R1K4 w  a1a3 + wheel×2   (9 plies)  -> (True,0)       DRAW
mx-chs-031  4k2/7/c6/7/1R5/7/2K4 w b3a3 + wheel×2   (9 plies)  -> (True,32000)  [LOSER=Red]
mx-chs-032  4k2/7/c6/7/7/7/R1K4 w  a1a3 + wheel×2 + a5b5 (10)  -> (True,-32000) [LOSER=Red]
```

Identical start, identical entry move and identical judged moves in 030 and 032; the answer flips on parity.

---

## 3. Mutual consistency, and consistency with the rest of the accepted contract

### 3.1 BLOCKING — the PR closes the mutual/mixed open question while the contract still answers one position class two different ways

> "The mutual and mixed cases are settled at the rule level by the accepted outcomes and interpretations
> above; what remains for them is their fixtures."

Take a side that, on every one of its moves in the span, both gives check and renews an attack on one and the
same unprotected enemy piece, while the other side perpetually chases. Two accepted lines fire:

- line 66 — "When one side perpetually checks and the other perpetually chases, the checking side is the side
  required to stop and loses if the violation is completed." → the checker loses.
- line 67 — "When both sides commit the same class of perpetual violation, the result is a draw." Both sides
  are committing perpetual chase, which is a class both commit. → draw.

The contract gives no precedence between them. The engine does — `position.cpp:2704-2705` tests
`perpetualThem || perpetualUs` first and only falls through to `chaseThem || chaseUs` when neither side is
perpetually checking, so a perpetual checker loses regardless of any simultaneous chase — and the
reconciliation lifts that into contract prose in Q4: "If one side commits perpetual check, that side loses
regardless of what the other side is doing, including a simultaneous perpetual chase: perpetual check
outranks perpetual chase without exception." **That sentence is exactly what is missing, and it is the sentence
that makes the claim of settledness true.**

The class is not hypothetical: a single move can be both a check and a chase. In `mx-mix-004`, White's `f5d6`
gives check (flag `T` at ply 1, verified above) and simultaneously attacks the black chariot then standing on
b5 — the horse's `d6b5` is a legal horse move with a free leg, confirmed against the engine's move list. I did
not construct a full witness in which one side does both on *every* move; the point stands regardless, because
the PR asserts settledness at the rule level and the rule level is what is silent.

Severity: **blocking**.
Correction: add Q4's precedence sentence to the accepted list (naturally after line 66), then the settledness
claim is earned.

### 3.2 BLOCKING — the safety arguments for interpretations 1 and 3 are false whenever the opponent is itself violating

> interpretation 1: "being wrong here costs a declinable draw rather than a wrongly decided game."
> interpretation 3: "This under-detects: it never produces a wrong winner, only a draw the players may decline."

Both claims are stated unconditionally. Both hold only when the opponent commits no violation. When the
opponent is itself committing the same class, an under-detection of side A's violation does not degrade the
game to a draw — it *promotes* the position from a `mutual-perpetual-chase` draw to a **unilateral,
auto-terminal loss for side B**, which the accepted contract commits without a claim ("A unilateral perpetual
violation becomes terminal automatically… Only neutral repetition is claim-gated", line 62). That is a wrong
winner, and it is unrecoverable.

Concretely for interpretation 1: Red alternates check and chase; Black perpetually chases. The contract as
accepted makes Black the sole violator and ends the game against Black. If the interpretation is wrong — which
the PR itself says is the likely case — the true result is at best a draw and at worst a Red loss. The error
is not a declinable draw; it is a reversed result. For interpretation 3 the same shape: Red's chase is
under-detected, Black is chasing too, the true result is a mutual draw, the delivered result is a Black loss.

This is not a theoretical worry, and the document knows it: the mechanism is the same one the PR's own new
open item records, and I executed it (§5.1) — a mutual chase in which one side's chase set is dropped is
adjudicated as a unilateral loss for the other. The contract cannot rest its acceptance of its riskiest
interpretation on a safety property it elsewhere records as failing.

Severity: **blocking**.
Correction, minimal, both bullets:
- interpretation 1: "…and because, where the opponent is not itself committing a violation, being wrong here
  costs a declinable draw rather than a wrongly decided game; where the opponent is also violating, a wrong
  reading here converts a mutual-violation draw into a unilateral loss, which is the case an amendment would
  have to revisit first."
- interpretation 3: "This under-detects. Against an opponent that is not itself violating it can only produce
  a draw the players may decline; where the opponent is also perpetually chasing it converts a mutual draw
  into a unilateral loss, so the limit is not unconditionally benign."

### 3.3 Consistency checks that pass

I worked through the accepted lines against each interpretation and found no other class with two answers:

- third-occurrence adjudication point (line 59, 62) — interpretations 1 and 2 both quantify over "the three
  occurrences"/"the span" and are consistent with it; executed runs fire at ply 8/9 and not at ply 4/5.
- "Only neutral repetition is claim-gated" (line 62) — interpretation 1 routes the alternating sequence to a
  *neutral* claimable repetition, so it is claim-gated, consistent. Interpretation 3 routes an under-detected
  chase to the same place, consistent.
- kings and soldiers excluded as chase targets (line 65) — no interaction with any of the three.
- mutual same-class draw (line 67) — interactions are 3.1 and 3.2 above; otherwise consistent.
- both sides alternating check and chase → neither violates → neutral claimable repetition; single answer.
- Red alternating, Black perpetually checking → line 63 alone fires; single answer (its *correctness* is the
  3.2 problem, not a contradiction).

### 3.4 Against `docs/engine-integration.md` on `main`, and the interaction with PR #21

`engine-integration.md` on `main` states the target behaviour as "neutral threefold repetition is a draw; a
unilateral perpetual checker or chaser loses; a mutual same-class violation draws; checking takes precedence
over chasing; and kings and soldiers are excluded as chase targets". None of the three interpretations
contradicts it, and — verified in §2 — the current fork already produces all three, so no interpretation in
this PR implies a new fork change. That is worth saying and the PR does not say it.

Two interactions with #21, which I reviewed only as context:

**Finding 3.4a — #21 says the rules basis for two of its fork corrections is in this PR. It is not.**
#21's description: "two corrections for defects that produce false terminal losses — a chaser counted as
chasing while pinned, and a flying-general pin test that does not require the intervening pieces to stand
between the generals… The rules interpretations behind the two adjudication corrections are a separate PR
against `xiangqi-rules.md`." The corresponding rule statements are the reconciliation's Q3 ("An attack by a
piece that could not legally make the capture — in particular a piece absolutely pinned against its own king…
— is not a threat and is not a chase") and Q1 ("A piece is pinned by the flying-general rule only when the two
kings stand on the same file and it is the only piece, **of either colour**, standing between them"). Neither
is in this diff, and the covering `Need to discuss` item ("Define how interrupted, discovered, and pinned
check/chase sequences are adjudicated") is still open and therefore explicitly non-normative. Merging #22 as
written and then #21 leaves an accepted fork change set whose stated rules basis does not exist.
Severity: **should-fix** (on this PR: add the two sentences; or #21's description and scope must change).

**Finding 3.4b — the new open item can add to a fork change set #21 makes accepted.** #21 moves
`engine-integration.md` to accepted with an enumerated fork change set "recorded so the divergence from
upstream is bounded"; the chase-window parity correction is not in it. If the open question added here is
answered "correct it", that enumeration must be reopened. Worth a sentence in one of the two PRs.
Severity: **nit**.

---

## 4. The 一将一捉 interpretation — testing the reasoning independently

### 4.1 Does the retained source enumerate exactly two violation classes and define each as persistent?

**Yes, verified against the retained evidence file itself**, not against a quotation of it.

```
$ shasum -a 256 discussion-drafts/evidence/pychess-minixiangqi-rules-2026-07-26.html
a79b663618033c2a8e4db897b51499d6409ade0543520ee950c9c768eae92077
```

That matches the hash pinned in `docs/xiangqi-rules.md` line 17 byte for byte, so the retained snapshot is
intact. Extracting the section text from the HTML gives five bullets, identical to
`pychess-variants/static/docs/minixiangqi.md:22-26` and to the reconciliation's §0 quotation:

- perpetual **checks** — "can be ruled to have lost unless he or she stops such checking";
- perpetual **chases** of "any one unprotected piece with one or more pieces, excluding generals and
  soldiers" — "will be ruled to have lost unless he or she stops such chasing";
- the cross-class case, the checker must stop;
- neither side violating and both persisting → "can be ruled as a draw";
- both sides violating "the same rule" → "can be ruled as a draw".

Exactly two violation classes; each described as a continuing behaviour that the player is required to stop;
the fifth bullet's "the same rule" confirms the taxonomy is two-valued. No text addresses alternation. The
PR's characterisation of the source is accurate as far as it goes — with the qualification in Finding 1.1b,
that "persistent" in the source does not by itself supply the move-by-move test the interpretation needs.

### 4.2 Does the engine actually agree?

**Yes, executed, not asserted.** `mx-mix-003` returns `(True, 0)` — a neutral draw — under the AXF target
variant, under the plain AXF child, and under built-in `minixiangqi`, with per-ply check flags `fTfffTfff`
confirming that Red really is checking on one move per cycle and not on the other (§2.5). The PR description's
"because the engine agrees" is supported by evidence. The document text does not make the claim, which is
correct discipline given line 21 ("Neither a Fairy-Stockfish search score nor an engine-specific optional
result silently changes user-visible rules") — no finding.

### 4.3 Is the safety property true in every case?

**No.** See Finding 3.2, which is the answer to this question and is graded blocking there. The short form:
treating the alternation as neutral produces a wrong *winner*, not a draw, in every position where the
opponent is itself sustaining a violation of a single class — the contract then reads the position as a
unilateral violation by the opponent and, per line 62, ends the game automatically against them. Nothing in
the three accepted interpretations or in the accepted lines above them prevents that composition; §5.1 shows
the identical draw→unilateral-loss conversion executing on the engine through the parity defect, so the shape
is demonstrated even though I did not construct a witness that combines alternation with a mutual chase.

### 4.4 One overstatement in the renewal rationale

> "would let a player pursue an undefended piece indefinitely by shuffling between squares that all attack it"

Under the rejected reading the pursuit is not indefinite: it produces a neutral repetition, claimable as a
draw at the third occurrence. The reconciliation's D3 puts it correctly — the alternative "would make a chaser
who steps sideways while keeping an undefended piece under attack innocent, which reads worse to a player".
Severity: **nit**. Correction: "would leave a chaser who steps sideways while keeping an undefended piece
under attack innocent, reducing the position to a claimable draw."

---

## 5. Status-line and document-status discipline

### 5.1 BLOCKING — the new open item materially understates the defect it records

> "The defect misses violations rather than inventing them, but the asymmetry is not explicable to a player
> and one corner of it can misattribute a mutual draw."

"Misattribute a mutual draw" is not what happens. What happens is that a drawn game becomes a decided game,
automatically and unrecoverably. Executed, on the reconciliation's own mutual-chase wheel `mx-mix-002`, with a
quiet white king step as the entry move:

```
mx-mix-002, history starting at the first occurrence
  2k2r1/7/1cN1R2/7/2r1nC1/7/1R2K2 w - - 0 1   c5b3 e3f5 b3c5 f5e3 ×2      -> (True,0)      DRAW

re-phased wheel X, bare
  2k2r1/7/1c2R2/7/1Nr1nC1/7/1R2K2 b - - 0 1   e3f5 b3c5 f5e3 c5b3 ×2      -> (True,0)      DRAW

the same wheel entered by one quiet move (white king d1-e1)
  2k2r1/7/1c2R2/7/1Nr1nC1/7/1R1K3 w - - 0 1   d1e1 + wheel×2  (9 plies)   -> (True,-32000) LOSER=Black
  the same, one ply later                                     (10 plies)  -> (True,0)      DRAW
```

Both sides are violating; the contract reserves `mutual-perpetual-chase` for exactly that; the engine ends the
game against Black. Under line 62 a unilateral violation is auto-terminal, so the app commits the loss with no
claim and archives `perpetual-chase` against a player who was owed a draw. `discussion-drafts/investigate-chase-window-parity.md`
— the investigation the PR describes as "now running" — reports the same thing at scale: "20 of the 26 entry
moves into that position turn the draw into 'Black loses' at the ninth ply, while the identical wheel one ply
later is a draw", and concludes "**Recommendation: patch, ungated**". The reconciliation's D1 is no softer:
"converting a `mutual-perpetual-chase` draw into a unilateral loss for the wrong side".

An owner reading "misses violations rather than inventing them" plus "can misattribute a mutual draw" would
reasonably defer this. The evidence says deferring it ships wrongly decided games in the majority of entries
into a mutual-chase position. The item is in `Need to discuss` and therefore non-normative, but its whole
function is to frame a decision, and as written it frames it wrongly.

Severity: **blocking**.
Correction: "…The defect drops a violation rather than inventing one, but one corner of it converts a
`mutual-perpetual-chase` draw into a unilateral, automatically terminal perpetual-chase loss for one of the
two violating sides, and the asymmetry is not explicable to a player."

### 5.2 The open item mis-states which thing varies

> "the same repeated sequence can adjudicate differently depending only on which side plays it"

It does not depend on which side plays it. In the decisive reproduction the *same* side plays the *same*
moves; what differs is the side to move at the occurrence on which adjudication lands — `mx-chs-030` and
`mx-chs-032` share a start position, an entry move and every judged move, and differ only by one trailing ply
(both re-executed in §2.7). The reconciliation's mechanism section is precise about this; the D1 summary
sentence the PR appears to have followed ("a violation for one colour and not the other") is the loose one.
Severity: **should-fix**. Correction: "…can adjudicate differently depending only on the side-to-move parity
at which its third occurrence falls."

### 5.3 "Under investigation." does not belong in a contract, and is stale

`AGENTS.md`: "Track progress, tasks, experiments, and delivery status in GitHub Issues or CI artifacts, not in
repository documents." `MiniXiangqi/CLAUDE.md`: "Track progress, tasks, experiments, and delivery status in
GitHub Issues, not in the contracts." A two-word status marker on an open question is exactly that. It is also
already stale: `discussion-drafts/investigate-chase-window-parity.md` was written at 18:08 and the PR commit
is 18:25, and that document is a finished investigation carrying an executive summary and a recommendation.
Severity: **should-fix**. Correction: delete the sentence; if the investigation must be visible, put it in
issue #2 or a new issue and let the contract carry only the question.

### 5.4 The status line's added sentence is circular and does not scope what follows

> "The accepted interpretations of alternating check and chase, of chase renewal, and of a general as sole
> defender are also accepted."

"The accepted interpretations … are also accepted" says nothing. More substantively, the sentence that
immediately follows is unchanged — "The exact definitions of protection, interruption, and discovered and
pinned attacks … remain unresolved" — while two of the three new interpretations are carve-outs of exactly
those areas (renewal is part of discovered attacks, Q3; sole defender is part of protection, Q1). A reader
cannot tell from the status line which part of protection is now settled.
Severity: **should-fix**. Correction: "The three interpretations recorded under **Accepted interpretations** —
alternating check and chase, chase renewal, and a general as sole defender — are accepted. Except as those
settle them, the exact definitions of protection, interruption, and discovered and pinned attacks … remain
unresolved."

### 5.5 The edited `Need to discuss` item claims more completeness than the diff delivers

> "The mutual and mixed cases are settled at the rule level by the accepted outcomes and interpretations
> above; what remains for them is their fixtures."

Besides Finding 3.1, two further pieces remain that are not fixtures:

- Q4's definition of *same class*, which the reconciliation marks `CONTRACT-ONLY` — i.e. it needs contract
  text and no code: "Two sides commit the **same class** when, over the same span, each independently
  satisfies that class's test; their targets and the pieces involved need not correspond in any way." Line 67
  uses "the same class" without defining it.
- D2 is undecided: `mutual-perpetual-chase` is not reportable from the engine's return value at all
  (reconciliation §3.4), so the contract reserves a reason identifier that nothing can currently emit. That is
  an engine-interface matter and #21 records the accessor, but it is not "their fixtures".

Severity: **should-fix**. Correction: add the *same class* sentence, and write "what remains for them is their
fixtures and the reporting of `mutual-perpetual-chase`".

### 5.6 Terminology drifts from the document's own vocabulary

The document says *king* throughout — "A king moves one square orthogonally inside its palace", "The two kings
may not face each other on an otherwise empty file", "Kings and soldiers are excluded as perpetual-chase
targets", "rejection of moves that would leave the kings facing on an empty file". The new section says
"general", "generals", and "the flying-generals condition", a term the document never defines. `testing.md`
gets the same drift, with the new gate saying "general" one line below an existing gate saying "king".
Severity: **should-fix**. Correction: use "king" and "the kings-facing condition defined under Movement", or
add "(the flying-generals condition: the two kings facing on an otherwise empty file)" once at first use.

### 5.7 Nits

- **The constructibility claim is unverifiable from the repository.** "**Both are constructible on the 7-by-7
  board.**" and the six/five piece counts are true (§2), but a standalone clone has no way to check them: no
  identifiers, no positions, and the evidence lives in `discussion-drafts/`, which "is not expected to exist in
  a standalone clone". The Normative source section solves the same problem by naming the retained file and its
  hash. Severity: **nit**. Correction: either name the fixtures the tranche will carry, or say the
  constructions are recorded in workspace-only research evidence.
- **`rules_version` is untouched and the PR does not say why.** The document's own rule is that it "increments
  only when an accepted interpretation change alters a legal move or a user-visible result". Interpretation 3
  narrows what line 64's word "unprotected" reaches, which a future reader could read as altering a
  user-visible result; the defence is that the status line already declares protection unresolved. Severity:
  **nit**. Correction: one clause in the section preamble — "None of the three alters a result the contract
  previously fixed, so `rules_version` is unchanged."
- **PR description inaccuracy.** "confirmed three defects that produce wrong results … all of which are engine
  work, handled in #21" — the chase-window parity defect is not in #21's enumerated fork change set, and this
  PR records it as an open question rather than as handled. Severity: **nit** (description, not contract).

---

## 6. Testing gates

### 6.1 Do the new gates match what the contract now states?

The interpretations gate mirrors the three bullets clause for clause, including their wording problems: it
inherits the renewal ambiguity of Finding 1.2a, and its "having not attacked it from that square before" drops
"the move", leaving "before" without a referent. Fix the contract first; the gate then follows.
Severity: **should-fix** (dependent on 1.2a); the dropped "the move" is a **nit**.

### 6.2 Is the parity-independence gate testable as written?

> "Verify a repeated sequence adjudicates identically whichever side plays it, so no outcome depends on
> side-to-move parity alone."

It is testable, and it tests the wrong property. "Whichever side plays it" is a colour-mirror test, and the
engine already passes that. The defect is a *parity* split with the colours held fixed: `mx-chs-030` and
`mx-chs-032` have the same start, the same entry move and the same judged White moves, and differ only in
whether the third occurrence lands with Black or White to move — draw at 9 plies, Red loses at 10 (§2.7). A
colour-mirrored pair would find nothing.
Severity: **should-fix**. Correction: "Verify that the same judged moves adjudicate identically regardless of
the side-to-move parity at which the third occurrence falls, using a matched pair that shares a start
position, an entry move and every judged move and differs only by one trailing non-violating ply."

### 6.3 Is anything accepted here left with no gate?

- The three interpretations are gated (subject to 6.1). The corrected constructibility statement has no gate,
  which is defensible — it is a claim about the deferred tranche — but nothing in `testing.md` obliges anyone
  to re-execute the two constructions before the tranche is approved. **nit**.
- Q4's precedence sentence and the *same class* definition, if added per Findings 3.1 and 5.5, need gates too;
  the existing line "Verify … mutual same-class draw, check-versus-chase precedence" covers the outcomes but
  not the precedence-over-a-simultaneous-chase case. **should-fix**, contingent on 3.1 landing.
- Structural note, not a finding against this PR: `testing.md` is still "**Status: Draft validation
  proposal.** Nothing in this document is normative until its status or an individual section is explicitly
  marked accepted." So the only gates for three newly accepted rules interpretations sit in a document that is
  non-normative as a whole, while `testing.md`'s own line requires "a minimized failing fixture before changing
  an accepted rule interpretation". Naming the deferred fixtures (`mx-mix-003`, the renewal fixture, and the
  non-flying-general king-recapture fixture) in the rules document, as it already does for `mx-chs-002`, would
  bind the tranche.

---

## Summary of findings

| # | Finding | Severity |
|---|---|---|
| 1.2a | Renewal wording ambiguous; plain reading inverts draw→loss for an advance along an existing attacking line (executed differential) | **blocking** |
| 3.1 | "Mutual and mixed … settled at the rule level" is claimed while lines 66 and 67 give two answers for a simultaneous check-and-chase; Q4's unconditional precedence sentence not lifted | **blocking** |
| 3.2 | "costs a declinable draw" / "never produces a wrong winner" are false when the opponent is also violating — an under-detection converts a mutual draw into an auto-terminal unilateral loss | **blocking** |
| 5.1 | New open item understates a defect I reproduced as a wrong decisive result ("misattribute a mutual draw") | **blocking** |
| 1.1a | Alternation explained per *occurrence* rather than per *move*; does not describe `mx-mix-003` | should-fix |
| 1.1b | Interpretation 1 rests on a persistence premise this document keeps non-normative, and credits it to the source | should-fix |
| 1.3b | Sole-defender limit stated without the protection definition it modifies or the fixture that pins it | should-fix |
| 3.4a | #21 says the pinned-chaser and flying-general-pin rule statements are in this PR; they are not | should-fix |
| 5.2 | Open item says "which side plays it"; the variable is the side-to-move parity at adjudication | should-fix |
| 5.3 | "Under investigation." is delivery status in a contract, and is stale | should-fix |
| 5.4 | Status-line sentence is circular and does not scope the "remain unresolved" clause | should-fix |
| 5.5 | "what remains for them is their fixtures" omits the *same class* definition (`CONTRACT-ONLY`) and D2 reporting | should-fix |
| 5.6 | "general"/"flying-generals" drift from the document's "king" vocabulary; same in `testing.md` | should-fix |
| 6.1 | Interpretations gate inherits the renewal ambiguity | should-fix |
| 6.2 | Parity gate tests colour symmetry, not the parity split it was written for | should-fix |
| 6.3 | Precedence-over-simultaneous-chase would need its own gate once 3.1 lands | should-fix |
| 1.2b | Contract states only the discovery-path renewal test; the engine's test is a union | nit |
| 3.4b | Open item may reopen #21's bounded fork change set | nit |
| 4.4 | "pursue an undefended piece indefinitely" overstates; it reaches a claimable draw | nit |
| 5.7 | Constructibility claim unverifiable from a clone; `rules_version` silence; PR-description inaccuracy | nit |
| 6.3b | No gate obliges re-execution of the two constructions | nit |

**What is right, and should be said plainly:** the constructibility correction is correct in both halves and I
reproduced it end to end, including the piece counts, the check pattern, the attribution controls and the
adjudication ply. The decision to record all three as *interpretations* rather than as readings of the source
is exactly right and the framing sentence is well judged. The engine does agree with all three, which the PR
verifies for the right reasons and does not lean on. The under/over-detection direction of interpretation 3 is
stated correctly. The three blocking findings in items 1, 3 and 5 are prose defects with short, concrete
corrections — all four could be fixed in a single small commit.

**MERGE / DO NOT MERGE: DO NOT MERGE**
