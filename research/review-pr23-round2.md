# Pre-merge review — PR #23 `design/app-shell-and-layout`, round 2

Reviewed: `git diff main...design/app-shell-and-layout`, single commit `77583b1` on top of `main`
(`1639da5`, which already carries PR #24), 2 files, +47 −9. Checked against `docs/interaction-design.md`,
`docs/product.md`, `docs/testing.md`, `docs/game-data.md`, `docs/core-interface.md` on the branch, against
my own round-1 rejection (`discussion-drafts/review-pr23.md`), and against the measured evidence in
`discussion-drafts/layout-budget.md`. Nothing under `MiniXiangqi/` or any worktree was modified; no Git or
GitHub state was changed.

Line numbers are the branch copies. All arithmetic below is mine, recomputed from `layout-budget.md`'s
**measured** inputs — I did not carry over any number from round 1.

**Standing assumptions, stated once.** Inter-element gap 12 pt and two gaps per stacked state; outer layout
margin 16 pt (measured); gutter 16 pt between board and panel; iPhone content height = screen − top inset −
83 (measured tab container), with no navigation bar; iPad scene chrome 116 pt (measured, full screen);
macOS content height 550 on the display the contract names, no toolbar. Numeral strips per the accepted
`:153`–`:154` formulas, shown at L and xxxL, hidden from AX1 up. Element heights from `layout-budget.md`
§2.4. Where a conclusion depends on one of these I say so.

---

## 1. Does the shape rule produce the claimed results?

> "**The choice is derived, not a named breakpoint.** Size the board to the height that remains after the
> chrome. If width is left over — enough for the panel — the panel goes beside it and the layout is side by
> side. If the board is instead bound by width, so that filling the height would overflow it, there is no
> room for a panel and the layout is stacked. That single test produces the right answer everywhere without
> naming a number: a portrait canvas is width-bound and stacks, a landscape one has width to spare and
> splits." — `:498`

### 1.1 "the height that remains after the chrome" is not one quantity, and the rule oscillates — **blocking**

The resident chrome is **not the same in the two arrangements**. In stacked, the turn status and the control
row sit above and below the board (`:500`). In side-by-side they are in the panel (`:501`, `:282`), so the
board gets the whole height. The difference is 127 pt on iOS (36.5 + 66.5 + 24) and 100 pt on macOS
(32 + 44 + 24). The rule must be evaluated *before* the arrangement is known, and the contract never says
which chrome to subtract. The two readings differ by exactly that much of leftover width, so there is a
97–127 pt band of window widths in which the rule selects side-by-side and, having selected it, the
condition that selected it becomes false.

Worked example, macOS content **820 × 550**, panel minimum 320 (the derived figure in `layout-budget.md`
§4.1; the contract states none — see 1.3):

| step | board height budget | board core | width left after board + margins + gutter | verdict |
|---|---|---|---|---|
| evaluate with the stacked chrome (100) | 550 − 100 = 450 | 406.5 | 820 − 32 − 406.5 − 16 = **365.5** | ≥ 320 → **side by side** |
| now in side-by-side the status and controls are in the panel | 550 | 503.5 | 820 − 32 − 503.5 − 16 = **268.5** | < 320 → **stacked** |
| back in stacked | 450 | 406.5 | **365.5** | ≥ 320 → side by side … |

Band at C = 550 on macOS: **W ∈ [775, 871]**, i.e. 97 pt wide, squarely inside ordinary Mac window widths.
On iOS/iPadOS the band is 127 pt wide at any given height. This is the same defect class as round-1 finding
2.4, except that round 1's cycle ran through the *navigation* presentation — which `layout-budget.md` §2.2
then measured away (the container costs 0 pt horizontally) — whereas this cycle is **intrinsic to the new
rule**: it is created by the two arrangements having different chrome, which is the whole point of having
two arrangements. Nothing in the change breaks it: there is no evaluation order, no hysteresis, and the new
gate does not test stability (round 1's stability gate was dropped in the rewrite).

**Correction.** Evaluate the test once, against the height a side-by-side board would have: "Size the board
to the height that remains after the *system* chrome alone — in side by side the turn status and controls
are in the panel, so nothing else is subtracted — and choose side by side only if the width still left
clears the panel's minimum. The test is evaluated against that height in both cases, so the choice can
never depend on the arrangement it selects."

### 1.2 "a portrait canvas is width-bound and stacks" is false on eight of the nine iPad portrait classes — **blocking**

The board is capped at 720 pt (`:511`). On every supported iPad in portrait except the mini 6 the board hits
the **cap**, not the width. The rule as written offers only two branches — height-bound (test the leftover
width) and width-bound (stack) — and has no branch for the case that actually occurs. The stated reason for
the headline claim "iPad portrait stacks" is therefore wrong on 8 of 9 devices; what really makes them stack
is the 720 cap plus a panel minimum the contract does not state.

Every supported iPad, full screen. Content height = H − 116; available width = W − 32; leftover =
availW − board − 16. Both readings from 1.1 agree on every row here, so the ambiguity does not change these
verdicts.

| iPad (portrait W × H) | content H | board core | what binds it | width left | verdict at panel min 320 | at 280 | at 264 |
|---|---|---|---|---|---|---|---|
| mini 6 / A17 744 × 1133 | 1017 | 712 | **width** | −16 | stacked | stacked | stacked |
| mini 5 768 × 1024 | 908 | 720 | **cap** | 0 | stacked | stacked | stacked |
| iPad 8/9 810 × 1080 | 964 | 720 | **cap** | 42 | stacked | stacked | stacked |
| iPad 10 / A16 / Air 11 820 × 1180 | 1064 | 720 | **cap** | 52 | stacked | stacked | stacked |
| Air 3 834 × 1112 | 996 | 720 | **cap** | 66 | stacked | stacked | stacked |
| Pro 11 1st–4th 834 × 1194 | 1078 | 720 | **cap** | 66 | stacked | stacked | stacked |
| Pro 11 M4/M5 834 × 1210 | 1094 | 720 | **cap** | 66 | stacked | stacked | stacked |
| Pro 12.9 / Air 13 1024 × 1366 | 1250 | 720 | **cap** | 256 | stacked | stacked | **side by side** |
| Pro 13 M4/M5 1032 × 1376 | 1260 | 720 | **cap** | **264** | stacked | stacked | **side by side** |

**Correction.** State the rule with three branches, and give the real reason: "The board is sized to the
remaining height, then to the available width, then to its 720-point cap, whichever is smallest. Side by side
is chosen when the width still left over clears the panel's minimum. On iPad in portrait the board reaches
its cap and the remainder is below the panel's minimum, so portrait stacks; the mini reaches the width first
and stacks for that reason."

### 1.3 "enough for the panel" — the panel's minimum width is still defined nowhere — **blocking**

> "If width is left over — **enough for the panel** — the panel goes beside it" — `:498`

Round-1 finding 2.1 was that the panel's minimum width exists in no document, so the derived rule is not
derivable. The rewrite changes the rule's *shape* and keeps the same undefined operand. I re-grepped
`docs/`: the panel's contents are listed at `:282` and `:501`, and no width is derived from them anywhere.

This is not academic here. The whole product-owner decision "iPad portrait stacks like iPhone" rests on the
last two rows of the table above, where the leftover is **256 and 264 pt**. `layout-budget.md` §4.1 derives
280 pt (control row, metadata allowed to truncate) as the smallest defensible panel minimum and 320 pt
(untruncated terminal metadata line) as the honest one. The decision therefore survives by **16 pt** against
the smaller of the two, and fails outright at any panel minimum below 264. A number that carries a
product-owner decision by 16 pt must be written down.

**Correction.** State the panel's minimum width in the same section, derived from its stated contents, and
say whether the metadata line may truncate — that single choice moves the figure between 280 and 320.
`layout-budget.md` §4.1 supplies both, with the driver named.

### 1.4 "a landscape one has width to spare and splits" is false for landscape windows under ~871 pt — **should-fix**

A 700 × 550 Mac content rectangle is landscape and stacks (leftover 245.5 under the stacked-chrome reading,
148.5 under the other; both below any panel minimum). So does a 700 × 660 iPad window. The sentence is a
blanket claim about shape, and shape is not what the rule tests — the rule tests an absolute leftover width.
The new testing gate repeats the claim verbatim and is falsifiable by resizing a Mac window (see 6, gate G2).

**Correction.** "A portrait canvas has no width to spare and stacks; a canvas wide enough that the leftover
clears the panel's minimum splits. Shape is the intuition; the leftover width is the test."

### 1.5 Stacked surplus width has no stated home, and it is now up to 280 pt — **should-fix**

> "Surplus width goes to the panel, and surplus height leaves the board vertically centred" — `:511`

In the stacked layout there is no panel, and after this change iPad portrait — every supported iPad — is
stacked. Surplus width in that layout runs from 0 (mini 6) to 280 pt (Pro 13), and the contract says nothing
about it. Surplus *height* is also large there: on a Pro 13 in portrait the composition is 899 pt in a
1260 pt content box.

**Correction.** "In the stacked layout surplus width leaves the board horizontally centred, as surplus
height leaves it vertically centred."

---

## 2. Does the sheet remove the failures it is claimed to remove?

### 2.1 It does — verified, and this is the change's strongest part

Recomputed with the move list out of the resident layout. Stacked replay is now board block + turn status +
transport (+ speed control), no move rows. `layout-budget.md` §6.3's three named failures:

| failure named in the evidence | round-1 shortfall | recomputed with the sheet | verdict |
|---|---|---|---|
| iPhone SE, result card, default text, **with** a nav bar | −17.5 | −17.5 (unchanged; fixed by removing the bar, 2.2) | fixed by 2.2 |
| iPhone SE, **stacked replay**, any text size | −18.5 at best | transport 466.0 (**+98.0**), with speed 505.0 (**+59.0**) against 564 | **fixed** |
| macOS constrained display, **stacked replay** | −19 to −59 | 439 (+77 against 516, +111 against 550) | **fixed** |

At default text the SE now holds every resident state at its *natural* pitch, not merely at the floor:
ordinary play and replay at p = 49.0 (width-bound), the result card at p = 48.6.

### 2.2 The navigation-bar arithmetic is correct — verified

> "on the shortest supported iPhone that bar is the difference between the result card fitting and not
> fitting" — `:509`

375 × 667, top inset 20, tab container 83 → content 510 with a 54 pt inline navigation bar, 564 without.
Result-card state = board block + turn status 36.5 + card 127.0 + 24.

| board | required | content 510 (bar) | content 564 (no bar) |
|---|---|---|---|
| at the 44 pt floor (block 340) | 527.5 | **−17.5** | **+36.5** |
| largest board that fits | — | p = 41.6 — **below the floor** | b = 340.4, **p = 48.6** |

The claim is exactly right, and stronger than stated: without the bar the board is 11 % above its floor
rather than at it. (That last point falsifies the gate — see 6, gate G4.)

### 2.3 "It is a single destination with no hierarchy to climb" is false for replay, which the same rule strands — **blocking**

> "**The board page presents no navigation bar.** It is a single destination with no hierarchy to climb" — `:509`

There are two board pages. History replay is pushed *into* — `:391` "Selecting an entry opens its read-only
replay", `:365` 回放 "opens the newly created History record from its initial position" — and `:382` requires
the user to return to the History list for Pin, Share and Delete. Replay's control inventory is "the
transport controls, **翻转棋盘**, and the affordance that summons the move list" (`:270`): no exit. With the
navigation bar removed there is no Back affordance anywhere in replay, and the contract defines none.

The rule as written is also unnecessary for replay: at the floor, stacked replay costs 466.0 (transport) and
505.0 (transport + speed) against the 510 pt content a replay page *with* a bar would have. But it is
necessary at AX3 (516.5 > 510), so simply exempting replay costs the AX3 commitment.

**Correction.** Scope the sentence — "The play board page presents no navigation bar" — and state how replay
is left: either a 完成 control in the replay row (which makes it four controls plus the transport, so say so),
or a standard navigation bar in replay with the AX3 consequence recorded.

### 2.4 A sheet over the board contradicts two accepted rules about material and the board block — **blocking**

> "Preserve board readability and interaction clarity where translucent or material surfaces surround game
> content. **They surround it and never overlap it**, per the boundary below." — `:33`, accepted
>
> "**Where it may not.** **No glass surface may intersect the board block**" — `:40`, accepted (PR #24)
>
> "System-provided glass — the tab bar or sidebar, navigation bar and toolbar, alerts, **sheets**, context
> menus, and History swipe actions — is additional and automatic." — `:38`, accepted

`:38` establishes that a sheet **is** glass in this contract's vocabulary; `:40` then forbids any glass
surface from intersecting the board block, without exempting the system-provided kind. On a 375 × 667 iPhone
the board block occupies roughly the middle 379 pt of a 564 pt content area; a sheet at any detent covers the
bottom of the screen and therefore intersects it. The rewrite makes that intersection the *primary* way to
read the move list, in ordinary play and in replay, and reconciles nothing. `:40`'s selling point is that it
is "a rectangle a reviewer can measure against a screenshot" — a reviewer measuring it against the new sheet
gets a failure.

**Correction.** Amend `:40` in this change: "System-provided glass presented over the whole page — sheets and
alerts — is outside this rule; it is transient, user-summoned, and dismissible, and the board is unobstructed
the moment it is dismissed. The rule binds the three custom surfaces and any resident chrome." Then say
explicitly that summoning the move list is allowed to cover the board.

### 2.5 In ordinary play nothing is allowed to summon the sheet — **should-fix**

> "Three controls sit together during play, never more" — `:266`
> "Anything consulted rather than watched … is reached on demand **as a sheet**" — `:500`

The play-control inventories for the two play modes are full at three. Replay gets an explicit "affordance
that summons the move list"; ordinary play gets none, and the contract asserts the on-demand behaviour
anyway. This is round-1 finding 4.4, unfixed. The new open item asks "how the move list is summoned", so it
is at least flagged — but accepted text and a new gate (G1: "in play and in replay alike") assert a behaviour
whose only means the same document says is undefined and whose obvious home the same document caps out.

**Correction.** Add to the open item: "including where the summoning affordance lives during ordinary play,
which the three-control cluster has no room for."

### 2.6 The replay row is seven controls and still omits the accepted autoplay speed control — **should-fix**

`:379` accepts a five-control transport; `:270` adds 翻转棋盘 and the move-list affordance, making seven; and
`:384` accepts "session-only speeds of 0.5×, 1×, and 2×", which appears in neither `:270` nor gate G7. This is
round-1 finding 4.3, unfixed and now one control worse. Measured, the six-control row's ideal width is 481 pt
against 343 available on the SE, so it already wraps; the seventh is added with no width check. The SE
absorbs it (+98 of slack at the floor), so this is a completeness defect rather than a fit one.

**Correction.** "**Replay** — the transport controls including the autoplay speed control, 翻转棋盘, and the
affordance that summons the move list." Mirror it in gate G7.

### 2.7 Summoning the sheet during autoplay — **nit**

`:384` pauses playback on manual navigation, board flip, and backgrounding. Whether summoning the move list
pauses it is undefined, and the move list is where the highlight the user is watching lives.

---

## 3. The stated minimums

> "**Minimum sizes are per platform, because the platforms do not measure the same thing.** An iPadOS scene
> contains system chrome that a macOS content rectangle does not, so one number cannot serve both. macOS
> takes a minimum of **360 by 512 points of content**; an iPadOS scene takes a minimum of **360 by 648
> points**." — `:505`

### 3.1 Both numbers hold at default text — verified

Required height = board block + turn status + state + 24. macOS uses the measured macOS element heights,
iPadOS the iOS ones with 116 pt of scene chrome subtracted (532 pt of content at 648).

| stacked state | macOS required | vs 512 | iPadOS required | vs 532 (scene 648) |
|---|---|---|---|---|
| ordinary play | 440 | **+72** | 467.0 | **+65.0** |
| threefold notice | 481 | +31 | 495.5 | +36.5 |
| replay (transport, sheet) | 439 | +73 | 466.0 | +66.0 |
| replay (transport + speed) | ~465 | ~+47 | 505.0 | +27.0 |
| **result card** | **503** | **+9** | **527.5** | **+4.5** |

Width: 360 − 32 = 328 ≥ 308 at the floor ✓, and above the 308 pt at which the measured control row starts to
wrap. The width is sound and 360 is the right choice over 372/380 (`layout-budget.md` §5.3).

### 3.2 The minimums do not hold at the text sizes the same section commits to — **blocking**

> "**Dynamic Type is designed and verified through the AX3 accessibility size.**" — `:513`

Recomputed at the floor, strips shown at L/xxxL and hidden from AX1 (per `:157`), on the two cases the
contract names:

**iPhone SE, 375 × 667, no navigation bar — content 564**

| size | play | result card | threefold | replay | replay + speed |
|---|---|---|---|---|---|
| L | +97.0 | +36.5 | +68.5 | +98.0 | +59.0 |
| xxxL | +83.0 | +8.0 | +18.5 | +84.5 | +45.5 |
| AX1 | +103.0 | +16.0 | +27.5 | +111.0 | +72.0 |
| **AX3** | +26.0 | **−38.0** | **−78.0** | +86.5 | +47.5 |

**iPadOS at the declared minimum scene 360 × 648 — content 532**

| size | play | result card | threefold | replay | replay + speed |
|---|---|---|---|---|---|
| L | +65.0 | **+4.5** | +36.5 | +66.0 | +27.0 |
| xxxL | +51.0 | **−24.0** | **−13.5** | +52.5 | +13.5 |
| AX1 | +71.0 | **−16.0** | **−4.5** | +79.0 | +40.0 |
| **AX3** | **−6.0** | **−70.0** | **−110.0** | +54.5 | +15.5 |

So: at AX3 the shortest supported iPhone cannot present the result card (−38) or the threefold notice (−78)
without breaking the floor, and the declared iPadOS minimum cannot present **ordinary play** (−6), the card
(−70) or the notice (−110). The iPadOS minimum fails the result card from **xxxL** upward — two steps below
the committed range. `:513` says the design is verified through AX3 and permits the board below its floor only
*above* AX3; the numbers say the escape is needed at AX3 and below. Gate G6 asks a tester to verify exactly
this and will fail.

**Correction.** One of: (a) raise the iPadOS scene minimum to cover AX3 — the card at AX3 needs 602 + 116 =
**718**, which costs the remaining tiling configurations (see 3.4); (b) scope the AX3 commitment honestly —
"designed and verified through AX3 at full screen; at the declared minimum sizes through xxxL"; or (c) extend
the yielding rule downward — "from xxxL upward the board yields ahead of the layout breaking" — and reconcile
it with `:503`/`:515`/`:129` per 3.3. Whichever is chosen, the two paragraphs must state the same thing.

### 3.3 The AX3 escape contradicts three unamended sentences, one of them accepted in another section — **blocking**

> "Above that **the board is permitted to fall below its pitch floor** rather than the layout breaking" — `:513`
>
> "a point of the grid is **never** smaller than 44 points on **every** platform" — `:503`, two lines above
>
> "That preference has a floor: **the board may not be driven below the sizes above**" — `:515`, two lines below
>
> "The accepted floor is `p ≥ 44 pt` on **every interactive board**, fixed under [Layout shapes] below." —
> `:129`, accepted in PR #24

The exemption is inserted between two sentences that deny it and is not reflected in the accepted Board
metrics sentence that delegates the floor to this very section. `:129` also draws the interactive /
non-interactive line that `:517` relies on for the pre-start preview; an unannounced third case ("interactive
but above AX3") weakens it silently.

**Correction.** Amend all four in this change: `:503` "never smaller than 44 points, except as
[Dynamic Type] below permits"; `:515` "may not be driven below the sizes above within the designed text-size
range"; `:129` "`p ≥ 44 pt` on every interactive board within the text-size range fixed under Layout shapes".

### 3.4 The 648 pt scene minimum is a product-scope consequence, still made outside `product.md` — **blocking**

The change touches two files; `product.md` is untouched. Recomputed over the full 26.5 iPad list (9 size
classes × 2 orientations = 18 device-orientations, 6 configurations each, exact fractions, gaps ignored):

| configuration | requirement at 360 × 648 | permitted |
|---|---|---|
| full screen | — | 18/18 |
| side half | W ≥ 720 | 18/18 |
| top/bottom half | H ≥ 1296 | **2/18** (only the 12.9″/13″ in portrait) |
| vertical third | W ≥ 1080 | 8/18 |
| horizontal third | H ≥ 1944 | **0/18** |
| quadrant | W ≥ 720 and H ≥ 1296 | **2/18** |

**60 of 108 excluded** — matching `layout-budget.md` §5.3 exactly. Three accepted statements are left
contradicting it:

> "iPad adapts to every orientation and to full-screen and windowed sizes **including the system tiling
> configurations**." — `testing.md:55`, pre-existing gate. Cannot pass on 16 of 18 device-orientations.
>
> "iPad supports every orientation, because iPadOS expects an app … **to being windowed at arbitrary sizes**"
> — `interaction-design.md:489`, accepted, untouched.
>
> "iPad supports every orientation, **as iPadOS multitasking expects.**" — `product.md:27`, accepted, untouched.

The change does add the honest platform sentence — "A declared minimum bounds how far a window or scene may
be resized; it is not a claim about which multitasking configurations the system will offer" — which fixes
round-1 finding 3.1 cleanly. But that sentence describes the mechanism, not the consequence, and it is the
consequence (round-1 findings 3.4, 3.5 and 3.6) that recurs here, **quantitatively worse** than round 1: the
height minimum went from 500 to 648.

`layout-budget.md` §6.2 offers 584 as the alternative and prices it: 54 configurations excluded instead of 60,
at the cost of the result card at a minimum-size window. The change picks 648 without recording that the
choice existed.

**Correction.** Amend `product.md:27` in this PR to state the tiling consequence, have `interaction-design.md`
reference it, reword `testing.md:55` to name the configurations that are supported, and record why 648 was
chosen over 584.

### 3.5 "one number cannot serve both" — the stated reason is half the evidence — **should-fix**

The contract gives one reason (a scene contains chrome a content rectangle does not). `layout-budget.md` §6.1
gives two, and the second is independent: the *same* elements are 20–25 pt smaller on macOS (result card 127
vs 107, control row 66.5 vs 44). Both are needed: with only the first reason a later reader can "simplify" by
adding 116 to the macOS number, getting 628, and be wrong by 20 pt — the true iPadOS requirement is 644.

**Correction.** Add: "and the same elements are smaller on macOS — a result card of 107 points against 127 —
so even after the chrome is accounted for the two requirements differ."

### 3.6 The 4.5 pt of iPadOS slack rests on chrome measured only at full screen — **should-fix**

The 116 pt figure was measured on iPad at 744, 820 and 1032 pt of width, full screen. It has never been
measured in a 360 pt-wide scene, where the horizontal size class is compact and the tab container may present
as an iPhone-style bottom bar (measured at 83 pt on iPhone, against 64 at the top on iPad). If the windowed
figure is 135 rather than 116, the result card's 4.5 pt of slack becomes −14.5 and the binding case fails at
default text.

**Correction.** Either measure the chrome at 360 pt of scene width before fixing 648, or state the 116 pt
input in the contract so that a later measurement is known to invalidate the number.

### 3.7 The macOS toolbar is still undeclared — **should-fix**

The 550 pt figure the same paragraph cites assumes no toolbar (measured). A standard `.unified` toolbar costs
34 pt, leaving 516 on the named worst-case display — 4 pt above the declared 512 minimum. `.expanded` leaves
499, below it, so the app could not present its own minimum window on the display the contract names as its
worst case. `:38` lists "navigation bar **and toolbar**" among the system glass the app may carry, so the
question is open in the contract, and `:509` removes only the navigation bar.

**Correction.** "The Mac window carries no toolbar, or at most a `.unifiedCompact` one; a standard unified
toolbar would leave four points above the declared minimum on the display named above."

### 3.8 "width never binds" contradicts the shape rule seven lines earlier — **should-fix**

> "Height is what binds on every iPhone; **width never is**." — `:507`
> "a portrait canvas is **width-bound** and stacks" — `:498`

Computed, the board on **every** supported iPhone is width-bound: on the SE the width allows 343 and the
height allows 401 after the stacked chrome. `:498` needs that to be true (it is what selects stacked);
`:507` denies it. The intended meaning of `:507` — that the *fit* problems are height problems — is true, but
the section uses one word for two things.

**Correction.** "Height is what runs out first on every iPhone; the width is never what fails, though it is
what sizes the board."

### 3.9 The device is not named — **nit**

`:507` gives dimensions only. `layout-budget.md` §6.2: "The contract should name the device and both
dimensions." **Correction.** "…is the iPhone SE (2nd and 3rd generation) at 375 by 667 points".

---

## 4. What the rewrite touches that was previously accepted

### 4.1 `:519` and `:492` now refer to a width-driven layout rule that no longer exists — **blocking**

> "Navigation uses one adaptive container, presenting as a tab bar at narrow widths and as a sidebar at wide
> ones. It follows **the same width-driven rule as the layout shapes** rather than device identity" — `:519`,
> untouched
>
> "Windows devices that rotate follow the same **width-driven layout rules**" — `:492`, untouched
>
> "chosen by **the shape of the space** rather than by device identity" — `:496`, changed by this PR

The layout shapes no longer have a width-driven rule; `:519` points at a rule the same commit deleted, and
the reference is load-bearing — it is the only statement of when the sidebar appears. The corresponding
pre-existing gate is broken too (see 6, gate P1). This is the navigation half of the open item the change
deletes (see 5.1).

**Correction.** Give navigation its own stated threshold, or say explicitly that navigation follows the same
*derived* test: "It presents as a sidebar wherever the layout is side by side and as a tab bar wherever it is
stacked." Then fix `:492` to "the same layout rules".

### 4.2 翻转棋盘 in Free Play is still lost, and the new justification does not recover it — **blocking**

> "Nothing is lost: 判和 and 认输 are meaningless once the game is over, **翻转棋盘 remains reachable from the
> recorded card's replay**, and the card carries the two actions that do apply. In the side-by-side layout the
> panel has room for both, and **the controls remain visible but disabled**." — `:360`
>
> "In Free Play … a visible **Flip Board** control allows the player to change orientation **at any time**."
> — `:214`, accepted

Round-1 finding 5.3 was blocking. The rewrite answers it by pointing at replay. Trace the accepted flow: the
card appears (`:359`); before confirmation the actions are 悔棋 and 结束对局 (`:362`) — **no replay exists
yet**, so during the entire pre-confirmation window the flip control is simply gone. After 结束对局 the card
offers 回放, which "opens the newly created History record **from its initial position**" (`:365`), so
recovering the flipped *final* position costs a confirmation, an immutable History record, a screen change and
a jump-to-end. And in side-by-side the panel's 翻转棋盘 is explicitly disabled. "At any time" is contradicted
in both layouts, and "nothing is lost" remains false.

**Correction.** Exempt the flip control from the displacement and the disabling: the card takes the place of
the *game-action* controls (悔棋, 判和, 认输), and 翻转棋盘 stays live in Free Play and replay as `:214`/`:215`
require. Mirror it in gate G10.

### 4.3 Side-by-side shows two 悔棋 controls in opposite states — **should-fix**

The card carries an enabled 悔棋 (`:362`); the panel's control row stays "visible but disabled" (`:360`),
including its own 悔棋. Same label, same panel, both states at once. Round-1 finding 5.4, unfixed.
**Correction.** Hide the displaced controls in side-by-side too, or exclude 悔棋 from the disabled row.

### 4.4 `:292` still points at an open item this change deleted — **should-fix**

> "The placement of the persistent **可判和** affordance **remains open below** and is not settled by this."
> — `:292`, accepted text, untouched

The item it points to ("Resolve how the non-dismissible result card, the retained draw-claim affordance, and
accessibility text sizes fit…") is deleted by this commit, and `:272` settles the placement. Per the status
header, everything outside **Need to discuss** is accepted, so the document now asserts as accepted that a
question is open which it has answered, and points below at nothing. Round-1 finding 4.5, unfixed.
**Correction.** "`可判和` is carried by the 判和 control, as [Play controls](#play-controls) states."

### 4.5 "The transport controls stay permanently visible" is in tension with the sheet on iPhone — **should-fix**

> "The transport controls stay permanently visible, since those are watched rather than consulted." — `:525`

In the stacked layout the controls are below the board (`:500`), which is where a sheet's first detent sits.
Either the transport is inside the sheet (contradicting "permanently visible" when the sheet is dismissed, and
"stay visible" when it is not), or the sheet must be constrained to a detent that clears it — which is a
presentation decision the new open item defers.

**Correction.** Add to the open item: "including whether the transport is inside the sheet or the sheet is
constrained to leave it visible."

### 4.6 Help has no entry point on the game screen once the navigation bar is gone — **should-fix**

> "Help is reachable from Settings **and from the game screen** without abandoning or pausing state" — `:417`,
> accepted

With no navigation bar (`:509`) and a three-control cluster that is full in both play modes (`:266`–`:269`),
the game screen has no home for a Help entry point. The change removes the affordance's conventional location
without providing another. **Correction.** Name the entry point, or note in the open item that the sheet
presentation must also carry it.

### 4.7 The accepted replay requirement is served, but only as a claim — **no finding, recorded**

`:380` requires the move list to highlight the current move and allow jumping. A sheet can do both. The
overturned sentence ("replay in the stacked layout shows the move list rather than hiding it, and the
surrounding chrome is what tightens to make room") was accepted text on `main`, and overturning it is inside
the product owner's decision. `:381`'s flip control survives in the replay inventory. `:258`'s read-only
board is unaffected. Consistent.

---

## 5. Document-status discipline

Decided by the product owner: sheets for consulted content; iPad portrait stacked like iPhone; no flip
control in human-versus-AI; the 720 pt cap; the result card replacing the controls; the resign confirmation
copy; behaviour above AX3 need not be designed. Everything else below is the author's.

### 5.1 The removed open items

| removed item | verdict |
|---|---|
| "Define the exact widths at which the layout shape **and the navigation presentation** change, **whether the navigation offers the user a switch** between tab bar and sidebar…, and how the on-demand move list is presented in the stacked layout." | **Not resolved.** Layout: replaced by a rule with an undefined operand (1.3) and an oscillation (1.1). **Navigation: broken, not resolved** — `:519` now cites a deleted rule (4.1). **User switch: deleted unanswered** — round 1's answer ("the user is not offered a choice") was dropped in the rewrite and nothing replaced it. Move list: resolved as a sheet, with its summoning re-opened. **Blocking.** |
| "Fix the minimum window size for macOS and for iPadOS windowing…, and name the narrowest supported iPhone…" | **Mostly resolved.** Two numbers, per platform, with the platform semantics stated. Defects at 3.2–3.7; device not named (3.9). |
| "Resolve how the non-dismissible result card, the retained draw-claim affordance, and accessibility text sizes fit the stacked layout's remaining space…" | **Answered; one answer is wrong.** Card ✓ (with 4.2 outstanding); draw claim ✓ but `:292` dangles (4.4); accessibility answered at AX3 and the answer does not hold at AX3 (3.2). |
| "Define what the side-by-side panel contains **beyond** the turn status, move list, game metadata, and controls, … and what the stacked layout does with the controls that panel would otherwise hold." | **Resolved except "beyond".** `:282` still restates the same four items without saying they are all of them; the stacked homes are now stated (controls below the board, metadata in the sheet) — a real improvement over round 1. **Nit.** |

**Correction for row 1.** Restore an open item: "Define when the navigation container presents as a sidebar
rather than a tab bar now that the layout rule names no width, and whether the user is offered the platform's
switch between them."

### 5.2 The new open item — well-formed, with one overlap — **should-fix**

> "Define the sheet presentation itself — how the move list is summoned and dismissed on each platform,
> whether it is resizable, and what it shows beyond the list."

A question, not a requirement; scoped; non-normative. But `:270` already decides part of it (replay has "the
affordance that summons the move list") and gate G7 tests that decision, so accepted text and a gate sit on
top of an open question. **Correction.** Either drop "how the move list is summoned" from the open item and
state the affordance for both play and replay, or drop the affordance from `:270` and G7.

### 5.3 The remaining author's choices, checked

| author's choice | assessment |
|---|---|
| The shape rule's formulation | Oscillates (1.1); its stated reason is false on 8 of 9 iPads (1.2) and for landscape windows (1.4); depends on an undefined panel minimum (1.3). **Blocking.** |
| 360 × 512 macOS content | Sound at default text (+9 on the binding state); toolbar undeclared (3.7). |
| 360 × 648 iPadOS scene | Sound at default text (+4.5); fails from xxxL (3.2); tiling consequence unstated and outside `product.md` (3.4); rests on unmeasured chrome (3.6). **Blocking.** |
| No navigation bar on the board page | Arithmetic verified (2.2); strands replay (2.3) and Help (4.6). On iPad the removal *costs* 10 pt (measured: 1027 with a bar, 1017 without, because the top tab bar and the bar share a row), so the saving is an iPhone-only fact — which the sentence does say. |
| The board yields above AX3 | Inside the owner's decision, but contradicts `:503`, `:515`, `:129` (3.3) and does not reach far enough down (3.2). **Blocking.** |
| Metadata to the sheet in stacked | Good; closes the round-1 6.1 gap. |
| "375 by 667 points" as the verified iPhone | Correct against the measured device list (narrowest width 375, shortest height 667, same device). Device unnamed (3.9); "width never binds" self-contradicts (3.8). |
| "a disc approaches 80 points" (`:511`) | 0.80 × (720/7) = **82.3**, which exceeds 80 rather than approaching it. Round-1 nit 6.4, unfixed. **Nit** — "a disc of about 82 points". |
| Blank line inside the **Need to discuss** list (`:545`) | Splits the list into two Markdown lists and renders with different spacing. **Nit** — delete it. |

### 5.4 The PR body describes a version that no longer exists — **should-fix**

Every number in it is wrong: "Minimum window: 380 × 500 points of content, on macOS and as an iPadOS scene";
"It currently falls near 700 points"; "the app … is available at the wider multitasking widths but **not the
narrowest**" (the platform behaviour the branch now correctly disclaims); "a 320-point Slide Over scene";
"The narrowest iPhone … is **375 points**"; "**Replay** — transport plus 翻转棋盘"; "**Nine** validation
gates". The body is the merge commit's public record. **Correction.** Rewrite it before merge.

---

## 6. The testing gates

The branch touches **ten** gate lines — nine new, one rewritten. Neither the brief's "eleven" nor the PR
body's "nine" matches; count them before merge.

| gate | verdict |
|---|---|
| **G1** move list "summoned as a sheet … in play and in replay alike, and that it costs the board no height until it is asked for" | Matches `:500`/`:525`. **Not executable in play**: no affordance exists to summon it (2.5). Asserts "as a sheet" on macOS, where the presentation is explicitly open (5.2). **Should-fix.** |
| **G2** "the layout choice is derived from shape: a board sized to the remaining height leaves room for the panel **in landscape** and on Mac windows and does not in portrait, so portrait stacks on both iPhone and iPad **without any width being named**" | **Fails.** A 700 × 550 landscape Mac window does not leave room (1.4). "A board sized to the remaining height" is the ambiguous quantity that oscillates (1.1). iPad portrait stacks by the cap and an unnamed panel width, not by shape (1.2, 1.3). And it contradicts the pre-existing gate P1 below. **Blocking.** |
| **G3** minimums "and that the board, its numeral strips, the turn status and **the control row** all fit within them" | Validated against the cheapest state again — the result card is 60.5 pt taller on iOS, 63 on macOS, and the contract requires it in the same window. The gate passes while the binding case has 4.5 pt (iPadOS) and 9 pt (macOS). Round-1 finding 1.3, softened but not fixed. **Should-fix** — name the tallest required state. |
| **G4** "on a 375 by 667 point iPhone the result card fits with the final board fully visible **at its pitch floor**" | **Fails as written.** Computed, the board sits at **p = 48.6**, not at the floor; a tester verifying "at its pitch floor" verifies a state the layout does not produce. Same defect class as round 1's "unshrunk". **Should-fix** — "at or above its pitch floor". |
| **G5** 720 cap, "**surplus width goes to the panel**", half-cell margin | Untestable in the stacked layout, which is where surplus width now actually occurs (up to 280 pt on iPad portrait) and where there is no panel (1.5). **Should-fix.** |
| **G6** "Verify the layout through the **AX3** accessibility size on the shortest supported iPhone" | **Fails.** At AX3 the SE cannot hold the result card (−38) or the threefold notice (−78) at the floor (3.2). **Blocking.** |
| **G7** play-control inventories | Matches `:268`–`:270`. Omits the accepted autoplay speed control from replay (2.6), and tests an affordance the new open item says is undefined (5.2). **Should-fix.** |
| **G8** 判和 claim state, "with no separate 可判和 element appearing" | Matches `:272`, but the pre-existing gate at `testing.md:87` requires "retained non-blocking **可判和** affordance in both play modes", and `:296`/`:287` keep 可判和 as accepted *metadata* copy. Two gates in one list give opposite instructions. Round-1 finding 4.6, unfixed. **Should-fix** — reword the older gate to name 判和, and scope this one to "no separate 可判和 *control* on the board page". |
| **G9** 认输 confirmation | Matches `:274`–`:280`, `product.md:40`, `game-data.md:51`/`:107`, `core-interface.md:50`. Executable as written. **Good.** |
| **G10** card takes the place of the controls; side-by-side controls "visible but disabled" | Asserts the behaviour that disables Free Play's 翻转棋盘 against `:214` "at any time" (4.2) and duplicates 悔棋 (4.3). **Blocking.** |
| **P1** pre-existing `testing.md:56`: "both the layout shape and the navigation presentation are **selected by available width** …, so a resized macOS window and a windowed iPad reach the same arrangement **at the same width**" | **Now contradicts G2** ("without any width being named") and the new `:496`. Left unamended by a change that invalidates it. **Blocking.** |
| **P2** pre-existing `testing.md:55`: iPad "including the system tiling configurations" | Cannot pass alongside the 648 pt scene minimum on 16 of 18 device-orientations (3.4). **Blocking.** |

---

## Verdict

**DO NOT MERGE**

Blocking findings:

1. **1.1** — "the height that remains after the chrome" is two different quantities; the rule oscillates over
   a 97–127 pt band of window widths (worked: 820 × 550 macOS).
2. **1.2** — "a portrait canvas is width-bound" is false on 8 of the 9 iPad portrait classes; they are
   cap-bound, and the rule has no branch for that case.
3. **1.3** — "enough for the panel" still has no value anywhere; the owner's "iPad portrait stacks" decision
   survives by 16 pt against the smallest defensible panel minimum.
4. **2.3** — "no hierarchy to climb" is false for replay, which is pushed from History; the rule removes the
   only way back and the contract defines no replacement.
5. **2.4** — a sheet over the board violates the accepted `:40` ("No glass surface may intersect the board
   block") and `:33` ("never overlap it"); the change's central mechanism is unreconciled with them.
6. **3.2** — the AX3 commitment does not hold: the SE fails the result card by 38 pt and the notice by 78 at
   AX3, and the declared iPadOS minimum fails the card from xxxL and ordinary play by 6 pt at AX3.
7. **3.3** — the "board may fall below its floor" escape contradicts `:503`, `:515` and the accepted `:129`,
   all left unamended.
8. **3.4** — the 648 pt scene minimum excludes 60 of 108 iPad tiling configurations, and `product.md:27`,
   `interaction-design.md:489` and `testing.md:55` are all left contradicting it; `product.md` is untouched.
9. **4.1** — `:519` and `:492` still cite "the same width-driven rule as the layout shapes", which this
   commit deleted; the sidebar's threshold is now undefined.
10. **4.2** — Free Play's 翻转棋盘 is still lost against `:214` "at any time"; pointing at the recorded card's
    replay does not recover it, and side-by-side still disables it.
11. **5.1** — an open item was deleted with two of its three questions unanswered, one of them (the
    tab-bar/sidebar switch) silently dropped.
12. **6, G2 / G6 / G10 / P1 / P2** — five gates assert what the contract does not guarantee, two of them
    pre-existing gates the change invalidates without amending.

Should-fix: 1.4 (landscape claim false), 1.5 (stacked surplus width), 2.5 (nothing summons the sheet in
play), 2.6 (seven controls; autoplay speed still missing), 3.5 (half the reason for two minimums), 3.6
(4.5 pt of slack on chrome never measured at that width), 3.7 (macOS toolbar undeclared), 3.8 ("width never
binds" contradicts `:498`), 4.3 (two 悔棋 controls), 4.4 (`:292` dangles), 4.5 (transport under the sheet),
4.6 (Help entry point), 5.2 (open item overlaps accepted text and a gate), 5.4 (PR body wholly stale), and
gates G1, G3, G4, G5, G7, G8.

Nits: 3.9 (name the SE), 5.1 row 4 ("beyond" unanswered), 5.3 ("a disc approaches 80" is 82.3), 5.3 (blank
line splits the open-items list), 2.7 (does summoning the sheet pause autoplay).

What is sound and should survive the next revision: the sheet decision itself, which removes all three of the
measured floor failures with 59–111 pt to spare and is verified above; the navigation-bar arithmetic on the
SE (−17.5 → +36.5), which is exactly right; two per-platform minimums with the platform semantics stated, and
the honest replacement for round 1's "unavailable at narrower multitasking widths"; 360 rather than 372 or 380
as the width; the 375 × 667 device figures; the 认输 confirmation and gate G9; and the metadata's new home in
the stacked layout.
