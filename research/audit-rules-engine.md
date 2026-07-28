# Audit — rules engine lens

Workspace-only research evidence. Not part of any repository, not a contract, authorises nothing.
Scope: `MiniXiangqi/docs/*.md` (all eight), `MiniXiangqi/fixtures/rules/` (16 fixtures + README), read as one
body of work, against the pinned Fairy-Stockfish fork.

**Method markers used throughout.** `[executed]` — I ran it and quote the output. `[read]` — quoted from a
file, with path and line. `[reasoned]` — my inference, labelled as such.

## What I executed

Build: `/Users/tianren/coding/minixiangqi/fs-chase/pyffish.cpython-314-darwin.so`, `Fairy-Stockfish 280726 LB`,
worktree at `131784a4` ("Make the repetition window span the same moves for both sides"), i.e. the fork with all
five accepted source changes present, including the parity correction.

Baseline `[executed]`: all 16 approved fixtures pass under
`[mxq:minixiangqi] chasingRule=axf; nMoveRule=0; promotedSoldiersChaseable=false`
(`discussion-drafts/engine-fixture-check.py /Users/tianren/coding/minixiangqi/fs-chase` → 0 failures).
Under plain built-in `minixiangqi` exactly two fail — `mx-chs-001` and `mx-chs-004` — which is precisely what
`engine-integration.md:128` claims. That claim is correct as written.

Also verified `[executed]`, both true as stated in `xiangqi-rules.md:37`: a soldier move does **not** reset the
fifth FEN field (`4k2/7/p6/7/1R5/7/2K4 w - - 0 1` + `b3a3 a5b5 a3b3 b5a5` → `... - 4 3`), and a capture does
(`d4d6` in `mx-move-003`'s position → `... - 0 3`). `mx-chs-003`'s asserted halfmove of `8` is right.

Fourteen findings follow, most severe first.

---

## 1. Contradiction — a *protected* rook chased by a horse or cannon is a terminal loss in the target engine

**Places that disagree.**

- `docs/xiangqi-rules.md:64` `[read]` — "A unilateral perpetual chase of the same **unprotected** target is a
  loss for the chasing side."
- `fixtures/rules/mx-chs-002.json`, `rationale` `[read]` — "Chasing a protected piece is not a perpetual-chase
  violation, so the repetition is neutral and merely claimable as a draw at the third occurrence."
- The pinned fork, `src/position.cpp`, `Position::chased()` `[read]` — inside `addChased`, before the
  protection test runs:

  ```
  // Attacks against stronger pieces
  if (attackerType == HORSE || attackerType == CANNON)
      b |= attacks & pieces(sideToMove, ROOK);
  ```

  A rook attacked by a horse or a cannon enters the chased set unconditionally. The `roots`/protection test
  further down is never consulted for it.

**Executed.** Position `4k2/7/r3r2/3N3/7/7/2K4 w - - 0 1` — black rook on a5 (the target), black rook on e5
defending it on both a5 and b5 throughout, white horse on d4, kings on e7/c1. Moves
`d4b3 a5b5 b3d4 b5a5 d4b3 a5b5 b3d4 b5a5` — the same eight-ply wheel shape as `mx-chs-001`, with the horse
renewing the attack from b3 (attacks a5) and d4 (attacks b5):

```
horse vs PROTECTED rook     ended=True rule=PERP_CHASE  -> BLACK wins
horse vs UNPROTECTED rook   ended=True rule=PERP_CHASE  -> BLACK wins     (control, e5 rook removed)
horse vs PROTECTED cannon   ended=True rule=N_FOLD      -> DRAW           (control, target is a cannon)
```

The third line is `mx-chs-002`'s own outcome with a horse in place of the rook, so the protection machinery
demonstrably works — it is simply bypassed when the target is a rook and the chaser is a horse or a cannon.

**Which is right.** The engine. This is AXF's 以低子捉高子 class: attacking a stronger piece with a weaker one is
a chase whether or not the stronger piece is defended, because the exchange still wins material. The contract
text is what is wrong, and it is wrong twice — once in the accepted rule at line 64 and once in an approved
fixture's rationale, which the README (`:5`) declares normative alongside the prose.

**Why this is the worst finding.** It is a wrong user-visible result in ordinary play, not an edge case: it
turns a neutral claimable repetition into an automatic loss for a player who committed no violation under the
contract as written, at the third occurrence, with no claim gate to stop it. Mini Xiangqi has two rooks, two
horses and two cannons a side and a seven-file board, so horse-or-cannon-versus-defended-rook shuttles are
common. No fixture covers it. It is **not** the deferred item at `xiangqi-rules.md:119` ("Define exactly what
makes a chased piece protected or unprotected"): the target here is protected under every definition; the
engine does not apply the protection test to this class at all.

**Severity.** Contradiction (highest).

**Correction.** Add to `xiangqi-rules.md`, in the accepted text beside line 64:

> A chase of a rook by a horse or a cannon is a violation whether or not the rook is protected, because the
> weaker attacker wins material on the exchange. The protection test applies only where attacker and target are
> of equal or inverted value.

and add a deferred-tranche fixture pair (`mx-chs-005`, horse vs protected rook = `perpetual-chase` loss;
`mx-chs-006`, horse vs protected cannon = `claimable-draw`) using the two positions executed above. If instead
the product owner wants the simpler "protected is never a violation" rule, that is a **sixth** fork change and
a deliberate divergence from AXF, and must be listed as such at `engine-integration.md:35`. **This is the
product owner's call, not a designer's**: the options are (a) adopt AXF's stronger-piece class — no code
change, contract text grows by two sentences, the app's rule is harder to explain in Help; or (b) keep the
simple rule — a fork patch, a divergence from the adjudication every other chasing variant uses, and a
permanent maintenance cost at every upstream merge.

---

## 2. Contradiction — the enumerated target-variant configuration fails an approved fixture

**Places that disagree.**

- `docs/engine-integration.md:124` `[read]` — "The custom variant disables the inherited move-count rule with
  `nMoveRule = 0`, uses `nFoldRule = 3`, and preserves illegal-perpetual-check adjudication." This is the
  document's complete enumeration of the target variant's settings.
- `docs/engine-integration.md:127` `[read]` — "AXF configuration alone does not satisfy the approved
  soldier-exclusion fixture `fixtures/rules/mx-chs-003` … the target variant requires a focused source change
  in the Fairy-Stockfish fork."
- `docs/engine-integration.md:39` `[read]` — the soldier change "introduces a variant property whose default
  preserves every existing variant's adjudication." The property is never named anywhere in the contracts.

**Executed.** Loading exactly what line 124 enumerates:

```
[minixiangqiaxf:minixiangqi]
chasingRule = axf
nMoveRule = 0
nFoldRule = 3
```

→ `1 fixture failure: mx-chs-003: expected value 0 for claimable-draw/threefold-repetition, got -32000`.

The property is `promotedSoldiersChaseable`, default `true` (fork `src/position.cpp`:
`if (var->promotedSoldiersChaseable) chaseExempt ^= promoted_soldiers(sideToMove);`). The variant must set it
to `false`. The source change is necessary but not sufficient, and line 127 says only that a source change is
required — a reader following the contract builds a variant that loses a game the rules say is a draw.

**Which is right.** The fixture. `mx-chs-003` is approved and the README's normative stance (`:5`) puts it above
any engine behaviour.

**Severity.** Contradiction.

**Correction.** `engine-integration.md:124` becomes: "The custom variant disables the inherited move-count rule
with `nMoveRule = 0`, uses `nFoldRule = 3`, sets `promotedSoldiersChaseable = false` so `mx-chs-003` holds, and
preserves illegal-perpetual-check adjudication." Name the property at line 39 too.

### 2b. The identifier `minixiangqiaxf` means two different rule sets in the two pinned repositories

`docs/engine-integration.md:132` `[read]` — "The target variant's identifier is **`minixiangqiaxf`** … The name
is distinct from built-in `minixiangqi` so that the two can be selected unambiguously in the same build."

The fork's own test suite, `fs-chase/test.py:140` `[read]`:

```
[minixiangqiaxf:minixiangqi]
chasingRule = axf
nMoveRule = 0

[minixiangqiaxfsoldierexempt:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
```

In the fork, `minixiangqiaxf` is the variant **without** the soldier exemption — the one that fails
`mx-chs-003`. The exempt variant has a different name. So the identifier the app contract pins as its shipping
variant denotes, in the repository the app pins by revision, a variant with the opposite adjudication. The
stated reason for choosing the name (unambiguous selection) is defeated by exactly the ambiguity it was meant
to prevent. **Correction:** either rename the app's variant (`minixiangqimx` reads clearly), or record in
`engine-integration.md` that the fork's `minixiangqiaxf` test variant is a control and must be renamed in the
fork.

---

## 3. Gap — the accepted "no move-count draw" rule has no fixture, and cannot have one in this set

**Places.**

- `docs/xiangqi-rules.md:58` `[read]` — "Mini Xiangqi has no automatic move-count draw. A Fairy-Stockfish
  variant used by the app must explicitly disable the inherited move-count rule with `nMoveRule = 0`."
- `fixtures/rules/README.md:39` `[read]` — "The shared core's rules facade is gated by these fixtures on every
  platform."
- `docs/xiangqi-rules.md:88` `[read]` — "the fixtures — not engine agreement — are its authority".

**Executed.** The inherited value is real: `chess_variant_base` sets `nMoveRule = 50` (fork
`src/variant.h:124`) and `minixiangqi_variant()` never overrides it (`src/variant.cpp:1224`). From
`4k2/7/7/7/7/7/2K4 w - - 98 60`, two quiet plies:

| variant | at rule50 = 100 |
|---|---|
| `[…:minixiangqi] chasingRule=axf` (no `nMoveRule`) | `is_optional_game_end` → `(True, 0)` — draw |
| the same plus `nMoveRule = 0` | `(False, …)` — ongoing |
| built-in `minixiangqi` | `(True, 0)` — draw |

And the gate does not hold: the longest approved fixture is **9 plies** (`mx-chs-004`); with
`promotedSoldiersChaseable = false` and `chasingRule = axf` but **no** `nMoveRule = 0`, all 16 fixtures pass —
`0 failures`. A build that loses that one line ships a rule the contract forbids and the fixture suite is
silent.

**Which is right.** The rule. What is missing is its gate.

**Severity.** Gap (high — an accepted rule with zero executable coverage).

**Correction.** Add `mx-rep-002`: any start FEN with `… - 98 <n>` plus two quiet plies (a bare-kings shuttle
from `mx-rep-001`'s frame will do), asserting `game_state: ongoing`, with a `rationale` naming
`nMoveRule = 0`. The two-ply history keeps the file small while making the assertion exact.

---

## 4. Contradiction — the accepted chase-renewal rule contradicts itself in consecutive sentences

**Place.** `docs/xiangqi-rules.md:75` `[read]`:

> **A chase renews when the chasing piece attacks the target from the square it now occupies and did not attack
> it from that square before the move.** A chasing piece that steps **away** from its target and still attacks
> it from the new square therefore renews the chase, while one that merely advances **toward** the target along
> a line on which its attack already stood does not.

Sentence 1 is vacuous `[reasoned]`: a piece that has just moved is, by definition, on a square it did not
occupy before the move, so "did not attack it from that square before the move" is true of *every* move to a
new square. Read literally it makes every post-move attack a renewal, which is the opposite of what sentence 2
says for the advancing-along-the-line case.

**The engine implements sentence 2** `[read]`, fork `src/position.cpp`, direct-attack path:

```
if (movedPiece == ROOK || movedPiece == CANNON)
    directAttacks &= ~line_bb(from, to);
```

**Executed.** `c3k2/7/7/7/7/7/R1K4 w - - 0 1` — unprotected black cannon on a7, white rook shuttling a1↔a3 on
the a-file, black king shuttling e7↔e6. Moves `a1a3 e7e6 a3a1 e6e7 a1a3 e7e6 a3a1 e6e7`:

```
rook-along-line   ended=True rule=N_FOLD  -> DRAW
```

The rook attacks a7 from a3, and did not attack a7 "from a3" before the move. Sentence 1 makes this a
perpetual chase and a Red loss; sentence 2 and the engine make it a neutral repetition.

**Which is right.** Sentence 2 and the engine. Sentence 1 is a drafting failure, not a rule.

**Severity.** Contradiction (a self-contradictory accepted interpretation).

**Correction.** Replace sentence 1 with a formulation that carries the line:

> A chase renews when the moving piece attacks the target from its new square by an attack that did not exist
> before the move. For a chariot or a cannon, an attack along the line the piece travelled already existed and
> does not renew; every other attack from the new square does. A non-sliding chaser renews with every attack
> from its new square.

**Related gap:** this accepted interpretation has **no fixture** and is **not** in the deferred tranche list at
`xiangqi-rules.md:121` ("protection variants, interruption, discovered and pinned attacks, mutual perpetual
check, and check-over-chase precedence"), while `testing.md:93` makes verifying it a required rules test. Both
of the executed positions above are ready-made minimal fixtures for it.

---

## 5. Gap — the contracts pin chase *targets* but never pin who may be a *chaser*

**Places.**

- `docs/xiangqi-rules.md:66` `[read]` — "Kings and soldiers are excluded as perpetual-chase **targets**."
  Nothing anywhere restricts the chasing piece.
- `docs/xiangqi-rules.md:64`, `docs/engine-integration.md:125` `[read]` — both state the loss rule with no
  restriction on the chaser.
- The fork `[read]` gates the entire direct-attack classifier on the mover:
  `if (movedPiece != KING && movedPiece != SOLDIER) { … addChased(to, movedPiece, directAttacks); }`

**Executed.** `4k2/7/c6/1P5/7/7/2K4 w - - 0 1` — `mx-chs-001`'s shape with a white **soldier** on b4/a4 as the
chaser, renewing the attack on an unprotected black cannon fleeing a5↔b5. Moves
`b4a4 a5b5 a4b4 b5a5 b4a4 a5b5 a4b4 b5a5`:

```
soldier-chaser     ended=True rule=N_FOLD  -> DRAW
rook-chaser (ctrl) ended=True rule=PERP_CHASE -> BLACK wins    (mx-chs-001, unchanged)
```

Under the contract as written, the soldier case is a Red loss (an unprotected cannon, chased, three
occurrences). The engine calls it neutral.

**Which is right.** The engine `[reasoned]` — a soldier that captures a cannon is a favourable exchange for the
defender, so classical practice does not treat soldier pursuit as 捉. But the contract does not say so, and a
rule nobody wrote down is a rule nobody can review.

**Severity.** Gap (an accepted rule whose scope is decided entirely by unpinned engine behaviour).

**Correction.** Extend `xiangqi-rules.md:66` to: "Kings and soldiers are excluded as perpetual-chase targets,
and a move by a king or a soldier never constitutes a chase." Add a fixture from the executed position, and
note it in `engine-integration.md`'s rule-integration list at `:125`, which today mentions only targets.

---

## 6. Gap — `rules_version` is written into every archive but is invisible to the C interface and to import

**Places.**

- `docs/xiangqi-rules.md:84` `[read]` — "The accepted rules interpretation carries an integer version,
  `rules_version` … It is `1` … It increments only when an accepted interpretation change alters a legal move
  or a user-visible result."
- `docs/game-data.md:38, :40` `[read]` — `content.rules_version` is a required member; "a game's meaning
  derives from the rules contract (`rules_id` + `rules_version`), never from the engine build that played it."
- `docs/game-data.md:64` `[read]` — the validation order dispatches explicitly on `archive_version` only
  ("envelope and explicit version dispatch … unsupported versions with a distinct created-by-a-newer-version
  message"). `rules_version` is an integer, not one of the closed vocabularies at `:48`, so nothing validates
  or branches on it.
- `docs/core-interface.md:39` `[read]` — `MxqVersion` reports "the C API version, the archive format versions
  (current and minimum readable), the store schema version, and the engine profile identifiers"; `:243` — "The
  C API version, archive format version, store schema version, and engine profile are four independent axes."
  `rules_version` is a fifth axis and is reported by no function. `MxqArchiveInfo` (`:150`) does not carry it
  either.

**Failure scenario** `[reasoned]`. `rules_version` becomes 2 for exactly the reason the contract names — say
finding 1 above is resolved by adopting the stronger-piece class. A file exported at version 1, whose recorded
terminal pair is `draw`/`threefold-repetition`, is imported into a version-2 build. Import replays it through
the current facade, which now adjudicates a `perpetual-chase` loss, the terminal pair disagrees, and the file
is rejected as inconsistent — violating the accepted compatibility promise at `game-data.md:165` ("a game file
exported by any version of Mini Xiangqi can be imported by that version and every later version"). The core
cannot even tell the user which interpretation the file was written under, because nothing surfaces the value.

**Severity.** Gap.

**Correction.** Add `rules_version` (current, and minimum interpretable) to `MxqVersion`; add `rules_version`
to `MxqArchiveInfo`; and add one clause to `game-data.md:64`'s validation order stating what import does with a
non-current `rules_version` — the honest options are reject-with-a-distinct-message, or accept-and-skip the
terminal-pair agreement check while still requiring move legality. **Which one is the product owner's call**:
rejecting is safe and loses old games; accepting preserves the library and lets a record's recorded result
disagree with what the current rules would say about the same moves.

---

## 7. Contradiction — the threading table permits four functions inside the search callback that the prose forbids

**Places, both in `docs/core-interface.md`.**

- `:218` `[read]` — table row: "status/blob helpers, `mxq_core_version`, `mxq_engine_plan`,
  `mxq_rules_start_fen`, `mxq_archive_supported_versions` | **any thread, including callbacks** | no".
- `:236` `[read]` — "**The search callback must copy and return.** It runs on the engine thread; inside it,
  **only the status/blob helpers are legal** — anything else returns `MXQ_ERR_ARG_REENTRANT`".

`mxq_rules_start_fen` is a rules-facade function and is named in both. One says it is callable in a callback;
the other says calling it there returns an error code.

**Which is right** `[reasoned]`. The table. All four are pure or immutable-constant reads with no core state,
which is exactly why they are grouped together; the prose bullet was written about re-entrancy into *sessions*
and over-reaches.

**Severity.** Contradiction (an implementable ambiguity — the implementer must pick, and the two bindings could
pick differently).

**Correction.** `:236` becomes "inside it, only the non-blocking, state-free functions in the first row of the
threading table are legal — anything else returns `MXQ_ERR_ARG_REENTRANT`".

---

## 8. Gap — "the engine thread is the sole caller of every engine entry point" versus the rules facade's threading

**Places.**

- `docs/xiangqi-rules.md:88` `[read]` — the rules facade "is built on the pinned Fairy-Stockfish fork library".
- `docs/architecture.md:26` `[read]` — "The rules facade and search facade are two contracts over one pinned
  engine implementation."
- `docs/core-interface.md:214` `[read]` — "The core creates exactly one internal thread — the engine thread,
  **sole caller of every engine entry point**."
- `docs/core-interface.md:226–231` `[read]` — `mxq_rules_*` evaluation: "any thread except a callback",
  non-blocking; session queries: "session owner", non-blocking; session mutations: "session owner, off the UI
  thread". None is marshalled — in explicit contrast with `mxq_engine_prepare`/`teardown`, whose row says "work
  executes marshalled on the engine thread".

Every rules query — legal-move generation, move application, repetition and chase adjudication — runs
Fairy-Stockfish `Position` code. Whether that counts as an "engine entry point" is never defined, and the
answer changes the implementation: Fairy-Stockfish's variant table, `Options`, and `Bitboards`/`Position`
initialization are process-global mutable state, which is the very fact `core-interface.md:41` cites to justify
singleton-enforcing `MxqCore` ("the embedded engine's process-global state admits one instance"). Two
detached replay sessions on two threads, or a fixture harness running the target variant and its control side
by side, are permitted by the table and unaddressed by the sentence.

**Severity.** Gap (an unpinned concurrency contract on the correctness-critical path).

**Correction.** Define the term at `core-interface.md:214`: "engine entry point means the search and
transposition-table surface — everything under `mxq_engine_` and `mxq_search_`. Rules evaluation uses the
engine library's position representation and is safe to call from any thread, because it touches no
process-global engine state after `mxq_core_init` completes." Then say explicitly whether variant selection is
part of the immutable post-init state — which finding 10 also needs.

---

## 9. Gap — the fixture harness must select two engine variants, but the accepted C surface has no selector

**Places.**

- `docs/engine-integration.md:132` `[read]` — the name is distinct "so that the two can be selected
  unambiguously in the same build, **which the fixture harness requires in order to run a variant and its
  control side by side**."
- `docs/testing.md:143` `[read]` — "Verify the target variant `minixiangqiaxf` and built-in `minixiangqi` can
  both be selected in one build."
- `docs/core-interface.md:105` `[read]` — "`mxq_rules_evaluate` and `mxq_rules_legal_moves` … are exactly the
  surface the approved conformance fixtures replay through; a fixture's every assertion maps onto their
  outputs." Neither takes a variant. `MxqCoreConfig` (`:39`) carries only the store directory, asset directory,
  caller API version, and flags.
- `docs/architecture.md:78` `[read]` — the fixtures "must be executed by one harness producing identical
  results everywhere".

So the contract that owns the harness's surface offers no way to do what the contract that owns the variant
says the harness requires. `[reasoned]` The likely intent is that the side-by-side comparison is fork-side
research, not a core capability — but `testing.md:143` states it as a product verification, and `flags` in
`MxqCoreConfig` is too vague to carry it by implication.

**Severity.** Gap.

**Correction.** Either add a variant selector — the smallest version-1-compatible shape is a
`control_variant` flag bit in `MxqCoreConfig` plus a `variant` field on `MxqEngineBudget` — or move the
side-by-side requirement out of `testing.md`'s core section into the fork's own suite, and reword
`engine-integration.md:132` to say "which the fork's own conformance harness requires".

---

## 10. Gap — nothing pins that a naturally terminal position has no legal continuation

**Places.**

- `docs/xiangqi-rules.md:62` `[read]` — "A unilateral perpetual violation **becomes terminal automatically**
  when a position first stands on the board for the third time…"
- `docs/game-data.md:64` `[read]` — import requires "every move must be legal in sequence, and the recorded
  terminal pair must agree with the replayed adjudication (… `resignation` and `ended-early` require a
  non-terminal final position …)".
- `docs/xiangqi-rules.md:51` `[read]` defines "no legal move" only for checkmate and stalemate. Nothing says a
  position already adjudicated terminal by repetition offers no moves.

**Executed.** At `mx-chk-001`'s asserted terminal position (Red has lost by perpetual check), the engine still
returns a non-empty legal set: `['d7c7']`; one ply further the position has 14 legal moves. At
`mx-chs-001`'s terminal position, 14 legal moves. The adjudication is a property of the history, not a
movegen constraint.

**Failure scenario** `[reasoned]`. A crafted (or simply hand-edited) archive replays a completed perpetual-check
loss and then keeps playing. Every move is legal in sequence. The final position is not terminal, so
`ended-early` with `outcome = none` is accepted, and a game the rules say Red lost is recorded as having no
competitive result. Import's untrusted-input stance (`game-data.md:127`) is defeated without a malformed byte.

**Severity.** Gap.

**Correction.** State in `xiangqi-rules.md` beside line 62: "No move is legal in a position that the rules have
adjudicated terminal; a history that continues past a natural terminal result is invalid." Then
`game-data.md:64`'s "every move must be legal in sequence" carries the check with no further wording, and the
rules facade must report `MXQ_ERR_RULES_INVALID_HISTORY` with the first-illegal index at that ply.

---

## 11. Ambiguity — the fixture `variant` field duplicates `rules_id` under a colliding name

**Places.**

- `fixtures/rules/README.md:24` `[read]` — "`variant` — the ruleset identity the position is defined against;
  always `minixiangqi`. This names the Mini Xiangqi ruleset of the rules contract, **not an engine variant to
  select** … and the built-in engine variant of the same name does not satisfy every fixture."
- `docs/game-data.md:38` `[read]` — "`rules_id` (`minixiangqi`, the ruleset identity of
  [xiangqi-rules.md](xiangqi-rules.md), **not an engine variant**)".
- `docs/xiangqi-rules.md:84` `[read]` — "Game archives record `rules_id` (`minixiangqi`) and this version".

One concept, two field names, and the README has to spend a sentence warning that the value it chose is the
name of a real engine variant that fails two of the fixtures in the same directory. `[reasoned]` The warning is
evidence that the name is wrong: a field whose correct use requires a paragraph of disclaimer is a field that
will be misused by the first harness someone writes.

**Severity.** Ambiguity (a footgun, not a live defect — the harness I ran passes the variant explicitly).

**Correction.** Rename the fixture field to `rules_id`, matching `game-data.md`, and add a sibling
`rules_version: 1`. That also closes half of finding 6: the repository would then record which fixtures define
interpretation version 1.

---

## 12. Ambiguity — "Two accepted outcomes have no fixture" undercounts, and line 80 claims coverage that does not exist

**Places, all `docs/xiangqi-rules.md`.**

- `:111` `[read]` — "**Two** accepted outcomes have no fixture in this set: a mutual perpetual-check draw and a
  mixed sequence exercising check-over-chase precedence."
- `:80` `[read]` — "The first minimized fixture set below pins **these outcomes** in their simplest forms,
  position identity, and the third-occurrence adjudication point." Placed immediately after the three accepted
  interpretations at `:74–:76`, this reads as claiming fixture coverage for them.
- `:121` `[read]` — the deferred tranche is "protection variants, interruption, discovered and pinned attacks,
  mutual perpetual check, and check-over-chase precedence."

The three accepted interpretations at `:74–:76` all produce user-visible outcomes and none has a fixture.
Only one of them — general-as-sole-defender — plausibly falls under "protection variants". The alternating
check-and-chase interpretation and the chase-renewal interpretation appear in **neither** the fixture list nor
the deferred tranche, while `testing.md:93` makes verifying both a required rules test. `:74` itself calls the
alternation reading "the interpretation most likely to be wrong" — the one most in need of a pinned fixture is
the one with no plan to acquire one.

For the record `[executed]`, the engine does produce the accepted alternation outcome. Position
`3k3/7/c6/R6/7/7/2K4 w - - 0 1` — Red's rook checks on one move of the cycle (`a4d4`, checking d7) and chases
the unprotected cannon on a5 on the other (`d4a4`); moves `a4d4 d7e7 d4a4 e7d7 a4d4 d7e7 d4a4 e7d7` →
`ended=True rule=N_FOLD -> DRAW`, with no end at four plies. That is a ready-made minimal fixture, and it
strengthens the doc's own hedge at `:74`: the engine's outcome agrees, though for the stated reason that it
implements no combined rule rather than because it agrees.

**Severity.** Ambiguity.

**Correction.** Correct the count at `:111` to name all five uncovered accepted behaviours; add "the
alternation and chase-renewal interpretations" to the deferred tranche at `:121`; and reword `:80` so it does
not claim the first set pins the three interpretations.

---

## 13. Ambiguity — "king" and "general" are used for the same piece and never equated

**Places.**

- `docs/xiangqi-rules.md:42, :66` `[read]` — "A **king** moves one square orthogonally inside its palace";
  "**Kings** and soldiers are excluded as perpetual-chase targets".
- `docs/xiangqi-rules.md:75–76, :111` `[read]` — "A chase whose target's only defender is a **general**";
  "the flying-**generals** condition"; "**general**-move discoveries".
- `docs/engine-integration.md:43` `[read]` — "the accepted exclusion of **generals** and soldiers" versus
  `:125` `[read]` — "**kings** and soldiers are excluded as chase targets". Same document, two terms, one
  paragraph apart in effect.
- `fixtures/rules/mx-end-003.json` `[read]` — title "Flying **general**", pieces `k`/`K`.
- `docs/interaction-design.md:248` `[read]` — "**General** in check".

No document states that the two words denote the same piece. `[reasoned]` A reader can infer it; a reviewer
checking whether `engine-integration.md:43`'s exemption matches `xiangqi-rules.md:66`'s cannot do so by
matching terms, which is exactly the check this audit is for.

**Severity.** Ambiguity (low, but it costs a reviewer real time on every chase question).

**Correction.** One sentence in `xiangqi-rules.md`'s "Board and pieces": "This contract calls the piece the
**king**, which is the traditional 将/帅 (general); the two names are used interchangeably in Xiangqi
literature and the fixtures encode it as `k`/`K`." Then use "king" throughout the rules and engine contracts,
and leave "general" to `interaction-design.md`, where user-facing copy belongs.

---

## 14. Gap — small items that are correct today but rest on unpinned engine behaviour

Each of these is verified true in the pinned fork and unstated in the contracts. `[reasoned]` They are grouped
because each correction is one sentence.

- **The fifth FEN field bounds repetition detection.** `docs/xiangqi-rules.md:37` `[read]` — "The fifth field
  counts plies since the last capture and **drives no rule**". In the fork it drives two: it gates the n-move
  rule (which is why `:58` exists at all), and it bounds the repetition window —
  `end = std::min(st->rule50, st->pliesFromNull)` in `is_optional_game_end`. `mx-chs-003`'s asserted halfmove
  of 8 is correct only because Mini Xiangqi soldiers are `SOLDIER`, not `PAWN`, and `nMoveRuleTypes` defaults
  to `piece_set(PAWN)` `[executed, confirmed]`. **Correction:** "drives no user-visible rule; the engine uses
  it to bound repetition detection, so it must count plies since the last capture exactly as specified."
- **The engine's in-search repetition threshold is twofold, not threefold.** `docs/testing.md:96` `[read]`
  requires that between the app adjudicator and the engine search configuration "position identity, repetition
  **occurrence**, and draw classification must agree". The fork's n-fold walk `[read]` uses
  `++cnt + 1 >= (ply > i && … ? 2 : n_fold_rule())` — inside the search tree a *second* occurrence already
  scores as a draw. Occurrence agreement is unachievable by construction. `testing.md` is draft, so this is not
  yet normative; it should not become normative in this form. **Correction:** drop "repetition occurrence" from
  that clause and require agreement on position identity and on the root adjudication only.
- **The repetition-branch accessor is described as enabling only one of the two reserved reasons.**
  `docs/engine-integration.md:44` `[read]` — "A read-only accessor reporting which repetition branch fired, so
  the reserved **`mutual-perpetual-chase`** reason can be recorded." `docs/xiangqi-rules.md:68` and `:120`
  `[read]` likewise name only the chase side. The accessor as landed reports `OPTIONAL_END_PERPETUAL_CHECK`
  too, and `mutual-perpetual-check` needs it for exactly the same reason — a mutual check draws with a draw
  value and is otherwise indistinguishable from a neutral repetition. **Correction:** name both reasons in all
  three places.

---

## What I checked and found sound

Recorded so the negative results are as available as the positive ones.

- All 16 fixtures are internally consistent: I hand-verified every FEN, legal-move set, rejected move, applied
  probe, halfmove and fullmove counter, and occurrence count, and separately replayed all of them
  `[executed]`. `mx-move-001`'s 19-move opening set, `mx-move-003`'s screen counting, `mx-end-001`'s mate,
  `mx-end-002`'s stalemate-as-loss, `mx-end-003`'s seven legal and six rejected moves, and `mx-chs-004`'s
  "repeated position is not the setup position" claim are all exactly right.
- `engine-integration.md:128`'s claim that built-in `minixiangqi` fails exactly `mx-chs-001` and `mx-chs-004`
  `[executed]` — confirmed, no more and no fewer.
- The count "sixteen fixtures" at `xiangqi-rules.md:94`, the bullet list at `:96–:109`, the directory contents,
  and `engine-integration.md:49`'s "all 16 approved fixtures" all agree.
- The state and reason vocabularies agree across `xiangqi-rules.md:92`, `fixtures/rules/README.md:33`,
  `core-interface.md:101–103`, and `game-data.md:49–51`, including the deliberate `MxqOutcome`/`MxqGameStatus`
  split and the `none`/`ended-early` pairing.
- Check-over-chase precedence, the mutual same-class draw, the general-as-sole-defender flying-general test,
  and the king chase-target exemption are all implemented in the pinned fork exactly as the contract states
  `[read]`, in `is_optional_game_end`'s result expression and in `chased()`'s `chaseExempt` and `roots` logic.
- The parity correction has landed (`131784a4`), so `xiangqi-rules.md:65` and `engine-integration.md:45`
  describe a defect that is fixed in the pinned revision; both are written in the present tense ("The engine
  currently evaluates…"), which will read as stale the moment the manifest names this revision. Worth a
  tense pass, not a finding.
- The canonical move notation, `^[a-g][1-7][a-g][1-7]$` (`core-interface.md:206`), the `MxqMove.text[8]`
  capacity, and the frozen 6-field FEN with capacity 96 are consistent with `xiangqi-rules.md:36–37` and with
  every fixture.
