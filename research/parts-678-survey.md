# Parts 6, 7 and 8 — what is actually still open

Workspace-only research evidence. Part of no repository. Non-normative: nothing here is a decision, and
nothing here authorises implementation. The contracts are `MiniXiangqi/docs/*.md`; this file only says what
those documents currently do and do not settle.

Prepared for the dispatch of nine parallel researchers across the three remaining design parts.

## Method, and what each claim rests on

- **Executed.** `git log`/`git show`/`git branch -vv` in `/Users/tianren/coding/minixiangqi/MiniXiangqi`;
  `gh pr list`, `gh issue view 2 --comments` read-only after sourcing the control identity (active account
  `ppppvz`, confirmed). Text extraction of every bolded Chinese and English string in the contracts by a
  throwaway Python pass.
- **Read.** All eight documents in `MiniXiangqi/docs/` at `main` = `1639da5` (working tree clean), in full for
  `interaction-design.md`, `testing.md`, `product.md`, `xiangqi-rules.md`, and in the relevant parts for the
  other four. Issue #2's body and all ten comments. PR #23's body (open, not merged).
- **Read (Apple).** `mcp__xcode__DocumentationSearch`, three queries. Findings and the honest negatives are in
  the last section.
- **Reasoned.** Every "already answered / partly answered" verdict, every collision between parts, and the
  suggested nine-way partition. These are my judgements about what the accepted text entails and are the
  things to disagree with.

Repository state at the time of writing: `main` is `1639da5` (merge of #24). Merged: #19, #20, #21, #22, #24.
**Open: #23 only** (part 4, app shell and layout), and issue #25 (restructure).

---

## 0. Corrections to the register before anyone starts

These are the traps. Two of them are of exactly the kind that has cost time twice.

### 0.1 Issue #2's own table is stale

| Part | Issue #2 says | Actually |
|---|---|---|
| 1 Rules adjudication | `decided · PR #22` | **merged**, #22 at 2026-07-28T02:16Z |
| 2 Engine lifecycle | `decided · PR #21` | **merged**, #21 at 2026-07-28T02:43Z |
| 5 Frame, motion, glass | `decided · PR pending` | **merged**, #24 at 2026-07-28T02:49Z |
| 4 App shell, layout | `decided · PR #23` | **open and rejected** — 13 blocking findings, being rewritten |

Consequence for parts 6–8: **part 4 is the only design part whose text is not yet in the contracts.** Anything
a part-6/7/8 researcher reads in PR #23's diff or body is *not* accepted and must not be treated as such —
including the resignation copy **确认认输？** / **认输后本局将记为你落败。**, the Free Play flip control
**翻转棋盘**, the three-control play cluster, the 380 × 500 pt minimum, the 720 pt board cap, and the 375 pt
iPhone. Part 6 in particular must not "approve English counterparts" for strings that are not yet accepted
Chinese.

### 0.2 Two items listed as open are substantially already answered

- **"Define help entry points"** (`interaction-design.md:527`). The accepted Help section already fixes the
  entry points at the destination level: *"Help is reachable from Settings and from the game screen without
  abandoning or pausing state: opening help never modifies the active game, and returning restores the exact
  prior context."* What is open is the concrete affordance, placement and label at those two entry points —
  not *whether* or *from where*.
- **"Define empty, loading, AI-thinking, error, corrupted-import, and destructive-action states"**
  (`interaction-design.md:537`). This bullet has survived unedited since the first contract commit `b5846ff`
  while four of its six categories were substantially decided underneath it. See §Part 7, item 7.5 for the
  itemised list of what is already accepted. Reopening the whole bullet would re-litigate merged work.

### 0.3 One item is narrower than it reads

**"Decide whether a pointer previews a piece's legal destinations on hover"** (`interaction-design.md:522`,
issue #2 files it under part 7). PR #19 already accepted the pointer-hover marker and said what it means:
*"The point under the pointer takes a faint rounded-square fill … It reports where the pointer is, not what is
legal,"* and the marker families rule that hover and focus *"report where an input device is, never what the
game is doing, and their shape is what says so."* So the visual question is closed; what survives is a pure
product-scope question — does a hover preview belong beside the accepted exclusion of hints and analysis. If
the answer is yes, the accepted destination-dot marker is the only vocabulary available for it.

### 0.4 One item is dual-owned and must be assigned once

**The localization review process** appears as an open item in *two* documents: `interaction-design.md:534`
(part 6) and `testing.md:211` (part 8, phrased as "and how approved English copy is validated against the
accepted Chinese source copy"). One decision, two homes. Give it to one researcher and have the result land in
both documents; do not brief two people on it.

### 0.5 One item is dual-owned across contracts, already routed

**What a player sees when re-preparation fails mid-game** appears at `engine-integration.md:194` and
`interaction-design.md:526`. The engine contract explicitly routes it — *"this belongs to
interaction-design.md"* — so it is one part-7 question, and the fix must also delete the engine document's
copy of it.

### 0.6 A real defect the register does not name

The localization contract says *"Simplified Chinese is the source language: the accepted user-facing copy in
this document is normative, and its English counterparts are translations of it."* But several user-facing
elements are named in the contracts **only in English, with no accepted Chinese source at all**:

- the three navigation destinations **Play**, **History**, **Settings** (`interaction-design.md:21–23`,
  `product.md:72–74`);
- the two mode entries **Human versus AI** and **Free Play** (`interaction-design.md:183`, `product.md:33`);
- **Resume Game** (`interaction-design.md:296`);
- **Flip Board** (`interaction-design.md:214`, and the History-replay orientation control);
- **Confirm Before Deleting** in `product.md:62` and `game-data.md:125`, whose Chinese counterpart
  **删除前确认** *is* accepted at `interaction-design.md:377` — so the same preference is named in different
  languages in different accepted contracts.

Part 6 is therefore not only "approve English for accepted Chinese". It is also **"supply accepted Chinese for
the elements that only have English"**, which is the direction the stated source-language rule actually
requires. Nobody has written this down anywhere.

### 0.7 A terminology conflict between two accepted contracts

`interaction-design.md:74` (accepted, PR #15): *"English piece names are General, Chariot, Horse, Cannon, and
Soldier."*
`xiangqi-rules.md:24–28, 45` (accepted, PR #13): *"Each side has a **king**, chariots, horses, cannons, and
soldiers"*, *"A **king** moves one square orthogonally inside its palace"*, and repeatedly "king safety",
"facing kings", "king palace confinement", plus the fixture identifier prose.

Two accepted contracts use different English words for the same piece. `xiangqi-rules.md` is arguably using
"king" as engineering vocabulary rather than user-facing copy, but it is not marked as such, and the fixture
and FEN vocabulary (`k`, `mx-move-005`) reinforce it. This is a live part-6 item and it is a *correction*, not
a new decision.

---

## Part 6 — wording and localization

Owning document for all of these: `interaction-design.md` (it owns localization by its own scope line), except
where noted.

### 6.1 English counterparts of the accepted Chinese copy

**Question.** What is the approved English string for each accepted Chinese user-facing string, given that
Chinese is the normative source and no English build is currently fully specified?

**Owner.** `interaction-design.md:533`. Downstream consumers: `product.md`, `game-data.md`, `testing.md`.

**Already answered, in part.**
- Accepted English already exists for four things and must be reused rather than re-decided: the piece names
  **General / Chariot / Horse / Cannon / Soldier** (`interaction-design.md:74`); the three setup options,
  glossed in `product.md:33` inside accepted text as **我先手** (I Move First), **AI 先手** (AI Moves First),
  **随机** (Random); **删除前确认** = **Confirm Before Deleting** (`product.md:62`, `game-data.md:125`); and
  the AI levels' *serialized* identifiers `fast` / `standard` / `deep` (`game-data.md`), which are machine
  values, not copy, but constrain what the English level names may sensibly be.
- The accepted text repeatedly says *"the localized equivalent of"* — for **轮到红方/轮到黑方**
  (`interaction-design.md:268`) and for **红方获胜 / 黑方获胜 / 和棋** (`:340`) — which is an explicit
  instruction that an English equivalent exists and is required, not a suggestion.

**Still open.** The strings themselves. The inventory below is what I extracted; it is the scope of this item.

*Fifty-eight distinct accepted Chinese strings in `interaction-design.md`, by line of first appearance:*

| Group | Strings |
|---|---|
| Nav / modes | *(none in Chinese — see §0.6)* |
| Play controls & actions | 开始对局 · 结束对局 · 完成 · 保存并继续 · 取消 · 重试 · 悔棋 · 判和 · 回放 · 继续对局 · 以和棋结束 · 删除 · 共享 · 置顶 · 取消置顶 |
| Pre-start setup | 本局设置 · 我先手 · AI 先手 · 随机 · AI 等级 · 快速 · 标准 · 深思 · 你将控制红黑双方，红方先行。 |
| Settings | 人机对弈默认设置 · 默认先后手 · 默认 AI 等级 · 删除前确认 |
| Turn status | 轮到红方 · 轮到黑方 · 你 · AI · 将军 · 可判和 |
| Result card | 红方获胜 · 黑方获胜 · 和棋 · 已记录到历史 |
| Alerts / notices | 开始新对局？ · 当前对局 · 这盘对局将按当前状态保存到历史。 · 无法保存对局 · 当前对局仍然保留。请重试。 · 无法启动 AI 对手 · 当前可用内存不足。请尝试关闭一些其他 App，然后重试。 · 局面已三次重复，可以和棋结束。 · 删除这盘棋？ · 删除后无法恢复。 |
| Transient | 无法保存这一步，请重试。 |
| Metadata examples (patterns, not literals) | 人机对弈 · 你执红 · 自由对弈 · 进行中 · 轮到黑方 · 42 步 · 红方获胜 · 将死 · 42 步 · 进行中 · 可判和 · 42 步 |
| Design names, status contested | 传统 · 现代 · 高对比 · 汉字 · 图标 — see 6.6 |

Not in scope, and must not be translated: the ten piece characters (帅将俥车傌马炮砲兵卒) and the notation
tokens (进 退 平 前 后), all fixed as **game content** by `interaction-design.md:73` and the notation section.

**Decision type.** *Mostly designer's call, with an owner-level frame.* Writing idiomatic English for each
string is a designer's job. Two things are the owner's: (a) the register — the Chinese copy is terse and
declarative (**删除后无法恢复。**), and English can be either equally terse or softer, and that choice is a
product voice decision; (b) whether the metadata *patterns* (`进行中 · 轮到黑方 · 42 步`) keep the middle-dot
composition in English or become a different structure, since English words are longer and the stacked layout
has no spare width.

**Trap.** Do not translate strings from PR #23. See §0.1.

### 6.2 The reverse gap — Chinese for the English-only elements

**Question.** What are the accepted Chinese strings for Play, History, Settings, Human versus AI, Free Play,
Resume Game, Flip Board, and Confirm Before Deleting, which the contracts currently name only in English?

**Owner.** `interaction-design.md`. Not listed anywhere as an open item — see §0.6.

**Already answered.** Only 删除前确认, which exists at `interaction-design.md:377` and simply needs the other
two documents brought into line.

**Decision type.** Designer's call for the wording; the *finding* that they are missing is not a decision at
all, it is a defect in the contract that part 6 should close.

### 6.3 English Xiangqi terminology beyond the piece names

**Question.** What is the app's English vocabulary for the rules, results and controls — check, checkmate,
stalemate, palace, file, rank, repetition, claim, perpetual check, perpetual chase, ended early, resignation,
undo, replay — and is the general called a General or a King?

**Owner.** `interaction-design.md:534`.

**Already answered, in part.** The *machine* vocabulary is frozen and should anchor the English copy without
being mistaken for it: `game-data.md` fixes the serialized reasons `checkmate`, `stalemate`,
`threefold-repetition`, `perpetual-check`, `perpetual-chase`, `resignation`, `ended-early`, and the outcomes
`none` / `draw` / red-wins / black-wins; `xiangqi-rules.md` fixes the same reason identifiers for fixtures.
"Palace", "file", "rank", "screen" (for the cannon) are used consistently in accepted rules prose.

**Still open.** The user-facing set, and the General/King conflict of §0.7. Also unresolved: what the English
build calls the notation itself, given that the move list stays in Chinese characters (see 6.5).

**Decision type.** *Designer's call*, with one owner question inside it: General vs King is a teaching
decision — "General" matches the Chinese 将/帅 and international Xiangqi usage, "King" is what a chess-literate
learner already knows. The product exists for Xiangqi education, which argues for General, but that is the
owner's to affirm because it also means correcting an accepted rules contract.

### 6.4 The localization review process

**Question.** By what process is English copy proposed, reviewed and accepted against the normative Chinese,
and what evidence does an internal build need that the two agree?

**Owner.** *Two* documents: `interaction-design.md:534` and `testing.md:211`. See §0.4 — one researcher.

**Already answered, in part.** `testing.md:157` (draft) already gates *"Verify the app follows the operating
system's language selection, including through an Apple per-app language change, and that it offers no
interface-language control of its own."* `interaction-design.md:457–459` accepts the design constraints: no
text in visual assets, layouts tolerate length differences, terminology consistent within each language.
Nothing about *process*.

**Decision type.** *Owner's decision.* This is about who signs off and what evidence is retained, in a project
with one internal reviewer and a small internal audience. The realistic options and their costs:
- **Contract-as-source-of-truth**: every string lives in the contract in both languages, and a PR review is
  the localization review. Zero new machinery; the contract grows and every copy tweak becomes a contract
  change.
- **String catalog as source of truth** with the contract holding only the strings whose exact wording is a
  product decision. Lower friction; the risk is drift between the two, which is what the current
  Chinese-only/English-only split already demonstrates.
- **Reviewed export/import round trip** (Xcode's XLIFF export, `Importing localizations`) with a named
  reviewer per language. Heaviest, and defensible only if a second English-native reviewer actually exists.

The owner picks; the consequence to state is that option 1 is the only one that keeps "the accepted copy is
normative" literally true.

### 6.5 Traditional notation's unhandled cases

**Question.** How does the move list render a move when the accepted 前/后 disambiguation does not suffice —
principally three or more same-type pieces sharing a file?

**Owner.** `interaction-design.md:519`.

**Already answered.** The two-piece case only: *"When two pieces of the same type stand on one file, the move
opens with 前 or 后 before the piece name and omits the file entirely — 前炮退二, not 炮前退二. 后 names the
piece nearer its own side and 前 the one nearer the opponent, a sense that is relative to the moving side."*
Everything else in the notation is accepted: file numbering from each player's own right, Chinese numerals for
Red and Arabic for Black *for every number in a move*, 进/退/平, rank-count values for chariot/cannon/soldier/
general and destination-file values for the horse.

**Still open, and bounded exactly.** From the frozen starting FEN
`rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1`, each side has 2 chariots, 2 horses, 2 cannons, 1 general
and **5 soldiers** (twelve pieces, as `product.md` states). So:
- **Only soldiers can reach three or more on one file** — every other type is capped at two, and there is one
  general. The board has 7 ranks, so up to 5 soldiers can in principle share a file. The unhandled range is
  three, four and five.
- A **second** unhandled case the contract does not name: same-type pieces doubled on *more than one file at
  once*. Two soldiers on file 3 and two on file 5 both qualify for 前/后, and the accepted rule *"omits the
  file entirely"*, so 前兵进一 becomes ambiguous. This is reachable with five sideways-capable soldiers and is
  a real gap in the accepted text, not a hypothetical.

Conventional Xiangqi answers exist for both (前/中/后 for three; positional numerals 一二三四五 counted from
the front for four and five; file retained alongside the marker when several files are doubled), but they vary
between sources and none is in the retained normative source, so this needs an explicit interpretation the way
the rules interpretations were recorded.

**Decision type.** *Designer's call*, with the caveat that whatever is chosen becomes an interpretation of a
convention rather than a reading of the normative source, and should be recorded as such — the same discipline
`xiangqi-rules.md` used for 一将一捉.

### 6.6 The notation test oracle

**Question.** Which table of positions and expected move strings is approved as the authority against which
the traditional-notation renderer is verified?

**Owner.** `interaction-design.md:520` for approval; `testing.md:186` already states the requirement.

**Already answered.** The *required coverage* is fully enumerated and accepted in draft `testing.md`: file
numbering from each side's own right; each side's own numerals used for every number; 进/退 carrying a rank
count for chariot, cannon, soldier and general but a destination file for the horse; 平 carrying a destination
file; and 前/后 leading the move, before the piece name and without a file, when two same-type pieces share a
file — *"That table is the oracle and must be approved alongside the notation itself, since the fixtures record
only canonical coordinates."* So the oracle's specification exists; the table does not.

**Still open.** The table. Note the dependency: it cannot be completed before 6.5, because it must cover the
three-or-more case once that is decided. Note also the coupling to part 8 — `testing.md` is wholly draft, so
this gate is currently non-binding whatever the table says.

**Decision type.** *Designer's call*, mechanical once 6.5 lands. The `fixtures/rules/` directory and the
frozen coordinate notation give a ready source of positions; the oracle is a presentation-layer artefact and
does not belong in `fixtures/rules/`, whose schema and immutability rules are already accepted for rules
conformance.

### 6.7 What an icon-symbol reader gets for the move list

**Question.** A user who selects **图标** cannot read the character-based move list; are they offered anything
beyond it?

**Owner.** `interaction-design.md:520` (first clause).

**Already answered.** The premise is settled: *"A user who selects icon symbols still reads a character-based
move list, since traditional notation names pieces by their characters."* The move list is not changing. Only
"whether that user is offered anything further" is open.

**Decision type.** *Owner's decision*, and a small one — it is a scope question. The options: nothing (the
learner is expected to pick up five characters, which is arguably the education purpose); an icon glyph
substituted for the piece character inside the move string (breaks the "carry what you read into any Xiangqi
book" rationale that justified traditional notation in the first place); or a Help table mapping icon to
character, which costs one static illustration and sits inside part 7's Help work.

### 6.8 Are the style and symbol names user-facing?

**Question.** Are **传统 / 现代 / 高对比** and **汉字 / 图标** interface strings the user reads in Settings, or
internal design names?

**Owner.** `interaction-design.md:535`.

**Already answered.** Nothing. Both preferences are accepted product scope (`product.md:82–83`, "the **piece
style** … defaulting to the traditional one", "the **piece symbols**, Chinese characters by default or
pictorial icons").

**Still open, and larger than it reads.** Settings must render two preference groups with labels and option
labels. Neither the *group* labels nor the option labels exist in either language — the contract has an
accepted Settings group name for the AI defaults (**人机对弈默认设置** with **默认先后手** and **默认 AI 等级**)
and nothing equivalent for style or symbols. So this item necessarily produces new accepted copy in Chinese
first, which then feeds 6.1.

**Decision type.** *Designer's call.* If they are user-facing, 高对比 has an English counterpart the platform
already owns ("Increase Contrast" is a system setting name, and reusing it for a piece style would be
misleading), which is worth flagging to whoever writes it.

---

## Part 7 — secondary surfaces

### 7.1 History list layout and formatting

**Question.** What is the exact row layout of the History list, and how are the date and the move count
formatted?

**Owner.** `interaction-design.md:524`, first clause.

**Already answered — substantially.** Do not reopen: ordering (pinned group first, most recently recorded or
imported first within each group, `interaction-design.md:368–369`, `game-data.md:120`); row *content* (date,
mode, result or end reason, move count; human side for human-versus-AI; a visible imported marker); selection
opens read-only replay; content is read-only and pinning is library organisation only; the complete swipe
vocabulary, action order, colours (blue **共享**, red **删除**, Delete nearest the trailing edge), full-swipe
behaviours, and the pointer/keyboard/screen-reader equivalents; that meaning is carried by icon and text as
well as colour; no Move action, no folders, no bulk deletion, search, filters or tags. `game-data.md:121`
guarantees the queryable summaries that back exactly this row.

**Still open.** The visual layout of the row (one line or two, hierarchy, where the imported marker sits), the
date format (absolute vs relative, whether time appears, locale behaviour — note `game-data.md` distinguishes
the *original game dates* from the *local History-added time* used for sorting, and the row must say which it
shows), and the move-count format ("42 步" is accepted as a *metadata* pattern in the save confirmation but is
not stated to be the History row's format).

**Decision type.** *Designer's call*, except one owner question: whether the row shows the game's own date or
the date it entered this library, since they differ for imported records and the list sorts by the latter.

### 7.2 Import, duplicate, conflict and error flows

**Question.** What does the user see when importing a file, and when the import is a duplicate, an identity
conflict, or a rejection?

**Owner.** `interaction-design.md:524`, second clause. The *semantics* are owned by `game-data.md` and are
already accepted.

**Already answered — the entire semantic layer.** `game-data.md` accepts: one file at a time; a valid import
creates immutable History and never touches the active game; duplicate = same `game_id`, same
`archive_version`, same content hash and bytes → the existing record is returned; conflict = same `game_id`
with differing content or differing archive version → rejected with no persistent change; the full validation
order and every rejection class (transport/size, UTF-8 and JSON under structural limits, envelope and version
dispatch, field validity, rules-level replay, then hashing, then one write transaction); the limits (1 MiB,
10 000 plies, depth 4, 32 members, 256-byte strings, 2 s budget); and crucially *"unsupported versions with a
**distinct created-by-a-newer-version message that is never presented as corruption**"*.
`interaction-design.md:381–382` accepts that a duplicate *"offers a way to view the existing record"* and a
conflict *"is rejected with an explanation"*.

**Still open — presentation only.** The file-picker presentation per platform; success feedback; the copy for
each rejection class and how many distinct messages there are (the validation order defines at least five
classes, and collapsing them to one message would discard the accepted requirement that the newer-version case
is distinguishable from corruption); how "view the existing record" is offered; and the conflict explanation's
wording. All of this is new accepted Chinese copy, which then feeds part 6 — see §Collisions.

**Decision type.** *Designer's call.* One owner question: how many distinct user-visible rejection messages
the product wants. One message per validation class is honest and verbose; two (a "cannot read this file" and
the mandated newer-version message) is the minimum the accepted contract allows.

### 7.3 The insufficient-memory notice

**Question.** How is the accepted low-memory notice presented, what happens on repeated failure, and what does
a screen reader announce?

**Owner.** `interaction-design.md:525`.

**Already answered.** The copy and behaviour are fully accepted (`interaction-design.md:279–292`, PR #9): title
**无法启动 AI 对手**, message **当前可用内存不足。请尝试关闭一些其他 App，然后重试。**, actions **取消** and
**重试**; Cancel creates or changes nothing and the in-memory draft survives; Retry re-probes rather than
caching; no smaller Hash and no automatic cleanup; the active game stays saved and unchanged; the notice
promises nothing about the OS terminating apps. `engine-integration.md` additionally accepts that an
**allocation failure at a valid budget reuses this same notice** rather than inventing a second message —
which means the notice now has *two* triggers, and the repeated-failure design must cover both.
`testing.md:83` and the engine section already gate the accepted copy and Retry semantics.

**Still open.** Presentation (alert vs inline vs sheet — note `interaction-design.md:38` fixes the three custom
glass surfaces and says system alerts and sheets are additional and automatic, so an alert is materially free
and an inline surface would be a fourth custom surface); what changes, if anything, after the second or third
failed Retry, given the accepted promise that the notice must not claim a retry will succeed; and the
accessibility announcement, which is a part-8 concern living inside a part-7 item.

**Decision type.** *Designer's call.* One genuine owner question: whether repeated failure eventually offers
a way forward other than Cancel — for instance falling back to Free Play, which is available with no engine at
all. That is a product behaviour, not a presentation.

### 7.4 The engine cannot be re-prepared mid-game

**Question.** What does a player see when the app resumes, a search is owed, and the engine cannot be
re-prepared?

**Owner.** `interaction-design.md:526`, routed here from `engine-integration.md:194`.

**Already answered — the whole underlying behaviour.** `engine-integration.md` accepts: suspension cancels any
search and releases the transposition table; the engine is re-prepared **only when a search is owed**, not on
resuming replay, Free Play, a confirmed result, a game awaiting the user's move, or no active game;
re-preparation **can fail, leaving the game active, saved, and resumable with the AI unable to move**; a
cancelled search's late result is discarded as superseded. `testing.md:141` gates exactly that. Both documents
also already record *why* the existing notice does not fit: it *"assumes a game that has not started, so
neither its wording nor its 取消 action fits"*.

**Still open.** Everything the player sees. Nothing at all is specified. The design has to answer: what the
turn status shows when it is the AI's turn and the AI cannot move; whether there is a Retry and where it
lives; what happens if the user simply plays on (they cannot — it is not their turn); whether resign, undo and
save-and-continue remain reachable (they are the only exits, and Undo of the human move that owes the reply is
the interesting one); and whether the game is silently degraded or explicitly reported.

**Decision type.** *Owner's decision on the exit, designer's on the presentation.* The exit is a product
question: is the accepted answer "the game stays stuck until a Retry succeeds, and the user's escape is Undo
or saving to History", or does the app offer to convert the game to Free Play, or to end it? The contracts
give no answer, and each option changes what the game record means. Frame it, do not pick it.

### 7.5 Empty, loading, AI-thinking, error, corrupted-import and destructive-action states

**Question.** What does each of these six state families look like?

**Owner.** `interaction-design.md:537`. See §0.2 — this bullet is stale.

**Already answered, category by category:**

| Category | Status |
|---|---|
| **AI-thinking** | Largely closed. Activity is attached to the AI's turn and does not replace the side-to-move line (`:215`); board input is disabled but **the board is never dimmed** (`:204`, `:216`); the indicator appears only if the search passes **500 ms** after the player's move (`:424`); it **carries no material at all** (`:42`); the AI's piece departs no earlier than the **260 ms** compose-beat floor. What remains is the indicator's *form* — which is `interaction-design.md:523`, a different bullet. |
| **Error** | Three accepted presentations already exist and cover most cases: **无法保存对局** / **当前对局仍然保留。请重试。** / 取消 · 重试 for terminal-commit and archive failures; the transient **无法保存这一步，请重试。** capsule for a failed move or Undo, with *no* capsule when the failure is the AI's reply; **无法启动 AI 对手** for the memory path. Open: import errors (7.2), re-preparation (7.4), deletion-persistence failure copy (`:380` accepts *"the record remains and the app presents an error"* without copy). |
| **Destructive-action** | Largely closed. **删除前确认** default-on, **删除这盘棋？** / **删除后无法恢复。** / 取消 · 删除, immediate deletion when disabled, no Undo, no Recently Deleted, red **删除** swipe action, and *"Destructive actions use the system's destructive role rather than a red tint, so red keeps one meaning"* (`:44`). Open: resignation's confirmation, which has no accepted interface at all — but that is **part 4**, in the open PR #23. Do not do it in part 7. |
| **Corrupted-import** | Semantics closed (7.2), copy open. |
| **Loading** | Genuinely open, and small. The only accepted loading-shaped behaviours are that **开始对局** cannot be invoked twice while creation is in progress and that leaving invalidates the attempt; nothing says what the user sees during it. Also unaddressed: app launch while the store opens and the active game is restored. |
| **Empty** | Genuinely open. An empty History list, and the Play destination with no active game (the accepted text describes the Play destination *with* an active game, at `:294`, and never without). |

**Decision type.** *Designer's call throughout.* The value of this item is now mostly *editorial*: rewrite the
bullet to name only what is actually open (empty, loading, import-error copy, deletion-failure copy) so it
stops implying that AI-thinking and destructive actions are undesigned.

### 7.6 Help structure and illustrations

**Question.** How is Help organised, what does each entry point look like, and what illustrations does it use?

**Owner.** `interaction-design.md:527`.

**Already answered.** The scope is fully accepted and is a hard boundary: Help is *"a read-only Mini Xiangqi
rules reference covering the board, the pieces and their movement, check and checkmate, stalemate, repetition
and the claimable draw, perpetual check, and perpetual chase, plus a short explanation of the app's own
controls"*; static, no position analysis, no move suggestions, no lessons or drills; reachable from Settings
and from the game screen without abandoning or pausing state, with the exact prior context restored on return;
localized like the rest of the interface. `product.md` repeats the read-only scope.
`interaction-design.md:69` additionally requires one specific content item: *"There is no river … **Help calls
it out**."*

**Still open.** The concrete affordance and placement of the two entry points; the section structure and
ordering within the eight accepted topics; whether Help is a sheet, a pushed destination or a separate window
on macOS; and the illustrations — how many, drawn how, and whether they reuse the accepted piece styles and
marker vocabulary (they should, and the metric system in `interaction-design.md:129–146` gives them a ready
scale).

**Decision type.** *Designer's call*, with two owner questions. First, whether Help explains the accepted
*interpretations* — 一将一捉 resolving to a claimable draw, and the general-as-sole-defender degradation — since
those are places where this app deliberately differs from what a competition-trained player expects, and a
teaching app that stays silent about them will be reported as buggy. Second, whether the illustrations are
drawn for this project or reuse the icon set, which couples to the still-open icon-set decision.

### 7.7 Pointer hover preview *(issue #2 files this under part 7; the brief omitted it)*

See §0.3. Question: does a pointer, before any selection, preview a piece's legal destinations? Owner
`interaction-design.md:522`. The hover marker itself is accepted; only the scope question survives.
**Owner's decision** — it sits directly against the accepted exclusion of hints and analysis, and the contract
says so in as many words.

---

## Part 8 — accessibility and validation

### 8.1 The board's VoiceOver interaction model

**Question.** How does a VoiceOver user navigate 49 intersections, learn what stands on each and what is
legal, and commit a move?

**Owner.** `interaction-design.md:532`, second clause.

**Already answered, in part — and the accepted fragments constrain the answer more than they look.**
- *"Keyboard and VoiceOver use an equivalent select-piece, inspect-destinations, and select-destination flow
  rather than requiring a drag gesture"* (`:233`). The three-step shape is therefore accepted; what is open is
  its realisation.
- Keyboard focus is an accepted board marker with exact geometry (`:253`), it carries hue as the one exception
  to the marker rules, and it is the only marker permitted to cross another — so a focus concept on the board
  already exists and VoiceOver focus should ride it rather than invent a second.
- The board is *"never read for two kinds of information at once"*: anything that is not a fact about the
  position lives on the turn status (`:184`). A VoiceOver model that announces save failures from the board
  would contradict an accepted rule.
- Several announcements are already required by name and have no text: the last move's *"accessibility
  announcement"* (`:247`), the Flip Board control's *"localized accessibility label"* (`:218`), the History
  rows' screen-reader custom actions for Pin/Unpin, Share and Delete (`:386`), and the 将军 token carrying
  check while the general is held (`:249`).
- `interaction-design.md:442–450` accepts six things the design *must consider* — labels/values/actions/reading
  order, keyboard and focus, non-colour state cues, Dynamic Type, Reduce Motion / Reduce Transparency, and
  alternatives to sound, haptics and animation. That is a checklist, not a model.

**Still open — the whole model.** Element granularity (49 point elements vs 7 rank rows vs one board element
with a custom rotor); what a point's label, value and hint say and in which order (piece, side, coordinate —
and *which* coordinate, since the user-visible notation is traditional and per-side while the canonical one is
`a1`–`g7`, and the file numerals are hidden at accessibility text sizes, which is precisely when a VoiceOver
user is most likely present); how legal destinations are enumerated without 12 swipes; whether custom actions
or a custom rotor carry "inspect destinations"; what is announced after the human's move, after the AI's move,
on check, on an illegal tap, on an Undo, and at a result; and the equivalent Narrator model for Windows, which
`interaction-design.md:536` defers to when the Windows frontend exists.

**Decision type.** *Designer's call*, and the largest single piece of undone design in the three parts. One
owner question inside it: whether an end-to-end nonvisual game is a *supported* capability or a best effort.
`testing.md:149` currently asserts the former — *"an end-to-end nonvisual board interaction"* — in a draft
document. Promoting that gate is a commitment.

**Apple guidance.** See the last section: Apple publishes the API surface and general VoiceOver guidance but
**nothing specific to a board-game grid**, so this model is ours to justify.

### 8.2 Accessibility acceptance criteria

**Question.** What must be true for a build to pass accessibility, expressed as criteria a reviewer can check
rather than principles?

**Owner.** `interaction-design.md:532`, first clause. Downstream: `testing.md:147–190`.

**Already answered — far more than the bullet suggests.** A great deal of measurable criteria already exists,
scattered across accepted text, and this item is substantially an act of *collection*:
- Contrast numbers, all accepted: symbol ≥ 4.5:1 against its disc face; disc boundary ≥ 3:1 against the
  style's own board surface; the side-carrying channel ≥ 3:1 (fills) or 2× ring width; grid and palace
  diagonals ≥ 3:1; active marker ink ≥ 4.5:1 and record ink ≥ 3:1, measured against the board surface *and*
  against the hover fill composited over it, shadows excluded, light and dark; file numerals ≥ 4.5:1 and 7:1
  under Increase Contrast.
- Behavioural rules, all accepted: Increase Contrast promotes record ink to active values and reduces resting
  shadows; the board under Differentiate Without Color is identical to the board without it, focus ring
  excepted; Reduce Motion is one rule that keeps every state and removes only travel, with the check pulse
  removed rather than converted; Reduce Transparency replaces each custom glass surface's material with an
  opaque fill and a hairline separator without moving or resizing it; the 44 pt point floor on every platform;
  the numeral strips hidden at accessibility text sizes; haptics unavailable rather than inert on hardware
  without them; no requirement is met by a shadow.
- `testing.md`'s UI/accessibility section already lists roughly forty verifications derived from these.

**Still open.** (a) The *criteria* that do not exist yet: Dynamic Type — the exact accessibility text size at
which the strips hide (`interaction-design.md:529`) and what the layout does above it; VoiceOver's own pass
condition, which depends on 8.1; keyboard coverage — which operations must have a keyboard command, given the
contract names one for Flip Board and none for anything else. (b) The *form*: whether accepted criteria live
as a checklist in `interaction-design.md`, as gates in `testing.md`, or both, given they are currently spread
across a dozen accepted paragraphs.

**Decision type.** *Designer's call for the criteria, owner's for the bar.* The owner question is the target:
the accepted numbers are WCAG AA-shaped (4.5:1 / 3:1), matching what Apple's Accessibility Inspector uses, and
whether the product claims AA conformance or simply meets these specific numbers is a statement the owner
makes, not the designer.

### 8.3 Moving `testing.md` from draft to accepted

**Question.** What has to be true before `testing.md` can drop *"Nothing in this document is normative"*?

**Owner.** `testing.md:5`, and its nine open items at `:206–214`.

**Already answered.** Nothing about the status. But the document's own status line states the acceptance
condition explicitly and it is the constraint on this whole item: *"Add exact commands and thresholds only
after they have been verified with the required toolchains and representative devices."* So acceptance is
gated on *execution*, not on drafting. `architecture.md` already accepts the build and CI policy and the core
test-runner decision; issue #2's own comment thread records that builds run locally now, with CI on a macOS 26
runner and a Windows runner once Windows work begins.

**The nine open items, and what each actually needs:**

| # | Item | Blocked on |
|---|---|---|
| 1 | `:206` Exact simulator and macOS build/test commands | Executing them. Not blocked by anything — the toolchain is pinned (Xcode 27 beta `27A5228h`) and the repo restructure (#25) changes the paths, so do it after #25 lands. |
| 2 | `:207` Supported simulator, device, macOS and Windows validation matrix | Owner: which physical devices the internal group actually has. Also feeds part 4's still-open device list. |
| 3 | `:208` Windows toolchain and commands | The Windows frontend, which does not exist. **Deferrable** — accept the rest without it. |
| 4 | `:209` GitHub Actions workflows and pinned inputs | `pinned-inputs.json`, which does not exist yet (engine work). |
| 5 | `:210` Performance, memory, energy and thermal thresholds per AI profile | Measurement on real hardware. Duplicated as `engine-integration.md:195` for the memory probe. |
| 6 | `:211` Localization review process | **Part 6** — see §0.4. |
| 7 | `:212` UI automation vs structured manual review | A designer/engineer call; nothing blocks it. |
| 8 | `:213` Import validation time budget measurement | An implementation exists nowhere; the 2 s budget is accepted, its measurement is not. |
| 9 | `:214` Evidence retained for an internal distribution candidate | Owner: what the internal release ritual is. |

**Still open — and the strategic question nobody has asked.** Four of the nine are blocked on artefacts that do
not exist (Windows frontend, `pinned-inputs.json`, a running app, real devices). If acceptance requires all
nine, `testing.md` stays draft for a long time and **every gate added by PRs #13–#24 stays non-binding**, which
is exactly the risk issue #2 flags. The alternative the document's own structure already supports is
**section-level acceptance** — its status line says *"until its status **or an individual section** is
explicitly marked accepted"*. Sections whose content is derived from accepted contracts rather than from
measurement (Rules, Game data, Product and interaction, most of UI/accessibility) could be accepted now, with
Required toolchain, thresholds, and build/distribution gates staying draft.

**Decision type.** *Owner's decision.* It is a question about what binding means and how much unmeasured
process the project is willing to commit to. Frame it as: accept everything at once and wait, versus accept
the derived sections now and leave the measured ones draft, versus leave it all draft and accept that no gate
binds. The middle option is the one the document was written to allow.

---

## Collisions between the parts, and a nine-way partition

### Collisions to resolve before dispatch

1. **Every new Chinese string part 7 writes becomes part 6 input.** Import errors, empty and loading states,
   deletion-failure copy, the re-preparation notice, Help section titles, and Settings labels for style and
   symbols are all new user-facing copy. If part 6 runs first it will approve English for a set that part 7
   then enlarges; if part 6 runs last it can be complete. **Recommendation:** part 6 owns the *rules and the
   process* plus the existing 58 strings; every new string part 7 invents carries its English counterpart in
   the same change, under part 6's rules. Say this in the briefs.
2. **Part 7's "accessibility announcement" clauses belong to part 8's model.** The insufficient-memory notice's
   announcement (7.3), the re-preparation notice's (7.4), and the import-result announcements (7.2) should all
   be written against 8.1's model rather than invented three times.
3. **The localization review process is one item in two documents** (§0.4).
4. **The AI-thinking indicator's *form*** is `interaction-design.md:523`, which the brief did not list under
   any part but which part 7's "AI-thinking state" and part 8's VoiceOver both need. Assign it once, to part 7.
5. **The notation oracle (6.6) depends on the notation cases (6.5)** and is gated by part 8's `testing.md`
   acceptance. Sequence: 6.5 → 6.6 → 8.3.
6. **Do not touch part 4's territory.** Resignation copy, the play-control cluster, minimum window, the result
   card's placement in the stacked layout, and the move list in the stacked layout are PR #23's, which is open
   and being rewritten.

### A suggested disjoint nine-way split

| # | Part | Scope | Do not touch |
|---|---|---|---|
| 1 | 6 | The 58-string English counterpart set, plus the reverse gap of §0.6 | terminology (2), process (3) |
| 2 | 6 | English Xiangqi terminology incl. the General/King conflict; style/symbol names user-facing or not (6.3, 6.8) | the string list (1) |
| 3 | 6 | Traditional notation's unhandled cases, the oracle table, and the icon-reader question (6.5, 6.6, 6.7) | anything not notation |
| 4 | 7 | History list layout and formatting; import, duplicate, conflict and error flows (7.1, 7.2) | Help, memory, engine |
| 5 | 7 | Insufficient memory and mid-game re-preparation (7.3, 7.4), plus the AI-thinking indicator's form | History, Help |
| 6 | 7 | Help structure, entry-point affordances, illustrations; the hover-preview scope question (7.6, 7.7) | copy outside Help |
| 7 | 8 | The board's VoiceOver interaction model (8.1) and the Narrator equivalence question | criteria (8), testing (9) |
| 8 | 8 | Accessibility acceptance criteria: collect the accepted ones, write the missing ones (8.2) | the VoiceOver model (7) |
| 9 | 8 | `testing.md` draft → accepted: the nine items, and the section-level-acceptance question (8.3) | new criteria (8) |

The localization review process (§0.4) goes to **#3's part-6 slot or #9's**, not both. I would give it to #9,
because its hard part is evidence and process rather than wording.

---

## What Apple publishes, and what it does not

Searched with `mcp__xcode__DocumentationSearch` against the pinned Xcode 27 beta documentation.

**Found and citable:**

- *Human Interface Guidelines > Accessibility > Vision* — states the contrast table the project's accepted
  numbers already match: "Up to 17 pts | All | 4.5:1", "18 pts | All | 3:1", "All | Bold | 3:1", and says
  Accessibility Inspector uses these WCAG Level AA values. Also: "Convey information with more than color
  alone", and to provide a higher-contrast scheme when Increase Contrast is on. This is the citation for 8.2's
  numbers, and it confirms the project's own figures are not invented.
- *Human Interface Guidelines > Accessibility > Cognitive* — "Minimize use of time-boxed interface elements.
  Views and controls that auto-dismiss on a timer can be problematic … Prefer dismissing views with an
  explicit action." Directly relevant to part 7's transient capsule and the acknowledgment beat.
- *SwiftUI > `View/accessibilityRotor(_:entries:)`* and *AppKit > `NSAccessibilityCustomRotor`* — the API for
  giving VoiceOver a shortcut to a named set of elements. The candidate mechanism for "inspect destinations"
  in 8.1.
- *visionOS > Improving accessibility support in your app > Add support for Direct Gesture mode* — shows the
  announcement API used for exactly this problem: `AccessibilityNotification.Announcement("Game piece
  hit").post()`, described as communicating "the results of meaningful events". The pattern for 8.1's
  move/check/result announcements, though the page is visionOS-scoped.
- *ObjectiveC > `UIAccessibilityFocus`* — "VoiceOver and other assistive technologies place a virtual focus on
  elements, which allows users to inspect an element without activating it," and advises moving selection with
  focus to spare the user an extra tap. Directly relevant to whether board focus and piece selection are one
  concept or two in 8.1.
- *Xcode > Localization* — *Preparing your interface for localization*, *Preparing your app's text for
  translation*, *Localizing and varying text with a string catalog*, *Importing localizations* (XLIFF round
  trip), and *Localizing your app using agents*, which notes that agent translations are marked "Machine
  Translated" in the catalog and carry `state-qualifier` `leveraged-mt` in XLIFF. Relevant to 6.4's options.

**Not found — say so plainly rather than inventing it:**

- **No Apple guidance for a board-game grid's VoiceOver model.** There is no page on element granularity for a
  game board, on announcing a grid position, or on chess-like selection with a screen reader. The closest
  material is *Designing for games* and *Game controls*, which cover touch controls and controller input, not
  screen-reader models. The board's VoiceOver interaction model is **ours to design and ours to justify**; the
  citable material is only the general API surface above.
- **No Apple specification for how Liquid Glass renders under Reduce Transparency** — the contract already says
  this at `interaction-design.md:52` and my searches did not contradict it.
- **No Apple guidance on a localization *review process*.** The documentation covers mechanism (catalogs,
  XLIFF export/import, agent translation states) and never who reviews or what evidence is retained. 6.4 is a
  product decision with no external authority to defer to.
