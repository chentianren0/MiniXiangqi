# Pre-merge review, round two — PR #22, "Accept three rule interpretations and correct a false claim"

**Under review:** branch `design/rules-adjudication` at `08d3532`, rebased onto `main` `d357c4a`.
Two commits: `1ca0867` (round one) and `08d3532` ("Fix pre-merge review findings in the rules interpretations").
Diff against `main`: `docs/xiangqi-rules.md` (+14/−5), `docs/testing.md` (+3/−0).
**Round-one report:** `discussion-drafts/review-pr22.md`.
**Scripts for this round:** `discussion-drafts/rv22r2-verify.py` (round one's `rv22-verify.py`, `rv22-renewal.py` still apply).

Read-only throughout. No repository modified, no GitHub write.

**Verdict: DO NOT MERGE.** All four round-one blocking findings were engaged seriously and three of them are
now materially better than the reconciliation's own text. But the second commit introduced two new defects of
its own, both executed and both one-line fixes: the restored renewal clause is not the clause the
reconciliation had, and read against `mx-chs-027` it inverts it; and the newly accepted parity line states the
wrong side as the loser. The second is now in the **accepted** list, which is where a factual error is least
tolerable.

---

## 0. Status of the four round-one blocking findings

| # | Round-one blocking finding | Round-two status |
|---|---|---|
| 1.2a | Renewal wording ambiguous; plain reading flips draw→loss | **Partly fixed, new defect introduced** — see 1 below |
| 3.1 | "Settled at the rule level" claimed while lines 66/67 conflict | **Fixed**, with one scope wrinkle — see 2 |
| 3.2 | Safety claims false when the opponent is also violating | **Fixed**, accurately and in both bullets — see 3 |
| 5.1 | Open item understated the parity defect | **Fixed in force, wrong in direction** — see 4 |

---

## 1. Renewal — does the new wording predict both verdicts, or only read better?

**It predicts three of my four wheels and inverts the fourth, which is the one fixture the interpretation
exists to decide.**

### 1.1 The new text

> "**A chase renews when the chasing piece attacks the target from the square it now occupies and did not
> attack it from that square before the move.** A piece that merely advances along a line on which its attack
> already stood does not renew the chase; a piece that arrives on the attacking line from off it does."

The reconciliation's Q3 sentence, which round one asked for, is:

> "A chasing piece that **steps away from a target and still attacks it from its new square** therefore renews
> the chase, while a piece that merely advances along a line on which its attack already stood does not."

The second half was restored verbatim. **The first half was replaced by a different clause** — "arrives on the
attacking line from off it" — which is not equivalent to it and does not cover the same case.

### 1.2 Executed — `rv22r2-verify.py`, fork `77d602e0`, target variant

```
=== A1  every move must renew — one chasing move + one idle move per cycle (mx-chs-020) ===
  fen  : 3k3/7/c6/7/1R5/7/2K4 w - - 0 1
  moves: b3a3 a5a6 a3b3 a6a5 ×2
  ply 8   (True,0)   DRAW

=== A2  ALONG the line: rook a1<->a3, cannon fixed on a5 ===
  fen  : 4k2/7/c6/7/7/7/R2K3 w - - 0 1
  moves: a1a3 e7e6 a3a1 e6e7 ×2
  ply 8   (True,0)   DRAW

=== A3  ACROSS onto the line: rook b3<->a3, cannon a5<->b5 ===
  fen  : 4k2/7/c6/7/1R5/7/2K4 w - - 0 1
  moves: b3a3 a5b5 a3b3 b5a5 ×2
  ply 8   (True,-32000) LOSER=Red

=== A4  mx-chs-027 ===
  fen  : 3k3/7/1r3N1/7/7/2K4/7 w - - 0 1
  moves: f5d6 b5d5 d6f5 d5b5 ×2
  ply 8   (True,32000 ) LOSER=Black
```

- **A1** establishes the premise the whole test rests on: a wheel in which one of the chasing side's two moves
  renews and the other does not is a draw. So a chase verdict means **every** move of that side renewed.
- **A2 / A3** are the round-one differential. The new wording gets both right: A2's White moves run along the
  a-file on which the attack already stood → "does not renew" → draw ✓; A3's White moves arrive on the
  attacking line from off it → "does" → Red loses ✓.
- **A4 is the problem.** In `mx-chs-027` Black's two moves are:
  - `b5d5` — the white horse is on d6; the rook arrives on the d-file, which it was off before. Covered by
    the new clause, renews ✓.
  - `d5b5` — the horse has gone back to f5; the rook already attacks f5 from d5 along rank 5, and it moves
    **along rank 5, away from the target**, to b5, from which it still attacks f5.

  By A1, the chase verdict at ply 8 proves the engine counts `d5b5` as a renewal. (It does so because the
  rook's own former square, d5, stood between b5 and f5 in the pre-move position, so the exact before/after
  test at `position.cpp:3050-3052` admits it.) But `d5b5` moves *along a line on which its attack already
  stood*, and it does *not* arrive on the attacking line from off it. Under the new dichotomy it is either
  excluded by the first clause or covered by neither.

### 1.3 Finding R2-1 — BLOCKING

Two moves that are both "along a line on which the attack already stood" adjudicate oppositely on the engine:
`a1a3` (toward the target) is not a renewal, `d5b5` (away from the target) is. The new sentence offers no
clause that separates them.

- Read "advances along" loosely, as any motion along that line, and the contract says `d5b5` does not renew.
  Black's chase then fails on half its moves and **`mx-chs-027` flips from a perpetual-chase loss to a
  claimable draw** — the same draw-versus-loss inversion round one flagged, in the opposite direction.
- Read "advances" strictly, as motion toward the target, and `d5b5` is covered by neither clause and falls
  back on the headline sentence, whose ambiguity was the original finding. (Here both readings of the headline
  happen to agree that it renews, so this reading is survivable — but the dichotomy is written as complete,
  "does not … does", and is not.)

The stakes are not abstract. The reconciliation calls `mx-chs-027` "the single fixture whose result depends on
the renewal interpretation adopted in Q3", and also "the deletion control that proves the chase component of
`mx-mix-004`" — the control this very PR cites two sections later: "check-over-chase precedence in five, **with
a control position proving the chase component real**". If the accepted renewal wording makes `mx-chs-027` a
draw, the PR's own constructibility correction is contradicted by the PR's own interpretation.

Severity: **blocking**.
Correction — keep the new clause and restore Q3's, which together predict all four wheels correctly:

> "A chasing piece that steps away from a target and still attacks it from its new square renews the chase, as
> does one that arrives on the attacking line from off it; a piece that merely advances along a line on which
> its attack already stood, toward the target, does not."

Checked against the runs: A1 `a3b3` attacks nothing → no renewal → draw ✓. A2 `a1a3` advances toward → no
renewal → draw ✓. A3 both moves arrive from off the line → Red loses ✓. A4 `b5d5` arrives from off the line
and `d5b5` steps away and still attacks → Black loses ✓.

### 1.4 Finding R2-2 — the reworded rationale is now self-defeating

> "The alternative reading — that a chase renews only when the threat did not exist anywhere beforehand —
> would let a player pursue an undefended piece indefinitely by **stepping between squares that each attack it
> afresh**"

If each square attacks the target *afresh*, then the threat did **not** exist beforehand, so the rejected
alternative would call every such move a renewal too. The sentence now describes a case on which the two
readings agree, and so illustrates nothing. The behaviour the alternative actually permits is the opposite: a
chaser keeping the target under **continuous** attack while moving between the squares it attacks from, so
that no move ever creates a threat that did not already exist — which is precisely `mx-chs-027`'s `d5b5`.

The reword's stated motive — that the old phrasing "described the case the rule does not catch" — was half
right and produced a worse sentence: "shuffling between squares that all attack it" is ambiguous between the
along-the-line case (A2, which the adopted rule indeed does not catch) and the step-away case (A4, which it
does). The fix is to name the case rather than gesture at it.

Severity: **should-fix**.
Correction: "…would let a player keep an undefended piece under continuous attack indefinitely, stepping
between the squares it attacks from without ever creating a threat that did not already exist, which is the
behaviour the rule exists to prevent."

---

## 2. Precedence — does the new sentence conflict with anything else in the accepted list?

> "When one side perpetually checks and the other perpetually chases, the checking side is the side required
> to stop and loses if the violation is completed. **Check outranks chase unconditionally: a side that is
> perpetually checking loses even if it is simultaneously chasing, and even if the other side is also
> chasing.**"

**The round-one conflict is closed.** My class — one side perpetually checking *and* chasing while the other
perpetually chases — is now answered once: the checker loses. Both "even if" clauses are needed and both are
present. It also matches the engine exactly: `position.cpp:2704-2705` evaluates `perpetualThem || perpetualUs`
before it ever reaches `chaseThem || chaseUs`, so no chase by either side can survive a perpetual check.

It also sits well beside interpretation 1, better than I expected: "simultaneously chasing" (both classes on
every move → the checker loses) and "alternating check and chase" (one class per move → neither violation) are
now the two halves of a clean taxonomy, and the words chosen keep them apart.

### 2.1 Finding R2-3 — one new scope wrinkle against the mutual-check draw

The main clause is unqualified — "a side that is perpetually checking loses" — and the two concessions
enumerate only *chasing* by either side. They conspicuously omit the case where **the other side is also
perpetually checking**, which line 67 resolves as a draw with the reserved reason `mutual-perpetual-check`,
which the engine resolves the same way (`:2704`, both flags set → `VALUE_DRAW`), and which I constructed and
executed in round one (`mx-mix-001`, six pieces, `(True,0)`). Read literally, the new sentence makes both
sides lose there.

Context does most of the work — the sentence opens "Check outranks *chase*", and line 67 is more specific — so
an implementer would almost certainly get it right. But this is the same shape as the round-one blocking
finding, in a document where the mutual-check outcome is constructed, named, and given its own serialization
identifier.

Severity: **should-fix** (not blocking: line 67 is specific and unchanged, and the framing clause scopes the
sentence to check-versus-chase).
Correction: append "; when both sides are perpetually checking, the mutual draw below applies instead."

### 2.2 The `Need to discuss` rewrite is now accurate

> "The mutual and mixed cases are settled at the outcome level by the accepted rules above; what remains for
> them is the definition of what makes two violations the same class, the reporting of a mutual chase
> distinctly from a claimed repetition, and their fixtures."

This is exactly right, and it closes round-one finding 5.5 in full: "outcome level" instead of "rule level",
the `CONTRACT-ONLY` same-class definition named, and D2's reporting gap named. No finding.

---

## 3. The safety claims

Both replacements are accurate against what I measured and reasoned in round one.

> "…where the opponent is not also violating, being wrong here costs only a claimable draw that should have
> been a loss; but where the opponent *is* violating, treating the alternation as innocent turns a
> mutual-violation draw into an automatic unilateral loss, which decides the game against the wrong side."

> "This under-detects. Against a non-violating opponent that costs only a claimable draw in place of a loss;
> against a violating one it can, like the interpretation above, resolve a mutual violation as a unilateral
> loss."

Correct in both bullets, including the "automatic" — which is the part that matters, since line 62 commits a
unilateral violation without a claim. The owner reaffirming the permissive reading with the exposure known is
exactly the right disposition of a two-sided question, and the contract now records the exposure rather than a
reassurance. **Round-one finding 3.2 is fully addressed.**

### 3.1 Finding R2-4 — the newly added ground for acceptance is close to circular

> "It is accepted because the source enumerates exactly two classes and defines each as persistent, and
> because **the engine's own adjudication agrees**."

The engine does agree — I executed it (`mx-mix-003` → `(True,0)` under the target variant, the plain AXF
child, and built-in `minixiangqi`). But as a *ground for accepting the interpretation* it is weak in a way the
document elsewhere is careful about:

- The document's own stance is "Neither a Fairy-Stockfish search score nor an engine-specific optional result
  silently changes user-visible rules" and "A fixture is not accepted merely because PyChess or
  Fairy-Stockfish currently produces the same result." Round one noted approvingly that the text did not lean
  on engine agreement; it now does.
- The agreement is not independent evidence. Fairy-Stockfish's AXF classifier has two accumulators, one for
  check and one for chase, each requiring its own condition at every ply; it has no combined 一将一捉 rule to
  apply. Its "agreement" is the absence of an implementation, not a judgement. And the stated risk is that AXF
  and CXA *competition practice* forbids the alternation — so citing the AXF *implementation* as support for
  the permissive reading answers the objection with the thing the objection is about.

Severity: **should-fix**.
Correction: "…and because adopting it requires no divergence from the engine's own adjudication, which
implements the two classes separately and has no combined rule."

### 3.2 Round-one finding 1.1b is now sharper, not weaker

The bullet still says the interpretation follows because the source "defines each as persistent". The premise
that actually does the work — that a class must hold at **every one of the side's moves** across the span, so
one non-conforming move destroys it — is not in the source; it is the interruption reading, which this same
document still lists under `Need to discuss` and therefore declares non-normative. With the precedence sentence
now drawing a sharp line between "simultaneously" and "alternating", the per-move test is load-bearing in two
accepted rules while remaining formally unresolved. Still **should-fix**; see §6.

---

## 4. Parity — is the new accepted line accurate against what was measured?

> "Adjudication does not depend on which side happens to be to move when the third occurrence lands. The
> engine currently evaluates a sustained chase over a window one move wider for one parity than the other,
> which costs a ply of detection in a unilateral chase and, in a mutual perpetual chase, resolves the required
> draw as a unilateral loss **against whichever side made the entering move**. A fork correction is required;
> see [engine-integration.md](engine-integration.md)."

Four claims. Three are accurate. The fourth is backwards.

- "Adjudication does not depend on which side happens to be to move when the third occurrence lands" —
  **accurate**, and it fixes round-one finding 5.2: it is now about parity, not colour. It also generalises a
  property the approved set already pins, since `mx-chk-001`/`mx-chk-002` are described as "pinned for both
  side-to-move parities".
- "a window one move wider for one parity than the other" — **accurate** (`position.cpp:2694-2695` versus
  `:2716`).
- "costs a ply of detection in a unilateral chase" — **accurate**; `mx-chs-030` draws at 9 plies and
  `mx-chs-032` — same start, same entry move, same judged moves — loses at 10.
- "resolves the required draw as a unilateral loss **against whichever side made the entering move**" —
  **wrong, and backwards.**

### 4.1 Executed — the same wheel entered by each colour in turn

```
=== B0a  mx-mix-002 as published — history begins at the first occurrence ===
  2k2r1/7/1cN1R2/7/2r1nC1/7/1R2K2 w - - 0 1   c5b3 e3f5 b3c5 f5e3 ×2
  ply 8   (True,0)   DRAW

=== B1  entered by a quiet WHITE move (white king d1-e1) ===
  2k2r1/7/1c2R2/7/1Nr1nC1/7/1R1K3 w - - 0 1   d1e1 + wheel×2   (9 plies)
  ply 9   (True,-32000) LOSER=Black
=== B1' the same, one ply later ===                            (10 plies)
  ply 10  (True,0)   DRAW

=== B2  entered by a quiet BLACK move (black king d7-c7) ===
  3k1r1/7/1cN1R2/7/2r1nC1/7/1R2K2 b - - 0 1   d7c7 + wheel×2   (9 plies)
  ply 9   (True,-32000) LOSER=Red
=== B2' the same, one ply later ===                            (10 plies)
  ply 10  (True,0)   DRAW
```

White enters, **Black** loses. Black enters, **Red** loses. The loss falls on the side that did **not** make
the entering move; the entering side is handed the win. That is also what the mechanism predicts — the entry
move's empty chase set is intersected into `chaseThem`, which describes the chase by the side that *just
moved* at the adjudicated ply, i.e. the side whose parity matches the entry — and it is what the independent
investigation says in words: "award the win to the side that made the quiet entry move, and archive
`perpetual-chase` against a player who was owed a draw."

PR #21's branch states it correctly and neutrally: "which of two equally violating sides loses depends only on
which of them made the move that entered the position." Only #22's sentence names a direction, and names the
wrong one.

### 4.2 Finding R2-5 — BLOCKING

An accepted line of a rules contract states the wrong side as the loser. The contract's whole purpose is to say
who loses; a reader, an implementer, or a tester reconstructing the defect from this sentence would look for a
loss against the entering side and find the opposite. It also propagates into the new gate.

Severity: **blocking**.
Correction: "…resolves the required draw as a unilateral loss against whichever side did **not** make the
entering move, handing the win to the side that did."

### 4.3 Finding R2-6 — the same error is in the new testing gate

> "…including that a mutual perpetual chase is a draw rather than **a loss for whichever side entered it**."

Same inversion. The operative instruction before it — "confirm the same verdict at the same occurrence" — does
catch the defect on its own (B1 and B2 give opposite verdicts, so the gate fails as it should), so this is not
independently blocking; but a tester reading the parenthetical is told to expect the wrong failure.
Severity: **should-fix**. Correction: "…is a draw rather than a loss for whichever side did not enter it."

### 4.4 Finding R2-7 — an accepted line that describes current implementation state, and a cross-reference that does not land

Two smaller problems with the same bullet:

- The middle sentence describes what "the engine currently" does. This document's own scope line says it "does
  not own … Fairy-Stockfish implementation details", and an accepted contract line that begins "currently"
  becomes false the moment the fork is patched, with nothing obliging anyone to come back for it. Keep the
  rule — "Adjudication does not depend on which side happens to be to move when the third occurrence lands" —
  in the accepted list, and move the description of the defect and the required correction to
  `engine-integration.md`, leaving the cross-reference.
- The cross-reference "see [engine-integration.md](engine-integration.md)" does not land. On `main` that
  document does not mention the parity correction at all. On PR #21's branch it does — but it also still
  says, in the same section: "One further confirmed defect — the chase window being one move wider for one
  side-to-move parity — is deliberately absent from this list pending a decision recorded in that document, so
  the list is complete for what is decided rather than for what is known." That sentence contradicts the
  bullet four lines above it, and it points back at a pending decision that this PR has just removed. Merged
  in either order, the pair is inconsistent for as long as that sentence survives.

Severity: **should-fix**, with a merge-order condition: #21's stale sentence must go, in #21, before or with
this merge. (It is #21's defect; it is reported here because #22's accepted line now depends on it.)

---

## 5. Anything else the new commit broke

I re-read the whole of both files at `08d3532`, not only the changed lines.

- **The status line was not updated for the two new accepted rules.** It still enumerates what is accepted and
  now omits both the parity rule and the unconditional-precedence rule, while `AGENTS.md` requires a partially
  accepted document to state exactly which sections are accepted. The parity bullet in particular is a new
  substantive commitment — it obliges a fork correction — and nothing in the status line covers it.
  Severity: **should-fix**. Correction: extend the accepted enumeration with "the parity independence of
  adjudication and the unconditional precedence of check over chase".
- **`rules_version` is still 1 and still unexplained.** Defensible — none of the three interpretations, the
  precedence sentence, or the parity rule alters a result the contract previously fixed — but the document's
  own rule invites the question and the answer should be one clause. Severity: **nit** (unchanged from round
  one).
- **No regression elsewhere.** The constructibility paragraph, the `Accepted interpretations` preamble, the
  third `Need to discuss` bullet and every other line are byte-identical to round one. The two round-one
  fixtures I re-ran to be sure the rebase changed nothing — `mx-mix-001` and `mx-mix-004` with its control —
  behave exactly as reported in round one.
- **Round-one finding 3.4a is substantially addressed, in #21 rather than here.** #21's branch now says "The
  two adjudication corrections rest on execution-confirmed defects rather than on the deferred definitions of
  protection, interruption, and discovered or pinned attacks, which xiangqi-rules.md still leaves open", which
  removes the dependency on rule statements that were never written. Only #21's *PR description* still says
  "The rules interpretations behind the two adjudication corrections are a separate PR against
  `xiangqi-rules.md`". Severity: **nit**, and it is #21's.

---

## 6. Which round-one should-fixes I now consider blocking

**None of them, individually.** Nothing in the round-two commit promoted an outstanding should-fix to
blocking, and I would not hold the merge for any of them on its own. Ranked by what I would take in the same
pass, since the same lines are already being edited:

1. **1.1a — "a check on one occurrence and a chase on the next"** (still unfixed). `occurrence` is this
   document's technical term for an occurrence of the repeated position; the case actually being settled is
   alternation between the side's *moves* inside one cycle (`mx-mix-003`: `f T f f f T f f f`). Now that the
   precedence sentence draws the line between "simultaneously" and "alternating" per move, this clause is the
   only place left using the wrong unit. Correction: Q4's "A side whose moves in the span are neither all
   checks nor all chases of one and the same piece has committed neither violation."
2. **1.1b / §3.2 above — the per-move persistence premise is non-normative and credited to the source.** Two
   accepted rules now depend on it.
3. **6.1 — the interpretations gate does not carry the discriminator.** It still gates only the ambiguous
   headline ("having not attacked it from that square before", with "before" left without a referent). Once
   R2-1 is fixed, the gate should carry the along/across/step-away distinction, since that is what a fixture
   would actually check.
4. **5.4 — the status-line sentence is circular** ("The accepted interpretations … are also accepted") **and
   does not scope the "remain unresolved" clause** that follows, now compounded by the omission in §5 above.
5. **1.3b — the sole-defender bullet still lacks the protection context and the fixture that pins it.**
6. **5.6 — "general" / "flying-generals" against the document's "king" vocabulary**, in both files.

The nits from round one stand unchanged: 1.2b (the contract states only the discovery-path half of a test the
engine applies as a union — R2-1's correction narrows this but does not close it), 4.4 (now superseded by
R2-2), 5.7 (constructibility claim unverifiable from a clone; `rules_version` silence).

---

## Summary

| # | Finding | Severity |
|---|---|---|
| R2-1 | Restored renewal clause is not Q3's; read against `mx-chs-027` it inverts it, and `mx-chs-027` is the control this PR's own constructibility correction relies on | **blocking** |
| R2-5 | New accepted parity line names the wrong loser — executed: White enters, Black loses; Black enters, Red loses | **blocking** |
| R2-2 | "squares that each attack it afresh" describes a case on which both readings agree; illustrates nothing | should-fix |
| R2-3 | Precedence sentence's unqualified main clause reads onto mutual perpetual check, which line 67 draws | should-fix |
| R2-4 | "the engine's own adjudication agrees" is offered as a ground for acceptance; it is the absence of an implementation, and the objection is about AXF practice | should-fix |
| R2-6 | New parity gate repeats the wrong direction in its parenthetical | should-fix |
| R2-7 | Accepted line describes current engine state; its cross-reference does not land on `main` and lands on a self-contradiction on #21's branch | should-fix |
| — | Status line not extended to the two new accepted rules | should-fix |
| — | Round-one 1.1a, 1.1b, 1.3b, 5.4, 5.6, 6.1 outstanding, none blocking | should-fix |

**What round two got right, and it is most of it:** the precedence rule is now stated once, correctly, and
matches the engine; the mutual/mixed open item is honest about what remains; both safety claims were replaced
with the actual exposure rather than softened; the parity defect was promoted from an open question to an
accepted requirement with a real gate behind it; and the new parity gate, unlike the one it replaces, would
actually fail on the current engine. Two sentences are wrong. Both fixes are a line each, and both are fully
specified above.

**MERGE / DO NOT MERGE: DO NOT MERGE**
