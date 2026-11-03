# Game Archive, 3.x Format

This lists what a game record carries today, in the archive the 3.x app writes and reads; #282 replaces the format with a new Codable archive. A saved or exported game is one JSON document: extension `.mxq`, UTI `com.chentianren.minixiangqi.game` conforming to `public.json`, MIME type `application/vnd.minixiangqi.game+json`. It is written in canonical form: one line, members sorted, integers only, no `null`.

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
- `start_fen`: the position the game began from. A Xiangqi game may start from any legal composed position with either side to move; Mini Xiangqi, Gomoku and Renju always use their fixed start. A Jieqi game's dealt start marks each face-down piece with its identity letter followed by `~`.
- `moves`: the move line in the game's notation, from `start_fen` on. A movement game's ply is a from and to square (`a9a10`); a placement game's is one point (`h8`).
- `mode`: `human-vs-ai`, `free-play`, `nearby` or `online`.
- `started_at`: when the game began.

Only in `human-vs-ai` games:

- `human_side`: the side the player took, `red` or `black`.
- `ai_level`: `fast`, `standard` or `deep`.
- `ai_movetime_ms`: the engine's time per move for that level when the game was played.
- `first_mover_choice`: what the player picked for who moves first: `human-first`, `ai-first` or `random`.

Only in networked Jieqi games, as evidence the deal was not chosen. Each is 64 lowercase hex digits (32 bytes); the derivation is in `core/src/mxq_deal.hpp`, which #282 keeps.

- `deal_commit`: the commitment exchanged in the handshake, the SHA-256 of the seed bytes.
- `deal_nonce`: the nonce the deal was derived with.
- `deal_seed`: the seed that hashes to the commitment.

Only in finished games, which every exported file is:

- `outcome`: `red-wins`, `black-wins`, `draw`, or `none` for a game ended early.
- `end_reason`: why it ended: a rule reason (`checkmate`, `stalemate`, `perpetual-check`, `perpetual-chase`, `threefold-repetition`, `mutual-perpetual-check`, `mutual-perpetual-chase`, `fifty-move-rule`, `forty-move-rule`, `five-in-a-row`, `board-full`), or `resignation`, `ended-early`, `agreed-draw`, `mutual-resignation`.
- `ended_at`: when the game ended.

How the two read together: `outcome` is `none` exactly when `end_reason` is `ended-early`. After a `resignation`, `outcome` names the winner, so the side that resigned is the other one. The draws are `threefold-repetition`, `mutual-perpetual-check`, `mutual-perpetual-chase`, `fifty-move-rule`, `forty-move-rule`, `board-full`, `agreed-draw` and `mutual-resignation`. `agreed-draw` and `mutual-resignation` occur only in networked play. `fifty-move-rule` is Xiangqi only and `forty-move-rule` Jieqi only; `five-in-a-row` and `board-full` belong to Gomoku and Renju, the other rule reasons to the xiangqi games.

Timestamps are UTC in the form `YYYY-MM-DDTHH:MM:SS.sssZ`.

## Not in the archive

Pin state, provenance (`locally-played` or `imported`), the time a game entered History, and the side this device played in a networked game are library fields stored beside the archive, not in it. The archive carries no per-move timing, comments, undo counts, engine identifiers or move count.
