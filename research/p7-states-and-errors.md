# Part 7 — p7-states: every remaining app state and error presentation

Workspace research draft. Not a contract, not a diff, and not authorization. The main thread authors all
contract text. Nothing under `MiniXiangqi/` was read for anything but reading, and nothing was written there.

**Area.** `interaction-design.md:525` (insufficient-memory notice: presentation, repeated failure,
accessibility announcement), `:526` (what a player sees when the engine cannot be re-prepared mid-game),
`:537` (empty, loading, AI-thinking, error, corrupted-import, destructive-action states), and — assigned here
by the survey's nine-way split, item #5 — the AI-thinking indicator's **form**, which is the first clause of
`interaction-design.md:523`.

**Explicitly not this area.** The History list's own layout and the import flow's placement and pickers
(7.1/7.2, survey slot #4); Help (7.6); the board's VoiceOver model (8.1); and everything inside open PR #23 —
the resignation confirmation, the play-control cluster, the result card's placement, the move list in the
stacked layout, and the minimum window size. Where this report's design touches those, it stops at the
boundary and says so.

---

## Method, and what each claim rests on

| Kind | What I did |
|---|---|
| **Executed** | Read all eight contracts in `MiniXiangqi/docs/` in full. Ran `gh pr list --state all` under the `ppppvz` identity (read-only, after sourcing `activate.zsh`): PRs #13–#22, #24 and #25 are **MERGED**; **#23 is the only open design PR**. Ran `grep` over `docs/*.md` to enumerate every accepted Chinese string (58 distinct) and every place a contract says "presents an error" without saying what it is. Ran six `mcp__xcode__DocumentationSearch` queries against the pinned Xcode 27 beta documentation. |
| **Read in a cited source** | Every HIG and API quotation below carries its page and section. Every contract claim carries a `file:line`. |
| **Reasoned** | Every recommendation. Where a number is ours rather than Apple's or the contract's, I say so at the number. |
| **Not measured** | Nothing was run on a device or in a simulator. Every duration I propose that is not already accepted is a first-version value in the same sense as `interaction-design.md:432`, and I mark it. |

---

## 0. What I found that nobody has listed as open

Six gaps, in the same register as the survey's §0.6 and §0.7. Each is a place where an accepted contract
requires a user-visible behaviour and does not define it, or names a path that does not exist.

**0.1 — `engine-integration.md:154` routes a damaged installation to a path that does not exist, and the
nearest accepted path gives wrong advice.** The accepted network-failure policy says a runtime hash
verification failure "means a damaged installation," that "**the AI does not start**," and that "the frontend
reports it through the accepted engine-unavailable path." There is no accepted engine-unavailable path. The
only accepted engine notice is **无法启动 AI 对手 / 当前可用内存不足。请尝试关闭一些其他 App，然后重试。**
(`interaction-design.md:283–284`), and `engine-integration.md:112` reuses it for *allocation failure at a
valid budget* — a memory condition — explicitly because "the situation the user is in is the same one." A
damaged installation is **not** the same situation: closing other apps cannot fix it, and retrying cannot
succeed. Telling that user to close apps and retry is an instruction that provably will not work. §4.4 below
proposes the missing copy. Whoever fixes it must also correct `engine-integration.md:154`'s dangling
reference.

**0.2 — the accepted save-failure capsule is "transient" and has no duration.** `interaction-design.md:257`
accepts a transient capsule reading **无法保存这一步，请重试。**, and `testing.md:184` gates its content, but no
contract says how long it stays or how it leaves. It is also the app's only time-boxed element, against which
Apple advises: *HIG > Accessibility > Cognitive* — "**Minimize use of time-boxed interface elements.** Views
and controls that auto-dismiss on a timer can be problematic for people who need longer to process
information, and for people who use assistive technologies that require more time to traverse the interface.
Prefer dismissing views with an explicit action." §7.2 proposes a duration and the accessibility route that
makes the time box safe.

**0.3 — a failed deletion has an accepted requirement and no copy.** `interaction-design.md:382`: "If
persistence fails, the record remains and the app presents an error." No title, no message, no actions. §8.2.

**0.4 — a failed game creation has an accepted requirement and no copy or presentation.**
`interaction-design.md:198` ("shows the applicable error") and `:207` ("presents an error"). The memory case
has accepted copy; the *persistence* case has none, and neither line says whether the error is an alert, an
inline line, or something else. §6.2.

**0.5 — a store that cannot be opened at all is designed nowhere.** `game-data.md:161` accepts that "a store
written by a newer build is refused rather than opened," and `core-interface.md:198` reserves
`MXQ_DOMAIN_STORE` codes for corruption and `schema too new`. This is the one failure with nothing to fall
back to: there is no active game to leave alone, no History to browse, and no board to look at. No contract
says what the user sees. §6.3, and one owner question.

**0.6 — the accepted Reduce Motion rule has never been applied to a system activity indicator.**
`interaction-design.md:428`: "Anything that animates position, scale, or rotation becomes a crossfade of at
most 120 ms," and "a repeating attention-grabbing animation is precisely what this setting exists to spare the
people who enable it." A system indeterminate activity indicator **rotates, continuously, forever**. Under the
accepted rule as written it cannot be shown under Reduce Motion. §5.4 resolves this the way the contract
already resolves the check pulse, and flags the clarification the contract needs.

---

## 1. One rule that generates the rest: the error-presentation ladder

The app already has four distinct accepted ways of reporting that something went wrong, and no rule that says
which to use. Reconstructing the rule from the accepted cases makes every undesigned case fall out, and makes
each new one checkable rather than argued.

Two facts select the rung: **did the user's committed state change or fail to change**, and **does the app
need a decision from the user**.

| Rung | Surface | Used when | Accepted instances |
|---|---|---|---|
| **0** | *nothing at all* | The failure is the app's own to retry and the user owes nothing. | A failed save of the AI's reply — `interaction-design.md:229`, `:257` |
| **1** | Transient capsule on the turn status | One ply failed, the state is unchanged, and the retry is simply repeating the gesture already made. No decision, so no dismissal. | **无法保存这一步，请重试。** — `:257` |
| **2** | Inline, non-modal text attached to the control that failed | The failure happened inside a page the user is standing on, and the retry *is* that page's own primary button. | *(none accepted; §6.2 proposes it for creation failure)* |
| **3** | System alert, two actions | The user cannot simply repeat the gesture they made, **or** the operation was a whole-game commit, **or** the remedy is outside the app. | **无法保存对局** `:319`; **无法启动 AI 对手** `:283` |
| **4** | Persistent inline state on the turn status | The condition is not a moment but a **state**, and lasts until something changes. An alert cannot express it, because dismissing an alert leaves no trace. | *(none accepted; §4 proposes it for mid-game engine unavailability)* |

Three rules govern the ladder:

- **One rung per failure.** No failure is reported twice, and none escalates from one rung to another.
- **Rungs 1, 2 and 4 carry no material.** `interaction-design.md:38` fixes exactly three custom glass surfaces
  — the play control cluster, the replay transport, and the shared result-card/threefold slot — and says
  system alerts and sheets are "additional and automatic". A rung-3 alert is therefore materially free. Rungs
  1, 2 and 4 are **text and controls drawn on surfaces that already exist**: the turn status is not one of the
  three, and neither is the pre-start page. Adding a line of text and a button to an existing element creates
  no fourth glass surface. This is the constraint that decides most of the presentation questions below, and
  every proposal in this report satisfies it by construction.
- **Rung 4 is new vocabulary and is used exactly once**, for §4. If a second candidate ever appears, that is a
  signal to re-examine, not to generalise.

---

## 2. One threshold, used everywhere: 500 ms

`interaction-design.md:424` already accepts a number for exactly this question: "If the search has not
returned within 500 ms of the player's move, the turn status shows AI activity; below that threshold nothing
appears, because an indicator that flashes for a fifth of a second is noise."

**Proposal: that sentence's threshold becomes the app's single rule for every indeterminate wait.**

> No progress indication is shown for an operation that completes within 500 ms. At 500 ms, the control that
> started the operation adopts an in-progress appearance. Nothing else on screen changes, and no operation
> ever blocks the whole window.

Everything the app can wait on is covered: AI search (accepted), engine preparation, game creation, store
open at launch, import validation, export, deletion, pin, and archive-and-clear. Reusing the accepted number
means the app has one figure a reviewer can check rather than a family of them, and it means the AI-thinking
indicator is not a special case but the first instance of a rule.

Two supporting rules, both ours:

- **No operation blocks the whole window.** Every operation in this app is either invalidatable (game
  creation, per `game-data.md:94`) or atomic and recoverable (every store transaction, per `game-data.md:68`).
  A full-window blocking overlay would buy nothing and would break the accepted rule that the board is never
  dimmed (`interaction-design.md:258`).
- **No automatic retries, no back-off timers, and no auto-dismissing progress.** Grounded in *HIG >
  Accessibility > Cognitive*, quoted at §0.2. The one exception is the accepted re-preparation rule
  (`engine-integration.md:72`), which fires when a search is owed — that is the contract firing, not a timer.

*HIG > Progress indicators > Best practices* says "**When possible, use a determinate progress indicator.**"
Only one wait in this app has a known duration — the AI search, whose `movetime` is frozen at game creation.
§5.3 explains why it is nevertheless indeterminate, and that is the only place the HIG preference is
knowingly declined.

---

## 3. The insufficient-memory notice (7.3 — `interaction-design.md:525`)

Accepted and unchanged: the copy (`:283–284`), both actions, that **取消** creates or changes nothing and
leaves the draft alive, that **重试** obtains a fresh probe rather than a cached value, that no smaller Hash
and no cleanup pass is attempted, that any game being resumed stays saved, and that the notice promises
nothing about the operating system (`:286–290`). `engine-integration.md:112` adds the second trigger:
allocation failure at a valid budget reuses this notice unchanged.

### 3.1 Presentation: a system alert, on every platform

**Recommendation: rung 3 — the platform's standard modal alert, attached to the app's one window.**

Three reasons, in order of strength.

1. **The accepted copy is already alert-shaped.** It was accepted as a *title*, a *message*, and *two
   actions*. That is precisely the structure *HIG > Alerts > Content* describes: "In all platforms, alerts
   display a title, optional informative text, and up to three buttons." Rendering it as anything else would
   either discard the title or invent a non-standard block for a shape the system already provides.
2. **The remedy is outside the app.** The message asks the user to close other apps. That is rung 3's own
   criterion. *HIG > Feedback > Best practices*: "**Use alerts to deliver critical — and ideally actionable —
   information.** By design, alerts disrupt the current context, so you need to match the importance of the
   information to the level of interruption." An AI opponent that cannot start, with an action the user can
   take, is exactly critical and actionable.
3. **It is materially free**, per `interaction-design.md:38`, whereas any custom inline surface would have to
   justify itself against the three-surface budget.

Concrete, and checkable against a screenshot:

- **重试** is the default action; **取消** takes the cancel role. Return activates 重试, Escape activates 取消.
  Neither is destructive; the destructive role is reserved (`:44`).
- On macOS the alert is a **window-modal sheet**, not an app-modal panel, because the app has one main window
  (`product.md:26`).
- On Windows the equivalent is the platform's standard modal content dialog. The exact WinUI 3 control is the
  Windows frontend's to name when it exists (`interaction-design.md:536`); what this contract fixes is that it
  is the platform's standard alert equivalent and not a recreated Apple panel (`:32`).
- The alert's presence is what enforces the accepted single-flight rule on **开始对局** while it is up.

### 3.2 The two retries are the same operation, and Random re-draws

Worth stating because it is currently implicit and looks like a contradiction. `interaction-design.md:198`
says a failure "re-enables **开始对局**", while the notice itself offers **重试**. These are not two different
operations: both repeat the accepted `prepare → resolve → create → search` sequence from step 1
(`engine-integration.md:79`). One consequence follows and should be written down, because a user will
otherwise be surprised: with **随机** selected, **每次重试都会重新抽取先后手** — accepted at
`engine-integration.md:82` ("a resolved side never survives a failed creation and a retry draws again"), but
never surfaced as something the interface implies.

### 3.3 Repeated failure: the alert stays, the emphasis moves once, and nothing is ever locked

The requirement is that repeated failure must not become a loop the user cannot escape. Structurally it
already is not one — **取消** at pre-start returns the user to a live setup page with their draft intact
(`:286`). What is missing is *information*: after several identical failures the user has no new fact and no
reason to expect a different outcome, and the notice is forbidden from promising one (`:290`).

**Proposal, in three parts. None of them changes an accepted string.**

1. **A failure streak counter**, scoped to the pre-start session. It is reset by: leaving the pre-start page,
   any successful preparation, and the app returning to the foreground — the last because closing other apps
   is the one action that plausibly changes the answer, and it necessarily takes the user out of the app.
2. **Streaks 1 and 2:** the alert exactly as accepted, with **重试** as the default action.
3. **Streak 3 and beyond:** the same alert, the same title, the same message, the same two actions — but
   **取消 becomes the default action and 重试 loses default emphasis**. The app stops steering the user into a
   fourth identical attempt without ever taking the attempt away from them.

Explicitly forbidden, and worth writing into the contract as prohibitions because each is the obvious thing a
future implementer would reach for:

- **重试 is never disabled**, never rate-limited, and never hidden.
- **No back-off delay** and **no automatic retry**. A retry happens only when the user asks.
- **No auto-dismissal of the alert.** *HIG > Accessibility > Cognitive*, quoted at §0.2.
- **No progressive disclosure of technical detail** — no byte counts, no "needed 256 MiB, had 190 MiB". The
  user cannot act differently on the number, and `core-interface.md:209` already fixes that `MxqError` detail
  strings are "short English diagnostics, never localized copy".

An alternative — a **third** alert action appearing at streak 3, offering a way forward that does not need the
engine at all — is a product decision, not a presentation one, and is framed as **Owner question 1**.

### 3.4 The retry is where the accessibility gap actually is

The alert's *appearance* needs no announcement. On Apple platforms the system moves VoiceOver focus into a
presented alert and reads title, then message, then buttons. Posting an
`AccessibilityNotification.Announcement` as well would double-speak.

The gap is the **retry**. Press **重试**, the probe runs, the budget is still below 256 MiB, and — if the
alert is kept on screen rather than dismissed and re-presented — *nothing changes*. A sighted user sees the
alert not go away. A VoiceOver user gets silence, having explicitly asked for an outcome.

**Proposal:**

- The alert is **not dismissed and re-presented** on retry. It remains, and the retry runs behind it. (If it
  were dismissed and re-presented, the system would re-read the whole alert and no announcement would be
  needed — but the flicker is worse, and focus would be thrown.)
- **重试 is single-flight** while an attempt is outstanding; **取消 stays live** throughout and uses the
  accepted invalidation path (`engine-integration.md:86`), so a late success releases whatever it prepared
  rather than committing a game.
- If the attempt has not resolved within **500 ms** (§2), 重试's label is replaced by an activity indicator at
  the label's size, the button keeps its own size so the alert does not reflow, and the alert's layout is
  otherwise untouched. Below-minimum failures are pure arithmetic on a fresh probe and will normally fall
  under the threshold — `core-interface.md:129` fixes that `mxq_engine_prepare` "refuses below the 256 MiB
  minimum with `MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY` **without initializing anything**". The allocation-failure
  trigger, which attempts up to 4 GiB, will not. *(Reasoned, not measured.)*
- **On a failed retry, post an announcement** carrying the outcome, at high priority. Apple's
  `AccessibilityNotification.Announcement` documentation shows exactly this pattern —
  `AccessibilityNotification.Announcement(highPriorityAnnouncement).post()` with
  `accessibilitySpeechAnnouncementPriority = .high` — and `UIAccessibilityPriority > Choosing a priority`
  defines `high` as "A high-priority announcement that interrupts other speech and isn't interruptible after
  it starts." High is right here because the announcement reports the result of an action the user explicitly
  took and must not be swallowed by the alert's own re-read of a focused button.
- **On a successful retry**, the alert dismisses and creation proceeds; the system's own focus change plus the
  game-start announcement (8.1's) cover it, and no extra announcement is posted.
- The streak-3 emphasis change is **not** announced. VoiceOver reads button order and default emphasis when
  the user reaches the buttons; announcing a button-order change would be noise.

---

## 4. The engine cannot be re-prepared mid-game (7.4 — `interaction-design.md:526`, `engine-integration.md:194`)

The situation, entirely from accepted text: the app was suspended, so any search was cancelled and the
transposition table released (`engine-integration.md:67`). On resume, the committed status reports the AI to
move with a search expected, so a search **is** owed and re-preparation runs (`:72`). It fails. "The game
remains active, saved, and resumable, with the AI unable to move until preparation succeeds" (`:73`). Both
contracts already record that the accepted notice does not fit, "whose wording and its **取消** action assume a
game that has not started."

### 4.1 It is a state, not an event — so it is not an alert

This is the decisive observation, and it decides the whole design.

The condition **persists**. It lasts until a preparation succeeds, which may be never. An alert cannot express
a persistent condition: whatever the user chooses, the alert goes away, and a dismissed alert leaves the user
in front of a board that silently does nothing on the AI's turn with no record of why. That is worse than
saying nothing.

Apple's guidance points the same way. *HIG > Feedback > Best practices*: "**Consider integrating status
feedback into your interface.** When status feedback is available near the items it describes, people get
important information without having to take action or leave their current context." And the same page's
warning about matching interruption to importance argues against an alert here for a second reason: the game
is not lost and nothing is destroyed. The user may legitimately want to study the position, undo, look at
History, or change a Setting. An alert forbids all of that to force a decision they may not want to make.

**So: rung 4 — a persistent inline state on the turn-status element.**

### 4.2 Why the turn status is the correct element, from accepted text alone

Four accepted sentences converge on it, which is unusually strong evidence that this is the intended home
rather than a convenient one:

- `:238` — "Anything the interface must say that is not a fact about the position — that a save failed, that
  input is unavailable right now — is said by the turn-status element instead, so the board is never read for
  two kinds of information at once." *"The AI cannot move"* is precisely a not-a-fact-about-the-position.
- `:269` — "AI thinking is shown as activity attached to the AI's turn; it does not replace or compete with
  the side-to-move line." The unavailable state is the **same slot in the same element**, with a different
  occupant. No new vocabulary.
- `:271` — the **将军** token establishes that a token accompanying the side-to-move line is accepted
  vocabulary.
- `:38` — the turn status is not one of the three custom glass surfaces, so nothing added to it can create a
  fourth. `:42` already says the AI-thinking indicator "carries no material at all"; its replacement inherits
  that.

And one accepted rule then works *unchanged* because of this choice: `:258` says an acknowledgment beat
answers unavailable input, and "the reason input is unavailable is always already on screen, so the beat
points at it rather than repeating it." Put the reason on the turn status and that sentence is true here
without amendment. Put it in an alert and it becomes false the moment the alert is dismissed.

### 4.3 The state, exactly

```
轮到黑方                      ← accepted, unchanged (:268)
AI · AI 暂时无法走子           ← accepted controller label (:269) + NEW state name
当前可用内存不足。请尝试关闭一些其他 App，然后重试。   ← ACCEPTED verbatim (:284)
                    [ 重试 ]  ← ACCEPTED string (:285), reused as a control
```

**The whole state needs exactly one new Chinese string.** The explanatory line is the accepted memory message
reused word for word, because the user is in literally the same situation the accepted message was written
for — the same argument `engine-integration.md:112` already makes when it reuses the whole notice for
allocation failure. The action reuses the accepted **重试**.

Behaviour:

- **One automatic attempt, on each occasion a search becomes owed.** This is the accepted rule
  (`engine-integration.md:72`) firing, not a new behaviour, and it means the common real recovery — the user
  closes other apps and comes back — works without their having to find the button. Returning to the
  foreground with a search still owed is such an occasion.
- **No automatic retries otherwise.** No timer, no polling. There is no signal to poll on, and a status that
  flickers between "thinking" and "unavailable" every few seconds is worse than a static one.
- **重试 is single-flight** and, if the attempt passes 500 ms, its label becomes an activity indicator at the
  label's size (§2).
- **During re-preparation the state shows the ordinary thinking treatment** (§5) rather than a third
  "preparing" state. From the user's side the AI is about to move; the difference between preparing and
  searching is an implementation detail they cannot act on differently, and a second label would be a
  distinction without a decision. *(Named honestly: this means 思考中 is shown while the engine is loading
  rather than searching. The alternative — a separate 准备中 label — is a second string for no available
  action, and I recommend against it.)*
- **The board is never dimmed** (`:258`), unchanged. **Board input is refused** with the accepted
  acknowledgment beat (`:258`), unchanged, and it now points at a reason that is genuinely on screen.

### 4.4 The second failure class: a damaged installation

Gap 0.1. If re-preparation fails for an engine-domain reason that is **not** memory —
`MXQ_DOMAIN_ENGINE`'s asset missing / mismatch, variant load failure, or faulted (`core-interface.md:200`) —
then "close other apps and retry" is advice that cannot work, and 重试 is a button that cannot succeed.

**Proposal: the same state, the same state name, a different explanatory line, and no 重试.**

```
轮到黑方
AI · AI 暂时无法走子
AI 组件已损坏。重新安装应用可以恢复。        ← NEW
```

`engine-integration.md:156` is the source of the remedy: "reinstalling restores the AI." The same copy fills
the dangling reference at `engine-integration.md:154` and, at game creation, fills the pre-start case: the
accepted title **无法启动 AI 对手** is reused (it is accurate for both classes), the message is this new line,
and — because retrying is pointless — the alert has a single dismissing action.

There is a cost in that remedy that the contract has not noticed, and it is **Owner question 5**: on iOS and
iPadOS, deleting the app deletes its container, so "reinstall the app" destroys every History record the user
has not exported.

### 4.5 The exits, enumerated — and why the state offers only one of them

The state's own affordance is **重试** and nothing else. Every other exit is the app's ordinary furniture and
must be verified to still work, because each is engine-independent:

| Exit | Still available? | Consequence |
|---|---|---|
| **重试** | yes, the state's own action | The only exit that preserves the game as what it is |
| **悔棋** (Undo) | yes — `undo_available` is core-derived (`core-interface.md:101`) and never consults the engine | Removes the human move that owes the reply (`:328`), returning the turn to the human. Does not unstick the game: the next human move owes a reply again. |
| **保存并继续** / selecting a new mode | yes — `mxq_store_archive_and_clear`, engine-independent | Archives as **ended early**, no competitive result (`:309`) |
| Resignation | technically available; **deliberately not offered here** | Records a human loss (`product.md:40`). Steering a user toward it because the app cannot start its own opponent would falsify the record. |
| History, replay, Settings, Help | yes | Unaffected |

The state does **not** duplicate any of them. Adding an "end this game" button inside the status would
duplicate the mode entries' accepted classification through a second path, and adding a mode conversion is not
a UI affordance at all — see **Owner question 2**.

### 4.6 Accessibility

- **On entering the state, announce it once**, at `.default` priority — *UIAccessibilityPriority*: "A
  default-priority announcement that interrupts existing speech, but is interruptible if a new speech
  utterance starts." Default rather than high, because this is a persistent state the user can re-read from
  the turn status at any time, not a one-shot result. The announcement text is the state name plus the
  explanatory line — no new string.
- **Never re-announce it.** A state that re-announces on every focus change or every refused tap is
  unusable.
- The turn-status element carries the state in its accessibility **value**, so it is readable on demand, and
  takes the `updatesFrequently` trait so assistive technology does not try to speak every change to it.
- **重试** is a plain button in the element and needs no custom action.
- The full announcement set, its ordering against the announcements already required by name at `:247`,
  `:218`, `:386` and `:249`, and the exact label/value/hint split all belong to **8.1**, which owns the
  model. This section supplies the content and the trigger, not the model.

### 4.7 One consequence for the still-open layout item

This state makes the turn status **two lines plus a control**, where ordinary play makes it one line plus a
small indicator. That is a real budget item for `interaction-design.md:515–516`, which are still open, and it
must be recorded as an input to them rather than solved here: the stacked layout has to absorb the taller
status without driving the board below its accepted 44 pt floor (`:480`). Whoever fixes the layout bounds
needs this state in the inventory; today it is not in anyone's.

### 4.8 The duplicate must be deleted

Fixing this item removes `interaction-design.md:526` **and** `engine-integration.md:194`. The engine document
already routes the question away ("this belongs to `interaction-design.md`"); leaving the routing note behind
after the destination is written would leave the register showing an open item that is closed.

---

## 5. The AI-thinking state, and the indicator's form (`interaction-design.md:523`, first clause)

Accepted and not reopened: activity is attached to the AI's turn and does not replace or compete with the
side-to-move line (`:269`); the board is **never** dimmed (`:258`); board input is disabled (`:274`); the
indicator carries **no material at all** (`:42`); it appears only once the search passes 500 ms after the
player's move (`:424`); the AI's piece departs no earlier than the 260 ms compose-beat floor (`:424`); and
activity must not be communicated by colour alone (`:277`).

### 5.1 Form

```
轮到黑方
AI · 思考中  ◌          ← accepted label (:269) + NEW word + system activity indicator
```

- The **secondary controller label** becomes the accepted **AI** joined to a new **思考中** by the same
  middle-dot the accepted metadata patterns use (`人机对弈 · 你执红`, `:305`). The word carries the state in
  text, satisfying `:277`.
- **Trailing it**, the platform's standard small indeterminate activity indicator, at the label's line
  height, in the label's own colour. Not board marker ink — marker ink belongs to the board (`:143`) and this
  is not a board marker.
- **No material**, per `:42`, and nothing here is one of the three glass surfaces.
- **The space is reserved.** The element's height and the label's baseline are identical whether the indicator
  is present or absent, so the status does not grow by a line every AI turn and the board does not shift under
  it in the stacked layout. This is checkable against two screenshots and is the requirement most likely to be
  missed.
- **Appearance:** at the accepted 500 ms threshold, fading in over 120 ms. **Disappearance:** at the instant
  the AI's piece departs — that is, at the compose-beat instant defined by `:424`, not at search return — so
  the label never blinks off and leaves a gap before the move begins.

Exact geometry and placement within the element are deliberately not fixed here: the turn status's own layout
and its placement in the side-by-side panel are `interaction-design.md:523`'s remaining clauses and PR #23's
territory.

### 5.2 Why *思考中* and not a bare spinner

*HIG > Progress indicators > Best practices*: "**If it's helpful, display a description that provides
additional context for the task.** Be accurate and succinct. Avoid vague terms like *loading* or
*authenticating* because they seldom add value." 思考中 names the actor and the activity in a domain the user
already understands — it is the opposite of a vague term. It is also what makes the state survive Reduce
Motion (§5.4) and what a VoiceOver user reads.

### 5.3 Why indeterminate, when the duration is known

This is the one place the HIG's stated preference is knowingly declined, so the reason should be on the
record.

The wait **is** known: every level is a fixed `movetime` — 1000, 3000 or 5000 ms — frozen into the game at
creation (`engine-integration.md:96–100`, `game-data.md:38`). *HIG > Progress indicators > Best practices*:
"**When possible, use a determinate progress indicator.** An indeterminate progress indicator shows that a
process is occurring, but it doesn't help people estimate how long a task will take." By that rule a
determinate bar or filling ring is available and is what Apple would prefer.

**Recommendation: indeterminate anyway**, for three reasons, the first of which is the contract's own:

1. `interaction-design.md:258` — "the pause while the AI thinks is exactly when a learner wants to study the
   position." A filling bar is an animation whose entire purpose is to be watched. It would compete for the
   eye with the board, in the one state the contract explicitly protects for looking at the board.
2. A determinate indicator makes a **promise the engine can miss in both directions**: `go movetime` may
   return early on a forced or mated line, and may overrun by a small margin. HIG on the same page warns that
   an uneven pace "can make people wonder if your app is still working and can even feel deceptive."
3. It would have to appear already part-filled — at 500 ms of a 3000 ms search, at 17% — or animate a
   catch-up, neither of which is honest or quiet.

If the owner disagrees, the determinate variant is cheap and well-defined: fill from 0 to 1 over
`ai_movetime_ms` from search start, clamp at 1, never restart, and hold at 1 until the move departs. I do not
recommend it.

### 5.4 Reduce Motion — gap 0.6, and how the contract already answers it

A system indeterminate indicator rotates continuously. `interaction-design.md:428` says anything animating
rotation becomes a crossfade of at most 120 ms, and that a repeating attention-grabbing animation "is
precisely what this setting exists to spare the people who enable it." Taken literally, the indicator cannot
run under Reduce Motion.

**The contract already contains the answer, in the check pulse.** `:428`: "The check pulse is removed rather
than converted… check is a persistent treatment plus a pulse, so the double ring and the **将军** token still
say everything the pulse said." The identical structure applies:

> **Under Reduce Motion the activity indicator is not drawn at all. 思考中 carries the state alone.** The
> state survives; only its animation is removed. This is the same resolution the accepted rule already applies
> to the check pulse, and it is why the state needed a word in the first place.

The cost is real and should be named: a Reduce Motion user sees a static label and cannot distinguish "still
searching" from "stalled". The mitigation is structural rather than cosmetic — the label exists **only** while
a search is genuinely outstanding, and it disappears at the instant the piece departs, so a stalled search
would present as a label that never goes away, which is a bug rather than an ambiguity.

The contract needs one clarifying sentence saying that the Reduce Motion rule reaches system-provided
indicators, because today a reader would reasonably assume the rule is about board pieces.

### 5.5 Accessibility: deliberately silent

**No announcement is posted when the AI begins thinking.** A human-versus-AI game has dozens of AI turns; an
announcement per turn would be intolerable, and *HIG > Accessibility > Cognitive* is about exactly this kind
of load. The state lives in the turn status's accessibility value and is read on demand.

The one announcement this moment needs is the AI's **completed move**, which `:247` already requires by name
("whose it was is carried by the turn status and the accessibility announcement") and which belongs to 8.1.

---

## 6. Loading states

### 6.1 Game creation

Accepted: **开始对局** cannot be invoked twice while creation is in progress, and leaving invalidates the
attempt (`:197`, `:206`, `game-data.md:94`). The appearance is undefined.

**Proposal, needing no new string:** at 500 ms (§2), **开始对局**'s label is replaced by an activity indicator
at the label's size. The button keeps its own frame, so nothing reflows. The button is non-invocable; the
rest of the page stays interactive so the user can still leave, which the accepted rule already handles. No
blocking overlay, no dimming, no cancel button — leaving *is* the cancel.

Two things worth recording:

- **The tint count is preserved.** `:44` fixes that **开始对局** is the one tinted element in the pre-start
  state and that at most one tinted element is ever visible. Replacing the label inside the button keeps the
  tint on exactly one element.
- **This state is ordinary, not exceptional.** Creation prepares the engine: a Hash allocation of up to 4 GiB,
  a 4,333,499-byte NNUE load, and a preflight of the engine's effective NNUE state
  (`engine-integration.md:135`, `:149`). *Reasoned, not measured:* that will frequently exceed 500 ms, so this
  is a state most users see on most games, and it deserves to be designed rather than treated as an edge case.
  Measuring it is a `testing.md` item, not a design one.

### 6.2 Creation failure — gap 0.4

The **memory** failure is rung 3 (§3). The **persistence** failure (`interaction-design.md:198`, `:207`) is
different in kind: the user is standing on the page, the retry is that page's own primary button, and the
remedy is nothing more than trying again.

**Proposal: rung 2 — an inline line beneath 开始对局**, reading **无法创建对局，请重试。** (new). Plain text
with the platform's standard error styling and its standard symbol; **no material**, so no fourth glass
surface; the pre-start preview yields space to it, which `testing.md:59` already requires ("Verify the
pre-start preview shrinks as needed so the setup controls always fit, **including when a creation-failure
error is shown**" — the test exists, the design it tests does not). The line clears on the next attempt and
when the user leaves.

Not an alert: an alert here would present a **重试** button one finger-width from an identical **开始对局**
button, which is the redundancy rung 2 exists to avoid.

### 6.3 Launch, and the store — gap 0.5

*HIG > Launching > Best practices*: "**Launch instantly.**" "**Restore the previous state when your app
restarts so people can continue where they left off.**" *HIG > Launching > Launch screens*: "**Downplay the
launch experience.** A launch screen isn't part of an onboarding experience or a splash screen, and it isn't
an opportunity for artistic expression." "**Design a launch screen that's nearly identical to the first screen
of your app or game.**" "**Avoid including text on your launch screen**… Because the content in a launch
screen doesn't change, any text you display won't be localized." (The last point matters directly: this app
has two languages and its own localization contract at `:455`.)

**Proposal:**

- The iOS and iPadOS launch screen is the Play destination's own empty chrome — the navigation container and
  the board's area — in the current appearance mode and orientation. **No text, no logo, no splash screen.**
  The app has no onboarding flow, and *HIG > Launching* places a splash screen at the beginning of one.
- macOS opens the window on the same skeleton; *HIG > Launching* — "macOS, visionOS, and watchOS don't require
  launch screens."
- The store opening and the active game resuming happen behind it. If restoration passes 500 ms, the Play
  destination shows its own in-progress treatment rather than the launch screen persisting.
- **If the store cannot be opened at all**, the app cannot function and there is nothing behind an alert to
  return to. The presentation is therefore a **full-destination state**, not an alert — on Apple platforms the
  platform's content-unavailable presentation (`ContentUnavailableView(label:description:actions:)`, confirmed
  in the SwiftUI documentation). Two classes, and the split is not optional:
  - **Schema too new** (`game-data.md:161`: "a store written by a newer build is refused rather than
    opened"): **无法打开数据** / **这些数据由更新版本的应用创建。请更新到最新版本。** The accepted archive
    rule (`game-data.md:64`) already mandates "a distinct created-by-a-newer-version message that **is never
    presented as corruption**" for *files*; the store deserves the same treatment and no contract says so.
    That inconsistency is worth fixing in the same change.
  - **Corruption or I/O**: **无法打开数据** / **应用数据无法读取。** plus a remedy sentence that is **Owner
    question 4**, because every honest remedy has a data cost.

### 6.4 Import validation, and every other store operation

- **Import** has an accepted validation budget of **two seconds on the slowest supported device**
  (`game-data.md:62`), so it crosses the threshold routinely. Same rule: single-flight, in-progress at 500 ms
  on the invoking affordance, the file picker already dismissed. The affordance's placement is 7.2's.
- **Delete, pin, export, archive-and-clear** are single-row transactions and will normally fall under the
  threshold; the rule covers them without a special case. Deletion is the one where the row disappears on
  success, so an in-progress treatment on the row matters if it is slow.
- **No operation gets a determinate indicator**, including import — the two-second figure is a budget ceiling,
  not a prediction, and *HIG > Progress indicators* warns specifically against a deceptive pace.

---

## 7. Error states — the collected inventory

### 7.1 The full map, after this report

| Failure | Rung | Surface | Copy | Status |
|---|---|---|---|---|
| AI reply's save fails | 0 | nothing | — | accepted `:229`, `:257` |
| User's move or Undo save fails | 1 | turn-status capsule | **无法保存这一步，请重试。** | accepted `:257`; duration proposed §7.2 |
| Input refused | — | acknowledgment beat | — | accepted `:258` |
| Game creation — persistence | 2 | inline under 开始对局 | **无法创建对局，请重试。** | **new**, §6.2 |
| Game creation — memory | 3 | alert | accepted `:283–284` | accepted; presentation §3.1 |
| Game creation — damaged assets | 3 | alert | **无法启动 AI 对手** + **AI 组件已损坏。重新安装应用可以恢复。** | **new**, §4.4 |
| Archive-and-clear, terminal commit | 3 | alert | accepted `:319–321` | accepted |
| Deletion persistence | 3 | alert | **无法删除** / **这盘棋仍然保留。请重试。** | **new**, §8.2 |
| Import rejection | 3 | alert | four messages, §9 | **new**, hand-off to 7.2 |
| Store cannot open | full destination | content-unavailable | **无法打开数据** / two messages | **new**, §6.3 |
| Engine unavailable mid-game | 4 | persistent turn-status state | one new string + accepted reuse | **new**, §4 |

Every row is at exactly one rung. No failure appears twice.

### 7.2 The transient capsule's duration — gap 0.2

The accepted capsule is time-boxed, and *HIG > Accessibility > Cognitive* advises against time-boxed elements.
The mitigation is that what it reports is fully visible without it — the board did not change — and that its
remedy is repeating a gesture rather than reading and acting.

**Proposal, ours, first-version values in the sense of `:432`:**

- Appears **within one frame of the touch**, per the accepted rule at `:430` that feedback answering a touch
  leads its animation.
- Holds for **4.0 s**, then fades over **200 ms**. Four seconds is roughly twice a comfortable reading time for
  the eleven-character message, allowing for a user whose attention was on the board.
- A **second failure restarts the hold** rather than stacking a second capsule. There is never more than one.
- It is **dismissed early by the user's next accepted move**, because the successful move is a better answer
  than the message.
- **It is announced**, at `.default` priority. This is what makes the time box safe for the users *HIG >
  Cognitive* is warning about: a screen-reader user gets the message in speech and does not have to find and
  read a view before it goes. This is also the "remaining transient announcements" clause of `:523`.

---

## 8. Destructive-action states

Largely accepted (`:377–381`, `:44`): **删除前确认** default-on, **删除这盘棋？** / **删除后无法恢复。** /
取消 · 删除, immediate deletion when the preference is off, no Undo, no Recently Deleted, red **删除** swipe
action, and destructive actions using the system's destructive **role** rather than a red tint. What follows
fills the remaining holes and does not reopen any of that. **Resignation's confirmation is not here** — it is
part 4's, in open PR #23.

### 8.1 Four details the accepted text leaves implicit

1. **In the confirmation alert, 取消 is the default action and 删除 takes the destructive role.** An alert
   whose destructive action is also its default is the classic trap, and the accepted text fixes the role but
   not the default.
2. **Cancelling a confirmation reached by a full swipe closes the swipe** and returns the row to rest. A row
   left open after a cancelled destruction reads as still-armed.
3. **No success confirmation.** *HIG > Feedback > Best practices*: "**When it makes sense, confirm that a
   significant action or task has completed** … It's generally best to reserve this type of confirmation for
   activities that are sufficiently important — because people typically expect their action or task to
   succeed, they only need to know when it doesn't." The row disappearing is the confirmation.
4. **Deletion has one accessibility requirement worth fixing**, because a row vanishing strands VoiceOver
   focus: on a confirmed deletion, focus moves to the row that took its place, or — if the list becomes empty
   — to the empty state (§10.1), with `AccessibilityNotification.LayoutChanged` posted carrying that element.
   Apple's documentation for `AccessibilityNotification.LayoutChanged` describes exactly this parameter:
   "Optionally, include a parameter that contains the accessibility element for VoiceOver to move to after
   processing the notification."

### 8.2 Failed deletion — gap 0.3

**Rung 3, deliberately parallel to the accepted archive failure**, so the two read as one family:

- Title **无法删除** (new)
- Message **这盘棋仍然保留。请重试。** (new — the accepted archive message is **当前对局仍然保留。请重试。**)
- Actions **取消** and **重试** (both accepted strings)

This is backed by `game-data.md:125` ("A failed deletion leaves the existing record intact"), so the message
states a fact the core guarantees rather than a hope.

---

## 9. Corrupted import, and the import error family

**Boundary.** The import *flow* — the picker, where the entry point sits, how the existing record is revealed
on a duplicate — is 7.2 / survey slot #4. What is proposed here is the **classification rule and the copy**,
which my brief names, offered to that slot as its shell. Whoever holds 7.2 should take or reject it whole
rather than writing a second set.

Every semantic is already accepted (`game-data.md:57`, `:60–64`, `core-interface.md:187`, `:199`). One
constraint is mandatory: unsupported versions are rejected "with a distinct created-by-a-newer-version message
**that is never presented as corruption**" (`game-data.md:64`). The minimum viable set is therefore two
messages. The survey's owner question is how many the product wants.

**Recommendation: four rejection messages plus one success**, because each maps to a different user action —
and a message the user cannot act on differently is a distinction they should not have to read.

| Class | Taxonomy | User's next action | Proposed message |
|---|---|---|---|
| Newer version | `MXQ_DOMAIN_ARCHIVE`, unsupported version | update the app | **这个文件由更新版本的应用创建。请更新后再导入。** |
| Unusable file | archive malformed / inconsistent replay / terminal-claim mismatch, rules-domain failures | pick a different file | **这个文件不是有效的对局文件。** |
| Too large | archive too large, `MXQ_DOMAIN_RESOURCE` limit | nothing — the file is valid but out of bounds | **这个文件太大，无法导入。** |
| Identity conflict | `MXQ_DOMAIN_STORE` identity conflict | reconcile two divergent copies | **历史中已有同一盘棋，但这个文件的内容不同。未做任何更改。** |
| Duplicate | `MXQ_IMPORT_EXISTING` — **success, not an error** (`core-interface.md:187`) | look at the record they already have | **这盘棋已经在历史中。** |

All four rejections share one title: **无法导入** (new).

Two notes on the choices:

- **"Too large" is a separate message because the contract creates the case.** `game-data.md:62` says in as
  many words that "a locally produced game exceeding the import bounds remains fully playable and replayable —
  only re-import of its export would be refused." A user re-importing their own valid, playable game and being
  told it "is not a valid game file" would be told something false.
- **The identity conflict is not corruption and must not read as it.** It is the one rejection where the user
  has two legitimate files, and the message's job is to say that nothing was changed.

**Success feedback.** *HIG > Feedback* (quoted at §8.1) argues against a "已导入" banner; the stronger
confirmation is that the new record **appears at the top of the list, revealed and selected**. For VoiceOver,
where "it appeared" is not perceivable, post a `LayoutChanged` announcement carrying the new row as the
focus element. Placement is 7.2's.

---

## 10. Empty states

### 10.1 History with no records — the app's only true empty state

There is exactly one, because the accepted scope excludes search, filters and tags (`product.md:65`), so there
is no "no results" state to distinguish it from.

- **Presentation:** the platform's content-unavailable presentation, centred in the list's area, replacing
  the list. On Apple platforms that is `ContentUnavailableView(label:description:actions:)`, whose
  label/description/actions shape is confirmed in the SwiftUI documentation and matches the three parts below.
  Apple publishes **no HIG page on empty states** — I searched and found nothing above the API level, and say
  so rather than inventing a citation. The recommendation is ours.
- **Title:** **还没有对局记录** (new)
- **Description:** **完成或保存一局棋后，它会出现在这里。** (new) — it names both routes a record can arrive
  by, which matters because "saved to History" is this app's ordinary way of ending a game, not an unusual one
  (`:309`).
- **Action:** the import entry point, whatever it turns out to be. An internal tester who has just been sent a
  `.mxq` file arrives at an empty History with nothing to do, and this is the one place the action is worth
  more than the list is. **The affordance's identity and label are 7.2's**, so this section reserves the slot
  and does not fill it.
- **No action that navigates to Play.** Play is one tap away in the same navigation container (`:488`), and an
  empty state that pushes the user to a different destination is a worse answer than the sentence that tells
  them where records come from.

### 10.2 Play with no active game is *not* an empty state — an editorial correction

`interaction-design.md:296` describes the Play destination *with* an active game and never without. That has
been read as an empty state; it is not one. Without an active game, Play shows the two mode entries — which
are the only way to start a game and must be present regardless — and simply omits the active-game metadata
block and **Resume Game**. The contract already has a name for it: `:344` calls it "the Play start state".

**Recommendation: no empty-state treatment on Play at all.** No illustration, no "no games yet" message. A
chooser with two primary actions is not an empty container, and dressing it as one would misdescribe it.

Whether it carries a one-line first-run orientation is **Owner question 3** — it is small, but it requires a
persisted first-run flag that is not in `product.md`'s closed Settings list.

### 10.3 The move list at an initial position

The move list is empty at the initial position of every game and every replay. **No placeholder**: a
two-line region with a centred message in it is clutter where blankness is self-explanatory.

One exception, for a real cost: a VoiceOver user reaching an empty list gets silence and cannot tell an empty
list from a broken one. Give the list container an accessibility value of **还没有走子** (new). One string,
never drawn, entirely for the screen reader.

---

## 11. Every new Chinese string this report proposes

All require approval. Per the survey's collision #1, each carries its English counterpart in the same change,
under part 6's rules — this report deliberately proposes **no** English, so that part 6 owns the rules and the
register rather than inheriting an unreviewed set.

Register followed throughout, from the accepted 58: titles are short noun phrases or questions ending in
**？**; messages are complete sentences ending in **。**; actions are two to four characters; `AI` and `App`
stay Latin; the middle dot `·` joins metadata.

| # | String | Where | Kind |
|---|---|---|---|
| 1 | **AI 暂时无法走子** | turn status, mid-game engine unavailable (§4.3, §4.4) | state name |
| 2 | **AI 组件已损坏。重新安装应用可以恢复。** | same state, and the pre-start alert (§4.4) | message |
| 3 | **思考中** | turn status, AI thinking (§5.1) | state name |
| 4 | **无法创建对局，请重试。** | inline under 开始对局 (§6.2) | inline error |
| 5 | **无法删除** | failed deletion alert (§8.2) | title |
| 6 | **这盘棋仍然保留。请重试。** | failed deletion alert (§8.2) | message |
| 7 | **无法打开数据** | store cannot open (§6.3) | title |
| 8 | **这些数据由更新版本的应用创建。请更新到最新版本。** | store schema too new (§6.3) | message |
| 9 | **应用数据无法读取。** | store corruption (§6.3) — remedy sentence pending Owner question 4 | message |
| 10 | **还没有对局记录** | empty History (§10.1) | title |
| 11 | **完成或保存一局棋后，它会出现在这里。** | empty History (§10.1) | description |
| 12 | **还没有走子** | empty move list, accessibility value only (§10.3) | a11y value |
| 13 | **重试失败。可用内存仍然不足。** | announced on a failed retry (§3.4) | announcement |
| 14 | **无法导入** | import rejections (§9) | title |
| 15 | **这个文件由更新版本的应用创建。请更新后再导入。** | import, newer version (§9) | message |
| 16 | **这个文件不是有效的对局文件。** | import, unusable (§9) | message |
| 17 | **这个文件太大，无法导入。** | import, too large (§9) | message |
| 18 | **历史中已有同一盘棋，但这个文件的内容不同。未做任何更改。** | import, identity conflict (§9) | message |
| 19 | **这盘棋已经在历史中。** | import duplicate — success (§9) | message |
| 20 | **好** | sole dismissing action on the damaged-assets alert (§4.4) | action |

Strings 14–19 belong to 7.2's change, not this one; they are listed so part 6's total is known.

**Deliberately reused rather than invented** — worth recording, because it is where most of the design effort
went: **当前可用内存不足。请尝试关闭一些其他 App，然后重试。** and **重试** carry the whole mid-game memory
state; **无法启动 AI 对手** carries the damaged-assets alert; **取消** and **重试** carry the failed-deletion
alert. The mid-game state that had *nothing* specified needs **one** new string.

---

## 12. What `testing.md` would need

Written as gates in that document's own register, for whoever holds 8.3. Each is verifiable without a device
measurement except where marked.

- No progress indication appears for any operation completing within 500 ms; at 500 ms the invoking control —
  and only that control — adopts an in-progress appearance, without reflowing its container.
- The turn status's height and baseline are identical with and without the AI activity indicator.
- Under Reduce Motion the AI activity indicator is absent and **思考中** is present.
- The insufficient-memory alert is not dismissed and re-presented by a retry; a failed retry posts a
  high-priority announcement; from the third consecutive failure 取消 is the default action; 重试 is never
  disabled and no automatic or delayed retry occurs.
- After suspension with a search owed and a failed re-preparation: the game is active, saved and resumable;
  the board is not dimmed; the turn status shows the accepted side-to-move line plus the unavailable state;
  Undo, the mode entries and Settings all remain reachable; a board tap produces the accepted acknowledgment
  beat; the state is announced once and never re-announced.
- A non-memory engine failure shows the damaged-assets copy and offers no 重试.
- The save-failure capsule holds for its accepted duration, never stacks, is dismissed by the next accepted
  move, and is announced.
- The deletion confirmation's default action is 取消 and its destructive action is 删除; a cancelled full-swipe
  confirmation closes the swipe; VoiceOver focus survives a deletion and lands on the empty state when the
  list empties.
- Each import rejection class produces its own message, and the newer-version message is never presented as
  corruption.
- Empty History shows the content-unavailable state; the Play start state shows no empty-state treatment.
- *(Device-dependent, and therefore blocked under 8.3's own rule)*: whether game creation and import routinely
  exceed 500 ms on representative hardware.

---

## Open for the owner

Six. Everything else in this report is a designer's call and is decided above with its reasoning.

**1. Does repeated insufficient-memory failure eventually offer a way forward other than 取消?**
*Context:* §3.3 already stops the app steering the user into further identical attempts, so nobody is trapped.
The question is whether the app should offer something *else*. HIG allows a third alert button.
- **(a) No — 取消 and 重试 only.** *Costs:* a user on a memory-constrained device who wants to play against
  the AI simply cannot, and the app never says what they could do instead. *Gains:* the notice keeps one
  meaning, and the app never nudges anyone away from what they asked for.
- **(b) A third action from the third failure: 开始自由对弈.** Free Play needs no engine at all
  (`engine-integration.md:72`). *Costs:* it offers a different product at the moment of failure, which can
  read as a downgrade; it is a mode switch reached from an error, which no other path in the app does; and the
  alert grows a third button that is absent the first two times. *Gains:* the user gets to play.
- **(c) A third action offering Help.** *Costs:* Help is a rules reference, not a troubleshooting surface
  (`:395`); it has nothing to say about memory. Not recommended, listed for completeness.

**2. When the engine cannot be re-prepared mid-game, is Retry the only exit the state itself offers?**
*Context:* §4.5 — Undo, save-and-continue and resignation all remain reachable as ordinary furniture.
- **(a) Retry only (recommended).** *Costs:* a user with a persistent memory problem can never finish that
  game as a human-versus-AI game; their exits record it as ended-early or as a resignation loss. *Gains:* the
  archive never says anything untrue about what happened.
- **(b) Offer to convert the game to Free Play.** *Costs:* this is **not** a UI decision. `mode` is frozen at
  creation and `human_side`, `ai_level` and `ai_movetime_ms` are present in the archive *exactly when* mode is
  `human-vs-ai` (`game-data.md:38`, `:48`). A mid-game mode change therefore requires either an archive
  version 2 that can record it, or a record that misdescribes the game it contains. *Gains:* the user finishes
  their game.
- **(c) Offer 结束对局 from inside the state.** *Costs:* a second path to the ended-early classification that
  the mode entries already provide (`:309`), for very little; it also puts an ending action inside an error
  state. *Gains:* one fewer step for a user who has given up.

**3. Does the Play start state carry first-run orientation text?**
- **(a) No (recommended).** *Costs:* a first-time tester sees two mode names and no sentence. *Gains:* no new
  persisted state; the Settings inventory in `product.md:76–83` stays closed.
- **(b) A single line on first launch only.** *Costs:* requires a persisted "has played" flag, which is a new
  local value outside the accepted seven preferences, and it must be decided whether it survives a reinstall.
  *Gains:* a slightly softer first launch.

**4. What does the app tell an internal tester when the store cannot be opened at all?**
*Context:* §6.3, gap 0.5. The schema-too-new case is answerable (tell them to update). The corruption case is
not, because every honest remedy costs data.
- **(a) Say only that the data cannot be read, and offer a relaunch.** *Costs:* if the corruption is
  persistent the app is permanently unusable and the user is told nothing they can act on. *Gains:* nothing is
  destroyed by following the advice.
- **(b) Name reinstalling, and name its cost.** *Costs:* on iOS and iPadOS reinstalling deletes the container
  and every unexported History record; the app would be instructing the user to destroy their data.
- **(c) Offer an explicit "start a new library" action** that moves the damaged store aside and opens a fresh
  one. *Costs:* the user's History disappears from their point of view, and the app now has a data-destroying
  button that no accepted contract describes; the damaged file survives for diagnosis, which matters for an
  internal build. *Gains:* the app stays usable and nothing is actually deleted.

**5. Does the damaged-assets copy tell the user to reinstall, given what that costs them?**
*Context:* §4.4. `engine-integration.md:156` says "reinstalling restores the AI," which is true of the AI and
silent about the History it also removes on iOS and iPadOS.
- **(a) Keep **重新安装应用可以恢复。** as proposed.** *Costs:* a user who follows it loses every unexported
  game. *Gains:* the shortest true instruction.
- **(b) Warn first: add a sentence telling them to export anything they want to keep.** *Costs:* a longer
  message in a small state, and it presumes they know what export is. *Gains:* nobody is instructed into data
  loss.
- **(c) Say nothing about the remedy.** *Costs:* the user is told the AI is broken and given no way out.

**6. How many distinct user-visible import rejection messages?**
*Context:* §9. The accepted floor is two (`game-data.md:64` mandates the newer-version message be distinct and
never presented as corruption). This is 7.2's item; it is repeated here only because §9 proposes the copy and
the count is the owner's.
- **(a) Two — newer-version, and everything else.** *Costs:* a user re-importing their own valid but oversized
  game is told the file is invalid, which `game-data.md:62` makes a reachable and false statement; an identity
  conflict is presented as corruption when it is not.
- **(b) Four, as proposed (recommended).** *Costs:* four strings to write, translate and review, and four
  branches to test. *Gains:* every message names an action the user can actually take, and no message says
  something false.

---

# Independent review

Adversarial verification of the report above, by a second agent. Method: read all eight contracts in
`MiniXiangqi/docs/` in full; verified every Apple citation against the pinned Xcode 27 beta documentation
via `DocumentationSearch`; measured text wrapping with `xcrun swift` on the pinned toolchain; executed the
workspace Fairy-Stockfish build to test the `go movetime` claims; ran read-only `gh pr list` under the
`ppppvz` identity. Nothing under `MiniXiangqi/` or any worktree was modified.

Twenty findings. **R1–R5 are blocking** — each either contradicts an accepted contract sentence, contradicts
the Apple page the report itself relies on, or contradicts another section of the report. R6–R14 should be
fixed before the copy goes to the owner. R15–R20 are precision defects.

## What survived

Recorded first, because most of the report does survive and the main thread needs to know which parts it can
lift without re-checking.

- **Every Apple quotation is verbatim and correctly attributed.** Verified individually: *HIG > Alerts >
  Content* ("In all platforms, alerts display a title, optional informative text, and up to three buttons.");
  *HIG > Feedback > Best practices* — all three quotes, including "Consider integrating status feedback into
  your interface…", "Use alerts to deliver critical — and ideally actionable — information…", and "…because
  people typically expect their action or task to succeed, they only need to know when it doesn't";
  *HIG > Loading > Showing progress*; *HIG > Progress indicators > Best practices* — "When possible, use a
  determinate progress indicator…", "If it's helpful, display a description that provides additional context
  for the task. Be accurate and succinct. Avoid vague terms like *loading* or *authenticating* because they
  seldom add value", and the deceptive-pace sentence; *HIG > Launching > Best practices* and *> Launch
  screens*; *HIG > Accessibility > Cognitive* ("Minimize use of time-boxed interface elements…"). No
  MISQUOTED and no NOT FOUND among the quotations themselves. Two of the *arguments* built on them fail
  (R1, R11).
- **Every API citation is real and says what is claimed.** `ContentUnavailableView.init(label:description:actions:)`
  exists with exactly those three `@ContentBuilder` parameters. `AccessibilityNotification.Announcement`'s
  own documentation carries precisely the code the report describes — `highPriorityAnnouncement.accessibilitySpeechAnnouncementPriority = .high`
  then `AccessibilityNotification.Announcement(highPriorityAnnouncement).post()`.
  `UIAccessibilityPriority > Choosing a priority` defines `high` as "A high-priority announcement that
  interrupts other speech and isn't interruptible after it starts" and `default` as "A default-priority
  announcement that interrupts existing speech, but is interruptible if a new speech utterance starts" —
  both quoted correctly. `AccessibilityNotification.LayoutChanged` carries the sentence "Optionally, include
  a parameter that contains the accessibility element for VoiceOver to move to after processing the
  notification." `AccessibilityTraits.updatesFrequently` exists.
- **"Apple publishes no HIG page on empty states" is corroborated.** Independent searches returned nothing
  above the API level. The report was right to say so rather than invent one.
- **The engine claim in §5.3 is true, and understated.** Executed against
  `Fairy-Stockfish/src/stockfish` (build `260726`, variant `minixiangqi`, Hash 256, driven over a held-open
  UCI pipe so `quit` could not truncate the search): `go movetime` **overruns** — movetime 1000 returned at
  1100 ms, 3000 at 3003 ms, 5000 at 5028 ms — and it **returns early** far more dramatically than the report
  claims. From `3k3/7/7/R6/7/7/3K3 w - - 0 1` (chariot-and-general against a bare general, mate in 2),
  `go movetime 5000` returned in **12 ms** at `depth 245 seldepth 4 score mate 2`, i.e. the iterative
  deepening loop exhausted `MAX_PLY` and stopped. That is a factor of ~400 between promise and reality on a
  single position, on a 7×7 board where such endgames are common. §5.3's conclusion is not merely defensible;
  a determinate bar would be actively wrong. Recommend the report cite this measurement instead of the softer
  "may return early on a forced or mated line".
- **The PR-territory claim was true when written.** `gh pr list` confirms #23 was the only open PR at the
  report's timestamp; #26 and #27 were opened at 12:33 and 12:45 UTC, after it.
- **The 58-string count checks out.** A regex sweep of bolded runs containing CJK across `docs/*.md` returns
  59, one of which is prose about 一将一捉 rather than user-facing copy.
- Gaps 0.1, 0.3, 0.4 and 0.5 are real: `engine-integration.md:154`'s "accepted engine-unavailable path" does
  not exist, `interaction-design.md:382`, `:198` and `:207` do require an error with no copy, and no contract
  describes an unopenable store. The catch at `testing.md:59` — a test for a creation-failure error whose
  design has never been written — is a genuine and useful find, subject to R13.

---

## R1 — BLOCKING. Making 取消 the default action is the opposite of what the HIG says, in two separate proposals

**Report, §8.1(1):** "**In the confirmation alert, 取消 is the default action and 删除 takes the destructive
role.** An alert whose destructive action is also its default is the classic trap, and the accepted text
fixes the role but not the default."

**Report, §3.3(3):** "the same alert, the same title, the same message, the same two actions — but **取消
becomes the default action and 重试 loses default emphasis**."

**What is wrong.** *HIG > Alerts > Buttons* — the section immediately after the one the report quotes for the
alert's shape — says the opposite in as many words:

> "If there's a destructive action, include a Cancel button to give people a clear, safe way to avoid the
> action. Always use the title "Cancel" for a button that cancels an alert's action. **Note that you don't
> want to make a Cancel button the default button.** If you want to encourage people to read an alert and not
> just automatically press Return to dismiss it, **avoid making any button the default button.**"

Apple's remedy for exactly the "classic trap" the report names is *no default button*, not *Cancel as
default*. The report reached §3.1's conclusions from *HIG > Alerts > Content* and never opened *Buttons*,
which is the section that governs both of the decisions it makes here. This is the pattern the brief warns
about: the justification does not survive the page it is drawn from.

There is a second omission on the same page that cuts against §8.1(1)'s other half:

> "**Use the destructive style to identify a button that performs a destructive action people didn't
> deliberately choose.** For example, when people deliberately choose a destructive action — such as Empty
> Trash — the resulting alert doesn't apply the destructive style to the Empty Trash button because the
> button performs the person's original intent."

A user who swiped to delete, or pressed 删除, chose deliberately. `interaction-design.md:44` has already
decided this for us ("Destructive actions use the system's destructive role rather than a red tint"), so the
role is not reopened — but the report should say that the contract's choice is a deliberate departure from
Apple's example rather than an application of it.

**Severity: blocking.** Two proposals, one of which is presented as correcting a known trap, are both
contradicted by the governing page.

**Correction.** In §8.1(1): **no default button** on the deletion confirmation — quote the HIG sentence as
the reason. In §3.3(3): the streak-3 change becomes "**no button is the default from the third consecutive
failure**", which achieves exactly what the report wants (the app stops steering the user into a fourth
attempt) with Apple's own mechanism, and removes the awkwardness of a Cancel that Return activates.

---

## R2 — BLOCKING. The claim that nothing here creates a fourth glass surface is a non-sequitur, and rung 4 puts a *control* on the turn status

**Report, §1:** "**Rungs 1, 2 and 4 carry no material.** `interaction-design.md:38` fixes exactly three custom
glass surfaces … and says system alerts and sheets are "additional and automatic". … Rungs 1, 2 and 4 are
**text and controls drawn on surfaces that already exist**: the turn status is not one of the three, and
neither is the pre-start page. Adding a line of text and a button to an existing element creates no fourth
glass surface."

**Contract, `interaction-design.md:31`:** "On Apple platforms, Liquid Glass is **the required material for
functional interface layers — navigation, controls, toolbars, and contextual actions** — and is not used in
the content layer."

**Contract, `:38`:** "The app defines **three** custom glass surfaces: the play control cluster, the replay
transport, and one shared slot… System-provided glass — the tab bar or sidebar, navigation bar and toolbar,
alerts, sheets, context menus, and History swipe actions — is additional and automatic."

**Contract, `:42`:** "**The AI-thinking indicator carries no material at all.**"

**What is wrong.** The inference "the turn status is not one of the three, therefore nothing added to it can
be a fourth" is backwards. `:38` says the app *defines* exactly three custom glass surfaces; a new custom
glass surface is a fourth wherever it is attached. And `:31` makes glass **required** of controls. §4.3 puts
a **重试 button** — a control, by any reading — into the turn status. That button therefore either takes
glass, which is a fourth custom surface `:38` forbids, or it must be granted an explicit exemption. `:42` is
the proof that such an exemption has to be written: the contract found it necessary to state in its own
sentence that even the *indicator* — which is not a control at all — carries no material. A button needs at
least as much.

The same reasoning is load-bearing for the report's own summary ("nothing in this report creates a fourth
custom glass surface against interaction-design.md:38"), so it is not a footnote.

**Severity: blocking.** It is the report's headline compliance claim and it does not hold.

**Correction.** Either (a) ask the contract for an explicit exemption in the same words `:42` uses — "the
mid-game unavailable state's 重试 control carries no material" — and say plainly that this is a *change* to
the glass inventory's reasoning rather than a consequence of it; or (b) place the retry affordance in the
play control cluster, which is already one of the three accepted glass surfaces and already holds the play
actions, leaving the turn status carrying text only. (b) also removes R4's layout pressure. Option (a) is
probably right, but it must be asked for, not assumed.

---

## R3 — BLOCKING. "The accepted rule firing, not a new behaviour" contradicts the emphasised accepted sentence

**Report, §4.3:** "**One automatic attempt, on each occasion a search becomes owed.** This is the accepted
rule (`engine-integration.md:72`) firing, not a new behaviour … **Returning to the foreground with a search
still owed is such an occasion.**" The report's own summary puts it more strongly: "including on each return
to the foreground, which is how the real recovery works".

**Contract, `engine-integration.md:72`:** "**Re-preparation happens when a search is next owed, not on return
to the foreground.** A search is owed exactly when the resumed state is an active human-versus-AI game whose
committed status reports the AI to move and a search expected."

**What is wrong.** The accepted sentence's emphasis is on precisely the clause the report reverses. Once
re-preparation has failed and the app is sitting in the rung-4 state, the search is *already* owed and has
never stopped being owed; "when a search is **next** owed" has already fired. Repeating the attempt on every
foreground return is a new trigger, and it is the exact trigger `:72` names and excludes. The report may well
be right that this is what the product wants — closing other apps and coming back is the real recovery path,
as it says — but it is a contract change, not an application, and `engine-integration.md` would have to be
edited alongside `interaction-design.md`.

**Severity: blocking.** Something new is presented as already accepted, which is the failure mode the brief
asks for specifically.

**Correction.** Say it plainly: "this requires amending `engine-integration.md:72`, whose current sentence
excludes foreground return as a trigger. The amendment: re-preparation is attempted when a search becomes
owed **and again on each return to the foreground while a search remains owed and unserved**." Then verify
the amendment does not disturb `testing.md:134`, which currently gates the exclusion.

---

## R4 — BLOCKING. The layout budget the report hands to `:515–516` is understated by half. Measured

**Report, §4.7:** "This state makes the turn status **two lines plus a control**, where ordinary play makes it
one line plus a small indicator. That is a real budget item for `interaction-design.md:515–516`… Whoever
fixes the layout bounds needs this state in the inventory."

**What is wrong.** The state drawn at §4.3 is three text blocks, not two:

```
轮到黑方
AI · AI 暂时无法走子
当前可用内存不足。请尝试关闭一些其他 App，然后重试。
                    [ 重试 ]
```

and the third one wraps. Measured with Core Text on the pinned toolchain (`xcrun swift` under
`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`, system font, `CTFramesetter` line count):

| Width | 17 pt body | 20 pt | 28 pt |
|---|---|---|---|
| 308 pt (the board core at the accepted 44 pt floor, `:134`) | **2 lines** | 2 | **3** |
| 340 pt | 2 | 2 | 3 |
| 370 pt | 2 | 2 | 2 |

The single-line width of 当前可用内存不足。请尝试关闭一些其他 App，然后重试。 is **431.9 pt at 17 pt**, against
a board core of 308 pt. So the state is **four text lines plus a control at the board floor, five at 28 pt** —
roughly double what §4.7 tells the layout owner to budget for. Since §4.7's entire purpose is to hand
`:515–516` a number, the number being wrong is the defect.

**Severity: blocking**, because a section whose only output is an input to someone else's open item must be
right.

**Correction.** Replace with the measured figures and the widths they were taken at, and note that the
message is the one line that wraps, so shortening it — or moving it to a disclosure — is the available lever.
This also strengthens the case for R2's option (b).

---

## R5 — BLOCKING. §5.4's Reduce Motion argument rests on a premise §5.1 and §4.3 both break

**Report, §5.4:** "The mitigation is structural rather than cosmetic — the label exists **only** while a
search is genuinely outstanding, and it disappears at the instant the piece departs, so a stalled search would
present as a label that never goes away, which is a bug rather than an ambiguity."

**Report, §5.1:** "**Disappearance:** at the instant the AI's piece departs — that is, at the compose-beat
instant defined by `:424`, **not at search return**."

**Report, §4.3:** "**During re-preparation the state shows the ordinary thinking treatment** (§5) rather than
a third "preparing" state. … *(Named honestly: this means 思考中 is shown while the engine is loading rather
than searching.)*"

**What is wrong.** The premise is false twice over, by the report's own text. Per `:424` the AI's piece
departs at "the later of two instants: when the search returns, and 260 ms after the player's own move has
finished animating", so 思考中 can be on screen for up to 260 ms after the search has returned. And §4.3
deliberately shows it while **no search exists at all**. §5.4's whole answer to "a Reduce Motion user cannot
distinguish still-searching from stalled" is that the label tracks a live search exactly; it does not.

Apple says the same thing about the indicator: *HIG > Progress indicators* — "All progress indicators are
transient, appearing only while an operation is ongoing and **disappearing after it completes**." §5.1's
hold-past-return is a deliberate departure from that, and the report does not name it as one.

**Severity: blocking**, because the Reduce Motion decision is one of the report's three headline results and
its stated mitigation is not true.

**Correction.** Two honest options. (a) Keep the hold-to-departure (it is good — it prevents the blink) and
drop the "only while a search is outstanding" mitigation, replacing it with the truthful one: under Reduce
Motion the state is carried by a word that appears and disappears with the AI's turn, and a stall presents as
a turn that never ends, which is visible whether or not a spinner is drawn. (b) Introduce the separate
准备中 label §4.3 rejects, which would restore the premise at the cost of a string. (a) is better; it just has
to be written correctly.

---

## R6 — §5.4 omits the one HIG rule that argues directly against its own recommendation

**Report, §5.4:** "**Under Reduce Motion the activity indicator is not drawn at all. 思考中 carries the state
alone.**"

**Not cited, *HIG > Progress indicators > Best practices*:** "**Keep progress indicators moving so people know
something is continuing to happen.** People tend to associate a stationary indicator with a stalled process or
a frozen app. If a process stalls for some reason, provide feedback that helps people understand the problem
and what they can do about it."

**What is wrong.** The report is scrupulous about naming where it declines Apple's preference (§5.3 does this
well), and then declines a second, more specific one silently. Removing the indicator entirely is a stronger
step than not keeping it moving, and this sentence is the counter-authority a reviewer will find first. The
report's §0.6 also asserts that `:428` "taken literally" forbids the indicator under Reduce Motion; that
reading is defensible but it is a reading, and *HIG > Accessibility > Cognitive* frames the setting as
"reducing **automatic and repetitive** animations, including zooming, scaling, and peripheral motion" — a
system activity indicator is arguably neither peripheral nor gratuitous when it is the only signal that the
app has not hung.

**Severity: medium.** The recommendation may still be right; the record is incomplete.

**Correction.** Quote the sentence, concede it, and rest the decision on `interaction-design.md:428` plus the
fact that 思考中 is a *label*, not a stationary indicator — a stationary spinner is what Apple warns about,
and the proposal draws no spinner at all. Add the missing half of Apple's own rule: name what the app does if
the process genuinely stalls.

---

## R7 — `faulted` is misclassified as a damaged installation, and the copy then instructs a data-destroying reinstall

**Report, §4.4:** "If re-preparation fails for an engine-domain reason that is **not** memory —
`MXQ_DOMAIN_ENGINE`'s asset missing / mismatch, variant load failure, **or faulted** (`core-interface.md:200`)
— then … **AI 组件已损坏。重新安装应用可以恢复。**"

**Contract, `core-interface.md:200`:** `MXQ_DOMAIN_ENGINE` | 6000 | "insufficient memory, asset missing /
mismatch, variant load failure, Hash allocation failure (reserved; reachable only after the fork change), no
move, illegal result, **faulted**".

**What is wrong.** Asset missing/mismatch and variant load failure are installation facts — the bundled bytes
are wrong, and `engine-integration.md:154` is right that this "means a damaged installation". `faulted` is
not: it is the engine having entered a bad runtime state, which `engine-integration.md:32` explicitly exists
to contain ("the accepted error contract forbids any exit crossing the core boundary… Recoverable Hash
allocation and release"). Telling a user whose engine faulted once that a component "已损坏" and that they
should reinstall is (a) probably false and (b) — by the report's own **Owner question 5** — an instruction to
destroy every unexported History record on iOS and iPadOS. The report identifies that cost and then routes a
recoverable condition into it.

**Severity: high.** This is the one place in the report where following its own copy loses user data.

**Correction.** Split the class. Asset missing/mismatch and variant load failure keep the damaged-installation
copy and no 重试. `faulted` takes the rung-4 state with 重试 offered, because a fresh `mxq_engine_prepare`
after a teardown is exactly the operation that can clear it. If the owner prefers one message, it must be the
one that does not instruct a reinstall.

---

## R8 — "AI · AI 暂时无法走子" says AI twice, and 暂时 is false for the class that has no retry

**Report, §4.3:**
```
AI · AI 暂时无法走子           ← accepted controller label (:269) + NEW state name
```
**Report, §5.1:**
```
AI · 思考中  ◌
```

**What is wrong.** Two problems in one string.

1. **The AI is duplicated.** `:269` fixes the secondary label as 你 or **AI**; string #1 then begins with AI
   again, so the element renders "AI · AI 暂时无法走子". §5.1's parallel construction correctly does not
   repeat it (AI · 思考中). The two sections are inconsistent with each other, and §4.3's version is the wrong
   one.
2. **暂时 is false in the damaged case.** §4.4 reuses this same state name for the class where, in the
   report's own words, "retrying cannot succeed" and the remedy is a reinstall. Telling that user the AI is
   *temporarily* unable to move is exactly the kind of false statement §9 refuses to make about oversized
   import files. The report's own standard convicts it.

**Severity: medium.** Copy that says something untrue, in a report whose stated principle is that no message
should.

**Correction.** String #1 becomes **暂时无法走子** for the memory class (rendering "AI · 暂时无法走子",
parallel with "AI · 思考中"), and the damaged class takes its own state name without 暂时 — **无法走子**, or
better a name that points at the cause, e.g. **AI 组件已损坏** as the state name with the remedy sentence
below it. That trades the report's "exactly one new string" headline for accuracy; the headline was worth less
than the accuracy.

---

## R9 — The register the report claims to have derived from the accepted 58 is contradicted by the accepted 58, and by four of its own strings

**Report, §11:** "Register followed throughout, from the accepted 58: titles are short **noun phrases** or
questions ending in **？**; messages are complete sentences ending in **。**; actions are **two to four
characters**; `AI` and `App` stay Latin; the middle dot `·` joins metadata."

**What is wrong.** Three of the five rules are false as stated. Enumerated from `docs/*.md`:

- **"Actions are two to four characters."** **保存并继续** (`:303`) is five. **以和棋结束** (`:350`) is five.
  And the report's own new action **好** (string #20) is **one**. The rule is wrong at both ends, and the
  report violates it in the same table where it states it.
- **"Titles are short noun phrases or questions."** Two of the four accepted titles — **无法保存对局**
  (`:319`) and **无法启动 AI 对手** (`:283`) — are negated verb phrases, and both of the report's own new
  titles (**无法删除**, **无法打开数据**) follow *that* pattern rather than the stated one. The stated rule
  describes neither the accepted set nor the proposal.
- **"`App` stays Latin."** The sole accepted precedent is 其他 **App** (`:284`). The report then writes
  **应用** in four new strings — #2 重新安装**应用**可以恢复。, #8 …更新版本的**应用**创建。, #9 **应用**数据
  无法读取。, #15 …更新版本的**应用**创建。 — without noting the departure. There may be a real distinction
  here (App = third-party apps the user closes; 应用 = this app), and if so it is a good one, but it has to be
  stated, because a translator or reviewer working from §11's rule will "fix" all four.

**Severity: medium.** §11 is the artefact part 6 inherits, and its stated rules are the thing part 6 will
apply.

**Correction.** Restate the register from the actual set: actions are **two to five** characters; titles are
short noun phrases, negated verb phrases of the form 无法+verb(+object), or questions ending in ？; and add
the explicit rule "**App** names other applications the user might close, **应用** names Mini Xiangqi itself",
or normalise all four to one form. Also reconsider #5 **无法删除**: every accepted 无法 title carries its
object (无法保存**对局**, 无法启动 **AI 对手**), so **无法删除这盘棋** is the register-consistent form.

---

## R10 — §2's universal rule contradicts §3.1's modal alert, in the report's own words

**Report, §2:** "**No operation blocks the whole window.** … A full-window blocking overlay would buy nothing"
— and the boxed rule: "Nothing else on screen changes, and **no operation ever blocks the whole window**."

**Report, §3.1:** "the platform's standard **modal** alert" … "**The alert's presence is what enforces the
accepted single-flight rule on 开始对局 while it is up.**"

**Report, §3.4:** "The alert is **not dismissed and re-presented** on retry. It remains, and **the retry runs
behind it**." … "If the attempt has not resolved within **500 ms**, 重试's label is replaced by an activity
indicator."

**What is wrong.** A modal alert blocks the whole window by definition — the report says so itself when it
uses the alert to enforce single-flight. So the retry attempt is an operation that runs with an in-progress
indicator while the whole window is blocked, which is exactly what §2's rule forbids in absolute terms. Both
positions are defensible; stating them as an absolute rule and its counterexample four pages apart is not.

**Severity: medium.** A general rule that generates the design should not be falsified by the first case it
generates.

**Correction.** Narrow the rule to what it actually means: "**no operation introduces a blocking overlay of
its own**; where an operation runs behind an alert the user already summoned, the alert is the modality and
nothing further is added." That is true, is what §3.4 does, and still forbids the progress-HUD pattern the
rule exists to exclude.

---

## R11 — §2's threshold rule is falsified by the accepted case it claims to generalise from

**Report, §2:** "**Proposal: that sentence's threshold becomes the app's single rule for every indeterminate
wait.** … At 500 ms, **the control that started the operation** adopts an in-progress appearance." … "it means
the AI-thinking indicator is not a special case but the first instance of a rule."

**Contract, `interaction-design.md:424`:** "If the search has not returned within 500 ms of the player's move,
**the turn status** shows AI activity."

**What is wrong.** The number generalises cleanly; the *location* clause does not. In the accepted case the
control that started the operation is the board — the player's tap on a destination — and the in-progress
appearance appears on the **turn status**, a different element entirely. So the accepted instance is a
counterexample to the second half of the rule the report says it instantiates. Nothing downstream breaks
(§6.1, §6.4 and §3.4 all put the treatment on the invoking control, correctly), but the rule as written would
require an in-progress appearance on the board, which `:258` forbids.

Related, and worth one sentence in §2: `:424`'s 500 ms is anchored to **the player's move**, not to search
start, while §2's is anchored to operation start. They nearly coincide but are not the same instant.

**Severity: medium.** A generative rule with a false clause will generate false cases later.

**Correction.** "At 500 ms an in-progress appearance appears on **the invoking control where the operation was
invoked from one, and otherwise on the element that owns the state** — which is what `:424` already does for
the AI search, whose invoking control is the board and whose owning element is the turn status."

---

## R12 — §5.5, §4.6 and §7.2 assign three different announcement policies without reconciling them

**Report, §7.2:** the save-failure capsule "**is announced**, at `.default` priority."
**Report, §4.6:** the mid-game unavailable state is announced once at `.default`.
**Report, §3.4:** a failed retry is announced at `.high`.
**Report, §3.3/§3.4:** "The streak-3 emphasis change is **not** announced."

**What is wrong.** The last one contradicts the reasoning of the first three. §3.4's argument for announcing a
failed retry is that a user "explicitly asked for an outcome" and must not get silence. At streak 3 the app
changes exactly one thing — which button carries default emphasis — and that change *is* the whole
information the design adds. Withholding it means the single new fact §3.3 introduces is available to sighted
users only. VoiceOver does not reliably speak default-button status on focus, so "VoiceOver reads button order
and default emphasis when the user reaches the buttons" is optimistic.

**Severity: medium.**

**Correction.** If R1's correction is taken (no default button at streak 3), the asymmetry mostly dissolves —
nothing is emphasised, so nothing is withheld. If the owner instead wants a positive signal at streak 3, it
has to be a perceivable one for everyone, which means a message change, which means a new string and a new
owner question. Say which.

---

## R13 — `testing.md` is cited as accepted requirement; it is normative nowhere

**Report, §0.2:** "`testing.md:184` **gates** its content".
**Report, §6.2:** "`testing.md:59` already requires ("Verify the pre-start preview shrinks as needed…") — **the
test exists, the design it tests does not**."

**Contract, `testing.md` status line:** "> **Status: Draft validation proposal.** **Nothing in this document
is normative until its status or an individual section is explicitly marked accepted.** Add exact commands and
thresholds only after they have been verified with the required toolchains and representative devices."

**What is wrong.** No section of `testing.md` is marked accepted, so nothing in it "gates" or "requires"
anything. The observation at §6.2 is still valuable — a draft test anticipates a design that was never
written, which is good evidence that the design is missing — but it must be described as evidence, not as an
existing requirement. §12, which proposes eleven new gates "in that document's own register", should also say
that they enter a draft document and are non-normative until accepted.

**Severity: medium**, because §6.2's rung-2 recommendation currently leans part of its weight on a
requirement that does not exist.

**Correction.** Reword to "a draft test at `testing.md:59` already anticipates a creation-failure error that
no contract defines", and add one sentence to §12 naming `testing.md`'s status.

---

## R14 — §6.3's launch-screen argument is refuted by the next sentence of the page it cites

**Report, §6.3:** "**No text, no logo, no splash screen.** The app has no onboarding flow, and *HIG >
Launching* places a splash screen at the beginning of one."

***HIG > Launching > Best practices*, in full:** "**If you need a splash screen, consider displaying it at the
beginning of your onboarding flow.** A splash screen is a beautiful graphic that succinctly communicates
branding and other information you need to provide. **If you don't provide an onboarding experience, you might
display your splash screen as soon as launching completes.**"

**What is wrong.** The report's inference — no onboarding, therefore no splash screen — is precisely the case
Apple's next sentence addresses, and it goes the other way. The conclusion (no splash screen) is almost
certainly right for this product, but the stated reason is refuted by the source. The right reasons are
already available and stronger: `product.md:12` scopes the product to internal education with no branding
requirement, `interaction-design.md:31` reserves the app's visual budget for the board, and *HIG > Launching >
Launch screens* says "**Don't advertise.** The launch screen isn't a branding opportunity."

**Severity: medium** — a MISQUOTE by omission, in the sense that the omitted clause reverses the argument.

**Correction.** Drop the onboarding inference. Keep "no splash screen" and justify it from Don't advertise plus
product scope.

---

## R15 — §3.4 cites an invalidation path that does not cover 取消

**Report, §3.4:** "**重试 is single-flight** while an attempt is outstanding; **取消 stays live** throughout
and uses **the accepted invalidation path** (`engine-integration.md:86`), so a late success releases whatever
it prepared rather than committing a game."

**Contract, `engine-integration.md:86`:** "**Leaving the pre-start state** at any point invalidates the
attempt, releases anything prepared, and prevents a late completion from committing."

**Contract, `interaction-design.md:286`:** "**取消** dismisses the notice without creating or changing an
active game. In pre-start setup, **the in-memory draft remains while the user stays on that page**."

**What is wrong.** Cancelling the alert explicitly does *not* leave the pre-start state — `:286` says the user
stays on the page with the draft intact — so `:86` does not apply to it. What §3.4 proposes (a 取消 pressed
during an outstanding attempt must invalidate that attempt) is sensible and probably necessary, but it is new
behaviour, not an accepted path. It also interacts with `game-data.md:94` ("Each creation attempt is
single-flight and bound to the identity or revision of the pre-start session"), which binds invalidation to
the session, not to the alert.

**Severity: low-medium.**

**Correction.** State it as a proposal: "cancelling the notice while an attempt is outstanding invalidates
that attempt on the same mechanism `game-data.md:94` defines, releasing anything prepared. No accepted
sentence covers this today; `engine-integration.md:86` covers only leaving the page."

---

## R16 — Two different alerts would carry the accepted title 无法启动 AI 对手 with different action sets

**Report, §4.4:** "the accepted title **无法启动 AI 对手** is reused (it is accurate for both classes), the
message is this new line, and — because retrying is pointless — the alert has **a single dismissing action**."

**Contract, `interaction-design.md:283–285`:** Title **无法启动 AI 对手** / Message **当前可用内存不足…** /
Actions **取消** and **重试**.
**Contract, `engine-integration.md:112`:** allocation failure "presents the accepted **无法启动 AI 对手** notice
**unchanged**."
**Draft test, `testing.md:139`:** verifies that same notice "unchanged".

**What is wrong.** After this change the app has two alerts sharing one title, with different messages and
different button counts, and the accepted phrasing "the notice" no longer names a unique object. A tester
following `testing.md:83`/`:139` will find an alert with that title and a single **好** and be unable to tell
whether the contract was violated. Separately, *HIG > Alerts > Best practices* says "**Avoid using an alert
merely to provide information.** People don't appreciate an interruption from an alert that's informative, but
not actionable" — a single-button alert whose only remedy is outside the app is close to that shape, and the
report does not engage with the sentence.

**Severity: low-medium.**

**Correction.** Either give the damaged-assets alert its own title (**AI 组件已损坏**, which is also the state
name R8 suggests, keeping one string for both) or state explicitly in the contract that the title is shared
and that the accepted memory notice is unchanged, so that "the notice" always means the memory one. Add a
sentence engaging with the informative-but-not-actionable rule.

---

## R17 — §9's "too large" row names the wrong domain and the message is false for the case it names

**Report, §9 table:** | Too large | archive too large, **`MXQ_DOMAIN_RESOURCE` limit** | … | **这个文件太大，
无法导入。** |

**Contract, `core-interface.md:199`:** `MXQ_DOMAIN_ARCHIVE` | 5000 | "malformed, unsupported version, **too
large**, inconsistent replay, terminal-claim mismatch".
**Contract, `core-interface.md:210`:** "…and **the import time budget exhausts as a resource-domain limit**."

**What is wrong.** "Too large" is an archive-domain code, not a resource-domain one. The resource domain
carries the *validation time budget* (`game-data.md:62`'s two seconds), which is a different condition: a
small, well-formed file on a slow device can exhaust it. Telling that user 这个文件太大 is false — the same
class of falsehood the report correctly refuses for the oversized-but-valid case one paragraph later.

**Severity: low-medium**, but it is a factual error about the taxonomy in the section whose whole claim is
that each message maps to a real, distinct class.

**Correction.** Split the row: archive-domain "too large" keeps 这个文件太大，无法导入。; the resource-domain
time-budget exhaustion needs either its own message or an explicit decision to fold it into the "unusable
file" class. This is a fifth class, so it belongs in **Owner question 6**'s option set rather than being
absorbed silently.

---

## R18 — The empty-History description names two of the three routes a record arrives by, and omits the one the same state's action offers

**Report, string #11:** **完成或保存一局棋后，它会出现在这里。** — "it names both routes a record can arrive
by".
**Report, §10.1, the same state:** "**Action:** the import entry point… An internal tester who has just been
sent a `.mxq` file arrives at an empty History with nothing to do."

**Contract, `game-data.md:118`:** "**Import** processes one game file at a time. A successful import creates
an immutable History record."

**What is wrong.** There are three routes, not two: completing a game, 保存并继续, and **import**. The
description asserts completeness ("both routes") and omits import — while the very state it describes puts an
import button underneath it. A user who arrives by the route the sentence forgets is told records come from
somewhere else.

**Severity: low-medium.**

**Correction.** Either drop the completeness claim from the annotation, or extend the copy, e.g.
**完成或保存一局棋后，它会出现在这里。也可以导入对局文件。** — noting that the second sentence duplicates the
action's own label, which is 7.2's, so the cleaner fix is to stop claiming the sentence is exhaustive.

---

## R19 — The `:44` tint budget is not addressed for the two new full-destination states

**Contract, `interaction-design.md:44`:** "Tint is reserved for a moment with a single obvious next action —
**开始对局** in either pre-start state, **结束对局** on the result card before confirmation, **完成** after
it — and **at most one tinted element is ever visible**."

**Report, §10.1 and §6.3:** both propose `ContentUnavailableView(label:description:actions:)` with an action —
the import entry point in empty History, and possibly a relaunch or new-library action in the store state.

**What is wrong.** `ContentUnavailableView`'s action slot renders as a prominent, tinted control by default on
current Apple platforms. `:44`'s reservation list is closed and app-wide ("at most one tinted element is ever
visible"), so an action in either new state is a fourth tinted moment the contract does not license. §6.1 is
careful about exactly this for **开始对局**; the two new states are not.

**Severity: low.**

**Correction.** One sentence in each: the action in these states is drawn untinted (plain or bordered), or the
contract's tint reservation is extended by name. The former is easier and consistent with `:44`'s intent.

---

## R20 — Three smaller precision defects

**(a) §2 over-extends `:258`.** Report: "would break the accepted rule that **the board is never dimmed**
(`interaction-design.md:258`)". `:258` actually says "The board is never dimmed **while the AI is thinking or
after a result is confirmed**". The accepted rule is scoped to two situations; §2 uses it as a universal
prohibition covering import, deletion and store operations, where no accepted sentence applies. The
conclusion is fine; the citation is doing work it cannot do. **Correction:** cite it as the precedent and
propose the generalisation as ours.

**(b) §0.2's "the app's only time-boxed element" is not true.** The acknowledgment beat "rises to full
emphasis and falls back" (`:258`) and the Reduce Motion illegal-tap response — "a single step to a stronger
appearance, **held briefly and then restored**" (`:250`) — are both time-boxed. What is true, and is what the
argument needs, is that the capsule is the app's only time-boxed element that **carries words**.
**Correction:** say that.

**(c) §2 cites `game-data.md:68` for "atomic and recoverable (every store transaction)".** `:68` says the core
"commits explicitly after every accepted move… the explicit transaction is the commit mechanism" — a statement
about *when*, not about atomicity or recovery. The claim is true and better supported by `game-data.md:146`
("The store is one process, one connection, one serialized writer; **every operation is one transaction**")
and `core-interface.md:238` ("Termination mid-transaction recovers to the last committed state through the
store's journal"). **Correction:** swap the citations.

---

## Two things the review agrees are genuinely the owner's, and one it does not

The six owner questions are correctly identified as owner questions, and options and costs are framed fairly
in five of them. One correction and one addition:

- **Owner question 5 is not really open in the form given.** Option (a) — keep 重新安装应用可以恢复。 — is not
  available once R7 is applied, because the copy would then only ever be shown for a genuinely damaged
  installation, where the instruction is true and there is no alternative. What remains open is only whether
  to add the export warning (option b), which is a copy-length question. Recommend reframing: "given that this
  message is now shown only when reinstalling is the sole remedy, does it warn about the History cost first?"
- **A seventh question the report does not ask.** R2 forces one: does the mid-game unavailable state's retry
  affordance live on the turn status (needing a glass exemption written into `:38`/`:42`) or in the play
  control cluster (already accepted glass, but mixing a recovery action into the play controls)? That is a
  visual-system decision with a contract consequence, not a designer's call, and it should be put to the owner
  alongside the other six.

## Bottom line

The ladder (§1) and the single threshold (§2) are the right shape and worth keeping; both need the corrections
at R2, R10 and R11 before they can generate anything safely. §4's central judgement — that mid-game engine
unavailability is a state and not an alert — is well argued from `:238`, `:269` and `:258`, and survives review
intact; what fails around it is the glass claim (R2), the "already accepted" framing of the retry trigger
(R3), the layout number (R4), the classification of `faulted` (R7) and the state's name (R8). §5's
indeterminate decision is correct and, on measurement, more strongly correct than the report claims; its
Reduce Motion mitigation needs rewriting (R5, R6). The copy needs the register restated (R9) and four strings
revised (R8, R9, R17, R18). Nothing in the report is wasted work, and none of the twenty findings requires
starting a section over.

---

# Independent review — second pass

A second adversarial verifier, reviewing **both** the report and the first review above. Method, all executed:
read all eight contracts in `MiniXiangqi/docs/` in full; re-pulled every Apple citation individually through
`mcp__xcode__DocumentationSearch` against the pinned Xcode 27 beta documentation; re-measured the first
review's Core Text figures with `xcrun swift` under `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`;
re-ran the workspace Fairy-Stockfish build (`Fairy-Stockfish/src/stockfish`) over a held-open UCI pipe to
re-test the `go movetime` claims; ran read-only `gh` under the `ppppvz` identity, including reading the
in-flight `mxq.h` on PR #26's branch. Nothing under `MiniXiangqi/` or any worktree was modified.

Fourteen new findings, **V1–V14**, plus a verification verdict on the first review's twenty.

---

## Part A — verdict on the first review

Everything I could check independently, checked.

**Confirmed by re-execution.**

- **R1 is confirmed verbatim.** *HIG > Alerts > Buttons* reads: "If there's a destructive action, include a
  Cancel button to give people a clear, safe way to avoid the action. Always use the title "Cancel" for a
  button that cancels an alert's action. **Note that you don't want to make a Cancel button the default
  button.** If you want to encourage people to read an alert and not just automatically press Return to
  dismiss it, **avoid making any button the default button.** Similarly, if you must display an alert with a
  single button that's also the default, use a Done button, not a Cancel button." The destructive-style quote
  is also verbatim on the same page. R1's correction — *no* default button rather than Cancel-as-default — is
  the page's own remedy and should be taken in both §8.1(1) and §3.3(3).
- **R4's measurement reproduces exactly.** Independent `CTFramesetter` line counting and
  `CTLineGetTypographicBounds`, system font, on the pinned toolchain:

  | String | 17 pt width | lines @308 / @340 / @370 |
  |---|---|---|
  | 当前可用内存不足。请尝试关闭一些其他 App，然后重试。 | **431.9 pt** | 17 pt: 2/2/2 · 20 pt: 2/2/2 · 28 pt: **3**/3/2 |
  | AI · AI 暂时无法走子 | 149.1 pt | 1 at every width and size tested |
  | 轮到黑方 | 67.4 pt | 1 |

  So the §4.3 state is 1 + 1 + 2 = **four text lines plus a control** at the 44 pt board floor and **five at
  28 pt**, exactly as R4 says. §4.7's "two lines plus a control" is an undercount by half. R4 stands.
- **The engine claims are confirmed, independently.** Same binary, variant `minixiangqi`, Hash 256, held-open
  pipe. Overrun on every level from the start position: `movetime 1000` → bestmove at **1037.5 ms**,
  `3000` → **3125.6 ms**, `5000` → **5026.1 ms**. Early return from `3k3/7/7/R6/7/7/3K3 w - - 0 1`:
  `go movetime 5000` → bestmove at **12.8 ms**, `info depth 245 seldepth 4 score mate 2 nodes 2187`. (My
  overrun figures differ from the first review's in the second digit — 3125 against 3003 — which is ordinary
  machine noise; the direction and the ~400× early-return factor are identical.) §5.3's conclusion is right
  and, as the first review says, understated.
- **R6, R14 and R16's counter-quotations are verbatim.** *HIG > Progress indicators > Best practices*: "Keep
  progress indicators moving so people know something is continuing to happen. People tend to associate a
  stationary indicator with a stalled process or a frozen app. If a process stalls for some reason, provide
  feedback that helps people understand the problem and what they can do about it." *HIG > Launching > Best
  practices*: "If you need a splash screen, consider displaying it at the beginning of your onboarding flow.
  … **If you don't provide an onboarding experience, you might display your splash screen as soon as launching
  completes.**" *HIG > Alerts > Best practices*: "Avoid using an alert merely to provide information. People
  don't appreciate an interruption from an alert that's informative, but not actionable."
- **R9's factual claims check out.** `grep` over `docs/*.md`: **应用 appears nowhere** in any accepted string —
  the sole precedent is 其他 **App** at `:284`, so the report's four uses of 应用 are a genuine, unannounced
  departure. Accepted action strings run **two to five** characters (保存并继续, 以和棋结束 are five), so §11's
  "two to four" is wrong at the top end as well as at the bottom.
- **R13 is confirmed on the text.** `testing.md`'s status line is "Nothing in this document is normative until
  its status or an individual section is explicitly marked accepted," and no section is so marked. The line
  numbers the report cites are right (`testing.md:59` and `:184` are the sentences quoted); only their
  normative force is wrong.
- **R17 is confirmed.** `core-interface.md:199` puts "too large" in `MXQ_DOMAIN_ARCHIVE`; `:210` puts the
  import time budget in the resource domain. §9's table conflates them.
- **The 59-run count reproduces** (`grep -oE '\*\*[^*]*[一-鿿][^*]*\*\*'`, unique), matching the first review.
- **PR territory re-checked.** `gh pr list --state open` today returns **#23** (`docs/interaction-design.md`,
  `docs/testing.md`), **#26** (core scaffold, no `docs/` files), **#27** (fixtures only). #26 and #27 do not
  touch the contracts, so the report's line citations are not stale.

**Corrections to the first review.**

- **R19's premise is wrong, and it should not be stated as a platform fact.** R19 says
  "`ContentUnavailableView`'s action slot renders as a prominent, tinted control by default on current Apple
  platforms." The documentation says no such thing.
  `ContentUnavailableView.init(label:description:actions:)` takes `@ContentBuilder actions: () -> Actions`
  where `Actions : View` — an arbitrary view the author supplies, whose button style the author chooses.
  Apple documents no default prominence for that slot. R19's *conclusion* is still worth one sentence in each
  of §10.1 and §6.3 — the `:44` reservation is closed and app-wide, so the action must be drawn untinted —
  but it must be written as an instruction to the implementer, not as a fact about the framework that the
  implementer would then discover to be false.
- **R7's criticism holds; R7's correction is speculative.** Routing `faulted` into "已损坏 / 重新安装" is
  wrong for the reason R7 gives, and it is the one place following the report's own copy destroys user data.
  But no accepted sentence says that a fresh `mxq_engine_prepare` after teardown clears a faulted engine;
  `engine-integration.md:32` is about *Hash allocation*, not about recovery from `faulted`. R7's fix should be
  proposed as ours, not derived. See **V2**, which supersedes R7 with a partition that is checkable against
  the header.
- **R2 is a real open question, and its option (b) trespasses.** The reading is fair: `:31` makes glass
  required *of* controls, `:38` fixes the custom count at three, and `:42` was thought necessary even for a
  non-control indicator. The counter-reading — that a standard system button in the turn status falls under
  `:38`'s "system-provided glass … additional and automatic" — does not survive, because that clause is a
  closed enumeration (tab bar or sidebar, navigation bar and toolbar, alerts, sheets, context menus, History
  swipe actions) and a free-standing button is not in it. So R2's conclusion stands: the exemption must be
  *asked for*. But R2's option (b), moving the retry into the play control cluster, puts the decision inside
  PR #23's territory, which this report has correctly ruled out of scope; it should be offered to #23, not
  taken here.
- **R9 convicts the wrong string in one place.** 好 as the **sole** action on a purely informational alert is
  exactly what the governing page permits: *HIG > Alerts > Buttons* — "In informational alerts only, you can
  use "OK" for acceptance"; "Avoid using OK as the default button title **unless the alert is purely
  informational**"; and, decisively, "if you must display an alert with a single button that's also the
  default, use a **Done** button, not a Cancel button" — so a 取消 there would have been wrong and an 好 is
  not. 好 is also Apple's own zh-Hans rendering of OK. **Keep string #20; fix §11's stated rule instead.**
- **R5, R3, R10, R11, R12, R15, R18 and R20 I re-read against the contracts and found sound**, with one
  amplification each at V1 (extends R5), V2 (supersedes R7) and V7 (extends R20).

---

## Part B — fourteen findings the first pass did not make

### V1 — HIGH. §4.3's automatic re-attempt makes the turn status oscillate between two heights, which §4.3's own next bullet forbids and §5.1's own requirement forbids. Measured

**Report, §4.3:** "**One automatic attempt, on each occasion a search becomes owed.** … Returning to the
foreground with a search still owed is such an occasion." And, two bullets later: "**During re-preparation the
state shows the ordinary thinking treatment** (§5) rather than a third "preparing" state."

**Report, §4.3, the bullet in between:** "**No automatic retries otherwise.** No timer, no polling. … a status
that **flickers between "thinking" and "unavailable"** every few seconds is worse than a static one."

**Report, §5.1:** "**The space is reserved.** The element's height and the label's baseline are identical
whether the indicator is present or absent, so the status does not grow by a line every AI turn and **the
board does not shift under it in the stacked layout**."

**What is wrong.** Put the three together. In the rung-4 state the user backgrounds the app and returns; a
search is still owed; an automatic attempt fires; the element collapses to the ordinary thinking treatment;
the attempt fails; the element expands again. Measured on the pinned toolchain at the 308 pt board core:

| What is shown | Text lines at 17 pt | at 28 pt |
|---|---|---|
| ordinary thinking treatment — 轮到黑方 / AI · 思考中 | **2** | 2 |
| rung-4 failed state — plus the message plus 重试 | **4 + a control** | **5 + a control** |

So the element swings by two text lines and a button, and in the stacked layout the board moves under it, on
every foreground return. That is (a) precisely the flicker §4.3 forbids polling in order to avoid — the report
rejects a timer for this reason and then reintroduces the same oscillation on a different trigger — and (b) a
direct breach of §5.1's own stated requirement, which the report calls "the requirement most likely to be
missed."

**Severity: high.** It is an internal contradiction between two of the report's three headline sections, and it
is what a reviewer with a device would see first.

**Correction.** Once the element has entered the rung-4 state, it holds its frame for the life of the state: a
re-attempt replaces only the *control's* label with the in-progress treatment (§2's own rule) and leaves the
state name and the explanatory line in place. Do not substitute the two-line thinking treatment. This also
removes the "思考中 is shown while the engine is loading" awkwardness §4.3 names honestly and then accepts,
and it is compatible with R5's correction (a).

---

### V2 — HIGH. §4.4's engine-failure taxonomy is a partition by "not memory" over a domain that has eight codes, three of which it leaves unrouted — and one of them has an accepted sentence saying where it must go

**Report, §4.4:** "If re-preparation fails for an engine-domain reason that is **not** memory —
`MXQ_DOMAIN_ENGINE`'s asset missing / mismatch, variant load failure, or faulted (`core-interface.md:200`) —
then … **AI 组件已损坏。重新安装应用可以恢复。**"

**Contract, `core-interface.md:200`:** `MXQ_DOMAIN_ENGINE` | 6000 | "insufficient memory, asset missing /
mismatch, variant load failure, **Hash allocation failure** (reserved; reachable only after the fork change),
**no move**, **illegal result**, faulted".

**Executed** — read of `core/include/mxq.h` on PR #26's branch, read-only via `gh api`, which enumerates the
domain concretely:

```
MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY    = 6001
MXQ_ERR_ENGINE_ASSET_MISSING          = 6002
MXQ_ERR_ENGINE_ASSET_MISMATCH         = 6003
MXQ_ERR_ENGINE_VARIANT_LOAD_FAILED    = 6004
MXQ_ERR_ENGINE_HASH_ALLOCATION_FAILED = 6005
MXQ_ERR_ENGINE_NO_MOVE                = 6006
MXQ_ERR_ENGINE_ILLEGAL_RESULT         = 6007
MXQ_ERR_ENGINE_FAULTED                = 6008
```

**What is wrong.** §4.4 names four of eight and selects the damaged-installation copy by the test "engine
domain **and** not memory". Three codes fall through that test into a message telling the user to reinstall:

1. **`6005` Hash allocation failure.** `engine-integration.md:112` already decides this one in as many words:
   "If allocation fails even though the calculated budget was at least 256 MiB, the AI does not start and the
   frontend presents the accepted **无法启动 AI 对手** notice **unchanged**. The situation the user is in is
   the same one — memory is not available right now." It is not `INSUFFICIENT_MEMORY`, so §4.4's test routes
   it to 已损坏 + reinstall — **contradicting an accepted sentence**, and instructing a data-destroying
   reinstall for a condition the contract says a retry can clear. The report's §3 has the right answer for the
   pre-start case and never carries it into §4's mid-game case.
2. **`6006` no move** and **`6007` illegal result.** These are not preparation failures at all: the engine is
   prepared and the *search* produces nothing usable. `core-interface.md:130` makes `6007` reachable by design
   ("Delivery applies the rejection ladder in order — cancelled → stale → malformed → **illegal under the
   rules facade** — and only a move surviving all four arrives as `MXQ_SEARCH_MOVE`"). The user-visible
   situation is exactly the one §4 owns — it is the AI's turn and the AI does not move — and **no contract and
   no section of this report says what the player sees.** This is a seventh gap, in the report's own assigned
   territory, and §0 does not list it.

**Severity: high.** One accepted-contract contradiction with a data-loss consequence, and one undesigned
user-visible state inside the report's own scope.

**Correction.** Partition by code rather than by "not memory", and say the partition out loud:

| Codes | Copy | Retry? |
|---|---|---|
| 6001, **6005** | the accepted memory message, verbatim | yes — `engine-integration.md:112` |
| 6002, 6003, 6004 | damaged-installation copy | no — retrying cannot succeed |
| **6006, 6007, 6008** | a recoverable class, its own line, **no reinstall instruction** | yes |

The third row needs one new string that the report does not currently have, and it is the row that keeps R7's
data-loss problem from recurring on two further codes. If the owner wants only two classes, the boundary must
be drawn so that no code whose remedy is unknown reaches the reinstall copy.

---

### V3 — MEDIUM-HIGH. The rung-4 state has entry conditions and no exit conditions, in the section whose whole thesis is that it is a state

**Report, §4.1:** "The condition **persists**. It lasts until a preparation succeeds, which may be never."
**Report, §1:** "Rung 4 … The condition is not a moment but a **state**, and lasts until something changes."

**What is wrong.** The report never says when the state leaves the screen. "Until a preparation succeeds" is
one exit; there are at least three more that the report itself creates or implies and does not name:

- **Undo.** §4.5's own table says Undo "Removes the human move that owes the reply … returning the turn to the
  human." At that instant the state's precondition is false — no search is owed, so by
  `engine-integration.md:72` no preparation is even attempted — yet nothing in §4 says the state clears, and
  §4.5's consequence column says only "Does not unstick the game." A state that survives the disappearance of
  the condition it reports is worse than an alert.
- **保存并继续 / selecting a new mode.** The active game is archived and cleared; there is no turn status.
- **Leaving Play and returning.** The condition still holds, so the state must return — which the report does
  not say either, and which matters because §4.6 says "announce it once … **never re-announce**." Once per
  what? Per entry into the state, per visit to Play, per app launch? A VoiceOver user who leaves and returns
  gets either a repeat every time or silence forever, and the report does not choose.

**Severity: medium-high**, because rung 4 is the one piece of new vocabulary the report introduces and this is
the part of it that a persistent state must specify.

**Correction.** Add an explicit clear rule: the state is shown exactly while the committed game owes a search
that no prepared engine can serve; it clears the moment either conjunct becomes false (successful preparation,
Undo, archive-and-clear, result commit). Scope §4.6's "announce once" to *each entry into the state*, and say
that re-entering Play with the condition unchanged re-announces.

---

### V4 — MEDIUM. §3.2's "every retry re-draws the side" is attached to the wrong failure and names a surprise the user cannot experience

**Report, §3.2:** "One consequence follows and **should be written down, because a user will otherwise be
surprised**: with **随机** selected, **每次重试都会重新抽取先后手** — accepted at `engine-integration.md:82`
… but never surfaced as something the interface implies."

**Contract, `engine-integration.md:79–82`:** "**Prepare** the engine from a fresh memory probe. Failure here
reports insufficient memory and creates nothing. 2. **Resolve** a Random first-mover choice … **only after
preparation succeeds**."
**Contract, `interaction-design.md:194`:** "**随机** remains unresolved and previews Red at the bottom.
Successful game creation flips the board only if Random resolves to **AI 先手**."

**What is wrong.** Two things, and §3.2 is the insufficient-memory section.

1. **In the failure this section is about, no side is ever drawn.** Insufficient memory is a step-1 failure.
   Step 2 runs "only after preparation succeeds", so resolution never happened and there is nothing to
   re-draw. The re-draw is real only for the *persistence* failure, which §3 does not cover.
2. **Even there, nothing is observable.** `:194` fixes that Random previews Red regardless and that the board
   flips only on successful creation. So a resolved side is never shown before it is committed; the user sees
   exactly one resolution, once, when a game actually exists. There is no second resolution to compare it to,
   and therefore no surprise.

**Severity: medium.** This is a claim presented as a finding the contract "never surfaced", offered as
something to write into the contract, and it is a fact about an internal step with no user-visible
consequence — the brief's "numbers attached to the wrong experiment", in prose form.

**Correction.** Delete the surprise framing. If anything is worth recording it is the opposite and it belongs
in §6.2, not §3: after a **persistence** failure, the side already resolved in step 2 is discarded, so a
retry is a fresh draw — which `engine-integration.md:82` already states and which the user still never sees.

---

### V5 — MEDIUM. The AI-thinking indicator has no minimum on-screen duration, so it can flash — the exact defect the accepted 500 ms threshold exists to prevent

**Contract, `:424`:** "If the search has not returned within 500 ms of the player's move, the turn status shows
AI activity; below that threshold nothing appears, **because an indicator that flashes for a fifth of a second
is noise**." And: the AI's piece departs "at the later of two instants: when the search returns, and 260 ms
after the player's own move has finished animating."

**Report, §5.1:** "**Appearance:** at the accepted 500 ms threshold, **fading in over 120 ms**.
**Disappearance:** at the instant the AI's piece departs … not at search return."

**What is wrong.** Take a search that returns at 520 ms with the player's move animation finished at 200 ms.
Departure is at `max(520, 460) = 520 ms`. The indicator begins a 120 ms fade-in at 500 ms and is removed at
520 ms — **20 ms of a 120 ms fade**. The band of search durations that produce a sub-120-ms appearance runs
roughly 500–620 ms, and it is not a rare band: it is exactly the band adjacent to the threshold. The accepted
sentence bounds the flash from below and the report's departure rule reintroduces it from above.

**Severity: medium.** It defeats the stated purpose of the one number the report elevates into a universal
rule, in the one case the contract already decided.

**Correction.** Give the indicator a minimum visible duration — ours, first-version in the sense of `:432` —
and let it be *the third instant the departure waits behind*, alongside `:424`'s two. Or, cheaper and with no
change to `:424`: state that the fade-out cancels and reverses an incomplete fade-in, so the worst case is a
short symmetric pulse rather than a hard cut. Either way the report must say which, because §12's gates
currently cannot detect the case.

---

### V6 — MEDIUM. Four import rejections are specified as alerts with no actions, and the duplicate message does not discharge the accepted requirement it replaces

**Report, §7.1's map:** "| Import rejection | 3 | **alert** | four messages, §9 |"
**Report, §9:** four titles/messages plus one success message. No button is named for any of the five.
**Report, §11:** the only action string it proposes is **好**, "sole dismissing action on the damaged-assets
alert" — assigned to §4.4, not to §9.

**Contract, `interaction-design.md:384`:** "An exact duplicate does not create a second record and **offers a
way to view the existing record**. A stable-identity conflict with different game content is rejected with an
explanation."

**What is wrong.** Two gaps in the artefact §9 explicitly asks 7.2 to "take or reject **whole**".

1. **No dismissing action for any of the four rejection alerts.** A rung-3 alert without a button is not a
   presentation. Whoever takes §9 whole will invent four action strings the report did not count, which
   defeats §11's stated purpose ("they are listed so part 6's total is known").
2. **String #19 alone cannot satisfy `:384`.** 这盘棋已经在历史中。 states the fact; the accepted sentence
   requires the app to *offer a way to view the record*. §9 classes the duplicate as "success, not an error"
   and gives it a message, then defers the affordance to 7.2 — so the copy as proposed is a message that,
   lifted by itself, would leave an accepted requirement unmet.

**Severity: medium.** The section's value is that it can be adopted as a unit; as written it cannot.

**Correction.** Name the dismissing action for the four rejections (**好** is the same purely-informational
case the HIG permits it for, and reusing it costs nothing), and mark #19 explicitly as *message plus a
required viewing action whose label is 7.2's* rather than as a complete item.

---

### V7 — MEDIUM. §7.1's "full map, after this report" is not full: four reachable store failures have accepted requirements, no copy, and no row

**Report, §7.1:** "The full map, after this report … **Every row is at exactly one rung. No failure appears
twice.**"

**What is missing**, all of them user-visible, all with an accepted sentence behind the operation and none with
a presentation anywhere:

- **Export failure.** `:376` "**共享** exports the selected History record as one game file"; `mxq_store_export`
  is fallible.
- **Pin / unpin failure.** `:374` "A left-to-right swipe reveals **置顶** or **取消置顶**. A complete swipe
  invokes that **reversible action immediately**." Immediately means the user has already seen the row move
  before the transaction can fail, so a failure has to visibly undo a change they watched happen — the one
  case in the app where a failure must reverse something on screen, and the ladder has no rung for it.
- **Opening a History record for replay fails.** `:370` "Selecting an entry opens its read-only replay";
  `mxq_store_history_open` can return store- or archive-domain failures.
- **Resuming the active game fails while the store itself opens.** Distinct from §6.3's "store cannot open":
  the library opens, History lists fine, and the one game the user wanted is unreadable. `product.md:46`
  makes resume an accepted promise ("The active game is saved automatically and **can be resumed** after the
  application exits and reopens"), and `mxq_game_resume_active` is fallible independently of store open.

**Severity: medium.** §0 is the report's own gap register and §7.1 claims completeness; four omissions of the
same kind as the four §0 does list is a defect in the claim, not only in the coverage.

**Correction.** Either add the rows — three of the four fall out of the ladder without argument (export and
open → rung 3 with the archive-failure family's shape; pin → rung 1, since the state is unchanged and the
gesture is repeatable) — or narrow the claim to "every failure this report designs".

---

### V8 — MEDIUM-LOW. §3.4's held-open alert produces an undesigned rung 3 → rung 2 sequence from a single press of 重试

**Report, §3.4:** "The alert is **not dismissed and re-presented** on retry. It remains, and the retry runs
behind it." … "**On a successful retry**, the alert dismisses and creation proceeds."
**Report, §1:** "**One rung per failure.** No failure is reported twice, and none escalates from one rung to
another."

**What is wrong.** `engine-integration.md:79` makes 重试 the whole `prepare → resolve → create → search`
sequence from step 1 — §3.2 says so itself. So a successful *preparation* does not end the operation: steps 2
and 3 still run, and step 3 can fail. The user presses 重试 inside a rung-3 alert, the alert vanishes, and a
rung-2 inline line appears beneath **开始对局** a moment later. §1's rules are not violated — these are two
different failures — but the ladder's purpose is to make presentation predictable, and the one transition
between rungs that a single gesture can produce is undescribed.

**Severity: medium-low.**

**Correction.** One sentence in §3.4 naming the sequence: a retry that clears preparation but fails
persistence dismisses the alert and reports the persistence failure at rung 2, because the failure changed.
Then say whether the streak counter resets (it should — §3.3 makes it reset on "any successful preparation",
which this is).

---

### V9 — LOW-MEDIUM. Two of §3.1's supporting statements do not support anything

**(a) The macOS sheet reason is inert.** Report: "On macOS the alert is a **window-modal sheet**, not an
app-modal panel, **because the app has one main window** (`product.md:26`)." With exactly one main window,
window-modal and app-modal are behaviourally near-identical — so `:26` is the reason the distinction barely
matters, not a reason to prefer one. The conclusion is right for a different reason (a sheet is the macOS
convention for an alert raised by a window's own operation); cite that instead.

**(b) The single-flight claim is false as stated.** Report: "**The alert's presence is what enforces the
accepted single-flight rule on 开始对局 while it is up.**" When the memory alert is up, no creation attempt is
in flight: `engine-integration.md:81` says a preparation failure "creates nothing", and `game-data.md:94`
binds single-flight to an *attempt*. There is nothing to enforce. Worse, `interaction-design.md:198` says the
failure "**re-enables 开始对局**" — a re-enablement the modal alert makes unreachable until 取消 is pressed.
The two are reconcilable (the button is enabled behind the alert and reachable after 取消) but the report
should reconcile them rather than assert that the alert is doing work the contract assigns elsewhere.

**Severity: low-medium**, twice — both are justifications that do not survive their own sentence.

---

### V10 — LOW. §11's register is undercut a third time, inside the same table, by its own two adjacent empty-History strings

Beyond R9's three: **#10 还没有对局记录** and **#11 完成或保存一局棋后，它会出现在这里。** are the title and
description of *one* state and use two different words for a game — 对局 in the title, 棋 in the description.
The accepted set uses **对局** for a game everywhere (开始对局, 结束对局, 当前对局, 开始新对局？,
这盘对局将按当前状态保存到历史。) and **这盘棋** only in 删除这盘棋？, where it names a *record*. Since the
empty state is about records, either both should be 棋 or both 对局; as written the two lines read as if they
are about different things.

**Correction.** Normalise the pair, and add the rule R9 asks for. And, per Part A, keep **好**.

---

### V11 — LOW. §4.5 cites a sentence whose precondition is false in the state it describes

**Report, §4.5:** "**悔棋** (Undo) … Removes the human move that owes the reply (`:328`)."
**Contract, `:328`:** "In human-versus-AI play, Undo **while the AI is thinking** cancels the search and
removes the human move that triggered it."

In the rung-4 state the AI is not thinking and no search exists, so `:328` does not apply on its face, and
`:329` ("After the AI has replied") does not either. `game-data.md:103`'s disjunct — "cancels an outstanding
reply search **and removes the triggering human move**" — reaches the case only by reading past its first
clause. **Correction:** cite `game-data.md:103`, and note plainly that no accepted sentence squarely covers
Undo when a search is owed but not running. It is a small contract gap and it belongs in §0 rather than being
papered over with a citation that does not fit.

---

### V12 — LOW. `updatesFrequently`'s documented meaning is narrower than the use §4.6 makes of it

**Report, §4.6:** the turn status "takes the `updatesFrequently` trait **so assistive technology does not try
to speak every change to it**."
**Documentation, `UIAccessibilityTraits.updatesFrequently`:** "The accessibility element frequently updates its
label or value." That is the whole definition. Apple documents no suppression behaviour.

The report is scrupulous elsewhere about marking what is ours; this one reads as a documented guarantee and is
a conventional expectation. **Correction:** state the trait's documented meaning and mark the suppression
effect as ours, or drop the causal clause.

---

### V13 — LOW. §6.1 declines a second explicit HIG preference silently — the same fault R6 finds in §5.4

**Report, §6.1:** "No blocking overlay, no dimming, **no cancel button** — leaving *is* the cancel."
**Not cited, *HIG > Progress indicators > Best practices*:** "**When it's feasible, let people halt
processing.** If people can interrupt a process without causing negative side effects, include a Cancel
button."

Game creation is precisely the feasible case: `game-data.md:94` makes it invalidatable with no persistent
effect, which is what "without causing negative side effects" means. The report's conclusion is probably still
right — leaving the page is an accepted, documented cancel, and a second control on a two-control page is
noise — but §5.3 sets the standard for how this report names a declined preference, and §6.1 does not meet it.
**Correction:** quote the sentence, concede it, and rest on `interaction-design.md:197`/`:206`, which already
give leaving the cancel semantics.

---

### V14 — LOW, and in the report's favour. Two Apple sentences that support §6.3 more directly than anything it cites

**§6.3's store-cannot-open state has direct authority the report did not find.** *HIG > Alerts > Best
practices*: "**Avoid showing an alert when your app starts.** If you need to inform people about new or
important information the moment they open your app, design a way to make the information easily discoverable.
**If your app detects a problem at startup, like no network connection, consider alternative ways to let people
know. For example, you could show cached or placeholder data and a nonintrusive label that describes the
problem.**" That is Apple saying, in the launch case specifically, what §6.3 argues from first principles.

**And *HIG > Loading > Best practices*** supports the launch skeleton: "**Show something as soon as possible.**
If you make people wait for loading to complete before displaying anything, they can interpret the lack of
content as a problem with your app or game. Instead, consider showing placeholder text, graphics, or animations
as content loads."

Together with R14's correction (drop the onboarding inference, keep "Don't advertise"), §6.3 ends up better
supported than it started. Worth adding because §6.3 currently rests its strongest claim on the one inference
the source reverses.

---

## Bottom line of the second pass

The first review's twenty findings hold, with two corrections: **R19's factual premise about
`ContentUnavailableView` is not documented and should be restated as a design instruction**, and **R9 convicts
好 wrongly — the HIG permits it exactly here**. R7's criticism is right and its fix should be replaced by
**V2**, which partitions the engine domain against the header rather than against "not memory" and catches two
further codes, one of them contradicting an accepted sentence.

Of my own fourteen, three are the ones that must be fixed before this goes to the owner: **V1** (the turn
status oscillates between two heights and the report forbids exactly that flicker two bullets earlier),
**V2** (Hash-allocation failure is routed to a reinstall instruction against `engine-integration.md:112`, and
`no move` / `illegal result` are an undesigned mid-game state inside this report's own scope), and **V3** (the
one new rung has no exit conditions). **V4** and **V5** are the two places where a claim is attached to the
wrong case. The rest are precision.

The report's central judgements survive both passes: mid-game engine unavailability is a **state** and not an
alert; the AI-thinking indicator is correctly **indeterminate**, and the measurement above makes that stronger
than the report claims (12.8 ms against a 5,000 ms promise, and overrun at every level); the empty-state
editorial correction on the Play start state is right; and the four-message import taxonomy is right for the
reason the report gives, subject to R17's domain fix. The ladder and the single threshold are the right shape
and, with R2, R10, R11 and V2 applied, are safe to generate from.
