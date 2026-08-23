# Game Archive Fixtures

This directory holds the approved, executable fixtures for the version 7 game archive: a **golden corpus** of archives the codec must accept, decoded exactly as stated, and a **rejection corpus** of one archive per rejection class the accepted validation order defines. The fixtures and [docs/game-data.md](../../docs/game-data.md) form one contract and are reviewed together: a change to either is a data-contract change.

Normative stance: every expected value comes from the accepted archive format, its serialized vocabularies, its cross-field rules, and its validation order — never from what the codec currently happens to do. A file here that the codec disagrees with is a codec defect until the contract says otherwise.

## Layout

```text
fixtures/archive/
├── valid/      <stem>.mxq + <stem>.expected.json — accepted, and what they decode to
└── rejected/   <stem>.mxq + <stem>.expected.json — refused, and with which status
```

Each archive is paired with an expectation sidecar of the same stem. The runner walks every `*.mxq` in both directories, so a new case is a new pair of files and never new runner code.

## What runs them

`core/tests/mxq_archive_tests.cpp`, registered with CTest as `archive_fixtures`, through the public C surface only:

```sh
cmake -S core -B core/.build -G Ninja -DMXQ_ENABLE_RULES_FACADE=ON
cmake --build core/.build
ctest --test-dir core/.build --output-on-failure
```

It takes `--fixtures <dir>` and honours `$MXQ_ARCHIVE_FIXTURES_DIR`.

Two configurations, deliberately different, exactly as `rules_fixtures` differs:

| | `mxq_archive_probe` | `mxq_archive_validate` |
|---|---|---|
| with `-DMXQ_ENABLE_RULES_FACADE=ON` | evaluated | evaluated |
| without it | evaluated | **NOT IMPLEMENTED**, never counted as a pass |

`validate` replays the move line through the rules facade, so without the engine it is not in the library at all — absent rather than stubbed, because the accepted error taxonomy has no not-implemented code. The probe half of every fixture still runs there, which is most of the structural corpus.

Different things skip in this runner and only one of them is that absence: a fixture of a placement game is passed over in a build without the second engine, and the argument-contract case is passed over in a debug build, where the assertions it asks about are compiled in. The closing NOT IMPLEMENTED banner speaks for the rules facade alone, so a run that skipped only the others does not claim `validate` was missing from a build that had it.

## The golden corpus

Every golden asserts these things:

- `mxq_archive_probe` accepts it and fills `MxqArchiveInfo` exactly as the sidecar states;
- `mxq_archive_validate` accepts it and fills a **byte-identical** `MxqArchiveInfo`, because validate is documented as everything probe does and then the rules replay;
- its bytes are already in **canonical form** — UTF-8, one line, members in codepoint order, no insignificant whitespace, integers only — checked by the runner rather than assumed, so these files are byte-exact inputs for the encoder that will have to reproduce them.

| file | shape | terminal pair |
|---|---|---|
| `free-play-created` | Free Play, active, no moves yet | none |
| `free-play-active` | Free Play, active | none: the active shape omits `outcome`, `end_reason`, `ended_at` |
| `free-play-ended-early` | Free Play, complete | `none` / `ended-early` |
| `free-play-draw-threefold` | Free Play, complete | `draw` / `threefold-repetition` |
| `human-vs-ai-checkmate` | human versus AI, complete | `red-wins` / `checkmate` |
| `human-vs-ai-resignation` | human versus AI, complete | `black-wins` / `resignation` |
| `human-vs-ai-active` | human versus AI, active, Random resolved to Black | none |
| `xiangqi-free-play-active` | Xiangqi, Free Play, active | none |
| `xiangqi-free-play-ended-early` | Xiangqi, Free Play, complete | `none` / `ended-early` |
| `xiangqi-custom-scene` | Xiangqi, Free Play, active, from a composed start with Black to move | none |
| `nearby-active` | nearby, active | none |
| `nearby-resignation` | nearby, complete | `red-wins` / `resignation` |
| `nearby-agreed-draw` | nearby, complete | `draw` / `agreed-draw` |
| `nearby-mutual-resignation` | nearby, complete | `draw` / `mutual-resignation` |
| `jieqi-nearby-active` | Jieqi, nearby, active, from a dealt start with the deal's provenance | none |
| `jieqi-nearby-ended-early` | Jieqi, nearby, complete | `none` / `ended-early` |
| `renju-free-play-active` | Renju, Free Play, active | none |
| `gomoku-15-five-in-a-row` | Gomoku, Free Play, complete | `red-wins` / `five-in-a-row` |

Between them they cover every game the format records, every `outcome` value, the terminal pairs a version 7 file can carry, both human sides, every AI level, both halves of the per-game start policy, and both halves of the omission rule: Free Play and networked play omit `human_side`, `ai_level`, `ai_movetime_ms` and `first_mover_choice` rather than writing a null, which is exactly what `MXQ_COLOR_NONE`, `MXQ_AI_LEVEL_NONE` and `MXQ_FIRST_MOVER_NONE` stand for on the other side of the C interface. Of the modes they cover human-versus-AI, Free Play and `nearby`; `online` is `nearby`'s twin in every rule this corpus exercises, and where that twinning is asserted is the core suite rather than a second set of documents differing in one member.

The networked goldens also carry the portability law: none of them names a peer device, a pairing, or which side this device's player took. `nearby-resignation` is a resignation with no `human_side` to check its winner against — the outcome names the winner and the side that resigned is its opposite — and the draws are the ends only two players can reach.

`jieqi-nearby-active` and `jieqi-nearby-ended-early` are the goldens whose start is dealt, and the ones that carry the deal's provenance — the active shape and the completed one, so that filing a dealt game is shown to keep the members the document holds while the wire session that held the digest dies with the game. Its `start_fen` is the deal itself — every hidden identity, ninety-nine characters, Red to move — and the members beside it are what make the record checkable rather than asserted: validation hashes the seed against the commitment, derives the deal as [docs/boardgame-protocol-v2.md](../../docs/boardgame-protocol-v2.md) derives it, and compares what comes out with the start in front of it. The seed and the nonce are plain values on purpose. They are a cross-implementation vector rather than a secret, and the vector was chosen so that deriving this deal draws a value of `0xfffffffd` below nine and has to discard it: an implementation that skipped the rejection sampling fails this file, and one that ran Fisher–Yates the other way, laid the pieces onto the squares in another order, or fed the seed and the nonce to the key in the other order fails it too.

The active-game shape is the archive as the store holds it while the game is being played, not something an export ever produces: an exported file is always a completed game. The codec reads both, and refusing to import an incomplete one is the importer's rule rather than the codec's. `free-play-created` is the extreme of that shape — the row a creation writes, with an empty `moves` array, which is a complete version 7 document and not an incomplete one.

The placement goldens are what the second board looks like in this format: a frozen empty 15×15 start, single-square plies, and — in `gomoku-15-five-in-a-row` — an end only a placement game's rules reach. A codec carrying a movement game's start position, move grammar or end-reason set passes every xiangqi golden unchanged and fails these.

### Sidecar

```json
{
  "title": "…",
  "why": "…",
  "info": {
    "archive_version": 7,
    "game": "minixiangqi",
    "move_count": 2,
    "mode": "free-play",
    "human_side": null,
    "outcome": "none",
    "end_reason": null,
    "started_at_ms": 1767225600000,
    "ended_at_ms": 0,
    "game_id": "019b76da-a800-7000-8000-000000000000"
  }
}
```

`info` is `MxqArchiveInfo`, in the serialized vocabulary. `game` is the file's own `rules_id`, decoded, and every sidecar states it: there is no absent value for it, so a sidecar that omitted it would fail rather than pass silently. `null` spells a NONE constant — `human_side: null` is `MXQ_COLOR_NONE`, `end_reason: null` is `MXQ_END_REASON_NONE`. `MxqOutcome` has no absent constant, so an archive that records no end reads `outcome: "none"` with `end_reason: null` and `ended_at_ms: 0`; **`end_reason` is what separates an ended-early record from a game that has not ended**, and the two active goldens pin that.

The identifiers are the deterministic sequence `MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY` documents — one per file, so no two goldens claim the same identity — and the timestamps start at the deterministic clock's epoch, so the round-trip fixtures in [`../store/`](../store/README.md) compare these files byte for byte against what the core writes.

### Every golden is produced

No golden is hand-written. Each is named from a scenario in [`../store/`](../store/README.md) — the active shapes from a round-trip scenario, the completed shapes from a terminal scenario in `../store/terminal/` — and the runners fail unless `mxq_archive_encode` reproduces the file byte for byte under `MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY`. A golden that no scenario produces is a golden nothing proves.

The identifiers and instants follow from that flag alone: the identity provider's counter-derived sequence, and a clock at a fixed epoch advancing one second per committed change. `game-data.md` § canonical form fixes what the instants mean — a stored document's `exported_at` is the committed change that produced it, and for an ending that is also its `ended_at` and its History-added time, because they are one event.

## The rejection corpus

One archive per rejection class of the accepted validation order, each stating the status **both** entry points must return. They differ exactly for the rules-tier classes, where a structural probe is documented to accept a file that a full validation refuses — that difference is itself the assertion.

| class | file | probe | validate |
|---|---|---|---|
| transport and size | `empty` | `MALFORMED` | `MALFORMED` |
| transport and size | *synthesised: 1 MiB + 1 byte* | `TOO_LARGE` | — |
| strict UTF-8 | `utf8-invalid` | `MALFORMED` | `MALFORMED` |
| JSON syntax | `json-syntax-truncated` | `MALFORMED` | `MALFORMED` |
| JSON syntax | `json-trailing-content` | `MALFORMED` | `MALFORMED` |
| JSON syntax | `not-an-object` | `MALFORMED` | `MALFORMED` |
| duplicate member name | `duplicate-member` | `MALFORMED` | `MALFORMED` |
| `null` | `null-member` | `MALFORMED` | `MALFORMED` |
| non-integer number | `non-integer-number` | `MALFORMED` | `MALFORMED` |
| structural limit: nesting depth | `depth-over-limit` | `TOO_LARGE` | `TOO_LARGE` |
| structural limit: members per object | `members-over-limit` | `TOO_LARGE` | `TOO_LARGE` |
| structural limit: string length | `string-over-limit` | `TOO_LARGE` | `TOO_LARGE` |
| structural limit: plies | *synthesised: 10 001 plies* | `TOO_LARGE` | — |
| envelope: in-band type check | `archive-format-wrong` | `MALFORMED` | `MALFORMED` |
| envelope: missing member | `envelope-member-missing` | `MALFORMED` | `MALFORMED` |
| envelope: malformed version | `version-not-positive` | `MALFORMED` | `MALFORMED` |
| **unsupported archive version** | `version-newer` | `UNSUPPORTED_VERSION` | `UNSUPPORTED_VERSION` |
| **unsupported archive version** | `version-older` | `UNSUPPORTED_VERSION` | `UNSUPPORTED_VERSION` |
| **unsupported rules version** | `rules-version-unsupported` | `UNSUPPORTED_VERSION` | `UNSUPPORTED_VERSION` |
| unknown member in a known version | `envelope-member-unknown` | `MALFORMED` | `MALFORMED` |
| unknown member in a known version | `content-member-unknown` | `MALFORMED` | `MALFORMED` |
| content: missing member | `content-member-missing` | `MALFORMED` | `MALFORMED` |
| content: wrong member type | `moves-not-an-array` | `MALFORMED` | `MALFORMED` |
| content: mode-to-configuration shape | `free-play-carries-human-side` | `MALFORMED` | `MALFORMED` |
| content: mode-to-configuration shape | `nearby-carries-human-side` | `MALFORMED` | `MALFORMED` |
| content: mode-to-configuration shape | `human-vs-ai-missing-ai-level` | `MALFORMED` | `MALFORMED` |
| closed vocabulary | `vocabulary-mode` | `MALFORMED` | `MALFORMED` |
| closed vocabulary | `vocabulary-outcome` | `MALFORMED` | `MALFORMED` |
| closed vocabulary | `vocabulary-end-reason` | `MALFORMED` | `MALFORMED` |
| closed vocabulary | `rules-id-wrong` | `MALFORMED` | `MALFORMED` |
| cross-field: the rule reason and the game | `cross-field-placement-reason` | `MALFORMED` | `MALFORMED` |
| cross-field: the rule reason and the game | `cross-field-movement-reason` | `MALFORMED` | `MALFORMED` |
| cross-field: the rule reason and the game | `cross-field-fifty-move-game` | `MALFORMED` | `MALFORMED` |
| field validity: move notation | `move-notation-placement` | `MALFORMED` | `MALFORMED` |
| field validity: move notation | `move-notation-other-board` | `MALFORMED` | `MALFORMED` |
| rules tier: initial position | `start-fen-other-game` | `MXQ_OK` | `INCONSISTENT_REPLAY` |
| field validity: `game_id` | `game-id-not-uuid7` | `MALFORMED` | `MALFORMED` |
| field validity: timestamp | `timestamp-form` | `MALFORMED` | `MALFORMED` |
| field validity: move notation | `move-notation` | `MALFORMED` | `MALFORMED` |
| cross-field: the terminal triple | `terminal-triple-partial` | `MALFORMED` | `MALFORMED` |
| cross-field: outcome and reason | `cross-field-draw-reason` | `MALFORMED` | `MALFORMED` |
| cross-field: outcome and reason | `cross-field-none-reason` | `MALFORMED` | `MALFORMED` |
| cross-field: resignation | `cross-field-resignation-mode` | `MALFORMED` | `MALFORMED` |
| cross-field: resignation | `cross-field-resignation-winner` | `MALFORMED` | `MALFORMED` |
| cross-field: agreed ending | `cross-field-agreed-draw-mode` | `MALFORMED` | `MALFORMED` |
| cross-field: time ordering | `time-ordering` | `MALFORMED` | `MALFORMED` |
| rules tier: initial position | `start-fen-not-frozen` | `MXQ_OK` | `MXQ_ERR_RULES_ILLEGAL_POSITION` |
| rules tier: initial position | `start-fen-illegal-setup` | `MXQ_OK` | `MXQ_ERR_RULES_ILLEGAL_POSITION` |
| rules tier: initial position | `start-fen-counters` | `MXQ_OK` | `INCONSISTENT_REPLAY` |
| rules tier: illegal move | `move-illegal` | `MXQ_OK` | `INCONSISTENT_REPLAY` |
| rules tier: terminal pair | `terminal-mismatch-checkmate` | `MXQ_OK` | `TERMINAL_MISMATCH` |
| rules tier: terminal pair | `terminal-mismatch-threefold` | `MXQ_OK` | `TERMINAL_MISMATCH` |
| rules tier: terminal pair | `terminal-mismatch-ended-early` | `MXQ_OK` | `TERMINAL_MISMATCH` |
| rules tier: terminal pair | `terminal-mismatch-agreed-draw` | `MXQ_OK` | `TERMINAL_MISMATCH` |
| rules tier: terminal pair | `terminal-mismatch-outcome` | `MXQ_OK` | `TERMINAL_MISMATCH` |
| cross-field: the rule reason and the game | `cross-field-forty-move-game` | `MALFORMED` | `MALFORMED` |
| content: the deal's presence | `jieqi-deal-members-missing` | `MALFORMED` | `MALFORMED` |
| content: the deal's presence | `jieqi-free-play-carries-deal` | `MALFORMED` | `MALFORMED` |
| content: the deal's presence | `nearby-carries-deal-members` | `MALFORMED` | `MALFORMED` |
| rules tier: the recorded deal | `jieqi-deal-commit-mismatch` | `MXQ_OK` | `INCONSISTENT_REPLAY` |
| rules tier: the recorded deal | `jieqi-deal-not-the-start` | `MXQ_OK` | `INCONSISTENT_REPLAY` |

Statuses are written without their `MXQ_ERR_ARCHIVE_` prefix here; the sidecars spell the constant in full. Some rows carry a status with no such prefix, and that is the point of them: see the start policy below.

Some limits are size limits, and a fixture file for one would be a megabyte or seventy kilobytes of noise in the repository. They are built by the runner instead, on **both** sides of each boundary — exactly 1 MiB and exactly 10 000 plies must be accepted, one byte and one ply more must not — which pins them as boundaries rather than approximations. That is why those rows say *synthesised*.

### Sidecar

```json
{
  "class": "rules tier: illegal move",
  "probe": "MXQ_OK",
  "validate": "MXQ_ERR_ARCHIVE_INCONSISTENT_REPLAY",
  "detail_contains": "not legal",
  "why": "…",
  "detail_index": 2
}
```

`probe` and `validate` are the exact `MxqStatus` constant names. `game` is optional and names the game the fixture is of, stated where that game is one a build may not carry; a runner in a build without it reports the fixture as not evaluated rather than asserting a refusal it would get for the wrong reason. `detail_contains` is a substring the diagnostic must carry, which is how the distinct created-by-a-newer-version message is pinned — `version-newer` requires the words *created by a newer version*, and that file also carries a member no version of this format knows, so it additionally pins that version dispatch answers **before** the unknown-member rule. `detail_index` is checked against `MxqError.detail_index` where the status carries one.

### Two versions are dispatched on, not one

`archive_version` says how the file is written; `rules_version` says which rules interpretation the game was played under. A file this build cannot reproduce for either reason gets the same answer family — `UNSUPPORTED_VERSION`, never corruption — with the diagnostic naming which of the two it was. `rules_id`, by contrast, is a closed vocabulary: a file naming a ruleset outside it is not a later version of ours, so it is `MALFORMED`.

`archive_version` is dispatched on in both directions, and `version-newer` and `version-older` are the pair. A file from ahead of this build and a file from behind it are different sentences to a reader — one says the build is old, the other says the file is — and each carries the diagnostic that says which. Both are refusals, and a refusal is the whole of what happens: the file is not read, and nothing else is done to it.

### The game axis is read before the rest of `content`

`rules_id` decides how other members are judged, which is why rejection fixtures exist for it beyond the vocabulary one. `move-notation-other-board` is a `minixiangqi` document whose move is `a1a10`: a move of the larger board and no move at all of the smaller one, which a reader carrying a single grammar would accept. `move-notation-placement` is a `renju` document whose ply is spelled as a movement — two squares of its own board, and no ply of a game where a stone arrives and nothing moves, which is why how many squares a move is comes from the game rather than from the text's length. `start-fen-other-game` is a `xiangqi` document opening from the Mini Xiangqi array: a real position of a real game, the wrong one, so nothing structural can catch it and the rules tier must — see the start policy below for the company it keeps. And `cross-field-placement-reason` and `cross-field-movement-reason` are the two directions of one rule — a rule reason belongs to the kind of game whose rules produce it — because a partition checked on one side only refuses half of what it knows, with `cross-field-fifty-move-game` for the narrowing inside it, the move-count rule that is Xiangqi's and not Mini Xiangqi's.

### Which position a document begins from is the game's own

These fixtures carry the start policy between them, and between them they cover both its rungs and both its answers.

- `xiangqi-custom-scene` is the golden: a `xiangqi` document whose `start_fen` is a composed position with Black to move. It is what a reader comparing `start_fen` against a frozen constant refuses.
- `start-fen-not-frozen` is a `minixiangqi` document opening from another position of its own board. Mini Xiangqi defines no setup-legality predicate, so it begins from its frozen start and from nowhere else — the file is refused with `MXQ_ERR_RULES_ILLEGAL_POSITION`, which is that predicate's own answer for a game that has none. Xiangqi is the single `rules_id` under which this file would be accepted, and that is the whole of what the per-game start policy makes of it.
- `start-fen-illegal-setup` is a `xiangqi` document whose composed start the predicate refuses: Red is not to move and stands in check. Its one ply is the general's capture that position offers, which is what makes it pin the **order** of the tier rather than only its answer — a build that replayed before judging the start reaches the engine's assertion that no capture is of a general and takes the process down instead of refusing the file. A document with no moves would be refused under either order and would pin nothing about which came first.
- `start-fen-counters` is the same composed position the golden opens from, spelled with the counters of a game that has plies behind it. It is refused on the structural rung, in the archive's own voice, because a start has no plies to count and the predicate's clauses — which read the pieces and the side to move — would accept it. It pins the import side of the counters rule, a different mapping from creation's, where the same position is `MXQ_ERR_RULES_INVALID_FEN`.
- `start-fen-other-game` is a `xiangqi` document opening from the Mini Xiangqi array, and it keeps its archive-domain `INCONSISTENT_REPLAY`. A position of no board is not one the predicate has an opinion about, so it is the file disagreeing with itself rather than the setup question being answered — which is why the two rows differ, and why a build that unified them would fail this one.

The corpus pins the frozen-only half of the policy through the Mini Xiangqi file, which is evaluated in every configuration that has the rules facade. The placement games' half is the same rule and has no fixture of its own: one would be evaluated only in a build carrying the second engine, so it would pin nothing where the corpus actually runs.

### A dealt start, and the evidence beside it

More fixtures carry the third half of that policy, the one Jieqi adds, and they divide the way the validation order divides it.

Some are structural, and they are the presence rule on both of its axes: the deal members ride a `jieqi` document whose mode is a networked one and no other. `jieqi-deal-members-missing` is that document without them, `jieqi-free-play-carries-deal` is the mode axis — Free Play deals its own start locally, so there is no handshake behind it for a commitment to bind — and `nearby-carries-deal-members` is the game axis, a `minixiangqi` nearby document carrying provenance for a deal that never happened. A rule checked on one side only refuses half of what it knows, which is why the corpus states them all.

The rest are the rules tier, and none is reachable structurally. `jieqi-deal-commit-mismatch` carries a well-formed commitment of some seed and not of this one; `jieqi-deal-not-the-start` carries evidence that is internally consistent — the seed does hash to the commitment — and still derives a different deal from the one `start_fen` holds, because the nonce is another peer's. The first is caught by hashing and the second only by deriving, which is why the derivation is part of validation rather than a convenience for whoever wants to check a record by hand. Both land on `INCONSISTENT_REPLAY`: a file whose own evidence contradicts its start is the file disagreeing with itself, not the setup question being answered.

## What the read path does not enforce

Some of the canonical form's clauses decide what a document *means* — UTF-8, integers only, `null` forbidden — and the read path enforces those, along with the duplicate-member rejection the validation order states separately. The rest — one line, members in codepoint order, no insignificant whitespace, minimal string escaping — describe the writer's output and are re-established by canonicalisation, which the accepted validation order performs after validation and before hashing. An incoming file that spells the same document differently is accepted and canonicalised; it is not refused over its whitespace.

The golden files are held to the full canonical form anyway, because they are what the encoder must reproduce.

## A second runner over the same corpus

`core/tests/mxq_interchange_tests.cpp`, registered as `store_interchange`, re-runs this corpus through `mxq_store_import` rather than through the codec's own entry points. It asserts nothing about what the codec decides — the sidecars already fix that, and it reads its expectations out of them — and everything about what the pipeline around it does: that every rejection class refuses through the surface a frontend actually calls, with the status the sidecar states for `validate`, and that the library is untouched each time. It also drives the round trip, the duplicate and conflict answers, and the accepted two-second budget over the largest golden.

The active shapes are its one deliberate divergence: they are valid version 7 documents, so `archive_fixtures` accepts them, and an import refuses them because an imported record is a completed game. That refusal is asked after the ordered stages rather than among them, so a file's rejection class is the same whichever entry point asked — which is what lets this runner read its expectations from these sidecars at all.

## Consumption

The archive codec is gated by these fixtures on every platform. Every rejection class in [docs/game-data.md](../../docs/game-data.md)'s accepted validation order has at least one fixture here, and a new rejection class arrives with one; a rejection the corpus does not cover is a gap in the corpus, not a licence to add one silently.
