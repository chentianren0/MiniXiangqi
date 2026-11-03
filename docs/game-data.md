# Game Files

A game file is one finished game: a JSON object, extension `.mxq`, UTI `com.chentianren.minixiangqi.game` conforming to `public.json`, MIME type `application/vnd.minixiangqi.game+json`. It is the History record itself, encoded; History exports one game per file and imports one file at a time.

## Members

- `version`: the format version, `1`. A file with a higher version is refused as written by a newer app.
- `id`: the game's identity, a UUID fixed when the game began. Importing a game the library already holds adds nothing.
- `kind`: which game: `minixiangqi`, `xiangqi`, `jieqi`, `gomoku-15` or `renju`.
- `mode`: `human-vs-ai`, `free-play`, `nearby` or `online`.
- `humanSide` and `aiLevel`: in `human-vs-ai` games only, the side the player took (`red` or `black`) and the AI's level (`fast`, `standard` or `deep`).
- `setup`: the position the game began from, where it is not the game's fixed start: a composed Xiangqi position, with either side to move, or a Jieqi deal, which marks each face-down piece with its identity letter followed by `~`. Absent for every other game.
- `moves`: the move line from that position, in the game's notation: a from and a to square in the movement games (`a9a10`), one point in the placement games (`h8`).
- `result`: `red-wins`, `black-wins`, `draw`, or `none` for a game ended early.
- `reason`: why it ended: a rule reason (`checkmate`, `stalemate`, `perpetual-check`, `perpetual-chase`, `threefold-repetition`, `mutual-perpetual-check`, `mutual-perpetual-chase`, `fifty-move-rule`, `forty-move-rule`, `five-in-a-row`, `board-full`), or `resignation`, `ended-early`, `agreed-draw`, `mutual-resignation`.
- `startedAt` and `endedAt`: ISO 8601 timestamps in UTC.

`red` is the side that moves first in every game, which is the black stone in Gomoku and Renju. `result` is `none` exactly when `reason` is `ended-early`. After a `resignation`, `result` names the winner, so the side that resigned is the other one. `agreed-draw` and `mutual-resignation` occur only in networked play; `fifty-move-rule` is Xiangqi's, `forty-move-rule` Jieqi's, and `five-in-a-row` and `board-full` the placement games'.

## Import

An import decodes the file, refuses a start the game's setup rules do not allow, replays every move through the rules, and refuses a line with a move that is not legal at its turn, or one whose rules-decided result the file contradicts. A refused file changes nothing.

## Not in the file

Whether a record is pinned, whether it was imported, the side this device played in a networked game, and what an unfinished networked game needs to resume stay in the library on this device. A game file carries no per-move timing, comments, undo counts or engine identifiers. Files written by the 3.x app are not read.
