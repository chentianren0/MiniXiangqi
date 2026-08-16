# The BoardGame Protocol, version 2

This document defines a wire contract by which two devices play one board game, and it is the whole of protocol version **2** — the version a peer announces as `hello`'s `protocol` 2. It defines no game's rules. Everything an implementing application builds around it — the transports that carry it, screens, discovery surfaces, permission handling, and whatever devices keep of finished games — is outside it. It is self-contained: nothing here is read against another document. Version 1 is a different protocol, described by its own document, and this one neither extends nor refers to it.

> **Status: binding.**

**A version-2 peer does not play with a version-1 peer.** `hello` announces one version and the check refuses anything else, so two devices whose versions differ share no game at all — not even a game both carry. Both devices update. There is no degradation and no negotiation, here or in any later version.

## The games it carries

The protocol carries games with two players, alternating turns, and deterministic rules — a pass, where a game has one, is a turn. A game may carry hidden information, under the shared-deal model below. The result must be decided by the move sequence and, where the game has one, the deal.

A game is named by a `rules_id`: a string of lowercase letters, digits, and hyphens, such as `minixiangqi` or `jieqi`. A `rules_id` names the complete game: its rules, its initial position, its move-text grammar, its result function, whether it is a hidden-information game, and the mapping from the two movers to whatever colours or stones the game calls them. A new game is a new `rules_id` and a game module in the implementing application — never a protocol change.

Two peers carrying one `rules_id` therefore agree, without saying so, on the facts about a game that are the protocol's own business: its move-text grammar, whether its session opens with the deal handshake, and what it draws from the deal stream. A **hidden-information game** is one whose start is dealt and whose play discloses that deal in pieces; its session opens with the handshake. Every other game's does not, and plays exactly as it would with the handshake absent.

`jieqi` is a hidden-information game, and it is the one this document names:

| `rules_id` | board | move text on the wire | deal |
|---|---|---|---|
| `jieqi` | 9 files × 10 ranks | one square of `a1`–`i10` followed by another, or the turn action `claim` | two permutations of fifteen, derived below |

**No identity travels.** A `move`'s text is the game's own move text and never names a hidden identity, in `jieqi` as in every other game; what a move revealed is not on the wire, and each end derives it from the deal it holds.

## The model

Two peers hold one reliable, ordered byte stream, whose authenticity and privacy belong to whatever carries it. Within each direction the stream preserves order, but a message from each side can always cross a message from the other. Neither peer is distinguished; the only asymmetry a session ever has is who proposed it, and the deal handshake is where that asymmetry is put to use.

What the protocol asks of a transport is only this: whole messages, rather than bytes a peer must frame for itself; a stable peer identity named behind every connection, which sessions and resume rely on, and which the transport names rather than anything here proves; exactly one such identity per peer — the same across a relaunch, the same behind every connection to that peer whatever carries it, and unchanged for as long as a session with that peer stands; and room for more than one connection to stand between one pair of peers at once.

**The shared deal.** A hidden-information game's start is dealt, and from the session's first ply both devices hold the entire deal. Each shows its player only what the game's rules allow that player to know. The deal is never sent: it is derived on both ends from the handshake's two contributions, and no message at any point of a session names a hidden identity. Every reveal is therefore a derivation rather than a disclosure over the wire, and the game's result stays a function of the move sequence and the deal.

**What that buys, and what it does not.** Within a completed handshake neither peer can choose or steer the deal: the commitment binds the dealer before the nonce arrives, and the derivation is fixed. A finished record is verifiable by anyone holding the commitment, the nonce and the seed. What the handshake does not do is oblige a peer to complete it — a handshake abandoned before the seed travels lets a modified dealer resample by reproposing — and it does not hide the deal from a device that holds it: a modified client can show its player every hidden identity from the first ply. The protocol's guarantees are about completed exchanges rather than about a peer's obedience; it has no cryptography of its own beyond the commitment, and a friendly game between two people in one room is not the place for more.

Every message is one JSON object with exactly one member: the message's name, whose value is an object holding its fields —

```json
{"move": {"session": "0b34…", "index": 7, "move": "b1b3"}}
```

`protocol` is an integer. `session` is an opaque string, minted by the proposer as a UUID, echoed verbatim, and compared byte-wise. `index`, `at`, `count`, `keep`, and `undos` are non-negative integers. `commit`, `nonce`, `seed`, and `deal_digest` are strings of exactly sixty-four lowercase hexadecimal digits — thirty-two bytes, most significant first — and any other string is malformed. A message carries exactly its named fields: `end` and `deal_digest` are the only two that may be omitted, each under the rule stated for it, and every other extra or missing member is malformed.

## Session states

Between one pair of peers at most one session is proposed, dealing or active at a time — save the crossing instant named under Proposing — and one finished session may linger in **ended** alongside it. Every message's validity is decided by its receiver at arrival from the state it holds:

- **proposed** — a `propose` is unanswered. A proposal is scoped to the connection it travelled on: `accept` and `decline` are effective only there, and an unanswered proposal dies with its connection.
- **dealing** — a hidden-information game's proposal was accepted and its deal handshake is in flight. No ply exists, none may be sent, and the only messages with a lawful meaning are the handshake's own. A **dealing** session is bound to the connection its `propose` travelled on and dies with it: it holds nothing worth reconciling, it is never resumed, and the pair simply proposes again and deals again.
- **active** — the proposal was accepted and, for a hidden-information game, this end has completed the deal handshake: the dealer by sending `deal_seed`, the other end by verifying it. Play is on, and the session is bound to the connection its `propose` travelled on.
- **ended** — the game has a result. An ended session still answers `resume`; it applies an arriving valid in-sequence `move` and merges arriving terminals by the precedence rule; every other message arriving for it is discarded, never a violation. A new proposal retires it.
- **void** — the session was destroyed without a result. A device forgets a void session.

## Messages

| Message | Fields | Meaning |
|---|---|---|
| `hello` | `protocol` | Opens a connection, both directions, before anything else. |
| `propose` | `session`, `rules_id`, `rules_version`, `proposer_moves` | Offer a game. |
| `accept` | `session` | The proposal is accepted. |
| `decline` | `session`, `reason` | A proposal or a resume is refused. |
| `deal_commit` | `session`, `commit` | The dealer binds its seed before it can know the other contribution. |
| `deal_nonce` | `session`, `nonce` | The other peer contributes its half. |
| `deal_seed` | `session`, `seed` | The dealer opens its commitment; both ends derive the deal. |
| `move` | `session`, `index`, `move` | One ply. |
| `offer_draw` | `session`, `at` | Offer to end the game as a draw. |
| `accept_draw` | `session` | The game ends as agreed. |
| `request_undo` | `session`, `at`, `keep` | Ask to retract every ply beyond the first `keep`. |
| `accept_undo` | `session` | The retraction happens. |
| `resign` | `session` | The sender loses. |
| `resume` | `session`, `undos`, `count`, `keep`, `end`, `deal_digest` | Continue an interrupted session. |

`reason` is one of `declined`, `unknown_game`, `rules_mismatch`, `busy`, `unknown_session`, `deal_mismatch`. A version-2 peer treats any other message name as a violation.

## Proposing a game

The proposer sends `propose`. The receiver accepts only when it implements `rules_id` with a `rules_version` exactly equal — an opaque string, compared byte-wise — and its player consents; otherwise it declines with the fitting reason. `proposer_moves` is `first` or `second`: which mover the proposer takes.

**A proposal naming a `rules_id` the receiver does not carry is declined, never a violation.** The receiver answers `decline` with `unknown_game` through the ordinary decline flow; the connection stands and the pair may propose again at once. That is this version's definition of the case and not a courtesy it extends: a game this document never names is still a game two version-2 peers play the moment both carry it, so **a later game is a new `rules_id` and never a version 3**.

A peer proposes only when its own copy of the pair's lingering session, if any, is settled: unsettled, it settles first or learns from that exchange that the session is void. An arriving `propose` retires the receiver's ended copy whatever its settledness. `busy` answers a `propose` that arrives while a **dealing** or **active** session exists with that peer. A `propose` that arrives while the receiver's own proposal is outstanding with that peer — on any connection — is the crossing case: the proposal whose session identifier sorts lower byte-wise survives, and the other is void without an answer.

On `accept`, a perfect-information game's session becomes **active** and play begins. A hidden-information game's becomes **dealing**, and the proposer sends `deal_commit` at once.

## The deal handshake

**The proposer is the dealer.** Three messages, in this order and no other, on the session's own connection:

1. The dealer draws a `seed` of thirty-two bytes from a cryptographically secure random source and sends `deal_commit` with `commit`, the SHA-256 of those bytes. A thirty-two-byte seed carries enough entropy that the hash discloses nothing about it and binds it completely, which is why the commitment needs no separate blinding value.
2. The other peer draws a `nonce` of thirty-two bytes from a cryptographically secure random source and sends `deal_nonce`.
3. The dealer sends `deal_seed` with the seed itself. The receiver hashes it and compares with the `commit` it holds; **a mismatch is a protocol violation**, which is the one thing the commitment exists to catch.

Within a completed handshake neither side can choose or steer the deal, because each fixes its contribution before it can know the other's: the dealer commits without having seen the nonce, and the nonce is drawn against a hash that discloses nothing. One honest, well-drawn contribution then makes the deal uniform. A handshake abandoned before the seed travels is the other case — the dealer holds both contributions by then and can decline to complete it and propose again, which is a resample — and it stands with the modified-client caveat above rather than against it: what is guaranteed here is the completed exchange, never a peer's obedience.

The dealer's session becomes **active** when it has sent `deal_seed`; the other end's when `deal_seed` arrives and verifies. The first ply may follow immediately. Until then no `move` exists and none is sent.

Every departure is a protocol violation: a handshake message for a perfect-information game's session, a `deal_commit` or `deal_seed` from the peer that is not the dealer, a `deal_nonce` from the dealer, any of the three arriving out of the stated order or a second time, a malformed value, and any other message arriving for a session in **dealing**.

### Deriving the deal

Both ends compute the deal from the seed and the nonce alone, and must compute the same one:

- **The key** is `SHA-256(seed ‖ nonce)` over the two thirty-two-byte values, seed first.
- **The stream** is the concatenation, for counter 0, 1, 2, … in turn, of `SHA-256(key ‖ counter)`, each counter written as eight bytes most significant first. It is read from the front, byte by byte as values are drawn, and never rewound.
- **A value below `n`**, for `n` from 2 to 2³²: take the next four bytes of the stream, most significant first, as an unsigned 32-bit integer `v`; with `limit` the largest multiple of `n` that is at most 2³², discard `v` and take another four bytes whenever `v` is `limit` or above; otherwise the value is `v mod n`. The discarding is what makes the value uniform — `v mod n` alone favours the low values whenever `n` does not divide 2³² — and it is part of the derivation rather than an implementation's choice.
- **A permutation** of `m` items numbered 0 to `m − 1`, for `m` of 2 or more: for `i` from `m − 1` down to 1, draw a value `j` below `i + 1` and exchange the items at `i` and `j`.
- **A game's deal** is one or more such permutations, drawn one after another from the one stream, in the order that game fixes. A game this document does not name fixes that order in its own module, which both peers carry.

`jieqi`'s deal is two permutations of fifteen items, Red's drawn first and Black's second. Each permutes that side's fifteen non-general pieces, held in the order chariot, chariot, horse, horse, elephant, elephant, advisor, advisor, cannon, cannon, soldier, soldier, soldier, soldier, soldier. The permuted list is then laid item by item onto that side's fifteen non-general start squares, first item onto first square:

- Red: `a1`, `b1`, `c1`, `d1`, `f1`, `g1`, `h1`, `i1`, `b3`, `h3`, `a4`, `c4`, `e4`, `g4`, `i4`
- Black: `a7`, `c7`, `e7`, `g7`, `i7`, `b8`, `h8`, `a10`, `b10`, `c10`, `d10`, `f10`, `g10`, `h10`, `i10`

The two generals are not dealt. Deriving a deal is protocol rather than rules because both ends must compute one identical deal from what crossed the wire; what the deal then means for play is the game's.

**The deal digest** is `SHA-256` over the deal itself: for each permutation the game drew, in the order it drew them, the item number standing at index 0, then the one at index 1, and so on, one byte each. For `jieqi` that is thirty bytes, Red's fifteen then Black's fifteen. No permutation this version derives runs past 256 items, so one byte an item is the whole encoding. The digest is what a resumed session compares, because it binds everything a deal comes from — the seed, the nonce, and the derivation itself — where the commitment binds the seed alone.

Kept beside a finished record, the commitment, the nonce and the seed make the whole game checkable by anyone: hash the seed against the commitment, derive the deal, replay the moves.

## Playing

Plies are numbered from zero; a session's `count` is the number of plies it holds. `proposer_moves` and index parity decide whose turn every ply is. A peer sends `move` only on its own turn and only with `index` equal to its `count`; `move`'s text is a move in the game's own grammar, and the receiver validates it with its own rules, against the position it derives from the deal it holds and the plies it holds. A `move` that lands voids the standing offer or request, on both sides.

## Offers and requests

Only the off-turn peer opens a negotiation, and at most one stands at a time. `offer_draw` and `request_undo` carry `at`, the sender's `count` when it sent them; an arrival whose `at` differs from the receiver's `count` is stale — silently void. While its item stands, the off-turn peer sends nothing further except `resign`.

The on-turn peer answers by accepting or by moving. `accept_draw` ends the game as a draw. `accept_undo` retracts every ply beyond the standing request's `keep`, and the session's `undos` — its count of accepted retractions, zero at birth — rises by one. `keep` ranges from 0, the initial position, to one less than the sender's `count`; anything else is malformed. An acceptance that matches no standing item is a violation. In a hidden-information game a retraction is no different: each end recomputes the position from the deal and the surviving plies, so a piece the retracted plies revealed stands hidden again.

Pending offers and requests do not survive a connection's end: each peer voids its knowledge of them when the connection carrying them dies.

## Ending

Ends decided by the game's rules need no message. `resign` — valid from either peer at any point of an active session — and `accept_draw` end the game explicitly. A peer that sent a terminal, or whose own ply decided the end, holds the session **unsettled** until a resume exchange completes for it, an `unknown_session` answer voids it, or the other peer's `propose` retires it.

One precedence rule decides every collision, applied whenever a peer learns of more than one end for a session: a rules-decided end from the reconciled plies outranks everything; then a draw by agreement; then, if both peers resigned, the game is a draw; then a single resignation stands.

A hidden-information game's end needs no disclosure message either. Each device already holds the deal, and what it discloses to its player at the end is decided by the game's rules and not by this protocol.

## Interruption and resume

A peer recognises its opponent on a fresh connection. It initiates `resume`, after `hello`, for a session that is **active**, or **ended** and unsettled — an unsettled peer may also open the exchange on the session's live connection. The exchange completes — and the session re-binds — on the connection the *proposer's* `resume` travelled on, which the proposer sends on exactly one connection of its choosing; every other `resume` either peer sent is void once it does, and a peer whose `resume` travelled any other connection re-sends it on the completing one. Neither peer sends a `move` for the session until it holds the other's `resume` on that connection.

`resume` states the session as the sender holds it: `undos` and `count`; `keep` — the surviving count of the last accepted retraction, meaningful when `undos` is above zero, otherwise echoed as the sender's `count`; `end` — the terminal the sender has sent for this session, `resign` or `accept_draw`, absent when it has sent none; and `deal_digest` — the digest of the deal this session derived, present for a hidden-information session and absent for every other. If one peer's `undos` is higher, the other truncates its plies to that peer's `keep`. Then the peer holding more plies resends the missing ones as ordinary `move` messages. Each peer merges the other's `end` by the precedence rule as if the terminal itself had arrived. A peer's exchange is complete — and the session settled — when it holds the other's `resume` on the completing connection and has received every ply reconciliation owes it from that `resume`.

**What a hidden-information session's ends persist is the handshake, not the deal.** Each end keeps the `commit`, the `nonce`, the `seed` and the `deal_digest` it computed when the handshake completed, beside everything it keeps for any session, and derives the deal from the seed and the nonce again whenever it needs it. Before using that deal it re-verifies it locally, and against everything the deal comes from: it hashes the persisted seed and compares with the persisted commitment, and it re-derives the deal and compares its digest with the persisted one. A failure of either check means what it holds is no longer the session, which it answers as a peer that does not know the session — a persisted nonce that has rotted passes the commitment check and fails the digest, which is why the digest is the one that travels. Nothing about the deal re-travels — not the seed, not the nonce, and least of all the deal.

A `resume` whose `deal_digest` differs from the receiver's own is two devices holding different games under one identifier: the receiver answers `decline` with `deal_mismatch`, and the session is void on both sides. A peer that genuinely does not know the session — it holds nothing for it, it retired it, it holds only a proposal that died with its connection, or its own deal failed re-verification — answers `decline` with `unknown_session`, and the session is void on both sides.

## Violations

A malformed message, an illegal move, a handshake departure named above, or any message with no lawful meaning in the receiver's connection and session state — beyond the stale-item, ended-state, and reconciliation allowances above — is a protocol violation: the detecting peer closes the connection and the session is void.

A connection carrying no session is the other case entirely: either peer may close one at any time, and such a closure means nothing.

## Versions

`hello` announces the one protocol version the sender speaks; this document is version **2**. A peer that cannot or will not speak the announced version closes the connection, and a peer announcing 1 is a peer this version closes on. Nothing ever obliges a newer version to accommodate an older one, and this version accommodates none.

## Deliberately absent

Clocks and every time control · timeouts of any kind, the deal handshake's included · spectators and third peers · chat · any cryptography of ours beyond the deal commitment · any secrecy of the deal from a device that holds it · rematch vocabulary · per-game parameter vocabulary (a configuration is a `rules_id`) · game-specific rights such as draw claims · end confirmation and post-end retraction · delivery acknowledgements (settlement rides the resume exchange) · graceful version degradation · a version bump for a new game (a new game is a new `rules_id`) · normative dependence on any other document.
