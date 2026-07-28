# Pre-merge review, round three — PR #22

**Under review:** `design/rules-adjudication` at `8ec95cf`, "Correct the renewal clause and the parity defect's
direction". Three commits on `main` `d357c4a`; `docs/xiangqi-rules.md` and `docs/testing.md` only.
**Prior rounds:** `discussion-drafts/review-pr22.md`, `discussion-drafts/review-pr22-round2.md`.
**Script for this round:** `discussion-drafts/rv22r3-verify.py`. Read-only throughout; no repository modified.

**Verdict: MERGE.** Both round-two blocking findings are fixed, and the renewal fix is confirmed by execution
rather than by reading: the wording now predicts all four wheels correctly, including the two it previously got
wrong in opposite directions. Nothing in the third commit broke anything. Four one-line should-fixes remain,
one of them a third pass at the same sentence; none can decide a game or let a broken implementation pass a
gate, so none is a merge condition.

---

## 1. Renewal — re-run against the new wording

**Confirmed: `a1a3` is predicted as no-renewal, `mx-chs-027`'s `d5b5` as renewal, and all four wheels now
match the engine.**

The wording under test:

> headline — "attacks the target from the square it now occupies and did not attack it from that square before
> the move"
> clause A — "A chasing piece that steps **away** from its target and still attacks it from the new square
> therefore renews the chase"
> clause B — "while one that merely advances **toward** the target along a line on which its attack already
> stood does not"

Executed, per move of the chasing side. `att?` is probed, not asserted: after the move the side to move is
flipped and the engine is asked whether the mover can capture on the target square.

```
=== A1  mx-chs-020 — b3a3 chases the a5 cannon, a3b3 does not attack it ===
  ply  move   att?  clause    wording predicts
  1    b3a3   True  headline  renews
  3    a3b3   False headline  no attack -> no renewal
  5    b3a3   True  headline  renews
  7    a3b3   False headline  no attack -> no renewal
  ENGINE at ply 8: DRAW

=== A2  ALONG — rook a1<->a3, cannon fixed on a5 ===
  ply  move   att?  clause    wording predicts
  1    a1a3   True  B         advances TOWARD along the standing line -> NO renewal
  3    a3a1   True  A         steps AWAY, still attacks -> renews
  5    a1a3   True  B         advances TOWARD along the standing line -> NO renewal
  7    a3a1   True  A         steps AWAY, still attacks -> renews
  ENGINE at ply 8: DRAW

=== A3  ACROSS — rook b3<->a3, cannon a5<->b5 ===
  ply  move   att?  clause    wording predicts
  1    b3a3   True  headline  no attack stood before -> renews (neither A nor B applies)
  3    a3b3   True  headline  no attack stood before -> renews
  5    b3a3   True  headline  no attack stood before -> renews
  7    a3b3   True  headline  no attack stood before -> renews
  ENGINE at ply 8: LOSER=Red

=== A4  mx-chs-027 — b5d5 arrives on the d-file; d5b5 steps AWAY along rank 5 ===
  ply  move   att?  clause    wording predicts
  2    b5d5   True  headline  no attack stood before -> renews
  4    d5b5   True  A         steps AWAY, still attacks -> renews
  6    b5d5   True  headline  no attack stood before -> renews
  8    d5b5   True  A         steps AWAY, still attacks -> renews
  ENGINE at ply 8: LOSER=Black
```

Read against A1's premise — a wheel in which one of the chasing side's moves fails to renew is a draw — the
wording and the engine agree on every wheel:

| wheel | wording | engine |
|---|---|---|
| A1 | `a3b3` attacks nothing → chase broken → claimable draw | DRAW ✓ |
| A2 | `a1a3` is clause B → chase broken → claimable draw | DRAW ✓ |
| A3 | every move renews → perpetual chase | LOSER=Red ✓ |
| A4 `mx-chs-027` | `b5d5` headline, `d5b5` clause A → every move renews → perpetual chase | LOSER=Black ✓ |

**Round-two blocking finding R2-1 is fixed.** `d5b5` — the move that the previous wording either excluded or
left uncovered, and which would have flipped `mx-chs-027` from a perpetual-chase loss to a claimable draw — is
now covered explicitly by clause A and predicted as a renewal, which is what the engine does. The two clauses
are the reconciliation's Q3 pair with the "toward" disambiguator added, and the disambiguator is doing real
work: without it the two clauses would both claim `d5b5`.

### 1.1 Residual — the across case is now carried by the headline alone

Finding, **nit**. In A3 neither clause applies: the rook was not attacking the cannon before the move, so it
neither "steps away and still attacks" nor "advances toward along a line on which its attack already stood".
The case falls back on the headline, which round one showed is readable two ways:

- *historical* — "this piece did not attack from that square before" — vacuously true, so it renews. Correct.
- *counterfactual* — "a piece on that square would not have attacked before" — a piece on a3 with a4 empty
  would have attacked a5, so it does not renew. Wrong; the wheel would be a draw.

Two things make this harmless rather than a defect. First, clause B is only non-redundant under the historical
reading: if the headline meant the counterfactual, a piece advancing toward its target along a standing line
would already be excluded by the headline and clause B would say nothing. A reader who notices that clause B
must be doing work is forced to the historical reading, which is the correct one. Second, and decisively, the
across case is pinned by an **already approved** fixture — `fixtures/rules/mx-chs-001.json` is byte-identical
to my A3 wheel (`4k2/7/c6/7/1R5/7/2K4 w - - 0 1`, `b3a3 a5b5 a3b3 b5a5` ×2, `black-wins / perpetual-chase @3`).
An implementer who adopted the counterfactual reading fails an approved fixture on the first run.

Optional correction if the sentence is touched again: add "; a piece that arrives on the attacking line from
off it renews, since no attack stood from that square before" — the round-two clause, kept alongside rather
than in place of clause A.

### 1.2 The rewritten alternative-reading sentence is now correct

> "would exempt a chaser that shuttles between two squares from each of which the threat is new, which is the
> behaviour the rule exists to catch"

This is right, and it is the case the two readings actually differ on. `mx-chs-027` is exactly that chaser:
the rook shuttles b5↔d5, the threat is new from each square, and the rejected reading would exempt it.
Round-two finding R2-2 is closed.

---

## 2. Parity direction — does it now match the measurement?

**The measurement is unchanged and unambiguous. The intent now matches it. The wording does not reliably say
so, and the gate says the opposite.**

```
  case                                         entered  plies    engine
  bare, history begins at the first occurrence -        8        DRAW
  quiet WHITE entry d1e1 (9 plies)             White    9        LOSER=Black
  quiet WHITE entry d1e1 (10 plies)            White    10       DRAW
  quiet BLACK entry d7c7 (9 plies)             Black    9        LOSER=Red
  quiet BLACK entry d7c7 (10 plies)            Black    10       DRAW
```

White enters, Black loses. Black enters, Red loses. The entering side is handed the win; the loss falls on the
other. Round-two blocking finding R2-5 — the line said the loss fell on the entering side — is no longer
false. But:

### 2.1 Finding R3-1 — the contract sentence's most literal reading is still the wrong one

> "resolves the required draw as a unilateral loss — **awarded to whichever side made the quiet move that
> entered the repeating position, against the other**."

The head noun is *loss*. "A loss awarded to X" reads, plainly, as *X receives the loss*, i.e. X loses — which
is backwards. Only the trailing "against the other" pulls it back, by invoking the judgement idiom ("awarded to
the plaintiff, against the defendant"), under which the award favours X and Y loses — which is right. A reader
who stops at the comma gets the wrong answer; a reader who finishes the sentence gets the right one. That is
not a state an accepted rules contract should be left in, on its third pass at the same sentence.

Severity: **should-fix**, not blocking. The operative rule in the same bullet — "Adjudication does not depend
on which side happens to be to move when the third occurrence lands" — is unambiguous and correct, and this
clause is descriptive of a defect that a required fork correction removes; it decides nothing.

Correction, in the plainest available form:

> "…resolves the required draw as a unilateral loss for the side that did **not** make the quiet move which
> entered the repeating position, handing the win to the side that did."

### 2.2 Finding R3-2 — the testing gate still states it backwards

> "…including that a mutual perpetual chase is a draw rather than **a loss awarded to the side that entered
> it**."

Here there is no "against the other" to rescue it: "a loss awarded to the side that entered it" says the
entering side loses. This is round-two finding R2-6 substantially unchanged — "awarded to" does not reverse
"a loss for".

Severity: **should-fix**, not blocking, for the same reason I gave in round two: the operative instruction
before it — "enter one repeating sequence by a quiet move from each side in turn, and confirm the same verdict
at the same occurrence" — fails on the current engine exactly as it should, since the two entries give
`LOSER=Black` and `LOSER=Red`. The parenthetical misdescribes the failure but cannot suppress it.

Correction: "…is a draw rather than a loss for whichever side did **not** enter it."

---

## 3. The should-fixes taken in the same pass

- **Precedence no longer reads onto mutual perpetual check.** "This orders check against chase; it does not
  override the mutual rule below, so two sides both perpetually checking remain a draw." Closes R2-3 exactly,
  and matches `position.cpp:2704`, where both perpetual flags set yields `VALUE_DRAW` — the outcome I
  constructed and executed in round one as `mx-mix-001`. **Fixed.**
- **The engine is no longer offered as a ground for the alternation reading.** "The engine is not evidence
  either way: it implements no combined check-and-chase rule, so its silence is the absence of an
  implementation rather than agreement, and the objection to this reading is precisely that competition
  practice may supply one." Accurate on the code — the classifier carries a check accumulator and a chase
  accumulator and nothing that spans them — and it states the circularity better than my suggested wording
  did. Closes R2-4. **Fixed.**
- **Status line** now carries "the unconditional precedence of check over chase, and the parity-independence
  of adjudication". Closes the coverage half of round-one 5.4. **Fixed** (the circularity and scoping half
  remains; see §5).
- **The interpretations gate carries the discriminator**: "…so that stepping away from a target while still
  attacking it renews while advancing toward it along an existing line does not." Closes round-one 6.1.
  **Fixed.**
- **Cross-reference.** Confirmed on `origin/design/engine-packaging`: the sentence claiming the parity fix "is
  deliberately absent from this list pending a decision" is gone, and the accepted fork change set carries
  "Correction of the repetition window's parity asymmetry" with a direction-neutral description ("which of two
  equally violating sides loses depends only on which of them made the move that entered the position").
  Round-two R2-7's second half is **fixed**; the two branches agree.

### 3.1 Finding R3-3 — the alternation clause moved away from the fix, not toward it

This was round-one 1.1a, restated in round two. It is now:

> "a sequence whose behaviour differs between **the occurrences that are counted** — a check at one, a chase
> at the next — sustains neither"

The commit message records this as "alternation is described per counted occurrence rather than per move". That
is the opposite of what the finding asked for, and the new phrasing is slightly further from the fixture than
the old one. `mx-mix-003`'s executed check flags are `f T f f f T f f f` with the counted occurrences at plies
0, 4 and 8. Red moves at plies 1, 3, 5, 7 — checking at 1 and 5, chasing at 3 and 7. So the behaviour between
occurrence 1 and occurrence 2 is *check then chase*, and between occurrence 2 and occurrence 3 it is *check
then chase* again: identical. The behaviour does not differ between the counted occurrences at all; the
alternation is between the side's two **moves inside each interval**. Adding the explicit condition "whose
behaviour differs between the occurrences that are counted" therefore describes a sequence that is all-check
for one cycle and all-chase for the next — which is not the case being settled, and not what `mx-mix-003` does.

Severity: **should-fix**, not blocking. The bolded headline — "A side alternating check and chase (一将一捉)
commits neither violation" — is the normative sentence, it is correct, and the testing gate states it
correctly too; the gloss can fail to explain the rule but cannot classify any sequence into a violation. Still,
it is now the last substantive prose defect in the riskiest bullet in the document.

Correction, the reconciliation's Q4 sentence, unchanged from what I proposed twice:

> "A side whose moves in the span are neither all checks nor all chases of one and the same piece has committed
> neither violation."

---

## 4. Anything the third commit broke

Nothing. I re-read both files in full at `8ec95cf` and re-ran every wheel from rounds one and two on the same
build (`r-scratch`, fork `77d602e0`, target variant): `mx-mix-001`, `mx-mix-004` with its `mx-chs-027` control,
`mx-mix-003`, `mx-chs-009`/`010`/`011`, `mx-chs-030`/`031`/`032`, and the A and B sets above. Every verdict is
identical to the earlier rounds. No accepted line changed meaning except the two that were meant to.

---

## 5. The three outstanding items — is any of them now blocking?

**None of them.** Taking them in the order you asked:

**1.1b — the per-move persistence premise, credited to the source while the document keeps it non-normative.**
Not blocking, and I want to be honest that this finding is weaker than I first framed it. With the engine
removed as a ground, the bullet's sole stated basis is "the source enumerates exactly two classes and defines
each as persistent" — and that basis is sound. The source's own word is *perpetual*, and the step from
"perpetual check" to "a sequence that is not checking throughout is not perpetual check" needs nothing beyond
the plain sense of the word. What remains deferred is only the **operational** test for "sustained", which the
document lists under `Need to discuss`. That gap is not live: the document also says items there "do not
authorize implementation", the tranche's fixtures are explicitly deferred, and the facade is gated on approved
fixtures rather than on prose. It should still be closed when the interruption question is settled — and if the
tranche lands without it, it becomes blocking then, because at that point something is authorized to be
implemented. Today it is not.

**1.3b — the sole-defender bullet lacks the protection context and the fixture that pins it.** Not blocking.
The rule is stated correctly, its direction is right (executed again this round: `mx-chs-009` Red loses,
`mx-chs-010` draw, `mx-chs-011` draw), and the exposure sentence added in round two is accurate. What is
missing is traceability — the reconciliation writes the limit into the Q1 protection definition and pins it
with `mx-chs-011`, and the contract states the limit without saying it is a limit on a definition it elsewhere
declares unresolved. That is a documentation improvement, and the deferred tranche's review is the natural
place to enforce it.

**5.6 — "general" and "flying-generals" against the document's "king" vocabulary.** Not blocking. No rule is
misstated; "flying generals" is standard xiangqi usage and the Movement section defines the condition in
substance ("The two kings may not face each other on an otherwise empty file"). It is a consistency wart in
two files, worth a pass whenever either file is next opened.

---

## Summary

| # | Finding | Severity |
|---|---|---|
| R3-1 | Parity sentence: "a unilateral loss — awarded to [the enterer], against the other" reads backwards until the final clause | should-fix |
| R3-2 | Parity gate: "a loss awarded to the side that entered it" is backwards, unrescued | should-fix |
| R3-3 | Alternation gloss moved to "differs between the occurrences that are counted", which `mx-mix-003` does not do | should-fix |
| 5.4 | Status line coverage fixed; "The accepted interpretations … are also accepted" still circular, and "remain unresolved" still unscoped | should-fix |
| 1.1 | Across case now carried by the ambiguous headline, mitigated by clause B's non-redundancy and pinned by approved `mx-chs-001` | nit |
| 1.1b, 1.3b, 5.6 | Outstanding from round one; none blocking, reasoning above | should-fix |
| 5.7 | `rules_version` silence; constructibility claim unverifiable from a clone | nit |

Everything this review found blocking across three rounds is now fixed, and each fix was verified by execution
rather than by reading: the renewal clause predicts all four wheels, the precedence rule is stated once and
matches the engine on both the check-versus-chase and the mutual-check branch, both safety claims state the
real exposure, and the parity defect is an accepted requirement with a gate that actually fails on the current
engine. The three constructibility claims I was asked to reproduce in round one — mutual perpetual check in six
pieces, check-over-chase precedence in five, and its control — reproduce unchanged. The four remaining
should-fixes are one line each and I would take them in the same pass, since two of them are the third pass at
one sentence and one of them has now moved in the wrong direction twice; but none can decide a game or let a
broken implementation pass a gate, and none is a condition of merge.

**MERGE / DO NOT MERGE: MERGE**
