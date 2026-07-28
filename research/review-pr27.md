# Independent pre-merge review — PR #27, `fixtures/edge-case-tranche`

**Reviewer stance.** The authority is `docs/xiangqi-rules.md` as accepted, together with the
selected public rules source that `fixtures/rules/README.md` names as the second authority
("every expected value in a fixture comes from the accepted rules contract and the selected
public rules source, never from what any engine returns"). Engine agreement is not evidence
of correctness. I derived every expectation myself before reading what the fixture claims.

**Method.** I wrote an independent Mini Xiangqi model from the contract text alone
(`/tmp/pr27-model/mxq.py`, `chase.py`, `chase2.py`) — board, movement, palace confinement,
flying general, legality, FEN round-trip, counters, position identity, repetition counting —
and a separate adjudicator (`/tmp/pr27-model/chase2.py`) implementing **only** the rules the
contract states. No engine is consulted anywhere in that model. I then ran a rule-mutation
sweep (`mutate.py`, `mutate2.py`) that disables one contract rule at a time to test whether
each fixture actually discriminates the rule it claims to pin.

**Headline.** The mechanical layer is flawless: 51/51 fixtures replay exactly, every FEN,
counter, check state, legal set, probe and occurrence index reproduces. Integrity, schema and
identifiers are clean. But **six fixtures assert outcomes that do not follow from the accepted
contract, and five of those contradict it**, and **one fixture asserts a game state at a ply
the contract says the game has already ended** — the same defect class the tranche itself
rejected `mx-chs-031` for. Verdict at the end.

---

## 1. Every one of the 35 new fixtures, derived independently

### 1.0 Mechanical replay — clean

```
$ python3 /tmp/pr27-model/check.py
51 fixtures
...
=== 2 model disagreement(s) ===
  mx-chs-022: VACUITY RISK third occurrence of some position first reached at ply 8, asserted ply is 12
  mx-chs-032: VACUITY RISK third occurrence of some position first reached at ply 9, asserted ply is 10
```

Zero disagreements on `result_fen`, `in_check`, `legal_moves`, `rejected_moves`, `applied`,
move legality, halfmove/fullmove arithmetic, or `at_occurrence`. Both flagged items are
analysed in §2. No start position is illegal (the side not to move is never in check).

### 1.1 Contract-only adjudication

```
$ python3 /tmp/pr27-model/run2.py gloss
...
6 disagreement(s) of 42
```

The model implementing only the contract's stated rules reproduces **36 of 42** history
fixtures exactly, including all 16 approved ones. The six divergences are listed below.

### 1.2 The decisive quotations

`docs/xiangqi-rules.md`:

> L64 — "A unilateral perpetual chase of the same **unprotected** target is a loss for the chasing side."
> L66 — "**Kings and soldiers are excluded as perpetual-chase targets.**"
> L78 — "AXF does not replace the selected public source as the user-visible rules authority."

The selected public source, retained at
`discussion-drafts/evidence/pychess-minixiangqi-rules-2026-07-26.html`
(SHA-256 `a79b663…92077`, matching `xiangqi-rules.md:17` exactly):

> "The side that perpetually chases any one **unprotected** piece with one or more pieces,
> excluding generals and soldiers, will be ruled to have lost unless he or she stops such chasing."

Neither authority contains a piece-value rule, a same-type exclusion, or anything making a
**protected** piece chaseable.

### 1.3 The six divergences

#### `mx-chs-014` — **BLOCKING**

> `"title": "A horse chasing a protected chariot is still a chase"` → `"state": "black-wins", "reason": "perpetual-chase"`
> rationale: *"an attack by a horse or a cannon on a chariot is a chase independently of protection, because the capture wins material even after the recapture"*

The chased chariot is protected on **both** squares of the shuttle — verified directly under
the contract's own protection notion (a legal recapture exists after the capture):

```
=== 014 : is the chased chariot protected? ===
  after ply 1: black chariot on d5 protected = True
  after ply 3: black chariot on c5 protected = True
```

The fixture therefore asserts a perpetual-chase **loss against a protected target**. Contract
L64 says the target must be unprotected; the public source says "any one unprotected piece".
The value rule appears in neither authority. The project's own reconciliation document says so
in as many words (`discussion-drafts/rules-edge-cases-reconciliation.md:390`):

> "The horse-or-cannon-versus-chariot clause is **an addition the retained source does not
> literally support**; the contract should record the reasoning rather than imply the source says it."

Model verdict: `claimable-draw / threefold-repetition`. The only mutation that flips it is
"AXF value rule" — a rule the contract does not contain.

**Correction:** either amend `xiangqi-rules.md` to state the value rule as a fourth accepted
interpretation (with its exposure recorded, as the other three are), or reject the fixture.
It cannot land while L64 says "unprotected".

#### `mx-chs-016` — **BLOCKING**

> `"title": "Chariot against chariot is a mutual attack, not a chase"` → `"state": "claimable-draw"`
> rationale: *"A target of the same type as the attacking piece is nevertheless not a chase target"*

The black chariot is **unprotected** (the black king on d7 defends neither d5 nor d4) and is
neither a king nor a soldier, so under L64 + L66 and under the public source this is a
perpetual chase and Red loses. The same-type exclusion exists in neither authority.

Model verdict: `black-wins / perpetual-chase`. Only "AXF same-type exclusion" flips it.

**Correction:** amend the contract to state the same-type exclusion (the reconciliation
document drafts the prose at §4 Q6), or reject.

#### `mx-chs-018` — **BLOCKING**

> `"title": "A soldier's move never creates a chase"` → `"state": "claimable-draw"`
> rationale: *"A soldier takes no part in the chase rule as a chasing piece"*

The fixture's own rationale concedes the attack is real: *"the white soldier genuinely attacks
the undefended black cannon after each of its moves — a3 attacks a4 and b3 attacks b4, and the
capture is legal."* Contract L66 excludes kings and soldiers **as targets**; nothing excludes
them as chasers. Under the contract as written this is a chase of an unprotected cannon and
Red loses.

This is not a technicality. The reconciliation document identifies the exact source of the
problem (`rules-edge-cases-reconciliation.md:388`):

> "the source phrase 'with one or more pieces, excluding generals and soldiers' is
> **grammatically ambiguous** between the chasing pieces and the chased piece. The engine
> implements **both** readings and both are standard AXF practice; **the accepted contract
> states only the target reading, and the attacker reading should be added.**"

That amendment has not been made. `mx-chs-018` silently adopts the second reading.

Model verdict: `black-wins / perpetual-chase`. Only "AXF chaser K/P excluded" flips it.

The fixture's own control claim *is* sound — I had it checked against the engine: replacing the
soldier with a chariot (`4k2/7/7/c6/1P5/7/2K4` → `4k2/7/7/c6/1R5/7/2K4`, identical eight-move
wheel) turns `(True, 0)` into `(True, −32000)`, and the soldier's capture really is in the
legal set at plies 0, 2, 4, 6, 8. So it is a meaningful negative — of a rule the contract lacks.

#### `mx-chs-019` — **BLOCKING**

Identical analysis with a king as the chaser; the rationale again concedes *"the white king
genuinely attacks the undefended black cannon after each of its moves … and the capture is
legal."* Model verdict `black-wins / perpetual-chase`.

Its control claim also holds, with a caveat worth recording: a literal chariot-for-king
substitution is not constructible, because the shuttling piece *is* the king and the palace plus
flying general force the relocated king off the file. Two independently scaffolded controls
(`4k2/7/7/7/3c3/2R1P2/4K2` and `4k2/7/7/4P2/3c3/2R4/4K2`) both return `(True, −32000)` against
the fixture's `(True, 0)`, so the verdict is not an artefact of the scaffolding.

**Correction for 018/019:** add the attacker reading to `xiangqi-rules.md:66`
("Kings and soldiers take no part in the perpetual-chase rule as targets **or as chasing
pieces**"), or reject both fixtures.

#### `mx-chs-029` — **BLOCKING** (and it is one of the three patch-gated fixtures)

> `"state": "claimable-draw"`, rationale: *"Both chariots are undefended and attack each other
> on equal terms, which **the same-type exclusion** makes a mutual attack rather than a chase"*

The pin half of this fixture **is** contract-grounded: `docs/engine-integration.md:42`
(Status: *Accepted engine contract*) names the P2 defect explicitly — *"a flying-general pin
test that counts only the victim's own pieces on the shared file, so a chaser standing between
the two generals is invisible to it and a demonstrably free piece is marked pinned."* The white
soldier on c2 is exactly that extra blocker.

But the **outcome** does not follow. Correcting the pin only matters if a same-type target is
excluded; without that unstated rule, White chases an unprotected chariot and Red loses whether
or not the black chariot is pinned. So `mx-chs-029` makes the gating of an accepted fork
correction depend on a rule the contract does not have. Model verdict: `black-wins /
perpetual-chase`; only "AXF same-type exclusion" flips it.

**Correction:** land the same-type amendment first, or re-gate P2 on a position where the pin
is decisive on its own.

#### `mx-chs-028` — **ACCEPT** (divergence explained by an accepted contract)

My contract-only model says `black-wins`, the fixture says `claimable-draw`. The difference is
"a chaser that cannot legally make the capture is not chasing", which `xiangqi-rules.md` does
not state — **but `engine-integration.md:42` does**, as an accepted wrong-result defect
("a chaser counted as chasing while pinned"), and `:51` confirms each such correction "lands
together with the fixture that pins it". `mx-chs-028` is that fixture. It is also the exact
mirror of `mx-chs-005` (a pinned *defender* does not protect), which I derive independently.
No objection.

### 1.4 Two fixtures whose answer is right but whose stated content is not

- **`mx-chs-017` — should-fix.** Expectation `black-wins` matches my model, but only by
  accident: under the contract as written `mx-chs-016` is *also* `black-wins`, so the 016/017
  pair — which exists solely to isolate the same-type exclusion — carries **zero** information
  until that rule is in the contract. Worse, the fixture is fragile: under the *literal* first
  sentence of the accepted renewal interpretation (L75) it becomes
  `draw / mutual-perpetual-chase`, because Black's chariot alternately attacks the white
  chariot on d1 down the same file.

  ```
  $ python3 /tmp/pr27-model/run2.py literal
  [DIFF] mx-chs-017   model=('draw', 'mutual-perpetual-chase')  fixture=('black-wins', 'perpetual-chase')
  ```

  Only the *gloss* sentence ("merely advances toward the target along a line on which its
  attack already stood does not [renew]") saves it. The rationale never mentions that Black has
  a counter-threat at all. **Correction:** state in the rationale that Black's d-file threat on
  the d1 chariot does not renew under L75's gloss, and note the dependence on the same-type
  exclusion.

- **`mx-chs-015` — should-fix (rationale only).** `claimable-draw` is correct and follows
  directly from L64 (the target is protected). But the rationale justifies it with the
  unsupported value rule — *"The horse and the cannon are treated as equals, so no value
  relation overrides the defence"* — which is a claim about a rule the contract does not have.
  **Correction:** rewrite the rationale to rest on "protected", which is what the contract says.

### 1.5 The remaining 27 new fixtures — derived and confirmed

Each of these I derived independently from the contract before comparing, and my model agrees:

| Fixture | Contract basis I used | Verdict |
|---|---|---|
| `mx-chk-003` | L63 loss for the checking side; battery check is a check | agrees |
| `mx-chk-004` | L63; attribution to the delivering side, not the side standing in check | agrees |
| `mx-chs-005` | L64 "unprotected": a pinned defender cannot legally recapture | agrees |
| `mx-chs-006` | L64 base case | agrees |
| `mx-chs-007` | protection judged after the capture (X-ray) | agrees |
| `mx-chs-008` | soldiers excluded as targets/chasers, not as defenders | agrees |
| `mx-chs-009` | **L76** general-as-sole-defender, flying general voids it | agrees |
| `mx-chs-010` | **L76** positive half | agrees |
| `mx-chs-011` | **L76** the accepted under-detection | agrees |
| `mx-chs-012` | L29/L42 palace confinement ⇒ no recapture outside the palace | agrees |
| `mx-chs-013` | L46 cannon capture needs exactly one screen | agrees |
| `mx-chs-020` | L62 "sustained across its occurrences" | agrees |
| `mx-chs-021` | L62 sustained; a king move never chases | agrees |
| `mx-chs-022` | L59 "the repeated position need not be the game's initial position" | agrees |
| `mx-chs-023` | L59 counts occurrences, not cycle length | agrees |
| `mx-chs-024` | L64 "the same … target"; source "any **one** unprotected piece" | agrees |
| `mx-chs-025` | source "with **one or more** pieces" | agrees |
| `mx-chs-026` | source "with one or more pieces"; discovered threat | agrees |
| `mx-chs-027` | **L75** renewal from a new square (step-away) | agrees |
| `mx-chs-030` | L65 parity independence; L75 advance-along-line renews nothing | agrees |
| `mx-chs-032` | same — but see §2, the ply is unreachable | agrees on value |
| `mx-chs-033` | L64 + discovered threat | agrees |
| `mx-chs-034` | L64 + discovered threat, other colour | agrees |
| `mx-mix-001` | L67/L68 mutual check ⇒ draw, reserved reason | agrees |
| `mx-mix-002` | L68 mutual chase ⇒ draw, reserved reason | agrees |
| `mx-mix-003` | **L74** alternating check and chase commits neither | agrees |
| `mx-mix-004` | **L67** check outranks chase unconditionally | agrees |

Per-ply check-flag strings, computed independently, confirm three claims made in rationales:

```
mx-mix-001: TTTTTTTTT   (claimed: in check at all nine plies)          OK
mx-mix-003: fTfffTfff   (claimed: "f T f f f T f f f")                  OK
mx-chs-027: fffffffff   (claimed: "No ply is a check")                  OK
mx-mix-002: fffffffff   (claimed: "neither side ever gives check")      OK
```

I also verified `mx-mix-002`'s start FEN is exactly the piece-union of `mx-chs-033` and
`mx-chs-034` and that all three share one move list — a genuinely well-built trio.

### 1.6 The gap is exactly four rules, and it closes cleanly

Adding **only** these four unstated rules to my contract model — same-type exclusion (with the
pinned-target carve-out), the horse/cannon-vs-chariot value rule, kings and soldiers excluded
as chasers, and the pinned chaser — makes the tranche fully self-consistent:

```
Contract model + the 4 unstated AXF rules (incl. the pinned-target carve-out):
  disagreements: NONE — all 42 history fixtures reproduce exactly
```

So the tranche is not incoherent. It is coherent **against a contract that has not been
written**. `discussion-drafts/rules-edge-cases-reconciliation.md` §4 Q1–Q6 already drafts that
prose "suitable for lifting into `docs/xiangqi-rules.md`". PR #27 ships the executable half and
omits the prose half.

### 1.7 The structural finding — **BLOCKING**

`fixtures/rules/README.md:3` (unchanged by this PR):

> "The fixtures and `docs/xiangqi-rules.md` **form one contract and are reviewed together**:
> a change to either is a rules-contract change."

`docs/xiangqi-rules.md:5` (unchanged by this PR):

> "The exact definitions of protection, interruption, and discovered and pinned attacks …
> **remain unresolved**. Items under **Need to discuss** are non-normative and
> **do not authorize implementation**."

`git diff main...fixtures/edge-case-tranche --name-only -- docs/` returns nothing. Merging as-is
produces a contract whose prose says protection is undefined while 20+ executable fixtures
define it, and whose L64/L66 are contradicted by four of its own fixtures. Nine specific lines
go stale on merge (5, 68, 80, 92, 94, 111, 119, 120, 121).

Related: `xiangqi-rules.md:84` — `rules_version` "increments only when an accepted
interpretation change alters a legal move or a user-visible result — never for … fixture
additions that pin existing behavior." `mx-chs-014`, `016`, `018`, `019` alter user-visible
results relative to the contract as written, so this is not a behaviour-pinning addition and
`rules_version` should go 1 → 2. It does not.

**Correction:** land the Q1–Q6 prose (or a reviewed subset) into `docs/xiangqi-rules.md` in the
same change, move the resolved items out of **Need to discuss**, and bump `rules_version`.

---

## 2. Vacuity

### 2.1 `mx-chs-032` asserts a game state one ply after the game has ended — **BLOCKING**

This is the defect the tranche rejected `mx-chs-031` for, applied to a fixture's **main
assertion** rather than to its boundary.

```
$ python3 /tmp/pr27-model/bnd.py
=== mx-chs-032: is the game already over before its asserted ply? ===
  after  8 plies: ongoing (occurrence 2)
  after  9 plies: black-wins/perpetual-chase (occurrence 3)
  after 10 plies: black-wins/perpetual-chase (occurrence 3)

=== mx-chs-030 vs mx-chs-032 prefix identity ===
  same start_fen: True
  032[:9] == 030: True   extra move: ['a5b5']
```

`mx-chs-032`'s nine-ply prefix **is** `mx-chs-030`, which the contract makes an **automatic**
terminal (L62: "becomes terminal automatically when a position first stands on the board for
the third time"). Unlike a claimable draw, the user cannot elect to continue. So ply 10 does
not exist for a conforming core.

**The two are structurally identical.** I reconstructed the rejected `mx-chs-031` from its
specification in `rules-edge-cases-reconciliation.md:487` and ran it through the same model:

```
=== the REJECTED mx-chs-031 (asserts at ply 9) ===
  after 8 plies: black-wins/perpetual-chase (occurrence 3)
  after 9 plies: black-wins/perpetual-chase (occurrence 3)

=== the MERGED mx-chs-032 (asserts at ply 10) ===
  after 9 plies:  black-wins/perpetual-chase (occurrence 3)
  after 10 plies: black-wins/perpetual-chase (occurrence 3)
```

The PR's account of why `mx-chs-031` was excluded is accurate — the position does recur at
plies 0, 4 and 8 and the contract does make it a completed loss at ply 8, one ply before the
assertion. But `mx-chs-032` has the same defect at the same distance, and it is being merged.
The tranche applies its own standard to one fixture and not the other.

The fixture discloses this — *"this history is a probe of the adjudication function rather than
a playable continuation"* — but disclosure does not make it satisfiable. `README.md:40` defines
consumption as: *"each fixture's history must replay with exactly the asserted legality,
positions, check states, and game states."* A core that satisfies `mx-chs-030` must refuse
move 10; a core that satisfies `mx-chs-032` must play it. **The two fixtures cannot both be
satisfied under the documented consumption model.** That is worse than the `mx-chs-031` defect
that was rejected, and it is being merged.

**Correction — and there is precedent for it in the tranche's own base set.** `mx-chk-001` and
`mx-chk-002` pin the identical wheel at both parities using **two different start FENs**, each
reaching its own third occurrence at ply 8, with no continuation past a terminal. Re-cut
`mx-chs-032` the same way: give it a start position phased one ply differently (e.g. one that
enters the same wheel with Black to move first) so its third occurrence is genuinely the first
terminal in its own history. Alternatively, extend the README schema to define a non-playable
"adjudication probe" as a distinct fixture kind, and re-review. Merging it as an ordinary
fixture is not an option consistent with rejecting `mx-chs-031`.

I checked that the pair's substantive claim survives that re-cut: both fixtures judge the
**identical** four White moves, so parity independence really is the whole content.

```
030 window=1..9  judged White plies=[2, 4, 6, 8]  targets={'c@a5'}
032 window=2..10 judged White plies=[2, 4, 6, 8]  targets={'c@a5'}
```

### 2.2 `mx-chs-022` — not vacuous, correctly constructed

The other flag from §1.0. At ply 8 the position reaches its third occurrence, but the span
carries the king-move interruption, so the contract makes it a **claimable** draw — non-terminal
— and the user may continue to ply 12.

```
=== mx-chs-022: is the game already over before its asserted ply? ===
  after  8 plies: claimable-draw/threefold-repetition (occurrence 3)
  after 12 plies: black-wins/perpetual-chase (occurrence 4)
```

Its boundary text says exactly this. No defect.

### 2.3 Every boundary claim verified

All 42 boundaries: the prefix position stands at occurrence 2 (occurrence 3 for `mx-chs-022`,
as its text states) and the asserted "not yet terminal / not yet claimable" is true under my
model. No boundary is one ply past a terminal except as covered in §2.1. `prefix_len` is
strictly inside range everywhere and always exactly one repetition cycle earlier.

**Weakness in the harness, not the fixtures (nit):** for a fixture asserting a *loss*, the
boundary check only fails when the prefix ended with a **non-zero** value
(`engine-fixture-check.py:120`). A wrong early *draw* at the boundary of a loss fixture would
pass silently. That is deliberate (it is what lets `mx-chs-022` work) but it means the boundary
of every loss-asserting fixture tests only "not terminal", not "not claimable".

### 2.4 Discrimination — does each fixture fail if its rule is removed?

Rule-mutation sweep, one rule disabled at a time. Every new fixture is flipped by at least one
mutation, i.e. none is dead weight:

| Rule removed | Fixtures that flip |
|---|---|
| protection ignored | `chs-002, 007, 008, 010, 011, 014, 015` |
| kings/soldiers chaseable as targets | `chs-003` |
| renewal = literal / strict-new | `chs-017, 025, 026, 027, 033, 034`, `mix-002` |
| window = whole game (drop P3) | `chs-022, 030, 032` |
| threshold = 2 occurrences | `chs-021` + every boundary |
| general judged strictly | `chs-011` |
| general never protects | `chs-010, 011` |
| "sustained by every move" dropped | `chs-007, 008, 010, 011, 014, 017, 020, 021, 024, 027`, `mix-003` |
| chase outranks check | `mix-004` |
| protection: pinned defender still protects | `chs-005` |
| protection: judged before the capture (no X-ray) | `chs-007, 013` |
| protection: king protects outside its palace | `chs-009, 012` |
| protection: cannon protects without a screen | `chs-013` |
| soldiers cannot defend | `chs-008` |
| discovered chase not counted | `chs-026, 033, 034`, `mix-002` |
| check counted only when the mover is the checker | `chk-003, chk-004`, `mix-001, mix-004` |
| pinned chaser cannot chase (P1) | `chs-028` |
| **AXF same-type exclusion** | `chs-016, 017, 029` |
| **AXF value rule** | `chs-014` |
| **AXF chaser K/P excluded** | `chs-018, 019` |

The last three rows are the problem: those five fixtures discriminate **only** rules that the
contract does not contain (§1.3).

`mx-chs-023` (cycle length) is flipped by no mutation in my set; its guard is structural — a
six-ply cycle — and I accept it as a real construction guard rather than dead weight.

---

## 3. The three patch-gated fixtures — **both halves verified**

### 3.1 Which build is which — established from source, not from directory names

`diff -rq` of each build's `src/` against the fork tree
`/Users/tianren/coding/minixiangqi/Fairy-Stockfish` @ `77d602e0` (branch `master`, clean — the
right baseline because it already carries `promotedSoldiersChaseable`, which the harness INI
sets). **Only `src/position.cpp` ever differs**; no other file differs in any build.

| dir | source identity | as labelled? |
|---|---|---|
| `w-base` | **byte-identical to master `src/`** | yes — genuinely unpatched |
| `w-p1` | master + P1 hunk only | yes |
| `w-p2` | master + P1 hunk **+** P2 hunk | **no — cumulative P1+P2** |
| `w-p3` | master + P3 hunk only | yes |

The distinguishing hunks are the expected ones: P1 masks a pinned chaser's attacks to its pin
line (`chaserPins & attackerSq` → `attacks &= line_bb(...)`); P2 replaces the flying-general pin
test that scanned `file_bb(...) & pieces(sideToMove)` with `between_bb(ksq, oksq) & pieces()`,
i.e. blockers **of either colour**; P3 defers the `chaseThem` intersection so it spans only the
moves inside the window.

All four shipped `.so` files were **rebuilt from their own sources** into `/tmp/pr27-engine/`
and every rebuilt engine's harness output is byte-identical to the shipped one. Identification
is confirmed by two independent routes.

### 3.2 Both halves of the gate

```
$ python3 discussion-drafts/engine-fixture-check.py <build> \
          /Users/tianren/coding/minixiangqi/fx-assembled/fixtures/rules

engine: Fairy-Stockfish 270726 LB by Fabian Fichter
fixtures: 51 from .../fx-assembled/fixtures/rules
...
target variant  (soldiers exempt):     3 failure(s)
    mx-chs-028: expected value 0 for claimable-draw/threefold-repetition, got -32000
    mx-chs-029: expected value 0 for claimable-draw/threefold-repetition, got -32000
    mx-chs-030: expected value 32000 for black-wins/perpetual-chase, got 0
```

**The PR's "51 fixtures, 48 pass, 3 fail" is exact, and the three failures are exactly
`mx-chs-028`, `029`, `030` — no more and no fewer.** The failure directions match the PR's
claim table: 028 and 029 give −32000 (Red loses) where the contract says claimable draw; 030
gives 0 (draw) where the contract says black-wins.

| fixture | base | p1 | p2(=P1+P2) | p3 | P2-only | P1+P2+P3 |
|---|---|---|---|---|---|---|
| `mx-chs-028` | FAIL | **ok** | ok | FAIL | FAIL | ok |
| `mx-chs-029` | FAIL | FAIL | **ok** | FAIL | **ok** | ok |
| `mx-chs-030` | FAIL | FAIL | FAIL | **ok** | FAIL | ok |

Each fails now for the stated reason and passes on its own correction. **No regressions**: no
patched build breaks any fixture that passes unpatched. P1+P2+P3 together gives **51/51**.

`mx-chs-028`'s premise was checked directly against the engine: at every ply the white
chariot's legal moves are strictly d-file (`d4d2 d4d3 d4d5 d4d6 d4d7`), `d4b4`/`d3b3` is never
legal, and the unpatched engine still rules Red the loser. The defect is real, and it is the
one `engine-integration.md:42` already accepts.

**Evidence-chain gap — should-fix.** As shipped, `w-p2` contains P1 as well, so the workspace
evidence cannot attribute `mx-chs-029` to P2 alone. A P2-only build was constructed for this
review and does fix 029 independently, so the conclusion holds — but the shipped artifact does
not support it. Label or rebuild `w-p2`.

**Sequencing — should-fix.** P3 landed in the fork (`fs-chase`, commit `131784a4`, "Make the
repetition window span the same moves for both sides") **during this review**. `mx-chs-030`'s
gate and the fork change that satisfies it were racing; confirm that fork commit is itself
reviewed rather than assuming it predates the fixture.

### 3.3 Is `mx-chs-032` really the control for `mx-chs-030`, and do they differ only as claimed?

**The parity claim is exactly right.** Same `start_fen`, `mx-chs-032.moves[:9] == mx-chs-030.moves`
with one extra Black move, and — the substantive point — both fixtures judge the **identical
four White moves**:

```
030 window=1..9  judged White plies=[2, 4, 6, 8]  targets={'c@a5'}
032 window=2..10 judged White plies=[2, 4, 6, 8]  targets={'c@a5'}
```

so a parity-independent adjudicator must return the same verdict for both, and the engine's
split (draw for 030, loss for 032) is genuinely the whole content of the pair. **But the ply
`mx-chs-032` asserts at is unreachable — see §2.1.** The pair's *claim* is sound; the *fixture*
is not.

**`mx-chs-030` lands with neither of its two controls intact — should-fix.** Its differential
partner `mx-chs-031` (the same wheel entered by a *chasing* move, which is what makes the
"advance along an existing line renews nothing" argument decisive) is excluded, and its parity
control `mx-chs-032` is defective. A corrected `mx-chs-031` exists on the local `gap-chs031`
branch with a different `start_fen` and entry move, and passes on both the unpatched and the
fully patched engine. Shipping 030 alone leaves the P3 argument resting on one fixture that
only says "the engine is wrong here", with the contrast that explains *why* absent.

---

## 4. The disclosed unvalidated claims — accurate but **incomplete**

The PR discloses two limits. Both are accurate. The disclosure is not complete.

**Verified accurate, and the collapse is worse than the PR says.** `engine-fixture-check.py:41-48`
maps *both* `claimable-draw` and `draw` to the value `0`:

```python
def expected_optional_value(state, fen):
    if state == "claimable-draw" or state == "draw":
        return 0
```

Measured on the unpatched baseline, the three states really are one value:

```
mx-mix-001: contract = draw/mutual-perpetual-check   -> sf.is_optional_game_end(...) -> (True, 0)
mx-mix-002: contract = draw/mutual-perpetual-chase   -> sf.is_optional_game_end(...) -> (True, 0)
mx-rep-001: contract = claimable-draw/threefold      -> sf.is_optional_game_end(...) -> (True, 0)
```

and the collapse is structural in the engine, not incidental to the harness:
`Position::is_optional_game_end` reduces mutual perpetual check, mutual chase and a neutral
n-fold to the same `VALUE_DRAW` literal, and the pyffish return has no channel for the branch
that fired. Both PR disclosures are therefore accurate, and both asserted values are correct
against the contract (L68 makes a same-class mutual violation a `draw` with a reserved reason,
distinct from a claimed repetition — I derive both independently in §1).

**Undisclosed properties of the same kind — should-fix:**

1. **`reason` is unvalidated for 49 of the 51 fixtures**, not just `mx-mix-002`. The harness
   reads `reason` only to route checkmate/stalemate; every other reason string is unchecked.
2. **`perpetual-check` and `perpetual-chase` are also indistinguishable.** 18 fixtures return
   `(True, −32000, stm=w)`: 13 `black-wins/perpetual-chase`, 3 `black-wins/perpetual-check`,
   and the two failing patch-gated draws. This is *not* disclosed anywhere. It matters most for
   **`mx-mix-004`**, whose entire point is that the reason is `perpetual-check` rather than
   `perpetual-chase`. The precedence *outcome* is validated behaviourally — `mx-chs-027` returns
   `+32000` (red-wins) and `mx-mix-004` returns `−32000` (black-wins) over the same eight plies,
   opposite winners from a one-piece change — but the reason label is contract-derived only.
3. **`draw` vs `claimable-draw` is undistinguishable for every fixture.** The PR discloses this
   for `mx-mix-001`'s state but says only that `mx-mix-002`'s *reason* is unvalidated;
   `mx-mix-002`'s `draw` state is equally unvalidated, and the distinction is user-visible
   (automatic vs claim-gated, L61 vs L62). 17 fixtures share `(True, 0, stm=w)`.
4. **`at_occurrence` (42 fixtures) and `boundary.expect` (42 fixtures) are never read at all.**
   `at_occurrence` matters exactly once — `mx-chs-022`'s `"at_occurrence": 4` is that fixture's
   entire point, and it is unvalidated.
5. `mx-mix-003` self-discloses correctly (*"The engine implements no combined check-and-chase
   rule, so its agreement here is the absence of an implementation rather than evidence"*) —
   this is the model the other cases should follow.
6. Nit: for the 7 `ongoing` fixtures `pyffish_isOptionalGameEnd` declares `Value result;`
   **uninitialised** and returns it unconditionally; the observed garbage varies (`0`, `−32000`).
   The harness only reads the boolean there, so nothing is wrong today, but the value is junk.

**Correction:** state the harness's read limits once in the PR body or in
`fixtures/rules/README.md` §Consumption — reason, `at_occurrence`, and the
draw/claimable-draw distinction are contract-derived for all 51 fixtures until the P4 accessor
lands — rather than attaching the limitation to two fixtures.

---

## 5. Immutability and integrity — **all confirmed**

- **16 approved fixtures byte-identical to `main`.** Verified per file by SHA-256 of the git
  blob on each side, and cross-checked by `comm -12` over `(blob, path)` pairs from
  `git ls-tree -r`: exactly 16 common pairs; the only main-side pair absent from the branch is
  the README blob `023c465`. None differs.
- **Only non-fixture change is the one README line** adding the `mx-mix-*` area. `--name-status`
  is exactly `M fixtures/rules/README.md` + 35 `A` under `fixtures/rules/`. Branch is a single
  clean commit `23ce90b` on `main` (`60fc044`); `fx-assembled` worktree is clean including
  untracked files.
- **Identifiers:** 51 files, 51 unique ids, `id` == filename stem and `area` == id segment in
  all 51. Numbering: move 1–6, end 1–3, rep 1, chk 1–4, chs 1–30 + 32–34, mix 1–4.
  **`mx-chs-031` is the only gap.**
- **Areas correct.** `mx-chs-033`/`034` assert *unilateral* verdicts and so are correctly `chs`,
  not `mix`; all four `mix` fixtures are genuinely cross-class or both-sides.
- **Stale contract (see §1.7):** `docs/xiangqi-rules.md` is untouched, leaving lines
  5, 68, 80, 92, 94, 111, 119, 120, 121 false or stale on merge. The README line 34 the PR did
  *not* touch still calls the two mutual reasons "reserved for the deferred mutual-violation
  fixtures" while the PR puts them into use.

---

## 6. Schema conformance — **51/51 clean, zero defects**

Checked mechanically against `fixtures/rules/README.md`:

- All 51 carry exactly `id, title, area, variant, start_fen, moves, assertions, boundary,
  rationale` — no missing key, **no invented key**. `assertions` carries exactly
  `in_check, result_fen, legal_moves, rejected_moves, applied, game_state`; `game_state` carries
  `state`, `reason`, and `at_occurrence` on exactly the 42 repetition-based outcomes.
  `applied[]` entries are exactly `{move, result_fen, in_check}`; `boundary` exactly
  `{prefix_len, expect}`.
- `variant == "minixiangqi"` everywhere.
- Every `state` in the allowed set; `reason` null for all 7 `ongoing`, otherwise in the
  documented vocabulary. `mutual-perpetual-check` / `mutual-perpetual-chase` appear only in
  `mx-mix-001` / `mx-mix-002`, which is what the reservation was for.
- **FEN:** all 106 FEN strings have exactly 6 fields, fields 3 and 4 are `-`, 7 ranks each
  summing to 7, only `KRNCP`/`krncp`, exactly one king per side.
- **Counters:** every `result_fen` reproduces exactly under the contract rule (reset on capture
  only, soldier moves do not reset; fullmove +1 after each Black move). All 367 plies legal at
  their turn. All 9 non-null `legal_moves` sets exact; all 6 `rejected_moves` genuinely illegal.
- `boundary.prefix_len` strictly inside range for all 42 that have one; the 9 without are the
  empty-history `move`/`end` fixtures, where a prefix is meaningless.

---

## 7. What the tranche still does not cover

The PR's count of **seven** uncovered accepted rules is **correct**, and I derived the same
seven independently:

1. `nMoveRule = 0` / the fifth FEN field drives no rule — **zero coverage**. Longest history is
   12 plies; highest halfmove counter in any `result_fen` is 12; **no history contains a single
   capture** (0/51). A variant shipped with the inherited move-count rule left on turns games
   into draws with all 51 fixtures green. The PR's framing of this is exactly right.
2. Position-identity **negative** half (L38): no placement recurs with both sides to move, so
   nothing rules out an implementation that ignores side to move.
3. Chariot movement.
4. "A bare position carries no prior occurrences" (L60).
5. The mutual-chase **misattribution** corner — `mx-mix-002` repeats at plies 0/4/8, so there is
   no quiet entry move and no "entering side". `engine-integration.md:45` requires exactly this
   fixture to accompany the parity correction: *"a mutual chase entered by a quiet move from
   each side in turn, with the one-ply-later continuation as its control."* `mx-chs-030`/`032`
   is a *unilateral* chase and is not it. **Merging PR #27 therefore does not unblock P3.** The
   PR states this correctly.
6. Kings excluded as chase **targets** (L66) — `mx-chs-003` covers soldiers only.
7. "Check outranks chase … loses **even if it is simultaneously chasing**" (L67) — `mx-mix-004`
   covers the *other* clause (the opponent also chasing); Red's checking moves there attack the
   black chariot at plies 1 and 5 but not 3 and 7, so Red is *not* simultaneously chasing.

**Two corrections to the PR's framing:**

- **The chariot gap is partial, not absent.** `mx-move-001` pins the obstructed case and
  `mx-move-006` pins a real three-square slide plus a rejected one. What is missing is an
  unobstructed chariot's complete legal set. "No fixture" overstates it.
- **One gap the PR misses: Black-side movement asymmetry.** Every non-empty `legal_moves` and
  every `rejected_moves` in all 51 fixtures is for a **Red-to-move** position. In particular
  **no fixture pins a Black soldier's forward direction** — every soldier move in every history
  is sideways, and the only forward soldier move anywhere is Red's `d4d5` probe in
  `mx-move-004`. An implementation with Black's soldier direction inverted passes all 51.
  Black's palace boundary, Black horse blocking and Black cannon screening are likewise
  constrained only implicitly by replay legality. Lower severity than `nMoveRule = 0` — a wrong
  Black soldier direction shows up the first time anyone plays — but it belongs on the list.
- Minor: the halfmove **reset on capture** is pinned only by three single-move `applied` probes;
  no replayed history contains a capture.

---

## Summary of findings

| # | Fixture | Severity | Finding |
|---|---|---|---|
| 1 | `mx-chs-014` | **blocking** | Asserts a chase loss against a **protected** target; contradicts `xiangqi-rules.md:64` and the public source. Rests on a value rule in neither authority. |
| 2 | `mx-chs-016` | **blocking** | Asserts no violation for chasing an **unprotected** chariot; contradicts L64 and L66, whose only exclusions are kings and soldiers. |
| 3 | `mx-chs-018` | **blocking** | Excludes soldiers as **chasers**; L66 excludes them only as targets. Adopts the second, unadopted reading of the source phrase. |
| 4 | `mx-chs-019` | **blocking** | Same, with a king as chaser. |
| 5 | `mx-chs-029` | **blocking** | Its `claimable-draw` requires the unstated same-type exclusion; makes an accepted fork correction's gating depend on a rule the contract lacks. |
| 6 | `mx-chs-032` | **blocking** | Asserts a game state at ply 10; the contract makes the game terminal at ply 9. Same defect class the tranche rejected `mx-chs-031` for. Cannot be satisfied together with `mx-chs-030`. |
| 7 | contract | **blocking** | `docs/xiangqi-rules.md` untouched; README:3 requires the two halves to move together; L5 still says these definitions are unresolved and "do not authorize implementation"; `rules_version` not bumped. |
| 8 | `mx-chs-017` | should-fix | Right answer for the wrong reason; the 016/017 pair carries no information under the contract as written; flips to a mutual draw under the literal reading of L75. |
| 9 | `mx-chs-015` | should-fix | Correct answer, rationale rests on the unsupported value rule. |
| 10 | disclosure | should-fix | Disclosure incomplete: `reason` unvalidated for 49/51; `perpetual-check` vs `perpetual-chase` indistinguishable (undisclosed, matters for `mx-mix-004`); `draw`/`claimable-draw` indistinguishable for all; `at_occurrence` and `boundary.expect` never read. Disclose once as a set-wide limit. |
| 11 | coverage | should-fix | Black-side movement asymmetry uncovered (Black soldier direction in particular); chariot gap is partial, not absent. |
| 12 | `w-p2` evidence | should-fix | The shipped `w-p2` build is **P1+P2**, so the workspace evidence cannot attribute `mx-chs-029` to P2 alone. A P2-only build confirms it does — but relabel or rebuild. |
| 13 | `mx-chs-030` | should-fix | Lands with neither control: `mx-chs-031` excluded, `mx-chs-032` defective. Also, the fork commit satisfying P3 (`fs-chase` `131784a4`) landed during this review — confirm it is itself reviewed. |
| 14 | `mx-chs-013` | nit | Rationale claims a cannon "never protects … the piece immediately next to it", but no defender in the position is ever adjacent to the target (e5 vs a5/b5). Not exercised. |
| 15 | harness | nit | `engine-fixture-check.py:120` lets a wrong early *draw* pass at the boundary of a loss-asserting fixture; `pyffish_isOptionalGameEnd` returns an uninitialised value for `ongoing`. |

**Nothing in items 1–6 is a construction error.** Every one of the 35 fixtures is mechanically
perfect, all three patch gates verify in both directions with no regressions, and the tranche is
internally consistent — against a contract that has not been written. The fix for items 1–5 and
7 is one document change that the workspace has already drafted
(`rules-edge-cases-reconciliation.md` §4 Q1–Q6). Item 6 needs a re-cut fixture on the
`mx-chk-001`/`mx-chk-002` pattern.

---

## Verdict

Two things in this tranche will look green forever while being wrong.

`mx-chs-014`, `016`, `018`, `019` and `029` pass on the engine *because they were derived from
the engine*. Each is discriminated by exactly one rule, and in each case that rule is absent
from `docs/xiangqi-rules.md` and from the retained public source — and two of them make
accepted contract sentences false: L64 says a chase target must be **unprotected**
(`mx-chs-014` chases a protected one and calls it a loss) and L66 says the **only** exclusions
are kings and soldiers as **targets** (`mx-chs-016` adds a same-type target exclusion,
`mx-chs-018`/`019` add an attacker-class exclusion). `fixtures/rules/README.md:5` — "every
expected value in a fixture comes from the accepted rules contract and the selected public
rules source, never from what any engine returns" — is not satisfied by these five.

`mx-chs-032` asserts a game state at a ply the contract says the game has already ended, which
is precisely why `mx-chs-031` was rejected from this same tranche. It cannot be satisfied
together with `mx-chs-030` under the consumption model in `README.md:40`.

None of this is hard to fix, and the project has already written most of the fix. Land the
Q1–Q6 prose from `rules-edge-cases-reconciliation.md` into `docs/xiangqi-rules.md` in the same
change, move the resolved items out of **Need to discuss**, bump `rules_version` to 2, and
re-cut `mx-chs-032` on the `mx-chk-001`/`mx-chk-002` two-start-FEN pattern. Then all 35
fixtures are derivable from the contract and I would sign it off without reservation.

As it stands the fixtures would become the executable authority for rules the contract does not
contain and, in four places, contradicts.

# DO NOT MERGE
