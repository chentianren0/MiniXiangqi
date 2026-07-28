# Parts 6, 7, 8 — decision agenda for the product owner

Workspace-only research note. Not a contract, not a proposal for merge. Assembled from nine verified research
reports and four contract audits, against `MiniXiangqi` at `cb75f17` (contracts unchanged since `60fc044`).

**How to use this.** §1 is the only part you have to act on: **39 decisions** — 27 that need discussion,
grouped so that decisions which constrain each other are decided together, plus 12 bounded one-line calls —
ranked by how much each unblocks. §2 is the defect list: 34 items, none of which needs you, but the first
eleven produce wrong behaviour and should not wait. §3 is the new Chinese copy, which becomes normative on
approval because Chinese is the source language. §4 is the order.

**Method.** Everything marked *executed* I ran here and the output is quoted. Everything marked *computed* I
recalculated from numbers in the accepted contracts. Everything else is read from a cited contract line or is
my reasoning, and is labelled as such. Line references are `document:line` at the commit above.

---

## 1. What needs the owner

Twenty-seven discussed decisions (Groups A–G) plus twelve bounded one-line calls (Group H). I dropped nine
that the reports raised and that a designer can settle — they are listed at the end of this section with what
settles them, so you can see they were considered rather than lost.

The reports raised roughly 46 owner decisions between them. Eight were the same question asked twice by two
reports and are merged here; nine are dropped as designer's calls; two are escalated from a report's blocking
list because they change accepted contract text; three come from the audits rather than the reports.

---

### Group A — Terminology (4 decisions). Decide first; everything in parts 6, 7 and 8 depends on it.

#### A1. Is the piece called **General** or **king** in English? ★ highest unblocking value

Two accepted contracts disagree, in one word, in ten places.

- `interaction-design.md:74` fixes the accepted English names as *General, Chariot, Horse, Cannon, Soldier*.
- `xiangqi-rules.md` says *king* at `:28`, `:29`, `:35` (×2), `:42`, `:43`, `:52`, `:66`, `:100`, `:104`.
- `engine-integration.md` contradicts itself: `:43` "generals and soldiers", `:53` and `:125` "kings and
  soldiers", in one document.
- `testing.md:92` "king and soldier chase-target exclusion" against `:186` "a checked general".
- `fixtures/rules/mx-end-003.json` manages both inside one title: *"Flying general: a move exposing facing
  kings…"*.

| Option | Cost |
|---|---|
| **Affirm General** *(recommended)* | Edit `xiangqi-rules.md` at ten lines, `engine-integration.md:125`, `testing.md:87`/`:92`, `game-data.md:175`, and the prose fields of six fixtures. Keep *flying general* as the rule name; leave `from_square` and `MxqColor` alone. |
| Adopt king | Edit `interaction-design.md:74` instead — one line. The app then teaches a name no Xiangqi book uses, and the pair 帅/将, both of which mean *general*, is left unexplained in Help. |

**Reasoning for General.** `interaction-design.md` is the only document that claims authority over English
piece naming and over terminology consistency (`:459`). The Chinese anchors are 帅/将 and the check token
将军; *king* has no anchor in the accepted Chinese at all. And `:395` makes Help a rules reference written
from `xiangqi-rules.md`, so *king* leaks straight into the one English surface a learner reads, beside a
board drawing 帅.

Two reports frame this as genuinely open; the copy audit and I both read it as already settled by which
document owns the term. It is on your desk as *confirm or overturn*, not as an open question, because either
answer edits an accepted contract.

Related and settled by the same answer: `xiangqi-rules.md` names one condition three ways — "kings facing"
(`:43`, `:104`) and "the flying-generals condition" (`:76`). One name, whichever piece word wins.

#### A2. What does **move** mean in English — one player's move, or a chess move?

`game-data.md:143` stores move count in plies. 步 says *ply* unambiguously to a Chinese reader. "42 moves"
will be read by a chess-literate user as twice that.

| Option | Cost |
|---|---|
| **"42 moves", where a move is one player's move** *(recommended)* | A chess reader silently halves it. Help, the move list and the notation must each define the term once. |
| "42 plies" | Exact; jargon in a beginner's app, in every History row. |
| "42 half-moves" | Exact and plain; ~1.5× wider, which worsens the measured English overflow in A/B below. |

**Reasoning.** 步 is the Xiangqi convention in both languages, it matches the app's own Undo vocabulary, and
the internal storage unit is unaffected. This propagates into A1's Help text, the History row, and the
notation, so it must be answered before any English copy is written.

#### A3. Is a board location a **point** or a **square**?

Not cosmetic — the two accepted contracts use opposite words, and one of them is the frozen coordinate
contract.

- `interaction-design.md:120`: "The board is never drawn as a checkerboard of squares, which would … teach a
  beginner the wrong mental model." The whole document then says *point*.
- `xiangqi-rules.md` uses **square** ten times *as the board term* and never uses *point* — including the
  frozen coordinate sentence (`:34` "Squares are named a1 through g7"), the canonical notation (`:36`), the
  movement rules (`:42`, `:44`, `:47`), and the bolded accepted interpretation (`:75`). *(executed: `grep -o
  square xiangqi-rules.md | wc -l` → 10; `grep -n point` → no board use.)*
- `core-interface.md:68` freezes `from_square` in the C API.
- `interaction-design.md:227`, `:440` and `testing.md:159` say "illegal square" inside the document that
  forbids the word.

| Option | Cost |
|---|---|
| **Point in all prose; machine identifiers unchanged** *(recommended)* | Rewrite ~10 lines of `xiangqi-rules.md`, `interaction-design.md:227`/`:440`, `testing.md:159`, and add one sentence saying `from_square`, `start_fen` and the `a1`–`g7` naming keep their spelling. |
| Square everywhere | One line of `interaction-design.md` deleted; the teaching argument at `:120` is abandoned. |

One research report asserts that "square appears nowhere as a board term, deliberately". That is false, and
it matters: this is the largest cross-contract terminology conflict in the set, and it reaches the frozen
coordinate contract and the frozen C interface. See §5.2.

#### A4. What is a board location **called out loud**?

Traditional notation has no absolute coordinate for a point — files are numbered from each player's own right
and `interaction-design.md:167` says ranks carry no labels. A VoiceOver model in which the user addresses 49
locations must therefore invent a name. New normative Chinese vocabulary, and a teaching decision.

| Option | Cost |
|---|---|
| (a) Per-side file and rank — 三路四 | Extends the accepted per-side numbering and flips with the board; every number is in the user's own frame. One location has two names, one per side — though `:163` already accepts exactly that for files. Invented vocabulary no book reinforces. |
| (b) Canonical `a1`–`g7` | Already exists, stable for both sides, survives a flip, is what an archive and a fixture contain. Latin letters read awkwardly under a Chinese voice, and a second coordinate system pulls against `:161`'s reason for choosing traditional notation. |
| **(c) (a) spoken, (b) available on request as default-importance custom content** *(recommended)* | Near zero to build; one more entry in the More Content rotor. |

The seven rank words (第一线 … 第七线) are part of this decision, not separate — one report proposes them as
approvable copy while leaving rank naming open in the same document. Constrained by A3: if A3 chooses
*square*, option (b) becomes the cheaper answer.

---

### Group B — Does the English build get the same shapes as the Chinese? (3 decisions)

`interaction-design.md:455` makes Simplified Chinese the source language and English "translations of it";
`:533` says no English has been approved. The 60-string English job is really a 46-string job — 11 strings
already have accepted English and 3 more are settled by accepted prose — but three shape questions have to be
answered before any of it is written.

#### B5. Does the middle-dot metadata composition survive in English?

Measured, two ways, on two surfaces, agreeing:

- Against the accepted 308 pt board block at the 44 pt pitch floor, at 17 pt: **every** Chinese metadata line
  fits on one line; **four of eight** realistic English equivalents overflow, by 27 to 111 pt. Worst:
  *Human versus AI · You: Black · Ended Early · 128 moves* at 419.2 pt.
- In the History row (insetGrouped, 375 pt container → 311 pt text width, iOS 27 simulator), at the default
  text size: every Chinese variant fits on one line, every English variant needs two. Row height 63.33 pt
  Chinese, 83.33 pt English.

| Option | Cost |
|---|---|
| **Keep one dot-joined run and let it wrap** *(recommended)* | Zero copy change. English rows are 83 pt against 63 pt at the default size — about 24% fewer rows per screen, reaching 441 pt per row at AX5, in the stacked layout `:515` already flags as constrained. |
| Drop English to 13 pt | **This option does not exist.** Re-measured: at 13 pt two lines are 309.1 pt and 334.2 pt against a 308 pt block. The worst line first fits at about 12.5 pt. |
| Label/value rows in English only | The accepted example lines at `:305` no longer describe the English build; parts 4 and 7 inherit a second layout. |
| Shorten the English end-reason names | "Mutual Perpetual Chase" has no shorter accurate form. This is a terminology change, not a layout one. |

#### B6. May English be **terser** than its normative Chinese source?

The Chinese is terse and uses 请 in exactly three places (`:284`, `:350`-family and the retry copy — one
report says two; see §5.3).

| Option | Cost |
|---|---|
| Mirror the source, carrying "Please" wherever 请 appears | Collides with HIG *Alerts → Buttons* ("Avoid explaining alert buttons") — a "Please try again" message sitting above a Try Again button — and grows the save-failure capsule from 266.8 to 318.0 pt. |
| **Follow the HIG and let English be terser** *(recommended)*, **and amend `:455` to say so** | The English build says slightly less than the normative copy in two places. Amending `:455` is what keeps the normativity claim true rather than quietly false by design. |

#### B7. What does a reader who cannot read the characters get from the move list?

This is one decision that three reports raise separately: the icon-symbol reader (`interaction-design.md:520`),
the English build's *spoken* move list, and the missing accessibility-label requirement for untranslated game
content. **Answer it once or the three answers will diverge.**

| Option | Cost |
|---|---|
| Nothing further | Zero build cost. The user who chose icons because they cannot read 兵 and 俥 gets help on the board and none in the list; an English-reading blind user cannot follow a game at all. |
| **A legend in Help, plus a spoken layer: the Chinese label with its speech language set, and an English gloss as default-importance custom content** *(recommended)* | Two forms to keep in step; an English rendering of the notation grammar is new work; the gloss must be asked for each time. |
| An always-visible move-list legend | Permanent vertical space in the layout that is tightest exactly at accessibility text sizes. |
| Icons inline in the list | Highest cost: the string stops being traditional notation and cannot be carried into a book, which is `:161`'s stated reason for choosing it; contradicts accepted `:168`. |

**One thing you cannot buy either way.** Two of the five accepted piece characters carry a Xiangqi-specific
reading a general Chinese voice gets wrong — 车 is *jū* not *chē*, and 将 as the Black general is *jiàng*
while 将军 (check) is *jiāngjūn*, the same character wrong in both directions inside one app. Apple documents
the fix (`accessibilitySpeechIPANotation`) and the same page states it is not used on macOS. Record it as a
platform gap.

---

### Group C — Rules truth (2 decisions). Executed here; the first produces a wrong game result today.

#### C8. A protected rook chased by a horse or a cannon: amend the rule, or patch the fork? ★

**Executed** against the pinned engine (pyffish `(0,0,89)` at `discussion-drafts/w-base`, variant
`[minixiangqiaxf:minixiangqi] chasingRule=axf nMoveRule=0 nFoldRule=3`):

```
4k2/7/r3r2/3N3/7/7/2K4 w   d4b3 a5b5 b3d4 b5a5 ×2  → is_optional_game_end = (True, -32000)   Red LOSES
4k2/7/c3r2/3N3/7/7/2K4 w   d4b3 a5b5 b3d4 b5a5 ×2  → is_optional_game_end = (True, 0)        draw
```

The black rook is defended by a black rook on e5 throughout. `xiangqi-rules.md:64` says a perpetual chase of
an **unprotected** target is a loss, and `mx-chs-002`'s rationale says "Chasing a protected piece is not a
perpetual-chase violation". The engine adds a rook attacked by a horse or a cannon to the chased set *before*
the protection test — AXF's 以低子捉高子 class. The identical shape with a cannon target draws, which proves
the protection machinery works and is simply bypassed for this class.

This is not the deferred protection question at `:119`: the target is protected under every definition. It is
reachable in ordinary play — two rooks, two horses and two cannons a side on a seven-file board — it commits
automatically at the third occurrence with no claim gate, and it decides the game against a player who
committed no violation under the accepted rules.

| Option | Cost |
|---|---|
| **Adopt the stronger-piece class as a fourth accepted interpretation in `xiangqi-rules.md`** *(recommended)* | Two sentences of contract text, no code change. `:64`'s "unprotected" becomes conditional; `mx-chs-002`'s rationale gains a sentence; Help's 长捉 topic grows. It is an interpretation the normative source does not settle, exactly like the three at `:74`–`:76`, and should be recorded as one. |
| Patch it out of the fork | A sixth focused change, a deliberate divergence from the adjudication every other chasing variant uses, and a permanent cost at every upstream merge. |

Either way, two fixtures must land: horse versus protected rook, horse versus protected cannon. The executed
FENs above are the constructions.

#### C9. Does the deferred fixture tranche gate the first internal build?

`xiangqi-rules.md:121` asks for approval "before the rules facade's chase adjudication is relied on beyond
the first approved set"; whether internal TestFlight counts is undecided.

| Option | Cost |
|---|---|
| **Gate on the parity-correction fixture and the mutual-chase corner only** *(recommended)*, plus C8's two | Some schedule. `engine-integration.md` already requires the parity fixture to land with its change, so this is nearly free. |
| Gate on the whole tranche | More schedule; the constructions exist, the approvals do not. |
| Gate on nothing | Testers play against an engine whose three accepted interpretations have no fixture, in a variant whose parity defect is the difference between a draw and a wrong-winner loss. |

**Reasoning for the middle.** The parity defect's failure mode is a *wrong winner*; the rest of the tranche
costs at worst a claimable draw where a loss was due. Those are not the same risk.

---

### Group D — What the accessibility commitment actually is (4 decisions)

#### D10. Is an end-to-end nonvisual game a **supported capability** or a best effort? ★

Two reports raise this independently. It is one decision, and it sizes the entire VoiceOver model, the
VoiceOver acceptance criteria, and part of `testing.md`. `testing.md:149` already asserts it — inside a draft
document, so nothing is committed.

| Option | Cost |
|---|---|
| **Supported and gated on Apple platforms, with Windows explicitly deferred in the same sentence** *(recommended)* | The pass condition becomes a release gate that needs physical hardware — VoiceOver is not available on Simulator — so it cannot be satisfied before a device matrix exists. |
| Best effort | Nobody is accountable for the model surviving contact with the app, which in a design-first repository is how a model quietly degrades to labels-only. |
| Out of scope for the internal MVP | Contradicts `:15` ("Treat accessibility as part of the design, not as a later visual adjustment") and the six commitments at `:442`–`:451`, which would have to be amended rather than left alone. |

**Reasoning.** Only the first keeps `:15` honest without writing a cheque on a frontend that does not exist.
The honest counter-question, which is yours and not mine: for a small internal Xiangqi group, will anyone in
it use it?

#### D11. Does the product claim an external accessibility standard?

The accepted numbers are WCAG-AA-shaped and match the table Accessibility Inspector uses.

| Option | Cost |
|---|---|
| **"We meet these specific numbers"** *(recommended)* | Zero extra work; every criterion is already written this way. No external name to point at — which, for internal-only distribution, costs nothing. |
| "WCAG 2.2 Level AA" | Imports focus visibility, target size, reflow and status messages, none of which has been audited. It turns two of the §2 defects (focus-ring contrast, pinned-state carrier) from discussions into failures, and someone must audit against all of it. |
| Apple Accessibility Nutrition Labels | Documented for App Store Connect; `product.md:14` makes distribution internal only, so it is a claim with no audience. |

#### D12. Which alternative input modes are supported?

Three separate yes/no answers, none of which appears anywhere in the contracts today.

- **Full Keyboard Access on iPad and Mac** — recommend **yes**. `:233` (select / inspect / select) and `:253`
  (the focus marker) already presuppose most of it. Saying no costs a keyboard-only user the board entirely
  on iPad. It makes 49 board locations focusable, which interacts with the VoiceOver element granularity.
- **Switch Control** — recommend **yes**. Probably nearly free, since tap-to-move already exists as the drag
  alternative; but "probably" is not a criterion and one confirming sentence is worth having.
- **Voice Control** — recommend **defer until A4 lands**. It requires every location to have a speakable
  name, which is exactly A4; deciding it before A4 decides A4 by accident.

#### D13. Does Windows meet the same bar?

| Option | Cost |
|---|---|
| **Apple-platform criteria today, with a stated commitment that Windows will be held to an equivalent bar written when its frontend is designed** *(recommended)* | An explicit admission that the two platforms are not at parity — true, and better said than discovered. |
| Platform-neutral criteria that Windows must already meet | Every criterion gates a platform that does not exist. |

---

### Group E — Failure and error scope (5 decisions)

#### E14. How many distinct user-visible import rejection messages?

Raised by two reports as one decision. The accepted floor is two: `game-data.md:64` mandates a distinct
created-by-a-newer-version message never presented as corruption.

| Option | Cost |
|---|---|
| Two | Tells a user re-importing their own valid but oversized game that the file is invalid — `game-data.md:62` makes that reachable and it is false — and presents an identity conflict as corruption when it is not. |
| **Four, cut so each implies a different next action: pick a different file / get a new copy / update the app / retry** *(recommended)* | Four strings to write, translate, review and test. The 2 s validation-budget timeout folds into "invalid or too large", which is the least comfortable seam. |
| Seven or more, one per class | Maximally honest; produces several messages a user cannot act on differently. |

Note: the two reports propose *different shapes* for the same four — one title with four messages, versus six
separate titled alerts. The count is yours; the shape is a designer's. See §5.4.

#### E15. When the engine cannot be re-prepared mid-game, is Retry the only exit the state offers?

Undo, save-and-continue and resignation all remain reachable as ordinary furniture regardless.

| Option | Cost |
|---|---|
| **Retry only** *(recommended)* | A user with a persistent memory problem can never finish that game *as* a human-versus-AI game; their exits record it as ended-early or a resignation loss. The archive never says anything untrue. |
| Offer to convert the game to Free Play | **This is not a UI decision.** Mode is frozen at creation, and `human_side`, `ai_level` and `ai_movetime_ms` are present exactly when mode is `human-vs-ai` (`game-data.md:38`, `:48`), so a mid-game mode change needs archive version 2 or a record that misdescribes the game it contains. |
| Offer 结束对局 from inside the state | A second path to the ended-early classification the mode entries already provide, and an ending action inside an error state. |

#### E16. Does repeated insufficient-memory failure eventually offer a third action?

| Option | Cost |
|---|---|
| **No — 取消 and 重试 only** *(recommended)* | A user on a constrained device gets no AI and the app never says what else they could do. |
| A third action from the third failure: 开始自由对弈 | A mode switch reached from an error, which no other path in the app does, and an alert that grows a third button it did not have the first two times. |
| A third action offering Help | Help is a rules reference with nothing to say about memory (`:395`). Listed for completeness only. |

#### E17. What does the app tell a tester when the store cannot be opened at all?

The schema-too-new case is answerable ("update the app"). The corruption case is not, because every honest
remedy costs data.

| Option | Cost |
|---|---|
| Say only that the data cannot be read, offer a relaunch | A permanently unusable app if the corruption is persistent, with nothing the user can act on. Following the advice destroys nothing. |
| Name reinstalling | On iOS and iPadOS reinstalling deletes the container and every unexported History record. The app would be instructing the user to destroy their data. |
| **An explicit "start a new library" action that moves the damaged store aside** *(recommended, and say in the copy that it is an internal build)* | The app gains a data-destroying-looking button no accepted contract describes, and the user's History disappears from their point of view. Nothing is actually deleted, and the damaged file survives for diagnosis — which is the whole point of an internal build. |

#### E18. Does the damaged-assets copy tell the user to reinstall, given what that costs them?

`engine-integration.md:156` says "reinstalling restores the AI" — true of the AI, silent about the History it
also removes on iOS and iPadOS.

| Option | Cost |
|---|---|
| Keep the short instruction | A user who follows it loses every unexported game. |
| **Warn first: tell them to export anything they want to keep** *(recommended)* | A longer message in a small state, and it presumes they know what export is. Nobody is instructed into data loss. |
| Say nothing about the remedy | Tells the user the AI is broken and gives them no way out. |

---

### Group F — Surface scope (5 decisions)

#### F19. Does Help admit the app's own rules interpretations?

`xiangqi-rules.md:74`–`:76` records three interpretations the source does not settle; two are visible to a
player. The contract itself calls 一将一捉 "the interpretation most likely to be wrong" and notes that
"competition practice is commonly summarised as forbidding the alternation".

| Option | Cost |
|---|---|
| **Both, in a short closing note in 长捉** *(recommended)* | A paragraph and some humility. A competition-trained tester reads it as a decision rather than a bug — and this build's testers are exactly that population. |
| 一将一捉 only | The commoner case; leaves the sole-defender case to be discovered. |
| Neither | A user who expects a win by 长捉 and gets a claimable draw has nowhere in the app to find out why, and will file it as a rules bug. |

#### F20. May a Help diagram be stepped through, and how large may Help grow?

Two questions with one answer, because interactivity and size both push Help past "deliberately small".

| Option | Cost |
|---|---|
| **Static diagram pairs only, plus a stated ceiling: no topic longer than one scroll at default text size on the narrowest supported iPhone, with 长捉 permitted to split** *(recommended)* | 长捉 must be split into two topics. Reviewers get something to enforce. |
| Rows 6–8 carry the replay transport | The best teaching device available at no new component cost — but Help becomes interactive, sitting directly beside `:397`'s "does not … offer interactive lessons or drills". A reviewer could reasonably read it as a scope breach. |
| No ceiling, governed by judgement | Nothing to argue about now; eleven rows drift toward a manual over successive passes. |

The research report offers no recommendation on the ceiling. I do, and here is why: Help is the one surface
with no natural size limit, and "deliberately small" is not a number a reviewer can hold anyone to.

#### F21. Does Help name its rules source, and where do the licence and attributions live?

- A one-line 规则依据 note: costs one line, gives a learner a next step in a product whose stated purpose is
  education. **Recommended.**
- Separately and not optional: **no accepted contract says where the GPLv3 licence text and third-party
  attributions are shown.** `product.md:13` licenses the app GPLv3 and `engine-integration.md` requires
  third-party notices "before any build containing the engine is distributed to internal testers". Only their
  *home* is open. Decide it here or open an issue.

#### F22. Does Settings preview the piece styles, or only name them?

| Option | Cost |
|---|---|
| **Names only for the first build** *(recommended)* | A purely verbal choice between 传统 and 现代, which is hard for a visual decision, and unlike Apple Chess this app's Settings destination leaves no live board visible behind it. |
| Names plus a static preview per option | Three style previews and two symbol previews, each re-rendered whenever a style's colour values change — and those values are still open (`:517`), while the icon set is still open (`:518`), so the symbol-row previews cannot be drawn at all yet. |
| Names plus one live board preview | Best explanation of what the setting does; a second board renderer path in Settings, and `:129` already had to carve out an exception for one non-interactive preview, so a second needs its own rule set. |

Revisit once `:517` and `:518` close.

#### F23. Can a `.mxq` file move without going through the app's one import screen?

Two reports ask this from opposite ends; it is one scope question.

| Option | Cost |
|---|---|
| **No document-open handler for the MVP; add a macOS Export… using `fileExporter`** *(recommended)* | The macOS command is a capability that exists on one platform and not the others, which `:25` allows only with "an explicit product decision" — this is that decision. |
| Declare a Viewer handler for the UTI | Double-tapping in Finder or Files works, but it creates a second import entry path with launch-time state: an import that runs before History is on screen, with its own success and failure presentation and its own answer to "what if a game is being created right now". None of that is in the accepted contract. |
| Drag out of the History list on macOS | `:386`'s rule is that platform gaps are filled by *equivalents*, not new capabilities. |

**Reasoning.** On the platform most likely to be used for moving files around, a `.mxq` currently cannot be
put on disk at all without going through another app. That is a genuine gap and `fileExporter` is the
platform's own equivalent. A document handler is a new entry path, which is not.

---

### Group G — Delivery gates (4 decisions)

#### G24. What shape does `testing.md` acceptance take? ★

Of 131 change-to-validation gates, **99 are executable as written** — the expected value is fixed in an
accepted contract and a tester could assert it today. 23 name a threshold, command, artefact, device matrix
or design decision that does not exist. Whole-document acceptance is unreachable on any schedule the project
controls: `testing.md:109`–`:110` need the Windows frontend.

| Option | Cost |
|---|---|
| Change nothing | Every gate added by PRs #13–#27 stays non-binding through the whole first implementation push. |
| **Section-by-section, with a marked Pending subsection holding the 23 and the Windows-dependent gates** *(recommended)* | 99 gates bind now. A gate later found impractical becomes a contract change rather than a draft edit — that trade is yours to accept. |
| Accept whole as-is | 23 gates accepted knowing they cannot pass, so "all gates pass" becomes a claim nobody can truthfully make, eroding the release gates at `:196`–`:200`. |

This also answers two sub-questions raised separately: the Windows-dependent gates stay in the document but
inside Pending, and the accessibility criteria bind as accepted *interaction design* regardless of
`testing.md`'s status.

Related and still yours: **how many pending gates may be unexecuted in an internal distribution candidate?**
`:196`–`:200` requires "passing critical UI tests" while "critical" is undefined. Naming the blocking subset
now — suggested: rules fixtures, store transactional invariants, import rejection classes, engine memory
boundaries — lets a candidate ship with the rest outstanding and everyone knows which.

#### G25. What does the localization review process cost?

| Option | Cost |
|---|---|
| Contract holds every string | The only option under which "the accepted copy is normative" stays literally true. `interaction-design.md` grows by ~70 rows and every copy tweak becomes a contract PR. |
| **Contract holds the strings whose wording is a product decision; the string catalog holds the rest — plus one test asserting every contract-quoted string appears verbatim in the catalog** *(recommended)* | Lower friction. Drift between the two is the failure mode — which is exactly why the test is part of the option rather than a nicety. |
| Full XLIFF round trip with a named reviewer per language | Heaviest; with one reviewer today it buys ceremony rather than scrutiny. |

I depart from the source report here, which recommends the first. Its objection to the middle — drift — is
correct and is testable; 70 rows of contract per copy tweak is not.

#### G26. Sanitizers and import fuzzing — pay now or accept the exposure?

| Option | Cost |
|---|---|
| **Add the sanitizer test-plan configuration now; defer fuzzing to a corpus-replay harness over the rejection classes** *(recommended)* | A second test-plan configuration before the first feature. Apple documents that it cannot share a configuration with performance measurement, so the split has to exist anyway. |
| Both now | A fuzz harness before any core source exists. |
| Neither | Defensible for an internal, offline app whose worst realistic case is a crash on a malformed file a tester chose to import — but `game-data.md:127` makes untrusted input a contract obligation, so it should be a decision rather than an omission. |

#### G27. Is the AI-profile measurement a release gate or a periodic observation?

| Option | Cost |
|---|---|
| Release gate | Apple publishes no automated energy or thermal metric for XCTest, so this means an Instruments run on real devices per candidate. Strong protection for the 4 GiB Hash policy. |
| **Periodic observation on a named cadence** *(recommended)* | Profiles can drift unnoticed on new hardware. `engine-integration.md:116` already forbids silent retuning, so the choice is about detection, not authority. |

---

### Group H — Twelve bounded calls, one line each

These are small, but each amends accepted text, adds a normative string, or reverses a stated reason — so
none of them is a designer's to take.

| # | Question | Recommendation | Cost of the alternative |
|---|---|---|---|
| H28 | Black's ordinal written in Chinese (一卒进1) against `:163`'s "every number in a move" | **Accept the exception** | No source writes `1卒进1`; the leading and trailing digits would be different kinds of thing rendered identically |
| H29 | Two files each carrying two or more soldiers: restore the origin file (前兵六进一), overriding `:166`'s unconditional "omits the file entirely" | **Accept**, with `:166` gaining "unless two files each carry two or more" | 前兵 names two soldiers and is ambiguous. Measured at 1.2–1.7% of positions — three times commoner than the case `:519` does name. Escalated here because it changes accepted contract text; the source report files it only as a blocking defect |
| H30 | Is **Stalemate** the English label for a *loss*? | **Keep Stalemate**; the result card's already-required second line (`:340`) corrects it | "No Legal Moves" is accurate but diverges from the frozen `stalemate` identifier; saying nothing teaches the wrong rule to exactly the reader this app exists for |
| H31 | 高对比 → **高对比度** | **Rename in the contract** at `:84`, `:95`, `:141` — one word for the thing | Keeping both makes these the project's only Chinese internal design name; shipping 高对比 reads as a truncation to any Chinese speaker |
| H32 | Does the Settings footer name Apple's own 增强对比度 / Increase Contrast? | **Yes** — it is the only version that removes the inference that choosing another style opts out of the accommodation | A permanent maintenance commitment in user-visible copy, tracking a per-platform system string. Note both proposed footers measure well past the accepted longest body text and need shortening regardless |
| H33 | Which instant does a History row show — the game's `ended_at` or the local History-added time? | **`ended_at`, with the 导入 · prefix explaining why an old game sits at the top** | Showing the added time makes an imported row say "今天 14:32" for a 2024 game; showing both pushes the line to ~300 pt of the 311 available |
| H34 | `game-data.md:40` requires import to check `ai_movetime_ms` "for presence and range" and no range exists | **100 ≤ value ≤ 60000** | `testing.md:113` has a boundary it cannot test. The three accepted values cannot be the range — the field exists precisely so a level's time can be retuned |
| H35 | Does the product name localize? | **No** — "Mini Xiangqi" stays Latin everywhere | `product.md:11` fixes it, `:461` exempts only the piece characters, and four proposed strings already embed it |
| H36 | Does the VoiceOver position summary state material counts (红方 N 子，黑方 M 子)? | **Yes** | `:498` declines a captured-piece display because "what remains is directly countable at a glance" — a claim that is simply false for a blind player. Costs a small asymmetry in the other direction |
| H37 | The numeral strips hide at accessibility text sizes (`:157`), removing information with no equivalent | **Keep the named exception and require the VoiceOver equivalent**, which A4 delivers free | Hiding them only when the layout genuinely cannot fit them is real layout work, depends on the still-open `:514`, and buys a size-dependent behaviour that is harder to test than a threshold |
| H38 | Where does the notation test oracle (110 rows, 24 positions) live? | **A fixture file under `fixtures/`, with the prose citing it** | In `interaction-design.md` a reviewer reads it and nothing executes it, and it adds 110 rows to a 73 KB document; in `testing.md` it stays non-binding along with everything else |
| H39 | Does the Play start state carry first-run orientation text? | **No** | A "has played" flag is an eighth persisted preference outside the accepted seven (`product.md:76`–`:83`), plus a decision about whether it survives a reinstall |

---

### Dropped — nine things the reports raised that a designer can settle

| Raised as | Settled by |
|---|---|
| Does a successful import say anything? | HIG *Alerts → Best practices*: silence plus the row appearing, scrolled into view and briefly highlighted |
| Does Help open at a topic chosen from the current position? | `:397` — Help "does not analyze the current position". Table of contents |
| Which form for four or five soldiers on one file | No measured occurrence in 21,888 positions; take the one specifying source (xqbase) |
| Where the mid-game engine-unavailable state lives | Four accepted sentences converge on the turn status (`:238`, `:269`, `:271`, `:38`) |
| The AI-thinking indicator's form | `:42` (no material) and `:258` (the pause is when a learner studies the position) settle it: indeterminate, no material, reserved height |
| Two History list sections versus a per-row pin badge | Pinned-ness is ordering, not decoration; `:368` already orders by it |
| Date and time formatting | Locale templates settle it — never write a date or time pattern |
| The order swipe actions are listed in | An implementation trap, not a choice: Delete must be listed **first** to sit nearest the trailing edge, the reverse of the contract sentence's reading order |
| The shape of the import alerts, once E14 fixes the count | Designer's, given the count |

---

## 2. What the audit found that must be fixed regardless

Thirty-four items: twenty-one produce wrong behaviour or an undefined state, thirteen are wording. None needs
the owner except where it points back at a §1 decision. Four of the first five were settled by execution here
rather than by reading.

### 2A — Would produce wrong behaviour (ranked by severity)

| # | Defect | Correction |
|---|---|---|
| **W1** | **A protected rook chased by a horse or a cannon is adjudicated a terminal loss** (executed, §1 C8), against `xiangqi-rules.md:64` and `mx-chs-002`'s rationale. Reachable in ordinary play; commits automatically; decides the game against a player who committed no violation | Decision C8, plus two fixtures |
| **W2** | `engine-integration.md:124`'s enumeration of the target variant is presented as complete and is not. **Executed:** the variant it describes returns `-32000` on `mx-chs-003`, which requires `0`. The missing setting is `promotedSoldiersChaseable = false`, named in no contract | Add the property to `:124`. Separately, flag to the fork that its own `test.py` binds `minixiangqiaxf` to the **non**-exempt variant, defeating `:132`'s naming rationale |
| **W3** | **No fixture pins `nMoveRule = 0`.** Executed: a variant missing it returns a draw two quiet plies after halfmove 98, and still passes all 16 approved fixtures — the longest is 9 plies. An accepted rule (`xiangqi-rules.md:58`) that no test can catch | Add `mx-rep-002`: start FEN at halfmove 98, two quiet plies, assert ongoing |
| **W4** | A naturally terminal position still has legal continuations (executed: `mx-chk-001`'s asserted terminal position returns `['d7c7']`). An imported archive can continue past a completed perpetual-check loss with every move legal in sequence and be recorded as ended-early — laundering a lost game past `game-data.md:64` | `ended-early` and `resignation` additionally require that no prior position completed a unilateral violation |
| **W5** | `engine-integration.md:154` routes a damaged installation to "the accepted engine-unavailable path" **which does not exist**. The nearest accepted notice tells that user to close other apps and retry, which provably cannot work | A second notice with a single dismissing action, plus the mid-game state (E15, E18) |
| **W6** | Engine preparation on the first AI reply after **any** resume is undefined. `engine-integration.md:72` prepares only "when a search is next owed" and excludes "a game awaiting the user's move" — the ordinary resume state. So every resumed AI game pays a probe, a 4 GiB Hash allocation and NNUE preparation under the user's first move, with no defined presentation and, on failure, a committed move behind it | Needs design, not wording. The declared open questions cover only the post-suspension case |
| **W7** | On a full store the user can neither archive nor abandon the active game (`product.md:47` + `interaction-design.md:317`), so **no new game can ever start** | Needs a defined escape |
| **W8** | **Resign has no interaction design at all.** `product.md:40` accepts it, `core-interface.md` exposes `mxq_game_resign` and `resign_available`, and `interaction-design.md` defines no control, placement, copy or availability rule — and does not list it as open | Design it, or list it |
| **W9** | The turn status has **no defined content once a game has a result**. `:268` "always identifies the side to move" against `:339`/`:343`; and `:271` plus `testing.md:186` require a 将军 token "for exactly as long as the side to move is in check", which in checkmate is forever, beside a card reading 红方获胜 · 将死 | Third exception stating the outcome in the result card's wording and suppressing the token in any terminal state; amend `:268` and `testing.md:186` |
| **W10** | **现代 cannot satisfy `:97` on any board.** Computed: white symbol at 4.5:1 caps the fill at L ≤ 0.1833; 3:1 between fills forces Black L ≤ 0.0278 and Red into 0.100–0.183. If the measured boundary is the fill edge, the board needs L ≥ 0.400; if it is the white ring, L ≤ 0.300. Disjoint. `:100`'s "stays valid on a dark board as well as a light one" is false under either reading, and `:97` never says which stroke is measured — so `testing.md:156` cannot be executed for 现代 at all | Name the measured stroke in `:97`; delete or replace `:100`'s last clause |
| **W11** | **The check pulse peak is arithmetically unreachable.** Computed: thickening symmetrically to `0.0325 p` at the stated centre-lines gives 0.41625 and 0.50375, crossing both structural limits, which is exactly what `:248` promises cannot happen. Only edge-anchored growth works — centre-lines 0.43625 and 0.48375, leaving 0.01500 p, reproducing the document's own "at least 0.015 p" to five places. `testing.md:179` asks a tester to verify the impossible | State the peak centre-lines |
| W12 | The drag's drop region is unstated and cannot equal its strengthening region. Strengthening engages within 0.45 p; if the drop region is the cell, releases up to 0.707 p commit, and π(0.45)² = 0.6362 — **36.4% of every cell can commit a move that was never previewed** | One radius governs both |
| W13 | **The board's hit region is stated nowhere in `docs/`.** The 44 pt floor is on the *cell pitch*; the disc is 0.80 p = 35.2 pt. Making the disc the tap target satisfies the accepted metric and misses Apple's 44×44 pt control floor by 8.8 pt. `testing.md:58` verifies the pitch and never the target | State that a location's hit region is its full 1 p × 1 p cell |
| W14 | Imported human-versus-AI replay orientation satisfies **both** halves of `:215`, one sentence apart. The record carries `human_side`, and provenance "never affect[s] equality" (`game-data.md:58`) so it must not change presentation | Default by `human_side` wherever one exists; Red at the bottom only for Free Play, which has none |
| W15 | Import rejection order can invert: `game-data.md:64` puts version dispatch before field validity, so a newer-version file must never be reported as a syntax complaint | State `testing.md:113`'s gate as "the reported class is the earliest failing stage" |
| W16 | `xiangqi-rules.md:75`'s accepted chase-renewal rule contradicts itself in consecutive sentences. Sentence 1 ("attacks the target from the square it now occupies and did not attack it from that square before") is vacuous — a piece that moved is by definition on a square it did not occupy — making every post-move attack a renewal, the opposite of sentence 2's exemption. The fork implements sentence 2 | Replace sentence 1. The shipped behaviour is right; the prose a second implementer would follow is not |
| W17 | `:426` "The accepted durations bound that wait to under half a second" is contradicted by `:416` "600 ms for a decision cycle", ten lines apart, with `:426` explicitly naming an Undo. That sentence is the justification for discarding input rather than queueing it | "bound that wait to 600 ms, and to 250 ms for anything but a decision-cycle Undo" |
| W18 | The AI indicator's 500 ms threshold and its 260 ms floor run on **different clocks** (tap versus arrival), and the threshold guarantees no minimum visible duration. Worked case: a one-step move plus a search returning at 501 ms shows the indicator for **1 ms** — the rule written to prevent a 200 ms flash admits an arbitrarily short one | Anchor the threshold on arrival and give the indicator a stated 200 ms minimum |
| W19 | `rules_version` is written into every archive (`game-data.md:38`) but reported by no C function, and `:64`'s validation dispatches only on `archive_version`. A version-1 export replayed by a version-2 facade has its terminal pair disagree and is rejected as inconsistent, breaking the promise at `:165` — and nothing can tell the user which interpretation wrote the file | Report it; branch on it |
| W20 | `core-interface.md:218` permits four functions inside the search callback that `:236` forbids ("only the status/blob helpers are legal") | Resolve; the two bindings could otherwise resolve it differently |
| W21 | `testing.md:96` requires app/search agreement on "repetition occurrence", which is unachievable: the fork's in-tree threshold is twofold | Rewrite the gate to what is achievable |

### 2B — Wording only

| # | Defect | Correction |
|---|---|---|
| Y1 | king/General across five documents and six fixtures | → §1 A1 |
| Y2 | Eight of sixteen fixtures call Red **"white"** and the chariot **"rook"**, against `xiangqi-rules.md:35` and `interaction-design.md:74`. `mx-chk-001`: *"The white rook alternates d4/c4 … the checking side (Red) loses."* | Prose-only rename in `title` and `rationale`, leaving `id`, `start_fen`, `moves` and `assertions` untouched so the fixtures' immutability rule is not engaged |
| Y3 | point / square | → §1 A3, including "illegal square" at `:227`, `:440`, `testing.md:159` |
| Y4 | **"cell" names two different rectangles offset by half a pitch.** `:120` "a 6-by-6 grid of cells with 49 intersections" (36 openings) against `:142` "that point's `1 p` by `1 p` cell" (49, point-centred). The point-centred sense is load-bearing in `:142`, `:240`, `:246`, `:247`, `:262` and `testing.md:178`. An implementer taking `:120`'s sense draws the last-move brackets half a pitch off and it still looks plausible | Delete "of cells" from `:120`; define the term once in Board metrics |
| Y5 | The keyboard focus ring both is and is not marker ink, in one bullet: `:143` lists it among active ink "for selection, legal destinations, captures, check, and focus" and then says it "is a platform affordance and never a game state". `testing.md:181` gates the second reading | Delete ", and focus" from `:143` |
| Y6 | `:154`'s "the `0.08 p` term is clear space between the board's outer line and the tallest numeral" is self-refuting. Computed: the strip sits outside the core, which already includes the 0.50 p margin, so actual clearance from the outer grid line is **0.58 p** = 25.5 pt at the floor. Measured from the outer line, numerals would sit *inside* the margin — what the same sentence forbids | Measure from the board core's edge |
| Y7 | `:141`'s "the `0.02 p` air gap … measured against the disc at its largest". Computed: at ×1.05 decoration reaches exactly 0.4200 p, so the gap there is **0.000 p**, not 0.02 (which is the at-rest value); and the disc at its largest is the dragged ×1.10 → 0.4400 p, past the marker floor, saved by an exemption this sentence never invokes. `testing.md:178` sends a tester to measure zero clearance | Restate both |
| Y8 | "without depending on haptics that a Mac does not have" (`:250`) and `testing.md:183` "where no haptic exists" are **false** — `NSHapticFeedbackManager`, and HIG *Playing haptics → macOS*. The conclusion survives on a narrower scoping (no haptic without a Magic Trackpad); the premise does not | Rescope both sentences |
| Y9 | 判和 at `:313` occurs exactly once in the whole set, bolded like a real string, against 可判和 (`:272`, `:352`, gated at `testing.md:78`) | 判和 → 可判和 |
| Y10 | `testing.md:169` gates "the compose-beat floor" — a name that appears in accepted text nowhere; the value is fixed at `:424` without it, and the only other use is a non-normative bullet. Separately, "beat" now names two unrelated things | Inline 260 ms, or name it at `:424` |
| Y11 | Exact-copy gates cover 27 of 58 strings with no stated rule. `testing.md:67` and `:73` quote every word of two alerts; `:82`, for a structurally identical alert, says only "the accepted confirmation copy", leaving 删除这盘棋？ and 删除后无法恢复。 unpinned. Same for the threefold notice, the low-memory message, and the turn status — the element on screen for the whole game | State the rule and apply it |
| Y12 | Eight controls exist only in English while `:455` makes Chinese normative and `:533` says no English is approved: Play, History, Settings, Human versus AI, Free Play, Resume Game, Flip Board, Confirm Before Deleting. Two are gated in English at `testing.md:66`. `product.md:34` also supplies unapproved English glosses inside an accepted section | → §3, rows 1–5 |
| Y13 | Eight of nine `end_reason` values and one of four `outcome` values have **no accepted Chinese string**, though three accepted behaviours display them (`:340`, `:296`, `:369`). The only Chinese reason string anywhere is 将死, buried in a composite example. `testing.md:68` gates "terminal result and reason" with nothing to verify against. 你执红 has no 你执黑 counterpart; `:369`'s "visible imported marker" has no string | → §3, rows 11–20 |

---

## 3. What is newly accepted copy

**123 distinct new Simplified Chinese strings** are proposed across six reports (127 proposals; four are
byte-identical across two reports). Each becomes normative on approval, because `interaction-design.md:455`
makes Chinese the source language. English counterparts are B5–B7's job and are not proposed here.

Nine surfaces have **two reports proposing different copy for the same thing** — marked ⚠ below. Those must
be reconciled before approval, not after.

### 3.1 Controls that exist only in English today (5) — *p6-copy*

| Chinese | Surface | Purpose |
|---|---|---|
| 历史 | Navigation destination | `interaction-design.md:22` |
| 设置 | Navigation destination | `:23` |
| 对局 | Navigation destination (Play) | `:21` |
| 回到对局 | Play destination action (Resume Game) | `:296`. **Must not** be 继续对局, which is already the threefold notice's action at `:350` |
| 翻转棋盘 | Flip Board control and its accessibility label | `:214`, `:218`, `:360` |

### 3.2 Settings — board and pieces (5) — *p6-names*

| Chinese | Surface | Purpose |
|---|---|---|
| 棋盘和棋子 | Settings group label | `product.md:82`–`:83` rows have no strings |
| 棋子样式 | Row label | Piece style |
| 棋子符号 | Row label | Piece symbols |
| **高对比度** | Style option | **Amends accepted 高对比** — see H31 |
| 棋子样式同时决定棋盘的配色。无论选择哪种样式，App 都会遵循系统的"增强对比度"设置。 | Group footer | Says the board changes too, and that the style is not the system accommodation. See H32; needs shortening |

*(传统, 现代, 汉字, 图标 are promoted from design names unchanged — not new.)*

### 3.3 Result and end-reason vocabulary (10) — *p7-history*

Required by `:340` (result card second line), `:296` (Play metadata) and `:369` (History rows).

| Chinese | Serialized value |
|---|---|
| 未分胜负 | `outcome = none` |
| 困毙 | `stalemate` |
| 三次重复 | `threefold-repetition` |
| 长将 | `perpetual-check` |
| 长捉 | `perpetual-chase` |
| 双方长将 | `mutual-perpetual-check` |
| 双方长捉 | `mutual-perpetual-chase` |
| 认输 | `resignation` — territory overlaps open PR #23 |
| 提前结束 | `ended-early` |
| 你执黑 | counterpart to accepted 你执红 |

### 3.4 History list and empty state (7 + ⚠2) — *p7-history*, ⚠ *p7-states*

已置顶 · 其他对局 · 导入 (row prefix) · 导入… (toolbar) · 导入对局… (empty-state button) ·
⚠ 还没有历史对局 / 还没有对局记录 · ⚠ 对局结束后会保存到这里。你也可以导入一个对局文件。 /
完成或保存一局棋后，它会出现在这里。

### 3.5 Import outcomes (⚠ two competing sets, 16 and 7) — *p7-history* vs *p7-states*

*p7-history* proposes six separately titled alerts; *p7-states* proposes one title 无法导入 with four
messages. **The count is E14; the shape is a designer's, once E14 lands.**

*p7-history:* 这盘棋已经在历史里 · 文件里的对局和历史中的一盘完全相同，所以没有重复添加。 · 查看 · 好 ·
这个文件和历史中的一盘棋冲突 · 它和历史中的一盘棋是同一局，但内容不同。历史没有改变。如果要用这个文件，请先删除历史中的那一盘。 ·
查看历史中的那一盘 · 这不是 Mini Xiangqi 对局文件 · 请选择一个 .mxq 对局文件。历史没有改变。 · 重新选择 ·
无法读取这个对局文件 · 文件的内容无效或过大，无法导入。历史没有改变。请确认文件完整，或者向对方要一份新的。 ·
这个文件由更新版本的 Mini Xiangqi 创建 · 当前版本无法读取它。请更新 Mini Xiangqi 后再试。历史没有改变。 ·
无法保存导入的对局 · 对局文件没有问题，但保存到历史时出错。历史没有改变。请重试。

*p7-states:* 无法导入 · 这个文件由更新版本的应用创建。请更新后再导入。 · 这个文件不是有效的对局文件。 ·
这个文件太大，无法导入。 · 历史中已有同一盘棋，但这个文件的内容不同。未做任何更改。 · 这盘棋已经在历史中。 · 好

### 3.6 Store, engine and creation failures (9) — *p7-states*

AI 暂时无法走子 (turn status, mid-game engine unavailable) · AI 组件已损坏。重新安装应用可以恢复。 (see E18) ·
思考中 (AI thinking) · 无法创建对局，请重试。 (inline under 开始对局) · 无法打开数据 ·
这些数据由更新版本的应用创建。请更新到最新版本。 · 应用数据无法读取。 (see E17) · 还没有走子 (empty move list,
accessibility value) · 重试失败。可用内存仍然不足。 (announcement)

### 3.7 Delete and pin failures (⚠ 2 + 4) — ⚠ *p7-states* vs *p7-history*

⚠ 无法删除 / 无法删除这盘棋 · ⚠ 这盘棋仍然保留。请重试。 / 这盘棋仍然保留在历史里。请重试。 ·
无法更改置顶状态 · 这盘棋的置顶状态没有改变。请重试。

### 3.8 Help (31, + 2 conditional) — *p7-help*

- Destination: 帮助 · Mini Xiangqi 帮助 (macOS Help menu)
- Groups: 入门 · 胜负与和棋 · 使用本应用
- Topics: 如果你会中国象棋 · ⚠ 棋盘与棋子 *(collides with Settings' 棋盘和棋子 — 与 against 和)* · 棋子怎么走 ·
  将军与将死 · 困毙 · 重复局面与判和 · 长将 · 长捉 · 走子、悔棋与认输 · 看懂棋谱 · 对局、历史与回放
- Sub-headings: 将 / 帅 · 车 · 炮 · 马 · 兵 / 卒 · 将帅不能对脸
- Vocabulary: 九宫 · 白脸将 · 蹩马腿 · 炮架 · 应将 · 重复局面 · 河界 · 士（仕）· 象（相）
- Conditional: 本应用的判定 (if F19 = both) · 规则依据 (if F21 = yes)

### 3.9 VoiceOver (29) — *p8-voiceover*

棋盘 · 局面 · 空 · 可走 · 可吃 · 被将军 · 上一步起点 · 上一步落点 · 可走的棋子 · 可走点 · 取消选择 ·
走到 ⟨point⟩ · 移到上一步落点 · 移到被将军的将 · 不能走到 ⟨point⟩。⟨piece⟩ 可走：⟨list⟩ · 共 ⟨N⟩ 个 ·
已选中 ⟨piece⟩ ⟨point⟩，⟨N⟩ 个可走点 · 已悔棋 · AI 的一步 · 已翻转棋盘，红方在下 · 已翻转棋盘，黑方在下 ·
第一线 … 第七线 (7) · 红方 ⟨N⟩ 子，黑方 ⟨M⟩ 子 *(only if H36 = yes)*

Plus the point coordinate itself — **pending A4**.

### 3.10 Reused verbatim, not new

取消 · 重试 · 红方获胜 · 黑方获胜 · 和棋 · 将死 · 人机对弈 · 自由对弈 · 你执红 · the `N 步` pattern ·
共享 · 删除 · 置顶 · 取消置顶 · 删除这盘棋？ · 删除后无法恢复。 · 当前可用内存不足。请尝试关闭一些其他 App，然后重试。 ·
无法启动 AI 对手 · 开始对局 · 保存并继续.
System-supplied and not ours to write: 今天, 昨天, and every date and time string.

---

## 4. Recommended order

### Decide now — nothing else can proceed correctly without these (9)

**A1** General/king · **A3** point/square · **C8** stronger-piece chase · **D10** nonvisual supported or best
effort · **G24** `testing.md` acceptance shape · **A2** what "move" means · **B5** the metadata run in English
· **B7** the move list for non-character readers · **C9** which fixtures gate the first build.

Alongside them, fix without asking: **W1–W5** (all four executed rules/engine defects plus the missing
engine-unavailable path) and **Y1**, **Y2**, **Y3** (the terminology renames A1 and A3 imply).

**Why these nine.** A1, A2 and A3 are inputs to every string in §3 and to Help, the move list, the VoiceOver
model and the notation — writing any of them first means rewriting them. C8 is a wrong game result reachable
in ordinary play. D10 sizes the whole VoiceOver model and the accessibility criteria. G24 decides whether any
of the 99 executable gates binds during the first implementation push. B5 and B7 decide layout and scope for
parts 6 and 7 simultaneously.

### Decide before the first UI pull request (8)

**A4** spoken coordinate · **B6** register · **E14** import message count · **E15** mid-game engine exits ·
**D11** the accessibility bar claimed · **H28**, **H29**, **H31** (the three amendments to accepted copy
rules).

Fix alongside: **W9–W13** (terminal turn status, 现代's impossible constraint, the check-pulse peak, the drop
region, the hit region) — every one of them is a number an implementer will otherwise pick wrongly and no
gate will catch. Plus **W17**, **W18** and **Y4**–**Y7**, which are cheap and all sit in the same paragraphs.

### Can wait until implementation has started (10)

**D12** input modes · **D13** Windows parity · **E16**–**E18** the three remaining error questions ·
**F19**–**F23** the five surface-scope questions · **G25**–**G27** the three delivery gates ·
**H30**, **H32**–**H39**.

These either concern a surface nobody has built (Help, Settings previews), depend on something still open
(`:517` colour values, `:518` icon set, the device matrix), or are cheap to revisit. **W6**, **W7** and **W8**
— resume-time preparation, the full store, and resign having no design at all — are undesigned states rather
than wrong numbers; they need a design pass, and that pass should be scheduled rather than squeezed into this
round.

### Blocked on artefacts that do not exist yet

Anything needing physical devices (the VoiceOver gate, the AI-profile measurement, the numeral-strip
confirmation on iOS), and everything Windows. Do not let these hold the rest: G24's Pending subsection exists
precisely so they can be recorded without blocking.

---

## 5. Where the reports disagree, and my reading

**5.1 The metadata line at 13 pt.** One report offers "drop English to 13 pt, where every line fits" as an
owner option; its own reviewer re-measured and two lines are 309.1 and 334.2 pt against a 308 pt block. **My
reading: the option does not exist and must be struck from B5.** The two reports measure different surfaces
(308 pt board block, 311 pt list row) and reach the same conclusion, which strengthens both.

**5.2 "square appears nowhere as a board term, deliberately".** False. Executed: `xiangqi-rules.md` uses it
ten times *as the board term*, including the frozen coordinate sentence and the canonical notation, and
`core-interface.md:68` freezes `from_square`. **My reading: the conflict is real, is larger than that report
allows, and is A3.**

**5.3 The register premise.** One report states the Chinese uses 请 "in exactly two places" and builds an
owner decision on it. There are three (`:284` among them), and the report's own English for the third already
drops it. **My reading: B6's premise needed correcting; the decision itself survives.**

**5.4 Two import alert sets.** `p7-history` proposes six titled alerts with long explanatory messages;
`p7-states` proposes one title with four short messages. They also differ on the delete-failure copy and the
empty-History copy. **My reading: `p7-states`' single-title shape is cheaper to translate and test;
`p7-history`'s four-way cut of the *classes* is the better one. Take the cut from one and the shape from the
other, once E14 fixes the count.**

**5.5 棋盘与棋子 against 棋盘和棋子.** Two reports mint the same phrase with different conjunctions for the
Help topic and the Settings group. **My reading: use 和 in both, per the Apple zh_CN precedent one of them
cites, and let the Help topic differ from the Settings group by scope rather than by particle.**

**5.6 "Nothing here creates a fourth glass surface."** One report claims this and then puts a 重试 button on
the turn status. `:31` makes glass required *of* controls. **My reading: its reviewer is right — an exemption
in `:42`'s own words must be asked for, not assumed.**

**5.7 Retry on return to the foreground.** One report presents an automatic re-attempt on foreground return
as "the accepted rule firing". `engine-integration.md:72` says the opposite in bold: *"Re-preparation happens
when a search is next owed, **not** on return to the foreground."* **My reading: verified against the
contract; it is a contract change, not an application of one, and must be proposed as such.**

**5.8 "Internal design vocabulary is English."** False — `interaction-design.md` bolds **Flip Board**,
**Resume Game**, **Play**, **History**, **Settings**, **Human versus AI** and **Free Play** as English *copy*.
**My reading: only the one-directional claim survives — every bolded Chinese term is copy — and that is
enough to carry the conclusion.** The same report separately affirms and denies that 高对比 is an
accessibility accommodation (`:78` co-equal looks, `:84` "for low-vision use"); H32 is where that has to be
resolved.

**5.9 "On a Mac there are no haptics."** Stated in accepted contract text at `:250` and `testing.md:183`, and
false — `NSHapticFeedbackManager` and HIG *Playing haptics → macOS* both exist. **My reading: the conclusion
(do not let a haptic be a sole carrier) survives on the narrower true statement that a Mac has none without a
Magic Trackpad; the premise must be rewritten.** Y8.

**5.10 The restored origin file (前兵六进一).** One report files this as a blocking defect while conceding it
overrides accepted `:166`. By that report's own stated criterion — "the owner's because it changes accepted
contract text" — it is an owner decision. **My reading: escalated, as H29.**

**5.11 The 44×44 pt target floor.** One report tags a blanket 44×44 criterion as Apple-grounded; HIG
*Accessibility → Mobility* gives iOS/iPadOS 44×44 default and 28×28 minimum, macOS 28×28 default and 20×20
minimum. **My reading: W13's "misses by 8.8 pt" is an iOS/iPadOS figure and should be stated as one.**

---

## Provenance

Executed here: the four engine probes in §2A (W1, W2, W3, and the `nMoveRule` fixture sweep), against
prebuilt pyffish `(0,0,89)` at `discussion-drafts/w-base`, with the harness run from `/tmp`. The grep counts
in A3, Y9 and Y12. Computed here: W10, W11, Y6, Y7, and the check-pulse edge-anchored solution. Everything
else is read from the cited contract line, or is quoted from a report whose own measurement method is stated
there. Nothing under `MiniXiangqi/` or any worktree was modified; no git or GitHub write of any kind.
