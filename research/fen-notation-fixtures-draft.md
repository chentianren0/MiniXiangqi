# Starting FEN, coordinates, notation, and the first conformance fixtures

## Scope and evidence base

This draft freezes the Mini Xiangqi starting-position encoding, the coordinate and move-notation contract, and a first minimized rules-conformance fixture set, and records how the current engines respond to every fixture. It proposes contract wording for `MiniXiangqi/docs/xiangqi-rules.md`; nothing here changes a repository.

Evidence was read from these clean local revisions:

- **FS** — `Fairy-Stockfish` at `c19b5f6c66894fdb0e88d0dd100e3885f744760a`.
- **PC** — `pychess-variants` at `961fd6dd60ce76d3baced1a77df49ca58edcb315`.
- Rules snapshot: `discussion-drafts/evidence/pychess-minixiangqi-rules-2026-07-26.html` (SHA-256 `a79b6636…`, per its `.SOURCE.md`).
- Engine runtime: the prebuilt `pyffish` 0.0.89 extension at `discussion-drafts/evidence/pyffish-build/pyffish.cpython-314-darwin.so` (`pyffish.info()` = `Fairy-Stockfish 260726 LB by Fabian Fichter`), run under Python 3.14.4.

Fixtures and the reproducible validation run live in `discussion-drafts/fixtures-draft/` (`mx-*.json`, `validate.py`, `minixiangqiaxf-validation.ini`, `validation-report.json`). The AXF child used for validation is `[minixiangqiaxf:minixiangqi]` with `chasingRule = axf` and `nMoveRule = 0` (scratch ini; the evidence ini was not modified).

Normative stance: every fixture's expected outcome comes from the accepted `docs/xiangqi-rules.md` contract and the selected PyChess rules source, never from what an engine returns. Engine returns are recorded separately as observations.

## Verified freeze facts

### 1. Starting FEN

**Proven source facts**

- The built-in `minixiangqi` start FEN is exactly `rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1`: `Fairy-Stockfish/src/variant.cpp:1236`, registered as `minixiangqi` at `Fairy-Stockfish/src/variant.cpp:1936`.
- PC ships the byte-identical start FEN for its `minixiangqi` variant: `pychess-variants/client/variants.ts:1434`.
- Empirical: `pyffish.start_fen("minixiangqi")` returns the same string, for both the built-in and the AXF child, and `get_fen(start, [])` round-trips it unchanged.

### 2. Board, coordinates, and starting squares

**Proven source facts**

- The board is 7 files by 7 ranks: `maxRank = RANK_7`, `maxFile = FILE_G` at `Fairy-Stockfish/src/variant.cpp:1228-1229`.
- Square names are file letter plus rank digit with `FILE_A→'a'` and `RANK_1→'1'`: `UCI::square` emits `char('a' + file_of(s)), char('1' + (rank_of(s) % 10))` for this board size and protocol (`Fairy-Stockfish/src/uci.cpp:484`, whole function 474-491). Squares are therefore `a1`…`g7`.
- FEN piece-placement fields are written from `max_rank()` down to `RANK_1` (`Fairy-Stockfish/src/position.cpp:703`): the first FEN field is rank 7, the last is rank 1.
- Therefore, from the start FEN: rank 1 (`RCNKNCR`) is the uppercase side's back rank with the king on **d1**; rank 7 (`rcnkncr`) is the lowercase side's back rank with the king on **d7**; uppercase soldiers stand on a2, c2, d2, e2, g2 and lowercase soldiers on a6, c6, d6, e6, g6; rooks a1/g1 and a7/g7, cannons b1/f1 and b7/f7, horses c1/e1 and c7/e7.
- Palaces: the White king is confined to files c–e, ranks 1–3; the Black king to files c–e, ranks 5–7 (`Fairy-Stockfish/src/variant.cpp:1237-1238`).
- Empirical corroboration: the complete legal-move set at the start is the 19 moves `a2a3 a2b2 c2b2 c2c3 d2d3 e2e3 e2f2 g2f2 g2g3 b1b2 b1b3 b1b4 b1b5 b1b6 f1f2 f1f3 f1f4 f1f5 f1f6` — soldiers of the side to move stand on rank 2 and advance toward rank 3, pinning the orientation (side to move at the bottom, ranks counted from its back rank).

**Inference**

`a1` is the left corner of the first-moving (Red) side's back rank from Red's point of view. This is the same convention as international chess algebraic naming restricted to files a–g and ranks 1–7.

### 3. Move notation

**Proven source facts**

- Engine moves are coordinate notation `<from><to>` (`UCI::move`, `Fairy-Stockfish/src/uci.cpp:510-559`). Suffixes exist only for promotion, piece promotion/demotion, gating, and walling moves; `minixiangqi` defines none of these (no promotion piece types, `doubleStep = false`, `castling = false`: `Fairy-Stockfish/src/variant.cpp:1240-1241`; PC declares empty promotion roles at `pychess-variants/client/variants.ts:1441`).
- Empirical: across every position and ply of all 16 fixtures, every legal move string matches `^[a-g][1-7][a-g][1-7]$`; a soldier stepping onto the last rank (`a6a7`) produces a plain 4-character move, the piece stays `P` in the resulting FEN, and its only legal move afterward is sideways (`a7b7`). No promotion, gating, or drop syntax can occur.

### 4. Side-to-move letters and colors

**Proven source facts**

- The side-to-move FEN field is `w` or `b` (`Fairy-Stockfish/src/position.cpp:770`); the start FEN says `w`, and uppercase pieces belong to the `w` side.
- PC maps this variant's first-moving side to the color name **Red** and the second to **Black**: `colors: { first: 'Red', second: 'Black' }` at `pychess-variants/client/variants.ts:1439`.

**Inference**

Contract mapping: `w` = Red = uppercase = ranks 1–2 at the start = moves first; `b` = Black = lowercase = ranks 6–7. All fixture expectations below use Red/Black in this sense.

### 5. FEN field structure

**Proven source facts**

- A `minixiangqi` FEN has exactly 6 fields: piece placement, side to move, `-`, `-`, halfmove counter, fullmove number.
  - The third field is the castling slot and is always `-` because no castling rights ever exist (`Fairy-Stockfish/src/position.cpp:810-811`; castling disabled at `variant.cpp:1241`).
  - The fourth field is the en-passant slot and is always `-` because no double step exists (`Fairy-Stockfish/src/position.cpp:816-817`; `doubleStep = false` at `variant.cpp:1240`).
- The halfmove counter is `st->rule50` (`Fairy-Stockfish/src/position.cpp:834`). It resets on any capture (`position.cpp:1671-1672`) and on irreversible moves of the piece types in `nMoveRuleTypes` — which defaults to PAWN only (`Fairy-Stockfish/src/variant.h:123`). Mini Xiangqi soldiers are the distinct `SOLDIER` type, so **soldier moves do not reset the halfmove counter**. Empirical: after `d2d3` from the start the FEN reads `… b - - 1 1`; after the capture sequence `d2d3 d6d5 d3d4 d5d4` it reads `… w - - 0 3`.
- The fullmove number is `1 + (gamePly - (sideToMove == BLACK)) / 2` (`Fairy-Stockfish/src/position.cpp:836`): it starts at 1 and increments after each Black move (empirically confirmed above).
- Under the target child configuration `nMoveRule = 0`, the n-move rule is disabled entirely (`if (n_move_rule() && …)` at `Fairy-Stockfish/src/position.cpp:2624`; INI key parsed at `Fairy-Stockfish/src/parser.cpp:501`), but the halfmove counter is still maintained and still bounds the repetition-detection window (`position.cpp:2651`).

**Inference**

In the frozen contract the halfmove field means "plies since the last capture" and drives no draw rule; it exists for FEN compatibility and for bounding repetition detection. Since no position can repeat across a capture (material differs), the bound has no user-visible effect.

### 6. Consistency with the PyChess evidence page

**Proven source facts**

- The retained snapshot contains the full rules text: 7x7 board, no river/advisors/elephants, pawns sideways-capable from the start, stalemate a loss, 3x3 palace, general face-off rule, blockable horse, chariot as rook, cannon screen capture, soldier forward-or-sideways movement, and the five perpetual-check/chase bullets (sections "Rules", "Additional Rules - Perpetual checks and chases", and "The Pieces" in `discussion-drafts/evidence/pychess-minixiangqi-rules-2026-07-26.html`).
- **Flag:** the snapshot's starting-position diagram is an external CDN image (`static/images/XiangqiGuide/Minixiangqi.png`) that is not embedded in the HTML, and the page text never states which color moves first. The snapshot alone therefore underdetermines the exact piece placement and first mover.
- The gap is closed by the pinned PC checkout, which is the same code that serves the page: its `minixiangqi` start FEN is byte-identical to the FS built-in (`pychess-variants/client/variants.ts:1434`) and it names the first mover Red (`variants.ts:1439`).

No discrepancy was found between the evidence page, PC's variant definition, and the FS built-in start position.

### 7. Repetition counting semantics

**Proven source facts**

- With `nFoldRule = 3` (the inherited default, `Fairy-Stockfish/src/variant.h:125`), `Position::is_optional_game_end` walks history at 2-ply steps and fires when `++cnt + 1 >= n_fold_rule()` (`Fairy-Stockfish/src/position.cpp:2701-2702`) — that is, at the **third total occurrence of the position, counting its first occurrence**, within the window `min(halfmove counter, plies since setup) ≥ 4` (`position.cpp:2651-2653`).
- Position identity is the Zobrist key (placement plus side to move; no en-passant or castling components exist in this variant), not the halfmove/fullmove fields.
- Empirical, at the exact boundary:
  - `mx-rep-001` (bare-kings shuttle; occurrences at plies 0/4/8): `is_optional_game_end` = `(False, …)` after 4 plies, `(True, 0)` after 8, under both variants.
  - `mx-chs-004` (repeated position first arises after White's first move; occurrences at plies 1/5/9): `(False, …)` after 5 plies, `(True, ±…)` after 9 — repetition counting is position-based, not tied to the setup FEN.
- The value element of an `is_optional_game_end` result is **meaningless when the flag is False** (uninitialized in `pyffish_isOptionalGameEnd`, `Fairy-Stockfish/src/pyffish.cpp:339-354`; observed `(False, 32000)`, `(False, 1)` etc.). Only the flag may be read in that case.

### 8. Perpetual-check adjudication values, built-in versus AXF child

**Proven source facts**

- Built-in `minixiangqi` sets `perpetualCheckIllegal = true` (`Fairy-Stockfish/src/variant.cpp:1244`); the AXF child inherits it and adds `chasingRule = axf`. The result value is produced inside the repetition branch from the side-to-move perspective, perpetual check first, then chase, then plain repetition (`Fairy-Stockfish/src/position.cpp:2657-2660, 2697, 2701-2707`); `VALUE_MATE = 32000` (`Fairy-Stockfish/src/types.h:353`).
- Empirical, identical under built-in and AXF child:
  - Checked side to move at the third occurrence (`mx-chk-001`): `(True, 32000)` — side to move wins, the perpetual checker loses.
  - Checking side to move at the third occurrence (`mx-chk-002`): `(True, -32000)` — side to move loses.
- Chase adjudication exists only in the AXF child: the same shuttle shapes return `(True, 0)` under built-in and `(True, ∓32000)` under AXF (see divergence analysis).

### 9. pyffish API notes required to interpret observations

**Proven source facts**

- `game_result(variant, fen, moves)` is only meaningful when the final position has no legal move (`assert(!MoveList<LEGAL>…)` and the checkmate/stalemate fallthrough, `Fairy-Stockfish/src/pyffish.cpp:299-318`). It returns −32000 for both checkmate and stalemate here because `stalemateValue = -VALUE_MATE` (`variant.cpp:1242`); `gives_check` distinguishes the two.
- `gives_check` reports whether the side to move is in check (`pyffish.cpp:262`).
- `validate_fen(fen, variant)` takes the FEN **first** (`pyffish.cpp:376-384`), returns `FEN_OK = 1`, and is structural only: it accepted a kings-facing FEN (`3k3/P6/7/7/7/7/3K3 w - - 0 1`) that move-level legality treats as an in-check position. Fixture-position legality below was therefore established by `validate_fen` plus hand verification (kings present and inside palaces, side not to move never attacked, no facing kings) plus the engine accepting every scripted move.
- `is_immediate_game_end` is `(False, …)` for every fixture: Mini Xiangqi has no immediate variant-end rule; checkmate and stalemate surface through empty legal-move sets, repetition outcomes through `is_optional_game_end`.

## Proposed contract wording (for `docs/xiangqi-rules.md`)

> Draft text, ready to lift once fixtures are approved:
>
> - The starting position is FEN `rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1`.
> - Squares are named `a1` through `g7`: files `a`–`g` from Red's left, ranks `1`–`7` from Red's back rank. FEN piece-placement fields list rank 7 first and rank 1 last.
> - `w` is Red: uppercase pieces, ranks 1–2 at the start, king on `d1`, palace `c1`–`e3`, moves first. `b` is Black: lowercase pieces, king on `d7`, palace `c5`–`e7`.
> - A move is written as origin square then destination square, for example `b1b4`. No suffix of any kind exists in Mini Xiangqi: there is no promotion, castling, en passant, drop, or gating.
> - A position record is a 6-field FEN. The third and fourth fields are always `-`. The fifth field counts plies since the last capture and drives no rule; the sixth is the fullmove number, starting at 1 and incrementing after each Black move.
> - Two positions are the same, for repetition purposes, exactly when piece placement and side to move are equal; the counters are ignored.
> - A repetition outcome (neutral claimable draw, or a perpetual violation result) is evaluated when a position stands on the board for the third time, counting its first occurrence; the occurrences need not include the game's initial position.

## The fixture set

Schema per fixture JSON (`discussion-drafts/fixtures-draft/mx-*.json`): `id`, `title`, `area`, `start_fen` (6-field), `moves` (UCI list, possibly empty), `assertions` (`in_check`; `result_fen` after `moves`; optional exact `legal_moves`; optional `rejected_moves`; optional `applied` one-move FEN/check probes; `game_state` with `state` ∈ {ongoing, claimable-draw, red-wins, black-wins, draw}, `reason` ∈ {checkmate, stalemate, threefold-repetition, perpetual-check, perpetual-chase}, and `at_occurrence` for repetition outcomes), optional `boundary` (`prefix_len` one repetition cycle earlier, which must not yet be terminal or claimable), and `rationale`. Engine observations live in this document and `validation-report.json`, never in the fixture files.

| id | title | key assertion | engine: built-in | engine: AXF child |
|---|---|---|---|---|
| mx-move-001 | Start-position move enumeration | exactly the 19 listed moves; ongoing | AGREES | AGREES |
| mx-move-002 | Blocked horse | 12-move set; `d4c6`,`d4e6` rejected (leg d5 occupied) | AGREES | AGREES |
| mx-move-003 | Cannon screens | 15-move set; 0-screen and 2-screen captures rejected, 1-screen capture legal + FEN probe | AGREES | AGREES |
| mx-move-004 | Soldier moves | 6-move set; backward `d4d3` rejected; forward/sideways capture FEN probes | AGREES | AGREES |
| mx-move-005 | King palace confinement | 3-move set; `e2f2` (leaving palace) rejected | AGREES | AGREES |
| mx-move-006 | Check with forced evasions | legal set is exactly {a4d4, d1c1, d1e1}; in check | AGREES | AGREES |
| mx-end-001 | Checkmate | no legal moves, in check; red-wins/checkmate | AGREES (`game_result` −32000) | AGREES |
| mx-end-002 | Stalemate is a loss | no legal moves, not in check; red-wins/stalemate | AGREES (`game_result` −32000) | AGREES |
| mx-end-003 | Flying-general rejection | 7-move set; every file-leaving cannon move rejected | AGREES | AGREES |
| mx-rep-001 | Neutral threefold | claimable-draw exactly at 3rd occurrence (ply 8), not at ply 4 | AGREES `(True, 0)` | AGREES `(True, 0)` |
| mx-chk-001 | Perpetual check, checked side to move | black-wins/perpetual-check at 3rd occurrence | AGREES `(True, 32000)` | AGREES `(True, 32000)` |
| mx-chk-002 | Perpetual check, checker to move | black-wins/perpetual-check at 3rd occurrence | AGREES `(True, -32000)` | AGREES `(True, -32000)` |
| mx-chs-001 | Rook chases unprotected cannon | black-wins/perpetual-chase at 3rd occurrence | **DIVERGES** `(True, 0)` | AGREES `(True, -32000)` |
| mx-chs-002 | Same chase, protected cannon | claimable-draw (no violation) | AGREES `(True, 0)` | AGREES `(True, 0)` |
| mx-chs-003 | Soldier-chase exclusion | claimable-draw (soldiers not chase targets) | AGREES `(True, 0)` | **DIVERGES** `(True, -32000)` |
| mx-chs-004 | Rook chases unprotected horse; repeated position ≠ setup position | black-wins/perpetual-chase at 3rd occurrence | **DIVERGES** `(True, 0)` | AGREES `(True, 32000)` |

Validation method: `fixtures-draft/validate.py` runs every fixture under both variants and additionally verifies, at every ply of every fixture, that the two variants produce identical legal-move sets (they do — AXF changes adjudication only). All scripted moves were legal at their turns, all result FENs, check states, exact legal sets, rejected moves, and applied probes matched, and every `boundary` prefix was confirmed not yet ended. 0 check failures; raw output in `fixtures-draft/validation-report.json`.

## Divergence analysis

1. **`mx-chs-003` under the AXF child — the soldier-chase mismatch, now confirmed by execution.** Normative: perpetual pursuit of a soldier is not a chase violation (evidence page: chase targets exclude "generals and soldiers"; accepted contract line "Kings and soldiers are excluded as perpetual-chase targets"), so the repetition is neutral and merely claimable. The AXF child instead scores the chasing side lost, `(True, -32000)`. Root cause in source: the chase classifier excludes only kings and *unpromoted* soldiers (`attacks &= ~(pieces(sideToMove, KING, SOLDIER) ^ promoted_soldiers(sideToMove))`, `Fairy-Stockfish/src/position.cpp:2989`), and Mini Xiangqi's `soldierPromotionRank` default of rank 1 (`Fairy-Stockfish/src/variant.h:118`) marks every soldier promoted from the start — the same mechanism that grants sideways movement. Exact conformance therefore requires a fork change that separates movement state from chase-target classification (as anticipated in `axf-source-analysis.md`); no INI property can express it.
2. **`mx-chs-001` / `mx-chs-004` under built-in `minixiangqi`.** Expected and structural: the built-in has `chasingRule = NO_CHASING`, so a unilateral perpetual chase surfaces as a neutral `(True, 0)` repetition instead of the normative loss. This is why the app's target child enables AXF; the built-in rows are recorded as the baseline, not as a defect to fix.
3. **`mx-chs-002` (protected target) — no divergence.** The AXF child correctly classifies the chase of a defended cannon as no violation: the differential pair chs-001 (undefended, −32000) versus chs-002 (defended, 0) isolates the protection test (`roots = attackers_to(…)` at `Fairy-Stockfish/src/position.cpp:3015-3017`). The fixture deliberately uses the simplest protection shape (an unpinned rook defender covering both flight squares); pinned defenders, king-only defenders under flying general, and X-ray protection are the deferred edge cases.
4. No other divergences: movement, mate, stalemate, flying general, neutral repetition, and both perpetual-check parities agree with the normative expectations under both variants.

## Deferred fixtures

- **Mutual perpetual check → draw (required item 12).** Not minimally constructible; deferred. Every 4-ply mutual cycle needs each side to parry the incoming check and give check in the same move, every move. Capture-with-check breaks the repetition window; block-with-check fails against rook checks (no rook path connects the two block squares around a palace king) and self-defeats against cannon checks (adding the blocker restores the screen); and discovered-check shuttles are phase-incompatible on this board — with wazir kings confined to disjoint palace bands (ranks 1–3 versus 5–7), a shared file makes one side's screen the other side's exposure (moving the king into its own cannon's screen square walks into the opposing battery), and rank-based batteries produce permanent rather than alternating check. A mutual construction likely needs more material and a longer cycle; it belongs with the deferred edge-case set. The engine-side draw path does exist (`perpetualThem && perpetualUs → VALUE_DRAW`, `Fairy-Stockfish/src/position.cpp:2704`).
- **Check-precedence mixed case (required item 16).** Not minimally constructible; deferred. The checked side's king cannot be the chaser (moves by kings and soldiers never enter the chase set: `Fairy-Stockfish/src/position.cpp:3026`), so the natural "king evades and thereby chases" shape is unavailable; block-parries only create chase attacks perpendicular to the block move (rook/cannon movers drop same-line attacks: `position.cpp:3030-3031`), and rook-block geometries that re-check every White move while Black's blocker shuttles collapse to symmetric rook-versus-rook attacks, which the classifier excludes (`position.cpp:3010`). Any working construction seems to need a discovered-chase component, which the task scopes out of this first set. The precedence itself is nonetheless pinned at source level: the perpetual-check branch is evaluated before the chase branch in the shared result expression (`position.cpp:2704-2705`), and both `mx-chk-*` fixtures exercise that branch.

## Open flags and discussion items

1. **Auto-terminal versus claim-gated violations.** FS reports perpetual-check/chase results through the *optional* game-end channel at the third occurrence, exactly like a neutral repetition; the accepted contract says a neutral third occurrence is claimable while a unilateral violation "is a loss". The contract still needs to say whether the app commits the violation loss automatically at the third occurrence or requires a claim (PyChess's server auto-ends non-draw optional results; its rules text says "can be ruled to have lost"). The fixtures assert the normative result at the third occurrence and stay silent on the commit mechanism.
2. **Result identifiers by violator, not by sign.** The engine value is side-to-move-relative (`mx-chk-001` +32000 versus `mx-chk-002` −32000 for the same user-visible outcome). Contract wording and the app result taxonomy should name the violator ("checking side loses"), never the side to move at the detection ply. Both parities are now pinned by fixtures.
3. **Evidence snapshot underdetermines the diagram.** The retained rules page carries no embedded starting diagram and no first-mover statement; the pinned PC checkout supplies both and matches FS exactly (§6). If the evidence folder should be self-sufficient, retain the CDN diagram image (network action — not performed here) or record `variants.ts:1431-1442` as a supplementary normative citation.
4. **Halfmove-clock quirk.** Soldier moves do not reset the FEN halfmove counter (SOLDIER is not in `nMoveRuleTypes`). Harmless under `nMoveRule = 0`, but any future FEN interchange with tools assuming "pawn move resets the clock" should know.
5. **`is_optional_game_end` False values are garbage.** Any wrapper must ignore the value element when the flag is False (§7). Similarly, `game_result` may only be consulted when the legal-move set is empty.
6. **`validate_fen` is structural.** It accepts kings-facing FENs; fixture legality needs the additional checks listed in §9. The app's own FEN validation contract should state whether facing-kings setups are rejected at load or surface as in-check positions.
7. **History dependence of adjudication.** Repetition state lives in move history, not in a FEN. Imported positions given as bare FENs can never trigger repetition outcomes for occurrences predating the import; the app's import/replay design must feed full histories to the rules facade (consistent with `axf-evaluation-plan.md` §0).
8. **Protection definition remains open.** `mx-chs-002` pins only the simplest "defended by an unpinned piece on both flight squares" case; the exact protection definition (pins, king defenders under flying general, X-rays, defenders that could not legally recapture) is the next fixture tranche, per the accepted contract's Need-to-discuss list.

## Reproduction

```
cd /Users/tianren/coding/minixiangqi/discussion-drafts/fixtures-draft
python3 validate.py --json validation-report.json
```

Requires only the workspace pyffish build (path resolved relative to the script) and Python 3.14. Exit status 0 means every scripted check passed; the raw per-fixture, per-variant observations print as `OBS`/`BND` lines and are also written to the JSON report.
