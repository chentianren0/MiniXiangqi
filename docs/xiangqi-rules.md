# Mini Xiangqi Rules

This document is for product reviewers, rules reviewers, engineers, and testers who need one contract for legal Mini Xiangqi play and user-visible game results. It owns the adopted interpretation of Mini Xiangqi rules and the identifiers that connect prose to executable conformance fixtures. It does not own engine search policy, Fairy-Stockfish implementation details, UI presentation, implementation progress, or work tracking.

> **Status: Partially accepted rules contract.** The normative source, ordinary board and movement rules, the starting position, coordinate, and notation contract, absence of a move-count draw, the repetition and violation adjudication points, high-level perpetual-check and perpetual-chase outcomes, the rules interpretation version, the runtime rules authority, and the first approved fixture set in [`fixtures/rules/`](../fixtures/rules/) are accepted. The accepted interpretations of alternating check and chase, of chase renewal, and of a general as sole defender, the unconditional precedence of check over chase, the parity-independence of adjudication, and the target, attacker and value classes are also accepted. The exact definitions of protection, interruption, and discovered and pinned attacks, and the fixtures for those and for the accepted mutual and mixed outcomes, remain unresolved. Items under **Need to discuss** are non-normative and do not authorize implementation.

## Normative source

The selected public rules source is:

- [PyChess Mini Xiangqi rules](https://www.pychess.org/variants/minixiangqi)

A dated copy is retained outside this repository as workspace-only research evidence. It is not a runtime dependency and is not expected to exist in a standalone clone:

- Retrieved: `2026-07-26T11:58:51-0700`
- Workspace file: `/Users/tianren/coding/minixiangqi/discussion-drafts/evidence/pychess-minixiangqi-rules-2026-07-26.html`
- SHA-256: `a79b663618033c2a8e4db897b51499d6409ade0543520ee950c9c768eae92077`

The snapshot's starting-position diagram is an external image that is not embedded in the retained file, and its text does not name the first mover. Those two facts are supplied by the source's own implementation, verified in the workspace reference checkout of `pychess-variants` at commit `961fd6dd60ce76d3baced1a77df49ca58edcb315` (`client/variants.ts:1434` for the starting FEN, `client/variants.ts:1439` for Red moving first), which matches the built-in Fairy-Stockfish `minixiangqi` variant byte for byte.

The public source and the accepted conformance fixtures are evidence for this contract. Neither a Fairy-Stockfish search score nor an engine-specific optional result silently changes user-visible rules.

## Board and pieces

- Mini Xiangqi uses a 7-by-7 board.
- There is no river.
- There are no advisors or elephants.
- Each side has a king, chariots, horses, cannons, and soldiers.
- Each king remains inside its 3-by-3 palace.

## Starting position, coordinates, and notation

- The starting position is FEN `rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1`. This string is byte-identical in the selected public source's implementation and in the built-in Fairy-Stockfish `minixiangqi` variant.
- Squares are named `a1` through `g7`: files `a` to `g` from Red's left, ranks `1` to `7` from Red's back rank. A FEN piece-placement field lists rank 7 first and rank 1 last.
- `w` is Red: uppercase pieces, moves first, king starting on `d1`, palace `c1`–`e3`. `b` is Black: lowercase pieces, king starting on `d7`, palace `c5`–`e7`.
- The canonical machine notation for a move is the origin square followed by the destination square, for example `b1b4`. No move suffix exists: Mini Xiangqi has no promotion, castling, en passant, drop, or gating. This notation is canonical for fixtures, game archives, and the shared core interface. The notation shown to the user is a separate presentation decision, accepted in [interaction-design.md](interaction-design.md), and never changes what is stored or exchanged.
- A position record is a 6-field FEN. The third and fourth fields are always `-`. The fifth field counts plies since the last capture and drives no rule; a soldier move does not reset it. The sixth field is the fullmove number, starting at 1 and incrementing after each Black move.
- Two position records denote the same position exactly when piece placement and side to move are equal; the two counters are ignored.

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

The complete result taxonomy, including user-ended games and imported records, is defined jointly with [Game data](game-data.md); the fixture result identifiers below seed the rule-derived part of that taxonomy.

## Move-count, repetition, perpetual check, and perpetual chase

- Mini Xiangqi has no automatic move-count draw. A Fairy-Stockfish variant used by the app must explicitly disable the inherited move-count rule with `nMoveRule = 0`.
- The repetition threshold is three occurrences of the same position, counting the first time the position stands on the board. The repeated position need not be the game's initial position.
- Repetition and violation state derive from the game's complete move history. A bare position carries no prior occurrences.
- On the third neutral occurrence, the position becomes eligible to be ruled a draw. In both human-versus-AI play and Free Play, this eligibility does not automatically commit a terminal result: the user may continue or claim the draw.
- A unilateral perpetual violation becomes terminal automatically when a position first stands on the board for the third time with the violation sustained across its occurrences: the rules facade reports the loss for the violating side as a natural result, presented through the standard result flow. Only neutral repetition is claim-gated.
- A unilateral perpetual-check violation is a loss for the checking side.
- A unilateral perpetual chase of the same unprotected target is a loss for the chasing side.
- Adjudication does not depend on which side happens to be to move when the third occurrence lands. The engine currently evaluates a sustained chase over a window one move wider for one parity than the other, which costs a ply of detection in a unilateral chase and, in a mutual perpetual chase, resolves the required draw as a unilateral loss for whichever side did **not** make the quiet move that entered the repeating position; the entering side is handed the win. A fork correction is required; see [engine-integration.md](engine-integration.md).
- Kings and soldiers take no part in the perpetual-chase rule, as targets or as chasing pieces: neither may be the chased piece, and a move by a king or a soldier never creates a chase. A king's or a soldier's move may still open another piece's line or horse leg, and the resulting threat is a chase by that other piece. Kings and soldiers protect normally.
- A piece of the same type as the chasing piece is not a chase target, because the attack is mutual and the target can answer it — unless that piece is pinned and therefore cannot answer.
- Independently of protection, an attack by a horse or a cannon on a chariot is always a chase, because the capture wins material even after the recapture. No other value relation overrides protection here: the chariot is the only piece these rules treat as strictly stronger than the horse and the cannon, which are treated as equals. This clause is an adopted AXF practice that the retained source does not literally state; it is recorded as reasoning rather than as a reading of the source.
- When one side perpetually checks and the other perpetually chases, the checking side is the side required to stop and loses if the violation is completed. Check outranks chase unconditionally: a side that is perpetually checking loses even if it is simultaneously chasing, and even if the other side is also chasing. This orders check against chase; it does not override the mutual rule below, so two sides both perpetually checking remain a draw.
- When both sides commit the same class of perpetual violation, the result is a draw. Its reserved reason identifiers are `mutual-perpetual-check` and `mutual-perpetual-chase`, so the outcome is serializable distinctly from a claimed repetition draw; the exact adjudication of mutual sequences and their fixtures remain in the deferred edge-case tranche.

### Accepted interpretations

Three questions the retained public source does not settle. Each is recorded here as an interpretation rather than as a reading of the source, so that an authoritative AXF or CXA text on any of them reopens it as a contract amendment rather than arriving as a discovery.

- **A side alternating check and chase (一将一捉) commits neither violation.** Each accepted violation class is a single behaviour sustained across the three occurrences; a side that checks in one part of the cycle and chases in another sustains neither on its own across the counted occurrences, so no single class persists, so the position resolves as a neutral claimable repetition. This is the interpretation most likely to be wrong: competition practice is commonly summarised as forbidding the alternation, and the retained source does not address it. It is accepted because the source enumerates exactly two classes and defines each as persistent. The engine is not evidence either way: it implements no combined check-and-chase rule, so its silence is the absence of an implementation rather than agreement, and the objection to this reading is precisely that competition practice may supply one. The exposure is stated rather than minimised: where the opponent is not also violating, being wrong here costs only a claimable draw that should have been a loss; but where the opponent *is* violating, treating the alternation as innocent turns a mutual-violation draw into an automatic unilateral loss, which decides the game against the wrong side.
- **A chase renews when the chasing piece attacks the target from the square it now occupies and did not attack it from that square before the move.** A chasing piece that steps **away** from its target and still attacks it from the new square therefore renews the chase, while one that merely advances **toward** the target along a line on which its attack already stood does not. The alternative reading — that a chase renews only when the threat did not exist anywhere beforehand — would exempt a chaser that shuttles between two squares from each of which the threat is new, which is the behaviour the rule exists to catch.
- **A chase whose target's only defender is a general is adjudicated on the flying-generals condition alone.** Where a general could not in fact recapture for some other reason, the target is nonetheless treated as defended, so the sequence degrades to a neutral claimable repetition rather than a loss. This under-detects. Against a non-violating opponent that costs only a claimable draw in place of a loss; against a violating one it can, like the interpretation above, resolve a mutual violation as a unilateral loss. The alternative would decide games on a condition this contract does not otherwise define.

The target engine behavior follows the selected PyChess Mini Xiangqi rules and uses Fairy-Stockfish's AXF chasing adjudication as its implementation direction. AXF does not replace the selected public source as the user-visible rules authority.

The first minimized fixture set below pins these outcomes in their simplest forms, position identity, and the third-occurrence adjudication point. Exact protection tests beyond the simplest defended-target case, interruption rules, discovered and pinned attacks, and mixed or mutual sequences remain unresolved until their fixtures are approved.

## Rules interpretation version

The accepted rules interpretation carries an integer version, `rules_version`, owned by this document. It is `1` as of the starting-position, notation, and first-fixture freeze. It increments only when an accepted interpretation change alters a legal move or a user-visible result — never for prose clarification, fixture additions that pin existing behavior, engine or fork revisions, or search configuration. Game archives record `rules_id` (`minixiangqi`) and this version, per [game-data.md](game-data.md).

## Runtime rules authority

The shared core's rules facade, defined in [architecture.md](architecture.md), executes the authoritative offline adjudication on every platform: legal moves, check state, results, repetition, claim eligibility, and perpetual violations. The facade is deterministic over position and history and is gated by the approved conformance fixtures. It is built on the pinned Fairy-Stockfish fork library, but the fixtures — not engine agreement — are its authority: when an approved fixture exposes an engine mismatch, the fork receives a focused change. Search scores and search-only results never commit a user-visible outcome.

## Conformance fixtures

The approved executable fixtures live in [`fixtures/rules/`](../fixtures/rules/); that directory's README defines the schema, the `mx-<area>-NNN` identifier scheme, and the immutability rules. Every fixture carries a stable identifier, an initial position, a complete move history, the expected resulting position and check state, the expected game state, and a concise rule rationale; movement and ending fixtures additionally assert exact legal-move sets, rejected moves, or applied single-move probes. Fixture game states use the state identifiers `ongoing`, `claimable-draw`, `red-wins`, `black-wins`, and `draw` with the reason identifiers `checkmate`, `stalemate`, `threefold-repetition`, `perpetual-check`, and `perpetual-chase`, and they name results by rule outcome — the violating side loses — never by the side to move at detection. The reason identifiers `mutual-perpetual-check` and `mutual-perpetual-chase` are reserved for the deferred mutual-violation fixtures.

The first approved set contains sixteen fixtures:

- `mx-move-001` — the complete 19-move legal set in the starting position;
- `mx-move-002` — horse blocking on the occupied first step;
- `mx-move-003` — cannon slides and the exactly-one-screen capture requirement;
- `mx-move-004` — soldier forward and sideways moves and captures, and the rejected backward move;
- `mx-move-005` — king palace confinement and single-step movement;
- `mx-move-006` — a check position whose legal set is exactly its evasions;
- `mx-end-001` — checkmate as a loss for the side to move;
- `mx-end-002` — stalemate as a loss for the side to move;
- `mx-end-003` — rejection of moves that would leave the kings facing on an empty file;
- `mx-rep-001` — neutral threefold repetition claimable exactly at the third occurrence and not earlier;
- `mx-chk-001` and `mx-chk-002` — unilateral perpetual check as a loss for the checking side at the third occurrence, pinned for both side-to-move parities;
- `mx-chs-001` and `mx-chs-004` — unilateral perpetual chase of an unprotected cannon or horse as a loss for the chasing side at the third occurrence, including a repeated position that is not the setup position;
- `mx-chs-002` — the same chase against a protected target is no violation and yields a neutral claimable repetition;
- `mx-chs-003` — perpetual pursuit of a soldier is excluded from the chase rule and yields a neutral claimable repetition.

Two accepted outcomes have no fixture in this set: a mutual perpetual-check draw and a mixed sequence exercising check-over-chase precedence. **Both are constructible on the 7-by-7 board.** An earlier statement here that neither yielded a minimal construction was wrong: it rested on a case analysis that ruled out only general-move discoveries, together with a negative search its own author correctly labelled strong evidence rather than proof. Subsequent work constructed and executed both — mutual perpetual check in six pieces, with the side to move in check at every ply of the cycle, and check-over-chase precedence in five, with a control position proving the chase component real. Their fixtures belong to the deferred edge-case tranche, which is where the constructions will be approved.

Fixtures and this document must be reviewed together. A fixture is not accepted merely because PyChess or Fairy-Stockfish currently produces the same result. Engine conformance to the approved fixtures, including the accepted limits of AXF chase configuration, is owned by [Engine integration](engine-integration.md); engine observations never alter the fixtures' authority.

## Need to discuss

> The following questions are non-normative and are not implementation requirements.

- Define exactly what makes a chased piece protected or unprotected beyond the simplest defended-target case pinned by `mx-chs-002`.
- Define how interrupted, discovered, and pinned check/chase sequences are adjudicated, and how a violation's target and pattern must persist across the three occurrences. The mutual and mixed cases are settled at the outcome level by the accepted rules above; what remains for them is the definition of what makes two violations the same class, the reporting of a mutual chase distinctly from a claimed repetition, and their fixtures.
- Approve the deferred edge-case fixture tranche — protection variants, interruption, discovered and pinned attacks, mutual perpetual check, and check-over-chase precedence — before the rules facade's chase adjudication is relied on beyond the first approved set. Constructions now exist for the two outcomes that previously had none.
