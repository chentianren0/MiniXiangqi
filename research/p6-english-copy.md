# Part 6 — the English counterpart of every accepted Chinese string, and the English Xiangqi terminology

Workspace-only research evidence. Part of no repository. **Non-normative**: nothing here is a decision and
nothing here authorises implementation. The contracts are `MiniXiangqi/docs/*.md`; this file proposes text for
the main thread to author, and records what the contracts do and do not currently settle.

Repository state read: `MiniXiangqi` at `60fc044` (merge of #25, the repository restructure), working tree
clean. `docs/` is unchanged by that merge.

---

## 0. Method — what is executed, what is cited, what is reasoned

- **Executed.** Extraction of every bolded string containing Han characters across all eight documents in
  `MiniXiangqi/docs/`, by a throwaway Python pass: **58 distinct bolded strings**, one of which is prose
  (`xiangqi-rules.md:74`, the parenthetical 一将一捉). Four of the remaining 57 are composite middle-dot
  *metadata lines* rather than atoms; decomposing them yields five further atoms (人机对弈, 你执红, 进行中,
  42 步, 将死). Adding the one bolded non-Han user-facing string (**AI**, the turn-status controller label at
  `interaction-design.md:269`) gives the exact scope of this item:

  > **60 accepted user-facing strings**, of which 59 contain Han characters and 1 (**AI**) does not.
  > Four of them are additionally specified as composite metadata lines.

  This is two more than the prior survey's count of 58, because that count was scoped to
  `interaction-design.md` and did not decompose the metadata lines.

- **Executed.** All width figures in this document were **measured**, not estimated: rendered with CoreText
  (`CTLineGetTypographicBounds`) using `NSFont.systemFont(ofSize:)` on the pinned toolchain
  (`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`, Swift 27.0 / build `26A5388g`), on macOS,
  with the system's own font cascade resolving the Han characters. A single Han character measures
  **16.85 pt** at 17 pt (full-width, as the accepted numeral-strip analysis at `interaction-design.md:155`
  already observes); a Latin `n` measures 9.49 pt. The equivalent measurement on iOS/iPadOS is a required
  device check, exactly as `interaction-design.md:72` and `:529` already require for the numeral strips.

- **Read (contracts).** `interaction-design.md`, `product.md`, `game-data.md`, `xiangqi-rules.md` in full;
  `testing.md`, `engine-integration.md`, `core-interface.md` in the relevant parts.

- **Read (Apple).** `mcp__xcode__DocumentationSearch`, six queries. Every citation below names the page and
  section. The honest negatives are in §11.

- **Reasoned.** Every proposed string, every terminology recommendation, the review process in §10, and every
  defect claim in §8. These are my judgements and are the things to disagree with.

**Trap honoured.** PR #23 (part 4, app shell and layout) is open and rejected. Nothing in it is accepted, so
this document proposes **no** English for 确认认输？ or 认输后本局将记为你落败。, and proposes 翻转棋盘 for
Flip Board **as a fresh proposal of my own** (§7), not as an import of PR #23's text. Where I need the *term*
认输 for the end-reason vocabulary (§6), that is a terminology recommendation, not an approval of PR #23's
confirmation copy.

---

## 1. What English is already accepted, and must be reused rather than re-decided

This is larger than the survey found. Eleven of the sixty strings already have accepted English somewhere in
the contracts, and three more have an accepted English term in prose that settles them.

| Chinese | Accepted English | Where it is accepted |
|---|---|---|
| 我先手 | **I Move First** | `product.md:34`, glossed inside accepted text |
| AI 先手 | **AI Moves First** | `product.md:34` |
| 随机 | **Random** | `product.md:34` |
| 删除前确认 | **Confirm Before Deleting** | `product.md:62`, `:80`; `game-data.md:125`, `:151`, `:153` |
| 人机对弈 | **Human versus AI** | `product.md:32`, `:48`, `:52`; `interaction-design.md:183`, `:298` |
| 自由对弈 | **Free Play** | `product.md:33`; `interaction-design.md:183` |
| 共享 | **Share** | `product.md:60`; `interaction-design.md:386` |
| 删除 | **Delete** | `product.md:60`; `interaction-design.md:386` |
| 置顶 / 取消置顶 | **Pin** / **Unpin** | `product.md:60`; `interaction-design.md:386`; `game-data.md:119` |
| 悔棋 | **Undo** | `interaction-design.md:313`, `:335`, `:341`, `:416` — the accepted prose names this control "Undo" throughout |
| 回放 | **Replay** | `interaction-design.md:356–364`, `:370`; "read-only replay" |
| 传统 / 现代 | **Traditional** / **Modern** | `product.md:82` names the default style "the traditional one"; the pairing is unambiguous |
| 汉字 / 图标 | **Chinese characters** / **icons** | `product.md:83`, "Chinese characters by default or pictorial icons" |
| AI | **AI** | identical in both languages |

Piece names — **General, Chariot, Horse, Cannon, Soldier** — are accepted at `interaction-design.md:74`. They
are not user-visible strings on the board (piece characters are game content, `:71`) but they anchor every
descriptive English string, and they are in conflict with `xiangqi-rules.md`; see §6 and §12.

**The consequence.** "Approve the English counterparts" (`interaction-design.md:533`) is a 46-string job, not a
60-string job, and 13 of the 46 are one or two words.

Two further accepted instructions are worth quoting because they mean an English string is *required*, not
optional: `interaction-design.md:268` ("using the localized equivalent of **轮到红方** or **轮到黑方**") and
`:340` ("the localized equivalent of **红方获胜**, **黑方获胜**, or **和棋**").

---

## 2. The conventions I applied, and the Apple text they rest on

Every proposal below follows five rules. I state them separately from the strings so they can be rejected as a
set rather than argued string by string.

**C1 — Alert titles.** HIG > Alerts > Content: *"Write a title that clearly and succinctly describes the
situation … If the title is a complete sentence, use sentence-style capitalization and appropriate ending
punctuation. If the title is a sentence fragment, use title-style capitalization, and don't add ending
punctuation."*
Applied: 开始新对局？ and 删除这盘棋？ are complete interrogative sentences → **"Start a new game?"**,
**"Delete this game?"** (sentence-style, keep the question mark). 无法保存对局 and 无法启动 AI 对手 are
fragments → **"Couldn't Save the Game"**, **"Couldn't Start the AI Opponent"** (title-style, no full stop).
Apple's own apps are not consistent with their own rule here (Photos titles a deletion alert in title-style),
so this is a rule I am choosing to follow literally rather than a rule the platform enforces.

**C2 — Alert messages.** Same page: *"Include informative text only if it adds value. If you need to add an
informative message, keep it as short as possible, using complete sentences, sentence-style capitalization, and
appropriate punctuation."* Every message below is a complete sentence with a full stop, matching the Chinese,
which also ends every message in 。

**C3 — Button titles.** HIG > Alerts > Buttons: *"Aim for a one- or two-word title that describes the result of
selecting the button … Always use 'Cancel' to title a button that cancels the alert's action. As with all
button titles, use title-style capitalization and no ending punctuation."* And HIG > Buttons > Content:
*"consider starting the label with a verb."*
Applied: 取消 → **Cancel** (mandated by name). Every other action is title-style, verb-first where it is an
action: Start Game, End Game, Save and Continue, Try Again, Undo, Claim Draw, Replay, Keep Playing,
End as a Draw, Delete, Share, Pin, Unpin, Done.

**C4 — The destructive-action rule is already satisfied.** HIG > Alerts > Buttons: *"If there's a destructive
action, include a Cancel button"* and the destructive style is for actions *"people didn't deliberately
choose."* `interaction-design.md:44` already accepts the system's destructive role rather than a red tint, and
:380 already pairs 删除 with 取消. Nothing in the English changes this.

**C5 — Preserve the function, not the wording.** The brief's rule, and it is the one that does real work below:
a confirmation that states an irreversible consequence must still state it (删除后无法恢复。); a factual
metadata line must stay factual (`interaction-design.md:305`, *"The metadata reports facts and does not ask the
user to classify the result"*); the accepted refusal of instruction must survive (`:273`, *"The design does not
add a separate, unrelated instruction such as 'please move' or 'your turn.'"*); and the low-memory notice must
keep being a suggestion rather than a promise (`:290`, *"it does not promise that the operating system will
terminate them or that a retry will succeed"*).

---

## 3. The master table

Widths are measured at 17 pt (the iOS `.body` default). `Δ` is the English width divided by the Chinese width.
"Accepted" in the Source column means the English is already accepted per §1 and is reproduced here for
completeness rather than proposed.

### 3.1 Actions and controls

| # | Chinese | Source | Proposed English | zh pt | en pt | Δ | Note |
|---|---|---|---|---|---|---|---|
| 1 | 开始对局 | `id:191`, `:196`, `:204–207`, `product:53`, `game-data:82` | **Start Game** | 67.4 | 86.2 | 1.28 | |
| 2 | 结束对局 | `id:44`, `:341`, `:343` | **End Game** | 67.4 | 78.4 | 1.16 | confirms a natural result; not a resignation |
| 3 | 完成 | `id:44`, `:344` | **Done** | 33.7 | 40.3 | 1.20 | HIG names Done as the single-button dismissal title |
| 4 | 保存并继续 | `id:186`, `:303`, `product:49`, `game-data:77` | **Save and Continue** | 84.3 | 142.5 | 1.69 | |
| 5 | 取消 | `id:285`, `:303`, `:313`, `:321`, `:380` | **Cancel** | 33.7 | 52.4 | 1.55 | mandated title (C3) |
| 6 | 重试 | `id:285`, `:321` | **Try Again** | 33.7 | 71.0 | 2.11 | **Retry** is 40.4 pt; see §9.1 |
| 7 | 悔棋 | `id:313`, `:341` | **Undo** *(accepted)* | 33.7 | 41.2 | 1.22 | |
| 8 | 判和 | `id:313` | **Claim Draw** | 33.7 | 86.3 | 2.56 | the action; see #33 for the state |
| 9 | 回放 | `id:344` | **Replay** *(accepted)* | 33.7 | 50.9 | 1.51 | |
| 10 | 继续对局 | `id:350`, `:352` | **Keep Playing** | 67.4 | 97.8 | 1.45 | see §9.2 — must not be reused for Resume Game |
| 11 | 以和棋结束 | `id:350`, `:351` | **End as a Draw** | 84.3 | 107.8 | 1.28 | |
| 12 | 删除 | `id:372`, `:380` | **Delete** *(accepted)* | 33.7 | 49.2 | 1.46 | |
| 13 | 共享 | `id:372`, `:376` | **Share** *(accepted)* | 33.7 | 44.0 | 1.31 | |
| 14 | 置顶 | `id:374` | **Pin** *(accepted)* | 33.7 | 23.6 | 0.70 | one of only three strings English shortens |
| 15 | 取消置顶 | `id:374` | **Unpin** *(accepted)* | 67.4 | 44.8 | 0.66 | |

### 3.2 Pre-start setup

| # | Chinese | Source | Proposed English | zh pt | en pt | Δ | Note |
|---|---|---|---|---|---|---|---|
| 16 | 本局设置 | `id:191`, `:204` | **This Game** | 67.4 | 81.3 | 1.21 | a control-group header; see §9.3 |
| 17 | 我先手 | `id:191`, `product:34` | **I Move First** *(accepted)* | 50.6 | 87.3 | 1.73 | |
| 18 | AI 先手 | `id:191`, `product:34` | **AI Moves First** *(accepted)* | 53.2 | 106.8 | 2.01 | |
| 19 | 随机 | `id:191`, `product:34` | **Random** *(accepted)* | 33.7 | 63.1 | 1.87 | |
| 20 | AI 等级 | `id:191` | **AI Level** | 53.2 | 59.0 | 1.11 | |
| 21 | 快速 | `id:195`, `product:37`, `engine:97` | **Fast** | 33.7 | 31.8 | 0.94 | matches serialized `fast` |
| 22 | 标准 | `id:195`, `engine:98` | **Standard** | 33.7 | 69.3 | 2.06 | matches serialized `standard` |
| 23 | 深思 | `id:195`, `engine:99` | **Deep** | 33.7 | 40.4 | 1.20 | matches serialized `deep`; see §9.4 |
| 24 | 你将控制红黑双方，红方先行。 | `id:203`, `testing:71` | **You control both Red and Black. Red moves first.** | 227.9 | 369.2 | 1.62 | second clause is accepted English at `product:52`; **does not fit the board block** — §5 |

### 3.3 Settings

| # | Chinese | Source | Proposed English | zh pt | en pt | Δ | Note |
|---|---|---|---|---|---|---|---|
| 25 | 人机对弈默认设置 | `id:209` | **Human versus AI Defaults** | 134.8 | 195.7 | 1.45 | group header |
| 26 | 默认先后手 | `id:209` | **Default First Mover** | 84.3 | 144.0 | 1.71 | anchored by the archive field `first_mover_choice`, `game-data:38`, `:48` |
| 27 | 默认 AI 等级 | `id:209` | **Default AI Level** | 91.2 | 118.1 | 1.29 | |
| 28 | 删除前确认 | `id:377`, `:381` | **Confirm Before Deleting** *(accepted)* | 84.3 | 182.9 | 2.17 | |

### 3.4 Turn status

| # | Chinese | Source | Proposed English | zh pt | en pt | Δ | Note |
|---|---|---|---|---|---|---|---|
| 29 | 轮到红方 | `id:268` | **Red to Move** | 67.4 | 95.1 | 1.41 | "side to move" is the accepted rules English (`xiangqi-rules:38`, `:51`, `:62`) |
| 30 | 轮到黑方 | `id:268` | **Black to Move** | 67.4 | 106.8 | 1.58 | |
| 31 | 你 | `id:269` | **You** | 16.9 | 28.4 | 1.69 | controller label, not an instruction (C5) |
| 32 | AI | `id:269` | **AI** *(accepted)* | — | — | 1.00 | |
| 33 | 将军 | `id:249`, `:271`, `:428`, `testing:171`, `:186` | **Check** | 33.7 | 48.5 | 1.44 | |
| 34 | 可判和 | `id:272`, `:305`, `:352`, `testing:78` | **Draw Available** (state) | 50.6 | 110.6 | 2.19 | one Chinese string doing two jobs; see §9.5 |

### 3.5 Result card

| # | Chinese | Source | Proposed English | zh pt | en pt | Δ | Note |
|---|---|---|---|---|---|---|---|
| 35 | 红方获胜 | `id:340`, `:305` | **Red Wins** | 67.4 | 71.8 | 1.07 | anchored by serialized `red-wins` |
| 36 | 黑方获胜 | `id:340` | **Black Wins** | 67.4 | 83.5 | 1.24 | `black-wins` |
| 37 | 和棋 | `id:340` | **Draw** | 33.7 | 39.2 | 1.16 | `draw` |
| 38 | 已记录到历史 | `id:343` | **Saved to History** | 101.1 | 125.2 | 1.24 | "Recorded in History" is 149.9 pt and reads colder |

### 3.6 Alerts and notices

| # | Chinese | Source | Proposed English | zh pt | en pt | Δ |
|---|---|---|---|---|---|---|
| 39 | 开始新对局？ | `id:300`, `testing:67` | **Start a new game?** | 92.8 | 141.3 | 1.52 |
| 40 | 当前对局 | `id:301`, `testing:67` | **Current Game** | 67.4 | 106.9 | 1.59 |
| 41 | 这盘对局将按当前状态保存到历史。 | `id:302`, `testing:67` | **This game will be saved to History as it is now.** | 261.4 | 350.3 | 1.34 |
| 42 | 无法保存对局 | `id:230`, `:257`, `:319`, `core-interface:210` | **Couldn't Save the Game** | 101.1 | 183.8 | 1.82 |
| 43 | 当前对局仍然保留。请重试。 | `id:320`, `testing:73` | **The current game is still saved. Please try again.** | 211.0 | 365.5 | 1.73 |
| 44 | 无法启动 AI 对手 | `id:283`, `:526`, `engine:112`, `:194` | **Couldn't Start the AI Opponent** | 124.9 | 234.9 | 1.88 |
| 45 | 当前可用内存不足。请尝试关闭一些其他 App，然后重试。 | `id:284` | **There isn't enough memory available right now. Try closing some other apps, then try again.** | 431.9 | 695.4 | 1.61 |
| 46 | 局面已三次重复，可以和棋结束。 | `id:350` | **This position has occurred three times. You can end the game as a draw.** | 244.7 | 549.4 | 2.24 |
| 47 | 删除这盘棋？ | `id:378` | **Delete this game?** | 92.8 | 136.3 | 1.47 |
| 48 | 删除后无法恢复。 | `id:379` | **This game can't be recovered.** | 126.5 | 230.1 | 1.82 |

Notes on this group:

- **#45** keeps the suggestion-not-promise shape `:290` requires: "Try closing some other apps" advises,
  and "then try again" does not claim success. The Chinese borrows the English word *App*; the English simply
  says *apps*.
- **#46** keeps 可以 as permission ("You **can** end the game as a draw"), which is what makes it a fact plus an
  option rather than an instruction — the accepted claim-gated behaviour at `xiangqi-rules:61` and the refusal
  of instruction at `id:273` both depend on that.
- **#48 must not be "This can't be undone."** That phrasing is 164.3 pt and reads better, but the app has an
  **Undo** control (#7) and `product.md:62` explicitly states there is *no* deletion Undo. "Can't be undone"
  would name the wrong mechanism in an app where Undo is a real, visible, different thing. **"This game can't
  be recovered."** preserves 无法恢复 exactly and avoids the collision.

### 3.7 Transient

| # | Chinese | Source | Proposed English | zh pt | en pt | Δ |
|---|---|---|---|---|---|---|
| 49 | 无法保存这一步，请重试。 | `id:257`, `testing:184` | **Couldn't save that move. Please try again.** | 194.2 | 318.0 | 1.64 |

Dropping "Please" gives **"Couldn't save that move. Try again."** at 266.8 pt. See §9.1 — this is the one place
where the length cost of mirroring the source's politeness is material, because the capsule is anchored to the
turn-status element rather than to a system alert that can wrap freely.

### 3.8 Metadata atoms (they compose the four accepted metadata lines)

| # | Chinese | Source | Proposed English | zh pt | en pt | Δ |
|---|---|---|---|---|---|---|
| 50 | 人机对弈 | `id:305` | **Human versus AI** *(accepted)* | 67.4 | 128.3 | 1.90 |
| 51 | 自由对弈 | `id:305` | **Free Play** *(accepted)* | 67.4 | 69.7 | 1.03 |
| 52 | 你执红 | `id:305` | **You: Red** | 50.6 | 67.1 | 1.33 |
| 53 | 进行中 | `id:305` | **In Progress** | 50.6 | 85.5 | 1.69 |
| 54 | 42 步 | `id:305` | **42 moves** | 41.5 | 74.5 | 1.79 |
| 55 | 将死 | `id:305` | **Checkmate** | 33.7 | 86.7 | 2.57 |

#54 is not a translation problem, it is a product decision, and #52 has a grammatical problem Chinese does not
have. Both are in §9.

### 3.9 Design names (status contested — gated on `interaction-design.md:535`)

| # | Chinese | Source | Proposed English | zh pt | en pt | Δ |
|---|---|---|---|---|---|---|
| 56 | 传统 | `id:82` | **Traditional** | 33.7 | 79.3 | 2.35 |
| 57 | 现代 | `id:83` | **Modern** | 33.7 | 59.0 | 1.75 |
| 58 | 高对比 | `id:84` | **High Contrast** | 50.6 | 105.5 | 2.09 |
| 59 | 汉字 | `id:108` | **Chinese Characters** | 33.7 | 149.7 | 4.44 |
| 60 | 图标 | `id:109` | **Icons** | 33.7 | 40.8 | 1.21 |

汉字 → Chinese Characters is the single worst expansion in the whole inventory at **4.44×**, and it is a
Settings option label sitting beside a value in a right-aligned row, which is the tightest place in the app for
a long string. **Characters** alone (2.4× shorter) is ambiguous next to **Icons** in a game where "character"
also means the glyph on a disc — which is precisely the meaning intended, so the ambiguity is benign. I
recommend **Chinese Characters** for the option and note **Characters** as the fallback if the row proves too
tight; that is a layout finding for part 4, not a copy decision.

---

## 4. The reverse gap — English-only elements that have no accepted Chinese

`interaction-design.md:455` accepts that *"Simplified Chinese is the source language: the accepted user-facing
copy in this document is normative, and its English counterparts are translations of it."* Six user-facing
elements violate that rule today by existing only in English. This is a defect in the contracts, not an open
question anyone has filed.

**Two of the six are already closed and nobody noticed.** The metadata examples at `interaction-design.md:305`
contain **人机对弈** and **自由对弈** as accepted Chinese. Those are the Chinese names of the two modes the
contracts otherwise name only in English. So Human versus AI ↔ 人机对弈 and Free Play ↔ 自由对弈 need
recording, not deciding.

| English-only element | Where | Proposed Chinese | Basis |
|---|---|---|---|
| **Human versus AI** | `id:183`, `:298`, `product:32` | **人机对弈** | already accepted at `id:305` |
| **Free Play** | `id:183`, `product:33` | **自由对弈** | already accepted at `id:305` |
| **History** | `id:22`, `product:73` | **历史** | already used in accepted copy: 保存到历史 (`id:302`), 已记录到历史 (`id:343`) |
| **Settings** | `id:23`, `product:74` | **设置** | already used in accepted copy: 本局设置 (`id:191`), 人机对弈默认设置 (`id:209`) |
| **Play** | `id:21`, `product:72` | **对局** | proposed; the destination that starts or resumes a game |
| **Resume Game** | `id:296` | **回到对局** | proposed; **must not** be 继续对局 — see §9.2 |
| **Flip Board** | `id:214`, `:218`, `:360` | **翻转棋盘** | proposed fresh here; not imported from PR #23 |
| **Confirm Before Deleting** | `product:62`, `:80`; `game-data:125` | **删除前确认** | already accepted at `id:377` — the two other contracts simply need aligning |

Four of the eight therefore require no decision at all; they require the contracts to record Chinese that is
already accepted elsewhere in them.

**A second, larger gap in *both* languages.** `game-data.md:50` freezes nine serialized `end_reason` values,
and `interaction-design.md:340`, `:369` and `product.md:59` all require the app to *display* a result reason —
on the result card's second line, in every History row, and in the save-before-mode metadata. Exactly **one**
of the nine has accepted display copy in either language: 将死 / Checkmate. The other eight have none, in
Chinese or English. Proposed vocabulary, with measured widths at 17 pt:

| Serialized | Proposed Chinese | Proposed English | zh pt | en pt | Δ |
|---|---|---|---|---|---|
| `checkmate` | 将死 *(accepted)* | **Checkmate** | 33.7 | 86.7 | 2.57 |
| `stalemate` | 困毙 | **Stalemate** | 33.7 | 76.5 | 2.27 |
| `threefold-repetition` | 三次重复 | **Threefold Repetition** | 67.4 | 154.5 | 2.29 |
| `perpetual-check` | 长将 | **Perpetual Check** | 33.7 | 125.7 | 3.73 |
| `perpetual-chase` | 长捉 | **Perpetual Chase** | 33.7 | 125.2 | 3.72 |
| `mutual-perpetual-check` | 双方长将 | **Mutual Perpetual Check** | 67.4 | 182.0 | 2.70 |
| `mutual-perpetual-chase` | 双方长捉 | **Mutual Perpetual Chase** | 67.4 | 181.5 | 2.69 |
| `resignation` | 认输 | **Resigned** | 33.7 | 70.6 | 2.10 |
| `ended-early` | 提前结束 | **Ended Early** | 67.4 | 90.2 | 1.34 |

三次重复 is a fragment of accepted copy (局面已三次重复, `id:350`) rather than an accepted label. 长将 and
长捉 are the standard Chinese Xiangqi terms and correspond exactly to the accepted English "perpetual check"
and "perpetual chase" (`xiangqi-rules.md:63–68`). **困毙** is the standard Xiangqi term for a side with no
legal move, and it is a better source string than a literal rendering of "stalemate" because in this ruleset
that state is a **loss**, not a draw — see §9.6.

These nine are the largest single block of undone copy inside part 6, they were not on anyone's list, and they
are also the strings that make the English metadata line overflow in §5.

---

## 5. Length — measured, and what it costs the accepted layout

`interaction-design.md:459` accepts that *"layouts must tolerate different text lengths"* but fixes no figure.
Here is the figure.

**Over the 60-string inventory, English is 1.60× the width of the accepted Chinese** (5474.5 pt of Chinese
against 8739.2 pt of English, at 17 pt, summed). The distribution matters more than the mean:

- **3 strings shrink**: 置顶 → Pin (0.70), 取消置顶 → Unpin (0.66), 快速 → Fast (0.94).
- **The long messages sit near the mean**: 1.34× to 1.73×, because Chinese sentences carry particles and
  English carries spaces.
- **Short labels are the worst**: two-character Chinese labels against multi-syllable English terms run 2.1× to
  2.6× (重试 → Try Again 2.11, 判和 → Claim Draw 2.56, 将死 → Checkmate 2.57), and the eight undone end-reason
  labels in §4 run **2.10× to 3.73×**.
- The single worst is 汉字 → Chinese Characters at **4.44×**.

**The concrete layout consequence, against the accepted board block.** `interaction-design.md:134` and `:154`
fix the board block at **308 pt wide** at the 44 pt pitch floor, and `:38–40` forbid anything from intersecting
it. Elements aligned to the board — the pre-start explanation and the metadata lines — are therefore working
against a measurable 308 pt.

| Line | Chinese | English | Verdict |
|---|---|---|---|
| 你将控制红黑双方，红方先行。 | 227.9 | 369.2 | Chinese fits on one line at 17 pt; **English does not** |
| 进行中 · 轮到黑方 · 42 步 | 186.1 | 293.5 | both fit, English with 14.5 pt to spare |
| 进行中 · 可判和 · 42 步 | 169.3 | 297.2 | both fit, English with 10.8 pt to spare |
| 和棋 · 三次重复 · 128 步 | 176.6 | 302.3 | both fit, English with 5.7 pt to spare |
| 红方获胜 · 三次重复 · 128 步 | 210.3 | 334.8 | **English over by 26.8 pt** |
| 黑方获胜 · 双方长捉 · 128 步 | 210.3 | 373.6 | **English over by 65.6 pt** |
| 人机对弈 · 你执红 · 认输 · 128 步 | 240.5 | 387.9 | **English over by 79.9 pt** |
| 人机对弈 · 你执黑 · 提前结束 · 128 步 | 274.2 | 419.2 | **English over by 111.2 pt** |

**Every Chinese metadata line fits the 308 pt board block at 17 pt. Four of the eight English equivalents do
not.** The middle-dot composition at `interaction-design.md:305` therefore survives in Chinese and does not
survive unchanged in English at the accepted floor. The choices are: let the line wrap to two; drop to a
smaller type style (at 13 pt every English line above fits — the widest is 268 pt); or change the composition
in English only (stack the metadata as label/value rows rather than a middle-dot run). That is a real product
choice and it is in §12.

Three caveats, stated so they can be disagreed with:

1. The 308 pt figure is the *board block*, which is what glass may not intersect. Where a metadata line
   actually sits — the Play destination's active-game row, the confirmation alert, a History row — is part 4's
   and part 7's undecided territory. An alert's own width on iPhone is wider than 308 pt and wraps freely, so
   #41, #43, #45 and #46 are not at risk; the *board-aligned* lines are.
2. Everything above is at 17 pt. At accessibility text sizes both languages overflow, but English reaches the
   overflow at a smaller size, and the numeral strips are already accepted as the first thing to yield
   (`id:157`). English gives that budget less headroom than the accepted Chinese analysis assumed.
3. Measured on macOS. `interaction-design.md:72` and `:529` already require the equivalent font measurement to
   be redone on iOS and iPadOS; these figures inherit that requirement.

**Apple's own tool for this exists and should be named in the contract.** Xcode > *Preparing your interface for
localization* > "Run your app using pseudolanguages" publishes seven pseudolanguages, of which three are
directly relevant here: **Double-Length Pseudolanguage** (*"Doubles the length of localizable strings to test
whether views adjust their size and position"*), **Accented Pseudolanguage**, and **Bounded String
Pseudolanguage** (*"Wraps strings to identify places where localized strings may appear truncated"*). Since the
measured worst case in this app is 4.44× and the mean is 1.60×, double-length is a *weaker* test than the real
English for the short labels and a *stronger* test for the sentences; it is a useful gate, not a sufficient
one.

---

## 6. English Xiangqi terminology (`interaction-design.md:534`)

The vocabulary below is what the English build should use consistently, per `:459` (*"Terminology for Xiangqi
pieces, rules, results, and controls must be consistent within each supported language"*). Where a term is
already fixed by an accepted contract I mark it and do not propose an alternative.

### 6.1 Pieces

| Piece | Red / Black character (game content) | English | Status |
|---|---|---|---|
| general | 帅 / 将 | **General** | accepted `id:74`; **conflicts with `xiangqi-rules.md`** — §12 |
| chariot | 俥 / 车 | **Chariot** | accepted `id:74` |
| horse | 傌 / 马 | **Horse** | accepted `id:74` |
| cannon | 炮 / 砲 | **Cannon** | accepted `id:74` |
| soldier | 兵 / 卒 | **Soldier** | accepted `id:74` |

The ten characters and the notation tokens 进 退 平 前 后 are **game content** (`id:71`, `:164`) and are never
translated. That boundary is accepted and this document does not touch it.

### 6.2 Board

| Concept | Chinese | English | Basis |
|---|---|---|---|
| point / intersection | 交叉点 | **point** | accepted `id:120` — "7-by-7 **points**", never "square" |
| file | 路 / 线 | **file** | accepted `xiangqi-rules:34`, `id:163` |
| rank | 横线 | **rank** | accepted `xiangqi-rules:34`, `id:167` |
| palace | 九宫 | **palace** | accepted `xiangqi-rules:29`, `id:122` |
| river | 河界 | **river** | accepted `id:123` — used only to say there is none |
| screen (cannon) | 炮架 | **screen** | accepted `xiangqi-rules:46` |
| cell pitch, board core, marker band | — | as accepted | `id:131–137`; internal geometry, not user-facing |

Note that "square" appears nowhere as a board term, deliberately, and English copy must not reintroduce it —
`id:120` says a checkerboard of squares *"would teach a beginner the wrong mental model."* The one accepted
exception is `id:227`, "Tapping an illegal board square", which is prose about input rather than a user-visible
string; it is worth fixing when that paragraph is next touched.

### 6.3 Rules and results

| Serialized identifier | Chinese | English | Status |
|---|---|---|---|
| — | 将军 | **check** | proposed (#33) |
| `checkmate` | 将死 | **checkmate** | Chinese accepted; English anchored by the identifier |
| `stalemate` | 困毙 | **stalemate** | both proposed; §9.6 |
| `threefold-repetition` | 三次重复 | **threefold repetition** | both proposed |
| `perpetual-check` | 长将 | **perpetual check** | English accepted `xiangqi-rules:63`; Chinese proposed |
| `perpetual-chase` | 长捉 | **perpetual chase** | English accepted `xiangqi-rules:64`; Chinese proposed |
| `mutual-perpetual-check` | 双方长将 | **mutual perpetual check** | English accepted `xiangqi-rules:68` |
| `mutual-perpetual-chase` | 双方长捉 | **mutual perpetual chase** | English accepted `xiangqi-rules:68` |
| `resignation` | 认输 | **resignation** / **Resigned** | English accepted `product:40`; Chinese proposed |
| `ended-early` | 提前结束 | **ended early** | English accepted `product:50`, `game-data:80` |
| `red-wins` / `black-wins` / `draw` | 红方获胜 / 黑方获胜 / 和棋 | **Red Wins / Black Wins / Draw** | Chinese accepted `id:340` |
| — | 一将一捉 | **alternating check and chase** | accepted `xiangqi-rules:74` |
| — | 判和 | **claim a draw** | proposed (#8); the accepted prose already says "draw claim" (`id:230`, `:313`) |
| — | 白脸将 / 对面笑 | **facing generals** | see below |

**One internal inconsistency to fix while doing this.** `xiangqi-rules.md:43` says *"The two kings may not face
each other on an otherwise empty file"*, `:104` calls the fixture *"kings facing on an empty file"*, and `:76`
calls the same condition *"the flying-generals condition"*. Three names, two of them using a piece name the
interaction contract does not use. If General is affirmed (§12), the whole family becomes **facing generals**
and the fixture prose follows.

### 6.4 Controls and app concepts

| Chinese | English | Status |
|---|---|---|
| 悔棋 | **Undo** | accepted in prose |
| 回放 | **Replay** | accepted in prose |
| 共享 / 删除 / 置顶 / 取消置顶 | **Share / Delete / Pin / Unpin** | accepted `product:60` |
| 导入 / 导出 | **Import** / **Export** | English accepted `game-data:111`, `product:63`; **Chinese proposed here, no accepted source string exists** |
| 帮助 | **Help** | English accepted `product:41`, `id:391`; **Chinese proposed**; the concrete label is part 7's (`id:527`) |
| 翻转棋盘 | **Flip Board** | English accepted `id:214`; Chinese proposed §4 |
| 回到对局 | **Resume Game** | English accepted `id:296`; Chinese proposed §4, §9.2 |
| 步 | **move** | see §9.7 — this is a product decision, not a term |
| 中文记谱法 | **traditional notation** | accepted prose `id:161`; no user-visible label exists in either language |

---

## 7. Where the accepted Chinese and English already agree — a note on what *not* to write

`interaction-design.md:273` refuses *"a separate, unrelated instruction such as 'please move' or 'your turn.'"*
Every turn-status proposal above is a **statement of whose move it is**, not an instruction: "Red to Move",
"You", "AI", "Check". "Your Turn", "Your Move", "It's your move" and "Make a move" are all excluded by that
accepted rule and none appears here. This is the single most likely place for an English translation to drift,
because "Your turn" is the idiomatic English a translator reaches for first and the Chinese 轮到红方 does not
license it.

Likewise `id:305` requires the metadata to *"report facts and not ask the user to classify the result."*
"Unfinished", "Abandoned", "Gave up" and "Quit" are therefore all excluded for `ended-early`; **Ended Early**
is neutral and matches the accepted English of `product.md:50`.

---

## 8. Defects in the accepted contracts that this work exposes

1. **Six user-facing elements exist only in English** despite the accepted source-language rule — §4. Two of
   them (Human versus AI, Free Play) already have accepted Chinese elsewhere in the same document, which makes
   the omission a recording failure rather than an unresolved question.
2. **The same preference is named in two languages in two accepted contracts**: 删除前确认 at `id:377` and
   **Confirm Before Deleting** at `product:62` / `game-data:125`.
3. **Two accepted contracts use different English words for the same piece**: General (`id:74`) against king
   (`xiangqi-rules:28`, `:42`, `:45`, `:52`, `:104`, and the fixture prose) — §12.
4. **`xiangqi-rules.md` names the facing-generals condition three different ways** — §6.3.
5. **Eight of nine serialized end reasons have no display copy in either language**, while three accepted
   contracts require the reason to be displayed — §4. This is not filed as open anywhere.
6. **The per-ply save-failure capsule's copy names only a move, but the accepted behaviour covers a move *or*
   an Undo.** `id:257` and `testing:184` both say the capsule is *"for a failed user move or Undo"*, and both
   specify the copy as 无法保存这一步，请重试。 — "this move". The imprecision is in the Chinese source. The
   English must not silently repair it: an English string that said "Couldn't save that change" while the
   normative Chinese says 这一步 would make the translation more accurate than its source, which is a contract
   change to the Chinese, not a translation choice.
7. **English needs a plural rule where Chinese needs none.** 42 步 is invariant; "42 moves" / "1 move" is not.
   The move count appears in the metadata line (`id:305`), in every History row (`id:369`, `product:59`,
   `game-data:121`), and a one-ply game is reachable in Free Play. Xcode > *Localizing strings that contain
   plurals* is the mechanism; the point for part 6 is that the English inventory contains at least one string
   that is a **pattern with a plural variant**, not a literal, and the contract should say so.

---

## 9. Strings where a faithful English rendering needs a decision, not a translator

These are the ones I will not decide silently. Most are designer-level; the ones that are the owner's are
marked and repeated in §12.

**9.1 — 请 (please), and the HIG rule against restating a button.** The Chinese uses 请 in exactly two places:
无法保存这一步，请重试。 (#49) and 当前对局仍然保留。请重试。 (#43). Mirroring it gives "Please try again."
next to a **Try Again** button, which is what HIG > Alerts > Content warns against: *"Avoid explaining alert
buttons. If your alert text and button titles are clear, you don't need to explain what the buttons do."*
Three coherent positions: (a) mirror 请 exactly and accept the redundancy (my recommendation for #43, where the
alert has room, and it keeps the translation faithful); (b) drop it in both and accept that English says less
than the normative source (saves 51 pt on the capsule, which matters — §3.7); (c) drop it only where the button
is adjacent. I recommend (a) for #43 and (b) for #49, on the grounds that the capsule has **no** button, so
"Please try again" there is instruction rather than redundancy, while the capsule is width-constrained.
*Designer's call; recorded because it makes English and Chinese differ in politeness.*

**9.2 — 继续对局 cannot also be Resume Game.** 继续对局 is accepted at `id:350` as the threefold notice's
*decline-the-draw* action. Resume Game (`id:296`) is a different action in a different place. In English the
two are naturally **Keep Playing** and **Resume Game** and there is no problem; in Chinese, the obvious
rendering of Resume Game is the string that is already taken. I propose **回到对局** for Resume Game. *Designer's
call, but it constrains §4 and must not be resolved by reuse.*

**9.3 — 本局设置 as a group header.** Literally "settings for this game". "This Game's Settings" is 160.5 pt
and clumsy; "Game Setup" is 94.1 pt but names a screen rather than a group; **This Game** is 81.3 pt and is the
Apple-idiomatic form for a settings group scoped to one object. I recommend **This Game**. *Designer's call.*

**9.4 — 深思.** 深思 is "deep thought / deliberation". **Deep** (40.4 pt) matches the serialized `deep` and
keeps the three levels one word each; **Deliberate** (78.0 pt) is better English but is easily misread as the
adjective; **Deep Think** (86.7 pt) is closest in meaning and least Apple-like. I recommend **Deep**.
*Designer's call.*

**9.5 — 可判和 does two jobs and English cannot.** `id:272` and `:352` call it an **affordance** (a control the
user acts on); `id:305` uses the same string as a **metadata token** (a fact about the game). Chinese already
distinguishes the action 判和 (`id:313`) from the state 可判和, so the source is internally consistent — but the
*affordance* is named with the state word, which English cannot carry: a control reading "Draw Available" is
not a control. I propose **Claim Draw** for the affordance and **Draw Available** for the metadata token, i.e.
English uses two strings where Chinese uses one. That is the right answer, and it means the contract must say
so explicitly rather than listing a single localized equivalent. *Designer's call with a contract-shape
consequence.*

**9.6 — Stalemate is a loss here, and "stalemate" says "draw" in English.** `xiangqi-rules.md:51` accepts that
*"A position with no legal move is a loss for the player who cannot move"*, and `mx-end-002` pins it. Any
chess-literate English reader sees "Stalemate" and reads "draw". This is a teaching app. Options: keep
**Stalemate** (matches the frozen identifier `stalemate`, one word, and Help corrects it); use **No Legal
Moves** (accurate, self-explaining, 5 pt wider than Stalemate at 17 pt, and diverges from the identifier); or
keep Stalemate on the card and add the explanatory second line the result card already provides (`id:340`,
*"A second line explains the result reason"*), which costs nothing because that line is already required. I
recommend the third. *Owner's — it is a teaching decision, see §12.*

**9.7 — 步 is plies, and "moves" is not.** `game-data.md:143` stores *"move count in plies"*, and
`interaction-design.md:305`'s example 42 步 is therefore 42 plies. Chinese 步 conventionally counts single
moves, so 42 步 is unambiguous to a Chinese reader. English "42 moves" will be read by a chess-literate user as
42 *full* moves — twice the number. The options are **42 moves** (natural, and consistent with what Xiangqi
instruction means by 步, but ambiguous to a chess reader), **42 plies** (exact, jargon, and unhelpful to the
beginner this app exists for), or **42 half-moves** (exact, ugly, 1.5× wider). I recommend **42 moves** with
Help defining a move as one player's move, because the app's own notation and its Undo behaviour already use
that sense throughout (`id:329` distinguishes a "ply" from a "decision cycle" precisely because it needs to).
*Owner's — it fixes what the app teaches "move" to mean, and it propagates into Help, the move list, and the
notation. See §12.*

**9.8 — 你执红 has no tense-neutral English.** 执红 ("holding Red") works for an ongoing game and a finished
one. English forces a choice: **You: Red** (67.1 pt, tense-free, but a colon inside a middle-dot run),
**Playing Red** (88.9 pt, ongoing), **You Played Red** (117.4 pt, finished). One string must serve the
pre-start confirmation's metadata (an active game) and the History row (a finished one). I recommend **You:
Red** / **You: Black**. *Designer's call.*

**9.9 — The middle-dot metadata composition does not survive at the board block in English.** §5 measures it:
four of eight realistic English metadata lines overflow 308 pt at 17 pt. *Owner's — see §12.*

**9.10 — 棋 and 对局 both become "game".** 删除这盘棋 uses 棋 (the game as a record); 开始新对局 uses 对局
(the game as a contest). English has one word. Nothing is broken by the collapse, but it means "game" carries
two senses in the English build that the Chinese keeps apart, and Help should not rely on the distinction.
*No decision needed; recorded so it is not rediscovered.*

---

## 10. The localization review process (`interaction-design.md:534` and `testing.md:211` — one decision, two homes)

**Apple publishes no process guidance for reviewing translation quality.** I searched for it and it is not
there. What Apple publishes is *mechanism*: String Catalogs, the Xcode Localization Catalog (`.xcloc`) with
XLIFF inside it, `xcodebuild -exportLocalizations` / `-importLocalizations`, pseudolanguages, and localization
screenshots. Who signs off, and on what evidence, is ours to design. I own that recommendation rather than
deferring it.

### 10.1 The proposal

**Bilingual contract table + String Catalog build artefact + a mechanical agreement gate.**

1. **The contract holds the normative bilingual table.** Every string in §3 and §4 lives in
   `interaction-design.md` as a three-column table — *key · Simplified Chinese (normative) · English* — and a
   change to any cell is a contract change reviewed as a contract change. This is the only option that keeps
   `id:455`'s claim ("the accepted user-facing copy in this document is normative") literally true, and the
   inventory is 60 strings plus the nine end reasons, which is small enough to carry.
2. **The String Catalog is the build artefact, and the key is the join.** `Localizable.xcstrings` with
   **stable symbolic keys** (`alert.saveFailed.title`), not with the source string as the key. Apple's default
   is source-string-as-key; that is wrong here, because the source language is Chinese and a Chinese key in a
   catalog reviewed by an English reader is unreadable, and because a wording change in the normative Chinese
   would silently orphan every translation.
3. **The gate is mechanical and belongs in `testing.md`.** One check, runnable in CI, that the contract table
   and the String Catalog agree for both languages: same key set, same values, no key in the catalog that is
   absent from the table. This is the evidence `testing.md:211` asks for, and it does not require a second
   human.
4. **Two human checks per internal build**, added to the existing manual smoke list at `testing.md:200`:
   - run the app under the **Double-Length** and **Bounded String** pseudolanguages and confirm no truncation
     and no board-block intersection (Xcode > *Preparing your interface for localization* > "Run your app using
     pseudolanguages");
   - run the app in English and in Simplified Chinese through the accepted smoke flows, using the system's
     per-app language setting, which `testing.md:157` already gates.
5. **Nothing machine-translated ships as accepted.** Xcode > *Localizing your app using agents* marks agent
   translations as **Machine Translated** in the catalog and sets XLIFF `state-qualifier` to `leveraged-mt`.
   The rule to record: a string in that state is a draft; acceptance is the contract table, and a build whose
   catalog still carries `leveraged-mt` on a user-facing key fails the agreement gate.
6. **No XLIFF export/import round trip**, and no named per-language reviewer, until a second English-native
   reviewer actually exists. Apple documents the round trip (*Exporting localizations*, *Editing XLIFF and
   string catalog files*, *Importing localizations*) and it is the right machinery for a vendor pipeline; for a
   two-language internal app with one reviewer it adds a hand-off with nobody on the other end.

### 10.2 What it costs

The contract grows by about 70 rows and every copy tweak becomes a PR against `interaction-design.md`. That is
the price of the normativity claim already in the contract, and it is the reason this is framed as the owner's
decision in §12 rather than settled here.

### 10.3 Where it lands

One decision, two homes: the *what* (bilingual table, symbolic keys, machine-translation rule) belongs in
`interaction-design.md`'s Localization section; the *evidence* (the agreement check, the two pseudolanguage
runs, the two-language smoke pass) belongs in `testing.md`, and `testing.md:211` is then deleted rather than
answered twice.

---

## 11. Apple documentation — what exists, and what does not

**Found and used:**

- HIG > **Alerts** > *Content* — the title/message capitalization and punctuation rule, "be direct, and use a
  neutral, approachable tone", "Avoid explaining alert buttons".
- HIG > **Alerts** > *Buttons* — one- or two-word titles, verb phrases, "Always use 'Cancel'", avoid OK,
  destructive-style guidance, title-style capitalization with no ending punctuation.
- HIG > **Buttons** > *Content* — "consider starting the label with a verb", title-style capitalization, and
  the link to the Apple Style Guide's capitalization definitions.
- HIG > **Inclusion** > *Languages* — plain language and avoiding culture-specific content as localization
  preparation.
- Xcode > **Preparing your interface for localization** > *Run your app using pseudolanguages* — the seven
  pseudolanguages, with the Double-Length, Accented and Bounded String definitions quoted in §5.
- Xcode > **Localizing your app using agents** > *Add languages and translations* — the Machine Translated
  state and the `leveraged-mt` XLIFF qualifier, used in §10.5.
- Xcode > **Exporting localizations**, **Editing XLIFF and string catalog files**, **Importing localizations** —
  the `.xcloc` / XLIFF round trip, cited and *not* adopted in §10.6.
- Xcode > **Localizing strings that contain plurals** — the mechanism behind §8.7.
- Xcode > **Localizing and varying text with a string catalog** — the String Catalog itself.

**Not found, stated plainly:**

- Apple publishes **nothing** on reviewing or accepting translation quality — no reviewer roles, no sign-off
  criteria, no evidence requirements. §10 is ours, and I own it.
- Apple publishes **nothing** on Chinese-to-English UI copy specifically, and nothing on choosing a non-English
  source language. The source-language rule at `id:455` has no external authority behind it; it is the
  project's own.
- Apple publishes **no** expansion factor or length budget for translated UI. The 1.60× mean and the 4.44×
  worst case in §5 are measured by me, not cited.
- The Apple Style Guide, which the HIG links to for capitalization, is an Apple Support page rather than
  developer documentation and is outside what the documentation tool returns; the capitalization rules used
  here are quoted from the HIG pages themselves, which restate them.

---

## 12. Open for the owner

Six choices genuinely need the product owner. Everything else in this document is a designer's call and is
marked as such in place.

### 12.1 General or King

`interaction-design.md:74` accepts **General**. `xiangqi-rules.md` says **king** at `:28`, `:42`, `:45`, `:52`,
`:104` and in the fixture prose, and the FEN letter `k` and the fixture id `mx-move-005` reinforce it. Two
accepted contracts, two English words, same piece.

- **Affirm General.** Matches the Chinese 帅/将, matches international Xiangqi usage, and matches the app's
  stated purpose of teaching Xiangqi rather than chess-with-different-pieces. **Cost:** `xiangqi-rules.md` must
  be corrected — an accepted contract edited — and the "kings facing" / "flying generals" family goes with it
  (§6.3). The FEN letter stays `k`, which is now a machine detail rather than a name.
- **Adopt King.** One word already used in the rules contract and in every engine artefact, and instantly
  understood by a chess-literate learner. **Cost:** `interaction-design.md:74` is edited instead, the app
  teaches a piece name no Xiangqi book uses, and the Red/Black character pair 帅/将 — both of which mean
  *general* — is left unexplained in Help.

*This is the owner's because it is a teaching decision and because either answer edits an accepted contract.*

### 12.2 What "move" means in English (步)

The stored count is plies (`game-data.md:143`); the Chinese 步 says so unambiguously; English "42 moves" does
not.

- **"42 moves", move = one player's move.** Natural, short, matches Xiangqi convention and the app's own Undo
  vocabulary. **Cost:** a chess-literate reader silently halves it; Help and the move list must define the
  term, and the definition then binds the notation work in 6.5 and the Help content in 7.6.
- **"42 plies".** Exact and unambiguous. **Cost:** jargon in a beginner's app, and it appears in every History
  row.
- **"42 half-moves".** Exact and plain. **Cost:** 1.5× wider, and it makes the metadata line overflow worse.

### 12.3 Whether the middle-dot metadata composition survives in English

Measured in §5: every Chinese metadata line fits the accepted 308 pt board block at 17 pt; four of eight
English equivalents overflow, by 27 to 111 pt.

- **Keep the composition, let it wrap.** Zero copy change. **Cost:** the English metadata is two lines where
  the Chinese is one, in the stacked layout that `id:515` already flags as space-constrained.
- **Keep the composition, drop English to a smaller style.** Every English line fits at 13 pt. **Cost:** the
  two languages render the same element at different type sizes, which is a divergence the contract has so far
  avoided everywhere.
- **Change the composition in English only** — label/value rows instead of a middle-dot run. **Cost:** the
  accepted example lines at `id:305` no longer describe the English build, and part 4 and part 7 inherit a
  second layout.
- **Shorten the English end-reason names** (§4) so the run fits. **Cost:** "Mutual Perpetual Chase" has no
  shorter accurate form, and shortening it is a terminology change, not a layout change.

### 12.4 Whether "Stalemate" is the English label for a loss

§9.6. Keep **Stalemate** and let the result card's already-required second line correct it (my recommendation,
costs nothing); or use **No Legal Moves** and diverge from the frozen `stalemate` identifier; or keep
Stalemate and say nothing, which teaches the wrong rule to exactly the reader this app exists for.

### 12.5 Register — how terse the English is allowed to be

The Chinese is terse and declarative and uses 请 exactly twice. Two coherent English voices:

- **Mirror the source.** English carries 请 as "Please" where and only where the Chinese has it, and says
  nothing the Chinese does not. **Cost:** it collides with HIG's "avoid explaining alert buttons" (§9.1), and
  the save-failure capsule grows from 266.8 to 318.0 pt.
- **Follow the HIG and let English be terser than its source.** **Cost:** the English build says less than the
  normative copy in two places, which is a small but real breach of "its English counterparts are translations
  of it."

*Owner's because it is product voice, and because the second option makes the normativity claim at `id:455`
slightly untrue by design.*

### 12.6 What the localization review process costs

§10 recommends: bilingual table in the contract, String Catalog with symbolic keys as the artefact, a
mechanical agreement check in `testing.md`, two pseudolanguage runs and a two-language smoke pass per internal
build, and no machine-translated string accepted.

- **Adopt it.** **Cost:** `interaction-design.md` grows by ~70 rows and every copy tweak is a contract PR. This
  is the only option under which "the accepted copy is normative" stays literally true.
- **Contract holds only the strings whose wording is a product decision; the catalog holds the rest.**
  **Cost:** lower friction, and drift between the two — which is exactly the failure mode the
  Chinese-only/English-only split in §4 and §8.1 already demonstrates in this project.
- **Full XLIFF export/import with a named reviewer per language.** **Cost:** heaviest, and defensible only if a
  second English-native reviewer exists. Today there is one reviewer, so this buys ceremony rather than
  scrutiny.

---

## 13. Sequencing note for whoever picks this up

- §4's end-reason vocabulary is a **prerequisite** for 6.6, the notation test oracle, and for part 7's History
  row design — both need the display strings this document proposes and neither can be finished without them.
- §3.9's five design names are gated on `interaction-design.md:535` (are style and symbol names user-facing?).
  If they are, that item must also produce the two Settings **group** labels, which exist in neither language;
  this document proposes the option labels only.
- Nothing here touches 6.5 (notation's unhandled cases) or 6.6 (the oracle table); they are separate items with
  separate owners and they do not depend on this one except through §4.

---

# Independent review

Adversarial verification of everything above against `MiniXiangqi` at `60fc044` (working tree clean),
against Apple documentation via `mcp__xcode__DocumentationSearch`, and by re-executing the report's own
measurements. Workspace-only; nothing here is a decision either.

**What I re-executed.** (a) The bolded-string extraction over all eight `docs/*.md`. (b) The CoreText width
measurement, independently written: `NSFont.systemFont(ofSize:)` + `CTLineCreateWithAttributedString` +
`CTLineGetTypographicBounds`, run under `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`,
covering 24 of the report's figures plus every metadata line at both 17 pt and 13 pt. (c) `grep` audits of
`king`/`square`/`请`/`ply` across the contracts. (d) Nine Apple documentation queries.

**What survived.** Every individual width I re-measured reproduces to 0.1 pt: Han 16.9, Latin `n` 9.5,
Pin 0.70, Unpin 0.66, Fast 0.94, Try Again 2.11, Claim Draw 2.56, Checkmate 2.57, Chinese Characters 4.44,
Retry 40.4, "This can't be undone." 164.3, capsule 318.0 / 266.8. **Every Apple citation is verbatim and in
the section named** — HIG > Alerts > Content (all three quotes), HIG > Alerts > Buttons (all four, including
the destructive-style and Cancel rules), HIG > Buttons > Content, HIG > Inclusion > Languages, Xcode
*Preparing your interface for localization* > Run your app using pseudolanguages (the Double-Length, Accented
and Bounded String wordings are exact, and there are indeed seven), Xcode *Localizing your app using agents* >
Add languages and translations (Machine Translated and `state-qualifier` = `leveraged-mt`, exact), *Editing
XLIFF and string catalog files*, *Importing localizations*, *Localizing strings that contain plurals*, String
Catalogs. **No MISQUOTED. No NOT FOUND.** The §3 master table is the correct 60-atom set. 困毙, 长将, 长捉 are
the right standard terms, and 步 = ply is right. The §3.6 #48 argument against "This can't be undone" holds:
`product.md:62` does say "A completed deletion is permanent: the target MVP has neither deletion Undo nor
Recently Deleted." The nine `end_reason` values at `game-data.md:50` and the "exactly one has display copy"
finding are both correct and are the most valuable thing in the document.

Twenty-three defects follow. Four are blocking.

---

## Blocking

### R1 — "at 13 pt every English line above fits" is false, and it kills one of §12.3's four options

> §5: "or drop to a smaller type style (**at 13 pt every English line above fits — the widest is 268 pt**)"
> §12.3: "**Keep the composition, drop English to a smaller style. Every English line fits at 13 pt.**"

Measured, same method, at 13 pt:

| Line | en @13 pt | vs 308 |
|---|---|---|
| In Progress · Black to Move · 42 moves | 234.1 | fits |
| In Progress · Draw Available · 42 moves | 237.2 | fits |
| Draw · Threefold Repetition · 128 moves | 241.0 | fits |
| Red Wins · Threefold Repetition · 128 moves | 267.0 | fits |
| Black Wins · Mutual Perpetual Chase · 128 moves | 297.6 | fits, 10.4 pt spare |
| Human versus AI · You: Red · Resigned · 128 moves | **309.1** | **over** |
| Human versus AI · You: Black · Ended Early · 128 moves | **334.2** | **over by 26.2** |
| You control both Red and Black. Red moves first. | 294.5 | fits |

The widest is **334.2 pt, not 268 pt**, and **two of the eight still overflow at 13 pt**. 268 is the fourth
line only — the report appears to have checked one line and generalised. The size at which the worst line
first fits is `308 / 419.2 × 17 ≈ **12.5 pt**`, below the 13 pt floor `interaction-design.md:153` sets for the
*numeral* strips and well into territory the contract does not use anywhere.

**Severity: blocking.** §12.3 presents four options to the owner and this one is stated as a measured fact.
It is not an option. **Correction:** delete "every English line fits at 13 pt"; if the smaller-type option is
kept at all, state it as ~12.5 pt and note that the contract uses no type style that small.

### R2 — "square appears nowhere as a board term" is the opposite of what the contracts say

> §6.2: "Note that 'square' appears nowhere as a board term, deliberately … **The one accepted exception is
> `id:227`**, 'Tapping an illegal board square', which is prose about input rather than a user-visible string"
> Summary: "Board: point (never 'square'), file, rank, palace, river, screen — **all already consistent in
> accepted rules prose**."

`xiangqi-rules.md` uses **square** as *the* board term, six times, including inside accepted normative text:

- `:34` "**Squares are named `a1` through `g7`**: files `a` to `g` from Red's left…" — the accepted coordinate contract
- `:36` "the origin **square** followed by the destination **square**" — the accepted canonical notation
- `:42` "A king moves one **square** orthogonally inside its palace."
- `:44` "A chariot moves any number of unobstructed **squares** orthogonally."
- `:47` "A soldier moves and captures one **square** forward or one **square** sideways…"
- `:75` inside the **bolded accepted interpretation**: "attacks the target from the **square** it now occupies"

And `core-interface.md:68` freezes it in the C API: `mxq_game_legal_moves_from(const MxqGame *game, const char
*from_square, …)`. `xiangqi-rules.md` never once uses "point" as a board term. Within
`interaction-design.md` the exception is *two* places, not one — `:227` and `:440` ("tapping an illegal
square") — plus `testing.md:159` ("the illegal-square haptic").

This is exactly the cross-contract terminology conflict the report files as defect §8.3 for General/king, and
it is the larger of the two: it reaches the frozen coordinate contract and the frozen C interface, not only
prose. The report asserts consistency at the precise point where the biggest inconsistency lives, and §6.2's
"point (never 'square')" would, if adopted as written, put the English terminology in direct conflict with an
accepted contract without anyone noticing.

**Severity: blocking.** **Correction:** file this as a defect beside §8.3/§8.4, and add it to §12.1's scope —
whoever decides General-or-King is deciding point-or-square in the same breath, because both are
`xiangqi-rules.md` prose against `interaction-design.md` prose. Note that unlike General/King, the C API name
`from_square` is a machine detail that need not follow the user-facing choice.

### R3 — the two headline aggregate widths are not derivable from the report's own table

> §5: "Over the 60-string inventory, English is 1.60× the width of the accepted Chinese (**5474.5 pt** of
> Chinese against **8739.2 pt** of English, at 17 pt, summed)."
> §0: "All width figures in this document were **measured**, not estimated."

Parsing the §3 master table mechanically (59 rows carry numbers; #32 **AI** carries `—`):

- sum zh = **4674.1 pt**, sum en = **7532.4 pt**, ratio **1.6115**.
- adding §4's nine end-reason rows (438.1 / 1092.9): **5112.2 / 8625.3**, ratio 1.687.

Neither reaches the stated totals. The stated Chinese total is 800.4 pt above the table's own sum and the
English total 1206.8 pt above it. The **ratio** the report leads with is nearly right by luck (1.60 against the
table's 1.61), but the two absolute figures are attached to no experiment the document contains.

**Severity: blocking**, because §0 stakes the document's credibility on "measured, not estimated" and these are
the two numbers a reader will quote. **Correction:** recompute and publish the sum, or drop the totals and
keep only the per-string ratios and the distribution, which are sound.

### R4 — the source uses 请 three times, not two, and the report's own English already drops one

> §9.1: "The Chinese uses 请 in **exactly two places**: 无法保存这一步，请重试。(#49) and 当前对局仍然保留。请重试。(#43)."
> §12.5: "The Chinese is terse and declarative and uses 请 **exactly twice**."

`grep -o '\*\*[^*]*请[^*]*\*\*' docs/*.md` returns three distinct strings. The third is #45 itself:

> `interaction-design.md:284` — **当前可用内存不足。请尝试关闭一些其他 App，然后重试。**

and the report's own proposed English for #45 is "There isn't enough memory available right now. **Try closing
some other apps**, then try again." — 请 dropped, silently, with no entry in §9.1 and no mention in §12.5.
So the document has already chosen option (b) for a string it excluded from the analysis that frames option
(b) as the owner's choice. §12.5's cost line ("the English build says less than the normative copy **in two
places**") is wrong in both the count and the inventory: the two places it names are #43 and #49, and #45 is a
third where the English *already* says less.

**Severity: blocking**, because §12.5 is an owner decision and its factual premise is wrong. **Correction:**
"three places"; add #45 to §9.1; state that #45's 请尝试 is a softener on an *instruction*, not a redundancy
beside a button, which is a different case from #43 and #49 and may resolve differently.

---

## Serious

### R5 — five of the "60 accepted user-facing strings" are not accepted user-facing strings

> §0: "gives the exact scope of this item: > **60 accepted user-facing strings**"

`interaction-design.md:535`, verbatim:

> "Decide **whether** the piece-style and piece-symbol names **are user-facing interface strings or internal
> design names**, and approve their wording if they are user-facing."

传统, 现代, 高对比, 汉字, 图标 are therefore not accepted user-facing strings; whether they are *any* kind of
user-facing string is open. §3.9 concedes this in its heading ("status contested — gated on
`interaction-design.md:535`") and §13 repeats it — but §0's headline, §1's "Eleven of the sixty", §5's "Over
the 60-string inventory", and §5's "The single worst is 汉字 → Chinese Characters at **4.44×**" all count them
as in scope. The worst expansion in the whole document is carried by a string that may never be shown to a
user.

**Severity: serious** — it is the document's single most-quoted number and it inflates the accepted scope by
five. **Correction:** "55 accepted user-facing strings, plus 5 gated on `:535`"; move §3.9 out of the
inventory totals; restate the worst *accepted* expansion, which is 判和 → Claim Draw at 2.56 and 将死 →
Checkmate at 2.57.

### R6 — the 308 pt board block is applied to text the contracts put in an alert and a list row

> §5: "**The concrete layout consequence, against the accepted board block.** … Elements aligned to the board
> — the pre-start explanation and the metadata lines — are therefore working against a measurable 308 pt."
> §12.3: "Measured in §5: every Chinese metadata line fits the accepted 308 pt board block at 17 pt; four of
> eight English equivalents overflow, by 27 to 111 pt."

The metadata lines at `:305` are the **confirmation alert's** metadata. `:298`–`:303` place them:
"Selecting **Human versus AI** or **Free Play** … immediately uses one fixed confirmation … Title: **开始新对局？**
/ Metadata header: **当前对局** / Message: … / Actions: …", then `:305` "Only the metadata changes … Example
metadata lines include …". The other two homes the report itself names are the History row (`:369`) and the
Play destination's active-game row (`:296`) — a list row and a destination that shows no board. None of the
three is board-aligned, and `:38`–`:40` constrain **glass surfaces**, not text: "No **glass surface** may
intersect the **board block**."

The report's caveat 1 admits this ("Where a metadata line actually sits … is part 4's and part 7's undecided
territory") and then §12.3 asks the owner to decide a layout question stated as measured fact against a
constraint the contract does not impose on these strings.

Worse for the framing: **every accepted example line fits in English.** Measured at 17 pt:

| Accepted example (`id:305`) | zh | en | vs 308 |
|---|---|---|---|
| 红方获胜 · 将死 · 42 步 → Red Wins · Checkmate · 42 moves | 169.3 | **259.6** | fits, 48.4 pt spare |
| 人机对弈 · 你执红 → Human versus AI · You: Red | 131.3 | **208.7** | fits |
| 进行中 · 轮到黑方 · 42 步 | 186.1 | 293.5 | fits |
| 进行中 · 可判和 · 42 步 | 169.3 | 297.2 | fits |
| 自由对弈 → Free Play | 67.4 | 69.7 | fits |

All five accepted examples fit. All four overflow cases are built from end-reason names the report itself
proposes in §4 (三次重复, 双方长捉, 认输, 提前结束) plus a **128**-ply count that appears in no accepted
example. The finding is legitimate as *foresight* — those strings will have to exist — but it is not "the
accepted composition does not survive."

**Severity: serious.** **Correction:** restate as "no accepted metadata line overflows; four *hypothetical*
lines built from §4's proposed end reasons and a three-digit move count do, **if** the line is ever bound to
308 pt, which no accepted contract requires." Then §12.3 becomes a note for parts 4 and 7, not a sixth owner
decision.

### R7 — "an alert's own width on iPhone is wider than 308 pt" is uncited and probably backwards

> §5, caveat 1: "**An alert's own width on iPhone is wider than 308 pt and wraps freely**, so #41, #43, #45 and
> #46 are not at risk; the *board-aligned* lines are."

This single unmeasured sentence exempts the four longest strings in the inventory (350.3, 365.5, 695.4 and
549.4 pt) from the whole analysis. It has no citation and no measurement, and it runs against the long-standing
`UIAlertController` alert width on iPhone of **270 pt** — narrower than 308, not wider. If that is right the
conclusion inverts: the alert bodies are the *most* constrained text in the app, and the report's method
(measure it) was available and was not applied.

Apple publishes no alert width in the HIG — I searched and it is not there — so this is measurable, not
citable. **Severity: serious**, because it is load-bearing and unexamined. **Correction:** measure the alert
content width on the narrowest supported iPhone before claiming these strings are safe, or state plainly that
their wrapping behaviour is unmeasured.

### R8 — 传统/现代 and 汉字/图标 are listed as "accepted English" on the wrong citation

> §1: "| 传统 / 现代 | **Traditional** / **Modern** | `product.md:82` names the default style 'the traditional
> one'; **the pairing is unambiguous** |"

`product.md:82` reads: "the **piece style**, chosen among the three accepted styles defined in
`interaction-design.md`, defaulting to the traditional one". That is one lowercase adjective inside a scope
bullet. "Modern" appears nowhere in `product.md`; the only English "modern" in the contracts is
`interaction-design.md:106`, "a learner may want icons on the traditional board, or characters on the modern
one" — again lowercase descriptive prose. "High contrast" in English appears exactly once, at
`interaction-design.md:536`, in a Windows accessibility to-do list about Narrator, unrelated to the style. So
§1 puts three strings in a table headed "What English is **already accepted**, and must be **reused rather than
re-decided**" on the strength of two adjectives and one inference the report itself flags ("the pairing is
unambiguous").

**Severity: serious**, because the table's whole purpose is to separate reuse from decision. **Correction:**
move all five design names out of §1 entirely; they are proposals gated on `:535`, exactly as §3.9 says.
(This and R5 are the same error seen from two sides, and §1 and §3.9 contradict each other on it — see R11.)

### R9 — the master table gives 可判和 the English §9.5 argues it must not have

> §3.4: "| 34 | 可判和 | `id:272`, `:305`, `:352`, `testing:78` | **Draw Available** (state) |"
> §9.5: "the *affordance* is named with the state word, which English cannot carry: **a control reading 'Draw
> Available' is not a control**. I propose **Claim Draw** for the affordance and **Draw Available** for the
> metadata token."

The affordance **is** 可判和. `interaction-design.md:272`: "The placement of the persistent **可判和**
affordance remains open below." `:352`: "the same still-valid claim is exposed through a non-blocking
**可判和** affordance." So row #34 — the only row for 可判和 — assigns to the affordance precisely the string
§9.5 says cannot be a control. Meanwhile "Claim Draw" is attached at #8 to 判和, which appears exactly once in
the contracts, at `:313`, in a sentence saying the confirmation does **not** offer it: "The confirmation does
not add **悔棋** or **判和** actions."

The master table is the deliverable. As written it hands the implementer "Draw Available" for the affordance
and "Claim Draw" for a string that names no control.

**Severity: serious.** **Correction:** split row #34 into 可判和 (affordance) → **Claim Draw** and 可判和
(metadata token) → **Draw Available**, and mark it as the one place where the English inventory is larger than
the Chinese — which is what §9.5 actually concludes and what the contract will have to record.

### R10 — §9.6/§12.4's recommendation is not free, and rests on a reading of `:340` the report elsewhere contradicts

> §9.6: "keep Stalemate on the card and **add the explanatory second line the result card already provides**
> (`id:340`, 'A second line explains the result reason'), **which costs nothing because that line is already
> required**. I recommend the third."

`interaction-design.md:340`: "The card title is the localized equivalent of **红方获胜**, **黑方获胜**, or
**和棋**. A second line explains the result reason." The second line **is** the reason. The report's own §4
and §5 treat the reason as a short label — 困毙 / Stalemate, set as a middle-dot token beside the result — and
§4 measures it as one. On that reading there is no spare line to correct "Stalemate" with, and the
recommendation requires new copy (a third line, or a reason line that is a sentence rather than a label). On
the other reading — the second line is an explanatory *sentence* — §4's whole end-reason label table is
answering the wrong question and §5's overflow analysis measures a string that does not exist.

The document needs one reading and does not pick one. **Severity: serious**, because §12.4 asks the owner to
choose between three options one of which is described as costing nothing and does not.

**Correction:** decide whether the result card's second line is the reason label or a sentence about it, say
so, and re-cost §12.4's option 3. Note that on the label reading the card still reads "**Black Wins** ·
Stalemate", and the title already contradicts the chess reader's inference — which is a real and free
mitigation the report does not use.

---

## Moderate

### R11 — §1 and §3 disagree about how many strings are already settled, and "46" follows from neither

> §1: "**Eleven** of the sixty strings already have accepted English somewhere in the contracts, and **three
> more** have an accepted English term in prose that settles them." … "**a 46-string job**, not a 60-string
> job, and 13 of the 46 are one or two words."

Eleven plus three is fourteen, and 60 − 14 = 46. But the §1 table lists **seventeen** strings once the slashed
rows are counted as the strings they are (置顶 / 取消置顶; 传统 / 现代; 汉字 / 图标), and the §3 master table
marks exactly **thirteen** rows "*(accepted)*": #7, #9, #12, #13, #14, #15, #17, #18, #19, #28, #32, #50, #51 —
which excludes all five design names. So the remaining job is 47 by §3's marking, 43 by §1's table, and 46 by
neither. Applying R5 and R8 (design names out of scope, out of §1) gives the defensible figure: **55 accepted
strings, 13 already settled, a 42-string job.**

**Severity: moderate.** **Correction:** one count, derived once, and make §1's table and §3's "(accepted)"
markers agree row for row.

### R12 — the extraction count is off by one and the stated arithmetic does not reach 60

> §0: "by a throwaway Python pass: **58 distinct bolded strings**, one of which is prose … Four of the
> remaining 57 are composite … decomposing them yields five further atoms … Adding the one bolded non-Han
> user-facing string (**AI**) gives … **60 accepted user-facing strings**"

Re-running the same extraction over all eight `docs/*.md` at `60fc044` returns **59** distinct bolded
Han-bearing strings, not 58. The arithmetic as stated gives 57 − 4 + 5 + 1 = **59**, not 60; the correct
answer of 60 follows only from 59 extracted (58 non-prose − 4 composite + 5 new atoms + AI = 60). The §3 table
of 60 is right; the executed number that produces it is misreported and the derivation does not close.

**Severity: moderate** — the table is correct, but §0 presents this as the executed foundation of the scope.
**Correction:** 59 extracted, 58 non-prose, 54 atomic, +5 decomposed atoms, +1 (**AI**) = 60.

### R13 — "six user-facing elements" against a table of eight

> §4: "**Six** user-facing elements violate that rule today by existing only in English."
> §4, two paragraphs later, after an eight-row table: "So **four of eight** need recording, not deciding."
> §8.1 repeats: "**Six** user-facing elements exist only in English".

The bolded English-only user-facing strings in the contracts are exactly eight: **Play** (`id:21`,
`product:72`), **History** (`id:22`, `product:73`), **Settings** (`id:23`, `product:74`), **Human versus AI**
(`id:183`, `:298`), **Free Play** (`id:183`, `product:33`), **Resume Game** (`id:296`), **Flip Board**
(`id:214`), **Confirm Before Deleting** (`product:62`, `game-data:125`). Six is wrong in both places.

**Severity: moderate.** **Correction:** eight throughout.

### R14 — 历史 and 设置 are not "already accepted"; two of the four, not four

> §4: "**Four of the eight therefore require no decision at all**; they require the contracts to record
> Chinese that is **already accepted** elsewhere in them."
> Table: "| **History** | … | **历史** | already used in accepted copy: 保存到历史 (`id:302`), 已记录到历史
> (`id:343`) |"

人机对弈 and 自由对弈 genuinely are accepted standalone strings, at `id:305`. 历史 and 设置 are **morphemes
inside** accepted strings — 这盘对局将按当前状态保存到**历史**。and 本局**设置** — not accepted labels. A
navigation destination label is a new string, however obvious; that is the same standard the report correctly
applies to 三次重复 ("a fragment of accepted copy … rather than an accepted label"). Applying it consistently
gives **two** of the eight requiring no decision, not four.

**Severity: moderate.** **Correction:** two recorded (人机对弈, 自由对弈), one already accepted and needing
only alignment (删除前确认), five proposed (历史, 设置, 对局, 回到对局, 翻转棋盘).

### R15 — "Apple publishes nothing on reviewing translation quality" is too strong, and misses the one page that bears on §10.6

> §11: "Apple publishes **nothing** on reviewing or accepting translation quality — no reviewer roles, no
> sign-off criteria, no evidence requirements. §10 is ours, and I own it."
> §10.6: "**no named per-language reviewer**, until a second English-native reviewer actually exists."

Apple publishes a thin but directly on-point recommendation, twice:

- Xcode > **Localization**, Overview: *"To get the best feedback on your translations, distribute your app to
  native speakers in the languages that you support. For more information on using TestFlight, see
  Distributing your app for beta testing and releases."*
- Xcode > **Localizing your app using agents** > *Test machine translations*: *"Get feedback from people who
  speak the languages and live in the regions you support."*

That is Apple naming a reviewer role (native speakers) and a delivery mechanism (TestFlight) — and this
product distributes by **TestFlight internal testing** (`product.md:14`), so the recommendation lands exactly
on §10.6's reasoning. It is not a sign-off process and it does not change §10's shape, but "nothing" is wrong
and the report's stated method is to engage what exists.

**Severity: moderate.** **Correction:** narrow the negative to "no reviewer roles, sign-off criteria, or
evidence requirements; the only guidance is 'get feedback from native speakers, via TestFlight'", and say
whether §10.4's two-language smoke pass is meant to satisfy it or replace it.

---

## Minor, but each one is a wrong citation a reader will follow

### R16 — the toolchain is mislabelled

> §0: "on the pinned toolchain (`DEVELOPER_DIR=…`, **Swift 27.0 / build `26A5388g`**)"

Measured on this machine: `sw_vers` → ProductVersion **27.0**, BuildVersion **26A5388g** — that is **macOS**,
not Swift. `swift --version` → **Apple Swift version 6.4** (`swiftlang-6.4.0.27.1`). `xcodebuild -version` →
**Xcode 27.0, build 27A5228h**, which is the build `testing.md:13` pins ("Expected build: `27A5228h`"). The
report names the OS build where the contract's own gate names the Xcode build.
**Correction:** "macOS 27.0 (26A5388g), Xcode 27.0 (27A5228h), Swift 6.4".

### R17 — `xiangqi-rules.md:45` is the horse, not a king

> §8.3 and §12.1: "General (`id:74`) against king (`xiangqi-rules:28`, `:42`, **`:45`**, `:52`, `:104`…)"

`:45` is "A horse uses Xiangqi horse movement and is blocked when its orthogonal first step is occupied." —
no king. The actual sites are `:28`, `:29`, `:35`, `:42`, `:43`, `:52`, and `:100`/`:104`/`:106` in the fixture
list. The finding is right; the citation list is not, in two places.

### R18 — `id:329` does not distinguish a ply from a decision cycle

> §9.7: "(`id:329` distinguishes a 'ply' from a 'decision cycle' precisely because it needs to)"

`:329` reads "After the AI has replied, one Undo action removes the AI reply and the preceding human move,
returning to the previous human decision point. The action can be repeated by complete decision cycles." — the
word "ply" is absent. The contrast is at **`:416`**: "an Undo transition must therefore complete within 250 ms
for **one ply** and 600 ms for a **decision cycle**." (`game-data.md:102` is the other "ply" site: "Free Play
removes one **ply** per Undo action".) The argument is sound; move it to `:416`.

### R19 — `testing.md:157` does not gate the language check

> §10.4 and the summary: "using the system's per-app language setting, **which `testing.md:157` already
> gates**."

`testing.md:157` is "Verify a held piece still reads as raised under Reduce Motion, and that no piece style
suppresses the lift." The per-app language check is **`testing.md:163`**: "Verify the app follows the operating
system's language selection, **including through an Apple per-app language change**, and that it offers no
interface-language control of its own." This citation is repeated in the summary, so it will propagate.

### R20 — the "Done" gloss borrows an alert rule for a card button

> §3.1 #3: "**Done** … HIG names Done as the single-button dismissal title"

What HIG > Alerts > Buttons says is narrower: *"if you must display an alert with a single button that's also
the default, use a Done button, not a Cancel button."* That is a rule about **alerts**. 完成 at
`interaction-design.md:344` is a button on the **result card** — a custom glass surface (`:38`) with two
actions, 回放 and 完成 — not an alert and not a single-button dismissal. The English is still right; the
justification does not apply. Say "Done is the platform's ordinary completion title" and drop the HIG hook, or
cite it accurately as an alert rule being borrowed by analogy.

### R21 — Import/Export citation covers Import only

> §6.4: "| 导入 / 导出 | **Import** / **Export** | English accepted `game-data:111`, `product:63` |"

`product.md:63` is "Import accepts one compatible game file at a time…" — Import only. English "export" is at
`game-data.md:111` ("## Import and export") and, as a verb, `product.md:60` ("Share **exports** one game
file"). Nothing in `product.md` names an **Export** control; `product:60`/`id:376` say **共享** exports the
file, which means the app may have no user-facing "Export" label at all. Worth a line, since §6.4 proposes
导出 for a control that may not exist.

### R22 — 对局 as the Play destination collides with 当前对局

> §4: "| **Play** | `id:21`, `product:72` | **对局** | proposed; the destination that starts or resumes a game |"

对局 is the head noun of four accepted strings — 开始对局, 结束对局, 继续对局, and the confirmation's own
metadata header **当前对局** (`id:301`). A tab reading 对局 sitting beside a confirmation headed 当前对局
makes the same word name the destination and the game object, in a flow where the user moves between them.
This is the mirror of the §9.2 problem the report catches for 继续对局 / Resume Game, and it is not flagged.
Not wrong, but it belongs in §9 as a designer's call with its alternatives (棋局, 下棋, 对弈) and their costs,
rather than in a table as a bare proposal.

### R23 — testing.md is cited as a source for accepted copy without noting its status

Fourteen source cells in §3 cite `testing.md` (`testing:67`, `:71`, `:73`, `:78`, `:122`, `:171`, `:184`,
`:186`…). `testing.md:5` says: "**Status: Draft validation proposal.** **Nothing in this document is normative
until its status or an individual section is explicitly marked accepted.**" The strings themselves are all
independently accepted in `interaction-design.md`, so nothing breaks — but a reader auditing a source column
should be told that these are corroborating, not authorising, citations. One sentence in §0 fixes it.
The same applies to `engine-integration.md:194`, cited for **无法启动 AI 对手** at §3.6 #44: that line sits
under **Need to discuss** and authorises nothing.

---

## What the corrections do to the six owner decisions

- **12.1 General or King** — stands, and gets **larger**: R2 shows point/square is the same conflict between
  the same two contracts, reaching the frozen coordinate contract and the C API. Frame them as one decision.
- **12.2 What "move" means** — stands unchanged. Verified: `game-data.md:143` "move count in plies";
  步 does count single moves in Chinese Xiangqi usage. This is the cleanest item in the document.
- **12.3 Middle-dot composition** — should be **withdrawn as an owner decision**. R1 removes the smaller-type
  option outright; R6 shows every accepted line fits and the overflow is driven by the report's own proposals
  plus a 128-ply count. What remains is a note to parts 4 and 7: "when §4's end-reason names are approved,
  re-measure the composed line against whatever width the History row and the confirmation actually have."
- **12.4 Stalemate** — stands, but R10 removes "costs nothing" from the recommended option and adds a free
  mitigation the report missed: the card title already reads **Black Wins**, which contradicts the chess
  reader's inference without any new copy.
- **12.5 Register** — stands, but on corrected facts: three 请, not two, and the English already drops one of
  them (R4).
- **12.6 Localization review process** — stands, adjusted by R15: Apple does recommend native-speaker feedback
  via TestFlight, which is this project's distribution channel, so option 3's "ceremony rather than scrutiny"
  needs one sentence engaging that recommendation rather than resting on a bare "Apple publishes nothing".

## Method note

Everything above is either quoted from a file at `60fc044`, or re-measured with the same CoreText method the
report used, or returned by `mcp__xcode__DocumentationSearch` and quoted verbatim. Where I could not verify —
the iPhone alert content width (R7) — I say so and call for a measurement rather than supplying a number.
