# Flow audit of the accepted contract set

Workspace-only research evidence. Not a contract, not a proposal for merge. The main thread authors any
contract text that follows from this.

**Scope.** All eight documents in `MiniXiangqi/docs/`, `MiniXiangqi/fixtures/rules/` and its README, read end
to end as one body of work, through one lens: **every user flow, hunting for states with no defined
behaviour**. Flows walked: launch and resume; starting a game in each mode; playing; undoing; claiming a draw;
resigning; a natural result; saving before a new mode; replay; History; import; export; deletion; engine
failure; save failure; suspension. At each step I asked what happens if the user does something unexpected, if
persistence fails, if the app is suspended, or if the engine is unavailable.

**Method markers.** Every claim below is marked as one of: *executed* (I ran it), *quoted* (verbatim from a
contract, with file and line), or *reasoned*. Where a choice belongs to the product owner rather than to a
designer, I say so and frame the options rather than choosing.

---

## What I executed, including what came back clean

Four checks were run rather than reasoned. Three found nothing wrong; reporting them so the reader knows the
ground is covered.

1. **The engine does not stall at a threefold-repeated root.** I was worried that a human-versus-AI game in the
   accepted `claimable-draw` state — the app keeps the game alive, the engine's variant has `nFoldRule = 3` —
   would leave the AI with no move to return. *Executed*, against
   `/Users/tianren/coding/minixiangqi/fs-staticlib/src/stockfish` (branch `mxq/static-library`), built-in
   variant `minixiangqi`, replaying the exact history of the approved fixture `mx-chs-002`
   (`4k2/7/c3r2/7/1R5/7/2K4 w - - 0 1` plus `b3a3 a5b5 a3b3 b5a5 b3a3 a5b5 a3b3 b5a5`, which the fixture
   asserts is `claimable-draw` at occurrence 3), then `go movetime 500`. Result: `bestmove b3b1`. The engine
   returns an ordinary legal move at a root position the app calls claimable. **No defect**; the flow concern
   is dropped. (It does not clear the *general* engine-failure gap in Finding 10 — `MXQ_ERR_ENGINE_NO_MOVE`
   still exists in the taxonomy with no user-visible mapping — but it removes the most likely way to reach it.)
2. **`core-interface.md` says "Six groups, 53 functions" (line 18).** *Executed* by counting the declarations
   in the code blocks: 5 prelude + 4 core lifecycle + 4 session lifecycle + 7 queries + 2 ordinary mutations +
   3 terminal commits + 4 session-free rules + 4 engine + 5 search + 4 archive + 3 store-active + 6
   store-history + 2 interchange = **53**. **No defect.**
3. **The move-travel table.** `interaction-design.md:420` gives 180, 195, 200, 210, 220, 230, 240 ms for
   distances 1, 2, √5, 3, 4, 5, 6 "following the square root of distance remapped onto the accepted band".
   *Executed*: `180 + 60·(√d − 1)/(√6 − 1)` gives 180.0, 197.1, 200.5, 210.3, 221.4, 231.2, 240.0, which
   rounds to 5 ms as 180, 195, 200, 210, 220, 230, 240 — the table exactly. Two plies at 240 ms leave 120 ms of
   overhead inside the accepted 600 ms decision-cycle Undo ceiling. **No defect.**
4. **The board-metric geometry.** *Executed* arithmetic on every figure in
   `interaction-design.md:131–157` and `240–262`: board core `7 p` = 308 pt at the floor; strip height
   `0.08 p + 0.887 s` = 15.94 → 16 pt, board block 308 × 340, hiding both strips returns 32 pt; grid
   `0.026 p` = 1.14 pt at the floor and hits the 1.60 ceiling at `p ≈ 61.5` ("about 62"); the selection ring at
   `0.440 p` centre-line × 1.05 lift spans 0.4463–0.4778 `p`, inside both the 0.42 floor and the 0.50 cell; the
   check pulse growing only inward/outward into the inter-ring gap leaves 0.015 `p`; the drag-strengthened
   capture ring's inner edge lands at 0.43 `p`; last-move brackets' nearest ink is at 0.53 `p` from the point
   centre. Every stated figure checks out. **No defect.**

---

## Findings, ranked by how likely a real user is to reach the undefined state

Severities: **contradiction** (two accepted statements cannot both hold), **gap** (a reachable state with no
defined behaviour), **ambiguity** (defined, but more than one reasonable reading).

### 1. The turn status has no defined content once the game has a result — reached at the end of every game

**Severity: contradiction.**

Quoted, `interaction-design.md:266–268`:

> A persistent status element near the board is one coherent description of the current play state:
> - Its primary line **always** identifies the side to move, using the localized equivalent of **轮到红方** or
>   **轮到黑方**.

Quoted, `interaction-design.md:339`:

> When a natural terminal result is reached, the final board remains fully visible and a non-dismissible result
> card appears near it.

The status element is persistent; the accepted exceptions to "always identifies the side to move" are exactly
two, both carved out explicitly — the pre-start state ("does not show a side-to-move status",
`interaction-design.md:190` and `:202`) and replay ("History replay uses a separate move-progress and playback
state rather than describing the position as a human or AI turn", `:275`). A checkmated, stalemated, resigned,
drawn or perpetual-violation position has **no side to move**, and no third carve-out exists. The element must
therefore say something the contract does not define, in the one state every finished game passes through and
sits in until the user taps **结束对局** — and then again after, since "the final board remains visible"
(`:343`).

It gets worse with the check token. Quoted, `interaction-design.md:271`:

> While the side to move is in check, a **将军** token accompanies the side-to-move line for as long as that
> remains true.

And `testing.md:186` turns that into a check: "Verify the **将军** token is present during play for exactly as
long as the side to move is in check". In checkmate the side to move *is* in check and remains so forever, so
the accepted rules require a **将军** token to sit permanently beside a side-to-move line that cannot exist,
next to a card that says **红方获胜 · 将死**.

**Which is right.** `:339`/`:343` — the result card is the accepted terminal presentation and is not in doubt.
The defect is in the turn-status section, which was written from the ongoing-play state outward and never
returned to the terminal one.

**Exact correction.** In `interaction-design.md`, under **Turn status**, add a third exception beside the
pre-start and replay ones:

> Once the committed game state is terminal — a natural result awaiting confirmation, a confirmed result, a
> claimed draw, or a resignation — the element stops describing a side to move and states the outcome, using
> the same localized result wording the result card's title uses. The **将军** token is not shown in a terminal
> state: a checkmate is reported as a checkmate, not as a check. In human-versus-AI play the **你**/**AI**
> controller label is retained only insofar as it is part of the result wording.

and amend `:268` to read "Its primary line identifies the side to move in every non-terminal state during
play," and `testing.md:186` to "…present during non-terminal play for exactly as long as the side to move is in
check". If the product owner would rather hide the element entirely while the card is up, that is the
alternative; it costs the accessibility anchor for the save-failure capsule and the acknowledgment beat
(`:272`), which is why I recommend keeping it and changing what it says.

---

### 2. Engine preparation on the first AI reply after any resume has no defined presentation, and its failure lands after the user's move is already committed — reached in every resumed human-versus-AI game

**Severity: gap** (the acknowledged open question covers a strictly narrower case than the one users reach).

Quoted, `engine-integration.md:72`:

> **Re-preparation happens when a search is next owed, not on return to the foreground.** A search is owed
> exactly when the resumed state is an active human-versus-AI game whose committed status reports the AI to
> move and a search expected. Replay, Free Play, a confirmed result, **a game awaiting the user's move**, and
> having no active game all require no engine, so none of them re-prepares one.

The overwhelmingly common resume state is "a game awaiting the user's move" — the user stopped playing after
their opponent moved. So no engine exists at resume; the user makes a move; *now* a search is owed; *now* the
core must probe memory, allocate up to 4 GiB of Hash, load and preflight the NNUE, and load the variant. Two
things are undefined about that moment:

**(a) What the user sees while preparation runs.** The only accepted timing rule is quoted,
`interaction-design.md:424`:

> If the search has not returned within 500 ms of the player's move, the turn status shows AI activity; below
> that threshold nothing appears, because an indicator that flashes for a fifth of a second is noise.

That threshold is defined against *the search*. Preparation is not a search, and the accepted compose-beat
floor ("the later of… 260 ms after the player's move has finished animating") is also defined against the
search returning. Nothing says whether preparation counts toward the 500 ms, or whether an allocation of
several gigabytes is allowed to produce a silent unresponsive board.

**(b) What happens when preparation fails there.** Quoted, `engine-integration.md:73`:

> Re-preparation obtains a fresh memory probe and can fail… The game remains active, saved, and resumable, with
> the AI unable to move until preparation succeeds. What the user sees in that mid-game case is not the
> accepted pre-start notice… it is an open interaction question below.

That open question is quoted at `interaction-design.md:526` and `engine-integration.md:194`, and both scope it
to "**after the app was suspended** and the AI is due to move". The reachable case is broader and materially
different: the user has just committed a move — `mxq_game_apply_move` "commits the updated state inside the
call" (`core-interface.md:49`) — so unlike every other accepted engine-failure path, this one leaves a
**persistent** change behind a failure. "Creates nothing" and "the draft remains" have no analogue. And the
contracts do not say which actions remain available in that stuck state: `interaction-design.md:328–329`
defines Undo "while the AI is thinking" and "after the AI has replied", and neither describes "the AI is due to
move and is not thinking".

**Which is right.** `engine-integration.md:72` is right that Free Play and replay must not hold an engine.
What is missing is the presentation and the recovery rules for the moment the engine is first needed.

**Exact correction.** Three additions.

1. In `interaction-design.md`, under **Turn status** or a new **AI preparation** subsection: "Preparing the AI
   counts as AI activity for the purposes of the 500 ms threshold: the turn status shows AI activity once 500
   ms have passed since the player's move, whether the time is spent preparing or searching. Board input
   remains unavailable throughout, exactly as while the AI is thinking."
2. Replace the two Need-to-discuss items with an accepted mid-game engine-unavailable state, and widen its
   trigger from "after the app was suspended" to "whenever preparation is attempted for an active
   human-versus-AI game that already has moves". See Finding 10 for the notice itself.
3. In `interaction-design.md`, under **Undo and result confirmation**, add: "In human-versus-AI play, Undo is
   available whenever the AI is to move, whether or not a search is running; where a search is running it is
   cancelled, and where none is running the human move is removed unchanged. This is what lets a player recover
   a game whose AI cannot be prepared." That single sentence also closes Finding 18.

---

### 3. Nothing freezes the AI's reply while a blocking decision is on screen

**Severity: gap.** Consequences include a confirmation that archives a different game from the one it
described, and a draw claim that is no longer legal when the user taps it.

The accepted contracts put four blocking presentations in front of a user during a game in which the AI may
commit a move at any instant: the save-and-continue confirmation (`interaction-design.md:298–305`), the
threefold notice (`:350`), the insufficient-memory notice (`:282`), and the **无法保存对局** retry
(`:317–321`). All four are reachable while the AI is thinking, because quoted, `interaction-design.md:298`:

> Both mode entries remain interactive whenever an active game exists.

and the accepted input rule is about the *board* only — quoted, `:274`: "Board input is accepted only when the
committed game state permits the user to move. It is disabled while the AI is thinking."

Two concrete failures, both *reasoned* from accepted text:

- **The confirmation describes a game that no longer exists.** The confirmation shows factual metadata — the
  accepted example is **进行中 · 轮到黑方 · 42 步** (`:305`) — while **保存并继续** classifies "from the
  committed game state" (`game-data.md:78`). With **标准** at 3 s per move, a user who taps *Human versus AI*
  during the AI's turn and reads the dialog can easily have the AI's reply commit before they tap **保存并继续**.
  They then archive **黑方获胜 · 将死 · 43 步** having agreed to save an ongoing game — a different
  classification, a different History record, and the accepted promise that "the metadata reports facts"
  (`:305`) quietly broken.
- **The draw claim becomes illegal between presentation and tap.** The threefold notice appears when the draw
  becomes available, which happens on the human's own move as often as on the AI's. Quoted,
  `core-interface.md:50`: "Claim commits the draw with reason `threefold-repetition` and **is legal only in the
  claimable state**." If the AI's reply commits while the notice is up, the position is no longer the repeated
  one, `mxq_game_claim_draw` returns a `MXQ_DOMAIN_STATE` code — and quoted, `core-interface.md:210`, the
  accepted user-visible mapping covers "any store-domain failure from `mxq_store_archive_and_clear` **or a
  terminal commit**", `MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY`, apply/undo store failures, and import failures.
  A state-domain refusal of a claim maps to nothing. The user tapped **以和棋结束** and the contracts do not say
  what they see.

**Which is right.** Neither statement is wrong on its own; the contract set simply never decides whether the
game's clock keeps running behind a dialog. It must.

**Exact correction.** Add to `interaction-design.md`, under **Saving the active game before choosing a new
mode** (and cross-referenced from the threefold section), a rule that covers all four presentations:

> While any of the four game-scoped blocking presentations is on screen — the save-and-continue confirmation,
> the threefold notice, the insufficient-memory notice, and the **无法保存对局** retry — a returned AI move is
> **held rather than applied**. It is applied as soon as the presentation is dismissed by an action that leaves
> the game active, and discarded when the action archives or ends the game. Search itself is not cancelled: the
> user may cancel, and a cancelled search would have to be paid for twice. Consequently the state described by
> a confirmation's metadata is exactly the state **保存并继续** archives, and a claim offered by the threefold
> notice is still legal when the user takes it.

The alternative — cancel the search on presentation and re-request it on dismissal — costs the user up to five
seconds each time and is worse; the third alternative, letting the move land and re-rendering the dialog, means
a dialog whose text changes under the reader's finger, which is unacceptable for a destructive-ish action. This
is a designer's call, not the owner's, and I am making it.

---

### 4. The relationship between the Play destination and the board is undefined, so leaving a game in progress has no specified behaviour

**Severity: gap.** Reached by anyone who checks History, opens Settings, or opens Help mid-game.

Quoted, `interaction-design.md:183`: "selecting **Human versus AI** or **Free Play** opens that mode's
pre-start state **on the board page**." Quoted, `:296`: "The Play destination shows the active game's metadata
and a direct **Resume Game** action." So there are two surfaces — a Play destination and a board page — and the
contract never says how one gets from the board back to the other, whether that is even permitted during play,
or what happens to the game when it does.

That would be a mere presentation hole if the app were turn-based-by-tap. It is not: the AI moves on its own.
Undefined, in a state a learner reaches constantly:

- Is the search cancelled when the user leaves the board page? `architecture.md:51` lists the cancel triggers
  as "Undo, game completion, active-game replacement, **leaving the relevant state**, and the platform's
  suspension signal". "Leaving the relevant state" is the only candidate and is not defined anywhere.
  `engine-integration.md:65` says the *release* trigger is explicitly not loss of focus — but a tab switch is
  neither suspension nor focus loss.
- If it is not cancelled, does the AI's move commit while the play screen is not on screen? If it does, the
  accepted motion language — "An AI move uses the same move language and leaves persistent origin and
  destination markers so the player can identify the completed move" (`:414`) — is spent on an empty room, and
  on return the player sees a changed board with no travel and no way to know what moved beyond the brackets.
- The same question applies to Help, which is quoted as explicitly permitted mid-game (`:396`): "Help is
  reachable from Settings and from the game screen without abandoning or pausing state: opening help never
  modifies the active game, and returning restores the exact prior context." "Never modifies the active game"
  is about Help; it says nothing about the AI, which will happily modify the active game while Help is open,
  making "restores the exact prior context" false through no fault of Help's.

**Which is right.** `:396` states the intent — leaving does not disturb the game — and it is the one I would
keep. The gap is that nothing extends that intent to the AI.

**Exact correction.** Add to `interaction-design.md`, under **Navigation**:

> The board is a page within the Play destination, and it may be left at any time; the active game is
> unaffected, because every accepted move is already committed. An outstanding AI search is **not** cancelled
> when the user leaves the board or opens Help, and a returned move is **held and applied when the board is next
> visible**, so the player always sees the AI's move animate. The engine is not released — release is the
> suspension signal's job — and the turn status on return reports the state as it then is.

This is the same "hold rather than apply" mechanism as Finding 3; one rule can serve both. If the owner
prefers, the opposite policy (apply immediately, and on return show the board already changed with last-move
brackets and no animation) is coherent too and cheaper to build — but it silently loses the one affordance the
contract provides for identifying the AI's move on a board the user was not watching.

---

### 5. Resign is an accepted product feature with no interaction design whatsoever

**Severity: gap.** Reached by every user who wants out of a losing game — which, against a level-20 engine, is
most of them.

Quoted, `product.md:40`:

> Resign is available only in human-versus-AI games. After confirmation, resignation records a loss for the
> human player.

Quoted, `core-interface.md:83` and `:101`: `mxq_game_resign(...)` exists, and `MxqGameStatus` carries a
`resign_available` flag "so frontends never re-derive rules policy". `game-data.md:107` records the outcome.
`testing.md:107` tests the persistence.

`interaction-design.md` — the document that "owns UI and UX behavior, navigation, … and platform adaptation"
(`:3`) — mentions resignation exactly twice, and both times only to say what it is *not*: `:342` ("Resignation
remains a separate confirmed action rather than being folded into the natural-result card") and `:230` (its
save failure uses **无法保存对局**). There is **no** resign control, no placement, no label, no confirmation
title, message or action copy, and no availability rule. It is not in any **Need to discuss** section either,
so it is not even a declared hole. Compare the treatment of every other terminal action: the threefold notice,
the result card, the deletion confirmation and the save-and-continue confirmation all have exact accepted
Chinese copy.

Specific states with no answer: is resign offered while the AI is thinking? While a natural result card is up
(the card is non-dismissible and offers only **悔棋** and **结束对局**, so presumably the control is
unreachable — but "unreachable" is an accident of layout, not a decision)? While the claimable-draw affordance
is showing? At ply 0? `resign_available` has no accepted definition to compute.

**Exact correction.** Add to `interaction-design.md`, in a new subsection beside **Undo and result
presentation**:

> **认输.** A resign control sits in the play control cluster in human-versus-AI play only; it is absent in Free
> Play and in replay. It is enabled whenever the committed game state is ongoing or claimable — including while
> the AI is thinking, since a player who has decided to stop should not have to wait for the opponent — and
> disabled once any natural terminal result exists, confirmed or not, and while an Undo transition is running.
> It uses the system's destructive role rather than a red tint. Choosing it presents:
> - Title: **确认认输？**
> - Message: **这盘对局将记为你输棋，并保存到历史。**
> - Actions: **取消** and **认输**, the latter destructive.
>
> Confirming commits the loss immediately and moves the game to immutable History; the final board remains
> visible and the card reads **已记录到历史**, with **回放** and **完成**, exactly as after **结束对局**. A
> failed commit uses the accepted **无法保存对局** presentation and leaves the game active and unchanged.

The exact Chinese strings are the product owner's to approve — the accepted copy in this document is normative
and mine are proposals — but the *structure* (control placement, availability rule, destructive role, reuse of
the recorded-state card) is a designer's call and I am making it. Also add the matching line to `testing.md`,
which currently verifies the result card, the threefold notice, the deletion confirmation and the
insufficient-memory notice, and never once exercises resignation's UI.

---

### 6. An unconfirmed natural result does not survive relaunch in any defined way

**Severity: gap.** Reached whenever a game ends and the app is terminated before the user taps **结束对局** —
a phone call, a swipe-up, an overnight jetsam.

The state is explicitly accepted as durable. Quoted, `game-data.md:105`:

> An unconfirmed natural terminal state remains the active game and can be undone.

and `game-data.md:143`: "A `game` row is the active game exactly when its committed outcome is null" — an
unconfirmed result has committed no outcome, so it is the active game and it survives termination. On relaunch
the user is on the Play destination, which quoted (`interaction-design.md:296`) "shows the active game's
metadata… the result and reason for a terminal game" and offers **Resume Game**.

Undefined: what **Resume Game** presents. The result card's accepted trigger is quoted, `:339`: "**When a
natural terminal result is reached**, the final board remains fully visible and a non-dismissible result card
appears near it." The result was reached in a previous process. Nothing says the card is re-presented, and
nothing else can present the outcome, because the turn status has no terminal wording either (Finding 1). The
literal reading gives a board with a finished position, no card, no side to move, and an Undo that removes the
mating move.

**Exact correction.** Change `interaction-design.md:339` to read "When a natural terminal result is reached, or
when an active game whose committed state is a natural terminal result is resumed, the final board remains
fully visible and a non-dismissible result card appears near it." Add to `testing.md`, under **Game data**,
beside the existing claimable-repetition relaunch test at `:106`: "Test persistence and relaunch of an active
game holding an unconfirmed natural terminal result, and verify the result card is presented on resume with
**悔棋** and **结束对局** still available."

---

### 7. The 可判和 affordance has no defined lifetime

**Severity: gap**, with an **ambiguity** inside it. Reached by any learner whose game repeats — and Mini
Xiangqi's tiny board makes repetition common; the rules contract spends most of its length on it.

Quoted, `interaction-design.md:350–352`:

> When the draw **first** becomes available, the notice says **局面已三次重复，可以和棋结束。** and offers
> **继续对局** and **以和棋结束**.
> After **继续对局**, the **same still-valid** claim is exposed through a non-blocking **可判和** affordance
> instead of repeatedly presenting the same blocking notice.

Three unanswered questions, all reachable:

- **When does the affordance go away?** Quoted, `xiangqi-rules.md:61`: "On the third neutral occurrence, **the
  position** becomes eligible to be ruled a draw" — eligibility is a property of the current position and
  history, so it evaporates the moment either side plays a move to a position that has not occurred three
  times. "Still-valid" gestures at this without stating it. A user who taps **继续对局**, plays on, and still
  sees **可判和** ten moves later would be offered a claim the core will refuse — the same unmapped
  `MXQ_DOMAIN_STATE` refusal as in Finding 3.
- **Does the blocking notice ever return?** "first becomes available" reads as once per game. But a *different*
  position reaching its own third occurrence later in the same game is a new claim, not the same one. Under the
  literal reading the second, unrelated claim is announced by nothing at all — the user must notice a small
  affordance appear. Under the other reading the notice interrupts again. Both are defensible; the contract
  picks neither.
- **What happens across Undo?** Undo from a claimable position removes the occurrence that created the claim.
  Nothing says the affordance disappears, and `interaction-design.md:313` explicitly tells the user they may
  "resume it and use the board's normal Undo **or draw-claim controls**" — the two interact and are never
  reconciled.

**Exact correction.** Replace `interaction-design.md:352` with:

> The **可判和** affordance is present exactly while the committed game state reports a claim available, and it
> disappears the moment it does not — including after a move that leaves the repeated position and after an
> Undo that removes an occurrence. The blocking notice is presented once for each distinct claim: it appears
> when a claim becomes available and no claim was available in the previous committed state, so a later,
> unrelated threefold repetition in the same game is announced again, while continuing and immediately
> repeating the same position is not.

This makes the affordance a pure function of `claim_available` (`core-interface.md:101`), which is exactly what
that flag is for, and it removes any path to an illegal claim.

---

### 8. Imported human-versus-AI games have two conflicting default replay orientations

**Severity: contradiction.** Reached the first time one internal tester shares an AI game with another — which
is what Share exists for.

Quoted, `interaction-design.md:215`, one sentence apart:

> Human-versus-AI history replay defaults to the original human player's perspective. Free Play **and imported
> history** default to Red at the bottom.

An imported human-versus-AI record satisfies both antecedents. And it genuinely carries the information the
first rule needs: quoted, `game-data.md:38`, `content` carries "for human-versus-AI games `human_side`", and
`product.md:59` requires History rows to identify the human side while marking imported entries — so the app
knows the imported game's human played Black and must still choose an orientation.

**Which is right.** The first rule. The second's purpose is to name a default for records that have *no* human
side — Free Play — and "imported" was swept in with it by association. Provenance is explicitly local metadata
that "never affect[s] equality" (`game-data.md:58`) and is not in the archive at all
(`game-data.md:52`); letting it change how a game is displayed contradicts the whole point of the archive being
portable and platform-identical.

**Exact correction.** Rewrite `interaction-design.md:215` as:

> History replay defaults to the original human player's perspective for every human-versus-AI record, whether
> played locally or imported, since the archive records the resolved human side. Free Play records, which have
> no human side, default to Red at the bottom. History replay provides the same visible orientation control.

---

### 9. A game-creation persistence failure has no error copy, and both accepted error presentations would state something false

**Severity: gap.** Reached on a full or failing disk, and by anyone testing the accepted failure path.

The failure is accepted and required to be presented. Quoted, `interaction-design.md:198`: "Failed AI
availability or active-game persistence keeps the page and draft available for retry, **shows the applicable
error**, and re-enables **开始对局**." Quoted, `:207` for Free Play: "A creation failure retains the pre-start
page, **presents an error**, and re-enables **开始对局**."

There is no applicable error. The contract set accepts exactly two error presentations, and neither fits:

- **无法启动 AI 对手** / **当前可用内存不足。请尝试关闭一些其他 App，然后重试。** (`:283–285`) — this is the
  memory notice; a store failure is not a memory condition, and closing other apps will not help.
- **无法保存对局** / **当前对局仍然保留。请重试。** (`:319–320`) — the message asserts that the current game is
  retained. In a creation failure there **is no current game**: `game-data.md:93` is explicit that "A failed
  creation in either mode leaves no active game". The message would be literally false, and worse, reassuring
  about a game that does not exist.

Note that Free Play's failure path can have no engine involvement at all, so this is not reducible to the
engine notice under any reading.

**Exact correction.** Add a third accepted presentation in `interaction-design.md`, under **Starting and
configuring a game**:

> A persistence failure during game creation, in either mode, uses:
> - Title: **无法创建对局**
> - Message: **这盘对局没有创建成功。请重试。**
> - Actions: **取消** and **重试**.
>
> **取消** dismisses the notice and leaves the pre-start state and its draft intact; **重试** repeats the whole
> creation operation, including a fresh memory probe and a fresh resolution of a **随机** first-mover choice.

Add the matching verification to `testing.md:74`, which today verifies that such a failure "create[s] no game or
persistent game-library change" but names no copy.

---

### 10. Every engine failure except insufficient memory has no user-visible flow, and the one accepted notice would misdescribe them

**Severity: contradiction** (an accepted document points at a presentation that does not fit) **plus gap**.

Quoted, `engine-integration.md:154`, on a network that fails verification:

> In that case **the AI does not start**, and the frontend reports it through the **accepted engine-unavailable
> path**.

There is no such path. The only accepted engine-unavailable presentation is quoted,
`interaction-design.md:282–285`:

> - Title: **无法启动 AI 对手**
> - Message: **当前可用内存不足。请尝试关闭一些其他 App，然后重试。**
> - Actions: **取消** and **重试**.

For a damaged installation this message is simply wrong, and **重试** can never succeed — it will re-probe
memory forever against a hash mismatch. The contract set is aware of the reasoning that justifies reuse in the
one case where it *is* right, quoted `engine-integration.md:112`: an allocation failure reuses the notice
because "the situation the user is in is the same one — memory is not available right now — and the same action
resolves it". That reasoning explicitly does not extend to a hash mismatch, which `:154` itself calls "a
damaged installation" whose remedy is reinstalling (`:156`).

The same hole covers the rest of the engine domain. Quoted, `core-interface.md:200`, `MXQ_DOMAIN_ENGINE`
carries "insufficient memory, **asset missing / mismatch, variant load failure**, Hash allocation failure…,
**no move, illegal result, faulted**"; quoted `:210`, the accepted user-visible mapping names exactly one of
them: "`MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY` drives the accepted low-memory retry flow". Seven codes, no
presentation, several of them mid-game. `testing.md:120` and `:140` require these cases to be *tested* with no
copy to test against.

**Exact correction.** Add to `interaction-design.md`, beside **Insufficient memory for AI play**:

> **AI 对手不可用（非内存原因）.** When the engine cannot be prepared or continue for any reason other than
> available memory — a missing, mismatched or unloadable network or variant configuration, or an engine fault —
> the app presents:
> - Title: **AI 对手不可用**
> - Message: **AI 组件无法加载，可能是安装文件损坏。请重新安装本应用。自由对弈、历史、回放、导入和导出不受影响。**
> - Action: **好**, alone. No **重试**: nothing the user can do here changes the outcome.
>
> Before a game exists, the notice leaves the pre-start state and draft intact and **开始对局** remains
> disabled for human-versus-AI until the app is relaunched. **In an active game with moves already played, the
> game remains active, saved and resumable; the board is not dimmed; the turn status reports that the AI cannot
> move; and Undo, 认输 and 保存并继续 all remain available**, so the player is never trapped in a game whose
> opponent cannot reply.

That last sentence is also the missing answer to the two Need-to-discuss items at
`interaction-design.md:526` and `engine-integration.md:194` — a mid-game *memory* failure wants the same
structure with the memory wording and a **重试** action, since there a retry genuinely can succeed. I recommend
resolving both as one accepted mid-game state rather than two.

---

### 11. Nothing defines what the user sees if the core cannot start

**Severity: gap.** Low likelihood per user, total consequence when it happens, and it is on the migration path
every internal build will exercise.

Quoted, `game-data.md:161`: "migration is forward-only, and a store written by a newer build is **refused
rather than opened**." Quoted, `core-interface.md:198`, the store domain carries "I/O, corruption, busy, full,
not found, identity conflict, **migration failed, schema too new**". Quoted, `architecture.md:59`: "Invalid
imports, persistence failures, unavailable engine resources, and engine failures must not terminate the app or
partially replace a committed game."

So the app must not terminate — and no accepted document says what it does instead. `mxq_core_init` can fail;
`mxq_game_resume_active` can fail on a corrupted blob or an active game whose move line no longer replays.
There is no launch flow in `interaction-design.md` at all: the document never describes what any destination
shows when the core is unavailable, and `interaction-design.md:537` defers only "empty, loading, AI-thinking,
error, corrupted-import, and destructive-action states", which is about states within a working app.

An internal tester who installs an older build over a newer one — routine during TestFlight testing — reaches
this immediately.

**Exact correction.** Add a short **Launch and unavailable store** subsection to `interaction-design.md`
defining: (a) the ordinary launch destination when the core initializes and there is no active game — this is
also the undefined "Play start state" of Finding 14; (b) a blocking, non-dismissible presentation when the core
cannot initialize, distinguishing "this store was written by a newer version of Mini Xiangqi" (which must never
be presented as corruption, matching the accepted archive-side rule at `game-data.md:64`) from an unreadable
store; (c) that no destination offers game or History content in that state, rather than showing an empty
History that would suggest data loss; and (d) that an active game which cannot be resumed leaves History
untouched and is reported separately. The exact copy is owner-approvable; the requirement that a
newer-store refusal never reads as data loss is not negotiable, because the user's data is intact and telling
them otherwise invites them to delete it.

---

### 12. The engine is never released when the active game stops needing it

**Severity: gap.** Always true after any AI game; invisible until iOS kills the app.

Quoted, `engine-integration.md:65`: "**The trigger** is the platform's own suspension or memory-pressure
signal, not loss of focus." Quoted, `:67`: "On that signal, any running search is cancelled **and the
transposition table released**". Quoted, `:103`: "The target cap is 4 GiB". Quoted, `:72`: re-preparation
happens when a search is next owed, and "Replay, Free Play, a confirmed result, a game awaiting the user's
move, and having no active game all require no engine".

Put those together with an ordinary session: play a human-versus-AI game (engine prepared, up to 4 GiB of
Hash), reach a result, tap **结束对局**, then **回放**, then browse History, pin a game, import a file, start a
Free Play game. In every one of those states the contract says no engine is needed — and no accepted rule ever
releases the one that is already prepared. The app sits on gigabytes it will not use, which
`engine-integration.md:67` itself identifies as "precisely the profile the operating system reclaims first".
`mxq_engine_teardown` exists (`core-interface.md:113`) and no accepted flow calls it except shutdown.

**Exact correction.** Add to `engine-integration.md`, under **Accepted backgrounding and teardown behavior**:

> The engine is also released, by the same whole cancel-and-release path, whenever the app enters a state that
> requires none: a terminal commit of any kind, `mxq_store_archive_and_clear`, the creation of a Free Play
> game, and the absence of an active game. Release is symmetric with the accepted re-preparation rule — the
> engine exists exactly while a human-versus-AI game is active — so a session that ends an AI game and browses
> History holds no Hash. Re-preparation on the next search owed is the accepted path back.

Add the matching check to `testing.md` beside `:134`.

---

### 13. A failed save of the AI's reply retries forever, silently

**Severity: gap.** Low likelihood, but the failure mode is an unbounded loop with no user-visible exit.

Quoted, `interaction-design.md:229`:

> When the failed save is the AI's reply, the game remains at the last committed position with the AI still to
> move, and **the app requests a new AI move** rather than asking the user to retry a move that is not theirs.

Quoted, `:257`: "When the failed save is the AI's reply **no capsule appears and the board shows nothing at
all**, because the retry is the app's to perform and not the user's."

On a full disk the commit fails deterministically. The app searches (up to 5 s), fails to commit, requests a
new search, and repeats — forever, at full CPU, with a board that shows AI activity and never changes and a
user who is told nothing. Nothing in the contract set bounds the retries, backs them off, or escalates. Contrast
the user's own move, where the identical failure is reported immediately and the user decides.

**Exact correction.** Amend `interaction-design.md:229` to:

> …the app requests a new AI move rather than asking the user to retry a move that is not theirs. Automatic
> retry is bounded: after **three** consecutive commit failures for the AI's reply the app stops retrying and
> presents the accepted **无法保存对局** presentation, whose **重试** resumes the same automatic path and whose
> **取消** leaves the game active, saved at its last committed position, and awaiting the user's decision. A
> failure the app cannot resolve is the user's to know about.

The number is a designer's choice; that the loop must terminate is not.

---

### 14. Leaving a pre-start state sideways lands on an undefined screen, and "Play start state" is an undefined term

**Severity: gap** plus **ambiguity**. Reached by anyone who checks the rules in Help, or History, while setting
a game up.

Quoted, `interaction-design.md:193`: the draft's values "are discarded as soon as the user **leaves the
page**". Quoted, `game-data.md:88`: "**Leaving either pre-start state discards it.**" Neither says what leaving
by tab switch or back-navigation puts on screen, and the Play destination is only ever described for the case
where an active game exists (`:296`). After discarding a pre-start state there is no active game — so the Play
destination's content in that state is undefined, and it is the state a user is in after every completed game
too.

The same missing definition has a name in the contract and only one use of it. Quoted,
`interaction-design.md:344`: the recorded card offers "**完成**, which returns to the **Play start state**".
That term appears exactly once in all eight documents and is never defined. It is presumably the Play
destination with no active game, but a reader cannot tell whether it means "the board page reset" or "the Play
destination".

**Exact correction.** Define the state once, in `interaction-design.md` under **Navigation**: "**Play start
state** — the Play destination with no active game: the two mode entries and nothing else; no board, no
metadata card, no **Resume Game**." Then use that term at `:344`, and add: "Leaving a pre-start state by any
route — back-navigation, switching destination, or opening Help — discards the draft and the pre-start state
and returns the Play destination to the Play start state. Opening Help from a pre-start state is the one
exception and preserves it, matching Help's accepted promise to restore the exact prior context." Whether Help
is that exception is genuinely the owner's call: it is a small implementation cost against a real annoyance for
the learner Help exists to serve.

---

### 15. The recorded-result card's 回放 has no defined way back

**Severity: gap.** Reached by every user who taps it — an accepted action on every completed game.

Quoted, `interaction-design.md:344`:

> The recorded state offers **回放**, which opens the newly created History record from its initial position,
> and **完成**, which returns to the Play start state.

Undefined: what leaving that replay does. Return to the card (which no longer describes an active game, since
the record is now immutable History)? To the History list, which the user never visited? To the Play start
state, silently discarding **完成**? Nothing says, and `interaction-design.md:361` only removes options
("Pin, Share, and Delete are managed from the History list rather than from replay").

A second, smaller hole in the same corner: nothing prevents the user from switching to History and deleting
that record while the card is still on screen, after which **回放** targets a record that no longer exists
(`mxq_store_history_delete` is unconditional; `mxq_store_history_open` would return store-domain not-found,
which has no user-visible mapping).

**Exact correction.** Amend `:344` to: "…and **完成**, which returns to the Play start state. Leaving that
replay returns to the recorded-result card, which remains available until **完成** is taken; the card is a
property of this session and does not survive relaunch. If the record has been deleted in the meantime, **回放**
is unavailable and the card offers only **完成**."

---

### 16. Board input while an unconfirmed natural result is on screen is described two different ways

**Severity: ambiguity**, with real bite for exactly the results this project's rules contract works hardest on.

Quoted, `interaction-design.md:274`: "Board input is accepted only when the committed game state permits the
user to move." Quoted, `:234`: "When input is unavailable, **including while the AI is thinking or after a
result is confirmed**, the board rejects the interaction before visually moving a piece." Quoted, `:258`: "The
board is never dimmed **while the AI is thinking or after a result is confirmed**."

Both enumerations name the *confirmed* case and omit the unconfirmed one, while the principle at `:274` covers
both. For checkmate and stalemate this is academic — there are no legal moves to attempt. For a **perpetual
check or perpetual chase** it is not: quoted, `xiangqi-rules.md:62`, "A unilateral perpetual violation becomes
terminal automatically… the rules facade reports the loss for the violating side as a natural result", and such
a position has plenty of legal moves. A learner who has just been told they lost by a rule they are still
learning will absolutely try to move a piece, and the contract gives two answers about what happens.

**Exact correction.** Change both enumerations to read "including while the AI is thinking and whenever a
natural terminal result exists, confirmed or not", so the acknowledgment beat at `:258` answers the tap and the
principle at `:274` is the only rule. No behaviour changes; the enumerations stop contradicting it.

---

### 17. Opening a `.mxq` file from outside the app is undefined

**Severity: gap.** Likely for the actual distribution model: internal testers on TestFlight sharing games.

The app declares a document type — quoted, `game-data.md:35`: "file extension `.mxq`, Apple UTI
`com.ppppvz.minixiangqi.game` conforming to `public.json`" — and Share "exports the selected History record as
one game file" (`interaction-design.md:376`). Declaring a UTI means the system will offer Mini Xiangqi as the
handler when a tester taps the file in Messages or Files. Every accepted import statement, however, describes
import as something initiated from inside the app: "Import selects one game file at a time" (`:383`), "Import
processes one game file at a time" (`game-data.md:118`).

Undefined: whether a document-open launch imports at all, what it shows if the app was cold-launched, what it
does if it arrives while a pre-start state or a blocking confirmation is on screen, and what it does with a
duplicate (the accepted in-app answer, "offers a way to view the existing record", assumes a History context).

**Exact correction.** Either (a) state in `product.md` that the target MVP does **not** register a document
handler and import is in-app only — in which case the UTI declaration needs a note that it exists for export
and system presentation only; or (b) define the flow in `interaction-design.md`: an externally opened file
navigates to History, runs the same accepted validation, and presents the same success, duplicate and conflict
results, deferring until any blocking presentation is dismissed and never touching the active game. This is a
product-owner choice: (a) is free and (b) is how a tester will actually expect to receive a game.

---

### 18. Undo has no defined case for "the AI's move has been decided but not yet shown"

**Severity: gap**, small window, frequent exposure.

Quoted, `interaction-design.md:328–329`: "Undo **while the AI is thinking** cancels the search and removes the
human move that triggered it. **After the AI has replied**, one Undo action removes the AI reply and the
preceding human move."

Between those two lies the accepted compose beat: quoted, `:424`, the AI's piece "departs at the later of two
instants: when the search returns, and 260 ms after the player's own move has finished animating". For a fast
reply the search has returned and the move is not yet applied — the AI is neither thinking nor has it replied.
Nor is this covered by the interruption rule at `:426`, which discards input during a *committing* transition;
nothing is animating yet.

The core is unambiguous (the committed history has one ply to remove, so `undo_plies` is 1), so this is a
frontend-presentation gap rather than a correctness one: is Undo enabled, and does taking it cancel a move the
user is about to see?

**Exact correction.** Add to `interaction-design.md:328`: "A search result that has returned but has not yet
been applied is treated as still thinking: Undo cancels it, the AI's move is never shown, and one ply is
removed." The alternative — defer the Undo until the AI's move has been applied and then remove two plies —
makes a player watch a move they were trying to prevent and then watch it disappear. The correction above also
resolves the "AI due to move but not searching" case from Finding 2 under a single rule if both are worded as
"whenever the AI is to move".

---

### 19. Flip Board during human-versus-AI play is neither granted nor denied

**Severity: ambiguity.**

Quoted, `interaction-design.md:213–215`: "In human-versus-AI play, the human player's side is displayed at the
bottom. … **In Free Play**, Red is at the bottom by default. Once the game starts, a visible **Flip Board**
control allows the player to change orientation at any time. Human-versus-AI history replay… History replay
provides the same visible orientation control."

The control is granted to Free Play and to replay and simply not mentioned for human-versus-AI play. Elsewhere
the contract seems to assume it exists there: quoted, `:426`, "Board flipping is the one action **deferred**
rather than discarded: it changes nothing about the game, so it is applied when the running transition ends" —
the committing transitions worth deferring behind are most obviously the AI's move. `testing.md:79` verifies
board-flip pause only in replay.

**Exact correction.** Decide it explicitly in `interaction-design.md:213`. I recommend granting it: "The
Flip Board control is available in every mode and in replay; in human-versus-AI play the default is the human's
side at the bottom and flipping changes presentation only." A learner playing Black against the AI who wants to
see the position the way a book prints it has no other route, and the accepted contract already establishes
that flipping is free of consequence. Denying it is defensible only on chrome-budget grounds, which is a
layout argument the open layout questions have not settled either way.

---

### 20. A store that cannot accept a write leaves the user with no way to start a game

**Severity: gap**, and partly a product-owner decision rather than a defect.

Quoted, `product.md:47`: "**Before starting another game, the user must save the active game to History.**"
Quoted, `interaction-design.md:317`: "If persistence fails, the old active game remains unchanged, the selected
pre-start state does not open, and no new game is created", with **取消** and **重试**.

On a full disk both branches are closed: the archive cannot commit, so the user cannot start a new game, and
there is no accepted way to abandon an active game without archiving it. The app becomes read-only with no
explanation of why, and the only accepted message — **当前对局仍然保留。请重试。** — invites a retry that will
keep failing.

**Exact correction (owner's choice, framed).** Option A: leave the behaviour as accepted and improve nothing;
the disk-full user is stuck but their data is intact. Option B: extend the **无法保存对局** presentation with a
third action on repeated failure that discards the active game **without** archiving it — cheap to build,
directly contradicts the accepted "must save" rule, and risks a user losing a game they wanted. Option C:
recognise the store-full condition specifically (`MXQ_DOMAIN_STORE` already distinguishes "full" from "I/O" at
`core-interface.md:198`) and say so in the message, so the user knows to free space. I recommend C alone: it
keeps the accepted rule, needs no new capability, and turns an unexplained dead end into an actionable one.

---

## Two structural observations that are not findings

- **`testing.md` declares itself entirely non-normative** — quoted, `:5`: "Nothing in this document is
  normative until its status or an individual section is explicitly marked accepted" — and no section is so
  marked. It is nevertheless the most detailed statement of several flows, and the build gate list at `:194`
  is what an internal release would be judged against. Nothing in it *contradicted* the other seven documents
  in this audit, which is a good sign for the set's coherence; but a reader should not treat its detail as
  accepted behaviour, and several of the corrections above need matching lines added there.
- **The declared open questions are honest but narrower than the states they name.** Both
  `interaction-design.md:526` and `engine-integration.md:194` scope the mid-game engine hole to "after the app
  was suspended", and `interaction-design.md:537` defers "empty, loading, AI-thinking, error, corrupted-import,
  and destructive-action states" — a list broad enough to sound like coverage while leaving Findings 1, 5, 6, 9
  and 11 outside it. A **Need to discuss** entry authorises nothing; where one exists, I ranked the finding
  lower but did not drop it.

## Ranking summary

| # | Finding | Severity | Likelihood a real user reaches it |
|---|---|---|---|
| 1 | Turn status undefined in a terminal state | contradiction | every game |
| 2 | AI preparation on the first reply after resume: no presentation, failure after a committed move | gap | every resumed AI game |
| 3 | AI reply may commit behind a blocking presentation | gap | common |
| 4 | Play destination ↔ board navigation, and the AI during it | gap | common |
| 5 | Resign has no interaction design at all | gap | common |
| 6 | Unconfirmed result across relaunch | gap | common |
| 7 | 可判和 affordance lifetime | gap + ambiguity | common in learner play |
| 8 | Imported human-versus-AI replay orientation | contradiction | first shared AI game |
| 9 | Creation-failure error copy | gap | uncommon; both accepted messages would lie |
| 10 | Engine failures other than low memory | contradiction + gap | uncommon; total when hit |
| 11 | Core cannot start | gap | uncommon; total when hit |
| 12 | Engine never released when unneeded | gap | every session, invisible until jetsam |
| 13 | Unbounded silent retry of the AI's save | gap | rare; unbounded loop |
| 14 | Leaving a pre-start state; "Play start state" undefined | gap + ambiguity | common |
| 15 | 回放 from the recorded card has no way back | gap | every completed game where it is tapped |
| 16 | Input during an unconfirmed perpetual-violation result | ambiguity | moderate |
| 17 | Opening a `.mxq` file from outside the app | gap | likely for internal testers |
| 18 | Undo during the compose beat | gap | occasional |
| 19 | Flip Board in human-versus-AI play | ambiguity | moderate |
| 20 | Store-full deadlock | gap + owner decision | rare |
