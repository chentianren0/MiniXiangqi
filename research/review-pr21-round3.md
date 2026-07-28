# Pre-merge review — PR #21 `design/engine-packaging`, round 3

Re-verification of `e9f1f8b` (three commits since round 2: `5730868`, `8f9a1d5`, `e9f1f8b`) against
`main` at `d357c4a`. Read-only throughout; nothing written to GitHub.

Prior reports: `review-pr21.md` (round 1), `review-pr21-round2.md` (round 2).

**Verdict: MERGE.** Both round-2 blocking findings are genuinely fixed, both should-fixes landed, and
the two new additions hold up. Two should-fixes remain, neither of which changes an implementer's
behaviour; I would take them in a follow-up rather than hold the merge.

---

## A. Round-two findings — verification

### A.1 B1 — both named lines fixed, and fixed consistently

`architecture.md:51` now reads:

> "…and **the platform's suspension signal** cancel outstanding work. Cancellation is cooperative. A
> result is rejected whenever its revision is stale, and independently whenever its request has been
> superseded: most cancellations follow a mutation and are caught by staleness, but a suspension
> cancels without mutating anything, so the revision still matches and the superseded request is the
> only thing that rejects it. Neither check alone covers both."

`core-interface.md:130` now reads:

> "…an un-cancelled in-flight search **that followed a mutation** is neutralized by staleness.
> Cancellation is nonetheless **a correctness requirement, not only a promptness optimization**: a
> cancellation that follows no mutation — the platform suspension path in
> [engine-integration.md](engine-integration.md) — leaves the revision matching, so the cancelled rung
> is the only one that rejects the late result."

Both corrections are complete and they agree with each other and with `engine-integration.md`'s "the
cancellation itself is what rejects it". The trigger word "app backgrounding" is gone from
`architecture.md`, which also closes the second half of B1 — the accepted trigger list no longer names
an event that the engine contract explicitly excludes on macOS and Windows. `core-interface.md` now
cross-references the owning document, so the delegation at `engine-integration.md:28` no longer leads
to a contradictory statement. **Resolved.**

### A.2 B2 — iOS memory pressure restored, and the Hash rule has a contract again

> "The trigger is **the platform's own suspension or memory-pressure signal**, not loss of focus. On
> iOS and iPadOS it is scene backgrounding, **and also a foreground memory-pressure warning** — the
> last signal before the system reclaims the process, on the platform where the per-process limit, the
> memory entitlements and up to 4 GiB of Hash all apply."

and, as its own bullet:

> "Every one of these paths cancels and releases whole. None shrinks Hash in place: a partially reduced
> transposition table is not a state this contract defines."

Both halves of B2 are fixed, and the restored bullet is scoped better than the round-1 original — it
covers *every* path rather than only the foreground memory-pressure case, so the surviving
`testing.md` gate ("takes the same cancel-and-release path and never shrinks Hash in place") now has
contract text behind it with margin to spare. **Resolved.**

### A.3 C1 — the P5 justification now matches the evidence

> "The classifier-path completion is different in kind and carries no fixture: a targeted search of
> 29,500 legal samples over 11.2 million cycles found **no** position where the gap changes an outcome,
> so it may well be unreachable. It is accepted not because a defect was demonstrated but because the
> accepted exclusion of kings and soldiers as chase targets should hold in every classifier path…"

Checked against `r-p4c.out` (29,500 legal samples, 11,192,728 cycles, 0 hits) and against
`rules-edge-cases-reconciliation.md` §3.5 ("a real code gap of unproven reachability, not a
demonstrated wrong result") and §6 ("A witness … **Not constructed**"). The claim "execution-confirmed"
is gone, the false fixture-gating clause is gone, and the reasoning now runs in the direction the
evidence actually supports. **Resolved**, and better stated than my suggested wording.

### A.4 C2 and C3

`Use NNUE` — now "does not change the `Use NNUE` option either — it clears the engine's *internal*
NNUE flag, so the option still reads true while the engine plays on classical evaluation." Matches
`evaluate.cpp:79-103` exactly. **Resolved.**

`interaction-design.md:486` — the routed question landed:

> "Define what a player sees when the engine cannot be re-prepared mid-game, after the app was
> suspended and the AI is due to move. The accepted **无法启动 AI 对手** notice assumes a game that has
> not started, so neither its wording nor its **取消** action fits; the game itself remains active,
> saved, and resumable throughout."

Names the notice, the 取消 mismatch and the invariant. **Resolved.**

---

## B. New material — the seventh fork change

### B.1 The bullet describes the defect accurately

> "**Correction of the repetition window's parity asymmetry**, which evaluates one side over a wider
> span than the other. In a unilateral chase this costs one ply of detection. In a mutual perpetual
> chase it is terminal: the draw the contract requires is adjudicated as a unilateral loss, and which
> of two equally violating sides loses depends only on which of them made the move that entered the
> position."

Checked clause by clause against `investigate-chase-window-parity.md` and against the source:

- "evaluates one side over a wider span" — `chaseUs` is extended after the three-occurrence test
  (`position.cpp:2716`), `chaseThem` before it (`:2694-2695`), so `chaseThem` additionally intersects
  the chase set of the move that *created* the first occurrence, outside the window. Since it is an
  intersection, the surplus term can only delete. Verified in source and in §1.1-1.2.
- "costs one ply of detection" in the unilateral case — matches the executed result: every one of the
  53 splits is `9 plies = draw, 10 plies = decisive` unpatched.
- The mutual-chase claim — matches the executed reproduction: "20 of the 26 entry moves into that
  position turn the draw into 'Black loses' at the ninth ply, while the identical wheel one ply later
  is a draw."

The bullet is if anything more careful than the reconciliation, which treated the mutual corner as a
secondary aggravating factor; the investigation concluded the opposite and the contract follows the
investigation. Accurate.

### B.2 The restated bar is honest

> "Preserving other variants' adjudication exactly is the preferred bar and the first patch met it, but
> it is not absolute, and the parity correction is the accepted exception. It is not a rules difference
> that a variant property could express — the repetition window is the same rule in every chasing
> variant — so gating it would mean carrying a second code path whose only purpose is to preserve the
> defect for variants this product does not ship."

This is the question I most wanted to test, and it passes. The paragraph does not hide the cost: it
states in the next sentence that the correction removes 53 parity splits *in built-in `xiangqi`*,
which is exactly the admission that the old bar ("leave built-in variants' adjudication unchanged")
is not met. The exception is named, singular, and attached to one identified change rather than left
open. The merit argument is a faithful compression of §4.6's reasoning — that unlike the soldier
exclusion, which encodes a genuine rules difference and is the right shape for a variant property,
this one would ship a property meaning "apply the repetition window consistently", preserving a bug
for variants the product does not ship.

One asymmetry worth noting, as a nit rather than a defect: the contract frames gating as a cost
("carrying a second code path"), while the investigation says gating is "**mechanically, yes and
trivially**" — three lines plus a documented property. The honest framing is that gating is cheap and
rejected on merit, not on cost. The merit argument carries it on its own, so nothing turns on this.

### B.3 The measurements are now accurate

The round-2 text credited the 53 to the 1,786-history differential. The restatement separates them
correctly, and each number checks out against `investigate-chase-window-parity.md` §4.4:

| claim | evidence | verdict |
|---|---|---|
| "the fork's 22 tests pass on both builds" | "`Ran 22 tests … OK` on both" | ✓ |
| "all 16 approved fixtures pass identically" | "byte-identical output, `target variant: 0 failure(s)` on both" | ✓ |
| "a broad 1,786-history differential shows no difference at all" | "**0 differing lines of 1786**" | ✓ |
| "53 parity splits in built-in `xiangqi`, every one of them removed" | targeted sweep, 117 entries, 53 → 0 | ✓ |
| "every one changing a `draw` into the verdict the unpatched engine already reaches one ply later" | "Every one of the 53 is `9 plies = draw, 10 plies = decisive` … patched `9 plies = decisive`" | ✓ |

The separation matters and is now right: the investigation explicitly warns that the 1,786-history
corpus "does *not* show xiangqi is unaffected — the corpus simply did not contain the defect's shape",
and the contract no longer implies otherwise. The "one ply later" clause is correctly scoped to the 53;
the other transition direction (a wrongly-decisive mutual chase becoming the required draw) is carried
by the bullet above it, so both directions appear and neither is overstated.

### B.4 The seventh change breaks nothing verified earlier — checked

- **The fixture harness control is safe.** `chasingRule = AXF_CHASING` is assigned in exactly one
  place, `variant.cpp:1750` in `xiangqi_variant()`. Built-in `minixiangqi` derives from
  `chess_variant_base()` and does not set it, and `position.cpp:598`
  (`si->chased = var->chasingRule ? chased() : Bitboard(0)`) makes every `chased` empty, so both
  accumulators are identically zero on either code path. The control side of the "run a variant against
  its control" claim I verified in round 1 is a provable no-op. Independently confirmed; `manchu` and
  `supply` derive from `xiangqi_variant_base()` and are likewise unaffected.
- **Variant packaging and NNUE are untouched** by this change.
- **The grounding is the strongest in the change set.** "…[xiangqi-rules.md](xiangqi-rules.md) records
  the rule it restores" — `xiangqi-rules.md:67`, "When both sides commit the same class of perpetual
  violation, the result is a draw", sits inside the accepted "high-level perpetual-check and
  perpetual-chase outcomes". So unlike P1 and P2, which rest on definitions that document still
  defers, the parity correction restores an outcome that is already accepted. The round-1 concern about
  citing deferred text does not apply to this item.
- **The `testing.md` gate tracks the new bar exactly.** The bar is now "keep the fork's own suite
  passing and every approved fixture passing"; the gate added in round 2 reads "Verify the complete
  approved fixture set passes against the pinned fork build named in `pinned-inputs.json`, and that the
  fork's own suite still passes, before that revision is packaged." No orphaned gate was left behind by
  dropping the old "leave built-in variants' adjudication unchanged" clause.
- **`rules_version` does not need to move.** `xiangqi-rules.md:75` increments it only for "an accepted
  interpretation change", never for "engine or fork revisions". The interpretation is unchanged here —
  the engine was wrong about an already-accepted outcome — so leaving it at 1 is right.

---

## C. Should-fix

### C.1 "every variant except `xiangqi` and our own" understates the blast radius by two

> "The change is provably inert for any variant that does not set a chasing rule, **which in the fork
> is every variant except `xiangqi` and our own**."

The first clause is verified true. The enumeration is not. The fork's own `variants.ini` ships two
sections that inherit from `xiangqi`:

- `[xiangqihouse:xiangqi]` — `variants.ini:373`
- `[crowdedxiangqi:xiangqi]` — `variants.ini:1234`

Neither overrides `chasingRule`, and ini inheritance is a full copy-construct —
`new Variant(*variants.find(variant_template)->second))->init()` at `variant.cpp:2186` — while
`Variant::init()` (`variant.h:222-227`) resets only `nnueAlias` and `endgameEval`. So both inherit
`chasingRule = AXF_CHASING` and are inside the blast radius; neither was covered by the targeted sweep,
which measured built-in `xiangqi` only.

This does not change the decision — both are the same variant family with the same repetition rule, so
the same "agrees with the answer it already gives one ply later" reasoning applies, and neither ships
in this product. But it is the sentence whose job is to bound the blast radius in the paragraph that
relaxes an accepted bar, so it should be right. (The investigation's §4.3 has the same gap: it grepped
`variant.cpp` and wrote "plus any `variants.ini` variant that sets `chasingRule`", which misses
inheritance.)

**Correction.** "The change is provably inert for any variant that does not set a chasing rule. In the
fork that leaves built-in `xiangqi`, the two `variants.ini` variants that inherit from it —
`xiangqihouse` and `crowdedxiangqi` — and our own; the measurements above cover built-in `xiangqi`."

### C.2 The parity correction is the only one of seven with no stated fixture expectation

The section now says P1 and P2 "each lands together with the fixture that pins it", and says the
classifier-path completion "carries no fixture" and why. Between those two explicit statements, the
parity correction is silent — and it is the one change that alters a shipped built-in variant's
adjudication in 53 measured cases.

More specifically, its headline justification has no test anywhere. `mx-chs-030`/`031`/`032` pin the
unilateral parity split; the **mutual-chase wrong-winner corner** — the reason the bullet gives for the
change being terminal rather than a one-ply delay — has no fixture in the reconciliation's slate at
all. The investigation asks for one by name and says why:

> "add one more fixture the reconciliation does not have: the mutual-chase parity pair from §3 …
> Without that fixture the wrong-winner corner is untested and **would silently return if the hunk is
> ever lost in an upstream merge**."

Because the new normative bar is "keep the fork's own suite passing and every approved fixture
passing", and none of those four fixtures is approved yet, the accepted contract currently permits the
parity correction to land with no regression gate on the behaviour it exists to fix.

**Correction.** Add one sentence after the measurements: "The parity correction lands together with
`mx-chs-030`, `mx-chs-031` and `mx-chs-032`, and with a mutual-chase parity fixture pinning the
wrong-winner corner, so the behaviour it restores cannot silently regress in a later upstream merge."

---

## D. Nits carried over from round 2 (none fixed, none blocking)

1. "Its Makefile currently produces an executable and a Python module" — `src/Makefile` has no Python
   target; `setup.py` builds the module.
2. "Landed;" is delivery status in a contract; the manifest's pinned revision is the record.
3. The new "Verify each platform's memory probe against the accepted budget boundaries on real
   hardware" gate still duplicates the pre-existing probe gate, which was never updated to name the
   now-fixed APIs.
4. macOS probe: free + inactive + purgeable double-counts and over-reports under memory compression.
   Deferred by an open item, so not urgent.
5. "then the store's outstanding work" still names a teardown step with no entry point in the
   53-function surface.
6. The round-1 gate clause "that the committed game is unchanged throughout" is still absent, while the
   contract still says "The committed game is never affected."
7. "Its structural loading with the current local `minixiangqi` engine has been verified" now sits
   beside the renamed file and reads as if it verified the bundled artifact; it verified the *built-in*
   variant.
8. The status line accepts "the pinned-input manifest" while an open item defers its schema.
9. New: the gating-cost framing in B.2 above.

---

## Verdict

Nineteen of nineteen round-1 findings and all four round-2 findings are now resolved. The two
additions are accurate, the restated bar is honest about the cost it accepts, and the seventh fork
change is provably inert for the fixture harness's control variant and better grounded in
`xiangqi-rules.md` than the two corrections that preceded it. The two remaining should-fixes — an
under-counted blast radius and a missing fixture expectation — are documentation completeness, not
implementation risk.

**MERGE**
