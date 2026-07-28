# Part 8.1 — The board's VoiceOver interaction model

Workspace research draft. Not a contract, not accepted, authorises nothing. It proposes text for
`interaction-design.md:532` (second clause) and evidence for the reviewer who writes it.

Method markers used throughout: **[measured]** = I executed it and report the numbers; **[cited]** = quoted
from a source named at the quote; **[reasoned]** = my inference, arguable on its face.

---

## 0. What the accepted contracts already fix

These are not proposals. They are the walls the model has to fit inside, and several of them decide more than
they look like they do.

| Accepted | Where | Consequence for this model |
|---|---|---|
| "Keyboard and VoiceOver use an equivalent select-piece, inspect-destinations, and select-destination flow rather than requiring a drag gesture." | `interaction-design.md:233` | The three-step shape is settled. Only its realisation is open. A one-step "double-tap a piece then double-tap a square" model is *already* what this says; what is undesigned is the middle step. |
| Keyboard focus is a board marker with exact geometry (`0.92 p` square, stroke `0.04 p`, radius `0.14 p`, band `0.44 p`–`0.48 p`), is the one marker carrying hue, and is the only marker permitted to cross another. | `:253` | A focus concept on the board already exists, with drawn geometry. VoiceOver focus must ride it rather than introduce a second. |
| "The board shows the position and the states of the position, and nothing else. Anything the interface must say that is not a fact about the position … is said by the turn-status element instead, so the board is never read for two kinds of information at once." | `:238` | Generalises cleanly to speech, and settles a dozen sub-questions at once. See §1.1. |
| Four announcements are required **by name** with no text written: the last move's "accessibility announcement" (`:247`), Flip Board's "localized accessibility label" (`:218`), History rows' screen-reader custom actions (`:386`), and the **将军** token as the place check is carried while the general is held (`:249`). | as listed | The announcement set is not a blank sheet; four entries are already mandatory. |
| Illegal tap draws **no board mark**; with a piece selected its legal destinations pulse once, and the selection is retained. Under Reduce Motion they change state once instead. | `:250` | The visual answer to an illegal tap is *the destination list*. The spoken answer must therefore also be the destination list, not a rejection noise. |
| A failed save is reported at the turn status, never on the board; unavailable input gets an opacity-only acknowledgment beat. | `:257`–`:258` | Neither becomes a board announcement. |
| Replay's board "is a read-only document, and a tap on it does nothing at all — no beat and no feedback." | `:258` | In replay no board point may carry an actionable trait. |
| The file-numeral strips are **hidden at accessibility text sizes**, with the cost named: "a reader cannot relate a move in the list to a file on the board without counting." | `:157` | This is precisely the setting under which a VoiceOver user is likeliest present. See §4.4 — for this user the model repairs the loss rather than inheriting it. |
| A point of the grid is never smaller than **44 pt** on every platform. | `:480` | Explore-by-touch works on this board without any special affordance. See §4.5. |
| Captured pieces are not displayed, because "what remains on the board is directly countable at a glance." | `:498`, `product.md:28` | The justification does not hold for a blind player. See §4.3 and Owner decision D. |
| A user who selects icon symbols "still reads a character-based move list." | `:168` | Generalises: a VoiceOver user reads a character-based move list too, in either interface language. See §6. |
| Piece characters "are identical in every supported language and are never translated." English piece names are General, Chariot, Horse, Cannon, Soldier, and "appear in help, accessibility announcements, and any descriptive text." | `:71`, `:74` | The board may speak English names; the move list's characters may not be replaced. |
| Help "does not analyze the current position, suggest moves, or offer interactive lessons or drills." | `:397`, `product.md:12`, `product.md:41` | Hard ceiling on what may be spoken. See §1.1. |
| Squares are named `a1` through `g7`; that notation "is canonical for fixtures, game archives, and the shared core interface." | `xiangqi-rules.md:34`, `:36` | A machine-stable coordinate exists. Whether it is the one spoken is Owner decision B. |

**Not accepted, do not assume:** anything in PR #23's diff or body. Resignation copy, the play-control cluster,
the result card's stacked-layout placement, and the move list in the stacked layout are that PR's territory and
it was rejected. Where this model needs one of those surfaces it names the requirement and not the widget.

---

## 1. Two governing rules

Everything below follows from these. If a reviewer disagrees with one of them, most of the model changes.

### 1.1 VoiceOver may say anything the board already shows, and nothing it does not

**[reasoned]**, but derived rather than invented: `:238` says the board shows the position and the states of the
position and nothing else, and `product.md:41` excludes position analysis. Together they draw a line that
settles the questions a designer is most tempted to get wrong:

- Legal destinations of the selected piece — **spoken**. They are already drawn for every sighted user (`:245`,
  `:246`). Speaking them is parity, not a new capability.
- The last move, check, selection, capture availability — **spoken**. All are drawn markers (`:244`–`:249`).
- Which enemy pieces attack a point; whether a piece is defended; whether a move is good — **not spoken, ever**.
  None of it is drawn for anyone. This is the analysis exclusion, and it is the single most likely place for a
  well-meaning implementation to over-deliver, because "is this square safe?" is the obvious next question a
  blind player will ask and the answer is genuinely useful. It is still out of scope.
- Save failures, "input unavailable", AI-thinking state — **not spoken from the board**. They live on the turn
  status per `:238`, and so does their spoken form.

### 1.2 Every accepted board marker has exactly one spoken carrier, and no state has two

**[reasoned].** The accepted marker vocabulary is a closed set with a stated design property — four shape
families, no two states confusable (`:240`). The spoken vocabulary should have the same property: a
one-to-one map, so a reviewer can check it exhaustively rather than by taste, and so that no state is either
silent or double-reported.

| Accepted marker | Where drawn | Spoken carrier | Notes |
|---|---|---|---|
| Selected piece — solid ring + ×1.05 lift | `:244` | `AccessibilityTraits.isSelected` on the point | VoiceOver appends "selected" itself; no custom string. |
| Legal empty destination — filled dot Ø `0.22 p` | `:245` | custom content **可走** / "legal move", `.high` importance, + `.isButton` | |
| Legal capture — dashed ring | `:246` | custom content **可吃** / "can capture", `.high` importance, + `.isButton` | Distinguished by word, as the visual is distinguished by shape. |
| Last move — corner brackets on origin **and** destination | `:247` | custom content **上一步起点** / **上一步落点**, `.default` importance, on the two points; plus the move announcement in §5 | Two carriers, one per role; the brackets are on two cells and so is the speech. |
| General in check — double ring | `:248` | value suffix **被将军** / "in check" on the general's own point | |
| A held general in check — rings hide | `:249` | **no gap exists in speech**; the value still says 被将军 | Nothing to reconcile: the visual conflict is a geometry conflict between two rings occupying one band, and speech has no band. The **将军** token still carries it on the turn status per `:271`, which is where a user who has lost the general goes to re-read it. |
| Illegal tap — destinations pulse once | `:250` | announcement enumerating the destinations, §5 | The pulse *is* the destination list; so is the sentence. |
| Dragged piece | `:251` | none | Unreachable: `:233` says VoiceOver never drags. |
| Pointer hover fill | `:252` | none | "It reports where the pointer is, not what is legal." A VoiceOver user has no pointer. |
| Keyboard focus ring | `:253` | **is** the VoiceOver cursor | §3. |
| Failed save (no board marker) | `:257` | turn-status element value, not the board | |
| Unavailable input (no board marker) | `:258` | absence of `.isButton`; no announcement | §5. |

That table is the deliverable a reviewer can audit. Nine of the twelve rows are forced by an accepted rule; the
three that are not (capture wording, last-move wording, the illegal-tap sentence) are marked as new copy in §7.

---

## 2. The element tree

### 2.1 What the board exposes

One accessibility container, labelled **棋盘** / "Board", declared with
`accessibilityElement(children: .contain)` **[cited: SwiftUI › `AccessibilityChildBehavior.contain` — "Any
child accessibility elements become children of the new accessibility element"]**. Containment rather than
`.combine` is required: `.combine` merges every child's properties into one element and would destroy the 49
addressable points; `.contain` keeps them while giving VoiceOver a single region a user can enter, leave, and
skip past.

Inside it, in reading order:

1. **One position-summary element** (§4.1).
2. **49 point elements**, one per intersection.

Fifty elements. No rank rows, no file headers, no separate piece elements. Nothing else is added to the linear
swipe path, because everything added to it costs every user a swipe forever; the shortcuts in §4 are all
*out of band*.

### 2.2 Why 49 points and not 7 rows or 1 board

**[reasoned].** Three candidate granularities:

- **One board element with the position in its value.** Cheapest to read, impossible to play: the accepted flow
  (`:233`) requires selecting a piece and then a destination, and a single element has one activation point.
  Rejected.
- **Seven rank-row elements.** Readable, still unplayable for the same reason, and it would put the 7 rows in
  the swipe path in *addition* to whatever mechanism made points activatable. Rejected as the primary tree;
  adopted as a *reading* mechanism in §4.2, where it costs nothing.
- **Forty-nine point elements.** The only granularity in which the accepted flow works, and the only one in
  which explore-by-touch gives a spatial map. Adopted, with §4 as the mitigation for its traversal cost.

### 2.3 Order of the 49

**Rank by rank from the near side outward; within a rank, leading to trailing as drawn.**

"Near side" follows the on-screen orientation, so the order flips when the board flips (`:216`: flipping
"changes presentation only"; the reading order is presentation). For a Red-at-bottom board the first element is
the leftmost point of Red's back rank and the last is the rightmost point of Black's back rank.

**[reasoned]** on the tie-break, which is not obvious. Traditional files are numbered from each player's own
right (`:163`), so for the near player the on-screen leading-to-trailing sweep runs **7, 6, 5, 4, 3, 2, 1** —
descending. It is tempting to traverse in ascending file order instead, so the numbers count up. Rejected,
because explore-by-touch cannot be reordered: dragging a finger left to right across the board *will* produce
七 六 五 四 三 二 一 whatever the swipe order is, and a swipe order that disagreed with the touch order would
give the same board two contradictory geometries. Descending is also exactly what the numeral strip shows a
sighted near player left to right (`:151`, `:167`), so the spoken order and the printed strip agree.

### 2.4 Traits

| Condition | Trait |
|---|---|
| A movable own piece, with nothing selected or another piece selected | `.isButton` |
| A legal destination of the currently selected piece | `.isButton` |
| The currently selected piece | `.isButton` + `.isSelected` |
| Everything else — empty points, enemy pieces that are not capture targets, own pieces with no legal move, every point in replay, every point while input is unavailable | **no trait** |

**[reasoned].** Deliberately *not* `.isNotEnabled` on the inert points. Marking 40-odd points "dimmed" would be
noise on every swipe and would misdescribe an empty square, which is not a disabled control but simply not a
control. Absence of the button trait is the honest signal, and it is the exact non-visual counterpart of the
accepted rule that "the board rejects the interaction before visually moving a piece" (`:234`) — a VoiceOver
user learns an action is unavailable *before* attempting it, which is strictly better than the sighted
experience.

Consequence worth stating: while the AI is thinking, no point on the board is a button. That is the whole of
the accepted acknowledgment beat's information (`:258`), delivered earlier and without a beat.

### 2.5 Siblings outside the board container

The turn status (`:266`–`:277`) is a separate element, not part of the board — required by `:238`. Its value
carries, in this order: side to move; controller (你 / AI) in Human-versus-AI; the **将军** token when
applicable; AI activity once past the accepted 500 ms threshold (`:424`); and the transient save-failure text
(`:257`).

**[cited: UIKit › `UIAccessibilityTraits.updatesFrequently` — "The accessibility element frequently updates
its label or value"]** — apply it to the turn status **only while AI activity is shown**, so that an animated
indicator does not cause VoiceOver to re-announce the element repeatedly. Removing it again when the search
returns is part of the requirement, not an optimisation.

---

## 3. Focus: one concept, not two

**VoiceOver's cursor drives the accepted keyboard focus marker.** In SwiftUI,
`@AccessibilityFocusState(for: .voiceOver)` bound to the same "focused point" state that keyboard arrow keys
drive **[cited: SwiftUI › `AccessibilityFocusState.init(for:)` — "Creates a new accessibility focus state of
the type and using the accessibility technologies you specify"]**.

Grounding **[cited: ObjectiveC › `UIAccessibilityFocus` — "VoiceOver and other assistive technologies place a
virtual focus on elements, which allows users to inspect an element without activating it. If you know the
current location of the virtual focus, you can optimize the user experience for assistive technology users"]**.

That same page goes on to recommend moving *selection* with focus, to spare the user an extra tap. **We
deliberately do not do that here, and the reason matters.** In this app, selecting a piece is a game action
with visible consequences — a lift, a ring, a full set of destination markers appearing and, per `:250`, the
thing an illegal tap will pulse. Moving selection with focus would mean that merely swiping across the board
repeatedly changed what it displays and what a subsequent double-tap would do. Focus inspects; activation
selects. This is one place where Apple's general advice is written for lists and forms and does not survive
contact with a game board, and the contract should say so rather than silently diverge.

Costs nothing in geometry: the focus ring already exists with fixed measurements and is already permitted to
cross other markers (`:253`), which is exactly what a cursor sitting on a selected, checked general needs to do.

---

## 4. Conveying a position efficiently

This is the substance of the brief. First, what the problem actually is.

### 4.0 Measured shape of a Mini Xiangqi position

**[measured]** — 42 048 positions from 400 random playouts from the frozen start FEN
`rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1`, adjudicated by the workspace pyffish build at
`discussion-drafts/w-base/`, variant `minixiangqi`, seed 20260728. Script:
`/Users/tianren/coding/minixiangqi/discussion-drafts/vo-measure.py`. Second pass over 12 122 positions
(120 playouts, same seed): `vo-measure2.py`.

| Quantity | min | p25 | median | mean | p75 | p95 | max |
|---|---|---|---|---|---|---|---|
| Legal moves per position | 1 | 18 | 23 | 22.08 | 27 | 33 | 46 |
| Distinct movable pieces (origins with ≥1 legal move) | 1 | 6 | 8 | 7.63 | 9 | 11 | **12** |
| Destinations per movable piece | 1 | 2 | 2 | 2.89 | 3 | 8 | **12** |
| Pieces on the board | 3 | 14 | 18 | 17.55 | 22 | 24 | 24 |
| Pieces per rank | 0 | — | 2 | 2.49 | — | 5 | 7 |

Further **[measured]**:

- Empty ranks are **8.2 %** of ranks; a position has a median of **7** non-empty ranks, mean 6.43.
- **92.37 %** of positions have at least two *movable* pieces of the same type for the side to move.
- Captures are **11.7 %** of legal moves on average.
- Start position: **19** legal moves, **7** movable pieces, per piece `{a2:2, b1:5, c2:2, d2:1, e2:2, f1:5,
  g2:2}` — matching the 19 pinned by `mx-move-001` (`xiangqi-rules.md:96`).
- The worst per-piece case, **12**, is a chariot with a clear rank and file — confirming the contract's own
  "a chariot on an open board offers a dozen of these at once" (`:245`) as an exact bound, not a figure of
  speech. A chariot on an empty 7×7 board reaches 6 + 6 = 12 points from any square.

Three design conclusions fall straight out:

1. **The traversal problem is real but bounded.** 49 elements, of which a median of 31 are empty. Reading the
   board point by point costs 49 gestures and 49 utterances to learn 18 facts.
2. **The enumeration problem is small.** A destination list has a median of 2 entries and a 95th percentile of
   8. Twelve is the hard ceiling. Lists that short can be custom actions; on a 9×10 board with 32 pieces they
   could not. This is a place where the variant's smallness genuinely buys something.
3. **A piece must be named with its coordinate, not by type.** In 92.37 % of positions "Chariot" is ambiguous
   for the side to move. Any label, action name, or rotor entry that omits the coordinate is wrong almost
   always.

### 4.1 The position-summary element

One element, first in the container, label **局面** / "Position", no traits, not actionable.

Its **value** is the whole position, read in the §2.3 order, near side first, naming only occupied points.
Median cost **[measured]**: about 18 piece mentions in one utterance, interruptible with VoiceOver's two-finger
tap. **One swipe replaces forty-nine.** This is the single highest-value element in the model and it costs one
element and no geometry.

Its **custom content**, all at `.default` importance — **[cited: SwiftUI ›
`accessibilityCustomContent(_:_:importance:)` — "High-importance information gets read out immediately, while
default-importance information must be explicitly asked for by the user"]**:

| Key | Value |
|---|---|
| 第一线 … 第七线 (seven entries) | that rank's contents, near side first |
| 子力 / "Material" | 红方 N 子，黑方 M 子 — **Owner decision D** |
| 上一步 / "Last move" | the traditional move string, or absent at an initial position (`:247`) |

Rank stepping therefore happens in the **More Content rotor**, which reads without moving focus and without
re-reading the whole board. That is exactly the affordance `.default` importance exists for, and it is why
ranks are custom content rather than rotor entries: **rotors are for going somewhere, custom content is for
hearing something.** Adopt that as the rule and the whole allocation follows.

### 4.2 Two custom rotors

**[cited: SwiftUI › Accessible navigation — "An accessibility rotor is a shortcut that enables users to
quickly navigate to specific elements of the user interface"]**.

| Rotor | Present when | Entries | Measured size |
|---|---|---|---|
| **可走的棋子** / "Movable pieces" | an active game, human to move | every piece of the side to move with ≥1 legal move; entry label = piece name + coordinate | median 8, p95 11, **max 12**; 7 at the start |
| **可走点** / "Destinations" | a piece is selected | that piece's legal destinations in board order; entry label = coordinate + 可走/可吃 | median 2, p95 8, **max 12** |

The first answers "which of my pieces can do anything" in at most 12 rotor steps instead of hunting 49 points.
The second answers the brief's "how are legal destinations enumerated without a dozen swipes" — a dozen is
literally the worst case, and the rotor makes it a dozen *rotor steps with focus landing on each*, not a dozen
blind swipes across intervening empty points.

Label the movable-pieces rotor **可走的棋子** and not 你的棋子: in Free Play the same person controls both
sides (`product.md:33`), so "your pieces" is false half the time and one string then has to serve two modes.

**Implementation constraint worth recording now [cited: SwiftUI › `accessibilityRotor(_:entries:entryID:
entryLabel:)` — "Using this modifier requires that the Rotor be attached to a `ScrollView`, or an Accessibility
Element directly within a `ScrollView`"; and `AccessibilityRotorEntry` — "An entry may also be created using an
optional namespace, for situations where there are multiple Accessibility elements within a `ForEach`
iteration or where a `ScrollView` is not present"]**. The board is not a scroll view. Only the closure form of
`accessibilityRotor`, with a `Namespace` and `accessibilityRotorEntry(id:in:)` on each point, will work. An
engineer who reaches for the `entries:` array overloads will find it silently does nothing.

### 4.3 Two custom actions on the board container

Pure navigation, no game effect, so they are safe to offer at any time:

- **移到上一步落点** / "Go to last move" — moves focus to the destination cell of the move that produced the
  position on screen. Directly serves `:247`, which requires the last move to have an accessibility
  announcement; the announcement says what it was, this says where.
- **移到被将军的将** / "Go to the general in check" — present only while a side is in check.

### 4.4 The numeral strips, and why their loss does not land on this user

`:157` accepts hiding both file-numeral strips at accessibility text sizes and names the cost: "without the
strips a reader cannot relate a move in the list to a file on the board without counting, which is a loss for
the same user the larger type was for."

**[reasoned]** For a VoiceOver user that loss does not occur: every point's label carries its coordinate, so the
board is self-labelling whatever the strips do. Worth stating in the contract, because it converts an accepted
regression into a non-issue for one user class, and because a reviewer reading `:157` and `:532` together will
otherwise ask.

It does *not* help a low-vision user at a large text size who is not running VoiceOver. That user is 8.2's
problem, not this model's.

### 4.5 What we deliberately do not build

- **Direct touch.** `accessibilityDirectTouch` passes touches to the app instead of to VoiceOver **[cited:
  UIKit › `UIAccessibility.DirectTouchOptions` — "Direct touch areas are regions of the screen where VoiceOver
  passes gestures directly to the app instead of interpreting them as VoiceOver commands"; `silentOnTouch` is
  "Appropriate for apps that provide direct audio feedback on touch that would conflict with speech
  feedback"]**. We have no such audio, and standard explore-by-touch already speaks the point under the finger
  **[cited: Accessibility › Performing accessibility testing for your app — gesture table, "Tap | Select and
  speak an item"]**. Enabling direct touch would remove the speech and buy nothing. The accepted 44 pt point
  floor (`:480`) is what makes standard explore-by-touch adequate here without any special affordance — an
  accepted layout decision paying an accessibility dividend it was not taken for.
- **A Braille board.** Apple does document a two-dimensional Braille surface **[cited: Accessibility › Vision ›
  "Braille displays — Display a graphical representation of images, icons, data, and more on a two-dimensional
  braille display"]**, and a 7×7 grid is an obvious fit. Out of scope: internal distribution to a small group
  (`product.md:14`), no evidence anyone in it has the hardware, and it is a capability rather than a model.
  Recorded here so the contract shows it was considered and declined, not overlooked.
- **Any attack, defence, threat or evaluation information.** §1.1.

---

## 5. The announcement set

Mechanism: `AccessibilityNotification.Announcement` **[cited: Accessibility › `AccessibilityNotification` —
"Announcement to convey an announcement to an assistive app … For announcement notifications, you can set a
priority to specify the announcement's importance relative to other announcements that are in the queue"]**.

Priorities, from the documented semantics **[cited: Foundation ›
`AttributeScopes.AccessibilityAttributes.AnnouncementPriorityAttribute` — "when `low` is specified,
announcements are queued and spoken when other speech utterances have completed. When `default` is specified,
announcements will interrupt existing speech, but are interruptible if a new speech utterance is started. When
`high` is specified, announcements will interrupt other speech and cannot be interrupted once started"]**.

**Governing split [reasoned], mirroring `:238`:** the board reports *state*, announcements report *events*. A
fact that stays true is on an element; a fact that happens is an announcement. Nothing is both.

| # | Event | Spoken | Priority | Why this priority |
|---|---|---|---|---|
| 1 | Human move committed | the traditional move string, e.g. 炮二平五 | **low** | The user just acted and knows what they did; nothing should interrupt whatever they were reading. Queued. |
| 2 | AI move committed | AI 的一步 + the move string | **default** | New information the user did not cause. Should interrupt idle speech; must remain interruptible so a user exploring the board can talk over it. |
| 3 | Check arises | appended to #1 or #2, **not a separate announcement** | as its carrier | Check is a persistent state that then lives on the general's point and the 将军 token (`:248`, `:271`). Announcing it separately would double-report the one thing `:249` already went to trouble to give a stable home. |
| 4 | Natural terminal result | result + reason, e.g. 红方获胜 · 将死 | **high** | The **only** high-priority announcement in the app. It ends the game; a user who missed it would keep trying to move. "Cannot be interrupted once started" is correct here and nowhere else. |
| 5 | Undo applied | 已悔棋 + the move now last | **default** | |
| 6 | Piece selected | piece + coordinate + destination count | **default** | The count is cheap and tells the user how long the next step is; median 2, p95 8 **[measured]**. |
| 7 | Selection cancelled | 已取消选择 | **low** | |
| 8 | Illegal activation **with a piece selected** | §5.1 | **default** | |
| 9 | Illegal activation **with nothing selected** | *nothing* | — | The point had no button trait; VoiceOver already said so. `:258`'s beat carries no information, so its spoken form is silence. |
| 10 | Replay step (manual or autoplay) | ply number + move string | **low** | At 2× autoplay, `default` would be a flood. Playback "waits for each move animation to finish before advancing" (`:362`), which bounds the rate; `low` queues the rest. |
| 11 | Save failure of a move or Undo | *nothing from the board* | — | Turn-status element value (`:257`). |
| 12 | AI thinking passes the 500 ms threshold | *nothing* | — | Turn-status element value. An announcement would interrupt for a state that may last five seconds (`:195`, `:424`). |
| 13 | Board flipped | 已翻转棋盘，红方在下 / 黑方在下 | **default** | The reading order of 49 elements just reversed. Not announcing it would be a silent re-map. |

Rows 1–2 discharge the accessibility announcement required by `:247`. Row 3 discharges `:249`. Flip Board's
label (`:218`) and History's custom actions (`:386`) are element properties, not announcements, and are named
here only so the four accepted requirements are visibly accounted for.

**HIG constraint on all of them [cited: HIG › Accessibility › Cognitive — "Minimize use of time-boxed
interface elements. Views and controls that auto-dismiss on a timer can be problematic for people who need
longer to process information, and for people who use assistive technologies that require more time to
traverse the interface. Prefer dismissing views with an explicit action"]**. The accepted save-failure capsule
and acknowledgment beat are both time-boxed. Their spoken counterparts are announcements and element values,
neither of which steals focus or requires dismissal — so the model complies without changing the visual design.

### 5.1 The illegal tap, when the visual answer is a pulse

The accepted response is pedagogical, and its reasoning is explicit: "the question a learner is asking is where
this piece may go, and answering it teaches more than marking the rejected point" (`:250`). The spoken response
has to teach the same thing.

With a piece selected, activating a point that is not one of its destinations:

- posts a `default`-priority announcement of the form **不能走到 ⟨point⟩。⟨piece⟩ 可走：⟨list⟩**;
- enumerates up to **six** destinations, then, if more remain, 共 N 个 and a pointer to the Destinations rotor.
  Six is chosen against the measured distribution: p95 is 8 and the max is 12, so the cap fires on well under
  5 % of selections **[measured]**;
- **retains the selection**, per `:250`, so the correction is one action away;
- fires the platform's lightest selection-weight feedback where the hardware has it, never the warning pattern
  (`:250`, `:440`). Haptics and speech do not compete, so this needs no adjustment;
- draws no board mark, and posts nothing under Reduce Motion that it would not post otherwise. `:428` removes
  *animation*; there is no animation here to remove, and the accepted rule is that "every state survives."

With nothing selected, row 9 above: silence, because the point was never a button.

---

## 6. Speaking traditional notation in both languages

The move list is character-based in both interface languages (`:71`, `:168`), so VoiceOver will read Chinese
characters in an English build. Three concrete hazards, two of which have documented fixes.

### 6.1 Polyphones — a real defect, with a partial fix

Two of the five accepted piece characters have a Xiangqi-specific reading that differs from their ordinary one:

| Character | Ordinary reading | Xiangqi reading | Where it appears |
|---|---|---|---|
| **车** (Black chariot) | chē | **jū** | `:64`, and every 车 move in a Black move string |
| **将** (Black general) | jiāng | **jiàng** | `:63` — while **将军** ("check", `:249`, `:271`) is jiāngjūn |

A general-purpose Chinese voice will get at least one of these wrong, and 将 wrong in *both* directions inside
the same app. **[cited: UIKit › Speech attributes for attributed strings; Foundation ›
`AttributeScopes.AccessibilityAttributes.IPANotationAttribute` — "The IPA representation defines pronunciation
of words that have the same spelling but different sounds," with a worked homograph example]**. Every spoken
occurrence of 车 and 将 in a game context should carry `accessibilitySpeechIPANotation`.

**Honest limitation, stated rather than glossed [cited: same page — "Note: This attribute is not used on
macOS"]**. On macOS the fix is unavailable. The exposure is that a Mac VoiceOver user hears 车 as chē and 将 as
jiāng; it is a comprehension annoyance rather than an ambiguity, since no other piece is a candidate. Record it
as a known platform gap, not as something the design solved.

### 6.2 Language of the utterance

**[cited: Foundation › `NSAttributedString.Key.accessibilitySpeechLanguage` — "The value of this key is an
`NSString` object that contains a BCP 47 language code. When applying it to text in a string, the rules for the
specified language govern how to pronounce that string"]**. Move strings and piece characters carry
`zh-Hans` in every build, so an English-voice user does not hear CJK read as garbage or skipped.

That fixes pronunciation and not comprehension: an English-interface user who does not read Chinese now hears a
correctly pronounced Mandarin move they cannot use. **Owner decision C.**

### 6.3 Numerals

Red writes Chinese numerals and Black Arabic, "and that applies to every number in a move" (`:163`). So 炮二平五
and 炮2平5 are the same move by opposite sides.

- The digits in a Black move are *file identifiers*, not quantities — but they are single digits 1–7, so a TTS
  reads them correctly without help. **Do not** apply `speechSpellsOutCharacters` here.
- A **move count** (42 步, `:305`) *is* a quantity and must be read as forty-two. **[cited: SwiftUI ›
  `Text.speechSpellsOutCharacters(_:)` — "A number representing a series of digits, like 25, spoken as
  'two-five' rather than 'twenty-five'"]** is the modifier that would break this if applied globally. Stating
  the asymmetry now is cheaper than debugging it later.

### 6.4 The two-piece rule

「前炮退二」 — 前/后 leads, before the piece name, with the file omitted (`:166`). Spoken as written; no
special handling. **[measured]** the related ambiguity — destinations reachable by more than one piece of the
same type average 1.008 per position and reach 9 — which is a notation question (survey item 6.5), not a
speech one. Named here only so the two are not confused: the notation's job is to disambiguate the *move*, and
the coordinate in every rotor entry and action name disambiguates the *piece*.

---

## 7. New user-facing copy this model requires

Simplified Chinese is the source language and its copy is normative (`:455`), so every string below is a
Chinese string that needs approving, with an English counterpart written under part 6's rules. This is the
collision the survey flagged: part 7 and part 8 both mint copy that part 6 then owns. Listing it rather than
approving it.

| Purpose | Proposed Chinese | Proposed English |
|---|---|---|
| Board container label | 棋盘 | Board |
| Summary element label | 局面 | Position |
| Empty point value | 空 | Empty |
| Legal destination | 可走 | Legal move |
| Legal capture | 可吃 | Can capture |
| In check, on the general's point | 被将军 | In check |
| Last move origin / destination | 上一步起点 / 上一步落点 | Last move from / Last move to |
| Movable-pieces rotor | 可走的棋子 | Movable pieces |
| Destinations rotor | 可走点 | Destinations |
| Deselect action | 取消选择 | Deselect |
| Move-to action (per destination) | 走到 ⟨point⟩ | Move to ⟨point⟩ |
| Go to last move | 移到上一步落点 | Go to last move |
| Go to checked general | 移到被将军的将 | Go to the general in check |
| Illegal activation | 不能走到 ⟨point⟩。⟨piece⟩ 可走：⟨list⟩ | Can't move there. ⟨piece⟩ can move to ⟨list⟩ |
| Overflow after six | 共 ⟨N⟩ 个 | ⟨N⟩ in all |
| Selection | 已选中 ⟨piece⟩ ⟨point⟩，⟨N⟩ 个可走点 | ⟨piece⟩ at ⟨point⟩ selected, ⟨N⟩ destinations |
| Undo | 已悔棋 | Move taken back |
| AI move prefix | AI 的一步 | AI played |
| Flip confirmation | 已翻转棋盘，红方在下 / 黑方在下 | Board flipped, Red at the bottom / Black at the bottom |
| Rank keys (7) | 第一线 … 第七线 | Rank 1 … Rank 7 |
| Material (if adopted) | 红方 ⟨N⟩ 子，黑方 ⟨M⟩ 子 | Red ⟨N⟩ pieces, Black ⟨M⟩ pieces |
| Point coordinate | **Owner decision B** | **Owner decision B** |

The English column also has to resolve the accepted contradiction between `interaction-design.md:74`
("General") and `xiangqi-rules.md:24-28,45` ("king"), because "Go to the general in check" and "General at …"
are strings in this model. Not mine to resolve — survey item 6.3, owner's.

---

## 8. What this contributes to 8.2 and 8.3

**VoiceOver's pass condition**, which 8.2 says it is blocked on:

> An end-to-end nonvisual game: with Screen Curtain on, start a Human-versus-AI game from the pre-start state,
> play at least ten legal moves including one capture and one check evasion, reach and confirm a natural
> result, and open the resulting replay and step through it — with no step requiring sight, no state
> discoverable only visually, and every row of the §1.2 marker table and the §5 announcement table exercised.

**[cited: Accessibility › Performing accessibility testing for your app — "Install your app on a physical
device, since VoiceOver isn't available on Simulator"; and "turn on the *screen curtain* to replicate the
experience of someone who is solely relying on VoiceOver"]**. So this gate needs real hardware, which is one of
the four artefacts 8.3 identifies as blocking `testing.md`. If the owner takes option (a) on Owner decision A,
this gate cannot be satisfied before a device matrix exists; the model can still be accepted as design.

`testing.md:149` already asserts "an end-to-end nonvisual board interaction" as a requirement, in a draft
document. It is the right requirement. Promoting it to accepted is Owner decision A.

**Keyboard coverage**, which 8.2 also lists as missing: this model names, for VoiceOver, a set of operations
that a keyboard equivalent must also reach — move focus by point, select, enumerate destinations, commit,
deselect, jump to last move, step replay, flip. The contract currently names a keyboard command for Flip Board
and nothing else (`:218`). That list is 8.2's to turn into criteria; it is recorded here because the two
designs share the same focus concept (§3) and should not be written twice.

**Windows / Narrator** is deferred by `:536`, but `:386` already names Narrator, so equivalence is
contemplated. Recommendation: express the accepted contract in the platform-neutral terms this document uses —
an element tree, a per-point spoken content table, two navigation shortcuts, two navigation actions, and an
announcement set with three urgency levels — so that the Windows section, when written, is a mapping table
rather than a second design. Every construct has a UI Automation counterpart. Not designing it here.

---

## 9. Apple documentation: what exists and what does not

Searched with `mcp__xcode__DocumentationSearch` against the pinned Xcode 27 beta (`27A5228h`) documentation.

**Found and used above:** `AccessibilityChildBehavior.contain`; `accessibilityCustomContent(_:_:importance:)`
and `AXCustomContent.Importance`; SwiftUI Accessible navigation and `AccessibilityRotorEntry`, including the
ScrollView constraint and the namespace escape hatch; `AccessibilityNotification` and `.Announcement`;
`AnnouncementPriorityAttribute` and `UIAccessibilityPriority`; `accessibilityAdjustableAction(_:)`;
`accessibilityActions(_:)` and `accessibilityAction(named:_:)`; `AccessibilityFocusState.init(for:)`;
`UIAccessibilityFocus`; `UIAccessibilityTraits.updatesFrequently` and `.allowsDirectInteraction`;
`UIAccessibility.DirectTouchOptions` with `silentOnTouch` and `requiresActivation`;
`accessibilitySpeechLanguage`, `accessibilitySpeechIPANotation`, `IPANotationAttribute` (with its macOS
caveat), `speechSpellsOutCharacters`; HIG › Accessibility › Cognitive; HIG › Accessibility › Vision;
Accessibility › Performing accessibility testing for your app; UIKit › Supporting VoiceOver in your app;
Accessibility › Vision › Braille displays.

**Not found — reported as absence, not filled in:**

- **No Apple guidance for a board game's screen-reader model.** HIG › Designing for games has a "Welcome
  everyone" section whose vision advice is "Prioritize perceivability … avoid relying solely on color," and
  Game controls covers touch and physical controllers. Neither addresses element granularity for a grid,
  announcing a board position, or piece selection with a screen reader. The closest artefact in the entire
  library is the sample project **Accessibility › WWDC21 Challenge: VoiceOver Maze** ("Navigate to the end of a
  dark maze using VoiceOver as your guide"), which is a companion download with no design prose in the
  documentation set. **This model is ours to design and ours to justify.**
- **No guidance on announcement volume or pacing during ongoing play.** The priority semantics are documented;
  how many announcements per minute a user will tolerate is not. §5's assignment of exactly one `high`
  announcement in the whole app is a judgement, not a citation.
- **No Apple text on speaking CJK game notation.** The pronunciation APIs exist; the fact that 车 is jū is
  domain knowledge, and the requirement in §6.1 is ours.

---

## Open for the owner

Four decisions, each genuinely the product owner's rather than a designer's, with what each costs.

### A. Is an end-to-end nonvisual game a *supported capability* or a *best effort*?

`testing.md:149` already asserts the former, inside a draft document. Promoting it is a commitment.

- **(a) Supported and gated.** §8's pass condition becomes a release gate. Cost: it requires physical devices
  (VoiceOver is not on Simulator), so it cannot be satisfied until 8.3's device matrix exists; and `:536`'s
  Windows deferral acquires an obligation, because a capability the product claims cannot be Apple-only.
- **(b) Best effort.** The model is designed and built; the gate stays advisory. Cost: no one is accountable
  for the model surviving contact with the app, which for a design-first repository is how a model quietly
  degrades to labels-only.
- **(c) Out of scope for the internal MVP.** Cost: contradicts `:15` ("Treat accessibility as part of the
  design, not as a later visual adjustment") and the six commitments at `:442`–`:451`, and would need those
  amended rather than merely left alone.

Recommendation, offered not chosen: **(a) for Apple platforms, with the Windows equivalent explicitly deferred
in the same sentence.** That is the only option that keeps `:15` honest without writing a cheque on a frontend
that does not exist.

### B. What is a point called out loud?

**Traditional Xiangqi notation has no absolute coordinate for a point.** Files are numbered from each player's
own right; "Ranks carry no labels, as they do not on a Xiangqi board" (`:167`). A move is named by a file, a
direction and a count — never by a square. So a model in which the user navigates 49 individually addressable
points *must invent a name for a point*, and no accepted contract supplies one. This is new user-facing
vocabulary in the source language, and a teaching decision about whether a learner acquires a coordinate system
that no Xiangqi book will ever use.

- **(a) Per-side file and rank** — e.g. 三路四 / "file 3, rank 4", the file from the speaker's own right and the
  rank counted outward from their own back rank. Extends the accepted per-side numbering consistently; flips
  with the board; every number the user hears is a number in their own frame. Cost: the same point has two
  names, one per side — though `:163` already accepts exactly that for files, so it is consistency rather than
  a new inconsistency. Cost: it is invented vocabulary that a book will not reinforce.
- **(b) The canonical `a1`–`g7`** (`xiangqi-rules.md:34`). Already exists, is stable, is what an archive, a
  fixture and a support conversation contain, is identical for both players and survives a flip. Cost: Latin
  letters read awkwardly under a Chinese voice; it is not per-side, so it clashes with every number the
  notation teaches; and `:161` is explicit that traditional notation was chosen so "a learner should be able to
  carry what they read here into any Xiangqi book" — a coordinate system pulling the other way is a small
  countercurrent to that.
- **(c) (a) spoken, (b) available on request** as `.default`-importance custom content on each point. Cost:
  near zero to build; one more thing in the More Content rotor.

Recommendation, offered not chosen: **(c)** — (a) is the one that matches what the app teaches, and (b) costs
one line and is what a user will need the first time they want to report something.

### C. What does an English build speak for a Chinese move list?

The characters are accepted game content and are never translated (`:71`); the move list stays character-based
even for a user who chose icon symbols (`:168`). With `accessibilitySpeechLanguage` set (§6.2) an English-build
VoiceOver user hears correctly pronounced Mandarin they may not understand.

- **(a) Chinese only.** Consistent with "piece characters are game content." Cost: for an English-reading blind
  user the move list is unusable, and the move list is how a game is followed.
- **(b) Chinese visible, English gloss spoken** — the element's visible text stays 炮二平五 and its accessibility
  label is "Cannon on file 2 moves across to file 5". Cost: the spoken and visible forms differ, which is
  exactly the divergence a sighted assistant will trip over; and it needs a full English rendering of the
  notation grammar, which is new work.
- **(c) Both** — Chinese as the label with its speech language set, English gloss as `.default`-importance
  custom content. Cost: two forms to keep in step; a user who wants the gloss asks for it every time.

**This is the same decision as survey item 6.7** ("what a user reading icon symbols is offered for the move
list", `:520`). Decide it once, for both, or the two answers will diverge.

### D. Does the position summary state material counts?

`:498` and `product.md:28` decline a captured-piece display because "what remains on the board is directly
countable at a glance." A blind player cannot glance; counting means traversing the board.

- **(a) Include** 红方 N 子，黑方 M 子 in the summary's custom content. It is a description of what is on
  screen, which is what a screen reader is for, and it repairs a justification that does not hold for this
  user. Cost: it hands a blind player a pre-computed number a sighted player has to count, which is a small
  asymmetry in the other direction, and it partially reverses the reasoning of an accepted product decision.
- **(b) Omit.** Strict parity with the sighted board. Cost: material balance — the most basic fact about a
  Xiangqi position after whose move it is — costs 49 swipes or one full summary read.

Small, but it touches an accepted product decision, which is the test for escalating it. Recommendation,
offered not chosen: **(a)**, on the ground that `:498`'s own stated reason is a claim about glanceability and
the claim is simply false for this user.

---

## Files

- Report: `/Users/tianren/coding/minixiangqi/discussion-drafts/p8-voiceover.md`
- Measurement scripts: `/Users/tianren/coding/minixiangqi/discussion-drafts/vo-measure.py`,
  `/Users/tianren/coding/minixiangqi/discussion-drafts/vo-measure2.py`
- Engine used: `/Users/tianren/coding/minixiangqi/discussion-drafts/w-base/pyffish.cpython-314-darwin.so`,
  variant `minixiangqi`, seed 20260728

---

# Independent review

Adversarial verification pass by a second agent. Method: I re-executed both measurement scripts against the
same engine build; I re-read every cited line of `interaction-design.md`, `product.md`, `xiangqi-rules.md` and
`testing.md`; and I re-searched every Apple citation with `mcp__xcode__DocumentationSearch` against the pinned
Xcode 27 beta documentation. Findings are ordered most severe first. Everything not listed here I checked and
found sound.

## What survived verification

**[executed]** Both scripts reproduce exactly. `vo-measure.py`: 42 048 positions, legal moves min 1 / p25 18 /
median 23 / mean 22.08 / p75 27 / p95 33 / max 46; movable pieces median 8, p95 11, max 12; destinations per
piece median 2, mean 2.89, p95 8, max 12 over n = 320 738; pieces on board median 18, max 24; start position 19
moves, 7 movable pieces, `{a2:2, b1:5, c2:2, d2:1, e2:2, f1:5, g2:2}`. `vo-measure2.py`: 12 122 positions,
0.9237 ambiguity fraction, pieces per rank median 2 / mean 2.49 / p95 5 / max 7, empty-rank fraction 0.082,
same-type shared destinations mean 1.008 / max 9, captures 0.1169. The max-12 example is a chariot on `c7`
with rank 7 and file c both empty, and 12 is a provable ceiling on 7×7 (≤ 6 along a rank, ≤ 6 along a file, and
no other piece type reaches more). §4.0 is trustworthy.

**[cited]** Sixteen Apple quotations checked word for word and all correct: `AccessibilityChildBehavior.contain`
and `.combine`; the `accessibilityCustomContent` importance sentence; Accessible navigation's rotor definition;
the `ScrollView` requirement sentence; `AccessibilityRotorEntry`'s namespace paragraph; `AccessibilityNotification`;
`AnnouncementPriorityAttribute`'s low/default/high semantics; `AccessibilityFocusState.init(for:)`;
`UIAccessibilityFocus` (including — verified — that the same Discussion does recommend moving selection with
focus, so §3's characterisation is fair); `UIAccessibilityTraits.updatesFrequently`;
`UIAccessibility.DirectTouchOptions`; Performing accessibility testing (Simulator, screen curtain, the gesture
table); `accessibilitySpeechLanguage`; `IPANotationAttribute` with its “live” homograph example and its macOS
note; `Text.speechSpellsOutCharacters(_:)`'s 25 → “two-five” example; HIG › Accessibility › Cognitive;
`accessibilityAdjustableAction(_:)`'s page-navigation example; Braille displays; Designing for games ›
Welcome everyone; and the WWDC21 VoiceOver Maze sample. **No fabricated citation was found.**

Contract quotations at `:233`, `:238`, `:244`–`:253`, `:157`, `:161`–`:168`, `:216`, `:218`, `:257`–`:258`,
`:362`, `:386`, `:424`, `:428`, `:440`, `:455`, `:480`, `:498`, `product.md:28`/`:33`/`:41`, `testing.md:149`
and `xiangqi-rules.md:34`/`:36`/`:96` are accurate, except where noted below.

---

## 1. The one rule offered as auditable is falsified by the report's own tables — **major**

> §1.2: "**Every accepted board marker has exactly one spoken carrier, and no state has two.** … a one-to-one
> map, so a reviewer can check it exhaustively rather than by taste, and so that no state is either silent or
> double-reported."

> §5: "the board reports *state*, announcements report *events*. A fact that stays true is on an element; a
> fact that happens is an announcement. **Nothing is both.**"

The last-move state has **five** carriers in this document: custom content 上一步起点 on the origin point and
上一步落点 on the destination (§1.2), the §5 row 1/2 announcement (which §1.2's own row concedes: "plus the move
announcement in §5"), the 上一步 entry in the summary element's custom content (§4.1), and the 移到上一步落点
action (§4.3). Selection has two: `.isSelected` on the point (§1.2) and the row 6 announcement — a state and an
event for the same fact, which the §5 split says cannot happen. Check has two by the same test: the value suffix
被将军 plus the appended check on rows 1–2.

This is not a nitpick, because §1.2's stated value is *precisely* that a reviewer can audit it mechanically. As
written, the first row a reviewer audits fails.

**Correction.** Split the rule into the two claims that are actually true and defensible: (a) every accepted
board marker has exactly one *primary* spoken carrier — the thing a user hears when focus lands on the point;
(b) a state that is also an event additionally gets exactly one announcement, and the summary, rotor and
navigation-action repetitions are deliberate secondary access paths, not double-reporting. Then the table can be
audited against a rule it satisfies. Delete "Nothing is both" or restrict it to "nothing is announced twice."

## 2. The two navigation actions and the replay adjustable action are attached to an element VoiceOver will not focus — **major**

> §4.3: "**Two custom actions on the board container.**"
> Replay: "an `accessibilityAdjustableAction` on the board container where increment is one move forward and
> decrement one back."

The container is declared `accessibilityElement(children: .contain)` (§2.1). **[cited]** SwiftUI ›
`AccessibilityChildBehavior.contain`: "An accessibility container groups child accessibility elements which
improves navigation. For example, all children of an accessibility container are navigated in order before
navigating through the next accessibility container." The container's purpose is that its *children* receive
focus. VoiceOver's Actions rotor surfaces the actions of the focused element; with focus on a point element,
actions declared on the ancestor container are not in that list. The report's own §2.1 says the container is a
region "a user can enter, leave, and skip past" — never one that focus rests on.

The adjustable action is the sharper case. **[cited]** Apple's documented pattern for exactly this — a page
control driven by `accessibilityAdjustableAction` — is on `AccessibilityChildBehavior.ignore`, which creates a
**single** element with no children:

> "`.accessibilityElement(children: .ignore)` … `.accessibilityValue("Page \(pageNumber) of \(pages.count)")`
> `.accessibilityAdjustableAction { action in … }`"

So the replay stepping mechanism the report calls "the closest thing to leafing through a game record" is, as
specified, unreachable — while §Replay simultaneously says "no point carries an actionable trait", leaving
nothing else on the board focusable that could carry it.

This is the same class of trap the report itself catches for rotors, which makes its absence here conspicuous.

**Correction.** Attach all three to the **position-summary element**, which is first in the swipe order and
already focusable, and say so explicitly in the contract; or state that the board container must additionally be
made a focusable element in its own right and accept the extra swipe. I could not run this on hardware —
VoiceOver is not on Simulator, per the report's own citation — so treat this as **plausible, verify on device**,
but it must not ship as an unexamined assumption.

## 3. §2.3's rank order contradicts published Apple guidance and the report's own tie-break argument — **major**

> §2.3: "**Rank by rank from the near side outward** … explore-by-touch cannot be reordered: dragging a finger
> left to right across the board *will* produce 七 六 五 四 三 二 一 whatever the swipe order is, and a swipe
> order that disagreed with the touch order would give the same board two contradictory geometries."

The argument is applied to the horizontal axis and then silently abandoned on the vertical one. A finger dragged
down the board produces far-rank-first; a swipe order that runs near-rank-first disagrees with it in exactly the
way the report says is disqualifying. The tie-break proves too much or too little.

**[cited, and not cited by the report]** HIG › VoiceOver › Navigation: "VoiceOver reads elements in the same
order people read content in the their active language and locale. For example, in US English, this is
top-to-bottom, left-to-right." Both supported languages are top-to-bottom. §2.3 chooses the opposite vertical
order without acknowledging the guidance, while §3 goes to some trouble to declare and justify its one
deliberate divergence from Apple advice. The asymmetry of care is the defect.

**Correction.** Either adopt top-to-bottom (far rank first, matching both the drawn board and the documented
reading order) and lose the "near side first" convenience, or keep near-side-first and add a §3-style paragraph
saying which Apple guidance is being departed from and why a board is not a document. Do not leave it silent.
Note also that near-side-first makes the linear order differ from what a sighted helper sees, which matters for
the mixed-sight use the internal group will actually have.

## 4. Owner decision B's premise is contradicted by the report's own §0 — **moderate**

> Owner B: "So a model in which the user navigates 49 individually addressable points *must invent a name for a
> point*, and **no accepted contract supplies one**."

> §0, row 12: "Squares are named `a1` through `g7` … | `xiangqi-rules.md:34`, `:36` | **A machine-stable
> coordinate exists.** Whether it is the one spoken is Owner decision B."

`xiangqi-rules.md:34` reads: "Squares are named `a1` through `g7`: files `a` to `g` from Red's left, ranks `1`
to `7` from Red's back rank." That is an accepted, absolute, per-point name. Option (b) of the same decision
then offers it. The decision's headline sentence and its own option (b) cannot both be true.

The true and still-interesting claim is narrower: no accepted contract supplies a *spoken, user-facing* name,
and traditional notation supplies no absolute one. That is enough to justify escalating; the overstatement is
what a reviewer will catch and it costs the item credibility.

**Correction.** Rewrite the premise as "traditional notation has no absolute point coordinate, and no accepted
contract supplies a *user-facing* name for a point; `a1`–`g7` exists but is accepted only as machine notation
(`xiangqi-rules.md:36`)."

## 5. §7 proposes rank vocabulary as approvable copy while Owner B leaves rank naming open — and the two schemes disagree — **moderate**

> §4.1: "| 第一线 … 第七线 (seven entries) | that rank's contents, **near side first** |"
> §7: "| Rank keys (7) | 第一线 … 第七线 | Rank 1 … Rank 7 |"
> Owner B (a): "**三路四** / 'file 3, rank 4', the file from the speaker's own right and the rank counted
> outward from their own back rank."

Three problems in one thread. First, 第一线 with "near side first" means the near player's own back rank, so its
referent **flips with the board** and differs between the two sides — a decision of exactly the kind Owner B
says is unsettled, presented in §7 as ready for approval. Second, under option B(b) (`a1`–`g7`) rank 1 is Red's
back rank absolutely, so adopting (b) silently changes what 第一线 denotes; the copy table and the open decision
are coupled and the report does not say so. Third, the same rank is called 四 in the coordinate and 第四线 in the
summary key — one model, two names for one thing, which is the very failure §4.0's conclusion 3 warns about for
pieces.

**Correction.** Move the rank keys into decision B, or fix them to the canonical (Red-relative) rank and state
that the summary reads ranks in a fixed absolute order regardless of orientation. Whichever is chosen, make the
coordinate string and the rank key use the same word for a rank.

## 6. Rows 8 and 9 rest on contradictory assumptions about activating a point that is not a button — **moderate**

> §5 row 9: "Illegal activation **with nothing selected** | *nothing* | — | **The point had no button trait;
> VoiceOver already said so.**"
> §5 row 8 / §5.1: "With a piece selected, activating a point that is not one of its destinations … posts a
> `default`-priority announcement."

Per §2.4, a point that is not a legal destination of the selection carries **no trait** in both cases. Row 9's
stated reason therefore applies verbatim to row 8. Either a non-button point can be activated — in which case
row 9's justification collapses and its silence needs a different reason — or it cannot, in which case §5.1, the
most carefully argued paragraph in the document, describes an event that never fires.

Separately, `:250` is explicit that the haptic fires in **both** cases: "**Either way** the platform's lightest
selection-weight feedback fires where the hardware provides it, never the warning pattern." §5.1 lists the
haptic only for the with-selection branch, and row 9 says "nothing". As written the model drops an accepted
behaviour. This is a proposal that contradicts accepted text, not a suggestion.

**Correction.** Say what mechanism makes an inert point activatable (in practice VoiceOver's default activation
forwards a synthetic tap to the underlying view, which is what reaches the app's existing illegal-tap path), and
then give row 9 its real reason — that with nothing selected there is no destination list to teach, so `:250`'s
own pedagogical argument yields no sentence. Restore the accepted haptic to row 9 explicitly.

## 7. §6.1's polyphone table is incomplete, and the report's own copy contains the defect it identifies — **moderate**

> §6.1: "**Two of the five accepted piece characters** have a Xiangqi-specific reading that differs from their
> ordinary one: 车 … 将."

There are **ten** accepted piece characters, not five — `interaction-design.md:63`–`:67` gives a distinct Red and
Black form for each of five types. And the table omits **俥**, Red's chariot, which carries the same Xiangqi
reading *jū* and is a rarer character that a general Mandarin voice is at least as likely to mispronounce or fail
to map at all. Every Red chariot move in the move list contains it. The defect the section exists to report is
under-reported by half.

Worse, §7's own proposed string reproduces the hazard inside one phrase:

> "| Go to checked general | **移到被将军的将** | Go to the general in check |"

That string contains 将军 (*jiāngjūn*, check) and 将 (*jiàng*, the Black general) three characters apart — the
"same character wrong in both directions" case, in a single spoken action name, in a document that flags the
problem two sections earlier.

**Correction.** Add 俥 (and state that 车/俥 are both *jū*) to the table. Either rewrite the action string to
avoid the collision (e.g. name the piece by its coordinate rather than by 将) or mark it in §7 as a string that
must carry per-run IPA, with the macOS gap explicitly inherited.

## 8. §7 does not in fact contain every new string the model requires — **moderate**

> §7: "every string below is a Chinese string that needs approving".

At least two required strings are missing. §5 row 4's example — "result + reason, e.g. **红方获胜 · 将死**" —
introduces **将死** as user-facing Chinese. 红方获胜 is accepted (`:340`), but no contract supplies Chinese copy
for a termination reason: `xiangqi-rules.md:92` defines only the machine identifiers `checkmate`, `stalemate`,
`threefold-repetition`, `perpetual-check`, `perpetual-chase`, and `:340` says only "A second line explains the
result reason" without fixing words. §5 row 10 ("ply number + move string") likewise needs a counter string that
is nowhere proposed.

**Correction.** Either add the five reason strings and the replay-step string to §7, or replace the row 4
example with a placeholder and state that result-reason copy is owned elsewhere and is a prerequisite for row 4.

## 9. Register and terminology problems in the proposed copy — **moderate**

> §7: "| AI move prefix | **AI 的一步** | AI played |"

This is a bare noun phrase, not a statement. Concatenated it yields "AI 的一步 炮二平五", which reads as a caption
rather than a report. Every accepted Chinese string in the contract is a finite statement or a command: 轮到红方
(`:268`), 已记录到历史 (`:343`), 无法保存这一步，请重试。 (`:257`), 局面已三次重复，可以和棋结束。 (`:350`). A verb
form — AI 走 炮二平五, or AI：炮二平五 — matches that register; the current string does not.

> §7: "| Move-to action (per destination) | **走到** ⟨point⟩ |" against "| Go to last move | **移到**上一步落点 |"

One character separates a committing game move from a focus jump with no game effect, in a spoken list, for a
user who cannot see which is which. 移 and 走 are also near-synonyms in ordinary Chinese. Prefer a verb for the
navigation actions that cannot be read as moving a piece — 跳到… or 转到… — and keep 走到 for the move.

Otherwise the copy is consistent with accepted terminology: 已悔棋 matches `:341`'s 悔棋, 被将军 matches `:249`'s
将军 token, 可走的棋子 is correctly preferred over 你的棋子 for the reason given (`product.md:33`). No proposed
string is an irreversible action needing a consequence clause — 取消选择 is trivially reversible and 走到 ⟨point⟩
commits an ordinary legal move, which `:224` explicitly exempts from confirmation. That part is right.

## 10. Owner A misplaces a cost that accepted text already imposes, and its recommendation needs a decision it does not name — **moderate**

> Owner A (a): "Cost: … `:536`'s Windows deferral acquires an obligation, **because a capability the product
> claims cannot be Apple-only**."

That obligation is not created by choosing (a); it is already accepted. `interaction-design.md:25`: "Platform
adaptation may change presentation, but it must not create different product capabilities without an explicit
product decision." `:506`: "the same operations must be exposed through that platform's conventional
equivalents … without changing product capabilities." `product.md:24`: "Product behavior and persisted meaning
are identical across platforms."

Which makes the recommendation the live issue:

> "Recommendation … **(a) for Apple platforms, with the Windows equivalent explicitly deferred in the same
> sentence.**"

That *is* a platform capability difference, and `:25` says one requires an explicit product decision. The
recommendation is defensible, but it should say that it is asking the owner to record that explicit decision,
not present the deferral as free.

Minor, same item: "`:442`–`:451`" starts at the `## Accessibility` heading; the six bullets are `:446`–`:451`.
And they are things the design "**must consider**", not commitments — so option (c) would arguably leave them
intact rather than requiring amendment. Weaken that sentence or cite `:15` alone, which does carry the weight.

## 11. `:71` is quoted without the clause that limits it — **minor, but it distorts Owner C**

> Contract `:71`: "Piece characters are game content, not interface text: they are identical in every supported
> language and are never translated **on the board**."
> §0: "Piece characters 'are identical in every supported language and are never translated.'"
> Owner C: "The characters are accepted game content and are never translated (`:71`)".

Dropping "on the board" turns a board-scoped rule into a global one, which makes option C(a) look
contract-mandated and options (b) and (c) look like departures from accepted behaviour. They are not: `:74`
positively permits English piece names in "accessibility announcements", and what actually keeps the move list
character-based is `:168` plus `:161`–`:164` (traditional notation names pieces by their characters), which the
report cites elsewhere.

**Correction.** Ground the constraint on `:168` and `:161`–`:164`, and quote `:71` in full or not at all.

## 12. A documented failure mode is asserted that the cited pages do not state — **minor**

> §4.2: "An engineer who reaches for the `entries:` array overloads will find it **silently does nothing**."

**[cited]** The pages say "Using this modifier requires that the Rotor be attached to a `ScrollView`, or an
Accessibility Element directly within a `ScrollView`, such as a `ForEach`." That is a stated requirement; the
consequence of violating it — silent no-op versus runtime warning versus partial behaviour — is nowhere
documented. The rest of the paragraph is correct and is a genuinely useful catch; only this clause overreaches.

**Correction.** Mark the clause **[reasoned]**, or write "the documentation states a requirement and does not
say what happens when it is unmet; assume the rotor does not appear."

## 13. Three citations are filed against the wrong page (text itself verified correct) — **minor**

- §4.5 attributes "`silentOnTouch` is 'Appropriate for apps that provide direct audio feedback on touch that
  would conflict with speech feedback'" to **UIKit › `UIAccessibility.DirectTouchOptions`**. That exact sentence
  is on **SwiftUI › `AccessibilityDirectTouchOptions.silentOnTouch`**; UIKit's own `silentOnTouch` page words it
  differently ("so that VoiceOver doesn't compete with the keyboard sounds"). The DirectTouchOptions quote in
  the same bracket *is* from the UIKit page and is correct.
- §9 files Braille displays under "**Accessibility › Vision**". The page is at
  `/documentation/Accessibility/braille-displays`, listed under **Accessibility API › Braille**.
- §7 cites "`xiangqi-rules.md:24-28,45`" for the "king" terminology. `:45` is the horse's movement rule; the
  king lines are `:28`, `:29`, `:42`–`:43`. The contradiction with `interaction-design.md:74` is real and worth
  escalating — only the line reference is wrong.

Also worth stating more carefully: §6.1's "This attribute is not used on macOS" is a note on the Swift
`AttributeScopes.AccessibilityAttributes.IPANotationAttribute` symbol. `NSAttributedString.Key.accessibilitySpeechIPANotation`
and `UIAccessibilitySpeechAttributeIPANotation` carry no such note. The inference that macOS VoiceOver ignores
IPA is plausible — the identical note appears on `QueueAnnouncementAttribute` and `TextualContextAttribute`, so
it is systematic — but it is an inference from one symbol's note rather than a documented statement about the
platform. Say which, since the whole point of that paragraph is honesty about a gap.

## 14. §9's sweep omits the one HIG page written about designing for a screen reader — **minor**

§9 lists HIG › Accessibility › Cognitive and › Vision among "found and used", and reports as **not found**: "No
Apple guidance for a board game's screen-reader model." The first claim is true and the second is true as
stated. But **HIG › VoiceOver** exists, is neither cited nor recorded as absent, and its Navigation section
speaks directly to four decisions this document makes:

> "Specify how elements are grouped, ordered, or linked. … Examine your app for places where relationships among
> elements are visual only. Then, describe these relationships to VoiceOver." — bears on §2.1's container.
> "VoiceOver reads elements in the same order people read content in the their active language and locale." —
> bears on §2.3, and contradicts it; see finding 3.
> "Inform VoiceOver when visible content or layout changes occur." — is the documented support for §5 row 13
> (board flip), which the report currently justifies from first principles alone.
> "Support the VoiceOver rotor when possible." — is the documented support for §4.2.

The model does not change, but "**This model is ours to design and ours to justify**" is stronger than the
library supports: three of its choices have HIG backing the report did not claim, and one has HIG against it.

**Correction.** Add HIG › VoiceOver to §9's found list, cite it at §2.1, §4.2 and §5 row 13, and narrow the
not-found claim to "no Apple guidance on grid element granularity, announcing a board position, or piece
selection" — which remains true and is the claim that matters.

## 15. `isSummaryElement` is neither used nor rejected — **minor**

> §4.1: "One element, first in the container, label 局面 / 'Position', **no traits**, not actionable."

**[cited]** UIKit › `UIAccessibilityTraits.summaryElement`: "The accessibility element provides summary
information when the app starts. … Use this trait to characterize an accessibility element that provides a
summary of current conditions, settings, or state, such as the current temperature in the Weather app."
SwiftUI exposes it as `AccessibilityTraits.isSummaryElement`. That is an exact description of the element §4.1
introduces. §2.4 presents its trait table as complete and §4.5 makes a point of recording what was considered
and declined; this one is neither adopted nor declined.

**Correction.** Adopt it, or add a line to §4.5 saying why not (the plausible reason: the trait's documented
purpose is app-launch summary, and this element is consulted throughout play).

## 16. §4.0's table mixes two experiments without marking which row came from which — **minor**

Rows 1–4 come from the 42 048-position pass; **"Pieces per rank" comes from the 12 122-position pass**, as do
the 8.2 %, 92.37 %, 1.008 and 11.7 % figures below it. The preamble names both scripts, but the table does not
label its rows, and a reviewer lifting the table into the contract will attribute the rank figure to the larger
sample. Both reproduce exactly, so nothing is wrong — only unlabelled.

Related, in conclusion 3:

> "In 92.37 % of positions '**Chariot**' is ambiguous for the side to move."

What was measured (`vo-measure2.py`) is that *at least one piece type* is duplicated among the movable pieces —
not that chariot in particular is. The design conclusion ("any label, action name, or rotor entry that omits the
coordinate is wrong almost always") is fully supported; the sentence naming chariot is not what the number says.

**Correction.** Add a column or footnote naming the source pass per row, and rewrite the sentence as "in
92.37 % of positions at least one piece type is ambiguous for the side to move."

## 17. Row 4's high-priority announcement races the accepted result card — **minor**

> §5 row 4: "Natural terminal result | result + reason | **high** | The **only** high-priority announcement in
> the app. … 'Cannot be interrupted once started' is correct here and nowhere else."

`:339` accepts that "a non-dismissible result card appears near" the board at that same instant. VoiceOver will
independently announce a newly presented card of that kind (screen- or layout-change handling), so the event has
two spoken carriers — the thing §5's own governing split forbids — and the one that fires is uninterruptible,
which means the user cannot skip it to reach the card. The choice of `high` may still be right, but the
interaction with the card is undesigned and the contract will be written from this table.

**Correction.** State how the announcement and the result card's own presentation are sequenced, and consider
whether the *card* rather than the announcement should be the carrier, with `high` reserved for the case where
focus does not move.

---

## Assessment

The evidence base is sound: I re-ran both measurement scripts and got byte-identical numbers, and every one of
the sixteen Apple quotations checked is verbatim and says what the report says it says. The honest reporting of
absences is real and unusual, and the two live defects it raises — no absolute coordinate in traditional
notation, and the 车/将 polyphones with the macOS IPA gap — are genuine and were not open anywhere.

The failures are of a consistent kind: **the report states its rules more strongly than its own tables obey
them** (findings 1, 4, 6), and **applies its own best argument to one axis and not the other** (finding 3). Two
buildability problems (finding 2) and the incomplete polyphone table (finding 7) are the items most likely to
cost real work if they reach the contract unaltered.

Findings 1, 2, 3 and 6 should be resolved before any of this text is proposed for `interaction-design.md:532`.
Findings 4, 5, 7, 8, 9 and 10 should be corrected in the draft. The rest are corrections a careful editor can
apply in place.
