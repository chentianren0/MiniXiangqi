# The BoardGame Protocol

This document defines a wire contract by which two devices play one board game: sessions, moves, the universal actions, interruption, and versioning, with one transport binding. It defines no game's rules. Everything an implementing application builds around it — screens, discovery surfaces, permission handling, and whatever devices keep of finished games — is outside it.

> **Status: draft.** Nothing here binds yet.

## The games it carries

The protocol carries games with two players, alternating turns, no hidden information, and deterministic rules — a pass, where a game has one, is a turn. The result must be decided by the move sequence alone: a game whose ending needs human judgement fits only through a rule variant that decides it mechanically (Go by two passes and computed area counting, for example). Hidden-information games are excluded permanently; that exclusion is what keeps trust simple — both players see everything, and the transport already authenticates and encrypts.

A game is named by a `rules_id`: a string of lowercase letters, digits, and hyphens, such as `minixiangqi` or `go-19`. A `rules_id` names the complete game: its rules, its initial position, its move-text grammar, its result function, and the mapping from the two movers to whatever colours or stones the game calls them. Two peers that share a `rules_id` and a `rules_version` therefore share all of it by construction, which is why no message ever carries a position, a grammar, or a parameter. A new game is a new `rules_id` and a game module in the implementing application — never a protocol change; a protocol that needed a new version to admit Go would have failed its one design requirement.

## The model

Two peers hold one reliable, ordered, authenticated, encrypted byte stream. Within each direction the stream preserves order, but a message from each side can always cross a message from the other; this contract resolves every such crossing deterministically. Neither peer is distinguished; the only asymmetry a session ever has is who proposed it.

Every message is one JSON object with exactly one member: the message's name, whose value is an object holding its fields —

```json
{"move": {"session": "0b34…", "index": 7, "move": "b1b3"}}
```

`protocol` is an integer. `session` is an opaque string, minted by the proposer as a lowercase UUID, echoed verbatim, and compared byte-wise. `index`, `at`, `count`, `keep`, and `undos` are non-negative integers. `end` is the string `resign` or `accept_draw`. A message carries exactly its named fields — `end` alone may be omitted — and an extra or missing member is malformed. `hello` is the first message on every connection, in both directions, before anything else.

## Session states

Between one pair of peers at most one session is proposed or active at a time — save the crossing instant named under Proposing — and one finished session may linger in **ended** beside the pair's dealings until, settled, a new proposal retires it. Every message's validity is decided by its receiver at arrival from the state it holds:

- **proposed** — a `propose` is unanswered. A proposal is scoped to the connection it travelled on: `accept` and `decline` are effective only there, and an unanswered proposal dies with its connection.
- **active** — the proposal was accepted; play is on.
- **ended** — the game has a result. An ended session still answers `resume`; it applies an arriving valid in-sequence `move` — any rules-decided end that yields merges by the precedence rule — and merges arriving terminals by the same rule; every other message arriving for it is discarded, never a violation. A new proposal in either direction retires it once it is settled, and a `resume` for a retired session meets `unknown_session`.
- **void** — the session was destroyed without a result, by a violation or an `unknown_session` answer. A device forgets a void session.

## Messages

| Message | Fields | Meaning |
|---|---|---|
| `hello` | `protocol` | Opens a connection, both directions, before anything else. |
| `propose` | `session`, `rules_id`, `rules_version`, `proposer_moves` | Offer a game. |
| `accept` | `session` | The proposal is accepted; play begins. |
| `decline` | `session`, `reason` | A proposal or a resume is refused. |
| `move` | `session`, `index`, `move` | One ply. |
| `offer_draw` | `session`, `at` | Offer to end the game as a draw. |
| `accept_draw` | `session` | The game ends as agreed. |
| `request_undo` | `session`, `at`, `keep` | Ask to retract every ply beyond the first `keep`. |
| `accept_undo` | `session`, `keep` | The retraction happens. |
| `resign` | `session` | The sender loses. |
| `resume` | `session`, `undos`, `count`, `keep`, `end` | Continue a session on a fresh connection. |

`reason` is one of `declined`, `unknown_game`, `rules_mismatch`, `busy`, `unknown_session`. A version-1 peer treats any other message name, or any malformed message, as a violation.

## Proposing a game

The proposer mints the session identifier and sends `propose`. The receiver accepts only when it implements `rules_id` with a `rules_version` exactly equal — `rules_version` is an opaque string, compared byte-wise — and its player consents; otherwise it declines with the fitting reason. Equal rules versions are what let both devices referee: with them the two implementations cannot disagree, and neither peer ever rules over the other.

`proposer_moves` is `first` or `second`: which mover the proposer takes. Proposing is choosing — the proposer picks the sides, and the other player's power is to decline.

A `propose`, sent or received, retires the pair's lingering **settled** ended session. A peer holding the pair's session unsettled does not propose: it settles first — one exchange on a live connection — or learns from that exchange that the session is void. `busy` answers a `propose` that arrives while an **active** session exists with that peer. A `propose` that arrives while the receiver's own proposal is outstanding with that peer — on any connection — is the crossing case, and the crossing itself is never answered: for that instant the pair holds two proposed sessions, the one whose session identifier sorts lower byte-wise survives while the other is void without an answer, and the survivor then stands as an ordinary proposal, answered on its own connection like any other.

A rematch is a new `propose` — there is no rematch vocabulary.

## Playing

Plies are numbered from zero; a session's `count` is the number of plies it holds, so the next ply is always ply `count`. `proposer_moves` and index parity decide whose turn every ply is. A peer sends `move` only on its own turn and only with `index` equal to its `count`; `move`'s text is a move in the game's own grammar, and the receiver validates it with its own rules. A `move` that lands voids the standing offer or request, on both sides.

## Offers and requests

Only the off-turn peer opens a negotiation, and at most one stands at a time. `offer_draw` and `request_undo` carry `at`, the sender's `count` when it sent them; an arrival whose `at` differs from the receiver's `count` is stale — silently void, because a move crossed it, and the sender learns the same from that move's arrival. While its item stands, the off-turn peer sends nothing further except `resign`.

The on-turn peer answers by accepting or by moving; moving on is the only refusal there is. `accept_draw` ends the game as a draw. `accept_undo` must repeat the standing request's `keep`: every ply beyond the first `keep` is retracted, play continues at ply `keep` with the turn parity gives it, and the session's `undos` — its count of accepted retractions, zero at birth — rises by one. `keep` ranges from 0, the initial position, to one less than the sender's `count`; anything else is malformed. An acceptance that matches no standing item is a violation.

A retraction both players want but only the on-turn player may grant is reached from the other side: the off-turn peer requests it, the on-turn peer accepts. Pending offers and requests do not survive a connection's end: each peer voids its knowledge of them when the connection carrying them dies, and the off-turn peer may simply open them again.

## Ending

Ends decided by the game's rules need no message: both devices reach the same verdict from the same plies, so a result message would only be a channel for disagreement. `resign` — valid from either peer at any point of an active session — and `accept_draw` end the game explicitly. An end is final: no confirmation attends it, and no retraction follows it — reopening a finished game is a new proposal. Delivery is never assumed: a peer that sent a terminal holds the session **unsettled** until a resume exchange completes for it or an `unknown_session` answer voids it.

Enders can cross, so one precedence rule decides every collision, applied identically by both peers whenever they learn of more than one end for a session: a rules-decided end from the reconciled plies outranks everything; then a draw by agreement; then, if both peers resigned, the game is a draw; then a single resignation stands.

## Interruption and resume

The transport names the peer device behind every connection, so a peer recognises its opponent on a fresh connection. It initiates `resume`, after `hello`, for a session that is **active**, or **ended** and unsettled; a settled or retired game asks for nothing. Either peer may send the first `resume`, but the exchange completes — and the session re-binds — on the connection the *proposer's* `resume` travelled on, which the proposer sends on exactly one connection of its choosing; every other `resume` either peer sent is void once it does, and a peer whose `resume` travelled any other connection re-sends it on the completing one. Neither peer sends a `move` for the session until it holds the other's `resume` on that connection.

`resume` states the session as the sender holds it: `undos` and `count`; `keep` — the surviving count of the last accepted retraction, meaningful when `undos` is above zero, otherwise echoed as the sender's `count`; and `end` — the terminal the sender has sent for this session, `resign` or `accept_draw`, absent when it has sent none. Reconciliation is then mechanical. If one peer's `undos` is higher — it can only be higher by one, since retractions need a live connection — the other truncates its plies to that peer's `keep`. Then the peer holding more plies resends the missing ones as ordinary `move` messages, which an ended receiver applies like any other. The declared ends need no replay: each peer merges the other's `end` by the precedence rule as if the terminal itself had arrived. A peer's exchange is complete — and the session settled — when it holds the other's `resume` on the completing connection and has received every ply reconciliation owes it from that `resume`; a peer that never receives what it is owed never completes, stays unsettled, and simply initiates again on the next fresh connection. Play continues wherever reconciliation left the session.

A peer that genuinely does not know the session — it holds nothing for it, it retired it, or it holds only a proposal that died with its connection — answers `decline` with `unknown_session`, and the session is void on both sides. What a device keeps of a game that ended void is its own business.

## Violations

A malformed message, a message before `hello`, a message for an unknown session outside the resume exchange, a `move` off turn or with the wrong `index` beyond resume's refill, an illegal move, an out-of-range `keep`, or an acceptance matching no standing item is a protocol violation. So is any message with no lawful meaning in the receiver's session state, beyond the stale-item, ended-state, and reconciliation allowances above. The detecting peer closes the connection and the session is void. The peers are honest implementations on an authenticated transport, so a violation is a bug — it surfaces loudly and is never repaired silently.

## Versions

`hello` announces the one protocol version the sender speaks; this document is version **1**. A peer that cannot or will not speak the announced version closes the connection. Nothing ever obliges a newer version to accommodate an older one: refusal is the honest floor, and any accommodation a future version offers is its own choice. Version 1 does not anticipate its successors.

## A transport binding: Wi-Fi Aware

The protocol above needs only the stream its model states. One binding is defined, for iPhone and iPad:

- The service is `_boardgame._tcp`, declared `Publishable` and `Subscribable` in `WiFiAwareServices`, with the `com.apple.developer.wifi-aware` entitlement carrying `Publish` and `Subscribe`.
- Devices pair once through the system's DeviceDiscoveryUI; pairing is the system's and outlives the application. The paired-device identity the transport reports for each connection is the peer identity that sessions and resume rely on.
- Both devices run the publisher and the subscriber together — no device is a host. Connections are TCP in `.bulk` performance mode on both sides, framed by the Network framework's JSON message coder, so the protocol layer sees whole messages.
- Two crossed connections may both come up when both devices connect at once. A session binds to the connection its `propose` — or, resumed, its proposer's `resume` — travelled on, and either peer may close a connection carrying no session at any time; such a closure means nothing.

## Deliberately absent

Clocks and every time control · spectators and third peers · hidden information · chat · cryptography of our own · rematch vocabulary · per-game parameter vocabulary (a configuration is a `rules_id`) · game-specific rights such as draw claims (a game's rules may express them as turn actions in its own grammar) · end confirmation and post-end retraction · delivery acknowledgements (settlement rides the resume exchange) · graceful version degradation · normative dependence on any other document.
