# BoardGame Nearby Protocol v1 and Nearby Play

This document defines the approved design target for BoardGame Nearby Protocol v1 and its first product use: nearby Xiangqi and Mini Xiangqi between two supported iPhones or iPads.

> **Status: approved draft.** This is the target of [campaign #114](https://github.com/ppppvz/MiniXiangqi/issues/114), not a claim about the behavior of the current build. A campaign stage makes a requirement binding only when its reviewed change updates the contract that owns that behavior.

## Scope

BoardGame Nearby Protocol separates a reusable session protocol from game-specific profiles.

- Version 1 supports exactly two devices, two seats, deterministic turn-based play, and public game state.
- Xiangqi and Mini Xiangqi are its first profiles. A future Go profile can define its board, moves, passes, scoring, and rules version without changing the session protocol.
- Hidden-information games, cryptographically fair shuffles, more than two seats, and simultaneous actions are outside version 1. A public-state card game can use version 1 if its profile satisfies the same deterministic two-seat contract.
- The first transport is Apple Wi-Fi Aware. The wire and game-profile layers do not depend on Wi-Fi Aware and can be carried by a future authenticated reliable byte stream.
- Nearby play adds no Internet matchmaking, relay, account, cloud state, telemetry, or fallback network path.

The protocol name is **BoardGame Nearby Protocol** and its wire identifier is `boardgame`. The working DNS-SD service type is `_boardgame._tcp`.

## Ownership and trust

The Apple frontend owns DeviceDiscoveryUI, Wi-Fi Aware capability and pairing UI, the selected-device listener and browser, the Network connection, TLS configuration, lifecycle callbacks, and native presentation. It passes received bytes and an opaque selected-peer binding to the shared core.

The shared core owns the frame codec, strict message schemas, version and profile negotiation, the host and guest state machines, command ordering, idempotency, game-profile validation, event persistence, resumption, and archive meaning. Network callbacks enqueue work to one serialized session owner; they never mutate a game session concurrently or reimplement rules in Swift.

The host orders commands and is the only ordinary game-state writer. It commits an accepted event locally before sending it. The guest independently validates every game event through the same rules core, commits it locally, and only then sends a persistence `receipt`. A receipt reports technical durability; it is never a player's acceptance of a result, draw, or takeback.

A modified or malicious paired client can disconnect, stall, or lie in its UI. The protocol does not provide remote attestation and cannot force liveness or honest presentation. It does prevent malformed input, replay, reordering, stale commands, and illegal game events from silently mutating a conforming peer. The guest's independent validation makes the host authoritative for order, not for the rules.

## Independent versions

The following axes never stand in for one another:

| Axis | Meaning |
| --- | --- |
| Wire version | Framing, envelopes, session messages, ordering, and resumption |
| Profile identifier and version | Game actions, canonical state, seats, and profile behavior |
| Rules identifier and version | The exact rules interpretation used to validate a game |
| Archive version | Portable game-record shape |
| Store schema version | Local durable tables and invariants |
| Core API version | The C-visible native interface |
| App version | Diagnostic implementation identity only |

Each peer's first `hello` advertises a minimum and maximum supported wire version and exact supported profile versions. The bootstrap `hello` and `hello_reject` envelopes carry `wire_version = 0`; zero is reserved for this fixed negotiation schema and can never be selected or mutate a game. The selected wire version is the highest value in the overlap, and every later envelope carries that value. Version 1 implementations advertise `min_version = 1` and `max_version = 1`; no overlap or no exact common profile fails before a game is created. There is no best-effort downgrade, and an app version never decides compatibility.

## Apple transport adapter

- Runtime availability comes from `WACapabilities`; the nearby-play entry is absent when the feature is unavailable. The campaign supports iPhone and iPad only, not macOS or Windows, although their History and replay surfaces must understand a nearby record.
- The app declares both `Publish` and `Subscribe` in the `com.apple.developer.wifi-aware` entitlement and declares `_boardgame._tcp` as both publishable and subscribable under `WiFiAwareServices`.
- DeviceDiscoveryUI performs pairing. The host uses `DevicePairingView`; the guest uses `DevicePicker`. A later game uses the current `WAPairedDevice` collection, which can change when a person removes access or reinstalls the app.
- The person explicitly selects the opponent. Both `WAPublisherListener` and `WASubscriberBrowser` are restricted to that selected paired device; the app never publishes to all paired devices, connects to the first discovered endpoint, or accepts a connection from a different paired device.
- `WAPairedDevice.PairingInfo`, including any display name, is unauthenticated pre-pairing data and is only a UI hint. Authorization is bound to the selected paired device and the peer observed on the established path.
- Publisher is the protocol host and subscriber is the guest. Both sides use the default `bulk` Wi-Fi Aware performance mode and default best-effort service class. The listener and browser use the same performance mode.
- Apple permits connection work while an app has foreground or background runtime; it does not grant permanent execution. Automatic reconnection means resumable attempts whenever the system gives the app runtime. Suspension, termination, pairing removal, and reinstall are ordinary recovery cases, not promises that a socket stays alive.
- Wi-Fi Aware is the only route for this adapter. Failure never falls back to infrastructure Wi-Fi, cellular data, an Internet service, or a local-network broadcast.

## Service name and registration gate

`boardgame` satisfies the syntax and 15-character limit that Apple derives from RFC 6335 and RFC 6763. The fully qualified working service type is `_boardgame._tcp`; the wire version is negotiated in-band and is not appended to the service name.

The working name is not treated as reserved. Immediately before an IANA application, the current Service Name and Transport Protocol Port Number Registry is checked again. The application is prepared only after two physical devices interoperate through the complete version 1 flow. If the name is assigned to another protocol before then, this project changes the service type rather than shipping a collision.

## Secure channel

The application stream uses TCP with TLS 1.3 and authenticated peer binding rooted in the selected Wi-Fi Aware pairing. Encrypted but unauthenticated TLS, disabled trust evaluation, and acceptance of any certificate are nonconforming.

Apple exposes a per-connection `WASharedSecret` for bootstrapping higher-layer security, including a `tlsPSK` purpose, and recommends TLS 1.3. The implementation stage must prove the supported peer-authentication configuration against the current SDK and two physical devices before that exact API sequence becomes binding. If a shared secret is used, it is derived anew for that connection and is never persisted, transmitted, reused, logged, or treated as a long-term key.

TLS early data and 0-RTT are disabled. Gameplay commands mutate durable state and are not replay-safe at the TLS layer; protocol idempotency is defense in depth, not permission to accept early data. Session resumption is allowed only after the ordinary TLS handshake has authenticated the selected peer.

## Framing and strict JSON

TCP carries a sequence of frames. Each frame is a four-byte unsigned big-endian payload length followed by exactly that many bytes of UTF-8 JSON. A zero length or a payload greater than 1 MiB is invalid. Version 1 has no compression.

Before any mutation, the receiver enforces all of these limits:

- strict UTF-8 and one complete RFC 8259 JSON object per frame;
- nesting depth at most 8, at most 64 members per object, and at most 4 KiB per string unless a profile defines a smaller limit;
- duplicate member names, `null`, floating-point values, unknown members, unknown message types, and values outside their schema are rejected;
- sequence numbers are JSON integers from 0 through `9007199254740991`, the exact interoperable integer range;
- identifiers are canonical lowercase RFC 9562 version 7 UUID strings. They provide uniqueness and orderability, not authentication or secrecy;
- every array and profile payload has a message-specific bound within the frame limit.

Hashes and idempotency comparisons use a canonical re-encoding of the decoded schema: UTF-8, object members in codepoint order, no insignificant whitespace, minimal string escaping, and integers only. The receiver reads and validates the length before allocating the payload, does not allow unbounded queued frames, and closes the connection after a bounded protocol error response when one can be sent safely. Partial, malformed, oversized, or semantically invalid messages have no game effect.

## Messages and table creation

Every envelope contains `type`, `wire_version`, and `message_id`. Messages for a created game also contain `game_id`. The closed version 1 families are:

- `hello` and `hello_reject` for wire and profile negotiation;
- `table_offer`, `table_accept`, and `table_reject` for the proposed game, exact profile and rules versions, starting state, and seat assignment;
- `command` for a player's intent;
- `event` for a host-committed state transition;
- `receipt` for the guest's highest contiguous durably committed event sequence;
- `resume` and `resume_reject` for reconnection;
- `protocol_error` and `close` for bounded termination.

Before an offer, both devices resolve any existing active game under the product's single-active-game rule. The host creates only a transient table draft, chooses who is Red, generates the version 7 `game_id`, and proposes the exact initial state. The guest validates and explicitly accepts that complete proposal.

Acceptance is not a false two-device transaction. The host first commits event 1, `game_started`, with the shared identity, configuration, initial state, host timestamps, and canonical state digest. The guest validates and commits that event, then receipts sequence 1. Neither side enables move input until the guest's receipt arrives. A failure leaves a resumable waiting table; it never creates two independently named games.

One table carries one game in version 1. A completed game returns both players to the table page; another game uses a fresh offer and `game_id`, not an in-place rematch.

## Commands, events, and durability

Every command carries a unique `command_id`, the `game_id`, the actor's seat, and `expected_event_seq`. The host accepts it only from the selected peer or local seat, only at the exact expected sequence, and only when the profile and session state permit it.

For each accepted command, one serialized host transaction commits the game mutation, the next event sequence, the full event, and the idempotency result before the event is sent. The guest checks sequence, actor, profile legality, canonical state digest, and result, then commits the event and its new contiguous sequence in one transaction before sending a receipt.

- Event sequences begin at 1 and have no gaps.
- Each event carries a prefix digest that binds its complete history: `H(n) = SHA-256("boardgame-event-v1" || H(n-1) || E(n))`, where `H(0)` is 32 zero bytes and `E(n)` is the canonical decoded event content excluding its digest field. Receipts and resume messages bind both the sequence and `H(n)`.
- Repeating an identical `command_id` returns its original result and never reapplies it. Identity is decided from the canonical decoded command fields and profile-canonical payload, excluding the transport `message_id` and the `command_id` used as the lookup key; JSON whitespace, escaping, and member order cannot change it. Reusing an identifier for different canonical content is a protocol error.
- Repeating an identical event is harmless. A conflicting event at an existing sequence is a fatal divergence.
- A stale command is refused with the current sequence; it is never guessed forward.
- A sequence gap, digest mismatch, or lost receipt enters resumption. No new command is accepted through an unresolved gap.
- The event sequence is durable replication state and is distinct from the core's in-memory position revision.

The protocol promises one local atomic commit at a time and eventual synchronization after reconnection. It cannot promise atomic commitment across two devices when either device is unreachable.

## Resumption

The selected peers reconnect with `game_id`, exact negotiated versions, the highest contiguous event sequence, its event-prefix digest, and its canonical state digest. The host retains the active game's complete event log and replays every missing event in order only when the guest's committed prefix matches.

A different prefix digest at the same committed sequence is fatal divergence: neither peer rewrites or discards committed history. If the prefix agrees but derived state is locally damaged, the guest may rebuild only that derived state from its own verified durable event log before accepting missing host events. A host that has lost an event the guest already committed also fails closed; version 1 has no rollback or merge operation.

The host does not migrate during version 1. Loss of the host pauses the game. A disconnect, suspension, or process exit never decides a winner and never silently ends the game. A peer-binding mismatch, removed pairing, unsupported version, or unknown game fails closed and requires an explicit recovery or new table.

## Game profiles

A profile defines:

- a globally collision-resistant profile identifier, profile version, rules identifier, and rules version;
- exactly two seats and their presentation names;
- initial-state validation and canonical state bytes;
- bounded action payloads and deterministic legality;
- whose turn it is and which seat may issue each game action;
- outcome, claimable-result, and natural-result interpretation;
- the canonical state digest, SHA-256 over the profile's canonical state bytes.

The first identifiers are `io.github.ppppvz.boardgame.xiangqi` and `io.github.ppppvz.boardgame.mini-xiangqi`, each at profile version 1. Their game action is a canonical move already accepted by the shared rules facade. Profile version and rules version are both checked; neither is inferred from board dimensions or an app build.

## Draw, takeback, resignation, leave, and results

All concurrent commands are resolved by durable host event order.

- A rules-authorized draw claim is unilateral. The host validates current eligibility and commits the draw immediately.
- A draw offer is a consent proposal. Acceptance commits the agreed draw immediately; rejection, cancellation, or a later move expires it. Only one draw offer may be pending.
- A takeback is a consent proposal, not direct Undo. It names the exact current last retained move event and removes one ply only after the opponent accepts. If that move is no longer last, the request is stale. Repeated takebacks require repeated requests. A pending request cannot complete while the opponent is unreachable.
- Resignation is unilateral and final, with the opponent winning. It is available in nearby play independently of the local human-versus-AI resignation rule.
- Deliberate leave is not resignation or forfeit. It ends an unfinished game early without a competitive result. A guest's leave while disconnected is a durable pending intent and is not reported as synchronized until the host orders it after resumption.
- A network loss by itself does nothing to the result. The game waits and resumes.

A deterministic natural result produced by the rules core stops moves and shows the ordinary dismissible result presentation, but remains the active game. Either player may send `finish_natural_result`; there is no per-player result acknowledgment. The host accepts it only at the current event head while the same natural result remains, then commits the final event and its local immutable History state. The guest validates and commits that event into equivalent History before its receipt. Until the host commit, either player may request the one-ply takeback above, and the game resumes only if the opponent accepts. Host order makes the first committed finish or accepted takeback decisive and makes the other command stale.

Neither finishing nor consent completes while the peers are disconnected. The result remains safely active and the UI may be left, but the synchronized game waits for resumption. This keeps every durable transition in one host-ordered log and avoids a separate result-acknowledgment or offline merge protocol.

## Portable and local data

Both devices preserve the host-created `game_id`, shared start metadata, ordered retained main line, profile and rules versions, result, and canonical timestamps. Their portable canonical game content and content hash agree.

The following are local replica metadata and never enter exported game content:

- the opaque selected-peer binding and any `WAPairedDevice` identifier;
- pairing or device display names;
- whether this device was host or guest;
- this device's local seat and any “your side” History label;
- event receipts, retry state, and connection diagnostics.

Deleting and reimporting an exported nearby record restores the shared game but not the local seat or peer label. Export remains replayable on every supported platform even though only capable iPhones and iPads can establish the nearby transport.

The existing archive and store version must not be silently reinterpreted. The implementation stage makes an explicit reviewed archive, schema, migration, and C-API version decision before the first nearby record is written.

## Failure behavior

- Invalid or unauthorized input is rejected before game mutation and is safe to log only as bounded metadata, never raw game frames or derived secrets.
- A host persistence failure creates no event. A guest persistence failure creates no receipt and resumption retries the event.
- A presentation failure cannot advance protocol state. UI reads the committed session state rather than predicting acceptance.
- A protocol violation, TLS failure, wrong peer, or impossible state closes the connection and leaves the last committed local state resumable.
- Resource limits apply before expensive rules replay. Repeated violations may end the connection but never delete or finalize a game.

## Verification gates

The shared conformance suite covers bootstrap and selected version handling, exact profile negotiation, every message schema, hostile framing and JSON, wrong peer and wrong seat, illegal and stale commands, canonical duplicate and conflicting identifiers, event gaps, committed-prefix mismatch, state-digest mismatch, lost receipts, full replay, persistence failure at each commit boundary, draw and takeback races, concurrent natural-result finish and takeback, disconnected finish refusal, and deterministic reconstruction of both replicas.

The Apple two-device matrix covers capability hiding, first pairing, later selection, wrong-peer rejection, unpairing, reinstall, idle and lock, background runtime, suspension, termination, radio loss, TLS failure, reconnect, and both games through equivalent History content. Wi-Fi Aware cannot be validated in Simulator; the secure table and lifecycle claims require two supported physical devices.

## Primary specifications

- Apple: [Wi-Fi Aware](https://developer.apple.com/documentation/wifiaware), [Adopting Wi-Fi Aware](https://developer.apple.com/documentation/wifiaware/adopting-wi-fi-aware), [Connecting devices for peer-to-peer Wi-Fi](https://developer.apple.com/documentation/wifiaware/connecting-paired-devices), [WAPairedDevice](https://developer.apple.com/documentation/wifiaware/wapaireddevice), and [WASharedSecret](https://developer.apple.com/documentation/wifiaware/washaredsecret).
- Service naming: [RFC 6335](https://www.rfc-editor.org/rfc/rfc6335) and [RFC 6763](https://www.rfc-editor.org/rfc/rfc6763), plus the current [IANA service-name registry](https://www.iana.org/assignments/service-names-port-numbers/).
- Wire security and data: [RFC 8446](https://www.rfc-editor.org/rfc/rfc8446), [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259), and [RFC 9562](https://www.rfc-editor.org/rfc/rfc9562).
