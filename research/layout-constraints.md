# Layout constraints — the table every scheme must solve against

Workspace research note. **Not a contract, not a proposal to merge.** It exists because the app's layout has
been rejected three times (`review-pr23.md`, `review-pr23-round2.md`), and each rejection turned on a number
that was asserted rather than computed. This note fixes the inputs: the device list, the measured chrome, the
state inventory, and the arithmetic that turns those into a maximum cell pitch. A later scheme is right or
wrong against this table, not against a remembered constant.

Nothing under `MiniXiangqi/` or any worktree was modified. No Git or GitHub state was changed. The only file
written is this one and the probe sources under `discussion-drafts/layout-probe/`.

**Toolchain.** Xcode 27.0 build `27A5228h`, `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`.
Host macOS 27.0 build `26A5388g`. The only iOS runtime this Xcode ships is **iOS 27.0 (`24A5390f`)**, so every
iOS/iPadOS number below was measured on 27.0, not on the 26.5 the product targets. iOS 26 and 27 are the same
design generation; I expect the chrome to match, but that expectation is **reasoned, not measured**, and it is
stated once here rather than per table.

**Label discipline.** Every number carries one of four labels and the label is load-bearing:

- **Measured** — produced by a probe in `discussion-drafts/layout-probe/`, named per table.
- **Documented** — read from Apple documentation through the Xcode 27 documentation tool, quoted.
- **Transferred** — a measurement taken on one device and applied to another in the same class, with the
  class stated. Used only for the five 26-only iPads that no runtime in this toolchain can boot.
- **Reasoned / derived** — arithmetic over the above. Inputs named.

---

## 0. Read this first: the cells that are infeasible at any arrangement

These are not design problems. No arrangement of the accepted elements makes them fit. They are product
decisions, and §10 prices each way out.

| # | infeasible cell | shortfall | robust to design tightening? |
|---|---|---|---|
| **I1** | **iPhone SE (375 × 667), natural-result card, AX2 and above.** Board at `p = 44`, strips hidden, no navigation bar, card replacing the control row, board fully visible. | −8 pt at AX2, **−86 pt at AX3**, −222 at AX5 | AX2's −8 is inside the tolerance of my 12 pt gap assumption. **AX3 is robust:** deleting *every* inter-element gap saves 24 pt and still leaves −62. |
| **I2** | **iPhone SE, threefold-repetition notice, AX2 and above.** Same conditions. | −36.5 at AX2, **−78 pt at AX3** | **Yes** at both. −54 at AX3 with zero gaps. |
| **I3** | **iPhone SE, result card *alongside* a still-visible control row, at every text size including xS.** | **−24.5 pt** at xS, −406 at AX5 | Marginal at xS (zero gaps → +11.5), hopeless above L. |
| **I4** | **Every supported iPhone, resident three-row move list in stacked replay, at some text size.** SE fails from **xS**; the largest iPhone (440 × 956) fails from **AX2**. | SE −56.5 at xS | **Yes** on the SE at every size. |
| **I5** | **Every supported iPad, every orientation: the horizontal-third tiling configuration.** The tallest horizontal third in the whole 26.5 list is 1376/3 = 458.7 pt (iPad Pro 13″ portrait), leaving 401.7 of content after 57 pt of chrome; ordinary play at `p = 44` needs 467. | **−65 pt** on the most favourable device, **−250** on the least | **Yes.** No declared minimum helps: a minimum cannot manufacture height. |
| **I6** | **Thirteen of eighteen iPad device-orientations: the top/bottom-half and quadrant configurations**, at default text. | iPad Air 3 portrait half: **−7 pt**; mini 6 portrait: −21.5; mini 5 landscape: **−179** | Yes on all but the two that fail by under 15 pt. |

**The single sentence that matters.** The accepted set

> `p ≥ 44` on every interactive board **∧** the final board stays fully visible and uncovered when the
> non-dismissible result card is shown **∧** iPhone SE (2nd/3rd generation) is supported **∧** the declared
> Dynamic Type range reaches AX3

**is unsatisfiable.** §6.1 is the arithmetic. Exactly one of those four must give, and §10 prices each.

Two lesser but still binding facts:

- **No iPhone is ever side by side.** The widest supported iPhone gives 400 pt of usable width; side by side
  needs `308 + panel + 16 ≥ 644` at the smallest defensible panel minimum. Stacked is the iPhone layout
  unconditionally, at every text size. *(Derived; §7.)*
- **The accepted layout rule is under-determined, not merely ambiguous.** Its three defensible readings
  disagree about the arrangement on **16 of the 18** iPad device-orientations. §7.3.

---

## 1. Device and window-class inventory

### 1.1 Method for membership

**Measured.** `xcrun simctl list devicetypes --json` reports per model a `minRuntimeVersion` /
`maxRuntimeVersion` pair packed as `(major << 16) | (minor << 8) | patch`. A model is on the iOS/iPadOS 26.5
list exactly when `min ≤ 26.5 ≤ max`. Re-run in this session; it reproduces `layout-budget.md` §1 exactly,
including the five iPads that carry `max = 26.99.0` and therefore **cannot be booted on any runtime this
toolchain ships**: iPad mini (5th generation), iPad (8th generation), iPad Air (3rd generation), iPad Pro
11″ (1st generation), iPad Pro 12.9″ (3rd generation). Their chrome is **transferred**, never measured, and
the transfer class is stated.

**Reasoned.** Apple does not drop device models in a point release, so the 26.5 list equals the 26.0 list.

### 1.2 iPhone — portrait only (`product.md`: "iPhone runs in portrait orientation only")

Point dimensions and top safe-area inset. Root-view `layoutMargins` measured at 375 and 440; the intermediate
classes are **reasoned** from UIKit's own 16/20 pt step and are marked.

| points (portrait) | devices on the 26.5 list | top safe area | bottom safe area | layout margin | source |
|---|---|---|---|---|---|
| **375 × 667** | iPhone SE (2nd gen), iPhone SE (3rd gen) | 20 | 0 | **16** | measured |
| 375 × 812 | iPhone 11 Pro, 12 mini, 13 mini | 50 | 34 | **16** | measured (13 mini) |
| 390 × 844 | iPhone 12, 12 Pro, 13, 13 Pro, 14, 16e, 17e | 47 | 34 | 16 | layout-budget; margin reasoned |
| 393 × 852 | iPhone 14 Pro, 15, 15 Pro, 16 | 59 | 34 | 16 | layout-budget; margin reasoned |
| 402 × 874 | iPhone 16 Pro, 17, 17 Pro | 62 | 34 | 16 | layout-budget; margin reasoned |
| 414 × 896 | iPhone 11, 11 Pro Max | 48 | 34 | 20 | layout-budget; margin reasoned |
| 420 × 912 | iPhone Air | 68 | 34 | 20 | layout-budget; margin reasoned |
| 428 × 926 | iPhone 12 Pro Max, 13 Pro Max, 14 Plus | 47 | 34 | 20 | layout-budget; margin reasoned |
| 430 × 932 | iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus | 59 | 34 | 20 | layout-budget; margin reasoned |
| **440 × 956** | iPhone 16 Pro Max, 17 Pro Max | 62 | 34 | **20** | measured (17 Pro Max) |

**Narrowest and shortest: 375 × 667, iPhone SE (2nd and 3rd generation)** — the same device is both. The
HIG's `360 × 780` row for the 12/13 mini describes physical pixels over the nominal scale, not the layout
coordinate space; measured, the mini is **375 × 812** at `scale 3.0`, `nativeScale 2.88`. This note repeats
`layout-budget.md` §1.2 because the trap is easy to fall back into.

### 1.3 iPad — every orientation (`product.md`: "iPad supports every orientation")

| points (portrait) | devices | top safe | bottom safe | home button | source |
|---|---|---|---|---|---|
| **744 × 1133** | iPad mini (6th gen), iPad mini (A17 Pro) | 32 | **25** | no | **measured** (A17 Pro) |
| 768 × 1024 | **iPad mini (5th gen)** — 26 only | 32 | 0 | yes | transferred from iPad (9th gen) |
| 810 × 1080 | **iPad (8th gen)** — 26 only — and iPad (9th gen) | 32 | **0** | yes | **measured** (9th gen) |
| 820 × 1180 | iPad (10th gen), iPad (A16), iPad Air 4/5, iPad Air 11″ M2/M3/M4 | 32 | 25 | no | **measured** (A16) |
| 834 × 1112 | **iPad Air (3rd gen)** — 26 only | 32 | 0 | yes | transferred from iPad (9th gen) |
| 834 × 1194 | **iPad Pro 11″ (1st gen)** — 26 only — and 11″ (2nd–4th gen) | 32 | 25 | no | transferred from iPad mini (A17) |
| 834 × 1210 | iPad Pro 11″ (M4), 11″ (M5) | 32 | 25 | no | transferred |
| 1024 × 1366 | **iPad Pro 12.9″ (3rd gen)** — 26 only — 12.9″ (4th–6th), iPad Air 13″ M2/M3/M4 | 32 | 25 | no | transferred |
| **1032 × 1376** | iPad Pro 13″ (M4), 13″ (M5) | 32 | 25 | no | **measured** (13″ M5) |

**Correction to `layout-budget.md` §2.2.** That note recorded the iPad bottom safe area as **20**. Measured
here on three different modern iPads (mini A17, A16, Pro 13″ M5), portrait and landscape, iOS 27.0, it is
**25**. Every iPad budget derived from 20 is **5 pt optimistic**, which matters: it turns round 2's "the
result card has 4.5 pt of slack at the declared iPadOS minimum" into **−0.5 pt**.

**Smallest iPad canvas: 768 × 1024, iPad mini (5th generation)** — shortest portrait height *and* shortest
landscape height in the list. It is the device most easily lost from a list built on the iOS 27 runtime.

### 1.4 iPad window classes the system offers

**Documented** — HIG *Multitasking: iPadOS*: windows present "Full screen" or "Windowed"; HIG *Layout:
iPadOS*: "Window controls provide the option to arrange windows to fill **halves, thirds, and quadrants** of
the screen, so it's important to check your layout at each of these sizes on a variety of devices"; and the
note that closes the question of whether the app can avoid any of them: "**Apps don't control multitasking
configurations** or receive any indication of the ones that people choose."

The window classes a scheme must therefore hold are, per device and per orientation:

| class | scene width | scene height |
|---|---|---|
| full screen | `W` | `H` |
| side half | `W/2` | `H` |
| top / bottom half | `W` | `H/2` |
| vertical third | `W/3` | `H` |
| vertical two-thirds | `2W/3` | `H` |
| horizontal third | `W` | `H/3` |
| quadrant | `W/2` | `H/2` |

9 size classes × 2 orientations × 7 configurations = **126 cells**. Inter-window gaps are ignored throughout,
which makes every verdict below slightly **optimistic**. §8 evaluates all 126.

### 1.5 macOS window classes

macOS has no device list; it has a window that runs from the app's declared `contentMinSize` to the screen's
`visibleFrame`. The binding end is the minimum, on the smallest display.

**Measured** on this host (macOS 27.0, `macprobe2.swift`) — the configuration `interaction-design.md` names
as its worst case, a built-in Retina display at the largest-text setting:

```
SCREEN frame=1024.00x663.00  visibleFrame=1024.00x584.00  backingScale=2.00
  menu bar + Dock consumed: width 0.00  height 79.00
```

The contract's "1024 by 663 … leaves a window of 1024 by 582" is confirmed to within the Dock's own height
(79 here, 81 in the `layout-budget.md` run — the difference is Dock size, a user setting). Use **582** as the
conservative figure.

Large displays are never binding and are listed only so a scheme states its upper end: a 16″ MacBook Pro is
1728 × 1117 pt, a Studio Display 2560 × 1440 pt (**reasoned**, from Apple's published default scaled modes;
not measured here). At those sizes the 720 pt board cap binds long before the window does.

---

## 2. Measured chrome

### 2.1 The adaptive navigation container has **three** presentations and two measured breakpoints

Probe `layout-probe/probe9.swift` and `probe10.swift`: the container the contract adopts,
`TabView(...).tabViewStyle(.sidebarAdaptable)`, hosted in real `UIWindow`s of successive widths on three
different iPads. **Measured**, iOS 27.0, and identical on iPad mini (A17 Pro), iPad (9th gen) and iPad Pro 13″
(M5):

| container width | presentation | leading inset | top inset added | bottom inset added |
|---|---|---|---|---|
| ≤ **664** | bottom bar | 0 | 0 | 47 + home indicator (72 measured with a 25 pt indicator) |
| **668 – 1024** | **top tab bar** | 0 | **64** | 0 |
| ≥ **1025** | **sidebar** | **280** | 0 | 0 |

The flip to the sidebar is exact: at 1024 pt the probe reports `insets=(t96 … lead0)`, at 1025 pt
`insets=(t32 … lead280)`. The flip to the top tab bar sits between 664 and 668 (the sweep stepped by 4).

**This overturns `layout-budget.md` §2.2 and §6.6.** That note concluded "the sidebar never appeared … the
adaptive navigation container costs height on iPad, not width" and therefore that the oscillation risk
round 1 identified "does not occur with the platform container as configured". It measured only **portrait**
canvases, all of which are below 1025 pt. In landscape the sidebar appears on **eight of the nine** iPad
classes, and it costs **280 pt of width** — 91 % of a board core at the pitch floor. iPad Pro 13″ (M4/M5) is
1032 pt wide **in portrait**, so it gets the sidebar in portrait too.

Which iPads see the sidebar, per orientation (**derived** from the measured breakpoints):

| device | portrait width | portrait presentation | landscape width | landscape presentation |
|---|---|---|---|---|
| mini 6 / mini A17 | 744 | top tab bar | 1133 | **sidebar** |
| mini 5 | 768 | top tab bar | **1024** | **top tab bar** (by one point) |
| iPad 8 / 9 | 810 | top tab bar | 1080 | **sidebar** |
| iPad 10 / A16 / Air 11″ | 820 | top tab bar | 1180 | **sidebar** |
| Air 3 | 834 | top tab bar | 1112 | **sidebar** |
| Pro 11″ 1st–4th | 834 | top tab bar | 1194 | **sidebar** |
| Pro 11″ M4/M5 | 834 | top tab bar | 1210 | **sidebar** |
| Pro 12.9″ / Air 13″ | 1024 | top tab bar (by one point) | 1366 | **sidebar** |
| Pro 13″ M4/M5 | **1032** | **sidebar** | 1376 | **sidebar** |

Two devices sit **one point** from a presentation change. The HIG also states the sidebar is partly the
user's: "The app first launches with **your choice** of a sidebar or a tab bar, and then people can tap to
switch between them." So a scheme cannot treat 280 pt as either always present or always absent.

### 2.2 iPhone chrome — measured, and **invariant across all twelve Dynamic Type steps**

Probe `probe8.swift`, run at every one of the twelve `UIContentSizeCategory` values from `extraSmall` to
`accessibilityExtraExtraExtraLarge`. On every iPhone measured (SE 3rd gen, 13 mini, 17 Pro Max) the container
values are byte-identical at all twelve:

| quantity | value | note |
|---|---|---|
| tab container contribution to the **bottom** safe area | **83.00** | every iPhone, every text size |
| inline navigation bar | **54.00** | every iPhone, every text size |
| large-title navigation bar | 106.00 | from `layout-budget.md`; probe8's large-title read did not settle before measurement and is not claimed here |
| root-view `layoutMargins` | 16.00 at 375 pt wide, 20.00 at 440 pt wide | measured |

**Chrome growth at accessibility sizes comes entirely from the app's own elements, never from the system
containers.** That is the fact that makes §5's table separable.

**Content height available to the app, per iPhone** (`H − topSafe − 83`, no navigation bar; subtract a
further 54 with one). **Derived** from measured inputs:

| screen | content height, no nav bar | with an inline nav bar | usable width |
|---|---|---|---|
| **375 × 667** | **564** | 510 | 343 |
| 375 × 812 | 679 | 625 | 343 |
| 390 × 844 | 714 | 660 | 358 |
| 393 × 852 | 710 | 656 | 361 |
| 402 × 874 | 729 | 675 | 370 |
| 414 × 896 | 765 | 711 | 374 |
| 420 × 912 | 761 | 707 | 380 |
| 428 × 926 | 796 | 742 | 388 |
| 430 × 932 | 790 | 736 | 390 |
| 440 × 956 | 811 | 757 | 400 |

### 2.3 iPad chrome — measured

`probe8.swift` / `probe9.swift`, portrait and landscape (landscape reached by building a landscape-only
`UISupportedInterfaceOrientations`, since `requestGeometryUpdate` is refused on iPadOS 26/27 and `simctl`
cannot rotate a device).

| iPad | orientation | scene | container | content width | content height |
|---|---|---|---|---|---|
| mini (A17 Pro) | portrait | 744 × 1133 | top tab bar | 744 | **1012** |
| mini (A17 Pro) | landscape | 1133 × 744 | **sidebar 280** | **853** | **687** |
| iPad (9th gen) | portrait | 810 × 1080 | top tab bar | 810 | **984** |
| iPad (9th gen) | landscape | 1080 × 810 | **sidebar 280** | **800** | **778** |
| iPad (A16) | portrait | 820 × 1180 | top tab bar | 820 | **1059** |
| iPad (A16) | landscape | 1180 × 820 | **sidebar 280** | **900** | **763** |
| iPad Pro 13″ (M5) | landscape | 1376 × 1032 | **sidebar 280** | **1096** | **975** |

Root-view `layoutMargins` on every iPad measured: **20.00** each side, at every width and every text size.
An inline navigation bar inside the tab **costs 10 pt, not 54**, on iPad: the top tab bar and the navigation
bar share one row (`content 1022` with a bar against `1012` without — measured, and unexplained by any
documentation I found).

**iPad vertical chrome, full screen:** `32 + 64 + 25 = 121` with the top tab bar and a home indicator;
`32 + 64 + 0 = 96` on the home-button iPads; `32 + 25 = 57` when the sidebar presents instead.

### 2.4 macOS chrome — measured

`macprobe2.swift`:

| window configuration | chrome above content | max content height on the 1024 × 663 display |
|---|---|---|
| title bar only | **32** | **550** |
| title bar + `.unifiedCompact` toolbar | 40 | 542 |
| title bar + `.unified` / `.automatic` toolbar | **66** | **516** |
| title bar + `.expanded` toolbar | 83 | 499 |
| title bar + `.preference` toolbar | 88 | 494 |

Side chrome is **0** in every configuration. `NSWindow.contentMinSize` does not clamp a programmatic
`setContentSize` — it bounds *interactive* resizing only (measured; same semantics as `UISceneSizeRestrictions`).

### 2.5 Dynamic Type is an iOS/iPadOS axis only — **measured**

`macprobe2.swift` measured every element at all twelve `DynamicTypeSize` values on macOS. **Every element is
identical at all twelve.** The `.dynamicTypeSize()` modifier has no effect on macOS; the platform's text-size
axis is the display scaling setting, which is already what the 1024 × 663 "largest text" display represents.

Two consequences a scheme must not get wrong:

1. **The macOS half of the constraint table has one text-size column, not twelve.** A macOS minimum derived
   "through AX3" is meaningless.
2. **The accepted rule "the numeral strips are hidden at accessibility text sizes" never fires on macOS.**
   The strips are always shown there, so the macOS board block is always `7p + 2 × strip(p)`.

### 2.6 Where a minimum can be declared — measured

| | iPhone | iPad | macOS |
|---|---|---|---|
| `UIWindowScene.sizeRestrictions` | **`nil`** | non-`nil`, default `0 × 0`, unbounded max | n/a |
| what a declared minimum means | *nothing — it cannot be declared* | a **scene** size, containing 96–121 pt of system chrome | a **content** size, below the title bar and toolbar |
| when it takes effect | — | asynchronously; read back `0 × 0` immediately, correct after ~3 s | immediately |

Any contract sentence of the form "the app declares that minimum to iOS" is **false for iPhone**.

---

## 3. The state inventory

Every state the layout must hold, with its element list. Element definitions are standard SwiftUI controls
carrying the accepted Chinese copy — a **floor** for what the real design costs, not the design's values.

| key | state | resident elements outside the board block | source of the requirement |
|---|---|---|---|
| `play-AI` | ordinary play, human vs AI | turn status; control row 悔棋 · 判和 · 认输 | `:264`, `:266` |
| `play-Free` | ordinary play, Free Play | turn status; control row 悔棋 · 判和 · **翻转棋盘** | `:214` "at any time" |
| `claim-retained` | play with the retained draw claim | identical to `play-AI` — 可判和 is carried by 判和 | `:292`, `:352` |
| `result-replaces` | natural result, card **replacing** the control row | turn status; result card (title, reason, 悔棋, 结束对局) | `:337`–`:339`; owner decision |
| `result-recorded` | after 结束对局 | turn status; card with 回放 · 完成 | `:343` |
| `result-alongside` | card **in addition to** a visible control row | turn status; control row; result card | the reading `:360` "visible but disabled" implies in side-by-side |
| `threefold-replaces` | threefold notice replacing the controls | turn status; notice (message, 继续对局, 以和棋结束) | `:347`–`:349` |
| `threefold-alongside` | notice in addition to the controls | turn status; control row; notice | alternative reading |
| `replay-transport` | replay, transport only | replay status; six-control transport (5 + 翻转棋盘) | `:354`–`:358` |
| `replay-t7` | replay, transport + a move-list affordance | replay status; seven-control transport | PR #23's sheet |
| `replay-speed` | replay, transport + autoplay speed | replay status; transport; speed control | `:384` |
| `replay-list1/3/5` | replay with a **resident** move list of 1/3/5 rows | replay status; transport + speed; N move rows | `:492` on `main` |
| `prestart-AI` | pre-start, human vs AI | side choice; difficulty; 开始对局 (**board has no floor here**) | `:181`–`:210`, `:517` |
| `prestart-Free` | pre-start, Free Play | explanatory line; 开始对局 (no floor) | `:181` |
| *(memory notice)* | insufficient memory for AI play | **system alert** — covers the page; the layout beneath is `prestart-*` or `play-*` and is unchanged | `:279`–`:290` |

**The insufficient-memory notice consumes no board height.** It is an alert with 取消 and 重试, and alerts
are system-presented over the whole scene. It belongs in the state list because a scheme must say what is
*behind* it, not because it competes for space. Its only layout obligation is that the state behind it is one
of the states above.

---

## 4. The board block

**Accepted formulas** (`interaction-design.md:153`–`:157`, merged as PR #24):

```
numeral size   s(p) = round(clamp(0.32 p, 13, 20))
strip height   t(p) = round(0.08 p + 0.887 s(p))
board core          = 7 p, square, capped at 720 pt
board block height  = 7 p + 2 t(p)   with strips
                    = 7 p           at accessibility text sizes (strips hidden)
board block width   = 7 p           in both cases
```

**Derived** values:

| `p` | core `7p` | `s` | strip `t` | block height, strips | block height, hidden |
|---|---|---|---|---|---|
| 40 | 280.0 | 13 | 15 | 310.0 | 280.0 |
| **44 (the floor)** | **308.0** | **14** | **16** | **340.0** | **308.0** |
| 48 | 336.0 | 15 | 17 | 370.0 | 336.0 |
| 52 | 364.0 | 17 | 19 | 402.0 | 364.0 |
| 60 | 420.0 | 19 | 22 | 464.0 | 420.0 |
| 72 | 504.0 | 20 | 24 | 552.0 | 504.0 |
| 88 | 616.0 | 20 | 25 | 666.0 | 616.0 |
| **102.857 (the cap)** | **720.0** | 20 | 26 | 772.0 | 720.0 |

`block(p) ≈ 7.728 p` while `s` is unclamped, and `7p + 40` once `s` reaches its 20 pt ceiling at `p ≥ 62.5`.
Inverting: **the maximum pitch that a height `A` allows is `A / 7.728` with strips and `A / 7` without**,
subject to `7p ≤ usable width` and `7p ≤ 720`.

---

## 5. The master table: chrome height per state, per text size, per width

This is the table a later agent computes against. Everything else in the note is derived from it plus §1–§2.

**Composition rule** used throughout, and stated so a scheme can replace it: the resident stack is
`Σ(element heights) + n × 12 pt`, where `n` is the number of resident elements outside the board block and
12 pt is one standard inter-element gap. Each element already carries its own 8 pt internal padding. **The
12 pt gap is mine, not the contract's**, and it is the smallest plausible value; §10 shows which conclusions
survive setting it to zero.

**Availability rule.** `board block height available = content height − chrome height`, and then
`p = min(available / 7.728 or /7, usable width / 7, 720/7)`.

### 5.1 iOS / iPadOS, usable width **343** (the iPhone SE, and any 375 pt-wide device)

*Measured elements (`probe8.swift`, iPhone SE 3rd gen, iOS 27.0), gaps added.*

| state | xS | S | M | L | xL | xxL | xxxL | AX1 | AX2 | AX3 | AX4 | AX5 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `play-AI` / `claim-retained` | 120.0 | 122.0 | 125.0 | **127.0** | 132.0 | 137.0 | 141.0 | 187.0 | 205.0 | 230.0 | 311.0 | 337.0 |
| `play-Free` | 120.0 | 122.0 | 125.0 | 127.0 | 132.0 | 137.0 | 170.0 | 187.0 | 205.0 | 326.0 | 423.0 | 461.0 |
| `result-replaces` | 173.5 | 178.0 | 183.5 | **187.5** | 197.5 | 207.5 | 216.0 | 240.0 | 264.0 | **342.0** | 437.5 | 478.5 |
| `result-recorded` | 173.5 | 178.0 | 183.5 | 187.5 | 197.5 | 207.5 | 216.0 | 240.0 | 264.0 | 294.0 | 381.5 | 416.5 |
| `result-alongside` | 248.5 | 254.0 | 261.0 | 266.0 | 278.5 | 291.0 | 301.5 | 365.5 | 401.5 | 496.0 | 608.0 | 662.0 |
| `threefold-replaces` | 145.0 | 148.0 | 152.5 | **155.5** | 163.0 | 170.5 | 205.5 | 228.5 | 292.5 | **334.0** | 543.5 | 594.5 |
| `threefold-alongside` | 220.0 | 224.0 | 230.0 | 234.0 | 244.0 | 254.0 | 291.0 | 354.0 | 430.0 | 488.0 | 714.0 | 778.0 |
| `replay-transport` / `replay-t7` | 118.5 | 121.5 | 124.0 | **126.0** | 130.5 | 135.5 | 139.5 | 145.0 | 156.0 | 169.5 | 240.5 | 259.0 |
| `replay-speed` | 157.5 | 160.5 | 163.0 | **165.0** | 169.5 | 174.5 | 178.5 | 184.0 | 195.0 | 208.5 | 279.5 | 298.0 |
| `replay-list1` | 198.5 | 202.5 | 206.5 | 209.5 | 216.5 | 224.0 | 259.0 | 275.5 | 298.5 | 376.5 | 472.0 | 571.5 |
| `replay-list3` | 280.5 | 286.5 | 293.5 | **298.5** | 310.5 | 323.0 | 420.0 | 458.5 | 505.5 | 712.5 | 857.0 | 1118.5 |
| `replay-list5` | 362.5 | 370.5 | 380.5 | 387.5 | 404.5 | 422.0 | 581.0 | 641.5 | 712.5 | 1048.5 | 1242.0 | 1665.5 |
| `prestart-AI` | 177.0 | 178.0 | 179.5 | 180.5 | 183.0 | 185.5 | 187.5 | 193.5 | 199.5 | 208.0 | 216.5 | 223.5 |
| `prestart-Free` | 117.5 | 120.0 | 122.5 | 124.5 | 129.5 | 134.5 | 139.0 | 149.5 | 197.5 | 220.0 | 243.0 | 324.0 |

### 5.2 The same at usable width **320** (a 360 pt-wide window — the candidate declared minimum)

Only the rows that differ from §5.1 are repeated; everything else is identical.

| state | xL | xxL | xxxL | AX2 | AX3 | AX5 |
|---|---|---|---|---|---|---|
| `play-Free` | **156.0** | **163.0** | 170.0 | **285.0** | 326.0 | 461.0 |
| `threefold-replaces` | 163.0 | **196.5** | 205.5 | 292.5 | 334.0 | **656.5** |
| `result-recorded` | 197.5 | 207.5 | 216.0 | 264.0 | 294.0 | **478.5** |

### 5.3 The same at usable width **404** and **720** (large iPhones; iPad panels)

| state | width | L | AX1 | AX3 | AX5 |
|---|---|---|---|---|---|
| `play-AI` | 404 | 127.0 | **153.0** | 230.0 | **275.0** |
| `play-AI` | 720 | 127.0 | 153.0 | **182.0** | **213.0** |
| `result-replaces` | 404 | 187.5 | 240.0 | **294.0** | **416.5** |
| `result-replaces` | 720 | 187.5 | 240.0 | 294.0 | **354.5** |
| `threefold-replaces` | 404 | 155.5 | 228.5 | 334.0 | 470.5 |
| `threefold-replaces` | 720 | 155.5 | **194.5** | **238.0** | **346.5** |
| `replay-list3` | 720 | 298.5 | 458.5 | 712.5 | 1056.5 |

**Width matters, and the widths at which it matters are measured.** The control row's ideal width is 278 pt
at L and it wraps to two rows below 280 (`h@264 = 88.5` against `h@280 = 66.5`). The result card's ideal
width is 343.5 pt at AX3, so on the SE's 343 pt of usable width it wraps and costs **254 pt instead of 206** —
a 48 pt penalty that a budget computed from ideal heights misses. Round 2's AX3 arithmetic used 206.

### 5.4 macOS — one column, because macOS has no Dynamic Type

*Measured (`macprobe2.swift`), gaps added, at every width from 264 to 720 (macOS elements do not wrap in
this range).*

| state | chrome height |
|---|---|
| `play-AI` / `play-Free` / `claim-retained` | **100.0** |
| `replay-transport` / `replay-t7` | 99.0 |
| `replay-speed` | 131.0 |
| `threefold-replaces` | 136.0 |
| `prestart-AI` | 144.0 |
| `result-replaces` / `result-recorded` | **163.0** |
| `replay-list1` | 171.0 |
| `threefold-alongside` | 192.0 |
| `result-alongside` | 219.0 |
| `replay-list3` | 251.0 |
| `replay-list5` | 331.0 |

macOS elements are 20–35 % smaller than their iOS counterparts at default text — result card **107** against
127, control row **44** against 66.5, move row **28** against 32.5, metadata **13** against 16, transport
**43** against 65.5. A minimum derived on one platform is miscalibrated on the other by 20–25 pt **per
element**, independently of the chrome difference.

---

## 6. Feasibility: every (device × orientation × state × text size) cell

The cell value is the **maximum pitch** achievable. `--` means the cell cannot reach `p = 44` at any
arrangement of these elements. Read the height available to the board block as
`content height (§2.2/§2.3) − chrome height (§5)`.

### 6.1 iPhone portrait, **no navigation bar**, board block at whatever pitch fits

| screen (content H) | state | xS | S | M | L | xL | xxL | xxxL | AX1 | AX2 | AX3 | AX4 | AX5 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **375×667 (564)** | play-AI | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 48 | **--** | **--** |
| | play-Free | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | **--** | **--** | **--** |
| | **result-replaces** | 49 | 49 | 49 | 49 | 48 | 46 | 45 | 46 | **--** | **--** | **--** | **--** |
| | **threefold-replaces** | 49 | 49 | 49 | 49 | 49 | 49 | 46 | 48 | **--** | **--** | **--** | **--** |
| | **result-alongside** | **--** | **--** | **--** | **--** | **--** | **--** | **--** | **--** | **--** | **--** | **--** | **--** |
| | replay-transport | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 46 | **--** |
| | replay-speed | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | **--** | **--** |
| | replay-list1 | 47 | 47 | 46 | 46 | 45 | 44 | **--** | **--** | **--** | **--** | **--** | **--** |
| | **replay-list3** | **--** | **--** | **--** | **--** | **--** | **--** | **--** | **--** | **--** | **--** | **--** | **--** |
| | prestart-AI *(no floor)* | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 |
| **375×812 (679)** | play-AI | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 |
| | result-replaces | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 48 | **--** | **--** |
| | result-alongside | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 45 | **--** | **--** | **--** | **--** |
| | threefold-replaces | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | **--** | **--** |
| | replay-list1 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | 49 | **--** | **--** | **--** |
| | replay-list3 | 49 | 49 | 49 | 49 | 48 | 46 | **--** | **--** | **--** | **--** | **--** | **--** |
| **440×956 (811)** | play-AI | 57 | 57 | 57 | 57 | 57 | 57 | 57 | 57 | 57 | 57 | 57 | 57 |
| | result-replaces | 57 | 57 | 57 | 57 | 57 | 57 | 57 | 57 | 57 | 57 | 57 | 56 |
| | result-alongside | 57 | 57 | 57 | 57 | 57 | 57 | 57 | 57 | 57 | 52 | 45 | **--** |
| | threefold-replaces | 57 | 57 | 57 | 57 | 57 | 57 | 57 | 57 | 57 | 57 | 57 | 49 |
| | replay-list1 | 57 | 57 | 57 | 57 | 57 | 57 | 57 | 57 | 57 | 57 | 56 | **--** |
| | replay-list3 | 57 | 57 | 57 | 57 | 57 | 57 | **51** | **50** | **--** | **--** | **--** | **--** |

Full grid for all ten iPhone classes and all ten states, with and without a navigation bar:
`layout-probe/table8-out.txt`. The compressed form — **the first text size at which `p = 44` fails** — is:

**No navigation bar:**

| screen | play-AI | play-Free | result-replaces | result-alongside | threefold | replay-speed | replay-list1 | replay-list3 |
|---|---|---|---|---|---|---|---|---|
| **375×667 SE** | AX4 | AX3 | **AX2** | **xS** | **AX2** | AX4 | xxxL | **xS** |
| 375×812 | ok | AX4 | AX4 | AX2 | AX4 | ok | AX3 | xxxL |
| 390×844 | ok | AX4 | AX4 | AX3 | AX4 | ok | AX4 | xxxL |
| 393×852 | ok | AX5 | AX5 | AX3 | AX4 | ok | AX4 | xxxL |
| 402×874 | ok | AX5 | AX5 | AX3 | AX4 | ok | AX5 | xxxL |
| 414×896 | ok | AX5 | AX5 | AX4 | AX5 | ok | AX5 | AX1 |
| 420×912 | ok | AX5 | AX5 | AX4 | AX5 | ok | AX5 | AX1 |
| 428×926 | ok | ok | ok | AX4 | AX5 | ok | AX5 | AX2 |
| 430×932 | ok | ok | ok | AX4 | AX5 | ok | AX5 | AX2 |
| 440×956 | ok | ok | ok | AX5 | ok | ok | AX5 | AX2 |

**With an inline navigation bar** (the same page, 54 pt shorter):

| screen | play-AI | play-Free | result-replaces | threefold | replay-speed | replay-list3 |
|---|---|---|---|---|---|---|
| **375×667 SE** | **AX2** | AX2 | **xS** | xxL | xxL | **xS** |
| 375×812 | AX5 | AX3 | AX3 | AX3 | ok | **S** |
| 440×956 | ok | ok | ok | AX5 | ok | xxxL |

**Removing the navigation bar from the board page is worth 54 pt and is the difference between the result
card fitting on the SE at default text and not fitting.** With a bar the SE cannot present the card at the
floor at *any* text size, including xS.

#### The proof behind **I1** and **I2**

iPhone SE, no navigation bar, card replacing the control row, strips hidden (AX3 is an accessibility size):

```
content height                                          564.0
turn status at AX3, 343 pt wide                          64.0   measured
result card at AX3, 343 pt wide (wraps: ideal W 343.5)  254.0   measured
two inter-element gaps                                   24.0   assumed
board block at p = 44, strips hidden                    308.0   accepted formula
                                                       ------
required                                                650.0
available                                               564.0
shortfall                                               -86.0
```

Setting every gap to zero leaves **−62.0**. Restoring the numeral strips costs a further 32. Presenting the
card at 359 pt of usable width instead of 343 would stop it wrapping and save 48 — but the SE is 375 pt wide
and its measured layout margin is 16 on each side, so 343 is what exists. **The cell is infeasible.**

The threefold notice at AX3 is `564 − (64.0 + 246.0 + 24) = 230` of board block against 308 required:
**−78**, **−54** with zero gaps.

Ordinary play at AX3 is `564 − 230 = 334 ≥ 308`: **it fits, with 26 pt to spare.** The failure is specific to
the two states that replace the control row with something taller, and both of those are states the player
did not summon and cannot dismiss.

### 6.2 iPad portrait, full screen

Every state except a resident three-row move list holds `p = 44` at **every** text size on **every**
supported iPad in portrait. `replay-list3` first fails at AX3 (mini 6, mini 5, iPad 8/9, Air 3), AX4
(iPad 10/A16/Air 11, Pro 11″) or AX5 (12.9″/13″).

### 6.3 iPad landscape, full screen, **with the measured 280 pt sidebar**, evaluated as a stacked composition

| device | content W | usable W | content H | play-AI | result-replaces | replay-list3 |
|---|---|---|---|---|---|---|
| mini 6 / A17 | 853 | 813 | 687 | ok | ok | fails from xxxL |
| mini 5 (no sidebar) | 1024 | 984 | 672 | ok | ok | fails from xxxL |
| iPad 8 / 9 | 800 | 760 | 778 | ok | ok | fails from AX2 |
| iPad 10 / A16 / Air 11″ | 900 | 860 | 763 | ok | ok | fails from AX1 |
| Air 3 | 792 | 752 | 802 | ok | ok | fails from AX2 |
| Pro 11″ (all) | 874 / 890 | 834 / 850 | 777 | ok | ok | fails from AX2 |
| Pro 12.9″ / Air 13″ | 1086 | 1046 | 967 | ok | ok | fails from AX3 |
| Pro 13″ M4/M5 | 1096 | 1056 | 975 | ok | ok | fails from AX3 |

### 6.4 macOS

One text-size column (§2.5). `required = chrome (§5.4) + 340` (strips always shown on macOS).

| state | required content height | vs 550 (no toolbar) | vs 542 (`unifiedCompact`) | vs 516 (`unified`) | vs a 512 declared minimum |
|---|---|---|---|---|---|
| `play-AI` | **440** | +110 | +102 | +76 | **+72** |
| `replay-transport` | 439 | +111 | +103 | +77 | +73 |
| `replay-speed` | 471 | +79 | +71 | +45 | +41 |
| `threefold-replaces` | 476 | +74 | +66 | +40 | +36 |
| `prestart-AI` | 484 (no floor applies) | — | — | — | — |
| **`result-replaces`** | **503** | +47 | +39 | **+13** | **+9** |
| `replay-list1` | 511 | +39 | +31 | +5 | +1 |
| `threefold-alongside` | 532 | +18 | +10 | **−16** | **−20** |
| `result-alongside` | 559 | **−9** | **−17** | **−43** | **−47** |
| `replay-list3` | **591** | **−41** | **−49** | **−75** | **−79** |

macOS is comfortable for every state the sheet decision keeps resident, and fails only for the two states
that keep the control row visible alongside a card or a notice, and for a resident multi-row move list.
**A standard `.unified` toolbar costs 34 pt and leaves the binding case 13 pt.** That is not a budget.

---

## 7. The layout-shape rule is under-determined

### 7.1 The panel's minimum width, derived

**Measured** ideal (untruncated) widths of the four contents `interaction-design.md:474` lists for the panel:

| panel content | iOS L | iOS xxxL | iOS AX3 | macOS |
|---|---|---|---|---|
| turn status | 167.5 | 203.0 | 308.0 | 141 |
| one move-list row | 239.0 | 280.0 | 407.0 | 208 |
| control row (悔棋 · 判和 · 认输) | 278.0 | 308.0 | 440.0 | 218 |
| game metadata — ongoing | 289.0 | 400.5 | 635.0 | 233 |
| **game metadata — terminal** | **320.0** | **445.5** | **711.5** | **257** |
| *(replay transport + 翻转棋盘)* | *481.0* | *528.0* | *666.0* | *383* |
| *(transport + 翻转棋盘 + list affordance)* | *558.0* | *613.0* | *773.5* | *444* |

**The terminal metadata line drives the panel minimum: 320 pt on iOS, 257 pt on macOS, at default text.** If
the metadata may truncate, the control row drives it and the figures are 280 and 218. If the replay transport
lives in the panel, 481 and 383.

### 7.2 Side by side is never available on iPhone — derived, unconditional

`308 (board at the floor) + 320 (panel) + 16 (gutter) = 644` of usable width. The widest supported iPhone has
**400**. Even at the most permissive panel minimum (280, truncating) the threshold is 604. **Stacked is the
iPhone layout at every text size and in every state.** No scheme needs a width test on iPhone.

### 7.3 On iPad the rule's three readings disagree on 16 of 18 device-orientations

The accepted rule (`:479`, and PR #23's rewrite) says the board is sized to what remains and the panel takes
the leftover. That sentence has three defensible readings, and they are not equivalent:

- **A — board sized to width *and* height, then test the leftover.** The board grows into the width, so the
  leftover is always negative.
- **C — board sized to the remaining *height* and the 720 cap, then test the leftover.** This is the reading
  round 2's §1.2 table computes.
- **B — reserve the panel first; side by side iff what remains for the board is at least 308.**

Full screen, default text, panel minimum 320, using the measured sidebar cost:

| device / orientation | usable W | content H | **A** | **C** (leftover) | **B** (leftover) |
|---|---|---|---|---|---|
| mini 6 / A17 portrait | 704 | 1012 | stacked | stacked (−32) | **side by side** (368) |
| mini 6 / A17 landscape | 813 | 687 | stacked | **stacked** (160) | **side by side** (477) |
| mini 5 portrait | 728 | 928 | stacked | stacked (−8) | **side by side** (392) |
| mini 5 landscape | 984 | 672 | **side by side** | **side by side** (346) | side by side (648) |
| iPad 8 / 9 portrait | 770 | 984 | stacked | stacked (34) | **side by side** (434) |
| iPad 8 / 9 landscape | 760 | 778 | stacked | **stacked** (24) | **side by side** (424) |
| iPad 10 / A16 / Air 11″ portrait | 780 | 1059 | stacked | stacked (44) | **side by side** (444) |
| iPad 10 / A16 / Air 11″ landscape | 860 | 763 | stacked | **stacked** (133) | **side by side** (524) |
| Air 3 portrait | 794 | 1016 | stacked | stacked (58) | **side by side** (458) |
| Air 3 landscape | 792 | 802 | stacked | **stacked** (56) | **side by side** (456) |
| Pro 11″ 1st–4th portrait | 794 | 1073 | stacked | stacked (58) | **side by side** (458) |
| Pro 11″ 1st–4th landscape | 874 | 777 | stacked | **stacked** (138) | **side by side** (538) |
| Pro 11″ M4/M5 portrait | 794 | 1089 | stacked | stacked (58) | **side by side** (458) |
| Pro 11″ M4/M5 landscape | 890 | 777 | stacked | **stacked** (154) | **side by side** (554) |
| Pro 12.9″ / Air 13″ portrait | 984 | 1245 | stacked | stacked (248) | **side by side** (648) |
| Pro 12.9″ / Air 13″ landscape | 1046 | 967 | stacked | **stacked** (310) | side by side (710) |
| Pro 13″ M4/M5 portrait | 712 | 1319 | stacked | stacked (−24) | **side by side** (376) |
| Pro 13″ M4/M5 landscape | 1056 | 975 | **side by side** | **side by side** (320) | side by side (720) |

**Readings B and C disagree on 16 of the 18 rows.** Worse, reading C — the one round 2 computed — makes
**iPad landscape stacked on seven of nine classes**, which contradicts the accepted sentence "**Side by
side**, used by iPad landscape" (`:475`). The cause is the measured 280 pt sidebar: it was invisible to
`layout-budget.md`, which measured only portrait.

**A scheme must state a priority order, not a "derived test".** The choice is a product decision with a
visible consequence: reading B gives every iPad a panel in both orientations; reading C gives most iPads a
stacked portrait *and* a stacked landscape.

### 7.4 The oscillation is real and its band is measurable

Reading C evaluated with the *stacked* chrome subtracted and then re-evaluated after selecting side by side
(where the status and controls move into the panel) is unstable, exactly as round 2 §1.1 says. Using the
measured iOS figures the two evaluations differ by `127 pt` of board height at default text, which is
`127 / 7.728 ≈ 16.4 pt` of pitch and therefore **115 pt** of leftover width. Any window whose leftover sits
in that 115 pt band flips arrangement on every layout pass. **A scheme must evaluate the test exactly once,
against one stated quantity.**

---

## 8. iPad tiling: all 126 cells

Ordinary play at `p = 44`, default text, exact fractions, gaps ignored (optimistic):

| configuration | holds `p = 44` | of | which fail |
|---|---|---|---|
| full screen | **18** | 18 | — |
| side half | **18** | 18 | — |
| vertical two-thirds | **18** | 18 | — |
| vertical third | **8** | 18 | every portrait orientation, and mini 5 landscape |
| **top / bottom half** | **5** | 18 | all but 820×1180 portrait, 834×1194 portrait, 834×1210 portrait, 1024×1366 portrait, 1032×1376 portrait |
| **quadrant** | **5** | 18 | same five survive |
| **horizontal third** | **0** | 18 | **every device, every orientation** |

**The horizontal third is unconditionally impossible.** The tallest horizontal third on the whole 26.5 list
is 1032 × 458.7 (iPad Pro 13″, portrait); after 32 + 25 of chrome — the Pro 13″ is 1032 pt wide and so shows
the sidebar rather than a top tab bar even in portrait — that is **401.7 pt** of content against the **467 pt**
ordinary play needs at the floor, a shortfall of **65.3**. The shortest horizontal third is 1133 × 248.

The top/bottom-half failures, in full, so a scheme can see how close the near ones are:
Air 3 portrait **−7.0**, Pro 13″ landscape −8.0, Pro 12.9″ landscape −12.0, mini 6 portrait −21.5,
iPad 8/9 portrait −23.0, mini 5 portrait −51.0, Air 3 landscape −82.0, iPad 8/9 landscape −94.0,
Pro 11″ landscape −107.0, iPad 10/A16 landscape −114.0, mini 6 landscape −152.0, mini 5 landscape −179.0.

### 8.1 What a declared scene minimum permits

**Derived** over all 126 cells. The right column counts cells the system could still offer.

| declared scene minimum | full | side half | top/bot half | vert third | 2/3 vert | horiz third | quadrant | **permitted of 126** |
|---|---|---|---|---|---|---|---|---|
| 320 × 642 | 18 | 18 | 2 | **11** | 18 | 0 | 2 | **69** |
| **360 × 584** | 18 | 18 | **5** | 8 | 18 | 0 | **5** | **72** |
| 360 × 642 *(result card at L)* | 18 | 18 | 2 | 8 | 18 | 0 | 2 | 66 |
| 360 × 664 *(resident 1-row list at L)* | 18 | 18 | 2 | 8 | 18 | 0 | 2 | 66 |
| 360 × 698 *(result card through AX1)* | 18 | 18 | **0** | 8 | 18 | 0 | **0** | 62 |
| **360 × 765** *(result card through AX3)* | **17** | **17** | 0 | 7 | 17 | 0 | 0 | **58** |
| 372 × 642 | 18 | 18 | 2 | **6** | 18 | 0 | 2 | 64 |

**A 765 pt scene minimum excludes an iPad mini in landscape from running the app at full screen at all**
(1133 × 744, and 744 < 765). Supporting the result card at AX3 in a minimum-size window and supporting the
iPad mini are mutually exclusive.

### 8.2 The scene height each state needs, at 360 pt of scene width

`scene height = chrome height (§5.2) + board block + 32 (status bar) + 83 (bottom bar, measured on iPhone;
the iPad windowed value is **unmeasured** — see §11)`:

| state | xS | L | xxxL | AX1 | AX3 | AX5 |
|---|---|---|---|---|---|---|
| `play-AI` | 575 | **582** | 596 | 610 | **653** | 760 |
| `result-replaces` | 628 | **642** | 671 | 663 | **765** | 902 |
| `threefold-replaces` | 600 | 610 | 660 | 686 | 757 | 1080 |
| `replay-speed` | 612 | 620 | 634 | 607 | 632 | 721 |
| `replay-list1` | 654 | 664 | 714 | 698 | 800 | 994 |
| `prestart-AI` | 632 | 636 | 642 | 616 | 631 | 646 |

---

## 9. The macOS window range

| bound | value | source |
|---|---|---|
| smallest sensible content width | **348** = 308 board + 2 × 20 margin | derived |
| content width at which side by side becomes possible | **601** = 308 + 257 panel + 16 gutter + 2 × 20 | derived, macOS panel minimum |
| smallest content height holding every resident state at `p = 44` | **511** (`replay-list1`) or **503** (`result-replaces`, if replay's list is a sheet) | derived from §5.4 |
| largest content height on the display the contract names | **550** no toolbar / 542 compact / **516** unified | measured |
| largest content height on a 16″ MacBook Pro | ≈ 1060 | reasoned |
| where the board stops growing | 720 pt core, reached at content height 772 | accepted cap |

macOS therefore has slack everywhere except the two "alongside" states and the resident multi-row move list,
and its single binding coincidence is that a **standard unified toolbar leaves the result card 13 pt** on the
named worst-case display. A scheme should state which toolbar the Mac window carries; the value is worth more
than the entire play-control row.

---

## 10. What relaxing each constraint would cost

Every row is a real option; none is free. The numbers are from §6.

| candidate relaxation | what it buys | what it costs |
|---|---|---|
| **Drop the iPhone SE (2nd/3rd gen) from the supported list.** | The result card and the threefold notice hold at the floor through **AX3** on the next-narrowest iPhone (375 × 812). | Buys exactly **one Dynamic Type step**: 375 × 812 still fails both from AX4. Seven of the ten iPhone classes still fail somewhere. And the SE 3rd generation is a currently supported device. |
| **Cap the declared Dynamic Type range at AX1.** | Every state except `result-alongside` and `replay-list3` holds `p = 44` on **every** supported iPhone. | The app declares that it does not support the five accessibility text sizes, which is what the setting exists for. |
| **Let `p` fall below 44 above the declared range.** | Nothing breaks structurally; the pitch degrades continuously. On the SE with the card at AX3 the board sits at **31.7 pt** — 72 % of the floor, a 25 pt disc, a 13 pt symbol. | Contradicts `:129` ("`p ≥ 44 pt` on **every interactive board**") and `:503`. The user at AX3 is the user least able to hit a 31.7 pt target. |
| **Declare the final board non-interactive**, as the pre-start preview already is. | The floor stops binding in exactly the two infeasible states, and **I1 and I2 dissolve**. The board would size to whatever remains: 222 pt of block at AX3, `p = 31.7`. | The contract's own rationale ("The floor exists to protect interaction, and a preview has none to protect") applies — but 悔棋 is on the card, so the board is one tap from being interactive again. And the floor also protects the marker geometry, whose finest distinctions are `0.015 p`. |
| **Let the page scroll at accessibility sizes.** | The board keeps `p = 44` and the chrome keeps its size at every text size on every device. | Breaks "the final board remains **fully visible**" (`:337`) unless that is rescoped to "fully visible when the page is scrolled to the board". The result card is non-dismissible, so a user could scroll it off screen. |
| **Make the result card a sheet.** | Removes it from the resident budget entirely. | Directly prohibited: the card "cannot be dismissed by tapping outside it" and the final board "may not be covered". The owner's transient-surface clarification explicitly does **not** extend to it. |
| **Tighten the inter-element gap from 12 pt to 0.** | 24 pt in every three-element state. | Recovers **I3 at xS only**. Does not recover I1 (−62 remains), I2 (−54), I4 or I5. |
| **Keep the move list out of the resident layout** (the sheet decision). | Removes **I4** on every device, and removes `replay-list3` from the budget. | Nothing in the accepted requirement — "highlights the currently displayed move and allows the user to jump to a selected move" — needs residency. This is the cheapest of all the relaxations and the only one that costs no accepted sentence. |
| **Declare a scene minimum of 360 × 584 instead of 642 or higher.** | 72 of 126 tiling cells instead of 66 or 58. | A minimum-size iPadOS window could not present the result card at the floor even at default text. |
| **State that horizontal thirds and most quadrants are unsupported.** | Nothing — it is already true. | `testing.md:55` ("iPad adapts … **including the system tiling configurations**") and `product.md:27` must be amended; the HIG note that apps do not control multitasking configurations means the app cannot prevent the user from choosing one. |

---

## 11. What is still open, and what would close it

1. **The iPad chrome in a narrow window is unmeasured.** Below 668 pt the container becomes a bottom bar; the
   measured 83 pt figure is the **iPhone**'s. A hosted-window proxy on iPad reported a 72 pt bottom inset
   with a 25 pt indicator, i.e. a 47 pt bar, but a hosted window is not a resized scene. Closing this needs a
   person dragging window controls in Simulator or on a device. **If the true figure is 83 rather than 72,
   every scene-minimum height in §8.2 rises by 11 pt.**
2. **What iPadOS does when a user selects a tile smaller than the declared minimum is unobserved.** The
   documentation does not say; "apps don't control multitasking configurations" makes clamping or
   overlapping more likely than omission, but that is reasoned.
3. **Five iPads cannot be booted on this toolchain** (§1.1). Their insets are transferred within a stated
   class — home-button iPads from iPad (9th gen), modern iPads from iPad mini (A17 Pro).
4. **The element heights are reconstructions.** Standard SwiftUI controls carrying the accepted copy. They
   are a **floor** for what the real design costs; the real turn status, control row, card and move list may
   each be taller, and every "ok" in §6 is therefore optimistic while every `--` is conservative.
5. **The 12 pt inter-element gap and the count of gaps per state are mine.** §10 shows which conclusions
   survive setting them to zero; I1, I2, I4 and I5 all do.
6. **The large-title navigation bar was not re-measured here**; `layout-budget.md`'s 106 pt is carried over
   and is not load-bearing for anything above, since no state uses one.
7. **Every iOS number is from iOS 27.0, not 26.5.** Re-measure before freezing.
8. **The sidebar is partly the user's choice** (HIG). A scheme must say what happens when a user on an iPad
   mini in landscape switches to the sidebar and 280 pt of width disappears.

---

## Appendix — reproducing this

All probe sources are in `discussion-drafts/layout-probe/` and are scratch code in no repository.

| file | what it measures |
|---|---|
| `probe8.swift` | screen bounds, safe areas, tab and nav-bar heights at **all twelve** Dynamic Type steps; every accepted-copy element's height and ideal width at all twelve sizes across fifteen widths; compact-size-class chrome on iPad |
| `probe9.swift` | chrome against the **real** window bounds in the real orientation; the `sidebarAdaptable` presentation at 28 widths |
| `probe10.swift` | the same at 1 pt resolution around the two breakpoints |
| `macprobe2.swift` | macOS title-bar and toolbar chrome for five toolbar styles; every element at all twelve Dynamic Type steps (measuring that macOS honours none of them) |
| `budget8.py`, `table8.py`, `shapes8.py` | the arithmetic in §§4–9 |
| `out8-*.txt`, `out9-*.txt`, `out10-*.txt`, `out-mac2.txt`, `table8-out.txt`, `shapes-out.txt` | raw output |

```
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcrun -sdk iphonesimulator swiftc -target arm64-apple-ios26.0-simulator -O probe8.swift -o LayoutProbe8P.app/LayoutProbe8
./run8.sh <udid> <label> P          # portrait build
./run8.sh <udid> <label> L          # landscape-only Info.plist: the only way to measure iPad landscape,
                                    # since requestGeometryUpdate is refused and simctl cannot rotate
xcrun swiftc -O macprobe2.swift -o macprobe2 && ./macprobe2
python3 table8.py all ; python3 shapes8.py
```

Simulator devices created for this run are named `MXQ8-*`.

---

## Corrections this note makes to `layout-budget.md`

Recorded explicitly, because a later agent will read both.

| `layout-budget.md` | corrected to | why it matters |
|---|---|---|
| iPad bottom safe area **20** | **25** (measured, three devices, both orientations) | every iPad budget was 5 pt optimistic; round 2's "+4.5 pt of slack" becomes −0.5 |
| iPad vertical chrome **116** | **121** with a home indicator, 96 on home-button iPads, **57** when the sidebar presents | the sidebar case was never considered |
| "the sidebar never appeared … the container costs 0 pt horizontally on iPad" (§2.2, §6.6) | the sidebar appears at **≥ 1025 pt** and costs **280 pt**; it is present on eight of nine iPads in landscape and on the Pro 13″ in portrait | reinstates the width-side oscillation risk that §6.6 declared closed |
| result card at AX3 = **206 pt** | **254 pt** on any device 375 pt wide, because the card's ideal width is 343.5 and it wraps | round 2's AX3 shortfalls were understated by 48 pt |
| element heights at five text sizes | **all twelve**, and the system chrome confirmed invariant across all twelve | the failures at AX2 and AX4 were invisible before |
| macOS treated as having a Dynamic Type range | **macOS honours no Dynamic Type at all** (measured) | a macOS minimum "verified through AX3" is not a claim about anything |
