# Layout budget — measured

Workspace research note. Not a contract, not a proposal to merge. It exists so that the minimum
window size, the layout breakpoint, and the 44-point pitch floor can be written from evidence rather
than from remembered constants, after PR #23 was rejected with thirteen blocking findings
(`discussion-drafts/review-pr23.md`), most of which trace to a number fixed without checking what
depended on it.

Nothing under `MiniXiangqi/` or any `wt-*` worktree was modified. No Git or GitHub state was changed.

## How to read this

Every number below carries one of three labels, and the label is load-bearing:

- **Measured** — produced by a probe I built and ran in this workspace, on the pinned toolchain.
  The probe sources are in `discussion-drafts/layout-probe/`; each table names the probe and the
  device.
- **Documented** — read from Apple documentation through the Xcode 27 beta documentation tool, quoted
  with its title and anchor.
- **Reasoned** — arithmetic over measured or documented inputs, or an inference. Marked as such, with
  its inputs named.

**Toolchain.** Xcode 27.0 build `27A5228h`, `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`.
Host macOS 27.0 build `26A5388g`. iOS SDK 27.0 (`23A344`).

**The one caveat that colours everything.** Xcode `27A5228h` ships exactly one iOS runtime —
**iOS 27.0 (`24A5390f`)** — so every iOS/iPadOS measurement below was taken on iOS 27.0, not on the
26.5 the product targets. iOS 26 and 27 are the same design generation (Liquid Glass, the floating
tab bar, the iPad windowing model), so I expect the chrome values to match, but that expectation is
**reasoned, not measured**. Before any number here is written into a contract it should be
re-measured on an iOS 26.5 runtime or on hardware. I say so once here and do not repeat it per table.

---

## 1. The real device list

### 1.1 How membership of the 26.5 list was established

**Measured.** CoreSimulator's device-type catalogue records, per device model, the runtime version
range that model supports. `xcrun simctl list devicetypes --json` reports `minRuntimeVersion` and
`maxRuntimeVersion` as packed integers, `(major << 16) | (minor << 8) | patch`:

| packed | decodes to |
|---|---|
| `1703936` | 26.0 |
| `1704704` | 26.3 |
| `1729280` | 26.99 — supported through iOS/iPadOS 26, dropped in 27 |
| `4294967295` | unbounded — supports 27 and later |
| `1204992` | 18.99 — last supported release was iOS 18 |

A device is on the 26.5 list exactly when `minRuntimeVersion ≤ 26.5 ≤ maxRuntimeVersion`. This is
authoritative for the question asked: it is Apple's own declared support window for each model,
shipped inside the toolchain the project pins.

Two sanity checks that the decoding is right, both matching Apple's published compatibility lists:
iPhone XR / XS / XS Max carry `max = 18.99` (iOS 26 did drop them), and iPad (7th generation) carries
`max = 18.99` while iPad (8th generation) carries `max = 26.99` (iPadOS 26 supports 8th generation
and later).

**Reasoned.** Apple does not drop device models in a point release, so the 26.5 list equals the 26.0
list. I could not verify that directly — 26.5 does not exist in this toolchain — but no counterexample
exists in Apple's release history.

**The trap PR #23's review fell into.** The review derived its device list from "the iOS 27 runtime",
which is the *wrong superset direction*. Five iPads run 26.5 but not 27, and the review's iPad tables
omit all five — including the physically smallest iPad canvas in the whole list.

### 1.2 iPhone — the 26.5 list, with point dimensions

Membership is **measured** (runtime bounds). Point dimensions are **measured** on the simulator
(`layout-probe/main.swift`, `UIWindowScene.screen.bounds`) for the ten screen classes I ran; the
remainder are **documented** (HIG *Layout: iOS, iPadOS device screen dimensions*) and assigned to a
measured class.

| UIKit points (portrait) | devices on the 26.5 list | dimension source |
|---|---|---|
| **375 × 667** | iPhone SE (2nd generation), iPhone SE (3rd generation) | measured |
| **375 × 812** | iPhone 11 Pro, iPhone 12 mini, iPhone 13 mini | measured (13 mini) |
| **390 × 844** | iPhone 12, 12 Pro, 13, 13 Pro, 14, 16e, **17e** | measured (17e) |
| **393 × 852** | iPhone 14 Pro, 15, 15 Pro, 16 | measured (16) |
| **402 × 874** | iPhone 16 Pro, 17, 17 Pro | measured (16 Pro) |
| **414 × 896** | iPhone 11, iPhone 11 Pro Max | measured (11) |
| **420 × 912** | iPhone Air | measured |
| **428 × 926** | iPhone 12 Pro Max, 13 Pro Max, 14 Plus | measured (14 Plus) |
| **430 × 932** | iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus | measured (16 Plus) |
| **440 × 956** | iPhone 16 Pro Max, 17 Pro Max | measured (17 Pro Max) |

**Narrowest width: 375 pt.** Three device families sit there — the SE at 667 tall and the
11 Pro / 12 mini / 13 mini at 812 tall.

**Shortest height: 667 pt — iPhone SE (2nd and 3rd generation).** This is the number the whole
budget turns on, and it is a *different device* from the narrowest-width one only in the sense that
the SE is both narrowest and shortest; the mini shares the width but not the height.

**iPhone 17e is not in the HIG table** (it is newer than the documentation in this toolchain).
Measured: **390 × 844**, scale 3.0, native bounds 1170 × 2532. That is the 16e / iPhone 14 class.

#### The 360 × 780 trap — resolved by measurement

Apple's HIG table lists **iPhone 13 mini and 12 mini as `360x780 pt (1080x2340 px @2x/@3x)`**. The
simulator measures something else:

```
screen.bounds=375.00x812.00  scale=3.00  nativeScale=2.88  nativeBounds=1080.00x2340.00
```
*(measured, `MXQ-13mini`, iOS 27.0)*

The mini renders a 375 × 812 point coordinate space at scale 3.0 into a 1125 × 2436 buffer and the
display engine downsamples it to the physical 1080 × 2340 panel — hence `nativeScale = 2.88`. The HIG
row is describing physical pixels divided by the nominal scale factor; **it is not the coordinate
space the app lays out in.** The layout-relevant width of a 13 mini is **375**, not 360.

The PR #23 review listed the mini as 375 × 812 and was right, by accident — its cited *table* is wrong
in both directions (it also omits the SE's 667 pt height from its argument). The HIG table is wrong for
this purpose. Only the measurement settles it. If anyone later "corrects" the contract to 360 pt on
the strength of the HIG table, this section is why they should not.

### 1.3 iPad — the 26.5 list, with point dimensions

Membership **measured** (runtime bounds). Dimensions **documented** (HIG table) except where a
measurement is noted.

| UIKit points (portrait) | devices on the 26.5 list | runs 27? |
|---|---|---|
| **744 × 1133** | iPad mini (6th generation), iPad mini (A17 Pro) | yes — *measured* |
| **768 × 1024** | **iPad mini (5th generation)** | **no — 26 only** |
| **810 × 1080** | **iPad (8th generation)**, iPad (9th generation) | 8th: **no**; 9th: yes |
| **820 × 1180** | iPad (10th gen), iPad (A16), iPad Air (4th/5th gen), iPad Air 11″ M2/M3/M4 | yes — *measured* |
| **834 × 1112** | **iPad Air (3rd generation)** | **no — 26 only** |
| **834 × 1194** | **iPad Pro 11″ (1st gen)**, iPad Pro 11″ (2nd–4th gen) | 1st: **no**; rest: yes |
| **834 × 1210** | iPad Pro 11″ (M4), iPad Pro 11″ (M5) | yes |
| **1024 × 1366** | **iPad Pro 12.9″ (3rd gen)**, 12.9″ (4th–6th gen), iPad Air 13″ M2/M3/M4 | 3rd: **no**; rest: yes |
| **1032 × 1376** | iPad Pro 13″ (M4), iPad Pro 13″ (M5) | yes — *measured* |

The five bolded 26-only models are the ones a list built from the iOS 27 runtime silently loses.

**Narrowest iPad width: 744 pt** — iPad mini (6th generation / A17 Pro), portrait.
**Shortest iPad height: 768 pt** — iPad mini (5th generation), landscape.
**Smallest iPad canvas overall: 768 × 1024** — iPad mini (5th generation). It has the shortest
portrait height (1024) *and* the shortest landscape height (768) of any supported iPad, and it is
absent from every table in the PR #23 review.

### 1.4 Narrowest and shortest, stated plainly

| quantity | value | device |
|---|---|---|
| narrowest supported width, any device | **375 pt** | iPhone SE (2nd/3rd gen); also 11 Pro, 12 mini, 13 mini |
| shortest supported height, any device | **667 pt** | iPhone SE (2nd/3rd gen) |
| narrowest supported iPad, portrait | 744 pt | iPad mini (6th gen), iPad mini (A17 Pro) |
| shortest supported iPad canvas dimension | 768 pt | iPad mini (5th gen), landscape height |

---

## 2. The chrome inventory, measured

Probe: `layout-probe/main.swift` (UIKit `UITabBarController` + `UINavigationController`) and
`layout-probe/swiftui.swift` (SwiftUI `TabView(...).tabViewStyle(.sidebarAdaptable)` — the exact
container `interaction-design.md` adopts). Both were run as scene-lifecycle apps; the iOS 26 SDK
refuses to launch an app without one (*measured*: `UIScene life cycle is required for apps built with
this SDK`).

Both probes agree on every number, which is worth stating: the UIKit container and the SwiftUI
`sidebarAdaptable` container cost the same.

### 2.1 iPhone, portrait — measured

| screen | status bar / top safe area | tab-bar contribution to bottom safe area | inline nav bar | **content height, nav bar present** | **content height, no nav bar** |
|---|---|---|---|---|---|
| 375 × 667 | 20 | 83 | 54 | **510** | **564** |
| 375 × 812 | 50 | 83 | 54 | 625 | 679 |
| 390 × 844 | 47 | 83 | 54 | 660 | 714 |
| 393 × 852 | 59 | 83 | 54 | 656 | 710 |
| 402 × 874 | 62 | 83 | 54 | 675 | 729 |
| 414 × 896 | 48 | 83 | 54 | 711 | 765 |
| 420 × 912 | 68 | 83 | 54 | 707 | 761 |
| 428 × 926 | 47 | 83 | 54 | 742 | 796 |
| 430 × 932 | 59 | 83 | 54 | 736 | 790 |
| 440 × 956 | 62 | 83 | 54 | 757 | 811 |

Four things in that table matter, and three of them contradict what PR #23 assumed:

1. **The navigation container costs 83 pt, not 49.** The review's illustrative arithmetic used a
   49 pt tab bar. Measured, the iOS 26/27 tab bar contributes **83 pt** to the content's bottom safe
   area on *every* iPhone, whether or not the device has a home indicator. On the SE
   (`window.safeAreaInsets.bottom = 0`) that is 83 pt of pure tab bar; on the 13 mini
   (`bottom = 34`) it is 49 pt of bar plus the 34 pt indicator. The tab bar does **not** float free
   of the layout on iPhone: it is inside the safe area, so content laid out to the safe area is
   already clear of it. The review's 1.2 finding was right that the container was omitted, and
   understated it by 34 pt.
2. **A navigation bar costs another 54 pt** (inline title), or **106 pt** with `prefersLargeTitles`
   (*measured*, SE: `navBar.frame.height = 106`, content top inset 126). Whether the board page
   carries one is not stated anywhere in the contract, and it is worth **54 pt** — more than the
   entire play-control row.
3. **Neither grows with Dynamic Type.** At `accessibilityExtraExtraExtraLarge` the tab bar is still
   83.00 and the inline nav bar still 54.00 on every device measured. Chrome growth at accessibility
   sizes comes entirely from the app's own elements, not from the system containers.
4. **The top inset is not monotone in screen size.** iPhone Air is 68, iPhone 17 Pro Max 62, iPhone
   14 Plus 47. A budget cannot be derived from screen height alone.

iPhone landscape is out of scope (`product.md`: portrait only), but for completeness, *measured* on a
13 mini: top 0, bottom 20, left/right 50, tab bar 64, content 712 × 233 with a nav bar.

### 2.2 iPad, full screen — measured

| iPad | screen | window safe area top / bottom | adaptive tab container | content height, nav bar | content height, tab only | horizontal cost |
|---|---|---|---|---|---|---|
| mini (6th gen) | 744 × 1133 | 32 / 20 | 64, at the **top** | 1027 | 1017 | **0** |
| iPad (A16) | 820 × 1180 | 32 / 20 | 64 | 1074 | 1064 | **0** |
| iPad Pro 13″ (M5) | 1032 × 1376 | 32 / 20 | 64 | 1270 | 1260 | **0** |

**Total iPad vertical chrome: 106 pt** with an inline navigation bar, **116 pt** with the tab
container alone. (The two differ because with a `NavigationStack` inside the tab, the top tab bar
and the navigation bar share one 54 pt row rather than stacking; *measured*, not explained by any
documentation I found.)

**The sidebar never appeared.** At 744, 820 and 1032 points of width, `TabView` with
`.tabViewStyle(.sidebarAdaptable)` presented as a **top tab bar** and the content's leading inset was
**0.00** at every width. This is a *measured* refutation of a premise the review's finding 2.4 rests
on: as configured by default, the adaptive navigation container costs **height on iPad, not width**,
so the "layout rule ⇄ navigation presentation" oscillation band the review describes does not arise
from the platform container. It could still arise if the app forces a sidebar. It is consistent with
the HIG (*Layout: iPadOS*): "The app first launches with **your choice** of a sidebar or a tab bar,
and then people can tap to switch between them" — the sidebar is a user choice, not a width outcome.

### 2.3 macOS — measured

Host: macOS 27.0 (`26A5388g`). Probe: `layout-probe/macprobe.swift`.

The machine this ran on **is** the configuration `interaction-design.md` names as its worst case:

```
SCREEN frame=1024.00x663.00  visibleFrame=1024.00x582.00  backingScale=2.00
  menu bar + Dock consumed: height 81.00
```

So the contract's "1024 by 663 … leaves a window of 1024 by 582" is **confirmed by measurement**, and
so is the 550 figure — but only for one of five window configurations:

| window configuration | chrome above content | max content height on this display |
|---|---|---|
| title bar only | **32** | **550** |
| title bar + `.unifiedCompact` toolbar | **40** | 542 |
| title bar + `.unified` / `.automatic` toolbar | **66** | **516** |
| title bar + `.expanded` toolbar | 83 | 499 |
| title bar + `.preference` toolbar | 88 | 494 |

The contract's 550 assumes **no toolbar**. A Mac app of this shape would ordinarily have one, and a
standard unified toolbar costs 34 pt more than the contract budgets. Side chrome is **0** in every
configuration.

Also *measured*: `NSWindow.contentMinSize` does **not** clamp a programmatic `setContentSize` — a
window asked for 100 × 100 with `contentMinSize = 380 × 500` reported content 100 × 100. The minimum
bounds *interactive* resizing only. Same semantics as iPadOS (§5).

### 2.4 Element heights — measured, with the accepted copy

Probe `layout-probe/probe3.swift`, iPhone SE (3rd gen), iOS 27.0, measured at 375 pt of width, using
the Chinese strings accepted in `interaction-design.md` on `main` and standard SwiftUI controls
(`.bordered` / `.borderedProminent`, `.controlSize(.large)`, 16 pt horizontal and 8 pt vertical
padding). These are *what standard components cost*, i.e. a floor for the real design, not the real
design's values.

| element | L (default) | xxxL | AX1 | AX3 | AX5 |
|---|---|---|---|---|---|
| turn status (轮到红方 · AI · 将军) | **36.5** | 43.5 | 49.5 | 64.0 | 141.5 |
| play-control row (悔棋 · 判和 · 认输) | **66.5** | 73.5 | 79.5 | 142.0 | 171.5 |
| result card (红方获胜 / reason / 悔棋 · 结束对局) | **127.0** | 148.5 | 166.5 | 206.0 | 313.0 |
| result card, recorded (回放 · 完成) | 127.0 | 148.5 | 166.5 | 206.0 | 251.0 |
| threefold notice (局面已三次重复… / 继续对局 · 以和棋结束) | **95.0** | 138.0 | 155.0 | 246.0 | 429.0 |
| replay transport, 5 controls + 翻转棋盘 | **65.5** | 72.0 | 71.5 | 81.5 | 93.5 |
| transport + autoplay-speed control | 104.5 | 111.0 | 110.5 | 120.5 | 132.5 |
| one move-list row (120. 炮二平五 … 马８进７) | **32.5** | 68.5 | 79.5 | 156.0 | 261.5 |
| game-metadata line, terminal form | 16.0 | 23.0 | 27.5 | 39.5 | 53.0 |

The same elements on macOS are much smaller (*measured*, `macprobe`): turn status **32**, control row
**44**, result card **107**, move row **28**, metadata **13**, transport **43**. macOS and iOS
therefore need *different* minimums; §6 returns to this.

Two measured facts about growth worth flagging: the play-control row **wraps** below 308 pt of width
even at default text (h@276 = 88.5 vs h@308 = 66.5), and the result card's own contribution roughly
**doubles** between L and AX3. The card is the element the whole budget is most sensitive to.

### 2.5 The board block

**Accepted contract** — `design/frame-motion-glass` merged to `main` as PR #24 while this note was
being written, so the strip geometry is no longer a proposal and the PR #23 review's finding 1.4
("the requirement depends on a value the same document says is not accepted") no longer applies.
`interaction-design.md:153–157` on `main` now states: numeral size `s = clamp(0.32 p, 13, 20)`
rounded to the nearest point; strip height `= 0.08 p + 0.887 s`, rounded; both strips shown or both
hidden; strips hidden at accessibility text sizes, "returns 32 points of height at the floor", and —
directly relevant here — "**Whether that is enough for every supported device at the largest text
sizes is settled by the layout bounds, not here.**" §3.5 is that settlement.

*Reasoned, from those formulas:* at `p = 44`, `s = 14.08` and strip `= 3.52 + 12.49 = 16.01`, so the
board block is `308 × 340`. That matches the branch's own claim ("16 points at the floor, giving a
board block of 308 by 340 points there") exactly, and confirms the branch's "hiding them removes
32 points of height".

So: **board block = 340 pt tall with numerals, 308 pt without. Board block width = 308 pt in both
cases** — the strips are horizontal, so they cost height only. The PR #23 review's finding 1.5 is
right about that.

---

## 3. The vertical budget

*Reasoned* arithmetic over §2's measured inputs. Composition: `board block + Σ(elements) + n × 12 pt`
where 12 pt is one standard inter-element gap and each element already carries its own 8 pt padding.
Numeral strips shown at L and xxxL, hidden at AX1 and above (per `design/frame-motion-glass`).

### 3.1 What each state costs at the 44 pt floor, default text

| stacked state | composition | total height |
|---|---|---|
| ordinary play | 340 + 36.5 (status) + 66.5 (controls) + 24 | **467.0** |
| threefold-repetition notice replacing the controls | 340 + 36.5 + 95.0 + 24 | **495.5** |
| replay, minimum (transport + one move row) | 340 + 36.5 + 65.5 + 32.5 + 36 | **510.5** |
| natural-result card replacing the controls | 340 + 36.5 + 127.0 + 24 | **527.5** |
| replay, full (transport + speed + three move rows) | 340 + 36.5 + 104.5 + 97.5 + 48 | **626.5** |
| result card *plus* the control row (side-by-side-like) | 340 + 36.5 + 66.5 + 127.0 + 36 | **606.0** |

The control row is the **cheapest** of the six. A minimum validated against it — which is what PR #23
did — is validated against the best case, not the binding one. The review's finding 1.3 is confirmed
with numbers: the result card costs **60.5 pt more** than the control row, and stacked replay costs
**160 pt more**.

### 3.2 Does it fit? — every supported iPhone, default text, board page carrying a navigation bar

Slack = content height − required height. Negative means the 44 pt floor cannot hold.

| screen | content | play | result card | threefold | replay min | replay full |
|---|---|---|---|---|---|---|
| **375 × 667** | 510 | +43.0 | **−17.5** | +14.5 | **−0.5** | **−116.5** |
| 375 × 812 | 625 | +158.0 | +97.5 | +129.5 | +114.5 | **−1.5** |
| 390 × 844 | 660 | +193.0 | +132.5 | +164.5 | +149.5 | +33.5 |
| 393 × 852 | 656 | +189.0 | +128.5 | +160.5 | +145.5 | +29.5 |
| 402 × 874 | 675 | +208.0 | +147.5 | +179.5 | +164.5 | +48.5 |
| 414 × 896 | 711 | +244.0 | +183.5 | +215.5 | +200.5 | +84.5 |
| 420 × 912 | 707 | +240.0 | +179.5 | +211.5 | +196.5 | +80.5 |
| 428 × 926 | 742 | +275.0 | +214.5 | +246.5 | +231.5 | +115.5 |
| 430 × 932 | 736 | +269.0 | +208.5 | +240.5 | +225.5 | +109.5 |
| 440 × 956 | 757 | +290.0 | +229.5 | +261.5 | +246.5 | +130.5 |

### 3.3 The same, with **no navigation bar** on the board page

| screen | content | play | result card | threefold | replay min | replay full |
|---|---|---|---|---|---|---|
| **375 × 667** | 564 | +97.0 | **+36.5** | +68.5 | +53.5 | **−62.5** |
| 375 × 812 | 679 | +212.0 | +151.5 | +183.5 | +168.5 | +52.5 |
| 390 × 844 | 714 | +247.0 | +186.5 | +218.5 | +203.5 | +87.5 |
| 393 × 852 | 710 | +243.0 | +182.5 | +214.5 | +199.5 | +83.5 |
| 402 × 874 | 729 | +262.0 | +201.5 | +233.5 | +218.5 | +102.5 |
| 414 × 896 | 765 | +298.0 | +237.5 | +269.5 | +254.5 | +138.5 |
| 420 × 912 | 761 | +294.0 | +233.5 | +265.5 | +250.5 | +134.5 |
| 428 × 926 | 796 | +329.0 | +268.5 | +300.5 | +285.5 | +169.5 |
| 430 × 932 | 790 | +323.0 | +262.5 | +294.5 | +279.5 | +163.5 |
| 440 × 956 | 811 | +344.0 | +283.5 | +315.5 | +300.5 | +184.5 |

**Removing the navigation bar from the board page is worth 54 pt and turns the SE's result-card
failure (−17.5) into a pass (+36.5).** That is the single cheapest fix available, and it costs
nothing the contract has committed to — no accepted text places a navigation bar on the board page.

### 3.4 The pitch each state would need on the SE, when it does not fit

*Reasoned*, solving `block(p) ≤ available` for `p`:

| SE state | with nav bar (content 510) | without nav bar (content 564) |
|---|---|---|
| ordinary play | p ≤ 49.6 — floor holds | p ≤ 56.5 — floor holds |
| result card | **p ≤ 41.7** | p ≤ 48.7 — floor holds |
| threefold notice | p ≤ 45.9 — holds | p ≤ 52.9 — holds |
| replay, transport + one move row | **p ≤ 43.9** | p ≤ 50.2 — holds |
| replay, transport + speed + three rows | **p ≤ 29.7** | **p ≤ 37.2** (strips hidden: 41.4) |

### 3.5 How far Dynamic Type can grow before the 44 pt floor breaks

The largest Dynamic Type size at which `p = 44` still fits, per device per state. *Reasoned* over the
measured element table; strips hidden from AX1 upward.

**Board page with a navigation bar:**

| screen | play | result card | threefold | replay min | replay full |
|---|---|---|---|---|---|
| **375 × 667** | AX1 | **never** | L | **never** | **never** |
| 375 × 812 | AX3 | AX3 | AX1 | AX1 | **never** |
| 390 × 844 | AX5 | AX3 | AX3 | AX3 | L |
| 393 × 852 | AX5 | AX3 | AX3 | AX3 | L |
| 402 × 874 | AX5 | AX3 | AX3 | AX3 | L |
| 414 × 896 | AX5 | AX3 | AX3 | AX3 | L |
| 420 × 912 | AX5 | AX3 | AX3 | AX3 | L |
| 428 × 926 | AX5 | AX3 | AX3 | AX3 | L |
| 430 × 932 | AX5 | AX3 | AX3 | AX3 | L |
| 440 × 956 | AX5 | AX3 | AX3 | AX3 | AX1 |

**Board page without a navigation bar:**

| screen | play | result card | threefold | replay min | replay full |
|---|---|---|---|---|---|
| **375 × 667** | AX3 | AX1 | AX1 | AX1 | **never** |
| 375 × 812 | AX5 | AX3 | AX3 | AX3 | L |
| 390 × 844 and every larger screen | AX5 | AX3–AX5 | AX3 | AX3 | L–AX1 |

Read plainly:

- **No supported iPhone holds `p = 44` in every accepted state at every text size.** The best case
  (440 × 956, no nav bar) still fails full stacked replay above AX1.
- **The iPhone SE cannot hold `p = 44` in stacked replay at any text size**, even with the numeral
  strips hidden and no navigation bar. It is short by 18.5 pt in the most favourable configuration.
- The SE holds `p = 44` for ordinary play up to **AX3** and for the result card up to **AX1**.

### 3.6 macOS, on the display the contract names as its worst case

*Reasoned*, using the **measured macOS** element heights (§2.4), which are much smaller than iOS's.
Available content height: 550 (no toolbar), 542 (`unifiedCompact`), 516 (`unified`).

| stacked state | required | 550 | 542 | 516 |
|---|---|---|---|---|
| ordinary play (340 + 32 + 44 + 24) | **440** | ✓ +110 | ✓ +102 | ✓ +76 |
| threefold notice (340 + 32 + ~85 + 24) | ~481 | ✓ | ✓ | ✓ |
| result card (340 + 32 + 107 + 24) | **503** | ✓ +47 | ✓ +39 | ✓ **+13** |
| replay, transport + three rows (340 + 32 + 43 + 84 + 36) | **535** | ✓ +15 | ✓ +7 | **✗ −19** |
| replay, transport + speed + three rows | **~575** | **✗ −25** | **✗ −33** | **✗ −59** |

So on the largest-text Mac display setting, at `p = 44`:

- ordinary play and the result card fit — the review's worry that they might not is *not* borne out,
  because macOS controls are far smaller than iOS controls;
- **full stacked replay does not fit**, by 25 pt without a toolbar and 59 pt with one;
- with a standard unified toolbar the result card leaves **13 pt** of slack in a 516 pt window. That
  is not a budget, it is a coincidence.

In practice a 1024-pt-wide Mac window is side-by-side (§4), so the Mac reaches these stacked states
only when the user narrows the window — which is precisely what the minimum window size governs.

---

## 4. The panel's minimum width

No contract states one. `interaction-design.md` lists the panel's contents — "the turn status, the
move list, game metadata, and controls" — so a minimum can be *derived* from them, which is what
`:457` implicitly promises and never delivers.

### 4.1 Derivation

**Measured** ideal (untruncated) widths of the four stated contents, accepted copy, iPhone metrics,
`probe3.swift`:

| panel content | L | xxxL | AX1 | AX3 |
|---|---|---|---|---|
| turn status | 167.5 | 203.0 | 233.5 | 308.0 |
| one move-list row | 239.0 | 280.0 | 318.0 | 407.0 |
| game metadata — ongoing form | 289.0 | 400.5 | 456.5 | 635.0 |
| **game metadata — terminal form** | **320.0** | **445.5** | **509.5** | **711.5** |
| control row (悔棋 · 判和 · 认输) | 278.0 | 308.0 | 348.5 | 440.0 |
| *(replay transport + 翻转棋盘)* | *481.0* | *528.0* | *543.5* | *666.0* |

**The game-metadata line drives the panel's minimum**, at **320 pt** at default text. That is a
defensible, reproducible number and it names its own driver, which is what finding 2.1 asked for.

Two caveats a contract must settle rather than inherit:

- **Truncation.** 320 pt is the width at which the *terminal* metadata line fits on one line without
  truncating. If the metadata is allowed to truncate or wrap, the control row (278) becomes the
  driver and the panel minimum is **280 pt**.
- **Replay.** If the replay transport lives in the panel in side-by-side, the panel minimum is
  **481 pt** — half again as large. Nothing in the contract says where the transport goes in
  side-by-side.

### 4.2 The width at which side-by-side becomes possible

*Reasoned:* `threshold = board core + panel minimum + outer margin + gutter + outer margin`, with the
16 pt layout margin **measured** on every device (`view.layoutMargins.left = 16.00`).

| panel minimum | driver | threshold = 308 + panel + 48 |
|---|---|---|
| 280 (metadata may truncate) | control row | **636 pt** |
| **320 (metadata untruncated)** | terminal metadata line | **676 pt** |
| 446 (untruncated at xxxL) | terminal metadata line | 802 pt |
| 481 (transport in the panel) | replay transport | 837 pt |

PR #23's "the switch falls near 700 points" is **reproducible only under the third-column assumption**
(panel ≈ 320–345, gutters ≈ 48). At the derived 320 pt panel minimum the honest figure is **676**, not
700. Finding 2.2 is confirmed: the 700 was not recomputable, and it is 24 pt off the value its own
inputs imply.

### 4.3 Every supported iPad, checked

The available width is the scene width: the adaptive navigation container took **0 pt** of horizontal
space at every iPad width measured (§2.2), and window safe-area left/right are 0.

| iPad | portrait W | landscape W | side-by-side at 636? | at 676? | at 802? |
|---|---|---|---|---|---|
| iPad mini (6th gen / A17 Pro) | 744 | 1133 | both | both | landscape only |
| iPad mini (5th gen) | 768 | 1024 | both | both | landscape only |
| iPad (8th / 9th gen) | 810 | 1080 | both | both | both |
| iPad (10th gen / A16 / Air 11″) | 820 | 1180 | both | both | both |
| iPad Air (3rd gen) | 834 | 1112 | both | both | both |
| iPad Pro 11″ (1st–4th gen) | 834 | 1194 | both | both | both |
| iPad Pro 11″ (M4 / M5) | 834 | 1210 | both | both | both |
| iPad Pro 12.9″ / Air 13″ | 1024 | 1366 | both | both | both |
| iPad Pro 13″ (M4 / M5) | 1032 | 1376 | both | both | both |

**Every supported iPad, in both orientations, at full screen, is side-by-side** under any panel
minimum up to 436 pt — because the narrowest iPad canvas is 744 pt and `744 − 308 − 48 = 388`. The
retained accepted sentence "**Stacked**, used by iPhone portrait and by narrow windows *including iPad
portrait*" is therefore false for every supported iPad at full screen, at the derived panel minimum.
Finding 2.3 is confirmed, and quantified: **the panel minimum would have to exceed 388 pt for iPad
mini portrait to be stacked**, which happens only at xxxL text and above.

Conversely, **no iPhone is ever side-by-side**: the widest supported iPhone is 440 pt, far below even
the 636 pt threshold. The stacked layout is the iPhone layout, unconditionally. That is a useful,
measured invariant the contract can rely on.

---

## 5. What a declared minimum scene size actually does on iPadOS 26

### 5.1 Documented

- HIG *Layout: iPadOS*: "People can freely **resize windows down to a minimum width and height,
  similar to window behavior in macOS**."
- *Multitasking on iPad, Mac, and Apple Vision Pro — Adapting to different window sizes*: "Since
  people can resize your app's window, **set a minimum size** for your window with
  `UISceneSizeRestrictions`."
- `UIWindowScene.sizeRestrictions`: "When the value of this property is **not `nil`**, use it to
  change the default minimum and maximum window sizes for your app. **If the value of this property
  is `nil`, the system doesn't allow you to set window size restrictions.**"
- HIG *Multitasking: iPadOS*, note: "**Apps don't control multitasking configurations** or receive
  any indication of the ones that people choose."
- HIG *Layout: iPadOS*: "Window controls provide the option to arrange windows to fill **halves,
  thirds, and quadrants** of the screen, so it's important to check your layout at each of these
  sizes on a variety of devices."

### 5.2 Measured

Probe `layout-probe/probe4.swift`, iOS 27.0 simulator:

| observation | iPhone SE | iPad mini (6th gen) | iPad (A16) |
|---|---|---|---|
| `windowScene.sizeRestrictions` | **`nil`** | non-`nil` | non-`nil` |
| default `minimumSize` | — | `0 × 0` | `0 × 0` |
| default `maximumSize` | — | unbounded | unbounded |
| `allowsFullScreen` default | — | `true` | `true` |
| after `minimumSize = 380 × 500`, read back immediately | — | `0 × 0` | `0 × 0` |
| after 3 s | — | **`380 × 500`** | **`380 × 500`** |
| `minimumSize.width = 640` after that | — | `640 × 500` | `640 × 500` |
| `allowsFullScreen = false` accepted | — | yes | yes |
| scene size after all of the above | — | still `744 × 1133` | still `820 × 1180` |

Three things follow, and they settle finding 3.1:

1. **On iPhone the app cannot declare a minimum at all.** `sizeRestrictions` is `nil`. Any contract
   sentence of the form "the app declares that minimum to iOS" is false for iPhone.
2. **On iPad the declaration is accepted, applied asynchronously, and bounds resizing.** It does not
   make the app "unavailable"; the scene keeps its full-screen size. PR #23's "available at the wider
   multitasking widths but not the narrowest" describes a behaviour the platform does not have. The
   correct statement is the review's: *a window cannot be resized below it*.
3. **What the system does when a user picks a tile smaller than the declared minimum is still not
   established.** The documentation does not say, and I could not observe it: it needs a person
   dragging window controls on a device or in Simulator's UI. The honest contract sentence is that
   the window stops resizing at the minimum, plus a testing gate that *records* the tiling behaviour
   as a measurement rather than asserting it. Note also that "Apps don't control multitasking
   configurations" makes it unlikely the system omits a tile option; clamping or overlapping is the
   more probable behaviour, but that is **reasoned, not measured**.

### 5.3 Which tiling configurations a given minimum permits

*Reasoned*, over the full 26.5 iPad list, using exact halves / thirds / quadrants of the screen
(inter-window gaps ignored, which makes these slightly optimistic). 18 device-orientations
(9 size classes × 2), 6 configurations each = 108 combinations.

| declared minimum | full | half (side) | half (top/bottom) | third (vertical) | third (horizontal) | quadrant | total excluded |
|---|---|---|---|---|---|---|---|
| **380 × 500** (PR #23) | 18/18 | 17/18 | 11/18 | 5/18 | **0/18** | 10/18 | 47 |
| 372 × 500 | 18/18 | **18/18** | 11/18 | 6/18 | 0/18 | 11/18 | 44 |
| **360 × 512** | 18/18 | 18/18 | 11/18 | 8/18 | 0/18 | 11/18 | **42** |
| 372 × 560 | 18/18 | 18/18 | 6/18 | 6/18 | 0/18 | 6/18 | 54 |
| 360 × 584 | 18/18 | 18/18 | 5/18 | 8/18 | 0/18 | 5/18 | 54 |
| 360 × 648 | 18/18 | 18/18 | 2/18 | 8/18 | 0/18 | 2/18 | 60 |
| 360 × 744 | 18/18 | 18/18 | **0/18** | 8/18 | 0/18 | **0/18** | 64 |

Findings:

- **Height is the binding dimension, by a wide margin**, exactly as the review's 3.3 says. Going from
  380 to 360 pt of width buys 5 lost configurations back; going from 500 to 648 pt of height costs 18.
- **Horizontal thirds are impossible at any height minimum above ~340**, on every iPad. The tallest
  horizontal third in the whole list is `1032 × 459` (iPad Pro 13″ portrait); the shortest is
  `1133 × 248`.
- **The width should be 372, not 380.** At 380 the iPad mini's portrait side-half (372 × 1133) is
  excluded by 8 pt, and its landscape vertical third (377.7) by 2.3 pt. At 372 both return. The
  review spotted this; the measurement confirms it. At 360 the vertical third on three more devices
  returns as well.
- A 360 × 512 minimum is strictly better than PR #23's 380 × 500 on every axis: it permits five more
  configurations *and* 12 pt more content height.

---

## 6. Recommendation

Everything in this section is **reasoned** from §§1–5. Where a judgement is the product owner's, I
frame the options rather than choose.

### 6.1 A single minimum cannot serve both platforms

Two independent reasons, both measured:

1. **The number means different things.** On macOS a minimum is a *content* size, below the title bar
   and toolbar. On iPadOS it is a *scene* size that **contains** 116 pt of system chrome (32 status
   bar + 64 tab container + 20 home indicator). "380 by 500 points of content, on macOS and for an
   iPadOS scene alike" (PR #23) equates two quantities that differ by 116 pt of usable height.
2. **The elements are different sizes.** The same result card is **127 pt** tall on iOS and **107 pt**
   on macOS; the same control row is **66.5** and **44**. A minimum derived on one platform is
   miscalibrated on the other by 20–25 pt per element.

**Recommend: state two minimums, and say what each measures.**

### 6.2 The numbers

**macOS — content minimum `360 × 512`.**

- Width 360: board block 308 + 2 × 16 margin = 340, plus 20 pt of slack for control growth. (Even
  340 would do; 360 is a round number with headroom, and matches the iPad figure.)
- Height 512: covers ordinary play (440), the threefold notice (~481), minimum replay (~479) and the
  result card (**503**) at `p = 44`, and fits under the smallest available content height on the
  constrained Mac display in every toolbar configuration a main window would use (516 with a full
  unified toolbar, 542 compact, 550 none).
- It does **not** cover full stacked replay (535–575). See 6.4.
- Consequence to state explicitly: on the 1024 × 663 largest-text Mac display, a window at the
  minimum with a unified toolbar has **13 pt** of vertical slack. The contract should say that the
  Mac board window carries **no toolbar**, or a `.unifiedCompact` one, and record why.

**iPadOS — scene minimum `360 × 648`, or `360 × 584` if the result card is not required in a
minimum-size window.**

- Width 360 rather than 380: recovers the iPad mini's portrait side-half and landscape vertical
  third, and three more vertical thirds elsewhere (§5.3). 360 is above the 340 the board block needs.
- The iPad scene contains **116 pt** of measured chrome, so the scene height needed for each state
  is `state + 116`: ordinary play **583**, threefold notice **612**, minimum replay **627**, result
  card **644**, full replay **743**.
- **648** therefore guarantees every required state at `p = 44` except full stacked replay. **584**
  guarantees only ordinary play, and would present the result card below the floor. The gap between
  the two is 3 tiling configurations (60 excluded versus 54).
- At either value, iPadOS keeps full screen and both side halves on every supported iPad, and loses
  most top/bottom halves and quadrants — at 648, all but the 13-inch models. **That is a
  product-scope consequence and belongs in `product.md`, not `interaction-design.md`** — the
  review's 3.6 is right.
- On **iPhone** no minimum can be declared (`sizeRestrictions` is `nil`, measured). Whatever the
  contract says about minimums, it must be scoped to macOS and iPadOS.

**Narrowest iPhone the stacked layout should be verified against: iPhone SE (2nd/3rd generation),
375 × 667 points.** Not "375 points wide" — the width is never the binding dimension on any iPhone
(375 − 32 = 343 ≥ 308, with room for `p` up to 49). The height is. The contract should name the
device and both dimensions, and should use one term — *supported*, or *verified against*, not both.

### 6.3 Does the 44 pt floor hold everywhere?

**No.** Three failures, in order of how much they cost to fix:

| where it fails | at | shortfall | cheapest remedy |
|---|---|---|---|
| iPhone SE, result card, default text, **with a navigation bar** | p = 41.7 | 17.5 pt | remove the navigation bar from the board page (+54 pt) |
| iPhone SE, **stacked replay** with a move list, any text size | p = 41.4 at best | 18.5 pt | see 6.4 |
| macOS constrained display, **stacked replay** with a move list | p ≈ 42 | 19–59 pt | see 6.4 |
| **every iPhone**, stacked replay, above AX1 | — | large | see 6.5 |
| iPhone SE, result card, above AX1; anything above AX3 | — | large | see 6.5 |

The first is free. The other two are the decisions.

### 6.4 Decision 1 — stacked replay is where the floor actually breaks

Stacked replay is the only *ordinary-play-adjacent* state that cannot be made to fit on the iPhone SE
or on the constrained Mac at `p = 44`. It costs 626.5 pt on iOS against the SE's 564 pt of content.

Options, framed:

- **(a) Exempt the replay board from the pitch floor.** The accepted contract already contains this
  exact reasoning for the pre-start preview: "a pre-start board is a **noninteractive preview with no
  touch targets**, so it carries no size floor … The floor exists to protect interaction, and a
  preview has none to protect." The accepted replay text says "**The board is read-only.** Replay does
  not offer move input" and "a tap on it does nothing at all — no beat and no feedback". By the
  contract's own stated rationale the replay board has no interaction to protect either. This is the
  option with the strongest existing grounding, and it costs 0 pt elsewhere. The counter-argument is
  that a floor also protects *legibility*, and the contract's floor paragraph mentions marker
  geometry as well as touch targets.
- **(b) Keep the floor and shrink stacked replay's chrome.** A one-row move list plus a transport
  without the separate speed control costs 510.5 and fits the SE at 564 (+53.5). This makes the move
  list a scroll region of one visible row, which reads as a demotion of an accepted requirement
  ("replay in the stacked layout shows the move list rather than hiding it").
- **(c) Keep the floor and drop the iPhone SE.** The narrowest supported iPhone becomes 375 × 812
  (11 Pro / 12 mini / 13 mini), where full stacked replay fits at default text with **+52.5** and the
  result card to AX3. This is a product-scope change, and the SE 3rd generation is a currently
  supported, currently sold-secondhand device.
- **(d) Raise the minimum window and accept the iPad tiling loss.** Does nothing for the iPhone SE,
  which has no minimum to raise. Only helps macOS and iPadOS.

Note (a) and (b) compose: exempting replay makes (b) unnecessary; adopting (b) makes (a) unnecessary.

### 6.5 Decision 2 — accessibility text sizes

*Measured*: the play-control row grows from 66.5 pt at default to **171.5 pt** at AX5; the result card
from 127 to **313**; a single move-list row from 32.5 to **261.5**. Hiding the numeral strips (which
`design/frame-motion-glass` already accepts) recovers 32 pt — about one-fifth of the control row's
growth alone.

At `p = 44` the iPhone SE runs out at **AX3** for ordinary play and **AX1** for the result card, and
every other supported iPhone runs out at **AX3–AX5**. Something must yield above those sizes.

Options, framed:

- **(a) The board yields.** Let `p` fall below 44 when Dynamic Type is at an accessibility size.
  Honest, and the pitch degrades gradually (the SE would sit at ≈32 pt at AX5). It contradicts the
  floor's own rationale most sharply, because a user at AX5 is exactly the user least able to hit a
  small target.
- **(b) The chrome yields further than "tighten".** Move the play controls into a compact
  presentation at accessibility sizes — an overflow menu, or a bottom bar that scrolls. Preserves the
  board, changes an accepted control inventory.
- **(c) The page scrolls.** At accessibility sizes the stacked layout becomes a scroll view: the
  board keeps `p = 44`, the chrome keeps its size, and the composition exceeds the viewport. This is
  the standard platform answer to Dynamic Type growth and the one that breaks no accepted rule except
  "the final board remains fully visible", which would need scoping to "fully visible when the page
  is scrolled to the board".
- **(d) Cap the supported Dynamic Type range** and say so. Least attractive; accessibility text sizes
  are not optional in practice.

This is the decision `interaction-design.md:497` already flags as open ("how accessibility text sizes
are accommodated once the control row and turn status grow"). The numbers above are what it needs to
be closed.

### 6.6 Two smaller things the evidence settles

- **The navigation bar on the board page is worth 54 pt and is undefined.** It is the largest single
  free variable in the budget — larger than the play-control row, larger than the numeral strips. The
  contract should say the board page has no navigation bar, and the chrome inventory should list the
  navigation container at its **measured 83 pt**, not at a remembered 49.
- **The oscillation risk is smaller than feared.** Measured, `sidebarAdaptable` presented as a top
  tab bar at 744, 820 and 1032 pt of width, taking **0 pt** horizontally on iPad and 64 pt
  vertically. The layout rule's width input does not depend on the navigation presentation unless the
  app forces a sidebar. Finding 2.4's cycle is real in principle but does not occur with the platform
  container as configured; if the contract wants a sidebar it must break the cycle explicitly.

---

## Appendix — reproducing this

All probe sources are in `discussion-drafts/layout-probe/`. All are scratch code; none is part of any
repository.

| file | what it measures |
|---|---|
| `main.swift` | screen bounds, native scale, safe areas, tab-bar and nav-bar heights, per-device content box, at L and AX5, with and without a navigation bar |
| `swiftui.swift` | the same for `TabView(...).tabViewStyle(.sidebarAdaptable)`, the container the contract adopts |
| `probe3.swift` | element ideal and wrapped heights with the accepted Chinese copy at L / xxxL / AX1 / AX3 / AX5; `sizeRestrictions` availability by idiom |
| `probe4.swift` | `UISceneSizeRestrictions` set/read-back behaviour and timing on iPad |
| `macprobe.swift` | macOS title-bar and toolbar chrome for five toolbar styles, screen budget, `contentMinSize` clamping, macOS element sizes |
| `budget.py`, `holds44.py`, `tiling.py` | the arithmetic in §§3 and 5.3 |
| `out-*.txt`, `out3-*.txt` | raw probe output |

Build and run, e.g.:

```
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcrun -sdk iphonesimulator swiftc -target arm64-apple-ios26.0-simulator -O main.swift \
      -o LayoutProbe.app/LayoutProbe
./run.sh <simulator-udid> "<label>"
xcrun swiftc -O macprobe.swift -o macprobe && ./macprobe
```

The probe apps must adopt the UIScene lifecycle and declare `UIApplicationSceneManifest`; the iOS 26
SDK refuses to launch an app that does not.

Simulator devices created for this run were named `MXQ-*` and deleted afterwards.

## Open, and honest about it

1. Every iOS number is from **iOS 27.0**, not 26.5. Re-measure before freezing.
2. The **element heights are my reconstructions** in standard SwiftUI controls with the accepted
   copy — a floor for what the real design costs, not the design's own values. The real turn status,
   control row, result card and move list may each be taller.
3. **What iPadOS does when a user selects a tile smaller than the declared minimum is unobserved.**
   It needs a person driving window controls.
4. The **inter-element gap of 12 pt** and the assumption of two-to-four gaps per state are mine. They
   are the smallest plausible values; a design with 16 pt gaps adds 8–16 pt per state.
5. I did not measure a **forced sidebar** presentation, so the sidebar's width — and therefore the
   real oscillation band if the contract wants one — is still unknown.
6. **iPad landscape was not measured directly.** `requestGeometryUpdate` is refused on iPadOS 26/27
   (*measured*: "The current windowing mode does not allow for programmatic changes to interface
   orientation"), and the simulator cannot be rotated from `simctl`. The iPad landscape figures in
   §4.3 and §5.3 are the portrait dimensions transposed, which is safe for widths and heights but
   assumes the safe-area insets are orientation-symmetric on iPad. They were (32 / 20) in every
   portrait measurement; that they stay so in landscape is **reasoned**, not measured.
