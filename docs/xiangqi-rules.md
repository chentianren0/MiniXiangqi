# Mini Xiangqi Rules

This document is for product reviewers, rules reviewers, engineers, and testers who need one contract for legal Mini Xiangqi play and user-visible game results. It owns the adopted interpretation of Mini Xiangqi rules and the identifiers that connect prose to executable conformance fixtures. It does not own engine search policy, Fairy-Stockfish implementation details, UI presentation, implementation progress, or work tracking.

> **Status: Partially accepted rules contract.** The normative source, ordinary board and movement rules, absence of a move-count draw, threefold-repetition threshold, and high-level perpetual-check and perpetual-chase outcomes below are accepted. Exact edge-case definitions, notation, executable fixtures, and the runtime rules authority remain unresolved. Items under **Need to discuss** are non-normative and do not authorize implementation.

## Normative source

The selected public rules source is:

- [PyChess Mini Xiangqi rules](https://www.pychess.org/variants/minixiangqi)

A dated copy is retained outside this repository as workspace-only research evidence. It is not a runtime dependency and is not expected to exist in a standalone clone:

- Retrieved: `2026-07-26T11:58:51-0700`
- Workspace file: `/Users/tianren/coding/minixiangqi/discussion-drafts/evidence/pychess-minixiangqi-rules-2026-07-26.html`
- SHA-256: `a79b663618033c2a8e4db897b51499d6409ade0543520ee950c9c768eae92077`

The public source and the accepted conformance fixtures are evidence for this contract. Neither a Fairy-Stockfish search score nor an engine-specific optional result silently changes user-visible rules.

## Board and pieces

- Mini Xiangqi uses a 7-by-7 board.
- There is no river.
- There are no advisors or elephants.
- Each side has a king, chariots, horses, cannons, and soldiers.
- Each king remains inside its 3-by-3 palace.

The exact starting-position encoding, coordinate system, and notation must be frozen with the first approved fixtures.

## Movement

- A king moves one square orthogonally inside its palace.
- The two kings may not face each other on an otherwise empty file; they attack each other through that file.
- A chariot moves any number of unobstructed squares orthogonally.
- A horse uses Xiangqi horse movement and is blocked when its orthogonal first step is occupied.
- A cannon moves like a chariot when not capturing. A cannon capture requires exactly one intervening screen.
- A soldier moves and captures one square forward or one square sideways from the start of the game.

## Ordinary game results

- A position with no legal move is a loss for the player who cannot move.
- Check, legal check evasion, and checkmate must follow the movement and king-safety rules above.

The complete result taxonomy, including user-ended games and imported records, is defined jointly with [Game data](game-data.md) after the unresolved rule outcomes below are accepted.

## Move-count, repetition, perpetual check, and perpetual chase

- Mini Xiangqi has no automatic move-count draw. A Fairy-Stockfish variant used by the app must explicitly disable the inherited move-count rule with `nMoveRule = 0`.
- The repetition threshold is three occurrences of the same position.
- On the third neutral occurrence, the position becomes eligible to be ruled a draw. In both human-versus-computer play and Free Play, this eligibility does not automatically commit a terminal result: the user may continue or claim the draw.
- A unilateral perpetual-check violation is a loss for the checking side.
- A unilateral perpetual chase of the same unprotected target is a loss for the chasing side.
- Kings and soldiers are excluded as perpetual-chase targets.
- When one side perpetually checks and the other perpetually chases, the checking side is the side required to stop and loses if the violation is completed.
- When both sides commit the same class of perpetual violation, the result is a draw.

The target engine behavior follows the selected PyChess Mini Xiangqi rules and uses Fairy-Stockfish's AXF chasing adjudication as its implementation direction. AXF does not replace the selected public source as the user-visible rules authority.

These accepted outcomes still require minimized executable fixtures. Exact position-identity fields, protection tests, interruption rules, discovered and pinned attacks, mixed or mutual sequences, and the point at which a violation becomes terminal remain unresolved until those fixtures are approved.

## Conformance fixtures

Every accepted fixture should have a stable identifier and include:

- an initial position;
- complete move history;
- the expected legal moves or rejected move;
- the expected resulting position and check state;
- the expected game result, when any;
- a concise rule rationale.

Fixtures and this document must be reviewed together. A fixture is not accepted merely because PyChess or Fairy-Stockfish currently produces the same result.

## Need to discuss

> The following questions are non-normative and are not implementation requirements.

- Freeze the exact starting FEN, side to move, coordinates, and canonical move notation.
- Define exactly what makes a chased piece protected or unprotected.
- Define how interrupted, discovered, pinned, mutual, and mixed check/chase sequences are adjudicated.
- Define the exact deterministic history boundary at which neutral repetition becomes claimable and each perpetual violation becomes terminal offline.
- Approve minimized long-check and long-chase fixtures before selecting the runtime rules authority.
- If AXF is selected and approved fixtures expose a mismatch, decide whether configuration is sufficient or a Fairy-Stockfish fork change is required for soldier sideways movement and chase-target exclusion.
- Decide whether the app, Fairy-Stockfish, or another component executes the authoritative offline adjudication.
