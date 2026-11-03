# Xiangqi and Mini Xiangqi rules

These are the rules of legal play and user-visible results in **Mini Xiangqi**, on a 7-by-7 board, and **Xiangqi**, on a 9-by-10 board, with the identifiers that connect them to the conformance fixtures.

The two games share almost everything: one notation, one position record, one adjudication. What differs is the board, the piece set, and the rules that follow from them. Everything below is stated once for both games and marked where it is not.

The exact prose definitions of protection, interruption, discovered and pinned attacks, and of what makes two violations the same class are not settled; the fixtures pin those cases by instance rather than by definition, and they are the authority until the prose exists.

## The game axis

Every position, move, archive and session belongs to exactly one game, and the game is never inferred from a position: the ruleset is not a property of the board. The identifier is `rules_id`:

| `rules_id` | board | palace | river | pieces per side |
|---|---|---|---|---|
| `minixiangqi` | 7 files × 7 ranks | `c1`–`e3`, `c5`–`e7` | none | general, 2 chariots, 2 horses, 2 cannons, 5 soldiers |
| `xiangqi` | 9 files × 10 ranks | `d1`–`f3`, `d8`–`f10` | between ranks 5 and 6 | general, 2 chariots, 2 horses, 2 elephants, 2 advisors, 2 cannons, 5 soldiers |

Mini Xiangqi has no river, no elephants and no advisors. Xiangqi has them all.

## Normative sources

For **Mini Xiangqi** the public rules source is [PyChess Mini Xiangqi rules](https://www.pychess.org/variants/minixiangqi):

- Retrieved: `2026-07-26T11:58:51-0700`
- SHA-256 of the retrieved page: `a79b663618033c2a8e4db897b51499d6409ade0543520ee950c9c768eae92077`

The page's starting-position diagram is an external image and its text does not name the first mover. Both facts come instead from the source's own implementation, `pychess-variants` at commit `961fd6dd60ce76d3baced1a77df49ca58edcb315` — `client/variants.ts:1434` for the starting FEN and `client/variants.ts:1439` for Red moving first — which matches the built-in Fairy-Stockfish `minixiangqi` variant byte for byte.

For **Xiangqi** the geometry, piece set, palace, river and starting position are the standard game's and are stated here directly.

Neither a Fairy-Stockfish search score nor an engine-specific optional result changes a user-visible rule.

## Starting positions, coordinates, and notation

- The starting position of Mini Xiangqi is FEN `rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1`, and of Xiangqi `rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1`. Each game has exactly one, and it is frozen. Which further positions a game may begin from is the setup-legality section's question below.
- Files are lettered `a` upward from Red's left and ranks numbered `1` upward from Red's back rank: `a1`–`g7` in Mini Xiangqi and `a1`–`i10` in Xiangqi. A FEN piece-placement field lists the highest rank first and rank 1 last.
- `w` is Red: uppercase pieces, moves first. `b` is Black: lowercase pieces.
- A square is a file letter followed by a rank written in decimal with no leading zero — two characters in Mini Xiangqi, and two or three in Xiangqi, where `a10` is a square and `a010` is not. The canonical machine notation for a move is the origin square followed by the destination square, so a move is four characters in Mini Xiangqi and four to six in Xiangqi, the longest being a move between two rank-10 squares, such as `a10b10`. No move suffix exists in either game: there is no promotion, castling, en passant, drop, or gating. A soldier crossing the river changes how it moves, and the player never chooses it, so it is not spelled. Parsing needs no lookahead, because a file letter is never a digit: the digit run after a file ends exactly where the next square begins, and `a1a10` is `a1` then `a10` and can be read no other way.
- This notation is canonical for fixtures, game archives, and the shared core interface. The notation shown to the user is a separate matter and never changes what is stored or exchanged.
- Beside the board moves, each game's canonical move-text grammar holds one turn action: `claim`, the word alone. It is a turn action of the side to move, lawful exactly when the claimable neutral repetition stands, and it ends the game as that claimed draw with reason `threefold-repetition`. It moves no piece. It exists for game exchange between implementations and lives only there: no archive spells it — an archive's terminal information records the claimed draw itself — and no fixture carries it.
- A position record is a 6-field FEN. The third and fourth fields are always `-`. The sixth field is the fullmove number, starting at 1 and incrementing after each Black move. The fifth field counts plies since the last capture; what it drives differs by game and is stated under the move-count rule below.
- Two position records denote the same position exactly when piece placement and side to move are equal; the two counters are ignored.

**Serialized vocabulary and display copy differ.** The identifiers frozen here and in the fixtures are technical vocabulary and never change to follow a display string: the FEN letter `k`, the word *square* in this document's technical prose, and reason identifiers such as `stalemate` mean what this document says they mean, in every archive, fixture, and core interface. The fixtures' own titles and rationales are frozen and keep the vocabulary they were written with, including *king* where they say it. What the user reads comes from the shipped string catalogs: English says *General* for the piece, *point* for an intersection of the board, and the approved reason words. Neither vocabulary is a translation of the other, and neither may be edited to make them match.

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

The complete result taxonomy, including user-ended games and imported records, is in [game-data.md](game-data.md); the fixture result identifiers below are the rule-derived part of it.

## Setup legality

**Xiangqi defines a setup-legality predicate**, and a Xiangqi game may begin from any position the predicate accepts. **Mini Xiangqi defines none**, so a Mini Xiangqi game begins from its frozen starting position and from no other.

A Xiangqi position is one to set up in when all of the following hold. The clauses are listed in the order a violation is reported in: a position breaking more than one clause is refused under the first, and among the point clauses under the first offending point, walking the board from `a1` upward. The count clause follows the point clauses because it is about a side and names no point, and the check clause is last.

- **The palace.** Every general stands on one of the nine points of its own palace, `d1`–`f3` for Red and `d8`–`f10` for Black. Every advisor stands on one of the five points of its own palace that an advisor reaches — the four corners and the centre: `d1`, `f1`, `e2`, `d3` and `f3` for Red, and `d8`, `f8`, `e9`, `d10` and `f10` for Black.
- **The elephants' side.** Every elephant stands on one of the seven points its own side of the river offers it: `a3`, `c1`, `c5`, `e3`, `g1`, `g5` and `i3` for Red, and `a8`, `c6`, `c10`, `e8`, `g6`, `g10` and `i8` for Black.
- **The soldiers' points.** No soldier stands behind its own starting soldier rank: a Red soldier on rank 4 or above, a Black soldier on rank 7 or below. And no soldier still on its own side of the river stands off the five files its side's soldiers start on, `a`, `c`, `e`, `g` and `i`. Across the river every file is one it may stand on.
- **Piece counts.** Exactly one general per side, and per side at most two advisors, two elephants, two horses, two chariots, two cannons, and five soldiers.
- **The side not to move is not in check.** The two generals facing each other on an otherwise empty file is such a check, so a position that stands them so is refused by this clause. The side **to** move may stand in check, and answering it is that side's first move.

The predicate reads piece placement and the side to move, which is the whole of what a position record denotes. It answers for a position that is still missing a general: that absence is the count clause's answer about that side and not a refusal to answer about the position. Whether a position is worth playing is not its question and neither is whether it is already decided: a position offering the side to move no legal move is a legal setup, and no game may begin from it.

Setup legality is pinned by conformance fixtures of an area of its own, `xq-set-NNN`, each stating a position and either the clause that refuses it or its acceptance.

## The move-count rule

This is one of the rules that differ.

- **Mini Xiangqi has no automatic move-count draw.** The fifth FEN field drives no rule there, and a soldier move does not reset it.
- **Xiangqi draws a game that has run fifty moves — one hundred plies — without a capture.** Only a capture resets the count: no piece's own move resets it, soldiers included. The draw is automatic rather than claim-gated, and its reason identifier is `fifty-move-rule`.

## Repetition, perpetual check, and perpetual chase

Stated once; both games adjudicate identically except for the one chase-target difference marked below.

- The repetition threshold is three occurrences of the same position, counting the first time the position stands on the board. The repeated position need not be the game's initial position.
- Repetition and violation state derive from the game's complete move history. A bare position carries no prior occurrences, and a position set up to be played from is bare.
- On the third neutral occurrence, the position becomes eligible to be ruled a draw. In both human-versus-AI play and Free Play, this eligibility does not automatically commit a terminal result: the user may continue or claim the draw.
- A unilateral perpetual violation becomes terminal automatically when a position first stands on the board for the third time with the violation sustained across its occurrences: the violating side loses, as a natural result presented through the standard result flow. Only neutral repetition is claim-gated.
- A unilateral perpetual-check violation is a loss for the checking side.
- A unilateral perpetual chase of the same unprotected target is a loss for the chasing side.
- **Adjudication does not depend on which side happens to be to move when the third occurrence lands.**
- Generals take no part in the perpetual-chase rule, as targets or as chasing pieces: a general may not be the chased piece, and a general's move never creates a chase. Its move may still open another piece's line or horse leg, and the resulting threat is a chase by that other piece. Generals protect normally.
- **Soldiers are another difference between the games.** In **Mini Xiangqi** a soldier is excluded exactly as a general is: it may not be a chase target, and its move never creates a chase. In **Xiangqi** a soldier that has crossed the river is an ordinary chase target; one that has not is excluded. `mx-chs-003` and `xq-chs-002` pin the difference.
- A piece of the same type as the chasing piece is not a chase target, unless that piece is pinned and therefore cannot answer the attack.
- Independently of protection, an attack by a horse or a cannon on a chariot is always a chase. No other value relation overrides protection here: the chariot is the only piece these rules treat as strictly stronger than the horse and the cannon, which are treated as equals. This clause is adopted AXF practice that the source does not literally state.
- When one side perpetually checks and the other perpetually chases, the checking side is the side required to stop and loses if the violation is completed. Check outranks chase unconditionally: a side that is perpetually checking loses even if it is simultaneously chasing, and even if the other side is also chasing. This orders check against chase; it does not override the mutual rule below, so two sides both perpetually checking remain a draw.
- When both sides commit the same class of perpetual violation, the result is a draw. Its reason identifiers are `mutual-perpetual-check` and `mutual-perpetual-chase`, so the outcome is serializable distinctly from a claimed repetition draw; their fixtures are the `mx-mix-*` ones carrying a `draw` state.

### Accepted interpretations

The source does not settle these questions. Each is an interpretation rather than a reading of the source, and they all apply to both games.

- **A side alternating check and chase (一将一捉) commits neither violation.** Each violation class is a single behaviour sustained across the three occurrences; a side that checks in one part of the cycle and chases in another sustains neither on its own across the counted occurrences, so no single class persists, so the position resolves as a neutral claimable repetition. This is the interpretation most likely to be wrong: competition practice commonly forbids the alternation, and the source does not address it.
- **A chase renews when the chasing piece attacks the target from the square it now occupies and did not attack it from that square before the move.** A chasing piece that steps **away** from its target and still attacks it from the new square therefore renews the chase, while one that merely advances **toward** the target along a line on which its attack already stood does not.
- **A chase whose target's only defender is a general is adjudicated on the flying-generals condition alone.** Where a general could not in fact recapture for some other reason, the target is nonetheless treated as defended, so the sequence degrades to a neutral claimable repetition rather than a loss.

Where the source is silent, the chase rules follow AXF practice; AXF does not replace the source as the rules authority.

## Rules interpretation version

The rules interpretation carries an integer version, `rules_version`. It is `1` for both games, as it is for every game the app carries. It increments only when an interpretation change alters a legal move or a user-visible result — never for prose clarification, fixture additions that pin existing behavior, engine or fork revisions, or search configuration. Game archives record `rules_id` and this version, per [game-data.md](game-data.md).

**[jieqi-rules.md](jieqi-rules.md) adopts the repetition, perpetual-check and perpetual-chase clauses above by reference.** An amendment to those clauses amends Jieqi's rules as well, the two games adjudicate identically, and their `rules_version` move together.

## Runtime rules authority

Legal moves, check state, results, repetition, claim eligibility, and perpetual violations are adjudicated offline on every platform. Every such question is asked of a named game; none is answered from a position alone. Adjudication is deterministic over game, position and history, and the conformance fixtures — not engine agreement — are its authority. Search scores and search-only results never commit a user-visible outcome.

## Conformance fixtures

The executable fixtures live in [`fixtures/rules/`](../fixtures/rules/); that directory's README defines the schema, the identifier scheme, and the immutability rules. Identifiers are `mx-<area>-NNN` for Mini Xiangqi and `xq-<area>-NNN` for Xiangqi, and each fixture names its own game in a `variant` member that the runner dispatches on. Every fixture carries a stable identifier, an initial position, a complete move history, the expected resulting position and check state, the expected game state, and a concise rule rationale; movement and ending fixtures additionally assert exact legal-move sets, rejected moves, or applied single-move probes. A setup fixture is the one shape outside that: it carries a position and either the clause that refuses it or its acceptance, and no move line. Fixture game states use the state identifiers `ongoing`, `claimable-draw`, `red-wins`, `black-wins`, and `draw` with the reason identifiers `checkmate`, `stalemate`, `threefold-repetition`, `perpetual-check`, `perpetual-chase`, and `fifty-move-rule`, and they name results by rule outcome — the violating side loses — never by the side to move at detection. The reason identifiers `mutual-perpetual-check` and `mutual-perpetual-chase` belong to the mutual-violation fixtures, which are the `mx-mix-*` ones carrying a `draw` state.

The set for these two games is what that directory holds under the `mx-` and `xq-` prefixes. Jieqi's `jq-` fixtures share the directory and belong to [jieqi-rules.md](jieqi-rules.md).

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

For Xiangqi, these pin what the 9-by-10 board adds and what it changes:

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

The rest are `xq-set-*`, the setup-legality area: one refusal per clause of the predicate above; the exactness of the point clauses — an advisor refused on a palace edge midpoint, inside the palace and off the five points it reaches, and a soldier refused on its own half for standing off the files it starts on; the answer for a board still missing a general — the count clause naming the side, and the same board with a misplaced advisor, where the point-anchored violation is what is reported; accepted positions — a composed scene, a side-to-move-in-check position, and the same off-file soldier across the river, which bounds the file clause at the river; and positions of no board at all — a rank spelling eight points and a side-to-move field that is neither `w` nor `b`, which the predicate's own reading of the frozen encoding refuses before any clause is reached. `mx-set-001` and `mx-set-002` are the pair that says Mini Xiangqi defines no predicate — its frozen start accepted, and any other position refused as not that start.
