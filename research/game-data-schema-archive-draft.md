# Core SQLite schema and game-archive format v1

## Scope and method

This draft proposes the concrete persistent representations the shared core owns: the version-1 portable game archive and the version-1 SQLite schema, plus the canonical-equivalence, duplicate-detection, import-validation, and compatibility rules that connect them. It answers most of the **Need to discuss** list in `MiniXiangqi/docs/game-data.md` and the import-limits item in `MiniXiangqi/docs/testing.md`.

Nothing here changes a repository. It is a workspace-only proposal for review; the accepted parts would later be lifted into `docs/game-data.md`, with two small edits required in `docs/xiangqi-rules.md` and `docs/engine-integration.md` (see §6).

**Boundary.** This draft owns persistent representations only: serialization, file format, canonical bytes, identifiers, DDL, migration, and import validation rules. C function signatures, handle models, error enums, and the threading contract are owned by the parallel C-interface draft. Where an API notion is needed here it is expressed as *behavior* ("import returns the existing record"), never as a signature.

Every section separates **Proven source facts** — statements traceable to an accepted contract section — from **Proposal**. Contract citations use `document § section`.

---

## 0. The shared identifier vocabulary

Everything below uses one style, matching the project's existing identifier conventions (`fixtures/rules/README.md § Identifiers` uses lowercase hyphenated tokens; `xiangqi-rules.md § Conformance fixtures` uses `red-wins`, `threefold-repetition`, etc.). All serialized identifiers are ASCII, lowercase, hyphen-separated, and never displayed to a user — display strings are Chinese and belong to `interaction-design.md`.

### Proven source facts

- Fixture game states are `ongoing`, `claimable-draw`, `red-wins`, `black-wins`, `draw`; fixture reasons are `checkmate`, `stalemate`, `threefold-repetition`, `perpetual-check`, `perpetual-chase` (`xiangqi-rules.md § Conformance fixtures`).
- Results are named by rule outcome — the violating side loses — never by the side to move at detection (same section).
- A neutral threefold repetition is claim-gated and never auto-commits; a unilateral perpetual violation is auto-terminal at the third sustained occurrence (`xiangqi-rules.md § Move-count, repetition, perpetual check, and perpetual chase`).
- Stalemate is a loss for the side that cannot move, not a draw (`xiangqi-rules.md § Ordinary game results`).
- A mutual same-class perpetual violation is a draw (same section). No reason identifier exists for it in the fixture vocabulary — see §6.1.
- Resignation exists only in human-versus-AI games and records a loss for the human (`product.md § Target-MVP play modes`).
- An ordinary ongoing game, including an unclaimed claimable repetition, is recorded with an ended-early reason and **no competitive result** (`game-data.md § Accepted save-before-mode behavior`; `product.md § Games and history`).
- The two play modes are Human versus AI and Free Play (`product.md § Target-MVP play modes`).
- The three AI levels are 快速 / 标准 / 深思 at `go movetime` 1000 / 3000 / 5000, and the selected level identifier and exact movetime are frozen with a created game (`engine-integration.md § Accepted search-profile policy`).
- The first-mover options are 我先手 / AI 先手 / 随机, and the resolved choice determines the human's side (`product.md § Target-MVP play modes`).
- `w` is Red, `b` is Black (`xiangqi-rules.md § Starting position, coordinates, and notation`).

### Proposal — the closed identifier sets

**Play mode** (`mode`)

| identifier | meaning |
|---|---|
| `human-vs-ai` | Human versus AI |
| `free-play` | Free Play |

**Side** (`human_side`, and the colour half of an outcome)

| identifier | meaning |
|---|---|
| `red` | the `w` side of a FEN; moves first |
| `black` | the `b` side of a FEN |

`red`/`black` rather than `w`/`b`: the archive is read by humans, and the outcome identifiers already spell the colours. FEN strings keep `w`/`b` because they are FENs.

**AI level** (`ai_level`)

| identifier | display | frozen `movetime` at v1 |
|---|---|---|
| `fast` | 快速 | 1000 |
| `standard` | 标准 | 3000 |
| `deep` | 深思 | 5000 |

**First-mover choice** (`first_mover_choice`)

| identifier | meaning |
|---|---|
| `human-first` | 我先手 |
| `ai-first` | AI 先手 |
| `random` | 随机; the resolved side is `human_side` |

**Outcome** (`outcome`) — the committed, user-visible result of a stored game

| identifier | meaning |
|---|---|
| `red-wins` | Red won |
| `black-wins` | Black won |
| `draw` | drawn |
| `none` | no competitive result (ended early) |

This is deliberately **not** the fixture state set. `ongoing` and `claimable-draw` are live rules states that can never be a stored game's committed outcome, and `none` is a user-scoped outcome with no rules analogue. The two vocabularies overlap on `red-wins`, `black-wins`, and `draw` and must keep those three spellings identical.

**End reason** (`end_reason`) — required whenever `outcome` is present

| identifier | outcome it may carry | origin |
|---|---|---|
| `checkmate` | `red-wins` / `black-wins` | rules, natural, user-confirmed |
| `stalemate` | `red-wins` / `black-wins` | rules, natural, user-confirmed |
| `perpetual-check` | `red-wins` / `black-wins` | rules, auto-terminal |
| `perpetual-chase` | `red-wins` / `black-wins` | rules, auto-terminal |
| `threefold-repetition` | `draw` | rules, **claim-gated** |
| `mutual-perpetual-check` | `draw` | rules, auto-terminal — *proposed addition, see §6.1* |
| `mutual-perpetual-chase` | `draw` | rules, auto-terminal — *proposed addition, see §6.1* |
| `resignation` | `red-wins` / `black-wins` | user action, `human-vs-ai` only |
| `ended-early` | `none` | 保存并继续 on a non-terminal game |

Two cross-field rules make this checkable at import and as a database constraint:

- `outcome = "none"` **if and only if** `end_reason = "ended-early"`.
- `outcome = "draw"` **if and only if** `end_reason` is one of the three draw reasons.

No separate "was it claimed?" flag is needed: in this ruleset the claim mechanism is fully determined by the reason. `threefold-repetition` is always a user claim; every other rules reason is automatic. If a later rules change ever makes a repetition draw automatic, that is a new archive version, not a silent reinterpretation.

**Provenance** (local library metadata; **not** an archive field — see §2.3)

| identifier | meaning |
|---|---|
| `locally-played` | this installation played the game and recorded it |
| `imported` | this record entered this library through the import operation |
| *(reserved)* `derived` | a future record created from an existing game, e.g. the excluded "start from a historical position" feature (`product.md § Target-MVP exclusions`) |

`derived` is reserved in the vocabulary but rejected by v1 code so that adding it later is not a schema-breaking change.

---

## 1. Archive format v1

### 1.1 Proven source facts

- The archive is independent of the database schema and is also the export/import interchange format; it must be portable across platforms and app versions (`game-data.md § Versioned game archive`).
- It must contain: archive format version; game identity and creation metadata; rules and variant version identifiers; initial position; ordered main-line moves; configuration needed to interpret the players and game; terminal information when completed (same section).
- Callers must not decode or modify the archive outside the core's codec (same section).
- One exported file contains one immutable History game; import processes one game file at a time (`game-data.md § Accepted MVP record behavior`).
- Exported files must round-trip across all supported platforms (`game-data.md § Import and export`).
- The importer must decode **without executing embedded content or resolving network references** (same section).
- Import and export must use explicit archive-version dispatch and preserve the ability to reject versions they cannot safely interpret (`game-data.md § Migration`).
- The archive does not preserve discarded moves, an undo count, hidden branches, or redo state (`game-data.md § Active games, history, and undo`).
- The app is fully offline and GPLv3, distributed internally only (`product.md § Product identity and distribution`).
- Canonical machine move notation is `<from><to>`, e.g. `b1b4`, with no suffix of any kind, and is canonical for fixtures, game archives, and the shared core interface (`xiangqi-rules.md § Starting position, coordinates, and notation`).
- The starting position is FEN `rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1`; a position record is a 6-field FEN (same section).
- Third-party repositories and imported game files are untrusted inputs (`MiniXiangqi/AGENTS.md § Change discipline`).
- Build inputs, revisions, and hashes must be pinned reproducibly (`engine-integration.md § Scope and ownership`).

### 1.2 Format evaluation

The payload is one game: at most a few thousand `<from><to>` strings plus about a dozen scalars. A 400-ply game is roughly 3 KB of text. Every candidate is technically adequate, so the decision is driven by the untrusted-input posture, reviewability, and dependency cost.

**A. Canonical JSON, one file — recommended.**

- Structurally satisfies "decode without executing embedded content or resolving network references": JSON has no includes, no references, no macros, no external entities, and no code. This requirement alone eliminates any format with an inclusion mechanism.
- Human-inspectable. This is an internal *education* app; a reviewer, a tester, or the user can open a file and read the moves without tooling, and a bug report can paste a file inline.
- Matches the project's existing JSON convention for reviewable executable artifacts (`fixtures/rules/*.json`).
- Cross-platform with zero endianness, alignment, or float-representation concerns — the format uses integers and strings only.
- Canonicalization is a solved problem (RFC 8785, JSON Canonicalization Scheme). JCS's only genuinely hard part is number serialization, which v1 removes by forbidding non-integer numbers.
- GPLv3-friendly: hardened JSON parsers exist under MIT/BSD/Apache-2.0, all GPLv3-compatible, so the licence adds no constraint. No parser needs to be hand-written.
- Diffable, so archive fixtures for migration tests (`testing.md § Game data`) are reviewable in Git.
- Cost: larger than binary (irrelevant at 3 KB) and a text parser is the attack surface (mitigated by hard streaming limits in §3.2 and a pinned, fuzzed parser).

**B. Zipped JSON container — rejected.**

- Its only advantage is room for future attachments (thumbnails, annotations), none of which are in the target MVP.
- It multiplies the untrusted-input surface for a 3 KB payload: compression bombs, path traversal in entry names, duplicate entries, encryption headers, and two independent size accountings.
- Canonicalization becomes a ZIP-level problem — entry order, per-entry timestamps, compression method, extra fields — which is materially harder than canonicalizing JSON.
- It adds a pinned third-party compression library, with its own licence and CVE stream, for negative benefit.
- It removes inspectability.

**C. Compact binary (custom TLV, or CBOR / FlatBuffers) — rejected for v1.**

- A hand-rolled TLV parser for untrusted input is the highest-risk option available and is the one thing the untrusted-input rule most argues against.
- CBOR has a good deterministic-encoding profile (RFC 8949 §4.2) but needs another pinned dependency and buys nothing at this size.
- Neither is inspectable; every debugging session needs a decoder, and migration fixtures stop being reviewable.
- Recorded for the future: if a later version ever needs per-move times, evaluations, or annotations at a scale where text hurts, deterministic CBOR is the natural upgrade and the v1 field set maps to it one-to-one.

**D. An existing chess/Xiangqi interchange format (PGN, XQF, WXF) — rejected.**

- None covers a 7×7 board, this variant's result taxonomy, or the per-game configuration the app must persist, so each would need private extensions anyway.
- There is no other Mini Xiangqi tool to interoperate with, so the interoperability argument is empty.
- PGN's grammar (comments, variations, NAGs, tag-pair escapes) is far larger than what a hostile-input parser should have to cover; XQF is a proprietary binary Chinese Xiangqi format and is a non-starter for this variant.

**Recommendation: A — a single canonical-JSON file.**

### 1.3 File identity

| aspect | proposal |
|---|---|
| filename extension | `.mxq` |
| Apple UTI | `com.ppppvz.minixiangqi.game`, conforming to `public.json` (and thus `public.data`), exported in the app's `Info.plist` with `public.filename-extension = mxq` |
| MIME type | `application/vnd.minixiangqi.game+json` (internal, unregistered; `application/json` is an acceptable fallback wherever a registered type is required) |
| Windows | `.mxq` association declared in the MSIX manifest with the same friendly name |
| in-band type check | the `archive_format` member must equal `"minixiangqi-game"`; JSON has no magic number, so this member is the authoritative check and the extension/UTI is only a hint |
| suggested default export filename | `minixiangqi-<yyyyMMdd-HHmmss>-<first 8 hex of game_id>.mxq`, e.g. `minixiangqi-20260727-091402-0198a6c1.mxq` — presentation, owned by the frontends |

`.mxq` is short, unclaimed by any widely deployed format, and unambiguous in a share sheet. Because distribution is internal only (`product.md § Product identity and distribution`), a global registry collision is not a blocker; on Apple platforms the UTI, not the extension, is the real type identity.

### 1.4 The v1 field set

Two levels: an **envelope** carrying version and identity, and a **`content`** object carrying everything that defines the game. The split exists so that "same identity" and "same content" can be compared independently, which is exactly what the accepted duplicate and conflict behaviours require (`game-data.md § Accepted MVP record behavior`).

Member names are chosen so that the canonical (alphabetical) ordering puts the version first: `archive_format` < `archive_version` < `content` < `game_id` < `origin`.

#### Envelope

| member | type | required | notes |
|---|---|---|---|
| `archive_format` | string | yes | exactly `"minixiangqi-game"` |
| `archive_version` | integer | yes | `1` for this specification; a single monotonically increasing integer, no minor component |
| `content` | object | yes | the identity-bearing payload; see below |
| `game_id` | string | yes | the game's stable identity; canonical lowercase 36-character UUID text |
| `origin` | object | yes | describes the **export event**, not the game; never hashed, never trusted |

#### `content`

| member | type | required | notes |
|---|---|---|---|
| `rules_id` | string | yes | `"minixiangqi"` — the ruleset of the rules contract, the same value and meaning as the fixtures' `variant` member (`fixtures/rules/README.md § Schema`), *not* an engine variant to select |
| `rules_version` | integer | yes | version of the accepted rules interpretation; `1` at freeze. See §6.2 — this number does not yet exist and must be declared by `xiangqi-rules.md` |
| `start_fen` | string | yes | 6-field FEN. **In v1 it must be exactly the frozen starting FEN** (see §3.3 stage 4 and shortlist decision 4) |
| `moves` | array of strings | yes | the ordered retained main line, each `^[a-g][1-7][a-g][1-7]$`; index 0 is Red's first move; may be empty |
| `mode` | string | yes | `human-vs-ai` \| `free-play` |
| `human_side` | string | iff `human-vs-ai` | `red` \| `black`; the *resolved* side |
| `ai_level` | string | iff `human-vs-ai` | `fast` \| `standard` \| `deep` |
| `ai_movetime_ms` | integer | iff `human-vs-ai` | the exact frozen `go movetime` value |
| `first_mover_choice` | string | iff `human-vs-ai` | `human-first` \| `ai-first` \| `random` |
| `outcome` | string | yes in a file | `red-wins` \| `black-wins` \| `draw` \| `none` |
| `end_reason` | string | yes in a file | from the §0 table; constrained against `outcome` |
| `started_at` | string | yes | RFC 3339 UTC instant, exactly `YYYY-MM-DDTHH:MM:SS.sssZ` |
| `ended_at` | string | yes in a file | same format; must be `>= started_at` |

Rationale for the less obvious choices:

- **`start_fen` is stored even though v1 permits only one value.** Omitting it would make the file non-self-describing and would make a later general-position version a breaking change rather than an additive one. The validator asserts the exact string.
- **No `move_count` member.** It is `moves` length. Storing a redundant count creates a second source of truth and a new inconsistency class for a hostile file to exploit. Move count is a *derived database column* (§4.2), not archive content.
- **`ai_movetime_ms` is stored beside `ai_level`** because the contract freezes both with the game and a later build may retune a level's time (`engine-integration.md § Accepted search-profile policy`). The importer therefore does **not** require the v1 level→time pairing; it requires only that both are present and in range. An archive written under a future retuning stays valid.
- **`first_mover_choice` is stored.** `human_side` alone cannot reconstruct whether the side was chosen or randomly resolved, and adding a member later costs an archive version. It slightly exceeds what any accepted contract requires — flagged in §6.9.
- **No engine, variant, or NNUE identifier.** `engine-integration.md § Accepted search-profile policy` versions those identifiers "so a saved *diagnostic record* can identify the configuration that produced a move". A diagnostic record is not the interchange format. Including a build identifier would make a game's serialized meaning depend on which binary produced the AI's replies, would make two otherwise-identical games hash differently, and would leak build detail into a shared file. The game's meaning derives from the rules contract only, which is what `rules_id` + `rules_version` name.
- **`origin` is regenerated on every export.** It describes the act of writing this file, so exporting the same record twice produces different *files* with identical `content` — which is precisely why the content hash (§2) covers `content` only.

#### `origin`

| member | type | required | notes |
|---|---|---|---|
| `app_version` | string | yes | the writing app's version string, informational only |
| `exported_at` | string | yes | RFC 3339 UTC instant of the export |

`origin` is never hashed, never compared, never displayed as authoritative, and **never used to set the local imported marker**. A hostile file can put anything here; nothing reads it except a diagnostic.

### 1.5 Worked example

Pretty-printed for review (the file on disk is the canonical one-line form):

```json
{
  "archive_format": "minixiangqi-game",
  "archive_version": 1,
  "content": {
    "ai_level": "standard",
    "ai_movetime_ms": 3000,
    "end_reason": "ended-early",
    "ended_at": "2026-07-27T09:14:02.006Z",
    "first_mover_choice": "human-first",
    "human_side": "red",
    "mode": "human-vs-ai",
    "moves": ["d2d3", "d6d5", "d3d4", "d5d4"],
    "outcome": "none",
    "rules_id": "minixiangqi",
    "rules_version": 1,
    "start_fen": "rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1",
    "started_at": "2026-07-27T09:12:33.140Z"
  },
  "game_id": "0198a6c1-4f20-7c3d-9b41-5e8f2a6d0c17",
  "origin": {
    "app_version": "0.1.0 (12)",
    "exported_at": "2026-07-27T09:20:11.771Z"
  }
}
```

The move sequence is a verified-legal one: `d2d3 d6d5 d3d4 d5d4` was executed against both engine variants during the FEN/notation freeze (`discussion-drafts/fen-notation-fixtures-draft.md` §5), leaving an ongoing position — consistent with `outcome: "none"`, `end_reason: "ended-early"`.

Canonical `content` bytes (385 bytes, one line, no trailing newline):

```
{"ai_level":"standard","ai_movetime_ms":3000,"end_reason":"ended-early","ended_at":"2026-07-27T09:14:02.006Z","first_mover_choice":"human-first","human_side":"red","mode":"human-vs-ai","moves":["d2d3","d6d5","d3d4","d5d4"],"outcome":"none","rules_id":"minixiangqi","rules_version":1,"start_fen":"rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1","started_at":"2026-07-27T09:12:33.140Z"}
```

`content_sha256` = `dddfc5f071a16edde15ef84a4792115ba60aee673720d0db2778a0247c7b70db`, reproducible with `printf '%s' '<the line above>' | shasum -a 256`.

### 1.6 Deliberate v1 exclusions

| excluded | why |
|---|---|
| pin state | Pinning is mutable *local library* metadata, not game content (`game-data.md § Active games, history, and undo`; `interaction-design.md § History library`). Including it would break duplicate detection — see §2.3. |
| local History-added time | Local ordering key; the contract explicitly separates it from the original game dates (`game-data.md § Accepted MVP record behavior`). |
| provenance / imported marker | Describes how a record entered *this* library, which is knowable locally without trusting the file. See §2.3. |
| per-move timing, evaluations, engine PV | No accepted surface consumes them; they would multiply file size and the untrusted-input surface, and they would make identical games hash differently across devices. |
| comments, annotations, tags, variations | The MVP has no tags, no editing, and no branches (`product.md § Target-MVP exclusions`). |
| discarded moves, undo count, redo state | Explicitly excluded by `game-data.md § Active games, history, and undo`. |
| resulting FEN / any derived position | Derivable by replay; a stored copy is a second source of truth a hostile file could contradict. |
| the pre-start draft, the transient requested mode | Never persisted (`game-data.md § Accepted pre-start state behavior`). |
| board orientation, autoplay speed | Presentation only (`interaction-design.md § Board orientation`, `§ History replay`). |
| engine/NNUE/variant build identifiers | §1.4. |
| any URL, path, or reference to another file | The importer must resolve no external references. |

---

## 2. Canonical equivalence and duplicate detection

### 2.1 Proven source facts

- If a validated import has the same stable identity **and** the same game content as an existing record, the core returns that existing record instead of inserting a duplicate (`game-data.md § Accepted MVP record behavior`).
- If a validated import has the same stable identity but **different** game content, the core rejects the file as an identity conflict without changing persistent state (same section).
- Product-level phrasing: an exact duplicate does not create another record and offers access to the existing one; a same-identity/different-content file is rejected as a conflict (`product.md § Games and history`; `interaction-design.md § History library`).
- Pinning changes only mutable library metadata (`game-data.md § Active games, history, and undo`).
- Two position records denote the same position exactly when piece placement and side to move are equal (`xiangqi-rules.md § Starting position, coordinates, and notation`) — position identity, distinct from *game* identity defined here.

### 2.2 Canonical byte rules

Canonicalization follows RFC 8785 (JCS) with v1 restrictions that remove its hard cases. It applies to any JSON object the format defines, and is used for two things: writing a file, and computing a hash.

1. **Encoding.** UTF-8. The writer never emits a byte-order mark. The reader tolerates and discards exactly one leading UTF-8 BOM (Windows tooling adds them) and rejects any other leading bytes.
2. **Member order.** Object members are serialized in ascending order of their names' UTF-16 code-unit sequences (JCS §3.2.3). All v1 member names match `^[a-z][a-z0-9_]*$`, so code-unit order, code-point order, and byte order coincide; an implementation may sort bytes.
3. **Whitespace.** None. No space after `:` or `,`, no indentation, no line breaks inside the serialization.
4. **Numbers.** Integers only, in the range `[-(2^53-1), 2^53-1]`. No leading `+`, no leading zeros other than `0` itself, no `-0`, no fraction, no exponent. Non-integer numbers, `NaN`, and `Infinity` are rejected at parse. (Every v1 number is small; the 2^53 bound keeps every conforming reader exact.)
5. **Strings.** Minimal escaping (JCS §3.2.2.2): escape only `"` as `\"`, `\` as `\\`, and C0 controls, using `\b \f \n \r \t` where defined and otherwise `\u00xx` with lowercase hex. Never escape `/`. Never use `\uXXXX` for a character that can be written literally. Every v1 string value is ASCII by construction, so in practice no escape is ever emitted; the rule exists so the codec stays correct if a later version adds free text.
6. **Booleans and null.** v1 uses no booleans. `null` is **rejected everywhere**, including as a member value. Absent means absent. (This deliberately diverges from the fixture JSON convention, which uses explicit `null` placeholders — fixtures are reviewed by humans and never hashed; archives are hashed, and the present-null / absent ambiguity is exactly the kind of thing that makes equality subtly wrong.)
7. **Arrays.** Order is significant and preserved; `moves` is the game.
8. **Optional members.** Omitted entirely when not applicable. A present member is never equivalent to an absent one.
9. **Duplicate member names.** Rejected at parse, not last-wins.
10. **The hash** is SHA-256 over exactly the canonical bytes of the `content` object, with no framing, no length prefix, and no trailing newline. All 32 bytes are stored; no truncation. SHA-256 is already the project's pinning hash (`engine-integration.md § Accepted NNUE handling policy`), so no new primitive is introduced.
11. **The file** is the canonical serialization of the whole envelope object followed by a single `LF` (`0x0A`). Readers are **lenient in whitespace and member order and strict in structure**: they accept any insignificant whitespace and any ordering, then re-canonicalize before hashing. This means a file that has been through a text editor still imports and still compares correctly, while equality remains a byte comparison.

Consequence worth stating: because the store persists the *canonical re-serialization* rather than the received bytes, a file this app wrote always round-trips byte-identically, and a hand-edited-but-equivalent file converges to the same bytes on import.

### 2.3 Identity, content, and volatile fields

| class | fields | affects `game_id` match | affects content hash |
|---|---|---|---|
| **stable identity** | `game_id` | yes | **no** |
| **game content** | every member of `content` | no | **yes** |
| **volatile / envelope** | `archive_format`, `origin.app_version`, `origin.exported_at` | no | no |
| **local library metadata** | pin state, History-added time, provenance/imported marker, database rowid, the 删除前确认 preference | no | no |
| **presentation state** | board orientation, autoplay speed, replay cursor | no | no |
| **version** | `archive_version` | no | compared separately (§2.4) |

**Why pin state must not be in the archive or the comparison.** Suppose it were. A user exports a game, pins it, exports again: the two files now differ in content. Importing the second onto a device that already holds the first would be classified as a same-identity/different-content **conflict** — the accepted rejection path — for a game that has not changed at all. Pin is a per-library organisational bit and would corrupt the very rule it participates in. The same argument applies to History-added time and to provenance. Recommendation: **no local library metadata in exports and none in the comparison.**

**Why identity must not be content-derived.** A content hash as the identity would make "same identity, different content" impossible by construction and would delete the accepted identity-conflict behaviour (`game-data.md § Accepted MVP record behavior`). It would also merge two genuinely distinct games that happen to be move-identical — a real possibility for short instructional games. Identity is therefore an independently generated opaque value.

**Identity scheme.** UUID version 7 (RFC 9562), serialized as canonical lowercase 36-character hyphenated text, generated by the core from an OS CSPRNG at game creation, frozen for the life of the game, and **never regenerated on import or re-export**.

- v7 over v4: the 48-bit millisecond prefix gives locality in the unique index and makes log and file-name correlation easy while debugging. Its only disclosure is the creation time, which the archive states outright in `started_at`. If that disclosure were ever unwanted, v4 is a drop-in replacement with no other change.
- Never `rand()`, never clock-only seeding.
- **Collision stance.** 74 random bits per millisecond; for an app that creates a handful of games per day, collision probability is negligible. It is nonetheless handled rather than assumed away, and it degrades into behaviour that is already specified: locally, `UNIQUE(game_uid)` turns a collision into a hard constraint failure, and creation retries with a fresh id (bounded retries, then a typed failure — which the accepted contract already covers, since a failed creation creates no game); on import, a collision presents exactly as the accepted identity-conflict rejection. **No new user-visible case is introduced by a collision.**

### 2.4 The comparison procedure

After a file has passed every validation stage in §3, the core holds `(game_id, archive_version, canonical content bytes, content_sha256)`. Inside one write transaction it looks the identity up in a single indexed read:

| lookup result | classification | behaviour |
|---|---|---|
| no row with this `game_uid` | new game | insert one History record |
| row exists, same `archive_version`, same hash **and** same bytes | exact duplicate | change nothing; return the existing record so the UI can offer to open it |
| row exists, same `archive_version`, different hash | identity conflict | reject; change nothing |
| row exists, different `archive_version` | identity conflict (conservative) | reject; change nothing — see §6.5 |
| row exists **and is the active game** | identity conflict | reject; change nothing, and never touch the active game |

Notes:

- **Hash first, then bytes.** The hash is an index, the bytes are the truth: on a hash match the core also compares the ~400-byte canonical blob. That is free at this size and removes every collision argument from the correctness story.
- **The lookup is O(1)**, an index seek on `game_uid` plus one comparison — not a scan over content.
- **The active row participates.** An active game has no committed outcome, so a terminal imported file with the same identity can never be content-equal to it; the match is always a conflict, and import never creates or replaces the active game (`game-data.md § Accepted MVP record behavior`).
- **Different identity + identical content is two records, by design.** This is what the accepted rule says (identity *and* content must match). Two people who play the same short instructional game each keep their own record.
- **Re-importing your own export is a no-op** that returns the existing record, because export preserves `game_id` and reproduces `content` byte-for-byte.
- **Dependency on the never-rewrite rule.** Byte equality across devices only holds because a stored archive's bytes are never re-encoded (§4.6, §5). That rule is load-bearing for duplicate detection, not merely conservative.

---

## 3. Import validation pipeline

### 3.1 Proven source facts

Before saving, the importer must (`game-data.md § Import and export`):

- enforce file-size and structural limits;
- reject unsupported versions and malformed fields;
- decode without executing embedded content or resolving network references;
- validate the initial position, ordered moves, and terminal claim through the rules facade;
- reject inconsistent or incomplete records with a user-facing error;
- create no persistent objects until validation succeeds.

Further:

- Import must never partially commit a game (same section).
- Importing must not contact a server (same section).
- Repetition and violation state derive from the game's complete move history; a bare position carries no prior occurrences (`xiangqi-rules.md § Move-count, repetition, perpetual check, and perpetual chase`).
- The rules facade is the authoritative offline adjudicator and is deterministic over position and history (`xiangqi-rules.md § Runtime rules authority`).
- Import size, nesting, move-count, and processing-time limits are an open item (`testing.md § Need to discuss`).
- Tests must reject oversized, malformed, unsupported, inconsistent, and partially valid imports without partial persistence (`testing.md § Game data`).

### 3.2 Limits

All limits are enforced **while** reading, not after building a tree, so a hostile file cannot force a large allocation before it is refused.

| limit | value | justification |
|---|---|---|
| maximum file bytes | 1 048 576 (1 MiB) | a maximal 10 000-ply game is ≈ 75 KB; this is ~14× headroom and still trivially bounded |
| maximum plies (`moves` length) | 10 000 | ≈ 3 hours of continuous Free Play at one move per second; see §6.6 — no accepted contract bounds a live game's length, so this must be at least as large as any game the app can produce |
| maximum JSON nesting depth | 4 | v1 needs 3 (envelope → `content` → `moves`); 4 gives one level of slack and forbids everything else |
| maximum members per object | 32 | v1's largest object has 13 members |
| maximum array elements | 10 000 | the ply cap |
| maximum string length | 256 bytes | v1's longest string is the 44-byte FEN |
| maximum total decoded bytes | 1 MiB | ties allocation to the file cap |
| validation wall-clock budget | 2 000 ms for a maximal file on the slowest supported device | import runs off the UI thread and is cancellable; exceeding the budget is a typed timeout rejection, never a partial commit |

These values are parameters, not contract semantics; changing them does not change the format.

### 3.3 Ordered stages

Every stage runs to a decision before the next begins. **Nothing touches the database until stage 6.** Stages 0–5 have no persistent side effects at all — no temporary rows, no staging table, no partial file.

**Stage 0 — transport and size.** Refuse a source larger than the byte cap without reading it fully. Read through a bounded reader that cannot exceed the cap.

**Stage 1 — encoding and syntax.** Decode UTF-8 strictly (reject overlong forms, surrogates, and truncated sequences); discard at most one leading BOM. Parse JSON with every §3.2 limit applied during parsing. Reject: duplicate member names, `null`, non-integer numbers, numbers outside the safe range, leading zeros, exponents, `NaN`/`Infinity`, and trailing content after the top-level value.

**Stage 2 — envelope and version dispatch.** Require `archive_format == "minixiangqi-game"`. Read `archive_version`. If it is not in the set of versions this build ships a decoder for, reject with the **unsupported-version** class and a message that says the file was made by a different version of the app — never a generic "corrupt file". Dispatch the rest of validation to that version's decoder (`game-data.md § Migration` requires explicit version dispatch). Reject any member not defined by that version — see §5 for why v1 is strict about unknown members.

**Stage 3 — field validity (no rules engine yet).** Purely structural and vocabulary checks:

- every required member present with the exact declared type; the conditional `human-vs-ai` members present exactly when `mode == "human-vs-ai"`;
- `game_id` in canonical lowercase 36-character UUID form (reject braces, URN prefixes, uppercase, and non-canonical spacing);
- `rules_id == "minixiangqi"` and `rules_version` in this build's supported set;
- `start_fen` structurally a 6-field FEN over the 7×7 alphabet, third and fourth fields `-`, counters non-negative integers;
- every move matches `^[a-g][1-7][a-g][1-7]$` with origin ≠ destination;
- `mode`, `human_side`, `ai_level`, `first_mover_choice`, `outcome`, `end_reason` in their closed vocabularies; `ai_movetime_ms` an integer in `[100, 600000]` (a range check, **not** the v1 level→time pairing — see §1.4);
- the two cross-field rules of §0: `none` ⇔ `ended-early`, and `draw` ⇔ a draw reason;
- `end_reason == "resignation"` implies `mode == "human-vs-ai"`;
- timestamps parse as RFC 3339 UTC in the exact declared form and `ended_at >= started_at`. Plausibility of the absolute date is **not** checked: a clock-skewed device that legitimately produced a file must not have it rejected.

**Stage 4 — rules-level validation, through the rules facade.** This is the authoritative stage; nothing above it is allowed to guess at legality.

1. **Initial position.** v1 requires `start_fen` to be **exactly** the frozen starting FEN `rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1`. Rationale in shortlist decision 4 and §6.3; the practical effect is that the facing-kings question cannot arise for a v1 file, because the only permitted initial position is a legal one.
2. **Move legality in sequence.** Replay every move from the initial position through the rules facade. Each must be in that position's legal set at its turn. A single failure rejects the file. The facade is deterministic over position and history, so this is reproducible across platforms.
3. **Terminal consistency.** Ask the facade for the state at the final position and require agreement with the recorded pair:

| `end_reason` / `outcome` | required facade state at the final position |
|---|---|
| `checkmate` → a win | terminal, `checkmate`, same winning side |
| `stalemate` → a win | terminal, `stalemate`, same winning side |
| `perpetual-check` → a win | terminal, `perpetual-check`, loss attributed to the same violating side |
| `perpetual-chase` → a win | terminal, `perpetual-chase`, loss attributed to the same violating side |
| `mutual-perpetual-*` → `draw` | terminal, the corresponding mutual violation *(pending §6.1)* |
| `threefold-repetition` → `draw` | **`claimable-draw`**, not terminal — the draw is a user claim, so the facade must report eligibility, not a committed result |
| `resignation` → a win for the non-human side | `ongoing` **or** `claimable-draw`; a resignation cannot follow a natural terminal position, and the winner must be the side opposite `human_side` |
| `ended-early` → `none` | `ongoing` **or** `claimable-draw`; **never** a natural terminal state, because the contract records an unconfirmed natural terminal game with its actual result rather than as ended early (`product.md § Games and history`) |

The `threefold-repetition` and `ended-early` rows are the two that catch a forged or corrupted record most sharply, and both fall directly out of accepted behaviour. Because the full history is replayed, repetition and violation state are available exactly as the rules contract requires; a bare final FEN could not support any of these checks.

**Stage 5 — canonicalize and hash.** Re-serialize `content` canonically (§2.2) and compute `content_sha256`. Nothing from the received byte layout survives this step except meaning.

**Stage 6 — the single write transaction.** Perform the §2.4 comparison and, only in the "new game" case, insert exactly one row. This is the first and only stage that writes. If it fails for any storage reason, the transaction rolls back and no record exists.

Placing every expensive check *before* the transaction keeps the write window to a few microseconds, which matters because the store is single-writer (§4.5).

### 3.4 Failure classes and behaviour

Every class below aborts atomically with no persistent change. The classes are validation outcomes, not an error enum — the error taxonomy is the C-interface draft's to define; these are the distinctions it must be able to carry.

| class | raised by | user-visible? |
|---|---|---|
| `too-large` | stage 0 | yes, distinct message |
| `malformed` | stages 1, 3 (encoding, JSON, limits, field types) | yes, one generic "not a valid game file" |
| `unsupported-version` | stage 2 | **yes, distinct message** — must not be reported as corruption |
| `illegal-move` | stage 4.2 | yes, folded into "the file's game is not valid" |
| `inconsistent-result` | stage 4.3 | yes, same message as above |
| `illegal-position` | stage 4.1 (v1: any non-standard start; future: position legality) | same |
| `identity-conflict` | stage 6 | **yes, distinct message** (`interaction-design.md § History library`) |
| `storage-failure` | stage 6 | yes, retryable |
| `timeout` | any stage past the budget | yes, retryable |
| *(not a failure)* `duplicate` | stage 6 | not an error: returns the existing record and offers to open it |

Three of these are separately visible to the user because the accepted UI already distinguishes them: duplicate (offers the existing record), conflict (explained rejection), and everything else (a general invalid-file error). Exact copy is `interaction-design.md`'s to own; suggested Chinese strings appear in §5.

---

## 4. SQLite schema v1

### 4.1 Proven source facts

- The core owns persistence through an embedded SQLite library store behind a repository boundary; frontends never touch the database directly (`game-data.md § Storage model`).
- The frontend supplies the store's location at startup (same section).
- The pinned SQLite version ships inside the core on every platform; the core does not depend on a system SQLite (same section).
- The conceptual model is one logical `GameLibrary` with an optional reference to the single active game, and one `StoredGame` per **active or History** game (same section).
- `StoredGame` carries queryable summary fields — stable identity, dates, play mode, participants, result summary, imported provenance, and pinned state — plus a versioned archive blob containing the complete replayable game record (same section).
- The core enforces the single-library and single-active-game invariants even where the schema cannot express them as constraints (same section).
- The core commits explicitly after every accepted move, undo, game completion, import, deletion, and other durable state change; a committed move is the recovery boundary after app exit or interruption (`game-data.md § Saving and starting another mode`).
- 保存并继续 places the active game in History and clears the active-game reference **in one atomic transaction** (`game-data.md § Accepted save-before-mode behavior`).
- A failed archive operation leaves the previously committed active game intact (same section).
- History games have immutable game content; pinning is mutable metadata; a record may be permanently deleted; a failed deletion leaves the record intact (`game-data.md § Active games, history, and undo`, `§ Import and export`).
- History sorts pinned before unpinned, then by a local History-added time, most recent first; the original game dates remain separate metadata (`game-data.md § Accepted MVP record behavior`).
- History retains queryable summaries for date, mode, result or end reason, move count, human side when applicable, and imported provenance (same section; `interaction-design.md § History library`).
- The data model must not assume multiple devices or concurrent writers (`game-data.md § Local-only boundary`).
- The core owns schema versioning and migrates forward from every schema shipped in an internal build; a database migration must not silently change the meaning of an existing archive (`game-data.md § Migration`).
- SQLite is an internal, replaceable component and is not visible through the C interface (`architecture.md § Dependency direction`).
- The core is responsible for its own internal synchronization (`architecture.md § Concurrency and lifecycle`).

### 4.2 DDL

Three tables. The DDL uses `STRICT` tables so a type mismatch is an error rather than a silent affinity conversion — appropriate for a correctness-critical store, and the reason the SQLite floor is 3.37.0 (§4.5).

```sql
-- Connection setup. journal_mode is persistent in the database header;
-- every other pragma here is PER CONNECTION and must be re-applied on every open.
PRAGMA journal_mode        = WAL;
PRAGMA foreign_keys        = ON;
PRAGMA synchronous         = FULL;
PRAGMA busy_timeout        = 5000;
PRAGMA journal_size_limit  = 1048576;
PRAGMA temp_store          = MEMORY;
PRAGMA trusted_schema      = OFF;
PRAGMA user_version        = 1;      -- the authoritative schema version

-- ---------------------------------------------------------------- meta
-- Non-authoritative bookkeeping. Migration NEVER reads this table.
CREATE TABLE meta (
  key   TEXT NOT NULL PRIMARY KEY,
  value TEXT NOT NULL
) STRICT, WITHOUT ROWID;
-- seeded keys: store_created_at_ms, store_created_by_app_version,
--              store_created_by_sqlite_version, last_opened_by_app_version

-- ---------------------------------------------------------------- game
-- One row per StoredGame: the active game (outcome IS NULL) or a History
-- record (outcome IS NOT NULL). Columns after content_json are DERIVED from
-- content_json and exist only to answer History-list queries.
CREATE TABLE game (
  id                   INTEGER NOT NULL PRIMARY KEY,   -- local surrogate; never exported
  game_uid             TEXT    NOT NULL,               -- stable identity, canonical lowercase UUIDv7
  archive_version      INTEGER NOT NULL,               -- archive format version of content_json
  content_json         BLOB    NOT NULL,               -- canonical UTF-8 bytes of the `content` object
  content_sha256       BLOB    NOT NULL,               -- 32 raw bytes over content_json

  -- derived summary (recomputable from content_json; never hand-edited)
  rules_id             TEXT    NOT NULL,
  rules_version        INTEGER NOT NULL,
  start_fen            TEXT    NOT NULL,
  mode                 TEXT    NOT NULL,
  human_side           TEXT,
  ai_level             TEXT,
  ai_movetime_ms       INTEGER,
  first_mover_choice   TEXT,
  move_count           INTEGER NOT NULL,               -- plies; = length(moves)
  outcome              TEXT,                           -- NULL exactly while the game is active
  end_reason           TEXT,
  started_at_ms        INTEGER NOT NULL,               -- epoch milliseconds, UTC
  ended_at_ms          INTEGER,

  -- local library metadata; never exported, never hashed
  provenance           TEXT    NOT NULL,
  pinned               INTEGER NOT NULL DEFAULT 0,
  history_added_at_ms  INTEGER,                        -- NULL exactly while the game is active
  revision             INTEGER NOT NULL DEFAULT 0,     -- monotonic per-game revision counter

  CONSTRAINT ck_uid_form      CHECK (length(game_uid) = 36 AND game_uid = lower(game_uid)),
  CONSTRAINT ck_hash_len      CHECK (length(content_sha256) = 32),
  CONSTRAINT ck_arch_version  CHECK (archive_version >= 1),
  CONSTRAINT ck_rules_id      CHECK (rules_id = 'minixiangqi'),
  CONSTRAINT ck_rules_version CHECK (rules_version >= 1),
  CONSTRAINT ck_move_count    CHECK (move_count >= 0),
  CONSTRAINT ck_mode          CHECK (mode IN ('human-vs-ai', 'free-play')),
  CONSTRAINT ck_hvai_fields   CHECK ((mode = 'human-vs-ai') =
                                     (human_side         IS NOT NULL AND
                                      ai_level           IS NOT NULL AND
                                      ai_movetime_ms     IS NOT NULL AND
                                      first_mover_choice IS NOT NULL)),
  CONSTRAINT ck_human_side    CHECK (human_side IS NULL OR human_side IN ('red', 'black')),
  CONSTRAINT ck_ai_level      CHECK (ai_level IS NULL OR ai_level IN ('fast', 'standard', 'deep')),
  CONSTRAINT ck_ai_movetime   CHECK (ai_movetime_ms IS NULL OR ai_movetime_ms BETWEEN 100 AND 600000),
  CONSTRAINT ck_first_mover   CHECK (first_mover_choice IS NULL OR
                                     first_mover_choice IN ('human-first', 'ai-first', 'random')),
  CONSTRAINT ck_outcome       CHECK (outcome IS NULL OR
                                     outcome IN ('red-wins', 'black-wins', 'draw', 'none')),
  CONSTRAINT ck_end_reason    CHECK (end_reason IS NULL OR end_reason IN
                                     ('checkmate', 'stalemate', 'threefold-repetition',
                                      'perpetual-check', 'perpetual-chase',
                                      'mutual-perpetual-check', 'mutual-perpetual-chase',
                                      'resignation', 'ended-early')),
  CONSTRAINT ck_terminal_pair CHECK ((outcome IS NULL) = (end_reason IS NULL)),
  CONSTRAINT ck_none_early    CHECK (outcome IS NULL OR
                                     ((outcome = 'none') = (end_reason = 'ended-early'))),
  CONSTRAINT ck_draw_reasons  CHECK (outcome IS NULL OR outcome <> 'draw' OR
                                     end_reason IN ('threefold-repetition',
                                                    'mutual-perpetual-check',
                                                    'mutual-perpetual-chase')),
  CONSTRAINT ck_win_reasons   CHECK (outcome IS NULL OR outcome NOT IN ('red-wins', 'black-wins') OR
                                     end_reason IN ('checkmate', 'stalemate', 'perpetual-check',
                                                    'perpetual-chase', 'resignation')),
  CONSTRAINT ck_resign_mode   CHECK (end_reason IS NULL OR end_reason <> 'resignation' OR
                                     mode = 'human-vs-ai'),
  CONSTRAINT ck_history_pair  CHECK ((history_added_at_ms IS NULL) = (outcome IS NULL)),
  CONSTRAINT ck_ended_pair    CHECK ((ended_at_ms IS NULL) = (outcome IS NULL)),
  CONSTRAINT ck_time_order    CHECK (ended_at_ms IS NULL OR ended_at_ms >= started_at_ms),
  CONSTRAINT ck_provenance    CHECK (provenance IN ('locally-played', 'imported')),
  CONSTRAINT ck_pinned        CHECK (pinned IN (0, 1)),
  CONSTRAINT ck_revision      CHECK (revision >= 0)
) STRICT;

CREATE UNIQUE INDEX ux_game_uid ON game (game_uid);

-- The accepted History ordering, fully covered and partial so the active game
-- is structurally excluded from the History list.
CREATE INDEX ix_game_history_order
  ON game (pinned DESC, history_added_at_ms DESC, id DESC)
  WHERE history_added_at_ms IS NOT NULL;

-- ------------------------------------------------------------- library
-- Exactly one row, forever.
CREATE TABLE library (
  id             INTEGER NOT NULL PRIMARY KEY CHECK (id = 1),
  created_at_ms  INTEGER NOT NULL,
  active_game_id INTEGER REFERENCES game(id) ON DELETE RESTRICT ON UPDATE RESTRICT
) STRICT;

INSERT INTO library (id, created_at_ms, active_game_id) VALUES (1, :now_ms, NULL);

-- ------------------------------------------------------------ triggers
-- The active reference may only point at a non-archived game.
CREATE TRIGGER trg_library_active_must_be_live
BEFORE UPDATE OF active_game_id ON library
WHEN NEW.active_game_id IS NOT NULL
 AND (SELECT history_added_at_ms FROM game WHERE id = NEW.active_game_id) IS NOT NULL
BEGIN SELECT RAISE(ABORT, 'active game reference must point at a live game'); END;

-- Archiving requires the active reference to be cleared first, in the same
-- transaction. This is what makes the archive-and-clear ordering unfakeable.
CREATE TRIGGER trg_game_archive_requires_cleared_active
BEFORE UPDATE OF history_added_at_ms ON game
WHEN NEW.history_added_at_ms IS NOT NULL
 AND OLD.history_added_at_ms IS NULL
 AND (SELECT active_game_id FROM library WHERE id = 1) = NEW.id
BEGIN SELECT RAISE(ABORT, 'clear the active reference before archiving'); END;

-- History game content is immutable. Only `pinned` may change after archiving.
CREATE TRIGGER trg_game_history_immutable
BEFORE UPDATE OF game_uid, archive_version, content_json, content_sha256,
                 rules_id, rules_version, start_fen, mode, human_side, ai_level,
                 ai_movetime_ms, first_mover_choice, move_count, outcome,
                 end_reason, started_at_ms, ended_at_ms, history_added_at_ms,
                 provenance, revision
ON game
WHEN OLD.history_added_at_ms IS NOT NULL
BEGIN SELECT RAISE(ABORT, 'history game content is immutable'); END;

CREATE TRIGGER trg_library_row_is_permanent
BEFORE DELETE ON library
BEGIN SELECT RAISE(ABORT, 'the library row is permanent'); END;
```

**The History list query**, which the partial index covers end to end:

```sql
SELECT id, game_uid, mode, human_side, outcome, end_reason, move_count,
       provenance, pinned, started_at_ms, ended_at_ms, history_added_at_ms
  FROM game
 WHERE history_added_at_ms IS NOT NULL
 ORDER BY pinned DESC, history_added_at_ms DESC, id DESC;
```

`id DESC` is a deterministic tie-break for two records added in the same millisecond. At MVP scale (hundreds to low thousands of records) no covering-index extension is needed; adding the projected columns to the index would be premature.

**Where the archive blob lives.** In `game.content_json`, in the same row as its summary. Not a side table, not an external file. One row is written and read atomically, there are no orphaned files to reconcile after a crash, and at a few kilobytes the blob is well below the size at which external storage starts to pay. External blobs would also reintroduce exactly the partial-commit hazard the import rule forbids.

**Derived versus denormalized.** `content_json` is the single source of truth for game meaning. Every column after it is a projection that exists to make the History list one indexed scan. The invariant is: **every derived column must be exactly recomputable from `content_json`, and a migration recomputes rather than edits them.** `move_count` is the clearest case — it is not in the archive at all (§1.4) and exists only here.

**No moves table.** Nothing in the product queries an individual ply; replay reads the whole game. A per-ply table would add thousands of rows per game, a second representation of the move line to keep consistent, and no capability. Every accepted move rewrites one small blob, which keeps "commit after every accepted move" a single-row `UPDATE`.

**No preferences table in v1.** Where Settings preferences live is an open question owned elsewhere (`game-data.md § Need to discuss`). If the answer is "the shared store", a `preference(key TEXT PRIMARY KEY, value TEXT NOT NULL) STRICT, WITHOUT ROWID` table is a purely additive schema step.

### 4.3 Invariant enforcement map

| invariant | enforced by |
|---|---|
| exactly one library | `CHECK (id = 1)` + the seed `INSERT` + `trg_library_row_is_permanent` — **schema** |
| at most one active game | a single nullable `library.active_game_id` column — **structural** |
| the active reference is never dangling | `FOREIGN KEY … ON DELETE RESTRICT` — **schema** |
| the active reference never points at a History record | `trg_library_active_must_be_live` — **schema** |
| creating a second active game is impossible | `UPDATE library SET active_game_id = … WHERE id = 1 AND active_game_id IS NULL` + a `changes() = 1` assertion — **statement shape** |
| an active row has no committed result | `ck_history_pair`, `ck_ended_pair` — **schema** |
| a History row has a complete, self-consistent result | `ck_terminal_pair`, `ck_none_early`, `ck_draw_reasons`, `ck_win_reasons`, `ck_resign_mode` — **schema** |
| archive-and-clear happens in this order, atomically | `trg_game_archive_requires_cleared_active` + one transaction — **schema + shape** |
| History game content is immutable | `trg_game_history_immutable` — **schema** |
| pin is the only mutable field of a History record | same trigger (every other column is in its guarded list) — **schema** |
| stable identity is unique | `ux_game_uid` — **schema** |
| the mode↔configuration relationship | `ck_hvai_fields` — **schema** |
| derived columns match `content_json` | **core logic**: one encode/decode path writes both; a `verify_invariants()` routine recomputes every derived column from the blob and is run by the test suite, after every migration, and behind a diagnostic action |
| ended-early is never recorded on a naturally terminal position | **core logic** at classification time and at §3.3 stage 4.3 — not expressible in SQL, which cannot replay a game |
| a game's move line is legal | **core logic** (rules facade); SQL sees only opaque bytes |
| exactly one writer | **core logic** (§4.5) |

The pattern: the schema catches every *shape* violation, including the ordering of archive-and-clear; the core catches every violation that needs the rules facade or the codec. Nothing correctness-critical relies on both.

### 4.4 Transaction shapes

Every statement below binds all values as parameters. **No file-derived or user-derived text is ever concatenated into SQL.**

**Create the active game** (only 开始对局 reaches here):

```sql
BEGIN IMMEDIATE;
  INSERT INTO game (game_uid, archive_version, content_json, content_sha256,
                    rules_id, rules_version, start_fen, mode, human_side, ai_level,
                    ai_movetime_ms, first_mover_choice, move_count,
                    started_at_ms, provenance, revision)
  VALUES (:uid, :av, :blob, :hash, 'minixiangqi', :rv, :fen, :mode, :side, :level,
          :movetime, :first_mover, 0, :now_ms, 'locally-played', 0)
  RETURNING id;                                   -- :new_id
  UPDATE library SET active_game_id = :new_id
   WHERE id = 1 AND active_game_id IS NULL;       -- assert changes() = 1
COMMIT;
```

The `AND active_game_id IS NULL` guard makes "there is at most one active game" a property of the statement, not of a code path that could be reordered.

**Commit an accepted move or an undo** (the same shape; undo shortens `moves`):

```sql
BEGIN IMMEDIATE;
  UPDATE game
     SET content_json = :blob, content_sha256 = :hash,
         move_count = :plies, revision = revision + 1
   WHERE id = (SELECT active_game_id FROM library WHERE id = 1);  -- assert changes() = 1
COMMIT;
```

`revision` is persisted rather than kept only in memory so a relaunch cannot reuse a revision number that an outstanding stale callback might still carry. Its consumer contract — how search requests carry and check it — belongs to the C-interface draft.

**Archive and clear (保存并继续, result confirmation, resignation confirmation, draw claim)** — one transaction, exactly as the accepted behaviour requires:

```sql
BEGIN IMMEDIATE;
  UPDATE library SET active_game_id = NULL WHERE id = 1;          -- assert changes() = 1
  UPDATE game
     SET content_json = :final_blob, content_sha256 = :final_hash,
         move_count = :plies, outcome = :outcome, end_reason = :reason,
         ended_at_ms = :ended_ms, history_added_at_ms = :now_ms,
         revision = revision + 1
   WHERE id = :active_id AND history_added_at_ms IS NULL;         -- assert changes() = 1
COMMIT;
```

The order is forced by `trg_game_archive_requires_cleared_active`. If `COMMIT` fails for any reason, the previously committed active game is intact and unchanged, no History record exists, and the caller reports the accepted persistence-failure path.

**Import** (after stages 0–5 have completed *outside* any transaction):

```sql
BEGIN IMMEDIATE;
  SELECT id, archive_version, content_sha256, content_json
    FROM game WHERE game_uid = :uid;
  -- no row                                  -> INSERT one History record, COMMIT
  -- row, same version, hash and bytes equal -> ROLLBACK, return that record (duplicate)
  -- anything else                           -> ROLLBACK, identity conflict
  INSERT INTO game (game_uid, archive_version, content_json, content_sha256,
                    rules_id, rules_version, start_fen, mode, human_side, ai_level,
                    ai_movetime_ms, first_mover_choice, move_count, outcome, end_reason,
                    started_at_ms, ended_at_ms, provenance, pinned,
                    history_added_at_ms, revision)
  VALUES (:uid, :av, :blob, :hash, 'minixiangqi', :rv, :fen, :mode, :side, :level,
          :movetime, :first_mover, :plies, :outcome, :reason,
          :started_ms, :ended_ms, 'imported', 0, :now_ms, 0);
COMMIT;
```

`history_added_at_ms = now` gives the accepted "most recently completed **or imported** first" ordering for free.

**Pin / unpin:**

```sql
UPDATE game SET pinned = :flag WHERE id = :id AND history_added_at_ms IS NOT NULL;
```

**Permanent delete:**

```sql
BEGIN IMMEDIATE;
  DELETE FROM game WHERE id = :id AND history_added_at_ms IS NOT NULL;  -- assert changes() = 1
COMMIT;
```

The predicate makes deleting the active game impossible even before the foreign key's `RESTRICT` would. A failure rolls back and the record remains, as the contract requires.

**Export:** a pure read. It emits the row's stored `archive_version` and `content_json` bytes verbatim inside a freshly built envelope with the row's `game_uid` and a new `origin` block. No local metadata leaves the store.

### 4.5 SQLite version, build options, pragmas, and concurrency

**Version policy.** Vendor the SQLite amalgamation inside the core, pinned exactly, following the same discipline the project already applies to engine and NNUE inputs (`engine-integration.md § Scope and ownership`, `§ Accepted NNUE handling policy`): record the release version string, `sqlite3_sourceid()`, the download URL, the byte length, and the SHA-256 in a machine-readable manifest, and verify the hash at build time so a mismatch fails the build. Pin the newest stable release at the time the core lands (the 3.5x series is current) and re-pin **deliberately** — as an explicit change with a changelog review — rather than by floating.

Feature floor, with the reason for each, so any future re-pin can be checked against it:

| feature used | minimum SQLite |
|---|---|
| partial indexes (`ix_game_history_order`) | 3.8.0 |
| `WITHOUT ROWID` (`meta`) | 3.8.2 |
| `PRAGMA trusted_schema` | 3.31.0 |
| `INSERT … RETURNING` | 3.35.0 |
| `STRICT` tables | **3.37.0** |

**Build options.**

```
-DSQLITE_THREADSAFE=1                 # serialized; the store is not on any hot path
-DSQLITE_DQS=0                        # no double-quoted string literals — a real correctness win
-DSQLITE_ENABLE_API_ARMOR=1           # validate API arguments in a correctness-critical store
-DSQLITE_OMIT_LOAD_EXTENSION=1        # no extension loading, ever
-DSQLITE_DEFAULT_FOREIGN_KEYS=1       # belt to the per-connection pragma's braces
-DSQLITE_DEFAULT_MEMSTATUS=0
-DSQLITE_LIKE_DOESNT_MATCH_BLOBS
-DSQLITE_MAX_EXPR_DEPTH=0
-DSQLITE_OMIT_DEPRECATED
-DSQLITE_OMIT_PROGRESS_CALLBACK
-DSQLITE_OMIT_SHARED_CACHE
-DSQLITE_USE_ALLOCA
```

This is SQLite's own recommended compile-time option set, plus `API_ARMOR` and `OMIT_LOAD_EXTENSION` for the untrusted-input posture. Notably, **no `SQLITE_ENABLE_*` feature module is enabled**: there is no full-text search (the MVP has no History search), no JSON SQL functions are used (the core parses the blob itself, so JSON never enters the SQL layer), no R-Tree, no session extension. Every enabled module would be attack surface and binary size for no capability. `SQLITE_THREADSAFE=1` rather than `=2` costs a mutex per API call at a few dozen calls per game — irrelevant — and removes an entire class of latent threading bug; `=2` remains available if measurement ever justifies it.

**Pragmas.** `journal_mode = WAL` is stored in the database header and persists; **every other pragma is per-connection and must be re-applied on every open** — a classic source of silently lost `foreign_keys` enforcement.

- **`journal_mode = WAL`.** The store commits on every accepted move; WAL turns each commit into an append instead of a rollback-journal round trip, and it is the more crash-resistant mode. Cost: the `-wal` and `-shm` sidecar files must be treated as part of the store by anything that copies, moves, or backs it up, and the connection must be checkpointed or closed cleanly when the app is backgrounded.
- **`synchronous = FULL`, not `NORMAL`.** The accepted contract says a committed move is the recovery boundary after interruption; `NORMAL` in WAL mode can lose the last transactions after a power loss, which would silently weaken that promise. `FULL` fsyncs the WAL on each commit — one fsync per move, far below the 1–5 s the AI already takes.
- **`foreign_keys = ON`** — otherwise the `RESTRICT` on the active reference is decorative.
- **`journal_size_limit = 1 MiB`** keeps the WAL bounded for a database that will rarely exceed a few megabytes.
- **`trusted_schema = OFF`**, **`temp_store = MEMORY`**, **`busy_timeout = 5000`** (harmless insurance under a single writer).
- **`PRAGMA quick_check`** at open, reporting a typed corruption error rather than proceeding; the database is small enough that this is milliseconds. **`PRAGMA optimize`** at close.

**Concurrency limits** — answering the open question directly, grounded in `game-data.md § Local-only boundary` ("must not assume multiple devices or concurrent writers") and `architecture.md § Concurrency and lifecycle` ("the core is responsible for its own internal synchronization"):

- **One process, one database connection, one writer.** The store is never opened by a second process or a second connection.
- **All store operations are serialized** through a single core-owned store executor. Reads and writes share the queue; frontends never see the queue.
- **No operation holds a transaction across a callback or across any I/O the core does not control.** Import performs all parsing, replay, and hashing *outside* the transaction so the write window is microseconds.
- **Cross-process access is unsupported and undefended**, consistent with the local-only boundary. If a platform ever needs a second process (a share extension, a Windows preview handler), that is a product-level change, not a pragma change.
- The engine runs on its own threads and **never touches the store**; results reach the store only after the game layer accepts them (`engine-integration.md § Search facade boundary`).

**iOS note (frontend-owned):** the frontend supplies the store's directory and therefore owns its data-protection class. Raising it to `NSFileProtectionComplete` would make WAL writes fail while the device is locked; the sidecar files must get the same class as the database.

### 4.6 Migration and bookkeeping

**Version key.** `PRAGMA user_version` is the single authoritative schema version, `1` for this schema. The `meta` table is diagnostic bookkeeping only and migration never reads it — a rule worth stating because a bookkeeping table that migration depends on becomes a bootstrapping problem.

**Open procedure.**

1. Open, apply the per-connection pragmas, `quick_check`.
2. `user_version == 0` → fresh store: create the whole schema, seed `library` and `meta`, set `user_version = 1`, all in one transaction.
3. `user_version < current` → apply steps in order, **each in its own transaction**, each setting `user_version` to its own target inside that transaction. Then `PRAGMA foreign_key_check` and the core's `verify_invariants()`; a failure aborts the open with a typed error and leaves the last successfully committed step in place.
4. `user_version == current` → proceed.
5. `user_version > current` → **stop.** Report a typed "store created by a newer version of the app" error; do not write, do not migrate down, do not rename or delete the file. This case is realistic under internal TestFlight distribution, where a tester can install an older build after a newer one; silently deleting or downgrading a store would be data loss.

Table-rebuild steps follow SQLite's documented procedure: `PRAGMA foreign_keys = OFF` **before** `BEGIN`, create the new table, copy, drop, rename, recreate indexes and triggers, `PRAGMA foreign_key_check`, `COMMIT`, then `PRAGMA foreign_keys = ON`. Triggers are dropped and recreated around a rebuild, which is also how a migration is permitted to recompute derived columns that `trg_game_history_immutable` otherwise protects.

**Archives are never rewritten by a database migration.** `game-data.md § Migration` requires that a database migration must not silently change the meaning of an existing archive. The strongest form of that guarantee is not to touch archive bytes at all: each row keeps its `archive_version` and its exact `content_json` forever, and readers dispatch on the stored version. What a migration *may* do is recompute the derived summary columns from the unchanged blob. This rule is also load-bearing for duplicate detection (§2.4).

**Export version policy.** Export re-emits **the record's stored `archive_version` and bytes**, not the newest version the app supports. Two consequences, both wanted: re-exporting an imported file reproduces it byte-for-byte, and an older peer can still read files that originated from an older build. New games are created at the newest version the creating build supports, so a library naturally holds a mix — which is fine, because decoders are versioned anyway.

**Migration fixtures.** Retain a file-backed store for every schema version shipped in an internal build, plus an archive file for every archive version, and migrate/import each forward in CI. This is what `testing.md § Game data` already asks for ("Test every released database schema migration and archive-format migration from file-backed fixtures"); the schema above makes those fixtures small enough to keep in the repository.

---

## 5. Compatibility promise

### Proven source facts

- Archive versions form a separate compatibility contract from the database schema; import and export must use explicit archive-version dispatch and preserve the ability to reject versions they cannot safely interpret (`game-data.md § Migration`).
- The core migrates the store forward from every schema shipped in an internal build (same section).
- Exported files must round-trip across all supported platforms (`game-data.md § Import and export`).
- Import accepts one *compatible* game file at a time (`product.md § Games and history`).

### Proposal

**User-visible promise** (semantics; the exact Chinese copy is `interaction-design.md`'s to own — `§ History library` records that import, duplicate, conflict, and error copy remain to be designed):

> A game file exported by any version of Mini Xiangqi can be imported by that version and by every later version. A file exported by a newer version of the app may not be readable by an older version; when that happens the app says the file was created by a newer version, and imports nothing. A file is never partially imported.

Suggested strings, offered for `interaction-design.md` to accept, reject, or rewrite:

- newer-than-supported file — 「这个棋局文件由更新版本的应用导出，当前版本无法读取。」
- identity conflict — 「这个文件与已有记录的标识相同但内容不同，无法导入。」
- exact duplicate — 「这盘棋已经在历史中。」 plus an action to open the existing record.

**Engineering form.**

1. `archive_version` is a single monotonically increasing integer with no minor component. A build ships a decoder for a closed set `{1 … N}` and rejects everything outside it.
2. **Version 1 never changes meaning.** Any correction — a new field, a changed identifier, a different canonicalization — is version 2. There is no "v1.1", and no field is ever reinterpreted in place.
3. **Unknown members are rejected within a version**, rather than ignored. The app is the only writer of these files, so leniency buys no interoperability; and silently ignoring a member would mean an older build could import a newer file while dropping meaning, which is the one failure mode this contract most wants to avoid. Forward compatibility is delivered by version dispatch, which is exactly what the accepted migration rule prescribes.
4. **Backward compatibility is unbounded.** A build must retain every shipped decoder. Decoders are small and are covered by the archive fixtures above.
5. **Never rewrite stored archives** (§4.6). A record's bytes and version are fixed at creation or import.

**Database migration stance.** Forward-only, from every schema shipped in an internal build, applied step by step in transactions, verified by `foreign_key_check` plus `verify_invariants()`. A newer-than-supported store is refused, not repaired. Archive blobs are never rewritten; derived columns may be recomputed. The database is a private implementation detail with no compatibility promise to anything outside the core (`architecture.md § Dependency direction`) — the *only* thing that crosses versions and devices is the archive.

---

## 6. Contradictions and gaps

These were found while designing against the current contracts. None is silently resolved above; each is either flagged here or explicitly parameterized.

**6.1 A mutual perpetual violation is an accepted outcome with no reason identifier.** `xiangqi-rules.md § Move-count, repetition, perpetual check, and perpetual chase` accepts "when both sides commit the same class of perpetual violation, the result is a draw", but the frozen fixture vocabulary in `§ Conformance fixtures` has only `perpetual-check` and `perpetual-chase`, neither of which expresses mutuality. A draw stored with one of those reasons would be indistinguishable from a claimed threefold draw, and the reason→outcome constraint in §0 would reject it. **Proposal:** add `mutual-perpetual-check` and `mutual-perpetual-chase` to the rules contract's reason vocabulary and to the fixtures README in the same change. The archive v1 field set already includes them, so accepting this costs no archive version — but it is a `docs/xiangqi-rules.md` edit and needs the user's approval. The corresponding fixtures are already deferred (`xiangqi-rules.md § Conformance fixtures` records that the mutual-check fixture had no minimal construction), so the identifier can be frozen ahead of its fixture.

**6.2 No rules-contract version number exists.** `game-data.md § Versioned game archive` requires the archive to carry "rules and variant version identifiers", and the archive must not tie meaning to an engine build. But `xiangqi-rules.md` declares no version, and the fixtures carry only `variant: "minixiangqi"`. **Proposal:** `xiangqi-rules.md` declares an integer rules version, starting at `1`, incremented only when an accepted interpretation changes a legal move or a result — not when prose is clarified and not when the engine or fork revision changes. Adopting the archive requires this declaration; without it `rules_version` has no owner.

**6.3 `validate_fen` is structural, and the initial-position legality contract is unwritten.** The FEN/notation freeze recorded that the reference engine accepts a kings-facing FEN as structurally valid (`discussion-drafts/fen-notation-fixtures-draft.md` §9 and open flag 6), and `xiangqi-rules.md` defines legality of *moves* but never defines which *setups* are legal. v1 sidesteps this entirely by permitting only the frozen starting FEN. When a later version permits arbitrary initial positions, the following predicate is proposed, and the recommendation is **reject at import**: exactly one king per side, each inside its own palace; no piece count exceeding the variant's; no soldier on an impossible square; **the side not to move is not in check, including through the facing-kings attack**; and the position's own terminal state consistent with the record's outcome. A facing-kings setup is unreachable by legal play and has no representation in the result taxonomy, so accepting it would create a position the rules facade cannot classify.

**6.4 The History row's "date" is ambiguous.** `product.md § Games and history` and `interaction-design.md § History library` say each entry shows "its date"; `game-data.md § Accepted MVP record behavior` says sorting uses a local History-added time and that "the original game dates remain separate metadata". For an imported record these differ, potentially by a long interval, and the contracts do not say which one the row displays. The schema supplies all three (`started_at_ms`, `ended_at_ms`, `history_added_at_ms`); the choice is an `interaction-design.md` decision.

**6.5 Cross-archive-version duplicate comparison is undefined and conservatively rejected.** §2.4 rejects a same-identity match whose stored `archive_version` differs from the imported file's, because v1 cannot compare a v1 content object with a v2 one. This can only arise once version 2 exists. **Constraint recorded for v2:** either v2 must define a lossless projection of v2 content down to v1 (so a version-independent digest exists), or the project must accept that a v1 export and a v2 export of the same game are treated as an identity conflict.

**6.6 No accepted contract bounds an active game's length.** With `nMoveRule = 0` and a claim-gated repetition draw, nothing terminates a Free Play game automatically. The import ply cap must therefore be at least as large as the longest game the app can produce, and 10 000 is proposed on that basis. Either the app also bounds live play at the same constant — a new product behaviour, and one the user should decide — or the cap must be documented as "larger than anything reachable in practice" and the mismatch accepted.

**6.7 Move count is not defined as plies or full moves.** `interaction-design.md § Saving the active game before choosing a new mode` shows metadata like 「42 步」 without saying which. The schema stores `move_count` as **plies** (the length of `moves`), because that is the only value the archive can supply without ambiguity; a full-move display value is `ceil(plies / 2)`. Confirming the display unit is an interaction-design item.

**6.8 Imported history replay orientation may rest on an assumption the archive removes.** `interaction-design.md § Board orientation` says human-versus-AI replay defaults to the original human's perspective, while "Free Play and imported history default to Red at the bottom". The archive *does* preserve `human_side` for an imported human-versus-AI game, so the imported exception is a choice rather than a data limitation. Worth re-confirming now that the data is available.

**6.9 `first_mover_choice` exceeds what any accepted contract requires.** `game-data.md § Accepted pre-start state behavior` freezes "the resolved human side, AI level identifier, and exact thinking-time value"; `product.md § Target-MVP play modes` retains "the resolved choice … the human player's Red or Black side". Neither requires retaining whether the side was chosen or randomly resolved. It is included because it cannot be reconstructed later and because adding a member costs an archive version. Confirm or drop before the format freezes.

**6.10 Provenance describes how the record entered *this* library, not the game's origin.** A user who exports a locally played game, deletes it, and re-imports the file sees the record marked as imported. This follows directly from the accepted wording ("imported entries are visibly marked") and from refusing to trust anything the file claims about itself, but it is a user-visible consequence worth confirming rather than discovering.

**6.11 Two open questions are deliberately untouched.** Where Settings preferences live (`game-data.md § Need to discuss`) is left out of the v1 DDL, and how frontends learn about library changes (`game-data.md § Need to discuss`; `architecture.md § Need to discuss`) is the C-interface draft's boundary — this draft only requires that "import returned the existing record" be expressible as an operation result.

---

## 7. Decision shortlist

Each item is a genuinely open, contract-changing choice with one recommendation.

1. **Portable format and file extension.** → **Canonical JSON, one file per game, extension `.mxq`**, Apple UTI `com.ppppvz.minixiangqi.game` conforming to `public.json`, MIME `application/vnd.minixiangqi.game+json`. It is the only candidate that structurally satisfies the "no embedded execution, no external references" rule, it stays human-inspectable for an education app, and it adds no compression or binary dependency for a 3 KB payload.

2. **Stable identity scheme.** → **UUID version 7**, canonical lowercase text, generated by the core at game creation, frozen forever, never regenerated on import or export, and never derived from content. A content-derived identity would delete the accepted identity-conflict behaviour; a collision degrades into the already-specified conflict or creation-failure paths rather than into a new user-visible case.

3. **Pin state (and other local metadata) in exports and duplicate comparison.** → **No.** Not in the archive, not in the hash. Including pin would make pinning-then-re-exporting the same game produce an identity *conflict* against the earlier export, breaking the rule it participates in. The same reasoning excludes History-added time and provenance.

4. **Facing kings and initial-position legality at import.** → **v1 permits only the frozen starting FEN**, so the question cannot arise for a v1 file. The app cannot produce any other start (starting from a historical position is an explicit MVP exclusion), so permitting arbitrary positions would create an untestable, unspecified import surface. When arbitrary starts are eventually allowed, **reject facing kings at import** using the §6.3 predicate.

5. **Compatibility promise.** → *"A game file exported by any version of Mini Xiangqi can be imported by that version and every later version. A file exported by a newer version of the app may not be readable by an older version; the app then says the file was created by a newer version and imports nothing. A file is never partially imported."* Backed by: a single integer archive version, unbounded decoder retention, unknown members rejected within a version, and stored archives never rewritten.

6. **Timestamp format.** → **RFC 3339 UTC, `YYYY-MM-DDTHH:MM:SS.sssZ`, fixed width, always `Z`** in the archive; **epoch milliseconds as `INTEGER`** in the database; displayed in the device's current time zone. Fixed-width UTC makes canonical bytes trivially stable and lossless in both directions. Accepted trade-off: a game exported across time zones may display a different local date on the importing device. If that matters, the alternative is an additional non-hashed local-offset field — recommended against for v1, since no accepted surface needs it.

7. **Add two rules reason identifiers** (`docs/xiangqi-rules.md` edit). → **Add `mutual-perpetual-check` and `mutual-perpetual-chase`** to the accepted reason vocabulary and to `fixtures/rules/README.md`, ahead of their deferred fixtures. Without them, the accepted mutual-violation draw has no serializable reason and cannot be stored distinguishably. Costs no archive version if done before the format freezes.

8. **Declare a rules-contract version** (`docs/xiangqi-rules.md` edit). → **`rules_version = 1`**, owned by the rules contract, incremented only when an accepted interpretation changes a legal move or a user-visible result — never for prose edits, engine revisions, or fork patches. The archive's `rules_version` has no owner until this exists.

### Parameters proposed (no decision needed unless you disagree)

| parameter | proposed |
|---|---|
| maximum import file size | 1 MiB |
| maximum plies (import and, if adopted, live play) | 10 000 |
| maximum JSON nesting depth / members per object / string length | 4 / 32 / 256 bytes |
| import validation wall-clock budget | 2 000 ms on the slowest supported device |
| SQLite pin | newest stable amalgamation at core landing, vendored, hash-pinned in a manifest; floor 3.37.0 for `STRICT` tables |
| SQLite build options | SQLite's recommended set plus `SQLITE_ENABLE_API_ARMOR`, `SQLITE_OMIT_LOAD_EXTENSION`, `SQLITE_DQS=0`, `SQLITE_THREADSAFE=1`; **no `SQLITE_ENABLE_*` feature module** |
| journal mode / durability / foreign keys | `WAL` / `synchronous = FULL` / `foreign_keys = ON` on every connection |
| store concurrency | one process, one connection, one writer, all operations serialized on a core-owned executor |
| schema version key | `PRAGMA user_version`, forward-only migration, newer-than-supported store refused |
| AI level identifiers | `fast` / `standard` / `deep` — needs a one-line addition to `engine-integration.md`, which names "the selected level identifier" without defining its serialized form |
