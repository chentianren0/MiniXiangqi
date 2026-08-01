# Rules Conformance Fixtures

This directory holds the approved, executable rules-conformance fixtures for both games this product plays. Each fixture is one JSON file encoding a ruleset, a position, an optional move history, and the normative expectations the shared core's rules facade must satisfy. The fixtures and [docs/xiangqi-rules.md](../../docs/xiangqi-rules.md) form one contract and are reviewed together: a change to either is a rules-contract change.

Normative stance: every expected value in a fixture comes from the accepted rules contract and the selected public rules source, never from what any engine returns. Engine agreement or disagreement with a fixture is evidence recorded outside this directory; when an approved fixture exposes an engine mismatch, the engine side receives a focused change.

## Identifiers

Fixture IDs are stable and lowercase, `<game>-<area>-NNN`. The game prefix is `mx-` for Mini Xiangqi and `xq-` for Xiangqi, and it must agree with the fixture's own `variant` member — the loader refuses a file whose id and ruleset disagree, so a fixture cannot be filed under one game and replayed under the other. The areas are shared:

- `*-move-*` — movement legality, blocking, palace and river confinement, check evasion.
- `*-end-*` — checkmate, stalemate loss, flying-general rejection.
- `*-cnt-*` — the move-count draw: absent in Mini Xiangqi, where long capture-free histories must stay ongoing, and present in Xiangqi, where the hundredth capture-free ply draws.
- `*-rep-*` — neutral repetition and claim eligibility.
- `*-chk-*` — perpetual check.
- `*-chs-*` — perpetual chase, protection, and chase-target exclusion.
- `*-mix-*` — cross-class and both-sides outcomes: mutual violations, check-over-chase precedence, and mixed-class sequences.

An accepted fixture's `id`, position, moves, and assertions are immutable in meaning; a corrected interpretation is a new fixture (or an explicitly reviewed amendment), not a silent edit.

## Schema

Every fixture has:

- `id`, `title`, `area` — identity as above.
- `variant` — the ruleset identity the position is defined against: `minixiangqi` or `xiangqi`. This is what the runner replays the fixture under, and it is load-bearing rather than a label: a fixture is never dispatched on the board its FEN implies, because the ruleset is not a property of the board. It names a ruleset of the rules contract, not an engine variant to select: the engine configuration that must satisfy these fixtures, including its chase adjudication, is defined in [docs/engine-integration.md](../../docs/engine-integration.md), and the built-in engine variant named `minixiangqi` does not satisfy every Mini Xiangqi fixture.
- `start_fen` — a 6-field FEN of that ruleset's board, per the frozen encoding in the rules contract.
- `moves` — the complete move history from `start_fen`, in canonical coordinate notation (`<from><to>`, e.g. `b1b4`, or `a9a10` on the larger board); possibly empty. Every move must be legal at its turn.
- `assertions` — the normative expectations at the position reached after `moves`:
  - `in_check` — whether the side to move is in check.
  - `result_fen` — the exact expected 6-field FEN.
  - `legal_moves` — when non-null, the exact complete legal-move set.
  - `rejected_moves` — when non-null, moves that must be illegal in this position; the `rationale` states why.
  - `applied` — when non-null, a list of single-move probes, each with `move`, `result_fen`, and `in_check`: applying the move must produce exactly that FEN and check state.
  - `game_state` — the normative state from `ongoing`, `claimable-draw`, `red-wins`, `black-wins`, or `draw`. For `ongoing`, `reason` is `null`; otherwise `reason` is one of `checkmate`, `stalemate`, `threefold-repetition`, `perpetual-check`, `perpetual-chase`, or `fifty-move-rule`, with `at_occurrence` for repetition-based outcomes and `0` for the ones that are not. The reasons `mutual-perpetual-check` and `mutual-perpetual-chase` belong to the mutual-violation fixtures, the `mx-mix-*` ones carrying a `draw` state. Results are named by rule outcome, never by the side to move at detection.
- `boundary` — when non-null, a `prefix_len` one repetition cycle earlier at which the outcome must not yet exist, pinning that the outcome attaches exactly at the asserted occurrence, plus a human-readable `expect` note stating what holds at that prefix.
- `rationale` — the rule the fixture pins, in one or two sentences.

## Consumption

The shared core's rules facade is gated by these fixtures on every platform: each fixture's history must replay, under the ruleset it declares, with exactly the asserted legality, positions, check states, and game states. The core test suite is the consuming harness once it exists; until then, the fixtures are validated against reference engines as workspace-only research evidence, which never substitutes for the normative expectations.
