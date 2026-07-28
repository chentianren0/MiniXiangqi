# Part 8 · Accessibility acceptance criteria, and an audit of the accepted contracts against them

Workspace-only research evidence. Part of no repository. **Non-normative**: nothing here is a decision, nothing
here authorises implementation, and nothing here amends a contract. The contracts are `MiniXiangqi/docs/*.md`.

Scope: `interaction-design.md:532`, **first clause only** — *"Define accessibility acceptance criteria"*. The
second clause of that bullet, the board's VoiceOver interaction model, belongs to another researcher; where a
criterion here depends on it I say so and stop rather than designing it.

---

## 0. Method — what each claim rests on

- **Executed.** Read all eight contracts at `MiniXiangqi/docs/` in full (`interaction-design.md`, `testing.md`,
  `product.md`, `game-data.md`, `xiangqi-rules.md`) or by targeted search (`architecture.md`,
  `core-interface.md`, `engine-integration.md` — searched for every accessibility term; the only two hits are
  `architecture.md:32-33`, which merely assign accessibility integration to the frontend layer). Recomputed
  every board metric at the 44 pt floor in Python. Grepped the whole `docs/` tree for `hit`/`touch target`/
  `tappable`, for `Dynamic Type`/`text size`/`Bold Text`/`Zoom`/`Switch Control`/`Voice Control`, and for
  `44 `. Results are quoted where they matter.
- **Read (Apple).** `mcp__xcode__DocumentationSearch` against the pinned Xcode 27 beta documentation, six
  queries. Every citation below is quoted from what came back; where Apple publishes nothing I say so.
- **Reasoned.** Every criterion's threshold where the contract does not already fix one, every audit verdict,
  and every consequence claim. These are my judgements and are the things to disagree with.

Recomputed board metrics at `p = 44 pt`, for reference throughout (all match the contract's own stated values,
so this is a check rather than a new result):

| Quantity | Formula | At floor |
|---|---|---|
| Board core | `7 p` | 308.0 pt |
| Piece disc | `0.80 p` | 35.2 pt |
| Piece symbol em / icon box | `0.50 p` | 22.0 pt |
| Marker band | `0.42 p`–`0.50 p` | 18.48–22.0 pt |
| Grid stroke | `0.026 p` | 1.144 pt |
| Numeral size | `0.32 p`, clamp 13–20 | 14 pt |
| Strip height | `0.08 p + 0.887 s` | 16 pt (two strips = 32 pt) |
| Legal-destination dot | Ø `0.22 p` | 9.68 pt |
| Check rings | r `0.4325 p` / `0.4875 p`, stroke `0.025 p` | 19.03 / 21.45 pt, 1.10 pt |
| Keyboard focus square | `0.92 p`, stroke `0.04 p` | 40.48 pt, 1.76 pt |

---

## 1. What Apple publishes, and what is ours

**Found and citable** (all quotes from the pinned Xcode 27 beta documentation):

| Source | What it gives us |
|---|---|
| HIG > Accessibility > Vision | The exact WCAG AA table Accessibility Inspector uses: *"Up to 17 pts / All / 4.5:1"*, *"18 pts / All / 3:1"*, *"All / Bold / 3:1"*. Also *"Convey information with more than color alone"*, *"Support larger text sizes … enlarge text by at least 200 percent"*, and the custom-type minimums (iOS/iPadOS 17 pt default, 11 pt minimum; macOS 13 / 10). |
| HIG > Accessibility > Cognitive | *"Minimize use of time-boxed interface elements. Views and controls that auto-dismiss on a timer can be problematic … Prefer dismissing views with an explicit action."* Plus a Reduce Motion recipe that matches the contract's own rule almost word for word: *"Tightening animation springs to reduce bounce effects"*, *"Replacing transitions in x-, y-, and z-axes with fades to avoid motion"*. |
| HIG > Accessibility > Speech | *"Let people use the keyboard alone to navigate and interact with your app"*; **Support Switch Control**. |
| HIG > Buttons > Best practices | *"a button needs a hit region of at least 44x44 pt … to ensure that people can select it easily, whether they use a fingertip, a pointer, their eyes, or a remote."* |
| HIG > Motion > Best practices | *"Make motion optional. … it's essential to avoid using it as the only way to communicate important information."* |
| HIG > Feedback > Best practices | *"When you provide feedback using color, text, sound, and haptics, people can receive it whether they silence their device, look away from the screen, or use VoiceOver."* |
| HIG > Typography > Supporting Dynamic Type | *"Make sure your app's layout adapts to all font sizes"*; *"Increase the size of meaningful interface icons as font size increases"*; points at `UIContentSizeCategory.isAccessibilityCategory`. |
| HIG > Keyboards > Best practices | *"Support Full Keyboard Access when possible."* |
| HIG > VoiceOver > Descriptions / Navigation | Labels for all key elements; describe relationships that are visual only; *"Inform VoiceOver when visible content or layout changes occur"*; support the rotor. |
| `XCUIAccessibilityAuditType` + `XCUIApplication.performAccessibilityAudit(for:_:)` | Nine machine-checkable audit types: `action`, `contrast`, `dynamicType`, `elementDetection`, `hitRegion`, `parentChild`, `sufficientElementDescription`, `textClipped`, `trait`. Apple: *"If the UI test finds any audit issues, it automatically fails."* |
| Accessibility > Testing system accessibility features | The exact settings list a tester toggles: Differentiate Without Color, Invert Colors, Increase Contrast, Reduce Transparency, Reduce Motion, Full Keyboard Access (all platforms); Bold Text, Dynamic Type, Button Shapes, On/Off Labels, Grayscale (iOS). |
| Accessibility > Performing accessibility audits | Accessibility Inspector's Audits pane and its Color Contrast Calculator (⌥⌘C). Also the honest caveat: *"eliminating all audit issues that Accessibility Inspector reports doesn't guarantee a fully accessible app."* |

**Not found — stated plainly rather than invented:**

- **No Apple specification for how Liquid Glass renders under Reduce Transparency.** `interaction-design.md:53`
  already says this; my searches did not contradict it. The three-row table at `:46-51` is ours.
- **No Apple guidance for a board-game grid's accessibility model** — no page on element granularity for a game
  board, none on announcing a grid position. Confirms the prior survey.
- **No Apple threshold for "how much" Increase Contrast must raise a border or reduce a shadow.** Apple's only
  quantitative statement is the WCAG table; the rest is *"provides a higher contrast color scheme"*.
- **No Apple minimum for a non-text graphic's contrast.** The 3:1 figures in the contract (disc boundary, grid,
  record ink) are WCAG 1.4.11-shaped, not Apple-published. They are ours, and defensible, but a reviewer who
  asks "where does 3:1 for a grid line come from?" should be told "us", not "Apple".

---

## 2. The criteria

Each criterion is written so that a tester can return **pass**, **fail**, or **cannot check — value open**, and
nothing else. `[C]` = already fixed by an accepted contract and merely collected here. `[A]` = grounded in an
Apple citation from §1. `[US]` = ours, with the reasoning stated.

### A. Contrast

Measured with Accessibility Inspector's Color Contrast Calculator (⌥⌘C) or an equivalent WCAG calculator, in
light and dark appearance, **with shadows excluded**, at the smallest supported board size and at one large one.

| # | Criterion | Threshold | Source |
|---|---|---|---|
| **C-1** | Piece symbol against its own disc face, character or icon | ≥ 4.5:1 | `[C]` :96, `[A]` HIG Vision (symbol em is 22 pt at floor, but the contract sets the stricter 4.5:1 anyway) |
| **C-2** | Disc boundary (ring or edge stroke) against that style's own board surface, at a point away from any marking | ≥ 3:1 | `[C]` :97 |
| **C-3** | The style's named non-hue side channel: 现代's two fills against **each other** | ≥ 3:1 | `[C]` :93 |
| **C-4** | 传统's ring pair: heavier ring ≥ 2× the width of the lighter, **and** each ring against its own disc face | ≥ 2× width; ≥ 3:1 | `[C]` :94 |
| **C-5** | 高对比: filled-versus-outlined construction, no further ratio | structural | `[C]` :95 |
| **C-6** | Grid and palace diagonals against the style's own board surface | ≥ 3:1 | `[C]` :147 |
| **C-7** | Active marker ink against the board surface **and** against the pointer hover fill composited over it | ≥ 4.5:1 | `[C]` :143 |
| **C-8** | Record marker ink, same two backgrounds | ≥ 3:1 | `[C]` :143 |
| **C-9** | File numerals against the board surface | ≥ 4.5:1 | `[C]` :156 (14 pt at floor is below Apple's 17 pt line, so 4.5:1 is the right row of the HIG table) |
| **C-10** | File numerals under Increase Contrast | ≥ 7:1 | `[C]` :156 |
| **C-11** | Record ink under Increase Contrast, promoted to active values | ≥ 4.5:1 | `[C]` :143 |
| **C-12** | Every one of C-1…C-11 holds **jointly**, with resting shadows removed, in both appearances, under Increase Contrast, and with either symbol set selected | all of the above | `[C]` :98 |
| **C-13** | The keyboard focus ring against the style's own board surface | **open — see F2** | `[US]` |
| **C-14** | Custom glass surfaces: text and controls on each surface, in each of the four states of the `:46-51` table | ≥ 4.5:1 body, 3:1 for ≥ 18 pt or bold | `[A]` HIG Vision |

*Reviewer's note, and it is the important one:* C-1 through C-12 are complete, exact, and **currently
unverifiable**, because no piece style has concrete colour values — `interaction-design.md:517` is open. See
F11.

### B. Dynamic Type and text

| # | Criterion | Threshold | Source |
|---|---|---|---|
| **T-1** | Every string in the functional interface — turn status, controls, alerts, result card, move list, Settings, History rows, Help — scales with Dynamic Type across the full supported range | no truncation, no clipping, no overlap | `[A]` HIG Supporting Dynamic Type; `[C]` :449 as a stated obligation |
| **T-2** | The supported range is the platform's whole range: xSmall through AX5 on iOS/iPadOS | xSmall…AX5 | `[US]` — the contract names no range; the platform's own range is the only non-arbitrary answer |
| **T-3** | The board is **exempt** from Dynamic Type: disc, symbol and marker sizes derive from `p`, not from text size | exemption, stated | `[US]` — see F15; the contract implies it at :129 and never says it |
| **T-4** | At every Dynamic Type size, including AX5, the board still satisfies `p ≥ 44 pt` on every supported configuration | `p ≥ 44 pt` | `[C]` :129, :480, testing.md:58 — **cannot check**: the device list and minimum window are open (:514) |
| **T-5** | The numeral strips hide exactly when the system reports an accessibility text size, both together | `isAccessibilityCategory == true`, i.e. AX1 and above | `[C]` :151, :157 for the behaviour; `[A]` for the predicate; the exact threshold is open at :529 — see §4 |
| **T-6** | The `textClipped` and `dynamicType` audit types report zero issues on every screen | 0 issues | `[A]` `XCUIAccessibilityAuditType` |
| **T-7** | Behaviour under Bold Text is defined and honoured, including for the numeral strips whose semibold/bold pairing is tuned by measurement | defined either way | `[A]` Accessibility Inspector's settings list — **currently undefined, see F9** |

### C. The four accepted platform settings, plus the ones the contract does not name

| # | Criterion | Threshold | Source |
|---|---|---|---|
| **S-1** | Reduce Motion: everything that animates position, scale or rotation becomes a crossfade of ≤ 120 ms; opacity, colour, stroke weight and shadow animations are unchanged; surviving springs lose overshoot, not duration; ordering is untouched | ≤ 120 ms; every state survives | `[C]` :428; `[A]` HIG Cognitive's identical recipe |
| **S-2** | Reduce Motion: the check pulse is **removed**, not converted, while the double ring, the 将军 token and the illegal-tap response still deliver their states | pulse absent, states present | `[C]` :428 |
| **S-3** | Reduce Motion: a held piece still reads as raised; no state is lost anywhere | 0 lost states | `[C]` :418, :428 |
| **S-4** | Reduce Transparency: each of the three custom glass surfaces takes an opaque fill and a hairline separator; **position, size, corner radius and spacing are byte-identical to the default state** | 0 pt geometry delta | `[C]` :48, :53 |
| **S-5** | Increase Contrast: record ink promoted to active values; numerals to 7:1; glass keeps its material and raises its border; resting shadows reduced; geometry unchanged | see C-10, C-11; geometry 0 pt delta | `[C]` :49, :86, :143, :156 — **two of five sub-clauses are unquantified, see F10** |
| **S-6** | Reduce Transparency **and** Increase Contrast together: opaque fill *and* raised border, geometry unchanged | both, 0 pt delta | `[C]` :50 |
| **S-7** | Differentiate Without Color: every game-state marker renders **identically** with the setting on and off, the keyboard focus ring excepted | pixel-identical, one exception | `[C]` :143, testing.md:181 |
| **S-8** | Differentiate Without Color: Red and Black remain distinguishable in every style, with either symbol set, in both appearances | distinguishable by C-3/C-4/C-5 channel | `[C]` :92-95, :113 |
| **S-9** | Dark appearance: all of A and C hold | as above | `[C]` :51, :98 |
| **S-10** | Full Keyboard Access, Switch Control, Voice Control, Zoom and Invert Colors: behaviour defined, or an explicit non-support statement recorded | defined either way | `[A]` HIG Speech, Keyboards; Accessibility Inspector settings list — **currently absent, see F9** |

### D. VoiceOver — the part that is not 8.1's

The board's own model is 8.1's. These are the criteria that hold **regardless** of which model 8.1 chooses, and
they are what makes 8.1's answer checkable when it arrives.

| # | Criterion | Threshold | Source |
|---|---|---|---|
| **V-1** | Every actionable element has a localized, context-specific label. Decorative elements are hidden from assistive technology | `sufficientElementDescription` audit = 0 issues | `[A]` HIG VoiceOver > Descriptions |
| **V-2** | Every element's trait matches its behaviour; an element exposed as actionable is either actionable or reports that it is not | `trait` audit = 0 issues | `[A]` `XCUIAccessibilityAuditType.trait` — **violated in replay, see F14** |
| **V-3** | Reading order matches the visual reading order of the active language, and relationships that are visual only (row groupings, turn-status composition, metadata lines) are described | order verified per screen | `[A]` HIG VoiceOver > Navigation |
| **V-4** | Every operation available by gesture is available as a custom action or an equivalent: History Pin/Unpin, Share, Delete; Flip Board; every play control | 1:1 coverage | `[C]` :386, :218 |
| **V-5** | Every state change not visible in the currently focused element is announced: the last move, the AI's move, check, Undo, a result, a save failure, an import result, an insufficient-memory notice, a mid-game re-preparation failure | announcement exists and is localized | `[C]` :247, :249, :218, :386 name four of these with **no text written**; the rest come from parts 7.2/7.3/7.4 — **8.1 owns the texts** |
| **V-6** | Text that is game content and is never translated — the piece characters, the notation tokens, the move list, the Chinese file numerals — carries a **localized accessibility label** even though its visible form does not localize | label present in both languages | `[US]`, and it is the direct consequence of :71 + :74 — **see F5** |
| **V-7** | A user reading only with VoiceOver can reach the same information the numeral strips carry when the strips are hidden | equivalent exists | `[US]` — **see F7**; depends on 8.1 |
| **V-8** | The board is never described with two kinds of information at once; anything that is not a fact about the position is announced from the turn status | 0 violations | `[C]` :238 — this constrains 8.1 rather than depending on it |
| **V-9** | Pass condition for an end-to-end nonvisual game | **open — owner's, see §5** | testing.md:149 asserts it in a draft document |

### E. Keyboard and alternative input

| # | Criterion | Threshold | Source |
|---|---|---|---|
| **K-1** | Where keyboard input is supported, the select-piece / inspect-destinations / select-destination flow is completable without a drag gesture | complete game playable | `[C]` :233 |
| **K-2** | Keyboard focus on the board is the accepted focus marker at :253, and VoiceOver focus rides it rather than introducing a second focus concept | one focus concept | `[C]` :253; `[US]` for the "rides it" clause, which is 8.1's to confirm |
| **K-3** | Every operation reachable by pointer or gesture has a keyboard path on macOS and Windows: move input, Undo, Flip Board, draw claim, resign, result confirmation, replay transport, History Pin/Share/Delete, import/export | 1:1 coverage | `[C]` :386, :505, :506; `[A]` HIG Keyboards — **only Flip Board is named anywhere, see F9** |
| **K-4** | No custom shortcut overrides a system-defined one | 0 collisions | `[A]` HIG Accessibility > Speech |
| **K-5** | Focus never becomes trapped, and focus is visible at all times when driven from the keyboard | 0 traps | `[A]` HIG Focus and selection |

### F. Targets, geometry and layout

| # | Criterion | Threshold | Source |
|---|---|---|---|
| **G-1** | Every interactive board point's **hit region** is at least 44 × 44 pt | ≥ 44 × 44 pt | `[A]` HIG Buttons — **the contract fixes the pitch, not the hit region, see F6** |
| **G-2** | Every control outside the board has a hit region of at least 44 × 44 pt | ≥ 44 × 44 pt | `[A]` HIG Buttons |
| **G-3** | `hitRegion` audit reports zero issues on every screen | 0 issues | `[A]` `XCUIAccessibilityAuditType.hitRegion` |
| **G-4** | The pre-start preview is not interactive and is correctly excluded from G-1 | no touch targets | `[C]` :486 |
| **G-5** | No marker leaves its own `1 p` cell at rest or at any moment of any animation, including the check pulse's peak; a dragged piece is exempt only while dragged | containment | `[C]` :142, :248 |

### G. The sole-carrier rule

The contract states it three times — `:436` (*"must never be the only way information is conveyed"*), `:277`
(turn ownership, activity and input availability not by colour alone), `:451` (alternatives for sound, haptics,
animation) — and `testing.md:152` gates it. Made checkable:

**SC-1.** For every piece of information the interface must convey, at least **two independent carriers** exist,
drawn from: text, shape/structure, luminance, position-in-a-labelled-element, sound, haptics. Colour alone,
motion alone, sound alone, haptics alone, and *ordering alone* each fail.

**SC-2.** Enumerated, this is the table a tester walks. `[ok]` = passes as accepted; `[!]` = audit finding.

| Information | Carrier 1 | Carrier 2 | |
|---|---|---|---|
| Side to move | turn-status text :268 | — (text alone is sufficient; SC-1 wants two only where one is non-textual) | ok |
| Controller 你 / AI | secondary label text :269 | — | ok |
| Check, during play | double ring, shape :248 | 将军 token, text :271 | ok |
| Check, in replay | double ring, shape :249 | **none** | **[!] F4** |
| Selection | solid ring, shape :244 | lift + scale + shadow :244 | ok |
| Legal empty destination | filled dot, shape :245 | — | ok |
| Legal capture | dashed ring, shape :246 | — | ok |
| Last move | corner brackets, shape :247 | accessibility announcement :247 (**text unwritten**) | ok / open |
| Side identity Red vs Black | glyph (汉字) or style channel :92-95 | style channel always :73 | ok |
| Illegal tap, piece selected | destination pulse :250 | lightest haptic where hardware provides | ok |
| Illegal tap, nothing selected | turn-status opacity beat :250 | lightest haptic **where hardware provides — absent on Mac** | **[!] F3** |
| Input unavailable | turn-status opacity beat :258 | same haptic, same gap | **[!] F3** |
| Per-ply save failure | capsule text :257 | warning haptic | ok (but see F8) |
| Result | card title + reason text :340 | — | ok |
| Claimable draw | 可判和 affordance :352 | — | ok |
| History swipe action meaning | icon | text :387 | ok |
| History row: imported | "visible imported marker" :369, **form unconstrained** | none required | **[!] F13** |
| History row: **pinned** | **position in the list only** :368 | **none** | **[!] F1** |

### H. The automated floor

**AU-1.** `XCUIApplication.performAccessibilityAudit(for: .all)` runs on every distinct screen state and
reports zero issues, or each remaining issue is recorded with a written justification. Screen states, from the
accepted flows: Play with no active game; Play with an active game; both pre-start states; play (human turn);
play (AI thinking); play in check; result card before confirmation; result card after; threefold notice; replay;
History empty; History populated; History with the delete confirmation; Settings; Help; each accepted error
presentation. `[A]` — Apple's own caveat applies: passing the audit is a floor, not a pass.

**AU-2.** The audit runs at the default text size **and** at AX5, and in light and dark appearance.

**AU-3.** Manual verification with VoiceOver, Full Keyboard Access and Increase Contrast is required in addition
to AU-1, because Apple says explicitly that the audit does not guarantee accessibility.

---

## 3. The audit — where the accepted contracts fail these criteria

Ordered by how much it would cost to fix late. Every line reference is to
`MiniXiangqi/docs/interaction-design.md` unless stated.

### F1 — Pinned state is carried by list position alone `[fails SC-1]`

`:368` *"Pinned records appear before unpinned records."* `:369` lists the row's content: date, mode, result or
end reason, move count, human side, imported marker. **No pin indicator.** `product.md:58-59` and
`game-data.md:120-121` agree, and `game-data.md:145` serves the ordering with a partial index — so the data is
there and the row simply does not show it.

Consequence: a user reading rows one at a time with VoiceOver, or landing partway down the list, cannot tell a
pinned record from an unpinned one. The state is recoverable only by revealing the swipe action and reading
whether it says 置顶 or 取消置顶 — that is, by starting a gesture in order to learn a fact. Sorting order is a
relationship that is *visual only*, which is exactly what HIG > VoiceOver > Navigation says to describe.

Fix direction (designer's): add pin state to the accepted row content, or require it in the row's accessibility
value, or both. Cost is one row element. Cost of finding it after the History list is built is a re-layout.

### F2 — The keyboard focus ring is the only marker with no contrast requirement `[C-13 cannot be checked]`

`:253` *"in the platform's focus colour"*, and `:143` explicitly exempts it from the marker vocabulary: *"the
keyboard focus ring, which carries hue, is a platform affordance and never a game state."* Every other ink on
the board has a stated ratio against the style's own board surface. The focus ring has none — and it is the one
colour the app does **not** choose, because it follows the user's accent colour on macOS and the platform focus
colour elsewhere.

Concrete failure: a user with the yellow accent colour, on 传统's *"warm low-chroma board surface"* (`:82`), gets
a 1.76 pt outline (at the floor) whose contrast against the board is whatever those two happen to be. Graphite
accent on a neutral 现代 board is the other bad case. The contract's own reasoning — matching the platform is
worth more than vocabulary purity — is sound, but it does not make the ring visible.

Fix direction (designer's): state a floor (3:1 against the board surface is the consistent number) and require a
contrasting hairline or halo behind the ring when the platform colour does not reach it — which is what AppKit's
own focus ring does on coloured backgrounds. Or record an explicit, reasoned exception. Either is one sentence;
silence is not.

### F3 — Two accepted feedback states have no second carrier, and on macOS have no carrier at all `[fails SC-1]`

Two states deliberately have no board marker (`:255-258`):

1. **Illegal tap with nothing selected** (`:250`) — *"the turn status gives the acknowledgment beat"*, plus
   *"the platform's lightest selection-weight feedback … where the hardware provides it"*.
2. **Unavailable input** (`:258`) — *"its background rises to full emphasis and falls back, **in opacity only,
   with no movement**, plus the same lightest feedback as an illegal tap."*

On a Mac there are no haptics — the contract says so itself at `:250` (*"without depending on haptics that a Mac
does not have"*) and at `:438`. So on macOS the sole carrier of both states is an opacity pulse on one element.
No text, no shape change, no announcement. That is an effect being the only carrier, which `:436` forbids and
`testing.md:152` gates.

The contract's defence is at `:258`: *"The reason input is unavailable is always already on screen, so the beat
points at it rather than repeating it."* That defence is correct for the AI's turn and for a confirmed result.
**It fails in one case the contract does not join up:** `:426` says input arriving during a *committing*
transition is *"discarded rather than queued"*. During the player's own move animation the turn status still
reads 轮到红方 · 你, so nothing on screen says why the tap was refused. The contract never says whether the beat
fires there at all.

Fix direction (designer's): either name an explicit exception — an acknowledgment is not information and is
exempt from SC-1 — or give the beat a text or announced carrier. Note that `testing.md:183` already gates the
*selected*-piece case on a Mac and not the nothing-selected case, so the test suite has the same blind spot.

### F4 — In replay, check has one carrier `[fails SC-1; overlaps 8.1]`

`:271` *"Replay has no side-to-move line and therefore no token; there the board's own check treatment carries
it, which is sound because replay never holds a piece."* `:249` and `testing.md:186` confirm the rings are
always visible in replay.

Visually this is fine — the double ring is shape and luminance, not colour. The failure is for a screen-reader
user: the one state most likely to need calling out has no text anywhere on the replay screen, and the 将军
token that carries it during play is deliberately absent. This is 8.1's to solve (the replay board's announced
state), but it is 8.2's to *require*, and neither document currently does.

### F5 — Untranslated game content has no accessibility-label requirement `[V-6]`

`:71` *"Piece characters are game content, not interface text: they are identical in every supported language
and are never translated on the board."* `:116` says the same for icons. `:168` *"A user who selects icon
symbols still reads a character-based move list."* `:163` gives Red Chinese numerals and Black Arabic numerals
for **every number in a move**.

`:74` gets halfway there: *"English piece names are General, Chariot, Horse, Cannon, and Soldier. They appear in
help, accessibility announcements, and any descriptive text."* But nothing requires the **move list rows**, the
**file-numeral strips**, or the **board's own point descriptions** to carry those names. In an English build a
VoiceOver user reading the move list gets `前炮退二` handed to whatever voice the system picks.

This is not the same question as 6.7 (what an icon reader sees). 6.7 asks about the *visible* list; this asks
about the *spoken* one, and the answer can be yes here and no there without contradiction.

Fix direction (designer's, feeding part 6): require a localized accessibility label per move-list entry and per
numeral strip. The vocabulary already exists — `:74`'s piece names plus part 6's terminology work.

### F6 — The board's hit region is never stated `[G-1]`

Grep result: the strings *hit region*, *touch target*, *tappable* appear **nowhere** in `docs/`. The only
occurrence of "touch targets" is `:486`, about the preview *not* having any.

What is fixed is the **cell pitch**: `p ≥ 44 pt` (`:129`, `:480`, `testing.md:58`). What is drawn is a disc of
`0.80 p` = **35.2 pt** at the floor. If an implementer makes the disc the tappable region — the natural reading
of "tap the piece" — the accepted metric is satisfied and Apple's 44 × 44 pt floor is not, by 8.8 pt.

`:480` shows the intent (*"On iOS and iPadOS that is the platform's default control size"*), and `testing.md:58`
gates the pitch. It just is not written as a rule about the hit region, and a hit region is what
`XCUIAccessibilityAuditType.hitRegion` measures.

Fix direction: one sentence — the interactive region of a point is its full `1 p × 1 p` cell, so adjacent points'
regions tile the board without gaps or overlap. This is free now and is a re-plumb later.

### F7 — The numeral strips remove information with no equivalent, at exactly the wrong moment `[V-7, T-5]`

`:157` *"The strips are hidden at accessibility text sizes … The cost is real and accepted: without the strips a
reader cannot relate a move in the list to a file on the board without counting, which is a loss for the same
user the larger type was for."*

The contract states the cost honestly, which is why this is a *criterion* problem rather than a hidden defect.
But note the sharper version it does not state: a VoiceOver user is disproportionately likely to be at an
accessibility text size, so the population that loses the file labels overlaps heavily with the population that
most needs a spoken coordinate. Whether they get one is 8.1's answer, and 8.1 does not know it is load-bearing
here unless someone says so.

Three options, all cheap now: name it as an accepted exception; require the file to be recoverable through the
board's VoiceOver value; or hide the strips only when the layout genuinely cannot fit them, rather than at a
size threshold. The third is the only one that costs layout work, and it depends on `:514`, which is open.

### F8 — Two time-boxed presentations have no duration `[T-1, HIG Cognitive]`

- `:257` the save-failure capsule is *"transient"*. No duration.
- `:250` under Reduce Motion the illegal-tap response is *"a single step to a stronger appearance, **held
  briefly** and then restored."* No duration.

Every other timing in the motion section is exact to the millisecond — 120–160, 180–240, 250, 260, 300–400, 340,
500, 600. These two are the exceptions, and they are precisely the two that HIG > Accessibility > Cognitive
warns about: *"Views and controls that auto-dismiss on a timer can be problematic for people who need longer to
process information, and for people who use assistive technologies that require more time to traverse the
interface. Prefer dismissing views with an explicit action."*

A tester cannot check "transient" or "briefly". Fix direction (designer's): give both a value, and state whether
the capsule can be dismissed or re-read explicitly, and whether it is announced (which is 8.1's, but the
requirement is 8.2's).

### F9 — Whole settings and input modes are unaddressed `[T-7, S-10, K-3]`

Grep result across all of `docs/`: **Bold Text, Zoom, Switch Control, Voice Control, Full Keyboard Access,
Button Shapes, Invert Colors and Grayscale appear nowhere.** Dynamic Type appears exactly twice in accepted text
— `:449` as a thing the design *must consider*, and `:157` as the strip-hiding rule.

Three of these have real design consequences here:

- **Bold Text.** `:155` fixes the numeral strips by measurement: Chinese semibold against Arabic bold, anchored
  so that *"at regular weight the single stroke of 一 measures about 1.02 points against a 1.14-point grid
  line"*. Bold Text would either break that tuning or be silently ignored. One sentence decides which.
- **Full Keyboard Access.** HIG > Keyboards: *"Support Full Keyboard Access when possible."* On a 49-point board
  this is not a small commitment — it makes every point a focusable target — and the accepted focus marker at
  `:253` already presupposes something like it. The contract needs to say whether FKA drives the same focus
  model or is out of scope.
- **Switch Control.** HIG > Accessibility > Speech names it directly. The accepted tap-to-move alternative to
  drag (`:222`, `:233`) is most of what Switch Control needs, so this is probably cheap — but "probably" is not
  a criterion.

Also missing: `:386` says History rows expose *"keyboard commands"* without naming one, and `:218` names a
keyboard command for Flip Board and for nothing else in the app. K-3 therefore cannot be checked at all.

### F10 — Increase Contrast is specified for two of five contrast families `[S-5]`

Promoted: record ink → active values (`:143`); numerals 4.5 → 7:1 (`:156`). **Not** promoted, and not stated to
be unchanged: the symbol's 4.5:1 (`:96`), the disc boundary's 3:1 (`:97`), the side channel's 3:1 (`:93`), the
grid's 3:1 (`:147`). Two further clauses are qualitative rather than numeric: *"resting shadows are reduced"*
(`:86`) and *"raise the container's border"* (`:49`).

So a tester told to "verify Increase Contrast" has two numbers, one geometry invariant, and four silences plus
two unquantified verbs. Apple publishes no threshold for how much to raise a border, so the numbers are ours —
but "ours" still has to be written down.

Note this is not a case for raising everything: the default already meets HIG's table, so Apple's fallback
clause (*"ensure it at least provides a higher contrast color scheme when Increase Contrast is turned on"*) does
not bind. What is needed is the explicit statement that the four unpromoted families are **unchanged** under
Increase Contrast, plus values for the two verbs.

### F11 — Every contrast criterion is unverifiable today, and that should be said where the criteria live

`:102` *"The exact colour values, ring weights, and board surfaces are part of the open visual-system work"*, and
`:517` is the open item. `:145` says the same for marker ink.

C-1 through C-12 are therefore complete and 0 % checkable. This is not a defect in the criteria — it is the
single fact that determines when an accessibility gate can bind, and it interacts directly with 8.3's question
about whether `testing.md` can be accepted section by section. Whoever writes the criteria into a contract
should write this sentence beside them rather than leaving a reviewer to discover it.

### F12 — The pointer hover fill's alpha is load-bearing and unfixed `[C-7, C-8]`

`:252` *"a faint rounded-square fill … in marker ink at low opacity"*. No value. But `:143` requires active and
record ink to reach their ratios *"against the pointer hover fill composited over it"* — so the fill's alpha is
an input to two accepted measurements and is itself never fixed. A tester cannot perform C-7 or C-8 on a hovered
point without it.

Secondary, and minor: Reduce Transparency's accepted table (`:46-51`) covers the three custom glass surfaces and
system surfaces. The hover fill is a low-alpha fill in the *content* layer, not a material, so it is arguably out
of Reduce Transparency's scope entirely (Apple describes the setting as *"reducing transparency and blur effects
on certain backgrounds"*). I think that is the right answer — but a reviewer will ask, and the contract should
say it rather than leave the omission to be read as an oversight.

### F13 — The imported marker's form is unconstrained `[SC-2]`

`:369` *"imported records have a visible imported marker."* That is the only requirement. It is the one History
row element that could plausibly ship as an icon alone, or as a tinted dot, and it carries provenance —
`game-data.md:52` treats provenance as real metadata. One clause fixes it: the marker carries text or a
localized accessibility label, not colour or shape alone.

### F14 — Elements that are exposed but inert `[V-2]`

`:258` *"In replay the board is a read-only document, and a tap on it does nothing at all — no beat and no
feedback — because any response would imply an interactivity that deliberately does not exist there."* And
during play, `:258` again: *"The board is never dimmed while the AI is thinking or after a result is
confirmed."*

Both are right visually. Neither says what an assistive technology is told. If the replay board's points are
exposed as accessibility elements with an actionable trait and activating one does nothing, a VoiceOver or
Switch Control user cannot distinguish "read-only by design" from "the app has hung" — and
`XCUIAccessibilityAuditType.trait` exists to catch exactly that mismatch. Same for the never-dimmed board while
input is unavailable: the visual decision is deliberate, so the *non*-visual channel has to carry the state
instead.

The resolution is 8.1's (traits and announced state on the board). The requirement — V-2 — is 8.2's, and belongs
in the criteria whichever model 8.1 picks.

### F15 — The board's Dynamic Type exemption is real, defensible, and unstated `[T-3]`

Every board dimension is a multiple of `p` (`:129`); nothing on the board responds to text size except the
strips vanishing. At AX5 the interface text around the board roughly triples while the 22 pt piece symbols do
not move at all. HIG > Typography: *"Increase the size of meaningful interface icons as font size increases."*
The piece symbols are the most meaningful glyphs in the app.

I think the contract's position is correct — the board is content, sized by its own 44 pt floor and by the
largest square that fits, and scaling pieces with text size would fight the geometry that the whole marker
vocabulary is derived from. But it is an **exemption**, it is nowhere stated, and a reviewer running the
`dynamicType` audit will raise it. State it, with the reason, and pair it with T-4 (the floor must survive AX5)
so the exemption is bounded rather than open-ended.

### F16 — No accessibility gate currently binds

`testing.md:5`: *"Nothing in this document is normative until its status or an individual section is explicitly
marked accepted."* Its UI/accessibility section (`:147-190`) already contains about forty verifications derived
from the accepted paragraphs — including `:152`, the sole-carrier gate that F1, F3, F4 and F13 fail against.
None of them binds.

This is 8.3's decision and I am not taking it. It is recorded here because it changes what "accepted criteria"
would *mean*: criteria written into `interaction-design.md` are accepted design; criteria written into
`testing.md` today are not accepted anything. See §4.

---

## 4. Where the criteria should live

The bullet at `:532` sits in `interaction-design.md`, and `testing.md:211`-adjacent verifications already exist.
Three options; I recommend the third.

1. **All in `interaction-design.md`.** Criteria are design commitments and become accepted immediately. But the
   document is already 538 lines and the thresholds are mostly restatements of numbers three sections above.
2. **All in `testing.md`.** Natural home for a checklist. But nothing there binds until 8.3 resolves, so
   accepting the criteria there accepts nothing.
3. **Split by kind.** `interaction-design.md` gains only what is a *design* decision and does not exist anywhere
   yet — the sole-carrier rule stated as SC-1 with its enumerated exceptions, the hit-region rule (F6), the
   Dynamic Type exemption (T-3), the Increase Contrast completion (F10), the focus-ring ratio (F2), the
   accessibility-label rule for untranslated content (V-6), and the Bold Text / FKA / Switch Control positions
   (F9). `testing.md` gains the *procedure*: the audit matrix (AU-1's screen-state list), the settings matrix,
   the measurement instrument, and the pass/fail form. Nothing is written twice; each document gets the half it
   owns by its own scope line.

Under option 3, the fix for F1, F3, F4, F13 and F14 lands as edits to the accepted behaviour sections rather
than as new criteria — which is the right outcome, because those five are defects in the design, not gaps in
the testing.

---

## 5. Open for the owner

Only the choices that genuinely need the product owner, each with its options and what each costs.

### O-1. What accessibility bar does the product claim?

The accepted numbers (4.5:1 / 3:1 / 7:1) are WCAG AA-shaped and match the table Accessibility Inspector uses.
Whether the product *claims* conformance is a statement, not a design.

- **"We meet these specific numbers."** Zero extra work; every criterion above is already written this way. No
  external standard to be held to, and no external standard to point at either.
- **"WCAG 2.2 Level AA."** Buys a recognised name. Costs the success criteria the contract has not looked at —
  focus visibility (F2 becomes mandatory, not optional), target size, reflow, and status messages (F3 becomes a
  failure, not a discussion). Someone has to read the standard and audit against all of it, not just contrast.
- **Apple's Accessibility Nutrition Labels.** Apple documents them for App Store Connect; distribution here is
  internal only (`product.md:14`), so this is a claim with no audience unless that changes. Mentioned for
  completeness rather than recommended.

### O-2. Is an end-to-end nonvisual game a supported capability or a best effort?

`testing.md:149` already asserts *"an end-to-end nonvisual board interaction"* — in a draft document, so nothing
is committed. **This is the same question 8.1 raises; answer it once.** It belongs here because it is the pass
condition for V-9 and because it sizes everything in §D.

- **Supported.** Every VoiceOver criterion becomes a release gate, and 8.1's model has to be complete and
  tested before the first internal build ships. For a Xiangqi teaching app used by a small internal group, the
  honest question is whether anyone in that group will use it.
- **Best effort.** V-1 through V-4 still bind (they are cheap and Apple-audited); V-5 through V-9 become
  aspirations. Cost: the app is not usable without sight, and saying so is better than implying otherwise in a
  document nobody re-reads.

The middle answer — supported on the board and on History, best effort in Help and Settings — is not available:
those are the easy surfaces and the board is the hard one.

### O-3. Which alternative input modes are supported? (F9)

Full Keyboard Access, Switch Control and Voice Control each need a yes or no.

- **Full Keyboard Access on iPad and Mac.** The accepted focus marker (`:253`) and the accepted
  select/inspect/select flow (`:233`) already presuppose most of it, so marginal cost is moderate — but it makes
  49 board points focusable targets and interacts with 8.1's element-granularity choice. Saying no costs a
  keyboard-only user the board entirely on iPad.
- **Switch Control.** Probably nearly free, because tap-to-move already exists as the drag alternative. "Nearly
  free" is worth one sentence of confirmation and no more.
- **Voice Control.** Requires every board point to have a speakable name, which means committing to a spoken
  coordinate scheme — traditional per-side, or canonical `a1`–`g7`. That is a real decision and it collides with
  8.1 and with part 6's terminology. Saying no here is defensible.

### O-4. The numeral-strip trade (F7)

The strips hide exactly when type grows, and the contract already accepts the information loss.

- **Keep it as a named exception.** Free. A low-vision user at AX1+ loses file labels and the contract says so.
- **Require an equivalent through VoiceOver.** Costs 8.1 one design decision (a coordinate in the point's value)
  and nothing in layout. Helps only users who run VoiceOver, which is not the same population.
- **Hide the strips only when the layout genuinely cannot fit them.** Costs real layout work and depends on
  `:514`, which is open. Helps the actual affected user, at the price of a size-dependent behaviour that is
  harder to test than a threshold.

### O-5. Does Windows meet the same bar? (`:536`)

`:506` requires equivalent operations through each platform's conventions, and `:536` defers Narrator and high
contrast until the Windows frontend exists. Two readings, and the owner picks:

- **The criteria are platform-neutral and Windows must meet all of them**, with Narrator substituted for
  VoiceOver. Costs a Windows accessibility design that nobody can start yet, and makes every criterion above
  gate a platform that does not exist.
- **The criteria are Apple-platform criteria today**, with a stated commitment that Windows will be held to an
  equivalent bar written when its frontend is designed. Costs an explicit statement that the two platforms are
  not yet at parity — which is true, and is better said than discovered.

### O-6. Do the criteria bind before `testing.md` is accepted? (F16)

Strictly 8.3's question, framed here only because §4's recommendation depends on the answer and the two
researchers should not answer it differently. If option 3 in §4 is taken, the design half of the criteria binds
immediately as accepted interaction design regardless of `testing.md`'s status — which is, I think, the reason
to prefer option 3.

---

# Independent review

Adversarial verification by a second agent. Method: re-read all eight contracts at
`MiniXiangqi/docs/`; re-ran every grep the report claims; re-checked every one of the ~90 line references
in the report against the file; re-queried the pinned Xcode 27 beta documentation for every Apple citation
(`mcp__xcode__DocumentationSearch`, eleven queries). Findings are ordered by severity. Nothing under
`MiniXiangqi/` was modified; no git or `gh` write was performed.

**What survived.** The line references are, with the two exceptions noted at R9 and R17, accurate: I checked
every `:NNN` citation individually and the quoted text matches. The recomputed board metrics table is correct
at `p = 44` (I recomputed independently: `7p = 308`, `0.80p = 35.2`, `0.50p = 22`, `0.026p = 1.144`,
`0.32p = 14.08 → 14`, `0.08p + 0.887×14 = 15.94 → 16`, `0.22p = 9.68`, `0.4325p/0.4875p = 19.03/21.45`,
`0.92p = 40.48`, `0.04p = 1.76`). The following Apple citations are **verbatim correct**: HIG Accessibility >
Vision (the WCAG AA table, "Convey information with more than color alone", the 200 percent clause, the
17/11 and 13/10 custom-type minimums, the Increase Contrast fallback clause); HIG Accessibility > Cognitive
(the time-boxed paragraph and the Reduce Motion recipe); HIG Accessibility > Speech (keyboard alone, *and*
"Avoid overriding system-defined keyboard shortcuts", so K-4's attribution is right); HIG Buttons > Best
practices (44x44 pt hit region); HIG Motion > Best practices ("Make motion optional"); HIG Feedback > Best
practices; HIG Typography > Supporting Dynamic Type; HIG Keyboards > Best practices; HIG VoiceOver >
Descriptions and > Navigation; `XCUIAccessibilityAuditType`'s nine types plus `all`; "If the UI test finds any
audit issues, it automatically fails"; "eliminating all audit issues … doesn't guarantee a fully accessible
app"; the Accessibility Inspector Settings-pane list; and Accessibility Nutrition Labels in App Store Connect
help. Findings F1, F5, F6, F10, F11, F12, F13, F16 are real and correctly grounded. That is the base the
findings below sit on.

---

## Blocking

### R1 — SC-1 as written fails two markers that SC-2 passes `[correctness; the central proposal]`

**Quoted.** SC-1 (`:179-181`): *"For every piece of information the interface must convey, at least **two
independent carriers** exist, drawn from: text, shape/structure, luminance, position-in-a-labelled-element,
sound, haptics."* SC-2 (`:192-193`): *"Legal empty destination | filled dot, shape :245 | — | ok"*; *"Legal
capture | dashed ring, shape :246 | — | ok"*.

**What is wrong.** Those two rows carry one non-textual carrier and an explicit em-dash for the second, and
are marked `ok`. The only exemption the table states is the one on the "Side to move" row — *"text alone is
sufficient; SC-1 wants two only where one is non-textual"* — and neither a filled dot nor a dashed ring is
text. Under SC-1 exactly as written, both fail. So the report's own enumeration contradicts its own rule at
two rows, and it is the rule the report asks to be written into an accepted contract (proposal 2, proposal 11).
A tester handed SC-1 and SC-2 together gets two different answers for the same marker.

**Severity: blocking.** SC-1 is the one genuinely new normative sentence the report proposes; it cannot ship
with a counterexample inside its own worked table.

**Correction.** State the shape exemption explicitly and symmetrically — e.g. *"a marker whose shape is unique
within its family and whose ink is at an accepted contrast ratio carries two channels, shape and luminance,
and satisfies SC-1 alone"* — and then re-walk the table under that wording, because it changes F3's verdict
too (see R2).

### R2 — SC-1's carrier taxonomy does not discriminate: any reading that fails F3 also fails the legal-destination dot `[correctness]`

**Quoted.** SC-1 lists *"text, shape/structure, luminance, position-in-a-labelled-element, sound, haptics"* as
independent carriers, and F3 (`:260-272`) concludes that on macOS *"the sole carrier of both states is an
opacity pulse on one element."*

**What is wrong.** An opacity beat on the turn-status element has, by SC-1's own list, **two** carriers:
luminance (the opacity change) and position-in-a-labelled-element (it happens on the turn status, which
`:272` designates as the element that carries exactly this class of message). If those count, F3 passes. If
they do not count — if a transient luminance change on a labelled element is one carrier — then the filled
destination dot, which is shape plus a luminance-defined ink, is also one carrier and fails. The taxonomy has
no rule for when shape-and-luminance are one channel or two, and the report applies it in opposite directions
on adjacent rows without saying so. This is the same defect as R1 seen from the other end, and it is why R1's
correction must be written before F3's verdict can be trusted.

**Severity: blocking.** F3 is one of the five "defects in accepted behaviour" the report asks the main thread
to fix by editing `interaction-design.md`. The evidence for it is not yet sound.

**Correction.** Define independence, not just enumerate channels: two carriers are independent when a single
user condition (colour blindness, no haptic hardware, haptics off, Reduce Motion, no sight) can remove one and
leave the other. Under that definition F3 survives on the *sound* ground given at R3, and the destination dot
passes, and the rule becomes checkable instead of nominal.

### R3 — F3 is under-scoped: the haptic carrier disappears on every platform, not only on macOS `[under-claim; missed defect]`

**Quoted.** F3 (`:270`): *"On a Mac there are no haptics … So on macOS the sole carrier of both states is an
opacity pulse on one element."* SC-2 (`:196`): *"Illegal tap, piece selected | destination pulse :250 |
lightest haptic where hardware provides | ok"*.

**What is wrong.** Two things. First, `interaction-design.md:438` — which the report cites — says *"Both are
user-controllable through separate Settings toggles"*, and `product.md:81` confirms *"a sound toggle and a
separate haptics toggle"*. A user who turns haptics off on an iPhone is in exactly the position F3 describes
for a Mac. The failure is therefore not platform-specific, it is *setting*-specific, and it is reachable on
every device the app ships to. That is a strictly stronger finding than the one the report made, and the
report had both citations in hand.

Second, the row at `:196` carries the identical caveat — *"lightest haptic where hardware provides"* — and is
marked `ok` while the row immediately below it is marked `[!] F3`. The stated difference (destination pulse
versus turn-status beat) is not a difference in the haptic carrier at all. With haptics off, the piece-selected
case is a pulse alone, and SC-1 says *"motion alone … fails"*.

**Severity: blocking.** It changes both the size of the finding and which rows of SC-2 are defective.

**Correction.** Rewrite F3 as: *the lightest-selection-weight haptic is not a carrier for SC-1 purposes,
because the user can remove it from Settings on every platform and the hardware removes it on some.* Then
re-mark `:196` as failing too, or give the pulse an independent second carrier. The macOS observation becomes
an aggravating case, not the case.

### R4 — "On a Mac there are no haptics" is false, and Apple publishes the correct ground `[MISQUOTED / factual]`

**Quoted.** F3 (`:270`): *"On a Mac there are no haptics — the contract says so itself at `:250` … and at
`:438`."*

**What is wrong.** macOS has haptics. Apple publishes `NSHapticFeedbackManager` — *"An object that provides
access to the haptic feedback management attributes on a system with a Force Touch trackpad"* (AppKit >
Mouse, Keyboard, and Trackpad > Trackpad) — and `NSHapticFeedbackPerformer.perform(_:performanceTime:)`. HIG >
Playing haptics > macOS states it in design terms: *"When a Magic Trackpad is available, your app can provide
one of the three following haptic patterns in response to a drag operation or force click"* (Alignment, Level
change, Generic). Also note that `:438` does not say a Mac has no haptics; it says haptics are available only
where the hardware provides them. Only `:250`'s parenthetical asserts it, and that assertion is wrong as a
general statement about Macs.

What *is* true, and is the citable ground the report should have used: Apple scopes macOS haptics to *"a drag
operation or force click"*, so an ordinary click on an illegal point is outside every documented macOS haptic
pattern, and `NSHapticFeedbackPerformer` carries *"Do not use it to provide feedback for events that are not
user initiated"* plus a warning against excessive use. The conclusion survives; the premise does not.

**Severity: blocking for the citation, not for the conclusion.** The report's mandate says never fabricate a
citation and own the recommendation; here it inherited a wrong factual claim from accepted text and repeated
it as established rather than auditing it, which is the one thing this part was asked to do.

**Correction.** Replace the premise. State that macOS haptic feedback exists but is documented only for drag
and force-click, that the app's illegal-tap event is neither, and that `interaction-design.md:250`'s
parenthetical *"haptics that a Mac does not have"* is itself a factual error in accepted text and should be
corrected to *"haptics a Mac does not provide for this class of event"*. That is a sixth defect in accepted
behaviour, and the report did not find it.

### R5 — T-6, V-2, AU-1 and AU-2 cannot be performed on macOS as written `[criteria unperformable on a supported platform]`

**Quoted.** T-6 (`:118`): *"The `textClipped` and `dynamicType` audit types report zero issues on **every
screen**"*. V-2 (`:144`): *"`trait` audit = 0 issues"*. AU-2 (`:215`): *"The audit runs at the default text
size **and** at AX5, and in light and dark appearance."*

**What is wrong.** Apple splits the audit types by platform. *Performing accessibility audits for your app >
All platforms*: Element description, Hit region, Contrast, Element detection. *> macOS*: Parent/child, Action.
*> iOS, watchOS, and tvOS*: **Clipped text, Traits, Dynamic Type**. So on macOS — a first-class supported
platform per `product.md:21` — `dynamicType`, `textClipped` and `trait` do not exist, and
`performAccessibilityAudit(for: .all)` silently does not run them. T-6 and V-2 are unperformable there, and
V-2 is the criterion the report uses to carry F14, which it says applies to *"the replay board and the
never-dimmed board"* — i.e. to the Mac as much as to iPhone.

Separately, HIG > Typography > Supporting Dynamic Type opens *"Dynamic Type is a system-level feature in iOS,
iPadOS, tvOS, visionOS, and watchOS"* — macOS is absent. There is no AX5 on a Mac. `interaction-design.md:482`
knows this and uses the right term, *"the largest-text setting on a current Mac"*, which is a display-scaling
setting, not Dynamic Type. T-2, T-4 and AU-2 conflate the two.

**Severity: blocking.** Three criteria and the automated floor return "cannot check" on a supported platform
for a reason the report does not record, and F14's evidence base shrinks to iOS/iPadOS.

**Correction.** Mark T-6 and V-2 iOS/iPadOS-only, and give macOS its own line naming `parentChild` and
`action`. Split T-2/T-4/AU-2 into a Dynamic Type axis (iOS/iPadOS, xSmall…AX5) and a macOS display-scaling
axis (the `:482` configuration). Say plainly that F14's `trait` argument is not machine-checkable on macOS and
needs a manual VoiceOver pass there.

### R6 — G-2 is stricter than Apple on macOS, and F6's "8.8 pt" is an iOS figure presented as universal `[MISQUOTED by omission]`

**Quoted.** G-2 (`:168`): *"Every control outside the board has a hit region of at least 44 × 44 pt | ≥ 44 × 44
pt | `[A]` HIG Buttons"*. F6 (`:321`): *"the accepted metric is satisfied and Apple's 44 × 44 pt floor is not,
by 8.8 pt."*

**What is wrong.** §1's "Found and citable" table omits **HIG > Accessibility > Mobility**, which is the single
most on-point Apple page for the report's whole §F group and publishes a table the report's numbers must be
read against:

| Platform | Default control size | Minimum control size |
|---|---|---|
| iOS, iPadOS | 44x44 pt | 28x28 pt |
| macOS | 28x28 pt | 20x20 pt |

Consequences. (a) G-2 as written, tagged `[A]`, would fail every standard macOS push button, toolbar item and
segmented control in the app — Apple's own macOS default is 28x28 — while claiming Apple's authority for
doing so. (b) F6's 35.2 pt disc clears both the macOS default and the macOS minimum; the "misses by 8.8 pt"
gap exists on iOS and iPadOS only. (c) The same page carries *"Consider spacing between controls as important
as size … about 12 points of padding"* and *"Offer alternatives to gestures"*, both directly relevant to G-2
and to the accepted tap-to-move alternative at `:222`, and *"Support mobility-related assistive technologies.
Features like VoiceOver, AssistiveTouch, Full Keyboard Access, Pointer Control, and Switch Control"*, which is
the cleanest Apple grounding for F9 and O-3 and is not cited.

**Severity: blocking for G-2, substantive for F6.** F6's fix direction (the interactive region is the full
`1 p × 1 p` cell) is right and unaffected — at `p ≥ 44` it satisfies every row of Apple's table on every
platform. The *argument* for it is what needs correcting.

**Correction.** Add HIG > Accessibility > Mobility to §1. Restate G-2 as 44x44 on iOS/iPadOS and *"the
platform's default control size, and never below its stated minimum"* on macOS. In F6, say the shortfall is
8.8 pt against the iOS/iPadOS default; on macOS the disc clears Apple's figures and the case for the cell-sized
hit region there is uniformity and `hitRegion`-audit cleanliness, not an Apple floor.

### R7 — "Accessibility Inspector's Color Contrast Calculator (⌥⌘C)" — NOT FOUND `[citation]`

**Quoted.** §A (`:85`): *"Measured with Accessibility Inspector's Color Contrast Calculator (⌥⌘C) or an
equivalent WCAG calculator"*. §1 (`:61`) lists it under *"Accessibility > Performing accessibility audits"*.

**What is wrong.** Four separate searches of the pinned documentation returned no page naming a "Color Contrast
Calculator" and no `⌥⌘C` shortcut. *Performing accessibility audits for your app* documents the Audits pane,
the target menu, the Run Audit button, the Options menu and fix suggestions — no calculator. *Inspecting the
accessibility of the screens in your app* documents the Inspection pane and names exactly two shortcuts,
Option-Space to toggle inspection mode and Control-Command-arrow to navigate. *Accessibility Inspector*
(overview) says only that the tool checks *"appropriate text size and color contrast levels"*. The report's own
method (`:22`) states *"Every citation below is quoted from what came back"*; this one did not.

**Severity: blocking.** It is the named measuring instrument for fourteen criteria and for proposal 11's
"instrument" line. A tester told to press a keystroke that may not exist is being told something the report
cannot support.

**Correction.** Either produce the page, or replace the instrument with what the pinned documentation does
support: the Audits pane's Contrast audit, `performAccessibilityAudit(for: .contrast)`, and an external WCAG
calculator applied to the style's declared colour values. Note plainly that the machine contrast audit checks
*"overlapping elements"*, which will not by itself measure a grid line against a board surface — that stays a
manual measurement.

### R8 — K-5 imports two WCAG criteria under an Apple label `[MISQUOTED]`

**Quoted.** K-5 (`:161`): *"Focus never becomes trapped, and focus is visible at all times when driven from the
keyboard | 0 traps | `[A]` HIG Focus and selection"*.

**What is wrong.** HIG > Focus and selection > Best practices contains five bullets: *"Rely on system-provided
focus effects"*, *"Avoid changing focus without people's interaction"*, *"Be consistent with the platform as
you help people bring focus to items in your app"*, *"Indicate focus using visual appearances that are
consistent with the platform"*, and *"In general, use a focus ring for a text or search field, but use a
highlight in a list or collection."* Neither a keyboard trap nor persistent focus visibility appears anywhere
on the page or in its iPadOS/tvOS/visionOS subsections. Both are WCAG 2.2 criteria — 2.1.2 No Keyboard Trap
and 2.4.7 Focus Visible.

This matters beyond the tag, because O-1 (`:507-509`) argues that choosing WCAG AA *"costs the success
criteria the contract has not looked at — focus visibility …"*. K-5 has already quietly adopted focus
visibility and keyboard trapping as `[A]` criteria, which pre-empts the option O-1 asks the owner to decide.

**Severity: blocking.** A misattributed citation inside a criterion set that is being proposed for a contract,
and it contradicts the report's own framing of the owner's choice.

**Correction.** Retag K-5 `[US]` with WCAG 2.1.2 / 2.4.7 named as its shape, exactly as §1 does honestly for
the 3:1 non-text figures. Then say in O-1 that K-5 is the one place the criteria already reach past Apple, so
option (a) needs it retagged or dropped.

---

## Substantive

### R9 — "Dynamic Type appears exactly twice in accepted text" — it appears once `[exact value wrong]`

**Quoted.** F9 (`:365-366`): *"Dynamic Type appears exactly twice in accepted text — `:449` as a thing the
design *must consider*, and `:157` as the strip-hiding rule."*

**What is wrong.** `grep -rn -i "dynamic type" docs/` returns exactly one hit, `interaction-design.md:449`.
Line 157 reads *"The strips are hidden at **accessibility text sizes**"* — a different phrase, which is
precisely the report's own point at T-5 and proposal 6, where it argues the wording is *"accessibility text
sizes"* and maps it onto `isAccessibilityCategory`. Counting that line as a "Dynamic Type" occurrence
contradicts the report's own reading of it three sections earlier. (For completeness: `accessibility text
size(s)` occurs at `:157`, `:515` and `:529` in `interaction-design.md` and at `testing.md:167`.)

**Severity: substantive.** The report offers exact counts so they can be disagreed with exactly; this one is
wrong, and it weakens the true and more striking version — Dynamic Type is named **once** in eight contracts,
in a bullet that only says the design must consider it.

**Correction.** "Dynamic Type appears exactly once in accepted text, at `:449`. The strip-hiding rule at `:157`
uses a different phrase, `accessibility text sizes`, which is why T-5 needs a predicate rather than a lookup."

### R10 — F1 says two contracts "agree"; they differ on whether the row list is closed `[over-claim]`

**Quoted.** F1 (`:230-231`): *"`:369` lists the row's content: date, mode, result or end reason, move count,
human side, imported marker. **No pin indicator.** `product.md:58-59` and `game-data.md:120-121` agree"*.

**What is wrong.** `product.md:59` reads *"Each History entry identifies **at least** its date, mode, result or
end reason, and move count"*. "At least" makes that list a floor, not a closed set: a visible pin indicator is
already permitted by `product.md` without any contract change. `interaction-design.md:369` has no such
qualifier (*"Each entry shows its date, mode …"*), so the two documents are not in agreement — one is open and
one reads closed. That difference is the whole question of whether F1 is a defect in accepted behaviour or a
design gap inside an accepted envelope, and the report resolves it by asserting agreement.

`game-data.md:121` is a third case again: it enumerates the *queryable summaries* and does not include pin
state, though pin state is stored and indexed (`:119`, `:144`, `:145`), so the data is available as the report
says.

**Severity: substantive.** F1 is the report's headline finding and is listed under "five defects in accepted
behaviour". On `product.md`'s wording it is a gap, not a contradiction, and that changes what the main thread
has to write.

**Correction.** State the difference. The defect is that `interaction-design.md:369` reads as a closed list
while `product.md:59` says "at least"; the fix is one sentence in `:369` plus the accessibility-value
requirement, and it is additive rather than a reversal.

### R11 — F15 quotes the HIG line against the exemption and omits the one for it, and misstates what the dynamicType audit does `[one-sided citation]`

**Quoted.** F15 (`:451-457`): *"HIG > Typography: 'Increase the size of meaningful interface icons as font size
increases.' The piece symbols are the most meaningful glyphs in the app. … a reviewer running the
`dynamicType` audit will raise it."*

**What is wrong.** Two omissions. (a) HIG > Typography > **Conveying hierarchy** publishes the counter-guidance
the exemption rests on, and names games specifically: *"Prioritize important content when responding to
text-size changes. Not all content is equally important. When someone chooses a larger text size, they
typically want to make the content they care about easier to read; they don't always want to increase the size
of every word on the screen. … in a game, people are often more interested in a character's dialog than in
transient hit-damage values."* That is a citable Apple basis for a bounded exemption; the report presents the
position as ours against Apple's grain, and §1 does not list this page.

(b) Apple describes the audit as *"**Dynamic Type**. This test checks whether the **text** in your app supports
Dynamic Type"* (Performing accessibility audits > iOS, watchOS, and tvOS). Board glyphs drawn as content, with
no text label, are not what it inspects — and per R5 it does not run on macOS at all. So the stated consequence
"a reviewer running the dynamicType audit will raise it" is unsupported.

**Severity: substantive.** F15's conclusion (state the exemption, bound it with T-4) is right, and would be
better supported, not worse, by fixing this.

**Correction.** Cite HIG Typography > Conveying hierarchy as the Apple basis for the exemption, keep
"Increase the size of meaningful interface icons" as the tension it must answer, and drop the audit claim in
favour of the real reason: an undeclared exemption is indistinguishable from an oversight to a human reviewer.

### R12 — "exact to the millisecond" is not what the motion section says `[over-claim inside its own paragraph]`

**Quoted.** F8 (`:352-353`): *"Every other timing in the motion section is exact to the millisecond — 120–160,
180–240, 250, 260, 300–400, 340, 500, 600."*

**What is wrong.** The list contradicts the claim in the same sentence: 120–160, 180–240 and 300–400 are
ranges, and the contract introduces each with *"approximately"* (`:408`, `:411`, `:417`). `:432` further says
*"Easing curves, shadow, opacity, and feedback strength are first-version values subject to adjustment"*, and
`:528` records a Need-to-discuss item to confirm the timings on hardware. So the section is a mixture of exact
values (340, 260, 500, 250, 600, and the seven per-distance figures at `:420`) and accepted approximate bands.

**Severity: substantive.** F8's real point — that "transient" and "held briefly" are the only two presentations
with no number at all, exact or banded — is correct and untouched. The rhetorical overstatement is the kind of
claim that does not survive its own paragraph, which is what this review was asked to catch.

**Correction.** "Every other timing in the motion section carries a number, exact or as an accepted band; these
two carry none."

### R13 — C-9 picks the wrong row of Apple's table for the bold Arabic digits, and does not audit `:156` for the same slip `[missed defect]`

**Quoted.** C-9 (`:98`): *"`[C]` :156 (14 pt at floor is below Apple's 17 pt line, so 4.5:1 is the right row of
the HIG table)"*. And `interaction-design.md:156`: *"They are text at 14 points at the floor, **below the size
at which a 3:1 ratio would suffice**, so the record-ink gate that governs the last-move brackets does not apply
to them."*

**What is wrong.** Apple's table has three rows, not two:

| Text size | Text weight | Minimum contrast ratio |
|---|---|---|
| Up to 17 pts | All | 4.5:1 |
| 18 pts | All | 3:1 |
| **All** | **Bold** | **3:1** |

`interaction-design.md:155` sets the Arabic digits **bold** and the Chinese numerals semibold. By Apple's third
row, the bold digits would satisfy the table at 3:1 at any size, so the accepted justification at `:156` — that
14 pt is *"below the size at which a 3:1 ratio would suffice"* — is wrong for half the numerals, and C-9
reproduces it. The 4.5:1 requirement itself is fine and stricter than Apple; only the stated reason is wrong,
and stating a wrong reason in accepted text is exactly the class of thing this part was asked to audit.

**Severity: substantive.** No threshold changes; a reasoning error in accepted text goes unrecorded.

**Correction.** C-9's source note should read: *the contract sets 4.5:1 deliberately, which is stricter than
Apple's table for the bold digits (row 3 would allow 3:1) and matches it for the semibold Chinese numerals at
14 pt (row 1). `:156`'s stated reason is inaccurate for the bold set and should be corrected without changing
the number.*

### R14 — Proposal 4's AppKit claim is unsourced and cuts against HIG Focus and selection `[unsupported factual claim]`

**Quoted.** F2 (`:255-257`): *"require a contrasting hairline or halo behind the ring when the platform colour
does not reach it — which is what AppKit's own focus ring does on coloured backgrounds."*

**What is wrong.** I found no Apple documentation for that behaviour. `NSColor.keyboardFocusIndicatorColor` is
documented as *"The ring that appears around the currently focused control when using the keyboard for
interface navigation"* and nothing more; `UIFocusHaloEffect` documents a customisable halo but says nothing
about an automatic contrasting backing. Meanwhile HIG > Focus and selection > Best practices says *"Rely on
system-provided focus effects. … Consider creating custom focus effects only if it's absolutely necessary"* and
*"Indicate focus using visual appearances that are consistent with the platform"* — which is guidance against
the proposed remedy, and is also the strongest available defence of the contract's current position at `:253`.

**Severity: substantive.** F2's finding (the focus ring is the only mark with no floor) is sound and worth
raising; the proposed fix is presented as merely matching platform behaviour when it is in fact a custom focus
effect Apple advises against.

**Correction.** Drop the AppKit assertion. Frame proposal 4 as a genuine trade the designer must make between
two cited Apple positions — HIG Vision's contrast expectation and HIG Focus and selection's "rely on
system-provided focus effects" — and note that the third option, recording a reasoned exception, is the one
Apple's own text supports most directly.

### R15 — Apple's own manual accessibility-testing checklist is absent, and it bears on AU-3, S-10, O-2 and O-3 `[omission]`

**What is missing.** *Performing accessibility testing for your app* (developer documentation) publishes both a
settings matrix (*Bold Text; Larger Text > Larger Accessibility Sizes; Button Shapes; On/Off Labels; Reduce
Transparency; Increase Contrast; Differentiate Without Color; Color Filters; Reduce Motion; Dim Flashing
Lights*) and a pass-condition checklist that includes, verbatim, *"A user can perform all tasks within your app
using only VoiceOver"*, *"… using only Voice Control"*, and *"… using only Switch Control"*, plus *"Your app
doesn't use color alone to convey information"* and *"Your app uses sufficient contrast for important UI
elements."*

**Why it matters.** (a) AU-3 asserts manual verification is required *"because Apple says explicitly that the
audit does not guarantee accessibility"* — true, but this page is the procedure Apple actually publishes for
it, and it is a better source for proposal 11's testing half than an invented matrix. (b) O-2 is framed as
though only `testing.md:149` asserts an end-to-end nonvisual game; Apple states the equivalent as a testing
criterion. That does not decide the product question — O-2 is still genuinely the owner's — but the report
should not imply the bar is unattested. (c) S-10 and O-3 gain a named Apple checklist for Voice Control and
Switch Control instead of a bare "define it either way".

**Severity: substantive.** The report's §1 "not found" claims remain honest, but this is a found-and-citable
page that changes how two open items are framed.

**Correction.** Add it to §1, cite it under AU-3, and in O-2 note that Apple publishes the "all tasks with
VoiceOver alone" criterion, so choosing "best effort" is a decision to fall short of a published Apple testing
criterion — which is a fair thing to decide, and better decided knowingly.

---

## Minor

### R16 — F6's grep claim contradicts itself in the same sentence

`:316-317`: *"the strings *hit region*, *touch target*, *tappable* appear **nowhere** in `docs/`. The only
occurrence of 'touch targets' is `:486`"*. §0 (`:18-19`) makes the same claim. I re-ran it: exactly one
occurrence, `interaction-design.md:486`. **Severity: cosmetic.** Correction: *"the strings hit region and
tappable appear nowhere in docs/; touch target(s) occurs exactly once, at :486, and only to say the pre-start
preview has none."*

### R17 — "the only two hits are `architecture.md:32-33`"

§0 (`:16-17`). `grep -rn -i accessib` over the six non-`interaction-design`, non-`testing` contracts returns
exactly **one** hit, `architecture.md:33` (*"localization resources and accessibility integration;"*). Line 32
is *"presentation, navigation, animation, sound, and haptics;"*, which is adjacent but is not an accessibility
hit. **Severity: cosmetic.** Correction: cite `architecture.md:33` and say "one hit".

### R18 — Proposal 6 resolves a contract open item the report elsewhere declines to touch

`:529` is an accepted Need-to-discuss item: *"define the exact accessibility text size at which the strips are
hidden."* Proposal 6 answers it (`isAccessibilityCategory`, AX1 and above). The answer is good and the
predicate is correctly attributed. But the report is otherwise strict about not answering other owners'
questions — it defers `:532`'s second clause to 8.1, `testing.md`'s acceptance to 8.3, and part 6's
terminology — and `:529` belongs to whoever owns the numeral-strip measurement confirmation on iOS. **Severity:
minor, scope discipline.** Correction: keep the recommendation, label it as a proposed answer to an open
contract item rather than as a criterion that "makes T-5 checkable today", since T-5 is not checkable until
`:529` is actually closed by the main thread.

### R19 — Two small inaccuracies in the Accessibility Inspector settings list

§1 (`:60`) tags Bold Text, Dynamic Type, Button Shapes, On/Off Labels and Grayscale as *"(iOS)"*. Apple's
heading is *"iOS, watchOS, and tvOS"*, and the Inspector labels the first one *"Bold fonts"* (*"This option
toggles the Bold Text setting"*). Everything else in the row is correct, including the all-platforms set.
**Severity: cosmetic.**

### R20 — F5 omits the nearest adjacent accepted line

F5 quotes `:71`, `:74`, `:116`, `:163`, `:168` but not `:461`: *"Piece characters are game content and are
excluded from localization, as defined under Piece representation. **Their English names localize wherever they
appear as text.**"* That sentence does not close the gap — the move list shows characters, not names, so F5
stands — but it is the accepted line closest to the requirement V-6 proposes, and a reviewer will look for it.
**Severity: cosmetic.** Correction: cite `:461` and say why it does not reach the move list, the numeral strips
or the board's point descriptions.

---

## Copy check

The report proposes no new user-facing copy, and its stated reason — that every missing string is owned by 8.1,
part 6, or parts 7.2/7.3/7.4 — is correct and consistent with the accepted contracts. Nothing to check against
register or terminology, and no irreversible action is described.

The one naming note is sound. 高对比 (`interaction-design.md:84`) does mean "high contrast", and if part 6's
item 6.8 makes the piece-style names user-facing, an English counterpart of "Increase Contrast" would collide
with the system setting that criterion S-5 checks independently. Two refinements: the collision is
English-only, because the Simplified Chinese system setting is 增强对比度 rather than 高对比, so the accepted
Chinese string is not at risk; and the same caution applies to 传统 and 现代 only as ordinary translation work,
not as a criterion ambiguity.

---

## Verdict

The audit half is the strong half: F1, F5, F6, F10, F11, F12, F13 and F16 are real, correctly cited, and worth
acting on, and F6's one-sentence fix is the highest-value line in the report. The criteria half is not yet
adoptable as written. SC-1 contradicts SC-2 at two rows (R1) and its carrier taxonomy does not discriminate
(R2), which undercuts F3, one of the five findings the report asks the main thread to write into accepted
behaviour. F3's own premise about macOS haptics is factually wrong (R4) while a stronger, citable version of
the same finding — the Settings toggle removes the haptic carrier on every platform (R3) — was available from
lines the report already cites. Three criteria and the automated floor are unperformable on macOS for reasons
not recorded (R5). One instrument citation is not in the pinned documentation (R7), one criterion carries an
Apple tag for two WCAG criteria (R8), one criterion is stricter than Apple on macOS while claiming Apple's
authority (R6), and the most on-point Apple page for the entire targets group is missing (R6, and R15 for the
testing procedure).

Recommended disposition: adopt §3's audit findings; hold §2's criteria until R1–R8 are resolved; and add the
sixth accepted-behaviour defect this review found, namely that `interaction-design.md:250`'s parenthetical
*"haptics that a Mac does not have"* is itself incorrect.
