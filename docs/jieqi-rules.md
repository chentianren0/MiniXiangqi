# Jieqi rules

These are the rules of legal play, of what each player is entitled to know, and of user-visible results in **Jieqi** (揭棋; in Vietnamese *cờ úp*), the hidden-identity xiangqi, with the identifiers that connect them to the conformance fixtures.

## The game axis

Every position, move, archive and session belongs to exactly one game, and the identifier is `rules_id`. Jieqi's value is:

| `rules_id` | board | palace | river | pieces per side |
|---|---|---|---|---|
| `jieqi` | 9 files × 10 ranks | `d1`–`f3`, `d8`–`f10` | between ranks 5 and 6 | general, 2 chariots, 2 horses, 2 elephants, 2 advisors, 2 cannons, 5 soldiers |

Jieqi's board, palaces, river, piece set and start squares are Xiangqi's exactly. Once every piece on the board has been revealed, a jieqi position is written the way a xiangqi position is written, and the two games give that one position different legal moves, because the advisor and the elephant are free here. Nothing about a position says which game is being played: the identifier is the whole of the answer.

## Normative sources

The **Chinese Wikipedia article 揭棋**, in its wikitext form, is the source for the deal, for hidden movement by the square's role, for the mandatory flip, for the freed revealed advisor and elephant, for the concealment of a captured hidden piece, and for the result taxonomy:

- URL: `https://zh.wikipedia.org/wiki/揭棋?action=raw`
- Retrieved: `2026-08-16T17:48:48Z`
- SHA-256 of the retrieved page: `ef6d6139e15d2e1636cd0ad7a1a86c0c8b991118f594f08df20ed0fa6a3bf524`

**Tencent's 天天象棋 揭棋玩法说明** is the source Wikipedia itself cites for those rules, and the source for the no-capture draw:

- URL: `https://image.qqchess.qq.com/test_160324/activity/html/jieqiguize.html`
- Retrieved: `2026-08-16T17:56:01Z`
- SHA-256 of the retrieved page: `70559e7975ccbe9f169dc3efae94f350bde92a7bccc6a00027281a5d33981b60`

**Club Xiangqi's Mystery Chinese Chess Rules** states the same game in English and is the source for revealed movement piece by piece, the soldier included:

- URL: `https://www.clubxiangqi.com/uprules.php`
- Retrieved: `2026-08-16T17:49:46Z`
- SHA-256 of the retrieved page: `88dc95094477f8a7eb646f478c6c45463206297955a793ca776ba2efee8c03df`

The **Pikafish `jieqi` branch** is the game's de-facto engine and the source for the no-capture rule's count, which it keeps in plies and resets on captures alone. The file is `src/position.cpp` at commit `9b963f727983a1d9308e0dca48b39c802b8e75a2`:

- Origin: `https://github.com/official-pikafish/Pikafish.git`, branch `jieqi`
- Retrieved: `2026-08-16T17:50:20Z`
- SHA-256 of the retrieved file: `461978fc73548847efaaa7a763935e407e5f335733c476ffe1804e09b765282f`

The geometry, the piece set, the palace, the river and the start squares are the standard game's and are stated here directly. The engine is cited for one thing only — how the no-capture rule is counted and what resets it, which the public statements leave unsaid — and for nothing else: neither a search score nor an engine-specific optional result changes a user-visible rule.

## The dealt start

Each side's fifteen non-general pieces are dealt face down onto that side's fifteen non-general start squares. The two generals stand face up on `e1` and `e10`, the only pieces that ever start face up. Red moves first.

The deal is uniform: every distinct assignment of a side's fifteen pieces to its fifteen squares is equally likely, and the two sides are dealt independently.

**Neither player knows any hidden identity, their own included.** No player deals, and no player is shown what was dealt.

A jieqi game begins from a dealt start and from no other position. Jieqi therefore defines no setup-legality predicate.

## Positions, coordinates, and notation

- Files are lettered `a` upward from Red's left and ranks numbered `1` upward from Red's back rank, `a1`–`i10`. A square is a file letter followed by a rank written in decimal with no leading zero, so `a10` is a square and `a010` is not. A FEN piece-placement field lists the highest rank first and rank 1 last. `w` is Red: uppercase pieces, moves first. `b` is Black: lowercase pieces.
- The canonical coordinate form of a move is the origin square followed by the destination square, four to six characters, the longest being a move between two rank-10 squares, such as `a10b10`. Parsing needs no lookahead, because a file letter is never a digit.
- **This coordinate notation is canonical for fixtures, game archives, and the shared core interface.** It carries no reveal and needs none: the deal recorded beside a game's moves makes every reveal derivable, so the coordinates and the deal together are a game's complete record. The notation shown to a human reader is a separate matter and never changes what is stored or exchanged.
- Beside the board moves, the canonical move-text grammar holds one turn action: `claim`, the word alone. It is a turn action of the side to move, lawful exactly when the claimable neutral repetition stands, and it ends the game as that claimed draw with reason `threefold-repetition`. It moves no piece and exists for game exchange between implementations.
- A position record is a 6-field FEN. The third and fourth fields are always `-`. The sixth field is the fullmove number, starting at 1 and incrementing after each Black move. The fifth field counts plies since the last capture and drives the no-capture rule below.
- **A face-down piece is written as its identity letter followed by `~`.** That is the whole of the difference from a xiangqi position record: the letter says what the piece is and the mark says the players do not know it. Red's back rank in one deal reads `P~N~P~R~KC~P~A~B~` — a face-down soldier standing on a chariot's start square, a face-down chariot on an advisor's, and the general face up between them.
- Two position records denote the same position exactly when piece placement — including which pieces are face down — and side to move are equal; the two counters are ignored.
- **A position record is the objective position, and it holds every hidden identity.** It is never what a player is shown. What each player may know is the disclosure section's subject.

## Movement

### A hidden piece

- A hidden piece moves and captures exactly as the xiangqi piece that starts on the square it stands on. A hidden piece has never moved, so that square is always its own start square, and the role it plays is the role that square gives it whatever it turns out to be.
- **On completing that move it flips face up, always** — whether or not it captured, and with no choice in the matter. From then on it is a revealed piece and moves as itself.
- A hidden piece on an advisor's start square is palace-bound like the advisor whose square it is, so its one legal destination is the palace centre, `e2` for Red and `e9` for Black.
- A hidden piece on an elephant's start square needs no rule about the river: an elephant's step from its own start square lands on its own side of the board, so the first move cannot cross.
- A hidden piece on a soldier's start square moves one square forward and no other way, because that is what a soldier on its own side of the river may do.
- A hidden piece that is captured never flips. It leaves the board face down.

### A revealed piece

A revealed piece moves as xiangqi's piece of that kind, with the advisor and the elephant freed:

- A general moves one square orthogonally inside its palace, and the two generals may not face each other on an otherwise empty file; they attack each other through that file. The generals are unchanged from xiangqi in every respect.
- An advisor moves one square diagonally, anywhere on the board. It is not confined to the palace.
- An elephant moves exactly two squares diagonally and is blocked when the square between is occupied. It may cross the river. The blocking eye is kept; only the confinement is lifted.
- A horse moves one square orthogonally and then one diagonally outward, and is blocked when that first orthogonal square is occupied, by any piece. What blocks it is the intervening square, never the destination.
- A chariot moves any number of unobstructed squares orthogonally.
- A cannon moves like a chariot when not capturing, and a cannon capture requires exactly one intervening screen.
- **A soldier moves by the side of the river it stands on**, not by any history of crossing: one square forward on its own side, and one square forward or sideways past the river. It never moves backward. A soldier may legitimately stand where no xiangqi soldier could — behind its own soldier rank, or off the five files soldiers start on — because a hidden piece is revealed wherever its first move ends, and from such a square it moves forward like any other soldier on its own side.

### Every fact that decides play is public

How a hidden piece moves is public: its square says it, and both players see the square. What a piece flips up as becomes public the instant it flips. So the position conceals exactly this: the identities still face down, and the identity of a hidden piece that has been captured. Neither of them decides a legal move, a check, or a result. Concealment is a property of the position and never of what a player remembers.

**A move's legality never depends on what the moving piece flips up as.** The piece occupies its destination whatever it turns out to be, and occupancy is the whole of what blocking, screening and the flying-general rule read. Both players therefore hold the same legal-move set, the same check state and the same adjudication at every moment of the game.

## Capture and disclosure

- **Capturing a hidden piece discloses its identity to the capturer alone.** Its owner learns only that a hidden piece was lost.
- A captured revealed piece is public to both players, as it was on the board.
- **When the game ends, every hidden identity is disclosed to both players** — by any ending, a resignation and an agreed draw included.
- **An accepted retraction returns the position's concealment, not the players' knowledge.** A piece the retracted moves revealed stands face down again and moves again by its square's role, and an identity a capture disclosed stays disclosed.

## Endings

- A position with no legal move is a loss for the player who cannot move. Stalemate is not a draw.
- Check, legal check evasion, and checkmate follow the movement and general-safety rules above.
- **A game that has run forty moves — eighty plies — without a capture is drawn.** Only a capture resets the count: no piece's own move resets it, and a reveal does not either. The draw is automatic rather than claim-gated, and its reason identifier is `forty-move-rule`.
- **Repetition, perpetual check and perpetual chase are adjudicated exactly as [xiangqi-rules.md](xiangqi-rules.md) adjudicates them** for Xiangqi — every clause of it, its accepted interpretations included — with the violating side losing, mutual violations drawn, and neutral threefold repetition claimable at the third occurrence.

An amendment to those clauses amends Jieqi's rules as well, and the two games' `rules_version` move together.

These follow from jieqi's own positions, and they are how those clauses are read here:

- **Every clause that names a piece type reads a hidden piece as the type its square gives it.** A hidden piece on a soldier's start square is a soldier for the chase rule's purposes, one on a chariot's start square is a chariot, and so on. Where a clause is phrased for a piece that has crossed the river, jieqi reads it by the side of the river the piece stands on.
- **No repeating cycle can contain a reveal.** A hidden piece stands only on its own start square and flips the moment it moves, so along a game's move history — which is what repetition is judged over — the set of face-down squares only ever shrinks. Two positions with equal placement therefore have equal face-down sets, and no reveal and no capture of a hidden piece lies between them. Every repetition, and so every perpetual violation, lies wholly inside one stretch of play between two reveals.

## Accepted interpretations

The sources do not settle these questions. Each is an interpretation rather than a reading of a source.

- **A soldier's sideways step is read by the side of the river it stands on, not by whether it crossed.** The two readings never differ in Xiangqi, where a soldier reaches the far side only by crossing; in jieqi a soldier revealed past the river has never crossed it.
- **Capturing a hidden piece discloses its identity to the capturer.** The sources say only that the owner of a captured hidden piece may not turn it over, and that the capturer sets it down face down; none says what the capturer may see.

## Rules interpretation version

The rules interpretation carries an integer version, `rules_version`. It is `1` for Jieqi, as it is for every game the app carries. It increments only when an interpretation change alters a legal move or a user-visible result — never for prose clarification, fixture additions that pin existing behavior, engine revisions, or search configuration.

## Runtime rules authority

Legal moves, check state, results, repetition, claim eligibility, perpetual violations, and what each reveal turns up are adjudicated offline on every platform. Every such question is asked of a named game; none is answered from a position alone. Adjudication holds the objective position, every hidden identity included; what a player may be shown is decided by the disclosure rules above.

Adjudication is deterministic over game, position and history, and the fixtures below — not any engine's agreement — are its authority. Search scores and search-only results never commit a user-visible outcome.

## Conformance fixtures

The executable fixtures live in [`fixtures/rules/`](../fixtures/rules/); that directory's README defines the schema, the identifier scheme, and the immutability rules, and Jieqi's fixtures are held to all of them. Identifiers are `jq-<area>-NNN`, the areas are the shared ones, and each fixture names `jieqi` in its `variant` member, which is what the runner dispatches on.

The set pins at a minimum:

- hidden movement by the square's role, one fixture per role, including a hidden piece that is not what its square says it is;
- the palace-bound hidden advisor, whose only legal destination is the palace centre;
- the mandatory flip: the position after a hidden piece's move carries that piece face up, capture or no capture;
- the freed revealed advisor and the freed revealed elephant, out of the palace and across the river, with the elephant's blocked eye and the horse's blocked leg intact beside them;
- the revealed soldier: forward on its own side, forward or sideways past the river, never backward, and standing legally behind its own soldier rank;
- checkmate, and stalemate as a loss for the side to move;
- the no-capture draw at the ply it lands and not two plies earlier, and a reveal inside that stretch failing to reset it;
- the adopted repetition and chase clauses, pinned for this game rather than left to the corpus of the games they are adopted from: a unilateral chase, the mutual arms, and a chase renewed by an attacker other than the one that was attacking before;
- adjudication across a reveal: a cycle that would repeat but for the reveal inside it is no repetition, and no violation attaches to it;
- a dealt start accepted, and a shape that is not a dealt start refused.

**The fixtures do not pin disclosure.** A fixture asserts positions, legality, check states and results, and not one of those changes with who is looking. The deal's uniformity is not pinned either: it is a property of a distribution rather than of a position, and no single fixture can assert it.
