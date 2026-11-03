# Game Archive, 3.x Format

This is the field inventory of the archive the 3.x app writes and reads, the format #282 replaces with a new Codable archive. A saved or exported game is one JSON document (extension `.mxq`, UTI `com.chentianren.minixiangqi.game`), written in canonical form: one line, members sorted, integers only, no `null`. A converter for existing libraries and exported files needs exactly these fields.

## Envelope

- `archive_format`: always `minixiangqi-game`; the in-band type check.
- `archive_version`: format version, `7`.
- `game_id`: the game's stable identity, a version 7 UUID in lowercase, fixed at creation and kept through export and import.
- `content`: everything that defines the game, listed below.
- `origin`: describes the export rather than the game, and is never compared.
  - `app_version`: product version of the app that wrote the file.
  - `exported_at`: when the file was exported, or for a stored game when it last changed.

## Content

- `rules_id`: which game: `minixiangqi`, `xiangqi`, `jieqi`, `gomoku-15` or `renju`.
- `rules_version`: rules interpretation version, `1` for every game.
- `start_fen`: the position the game began from. A Jieqi game's dealt start marks each face-down piece with its identity letter followed by `~`.
- `moves`: the move line in the game's notation, from `start_fen` on. A movement game's ply is a from and to square (`a9a10`); a placement game's is one point (`h8`).
- `mode`: `human-vs-ai`, `free-play`, `nearby` or `online`.
- `started_at`: when the game began.

Only in `human-vs-ai` games:

- `human_side`: the side the player took, `red` or `black`.
- `ai_level`: `fast`, `standard` or `deep`.
- `ai_movetime_ms`: the engine's time per move for that level when the game was played.
- `first_mover_choice`: what the player picked for who moves first: `human-first`, `ai-first` or `random`.

Only in networked Jieqi games, as evidence the deal was not chosen:

- `deal_commit`: the commitment exchanged in the handshake.
- `deal_nonce`: the nonce the deal was derived with.
- `deal_seed`: the seed that hashes to the commitment.

Only in finished games, which every exported file is:

- `outcome`: `red-wins`, `black-wins`, `draw`, or `none` for a game ended early.
- `end_reason`: why it ended: a rule reason (`checkmate`, `stalemate`, `perpetual-check`, `perpetual-chase`, `threefold-repetition`, `mutual-perpetual-check`, `mutual-perpetual-chase`, `fifty-move-rule`, `forty-move-rule`, `five-in-a-row`, `board-full`), or `resignation`, `ended-early`, `agreed-draw`, `mutual-resignation`.
- `ended_at`: when the game ended.

Timestamps are UTC in the form `YYYY-MM-DDTHH:MM:SS.sssZ`.

## Not in the archive

Pin state, provenance (`locally-played` or `imported`), the time a game entered History, and the side this device played in a networked game are library fields stored beside the archive, not in it. The archive carries no per-move timing, comments, undo counts, engine identifiers or move count.
