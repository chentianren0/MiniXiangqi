# Part 7 · p7-history — the History list, and the import / export / duplicate / conflict / error flows

Workspace research note. **Not a contract, not a diff.** Everything below is a proposal for the main
thread to author into `MiniXiangqi/docs/interaction-design.md`. Every Chinese string marked **NEW** is
new copy needing approval and becomes part-6 input the moment it is accepted.

Scope: `interaction-design.md:389` and `:524` — "The exact list layout, date and move-count formatting,
file-picker presentation, import feedback, conflict feedback, and recoverable error copy remain to be
designed." Plus the two copy gaps that sit inside the same surface and are named nowhere else: the
deletion-persistence-failure error (`:382` accepts that an error is presented and gives no copy) and the
History list's empty state (`:537`, the stale blanket bullet).

## 0. Method, and how to read the three kinds of claim

Throughout I separate:

- **Measured** — I compiled and ran it on this machine, on the pinned Xcode 27 beta
  (`/Applications/Xcode-beta.app`), and the numbers are reproducible from the scripts named below.
- **Cited** — quoted from Apple's published documentation with the page and section.
- **Reasoned** — my inference or judgement. Disagreeable, and I say so where it is close.

Artefacts I wrote and ran (workspace only, no repository touched):

| file | what it does |
|---|---|
| `discussion-drafts/p7-date-probe.swift` | Foundation date/time formatting in `zh-Hans-CN`, `en-US`, `en-GB`; string widths at 15 pt; export filename candidates. Run with `xcrun swift`. |
| `discussion-drafts/p7-list-probe.swift` | iOS 27.0 simulator app, sections (a)–(d): `UICollectionLayoutListConfiguration` cell geometry at a 375 pt container; three candidate row layouts across five Dynamic Type sizes in both languages; secondary-line wrap counts; the 44 pt floor check. |
| `discussion-drafts/p7-row-probe.swift` | iOS 27.0 simulator app, sections (i)–(iv): joined versus split secondary line at every text size; SF Symbol existence; line-1 string widths at body and AX5. |

Both simulator probes were built with `xcrun -sdk iphonesimulator swiftc -target arm64-apple-ios26.0-simulator`
and run through `simctl`; each writes its output into its own container's `Documents`.

The simulator run used **iPhone 17e, iOS 27.0**, with widths *forced* to 375 / 343 / 311 pt rather than
taken from the device, because no 375 pt-wide runtime is currently installed. `layout-budget.md:147`
establishes 375 pt as the narrowest supported width (iPhone SE 2nd/3rd gen, 11 Pro, 12 mini, 13 mini), so
forcing the width reproduces the binding case exactly; only the device chrome differs, and no measurement
below depends on it.

I did **not** measure macOS list geometry or Windows anything. Where I say something about those, it is
reasoned or cited, and I mark it.

## 1. What is already accepted, and is therefore not up for redesign here

Restating so the proposal is visibly bounded by it.

**Ordering and content** — pinned records before unpinned; newest **History-added time** first within each
group, with a deterministic tie-break (`interaction-design.md:368`, `game-data.md:120`, and
`core-interface.md:184` makes the order a *core* guarantee: "frontends never re-sort"). Each row shows
date, mode, result or end reason, and move count; human-versus-AI rows also show the human side; imported
rows carry a visible imported marker (`:369`, `game-data.md:121`).

**Interaction** — selecting a row opens read-only replay (`:370`). Trailing partial swipe reveals blue
**共享** then red **删除**, Delete nearest the trailing edge; a complete trailing swipe invokes Delete
(`:372–373`). A leading swipe reveals **置顶** / **取消置顶**; a complete leading swipe invokes it
immediately (`:374`). No Move action (`:375`). Pointer context menus, keyboard commands and screen-reader
custom actions expose equivalent Pin/Unpin, Share and Delete **without adding permanent row buttons**;
on Windows the context menu is the primary path (`:386`). Action meaning is carried by icon and text as
well as colour (`:387`).

**Destructive action** — **删除前确认** default-on, with exact accepted copy 删除这盘棋？ /
删除后无法恢复。 / 取消 · 删除 (`:377–380`). No deletion Undo, no Recently Deleted (`:381–382`).

**Transfer semantics** — every one of them, in `game-data.md`: one game per file and one file per import;
a valid import creates immutable History and never touches the active game; duplicate = same `game_id` +
same `archive_version` + same content hash and bytes → the existing record is returned as *success*
(`core-interface.md:187`, `MXQ_IMPORT_EXISTING`); conflict = same `game_id` with differing content or a
differing stored archive version → rejected with no persistent change (`game-data.md:57`); the full
ordered validation pipeline and every rejection class (`:64`); the limits — 1 MiB, 10 000 plies, JSON
depth 4, 32 members per object, 256-byte strings, 2 s budget (`:62`); and the mandate that unsupported
versions get "a **distinct created-by-a-newer-version message that is never presented as corruption**"
(`:64`). The archive is `.mxq`, UTI `com.ppppvz.minixiangqi.game` conforming to `public.json`
(`game-data.md:35`).

**Glass budget** — system alerts, sheets, context menus and History swipe actions are *additional and
automatic*, outside the three custom glass surfaces (`interaction-design.md:38`). So every alert this
document proposes costs nothing against that budget. An *inline* custom surface would be a fourth, which
is the reason nothing below invents one.

Three things this document must **not** do, from the survey: it must not use any string from PR #23
(rejected, 13 blocking findings — nothing in it is accepted); it must not re-litigate the swipe
vocabulary; and it must not name the History destination in English as though that were settled — see §12.

## 2. Measured evidence

### 2.1 List geometry

*Measured*, `p7-list-probe.swift` section (a), `UICollectionLayoutListConfiguration` at a 375 pt container:

| appearance | cell origin x | cell width | default cell height |
|---|---|---|---|
| `plain` | 0.00 | 375.00 | 72.33 |
| `grouped` | 0.00 | 375.00 | 72.33 |
| `insetGrouped` | **16.00** | **343.00** | 72.33 |
| `sidebar` | 16.00 | 343.00 | 62.00 |

With `insetGrouped` and 16 pt of horizontal padding inside the row, **the text width on the narrowest
supported iPhone is 311 pt.** Every width figure below is against that 311.

### 2.2 Does the accepted middle-dot metadata pattern fit?

*Measured*, `p7-list-probe.swift` section (c) — lines needed by the secondary string at 311 pt:

| Dynamic Type | subheadline pt | zh h-vs-AI | zh longest | zh ended-early | en h-vs-AI | en longest | en ended-early |
|---|---|---|---|---|---|---|---|
| L | 15 | **1** | **1** | **1** | 2 | 2 | 2 |
| xxxL | 21 | 2 | 1 | 2 | 2 | 2 | 2 |
| AX1 | 25 | 2 | 2 | 2 | 3 | 2 | 3 |
| AX3 | 36 | 3 | 2 | 3 | 4 | 3 | 4 |
| AX5 | 49 | 3 | 3 | 3 | 5 | 5 | 5 |

**The single most important measured result in this note: at the default text size, on the narrowest
supported iPhone, every Chinese variant of the accepted dot-joined metadata line fits on one line, and
every English variant needs two.** Chinese is the source language, so the design is right in Chinese and
pays a line in English. That is a real, quantified localization cost, not a hypothesis, and it lands on
part 6 (§12).

### 2.3 Does splitting the dot-joined run help at large text?

I expected splitting the run into one line per segment to be *shorter* at accessibility sizes, because
wrapping happens at meaningful boundaries. **It is not. It is strictly taller at every size measured.**
*Measured*, `p7-row-probe.swift` section (i), 343 pt cell:

| case | L | xxxL | AX1 | AX3 | AX5 |
|---|---|---|---|---|---|
| zh worst — joined | 63.33 | 104.00 | 119.67 | 202.00 | 325.00 |
| zh worst — split | 147.33 | 191.67 | 220.67 | 300.00 | 456.00 |
| en worst — joined | 83.33 | 104.00 | 150.67 | 293.00 | 441.00 |
| en worst — split | 147.33 | 191.67 | 220.67 | 348.00 | 514.00 |

The split form costs **+11 to +131 pt** in every one of the twenty cells. So the design keeps one
dot-joined run at every text size and simply lets it wrap. I record the disproven hypothesis because a
reviewer will otherwise propose it.

### 2.4 Row heights, and the 44 pt floor

*Measured*, 343 pt cell, the layout specified in §3:

| | L | xxxL | AX1 | AX3 | AX5 |
|---|---|---|---|---|---|
| Chinese, worst row | **63.33** | 104.00 | 119.67 | 202.00 | 325.00 |
| English, worst row | **83.33** | 104.00 | 150.67 | 293.00 | 441.00 |

63.33 pt clears the accepted 44 pt hit-target floor (`interaction-design.md:480`) at the default size with
19 pt to spare, and grows from there. No minimum-height clamp is needed.

### 2.5 Date and time, in both locales

*Measured*, `p7-date-probe.swift`. Every string below is verbatim Foundation output on the pinned
toolchain, `Asia/Shanghai`, Gregorian.

`Date.FormatStyle(date: .numeric, time: .shortened)`:

| instant | zh-Hans-CN | en-US | en-GB |
|---|---|---|---|
| 2026-07-28 14:32 | `2026/7/28 14:32` | `7/28/2026, 2:32 PM` | `28/07/2026, 14:32` |
| 2025-12-31 23:59 | `2025/12/31 23:59` | `12/31/2025, 11:59 PM` | `31/12/2025, 23:59` |
| 2024-11-09 12:00 | `2024/11/9 12:00` | `11/9/2024, 12:00 PM` | `09/11/2024, 12:00` |

`DateFormatter` with `doesRelativeDateFormatting = true`, `dateStyle = .short`, `timeStyle = .short`:

| instant | zh-Hans-CN | en-US |
|---|---|---|
| today 14:32 | `今天 14:32` | `Today, 2:32 PM` |
| yesterday 21:05 | `昨天 21:05` | `Yesterday, 9:05 PM` |
| 6 days ago | `2026/7/22 18:45` | `7/22/26, 6:45 PM` |

`RelativeDateTimeFormatter` alone, for comparison: `5天前` / `6个月前` / `去年` — **rejected**, because it
cannot distinguish two games and the brief forbids losing that information.

**Clock convention**, *measured*, `DateFormatter.dateFormat(fromTemplate:)`:

| locale | template `jm` | template `Hm` |
|---|---|---|
| zh-Hans-CN | `HH:mm` | `HH:mm` |
| en-US | `h:mm a` | `HH:mm` |
| en-GB | `HH:mm` | `HH:mm` |

So the 12/24-hour decision belongs to the locale and to the user's own system setting, and the app must
never write a pattern. This is a one-line implementation rule with a real failure mode if ignored.

### 2.6 Line-1 widths against the 311 pt budget

*Measured*, `p7-row-probe.swift` section (iii), `.body` at 17 pt:

| string | width | of 311 |
|---|---|---|
| `今天 14:32` | 80.60 | 26 % |
| `2025/12/31 23:59` | 134.23 | 43 % |
| `导入 · 今天 14:32` | 127.62 | 41 % |
| `导入 · 2024/11/9 12:00` | 168.81 | 54 % |
| `Yesterday at 9:05 PM` | 162.98 | 52 % |
| `12/31/2025, 11:59 PM` | 162.26 | 52 % |
| `Imported · Today at 2:32 PM` | 215.14 | 69 % |
| `Imported · 11/9/2024, 12:00 PM` | **237.44** | **76 %** |

Every line-1 form fits on one line at the default size in both languages, with the worst case leaving
73.6 pt of slack. At AX5 (53 pt body) the same strings measure 510 and 710 pt and wrap; that is expected
and the row simply grows.

### 2.7 Symbols

*Measured*, `p7-row-probe.swift` section (ii) — `square.and.arrow.up`, `square.and.arrow.up.fill`,
`square.and.arrow.down`, `square.and.arrow.down.fill`, `trash`, `trash.fill`, `pin`, `pin.fill`,
`pin.slash`, `pin.slash.fill`, `arrow.down.doc`, `tray.and.arrow.down` — **all twelve exist** on
iOS 27.0. The `.fill` variants matter because SwiftUI "automatically applies the `fill` symbol variant"
to swipe-action labels (*cited*: SwiftUI, `View/swipeActions(edge:allowsFullSwipe:content:)`,
Discussion).

## 3. The History list

### 3.1 Container

- **iOS / iPadOS:** a `List` in `.insetGrouped`. *Reasoned*: it is the style whose geometry I measured,
  it gives the row a card edge that reads correctly beside the app's Liquid Glass navigation, and its
  16 pt inset is the same inset the rest of the app's chrome uses.
- **macOS:** the same `List` in the platform's inset style inside the detail column of the accepted
  adaptive navigation container (`:488`). *Reasoned, not measured* — I did not measure macOS list metrics.
- **Windows:** a `ListView` under Fluent conventions; the row's information content and order are
  identical, per `product.md:24`.

### 3.2 Two sections rather than a per-row pin badge

The accepted ordering already speaks of two **groups** ("Within the pinned and unpinned groups…",
`product.md:58`). Render them as two list sections:

- **已置顶** — **NEW** — the pinned group, shown only when at least one record is pinned.
- **其他对局** — **NEW** — the unpinned group, headed only when the pinned section exists. With nothing
  pinned there is one unheaded section and the list looks exactly as it does today.

*Reasoned.* This is worth its cost for three reasons. It removes a per-row pin glyph from a row that is
already carrying six facts. It makes pinned-ness legible **as ordering** rather than as decoration, which
is what it actually is. And it gives pin/unpin a visible confirmation for free: a full leading swipe moves
the row between sections, so a *failed* pin is visible as a row that did not move (§9.3).

Section headers use the platform's standard header treatment; no counts. *Reasoned*: a count next to a
header reads as a filter result, and the target MVP has no search or filters (`:385`).

### 3.3 The row

Two text lines, no accessory column, no permanent buttons (which `:386` forbids), a system disclosure
indicator where the platform supplies one.

```
┌───────────────────────────────────────────────────────┐
│  今天 14:32                                         › │   line 1  .body, primary label
│  人机对弈 · 你执红 · 红方获胜 · 将死 · 42 步            │   line 2  .subheadline, secondary label
└───────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────┐
│  导入 · 2024/11/9 12:00                             › │   imported record
│  自由对弈 · 和棋 · 三次重复 · 118 步                    │
└───────────────────────────────────────────────────────┘
```

**Metrics** (the values I measured with; they are a starting specification, not derived constants):
16 pt horizontal and 11 pt vertical padding inside the row, 3 pt between the two lines, line 2 at
`lineLimit(nil)` — **it must never truncate**, because every token in it is contract-required row content
and an ellipsis would drop one.

**Line 1 — when.** The date-time (§4), preceded by **导入 ·** for an imported record.

**Line 2 — what.** A single run joined by ` · `, in this fixed order, omitting the segments that do not
apply:

`模式 · [执子] · 结果 · [结束原因] · 步数`

The order is the accepted enumeration order from `:369` and `game-data.md:121` ("date, mode, result or end
reason, move count, human side"), reconciled with the accepted example metadata lines at `:305`, which
show configuration (`人机对弈 · 你执红`) and state (`红方获胜 · 将死 · 42 步`) as two lines with exactly this
internal order. **Line 2 is those two accepted lines concatenated with the same separator.** *Reasoned*,
and I think it is the strongest single argument in this document: the History row invents no metadata
vocabulary at all, it re-uses the one the contract already accepted for the save-and-continue confirmation.
A reviewer can diff the two.

Segments omitted when inapplicable: `执子` in Free Play (`:270` — Free Play has no controller label);
`结束原因` when the outcome is a resignation or an early end, because the outcome word already carries it
(`未分胜负 · 提前结束` would say the same thing twice — see §5 for where the redundancy actually bites).

**No imported *symbol*.** *Reasoned.* The text prefix **导入 ·** costs a measured 47 pt on a line with
73.6 pt of slack in its worst case (§2.6), needs no legend, localizes, survives Dynamic Type and
Increase Contrast unchanged, reads correctly to VoiceOver without an `accessibilityLabel`, and gives the
Windows frontend nothing to reinvent. A glyph would need all of those built for it. It also solves a
second problem for free — see §4.3.

### 3.4 What the row deliberately does not show

AI level, first-mover choice, `started_at`, the archive version, and the stable identity. All of them
belong to the replay screen's metadata, which is part 4's open item (`:516`) and not mine. I flag the
dependency rather than design it.

## 4. Date and time formatting

### 4.1 The rule

For a record whose displayed instant is *T*, in the user's own locale, calendar and time zone:

| condition | form | measured zh | measured en-US |
|---|---|---|---|
| `Calendar.isDateInToday(T)` | localized *today* word + short time | `今天 14:32` | `Today, 2:32 PM` |
| `Calendar.isDateInYesterday(T)` | localized *yesterday* word + short time | `昨天 21:05` | `Yesterday, 9:05 PM` |
| otherwise | `Date.FormatStyle(date: .numeric, time: .shortened)` | `2026/7/22 18:45` | `7/22/2026, 6:45 PM` |

Rules that fall out of the measurements and must be stated because they are easy to get wrong:

- **Never write a date or time pattern.** The 12/24-hour choice is the locale's and the user's
  (§2.5, measured). `Date.FormatStyle` and `DateFormatter` both honour it; a hand-written `HH:mm` does not.
- **The time is always present**, in every branch. It is what distinguishes two games played on one day,
  which is the brief's explicit requirement.
- **The year is always present** in the non-relative branch, four digits. `.numeric` gives four;
  `DateFormatter.Style.short` gives two (`7/22/26`, measured). *Reasoned*: a library kept across years is
  exactly where a two-digit year is least helpful, and §2.6 shows the four-digit form fits with room.

**Implementation note, measured, and the reason this is three rules and not one call.** Foundation cannot
produce this combination in a single call. Relative day names come only from `DateFormatter`'s
`doesRelativeDateFormatting`, which pairs with `DateFormatter.Style` — and `.short` gives a two-digit year
while `.medium` gives the long form (`2026年7月22日 18:45` at 155.0 pt, `Jul 22, 2026 at 6:45 PM` at
162.9 pt; both measured, both fit, both wider than needed). So the app branches on
`isDateInToday` / `isDateInYesterday`, takes the day word from the system rather than hard-coding 今天 and
昨天, and uses `Date.FormatStyle` otherwise. **今天 and 昨天 are therefore not new copy** — they are
system-supplied strings, and writing our own would diverge from the rest of the OS.

The two single-call fallbacks, with their measured costs, in case a reviewer prefers one:
`.short`/`.short` relative → narrower but a two-digit year in English; `.medium`/`.short` relative →
four-digit year and month names, ~40 pt wider in Chinese and still inside 311.

### 4.2 Why not "5 days ago"

*Measured* (`p7-date-probe.swift` section D): `RelativeDateTimeFormatter` renders the seven sample
instants as `1小时前`, `18小时前`, `5天前`, `6个月前`, `6个月前`, `去年`. Two different games map to the
same string in that sample. It fails the brief's requirement outright and is rejected.

Today and yesterday are safe because they carry the exact time alongside; `今天 14:32` and `今天 09:05` are
distinct, and `今天` is unambiguous for the ~48 hours it is used.

### 4.3 *Which* instant — and why 导入 · resolves it

This is the one question in §7.1 the survey correctly assigns to the owner, so §13.1 states the options.
My recommendation, and the reasoning:

The contract keeps two different timestamps. The archive carries the game's own `started_at` and
`ended_at` (`game-data.md:38`). The store carries a **local History-added time**, and *that* is the sort
key (`game-data.md:120`, `:145`). For a locally played game they are the same transaction and differ by
milliseconds. For an imported game they can differ by years.

A list that sorts by one value and displays another reads as broken. So either the row shows the sort key,
or the ordering must be explained. **Recommendation: the row shows the game's own `ended_at`, and imported
rows are prefixed 导入 ·, which is what explains the ordering.**

- `ended_at` is the more meaningful instant — it is when the game happened, which is what a person is
  looking for — and it is the instant that distinguishes two imported games.
- For every locally played record the two instants are identical, so this changes nothing for the
  overwhelming majority of rows.
- For an imported record the row reads `导入 · 2024/11/9 12:00` — "imported; played 2024-11-09" — which
  both identifies the game *and* says why an old game is sitting at the top of the list.
- The alternative, showing the History-added time, produces `导入 · 今天 14:32` for a 2024 game: correct
  about ordering, useless for identification, and it pushes the game's real date entirely into replay.

`ended_at` rather than `started_at` because every History record is completed (`game-data.md:38`: `outcome`,
`end_reason` and `ended_at` are "present exactly when the game is completed, which every exported file is"),
and because `ended_at` is the instant that made it a record — the same role the History-added time plays.
A game spanning midnight is the only case where the two differ.

**Residual limitation, stated plainly.** Two records identical in every accepted row field — same
`ended_at` minute, same mode, same side, same outcome, same reason, same ply count — are indistinguishable
in the list. That is a property of the accepted row-content set, not of this formatting. It is reachable
in practice only by importing two different 3-ply ended-early Free Play games recorded in the same minute.
The row cannot fix it without adding a field the contract does not list; opening the record does.

## 5. Move count, and the outcome / reason vocabulary

### 5.1 Move count

Format: **the integer, a space, and the unit** — `42 步` — which is the accepted pattern at `:305`.
Use the locale's own grouping (`IntegerFormatStyle`), so the ceiling case renders `10,000 步` /
`10,000 moves` rather than `10000`.

**`步` counts plies, not full moves.** `game-data.md:143` stores "move count in plies" and `:40` defines it
as the length of `moves`, whose index 0 is Red's first move. In Chinese Xiangqi usage 步 *is* one side's
move, so the Chinese is exactly right and needs no gloss. **English is the problem**, because in chess
notation "move" means a pair. English `42 moves` is only correct if the reader takes the ordinary-English
sense. The precise alternatives — "42 plies", "42 half-moves" — are jargon a learner should not meet in a
list row. *Reasoned recommendation*: use `42 moves` in English, and make the equivalence an explicit entry
in the localization glossary and one sentence in Help. This is a part-6 item that originates here.

Edge cases the row must render: **`0 步`** is reachable — an ordinary game archived through 保存并继续
before either side moved is recorded ended-early with an empty move list (`game-data.md:80`). English
pluralises zero as `0 moves` and one as `1 move`; use `AttributedString`-style pluralization rather than a
concatenation.

### 5.2 The outcome and reason tokens

The row needs one word per committed `outcome` and one per `end_reason` (`game-data.md:49–50`). Most
already exist.

| serialized | Chinese | status |
|---|---|---|
| `outcome = red-wins` | **红方获胜** | accepted, `:340` |
| `outcome = black-wins` | **黑方获胜** | accepted, `:340` |
| `outcome = draw` | **和棋** | accepted, `:340` |
| `outcome = none` | **未分胜负** | **NEW** |
| `end_reason = checkmate` | **将死** | accepted, `:305` metadata example |
| `end_reason = stalemate` | **困毙** | **NEW** |
| `end_reason = threefold-repetition` | **三次重复** | **NEW** (the phrase 局面已三次重复 is accepted at `:350`; the bare token is not) |
| `end_reason = perpetual-check` | **长将** | **NEW** |
| `end_reason = perpetual-chase` | **长捉** | **NEW** |
| `end_reason = mutual-perpetual-check` | **双方长将** | **NEW** |
| `end_reason = mutual-perpetual-chase` | **双方长捉** | **NEW** |
| `end_reason = resignation` | **认输** | **NEW** |
| `end_reason = ended-early` | **提前结束** | **NEW** |
| `mode = human-vs-ai` | **人机对弈** | accepted, `:305` |
| `mode = free-play` | **自由对弈** | accepted, `:305` |
| human side Red / Black | **你执红** / **你执黑** | 你执红 accepted at `:305`; 你执黑 is its obvious pair and I still mark it **NEW** |

困毙, 长将 and 长捉 are the standard Chinese Xiangqi terms, and 困毙 is correct for this ruleset
specifically because `xiangqi-rules.md:103` makes stalemate **a loss for the side to move**, not a draw —
so the English gloss must not be "stalemate → draw".

**Redundancy rule.** Two pairs say the same thing twice and the reason is dropped:
`未分胜负 · 提前结束` → **未分胜负**; and a resignation is `红方获胜 · 认输` / `黑方获胜 · 认输`, where the
reason *is* informative and stays. *Reasoned.*

**Collision to flag.** 认输 also appears in the rejected PR #23 (`确认认输？`). Nothing there is accepted.
The string proposed here is a History *reason* token, not a confirmation title; whoever writes the
resignation confirmation should reuse this token rather than the rejected diff's.

## 6. Actions: swipe, context menu, keyboard, VoiceOver

### 6.1 The swipe implementation detail that is easy to get backwards

*Cited*, SwiftUI `View/swipeActions(edge:allowsFullSwipe:content:)`, Discussion: "Actions appear in the
order you list them, **starting from the swipe's originating edge**." And UIKit
`UISwipeActionsConfiguration/init(actions:)`: "The first item in the array represents the outermost action.
For example, when the user swipes from right-to-left, the first action is rightmost. The first action is
also the default action."

The accepted contract says Delete is nearest the trailing edge and a full trailing swipe invokes Delete
(`:372–373`). **Therefore Delete must be listed first and Share second**, which is the reverse of the
reading order in the contract sentence. `testing.md:81` gates "action order", so this is exactly the kind
of thing a test will catch late and a note will prevent. The accepted full-swipe behaviour then comes free
from the framework default (`allowsFullSwipe` defaults to `true`, and the first action is the default
action) — no override is needed on either edge.

```
.swipeActions(edge: .trailing) {          // Delete first → rightmost → full-swipe default
    Button("删除", systemImage: "trash", role: .destructive) { … }
    Button("共享", systemImage: "square.and.arrow.up") { … }.tint(.blue)
}
.swipeActions(edge: .leading) {
    Button(pinned ? "取消置顶" : "置顶",
           systemImage: pinned ? "pin.slash" : "pin") { … }.tint(.orange)
}
```

- Red for Delete comes from `role: .destructive` rather than a tint — *cited*, same Discussion: "the delete
  action appears in `red` because it has the `destructive` role" — which also satisfies the accepted rule
  that "Destructive actions use the system's destructive role rather than a red tint, so red keeps one
  meaning" (`:44`).
- Blue for Share is accepted (`:372`) and needs the explicit `.tint(.blue)` shown.
- **Pin's colour is not specified anywhere, and Apple publishes no standard colour for a pin swipe
  action.** I checked. `.tint(.orange)` is the closest published precedent — the SwiftUI `swipeActions`
  documentation's own example tints its secondary trailing action orange — and orange is distinct from
  both the accepted blue and the system destructive red. This is a **reasoned** choice with a weak
  citation, and I would not defend it hard.
- All four symbols exist (§2.7, measured), and SwiftUI substitutes the `.fill` variants automatically.

**Row-level swipe hygiene is free.** *Cited*, SwiftUI `View/swipeActionsContainer()`: `List` already
guarantees that only one row's actions are revealed at a time, that scrolling dismisses them, and that
tapping outside dismisses them — "Applying this modifier to a `List` is a no-op". Nothing to build.

### 6.2 The non-swipe equivalents

`:386` accepts that they exist and names none. Proposal:

- **Context menu** (right-click, long-press, Menu key), in the same order the swipes read:
  置顶 / 取消置顶, 共享, 删除 — Delete last and marked destructive.
- **Keyboard**, macOS, with a row selected: `Return` opens replay; `Delete` and `⌘⌫` both delete;
  Pin/Unpin and Share have **no invented shortcut** and live in the context menu and the menu bar.
  *Reasoned*: the contract names exactly one keyboard command in the whole app (Flip Board, `:218`), and
  inventing two more here would front-run the keyboard-coverage gap that part 8 owns (`8.2`).
- **VoiceOver custom actions** (`accessibilityActions`), same three, same order — which is what `:386`
  already requires. See §11.

## 7. Empty and loading states

Both are inside `interaction-design.md:537`'s stale blanket bullet, and both are genuinely open.

**Empty.** Use `ContentUnavailableView` — *cited*, SwiftUI `ContentUnavailableView`: "It is recommended to
use `ContentUnavailableView` in situations where a view's content cannot be displayed. That could be
caused by a network error, **a list without items**, a search that returns no results etc." UIKit's
equivalent for Windows-parity thinking is `UIContentUnavailableView`.

- Symbol: `tray.and.arrow.down` (existence measured, §2.7).
- Title: **还没有历史对局** — **NEW**
- Description: **对局结束后会保存到这里。你也可以导入一个对局文件。** — **NEW**
- Action: a button **导入对局…** — **NEW** — which opens the same picker as the toolbar item (§8.1).

*Reasoned*: an empty History is the state a brand-new internal tester sees first, and it is the one moment
where naming import pays for itself, because there is nothing else on screen to do.

**Loading.** Two distinct waits:

- *The store opening at launch, and the first page of History.* `mxq_store_history_page` is a synchronous
  local SQLite read off the UI thread (`core-interface.md`, threading table). Show nothing. *Reasoned*: a
  local paged read of a library that cannot exceed a few thousand rows will not reach the threshold at
  which an indicator helps, and HIG's own advice is that "the best content-loading experience finishes
  before people become aware of it" (*cited*, HIG **Loading**).
- *Import validation.* Budgeted at ≤ 2 s on the slowest supported device (`game-data.md:62`). See §8.3.

## 8. Import

### 8.1 Entry point

The contract accepts that import exists (`:383`) and never says where it lives. Proposal:

- **iOS / iPadOS / macOS:** a toolbar item on the History destination — label **导入…** — **NEW** —
  symbol `square.and.arrow.down`.
- **macOS additionally:** a menu-bar command in `CommandGroupPlacement.importExport`, which is *cited*
  as "Placement for commands that relate to importing and exporting data using formats that the app
  doesn't natively support". No keyboard shortcut. *Reasoned*: `⌘O` means Open a document, and this app
  has no documents in the `DocumentGroup` sense.
- **Windows:** a command-bar button in the same position, per `product.md:24`.
- **Not** a drag-and-drop target on iOS/iPadOS/macOS, and **not** a Files/Finder document handler — both
  are additional entry paths that the contract does not authorize. The handler question is worth asking
  and is §13.3.

### 8.2 The picker

*Cited*, SwiftUI `View/fileImporter(isPresented:allowedContentTypes:allowsMultipleSelection:onCompletion:onCancellation:)`.

```swift
.fileImporter(isPresented: $importing,
              allowedContentTypes: [.miniXiangqiGame],   // com.ppppvz.minixiangqi.game
              allowsMultipleSelection: false,
              onCompletion: …, onCancellation: …)
.fileDialogCustomizationID("com.ppppvz.minixiangqi.import")   // macOS
.fileDialogConfirmationLabel("导入")                            // macOS
```

- `allowsMultipleSelection: false` **structurally enforces** the accepted one-file-at-a-time rule
  (`:383`, `game-data.md:118`) at the picker, rather than letting the user select five files and then
  rejecting four. *Reasoned*, and it is the cheapest place to honour a contract rule.
- `allowedContentTypes` filters to the declared UTI, so `.mxq` files are selectable and nothing else is.
  The in-band `archive_format` check remains authoritative (`game-data.md:36`: "the extension and UTI are
  hints only"), which is why §8.5 still has a "not our file" rejection class.
- **Security scope.** *Cited*, same page: "This dialog provides security-scoped URLs. Call the
  `startAccessingSecurityScopedResource` method to access or bookmark the URLs, and the
  `stopAccessingSecurityScopedResource` method to release the access." The app reads the bytes inside that
  scope, hands them to `mxq_store_import`, and releases. **It retains no bookmark and keeps no reference
  to the source file** — which is the right posture for an input the repository's own `CLAUDE.md` calls
  untrusted.
- **macOS only:** `fileDialogCustomizationID` "stores the current directory, view style … and expanded
  window size" and restores them per invocation (*cited*), which is worth the one line because an internal
  tester importing several files in a session goes back to the same folder. `fileDialogConfirmationLabel`
  makes the confirm button say 导入 rather than Open. I deliberately do **not** set `fileDialogMessage`:
  the panel already has a title, and an added message is noise.
- **Offline.** `product.md:15` requires the app to be fully offline and `game-data.md:136` says "Importing
  must not contact a server." The system picker may show iCloud Drive locations; the *system* materializes
  the file the user chose, and the app makes no network call. Worth writing into the contract explicitly
  so a reviewer does not read the picker as a violation.

### 8.3 Progress

Import is one bounded operation with a 2 s ceiling. *Reasoned*, and grounded in a number the contract
already accepted rather than a new one:

- **Below 500 ms, show nothing.** This is exactly the accepted AI-activity threshold and its stated
  reason: "If the search has not returned within 500 ms of the player's move, the turn status shows AI
  activity; below that threshold nothing appears, because an indicator that flashes for a fifth of a
  second is noise" (`:424`). Reusing the number rather than inventing a second one is the point.
- **At or beyond 500 ms**, the History toolbar item becomes an indeterminate `ProgressView`. The picker
  is already dismissed and the list stays scrollable and usable. *Cited*, HIG **Feedback → Best
  practices**: "Consider integrating status feedback into your interface. When status feedback is
  available near the items it describes, people get important information without having to take action or
  leave their current context."
- **No Cancel and no blocking overlay.** *Reasoned*: the operation is bounded at 2 s, nothing is written
  until the final transaction (`game-data.md:64`), so cancelling buys nothing a two-second wait does not.
  HIG says to offer Cancel "when it's feasible"; here it is feasible and pointless.

### 8.4 Success

**No alert.** *Cited*, HIG **Feedback → Best practices**: "When it makes sense, confirm that a significant
action or task has completed… It's generally best to reserve this type of confirmation for activities that
are sufficiently important — because people typically expect their action or task to succeed, they only
need to know when it doesn't." And HIG **Alerts → Best practices**: "Avoid using an alert merely to
provide information."

What happens instead:

1. The new record appears at the head of **其他对局** (its History-added time is now; it is not pinned).
2. The list scrolls it into view and applies a brief row highlight, ~600 ms, decaying to the normal row
   background.
3. Under Reduce Motion the scroll is an immediate jump and the highlight is unchanged. This is the
   accepted Reduce Motion rule applied without exception: "Anything that animates position, scale, or
   rotation becomes a crossfade of at most 120 ms; anything that animates opacity, colour, stroke weight,
   or shadow is unchanged, because none of those is motion" (`:428`). The scroll is position; the
   highlight is colour.
4. VoiceOver: post `AccessibilityNotification.LayoutChanged` **with the new row as its argument**, so
   focus lands on the row and VoiceOver reads the row itself. *Cited*, Accessibility
   `AccessibilityNotification.LayoutChanged`: "Optionally, include a parameter that contains the
   accessibility element for VoiceOver to move to after processing the notification." *Reasoned*: this is
   better than an announcement, because the row **is** the information — an announcement would say "已导入"
   and then the user would still have to go find it.

Whether this silence is enough is a product judgement, not a design one: §13.5.

### 8.5 The failure and near-failure outcomes

The accepted pipeline defines many rejection classes (`game-data.md:64`). How many *messages* the product
wants is the owner's call (§13.2). **My recommendation is four**, cut so that each one implies a different
next action, plus the two non-rejection outcomes. All are system alerts, which cost nothing against the
glass budget (`:38`).

Every message obeys the brief's three-part rule — **what happened, what survived, what you can do** — and
every one of them says 历史没有改变 explicitly, because "no persistent change" is the accepted guarantee
(`game-data.md:57`, `:64`) and a user has no other way to know it held.

Copy is written to HIG **Alerts → Content**: "Write a title that clearly and succinctly describes the
situation… describe what happened, the context in which it happened, and why. Avoid writing a title that
doesn't convey useful information — like 'Error'."

---

**(a) Duplicate** — `MXQ_IMPORT_EXISTING`. A *success*, not an error (`core-interface.md:187`). An alert is
right here, because the user's expectation — a new row — is deliberately not met and the contract requires
that the existing record be offered (`:384`).

| | |
|---|---|
| Title | **这盘棋已经在历史里** — **NEW** |
| Message | **文件里的对局和历史中的一盘完全相同，所以没有重复添加。** — **NEW** |
| Actions | **查看** (default) · **好** — both **NEW** |

**查看** dismisses and opens the existing record's replay, which is the accepted "offers a way to view the
existing record". *Honest note on 好*: HIG says to avoid OK "unless the alert is purely informational" and
to use "Cancel" only for a button that cancels the alert's action. Nothing here is being cancelled, and the
alert is informational plus one optional navigation, so 好 is the least bad of the available titles;
完成 and 关闭 both imply a task ended.

---

**(b) Identity conflict** — same `game_id`, different content, or a differing stored archive version
(`game-data.md:57`).

| | |
|---|---|
| Title | **这个文件和历史中的一盘棋冲突** — **NEW** |
| Message | **它和历史中的一盘棋是同一局，但内容不同。历史没有改变。如果要用这个文件，请先删除历史中的那一盘。** — **NEW** |
| Actions | **查看历史中的那一盘** · **好** — both **NEW** |

The message is the longest in the set because the situation genuinely needs three sentences: what it is,
what survived, and the only route forward. *Reasoned*: naming the route matters, because deleting the
existing record is permanent and the user should reach that decision deliberately rather than by
experiment.

---

**(c) Not a Mini Xiangqi game file** — the in-band `archive_format` member is absent or wrong, or the
transport failed before anything could be read. The user picked the wrong file.

| | |
|---|---|
| Title | **这不是 Mini Xiangqi 对局文件** — **NEW** |
| Message | **请选择一个 .mxq 对局文件。历史没有改变。** — **NEW** |
| Actions | **重新选择** (default) · **好** — 重新选择 **NEW** |

**重新选择** re-opens the picker. *Reasoned*: this is the one rejection where the remedy is one tap away,
so offering it is worth an extra button.

---

**(d) The file cannot be read** — malformed UTF-8 or JSON, a structural limit exceeded, an unknown member
inside a known version, a closed-vocabulary or cross-field violation, an illegal move line, a terminal
claim that disagrees with replay, an oversized file, or a validation that exceeded the 2 s budget.

| | |
|---|---|
| Title | **无法读取这个对局文件** — **NEW** |
| Message | **文件的内容无效或过大，无法导入。历史没有改变。请确认文件完整，或者向对方要一份新的。** — **NEW** |
| Actions | **好** |

*Reasoned* on the merge: from the user's side these are one situation — this copy of this file is not
usable and nothing they can do in the app changes that. Splitting them into seven messages would make the
app more talkative without making it more useful. The precise cause rides in `MxqError`'s "short English
diagnostics" (`core-interface.md`) for a developer, never in the UI.

Note the 2 s budget being folded in here: it is a property of the *file* (too complex to check inside the
accepted bound), and the honest user-facing summary of it is "invalid or too large". If the owner prefers
a distinct timeout message, that is a fifth class.

---

**(e) Created by a newer version** — the mandated distinct message (`game-data.md:64`,
`testing.md:113`). **This alert must never use 损坏 or any word meaning corrupt.**

| | |
|---|---|
| Title | **这个文件由更新版本的 Mini Xiangqi 创建** — **NEW** |
| Message | **当前版本无法读取它。请更新 Mini Xiangqi 后再试。历史没有改变。** — **NEW** |
| Actions | **好** |

This is the exact wording of the accepted compatibility promise turned into user copy: "a file exported by
a newer version may not be readable by an older one, which then says the file was created by a newer
version and imports nothing" (`game-data.md:165`).

---

**(f) The file was fine but saving failed** — a store-domain failure at the single write transaction
(I/O, full, busy).

| | |
|---|---|
| Title | **无法保存导入的对局** — **NEW** |
| Message | **对局文件没有问题，但保存到历史时出错。历史没有改变。请重试。** — **NEW** |
| Actions | **取消** · **重试** |

*Reasoned*: deliberately shaped as a sibling of the accepted archive-failure alert — **无法保存对局** /
**当前对局仍然保留。请重试。** / 取消 · 重试 (`:319–321`). Same title stem, same closing sentence rhythm,
same action pair. Two "could not save" failures in one app should read as one family. **取消** and
**重试** are already accepted strings and are reused verbatim.

## 9. Export, deletion and pin

### 9.1 共享

Accepted: "**共享** exports the selected History record as one game file" (`:376`).

- **iOS / iPadOS / macOS:** `ShareLink` over a `Transferable` game record.
- **The `Transferable` conformance must include a `FileRepresentation`.** *Cited*, SwiftUI `ShareLink`,
  Overview: "some applications offer their sharing service for files, but not for a wide range of
  different data types, for example, Mail.app, Notes.app, Messages.app or AirDrop. If you don't see a
  particular sharing service in the presented `ShareLink`, try adding a `FileRepresentation` to the type's
  `Transferable` conformance." **AirDrop is precisely how an offline internal team moves a file between two
  devices**, so a `DataRepresentation`-only conformance would silently remove the app's main transfer
  route. Worth a sentence in the contract.
- **Default filename**, *measured* (`p7-date-probe.swift` section H):

  `minixiangqi-2026-07-28-1432.mxq`

  built from the game's **`ended_at`**, formatted with `en_US_POSIX` and `yyyy-MM-dd-HHmm`.

  Three deliberate choices. **`ended_at`, not the export time**, because `origin.exported_at` "is
  regenerated on every export, never hashed, never compared, never trusted" (`game-data.md:41`) — using it
  would give the same game a different filename every time it is shared. **`en_US_POSIX`, not the user's
  locale**, so the filename is identical on every device and sorts chronologically in a folder; this is a
  deliberate, narrow exception to the localization rule and should be written down as one, because a
  reviewer will otherwise read it as a bug. **No localized words in the filename** for the same reason.
  A collision — the same game exported twice into one folder — is handled by the system picker's own
  " 2" suffix; if the owner wants collision-proof names, appending the first 8 hex characters of `game_id`
  is the obvious extension and is *not* recommended by default because it makes the name unreadable.

### 9.2 Deletion failure

`:382` accepts "If persistence fails, the record remains and the app presents an error" and gives no copy.

| | |
|---|---|
| Title | **无法删除这盘棋** — **NEW** |
| Message | **这盘棋仍然保留在历史里。请重试。** — **NEW** |
| Actions | **取消** · **重试** |

Same family as `:319–321` and as §8.5(f). Three "could not do it, nothing changed, try again" alerts, one
shape.

### 9.3 Pin / unpin failure

Named nowhere. Pin is a store write and can fail.

| | |
|---|---|
| Title | **无法更改置顶状态** — **NEW** |
| Message | **这盘棋的置顶状态没有改变。请重试。** — **NEW** |
| Actions | **好** |

*Reasoned, and the weakest recommendation in this document.* This is the only alert here for a
**reversible, low-stakes** action, and the accepted philosophy for that class is the opposite — a failed
move or Undo gets "brief non-blocking feedback" and no dialog (`:228`). I still recommend the alert
because History has no turn-status element to anchor a capsule to, an inline surface would be a fourth
custom glass surface (`:38`), and on macOS there is no haptic, so the row silently failing to move between
sections is the only other signal. A reviewer who prefers the non-blocking treatment has a good argument
and would need to say where the feedback lives.

## 10. What this proposal costs in Windows terms

*Reasoned throughout; I measured nothing on Windows and the frontend does not exist.*

Nothing here needs a Windows-only concept. The row is two text lines with no custom accessory. The section
headers are list group headers. The alerts are `ContentDialog`s with the same titles, messages and button
order. The picker is `FileOpenPicker` filtered to `.mxq` with single selection. Share is the Windows share
contract or a save dialog. The one genuine difference is already accepted: "on Windows, the context menu is
the primary path to these actions" (`:386`), so the swipe vocabulary maps to context-menu items in the same
order. The date and move-count rules are `CultureInfo`-driven by the same argument as §4.

## 11. Accessibility

This is part 8's territory for the *board*; the History list's own behaviour is mine, and I keep it inside
what `:386` already accepts.

- **Row element.** One accessibility element per row, not two. Label = line 1 then line 2, read as one
  sentence with the ` · ` separators spoken as pauses rather than as the character. *Reasoned*: a
  screen-reader user should not have to swipe twice per row down a list.
- **Custom actions** (`accessibilityActions`): 置顶/取消置顶, 共享, 删除 — the accepted set, in the accepted
  order (`:386`).
- **Section headers** carry the header trait so the rotor can jump between 已置顶 and 其他对局.
- **After import**, `AccessibilityNotification.LayoutChanged` with the new row as the argument (§8.4).
- **After deletion**, no announcement: the row is gone, the list re-lays out, and VoiceOver's own list
  handling covers it. *Reasoned.*
- **No time-boxed content.** The success highlight decays but nothing dismisses itself, and every alert
  needs an explicit action. *Cited*, HIG **Accessibility → Cognitive**: "Minimize use of time-boxed
  interface elements. Views and controls that auto-dismiss on a timer can be problematic for people who
  need longer to process information, and for people who use assistive technologies that require more time
  to traverse the interface. Prefer dismissing views with an explicit action."
- **Contrast and colour.** Nothing in the row carries meaning by colour: 导入 is a word, pin state is a
  section, the swipe actions carry icon and text as well as colour (accepted, `:387`). So the row is
  identical under Differentiate Without Color, and Reduce Transparency and Increase Contrast are handled
  entirely by the system, because the list is a system surface.

## 12. Collisions with the other parts

- **Everything marked NEW in this document is part-6 input.** By my count this note proposes **37** new
  Chinese strings (§14) — against the 58 the survey counted as already accepted in the whole document, so
  this one surface enlarges the localization set by roughly two thirds. `interaction-design.md:533` requires English counterparts for every accepted
  Chinese string, so accepting this design enlarges 6.1 by that much. The English glosses I use in tables
  are working translations for discussion, **not proposals for approval**.
- **§2.2 is a 6.1 finding, measured.** The accepted middle-dot metadata pattern fits Chinese on one line
  and needs two in English at the default size on the narrowest iPhone. The survey lists "whether the
  middle-dot metadata patterns survive in English" as an owner-level framing question inside 6.1; here is
  the number it needs. §13.4.
- **§5.1 is a 6.3 finding.** 步 = ply is unambiguous in Chinese and ambiguous in English. The glossary
  needs the equivalence.
- **The History destination has no accepted Chinese name** — survey defect 6.2. Every screen title and
  every message above that would want to say "History" says 历史 in my prose; I have **not** listed 历史 as
  a NEW string because naming the three primary destinations is 6.2's job and should be decided once, for
  all three, not incidentally here.
- **Part 4 (PR #23, rejected)** owns the replay screen's metadata panel and the stacked layout. §3.4 hands
  it `started_at`, AI level and first-mover choice and designs none of it.
- **Part 7.4** (engine cannot be re-prepared mid-game) shares the "could not do it, nothing changed"
  alert family established in §8.5(f) and §9.2 and should join it rather than invent a fourth shape.

## 13. Open for the owner

Only the choices that are genuinely the product owner's, with what each costs.

### 13.1 Which instant the History row shows

The list sorts by the local History-added time; the archive carries the game's own `ended_at`. For a
locally played record they are the same; for an imported record they can be years apart.

- **Show `ended_at`, prefixed 导入 · for imported rows** (my recommendation). The date identifies the game.
  An imported 2024 game sits at the top of the list showing 2024, and the 导入 prefix is what explains why.
  Costs: the list's dates are not monotonic wherever an import happened, and the reader has to accept the
  prefix as the explanation.
- **Show the History-added time.** The list reads strictly newest-first. Costs: an imported row says
  `导入 · 今天 14:32` for a game played in 2024 — true about the library, useless for identifying the game —
  and the game's own date is only visible after opening the record.
- **Show both on imported rows** (`… · 对局于 2024/11/9` appended to line 2). Costs: no ambiguity at all,
  but it pushes the Chinese line-2 worst case from one line to two (measured: that line is already at
  roughly 300 pt of the 311 available), so imported rows become taller than local ones in both languages.

### 13.2 How many distinct import-rejection messages

The accepted validation pipeline defines at least seven rejection classes; the accepted contract mandates
that exactly one of them — created-by-a-newer-version — is distinguishable and never presented as
corruption.

- **Two** (a generic failure plus the mandated newer-version message). Cheapest to write, translate and
  test. Costs: a user who picked the wrong file gets the same message as a user with a damaged file, and
  cannot tell which mistake they made.
- **Four** (§8.5 c–f; my recommendation). Each message implies a different next action: pick a different
  file / get a new copy / update the app / retry. Costs: four sets of copy in two languages, four test
  cases.
- **One per class, seven or more.** Maximally honest. Costs: several messages a user cannot act on
  differently, and a translation and review burden out of proportion to an internal MVP.

### 13.3 Should the app open `.mxq` files from Finder and the Files app

`game-data.md:35` already declares the UTI, so the system will associate the type with the app whether or
not it is claimed as a document handler.

- **No handler** (my recommendation for the MVP). Import happens from one place, on one screen, with the
  list already in view to receive the result. Costs: a tester who receives a `.mxq` by AirDrop must open
  the app and use 导入… rather than tapping the file.
- **Declare a Viewer handler.** Double-tapping a `.mxq` launches the app and imports it. Costs: a second
  entry path with its own state — an import that runs at launch, before History is on screen, needing its
  own success and failure presentation and its own answer to "what if a game is being created right now".
  That is a real amount of new design, and none of it is in the accepted contract.

### 13.4 Does English keep the dot-joined metadata run

Measured (§2.2): every Chinese variant fits one line at the default size on the narrowest iPhone; every
English variant needs two.

- **Keep it.** One pattern, one implementation, Chinese optimal. Costs: English rows are 83 pt instead of
  63 pt at the default size — about 24 % fewer rows per screen — and English at AX5 reaches 441 pt per row.
- **Give English a different pattern** (for example dropping 结束原因 from the row and leaving it to
  replay). Costs: the two languages then show different information in the same list, which contradicts
  `product.md:24`'s rule that product behaviour is identical across presentations, and it would need an
  explicit exception.

This is the owner's because it is the first concrete instance of the question 6.1 has to answer for all 58
accepted Chinese strings: does English get the same shape or its own?

### 13.5 Does a successful import say anything at all

My recommendation is silence plus the row appearing, scrolled into view and briefly highlighted, on HIG's
reasoning that confirmations are for activities important enough that people would otherwise doubt them.

- **Silence** (recommendation). Costs: a user who imports a duplicate-looking file and gets no message may
  not immediately notice which row is new, especially if the list is long.
- **A confirmation alert.** Unambiguous. Costs: an alert on the app's most routine successful action, which
  is what HIG **Alerts → Best practices** specifically warns against, and it trains people to dismiss
  alerts without reading them — which then weakens the five alerts in §8.5 that matter.

### 13.6 Can a Mac user save a `.mxq` to a folder

`:376` accepts one export action, 共享. On macOS the sharing popover offers services, not "save to a
folder".

- **Share only** (strict reading of the contract). Costs: on the platform most likely to be used for
  moving files around, a `.mxq` cannot be put on disk at all without going through another app.
- **Add a macOS Export… command** using `fileExporter`, in the same `importExport` menu group as Import.
  Costs: a capability that exists on one platform and not the others, which `interaction-design.md:25`
  allows only with "an explicit product decision" — which is exactly what this question is.
- **Support dragging a row out of the list** as a file. Costs: an interaction with no accepted
  specification and no Windows or iOS equivalent, and `:386`'s rule that platform gaps are filled by
  equivalents rather than new capabilities cuts against it.

## 14. Every new string, in one place

All **NEW**, all needing approval, all feeding part 6. English column is a working gloss for discussion
only.

| # | Chinese | where | working English |
|---|---|---|---|
| 1 | 已置顶 | section header | Pinned |
| 2 | 其他对局 | section header | Other Games |
| 3 | 导入 | row prefix for imported records | Imported |
| 4 | 未分胜负 | outcome `none` | No result |
| 5 | 困毙 | reason `stalemate` | Stalemate |
| 6 | 三次重复 | reason `threefold-repetition` | Threefold repetition |
| 7 | 长将 | reason `perpetual-check` | Perpetual check |
| 8 | 长捉 | reason `perpetual-chase` | Perpetual chase |
| 9 | 双方长将 | reason `mutual-perpetual-check` | Mutual perpetual check |
| 10 | 双方长捉 | reason `mutual-perpetual-chase` | Mutual perpetual chase |
| 11 | 认输 | reason `resignation` | Resignation |
| 12 | 提前结束 | reason `ended-early` | Ended early |
| 13 | 你执黑 | row, human side Black | You played Black |
| 14 | 还没有历史对局 | empty state title | No Games Yet |
| 15 | 对局结束后会保存到这里。你也可以导入一个对局文件。 | empty state description | Games you finish are saved here. You can also import a game file. |
| 16 | 导入对局… | empty state button | Import Game… |
| 17 | 导入… | toolbar item | Import… |
| 18 | 这盘棋已经在历史里 | duplicate title | This Game Is Already in History |
| 19 | 文件里的对局和历史中的一盘完全相同，所以没有重复添加。 | duplicate message | The game in this file is identical to one already in History, so it wasn't added again. |
| 20 | 查看 | duplicate action | View |
| 21 | 好 | acknowledgement action | OK |
| 22 | 这个文件和历史中的一盘棋冲突 | conflict title | This File Conflicts with a Game in History |
| 23 | 它和历史中的一盘棋是同一局，但内容不同。历史没有改变。如果要用这个文件，请先删除历史中的那一盘。 | conflict message | It is the same game as one in History, but its contents differ. History is unchanged. To use this file, delete that game from History first. |
| 24 | 查看历史中的那一盘 | conflict action | View the Game in History |
| 25 | 这不是 Mini Xiangqi 对局文件 | wrong-file title | This Isn't a Mini Xiangqi Game File |
| 26 | 请选择一个 .mxq 对局文件。历史没有改变。 | wrong-file message | Choose a .mxq game file. History is unchanged. |
| 27 | 重新选择 | wrong-file action | Choose Another |
| 28 | 无法读取这个对局文件 | unreadable title | Can't Read This Game File |
| 29 | 文件的内容无效或过大，无法导入。历史没有改变。请确认文件完整，或者向对方要一份新的。 | unreadable message | The file's contents are invalid or too large to import. History is unchanged. Check that the file is complete, or ask for a new copy. |
| 30 | 这个文件由更新版本的 Mini Xiangqi 创建 | newer-version title | This File Was Created by a Newer Version of Mini Xiangqi |
| 31 | 当前版本无法读取它。请更新 Mini Xiangqi 后再试。历史没有改变。 | newer-version message | This version can't read it. Update Mini Xiangqi and try again. History is unchanged. |
| 32 | 无法保存导入的对局 | import-save-failure title | Couldn't Save the Imported Game |
| 33 | 对局文件没有问题，但保存到历史时出错。历史没有改变。请重试。 | import-save-failure message | The game file is fine, but saving it to History failed. History is unchanged. Try again. |
| 34 | 无法删除这盘棋 | delete-failure title | Couldn't Delete This Game |
| 35 | 这盘棋仍然保留在历史里。请重试。 | delete-failure message | This game is still in History. Try again. |
| 36 | 无法更改置顶状态 | pin-failure title | Couldn't Change Pinned State |
| 37 | 这盘棋的置顶状态没有改变。请重试。 | pin-failure message | This game's pinned state is unchanged. Try again. |

Reused verbatim, already accepted, **not** new: 取消, 重试, 红方获胜, 黑方获胜, 和棋, 将死, 人机对弈,
自由对弈, 你执红, the `N 步` pattern, 共享, 删除, 置顶, 取消置顶, 删除这盘棋？, 删除后无法恢复。
System-supplied, **not** ours to write: 今天, 昨天, and every date and time string in §4.

## 15. Contract edits this implies

For the main thread, not for me.

1. **`interaction-design.md:389`** — the sentence "The exact list layout, date and move-count formatting,
   file-picker presentation, import feedback, conflict feedback, and recoverable error copy remain to be
   designed" is fully answered by §3–§9 and should be deleted when they land.
2. **`interaction-design.md:524`** — the matching **Need to discuss** bullet should be deleted with it.
3. **`interaction-design.md:537`** — the stale blanket bullet loses "empty" and "loading" (§7) and
   "corrupted-import" (§8.5 d–e). What survives of it after this and the other part-7 items is small
   enough to be rewritten rather than trimmed.
4. **`interaction-design.md:382`** — "the app presents an error" gains the copy in §9.2.
5. **New**, in `game-data.md` or `interaction-design.md`: the export filename rule (§9.1) is a deliberate
   localization exception and needs to be written as one.
6. **`testing.md`** — §6.1's action-ordering rule, §4's "never write a date pattern" rule, and §9.1's
   `FileRepresentation` requirement are all things that fail silently and are cheap to gate.

---

# Independent review

Adversarial verification pass by a second agent. I re-read every contract line the note cites, re-ran the
reproducible measurements I could reproduce, and checked all fourteen Apple citations against the pinned
Xcode 27 beta documentation index. **I did not modify anything under `MiniXiangqi/`, did not touch git or
GitHub, and wrote only to this file.** Where I measured, I say so and give the command's output; my own
measurements used `NSFont.systemFont` on macOS via `xcrun swift`, which is an approximation of the
simulator's `UIFont` and is labelled as such.

**What survived.** The headline implementation trap in §6.1 is correct and both of its citations are exact.
The §2.6 line-1 width table reproduces to the hundredth of a point on my machine, which raises confidence in
the probes generally. Twelve of the fourteen Apple citations verify verbatim. The redundancy analysis, the
`ended_at`-not-`exported_at` filename argument, the `FileRepresentation` requirement, the
`allowsMultipleSelection: false` argument, and the framing of §13.1–§13.6 as owner calls are all sound.

**What did not.** Twenty findings below. Two are blocking: a stated cross-device guarantee that the proposed
implementation does not deliver, and a direct contradiction between §3.3 and §5.2 about what the row shows.

## A. Citation audit

### A.1 Apple documentation — verified verbatim

| # | Claim location | Source | Verdict |
|---|---|---|---|
| 1 | §6.1 | SwiftUI `View/swipeActions(edge:allowsFullSwipe:content:)`, Discussion — "Actions appear in the order you list them, starting from the swipe's originating edge." | **VERIFIED**, exact. The page continues "In the example above, the Delete action appears closest to the screen's trailing edge," which is the note's exact case. |
| 2 | §6.1 | UIKit `UISwipeActionsConfiguration/init(actions:)` — "The first item in the array represents the outermost action. For example, when the user swipes from right-to-left, the first action is rightmost. The first action is also the default action." | **VERIFIED**, exact, word for word. |
| 3 | §2.7, §6.1 | SwiftUI `swipeActions`, Discussion — "For labels or images that appear in swipe actions, SwiftUI automatically applies the `fill` symbol variant" | **VERIFIED**. |
| 4 | §6.1 | Same page — "the delete action appears in `red` because it has the `destructive` role" | **VERIFIED**. |
| 5 | §6.1 | Same page — the example tints its second trailing action `.orange` | **VERIFIED**. The example's second trailing action is Flag, tinted orange; the note's characterisation ("its secondary trailing action") is accurate. |
| 6 | §6.1 | SwiftUI `View/swipeActionsContainer()` — "Applying this modifier to a `List` is a no-op, since `List` already provides this coordination." | **VERIFIED**, exact, and all three enumerated guarantees ("Only one row's swipe actions are revealed at a time", "Scrolling the container dismisses any open actions", "Tapping outside the active row dismisses its actions") appear as claimed. |
| 7 | §8.1 | SwiftUI `CommandGroupPlacement/importExport` — "Placement for commands that relate to importing and exporting data using formats that the app doesn't natively support." | **VERIFIED** as text — but see finding B15, where the quote undercuts the use it is put to. |
| 8 | §8.2 | SwiftUI `View/fileDialogCustomizationID(_:)` — "Among other parameters, it stores the current directory, view style (e.g., Icons, List, Columns), recent places, and expanded window size." | **VERIFIED**; the note's elision is faithful. |
| 9 | §9.1 | SwiftUI `ShareLink`, Overview — "Note that some applications offer their sharing service for files, but not for a wide range of different data types, for example, Mail.app, Notes.app, Messages.app or AirDrop. If you don't see a particular sharing service in the presented `ShareLink`, try adding a `FileRepresentation` to the type's `Transferable` conformance." | **VERIFIED**, exact. |
| 10 | §8.4, §11 | Accessibility `AccessibilityNotification.LayoutChanged` — "Optionally, include a parameter that contains the accessibility element for VoiceOver to move to after processing the notification." | **VERIFIED**, exact. |
| 11 | §8.3, §8.4 | HIG **Feedback → Best practices**, both quotes | **VERIFIED**, both exact. |
| 12 | §8.4 | HIG **Alerts → Best practices** — "Avoid using an alert merely to provide information." | **VERIFIED**, exact. See B11a for the passage on the same page the note does not quote. |
| 13 | §8.5 | HIG **Alerts → Content** — "Write a title that clearly and succinctly describes the situation… describe what happened, the context in which it happened, and why. Avoid writing a title that doesn't convey useful information — like 'Error'" | **VERIFIED**; elisions faithful. |
| 14 | §7 | HIG **Loading** — "The best content-loading experience finishes before people become aware of it." | **VERIFIED**; it is the page's own abstract. |
| 15 | §11 | HIG **Accessibility → Cognitive** — "Minimize use of time-boxed interface elements. Views and controls that auto-dismiss on a timer can be problematic for people who need longer to process information, and for people who use assistive technologies that require more time to traverse the interface. Prefer dismissing views with an explicit action." | **VERIFIED**, exact — and it contradicts the note's own §8.4. See B11. |
| 16 | §8.5(a) | HIG **Alerts → Buttons** — "In informational alerts only, you can use 'OK' for acceptance"; "Always use 'Cancel' to title a button that cancels the alert's action"; "Avoid using OK as the default button title unless the alert is purely informational." | **VERIFIED**; the note's paraphrase is accurate. |

### A.2 Apple documentation — could not confirm

Two quotations I could not retrieve through `DocumentationSearch` on this toolchain. I am **not** calling
them NOT FOUND, because the search is semantic and returned neighbouring pages rather than the pages
themselves; I am recording that they are **unverified** so the main thread does not treat them as checked.

- §7, `ContentUnavailableView` Overview — "It is recommended to use `ContentUnavailableView` in situations
  where a view's content cannot be displayed. That could be caused by a network error, a list without items,
  a search that returns no results etc." The search returned `ContentUnavailableView.search`,
  `.search(text:)` and the initializers, never the type's Overview. **UNVERIFIED.**
- §8.2, `fileImporter(…)` — "This dialog provides security-scoped URLs. Call the
  `startAccessingSecurityScopedResource` method to access or bookmark the URLs, and the
  `stopAccessingSecurityScopedResource` method to release the access." The `fileMover` family carries the
  equivalent substance in different words ("To access the received URLs, call
  `startAccessingSecurityScopedResource`. When the access is no longer required, call
  `stopAccessingSecurityScopedResource`."), so the *substance* is right; the *wording* is unconfirmed.
  **UNVERIFIED.**

### A.3 Contract citations — verified

`interaction-design.md` :25, :38, :44, :218, :228, :270, :305, :319–321, :340, :350, :368–:387, :389, :424,
:428, :455, :488, :524, :533, :537; `game-data.md` :35, :36, :38, :41, :49–51, :57, :62, :64, :118, :120,
:121, :136, :143, :145, :165; `product.md` :15, :24, :58; `testing.md` :81, :113; `core-interface.md` :184,
:187, and the "short English diagnostics" sentence (:209) and threading table (:212–231). All read as the
note says they read. Three contract citations are wrong; they are findings B7, B19 and B21.

## B. Findings

### B1 — BLOCKING. The export filename's "byte-identical on every device" guarantee does not hold

**§9.1 says:** "**`en_US_POSIX`, not the user's locale**, so the filename is identical on every device and
sorts chronologically in a folder; this is a deliberate, narrow exception to the localization rule and should
be written down as one" — for `minixiangqi-2026-07-28-1432.mxq`, "built from the game's **`ended_at`**,
formatted with `en_US_POSIX` and `yyyy-MM-dd-HHmm`".

**What is wrong.** `en_US_POSIX` pins the *locale* — digit shapes, calendar, era names, and the refusal to
honour the user's 12/24-hour preference. It does not pin the *time zone*. `ended_at` is an RFC 3339 **UTC**
instant (`game-data.md:38`: "Timestamps are RFC 3339 UTC instants in the exact fixed-width form
`YYYY-MM-DDTHH:MM:SS.sssZ`"). A `DateFormatter` or `Date.FormatStyle` with no explicit `timeZone` renders in
`TimeZone.current`. So the same archive exported from a Mac in `Asia/Shanghai` and an iPhone in
`America/Los_Angeles` produces `minixiangqi-2026-07-28-1432.mxq` on one and `minixiangqi-2026-07-27-2332.mxq`
on the other. The paragraph's own stated purpose — one game, one name, everywhere — fails, and it fails
silently, exactly like the two rules §15.6 sends to `testing.md`.

This also collides with a choice the note does not surface: a UTC-rendered filename will not match the date
the row shows for most of the world, and a locally-rendered one is not stable. Those cannot both be had.

**Severity: blocking** — it is a stated guarantee the specification does not deliver, and it is the kind of
thing that is discovered by a tester in another time zone months later.

**Correction.** State the rule as *locale `en_US_POSIX` **and** a pinned `timeZone`*, and make the time zone
an explicit decision with its cost: `TimeZone(identifier: "UTC")` gives the cross-device identity the
paragraph claims but a name that can differ by a day from the row; `TimeZone.current` gives a name that
matches the row but is not stable across devices. This belongs in §13 as a seventh owner question, or at
minimum in §15.5's contract-edit item. Add it to §15.6's `testing.md` list beside the other two silent
failures.

### B2 — BLOCKING. §3.3 and §5.2 give opposite rules for the resignation row

**§3.3 says:** "Segments omitted when inapplicable: … `结束原因` when the outcome is **a resignation or an
early end**, because the outcome word already carries it".

**§5.2 says:** "**Redundancy rule.** Two pairs say the same thing twice and the reason is dropped:
`未分胜负 · 提前结束` → **未分胜负**; and **a resignation is `红方获胜 · 认输` / `黑方获胜 · 认输`, where the
reason *is* informative and stays.**"

**What is wrong.** These are flatly contradictory: §3.3 drops 认输 from the row, §5.2 keeps it. §5.2 is
right on the merits — 红方获胜 alone does not tell a human-versus-AI player whether they were mated or
resigned, and the note argues that itself — but §3.3 is the section a contract author would transcribe,
because it is the one that specifies the row. A reader implementing §3.3 ships a row that never shows 认输,
which then makes NEW string #11 dead too (compare B3).

The §5.2 sentence is also internally broken: "**Two pairs** say the same thing twice and the reason is
dropped" is followed by one pair dropped and one pair kept.

**Severity: blocking** — two accepted-looking specifications of the same row field, disagreeing.

**Correction.** Rewrite §3.3's omission clause to "`结束原因` when the outcome word already carries it, which
is exactly the `outcome = none` case; see §5.2," and rewrite §5.2's opening to "One pair says the same thing
twice and its reason is dropped; one pair looks redundant and is not."

### B3 — MAJOR. 提前结束 (NEW string #12) can never be displayed

**§14 row 12 asks for approval of** 提前结束, "where: reason `ended-early`". **§5.2's redundancy rule
removes it:** "`未分胜负 · 提前结束` → **未分胜负**".

**What is wrong.** `game-data.md:51` makes the cross-field rule exact: "`outcome = none` **exactly when**
`end_reason = ended-early`". So `ended-early` never co-occurs with any other outcome, and 未分胜负 never
co-occurs with any other reason. Under the note's own redundancy rule the reason is dropped in the only
case in which it can occur — so 提前结束 is unreachable in the History row, which is the only place §14
says it lives. The note is asking the owner to approve, and part 6 to translate, a string the design
guarantees is never rendered.

**Severity: major** — it inflates the approval and localization surface the note itself is warning about in
§12, and it will read to a reviewer as a design that has not been walked through its own vocabulary.

**Correction.** Either drop #12 from §14 with a one-line note that the redundancy rule makes it unreachable,
or keep it and say where else it appears (the replay metadata panel is part 4's, not this note's — §3.4
already disclaims it). Recount §12's "**37** new Chinese strings" accordingly; see also B13, which removes
another.

### B4 — MAJOR. 历史 is declared not-new while ten of the thirty-seven NEW strings depend on it

**§12 says:** "**The History destination has no accepted Chinese name** — survey defect 6.2. Every screen
title and every message above that would want to say 'History' says 历史 **in my prose**; I have **not**
listed 历史 as a NEW string because naming the three primary destinations is 6.2's job and should be decided
once, for all three, not incidentally here."

**What is wrong.** It is not only in the prose. 历史 is embedded in ten of the thirty-seven strings §14
submits for approval: #14 还没有**历史**对局, #18 这盘棋已经在**历史**里, #22 这个文件和**历史**中的一盘棋冲突,
#23 …**历史**中的一盘棋…**历史**没有改变…**历史**中的那一盘, #24 查看**历史**中的那一盘,
#26 **历史**没有改变, #29 **历史**没有改变, #31 **历史**没有改变, #33 保存到**历史**时出错…**历史**没有改变,
#35 这盘棋仍然保留在**历史**里.

So the note is simultaneously (a) declaring the destination's name an open question owned by 6.2 and
(b) asking the owner to approve ten strings that hard-code one answer to it. If 6.2 names the destination
对局记录 or 棋谱, all ten strings are rewritten — including the 历史没有改变 sentence the note calls its
single most important guarantee ("every one of them says 历史没有改变 explicitly, because 'no persistent
change' is the accepted guarantee"). This is exactly the "presented as settled when it is an open product
decision" failure the review brief asks about, and the note asserts the opposite about itself.

**Severity: major** — it mis-states the note's own content, and it hides a real dependency from the main
thread.

**Correction.** Add a sentence to §12 and a note at the head of §14: *every string containing 历史 is
provisional on 6.2's naming of the History destination; if that name changes, these ten strings change with
it.* Consider factoring the guarantee sentence so it is one reusable clause rather than five copies.

### B5 — MAJOR. "EVERY Chinese variant fits on one line" is not established by the evidence given

**§2.2 says:** "**The single most important measured result in this note: at the default text size, on the
narrowest supported iPhone, every Chinese variant of the accepted dot-joined metadata line fits on one line,
and every English variant needs two.**" The report summary escalates this to "the first quantified instance
of the question part 6.1 has to answer for all 58 accepted strings."

**What is wrong.** `p7-list-probe.swift` measures exactly **three** Chinese strings:

```
static let secondaryLongest = "自由对弈 · 和棋 · 三次重复 · 118 步"
static let secondaryAI      = "人机对弈 · 你执红 · 红方获胜 · 将死 · 42 步"
static let secondaryEarly   = "人机对弈 · 你执黑 · 未分胜负 · 提前结束 · 3 步"
```

"Every variant" is a universal claim over the whole §5.2 vocabulary — four outcomes × nine reasons × two
modes × two sides × the ply count — and three samples do not establish it. Worse, the string labelled
"longest" is not the longest, and one of the three (`secondaryEarly`) is a string §5.2 forbids (B6).

**What I measured.** `NSFont.systemFont(ofSize: 15)` on macOS, same 311 pt budget (approximation of the
simulator's `UIFont`):

```
 279.34  FITS   人机对弈 · 你执红 · 红方获胜 · 将死 · 42 步
 227.06  FITS   自由对弈 · 和棋 · 三次重复 · 118 步
 300.04  FITS   人机对弈 · 你执黑 · 未分胜负 · 提前结束 · 3 步
 283.89  FITS   人机对弈 · 你执黑 · 和棋 · 双方长捉 · 118 步
 307.73  FITS   人机对弈 · 你执黑 · 和棋 · 双方长将 · 10,000 步
 307.73  FITS   人机对弈 · 你执红 · 黑方获胜 · 长捉 · 10,000 步
 307.73  FITS   人机对弈 · 你执红 · 红方获胜 · 将死 · 10,000 步
```

The conclusion survives — but the true worst constructible row is **307.73 pt against 311**, a margin of
**3.27 pt, about one per cent**, not the comfortable result the note's phrasing implies; and none of the
three measured strings is that case. A five-digit grouped ply count plus a four-glyph reason is the binding
combination, and it was never measured. Add one character anywhere — a six-digit ply count (B16), a
different system font metric on iOS, a locale whose grouping separator is wider — and the claim inverts.

**Severity: major** — this is the note's self-nominated load-bearing result and the input to owner question
§13.4. A 1 % margin and a 6.1 decision should not rest on three hand-picked samples.

**Correction.** Extend `p7-list-probe.swift` section (c) to enumerate the vocabulary rather than sample it —
it is a few dozen strings and the probe already has the machinery — and restate §2.2 as "the longest
constructible Chinese row measures X pt of 311 at the default size, leaving Y pt", with the actual worst
string printed. If the real margin is ~3 pt, say so: that is a materially different fact for §13.4 than
"every variant fits."

### B6 — MAJOR. The "worst case" rows are measured with a string the design forbids

**§2.3 and §2.4 label** `人机对弈 · 你执黑 · 未分胜负 · 提前结束 · 3 步` (and its English twin
`Human vs AI · You played Black · No result · Ended early · 3 moves`) as "**zh worst**" / "**en worst**",
and every number in §2.4's row-height table and §2.2's "ended-early" column comes from it. **§5.2 forbids
that string**: "`未分胜负 · 提前结束` → **未分胜负**".

**What is wrong.** The note's own redundancy rule deletes the fourth segment. So §2.4's headline "Measured
row height 63.33 pt in Chinese and 83.33 pt in English at the default size" is the height of a row the app
never draws, and §2.2's ended-early column measures a line that cannot occur. This is precisely "numbers
attached to the wrong experiment".

It propagates. §13.1's argument against showing both instants — "measured: that line is already at roughly
**300 pt** of the 311 available" — is the 300.04 pt figure for the forbidden string. The number that
actually belongs there is 307.73 (B5), which strengthens the conclusion but is not the number given.

**Severity: major.** The conclusions happen to survive, but every quoted row-height figure is attached to
the wrong string, and a reviewer who checks will not know which other numbers to trust.

**Correction.** Re-run sections (b)–(d) of `p7-list-probe.swift` and section (i) of `p7-row-probe.swift`
against post-redundancy-rule strings, including the true worst from B5, and re-state §2.2, §2.3, §2.4 and
§13.1 from that run. Add a sentence to §0 saying the probe strings are generated from §5.2's vocabulary so
the two cannot drift apart again.

### B7 — MAJOR. The 44 pt floor is attributed to a contract line that is about the board, not a list row

**§2.4 says:** "63.33 pt clears the accepted 44 pt hit-target floor (`interaction-design.md:480`) at the
default size with 19 pt to spare".

**`interaction-design.md:480` says:** "The board is square and is sized to the largest square fitting
**both** the available width and the height left after the surrounding chrome, so it never overflows a short
window. Within that, **a point of the grid is never smaller than 44 points** on **every** platform."

**What is wrong.** :480 fixes the board's **cell pitch** `p ≥ 44 pt` — the same rule stated at :129, "The
accepted floor is `p ≥ 44 pt` on every interactive board" — and the surrounding paragraph explains it in
terms of the marker vocabulary in Board metrics. It is not a general hit-target floor and says nothing about
list rows. **No accepted contract line imposes a 44 pt minimum on a History row.** The real source of 44 pt
for a row is HIG **Accessibility → Mobility**, whose table gives iOS/iPadOS a *default* control size of
44×44 pt and a *minimum* of 28×28 pt — which is a guideline, not this project's accepted contract, and which
the note does not cite.

**Severity: major** — the review brief treats a false claim about what a contract says as a defect rather
than a suggestion, and this one manufactures an accepted requirement that does not exist. It also matters in
the other direction: if the row genuinely has no accepted floor, §2.4's "No minimum-height clamp is needed"
is answering a question nobody asked, and if the project *wants* one it has to be added rather than assumed.

**Correction.** Replace the citation with HIG **Accessibility → Mobility**'s control-size table, say plainly
that the contract fixes 44 pt for the board's cell pitch and is silent on list rows, and either drop the
"clears the floor" framing or propose the row floor as a new contract sentence in §15.

### B8 — MAJOR. §8.5(c) asserts a fact the app does not know, and gives advice the user already followed

**§8.5(c) covers:** "the in-band `archive_format` member is absent or wrong, **or the transport failed before
anything could be read**. The user picked the wrong file." **Title:** 这不是 Mini Xiangqi 对局文件.
**Message:** 请选择一个 .mxq 对局文件。历史没有改变。

**Two problems.**

*First, the title lies in one of its own listed cases.* A transport failure — the file could not be read at
all, the security-scoped access failed, an iCloud materialization failed — tells the app **nothing** about
whether the file is a Mini Xiangqi game file. Announcing "这不是 Mini Xiangqi 对局文件" for a file the app
never managed to open is a false statement to the user, and it directly violates the HIG **Alerts → Content**
rule the note itself quotes two paragraphs earlier: "describe **what happened**, the context in which it
happened, and why."

*Second, the remedy restates what the user just did.* §8.2 sets
`allowedContentTypes: [.miniXiangqiGame]`, which the note says "filters to the declared UTI, so `.mxq` files
are selectable and nothing else is." Under that picker the reachable population of this alert is almost
entirely files that **are** `.mxq` by extension and UTI but whose in-band `archive_format` is absent or wrong
(`game-data.md:36`: "the extension and UTI are hints only"). Telling that user 请选择一个 .mxq 对局文件 —
"choose a .mxq game file" — instructs them to repeat the action that just failed.

**Severity: major** — a user-facing message that is false in one branch and unactionable in the other, in
the one rejection class the note singles out as having a one-tap remedy.

**Correction.** Split the transport failure out of (c) — it belongs with (d), whose 无法读取这个对局文件 is
literally true of it — and re-word (c)'s message so it names the real cause: something on the order of
*这个文件不是 Mini Xiangqi 创建的对局文件。历史没有改变。* Keep 重新选择.

### B9 — MAJOR. The conflict alert's 查看历史中的那一盘 needs data the accepted C interface does not supply

**§8.5(b) proposes actions** **查看历史中的那一盘** · **好**, and argues "naming the route matters".

**What is wrong.** `core-interface.md:187` is precise about what comes back: "`mxq_store_import` returns
`MXQ_IMPORT_EXISTING` **with the existing record** for an exact duplicate — success, not an error — and
**typed failures** for every rejection class defined by the import pipeline". The existing record is promised
for the **duplicate** case only. For an identity conflict — a `MXQ_DOMAIN_STORE` "identity conflict"
(`core-interface.md:198`) — the contract promises a typed failure and nothing else. Nor is there another way
in: the History surface is `mxq_store_history_get(record_id)` / `mxq_store_history_open(record_id)`
(`core-interface.md:168–171`), both keyed on the local `record_id`; **there is no lookup by `game_id`**, and
`game_id` is all the frontend can learn from `mxq_archive_probe`/`validate` via `MxqArchiveInfo`
(`core-interface.md:150`).

So §8.5(a)'s 查看 is implementable exactly as specified, and §8.5(b)'s 查看历史中的那一盘 is not. The note
does not notice the asymmetry, and §15's contract-edit list does not ask for the interface change it needs.

**Severity: major** — a proposed action with no data path, in a flow the accepted contract already requires
to be explained (`:384`, "A stable-identity conflict with different game content is rejected with an
explanation").

**Correction.** Add a §15 item: either `mxq_store_import` must set `out_record_id` (and optionally
`out_summary`) on the identity-conflict failure, or `core-interface.md` needs a lookup-by-`game_id`. Until
one exists, mark 查看历史中的那一盘 as contingent, and note the fallback — a single 好 — in §8.5(b).

### B10 — MODERATE. "The operation is bounded at 2 s" overstates the contract, and it is the whole argument for having no Cancel

**§8.3 says:** "Import is one bounded operation with a **2 s ceiling**" and "**No Cancel and no blocking
overlay.** *Reasoned*: the operation is **bounded at 2 s**, nothing is written until the final transaction
(`game-data.md:64`), so cancelling buys nothing a two-second wait does not."

**`game-data.md:62` says:** "Import limits: at most 1 MiB per file, 10 000 plies, JSON nesting depth 4, 32
members per object, 256-byte strings, and **a validation time budget of two seconds** on the slowest
supported device."

**What is wrong.** Two seconds bounds **validation**, not import. `game-data.md:64` puts three more stages
after validation — "then canonicalization and hashing; then **the single write transaction** performing
duplicate/conflict comparison and, only for a new game, one insert" — and `core-interface.md:210` confirms
the budget is a validation-stage concept: "the import time budget exhausts as a resource-domain limit." The
write transaction is a SQLite commit with WAL and full synchronous durability (`game-data.md:146`); on a
busy or slow store it has no accepted bound at all, and §8.5(f) exists precisely because it can fail.

Since "bounded at 2 s" is the sole premise of "cancelling buys nothing", the conclusion is not supported as
argued. It is probably still the right answer — a Cancel that cannot safely interrupt a write transaction is
worse than none — but that is a different argument.

**Severity: moderate** — a justification that does not survive its own paragraph.

**Correction.** Restate as: *validation is bounded at 2 s; the write transaction is not separately bounded
but is atomic and non-interruptible, so a Cancel could only abandon the UI, not the operation — which is
why there is none.* That reasoning is stronger and is contract-true.

### B11 — MODERATE. §11's "nothing time-boxed" contradicts §8.4's 600 ms highlight, against the citation §11 uses

**§11 says:** "**No time-boxed content.** The success highlight decays but nothing dismisses itself, and
every alert needs an explicit action. *Cited*, HIG **Accessibility → Cognitive**: 'Minimize use of
time-boxed interface elements. Views and controls that auto-dismiss on a timer can be problematic for people
who need longer to process information…'"

**§8.4 says:** "The list scrolls it into view and applies a **brief row highlight, ~600 ms**, decaying to the
normal row background."

**§13.5 says the cost out loud:** "a user who imports a file and gets no message **may not immediately
notice which row is new**".

**What is wrong.** A highlight that decays on a 600 ms timer *is* a time-boxed interface element, and by
§13.5's own admission it is the only sighted indication of which row was just added. "Nothing dismisses
itself" is false of the very thing §8.4 specifies. The HIG passage quoted is about exactly this: an element
carrying information that disappears on a timer, in under a second, with no explicit action.

This is not a reason to abandon the silent-success recommendation — the row itself persists, which is the
note's better argument — but §11 cannot claim the property it claims.

**Severity: moderate** — a self-contradiction that a reviewer reading §11 in isolation would accept.

**Correction.** Change §11 to "**Nothing whose disappearance loses information.** The success highlight
decays after ~600 ms; the row it highlights persists indefinitely, so no information is time-boxed. Every
alert requires an explicit action." That is defensible and does not overclaim.

**B11a, related.** HIG **Alerts → Best practices** contains a passage the note does not quote and which
bears directly on §9.3: "**Avoid displaying alerts for common, undoable actions, even when they're
destructive.**" §9.3's pin-failure alert is for a reversible action; the note already labels it its weakest
recommendation and cites `interaction-design.md:228` against itself, which is good practice, but it should
cite the HIG passage too rather than only the contract. Omitting the strongest contrary evidence from the
same page it quotes for support weakens the honesty the section is going for. *Severity: minor.*

### B12 — MODERATE. §8.4's Reduce Motion treatment is an interpretation, presented as the rule "applied without exception"

**§8.4 says:** "Under Reduce Motion the scroll is an immediate jump and the highlight is unchanged. **This is
the accepted Reduce Motion rule applied without exception:** 'Anything that animates position, scale, or
rotation becomes a crossfade of at most 120 ms; anything that animates opacity, colour, stroke weight, or
shadow is unchanged…' (`:428`)."

**What is wrong.** `:428` says position becomes **a crossfade of at most 120 ms**. §8.4 substitutes **an
immediate jump**. Those are not the same treatment, and the note asserts identity in the same sentence that
quotes the text disproving it. (`:418` does permit "a brief crossfade **or immediate state update**", so the
outcome is contract-legal — but via :418, and as a judgement, not as :428 "without exception".)

**Severity: moderate** — small in effect, but it is the pattern the brief names: a justification that does
not survive its own paragraph, in a sentence claiming rigour.

**Correction.** Cite `:418` as well and say plainly that a scroll has nothing to crossfade *to*, so the
immediate-update branch of :418 applies; drop "without exception".

### B13 — MODERATE. 好 is very likely system-supplied, by the note's own 今天 / 昨天 test

**§14 row 21 lists 好 as NEW,** "acknowledgement action". **§14's closing says:** "System-supplied, **not**
ours to write: 今天, 昨天, and every date and time string in §4."

**What is wrong.** SwiftUI's `alert` family documents: "**If no actions are present, the system includes a
standard 'OK' action.** No default cancel action is provided." (verified on `View/alert(_:item:actions:)`
and siblings). That system-supplied OK is localized by the system — 好 in zh-Hans — exactly as 今天 and 昨天
are. §8.5(d) and §8.5(e), and §9.3, are single-action alerts whose only action is 好; for them the app should
supply **no** action and inherit the system string, which is the same argument the note makes for the day
words ("writing our own would diverge from the rest of the OS").

The multi-action alerts (a), (b), (c) do need an explicit second button, so 好 is not eliminated entirely —
but it is not straightforwardly NEW copy either, and the note's own criterion says so.

**Severity: moderate** — it is the note's own system-versus-ours test applied inconsistently, and it changes
the §12 headline count.

**Correction.** Split #21: note that for single-action alerts the system supplies the acknowledgement and the
app should pass no actions; list 好 as NEW only for the multi-action alerts, and say which. Recompute §12's
count with B3.

### B14 — MODERATE. `product.md:24` is about platforms, not languages, and §13.4 leans on it

**§13.4 says:** giving English its own pattern "**contradicts `product.md:24`'s rule that product behaviour
is identical across presentations**, and it would need an explicit exception." §12 makes the same move.

**`product.md:24` says:** "Each platform uses a native frontend — SwiftUI on Apple platforms and WinUI 3 on
Windows — over one shared core, as defined in architecture.md. **Product behavior and persisted meaning are
identical across platforms**; presentation follows each platform's conventions."

**What is wrong.** :24 is a sentence about **platforms** — Apple versus Windows — inside a section titled
Target platforms. It says nothing about languages. Using it to constrain a **localization** choice imports a
constraint the contract does not contain, and it does so in an owner question, where a manufactured
constraint quietly pre-decides the answer. §3.1's use of the same line for Windows row content is correct;
§13.4's is not.

The genuinely applicable accepted text is `interaction-design.md:455` — "Simplified Chinese is the source
language: the accepted user-facing copy in this document is normative, and **its English counterparts are
translations of it**" — which is a stronger argument anyway, because a translation that omits a field is not
a translation. `:459`'s "layouts must tolerate different text lengths" also bears.

**Severity: moderate** — a contract line cited for something it does not say, inside a decision framed for
the owner.

**Correction.** Replace the `product.md:24` citation in §13.4 and §12 with `interaction-design.md:455`
and `:459`, and restate the cost as "English would show less information than the normative Chinese, which
is a translation divergence rather than a platform divergence."

### B15 — MODERATE. The `importExport` citation says the opposite of the use it is put to

**§8.1 says:** "a menu-bar command in `CommandGroupPlacement.importExport`, which is *cited* as 'Placement
for commands that relate to importing and exporting data using formats that the app doesn't natively
support'."

**What is wrong.** The quotation is exact (A.1 #7) — and it describes placement for **foreign** formats. The
`.mxq` archive is the app's own native interchange format: `game-data.md:35` declares its extension, its
Apple UTI and its MIME type, and `game-data.md:113` calls export "a portable, versioned game archive". By the
quoted wording, `importExport` is the placement this command does **not** belong in. The note quotes the
sentence and then says it is "the placement for exactly this", which is the reverse of what it reads.

The recommendation may still be right in practice — the note's own observation that "this app has no
documents in the `DocumentGroup` sense" rules out `newItem` and Open — but that makes it a *reasoned* choice
against a citation, not a *cited* one, and the note's own §0 taxonomy requires that distinction.

**Severity: moderate** — a citation presented as supporting a choice that its text argues against.

**Correction.** Reclassify as *reasoned*: "`importExport` is documented for formats the app doesn't natively
support, which `.mxq` is not; it is nonetheless the only placement that fits, because the app has no
documents in the `DocumentGroup` sense and so `newItem` and Open do not apply. Recorded as a judgement
against the documented wording."

### B16 — MODERATE. "The ceiling case renders `10,000 步`" contradicts `game-data.md:62`

**§5.1 says:** "Use the locale's own grouping (`IntegerFormatStyle`), so **the ceiling case** renders
`10,000 步` / `10,000 moves` rather than `10000`."

**`game-data.md:62` says:** "Import limits: at most 1 MiB per file, **10 000 plies**… **These bound the
import surface only; live local play is not length-limited, and a locally produced game exceeding the import
bounds remains fully playable and replayable** — only re-import of its export would be refused."

**What is wrong.** 10 000 plies is not a ceiling on what the row must render; it is a ceiling on what may be
*imported*. A locally played game may exceed it, and the contract says so explicitly and deliberately. The
row therefore has to render six-digit ply counts. Combined with B5, that matters: my measurement puts the
worst five-digit row at 307.73 pt of 311, so one more digit (≈ +8 pt at 15 pt) pushes the Chinese row past
the budget and wraps it — inverting §2.2's headline result for the reachable-but-rare case.

**Severity: moderate** — a false statement about an accepted contract, with a measurable consequence for the
note's central result. Practically unreachable (a 100 000-ply Mini Xiangqi game), but the contract went out
of its way to say local play is unbounded.

**Correction.** Change "the ceiling case" to "the import ceiling"; state that local play is unbounded per
`game-data.md:62`, and record the measured width at which line 2 wraps in Chinese, so the wrap is a known
consequence rather than a surprise.

### B17 — MODERATE. Whether 删除前确认 gates the non-swipe deletions is left unspecified

**§6.2 proposes:** a context menu with 删除, "**Keyboard**, macOS, with a row selected: `Return` opens
replay; `Delete` and `⌘⌫` both delete", and VoiceOver custom actions including 删除.

**`interaction-design.md:377` says:** "**删除前确认** is a Settings toggle and is enabled by default. When
enabled, **either the visible Delete action or a complete swipe** presents: [the confirmation]". **`:381`
says:** "When **删除前确认** is disabled, **either deletion gesture** permanently deletes immediately."

**What is wrong.** The accepted sentences enumerate exactly two entry points, both of them swipe-surface
ones. A keyboard `⌘⌫`, a context-menu 删除, and a VoiceOver custom action are none of the three named things,
so the accepted confirmation rule does not literally reach them — and §6.2 introduces all three without
saying whether the confirmation applies. `testing.md:82` gates "**删除前确认** defaults on and governs both
the visible Delete action and complete swipe" and would not catch a keyboard path that skips it.

Given `:386`'s "expose **equivalent** … Delete operations", the intent is clearly that they are gated. But
this is the note's own §6.1 pattern — a rule that fails silently and is cheap to write down — and it is not
written down.

**Severity: moderate** — an unstated rule on the one irreversible action in the surface.

**Correction.** Add one sentence to §6.2: *every Delete entry point — swipe action, full swipe, context menu,
keyboard, and VoiceOver custom action — is gated by 删除前确认 identically.* Add it to §15's `testing.md`
list beside the action-ordering rule, and propose widening `:377`/`:381` from "either deletion gesture" to
"any Delete entry point" in §15.

### B18 — MINOR. §3.3's "no `accessibilityLabel`" and §11's combined label cannot both be true

**§3.3 says of 导入:** it "**reads correctly to VoiceOver without an `accessibilityLabel`**".

**§11 says:** "One accessibility element per row, not two. Label = line 1 then line 2, **read as one sentence
with the ` · ` separators spoken as pauses rather than as the character**."

**What is wrong.** Making a row one element with a composed label whose middle dots are re-spoken as pauses
*is* supplying an `accessibilityLabel` — there is no other mechanism; `accessibilityElement(children:
.combine)` concatenates the visible text and leaves the ` · ` glyphs in it. So the row necessarily carries a
constructed label, and 导入's virtue is that it needs no *special* handling inside that label, not that no
label exists.

**Severity: minor** — the design is fine; one of its stated advantages is stated wrongly, and it is used as
an argument for text over a glyph.

**Correction.** In §3.3, say "contributes its own word to the row's accessibility label with no extra
mapping, where a glyph would need one." §11 is right as written.

### B19 — MINOR. Two `game-data.md` line citations point at the wrong bullets

**§5.1 says:** "**`0 步`** is reachable — an ordinary game archived through 保存并继续 before either side
moved is recorded ended-early with an empty move list (`game-data.md:80`)."

**`game-data.md:80` is:** "a claimable neutral repetition that has not been claimed remains an ongoing game
and is therefore recorded as ended early, not as a draw" — the repetition case, not the ordinary case, and it
says nothing about an empty move list. The bullet the sentence wants is **:79**, "an ordinary ongoing game is
recorded with an ended-early reason and no competitive result" (and `:108` in the History section). Neither
mentions zero plies; the 0-ply reachability is a correct *inference* from `:184` (any active game may be
saved) plus `:79`, and should be labelled as one.

**Also in §5.1:** "`:40` defines it as the length of `moves`, whose **index 0 is Red's first move**." `:40`
carries "No move count is serialized (it is the length of `moves`)"; the "index 0 is Red's first move" clause
is at **:38**.

**Severity: minor**, but the note's whole method rests on citations a reader can check in one keystroke.

**Correction.** `:79`/`:108` for the ended-early classification, `:184` for reachability, `:38` for the move
index, and mark the 0-ply case *reasoned*.

### B20 — MINOR. Two more contract references point at neighbouring rules

- **§3.4** — "the replay screen's metadata, which is part 4's open item (`:516`)". `:516` is "Define what the
  **side-by-side panel** contains beyond the turn status, move list, game metadata, and controls…" — a
  during-play layout question. The replay screen's metadata panel is not what :516 is about; §12 separately
  and correctly assigns it to part 4 (PR #23) with no line cite, which is the honest form.
- **§13.6** — "`:386`'s rule that platform gaps are filled by equivalents rather than new capabilities cuts
  against it". `:386` is about History row actions specifically and contains no such general rule. The
  general rule is **`:506`**: "Where a platform lacks an interaction idiom used elsewhere — for example, list
  swipe actions on Windows — the same operations must be exposed through that platform's conventional
  equivalents… **without changing product capabilities**." (`:25` is the other half.)

**Severity: minor.** **Correction.** Drop the :516 cite or replace it with a plain statement that part 4 owns
it; cite :506 (and :25) in §13.6.

### B21 — MINOR. §2.3's "+11 to +131 pt in every one of the twenty cells" cannot be checked against the table it follows

**§2.3 says:** "The split form costs **+11 to +131 pt** in every one of the **twenty** cells", immediately
after a table with **ten** deltas whose range is **+55.00 to +131.00**:

```
zh:  84.00  87.67  101.00   98.00  131.00
en:  64.00  87.67   70.00   55.00   73.00
```

**What is wrong.** `p7-row-probe.swift` measures four cases × five sizes = twenty comparisons ("zh worst",
"zh draw", "en worst", "en draw"), so "twenty" is right about the probe — but the note prints only two of the
four cases, and the +11 minimum lives in a row the reader never sees. A reviewer checking the arithmetic
concludes the stated range is wrong. Given that §2.3 exists specifically so a reviewer will not re-propose
the split layout, its numbers need to be checkable from the page.

**Severity: minor** (the conclusion is unaffected; the presentation defeats its own purpose).

**Correction.** Print all four cases, or state the range as "+55 to +131 pt across the ten cells shown, +11
at minimum across all twenty measured".

### B22 — MINOR. `AttributedString` is not a pluralization mechanism

**§5.1 says:** "English pluralises zero as `0 moves` and one as `1 move`; use `AttributedString`-style
pluralization rather than a concatenation."

**What is wrong.** `AttributedString` is a rich-text type; it does not select plural forms. The mechanisms
are the String Catalog's plural variations (`.xcstrings`, or `.stringsdict` historically) and SwiftUI/
Foundation's automatic grammatical agreement in `LocalizedStringResource` interpolation. Naming the wrong
API in a note whose §15.6 asks `testing.md` to gate implementation details is a small but avoidable error.

**Severity: minor.** **Correction.** "Use a String Catalog plural variation rather than a concatenation."

### B23 — MINOR. Two unsupported supporting claims

- **§3.1** — "its 16 pt inset is **the same inset the rest of the app's chrome uses**". No accepted contract
  fixes an app-wide 16 pt chrome inset; `interaction-design.md` specifies the board's insets in multiples of
  the cell pitch `p` (:127–:157) and says nothing about chrome. Presented as a reason for choosing
  `insetGrouped`, it is an assertion about a system that has not been specified. *Correction:* drop the
  clause or mark it as an assumption to be checked against the layout work `:513`–`:514` owns.
- **§6.2** — "the contract **names exactly one keyboard command in the whole app** (Flip Board, `:218`)".
  `:218` names no command; it says the flip control "has a localized accessibility label and an **equivalent
  keyboard command where keyboard input is supported**" — a requirement that one exist, with no key given.
  `:233` separately requires a keyboard equivalent for the whole move-input flow. The argument (do not invent
  shortcuts here) is right; the supporting sentence is not accurate. *Correction:* "the contract requires a
  keyboard equivalent for exactly one named control (:218) and for board input generally (:233), and fixes no
  key anywhere."

## C. Things checked and found sound, recorded so they are not re-litigated

- **The Delete-first ordering rule (§6.1).** Both citations are verbatim; the reasoning from
  `interaction-design.md:372`'s "From left to right, they are blue **共享** and red **删除**, with Delete
  nearest the trailing edge" to "Delete listed first" is correct for both supported languages (both LTR;
  `HorizontalEdge`'s note that leading/trailing depend on locale does not bite). `allowsFullSwipe` does
  default to `true` and the first action is the default action, so §6.1's "no override is needed" holds.
- **`swipeActionsContainer()` (§6.1).** Exists on iOS 27; the no-op-on-`List` sentence is exact.
- **The `FileRepresentation` requirement (§9.1).** Exact quote, and the AirDrop inference is the one the
  documentation supports.
- **§2.6's line-1 widths.** I reproduced them on macOS at 17 pt: `今天 14:32` = 80.60, `导入 · 今天 14:32` =
  127.62, `导入 · 2024/11/9 12:00` = 168.81, `Imported · 11/9/2024, 12:00 PM` = 237.44 — identical to the
  note's figures to two decimals. The 47 pt cost of the 导入 · prefix and the 73.6 pt worst-case slack both
  check out.
- **The English wrap claim (§2.2).** I measured the three probe strings plus a constructed English worst case
  (`Human vs AI · You played Black · Draw · Mutual perpetual chase · 10,000 moves`, 541.81 pt): all exceed
  311 pt, all need two lines at 15 pt. Unlike the Chinese claim (B5), this one is robust.
- **困毙 for stalemate.** Correct for this ruleset. `xiangqi-rules.md:51` — "A position with no legal move is
  a loss for the player who cannot move" — and the fixture `mx-end-002` at `:103` make stalemate a loss, so
  the note's warning that the English gloss must not say "draw" is right, and 困毙 is the standard Chinese
  term for that outcome. 长将, 长捉, 双方长将 and 双方长捉 likewise match `xiangqi-rules.md:63`, `:64` and
  `:68`, whose reserved identifiers are exactly `mutual-perpetual-check` and `mutual-perpetual-chase`.
- **The vocabulary is complete.** All four `outcome` values and all nine `end_reason` values from
  `game-data.md:49–50` are tabulated in §5.2; none is missing.
- **`ended_at` rather than `started_at` (§4.3).** `game-data.md:38`'s "present exactly when the game is
  completed, which every exported file is" supports it exactly as quoted.
- **The glass-budget argument (§1, §8.5, §9.3).** `interaction-design.md:38` does list "alerts, sheets,
  context menus, and History swipe actions" as "additional and automatic", so the alerts genuinely cost
  nothing against the three-surface budget, and §9.3's "an inline surface would be a fourth" is a real
  constraint rather than a rhetorical one.
- **The 500 ms reuse (§8.3).** `:424` says what the note says it says, and reusing the number rather than
  inventing one is the right instinct.
- **The 无法保存对局 family (§8.5(f), §9.2).** `:319–321` matches verbatim, 取消 and 重试 are genuinely
  already accepted, and `testing.md:73` already gates that exact quadruple — so the sibling-shape argument is
  well founded.
- **The redundancy analysis itself (§5.2).** `game-data.md:51`'s "`outcome = none` exactly when
  `end_reason = ended-early`" makes the note's rule exactly right (which is also what makes B3 true).
- **§13.1–§13.6 are correctly the owner's.** I found nothing deferred there that a merged contract already
  decides. Conversely, the one thing the note presents as settled that is not is the History destination's
  Chinese name (B4).

## D. Summary

| Severity | Findings |
|---|---|
| Blocking | B1 (export filename time zone), B2 (§3.3 vs §5.2 on 认输) |
| Major | B3, B4, B5, B6, B7, B8, B9 |
| Moderate | B10, B11 (+B11a), B12, B13, B14, B15, B16, B17 |
| Minor | B18, B19, B20, B21, B22, B23 |

Nothing here overturns the note's shape. The two-section list, the two-line row, the dot-joined run, the
date rule, the four-message cut, the silent success and the six owner questions all survive the check. What
needs work before any of it becomes contract text is the evidence layer: three of the load-bearing numbers
are attached to strings the design forbids or to samples that do not support the universal claim made from
them, one contract citation invents an accepted requirement, and one paragraph promises a cross-device
guarantee its own implementation does not deliver.
