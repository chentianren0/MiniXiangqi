# The BoardGame Protocol

This document defines the wire contract two nearby devices use to play one board game: sessions, moves, the universal actions, interruption, and the Wi-Fi Aware binding. It is game-agnostic and defines no game's rules, and it does not define the Nearby Play feature — entry, screens, pairing surfaces, permission states, and History belong to the feature's own design.

> **Status: draft.** Nothing here binds yet.

## The games it carries

The protocol carries games with two players, alternating turns, no hidden information, and deterministic rules — a pass, where a game has one, is a turn. The result must be decided by the move sequence alone: a game whose ending needs human judgement fits only through a rule variant that decides it mechanically (Go by two passes and computed area counting, for example). Hidden-information games are excluded permanently; that exclusion is what keeps trust simple — both players see everything, and the transport already authenticates and encrypts.

A game is named by its `rules_id`, the same identity the game archives carry ([game-data.md](game-data.md)): lowercase letters, digits, and hyphens. This application implements `minixiangqi` and `xiangqi`, each from its standard initial position. A new game is a new `rules_id` and a game module in the app — never a protocol change; a protocol that needed a new version to admit Go would have failed its one design requirement.

## The model

Two peers hold one reliable, ordered, authenticated, encrypted byte stream. Neither peer is distinguished; the only asymmetry a session has is who proposed it. At most one session — proposed or active — exists per pair of peers at a time.

Every message is one JSON object with exactly one member: the message's name, whose value is an object holding its fields —

```json
{"move": {"session": "0B34…", "index": 7, "move": "b1b3"}}
```

## Messages

| Message | Fields | Meaning |
|---|---|---|
| `hello` | `protocol` | The first message on every connection, in both directions, before anything else. |
| `propose` | `session`, `rules_id`, `rules_version`, `proposer_moves` | Offer a game. |
| `accept` | `session` | The proposal is accepted; play begins. |
| `decline` | `session`, `reason` | A proposal or a resume is refused. |
| `move` | `session`, `index`, `move` | One ply. |
| `offer_draw` | `session` | Offer to end the game as a draw. |
| `accept_draw` | `session` | The game ends as agreed. |
| `request_undo` | `session`, `to_index` | Ask to retract every ply after `to_index`. |
| `accept_undo` | `session`, `to_index` | The retraction happens. |
| `resign` | `session` | The sender loses, at once. |
| `resume` | `session`, `next_index` | Continue an interrupted session on a fresh connection. |

`reason` is one of `declined`, `unknown_game`, `rules_mismatch`, `busy`, `unknown_session`. A version-1 peer treats any other message name, or any malformed message, as a violation.

## Proposing a game

The proposer mints the session identifier (a UUID) and sends `propose`. The receiver accepts only when it has a game module for `rules_id` whose `rules_version` is exactly equal — the same string the game's archives carry — and its player consents; otherwise it declines with the fitting reason. Equal rules versions are what let both devices referee: with them, the two cores cannot disagree, and neither device ever rules over the other.

`proposer_moves` is `first` or `second`: which mover the proposer takes. The game maps movers to its own colours — in both implemented games the first mover is Red. Proposing is choosing: the proposer picks the sides, and the other player's power is to decline.

While a session exists with a peer, any further `propose` from that peer is declined `busy`. When both peers propose to each other at once, the proposal whose session identifier sorts lower (byte-wise) survives and the other is void without an answer.

A rematch is a new `propose` on the same connection — there is no rematch vocabulary.

## Playing

`index` is the 0-based ply number, the same index the archive's `moves` array uses, and `move` is the game's canonical move text, the same text the archives retain. A peer sends a move only on its own turn — `proposer_moves` and index parity decide whose turn every index is — and only with `index` equal to the number of plies both sides hold. The receiver validates every move with its own rules.

## Offers and requests

An offer or request stands until it is accepted or until any `move` lands: a move voids every pending offer and request, and moving on is the only refusal there is. A new offer or request replaces the sender's previous one.

`request_undo` names `to_index`, the last ply that survives. Only the other peer may answer, and `accept_undo` must repeat the pending `to_index`; acceptance retracts every later ply, and play continues at `to_index + 1` with the turn that parity gives it.

## Ending

Ends decided by the game's rules — mate, stalemate, whatever the game defines — need no message: both devices reach the same verdict from the same moves, so a result message would only be a channel for disagreement. `resign` and `accept_draw` end the game explicitly. After any end the session is over; the connection remains, and a rematch is a fresh proposal.

## Interruption and resume

The transport names the peer device behind every connection, so a peer holding an unfinished session recognises its opponent on a fresh connection and sends `resume` after `hello`, with `next_index` equal to the count of plies it holds. When both peers know the session, each learns from the other's `next_index` who is behind, and the peer holding more resends the missing plies as ordinary `move` messages; play continues. A peer that does not know the session answers `decline` with `unknown_session`, and the session is void — what a device keeps of a game that ended this way is the feature's business, not the wire's.

## Violations

A malformed message, an unknown session, a move out of turn or out of sequence beyond resume's refill, an `accept_undo` that matches no pending request, or an illegal move is a protocol violation: the detecting peer closes the connection and the session is void. The peers are identical honest applications on an authenticated transport, so a violation is a bug — it surfaces loudly and is never repaired silently.

## Versions

`hello` announces the one protocol version the sender speaks; this document is version **1**. A peer that cannot or will not speak the announced version closes the connection. Nothing ever obliges a newer version to accommodate an older one: refusal is the honest floor, and any accommodation a future version offers is its own choice. Version 1 does not anticipate its successors.

## The Wi-Fi Aware binding

- The service is `_boardgame._tcp`, declared `Publishable` and `Subscribable` in `WiFiAwareServices`, with the `com.apple.developer.wifi-aware` entitlement carrying `Publish` and `Subscribe`. iPhone and iPad only, per the framework's supported devices.
- Devices pair once through the system's DeviceDiscoveryUI; pairing is the system's and outlives the app. The paired-device identity the transport reports for each connection is the peer identity that sessions and resume rely on.
- Both devices run the publisher and the subscriber together — no device is a host. Connections are TCP in `.bulk` performance mode on both sides, framed by the Network framework's JSON message coder, so the protocol layer sees whole messages.
- Two crossed connections may both come up when both devices connect at once. A session binds to the connection its `propose` travelled on, and either peer may close a connection carrying no session at any time; such a closure means nothing.

## Deliberately absent

Clocks and every time control · spectators and third peers · hidden information · chat · cryptography of our own · rematch vocabulary · per-game parameter vocabulary (a configuration is a `rules_id`) · graceful version degradation.
