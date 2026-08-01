# Game Archive Fixtures

This directory holds the approved, executable fixtures for the version 2 game archive: a **golden corpus** of archives the codec must accept, decoded exactly as stated, and a **rejection corpus** of one archive per rejection class the accepted validation order defines. The fixtures and [docs/game-data.md](../../docs/game-data.md) form one contract and are reviewed together: a change to either is a data-contract change.

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

## The golden corpus

Every golden asserts three things:

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

Between them they cover both games, all four `outcome` values, the terminal pairs a version 2 file can carry, both modes, both human sides, all three AI levels, and both halves of the omission rule: Free Play omits `human_side`, `ai_level`, `ai_movetime_ms` and `first_mover_choice` rather than writing a null, which is exactly what `MXQ_COLOR_NONE`, `MXQ_AI_LEVEL_NONE` and `MXQ_FIRST_MOVER_NONE` stand for on the other side of the C interface.

The active-game shape is the archive as the store holds it while the game is being played, not something an export ever produces: an exported file is always a completed game. The codec reads both, and refusing to import an incomplete one is the importer's rule rather than the codec's. `free-play-created` is the extreme of that shape — the row a creation writes, with an empty `moves` array, which is a complete version 2 document and not an incomplete one.

### Sidecar

```json
{
  "title": "…",
  "why": "…",
  "info": {
    "archive_version": 2,
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

### Provenance: every golden is now produced

All seven files are **produced** rather than hand-written. `fixtures/store/` names each of them from a scenario — the three active shapes from a round-trip scenario, the four completed shapes from a terminal scenario in `fixtures/store/terminal/` — and the runners fail unless `mxq_archive_encode` reproduces the file byte for byte under `MXQ_CORE_FLAG_DETERMINISTIC_IDENTITY`.

The regenerations, in order:

- `free-play-created` was added with the encoder, as the shape a creation writes.
- `free-play-active` and `human-vs-ai-active` had their `origin.exported_at` restamped from `2026-01-01T00:01:00.000Z`, a hand-chosen "a minute later", to the instant of the committed change each document actually records — the second of their two moves, at `2026-01-01T00:00:02.000Z`.
- The four completed goldens — `free-play-ended-early`, `free-play-draw-threefold`, `human-vs-ai-checkmate`, `human-vs-ai-resignation` — had their `ended_at` and `origin.exported_at` restamped when the archiving paths that can produce them landed. Both now carry the instant of the one committed event that ended each game, which under the deterministic clock is the creation plus one second per committed change: `00:00:03.000` after two moves and an archive-and-clear, `00:00:09.000` after eight moves and a claim, `00:00:04.000` after three moves and a confirmation, `00:00:03.000` after two moves and a resignation. Their sidecars' `ended_at_ms` moved with them; nothing else in any of the eight files changed, and no sidecar changed for `origin`, which is never part of what a file decodes to.

`game-data.md` § canonical form states the rule those instants follow: a stored document's `exported_at` is the committed change that produced it, and for an ending that is also its `ended_at` and its History-added time, because they are one event.

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
| **unsupported rules version** | `rules-version-unsupported` | `UNSUPPORTED_VERSION` | `UNSUPPORTED_VERSION` |
| unknown member in a known version | `envelope-member-unknown` | `MALFORMED` | `MALFORMED` |
| unknown member in a known version | `content-member-unknown` | `MALFORMED` | `MALFORMED` |
| content: missing member | `content-member-missing` | `MALFORMED` | `MALFORMED` |
| content: wrong member type | `moves-not-an-array` | `MALFORMED` | `MALFORMED` |
| content: mode-to-configuration shape | `free-play-carries-human-side` | `MALFORMED` | `MALFORMED` |
| content: mode-to-configuration shape | `human-vs-ai-missing-ai-level` | `MALFORMED` | `MALFORMED` |
| closed vocabulary | `vocabulary-mode` | `MALFORMED` | `MALFORMED` |
| closed vocabulary | `vocabulary-outcome` | `MALFORMED` | `MALFORMED` |
| closed vocabulary | `vocabulary-end-reason` | `MALFORMED` | `MALFORMED` |
| closed vocabulary | `rules-id-wrong` | `MALFORMED` | `MALFORMED` |
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
| cross-field: time ordering | `time-ordering` | `MALFORMED` | `MALFORMED` |
| rules tier: initial position | `start-fen-not-frozen` | `MXQ_OK` | `INCONSISTENT_REPLAY` |
| rules tier: illegal move | `move-illegal` | `MXQ_OK` | `INCONSISTENT_REPLAY` |
| rules tier: terminal pair | `terminal-mismatch-checkmate` | `MXQ_OK` | `TERMINAL_MISMATCH` |
| rules tier: terminal pair | `terminal-mismatch-threefold` | `MXQ_OK` | `TERMINAL_MISMATCH` |
| rules tier: terminal pair | `terminal-mismatch-ended-early` | `MXQ_OK` | `TERMINAL_MISMATCH` |
| rules tier: terminal pair | `terminal-mismatch-outcome` | `MXQ_OK` | `TERMINAL_MISMATCH` |

Statuses are written without their `MXQ_ERR_ARCHIVE_` prefix here; the sidecars spell the constant in full.

Two limits are size limits, and a fixture file for either would be a megabyte or seventy kilobytes of noise in the repository. They are built by the runner instead, on **both** sides of each boundary — exactly 1 MiB and exactly 10 000 plies must be accepted, one byte and one ply more must not — which pins them as boundaries rather than approximations. That is why those two rows say *synthesised*.

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

`probe` and `validate` are the exact `MxqStatus` constant names. `detail_contains` is a substring the diagnostic must carry, which is how the distinct created-by-a-newer-version message is pinned — `version-newer` requires the words *created by a newer version*, and that file also carries a member no version of this format knows, so it additionally pins that version dispatch answers **before** the unknown-member rule. `detail_index` is checked against `MxqError.detail_index` where the status carries one.

### Two versions are dispatched on, not one

`archive_version` says how the file is written; `rules_version` says which rules interpretation the game was played under. A file this build cannot reproduce for either reason gets the same answer family — `UNSUPPORTED_VERSION`, never corruption — with the diagnostic naming which of the two it was. `rules_id`, by contrast, is a closed vocabulary of two values: a file naming a third ruleset is not a later version of ours, so it is `MALFORMED`.

### The game axis is read before the rest of `content`

`rules_id` decides how two other members are judged, which is why two rejection fixtures exist for it beyond the vocabulary one. `move-notation-other-board` is a `minixiangqi` document whose move is `a1a10`: a move of the larger board and no move at all of the smaller one, which a reader carrying a single grammar would accept. `start-fen-other-game` is a `xiangqi` document opening from the Mini Xiangqi array: a real position of a real game, the wrong one, so nothing structural can catch it and the rules tier must. Between them they pin that the board and the starting position both follow the named game rather than a constant.

## What the read path does not enforce

The canonical form has seven clauses. Three of them decide what a document *means* — UTF-8, integers only, `null` forbidden — and the read path enforces those, along with the duplicate-member rejection the validation order states separately. The other four — one line, members in codepoint order, no insignificant whitespace, minimal string escaping — describe the writer's output and are re-established by canonicalisation, which the accepted validation order performs after validation and before hashing. An incoming file that spells the same document differently is accepted and canonicalised; it is not refused over its whitespace.

The golden files are held to the full canonical form anyway, because they are what the encoder must reproduce.

## A second runner over the same corpus

`core/tests/mxq_interchange_tests.cpp`, registered as `store_interchange`, re-runs this corpus through `mxq_store_import` rather than through the codec's own entry points. It asserts nothing about what the codec decides — the sidecars already fix that, and it reads its expectations out of them — and everything about what the pipeline around it does: that every rejection class refuses through the surface a frontend actually calls, with the status the sidecar states for `validate`, and that the library is untouched each time. It also drives the round trip, the duplicate and conflict answers, and the accepted two-second budget over the largest golden.

The three active shapes are its one deliberate divergence: they are valid version 2 documents, so `archive_fixtures` accepts them, and an import refuses them because an imported record is a completed game. That refusal is asked after the ordered stages rather than among them, so a file's rejection class is the same whichever entry point asked — which is what lets this runner read its expectations from these sidecars at all.

## Consumption

The archive codec is gated by these fixtures on every platform. Every rejection class in [docs/game-data.md](../../docs/game-data.md)'s accepted validation order has at least one fixture here, and a new rejection class arrives with one; a rejection the corpus does not cover is a gap in the corpus, not a licence to add one silently.
