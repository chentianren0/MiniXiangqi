# Rules Conformance Fixtures

This directory holds the approved, executable rules-conformance fixtures for the three games whose rules this product owns. Each fixture is one JSON file encoding a ruleset, a position, an optional move history, and the normative expectations the shared core's rules facade must satisfy. The fixtures and the rules contract of the game each names — [docs/xiangqi-rules.md](../../docs/xiangqi-rules.md) for Mini Xiangqi and Xiangqi, [docs/jieqi-rules.md](../../docs/jieqi-rules.md) for Jieqi — form one contract and are reviewed together: a change to either is a rules-contract change. The placement games are not here at all: their rules authority is their pinned engine, per [docs/placement-engine-integration.md](../../docs/placement-engine-integration.md), so this project has no second reading of them to hold one against.

Normative stance: every expected value in a fixture comes from the accepted rules contract and the selected public rules source, never from what any engine returns. Engine agreement or disagreement with a fixture is evidence recorded outside this directory; when an approved fixture exposes an engine mismatch, the engine side receives a focused change.

## Identifiers

Fixture IDs are stable and lowercase, `<game>-<area>-NNN`. The game prefix is `mx-` for Mini Xiangqi, `xq-` for Xiangqi and `jq-` for Jieqi, and it must agree with the fixture's own `variant` member — the loader refuses a file whose id and ruleset disagree, so a fixture cannot be filed under one game and replayed under the other. That agreement carries the most for the last two: Xiangqi and Jieqi share one board exactly, and a Jieqi position with nothing left face down is spelled exactly as the Xiangqi position it is not. The areas are shared:

- `*-move-*` — movement legality, blocking, palace and river confinement, check evasion.
- `*-end-*` — checkmate, stalemate loss, flying-general rejection.
- `*-cnt-*` — the move-count draw: absent in Mini Xiangqi, where long capture-free histories must stay ongoing; present in Xiangqi, where the hundredth capture-free ply draws; and present in Jieqi, where the eightieth does.
- `*-rep-*` — neutral repetition and claim eligibility.
- `*-chk-*` — perpetual check.
- `*-chs-*` — perpetual chase, protection, and chase-target exclusion.
- `*-mix-*` — cross-class and both-sides outcomes: mutual violations, check-over-chase precedence, and mixed-class sequences.
- `*-set-*` — setup legality: whether a game may begin in a stated position at all, which is the only area that asks a question about a position rather than about play over one.

An accepted fixture's `id`, position, moves, and assertions are immutable in meaning; a corrected interpretation is a new fixture (or an explicitly reviewed amendment), not a silent edit.

## Schema

A fixture is one of two shapes. Both carry:

- `id`, `title`, `area` — identity as above.
- `variant` — the ruleset identity the position is defined against: `minixiangqi`, `xiangqi` or `jieqi`. This is what the runner replays the fixture under, and it is load-bearing rather than a label: a fixture is never dispatched on the board its FEN implies, because the ruleset is not a property of the board. It names a ruleset of the rules contract, not an engine variant to select: the engine configuration that must satisfy these fixtures, including its chase adjudication, is defined in [docs/engine-integration.md](../../docs/engine-integration.md) for the first two — where the built-in engine variant named `minixiangqi` does not satisfy every Mini Xiangqi fixture — and in [docs/jieqi-engine-integration.md](../../docs/jieqi-engine-integration.md) for the third, which is answered by a different embedded engine entirely.
- `start_fen` — a 6-field FEN of that ruleset's board, per the frozen encoding in the rules contract. A `jieqi` position is that game's own record form: a face-down piece is written as its identity letter followed by `~`, so `P~` on a chariot's start square is a soldier standing there face down, and a record with no `~` in it is a position of that game with nothing left concealed. The record holds every hidden identity, which is what makes a fixture's expectations derivable at all; who is entitled to know one is a rule of the game that no fixture pins.
- `rationale` — the rule the fixture pins, in one or two sentences.

Beyond those four, a **setup fixture** carries `setup` alone and a **play fixture** carries `moves`, `assertions` and `boundary`. That member is what the loader dispatches on, and a file mixing the two shapes is a load error rather than a fixture half of whose members are ignored: a history has no meaning for a position being judged as a starting point, and a legal-move set over a position no game could reach would pin an answer nothing asks for.

### A setup fixture

- `setup` — what the setup-legality predicate must answer for `start_fen`:
  - `status` — the answer the entry returns: `ok` for a legal setup, `illegal-position` for a position that breaks a setup rule, or `invalid-fen` for one that is not a position of the game's board at all and so reaches no rule. It is stated rather than derived from `rule`, because that third answer has no rule to derive it from.
  - `rule` — the setup rule that broke: `piece-count`, `palace`, `elephant-side`, `soldier-rank`, `facing-generals`, `opponent-in-check`, `not-frozen-start`, or `not-dealt-start`. Non-null exactly when `status` is `illegal-position`. The last two belong to games whose rules define no predicate at all: `not-frozen-start` to a game that begins from one position, and `not-dealt-start` to Jieqi, which begins from a dealt start and holds one of those for every deal.
  - `side` — the side the violation belongs to, `red` or `black`, or `null` where the rule names none. It is `null` whenever `rule` is.
  - `square` — the point the violation stands at, or `null` where the rule names none. It is `null` whenever `rule` is.

Which of `side` and `square` a rule carries is that rule's own and is pinned by the fixtures rather than restated in the loader.

### A play fixture

- `moves` — the complete move history from `start_fen`, in canonical coordinate notation (`<from><to>`, e.g. `b1b4`, or `a9a10` on the larger board); possibly empty. Every move must be legal at its turn.
- `assertions` — the normative expectations at the position reached after `moves`:
  - `in_check` — whether the side to move is in check.
  - `result_fen` — the exact expected 6-field FEN.
  - `legal_moves` — when non-null, the exact complete legal-move set.
  - `rejected_moves` — when non-null, moves that must be illegal in this position; the `rationale` states why.
  - `applied` — when non-null, a list of single-move probes, each with `move`, `result_fen`, and `in_check`: applying the move must produce exactly that FEN and check state.
  - `game_state` — the normative state from `ongoing`, `claimable-draw`, `red-wins`, `black-wins`, or `draw`. For `ongoing`, `reason` is `null`; otherwise `reason` is one of `checkmate`, `stalemate`, `threefold-repetition`, `perpetual-check`, `perpetual-chase`, `fifty-move-rule`, or `forty-move-rule`, with `at_occurrence` for repetition-based outcomes and `0` for the ones that are not. The last two are one game's each: `fifty-move-rule` is Xiangqi's and `forty-move-rule` is Jieqi's, two games counting captureless play to two different numbers. The reasons `mutual-perpetual-check` and `mutual-perpetual-chase` belong to the mutual-violation fixtures, the `mx-mix-*` and `jq-mix-*` ones carrying a `draw` state. Results are named by rule outcome, never by the side to move at detection.
- `boundary` — when non-null, a `prefix_len` one repetition cycle earlier at which the outcome must not yet exist, pinning that the outcome attaches exactly at the asserted occurrence, plus a human-readable `expect` note stating what holds at that prefix.

## Consumption

The shared core's rules facade is gated by these fixtures on every platform, under the ruleset each declares: a play fixture's history must replay with exactly the asserted legality, positions, check states and game states, and a setup fixture's position must be judged with exactly the asserted status, rule, side and square. The core test suite is the consuming harness, and it is the same harness everywhere.
