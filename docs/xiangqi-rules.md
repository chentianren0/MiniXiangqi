# Rules

This document is the one contract for legal play and user-visible results in the product's two xiangqi games: **Mini Xiangqi** on a 7-by-7 board and **Xiangqi** on a 9-by-10 board. It owns the adopted interpretation of their rules and the identifiers that connect prose to the executable conformance fixtures. It does not own engine search policy, Fairy-Stockfish implementation details, UI presentation, or the placement games, whose rules authority is their pinned engine per [placement-engine-integration.md](placement-engine-integration.md).

> **Status: binding, with one gap a reader must know about.** Everything stated here is accepted. The exact prose definitions of protection, interruption, discovered and pinned attacks, and of what makes two violations the same class are not settled; the approved fixtures pin those cases by instance rather than by definition, and the fixtures are the authority until the prose exists.

The two games share almost everything: one notation, one position record, one adjudication. What differs is the board, the piece set, and two rules that follow from them. Everything below is stated once for both games and marked where it is not.

## The game axis

Every position, move, archive and session belongs to exactly one game. Nothing infers which: the two boards differ in size today, so a position happens to imply one, but the ruleset is not a property of the board and a core reading it off the position would be guessing the moment two games shared a geometry. The identifier is `rules_id`, and two of its values are this document's:

| `rules_id` | board | palace | river | pieces per side |
|---|---|---|---|---|
| `minixiangqi` | 7 files × 7 ranks | `c1`–`e3`, `c5`–`e7` | none | general, 2 chariots, 2 horses, 2 cannons, 5 soldiers |
| `xiangqi` | 9 files × 10 ranks | `d1`–`f3`, `d8`–`f10` | between ranks 5 and 6 | general, 2 chariots, 2 horses, 2 elephants, 2 advisors, 2 cannons, 5 soldiers |

Mini Xiangqi has no river, no elephants and no advisors. Xiangqi has all three.

## Normative sources

For **Mini Xiangqi** the selected public rules source is [PyChess Mini Xiangqi rules](https://www.pychess.org/variants/minixiangqi). A dated copy is retained outside this repository as workspace-only research evidence. It is not a runtime dependency and is not expected to exist in a standalone clone:

- Retrieved: `2026-07-26T11:58:51-0700`
- Workspace file: `/Users/tianren/coding/minixiangqi/discussion-drafts/evidence/pychess-minixiangqi-rules-2026-07-26.html`
- SHA-256: `a79b663618033c2a8e4db897b51499d6409ade0543520ee950c9c768eae92077`

The snapshot's starting-position diagram is an external image that is not embedded in the retained file, and its text does not name the first mover. Both facts come instead from the source's own implementation, in the workspace reference checkout of `pychess-variants` at commit `961fd6dd60ce76d3baced1a77df49ca58edcb315` — `client/variants.ts:1434` for the starting FEN and `client/variants.ts:1439` for Red moving first — which matches the built-in Fairy-Stockfish `minixiangqi` variant byte for byte.

For **Xiangqi** the geometry, piece set, palace, river and starting position are the standard game's and are not in dispute; they are stated in this document directly. No dated snapshot is retained for them and none is claimed. The pinned fork's built-in `xiangqi` variant declares the same values, which is what [engine-integration.md](engine-integration.md) binds; that agreement is a fact about the engine axis, not the source of the rule.

The public source and the accepted conformance fixtures are the evidence for this contract. Neither a Fairy-Stockfish search score nor an engine-specific optional result silently changes user-visible rules.

## Starting positions, coordinates, and notation

- The starting position of Mini Xiangqi is FEN `rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1`, and of Xiangqi `rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1`. Each game has exactly one, and it is frozen. Which further positions a game may begin from is the setup-legality section's question below.
- Files are lettered `a` upward from Red's left and ranks numbered `1` upward from Red's back rank: `a1`–`g7` in Mini Xiangqi and `a1`–`i10` in Xiangqi. A FEN piece-placement field lists the highest rank first and rank 1 last.
- `w` is Red: uppercase pieces, moves first. `b` is Black: lowercase pieces.
- A square is a file letter followed by a rank written in decimal with no leading zero — two characters in Mini Xiangqi, and two or three in Xiangqi, where `a10` is a square and `a010` is not. The canonical machine notation for a move is the origin square followed by the destination square, so a move is four characters in Mini Xiangqi and four to six in Xiangqi, of which `a9a10` is the longest. No move suffix exists in either game: there is no promotion, castling, en passant, drop, or gating. A soldier crossing the river changes how it moves, and the player never chooses it, so it is not spelled. Parsing needs no lookahead, because a file letter is never a digit: the digit run after a file ends exactly where the next square begins, and `a1a10` is `a1` then `a10` and can be read no other way.
- This notation is canonical for fixtures, game archives, and the shared core interface. The notation shown to the user is a separate presentation decision, fixed in [interaction-design.md](interaction-design.md), and never changes what is stored or exchanged.
- Beside the board moves, each game's canonical move-text grammar holds one turn action: `claim`, the word alone. It is a turn action of the side to move, lawful exactly when the claimable neutral repetition stands, and it ends the game as that claimed draw with reason `threefold-repetition`. It moves no piece. It exists for game exchange between implementations and lives only there: no archive spells it — an archive's terminal information records the claimed draw itself — no fixture carries it, and it never crosses the core's C interface.
- A position record is a 6-field FEN. The third and fourth fields are always `-`. The sixth field is the fullmove number, starting at 1 and incrementing after each Black move. The fifth field counts plies since the last capture; what it drives differs by game and is stated under the move-count rule below.
- Two position records denote the same position exactly when piece placement and side to move are equal; the two counters are ignored.

**Serialized vocabulary and display copy differ deliberately.** The identifiers frozen here and in the fixtures are technical vocabulary and never change to follow a display string: the FEN letter `k`, the word *square* in this document's technical prose, and reason identifiers such as `stalemate` mean what this document says they mean, in every archive, fixture, and core interface. The approved fixtures' own titles and rationales are frozen artifacts and keep the vocabulary they were approved with, including *king* where they say it. What the user reads is a separate matter, carried by the shipped string catalogs: English says *General* for the piece, *point* for an intersection of the board as [interaction-design.md](interaction-design.md) requires, and the approved reason words. Neither vocabulary is a translation of the other, and neither may be edited to make them match.

## Movement

Shared by both games:

- A general moves one square orthogonally inside its palace.
- The two generals may not face each other on an otherwise empty file; they attack each other through that file.
- A chariot moves any number of unobstructed squares orthogonally.
- A horse moves one square orthogonally and then one diagonally outward, and is blocked when that first orthogonal square is occupied — by any piece, its own or the opponent's. What blocks it is the intervening square, never the destination.
- A cannon moves like a chariot when not capturing. A cannon capture requires exactly one intervening screen.

Mini Xiangqi only:

- A soldier moves and captures one square forward or one square sideways from the start of the game, and never backward.

Xiangqi only:

- An advisor moves one square diagonally and never leaves its palace.
- An elephant moves exactly two squares diagonally and is blocked when the square between is occupied. It never crosses the river: an elephant stays on its own side of the board for the whole game.
- A soldier moves and captures one square forward until it crosses the river, after which it may also move and capture one square sideways. It never moves backward.

## Ordinary game results

- A position with no legal move is a loss for the player who cannot move. Stalemate is not a draw in either game.
- Check, legal check evasion, and checkmate must follow the movement and general-safety rules above.

The complete result taxonomy, including user-ended games and imported records, is defined jointly with [game-data.md](game-data.md); the fixture result identifiers below seed the rule-derived part of that taxonomy.

## Setup legality

A position a game may be set up in is a question of that game's own rules, and **Xiangqi is the game that answers it**: it defines the predicate below, and a Xiangqi game may begin from any position the predicate accepts. **Mini Xiangqi defines none**, so a Mini Xiangqi game begins from its frozen starting position and from no other.

A Xiangqi position is one to set up in when all of the following hold. They are stated in the order a violation is reported in, so a position breaking more than one of them is refused under the first:

- **Piece counts.** Exactly one general per side, and per side at most two advisors, two elephants, two horses, two chariots, two cannons, and five soldiers.
- **The palace.** Every general and every advisor stands inside its own palace, `d1`–`f3` for Red and `d8`–`f10` for Black.
- **The elephants' side.** Every elephant stands on one of the seven points its own side of the river offers it: `a3`, `c1`, `c5`, `e3`, `g1`, `g5` and `i3` for Red, and `a8`, `c6`, `c10`, `e8`, `g6`, `g10` and `i8` for Black.
- **The soldiers' rank.** No soldier stands behind its own starting soldier rank: a Red soldier on rank 4 or above, a Black soldier on rank 7 or below.
- **The side not to move is not in check.** The two generals facing each other on an otherwise empty file is such a check, so a position that stands them so is refused by this clause. The side **to** move may stand in check, and answering it is that side's first move.

The predicate reads piece placement and the side to move, which is the whole of what a position record denotes. Whether a position is worth playing is not its question and neither is whether it is already decided: a position offering the side to move no legal move is a legal setup and is not a game to begin, which is [core-interface.md](core-interface.md)'s rule for creating a session rather than this document's.

Setup legality is pinned as every other rule area is, by conformance fixtures of an area of its own under the identifier scheme below — `xq-set-NNN` — each stating a position and either the clause that refuses it or its acceptance.

## The move-count rule

This is one of the two rules that differ.

- **Mini Xiangqi has no automatic move-count draw.** The fifth FEN field drives no rule there, and a soldier move does not reset it. A Fairy-Stockfish variant used for this game must explicitly disable the inherited move-count rule with `nMoveRule = 0`.
- **Xiangqi draws a game that has run fifty moves — one hundred plies — without a capture.** Only a capture resets the count: no piece's own move resets it, soldiers included, because a soldier's advance is not irreversible in the way the rule elsewhere assumes. The draw is automatic rather than claim-gated, and its reason identifier is `fifty-move-rule`.

## Repetition, perpetual check, and perpetual chase

Stated once; both games adjudicate identically except for the one chase-target difference marked below.

- The repetition threshold is three occurrences of the same position, counting the first time the position stands on the board. The repeated position need not be the game's initial position.
- Repetition and violation state derive from the game's complete move history. A bare position carries no prior occurrences, and a position set up to be played from is bare.
- On the third neutral occurrence, the position becomes eligible to be ruled a draw. In both human-versus-AI play and Free Play, this eligibility does not automatically commit a terminal result: the user may continue or claim the draw.
- A unilateral perpetual violation becomes terminal automatically when a position first stands on the board for the third time with the violation sustained across its occurrences: the rules facade reports the loss for the violating side as a natural result, presented through the standard result flow. Only neutral repetition is claim-gated.
- A unilateral perpetual-check violation is a loss for the checking side.
- A unilateral perpetual chase of the same unprotected target is a loss for the chasing side.
- **Adjudication does not depend on which side happens to be to move when the third occurrence lands.** The unmodified engine evaluates a sustained chase over a window one move wider for one parity than the other, which costs a ply of detection in a unilateral chase and, in a mutual perpetual chase, resolves the required draw as a unilateral loss for whichever side did **not** make the quiet move that entered the repeating position. The fork correction that restores this rule is in [engine-integration.md](engine-integration.md)'s change set.
- Generals take no part in the perpetual-chase rule, as targets or as chasing pieces: a general may not be the chased piece, and a general's move never creates a chase. Its move may still open another piece's line or horse leg, and the resulting threat is a chase by that other piece. Generals protect normally.
- **Soldiers are the second difference between the games.** In **Mini Xiangqi** a soldier is excluded exactly as a general is: it may not be a chase target, and its move never creates a chase. In **Xiangqi** a soldier that has crossed the river is an ordinary chase target; one that has not is excluded. The reason is the same in both: the exclusion is of a piece that cannot answer an attack by stepping aside, and a Mini Xiangqi soldier moves sideways from the first move of the game. Whichever way a build reads this, one of `mx-chs-003` and `xq-chs-002` fails it.
- A piece of the same type as the chasing piece is not a chase target, because the attack is mutual and the target can answer it — unless that piece is pinned and therefore cannot answer.
- Independently of protection, an attack by a horse or a cannon on a chariot is always a chase, because the capture wins material even after the recapture. No other value relation overrides protection here: the chariot is the only piece these rules treat as strictly stronger than the horse and the cannon, which are treated as equals. This clause is an adopted AXF practice that the retained source does not literally state; it is recorded as reasoning rather than as a reading of the source.
- When one side perpetually checks and the other perpetually chases, the checking side is the side required to stop and loses if the violation is completed. Check outranks chase unconditionally: a side that is perpetually checking loses even if it is simultaneously chasing, and even if the other side is also chasing. This orders check against chase; it does not override the mutual rule below, so two sides both perpetually checking remain a draw.
- When both sides commit the same class of perpetual violation, the result is a draw. Its reason identifiers are `mutual-perpetual-check` and `mutual-perpetual-chase`, so the outcome is serializable distinctly from a claimed repetition draw; their fixtures are the `mx-mix-*` ones carrying a `draw` state, and the engine reports the rule directly.

### Accepted interpretations

Three questions the retained public source does not settle. Each is recorded as an interpretation rather than as a reading of the source, so that an authoritative AXF or CXA text on any of them reopens it as a contract amendment rather than arriving as a discovery. All three apply to both games.

- **A side alternating check and chase (一将一捉) commits neither violation.** Each accepted violation class is a single behaviour sustained across the three occurrences; a side that checks in one part of the cycle and chases in another sustains neither on its own across the counted occurrences, so no single class persists, so the position resolves as a neutral claimable repetition. This is the interpretation most likely to be wrong: competition practice is commonly summarised as forbidding the alternation, and the retained source does not address it. It is accepted because the source enumerates exactly two classes and defines each as persistent. The engine is not evidence either way: it implements no combined check-and-chase rule, so its silence is the absence of an implementation rather than agreement. The exposure is stated rather than minimised: where the opponent is not also violating, being wrong here costs only a claimable draw that should have been a loss; but where the opponent *is* violating, treating the alternation as innocent turns a mutual-violation draw into an automatic unilateral loss, which decides the game against the wrong side.
- **A chase renews when the chasing piece attacks the target from the square it now occupies and did not attack it from that square before the move.** A chasing piece that steps **away** from its target and still attacks it from the new square therefore renews the chase, while one that merely advances **toward** the target along a line on which its attack already stood does not. The alternative reading — that a chase renews only when the threat did not exist anywhere beforehand — would exempt a chaser that shuttles between two squares from each of which the threat is new, which is the behaviour the rule exists to catch.
- **A chase whose target's only defender is a general is adjudicated on the flying-generals condition alone.** Where a general could not in fact recapture for some other reason, the target is nonetheless treated as defended, so the sequence degrades to a neutral claimable repetition rather than a loss. This under-detects. Against a non-violating opponent that costs only a claimable draw in place of a loss; against a violating one it can, like the interpretation above, resolve a mutual violation as a unilateral loss. The alternative would decide games on a condition this contract does not otherwise define.

The target engine behavior follows the selected public rules sources and uses Fairy-Stockfish's AXF chasing adjudication as its implementation direction. AXF does not replace those sources as the user-visible rules authority.

## Rules interpretation version

The accepted rules interpretation carries an integer version, `rules_version`, and this document owns what it means for the two games above. It is `1`, as it is for every game the app carries. It increments only when an accepted interpretation change alters a legal move or a user-visible result — never for prose clarification, fixture additions that pin existing behavior, engine or fork revisions, or search configuration. Game archives record `rules_id` and this version, per [game-data.md](game-data.md).

## Runtime rules authority

The shared core's rules facade, defined in [architecture.md](architecture.md), executes the authoritative offline adjudication on every platform: legal moves, check state, results, repetition, claim eligibility, and perpetual violations. Every one of its questions is asked of a named game; none is answered from a position alone. The facade is deterministic over game, position and history and is gated by the approved conformance fixtures. It is built on the pinned Fairy-Stockfish fork library, but the fixtures — not engine agreement — are its authority: when an approved fixture exposes an engine mismatch, the fork receives a focused change. Search scores and search-only results never commit a user-visible outcome.

## Conformance fixtures

The approved executable fixtures live in [`fixtures/rules/`](../fixtures/rules/); that directory's README defines the schema, the identifier scheme, and the immutability rules. Identifiers are `mx-<area>-NNN` for Mini Xiangqi and `xq-<area>-NNN` for Xiangqi, and each fixture names its own game in a `variant` member that the runner dispatches on. Every fixture carries a stable identifier, an initial position, a complete move history, the expected resulting position and check state, the expected game state, and a concise rule rationale; movement and ending fixtures additionally assert exact legal-move sets, rejected moves, or applied single-move probes. A setup fixture is the one shape outside that: it carries a position and either the clause that refuses it or its acceptance, and no move line. Fixture game states use the state identifiers `ongoing`, `claimable-draw`, `red-wins`, `black-wins`, and `draw` with the reason identifiers `checkmate`, `stalemate`, `threefold-repetition`, `perpetual-check`, `perpetual-chase`, and `fifty-move-rule`, and they name results by rule outcome — the violating side loses — never by the side to move at detection. The reason identifiers `mutual-perpetual-check` and `mutual-perpetual-chase` belong to the mutual-violation fixtures, which are the `mx-mix-*` ones carrying a `draw` state.

The approved set contains **eighty-nine** fixtures: sixty-eight for Mini Xiangqi and twenty-one for Xiangqi.

For Mini Xiangqi, these pin the rules above in their simplest forms, position identity, and the third-occurrence adjudication point:

- `mx-move-001` — the complete 19-move legal set in the starting position;
- `mx-move-002` — horse blocking on the occupied first step;
- `mx-move-003` — cannon slides and the exactly-one-screen capture requirement;
- `mx-move-004` — soldier forward and sideways moves and captures, and the rejected backward move;
- `mx-move-005` — general palace confinement and single-step movement;
- `mx-move-006` — a check position whose legal set is exactly its evasions;
- `mx-end-001` — checkmate as a loss for the side to move;
- `mx-end-002` — stalemate as a loss for the side to move;
- `mx-end-003` — rejection of moves that would leave the generals facing on an empty file;
- `mx-rep-001` — neutral threefold repetition claimable exactly at the third occurrence and not earlier;
- `mx-chk-001` and `mx-chk-002` — unilateral perpetual check as a loss for the checking side at the third occurrence, pinned for both side-to-move parities;
- `mx-chs-001` and `mx-chs-004` — unilateral perpetual chase of an unprotected cannon or horse as a loss for the chasing side at the third occurrence, including a repeated position that is not the setup position;
- `mx-chs-002` — the same chase against a protected target is no violation and yields a neutral claimable repetition;
- `mx-chs-003` — perpetual pursuit of a soldier is excluded from the chase rule and yields a neutral claimable repetition.

The remainder extend the same areas: chariot range and obstruction in `mx-move-*`; position identity, and the absence of prior occurrences in a bare position, in `mx-rep-*`; the absent move-count draw in `mx-cnt-*`; discovered and battery check in `mx-chk-*`; the protection, renewal, pinned-defender, and target-exclusion variants that make up the bulk of `mx-chs-*`; and the cross-class and both-sides outcomes in `mx-mix-*`.

**A mutual perpetual-check draw and check-over-chase precedence are both constructible on the 7-by-7 board, and both are pinned.** `mx-mix-001` is the mutual perpetual check, six pieces with the side to move in check at every ply of the cycle and each side's move both an evasion and a check. `mx-mix-004` and `mx-mix-007` are the precedence, in five pieces each: the first has the checked side chasing, the second has the checking side chasing with the same move, and both lose for the checking side. Each carries a deletion control identical but for the piece that supplies the check — `mx-chs-027` and `mx-chs-037` — which is a perpetual chase in its own right and is what proves the chase component real.

For Xiangqi, twelve pin what the 9-by-10 board adds and what it changes:

- `xq-move-001` — the horse's blocking square, on a board where the same horse has eight destinations;
- `xq-move-002` — the elephant's blocked eye and its confinement to its own side of the river, as two separate rules;
- `xq-move-003` — palace confinement for the general and the advisor, and the advisor's diagonal step;
- `xq-move-004` — a soldier before and a soldier after the river in one position, and neither retreating;
- `xq-move-005` — the flying-generals rule, as the reason every move of the only blocking piece is illegal;
- `xq-end-001` and `xq-end-002` — checkmate, and stalemate as a loss for the side to move;
- `xq-chk-001` — unilateral perpetual check as a loss for the checking side at the third occurrence;
- `xq-chs-001` — unilateral perpetual chase of an unprotected cannon as a loss for the chasing side;
- `xq-chs-002` — a soldier that has crossed the river **is** a chase target, which is the difference from `mx-chs-003`;
- `xq-rep-001` — neutral repetition claimable exactly at the third occurrence;
- `xq-cnt-001` — the move-count draw, at the ply it lands and not two plies earlier.

The remaining nine are `xq-set-*`, the setup-legality area: one refusal per clause of the predicate above, a composed scene and a side-to-move-in-check position it accepts, and one position of no board at all, which the structural precondition refuses before any clause is reached. `mx-set-001` and `mx-set-002` are the pair that says Mini Xiangqi defines no predicate — its frozen start accepted, and any other position refused as not that start.

Fixtures and this document must be reviewed together. A fixture is not accepted merely because PyChess or Fairy-Stockfish produces the same result. Engine conformance to the approved fixtures, including the accepted limits of AXF chase configuration, is owned by [engine-integration.md](engine-integration.md); engine observations never alter the fixtures' authority.
