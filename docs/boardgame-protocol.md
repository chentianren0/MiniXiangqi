# The BoardGame Protocol

This document defines a wire contract by which two devices play one board game, with one transport binding. It defines no game's rules. Everything an implementing application builds around it — screens, discovery surfaces, permission handling, and whatever devices keep of finished games — is outside it.

> **Status: binding.**

## The games it carries

The protocol carries games with two players, alternating turns, no hidden information, and deterministic rules — a pass, where a game has one, is a turn. The result must be decided by the move sequence alone. Hidden-information games are excluded permanently.

A game is named by a `rules_id`: a string of lowercase letters, digits, and hyphens, such as `minixiangqi` or `go-19`. A `rules_id` names the complete game: its rules, its initial position, its move-text grammar, its result function, and the mapping from the two movers to whatever colours or stones the game calls them. A new game is a new `rules_id` and a game module in the implementing application — never a protocol change.

## The model

Two peers hold one reliable, ordered byte stream, whose authenticity and privacy are the carrying link's own. Within each direction the stream preserves order, but a message from each side can always cross a message from the other. Neither peer is distinguished; the only asymmetry a session ever has is who proposed it.

Every message is one JSON object with exactly one member: the message's name, whose value is an object holding its fields —

```json
{"move": {"session": "0b34…", "index": 7, "move": "b1b3"}}
```

`protocol` is an integer. `session` is an opaque string, minted by the proposer as a UUID, echoed verbatim, and compared byte-wise. `index`, `at`, `count`, `keep`, and `undos` are non-negative integers. A message carries exactly its named fields — `end` alone may be omitted — and an extra or missing member is malformed.

## Session states

Between one pair of peers at most one session is proposed or active at a time — save the crossing instant named under Proposing — and one finished session may linger in **ended** beside the pair's dealings. Every message's validity is decided by its receiver at arrival from the state it holds:

- **proposed** — a `propose` is unanswered. A proposal is scoped to the connection it travelled on: `accept` and `decline` are effective only there, and an unanswered proposal dies with its connection.
- **active** — the proposal was accepted; play is on.
- **ended** — the game has a result. An ended session still answers `resume`; it applies an arriving valid in-sequence `move` and merges arriving terminals by the precedence rule; every other message arriving for it is discarded, never a violation. A new proposal retires it.
- **void** — the session was destroyed without a result. A device forgets a void session.

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
| `accept_undo` | `session` | The retraction happens. |
| `resign` | `session` | The sender loses. |
| `resume` | `session`, `undos`, `count`, `keep`, `end` | Continue an interrupted session. |

`reason` is one of `declined`, `unknown_game`, `rules_mismatch`, `busy`, `unknown_session`. A version-1 peer treats any other message name as a violation.

## Proposing a game

The proposer sends `propose`. The receiver accepts only when it implements `rules_id` with a `rules_version` exactly equal — an opaque string, compared byte-wise — and its player consents; otherwise it declines with the fitting reason. `proposer_moves` is `first` or `second`: which mover the proposer takes.

A peer proposes only when its own copy of the pair's lingering session, if any, is settled: unsettled, it settles first or learns from that exchange that the session is void. An arriving `propose` retires the receiver's ended copy whatever its settledness. `busy` answers a `propose` that arrives while an **active** session exists with that peer. A `propose` that arrives while the receiver's own proposal is outstanding with that peer — on any connection — is the crossing case: the proposal whose session identifier sorts lower byte-wise survives, and the other is void without an answer.

## Playing

Plies are numbered from zero; a session's `count` is the number of plies it holds. `proposer_moves` and index parity decide whose turn every ply is. A peer sends `move` only on its own turn and only with `index` equal to its `count`; `move`'s text is a move in the game's own grammar, and the receiver validates it with its own rules. A `move` that lands voids the standing offer or request, on both sides.

## Offers and requests

Only the off-turn peer opens a negotiation, and at most one stands at a time. `offer_draw` and `request_undo` carry `at`, the sender's `count` when it sent them; an arrival whose `at` differs from the receiver's `count` is stale — silently void. While its item stands, the off-turn peer sends nothing further except `resign`.

The on-turn peer answers by accepting or by moving. `accept_draw` ends the game as a draw. `accept_undo` retracts every ply beyond the standing request's `keep`, and the session's `undos` — its count of accepted retractions, zero at birth — rises by one. `keep` ranges from 0, the initial position, to one less than the sender's `count`; anything else is malformed. An acceptance that matches no standing item is a violation.

Pending offers and requests do not survive a connection's end: each peer voids its knowledge of them when the connection carrying them dies.

## Ending

Ends decided by the game's rules need no message. `resign` — valid from either peer at any point of an active session — and `accept_draw` end the game explicitly. A peer that sent a terminal, or whose own ply decided the end, holds the session **unsettled** until a resume exchange completes for it, an `unknown_session` answer voids it, or the other peer's `propose` retires it.

One precedence rule decides every collision, applied whenever a peer learns of more than one end for a session: a rules-decided end from the reconciled plies outranks everything; then a draw by agreement; then, if both peers resigned, the game is a draw; then a single resignation stands.

## Interruption and resume

The transport names the peer device behind every connection, so a peer recognises its opponent on a fresh connection. It initiates `resume`, after `hello`, for a session that is **active**, or **ended** and unsettled — an unsettled peer may also open the exchange on the session's live connection. The exchange completes — and the session re-binds — on the connection the *proposer's* `resume` travelled on, which the proposer sends on exactly one connection of its choosing; every other `resume` either peer sent is void once it does, and a peer whose `resume` travelled any other connection re-sends it on the completing one. Neither peer sends a `move` for the session until it holds the other's `resume` on that connection.

`resume` states the session as the sender holds it: `undos` and `count`; `keep` — the surviving count of the last accepted retraction, meaningful when `undos` is above zero, otherwise echoed as the sender's `count`; and `end` — the terminal the sender has sent for this session, `resign` or `accept_draw`, absent when it has sent none. If one peer's `undos` is higher, the other truncates its plies to that peer's `keep`. Then the peer holding more plies resends the missing ones as ordinary `move` messages. Each peer merges the other's `end` by the precedence rule as if the terminal itself had arrived. A peer's exchange is complete — and the session settled — when it holds the other's `resume` on the completing connection and has received every ply reconciliation owes it from that `resume`.

A peer that genuinely does not know the session — it holds nothing for it, it retired it, or it holds only a proposal that died with its connection — answers `decline` with `unknown_session`, and the session is void on both sides.

## Violations

A malformed message, an illegal move, or any message with no lawful meaning in the receiver's connection and session state — beyond the stale-item, ended-state, and reconciliation allowances above — is a protocol violation: the detecting peer closes the connection and the session is void.

## Versions

`hello` announces the one protocol version the sender speaks; this document is version **1**. A peer that cannot or will not speak the announced version closes the connection. Nothing ever obliges a newer version to accommodate an older one.

## A transport binding: iPhone and iPad

The protocol above needs only the stream its model states. One binding is defined, for iPhone and iPad, and it carries a connection over either of two links; nothing above the transport tells the two apart.

- **Wi-Fi Aware.** The service is `_boardgame._tcp`, declared `Publishable` and `Subscribable` in `WiFiAwareServices`, with the `com.apple.developer.wifi-aware` entitlement carrying `Publish` and `Subscribe`. Devices pair once through the system's DeviceDiscoveryUI; pairing is the system's and outlives the application, and the platform authenticates and encrypts what it carries. Both devices run the publisher and the subscriber together, in `.realtime` performance mode on both sides.
- **The local network.** `_boardgame._tcp` is the Bonjour service type, advertised and browsed by both devices together. Every device on the network running the application is reachable, and no pairing stands before a proposal.
- The transport names a stable peer identity behind every connection, whatever link carries it, and that identity is what sessions and resume rely on. A paired device's system identity is one source of it; an application-minted identifier, stated by the peer and proved by nothing, is the other. A game is gated by the consent a proposal asks for and by nothing else.
- Connections are TCP framed by the Network framework's JSON message coder, so the protocol layer sees whole messages.
- Two crossed connections may both come up when both devices connect at once, on one link or on two. A session binds to the connection its `propose` — or, resumed, its proposer's `resume` — travelled on, and either peer may close a connection carrying no session at any time; such a closure means nothing.

## Deliberately absent

Clocks and every time control · spectators and third peers · hidden information · chat · cryptography of our own · rematch vocabulary · per-game parameter vocabulary (a configuration is a `rules_id`) · game-specific rights such as draw claims · end confirmation and post-end retraction · delivery acknowledgements (settlement rides the resume exchange) · graceful version degradation · normative dependence on any other document.
