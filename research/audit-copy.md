# Copy and terminology audit of the accepted contract set

Workspace-only research evidence. Not part of any repository, not a contract, and it authorizes nothing.
The main thread authors all contract text; everything below is a finding plus a proposed exact correction.

Audited: the eight documents in `MiniXiangqi/docs/` (`product.md`, `architecture.md`, `xiangqi-rules.md`,
`game-data.md`, `core-interface.md`, `engine-integration.md`, `interaction-design.md`, `testing.md`), the
sixteen fixtures in `MiniXiangqi/fixtures/rules/`, and `MiniXiangqi/fixtures/rules/README.md`. Read end to
end, then cross-checked by script.

Method note, applied throughout. **Executed** means I ran it and the numbers below are its output.
**Read** means I am quoting a document. **Reasoned** means it is my judgement and you may disagree with it.
Nothing here required the engine: every question in this lens is settled by exact string comparison over the
contract set, so I settled them that way rather than by argument.

---

## 1. The complete inventory of accepted Chinese copy

**Executed.** Extracted every bold run containing a CJK codepoint from `docs/*.md`:

```
accepted strings: 58   gated by an exact-copy check in testing.md: 27   ungated: 31
strings whose only definition is in testing.md: 0
strings that appear in two documents with different wording: 0
```

That last line is the one genuinely reassuring result in this report, and it is a computed result rather
than an impression: every string that appears in more than one document is byte-identical in all of them,
including the long ones (`这盘对局将按当前状态保存到历史。`, `当前对局仍然保留。请重试。`,
`你将控制红黑双方，红方先行。`, `无法保存这一步，请重试。`) and including the space in `AI 先手`,
`默认 AI 等级` and `无法启动 AI 对手`. Punctuation is also internally consistent: every message ends in `。`,
every question title ends in `？`, no statement title carries terminal punctuation.

The inventory, with its single normative source and every place it is restated. `id` = `interaction-design.md`,
`prod` = `product.md`, `eng` = `engine-integration.md`, `gd` = `game-data.md`, `test` = `testing.md`.

| String | Role | Defined | Restated | Gated |
|---|---|---|---|---|
| `我先手` | first-mover choice | id:191 | id:209,213; prod:34,35 | test:63 |
| `AI 先手` | first-mover choice | id:191 | id:194,213; prod:34,35 | test:63,65 |
| `随机` | first-mover choice | id:191 | id:194,213; prod:34,35 | test:63 |
| `本局设置` | per-game setup group | id:191 | id:204 | — |
| `AI 等级` | per-game level control | id:191 | — | — |
| `人机对弈默认设置` | Settings group | id:209 | — | — |
| `默认先后手` | Settings row | id:209 | — | — |
| `默认 AI 等级` | Settings row | id:209 | — | — |
| `快速` | AI level | id:195 | prod:37; eng:97 | test:122 |
| `标准` | AI level (default) | id:195 | id:209; prod:37; eng:98 | test:63,122 |
| `深思` | AI level | id:195 | prod:37; eng:99 | test:122 |
| `开始对局` | primary action, both pre-starts | id:196 | id:44,197,198,204–207,315; prod:53; gd:82,90,92 | test:65,71,75 |
| `你将控制红黑双方，红方先行。` | Free Play pre-start text | id:203 | — | test:71 |
| `轮到红方` | turn status primary | id:268 | — | — |
| `轮到黑方` | turn status primary | id:268 | id:305 | — |
| `你` | controller label | id:269 | id:305 (`你执红`) | — |
| `将军` | check token | id:249 | id:271 | test:171,186 |
| `可判和` | claim affordance | id:272 | id:305,352 | test:78 |
| `无法保存这一步，请重试。` | per-ply save-failure capsule | id:257 | — | test:184 |
| `无法启动 AI 对手` | low-memory title | id:283 | id:526; eng:112,194 | test:139 |
| `当前可用内存不足。请尝试关闭一些其他 App，然后重试。` | low-memory message | id:284 | — | — |
| `取消` | dismiss (5 dialogs) | id:285 | id:286,303,313,321,380,526 | test:67,73 |
| `重试` | retry (2 dialogs) | id:285 | id:321 | test:73 |
| `开始新对局？` | save-and-continue title | id:300 | — | test:67 |
| `当前对局` | metadata header | id:301 | — | test:67 |
| `这盘对局将按当前状态保存到历史。` | save-and-continue message | id:302 | — | test:67 |
| `保存并继续` | save-and-continue action | id:303 | id:186,207,307,334; prod:49,55; gd:77,105,106 | test:67,72,105 |
| `人机对弈 · 你执红` | metadata example | id:305 | — | — |
| `自由对弈` | metadata example | id:305 | — | — |
| `进行中 · 轮到黑方 · 42 步` | metadata example | id:305 | — | — |
| `红方获胜 · 将死 · 42 步` | metadata example | id:305 | — | — |
| `进行中 · 可判和 · 42 步` | metadata example | id:305 | — | — |
| `判和` | (orphan — see §9) | id:313 | — | — |
| `悔棋` | Undo on the result card | id:341 | id:313 | test:77 |
| `无法保存对局` | archive-failure title | id:319 | id:230,257 | test:73,184 |
| `当前对局仍然保留。请重试。` | archive-failure message | id:320 | — | test:73 |
| `红方获胜` | result card title | id:340 | id:305 | — |
| `黑方获胜` | result card title | id:340 | — | — |
| `和棋` | result card title | id:340 | — | — |
| `结束对局` | confirm result | id:341 | id:44,343 | test:77 |
| `已记录到历史` | recorded state title | id:343 | — | — |
| `回放` | open replay | id:344 | — | test:77 |
| `完成` | done | id:344 | id:44 | test:77 |
| `局面已三次重复，可以和棋结束。` | threefold notice | id:350 | — | — |
| `继续对局` | keep playing | id:350 | id:352 | test:78 |
| `以和棋结束` | claim the draw | id:350 | id:351 | test:78 |
| `共享` | swipe / share | id:372 | id:376 | — |
| `删除` | swipe / confirm delete | id:372 | id:380 | — |
| `置顶` | pin | id:374 | — | — |
| `取消置顶` | unpin | id:374 | — | — |
| `删除前确认` | Settings toggle | id:377 | id:381 | test:82 |
| `删除这盘棋？` | delete confirmation title | id:378 | — | — |
| `删除后无法恢复。` | delete confirmation message | id:379 | — | — |
| `传统` / `现代` / `高对比` | piece style names | id:82–84 | id:93–95,100,141 | — |
| `汉字` / `图标` | piece symbol names | id:108,109 | — | — |

Plus the game-content characters, which are accepted but are not interface strings
(`interaction-design.md:59–71`): `帅 将 俥 车 傌 马 炮 砲 兵 卒`, and the notation particles
`进 退 平 前 后` with the Chinese numerals (`interaction-design.md:163–166`, gated at `testing.md:189`).

---

## 2. `king` against `General` — one piece, two accepted English names, inside single documents

**Severity: contradiction.** This is the worst defect in the lens and the only one that will reach users.

`interaction-design.md:74` (accepted, not "Need to discuss"):

> English piece names are General, Chariot, Horse, Cannon, and Soldier. They appear in help, accessibility
> announcements, and any descriptive text, never as board labels.

`xiangqi-rules.md:28,42,43,66`:

> Each side has a king, chariots, horses, cannons, and soldiers.
> A king moves one square orthogonally inside its palace.
> The two kings may not face each other on an otherwise empty file …
> Kings and soldiers are excluded as perpetual-chase targets.

It is not a clean split by document. **`xiangqi-rules.md` contradicts itself**: line 66 says "Kings and
soldiers", line 76 says "A chase whose target's only defender is **a general** is adjudicated on the
**flying-generals** condition alone" — same piece, same document, both in accepted text, fourteen lines apart.

**`engine-integration.md` contradicts itself** in adjacent bullets of the same list:

> line 43: … so the accepted exclusion of **generals** and soldiers holds in every path rather than in two of three.
> line 125: … and **kings** and soldiers are excluded as chase targets.

**`testing.md` contradicts itself**: line 92 gates "**king** and soldier chase-target exclusion"; line 186
gates "the check rings hide while a checked **general** is selected or dragged".

**`mx-end-003.json` contradicts itself inside one title string**:

> "Flying **general**: a move exposing facing **kings** on an empty file is rejected"

**Which is right: `General`.** Three reasons, in order of weight. (a) `interaction-design.md` is the document
whose scope statement claims "localization" and "Terminology for Xiangqi pieces, rules, results, and controls
must be consistent within each supported language" (line 459); no other document claims ownership of English
piece naming, so `interaction-design.md:74` is the only *authority* statement in the set and everything else
is incidental usage. (b) The Chinese is `帅`/`将`, whose accepted glyph pair is the general, and the check
token is `将军`; "king" has no anchor in the accepted Chinese at all. (c) `interaction-design.md:395` makes
Help a rules reference "covering the board, the pieces and their movement, check and checkmate, stalemate,
repetition and the claimable draw, perpetual check, and perpetual chase" — i.e. Help's English text is written
*from* `xiangqi-rules.md`, so "king" leaks straight into the one English surface a learner reads, next to a
board drawing 帅.

**Exact correction.** Replace `king`/`kings` with `general`/`generals` in: `xiangqi-rules.md` lines 28, 29,
35 (×2), 42, 43, 52 (`king-safety` → `general-safety`), 66, 100, 104; `engine-integration.md:125`;
`testing.md:87` (`king safety` → `general safety`) and `:92`; `game-data.md:175`; and in the fixtures
`mx-move-001`, `mx-move-005` (title and rationale), `mx-move-006`, `mx-chk-001`, `mx-chs-003`, `mx-end-003`
(title). Keep "flying general" as the name of the facing-generals rule, since that is already the phrase
`xiangqi-rules.md:76`, `engine-integration.md:42` and the fixtures README use. Keep `MxqColor` and the
`from_square` identifier names in `core-interface.md` untouched — machine identifiers are a separate
vocabulary and nothing in the set claims otherwise.

---

## 3. The fixtures call Red "white" and the chariot "rook", twice in the same sentence as "Red"

**Severity: contradiction.** The fixtures are accepted contract material — `xiangqi-rules.md:5` accepts
"the first approved fixture set in `fixtures/rules/`", and the README says the fixtures and the rules document
"form one contract and are reviewed together".

`xiangqi-rules.md:35`:

> `w` is Red: uppercase pieces, moves first, king starting on `d1` …

`mx-chk-001.json` rationale, in full:

> "The **white** rook alternates d4/c4, checking after every **white** move, while the black king shuttles
> d7/c7 without ever checking. On the third occurrence of the repeated in-check position the perpetual-check
> violation is complete and the checking side (**Red**) loses."

The same sentence pair names one side "white" three times and "Red" once. `mx-chs-001.json` does the same:
"The **white** rook re-attacks the same unprotected black cannon … the chasing side (**Red**) loses."
`mx-chs-004.json`: "The repeated position first arises after **White's** first move … The chasing side
(**Red**) loses." `mx-move-006.json`: "Black rook d5 checks the **white** king d1".

"rook" for chariot appears in eight of the sixteen fixtures — `mx-chs-001` (title *and* rationale),
`mx-chs-002`, `mx-chs-003`, `mx-chs-004`, `mx-chk-001`, `mx-move-001`, `mx-move-006`, `mx-end-001`,
`mx-end-002`.

**Which is right: `Red` and `Chariot`.** `xiangqi-rules.md:35` fixes the colour names in one sentence that no
other document disputes, and §2 above fixes the piece names. "white"/"rook" are chess vocabulary that entered
with the FEN and the engine, which is exactly the direction of authority the contract set forbids
(`fixtures/rules/README.md:5`: "every expected value in a fixture comes from the accepted rules contract and
the selected public rules source, never from what any engine returns").

**Exact correction.** In fixture `title` and `rationale` prose only — no `id`, `start_fen`, `moves` or
`assertions` change, so `README.md:17`'s immutability rule is not touched — replace `white`/`White` with
`Red`, and `rook`/`Rook`/`rooks` with `chariot`/`Chariot`/`chariots`. `mx-chs-001`'s title becomes
"Unilateral perpetual chase of an unprotected cannon by a chariot".

---

## 4. Eight user-facing controls exist only in English, and the contract says the opposite

**Severity: contradiction.**

`interaction-design.md:455`:

> The supported languages are Simplified Chinese and English. **Simplified Chinese is the source language:**
> the accepted user-facing copy in this document is normative, and its English counterparts are translations of it.

`interaction-design.md:533`, in Need to discuss:

> Approve the English counterparts of every accepted Chinese string in this document. **The accepted copy is
> Chinese and exact; no English equivalent has been approved**, so an English build is not yet fully specified.

Both sentences assert that the Chinese set is complete and only English is outstanding. **Executed** — the
bold-run scan over `docs/*.md` for short capitalised non-CJK runs returns these user-facing control names,
typeset in exactly the same bold as the Chinese strings, with no Chinese counterpart anywhere in the set:

| English-only label | Where |
|---|---|
| **Play** | `interaction-design.md:21`, `product.md:72` |
| **History** | `interaction-design.md:22`, `product.md:73` |
| **Settings** | `interaction-design.md:23`, `product.md:74` |
| **Human versus AI** | `interaction-design.md:183,298`, `product.md:32`, **gated at `testing.md:66`** |
| **Free Play** | `interaction-design.md:183,298`, `product.md:33`, **gated at `testing.md:66`** |
| **Resume Game** | `interaction-design.md:296` |
| **Flip Board** | `interaction-design.md:214`, restated unbolded at `:360` |
| **Confirm Before Deleting** | `product.md:62,80`, `game-data.md:125,151,153` |

Two of these are gated. `testing.md:66` reads "verify that tapping either **Human versus AI** or **Free Play**
remains available" — a validation gate on a control label that has no normative source-language string.
`interaction-design.md:386` extends the same problem to Windows: "Pointer context menus, keyboard commands,
and screen-reader custom actions … expose equivalent Pin or Unpin, Share, and Delete operations" — three
controls whose Chinese labels (`置顶`/`取消置顶`, `共享`, `删除`) do exist, described in English in a sentence
that specifies a surface.

**Which is right: the Chinese-is-source rule.** It is the explicit, reasoned statement; the English labels are
prose convenience that hardened into bold. And the app ships Simplified Chinese first: an English-only label
is not a translation gap, it is a missing source string.

**Exact correction, in three parts.**

*Already resolvable from the set.* Three of the eight have a Chinese string that exists but was never promoted
out of an example or a neighbouring section: `interaction-design.md:305` gives the mode names as `人机对弈` and
`自由对弈` inside its metadata examples, and `interaction-design.md:377` gives `删除前确认` for **Confirm
Before Deleting**. State that the mode entries, the History rows and the confirmation metadata all use the same
two mode strings, and that `删除前确认` is the setting's only name — then delete the English name from
`product.md:62,80` and `game-data.md:125,151,153` or mark it as a gloss.

*Needs new strings.* **Play**, **History**, **Settings**, and **Flip Board** have no Chinese anywhere in the set
and need four new source strings.

*Needs a product decision, not a designer's default.* **Resume Game**'s obvious Chinese rendering, `继续对局`,
is already taken — it is the "keep playing" action on the threefold notice (`interaction-design.md:350`, gated
at `testing.md:78`). The two ways out have different costs and the choice is the product owner's: (a) rename
the threefold action (e.g. `继续下棋`) and give `继续对局` to Resume Game, which touches an accepted, gated
string and its gate; or (b) leave the threefold action alone and give Resume Game a different string, which
touches nothing accepted. (b) is cheaper; (a) reads better on the Play destination, where "continue the game"
is the more natural phrase. I would not pick for you.

Finally, rewrite `interaction-design.md:533` so it stops asserting that the Chinese set is complete.

Related, same root: `product.md:34` supplies parenthetical English **inside an accepted section** —
"**我先手** (I Move First), **AI 先手** (AI Moves First), and **随机** (Random)" — which is unapproved English
copy under `interaction-design.md:533`'s own rule. Either mark them as non-normative glosses or delete them.

---

## 5. `cell` names two different rectangles, offset by half a pitch

**Severity: contradiction.** Both in accepted text, in one document, in the section a reviewer measures
against a screenshot.

`interaction-design.md:120`:

> a 7-by-7 board is 7-by-7 **points**: a **6-by-6 grid of cells** with 49 intersections, the outer points
> sitting on the border lines.

`interaction-design.md:142`:

> **Every marker stays inside its own cell.** A marker belonging to a point is contained within **that point's
> `1 p` by `1 p` cell** — for a circular marker, a radius of at most `0.50 p` …

The first is the 36 openings *between* the lines. The second is the 49 squares *centred on* the intersections.
They are the same size and offset by `0.5 p`, which is the worst possible kind of collision: an implementer
who takes line 120's definition and applies it to line 247 ("Four L-shaped corner brackets on both the origin
cell and the destination cell … inset `0.05 p` from each cell corner") draws the last-move brackets half a
pitch off the piece, and the drawing still looks plausible. The point-centred sense is load-bearing in lines
142, 240, 246, 247, 262 and in `testing.md:178` ("no marker leaves its own `1 p` cell"); the grid sense appears
once, at line 120.

**Which is right: the point-centred sense**, by weight of use and because every metric in the table is derived
from it. Line 120 is the outlier.

**Exact correction.** Change `interaction-design.md:120` to "a 7-by-7 board is 7-by-7 **points**: a 6-by-6 grid
with 49 intersections, the outer points sitting on the border lines." Deleting the two words "of cells" fixes
it with no other consequence — the sentence's job is to establish points, not to name the openings. Then add
one sentence to Board metrics fixing the term: "A **cell** is the `1 p` by `1 p` square centred on a point;
there are 49 of them and they tile the board core." Note that `half-cell margin` (lines 40, 125, 134, 149, 151)
and `cell pitch` (line 129) stay correct under either reading, so nothing else moves.

---

## 6. The keyboard focus ring is listed as a user of active ink and, three lines later, excluded from marker ink

**Severity: contradiction.**

`interaction-design.md:143`, one bullet, quoted with the two halves adjacent:

> Each style defines one **marker ink** per appearance, used at two strengths: **active ink**, at a contrast
> of at least 4.5:1, for selection, legal destinations, captures, check, and **focus**; and **record ink** …
> Because every game-state marker is carried by luminance and shape rather than by hue, the board under
> Differentiate Without Color is identical to the board without it; **the keyboard focus ring, which carries
> hue, is a platform affordance and never a game state.**

`interaction-design.md:253`:

> **Keyboard focus.** The focused point takes a rounded-square outline … **in the platform's focus colour**.
> … **It is the one marker that carries hue** …

`testing.md:181` gates the second reading: "Verify every game-state marker renders identically with
Differentiate Without Color enabled and disabled, **the keyboard focus ring excepted**."

**Which is right: focus is not marker ink.** Two accepted sentences and the gate agree; the word "focus" in
the active-ink list is the single dissenter, and it is also the only one of the five listed items that is not
a game state — the bullet's own closing clause says so.

**Exact correction.** Delete ", and focus" from `interaction-design.md:143`, leaving "for selection, legal
destinations, captures, and check". No other text changes; nothing downstream depends on focus being marker ink.

---

## 7. "illegal square" survived a merge that ruled out squares

**Severity: contradiction**, low blast radius but it is the exact mental model the contract says to protect.

`interaction-design.md:120`:

> The board is **never drawn as a checkerboard of squares**, which would be wrong to anyone who knows the game
> and would **teach a beginner the wrong mental model**.

Three accepted places still say square, all describing the same interaction:

> `interaction-design.md:227`: Tapping an **illegal board square** does not move the piece or cancel the current selection.
> `interaction-design.md:440`: … tapping an **illegal square** is a normal part of learning how the pieces move …
> `testing.md:159`: Verify the **illegal-square** haptic uses the lightest selection-weight feedback …

Meanwhile the marker section that owns the behaviour calls it correctly: `interaction-design.md:250` is headed
"**Illegal tap.**" and speaks of "the rejected **point**".

**Which is right: point / illegal tap**, per line 120 and per line 250's own heading.

**Exact correction.** `:227` → "Tapping an illegal point does not move the piece or cancel the current
selection." `:440` → "tapping an illegal point is a normal part of learning". `testing.md:159` →
"Verify the illegal-tap haptic …". `xiangqi-rules.md`'s use of "square" (lines 34, 36, 42, 44, 47, 75) and
`core-interface.md`'s `from_square` are a different vocabulary — coordinates and FEN — and should be left alone;
the two vocabularies are already separated by the accepted split between canonical notation and presentation
(`xiangqi-rules.md:36`).

---

## 8. Eight of nine end reasons and one of four outcomes have no accepted Chinese string

**Severity: gap.** This is the largest hole in the copy set and it is invisible because the one reason string
that exists is buried in an example.

`game-data.md:50` fixes the serialized `end_reason` vocabulary at nine values: `checkmate`, `stalemate`,
`perpetual-check`, `perpetual-chase`, `threefold-repetition`, `mutual-perpetual-check`,
`mutual-perpetual-chase`, `resignation`, `ended-early`. `game-data.md:49` fixes `outcome` at four:
`red-wins`, `black-wins`, `draw`, `none`.

Three accepted behaviours display a reason to the user:

> `interaction-design.md:340`: The card title is the localized equivalent of **红方获胜**, **黑方获胜**, or **和棋**. **A second line explains the result reason.**
> `interaction-design.md:296`: It shows the side to move for an ongoing game, **the result and reason** for a terminal game …
> `interaction-design.md:369`: Each entry shows its date, mode, **result or end reason**, and move count.

**Executed** — the only Chinese reason string in the whole set is `将死`, and it exists only inside the
composite example `红方获胜 · 将死 · 42 步` at `interaction-design.md:305`. Nothing defines Chinese for
stalemate, perpetual check, perpetual chase, threefold repetition, the two mutual reasons, resignation, or
`ended-early`. `ended-early` is the *most common* one — every save-before-mode archive produces it
(`product.md:50`, `game-data.md:79`) — and `outcome = none` has no string either, so the History row for the
commonest kind of record is unspecified.

`testing.md:68` gates it anyway: "Verify factual metadata for mode, human side when applicable, ongoing side
to move or **terminal result and reason**, claim availability, and move count." There is nothing to verify
against.

**Exact correction.** Define ten strings in `interaction-design.md` beside the result card, as one table:
the four outcomes (`红方获胜`, `黑方获胜`, `和棋`, and a string for `none`) and the nine reasons. `将死`
already exists and should be promoted out of the example. I will not invent the other nine here — reason
wording for a teaching app is a product decision, and two of them (`mutual-perpetual-check` /
`mutual-perpetual-chase`) name outcomes whose adjudication `xiangqi-rules.md:68` still defers, so their copy
should be written together with those fixtures rather than ahead of them. What the contract needs now is the
table's existence and the note that `ended-early` needs both a reason string and an `outcome = none` string.

Two smaller members of the same family: `interaction-design.md:305` gives `你执红` with no `你执黑`
counterpart, and `interaction-design.md:369` requires "imported records have a visible imported marker" with
no string for it.

---

## 9. `判和` is an orphan string that contradicts the two draw-claim strings that do exist

**Severity: contradiction** (or a typo, which is the same repair).

`interaction-design.md:313`:

> The confirmation does not add **悔棋** or **判和** actions.

**Executed** — `判和` occurs exactly once in the entire contract set. The accepted draw-claim vocabulary is
`可判和` (the persistent affordance, `:272`, `:352`, gated at `testing.md:78`) and `以和棋结束` (the action
that commits the draw, `:350`, `:351`). `判和` is a third form, bolded exactly like a real string, sitting
beside `悔棋`, which *is* a real string.

**Which is right: `可判和`.** That is what the board actually offers at the moment line 313 is describing —
line 313's own next sentence says "the user can resume it and use the board's normal Undo or draw-claim
controls", and the board's draw-claim control is the `可判和` affordance.

**Exact correction.** `interaction-design.md:313` → "The confirmation does not add **悔棋** or **可判和**
actions."

---

## 10. `testing.md` gates the "compose-beat floor", a term defined only in a non-normative section

**Severity: gap**, and the cleanest instance of "gated but not defined" in the set.

`testing.md:169`:

> Verify the AI's piece departs no earlier than **the compose-beat floor** after the player's move has finished
> animating, including after a capture …

**Executed** — `compose` appears five times in `docs/`. Three are the unrelated verb "composes". The other two
are `testing.md:169` and `interaction-design.md:528`, which is a **Need to discuss** bullet — explicitly
non-normative, authorizing nothing. The accepted text that actually specifies the behaviour,
`interaction-design.md:424`, never uses the name:

> **The AI's move has a floor, not a delay.** Its piece departs at the later of two instants: when the search
> returns, and **260 ms** after the player's own move has finished animating …

So a release gate names a value by a term whose only occurrences are a test gate and a question. Separately,
"beat" now names two unrelated things: this floor, and the **acknowledgment beat** on the turn-status element
(`interaction-design.md:258`, gated at `testing.md:182`).

**Exact correction.** Name the value in the accepted text: add "This **compose beat** is 260 ms." to
`interaction-design.md:424`, or drop the name and rewrite `testing.md:169` as "no earlier than 260 ms after
the player's move has finished animating". The second is smaller and removes the "beat" collision; I prefer it.

---

## 11. Exact-copy gates cover 27 of 58 strings, with no rule for which

**Severity: gap.**

**Executed.** 27 strings carry an exact-copy gate in `testing.md`; 31 do not. The 31 ungated ones:

```
轮到红方  轮到黑方  你  红方获胜  黑方获胜  和棋  已记录到历史
局面已三次重复，可以和棋结束。  删除这盘棋？  删除后无法恢复。  删除  共享  置顶  取消置顶
当前可用内存不足。请尝试关闭一些其他 App，然后重试。
本局设置  AI 等级  人机对弈默认设置  默认先后手  默认 AI 等级
人机对弈 · 你执红   自由对弈   进行中 · 轮到黑方 · 42 步
红方获胜 · 将死 · 42 步   进行中 · 可判和 · 42 步
传统  现代  高对比  汉字  图标  判和
```

The standard is visibly inconsistent within one bullet list. `testing.md:67` and `:73` quote every word of two
alerts:

> Verify the exact fixed copy: **开始新对局？**, metadata header **当前对局**, **这盘对局将按当前状态保存到历史。**, **取消**, and **保存并继续**.

while `testing.md:82`, for a structurally identical alert, says only:

> Verify **删除前确认** defaults on … **Test the accepted confirmation copy**, Cancel, confirmed deletion …

— which leaves `删除这盘棋？` and `删除后无法恢复。` unpinned. The same happens to the threefold notice
(`testing.md:78` quotes the two actions but not `局面已三次重复，可以和棋结束。`) and to the low-memory alert
(`testing.md:83` says "the accepted insufficient-memory title, message, Cancel, and Retry actions";
`testing.md:139` quotes the title only, never `当前可用内存不足。…`). The turn status — the element on screen
for the entire game — has no copy gate at all: `testing.md:76` gates "the turn-status matrix" without quoting
`轮到红方`, `轮到黑方`, `你`, or `将军`'s companions.

**Which is right: quote everything.** The set is 58 strings; the cost of quoting them is a page, and the
reason to quote them is stated in the contract itself — `interaction-design.md:455` makes the Chinese copy
*normative and exact*, and copy that is exact but ungated is exact only by accident.

**Exact correction.** Extend the quoting style of `testing.md:67` to the delete confirmation, the threefold
notice text, the low-memory message, the turn status, the result-card titles and `已记录到历史`, and the
Settings and per-game group labels. Or, cheaper and better: add one bullet — "Verify every string in the
accepted copy inventory renders byte-identically to the contract, in every state that presents it" — and put
the inventory in `interaction-design.md` as a table. The table is worth having anyway: it did not exist before
this audit, which is why the four defects in §§8–9 and §13 went unnoticed.

Note also `testing.md:81` and `:82`, adjacent bullets on the same feature, name the same controls in different
languages — ":81 … icon-and-text labels, **Share and Delete** colors, immediate **Pin or Unpin**, full-swipe
**Delete**" against ":82 Verify **删除前确认** …" — while the contract's names for those controls are `共享`,
`删除`, `置顶`, `取消置顶`.

---

## 12. `profile` names three different things

**Severity: ambiguity.**

1. A **difficulty level**: `engine-integration.md:88` "AI difficulty profiles", `:90` "Accepted search-profile
   policy", `:116` "The accepted levels are relative app **profiles** rather than calibrated Mini Xiangqi
   ratings", `testing.md:130` "the accepted 1-, 3-, and 5-second **profiles**", `testing.md:210` "thresholds
   for each AI **profile**".
2. A **build identity**: `core-interface.md:39` "the **engine profile identifiers** — core revision, pinned
   fork revision, variant identifier, and NNUE SHA-256", `:243` "The C API version, archive format version,
   store schema version, and **engine profile** are four independent axes".
3. An **option set**: `architecture.md:22` "with the **option profiles**, cancellation, and lifecycle defined
   in engine-integration.md", `engine-integration.md:9` "packaged engine artifacts, **option profiles**,
   lifecycle integration".

The collision is not theoretical. `core-interface.md:131` says `MxqSearchResult` carries "bounded diagnostics
(score, depth, nodes, elapsed, **profile identifier**)" and `mxq_engine_query` returns `out_profile_id` —
a reader coming from `engine-integration.md:116` will read that as the difficulty level, which is already
carried separately as `ai_level`. `engine-integration.md:110` ("Engine, variant, NNUE, and option identifiers
are versioned with **the internal profile**") mixes senses 2 and 3 in one sentence.

**Exact correction.** Keep exactly one. Sense 2 is the one with an identifier in the C header, so it keeps
`profile`. Rename sense 1 to **level** throughout (`engine-integration.md:88` → "AI difficulty levels",
`:90` → "Accepted search-level policy", `:116` → "relative app levels", `testing.md:130,210`), which also
matches the user-facing `AI 等级`. Rename sense 3 to **option set** (`architecture.md:22`,
`engine-integration.md:9`, `:110`).

---

## 13. The fixture field is called `variant`, which is the one word `game-data.md` says it is not

**Severity: ambiguity**, with a real trap behind it.

`fixtures/rules/README.md:24`:

> `variant` — the ruleset identity the position is defined against; always `minixiangqi`. **This names the
> Mini Xiangqi ruleset of the rules contract, not an engine variant to select**: the engine configuration that
> must satisfy these fixtures … is defined in docs/engine-integration.md, and **the built-in engine variant of
> the same name does not satisfy every fixture.**

`game-data.md:38` names the identical concept differently, and with the identical warning:

> `rules_id` (`minixiangqi`, **the ruleset identity of xiangqi-rules.md, not an engine variant**) …

One concept, two field names, and the fixture's chosen name is the exact word both documents spend a clause
disowning. The trap is concrete: `engine-integration.md:132` names the real engine variant
**`minixiangqiaxf`**, and `:128` records that built-in `minixiangqi` fails `mx-chs-001` and `mx-chs-004`,
while `:127` records it fails `mx-chs-003`. A harness author who reads `"variant": "minixiangqi"` as a
selector configures the engine that is known to fail three of the sixteen fixtures.

**Which is right: `rules_id`.** It is the name in the serialized vocabulary that `xiangqi-rules.md:84` and
`core-interface.md` both reference, and it needs no disclaimer.

**Exact correction.** Rename the fixture field `variant` → `rules_id` in all sixteen files and in
`README.md:24`, and delete the now-unnecessary "not an engine variant to select" clause, keeping only the
sentence about built-in `minixiangqi` not satisfying every fixture. `README.md:17`'s immutability rule covers
"`id`, position, moves, and assertions", so a field rename is outside it — but it is still a schema change and
should be reviewed as one.

---

## 14. `无法保存对局`'s two actions are defined only for the flow it was written for

**Severity: ambiguity.** Copy that a merged decision made reachable from a second caller, without the
surrounding text following.

`interaction-design.md:317–323` defines the alert inside "Saving the active game before choosing a new mode":

> Title: **无法保存对局** / Message: **当前对局仍然保留。请重试。** / Actions: **取消** and **重试**.
> … Cancelling the error **discards it** [the requested destination]; retrying **repeats the same atomic
> archive operation**.

Two later, accepted statements route other failures into the same alert:

> `interaction-design.md:230`: A failed draw claim, resignation, or result confirmation uses the accepted
> **无法保存对局** retry presentation and leaves the game active and unchanged.
> `core-interface.md:210`: any store-domain failure from `mxq_store_archive_and_clear` **or a terminal commit**
> drives the accepted 无法保存对局 retry flow …

For a failed `mxq_game_confirm_result` there is no "requested destination" for `取消` to discard, and `重试`
repeats a terminal commit rather than "the same atomic archive operation". The title and message survive the
reuse cleanly — `当前对局仍然保留` is true in every case — but the two actions' defined semantics do not.

**Exact correction.** Move the alert's definition out of the save-before-mode section into a shared subsection,
and restate the actions caller-independently: "`重试` repeats the failed operation; `取消` dismisses the alert
and leaves the game active and unchanged, discarding any temporarily selected destination." Then
`interaction-design.md:230` and `core-interface.md:210` point at one definition instead of borrowing one.
(Also: `core-interface.md:210` is the only place in the set that writes `无法保存对局` unbolded, and
`engine-integration.md:194` the only place that writes `取消` unbolded. Cosmetic, but the bold is what marks a
string in this set.)

---

## 15. Smaller findings

**15.1 `可判和` is both a button and a read-only status token.** Severity: ambiguity. It is the label of the
persistent affordance that claims the draw (`interaction-design.md:272`, `:352`) and also a metadata value in
the save-and-continue confirmation, `进行中 · 可判和 · 42 步` (`:305`), where `:305` insists "The metadata
reports facts and does not ask the user to classify the result." A word that is a button everywhere else is a
poor choice for a non-interactive fact. Correction: use a distinct status token in the metadata line — the
concept there is "a draw may be claimed", not the control.

**15.2 The piece-style and piece-symbol names are typeset as accepted copy but are not accepted copy.**
Severity: ambiguity. `传统`, `现代`, `高对比`, `汉字`, `图标` are bolded exactly like the 53 strings that *are*
accepted user-facing copy, while `interaction-design.md:535` says "Decide whether the piece-style and
piece-symbol names are user-facing interface strings or internal design names, and approve their wording if
they are user-facing." The document's own typographic convention contradicts its open question. Correction:
until 535 is answered, set them as code or italic rather than bold, or add a parenthetical "(design names,
not yet approved as interface strings)".

**15.3 "persistent origin and destination markers" collides with two other defined markers.** Severity:
ambiguity. `interaction-design.md:414`: "An AI move … leaves **persistent origin and destination markers** so
the player can identify the completed move." But `origin marker` is the drag-origin hollow dot in record ink
(`:141`, `:251`) and `destination dot` is the legal-destination dot in active ink (`:245`), and `:247`
explicitly says "The AI's move uses **these same brackets** rather than a second marker". Correction: `:414`
→ "leaves the last-move brackets on the origin and destination cells".

**15.4 "notice" names both a custom glass surface and a system alert.** Severity: ambiguity. The threefold
**notice** (`:350`) is one of the three custom glass surfaces (`:38`); the insufficient-memory **notice**
(`:282`) has Title/Message/Actions and, since it is not among the three, must be a system alert. Correction:
call the second one an alert.

**15.5 "the Play start state" is used once and never defined.** Severity: ambiguity.
`interaction-design.md:344`: "**完成**, which returns to **the Play start state**." Elsewhere the destination
is "the Play destination" (`:296`), which is specified only for the case where an active game exists — and
after `完成` there is none. `interaction-design.md:537` defers "empty, loading, … states", so this is a
forward reference to undefined work. Correction: say "returns to the Play destination" and let `:537` own
what it shows with no active game.

**15.6 "the localized equivalent of" appears for two strings and nowhere else.** Severity: ambiguity.
`:268` ("using the localized equivalent of **轮到红方** or **轮到黑方**") and `:340` ("The card title is the
localized equivalent of **红方获胜** …") hedge in a way that reads as though the Chinese is itself a
localization of some source, which `:455` says it is not. Correction: state them flatly like the other 56.

**15.7 No accepted Chinese product name.** Severity: gap. `product.md:11` fixes "The product name is
**Mini Xiangqi**", `interaction-design.md:455` makes Simplified Chinese the source language, and nothing says
whether the product name localizes (`:461` exempts only the piece characters). The app needs a display name
in its source language on day one. Whether it localizes at all is the product owner's call, not a designer's:
leaving it "Mini Xiangqi" is defensible for an internal build and costs nothing; giving it a Chinese name is
also defensible and costs one string plus a decision about the Windows package name.

**15.8 `App` in the low-memory message is Apple house style.** Severity: ambiguity.
`当前可用内存不足。请尝试关闭一些其他 App，然后重试。` uses Apple's Simplified Chinese convention of leaving
"App" in Latin. Microsoft's Simplified Chinese convention is `应用`. `product.md:24` requires "presentation
follows each platform's conventions", so one normative string cannot satisfy both. Correction: either accept
one form for both platforms and say so, or record the Windows variant now while the string is being written.

**15.9 Unlabelled controls in specified groups.** Severity: gap; sub-case of §4/§8. `interaction-design.md:191`
gives the per-game group `本局设置` and the level control `AI 等级`, but the first-mover control inside it has
no label, while its Settings twin does (`默认先后手`, `:209`). `:209` requires a footer — "Its footer explains
that these values initialize future human-versus-AI setup and do not change an active game" — whose text is
not given. `product.md:81–83` accepts four more Settings rows (sound toggle, haptics toggle, piece style,
piece symbols) with no strings at all. The play screen's own Undo control has no defined label; `悔棋` is
defined only as the result-card action (`:341`), and `:313` uses it as though it were the general Undo name.

**15.10 The accepted piece characters are gated for rendering but not for assignment.** Severity: gap.
`testing.md:153` verifies the characters "all resolve to the same Chinese font family … with matching advance
widths"; nothing gates that Red draws `帅` and Black `将`, or that the cannon pair is `炮`/`砲` rather than the
`包` that `interaction-design.md:70` records the source's summary table as giving. Correction: add "Verify each
piece type draws its accepted Red and Black character per the table in `interaction-design.md`."

---

## 16. What I checked and found clean

Recorded so the absence of a finding is distinguishable from an absence of checking.

- **No Chinese string differs in wording between documents.** Executed, over all 58; every multi-document
  string is byte-identical, including spacing around Latin runs.
- **No `testing.md` gate quotes a Chinese string that no contract defines.** Executed; the reverse direction
  is §11, and the English-label version of the problem is §4.
- **Terminal punctuation and question marks are consistent.** All seven messages end `。`; both question
  titles end `？`; no statement title carries punctuation.
- **AI level names, times and identifiers agree in four documents.** `快速`/`标准`/`深思` ↔ 1/3/5 s ↔
  `go movetime 1000/3000/5000` ↔ `fast`/`standard`/`deep`, with `标准` the new-install default:
  `product.md:37`, `interaction-design.md:195,209`, `engine-integration.md:96–101`, `game-data.md:48`,
  `testing.md:63,122`.
- **The state and reason identifier vocabularies agree across four sources.** `xiangqi-rules.md:92`,
  `fixtures/rules/README.md:33`, `game-data.md:49–51`, `core-interface.md:101–103`, and all sixteen fixture
  files use the same spellings, and the deliberate `MxqOutcome`/`MxqGameStatus.state` split is stated
  identically in both places that describe it.
- **The `保存并继续` classification rules agree in three documents** — `product.md:50,51`,
  `interaction-design.md:309–311`, `game-data.md:79–81` — including the awkward case (an unclaimed claimable
  repetition archives as ended-early, not as a draw).
- **`game-data.md:151`'s "seven persistent preferences" is seven**, and matches `product.md:78–83` item for item.
- **Board metrics arithmetic is self-consistent.** Executed: `7 p` = 308 at `p = 44`; disc `0.80 p` = 35.2;
  symbol `0.50 p` = 22; marker band 18.48–22 ("18.5 to 22"); grid `0.026 p` = 1.144 ("1.14") reaching the
  1.60 ceiling at `p ≈ 61.5` ("about 62"); numeral size `0.32 p` = 14.08 → 14; strip height
  `0.08 p + 0.887 s` = 15.94 → 16, board block 308 × 340, hiding both strips returning 32.
- **The seven move-travel durations follow the stated rule.** Executed: `180 + 60·(√d − 1)/(√6 − 1)` gives
  180, 197, 200 (horse, `d = √5`), 210, 221, 231, 240, which rounds to 5 ms as the published 180, 195, 200,
  210, 220, 230, 240.
- **`mx-move-001`'s rationale matches its data.** Executed by hand from the frozen FEN: 9 soldier moves
  (a2a3, a2b2, c2b2, c2c3, d2d3, e2e3, e2f2, g2f2, g2g3) plus 10 cannon slides (b1b2–b1b6, f1f2–f1f6) = the
  19 listed moves, and b7/f7 are indeed unreachable with zero screens.

---

## 17. Ranked summary

| # | Severity | Finding | Smallest fix |
|---|---|---|---|
| 2 | contradiction | `king` vs `General` for one piece, inside single documents | rename to General in 4 docs + 6 fixtures |
| 3 | contradiction | fixtures say "white"/"rook" beside "Red" | prose-only rename in 9 fixtures |
| 4 | contradiction | 8 controls English-only; `:533` claims the reverse | define Chinese labels; rewrite `:533` |
| 5 | contradiction | `cell` = 36 openings and 49 point-squares | delete "of cells" at `:120`; define the term |
| 6 | contradiction | focus ring both is and is not marker ink | delete ", and focus" at `:143` |
| 7 | contradiction | "illegal square" against points-not-squares | 3 word swaps |
| 8 | gap | 8/9 end reasons, 1/4 outcomes have no Chinese | add the reason/outcome copy table |
| 9 | contradiction | orphan `判和` | → `可判和` |
| 10 | gap | gate names "compose-beat", defined nowhere normative | inline 260 ms in the gate |
| 11 | gap | 31/58 strings have no exact-copy gate | one inventory table + one gate |
| 12 | ambiguity | `profile` names three things | level / option set / profile |
| 13 | ambiguity | fixture field `variant` is the disowned word | → `rules_id` |
| 14 | ambiguity | `无法保存对局` actions defined for one caller only | move to a shared subsection |
| 15 | ambiguity/gap | ten smaller items | see §15 |
