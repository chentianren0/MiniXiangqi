# Part 7 · Help — structure, entry points, and illustrations

Research draft for the main thread. **Not contract text.** Nothing here is accepted; the main thread
authors whatever reaches `docs/interaction-design.md`.

Target item: `interaction-design.md:527` — *"Define help entry points, content organization, and
illustrations within the accepted read-only rules-reference scope."*

Throughout, three kinds of claim are kept apart:

- **Executed** — I ran it in this workspace and the output is reproduced.
- **Cited** — quoted from an accepted contract in `MiniXiangqi/docs/` or from Apple documentation, with
  the page and section named.
- **Reasoned** — my inference or my recommendation. Disagreeable by design.

Executed work used the pre-built Fairy-Stockfish Python extension at
`/Users/tianren/coding/minixiangqi/fs-chase/pyffish.cpython-314-darwin.so` (`pyffish.version() =
(0, 0, 89)`), built-in `minixiangqi` variant, invoked read-only. The engine was used **only** to
enumerate legal moves in candidate diagram positions; every rule statement in this report is taken from
`docs/xiangqi-rules.md` and the approved fixtures, never from the engine. That distinction matters here
because the built-in variant is known not to satisfy every approved fixture
(`fixtures/rules/README.md`, and `mx-chs-003`'s own rationale).

---

## 0. The accepted boundary, restated so it can be checked against

Everything in this list is already accepted and is **not** reopened below.

| Accepted | Source |
|---|---|
| Help is a read-only Mini Xiangqi rules reference covering *the board, the pieces and their movement, check and checkmate, stalemate, repetition and the claimable draw, perpetual check, and perpetual chase, plus a short explanation of the app's own controls* | `interaction-design.md:395` |
| Reachable from Settings **and** from the game screen, without abandoning or pausing state; opening it never modifies the active game; returning restores the exact prior context | `interaction-design.md:396` |
| Static reference material — no position analysis, no move suggestions, no interactive lessons or drills | `interaction-design.md:397`, `product.md:41`, `product.md:97` |
| Help text follows the same localization requirements as the rest of the interface | `interaction-design.md:398` |
| Education in the target MVP means *learning through play … supported by in-app help that explains the pieces, rules, and results* | `product.md:12` |
| English piece names — General, Chariot, Horse, Cannon, Soldier — *appear in help*, never as board labels | `interaction-design.md:74` |
| *There is no river … **Help calls it out.*** | `interaction-design.md:123` |

Three accepted constraints from outside the Help section bind the answer and are easy to miss:

1. **`interaction-design.md:38`** — the app defines **exactly three** custom glass surfaces (play control
   cluster, replay transport, and the shared result-card/threefold slot). *"System-provided glass — the
   tab bar or sidebar, navigation bar and toolbar, alerts, sheets, context menus, and History swipe
   actions — is additional and automatic."* A Help entry point that introduces a fourth custom glass
   surface is a contract violation; a Help entry point on a system surface is free.
2. **`product.md:70–74`** — the primary destinations are exactly **Play**, **History**, **Settings**. Help
   is not a fourth destination.
3. **`interaction-design.md:193`** — a pre-start draft is *"discarded as soon as the user leaves the
   page."* This one turns out to be load-bearing; see §2.3.

---

## 1. What is genuinely open, and what this report answers

`interaction-design.md:527` names three things. Splitting them honestly:

| Open sub-question | Status after this report |
|---|---|
| Entry points — the concrete affordance, placement, label, and presentation shell from each of the two accepted entrances | Answered, §2, with one dependency on the unaccepted part 4 |
| Content organization — section structure, ordering, teaching order, and how the standard-Xiangqi arrival is handled | Answered, §3–§4 |
| Illustrations — how many, drawn how, and with what scale | Answered, §5, with executed evidence and a derived metric band |

Not open, and deliberately left alone: *whether* Help is reachable and *from where* — that is settled at
`interaction-design.md:396`.

---

## 2. Entry points

### 2.1 The design constraints, before the design

- Help must be reachable from the game screen. It must not cost a fourth custom glass surface (§0.1).
- It must not intersect the **board block** (`interaction-design.md:40`).
- It must not be added to the turn-status element, which is *"one coherent description of the current
  play state"* and which the contract explicitly forbids loading with unrelated instruction
  (`interaction-design.md:266`, `:273`).
- It cannot become a fourth tab (§0.2).
- **The vertical budget is real.** The measured chrome inventory in `discussion-drafts/layout-budget.md`
  (a prior agent's on-device measurement, iOS 27.0) records that a navigation bar costs **54 pt** on the
  board page, that the narrowest supported iPhone is **375 × 667** (SE 2nd/3rd gen), and that removing
  the navigation bar from the board page is what turns the SE's result-card configuration from failing
  to passing. So *"put a question-mark button in the play screen's navigation bar"* may not be an option
  at all on iPhone — it depends on a chrome inventory that PR #23 has not landed.

That last point is the reason this section gives a **rule** plus a per-layout affordance, rather than one
affordance that would be wrong half the time.

### 2.2 Proposal — the rule

> Help is reached from a control on a **system-provided functional surface** or from within the play
> control cluster. It never adds a custom glass surface, never sits inside the board block, and never
> attaches to the turn status.

Concretely, per layout (reasoned; the stacked case is dependent on part 4):

| Entrance | Layout / platform | Affordance | Notes |
|---|---|---|---|
| Settings | all | A row in its own Settings section, below the accepted preference groups | Help is not a preference, so it does not belong in `人机对弈默认设置` or beside the style/symbol pickers |
| Game screen | side-by-side (iPad landscape, wide iPad windows, ordinary Mac windows) | An item in the panel beside the board | `interaction-design.md:478` defines the panel as carrying *"controls that do not need to sit under the thumb"* — that is exactly what Help is |
| Game screen | stacked (iPhone portrait, narrow windows) | A low-emphasis item at the trailing end of the **play control cluster** | Costs no vertical chrome, because the cluster already exists and is already glass. **Dependent on part 4 (PR #23), which is not accepted** |
| Game screen | macOS, additionally | `Help ▸ Mini Xiangqi 帮助`, ⌘? | Required by HIG *The menu bar > Help menu*: the Help menu *"provides access to an app's help documentation"* and sits at the trailing end of the menu bar |

Ruled out, with reasons rather than taste:

- **A fourth tab.** Contradicts `product.md:70`.
- **A navigation bar on the board page purely to hold Help.** 54 pt measured, on the device that is
  already 17.5 pt short in the result-card state (`layout-budget.md:661`). Help is the least
  time-critical control in the app; it should not be the reason the board shrinks.
- **A floating help button over the board.** Fourth custom glass surface, and it intersects the board
  block.
- **A long-press or context menu on the board.** Board input is fully specified at
  `interaction-design.md:220–234`; a hidden gesture also contradicts the app's own stated preference for
  visible controls (`:218`, on Flip Board).
- **A tooltip-only affordance on Mac.** HIG *Offering help > macOS, visionOS* scopes tooltips to
  *"briefly describes how to use a component"* — it is the wrong instrument for a rules reference.

**One help control per surface.** AppKit's `NSButton.BezelStyle.helpButton` documentation states:
*"Include no more than one help button per window. Multiple help buttons in the same context make it
hard for people to predict the result of clicking one."* On macOS the toolbar/panel item and the Help
menu item are not "in the same context" and both are expected; within the window itself there is exactly
one.

### 2.3 Presentation shell — and why the pre-start draft decides it

Two shells, one content view.

| Entrance | Shell |
|---|---|
| Settings | **Pushed** onto the Settings navigation stack |
| Game screen, iOS/iPadOS | **Sheet** over the play screen, containing its own navigation stack, dismissed by `完成`. Large detent on iPhone; page or form sheet on iPad |
| Game screen, macOS | **A separate auxiliary window** |

The iPad choice follows HIG *Sheets > iOS, iPadOS*: *"Prefer using the page or form sheet presentation
styles in an iPadOS app."*

**The reason the game-screen entrance must be a sheet and not a push is `interaction-design.md:193`.** In
the human-versus-AI pre-start state the setup draft's values *"are discarded as soon as the user leaves
the page."* The pre-start state lives on the board page (`:183`), and a learner sitting in pre-start —
choosing 先手 and AI 等级 for the first time — is precisely the person most likely to open Help. If Help
pushed, it would leave the page, silently reset `我先手`/`AI 先手`/`随机` and `AI 等级` to the Settings
defaults, and contradict the accepted *"returning restores the exact prior context."* A sheet does not
leave the page. This is not a stylistic preference; it is the accepted draft rule choosing the shell.

**Why macOS gets a window rather than a sheet.** A macOS sheet is modal and dims its parent
(HIG *Sheets > macOS*: *"The parent window is dimmed while the sheet is onscreen"*). During
human-versus-AI play the AI may be searching; dimming the board for the duration of a rules lookup is
the closest thing to "pausing state" that the accepted text forbids in spirit. HIG *Sheets > Best
practices* points the same way: *"In a macOS experience, you might want to open a new window or let
people enter full-screen mode instead of using a sheet."*

> **Contract interaction to resolve in the text.** `product.md:26` says *"The application has one main
> window; multiple main windows are not supported."* A Help window is an auxiliary window, not a second
> main window, but the contract does not currently say so. Whatever text lands should make the
> distinction explicit rather than leave a reader to infer it.

**Rejected: an Apple Help Book.** It is the macOS-native answer (HIG *The menu bar > Help menu*:
*"When the content uses the Help Book format, opens the content in the built-in Help Viewer"*), and
`SwiftUI.HelpLink(anchor:)` exists for it. It is nonetheless wrong here: a Help Book is a separate HTML
content pipeline with its own localization mechanism, which conflicts with `interaction-design.md:398`
(*"Help text follows the same localization requirements as the rest of the interface"*), it exists on
macOS only while the same content must ship to iOS, iPadOS and Windows, and it cannot render the board
diagrams §5 proposes. One content view in the app's own string catalogue serves all four platforms.

**Modality objection, answered.** HIG *Modality > Best practices* warns: *"Take care to avoid creating a
modal experience that feels like an app within your app. In particular, presenting a hierarchy of views
within a modal task can make people forget how to retrace their steps."* Help is a two-level hierarchy
(table of contents → one topic), with a single path through it, a standard Back, and one unambiguous
dismiss control. That is the same shape as a Settings sheet and is within what the guidance
contemplates; the same page also says *"Consider using a full-screen modal style for in-depth content."*
Two levels is the ceiling — §3 keeps Help there.

### 2.4 Entry-point behaviour: where Help opens, and what the game does meanwhile

**Where Help opens.** Always at the table of contents, from both entrances, every time. No restored
scroll position across presentations; within one presentation the navigation stack behaves normally.

Reasoned: the alternative — opening at a topic chosen from the current position (`长捉` after a chase,
`将军与将死` while in check) — is contextual help, which HIG *Offering help > Best practices* actively
recommends (*"directly relate the help you provide to the precise action or task people are doing right
now"*). It is nonetheless the wrong call here: choosing the topic **is** reading the position, and the
accepted scope says Help *"does not analyze the current position."* A player who saw Help open itself at
`长捉` would reasonably conclude the app had just commented on their move. Cost of my recommendation: a
user re-reading one topic pays one extra tap each time. That is the right price. Framed for the owner in
§9.

**What the active game does while Help is open.** The accepted texts already decide most of this; the
table is an inventory rather than an invention.

| State when Help opens | What happens | Basis |
|---|---|---|
| Ongoing game, human to move | Nothing. Board, selection, and legal-destination markers are exactly as left | `:396` "restores the exact prior context" |
| A piece is selected | The selection survives; on return the same disc is lifted with the same destination markers | same |
| AI is thinking | The search continues and may complete and commit while Help is covering the board. On return the board shows the committed position, and the last-move brackets identify the AI's move | `:414` — the AI's move *"leaves persistent origin and destination markers so the player can identify the completed move"*; `:247` — brackets *"always mark the move that produced the position on screen"* |
| A natural result card is presented | The card is non-dismissible (`:339`); Help does not dismiss it; on return it is unchanged | `:339` |
| Threefold notice or the retained `可判和` affordance | Unchanged | `:350–352` |
| Human-versus-AI or Free Play pre-start | The in-memory draft survives, because a sheet does not leave the page (§2.3) | `:193` |
| History replay, autoplay running | **Proposed addition:** opening Help pauses autoplay | `:363` already pauses playback when *"the app mov[es] to the background"*; a sheet that covers the board has the same consequence for the viewer, and playback the user cannot see is playback wasted |

Two of these rows are proposals rather than deductions and should be marked as such in any contract text:
the AI-move-while-covered row (the alternative — deferring the arrival animation until Help closes —
would mean the app holds a committed state off-screen, which is worse) and the autoplay row.

---

## 3. Content organization

### 3.1 The organizing principle

Two readers arrive at this Help with opposite needs:

- Someone who has never played any Xiangqi. For them the game has no absences. Telling a beginner that
  there is *no river* and *no advisors or elephants* is telling them about pieces and lines they have
  never heard of, and it makes a simple game sound like a reduced version of a complicated one.
- Someone who plays standard Chinese Xiangqi. For them almost everything is already known and only the
  differences matter; a full re-teaching of how a 车 moves is an obstacle.

The principle that resolves this:

> **The teaching text never names what the game does not have. Absences are named in exactly one place —
> the first row of the table of contents, whose own title is its audience filter.**

So `棋子怎么走 › 兵 / 卒` says *"one point forward or sideways, never backward"* and stops. The sentence
*"in standard Xiangqi a soldier only gains the sideways move after crossing the river; here there is no
river, so it has the move from the first ply"* lives in row 1 and nowhere else.

This also satisfies `interaction-design.md:123` (*"There is no river … Help calls it out"*) precisely,
in a place where the statement means something to its reader, and it keeps row 1 from being scope
creep: row 1 introduces **no topic that is not already in the accepted eight**. It is a second
presentation of the accepted material for a second audience.

### 3.2 The table of contents — 11 rows, three groups

Copy is **Simplified Chinese, proposed, requiring approval.** Simplified Chinese is the source language
and the accepted copy is normative (`interaction-design.md:455`), so these are drafted as source strings,
not as translations. English is given as a working gloss only and is **not** proposed for approval — that
belongs to item 6.1.

**帮助** *(destination title; also the Settings row label and the macOS menu item `Mini Xiangqi 帮助`)*

| # | Group | Proposed Chinese heading | Working gloss | Accepted topic covered |
|---|---|---|---|---|
| 1 | 入门 | **如果你会中国象棋** | If you already play Xiangqi | (re-presentation; no new topic) |
| 2 | 入门 | **棋盘与棋子** | The board and the pieces | the board; the pieces |
| 3 | 入门 | **棋子怎么走** | How the pieces move | their movement |
| 4 | 胜负与和棋 | **将军与将死** | Check and checkmate | check and checkmate |
| 5 | 胜负与和棋 | **困毙** | Stalemate | stalemate |
| 6 | 胜负与和棋 | **重复局面与判和** | Repetition and the claimable draw | repetition and the claimable draw |
| 7 | 胜负与和棋 | **长将** | Perpetual check | perpetual check |
| 8 | 胜负与和棋 | **长捉** | Perpetual chase | perpetual chase |
| 9 | 使用本应用 | **走子、悔棋与认输** | Moving, undo, and resigning | the app's own controls |
| 10 | 使用本应用 | **看懂棋谱** | Reading the move list | the app's own controls |
| 11 | 使用本应用 | **对局、历史与回放** | Games, History, and replay | the app's own controls |

Group headings, proposed: **入门**, **胜负与和棋**, **使用本应用**.

Coverage check against `interaction-design.md:395`: board → 2; pieces and their movement → 2 and 3;
check and checkmate → 4; stalemate → 5; repetition and the claimable draw → 6; perpetual check → 7;
perpetual chase → 8; the app's own controls → 9, 10, 11. Nothing outside the accepted list appears.

Row 3 carries six sub-sections; every other row is a single flat page. Maximum depth is therefore
table of contents → topic → (in row 3 only) an anchored sub-section, which stays inside the two-level
ceiling §2.3 committed to.

### 3.3 Teaching order, and why each ordering decision is what it is

**Groups.** Board before pieces before results before app. A learner cannot be told what checkmate is
before knowing what a general is, and cannot be told what the Undo control does before having anything
to undo.

**Within row 3 — the movement order:**

| Order | Sub-section (proposed Chinese) | Why here |
|---|---|---|
| 1 | **将 / 帅** | The object of the game. Everything else is measured against the general's safety, and the palace introduces the board's one special region |
| 2 | **车** | The simplest movement rule in the game, and the reference the next piece is defined against |
| 3 | **炮** | A **hard dependency**: the accepted rule is literally *"A cannon moves like a chariot when not capturing"* (`xiangqi-rules.md:46`). The cannon cannot be taught before the chariot without restating the chariot's rule |
| 4 | **马** | The only piece whose move is not along a line, and the only one with a blocking rule. Hardest, so it comes after the reader has had three easy wins |
| 5 | **兵 / 卒** | Simple to state, but the piece a standard-Xiangqi player will get wrong, and the piece the first-move surprise in row 2 depends on. Last, so it gets undivided attention |
| 6 | **将帅不能对脸** | The flying-generals rule. Last because it is a rule about a **file being empty between two generals**, so the reader needs to know what can stand on a file first, and because the approved fixture that pins it (`mx-end-003`) uses a cannon (§5.4) |

Alternative considered and rejected: putting 兵 / 卒 second, on the grounds that it is the simplest piece
for an absolute beginner. Rejected because it breaks the 车 → 炮 adjacency the accepted rule text forces,
and because it wastes the last slot — the position a reader remembers best — on the least surprising
piece.

**Within group two — the results order** is exactly the accepted enumeration order at
`interaction-design.md:395`: check and checkmate, stalemate, repetition and the claimable draw, perpetual
check, perpetual chase. That order is also the right teaching order independently: checkmate before its
near-miss (困毙), and plain repetition before its two violations, since both violations are defined as
*"a single behaviour sustained across the three occurrences"* (`xiangqi-rules.md:74`) and the reader must
know what an occurrence is first.

### 3.4 Row 1 — 如果你会中国象棋

The only row whose content is a list of differences. Proposed content, each item traceable:

| Difference | Source |
|---|---|
| 棋盘是 7×7，不是 9×10 | `xiangqi-rules.md:25` |
| 没有河界。棋盘从第一横到第七横是连通的 | `xiangqi-rules.md:26`; `interaction-design.md:123` |
| 没有士（仕），也没有象（相） | `xiangqi-rules.md:27` |
| 每方 12 个子：将 / 帅 1、车 2、马 2、炮 2、兵 / 卒 5 | derived from the frozen FEN `rcnkncr/p1ppp1p/…` (`xiangqi-rules.md:33`) |
| 炮摆在底线，紧挨着车 | derived from the same FEN; in standard Xiangqi cannons start on the third rank. This is the difference that will make the opening feel most alien, and it is currently named nowhere |
| 兵 / 卒 从第一步起就可以左右走，也可以左右吃子。没有过河，也没有升变 | `xiangqi-rules.md:47` |
| 九宫、将帅不能对脸、将军与将死，都和你熟悉的一样 | `xiangqi-rules.md:29`, `:42–43` — **what is unchanged is as valuable as what changed** |
| 没有自然限着（步数）和棋 | `xiangqi-rules.md:58` |
| 三次重复局面可以判和；长将、长捉判负 | `xiangqi-rules.md:61–64` |

The seventh row is a deliberate inclusion. A differences list that only lists differences leaves the
reader unsure which of their existing knowledge still applies; naming the unchanged rules is what makes
the list usable.

**No standard-Xiangqi diagram.** Row 1 is text only. The app's board view cannot render a 9×10 board with
a river, advisors and elephants, so a contrast diagram would be the single bespoke drawn asset in the
whole of Help — see §5.6.

### 3.5 What row 5 (困毙) must say, and to whom

`mx-end-002` pins it: *"Black is not in check and has no legal move: in Mini Xiangqi this is a loss for
the player to move, not a draw."*

This is **not** a difference from standard Xiangqi — 困毙 is a loss there too. It is a difference from
international chess. So it does not belong in row 1, whose audience is Xiangqi players. It belongs in
row 5 as one short sentence for anyone arriving from chess. Reasoned: this is the single rule most likely
to be reported as a bug, because a chess player who is stalemated will see a loss and assume the app is
broken, and because the paired diagrams (§5.4, D14/D15) make the distinction visible in one glance.

### 3.6 Rows 9–11 — the app's own controls

The accepted scope is *"a short explanation of the app's own controls"* — short is part of the contract.
Proposed division:

- **走子、悔棋与认输** — tap and drag both commit through the same boundary (`:222`); tapping an illegal
  point is normal and answers by strengthening the destinations rather than by marking the rejected
  point (`:250`); what Undo removes in each mode (`:327–331`); Redo does not exist (`:332`); resignation
  exists only in human-versus-AI and is confirmed (`product.md:40`). This is also the right home for the
  one marker behaviour that a learner will otherwise misread: **while a checked general is held, its
  check rings hide** (`:249`) — during play the `将军` token carries it, and Help should say so.
- **看懂棋谱** — the board edges and the move list use traditional notation, files are numbered from each
  player's own right, Red writes Chinese numerals and Black Arabic ones (`:163–167`).
- **对局、历史与回放** — one active game at a time, saving before starting another, what History records,
  and that replay is read-only.

**Sequencing.** Rows 9 and 11 describe controls that part 4 (PR #23) names and that PR #23 is **not**
accepted, so they cannot be written yet. Row 10 depends on item 6.5/6.6 — the notation contract leaves
cases open and the oracle table does not exist — so it cannot carry an example move string yet either.
Rows 1–8 depend only on accepted material and can be written now. See §7.

### 3.7 Explicit exclusions

Recording these keeps a later reviewer from re-adding them.

- **No search field.** Eleven rows fit on one screen; a search field would be chrome over nothing.
- **No onboarding flow and no first-launch presentation of Help.** HIG *Onboarding > Best practices*:
  *"If you let people skip the tutorial when they first launch your app or game, don't present it again
  on subsequent launches, but make sure it's easy for people to find if they want to view it later. For
  example, you could make the tutorial available in a help, account, or settings area."* Help **is** that
  later place; making it a launch gate would also collide with `product.md:97`, which excludes structured
  lessons.
- **No TipKit tips or in-context coach marks.** HIG *Onboarding* recommends them, but they are
  contextual, they fire on app state, and the accepted scope says Help is static reference that does not
  analyse the position. This is a real recommendation being declined for a contract reason, and it is
  named here so the decline is visible rather than accidental.
- **No "what's new", no version notes, no feedback link.**
- **No cross-links from a rules topic into the live game.**

---

## 4. Terminology

Help introduces more rules vocabulary than the rest of the app combined, and
`interaction-design.md:459` requires *"Terminology for Xiangqi pieces, rules, results, and controls
[to be] consistent within each supported language."* The table separates what already exists from what
Help would create.

| Concept | Already accepted Chinese | Where | Proposed if absent |
|---|---|---|---|
| check | **将军** | `interaction-design.md:249`, `:271` | — |
| checkmate | **将死** | `:305` (metadata example `红方获胜 · 将死 · 42 步`) | — |
| draw | **和棋** | `:340` | — |
| claimable draw | **可判和** | `:272`, `:352` | — |
| threefold repetition | **局面已三次重复** | `:350` | heading form: **重复局面** |
| stalemate | *(none)* | — | **困毙** |
| perpetual check | *(none)* | — | **长将** |
| perpetual chase | *(none)* | — | **长捉** |
| alternating check and chase | **一将一捉** | `xiangqi-rules.md:74` | — |
| palace | *(none)* | — | **九宫** |
| flying generals | *(none)* | — | **将帅不能对脸**（传统称 **白脸将**） |
| horse block | *(none)* | — | **蹩马腿** |
| cannon screen | *(none)* | — | **炮架** |
| answering a check | *(none)* | — | **应将** |
| river | *(none)* | — | **河界** (used only in row 1) |
| advisor / elephant | *(none)* | — | **士（仕）** / **象（相）** (used only in row 1) |

> **A defect this surfaces, not previously listed as open.** `interaction-design.md:340` says the result
> card's *"second line explains the result reason"*, and `game-data.md:50` fixes nine machine reasons
> (`checkmate`, `stalemate`, `perpetual-check`, `perpetual-chase`, `threefold-repetition`,
> `mutual-perpetual-check`, `mutual-perpetual-chase`, `resignation`, `ended-early`). Accepted Chinese
> exists for exactly one of them — `将死`. So the result card's own copy for stalemate, perpetual check
> and perpetual chase does not exist, and Help would be the first place those words are written down. If
> Help writes them independently, the game screen and Help will say different words for the same
> outcome, which is exactly what `:459` forbids. **The rule vocabulary in this table and the
> result-reason strings are one approval, not two.**

---

## 5. Illustrations

### 5.1 The recommendation, in one sentence

> Every illustration in Help is a **board state rendered by the app's own board view from data** — a FEN,
> optionally a selected piece, optionally a move — using the accepted marker vocabulary. Help ships
> **zero drawn image assets and zero screenshots.**

### 5.2 Executed evidence for it: hand-built diagrams are wrong more often than you would guess

I built minimal teaching positions by hand and then asked the rules engine what was actually legal in
them. Three of my hand-built frames were silently governed by a rule other than the one they meant to
teach — in every case the flying-generals rule, because a minimal diagram tends to leave a file empty
between the two generals.

Executed (`pyffish.legal_moves`, `minixiangqi`):

```
'3k3/7/7/3N3/7/7/3K3 w'   horse on d4, intended: the horse's 8 destinations
  → horse moves: []              (0, not 8)  all legal: ['d1c1','d1d2','d1e1']

'3k3/7/7/2N4/7/7/3K3 w'   horse on c4, intended: the horse's 8 destinations
  → horse moves: ['c4d2','c4d6'] (2, not 8)  all legal: ['c4d2','c4d6','d1c1','d1e1']

'P6/7/3k3/7/7/7/3K3 w'    soldier on a7, intended: the soldier's one sideways move
  → soldier moves: []            (0, not 1)  all legal: ['d1c1','d1e1']
```

In each case the demonstration piece is the only thing between the generals on the d-file, so the
position is one in which Red must address the generals facing, and the piece the diagram exists to show
either cannot move at all or can move only to squares that keep the file blocked. A drawn diagram would
have shipped the wrong dots and nobody would have noticed until a learner counted.

A fourth, subtler instance survives in the diagram set I do recommend: in `2k4/7/7/4R2/7/7/3K3 w` the red
general on d1 cannot play `d1c1`, because the black general stands on c7 and the c-file is empty.

```
'2k4/7/7/4R2/7/7/3K3 w'  → all legal: 12 chariot moves + ['d1d2','d1e1']   (no 'd1c1')
```

That one is harmless — the diagram highlights the chariot, so the general's options are never drawn —
but it is the same trap, and it is why the frame's generals must be checked in every diagram rather than
copied from the last one.

**Conclusion.** A generated diagram cannot disagree with the rules; a drawn one can, and did, three times
out of three attempts. That is the strongest single argument in this report.

### 5.3 The other four arguments, and the honest costs

**Combinatorics.** The user chooses among three piece styles (`传统`, `现代`, `高对比`) and two symbol
sets (`汉字`, `图标`) — `interaction-design.md:78`, `:104` — and each renders differently in light and
dark appearance and again under Increase Contrast. A drawn diagram would need 3 × 2 × 2 = **12 variants**
before Increase Contrast, or 24 with it, and would still be wrong the moment a style's colour values are
fixed (`:102`, still open). Twenty-four diagrams × 12 variants is 288 assets against 24 rows of data.

**The learner sees their own board.** Someone who chose `图标` because they cannot read the characters
must not be shown `汉字` in the place that exists to teach them. A generated diagram follows the user's
Settings for free. HIG *Offering help > Best practices*: *"Use relevant and consistent language and
images in your help content. Always make sure guidance is appropriate for the current context."*

**No new visual vocabulary.** Every marker a diagram needs is already specified with exact geometry:
selection ring, legal-destination dot, capture ring, last-move brackets, check double ring
(`interaction-design.md:244–248`). Help invents nothing.

**Accessibility inheritance.** Increase Contrast promotion, Differentiate Without Color identity, Reduce
Transparency behaviour, and the board's VoiceOver model apply to a generated diagram automatically. A
drawn asset would need its own alt text per diagram per language and would silently ignore all four
settings.

Costs, stated:

- Help becomes a consumer of the rules facade at render time. **Mitigation:** the diagram data carries
  its own expected marker set, and a test asserts that set equals what the facade returns. Help is then
  correct even without a live call, and a rules change that would falsify a diagram fails a test instead
  of shipping.
- It requires one contract edit; see §5.5.
- It cannot draw a standard-Xiangqi board; see §5.6.

### 5.4 The diagram inventory — 24 entries, every marker set executed

**Twelve of the sixteen approved conformance fixtures** supply diagrams here — `mx-move-002` … `-005`,
all three `mx-end-*`, `mx-rep-001`, `mx-chk-001`, and `mx-chs-001` … `-003`. (D01 additionally shows
`mx-move-001`'s position, the frozen start, but with no markers.) Their legality and their game state
have already been reviewed as part of
the rules contract, so recommending them as the teaching diagrams means the teaching material and the
test oracle cannot drift apart. (Entries D21 and D22 each stand for a **pair** of diagrams — the two
halves of one cycle — so the drawn count is 26.)

All "verified markers" columns below are executed output from `pyffish.legal_moves` on the built-in
`minixiangqi` variant. Notation: **dot** = legal empty destination, **ring** = legal capture, **check** =
the double check ring, **brackets** = last-move corner brackets.

| ID | Row | Position | Source | Focus | Verified markers |
|---|---|---|---|---|---|
| D01 | 2 | `rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1` | frozen start FEN | none | none — the board and the 24 pieces alone |
| D02 | 3 · 将/帅 | `2k4/7/7/7/7/4K2/7 w - - 0 1` | **mx-move-005** | e2 | dots d2, e1, e3 — and **not** f2, which leaves the palace |
| D03 | 3 · 车 | `2k4/7/7/4R2/7/7/3K3 w - - 0 1` | new | e4 | 12 dots: a4 b4 c4 d4 f4 g4 e1 e2 e3 e5 e6 e7 |
| D04 | 3 · 炮 | `2k4/7/7/4C2/7/7/3K3 w - - 0 1` | new | e4 | **the identical 12 dots** — same picture, different piece |
| D05 | 3 · 炮 | `2k4/4r2/7/7/7/4C2/3K3 w - - 0 1` | new | e2 | dots a2 b2 c2 d2 f2 g2 e1 e3 e4 e5 — **no ring on e6**: no screen |
| D06 | 3 · 炮 | `2k4/4r2/7/4P2/7/4C2/3K3 w - - 0 1` | new | e2 | dots a2 b2 c2 d2 f2 g2 e1 e3 + **ring on e6**: exactly one screen |
| D07 | 3 · 炮 | `2k4/4r2/4P2/4P2/7/4C2/3K3 w - - 0 1` | new | e2 | dots a2 b2 c2 d2 f2 g2 e1 e3 — **no ring**: two screens |
| D08 | 3 · 炮 | `2k4/3c3/3p3/n2CPCr/7/7/4K2 w - - 0 1` | **mx-move-003** | d4 | dots b4 c4 d1 d2 d3 + ring d6 — the combined case |
| D09 | 3 · 马 | `3k3/7/3P3/3N3/7/7/3K3 w - - 0 1` | **mx-move-002** | d4 | 6 dots b3 b5 c2 e2 f3 f5 — and **not** c6/e6, whose first step d5 is occupied |
| D10 | 3 · 兵/卒 | `3k3/7/3p3/2cP3/7/7/3K3 w - - 0 1` | **mx-move-004** | d4 | dot e4 + rings d5, c4 — and **not** d3 |
| D11 | 3 · 兵/卒 | `P6/7/2k4/7/7/7/3K3 w - - 0 1` | new | a7 | one dot b7 — a soldier on the far rank is neither stuck nor promoted |
| D12 | 3 · 对脸 | `3k3/7/7/3C3/7/7/3K3 w - - 0 1` | **mx-end-003** | d4 | 4 dots d2 d3 d5 d6 — every sideways move is refused |
| D13 | 4 | `3k3/7/3r3/5N1/7/7/3K3 w - - 0 1` | new | — | **check** on d1. 4 legal replies exist |
| D14 | 4 | ↳ after `d1e1` | new | — | brackets d1→e1, no check |
| D15 | 4 | ↳ after `f4d3` | new | — | brackets f4→d3, no check (interposition) |
| D16 | 4 | ↳ after `f4d5` | new | — | brackets f4→d5, no check (capture of the checker) |
| D17 | 4 | `R2k3/1R5/7/7/7/7/2K4 b - - 0 1` | **mx-end-001** | — | **check** on d7; **0 legal moves** |
| D18 | 5 | `3k3/2R1R2/7/7/7/7/2K4 b - - 0 1` | **mx-end-002** | — | **no check**; **0 legal moves** — and still a loss |
| D19 | 6 | `4k2/7/7/7/7/7/2K4 w` + `c1c2 e7e6` | **mx-rep-001** | — | the two positions of the cycle |
| D20 | 6 | ↳ the other half of the cycle | **mx-rep-001** | — | — |
| D21 | 7 | `3k3/7/7/3R3/7/7/4K2 b` cycle | **mx-chk-001** | — | check present at both halves; Black never checks |
| D22 | 8 | `4k2/7/c6/7/1R5/7/2K4 w` cycle | **mx-chs-001** | — | the cannon is attacked at both halves |
| D23 | 8 | `4k2/7/c3r2/7/1R5/7/2K4 w - - 0 1` | **mx-chs-002** | — | **the same shuttle, but the cannon is defended — no violation** |
| D24 | 8 | `4k2/7/p6/7/1R5/7/2K4 w - - 0 1` | **mx-chs-003** | — | **the same shuttle against a soldier — excluded from the chase rule** |

Three of these deserve a note.

**D03/D04 are the same picture.** Executed: a chariot on e4 and a cannon on e4 in the same otherwise-empty
frame have byte-identical legal-move sets, `['e4a4','e4b4','e4c4','e4d4','e4e1','e4e2','e4e3','e4e5','e4e6','e4e7','e4f4','e4g4']`.
Two diagrams, identical markers, one caption: *a cannon that is not capturing moves exactly like a
chariot.* That is the accepted rule (`xiangqi-rules.md:46`) taught by a picture rather than by a sentence,
and it is only available because the diagrams are generated from the same rules the sentence states.

**D05 / D06 / D07 are one family.** Three diagrams differing only in how many pieces stand between the
cannon on e2 and the black chariot on e6: zero, one, two. The capture ring appears in exactly the middle
one. Executed above.

**D13–D16 teach check without ever selecting a general.** The three ways out of check — move, interpose,
capture — cannot be shown as one board state, because they belong to different pieces and the board shows
one selection at a time. Showing them as *results* instead (the position after each escape, with the
last-move brackets) uses only accepted markers, needs no selection, and sidesteps a genuine trap:
`interaction-design.md:249` hides the check rings while a checked general is held, and Help has no turn
status to carry the `将军` token through the gap. A Help diagram that selected the checked general would
therefore show a general in check with no check indication anywhere. Executed: from D13 the legal set is
exactly `['d1c1','d1e1','f4d3','f4d5']`, and all four resulting positions leave Black not in check.

**Fixture debt.** Ten entries use positions that are not yet approved fixtures — D03, D04, D05, D06, D07,
D11, D13, and D13's three follow-ups D14–D16. Those reduce to **seven distinct start positions**, because
D14–D16 are single moves applied to D13's position, which is exactly the shape the fixture schema's
`applied` probe already encodes (`fixtures/rules/README.md`: *"`applied` — … a list of single-move
probes, each with `move`, `result_fen`, and `in_check`"*). Recommendation: those seven become fixtures
(`mx-move-007` …, `mx-end-004`) before Help ships, so that every marker Help draws is a normative
assertion rather than a render-time query. The exact positions and their executed move sets are in the
table above and can be transcribed directly into fixture files.

### 5.5 Diagram scale — a derived band, and the one contract edit this needs

`interaction-design.md:129` currently says: *"A pre-start preview is not interactive and carries no floor,
so it shows no game-state markers and its symbol size is governed by legibility rather than by this
system."* A Help diagram is also non-interactive — but it must show game-state markers, which is exactly
what that sentence rules out for the only non-interactive board the contract currently has. **The
contract needs to distinguish the pre-start preview from a Help diagram; this is a real edit, not a
gap.**

What scale? Not the 44 pt interactive floor, which exists to protect touch targets a diagram does not
have. But the marker vocabulary is defined as fractions of the pitch `p`, so a diagram that shrinks far
enough stops being able to draw its own markers. The accepted metric system names exactly where it
stops being proportional (`interaction-design.md:147`): *"**The grid** is stroked at `0.026 p`, clamped
to between 0.80 and 1.60 points … reaching the ceiling from a pitch of about 62 points upward … The
lower bound binds only if a smaller pitch is ever accepted."*

Computed from that clamp:

- lower clamp: `0.80 / 0.026` = **30.77 pt**
- upper clamp: `1.60 / 0.026` = **61.54 pt**

Below the lower clamp the grid stops thinning while the markers keep thinning, so the check ring
(`0.025 p`) becomes **finer than the grid line** — inverting the relationship `:147` deliberately builds
on (*"the check ring is `0.025 p` against the grid's `0.026 p` — so the two are told apart by shape and
by ink strength rather than by weight"*). Above the upper clamp the grid stops thickening while
everything else grows, so a large diagram and a small one look like different drawing systems.

> **Proposal.** A Help diagram's cell pitch is held inside the accepted metric system's proportional
> band, **31 pt ≤ p ≤ 61 pt** — a board core of **217 pt to 427 pt** square, sized to the width of the
> text column. It shows no file-numeral strips except in row 10 (看懂棋谱), where they are the subject.

Both bounds come from one accepted clamp, not from taste. Computed geometry at the two bounds and at the
interactive floor for comparison:

| Quantity | p = 31 | p = 44 (interactive floor) | p = 61 |
|---|---|---|---|
| board core `7p` | 217.00 | 308.00 | 427.00 |
| piece disc `0.80p` | 24.80 | 35.20 | 48.80 |
| symbol `0.50p` | 15.50 | 22.00 | 30.50 |
| destination dot `0.22p` | 6.82 | 9.68 | 13.42 |
| capture-ring stroke `0.055p` | 1.71 | 2.42 | 3.35 |
| selection-ring stroke `0.030p` | 0.93 | 1.32 | 1.83 |
| check-ring stroke `0.025p` | 0.78 | 1.10 | 1.53 |
| gap between the two check rings `0.030p` | 0.93 | 1.32 | 1.83 |
| last-move bracket arm `0.13p` | 4.03 | 5.72 | 7.93 |
| grid `0.026p` | 0.81 | 1.14 | 1.59 |

At the floor the symbol is 15.5 pt, comfortably above the minimum text sizes HIG *Designing for games >
Look stunning on every display* tabulates (iOS/iPadOS 11 pt, macOS 10 pt).

Where the floor actually binds: at the narrowest supported iPhone width of **375 pt**
(`layout-budget.md:147`, measured) a text column of roughly 335 pt gives p ≈ 47, above the interactive
floor already. The 31 pt floor binds only in a **narrow iPad window** — at a 320 pt scene width the
column is about 280 pt and p lands at 40. So the band is not a compromise on iPhone; it is insurance for
iPad multitasking, whose minimum window size is itself still open (`interaction-design.md:514`).

One risk worth naming: at p = 31 the check-ring stroke is 0.78 pt, which on a **1× display** (an old
external monitor on a Mac) is sub-pixel and will alias. It is thin at the interactive floor too
(1.10 pt), so this is not new, but a diagram makes it more visible than play does.

### 5.6 The two things a generated diagram cannot do, and what to do instead

**A standard-Xiangqi contrast board.** The board view renders 7×7 Mini Xiangqi and nothing else. Row 1 is
therefore text only. Reasoned: the alternative — one drawn 9×10 board — would be the sole image asset in
Help, would need its own style variants and its own alt text, and would teach a board this app never
plays. Not worth it. Readers of row 1 already know what a standard board looks like; that is what makes
them readers of row 1.

**Pictures of the app's own controls.** Screenshots would need re-capture per platform, per layout, per
piece style, per appearance and per language, and would be stale the day the first control moves.
Recommendation: rows 9–11 reference controls by their **own localized label plus their inline symbol**,
rendered live in the text, so a control's picture in Help is always the control that is actually in the
app. HIG *Offering help > Best practices*: *"Avoid bloating your help content by explaining how standard
components or patterns work. Instead, describe the specific action or task that a standard element
performs in your app or game."*

### 5.7 Motion in diagrams

Rows 6, 7 and 8 each teach a **cycle**, which is a sequence rather than a position. Three ways to show it:

| Option | Cost |
|---|---|
| **(a) Two static diagrams side by side (or stacked on iPhone) plus a numbered occurrence line.** *Recommended.* | Nothing animates, so Reduce Motion is a non-question and the Accessibility *Animated Images* setting (which asks apps to *"Pause animations in animated images … when people turn off the Animated Images setting"*) does not apply. Costs the reader one inference: that the cycle repeats |
| (b) An auto-looping animation of the cycle | A repeating attention-grabbing animation is precisely what `interaction-design.md:428` removes under Reduce Motion, and there would be nothing left after removing it. Rejected |
| (c) The read-only replay transport applied to a canned position | Genuinely the best teaching device, and the app already owns it. But it makes Help interactive, which brushes against *"does not … offer interactive lessons or drills."* Owner question — §9 |

Under (a), rows 6–8 also carry the exact occurrence arithmetic, which is executed and worth stating
plainly because it is the one thing about repetition that people get wrong:

```
mx-rep-001, bare generals shuttling:
  ply 0  4k2/7/7/7/7/7/2K4 w   1st occurrence   no claim
  ply 4  4k2/7/7/7/7/7/2K4 w   2nd occurrence   no claim
  ply 8  4k2/7/7/7/7/7/2K4 w   3rd occurrence   claim available
```

Executed: the claim appears at ply 8 and at no earlier ply, matching the fixture's own boundary
assertion.

---

## 6. Accessibility

Item 8.1 (the board's VoiceOver interaction model) is open and belongs to another researcher. This
section states only what Help *needs* from it and what is Help-specific, and deliberately does not
pre-empt it.

**Help-specific and decidable here:**

- **A Help diagram is one accessibility element, not 49.** There is nothing to navigate — the diagram is
  a statement, not a position under play. HIG *VoiceOver > Descriptions*: *"Make charts and other
  infographics fully accessible. Provide a concise description of each infographic that explains what it
  conveys."* The description is generated from the diagram's own data (the position and the marker set),
  not hand-written per diagram per language, which is the same reason §5 gives for generating the
  picture.
- **Headings are real headings.** HIG *VoiceOver > Navigation*: *"Use titles and headings to help people
  navigate your information hierarchy … use accurate section headings that help people build a mental
  model of each page's information hierarchy."* With eleven rows and six sub-sections in row 3, the rotor
  is how a VoiceOver user reaches row 3's 马 section without swiping past five pieces.
- **Full Dynamic Type**, including accessibility sizes, throughout. Help is a text document; there is no
  argument for capping it. The diagram is content and keeps its own scale rather than growing with the
  text — but its **caption** grows, so caption and diagram must stack rather than sit side by side at
  accessibility sizes.
- **The diagram never becomes the only carrier of a rule.** Every diagram has a caption that states the
  rule in words. This follows the app's own standing rule that information is never conveyed by one
  channel alone (`interaction-design.md:277`, `:436`).

**What Help needs from 8.1, and must not answer on its own:**

- **Which coordinate is spoken.** The user-visible notation is traditional and per-side, the canonical one
  is `a1`–`g7`, and the numeral strips hide at accessibility text sizes. Whatever 8.1 decides for the
  playing board governs Help diagrams identically — a learner must not hear one coordinate system in Help
  and another in the game.
- **How the marker vocabulary is spoken** — "legal destination", "capture", "check", "last move".

---

## 7. Dependencies and sequencing

| Help content | Blocked on | Can be written now? |
|---|---|---|
| Rows 1–8 (all rules content) | nothing — every rule is accepted in `xiangqi-rules.md` and pinned by approved fixtures | **Yes** |
| The rule vocabulary (§4) | must be approved **jointly** with the result-card reason strings, which do not exist | Draft now, approve together |
| Row 9 (走子、悔棋与认输) | **part 4 / PR #23** names the play controls; PR #23 is not accepted | No |
| Row 10 (看懂棋谱) | **items 6.5 and 6.6** — notation leaves cases open and the oracle table does not exist | No; no example move string may be written yet |
| Row 11 (对局、历史与回放) | part 4 for the play-screen controls; **item 7.1** for what a History row shows | Partly |
| Entry point, stacked layout | **part 4** — the play control cluster's contents | No |
| Entry point, side-by-side | **item 4** at `interaction-design.md:516` — what the panel contains | Partly |
| Diagram scale | needs the `:129` edit in §5.5 | Yes, as a proposed edit |
| Eight new fixtures (§5.4) | nothing | **Yes** |
| Diagram VoiceOver descriptions | **item 8.1** | No |
| English Help text | **items 6.1, 6.3** | No |

The useful consequence: **rows 1–8, the eight new fixtures, the diagram inventory and the diagram scale
are all unblocked today and constitute the great majority of Help.** Only the three app-controls rows and
the entry-point affordance wait on part 4.

---

## 8. Copy proposed for approval

Consolidated, so an approver sees one list. All Simplified Chinese, all **new**, none accepted.

**Destination and entry**

| String | Use |
|---|---|
| **帮助** | Help destination title; Settings row label; accessibility label of the game-screen control |
| **Mini Xiangqi 帮助** | macOS Help-menu item |

**Group headings**

**入门** · **胜负与和棋** · **使用本应用**

**Topic headings** — the eleven in §3.2:
**如果你会中国象棋** · **棋盘与棋子** · **棋子怎么走** · **将军与将死** · **困毙** ·
**重复局面与判和** · **长将** · **长捉** · **走子、悔棋与认输** · **看懂棋谱** · **对局、历史与回放**

**Row 3 sub-headings**
**将 / 帅** · **车** · **炮** · **马** · **兵 / 卒** · **将帅不能对脸**

**Rules vocabulary** — the "Proposed if absent" column of §4:
**困毙** · **长将** · **长捉** · **九宫** · **将帅不能对脸**（**白脸将**）· **蹩马腿** · **炮架** ·
**应将** · **重复局面** · **河界** · **士（仕）** · **象（相）**

Body copy is deliberately not drafted here. It is a separate pass, it is long, and it should be written
against approved headings and an approved vocabulary rather than in parallel with them. What §3.4 and
§3.5 give is the *content requirement* for the two rows whose content is not simply a restatement of an
accepted rule.

---

## 9. Open for the owner

Only choices that genuinely need the product owner. Everything else above is a designer's call and is
recommended rather than asked.

### 9.1 Does Help admit the app's own rules interpretations?

`xiangqi-rules.md:74–76` records three interpretations the normative source does not settle. Two of them
are visible to a player:

- **一将一捉** — a side that alternates checking and chasing commits **neither** violation here, so the
  position resolves as a claimable draw. The contract itself says this is *"the interpretation most
  likely to be wrong"* and that *"competition practice is commonly summarised as forbidding the
  alternation."*
- **A chased piece whose only defender is a general** is treated as defended, so the sequence degrades to
  a claimable draw rather than a loss. The contract calls this *"under-detect[ion]."*

| Option | Cost |
|---|---|
| **(a) Help says both, in a short closing note in 长捉 (proposed heading: 本应用的判定).** *My recommendation.* | Admits in the teaching material that the app takes a position on a disputed rule. Costs a paragraph and some humility; buys that a competition-trained tester reads it as a decision rather than as a bug |
| (b) Help says 一将一捉 only | The commoner case, and the one a player can actually reach on purpose. Leaves the defender case to be discovered |
| (c) Help says neither | Help stays shorter and simpler. A user who expects a win by 长捉 and gets a claimable draw has nowhere in the app to find out why, and will file it as a rules bug |

This is the owner's because it is a question about what the product is willing to say about itself, not
about how to say it.

### 9.2 Does Help name its rules source?

The rules come from a specific public source (`xiangqi-rules.md:11`, PyChess Mini Xiangqi), and the app is
GPLv3 (`product.md:13`).

| Option | Cost |
|---|---|
| (a) A one-line 规则依据 note at the end of Help | Costs one line. Tells a learner where to read more, which suits a product whose stated purpose is education |
| (b) Nothing | Nothing to maintain. A learner who wants to go further has no next step, in a product that exists to teach |

Related but out of part 7's scope, and flagged only so it is not lost: **no accepted contract says where
the GPLv3 licence text and third-party attributions are shown.** Settings and Help are where such things
normally live, so whoever decides Help's Settings section should decide it in the same breath, or an
issue should be opened.

### 9.3 May a Help diagram be stepped through?

§5.7 option (c). The three repetition topics teach cycles, and the app already owns a read-only replay
transport that would show them perfectly.

| Option | Cost |
|---|---|
| **(a) Static diagram pairs only.** *My recommendation, and the default if this is not decided.* | Help stays unambiguously static. The reader infers that the cycle repeats from a caption rather than seeing it |
| (b) Help diagrams for rows 6–8 carry the replay transport (step forward, step back; no autoplay) | The best teaching device available, and it costs no new component. But Help becomes interactive, which sits directly beside the accepted *"does not … offer interactive lessons or drills"*, and a reviewer could reasonably read it as a scope breach |

Owner's because it is scope, not craft — exactly the shape of the hover-preview question at
`interaction-design.md:522`.

### 9.4 Does Help open at a topic chosen from the current position?

§2.4. My recommendation is no, always the table of contents.

| Option | Cost |
|---|---|
| **(a) Always the table of contents.** *Recommended.* | One extra tap for a repeat reader. Help never appears to comment on the game |
| (b) The game screen opens Help at the topic matching the current state | HIG *Offering help* explicitly recommends contextual help. But choosing the topic requires reading the position, and a player who sees Help open itself at 长捉 will conclude the app just judged their move — which the accepted scope says it does not do |

### 9.5 How large may Help's rules content grow?

The accepted word is *"deliberately small"* and *"a **short** explanation of the app's own controls."*
Neither is a number, and Help is the one surface with no natural size limit.

| Option | Cost |
|---|---|
| (a) A stated ceiling — e.g. no topic longer than one scroll at default text size on the narrowest supported iPhone | Gives reviewers something to enforce. Some rules (长捉, with its exceptions for defended pieces and for soldiers) genuinely need more than one screen and would have to be split |
| (b) No ceiling; "deliberately small" governs by judgement | Nothing to argue about now. The eleven rows drift toward a manual over successive passes, which is how every help section in history has grown |

I have no recommendation here. It is a question about how much of the product's effort belongs in Help
versus in the board itself, and that is the owner's to weigh.

---

## Appendix A — reproducing the executed checks

```zsh
PYTHONPATH=/Users/tianren/coding/minixiangqi/fs-chase python3 - <<'PY'
import pyffish as sf
V = 'minixiangqi'
for tag, fen, focus in [
    ('D03 chariot',        '2k4/7/7/4R2/7/7/3K3 w - - 0 1', 'e4'),
    ('D04 cannon',         '2k4/7/7/4C2/7/7/3K3 w - - 0 1', 'e4'),
    ('D05 no screen',      '2k4/4r2/7/7/7/4C2/3K3 w - - 0 1', 'e2'),
    ('D06 one screen',     '2k4/4r2/7/4P2/7/4C2/3K3 w - - 0 1', 'e2'),
    ('D07 two screens',    '2k4/4r2/4P2/4P2/7/4C2/3K3 w - - 0 1', 'e2'),
    ('D11 far-rank sold.', 'P6/7/2k4/7/7/7/3K3 w - - 0 1', 'a7'),
    ('D13 check',          '3k3/7/3r3/5N1/7/7/3K3 w - - 0 1', None),
    ('trap: N on d4',      '3k3/7/7/3N3/7/7/3K3 w - - 0 1', 'd4'),
    ('trap: N on c4',      '3k3/7/7/2N4/7/7/3K3 w - - 0 1', 'c4'),
    ('trap: P on a7',      'P6/7/3k3/7/7/7/3K3 w - - 0 1', 'a7'),
]:
    lm = sorted(sf.legal_moves(V, fen, []))
    sel = [m for m in lm if m.startswith(focus)] if focus else lm
    print('%-20s focus=%-2s %s' % (tag, focus or '-', sel))
PY
```

`fs-chase` is a workspace worktree of the `ppppvz` Fairy-Stockfish fork with the extension already built
per the recorded build recipe. Nothing in this report was written to that worktree or to `MiniXiangqi/`.

## Appendix B — Apple documentation consulted, and what it does not say

Cited above:

- HIG **Offering help > Best practices** — let tasks inform the help; consistent language and images;
  do not explain standard components.
- HIG **Offering help > macOS, visionOS** — tooltips, scoped to describing a single control.
- HIG **Offering help > Platform considerations** — verbatim: *"No additional considerations for iOS,
  iPadOS, tvOS, or watchOS."*
- HIG **The menu bar > Help menu** — the Help menu's position and contents; keep the item count small.
- HIG **Modality > Best practices** — modal hierarchies; full-screen modal for in-depth content.
- HIG **Sheets > Best practices**, **> iOS, iPadOS**, **> macOS** — alternatives to sheets; page/form
  sheet preference on iPad; the dimmed parent window on macOS.
- HIG **Onboarding > Best practices** — an optional tutorial belongs in a help or settings area.
- HIG **VoiceOver > Descriptions** and **> Navigation** — describing infographics; headings and the rotor.
- HIG **Designing for games > Look stunning on every display** — minimum text sizes per platform.
- AppKit **`NSButton.BezelStyle.helpButton`** — at most one help button per window.
- SwiftUI **`HelpLink`** — the standard macOS help-button appearance and its Help Book anchor.
- Accessibility **Animated images** — pause animations when the Animated Images setting is off.

**Where Apple publishes nothing, said plainly.** There is no Apple guidance on how a board game should
present a rules reference, none on structuring in-app rules documentation, and none on rendering
teaching diagrams from live game state. HIG *Offering help* is about tooltips, the Help menu and the Help
Book; its iOS section is one sentence saying there is nothing further. Every structural recommendation in
§3 and §5 is therefore ours, argued from the accepted contracts and from executed evidence, with no
external authority to defer to. Saying so is more useful than manufacturing a citation.

---

# Independent review

Adversarial pass by a second agent. I re-read every accepted contract the report cites, re-ran every
engine claim against the same extension the report used
(`/Users/tianren/coding/minixiangqi/fs-chase`, `pyffish.version() = (0, 0, 89)`, `minixiangqi`,
read-only), and looked up every Apple citation in Apple's own documentation. Nothing under
`MiniXiangqi/` or any worktree was touched; no git or GitHub writes.

**What holds.** All ten `legal_moves` probes in Appendix A reproduce byte for byte, including the
three flying-generals traps, D03/D04's identical twelve-destination sets, the D05/D06/D07 screen
family, D11's single `a7b7`, and D13's `['d1c1','d1e1','f4d3','f4d5']` with all four results
check-free. The 19-move start position, the `mx-rep-001` claim appearing at ply 8 and no earlier, and
every fixture-derived diagram's marker set (D02, D08, D09, D10, D12, D17, D18) also reproduce. The
line references into `interaction-design.md`, `xiangqi-rules.md`, `product.md`, `game-data.md` and
`layout-budget.md` are accurate; I found no fabricated citation. The organizing principle in §3.1, the
teaching order in §3.3, and the case for generated rather than drawn illustrations survive the review.

**What does not.** Twelve findings below. The most serious cluster is §5.5, where the one number the
report calls "derived not chosen" rests on a claim that is false, is bounded above by a condition the
accepted contract deliberately creates, and by the report's own two worked examples never binds
anywhere.

---

## R1 — §5.5: the lower bound's derivation is false. Severity: high

**Report:** "Below the lower clamp the grid stops thinning while the markers keep thinning, so the
check ring (`0.025 p`) becomes **finer than the grid line** — inverting the relationship `:147`
deliberately builds on."

**Contract, `interaction-design.md:147`:** "The grid is very close in weight to the finest game-state
marker — the check ring is `0.025 p` against the grid's `0.026 p` — **so the two are told apart by
shape and by ink strength rather than by weight**".

**What is wrong.** Two things, and either alone kills the derivation.

1. `0.025 p < 0.026 p` at *every* pitch. The check ring is finer than the grid at p = 100, at p = 61,
   at p = 44 (1.10 against 1.144) and at p = 31 (0.775 against 0.806). It does not "become" finer below
   the clamp and nothing "inverts" — the ordering is constant and the clamp cannot change it.
2. The relationship `:147` builds on is explicitly *not* a weight relationship. The contract's own
   sentence says the two are told apart "rather than by weight". A bound justified by protecting a
   weight relationship the contract disclaims in the same sentence does not survive its own paragraph.

**Correction.** There is a real effect at the clamp, and it is the opposite direction from the one
stated: below `0.80 / 0.026 = 30.77` the grid is pinned at 0.80 pt while every marker keeps shrinking,
so the grid becomes progressively **heavier** than the finest marker — 0.80 against 0.625 at p = 25, a
ratio of 1.28, against 1.04 at p = 44. That breaks `:147`'s "very close in weight", which is a real
accepted property. Either restate the bound on that basis, or drop the lower bound and say the floor
is a legibility judgement rather than a derivation.

## R2 — §5.5: the upper bound argues from a condition the contract creates on purpose, and that the shipping board is already in. Severity: high

**Report:** "Above the upper clamp the grid stops thickening while everything else grows, so a large
diagram and a small one look like different drawing systems." Proposal: "**31 pt ≤ p ≤ 61 pt**".

**Contract, `:147`:** "clamped to between 0.80 and 1.60 points — 1.14 points at the floor, **reaching
the ceiling from a pitch of about 62 points upward, so the lines never coarsen as the board grows.**"

**What is wrong.** The ceiling is a stated feature with a stated purpose, not a degradation. And the
accepted layout rules put the *playing* board above it routinely: `:480` sizes the board to "the
largest square fitting both the available width and the height left after the surrounding chrome", and
`:482` treats 308 pt (p = 44) as the constrained case, not the typical one. An iPad or a wide Mac
window gives a board core several hundred points larger, i.e. p well above 62. So the accepted app
ships boards outside the report's "proportional band" most of the time, with contract approval. A cap
at 61 pt for Help diagrams cannot be derived from a clamp the accepted board crosses as a matter of
course.

**Correction.** Drop the upper bound, or re-argue it as "a Help diagram should not be larger than the
text column it annotates", which is a real constraint and does not need `:147`.

## R3 — §5.5: internal contradiction — the proposed floor binds nowhere, by the report's own numbers. Severity: high

**Report:** "The floor does not bind on iPhone (375 pt narrowest measured width gives p ≈ 47) … The
31 pt floor binds only in a **narrow iPad window** — at a 320 pt scene width the column is about 280 pt
and **p lands at 40**."

**What is wrong.** 40 > 31. The floor does not bind in the narrow iPad window either. Both worked
examples clear the proposed floor with room to spare, so the report's own evidence shows the lower
bound is inert in every configuration it examined, immediately after presenting it as "insurance for
iPad multitasking".

**Correction.** Either produce a configuration where p actually falls below 31, or state plainly that
the floor is precautionary and currently binds nowhere.

## R4 — §5.4: "every marker set executed" is not true of D17–D24, and the engine used cannot verify the chase family at all. Severity: high

**Report:** "All 'verified markers' columns below are executed output from `pyffish.legal_moves` on
the built-in `minixiangqi` variant." And in the summary: "A 24-entry diagram inventory with every
marker set executed."

**What is wrong.** D17, D18, D21, D22, D23 and D24 assert check state, mate-versus-stalemate, and
perpetual-chase adjudication. None of those is a `legal_moves` output. Worse, the chase family cannot
be verified with this tool at all. Executed here:

```
mx-chs-001  is_optional_game_end=(True, 0)   is_immediate_game_end=(False, 0)
mx-chs-002  is_optional_game_end=(True, 0)   is_immediate_game_end=(False, 0)
mx-chs-003  is_optional_game_end=(True, 0)   is_immediate_game_end=(False, 0)
```

The built-in variant returns a claimable draw for all three. It does not reproduce `mx-chs-001`'s
`black-wins / perpetual-chase`, and therefore **cannot distinguish D22 from D23 or D24** — which is
precisely the contrast those three diagrams exist to teach. The report's own opening says as much
("the built-in variant is known not to satisfy every approved fixture … and `mx-chs-003`'s own
rationale"), so the blanket sentence in §5.4 contradicts the report's own method note eight sections
earlier.

**Correction.** Split the column honestly: "executed" for the diagrams whose markers are `legal_moves`
output (D02–D12, D13–D16), "asserted by fixture" for D17, D18, D21–D24, and add a line saying the
chase diagrams' teaching content is pinned by the fixtures and is **not** reproducible on the current
engine until the fork correction lands.

## R5 — §2.2 vs §2.3: the sheet argument and the iPhone affordance do not meet. Severity: medium

**Report, §2.3:** "The pre-start state lives on the board page (`:183`), and a learner sitting in
pre-start … is precisely the person most likely to open Help." That is the whole case for the sheet.

**Report, §2.2:** the only stacked-layout game-screen affordance is "A low-emphasis item at the
trailing end of the **play control cluster**".

**Contract:** `:188` "The human-versus-AI pre-start state **is not an active game**"; `:200` the same
for Free Play; `:38` scopes the play control cluster to "**ordinary play** meaning **an active game**
on the play screen"; `:190`–`:204` enumerate what pre-start shows — a noninteractive preview,
**本局设置**, **开始对局** — and do not include the play control cluster.

**What is wrong.** On iPhone the proposal may leave Help with no entry point at all in exactly the
state whose existence justifies the sheet. Meanwhile `:396` requires Help to be reachable "from the
game screen", and `:183` puts pre-start on the board page, so pre-start is a game-screen state where
reachability is already accepted.

**Correction.** Either name a pre-start affordance explicitly (and note it is a second dependency on
part 4), or drop the pre-start argument and rest the sheet on a reason that survives without it.

## R6 — §2.2: MISATTRIBUTED citation, and the same Apple page contradicts two of the report's own proposals. Severity: medium

**Report:** "AppKit's `NSButton.BezelStyle.helpButton` documentation states: *'Include no more than
one help button per window. Multiple help buttons in the same context make it hard for people to
predict the result of clicking one.'*"

**Verified.** The sentence is verbatim correct, but it is **HIG › Buttons › Help buttons**
(`/design/Human-Interface-Guidelines/buttons#Help-buttons`), not AppKit symbol documentation. Marked
**MISATTRIBUTED**, not fabricated.

**And the same section says two things the report does not report:**

- *"**Use a help button within a view, not in the window frame.** For example, avoid placing a help
  button in a toolbar or status bar."* — against §2.2's "on macOS the **toolbar**/panel item".
- *"**When possible, open the help topic that's related to the current context.** … If no specific help
  topic applies directly to the current context, open the top level of your app's help documentation
  when people choose a help button."* — a second, more direct Apple recommendation for exactly the
  contextual entry the report rejects in §2.4 and frames in §9.4 as resting only on the softer
  "Offering help › Best practices". Quoting one line of a page and omitting the two that cut against
  you is the pattern this review exists to catch.

**Correction.** Fix the attribution; move the macOS in-window affordance out of the toolbar; and add
the Help-buttons contextual guidance to §9.4's option (b) so the owner sees the strength of the case
they are being asked to decline.

## R7 — §2.3: the sheet's dismissal control contradicts the HIG page cited beside it and re-uses an accepted string. Severity: medium

**Report:** "**Sheet** over the play screen, containing its own navigation stack, **dismissed by
`完成`**."

**HIG › Sheets › Best practices** (the page the report cites two paragraphs later): *"**Provide an
alternative to the Done button.** If you provide a Done button, always pair it with a Cancel button …
Relying solely on the Done button implies that completing the task is the only way to exit the sheet,
which can feel restrictive or misleading."* **HIG › Sheets › Anatomy** scopes the two: Cancel/Close
"dismisses a sheet without saving any changes"; Done "dismisses a sheet **after completing a task or
explicitly saving changes**". A read-only rules reference has no task to complete and nothing to save.

**Second problem.** `完成` is already accepted with a different meaning: `:344` "**完成**, which returns
to the Play start state" on the recorded-result card, and `:44` lists it among the three tinted moments
"with a single obvious next action". Using it as the Help sheet's dismissal makes one accepted string
mean two things, against `:459` ("Terminology … must be consistent within each supported language").

**Correction.** Use a close/cancel-role dismissal with its own string, and say so in §8's copy list.

## R8 — §3.5: wrong diagram IDs. Severity: medium

**Report:** "because the paired diagrams (§5.4, **D14/D15**) make the distinction visible in one
glance."

**What is wrong.** D14 and D15 are two of D13's check escapes (after `d1e1` and after `f4d3`). The
checkmate-versus-stalemate pair is **D17** (`mx-end-001`) and **D18** (`mx-end-002`), as §5.4 and the
report's own summary both say.

**Correction.** D17/D18.

## R9 — §7: seven fixtures or eight. Severity: medium

**Report, §5.4:** "Those reduce to **seven distinct start positions** … Recommendation: **those seven**
become fixtures."
**Report, §7:** table row "**Eight new fixtures** (§5.4)", and prose "rows 1–8, the **eight** new
fixtures".

**What is wrong.** Seven is right: D03, D04, D05, D06, D07, D11, D13. D14–D16 are single-move `applied`
probes on D13, as §5.4 itself argues. §7 says eight twice.

## R10 — §2.1 and §5.5: the narrowest supported iPhone is presented as settled and is an open item. Severity: medium

**Report:** "the narrowest supported iPhone is **375 × 667** (SE 2nd/3rd gen)"; "at the narrowest
supported iPhone width of **375 pt** (`layout-budget.md:147`, measured)"; and the conclusion that a
navigation bar on the board page "**may not be an option at all on iPhone**".

**Contract, `:514`:** "Fix the minimum window size for macOS and for iPadOS windowing … **and name the
narrowest supported iPhone the stacked layout is verified against.**" That is in **Need to discuss** —
non-normative, authorising nothing.

**What is right.** The three numbers reproduce in the draft: `layout-budget.md:147` gives 375 pt,
`:169` gives the 54 pt inline navigation bar, `:661` gives the 17.5 pt shortfall. `layout-budget.md`
is a workspace draft, not a contract.

**Correction.** Keep the measurement, weaken the conclusion: the navigation-bar option is ruled out
*conditional on* the SE remaining in the supported set, which `:514` has not yet decided.

## R11 — §5.5: the contract edit is understated by one clause. Severity: medium

**Report:** "**The contract needs to distinguish the pre-start preview from a Help diagram; this is a
real edit, not a gap.**" — naming only `:129`.

**What is missing.** `:480` is the binding sentence: "Within that, a point of the grid is **never
smaller than 44 points on every platform**." Its single accepted exception is `:486`: "One exception:
a **pre-start board** is a noninteractive preview with no touch targets, so it carries no size floor …
The floor exists to protect interaction, and a preview has none to protect." The rationale supports the
report, but the exception is granted to exactly one named thing. A Help diagram at p = 31 requires
`:480`/`:486` to be amended as well.

## R12 — §3.2, §3.4, §8: the proposed Chinese piece headings contradict the accepted piece-character table three different ways. Severity: medium

**Contract, `:61`–`:67`** — the accepted table is **Red then Black**:

| Piece | Red | Black |
|---|---|---|
| General | 帅 | 将 |
| Chariot | 俥 | 车 |
| Horse | 傌 | 马 |
| Cannon | 炮 | 砲 |
| Soldier | 兵 | 卒 |

**Report, row 3 sub-headings:** "**将 / 帅** · **车** · **炮** · **马** · **兵 / 卒** · 将帅不能对脸".

**What is wrong.** Three conventions in one list of five pieces:

- **将 / 帅** — both forms, but **Black then Red**, reversed from the accepted table.
- **兵 / 卒** — both forms, **Red then Black**, matching.
- **车**, **马**, **炮** — one form each, and the sides do not agree: 车 and 马 are the **Black** forms,
  炮 is the **Red** form. A learner who chose Red will see 俥 and 傌 on their own discs and 车 and 马 in
  the section that teaches them.

`:71` makes these characters accepted game content, and `:459` requires terminology to be consistent
within a language. §3.4's proposed line "每方 12 个子：将 / 帅 1、车 2、马 2、炮 2、兵 / 卒 5" and §8's
consolidated list repeat it.

**Correction.** One convention, following the accepted table: **帅 / 将 · 俥 / 车 · 傌 / 马 · 炮 / 砲 ·
兵 / 卒**. (The flying-generals heading 将帅不能对脸 is idiomatic as a compound and can stay, but say so
rather than leave it looking like a fourth convention.)

---

## Lower-severity findings

**R13 — §5.2: "three of three" homogenises two different failures.** Executed: in
`3k3/7/7/2N4/7/7/3K3 w` and `P6/7/3k3/7/7/7/3K3 w` the kings already face on an empty d-file. Asking
the engine for **Black's** moves in the same frames returns `['d7c7','d7e7']` and `['d5c5','d5e5']` —
only moves that break the facing. So no legal Black move could have produced either position: both are
**unreachable**, not merely mis-taught. Only the horse-on-d4 frame is a legal, reachable position that
silently teaches the wrong thing. This *strengthens* the argument for generation — a generator would
refuse an unreachable frame — but "the horse has 2 destinations instead of 8" is a marker claim about a
position that cannot occur, which is a different and weaker point than the d4 case. Say which is which.

**R14 — §5.4 D21: "check present at both halves" is neither executed nor unambiguous.** Executed over
`mx-chk-001`'s cycle: Black is in check at plies 0, 2, 4, 6, 8 and **nobody** is in check at plies 1,
3, 5, 7 — which is what `mx-chk-002`'s own rationale says ("phased so the repeated position has the
checking side (Red) to move and **no one momentarily in check**"). The claim is true only under the
reading that the "two halves" are the two Black-to-move positions two plies apart. State which two
positions the pair draws; the natural before-and-after pair one ply apart makes the caption false.

**R15 — §5.4/§5.3: inconsistent diagram bookkeeping.** D19 and D20 are two entries for the two
positions of one cycle, while D21 and D22 are one entry each "stand[ing] for a **pair**" — and D19's
own cell already reads "the two positions of the cycle", after which D20 reads "the other half".
Separately, §5.3 computes "Twenty-four diagrams × 12 variants is 288 assets" against §5.4's own drawn
count of **26**, and against its own "12 variants before Increase Contrast, **or 24 with it**". Neither
error changes the conclusion; both are the kind of arithmetic a reviewer will check.

**R16 — §2.2: ⌘? verified, but under-cited and slightly off-target.** HIG › Keyboards › Standard
keyboard shortcuts does assign it — *"Question mark (?) | Command-Question mark | **Open the app's Help
menu**"*, and the same page notes *"the keyboard shortcut for Help is Command-Question mark, not
Shift-Command-Slash."* The documented action is opening the Help **menu**, not invoking the app's Help
item; since the report rejects the Help Book (so macOS installs no search field there), binding it to
the item is defensible, but say so. Also, §2.2's table says the macOS menu item is "**Required by** HIG
*The menu bar > Help menu*". That page describes the Help menu and its conventional items; it does not
state a requirement. Soften to "conventional per".

**R17 — §5.4: `mx-move-006` is passed over in silence.** It is an approved fixture titled "In check:
the legal set is exactly the evasions" (`7/3k3/3r3/R6/7/7/3K3 w`, legal `['a4d4','d1c1','d1e1']`),
directly on row 4's topic. D13 is a better teaching frame — verified: it adds the capture escape
`f4d5`, which `mx-move-006` lacks — but the report's central claim for fixture-sourced diagrams is
that "the teaching material and the test oracle cannot drift apart", and it then adds fixture debt on
the one row where an approved fixture already exists, without mentioning it. One sentence fixes this.

**R18 — §2.4 vs §0: one proposed row breaks a clause §0 lists as accepted and not reopened.** §0
records `:396` — "opening it never modifies the active game; **returning restores the exact prior
context**" — as accepted. §2.4 then proposes that the AI "may complete and commit while Help is
covering the board", so on return the position and the side to move have both changed. The report marks
the row a proposal but never names the conflict with the sentence it quoted. Either argue explicitly
that "context" means the UI context rather than the game state, or move the row into §9 as a sixth
owner question. As written it reads as a deduction against an accepted clause.

**R19 — §2.4/§9.4: an accepted line the report never cites cuts the other way.** `:179`, in the list of
what the board and game interaction design must cover: "**Help that explains both game concepts and
interface behavior in context.**" That is accepted text, it is about Help, and it uses the word the
report's recommendation refuses ("Help never appears to comment on the game"). It is probably
reconcilable — "in context" may mean "reachable without leaving the game" rather than "opened at a
topic chosen from the position" — but a proposal this strong has to address `:179` rather than omit it,
especially given the HIG Help-buttons line in R6 pointing the same way.

---

## Citation verification summary

| Cited | Verdict |
|---|---|
| HIG *Offering help › Best practices* — "directly relate the help you provide…", "Use relevant and consistent language and images…", "Avoid bloating your help content…" | **VERIFIED** verbatim |
| HIG *Offering help › macOS, visionOS* — tooltip "briefly describes how to use a component" | **VERIFIED** verbatim |
| HIG *The menu bar › Help menu* — "provides access to an app's help documentation"; "When the content uses the Help Book format, opens the content in the built-in Help Viewer" | **VERIFIED** verbatim; "Required by" overstates (R16) |
| HIG *Sheets › iOS, iPadOS* — "Prefer using the page or form sheet presentation styles in an iPadOS app." | **VERIFIED** verbatim |
| HIG *Sheets › macOS* — "The parent window is dimmed while the sheet is onscreen" | **VERIFIED** verbatim |
| HIG *Sheets › Best practices* — "In a macOS experience, you might want to open a new window…" | **VERIFIED** verbatim; same page contradicts the `完成` dismissal (R7) |
| HIG *Modality › Best practices* — "Take care to avoid creating a modal experience that feels like an app within your app…"; "Consider using a full-screen modal style for in-depth content" | **VERIFIED**; the second quote drops "or a complex task" |
| HIG *Onboarding › Best practices* — "If you let people skip the tutorial…" | **VERIFIED** verbatim |
| HIG *VoiceOver › Descriptions* — "Make charts and other infographics fully accessible…" | **VERIFIED** verbatim |
| HIG *VoiceOver › Navigation* — "Use titles and headings…", "use accurate section headings…" | **VERIFIED** verbatim |
| HIG *Designing for games › Look stunning on every display* — iOS/iPadOS 11 pt, macOS 10 pt minimum text | **VERIFIED**; table also gives defaults 17 pt / 13 pt |
| AppKit `NSButton.BezelStyle.helpButton` — "Include no more than one help button per window…" | **MISATTRIBUTED** — the text is HIG *Buttons › Help buttons* (R6) |
| ⌘? for the Help item | **VERIFIED** in HIG *Keyboards › Standard keyboard shortcuts*, with a caveat (R16) |
| HIG *Offering help › Platform considerations* — "No additional considerations for iOS, iPadOS, tvOS, or watchOS" | **NOT INDEPENDENTLY CONFIRMED** — plausible and consistent with the identical line on *Onboarding › Platform considerations*, but I did not retrieve the *Offering help* one; mark it or drop it |
| SwiftUI `HelpLink(anchor:)`; Accessibility *Animated images* | **NOT INDEPENDENTLY CONFIRMED** — neither is load-bearing for a recommendation |

No fabricated citation was found. One attribution error (R6) and two unconfirmed references.

## Executed record for this review

```
pyffish.version() = (0, 0, 89)   variant = minixiangqi   (fs-chase, read-only)

reproduced exactly: all 10 Appendix A probes; mx-move-001..006, mx-end-001..003,
mx-rep-001, mx-chk-001..002, mx-chs-001..004 start positions and legal sets.

new, not in the report:
  3k3/7/7/2N4/7/7/3K3 b  -> ['d7c7','d7e7']        (frame is unreachable — R13)
  P6/7/3k3/7/7/7/3K3 b   -> ['d5c5','d5e5']        (frame is unreachable — R13)
  mx-chk-001 cycle: in_check True at plies 0,2,4,6,8; False at 1,3,5,7   (R14)
  mx-chs-001 / -002 / -003: is_optional_game_end all (True, 0),
                            is_immediate_game_end all (False, 0)         (R4)
```

## Verdict

The executed core is sound and the illustration strategy is the right one. §5.5 should be rewritten or
withdrawn before any of it reaches contract text — all three of its load-bearing claims fail. §2.2/§2.3
needs the iPhone pre-start gap closed (R5), the AppKit attribution fixed and the two contrary
Help-buttons lines surfaced (R6), and the `完成` dismissal reconsidered (R7). §5.4's "every marker
executed" must be qualified (R4). The Chinese piece headings need one convention (R12). The rest are
corrections of the kind that take a line each.
