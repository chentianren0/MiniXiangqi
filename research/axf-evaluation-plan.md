# Empirical evaluation plan: Fairy-Stockfish AXF with Mini Xiangqi NNUE

## Decision and evidence base

The first experiment should be a configuration-only Fairy-Stockfish candidate, not a fork and not a new reinforcement-learning engine:

```ini
[minixiangqiaxf:minixiangqi]
chasingRule = axf
```

Compare that candidate with built-in `minixiangqi`, both with and without the same NNUE. AXF is an experimental search/adjudication input, not the app's rules authority. Patch Fairy-Stockfish only if a named gate below identifies a source-level blocker that configuration or packaging cannot solve.

Evidence was read from these clean local revisions:

- **FS** — `Fairy-Stockfish` at `c19b5f6c66894fdb0e88d0dd100e3885f744760a`.
- **PC** — `pychess-variants` at `961fd6dd60ce76d3baced1a77df49ca58edcb315`.
- **APP** — `MiniXiangqi` at `d92a966b1d46f413139a7b8ee7d80fa9f5f2b330`.

No `.nnue` file is present in the inspected repositories. The “existing Mini Xiangqi NNUE” must therefore enter the experiment as an explicit, immutable input: record its filename, byte length, SHA-256, provenance/training revision if known, and bundled-app path. Do not treat a filename as compatibility evidence.

### Source-established facts

1. Built-in Mini Xiangqi is a 7×7 Xiangqi-template variant with five piece types, the stated start FEN, palace-restricted kings, no river behavior, flying generals, losing stalemate, and illegal perpetual check. It does **not** enable AXF chasing. Full Xiangqi separately enables `AXF_CHASING`. [FS `src/variant.cpp:1222-1246,1728-1751`]
2. A configured variant can inherit a built-in variant, and `chasingRule=axf` is parsed. Variant configuration can be loaded from `VariantPath`, a file, or an in-memory here-document. [FS `src/parser.cpp:99-103,497-507`; `src/variant.cpp:2147-2228`; `src/uci.cpp:245-283`; `src/ucioption.cpp:203-210`]
3. AXF sets per-position `chased` state and affects optional repetition adjudication. The legal-root move list is still built from `MoveList<LEGAL>`. [FS `src/position.cpp:576-599,2648-2718,2971-3089`; `src/thread.cpp:181-215`]
4. PyChess delegates Mini Xiangqi FEN transitions, legal moves, check state, and game-end queries to `pyffish`. PyChess pins `pyffish==0.0.89`; the local Fairy-Stockfish history maps that version bump to `f69f4878d4996737f1578285fdd4420cbdf786c5`. [PC `pyproject.toml:7-23`; `uv.lock:962-974`; `server/fairy/fairy_board.py:19-35,109-201,223-367`; FS `setup.py:44` at commit `f69f4878…`]
5. PyChess passes full history to optional-game-end queries, but ordinary Mini Xiangqi legal-move queries use the current FEN without history. Its server auto-ends a non-draw optional result, while a neutral repetition in a human game is claimable rather than automatically ended because Mini Xiangqi is not in `n_fold_is_draw`. [PC `server/fairy/fairy_board.py:281-317,325-356`; `server/game.py:309-320,1058-1126`]
6. NNUE activation first filters the file by a basename prefix matching the exact variant name or a compiled alias. A configured `minixiangqiaxf` therefore needs the same bytes packaged under a `minixiangqiaxf...nnue` basename unless code supplies an alias. Loading checks the file version, static architecture hash, expected parameter reads, and EOF; failed verification exits the process. [FS `src/evaluate.cpp:69-172`; `src/nnue/evaluate_nnue.cpp:93-136`; `src/nnue/nnue_common.h:48-55`; `src/nnue/evaluate_nnue.h:30-33`]
7. **Inference from FS:** Mini Xiangqi’s current feature mapping has 3,969 dynamic input dimensions and a maximum of 24 pieces: 49 squares × (2 × 5 piece types − 1 king channel) × 9 oriented palace king squares. That mapping follows the variant-derived indexing code; the number is not encoded into the static architecture hash. A structurally loadable file is therefore not, by itself, proof that its learned feature semantics match this variant. [FS `src/variant.cpp:1224-1246,2006-2083`; `src/nnue/features/half_ka_v2_variants.h:37-65`; `src/nnue/nnue_feature_transformer.h:185-212`]
8. Local AXF regression cases exercise `xiangqi`, not `minixiangqi`. This is a coverage gap to fill before assuming the full-board chase classifier transfers unchanged to the 7×7 game. [FS `test.py:1151-1205`]
9. The local history identifies the initial chasing implementation as `9022a70549bf741db2fe4b57af42739b1cb91a2d` and a later repetition correction as `fbe816bf6d29ee36d203abea6da9947c03bc73d8`. Upstream itself says the implementation has cases “not handled correctly yet” in the still-open [issue #468](https://github.com/fairy-stockfish/Fairy-Stockfish/issues/468). In 2025 the maintainer reiterated that it is incomplete and closed [issue #938](https://github.com/fairy-stockfish/Fairy-Stockfish/issues/938#issuecomment-3568312624) as a duplicate. This is stronger than an inferred coverage concern: AXF must not be treated as a complete rules oracle.

### Verified local smoke observations to preserve as fixtures

These observations prove feasibility, not general correctness:

- `pyffish 0.0.89` accepted the inherited `[minixiangqiaxf:minixiangqi]` configuration.
- For FEN `4k2/7/c6/7/1R5/7/2K4 w - - 0 1` and moves `2 * ['b3a3', 'a5b5', 'a3b3', 'b5a5']`, built-in `minixiangqi` returned optional result `(True, 0)`, while `minixiangqiaxf` returned `(True, -32000)`. The sequence models White's rook repeatedly chasing the same unprotected Black cannon; on the third occurrence White is to move and AXF scores White's loss.
- The existing NNUE loaded for the configured child only after an otherwise byte-identical copy was renamed with the `minixiangqiaxf` prefix, matching the source prefix gate.

Reproduce all three from a clean FS build and record the binary hash, NNUE hashes, exact commands, stdout/stderr, and `pyffish.info()` before treating them as release evidence.

## Frozen candidate matrix

Use one Fairy-Stockfish source revision, compiler, optimization flags, thread count, hash size, opening set, adjudicator, and device power state across a comparison.

| ID | Variant | Evaluation | Purpose |
|---|---|---|---|
| A | built-in `minixiangqi` | `Use NNUE=false` | Classical safety and strength baseline |
| B | built-in `minixiangqi` | Existing NNUE | Isolate NNUE value and compatibility |
| C | configured `minixiangqiaxf` | Same NNUE bytes under an accepted basename | Configuration-only AXF candidate |
| D | configured `minixiangqiaxf` | `Use NNUE=false` | Separate AXF effects from NNUE effects |
| P | Focused fork, only if triggered | Same as the failing candidate | Demonstrate that a specific patch fixes the blocker |

Every run must record FS and PC commit hashes, `pyffish.version()` and `pyffish.info()`, app build identifier, NNUE SHA-256, candidate configuration text, device/OS, engine options, seed, starting FEN/move history, and raw protocol transcript. Clear the hash between independent positions unless the test explicitly measures game play.

## 0. Rules-conformance corpus and authority boundary

This is the first gate. The app must own the authoritative Mini Xiangqi rules core: legal moves, state transitions, check/mate/stalemate, repetition history, and the user-visible game result. The engine receives a position/history and proposes a move; neither a Fairy-Stockfish score nor its optional-game-end result may directly mutate authoritative game state.

Build a compact, reviewable conformance corpus before engine comparison:

- The exact Mini Xiangqi board, pieces, palace, flying-general, horse-leg, cannon-screen/capture, soldier, check/evasion, mate, stalemate, and 50-move cases.
- Repetition families: neutral repetition, perpetual check, unilateral chase, mutual chase, interrupted chase, capture-defense, pinned attacker, discovered chase, and mixed check/chase.
- The verified 7×7 direct-chase loop above, with the intended **app** outcome approved independently of the engine outputs.
- Relevant upstream full-Xiangqi cases from FS `test.py:1157-1205` and issues #468/#938, adapted to 7×7 only where a human reviewer can establish that the same rule premise survives the adaptation.

Each fixture stores initial FEN, complete move history, expected legal set at every ply, expected FEN/check state, and expected authoritative result with a short rule rationale. Two-person review is required for every chase result because upstream AXF is explicitly incomplete and the official chase rules can be interpretation-sensitive.

**Pass:** the app-owned core passes every approved fixture and can replay them without consulting the search engine. No later engine result can waive this gate.

## 1. Engine semantic compatibility gates

Use a deterministic corpus with four small parts:

- Start-position perft with root splits through depth 5.
- Exact differential traversal through depth 4.
- 10,000 seeded, reachable positions sampled from legal playouts, stratified across opening, capture-heavy, reduced-material, check/evasion, palace-edge, cannon-screen, horse-leg, flying-general, and long reversible histories.
- The approved rules-conformance fixtures, including positions near the 50-move limit.

For every traversed state and every candidate:

1. Compare the complete legal-move set with the PyChess oracle.
2. Apply every legal move and compare the resulting canonical FEN, side to move, check state, and immediate-game-end tuple.
3. Replay the same state from initial FEN plus full move history and compare the optional-game-end tuple.
4. Mutate a bounded sample of source/destination squares and ensure the app rejects every move outside the oracle set.
5. Ask the candidate for a move at fixed nodes; reject `0000`, a timeout, or a best move outside the oracle set whenever the oracle says a legal move exists.

**Pass:** zero legal-set, FEN-transition, check-state, or immediate-terminal mismatches; zero illegal best moves. Optional-adjudication differences may pass only under the classification below. A single reproducible hard mismatch stops strength and performance work until diagnosed.

The local ignored binary reported the same start-position perft totals for built-in Mini Xiangqi and the one-line AXF child—19, 331, 6,664, 127,164, and 2,666,905 at depths 1–5. Treat these only as harness canaries; regenerate them from a newly built binary at FS before using them as acceptance evidence.

### PyChess as a compatibility oracle, with its limitation made explicit

Instantiate `FairyBoard("minixiangqi")` against PC’s pinned environment. Use its `legal_moves()`, `push()/get_fen`, `is_checked()`, `is_immediate_game_end()`, and `is_optional_game_end()` outputs, then run the corresponding `Game.update_status()` policy. This captures the current PyChess compatibility contract, including the difference between a claimable neutral repetition and an automatically scored non-draw violation.

PyChess is **not an independent rules implementation**: those board operations call `pyffish`, which is Fairy-Stockfish code. It is an oracle for compatibility with the current service, not the app's runtime authority and not proof that both implementations are correct. The app-owned, reviewed conformance corpus is the independent semantic check; disputed chase cases must be resolved as Mini Xiangqi rules questions rather than decided by engine agreement.

### Detecting harmless internal adjudication differences

Always compare histories, not only final FENs, because the repetition and chase state is historical. For each divergence record:

```text
initial FEN + moves
oracle legal set / candidate legal set
oracle immediate(end,result) / candidate immediate(end,result)
oracle optional(end,result) / candidate optional(end,result)
oracle user-visible server status / app status
candidate score, PV, and bestmove
```

Classify a difference as **adjudication-only** only when all of these hold:

- Legal sets and all next FENs are identical.
- Check, mate, stalemate, and immediate variant-end status are identical.
- Only the AXF candidate’s optional repetition result differs.
- The candidate still returns a legal root move.
- The app-owned authoritative rules core—not PyChess at runtime and not the search engine—accepts moves and declares the game result; its approved behavior is differentially checked against PyChess.

This separation is source-consistent: UCI root search only treats optional root game end specially for XBoard, while non-root search evaluates `is_game_end()`. AXF can therefore change internal line valuation without making a different user move legal. [FS `src/search.cpp:175-215,675-737`]

Use the verified 7×7 rook/cannon loop as the calibration case. If the approved app rule says draw, C's `-32000` remains internal and the app must continue/score the game itself. If the approved app rule says White loses, built-in PyChess's draw is an explicit compatibility exception. In both cases, legal moves and FEN transitions must still match exactly.

Anything else is a **hard incompatibility**. In particular, an AXF claim exposed as an app win/loss, a missing legal move, a different FEN, or `bestmove 0000` in a live PyChess position is not harmless.

## 2. Engine robustness

Run A–D through the same harness:

- AddressSanitizer and UndefinedBehaviorSanitizer builds over the semantic corpus, plus 1,000 seeded random games or until 600 ply.
- Incremental move/undo/replay loops: after every move and undo, compare FEN, key-independent observable state, legal moves, and evaluation with a freshly reconstructed position.
- 1,000 lifecycle cycles covering initialize, load variant, switch B↔C, load net, `ucinewgame`, search, `stop`, background cancellation, foreground resume, and teardown.
- Search cancellation at random depths/times, including immediately after `go`; concurrent UI requests must be serialized at the engine boundary.
- Negative inputs at the wrapper boundary: malformed FEN, stale move, missing/truncated/wrong NNUE, and unavailable asset. The wrapper must reject or fall back without corrupting the current game.
- A 20-minute continuous-search soak and a 1,000-game fixed-node self-play soak on a physical device.

**Pass:** no crash, sanitizer finding, hang, state drift, illegal best move, or unbounded memory growth. Cancellation and load-failure requirements are also subject to the timing and NNUE gates below.

## 3. NNUE load and semantic compatibility

### Structural load gate

1. Fingerprint the network and preserve the original bytes.
2. Test its original name with B.
3. Copy the same bytes into the app bundle under an accepted `minixiangqiaxf...nnue` name for C; prove the SHA-256 remains identical. The verified smoke test succeeded only after this prefix change; rerun it as a release-build assertion.
4. Capture `info string NNUE evaluation using ... enabled` before the first search. Confirm `eval` and fixed-node `go` complete.
5. Negative-test a wrong prefix, missing file, one-byte truncation, one-byte append, wrong architecture, and wrong-variant net.

**Pass:** B and C load the exact expected SHA-256 and never silently use classical evaluation. Every negative case becomes a recoverable app error or an explicit classical fallback.

Unmodified FS calls `exit(EXIT_FAILURE)` after failed verification. If the engine is linked in-process and the wrapper cannot fully preflight the bundled asset before `go`, this is a focused-patch trigger; killing the Apple app is unacceptable. [FS `src/evaluate.cpp:140-170`]

### Semantic NNUE gate

Structural loading must be followed by:

- Bit-identical evaluation after an incremental move sequence versus evaluation after reconstructing the same FEN, including king moves, captures, and undo.
- Color/rank-flip symmetry checks with a predeclared tolerance of 1 centipawn.
- Identical static evaluation for B and C at the same FEN; AXF changes history adjudication, not board feature indexing.
- Finite, in-range scores over the 10,000-position corpus. For every legal king move and piece-count bucket transition, incremental and freshly reconstructed evaluation must agree even when the score legitimately changes sharply.
- Fixed-node comparison with NNUE disabled to show that any crash, illegal PV, or semantic mismatch is not hidden by evaluation choice.

**Pass:** zero incremental/fresh mismatches, zero B/C static-eval mismatch, symmetry within tolerance, and no illegal PV. A strength failure with otherwise correct loading is a network-quality result, not automatically an engine-patch reason.

## 4. Search quality

Create a compact, reviewable suite rather than treating a deeper copy of the same engine as truth:

- Forced mates and only-move defenses, with independently verified solutions.
- Immediate material tactics involving rooks, cannons, horses, and flying generals.
- Quiet positions where shallow material gain loses to mate or perpetual check.
- Every reviewed repetition/chase fixture, including choices that enter, avoid, or escape the cycle.
- A stability sample: compare best move and principal variation at 1×, 4×, and 16× the target node budget.

Report solved rate, mate-distance accuracy, legal-PV rate, best-move stability, node count, and score change for A–D. Review every C-vs-B change on the chase suite; AXF should improve cycle decisions without changing ordinary tactics.

**Pass:** 100% legal PVs and all forced mate/only-move safety cases solved at the shipping budget. C must improve or preserve the reviewed AXF cases and show no new catastrophic miss outside them. If NNUE changes a correct forced result into a wrong one at the same nodes, stop and investigate the net/search interaction before strength testing.

## 5. Time-control behavior

FS accepts fixed `movetime`, remaining clocks/increments, depth, and node limits. Its manager subtracts `Move Overhead`, caps maximum use, and supports node-time mode. [FS `src/uci.cpp:126-174`; `src/timeman.cpp:38-113`; `src/search.cpp:1953-1985`]

Test each shipping control plus diagnostic points:

- `movetime`: 25, 50, 100, 250, 500, and 1,000 ms.
- Clock play: 1+0, 1+1, 3+2, and 10+5, including less than one second remaining.
- Forced single legal move, high branching, in-check, just-out-of-book, and long-repetition positions.
- Cold start, warm engine, active thermal throttling, app background cancellation, and immediate user move after cancellation.

Measure from app request to accepted legal best move, not only engine-reported time. Set `Move Overhead` from measured p99 dispatch/UI jitter before the final run.

**Provisional pass thresholds (inference; replace before the run if product budgets differ):**

- No flag or illegal/missing best move in 10,000 timed moves.
- For fixed `movetime`, wall time is at most request + `max(50 ms, 10%)` at p99.
- `stop` to callback is ≤100 ms at p99.
- With a live clock, the engine never consumes the remaining time minus the measured safety reserve.
- Timing miss rates for C and B are statistically indistinguishable; NNUE loading occurs before, not inside, the first timed move.

## 6. Strength measurement

Use the app-owned rules core as the external game adjudicator for all matches so C cannot award itself an AXF win. Differentially verify each adjudication against PyChess and separately log an approved exception. Use 50–100 varied, legal opening prefixes generated and validated by both the app core and the PyChess oracle. Play every opening twice with colors reversed.

Run two kinds of matches:

1. **Fixed nodes** on desktop: isolates algorithm/evaluation changes from device speed.
2. **Shipping time control** on each target-device class: measures the product users receive.

Primary comparisons are B vs A (value of NNUE), C vs B (value/cost of AXF), and C vs A (combined candidate). Use paired-game pentanomial statistics, report score, draws, Elo estimate, and a 95% confidence interval. Start with 400 paired games; continue to 1,000 and then 2,000 only while the decision remains inconclusive.

Predeclare these decision margins:

- **NNUE go:** B’s lower 95% Elo bound is at least +20 versus A.
- **NNUE no-go:** B’s upper 95% bound is ≤0 versus A.
- **AXF non-inferiority:** C’s lower bound is above −20 Elo versus B **and** C materially reduces reviewed AXF-suite errors.
- Otherwise the result is inconclusive; do not convert uncertainty into a strength claim.

Also retain raw game histories and separately report outcomes affected by oracle/candidate adjudication disagreement. Human playtesting can assess style and difficulty after these gates, but it does not replace controlled match statistics.

## 7. Apple-device performance

APP currently targets iPhone/iPad and macOS. Test Release arm64 builds on the oldest supported physical iPhone/iPad class, a representative current phone, and the least-capable supported Apple-silicon Mac. Simulator numbers are diagnostic only. [APP `MiniXiangqi.xcodeproj/project.pbxproj:393-409,444-460`]

Use one engine thread and a fixed hash allocation first; increase either only after measurement. For A–D collect:

- App launch-to-engine-ready and cold NNUE-load latency.
- First-move and warm-move latency.
- Nodes/second and its coefficient of variation.
- Peak and steady resident memory, dirty memory after teardown, bundled binary/net size.
- CPU time, Energy Log, thermal state, battery change, and UI frame stalls during a 20-minute soak.
- Search cancellation and app background/foreground behavior.

**Provisional pass thresholds (inference):** p95 cold engine readiness ≤500 ms off the main thread; p99 main-thread blocking ≤16 ms; engine-related resident-memory delta ≤64 MiB over the no-engine app; no jetsam; no serious/critical thermal state during the 20-minute normal-play profile; warm NPS degradation after the soak <25%; and the timing-control gate still passes on the slowest device. Replace a threshold only before seeing candidate results.

## 8. Stop/go criteria for a Fairy-Stockfish patch

### Ship configuration C without a fork when

- All hard semantic, robustness, NNUE, timing, and device gates pass.
- All optional differences are reviewed adjudication-only differences contained behind the app-owned rules authority.
- C passes AXF non-inferiority and improves the reviewed chase behavior.
- Renaming the same NNUE bytes for the configured variant is acceptable packaging.

### Do not patch; use or retain another baseline when

- AXF provides no chase-suite benefit: use B.
- The NNUE is weak or too costly but classical search passes product strength/performance needs: use A or D.
- A mismatch is in app rules/adjudication rather than Fairy-Stockfish.
- A strength issue is traceable to network training, search budget, opening bias, or time settings rather than a source defect.

### Open a focused fork only when a minimized reproducer proves one of these

- In-process NNUE failure can terminate the app and cannot be safely preflighted; patch loading to return an error and select explicit classical fallback.
- The configured-variant name/alias restriction cannot be satisfied by safe packaging.
- AXF config is not reliably loadable in the Apple integration.
- A reviewed Mini Xiangqi chase fixture exposes a reproducible classifier/search bug, and the intended rule genuinely requires AXF.
- A crash, state-corruption, cancellation, or platform-build defect is inside FS.

For any patch, require: one minimized failing test, one behavior-focused regression test, a small diff, A/B evidence that only the target behavior changes, the full gates rerun as P, a pinned fork revision, and an explicit upstream/rebase plan. Do not simply enable AXF on built-in `minixiangqi`; that would change the semantics used by PyChess and collapse the intentional separation between user rules and search policy.

The known upstream incompleteness makes “finish AXF” too broad to qualify as a focused patch. If the conformance corpus reveals several independent classifier defects, disable AXF for shipping or scope a separate rules-engine project; do not let a growing chase rewrite hide inside the Apple integration.

### Stop the integration entirely when

- A legal/FEN/immediate-terminal mismatch remains unexplained.
- The existing NNUE’s provenance or bytes cannot be frozen.
- The app cannot contain engine fatal errors or memory/thermal behavior on the slowest supported device.
- Strength evidence stays below the declared product floor after both NNUE and classical baselines are measured.

## Option cost and risk

| Option | Up-front/ongoing cost | Main risks | Evidence-based role |
|---|---|---|---|
| **AXF configured child variant** | Low / low | Upstream explicitly calls chasing incomplete; transfer to 7×7 is unvalidated; custom name affects NNUE prefix; internal adjudication may diverge from the app rules core and PyChess | Start with it as a bounded experiment, not as rules authority. It is supported by the existing parser and preserves an unmodified upstream engine. |
| **Focused FS patch/fork** | Medium / medium-to-high | Regression and rebase burden; accidental user-rule changes; app-fatal error handling if left unchanged | Use only for a minimized source blocker and keep the patch narrow. |
| **Classical search without NNUE** | Low / low | Unknown strength/style ceiling; potentially more nodes/time for comparable play | Required baseline and safe fallback; FS already selects classical evaluation when NNUE is disabled. [FS `src/evaluate.cpp:1605-1647`; `src/ucioption.cpp:203-208`] |
| **Future AlphaZero-style self-play RL engine** | Very high / very high | Requires a new rules environment, policy/value model, MCTS, self-play/training/evaluation infrastructure, reproducibility controls, and Apple inference optimization; high compute and model-risk before product evidence exists | A later research track only if measured NNUE+search strength is inadequate or a distinct learned style becomes a product requirement. |

**Inference:** Nothing in the current evidence requires pure RL. FS already supplies legal move generation, alpha-beta search, time management, classical evaluation, variant NNUE, and AXF adjudication. The minimum informative experiment is therefore C against A and B. An AlphaZero-style engine should not be the starting point unless those measured baselines fail a predeclared strength goal that tuning or NNUE retraining cannot meet.

## Required decision packet

The final go/no-go review should contain only:

1. Frozen revisions, build settings, configuration, and NNUE fingerprint/provenance.
2. Semantic differential summary with every nonzero divergence attached.
3. Sanitizer/soak/lifecycle results.
4. NNUE positive and negative load results plus incremental/fresh checks.
5. Search-suite results.
6. Timing and physical-device measurements.
7. Paired strength estimates and confidence intervals.
8. One decision: configure, use built-in Mini Xiangqi, fall back to classical, make a named focused patch, or stop.

An unexplained failure in an earlier gate blocks claims from later gates; faster NPS or higher self-play Elo never overrides illegal user-visible behavior.
