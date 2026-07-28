# Part 6, item p6-names — Are the piece-style and piece-symbol names user-facing?

**Research draft. Not a contract, not a diff, authorises nothing.** The main thread authors all contract text.
Written against `MiniXiangqi/docs/*.md` as accepted on 2026-07-28, after the five design PRs merged that day.
PR #23 (part 4) is rejected and its content is not accepted; nothing here depends on it.

**Question, from `interaction-design.md:535`.** *"Decide whether the piece-style and piece-symbol names are
user-facing interface strings or internal design names, and approve their wording if they are user-facing."*

**Short answer.** They are user-facing, they always were by the document's own convention, and four of the five
words survive verbatim. The fifth, **高对比**, must become **高对比度** to be idiomatic — and that one change
is what turns this from a bookkeeping item into a decision, because 高对比度 is character-for-character the
string Apple ships in Simplified Chinese for the system accessibility setting *High contrast*. Beyond the five
option labels, the item necessarily produces four strings that exist in neither language today: a group label,
two row labels, and a footer.

---

## 0. Method — what is executed, what is cited, what is reasoned

| Class | Content |
|---|---|
| **Executed** | Extracted localized strings from macOS 27 (Darwin 27.0.0) shipped system software with `plistlib`/`plutil` and `strings`, read-only: `/System/Applications/Chess.app/…/Localizable.loctable`, `…/Board.loctable`, `…/Base.lproj/Board.nib`, and `/System/Library/ExtensionKit/Extensions/AccessibilitySettingsExtension.appex/…/Localizable.loctable`. Read `pychess-variants/client/boardSettings.ts` in the local read-only checkout. Measured every candidate string's rendered width with AppKit `NSFont.systemFont(ofSize:)` under `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` (script at `/tmp/p6-measure.swift`, `/tmp/p6-m2.swift`, `/tmp/p6-m3.swift`; scratch only, nothing written into the workspace). Enumerated all 58 distinct bolded Chinese terms in `interaction-design.md` with `grep -o | sort -u`. |
| **Cited** | Apple Human Interface Guidelines, pages and sections named inline in §4. Lichess translation source on GitHub (`translation/source/site.xml`, `translation/dest/site/zh-CN.xml`). One vendor page, `chessroad.cn/features/custom-themes.html`. |
| **Reasoned** | The recommendation itself, the register argument, the row-fit arithmetic's consequences, and the contract-edit list in §9. |

Two honest negatives, stated plainly. **Apple publishes no guidance on naming a theme or skin picker in a
game**, and none on wording in Simplified Chinese — Apple's Chinese terminology is not documentation, it is
shipped software, so every Chinese Apple string below is an extraction with its file and key given, not a
citation. And **the search for how Chinese-language Xiangqi apps label this is thin**: I verified one vendor
page and one open-source translation; App Store screenshots and the summaries a web search returns are not
evidence I am willing to put weight on, so §3 says what each source is and how firm it is.

---

## 1. The decision: user-facing, and the contract already treats them that way

Four arguments, strongest first.

### 1.1 The document's own convention already classifies them as copy — this is measurable

`interaction-design.md` marks two different kinds of term in bold. Internal design vocabulary is **English**:
*board block* (:40), *cell pitch* (:129), *marker ink*, *active ink*, *record ink* (:141). Accepted
user-facing copy is **Chinese**.

I enumerated every bolded Chinese term in the document — there are 58 distinct ones. Fifty-three of them are
unambiguously strings a user reads: **开始对局**, **保存并继续**, **我先手**, **默认 AI 等级**,
**人机对弈默认设置**, **删除这盘棋？**, **当前可用内存不足。请尝试关闭一些其他 App，然后重试。**, and so on.
The remaining five are exactly **传统**, **现代**, **高对比**, **汉字**, **图标**.

So the document has one convention with one exception, and the exception is precisely the set under
question. There is no third category of "Chinese internal design name" anywhere in the contract. Reading these
five as internal names requires inventing that category; reading them as copy requires nothing. The cheaper
reading is that they were always copy and the contract simply never said so.

### 1.2 A string exists whether or not it is displayed, because accessibility requires one

Part 8 is going to write the accessibility acceptance criteria, and `interaction-design.md:218` already
accepts that a control needs *"a localized accessibility label"*. Three radio options rendered as three
unlabelled previews still need three accessibility labels, in both languages, reviewed and translated. The
choice is therefore not "strings or no strings" — it is "one string per option, or one string per option plus
an unrelated visible treatment". Declaring the names internal saves nothing and creates a second vocabulary
that has to be kept in step with the first.

### 1.3 A picture-only picker fails the audience the third style exists for

`interaction-design.md:84` defines 高对比 as *for low-vision use*. A picker whose options are distinguishable
only by three rendered board thumbnails is precisely the control a low-vision user cannot resolve, and the
option they most need is the one they cannot find. This is not a hypothetical: the accepted contract hides the
board's file-numeral strips at accessibility text sizes (`:157`, accepted), which is the project
already acknowledging that this user exists and that graphics-only affordances break for them.

### 1.4 Apple's own board game localizes its style names, and it does not use thumbnails

Executed. macOS 27 `Chess.app` ships a Preferences pane whose Style group contains two pop-up menus, and every
style value is a translated string:

| Key (`Localizable.loctable`) | en | zh_CN |
|---|---|---|
| `Wood` | Wood | 木纹 |
| `Metal` | Metal | 金属 |
| `Marble` | Marble | 大理石 |
| `Grass` | Grass | 草地 |
| `Fur` | Fur | 毛皮 |
| `Glass` | Glass | 玻璃 |

and the surrounding chrome, from `Board.loctable` (English from `Base.lproj/Board.nib`, which carries no `en`
entry because English is the development language):

| Key | en (from the nib) | zh_CN | zh_TW |
|---|---|---|---|
| `200876.title` | Style | 样式 | 樣式 |
| `200876.ibShadowedToolTip` | Select the look of the board and pieces. | 选择棋盘和棋子的样式。 | 選取棋盤和棋子的外觀。 |
| `200907.title` | Board | 棋盘 | 棋盤 |
| `200908.title` | Pieces | 棋子 | 棋子 |
| `200871.title` | Preferences | 偏好设置 | 偏好設定 |

Apple's own answer to this exact question, in a chess app, in Simplified Chinese, is: named, localized,
grouped under a heading, with a one-sentence explanation. That is the shape I propose in §5.

**Conclusion.** The names are user-facing interface strings. They are interface text, not game content, and
they localize — the opposite of the piece characters (`:71`) and the icons (`:116`), which do not.

---

## 2. What must change in the wording: 高对比 → 高对比度

Adopting the design names verbatim ships one string that is not idiomatic Chinese. 对比 is a verb or a
relation ("to contrast"); the noun a UI label needs is 对比度. Apple is consistent about this. Executed, from
`AccessibilitySettingsExtension.appex/Contents/Resources/Localizable.loctable` on this machine:

| Key | en | zh_CN | zh_TW |
|---|---|---|---|
| `display.increaseContrast` | Increase contrast | 增强对比度 | 增加對比 |
| `keyboard.access.highContrast` | High contrast | 高对比度 | 高對比 |
| `display.reduceTransparency` | Reduce transparency | 降低透明度 | 減少透明度 |
| `display.differentiateWithoutColor` | Differentiate without color | 无需用颜色区分 | 不以顏色來區分 |
| `display.reduceMotion` | Reduce motion | 减弱动态效果 | 減少動態效果 |
| `display.contrast` | Display contrast | 显示对比度 | 顯示器對比度 |

Every Simplified Chinese form ends in 度. There is no Apple Simplified Chinese string of the form 高对比.

That fix creates the real problem: **高对比度 is byte-identical to Apple's zh_CN string for the system
setting *High contrast*, and one character-class away from 增强对比度, the system setting this app is already
contractually required to respond to** (`interaction-design.md:99`, `:141`, `testing.md:154`, `:180`).

The HIG names this hazard directly. *Settings > Best practices* tells designers to respect systemwide settings
and "avoid including redundant versions of them in your custom settings area", and explains that a custom
version of a global option implies the systemwide one may not apply to your app. That is exactly the wrong
inference here, because the accepted contract requires all three styles to hold their contrast floors under
Increase Contrast — the high-contrast style is not the accessible one, it is the most structurally separated
one.

### 2.1 The recommendation, and the runner-up, with what each costs

**Recommend: 高对比度 / High Contrast, with a group footer that disambiguates.** The label is accurate and it
is the phrase a low-vision user will scan for. The HIG warning is about duplicating a global option's
*function*; this option does not turn anything on or off, and one sentence of footer removes the ambiguity.
HIG *Writing > Best practices* explicitly sanctions that move — add an explanation when the label alone is not
enough. Cost: the app carries one sentence of copy that references an OS setting by name, which has to be
re-derived per platform (see §5.3 and Owner item 3).

**Runner-up: 强对比 / Strong Contrast.** Avoids the verbatim Simplified Chinese collision entirely and keeps
the meaning legible. Cost: a coined term with no precedent in either language — 强对比 is not an Apple string
and not a term I found in any surveyed app, and "Strong Contrast" is not an Apple English setting name either,
so the app invents vocabulary in the one area where borrowing the platform's is safest. Measured, it is also
the longest of the candidates (121.0 pt at 17 pt against 105.5 pt for High Contrast).

**Rejected: a neutral look-name** such as 描边 / Outlined, or 醒目 / Bold. Outlined describes the construction
and parallels 传统/现代 grammatically, and it removes the collision completely, but a user who needs the style
would never recognise it — it optimises the wrong thing. Bold collides with the system's Bold Text (zh_CN
粗体文本), which is a worse collision than the one it avoids.

**Not recommended: keeping 高对比 as the shipped string.** It is the only option that ships text no Chinese
speaker would write on a label.

---

## 3. Survey — how comparable apps label the equivalent choices

Four sources, graded by how firm the evidence is.

**(a) Apple Chess.app, macOS 27 — firm, extracted from the shipped binary.** See §1.4. Named localized styles,
under a group heading 样式 / Style, split into two rows 棋盘 / Board and 棋子 / Pieces, with a tooltip
explaining the group. No thumbnails in the picker; the preview is the board itself, live behind the sheet.

**(b) Lichess — firm, from the project's own translation files.** `translation/source/site.xml` defines
`pieceSet` as `Piece set`; `translation/dest/site/zh-CN.xml` renders it **棋子样式**. `preferences.xml`
defines the section header `display` as `Display`, which zh-CN renders 界面设置. Lichess names the *row* and
then presents the individual sets by proper name (cburnett, merida, …) with a rendered preview beside each —
i.e. the row label is translated and the option names are not, because they are brand names rather than
descriptions. Our five option names are descriptions, so they translate.

**(c) pychess-variants — firm, read from the local checkout, and the most instructive negative.**
`client/boardSettings.ts`, `PieceStyleSettings.view()`, builds one radio input per style and gives each one a
label whose text content is the empty string `''`; the option is identified purely by a CSS class that paints
a preview image. The internal names for the Xiangqi family (`client/variants.ts:264-270`: `lishu`,
`xiangqi2di`, `xiangqi`, `xiangqict3`, `xiangqihnz`, `xiangqict2`) are never shown to anyone. So a real
Xiangqi product does exist that answers this question "internal design names, previews only". It is also, by
construction, the design §1.3 rejects: there is no text for a screen reader to read, in any language.

**(d) 象棋公社 / ChessRoad, `chessroad.cn/features/custom-themes.html` — softer, a vendor marketing page
fetched today, not a screenshot of the running app.** Its appearance feature is presented under 皮肤 ("skins"),
with named styles 经典木纹, 水墨丹青, 现代简约, 暗夜模式. Two things it establishes: Chinese Xiangqi apps do
name their styles rather than showing thumbnails alone, and **现代 is idiomatic as a style name in this
category** (现代简约 = "modern minimalist"). It does not establish anything about a character-versus-icon
switch; I did not find a verifiable source for how any Chinese Xiangqi app labels that, and I am not going to
invent one. That gap matters less than it looks, because 汉字 and 图标 are both ordinary words — 图标 is
Apple's own zh_CN for *Icon* (extracted: `Icon` → `图标`).

**What the survey does not support.** Nobody surveyed offers a "characters or icons" switch, because no other
game needs one: Xiangqi's pieces are text, and this app's icon set exists for readers who do not know the
characters. The 汉字/图标 pair is ours to name, and there is no external usage to defer to.

---

## 4. Apple documentation, quoted where it says something and named where it does not

- **HIG > Settings > Best practices** — respect systemwide settings and "avoid including redundant versions of
  them in your custom settings area"; also, minimize the number of settings offered, and choose defaults that
  suit most people. Bears directly on §2 and on the group's size (two rows, both with accepted defaults).
- **HIG > Writing > Best practices** — keep settings labels clear and simple, and add an explanation when the
  label alone is not enough; adopt one capitalization rule and apply it consistently. This is the authority
  for the footer in §5.3.
- **HIG > Segmented controls > Content** — segment labels should be nouns or noun phrases in title-style
  capitalization, and a segmented control of text labels needs no introductory text. If the two symbol options
  ship as a segmented control, this is why they are nouns and why the row label could in principle be dropped
  (I recommend keeping it — see §5.4).
- **HIG > Menus > Labels** — title-style capitalization for consistency with platform experiences, and drop
  articles. This plus the accepted English *Confirm Before Deleting* settles the capitalization question in
  §5.5.
- **Foundation > Adding a settings interface to your app > Integrate settings into your app's UI on other
  platforms** — settings people change occasionally belong in a dedicated in-app scene rather than the system
  Settings app, which is what the accepted Settings destination already is.

**Apple publishes nothing** on naming a game's theme or skin picker, nothing on whether such names should be
localized (Chess.app answers by example, not by documentation), and nothing in any language other than English
that is documentation rather than shipped software. The wording below is ours, and I own it.

---

## 5. Proposed strings

Simplified Chinese is the source; English is its counterpart, per `interaction-design.md:455`.

### 5.1 The complete set

| Role | Simplified Chinese (source) | English | Status |
|---|---|---|---|
| Settings group label | **棋盘和棋子** | **Board and Pieces** | new |
| Row 1 label | **棋子样式** | **Piece Style** | new |
| Row 1 option (default) | **传统** | **Traditional** | promoted from design name, unchanged |
| Row 1 option | **现代** | **Modern** | promoted from design name, unchanged |
| Row 1 option | **高对比度** | **High Contrast** | promoted, **amended** from 高对比 |
| Row 2 label | **棋子符号** | **Piece Symbols** | new |
| Row 2 option (default) | **汉字** | **Chinese Characters** | promoted from design name, unchanged |
| Row 2 option | **图标** | **Icons** | promoted from design name, unchanged |
| Group footer | **棋子样式同时决定棋盘的配色。无论选择哪种样式，App 都会遵循系统的“增强对比度”设置。** | **The piece style also sets the board colors. Whichever style you choose, the app follows the system's Increase Contrast setting.** | new, see §5.3 and Owner item 3 |

Net effect on part 6.1's inventory: the count of distinct accepted Chinese strings in `interaction-design.md`
goes from **58 to 62**, and the row the prior survey labelled "design names, status contested" merges into the
Settings group.

### 5.2 Why each word

- **棋盘和棋子 / Board and Pieces** for the group. It is true of both rows — a style repaints the board
  surface (`:80`) and the symbols paint the pieces — and it echoes Apple Chess's own zh_CN phrasing
  选择棋盘和棋子的样式。, including 和 rather than 与. **I rejected 外观 / Appearance**, which is the obvious
  choice and the wrong one: 外观 is Apple's zh_CN for the system's light/dark Appearance setting, and this app
  offers no appearance control (it follows the system), so the group would advertise something it does not do
  — the same §2 hazard in milder form. I also rejected 样式 / Style alone: fine as a pane title inside a
  Preferences window, too vague as one section header among several in a single scrolling Settings list.
- **棋子样式 / Piece Style.** Matches `product.md:82`'s accepted English exactly, and independently matches
  Lichess's Simplified Chinese for the same concept. Two unrelated sources landing on the same four characters
  is about as much corroboration as this kind of string ever gets.
- **棋子符号 / Piece Symbols.** Matches `product.md:83`'s accepted English exactly. 符号 is Apple's zh_CN for
  *Symbols* (extracted). It is also the word the accepted contract already uses in English throughout §Piece
  symbols, so the row label is a translation of an accepted term rather than a new coinage.
- **传统 / Traditional**, **现代 / Modern.** Unchanged, idiomatic, and 现代 is attested in this exact product
  category (§3d).
- **汉字 / Chinese Characters.** Not "Characters" — in a game, English *characters* first reads as personae,
  and the row label does not disambiguate it fast enough. Accepted `product.md:83` already says "Chinese
  characters", so this is the faithful counterpart. It is the longest string in the set and §5.4 says what
  that costs.
- **图标 / Icons.** 图标 is Apple's zh_CN for *Icon*; English plural to match the plural row label.

### 5.3 The footer, and what it is for

Two things need saying and neither fits in a label, which is the condition HIG *Writing* sets for adding an
explanation:

1. the row says *piece* style but the **board** changes too (`interaction-design.md:80`);
2. **高对比度 is a look, not the system accommodation** — the app follows the system setting under all three
   styles (`:99`).

Measured, at 13 pt: the Chinese footer is 527.2 pt of text (44 characters) and the English 768.3 pt (127
characters), so at a 353 pt content width they set to roughly 2 and 3 lines respectively. Both are within the
length of the accepted 无法启动 AI 对手 notice's body text, so they are in register for this contract.

An alternative that names no system setting — 棋子样式同时决定棋盘的配色。三种样式都满足相同的对比度要求，也都会跟随系统的辅助功能设置。 /
"The piece style also sets the board colors. All three styles meet the same contrast requirements and follow
the system's accessibility settings." — measures 574.5 pt and 858.8 pt, is vaguer, and avoids committing the
copy to a per-platform system-string lookup. That trade is Owner item 3.

### 5.4 Measured widths, so the layout can be checked rather than argued

Executed with AppKit `NSFont.systemFont(ofSize:)` on macOS 27; Latin is proportional SF, Chinese resolves to
the full-width Chinese family at a uniform 0.991 em advance, consistent with `interaction-design.md:72`.

Row label plus trailing value, both at body size:

| Pair | 17 pt | 19 pt | 21 pt | 23 pt |
|---|---|---|---|---|
| 棋子样式 + 高对比度 | 134.8 | 150.7 | 160.4 | 175.2 |
| 棋子符号 + 汉字 | 101.1 | 113.0 | 120.3 | 131.4 |
| Piece Style + High Contrast | 189.7 | 210.6 | 227.7 | 247.4 |
| **Piece Symbols + Chinese Characters** | **261.3** | **290.2** | **314.1** | **341.4** |
| *(Piece Symbols + Characters, for comparison)* | *195.4* | *216.9* | *234.7* | *254.9* |

Individual strings at 17 pt: 棋盘和棋子 84.3 · 棋子样式 67.4 · 棋子符号 67.4 · 传统 33.7 · 现代 33.7 ·
高对比度 67.4 · 汉字 33.7 · 图标 33.7 · Board and Pieces 132.5 · Piece Style 84.2 · Piece Symbols 111.6 ·
Traditional 79.3 · Modern 59.0 · High Contrast 105.5 · Chinese Characters 149.7 · Icons 40.8. For scale, the
accepted **人机对弈默认设置** is 134.8 and **Confirm Before Deleting** is 182.9.

**The one consequence.** English *Piece Symbols* + *Chinese Characters* is the only pair that strains a
label-plus-trailing-value row. At 17 pt it needs 261.3 pt of text; add 16 pt margins on each side and a
disclosure indicator and it clears a 320 pt-wide device by single digits, and at the very next Dynamic Type
step (19 pt, 290.2 pt of text) it does not fit at all. Chinese never comes close. Three ways out, in
preference order: present the choice as an inline list or a navigation destination rather than a trailing
value; or let the value truncate, which is acceptable because the two options differ in their first word; or
shorten the English to *Characters*, which I do not recommend for the reason in §5.2. **This is input to the
part 4 layout rewrite, not a decision this item takes** — it is recorded here so nobody has to re-measure.

### 5.5 Capitalization and register

English uses **title-style capitalization**: *Board and Pieces*, *Piece Style*, *High Contrast*, *Chinese
Characters*. That follows HIG *Menus > Labels* and *Segmented controls > Content*, and it matches the only
accepted English UI string in the contracts, *Confirm Before Deleting* (`product.md:62`, `game-data.md:125`).
Noted for honesty: macOS 27's own Accessibility settings ship sentence case ("Increase contrast", extracted
above), so Apple is not internally consistent here; the tie-break is the project's own accepted string.

Chinese follows the accepted copy's register — terse, declarative, full-width punctuation, a space on each
side of Latin runs, exactly as **默认 AI 等级** and **当前可用内存不足。请尝试关闭一些其他 App，然后重试。**
already do. The footer's quotation marks are the zh_CN curly pair “ ”.

---

## 6. The naming boundary, which the contract half-states

The contract says twice that what is drawn on the board does not localize:

- `:71` — piece characters are game content, identical in every language, never translated on the board;
- `:116` — icons are game presentation, they do not change with the interface language.

It never states the complement. The missing sentence is the whole point of this item, and it is short:

> The piece-style and piece-symbol **names** are interface text, not game content. They localize; the
> characters and icons they name do not.

That sentence resolves what would otherwise be a live ambiguity in an English build: an English-reading user
selects **Chinese Characters** and the board shows 帅 俥 傌 — the label localized, the thing it names did not,
and that is correct and intended.

---

## 7. A separate layer nobody has named: the stored value

Three distinct things are being conflated by the phrase "the names":

1. the **design name** used in contract prose (传统);
2. the **interface string** in each language (传统 / Traditional);
3. the **stored preference value**, which no accepted document defines.

`game-data.md:151` places both preferences in each platform's own preference system and states that
divergence between platforms is bounded by that document's serialized vocabularies. There is a ready
precedent: `ai_level` serializes as `fast` / `standard` / `deep` while its copy is 快速 / 标准 / 深思
(`game-data.md:48`). Proposing the same shape here costs nothing and decouples copy from storage, so a later
wording change is not a migration:

```
piece_style:   traditional | modern | high-contrast     (default: traditional)
piece_symbols: characters | icons                       (default: characters)
```

Note the asymmetry this makes explicit and safe: the stored value stays `high-contrast` whichever way §2's
naming question is resolved. **This is a proposal, not part of the question asked**, and it belongs to
`game-data.md`'s Accepted Settings placement section rather than to `interaction-design.md`. Flagging it so it
is not lost; it is an engineering call, not the owner's.

---

## 8. What this hands to the rest of part 6

- **6.1 (English counterparts)** gains 4 new Chinese source strings (group, two rows, footer) and inherits 5
  already-existing ones whose category changes from "contested" to "accepted copy". Inventory 58 → 62. (My
independent `grep -o | sort -u` count of distinct bolded Chinese terms is also 58, which matches the prior
survey's figure — the two counts agree, they are not being added together.)
- **6.2 (the reverse gap)** is not fixed by this item, but is illuminated by it: the same defect — a UI element
  named only in English despite Chinese being normative — would have been created here if the group and rows
  had been specified in English only. Whoever writes 6.2 should take 棋盘和棋子 / 棋子样式 / 棋子符号 as
  worked examples of the fix's shape.
- **6.3 (English terminology)** should record *Piece Style*, *Piece Symbols*, *Traditional*, *Modern*, *High
  Contrast*, *Chinese Characters*, *Icons* in the app's English vocabulary. Nothing here touches the
  General-versus-King conflict.
- **6.7 (what an icon reader gets for the move list)** is adjacent but untouched: this item names the option,
  it does not decide what selecting it offers elsewhere.
- **Part 8.2** gains one accessibility criterion candidate: every option in both rows exposes its name to the
  screen reader, and the low-vision style is reachable without resolving a thumbnail.

---

## 9. Accepted document text that would change

Precise, with line numbers as of today. Nothing below is a diff; the main thread writes the text.

**`interaction-design.md`**

| Line | What | Required |
|---|---|---|
| :82, :83, :84 | The three style definitions, opening with **传统** / **现代** / **高对比** | :84's name becomes **高对比度** if §2 is accepted. A sentence must be added — best at :80 or after :116 — stating that these names are user-facing interface text that localizes, per §6. |
| :95 | *"by construction, in 高对比 — filled against outlined…"* | Rename to 高对比度. |
| :141 | *"…legible against 传统's heavier Black ring, 现代's white inset ring, and 高对比's outlined disc alike…"* | Rename to 高对比度's. |
| :93, :94, :100 | Use 现代 and 传统 only | **No change.** Listed so a reviewer does not "fix" them. |
| :108, :109 | **汉字** / **图标** definitions | No rename; covered by the new §6 sentence. |
| after :116 (or a new paragraph beside :209) | — | **New accepted paragraph** giving the group label, both row labels, all five option labels, the footer, and the two accepted defaults — modelled on :209, which does exactly this for **人机对弈默认设置**. |
| :459 | *"Terminology for Xiangqi pieces, rules, results, and controls must be consistent within each supported language."* | A style name is none of those four. Generalise the list, or add settings and options to it. |
| :535 | The Need-to-discuss bullet | **Delete** on acceptance. |

**`product.md`**

| Line | What | Required |
|---|---|---|
| :82 | *"the **piece style**, chosen among the three accepted styles defined in `interaction-design.md`, defaulting to the traditional one"* | Strictly no change — it defers correctly. But "the traditional one" is now an English gloss of an accepted Chinese string, so it should either name 传统 or say "the first-listed". |
| :83 | *"the **piece symbols**, Chinese characters by default or pictorial icons"* | No change. Its English is the source of the counterparts in §5.1 and should not drift from them. |

**`game-data.md`**

| Line | What | Required |
|---|---|---|
| :151 | Lists both preferences in English prose | No change required. Changes only if §7's stored identifiers are accepted, in which case they belong in that section. |

**`testing.md`** — :154, :156, :157, :158, :160, :165, :177, :178, :180, :188 all refer to "each accepted piece
style" and "the piece-style, piece-symbols … choices" generically and **need no change**. Checked explicitly,
because a rename that leaks into the test contract is the obvious way to get this wrong.

**Nothing in `xiangqi-rules.md`, `core-interface.md`, or `architecture.md` refers to these names.** Checked.

---

## 10. Residual risk

- **The Chinese wording is one native-speaker review away from being final.** I can show that 高对比 is not
  how Apple writes it and that 棋子样式 is what Lichess's translators chose, but I cannot substitute for a
  reviewer. That is precisely the machinery item 6.4 exists to create, and this item is a good first test
  case for whatever process the owner picks there.
- **The Chinese Xiangqi app survey is one verified vendor page deep.** More would strengthen §3d but would not
  change the recommendation, because §1 and §2 rest on the contract's own convention and on extracted Apple
  strings, not on competitor practice.
- **All widths were measured on macOS.** iOS uses the same families, so the numbers should carry, but
  `interaction-design.md:72` already requires a device check for the piece characters and the same discipline
  applies here — treat §5.4 as indicative until confirmed on device, which is `testing.md`'s dependency
  anyway.
- **Windows is unspecified.** The footer's reference to a named system setting is the only place this item
  creates a Windows obligation; §5.3's alternative removes it.

---

## Open for the owner

Three. Everything else above is a designer's call and I have made it.

### 1. One vocabulary, or two?

Accepting §5 makes 高对比度 a user-facing string while the contract's design name is 高对比.

- **Rename in the contract** — 高对比 becomes 高对比度 in all three places (`:84`, `:95`, `:141`), and the
  document has exactly one word for the thing. *Cost:* editing three lines of accepted normative prose in a
  merged contract, and any external note or review that quotes 高对比 goes stale.
- **Keep both** — 高对比 stays the internal short name, 高对比度 is the string. *Cost:* the project acquires
  its first Chinese-language internal design name, which is the exact category §1.1 shows does not currently
  exist; every future reader must learn that these five words are copy except when they are not.
- **Ship 高对比 as the string** — no edit at all. *Cost:* one label on a shipped screen that reads as a
  truncation to any Chinese speaker.

Recommendation: rename. It is three lines, and it keeps the document's one-convention property intact.

### 2. Does Settings preview the options, or only name them?

Naming is settled; showing is a scope question with an asset cost, and it interacts with the still-open icon
set (`:518`).

- **Names only.** Ships today, works for the screen reader, works at every text size. *Cost:* a user picks
  between 传统 and 现代 from words alone, which is genuinely hard for a visual choice — Apple Chess mitigates
  this by leaving the live board visible behind the pane, which this app's Settings destination does not.
- **Names plus a small static preview per option.** *Cost:* the style row needs three previews and the symbol
  row two, and every preview must be re-rendered whenever a style's colour values change (those values are
  themselves still open, `:517`). The previews must also degrade at accessibility text sizes rather than
  fighting for the row.
- **Names plus one live board preview that updates as the choice changes.** Best explanation of what the
  setting does. *Cost:* the largest — a second board renderer path in Settings, and `interaction-design.md:129`
  already had to carve out an exception for a non-interactive preview once (the pre-start board, which is
  exempt from the `p ≥ 44 pt` floor and shows no game-state markers), so the rule set for a second one has to
  be written.

### 3. How is the high-contrast style positioned, and does the copy name a system setting?

- **Third option in the same list, with the §5.3 footer that names 增强对比度 / Increase Contrast.** Clearest;
  removes the "is this the accessible one?" question outright. *Cost:* the app's copy now references an OS
  setting by name, so it must track Apple's string (macOS 27 currently ships "Increase contrast" in sentence
  case and 增强对比度) and must be rewritten for Windows, whose equivalent is named differently. That is a
  small permanent maintenance commitment in user-visible copy.
- **Third option in the same list, with the vaguer footer that names no system setting.** *Cost:* 47 pt more
  Chinese and 90 pt more English of footer, and a weaker denial — it says the styles are equivalent on
  contrast without saying the system setting still applies.
- **No footer.** *Cost:* accepts the HIG-flagged inference that choosing another style opts out of the system
  accommodation, and leaves the "piece style repaints the board" surprise unexplained too.
- **Separate the style out** — present it as its own row or marked as an accessibility option. *Cost:* a
  fourth Settings row and a structural claim the contract does not make; the three styles are accepted as
  co-equal looks (`:78`), not as two looks plus an accommodation.

Recommendation: the first, because it is the only one that answers both questions the footer exists to answer.
But the maintenance commitment in user-visible copy is a product decision, not a design one.

---

# Independent review

**Adversarial verification pass, 2026-07-28.** Appended, not merged into the draft above; nothing above was
edited. Everything below is either *executed* on this machine, *quoted* from an accepted contract or an Apple
page I opened, or *reasoned* and labelled as such.

## What I re-ran and what held

I re-executed the report's own extractions and measurements rather than taking them on trust.

- **Chess.app strings — exact.** `plistlib` on `/System/Applications/Chess.app/Contents/Resources/Localizable.loctable`
  reproduces all six style rows verbatim (`Wood`→木纹, `Metal`→金属, `Marble`→大理石, `Grass`→草地, `Fur`→毛皮,
  `Glass`→玻璃). `Board.loctable` reproduces all five chrome rows including the zh_TW column, and `strings` on
  `Base.lproj/Board.nib` confirms the English `Style`, `Board`, `Pieces`, `Preferences`, and
  `Select the look of the board and pieces.` **No defect.**
- **Accessibility strings — exact.** All six rows of §2's table reproduce from
  `AccessibilitySettingsExtension.appex/.../Localizable.loctable`, en / zh_CN / zh_TW, character for character.
  I also confirmed the report's negative: scanning every zh_CN value in that table, the only string containing
  高对比 is `keyboard.access.highContrast` = 高对比度; there is no bare 高对比. **No defect** — but see F1 for what
  that key actually is.
- **Every width — reproduced to ±0.1 pt.** Independent script, `NSFont.systemFont(ofSize:)`, AppKit, macOS 27,
  `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`. 棋盘和棋子 84.3 · 棋子样式/棋子符号/高对比度
  67.4 · 传统/现代/汉字/图标 33.7 · Board and Pieces 132.5 · Piece Style 84.2 · Piece Symbols 111.6 · High
  Contrast 105.5 · Chinese Characters 149.7 · Icons 40.8 · Strong Contrast 121.0 · Confirm Before Deleting
  182.9 · 人机对弈默认设置 134.8. Footers at 13 pt: 527.2 / 768.3 / 574.5 / 858.8. The 0.991 em Chinese advance
  checks out (67.4 ÷ 4 ÷ 17 = 0.991). Owner item 3(b)'s deltas check out (574.5−527.2 = 47.3; 858.8−768.3 = 90.5).
  **No defect in the numbers themselves** — see F3 for what one of them is being compared against.
- **Every Apple documentation citation in §4 — exists and says what is claimed.** *Settings > Best practices*
  ("Respect people's systemwide settings and avoid including redundant versions of them in your custom settings
  area", plus "Minimize the number of settings you offer" and the defaults sentence); *Writing > Best practices*
  ("Keep settings labels clear and simple… If the setting label isn't enough, add an explanation" and the
  capitalization paragraph); *Segmented controls > Content* ("Use nouns or noun phrases for segment labels…
  title-style capitalization. A segmented control that displays text labels doesn't need introductory text");
  *Menus > Labels* ("To be consistent with platform experiences, use title-style capitalization" and the
  articles rule); *Foundation > Adding a settings interface to your app > Integrate settings into your app's UI
  on other platforms* (settings changed occasionally go in a separate scene). **Nothing MISQUOTED, nothing NOT
  FOUND.** See F10 for a scope caveat on two of them.
- **The honest negative holds.** I searched Apple's documentation for guidance on naming a game's theme or skin
  picker and found none. The nearest thing is *Game Center > Using custom UI*, which prescribes terminology only
  for Game Center's own features. The report's refusal to fabricate here is correct and worth keeping.
- **Contract line numbers — accurate except one.** I checked every citation: interaction-design.md :40, :71,
  :72, :78, :80, :82, :83, :84, :93, :94, :95, :100, :108, :109, :116, :129, :141, :157, :209, :218, :455,
  :459, :517, :518, :535; product.md :62, :80, :82, :83; game-data.md :125, :151; testing.md :154, :156, :157,
  :158, :160, :165, :177, :178, :180, :188. All correct. `grep -n 高对比` returns exactly :84, :95, :141 — §9's
  rename list is complete. testing.md genuinely needs no change. The one exception is F6.
- **The 58 count is right.** `grep -o '\*\*[^*]*\*\*' interaction-design.md | grep -P '[\x{4e00}-\x{9fff}]' |
  sort -u | wc -l` = 58, and the set contains exactly 传统, 现代, 高对比, 汉字, 图标 among the disputed five.
- **pychess and the outside sources.** `client/boardSettings.ts` `PieceStyleSettings.view()` does pass `''` as
  the label's text content — verified. `chessroad.cn/features/custom-themes.html` does present 皮肤 with
  经典木纹 / 水墨丹青 / 现代简约 / 暗夜模式 — verified. Lichess `translation/dest/site/zh-CN.xml` does render
  `pieceSet` as 棋子样式 — verified (but see F11).

Now the defects.

---

## F1 — "the system High contrast setting" is a Full Keyboard Access sub-option. SEVERITY: HIGH

**Quoted (short answer, and §2):** *"高对比度 is character-for-character the string Apple ships in Simplified
Chinese for the system accessibility setting High contrast"*; *"高对比度 is byte-identical to Apple's zh_CN
string for the system setting High contrast"*; and the framing *"that one change is what turns this from a
bookkeeping item into a decision."*

**What is wrong.** Executed. The key is `keyboard.access.highContrast`. Its siblings in the same table are
`keyboard.access.toggle` = *Full Keyboard Access* / 全键盘控制, `keyboard.access.appearance` = *Appearance* /
外观, `keyboard.access.color` = *Color* / 颜色, `keyboard.access.increaseSize` = *Increase size* / 增加大小. So
Apple's "High contrast" here is an appearance option for the **Full Keyboard Access focus indicator** — the
keyboard navigation highlight — not a top-level accessibility accommodation. It is not something a user manages
globally and expects every app to honour; it is a rendering option for a focus ring inside a keyboard-navigation
feature most users never turn on.

That matters because the HIG hazard the report invokes is specifically about *global options*: *"People expect
to use the system-provided Settings app to manage global options like accessibility accommodations, scrolling
behavior, and authentication methods, and they expect all apps and games to adhere to their choices."* A
keyboard focus-ring appearance option is not in that class. The collision is a coincidence of vocabulary
(对比度 is simply how Chinese says "contrast"), not a duplication of a systemwide setting.

The report's *real* hazard — 增强对比度 / Increase Contrast, which the app genuinely must honour — survives
intact, and it exists whether or not 度 is added: a Chinese user reading 高对比 next to a system 增强对比度 has
the same question. So the amendment does not create the decision; the report's causal claim is backwards.

**Correction.** State what `keyboard.access.highContrast` is. Then re-argue: the footer is worth having because
of the *Increase Contrast* adjacency and because of the board-repaint surprise, both of which stand on their own.
Drop *"that one change is what turns this from a bookkeeping item into a decision"* — Owner decision 3 exists
independently of the 度. This also lowers the price of Owner 3(a): the maintenance commitment is to track
*Increase Contrast* / 增强对比度, which the contract already commits the app to at :98 and testing.md:180, not
to track a string the app has no other relationship with.

---

## F2 — the "co-equal looks" claim contradicts :84, and the report relies on :84 elsewhere. SEVERITY: HIGH

**Contract, `interaction-design.md:84`:** *"**高对比** — Red is a filled disc with the symbol reversed out of
it; Black is an outlined disc on a neutral face with a heavier ring. Structure and luminance carry the side as
strongly as possible, **for low-vision use**."*

**Contract, `interaction-design.md:78`:** *"The user chooses among three accepted piece styles, since a learner
and an experienced player want different things from the same board."*

**Report, Owner item 3(d):** *"a structural claim the contract does not make; the three styles are accepted as
co-equal looks (`:78`), not as two looks plus an accommodation."* **Report, §2:** *"the high-contrast style is
not the accessible one, it is the most structurally separated one."* **Report, §5.3:** *"**高对比度 is a look,
not the system accommodation**."*

**What is wrong.** Two things. First, :78 does not say "co-equal"; it says the three exist because different
players want different things — which is a statement that they serve *different* users, not equivalent ones.
The paraphrase inserts a claim the line does not carry. Second, and worse, :84 explicitly designates the style
*for low-vision use*, and the report's own §1.3 leans on exactly that phrase — *"`interaction-design.md:84`
defines 高对比 as *for low-vision use*"* — to defeat the thumbnail-only picker. The report therefore affirms the
style's accessibility purpose when it needs it and denies it two sections later when denying it is convenient.

**Correction.** The defensible sentence is narrow: 高对比度 is an accessibility-motivated *look*, and choosing
another look does not opt out of the system's Increase Contrast behaviour, which applies to all three (:98).
Say that. Then re-cost Owner 3(d) against :84 rather than against a paraphrase of :78 — the contract *does*
name a low-vision purpose for exactly one style, so "mark it as an accessibility option" is closer to the
accepted text than the report allows, and its real cost is the fourth row and the loss of a flat three-way
choice, not a contradiction with the contract.

---

## F3 — §5.3's register claim is falsified by the report's own measurement method. SEVERITY: HIGH

**Report, §5.3:** *"Measured, at 13 pt: the Chinese footer is 527.2 pt of text (44 characters) and the English
768.3 pt (127 characters)… **Both are within the length of the accepted 无法启动 AI 对手 notice's body text**, so
they are in register for this contract."*

**Contract, `interaction-design.md:284`:** *"Message: **当前可用内存不足。请尝试关闭一些其他 App，然后重试。**"*

**What is wrong.** Executed, same method, same font, same size. The accepted message body is **28 characters and
331.6 pt at 13 pt**. The proposed Chinese footer is 44 characters / **527.2 pt** — 59% longer. The English
footer is 127 characters / **768.3 pt** — 132% longer. Neither is "within" it; both are the longest strings the
document would contain. The alternative footer is worse: 574.5 pt and 858.8 pt. The claim is the report's own
numbers pointed at the wrong conclusion.

**Correction.** Delete the sentence, and either accept that the footer is the longest accepted string
(defensible — it is a footer, not an alert body, and HIG *Writing* sanctions the explanation) or shorten it and
say by how much. For calibration I measured one shorter candidate by the same method:
**棋子样式同时决定棋盘的配色。三种样式都遵循系统的"增强对比度"设置。** — 34 characters, **422.9 pt** at 13 pt.
That is 20% shorter than the proposal and still 28% longer than the accepted message body, which is the honest
shape of the trade: a footer carrying both facts cannot get under 331.6 pt in Chinese, so the claim should be
dropped rather than engineered. I am not proposing this string over the report's; I am showing that no version
supports the sentence as written.

---

## F4 — the "one layout consequence" is computed against a device the accepted platforms exclude. SEVERITY: HIGH

**Report, §5.4:** *"At 17 pt it needs 261.3 pt of text; add 16 pt margins on each side and a disclosure
indicator and it **clears a 320 pt-wide device by single digits**, and at the very next Dynamic Type step (19 pt,
290.2 pt of text) **it does not fit at all**."* **Report, §5.3:** *"at a **353 pt** content width they set to
roughly 2 and 3 lines."*

**Contract, `product.md:19`:** *"iOS 26.5 or later."* **Contract, `interaction-design.md:514`, still open:**
*"Fix the minimum window size for macOS and for iPadOS windowing, which the board and chrome floors together
determine, and **name the narrowest supported iPhone the stacked layout is verified against**."*

**What is wrong.** Three problems compounding.

1. **320 pt is not a native width for this product.** No iPhone that runs iOS 26.5 has a 320 pt logical width;
   the narrowest is 375 pt. 320 pt is reachable only under Display Zoom — which may well be the right worst
   case, but the report never says so, so the reader cannot check the assumption.
2. **The narrowest supported iPhone is an open contract question** (:514). The report presents a derived
   consequence as if its input were settled, which is the failure mode this review is meant to catch. It also
   sits oddly against the draft's own preamble, *"PR #23 (part 4) is rejected and its content is not accepted;
   nothing here depends on it"* — the 320 pt figure has no accepted source anywhere.
3. **§5.3 and §5.4 assume different devices.** 353 pt of content width in §5.3 versus 320 − 32 = 288 pt in §5.4,
   with neither sourced. Two adjacent sections model two different phones.

**Recomputed at 375 pt** (343 pt content after 16 pt margins each side), reasoned from my own measurements:
slack for *Piece Symbols* + *Chinese Characters* is **81.7 pt at 17 pt, 52.8 at 19, 28.9 at 21, 1.6 at 23**. The
row survives comfortably to xLarge, is tight at xxLarge, and fails at xxxLarge. It does **not** fail "at the
very next Dynamic Type step". The headline consequence is an artefact of the unsourced 320 pt.

**Correction.** Name the assumption explicitly and give the result as a function of width — e.g. "the pair needs
261.3 pt at 17 pt, so it fits a label-plus-value row above roughly 295 pt of content width and fails below it;
which devices that excludes depends on :514, which is open." That is the same useful input to part 4 without
asserting a device the contract has not chosen. The three ways out and their preference order are unaffected.

---

## F5 — §1.1's premise is false as stated, and §8 concedes it. SEVERITY: MEDIUM

**Report, §1.1:** *"`interaction-design.md` marks two different kinds of term in bold. Internal design
vocabulary is **English**… Accepted user-facing copy is **Chinese**… So the document has one convention with one
exception, and the exception is precisely the set under question."*

**What is wrong.** Executed: `grep -o '\*\*[^*]*\*\*'` over the same file, filtered to non-Chinese, returns a
list that includes **Flip Board** (:214 — *"a visible **Flip Board** control allows the player to change
orientation"*, and :218 gives that control a localized accessibility label, so it is unambiguously a user-facing
control), **Resume Game** (:296 — *"a direct **Resume Game** action"*), **Free Play** and **Human versus AI**
(:183, :298 — selectable mode entries), and **Play** / **History** / **Settings** (:21–:23 — the three
destinations). Bolded English in this document is therefore *not* a marker of internal vocabulary; it is a mix
of internal vocabulary (*board block*, *cell pitch*, *marker ink*) and user-facing names whose Chinese has not
been written yet.

The report knows this — §8 says 6.2 concerns *"a UI element named only in English despite Chinese being
normative"* — so §1.1 and §8 contradict each other within the same draft.

**What survives.** The one-directional claim: *every* bolded Chinese term in the document is user-facing copy,
53 of them uncontroversially, and there is no bolded Chinese term anywhere that is an internal design name. That
is still the strongest argument in the report and it is enough. It is the symmetry that is false.

**Correction.** Rewrite §1.1 to the one-directional form, and add the observation that the English side is
mixed — which is a free, correct, and useful handoff to 6.2 rather than a contradiction of it.

---

## F6 — `:99` is a blank line, cited twice. SEVERITY: MEDIUM

**Report, §2:** *"the system setting this app is already contractually required to respond to
(`interaction-design.md:99`, `:141`, `testing.md:154`, `:180`)"*. **Report, §5.3:** *"the app follows the system
setting under all three styles (`:99`)"*.

**What is wrong.** `sed -n '99p' interaction-design.md` returns an empty line. The sentence the report wants is
`:98` — *"All of the above hold with resting shadows removed, in light and dark appearance, under Increase
Contrast, and with either symbol set selected."*

**Correction.** `:98`. Small, but this is a document whose entire method is exact line numbers, and the
proposition it supports is load-bearing for the footer.

---

## F7 — §7 attributes to `game-data.md` a sentence that is not there. SEVERITY: MEDIUM

**Report, §7:** *"`game-data.md:151` places both preferences in each platform's own preference system and
**states that divergence between platforms is bounded by that document's serialized vocabularies**."*

**What is wrong.** Executed: `grep -n 'diverg' MiniXiangqi/docs/*.md` returns **zero hits in any accepted
document**. What the section actually says is:

- `:147` — *"Local preferences are not in schema version 1 and are not planned for a later one: they live with
  each platform, per the accepted placement below."*
- `:151` — the seven preferences *"live in **each platform's own preference system**, not in the shared store."*
- `:154` — *"The core therefore never reads a preference."*
- `:155` — *"Each platform gains its system's own defaults registration, change observation, and settings
  integration rather than the core reimplementing them."*

None of that bounds divergence by a serialized vocabulary. If anything the accepted text points the other way:
these values are deliberately outside the shared serialized world. The proposal in §7 may still be a good idea —
a shared value vocabulary costs nothing and buys cross-platform legibility — but it is a *new* proposal, not one
the contract already implies, and §7 should say so.

**Second, smaller error in the same paragraph.** *"`ai_level` serializes as `fast`/`standard`/`deep` while its
copy is 快速/标准/深思 (`game-data.md:48`)"*. `game-data.md:48` carries only the serialization, and it is the
*game record* vocabulary, not a preference vocabulary. The copy is at `product.md:37`, `interaction-design.md:195`,
and `engine-integration.md:97`–`:99`. The precedent is also weaker than presented: `ai_level` is serialized
because it is frozen into a game record, which is exactly the reason that does **not** apply to a presentation
preference.

**Correction.** Cite `:147`/`:151`/`:154`/`:155` for what they say, drop the divergence sentence, and present
§7 as a fresh proposal that has to argue for itself against `:147`'s "not in schema version 1 and not planned
for a later one".

---

## F8 — §1.2 generalizes a single-control statement into a general rule. SEVERITY: MEDIUM

**Contract, `interaction-design.md:218`:** *"Board flipping uses a visible control rather than a hidden rotation
gesture. **The control** has a localized accessibility label and an equivalent keyboard command where keyboard
input is supported."*

**Report, §1.2 (and the summary):** *"`interaction-design.md:218` already accepts that **a control** needs *'a
localized accessibility label'*"*; summary: *"the contract already requires a localized accessibility label at
:218"*.

**What is wrong.** :218 is a sentence about the board-flip control specifically, inside the Board orientation
section. It is not a general labelling rule, and there is no general one: `interaction-design.md:532` — *"Define
accessibility acceptance criteria and the board's VoiceOver interaction model"* — is still open, and the report
itself says part 8 will write those criteria.

The argument is nevertheless correct on platform grounds, and the report does not need the contract for it: a
radio option with no text has no accessible name on any Apple platform, which is a framework fact, not a
contract claim.

**Correction.** Make it a platform argument and cite the platform. Use :218 only as evidence that the contract's
instinct is already to require labels where it has spoken.

---

## F9 — §1.3's supporting inference runs backwards. SEVERITY: MEDIUM-LOW

**Report, §1.3:** *"This is not a hypothetical: the accepted contract hides the board's file-numeral strips at
accessibility text sizes (`:157`, accepted), which is **the project already acknowledging that this user exists
and that graphics-only affordances break for them**."*

**Contract, `:157`:** *"**The strips are hidden at accessibility text sizes.** They are the first thing to
yield when type grows… The cost is real and accepted: without the strips a reader cannot relate a move in the
list to a file on the board without counting, **which is a loss for the same user the larger type was for**."*

**What is wrong.** :157 *removes text* from a large-type user, for space, and the contract explicitly books that
as a cost to that user. It is a precedent for withdrawing text at accessibility sizes, not a precedent for
preferring text over graphics. The clause "and that graphics-only affordances break for them" is not in :157 in
any form; the numerals are text, and what replaces them is nothing.

**Correction.** Delete the sentence. §1.3's direct argument — three unlabelled thumbnails cannot be resolved by
the user :84 names, and the option they most need is the one they cannot find — is sound and needs no prop.

---

## F10 — §5.5's tie-break rests on a false uniqueness claim, and one cited HIG line permits the opposite. SEVERITY: LOW

**Report, §5.5:** *"it matches **the only accepted English UI string in the contracts**, *Confirm Before
Deleting* (`product.md:62`, `game-data.md:125`)… the tie-break is the project's own accepted string."*

**What is wrong.** Two things.

1. It is not the only one. As in F5: **Flip Board**, **Resume Game**, **Free Play**, **Human versus AI**,
   **Play**, **History**, **Settings** are all bolded English names of user-facing elements in
   `interaction-design.md`. (This actually *helps* the recommendation — all of them are title case — but the
   claim as written is false, and it is presented as the decisive fact.)
2. The HIG line the report cites for consistency says something more permissive than the report uses it for.
   Verified text of *Writing > Best practices*: *"Choose a style for each UI element type and use it consistently
   throughout your app — for example, title case for all alerts or sentence case for all headlines."* That
   explicitly allows a different rule per element type, so a toggle label being title case does not settle a
   Settings group header, a row label, or an option value. And *Menus > Labels* and *Segmented controls >
   Content* are scoped to menu items and segment labels respectively; neither covers a grouped-list header or a
   trailing value.

**Correction.** Keep the recommendation — title case is right, and the corroboration is now seven accepted
English UI names rather than one — but state the authority accurately: Apple permits per-element-type rules,
the project's existing English UI names are uniformly title case, and that is why title case wins. Also keep the
existing honest note that macOS 27's own Accessibility settings ship sentence case.

---

## F11 — the Lichess corroboration is about the Chinese only. SEVERITY: LOW

**Report (summary and §5.2):** *"Lichess (translation source pieceSet=\"Piece set\" → zh-CN 棋子样式,
**independently matching my proposed row label**)"*; *"Matches `product.md:82`'s accepted English exactly, and
independently matches Lichess's Simplified Chinese for the same concept. **Two unrelated sources landing on the
same four characters** is about as much corroboration as this kind of string ever gets."*

**Verified, both files fetched today.** `translation/source/site.xml`: `<string name="pieceSet">Piece set</string>`.
`translation/dest/site/zh-CN.xml`: `pieceSet` → 棋子样式.

**What is wrong.** Nothing factual — but the inference is narrower than the phrasing. Lichess's own English for
those four characters is *Piece set*, not *Piece Style*. So the source corroborates **棋子样式 as idiomatic
Simplified Chinese for this concept**, which is genuinely useful, and says nothing about the English half of the
pair. The English half rests on `product.md:82` alone. The second "independently" in §5.2 and the summary
overstates it by implying the *pairing* is corroborated.

**Correction.** One clause: "Lichess's translators chose 棋子样式 for their *Piece set*; the Chinese is
corroborated, the English pairing is `product.md:82`'s."

---

## F12 — the pychess citation is a 6-of-19 slice, and the line range is off by one. SEVERITY: LOW

**Report, §3(c):** *"The internal names for the Xiangqi family (`client/variants.ts:264-270`: `lishu`,
`xiangqi2di`, `xiangqi`, `xiangqict3`, `xiangqihnz`, `xiangqict2`) are never shown to anyone."*

**Executed, from the local read-only checkout.** `:264` is the `pieceCSS: [` line. The names run `:265`–`:283`
and there are **19** of them: the six listed, then `lishuw`, `xiangqict2w`, `xiangqiwikim`, `xiangqiKa`,
`xiangqittxqhnz`, `xiangqittxqintl`, `xiangqi2d`, `xiangqihnzw`, `eventhanzi`, `eventhanziguided`, `eventintl`,
`euro`, `disguised`.

**Why it matters slightly more than pedantry.** Nineteen unnamed thumbnail options is a much stronger example
of the failure mode §1.3 describes than six is. The correction strengthens the report.

**Correction.** `client/variants.ts:265-283`, 19 entries.

---

## F13 — three Apple strings are asserted without the file and key the method promises. SEVERITY: LOW

**Report, §0:** *"every Chinese Apple string below is **an extraction with its file and key given**."*
**Report, §5.2 / §3(d):** *"符号 is Apple's zh_CN for *Symbols* (extracted)"*; *"图标 is Apple's own zh_CN for
*Icon* (extracted: `Icon` → `图标`)"*; §5.2: *"外观 is Apple's zh_CN for the system's light/dark Appearance
setting"*.

**What is wrong.** No file or key for any of the three, in a report that made a point of the discipline.

**Verified anyway, so the claims stand** — supplying the missing citations:
- `Icon` → 图标: `/System/Library/ExtensionKit/Extensions/ControlCenterSettings.appex/Contents/Resources/Localizable.loctable`, key `Icon`.
- `Appearance` → 外观: `.../Appearance.appex/.../Localizable.loctable`, key `Appearance`.
- `Symbols` → 符号: keys `SectionTitle-Symbols` and `CategoryGroup-Symbols` in shipped system app loctables.

**One caution on 外观.** The same loctable scan shows `keyboard.access.appearance`, `zoom.appearance`,
`hoverColor.appearance`, `switchControl.appearance` all → 外观 as well. 外观 is Apple's general zh_CN for
"Appearance", not exclusively the light/dark setting's name, so the §5.2 rejection of 外观 is weaker than stated
— it collides with a common word, not with one specific setting. The rejection is still right for a different
and better reason: the app offers no appearance control at all, so an 外观 group would advertise a capability
that does not exist.

---

## F14 — the Chess.app "shape" is inverted relative to the model it cites. SEVERITY: LOW (design judgement, flagged not decided)

**Report, §1.4:** *"Apple's own answer to this exact question… is: named, localized, grouped under a heading,
with a one-sentence explanation. **That is the shape I propose in §5.**"* **Report, §5.2:** *"I also rejected
样式 / Style alone: fine as a pane title inside a Preferences window, too vague as one section header among
several in a single scrolling Settings list."*

**What Chess actually ships (verified):** group `200876.title` = **Style / 样式**, rows `200907.title` = **Board /
棋盘** and `200908.title` = **Pieces / 棋子**, tooltip *"Select the look of the board and pieces."* /
选择棋盘和棋子的样式。

**What is wrong.** The proposal inverts it: group **Board and Pieces / 棋盘和棋子**, rows **Piece Style /
棋子样式** and **Piece Symbols / 棋子符号**. That may well be right for a scrolling Settings list rather than a
Preferences pane — but "that is the shape I propose" claims a borrowing that did not happen, and the report then
rejects the one element it actually did borrow the wording from.

**Two consequences worth costing, which the report does not:**
1. **The group names a control it does not contain.** "Board and Pieces" / 棋盘和棋子 promises a board setting;
   there is no board row. The footer then exists partly to explain that the board changes as a side effect of a
   *piece* setting — the group label creates the confusion the footer resolves. A group named for the pieces
   alone would not need that half of the footer.
2. **棋子 appears three times** across a group label and two row labels (棋盘和棋子 / 棋子样式 / 棋子符号).
   Apple's structure avoids the repetition by putting the shared noun in the rows and the shared concept in the
   group.

**Correction.** Either fix the sentence to "Apple's precedent is: named, localized, grouped, explained — I keep
those four properties and reorganize the hierarchy for a scrolling list, at the cost of naming a board control
the group does not contain", or reconsider a group whose label does not promise a board row. This is a
designer's call, not the owner's; I am flagging the unpriced cost, not choosing.

---

## F15 — the 58 → 62 inventory assumes one outcome of Owner decision 1. SEVERITY: LOW

**Report, §5.1 / §8:** *"the count of distinct accepted Chinese strings in `interaction-design.md` goes from
**58 to 62**"*, presented flatly.

**What is wrong.** 62 is right only under Owner 1(a) (rename in the contract) or 1(c) (ship 高对比). Under 1(b)
(*"Keep both — 高对比 stays the internal short name, 高对比度 is the string"*) both terms exist and the count is
**63**, which is also the outcome that creates the very "Chinese internal design name" category §1.1 says does
not exist. The report offers 1(b) as a live option and then hands 6.1 a number that silently excludes it.

**Correction.** State the figure per branch, or say "62 under the recommended branch".

---

## Two things the report defers that are already decided, and one it settles that is not its to settle

- **Already decided, contra §9's product.md row.** The report writes *"Strictly no change — it defers
  correctly"* and then, in the same cell, asks for a change (*"it should either name 传统 or say 'the
  first-listed'"*). `product.md:82` reads *"defaulting to the traditional one"*, which is an English gloss and
  will be a *translation* once 传统 is accepted copy; `interaction-design.md:455` already settles that Chinese
  is the source and English its counterpart, so this is not a judgement call left open — the gloss has to become
  a counterpart of 传统 or a positional reference. Pick one in the cell rather than saying both.
- **Already open, contra §5.4's framing.** Covered in F4: the narrowest supported iPhone is `:514`.
- **Settled here that is not this item's to settle.** `interaction-design.md:535` asks two things: user-facing
  or internal, and approve the wording *if* user-facing. The group label, the two row labels, and the footer are
  four strings the question does not ask for, and `:209` is the only accepted Settings group in the contract.
  The report is candid that they are new, and §9 correctly asks for a new accepted paragraph — but the summary's
  *"Naming is settled; showing is scope"* elides that a new Settings group's *existence* (as against its
  wording) is a structural addition to an accepted document, not a naming consequence. Worth one sentence
  saying so, so the main thread does not accept a group by accepting a label.

---

## On the Chinese copy specifically

Checked against register, against the accepted strings, and for whether each says what §5.2 says it says.

- **传统 / 现代 / 汉字 / 图标** — idiomatic, correct, and consistent with the accepted register. 现代 is attested
  in this exact product category (chessroad's 现代简约, verified). **No objection.**
- **高对比度** — the amendment is right on the Chinese. 对比 alone is not what a Simplified Chinese label uses;
  every Apple zh_CN form in the extracted table ends in 度. The recommendation survives F1 — F1 changes the
  *reason*, not the string.
- **棋子样式 / 棋子符号** — both idiomatic; 棋子样式 is independently attested (Lichess, verified). **No
  objection.**
- **棋盘和棋子** — grammatical and echoes Chess's 选择棋盘和棋子的样式。 correctly, including 和 over 与. My
  objection is F14's, about what the label promises, not about the Chinese.
- **The footer.** 棋子样式同时决定棋盘的配色。无论选择哪种样式，App 都会遵循系统的"增强对比度"设置。 says what
  §5.3 claims it says, and both facts are accurate to the contract (:80 for the board, :98 for Increase
  Contrast). Register is consistent with the accepted copy: full-width 。and ，, spaces around the Latin run
  `App` exactly as 当前可用内存不足。请尝试关闭一些其他 App，然后重试。 does, zh_CN curly quotes. **The English
  counterpart matches the Chinese** — no drift, no added or dropped claim. The problems are F3 (length) and F2
  (the stated rationale), not the sentence's meaning.
- **Irreversible-action consequences: not applicable, and correctly so.** Neither row is destructive; both are
  presentation preferences that `:78` and `:110` accept as changing presentation only. Nothing here needs the
  treatment `product.md:62` / `game-data.md:125` give deletion, and the report does not claim otherwise.
- **One terminology check the report does not make and should.** `interaction-design.md:459` requires
  terminology consistency *within each language*. The accepted Chinese already uses 棋子 for a piece throughout,
  and the proposed strings are consistent with it. But the accepted document also uses **汉字** at :108 to name
  the symbol set while `product.md:83`'s English says "Chinese characters" — so 汉字 ↔ *Chinese Characters* is
  already the de facto pair and §5.2 is right to keep it. Recording that as a positive check, since §9 asks for
  :459 to be generalized and a reviewer may wonder whether the generalization is load-bearing. It is not: the
  proposed strings pass :459 as written.

---

## Verdict

**NEEDS WORK — the conclusion is sound, three of its supports are not.**

The core answer is right and I would not reopen it: the names are user-facing, four of the five words survive,
and 高对比 → 高对比度 is a correct fix. The extractions, the measurements, and every Apple citation are clean —
unusually so; I could not find a fabricated citation or a mis-transcribed string anywhere.

But three claims should not ship in their current form. **F1** mischaracterizes the string collision that the
report makes the pivot of the entire item, and the mischaracterization inflates Owner decision 3. **F3** and
**F4** are numbers pointed at the wrong comparison and the wrong device — the register claim is refuted by the
report's own measurement, and the layout consequence is derived from a 320 pt phone that `product.md:19`'s
platform floor excludes and that `interaction-design.md:514` leaves open in any case. **F2** and **F5** are
internal contradictions: the report affirms and denies the high-contrast style's accessibility purpose, and
§1.1's stated convention is contradicted by §8 and by seven bolded English UI names in the contract.

Fixing F1–F5 does not change the recommendation. It changes what the owner is being asked to buy in decision 3,
removes a layout consequence that part 4 would otherwise inherit as a constraint, and leaves §1.1 with an
argument that is narrower and actually true.
