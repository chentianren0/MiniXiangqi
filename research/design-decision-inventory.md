# Mini Xiangqi — Design Decision Inventory

> **Status: workspace-only research artifact. Non-normative.**
>
> This is a deduplicated register of what is genuinely still open before implementation,
> assembled by reading the eight contracts in `MiniXiangqi/docs/`, GitHub issue
> `ppppvz/MiniXiangqi#2` and its full comment thread, the merged PR history (#1–#18 in the app
> repository, #1 in the fork), and the workspace drafts. Nothing here accepts, changes, or
> supersedes any contract. Where this document says an item is "resolved", that means a merged
> PR or recorded evidence already settled it — the *contract text* is still whatever the
> contract says, and closing the stale entry is itself a small editing task.
>
> Compiled 2026-07-27 against app-repo `main` at `f73e41b` (PR #18 merged) and fork `master`
> at `77d602e0` (fork PR #1 merged).

---

## 0. Reading this document

- **Section A** is the live register: every genuinely open decision, one row each, with
  blocking status and dependencies. Traps are called out in **A.2** (believed open, actually
  closed) and **A.3** (believed settled, but no contract says so).
- **Section B** grades the survey's D1–D26 and C1–C8.
- **Section C** proposes discussion sessions and their deliverables.
- **Section D** is the implementation-readiness verdict.

Source codes used throughout:

| Code | Source |
|---|---|
| `PRODUCT` `INTERACT` `RULES` `ARCH` `CORE` `DATA` `ENGINE` `TESTING` | the eight `MiniXiangqi/docs/*.md` contracts |
| `ISSUE2` | GitHub issue `ppppvz/MiniXiangqi#2` — body checklist |
| `ISSUE2c` | issue #2 comment thread (eight comments, last one PR #15) |
| `SURVEY` | `discussion-drafts/apple-ui-design-survey.md` §10 (D1–D26), §11 (C1–C8), §12 |
| `FABLE` | `discussion-drafts/board-visual-language-design.fable-partial.md` (unfinished, ends mid-§2.6) |
| `RECON` | `discussion-drafts/rules-edge-cases-reconciliation.md` |
| `PR#n` | merged app-repo pull request; `FS#1` = `ppppvz/Fairy-Stockfish#1` |

**Blocking** column: `BLOCK` = a named first implementation task cannot responsibly start until
this is decided; `PARALLEL` = can be settled while early implementation proceeds; `DEFER` =
explicitly parked or gated on a later phase (Windows, English build, distribution).

**Headline count: 67 live open questions** — **31 `BLOCK`**, 25 `PARALLEL`, 11 `DEFER`.
Separately, **9 items listed as open are already closed** (A.2) and **10 items are treated as
settled but no contract states them** (A.3).

The `BLOCK` count is high because it is measured per first-task, not per project: 8 of the 31
are the single rules tranche, and 12 more are the four "before any code in this area" clusters
(core, shell, board, wording). Nothing here says 31 decisions must precede the first commit —
D.1 names which task each one actually gates.

---

# A. The live open-question register

## A.1 Register

### Rules adjudication and conformance fixtures

| ID | Question | Owner | Raised by | Blocking | Depends on |
|---|---|---|---|---|---|
| Q01 | What exactly makes a chased piece protected, including X-ray defence, cannon screens, palace-confined kings, pinned defenders, and the flying-general pin that must consider pieces of **both** colours? | `RULES` | `RULES`, `ISSUE2`, `RECON §Q1` | BLOCK | — |
| Q02 | Over what span is a perpetual violation judged, and what interrupts or renews it (including a violation attaching at a fourth or later occurrence)? | `RULES` | `RULES`, `RECON §Q2` | BLOCK | Q01 |
| Q03 | Do we adopt the engine's *renewal* test for discovered and pinned attacks ("attacks from the square it now occupies and did not attack from that square before"), and do we patch the pinned-attacker false loss? | `RULES` | `RULES`, `RECON §Q3`+`§D3`, patch `P1` | BLOCK | Q01, Q02 |
| Q04 | How are mutual and mixed sequences classified — in particular, is 一将一捉 (alternating check and chase) a violation or not? | `RULES` | `RULES`, `RECON §Q4`+`§D4` | BLOCK | Q02 |
| Q05 | Do we patch the chase-window parity defect, which makes the same four moves a violation for one colour and not the other? | `RULES` | `RECON §Q5`+`§D1`, patch `P3` | BLOCK | Q02 |
| Q06 | Target and attacker classes: add the attacker reading of the soldier/king exclusion; record the horse-or-cannon-versus-chariot value rule the source does not literally support; adopt-or-patch the king-as-sole-root recapture test; patch the discovered-check exemption gap. | `RULES` | `RULES`, `RECON §Q6`+`§D5`+`§D6`, patch `P5`, `ISSUE2c` (FS#1 follow-up 1) | BLOCK | Q01 |
| Q07 | How is `mutual-perpetual-chase` reported? The engine's return value cannot distinguish it; options are a read-only fork accessor (`P4`), retiring the reserved reason, or shipping the ambiguity. | `RULES` + `ENGINE` | `RECON §3.4`+`§D2` | BLOCK | Q04 |
| Q08 | Approve the deferred fixture tranche — 36 new fixtures `mx-chs-005…034`, `mx-chk-003…004`, and a new `mx-mix-*` area needing a `fixtures/rules/README.md` addition. | `RULES` | `RULES`, `ISSUE2`, `RECON §5` | BLOCK | Q01–Q07 |

### Engine integration, packaging, and lifecycle

| ID | Question | Owner | Raised by | Blocking | Depends on |
|---|---|---|---|---|---|
| Q09 | The custom variant's final identifier, bundled `variants.ini` filename, network alias strategy, and the focused fork-patch boundary. | `ENGINE` | `ENGINE`, `ISSUE2c` | BLOCK | Q03, Q05, Q06, Q07 (they define the patch set) |
| Q10 | The pinned-manifest format shared between the app and Fairy-Stockfish repositories — and where fork revision `77d602e0` is durably recorded, since today it exists only in an issue comment. | `ENGINE` | `ENGINE`, `ISSUE2c` (FS#1 follow-up 2) | BLOCK | Q09 |
| Q11 | The bundled network's packaging name, load-verification checks, and per-platform fallback policy. | `ENGINE` | `ENGINE`, `ISSUE2` | PARALLEL | Q10 |
| Q12 | User-visible recovery when Hash allocation itself fails despite a calculated budget ≥ 256 MiB. | `ENGINE` + `INTERACT` | `ENGINE`, `ISSUE2` (explicit `- [ ]`) | BLOCK | recoverable-Hash fork change |
| Q13 | Backgrounding, suspension, teardown, and memory-pressure behaviour on each platform. | `ENGINE` | `ENGINE`, `ISSUE2` | PARALLEL | Q12 |
| Q14 | The exact ordering and cleanup contract between pre-start engine preparation, Random resolution, active-game persistence, and the first search. `CORE` assumes prepare → resolve → create → search but explicitly says `ENGINE` owns it and it is open there. | `ENGINE` (per `CORE`) | `ENGINE`, `CORE` | BLOCK | — |
| Q15 | The exact Windows memory-probe API, and verification of the macOS probe's behaviour. | `ENGINE` | `ENGINE`, `ISSUE2c` | PARALLEL (macOS) / DEFER (Windows) | — |

### Shared core, data, and repository structure

| ID | Question | Owner | Raised by | Blocking | Depends on |
|---|---|---|---|---|---|
| Q16 | Whether `mxq_engine_query` exposes additional bounded diagnostics (hash utilisation, NPS) for a future internal diagnostics surface. | `CORE` | `CORE` | PARALLEL | — |
| Q17 | Concrete capacity constants — `MXQ_DETAIL_CAP`, page sizes, legal-move array headroom — to finalise against measured worst cases. | `CORE` | `CORE` | PARALLEL | — |
| Q18 | Where Settings preferences live on each platform: the shared store or each platform's native preference system. **If the shared store, accepted C-interface v1 has no Settings functions** and needs an additive group. | `DATA` (+ `CORE`) | `DATA`, `ISSUE2c` (PR #12 new questions) | BLOCK | — |
| Q19 | The setup-legality predicate for a future archive version that permits initial positions other than the frozen start. | `DATA` | `DATA` | DEFER (v1 restricts `start_fen` to the frozen FEN) | — |
| Q20 | Windows toolchain pinning for the core and frontend, and the CI matrix that builds all platforms. | `ARCH` | `ARCH`, `TESTING`, `ISSUE2c` | DEFER (Windows phase) | — |
| Q21 | Whether core tests standardise on one framework or per-platform runners. | `ARCH` | `ARCH` | BLOCK (first core code) | — |
| Q22 | **Accept the repository restructuring steps.** `ARCH`'s status line says the target layout `core/ apple/ windows/` is recorded but "the repository restructuring steps remain draft until reviewed", and relocating the Xcode project is subject to the protected-settings review in `AGENTS.md`. | `ARCH` | `ARCH` status line (not in any `Need to discuss`) | BLOCK (the agreed next engineering step *is* this restructure) | Q21 |
| Q23 | A static-library build target in the fork — the fork's Makefile does not provide one, and the core cannot link the engine without it. Not tracked in any app-repo document. | fork repo | `ISSUE2c` (FS#1 closing paragraph) | BLOCK | Q09, Q10 |

### Product scope

| ID | Question | Owner | Raised by | Blocking | Depends on |
|---|---|---|---|---|---|
| Q24 | What "fully offline" permits for platform-provided local diagnostics, ordinary OS backup, and other system behaviour. | `PRODUCT` | `PRODUCT`, `ISSUE2` | PARALLEL (affects entitlements / backup exclusion) | — |
| Q25 | Whether the app needs its own interface-language control on any platform. | `PRODUCT` | `PRODUCT`, `ISSUE2` (PR #15 note) | DEFER (English build) | Q57 |
| Q26 | Whether either mode needs a direct non-competitive **End Game** action outside the save-before-mode flow. **Tracked only in `ISSUE2`; no document's `Need to discuss` carries it.** | `PRODUCT` | `ISSUE2` only | BLOCK (Play control inventory) | Q32 |
| Q27 | The exact Windows internal-distribution mechanism, packaging format, and minimum tested Windows configuration. | `PRODUCT` | `PRODUCT`, `ISSUE2c` | DEFER (Windows phase) | Q20 |
| Q28 | Whether to reconsider starting from a historical position after estimating complexity. | `PRODUCT` | `PRODUCT` | DEFER (explicit MVP exclusion) | — |

### Interaction — layout and shell

| ID | Question | Owner | Raised by | Blocking | Depends on |
|---|---|---|---|---|---|
| Q29 | The exact widths at which the layout shape and the navigation presentation change; whether the user may switch between tab bar and sidebar; how the stacked layout surfaces the on-demand move list. | `INTERACT` | `INTERACT`, `ISSUE2`, `SURVEY §3.3.2`, `SURVEY §12.4` | BLOCK (app shell) | — |
| Q30 | Minimum window size for macOS and iPadOS, and the narrowest supported iPhone the stacked layout is verified against. | `INTERACT` | `INTERACT`, `SURVEY §3.3.3`, `SURVEY §12.3` | BLOCK (app shell) | Q29, Q32 |
| Q31 | Whether the board has a **maximum** size and what surplus space does on a very wide or very tall window. Survey proposes a 720 pt cap (`D8`); **no contract mentions a cap and no `Need to discuss` item tracks it.** | `INTERACT` | `SURVEY D8` only | PARALLEL | Q29, Q32 |
| Q32 | What the side-by-side panel contains beyond turn status, move list, metadata and controls; how that metadata relates to Play's own active-game metadata; what the stacked layout does with those controls. This is where the **play control inventory** (悔棋 / 判和 / 认输 / 翻转棋盘) has to be settled. | `INTERACT` | `INTERACT`, `ISSUE2`, `SURVEY §3.3.2` | BLOCK (Play screen) | Q26, Q43 |
| Q33 | How the non-dismissible result card, the retained 可判和 affordance, and accessibility text sizes fit the stacked layout's remaining space. | `INTERACT` | `INTERACT`, `SURVEY D9` | BLOCK (result flow) | Q29, Q30, Q52 |

### Interaction — board visual system

| ID | Question | Owner | Raised by | Blocking | Depends on |
|---|---|---|---|---|---|
| Q34 | Each piece style's concrete values — role colours, disc fills, ring weights, grid stroke, and its own board surface — within the accepted constraints. | `INTERACT` | `INTERACT`, `ISSUE2`, `FABLE §1` | BLOCK (board rendering) | — |
| Q35 | Design the icon set, and decide drawn-for-this-project versus adopting a freely licensed international set. Chariot against cannon is the pair it must earn. | `INTERACT` | `INTERACT`, `PR#17` | PARALLEL (汉字 is the default; 图标 can follow) | Q34 |
| Q36 | Whether file numbers may be hidden, and the visual system for them and for typography. | `INTERACT` | `INTERACT` | PARALLEL | Q34 |
| Q37 | Board themes beyond the three accepted piece styles, if any are wanted. | `INTERACT` | `INTERACT` | DEFER | Q34 |
| Q38 | Exact visual treatment for selection, legal destinations, captures, illegal-square feedback, save-failure feedback, and unavailable input — including the **save-failure copy**, which has no accepted string. | `INTERACT` | `INTERACT`, `ISSUE2`, `SURVEY D11 D12 C6`, `FABLE §2.2 (S1–S12)` | BLOCK (board rendering) | Q34 |
| Q39 | Hover preview of legal destinations on iPad and Mac. Sits directly against the "no AI hints" product exclusion, so it is a scope question, not only a visual one. | `INTERACT` + `PRODUCT` | `SURVEY D16`, `FABLE §2.2 S11` | PARALLEL | Q38 |

### Interaction — notation, status, and user-visible wording

| ID | Question | Owner | Raised by | Blocking | Depends on |
|---|---|---|---|---|---|
| Q40 | How traditional notation renders the cases the contract leaves open, notably three or more same-type pieces sharing a file — reachable because all five soldiers move sideways. | `INTERACT` | `INTERACT`, `PR#17` | BLOCK (move list) | — |
| Q41 | Approve the table of positions and expected move strings that is the notation's test oracle, and decide what an icon-symbol reader is offered for the character-based move list. | `INTERACT` + `TESTING` | `INTERACT`, `TESTING` l.147 | BLOCK (move list + its tests) | Q40, Q35 |
| Q42 | The turn status's exact AI-activity treatment, a persistent check token, transient announcements, VoiceOver behaviour, and its placement inside the side-by-side panel. | `INTERACT` | `INTERACT`, `ISSUE2` (`- [ ]`), `SURVEY D10`, `FABLE §2.2 S6 S8 S9` | BLOCK (status element) | Q32, Q51 |
| Q43 | The **user-visible result and end-reason wording table**, and the resignation confirmation copy and control placement. `DATA` freezes the serialized identifiers; no contract states the displayed strings beyond 红方获胜 / 黑方获胜 / 和棋 and one example metadata line. | `INTERACT` | `SURVEY D23`; gap found in `INTERACT` vs `DATA` | BLOCK (result card, History rows) | Q26 |

### Interaction — secondary surfaces and states

| ID | Question | Owner | Raised by | Blocking | Depends on |
|---|---|---|---|---|---|
| Q44 | The exact History-list layout, date and move-count formatting, and detailed import, duplicate, conflict, success, and recoverable-error flows. | `INTERACT` | `INTERACT`, `ISSUE2` (two `- [ ]`) | PARALLEL | Q43 |
| Q45 | Insufficient-memory notice presentation, repeated-failure behaviour, and accessibility announcement. | `INTERACT` | `INTERACT` | PARALLEL | Q12 |
| Q46 | Help entry points, content organisation, and illustrations, within the accepted read-only rules-reference scope — including the macOS placement question (menu + ⌘⇧/ rather than a toolbar item). | `INTERACT` | `INTERACT`, `ISSUE2`, `SURVEY D20 D21 C5` | PARALLEL | Q54 |
| Q47 | Empty, loading, AI-thinking, error, corrupted-import, and destructive-action states. | `INTERACT` | `INTERACT` | PARALLEL | Q38, Q44 |

### Interaction — motion, sound, haptics

| ID | Question | Owner | Raised by | Blocking | Depends on |
|---|---|---|---|---|---|
| Q48 | Refine first-version motion timings, easing, interruption behaviour, and feedback strength through physical-device testing — including whether manual navigation during autoplay cuts the running animation short. | `INTERACT` | `INTERACT`, `ISSUE2`, `SURVEY C3 §12.2`, `FABLE §3 (unwritten)` | PARALLEL | Q38 |
| Q49 | The sound events, sound design, platform differences, and whether autoplay is silent. | `INTERACT` | `INTERACT`, `ISSUE2`, `SURVEY D13 D26 §12.9` | PARALLEL | — |
| Q50 | The haptic events behind the accepted haptics toggle, and their device scope. The illegal-tap weight is already settled (PR #16); the rest is not. | `INTERACT` | `INTERACT`, `ISSUE2`, `SURVEY D14` | PARALLEL | Q49 |

### Interaction — accessibility and platform adaptation

| ID | Question | Owner | Raised by | Blocking | Depends on |
|---|---|---|---|---|---|
| Q51 | Accessibility acceptance criteria and the board's VoiceOver interaction model — element granularity, custom rotors, reading order under flip. | `INTERACT` | `INTERACT`, `ISSUE2`, `SURVEY D17 D18 §7.3 §12.7` | BLOCK (board rendering — retrofitting a 49-element model is expensive) | Q38 |
| Q52 | How the board relates to Dynamic Type: record the deviation (the board sizes to available area, not to text size) or change it. | `INTERACT` | `SURVEY D19 C7` — **no contract states either position** | BLOCK (layout) | Q29 |
| Q53 | How Liquid Glass behaves with Increase Contrast, Reduce Transparency, and different platform appearances — plus the contract-wording fix so "required" does not read as "maximise". | `INTERACT` | `INTERACT`, `ISSUE2`, `SURVEY C1 §12.6` | PARALLEL | Q34 |
| Q54 | The keyboard-shortcut and menu-bar inventory for macOS and iPad, including ⌘Z = 悔棋 and removing Redo from the Edit menu. **Untracked in every contract**; `INTERACT` only promises "an equivalent keyboard command where supported". | `INTERACT` | `SURVEY D24 §3.3.4` | PARALLEL | Q32 |
| Q55 | Windows navigation presentation, Fluent material usage, Narrator and high-contrast equivalents, and touch behaviour. | `INTERACT` | `INTERACT`, `PRODUCT` | DEFER (Windows phase) | Q29 |
| Q56 | Whether the board mirrors under an RTL interface language. Currently moot (zh-Hans + en) but cheap to record. | `INTERACT` | `SURVEY D25` — untracked | DEFER | — |

### Localization

| ID | Question | Owner | Raised by | Blocking | Depends on |
|---|---|---|---|---|---|
| Q57 | Approve the English counterpart of **every** accepted Chinese string. The accepted copy is Chinese and exact; no English equivalent is approved, so an English build is not yet fully specified. | `INTERACT` | `INTERACT`, `ISSUE2`, `PR#15` | DEFER (blocks the English build only) | Q43, Q45 |
| Q58 | English Xiangqi terminology beyond the accepted piece names, and the localization review process (duplicated verbatim in `TESTING`). | `INTERACT` + `TESTING` | `INTERACT`, `TESTING`, `ISSUE2` | DEFER | Q57 |
| Q59 | Whether the piece-style and piece-symbol names (传统 / 现代 / 高对比, 汉字 / 图标) are user-facing interface strings or internal design names. | `INTERACT` | `INTERACT`, `PR#17` | PARALLEL (Settings screen) | — |

### Validation and release

| ID | Question | Owner | Raised by | Blocking | Depends on |
|---|---|---|---|---|---|
| Q60 | **Accept `TESTING` — or named sections of it — as normative.** Its status line reads "Draft validation proposal. Nothing in this document is normative until its status or an individual section is explicitly marked accepted", so every gate added by PRs #13–#18 is currently non-binding. | `TESTING` | `TESTING` status line (not in any `Need to discuss`) | BLOCK (any validation claim) | Q61 |
| Q61 | Verify and record the exact simulator and macOS build/test commands. | `TESTING` | `TESTING` | BLOCK (first build gate) | — |
| Q62 | Select the supported simulator, physical-device, macOS, and Windows validation matrix. | `TESTING` | `TESTING` | PARALLEL | Q61 |
| Q63 | Define the GitHub Actions workflows, their pinned inputs, and which artifacts they retain. | `TESTING` | `TESTING`, `ARCH`, `ISSUE2c` | PARALLEL | Q10, Q61 |
| Q64 | Performance, memory, energy, and thermal thresholds for each AI profile. | `TESTING` | `TESTING`, `ENGINE`, `ISSUE2` | PARALLEL | Q62 |
| Q65 | Which critical flows require UI automation versus structured manual review. | `TESTING` | `TESTING` | PARALLEL | Q62 |
| Q66 | How the accepted 2-second import validation budget is measured and enforced on each platform. | `TESTING` | `TESTING`, `DATA` | PARALLEL | Q62 |
| Q67 | Which evidence must be retained for an internal distribution candidate. | `TESTING` | `TESTING` | DEFER (first TestFlight build) | Q63 |

---

## A.2 Traps — listed as open, but already resolved

These are the rows that will waste discussion time if not struck first. Each carries the
evidence that closes it.

| # | Where it is still listed open | Actually resolved by | Evidence |
|---|---|---|---|
| **T1** | `ENGINE` `Need to discuss`: "Validate the complete approved fixture set, including `mx-chs-003`, against the fork build that implements soldier chase-target exclusion." | fork PR `FS#1`, merged at `77d602e0` | `ISSUE2c` (7th comment) states verbatim: "This resolves the engine-integration item…". All 16 approved fixtures pass against the patched target variant, 0 failures; the same variant without `promotedSoldiersChaseable` still fails `mx-chs-003`. Independently re-verified in `RECON §0` on a rebuild of `77d602e0`. **The document was never updated.** |
| **T2** | `ISSUE2` ticked item: "Settings scope enumerated in PR #15: … and **Western piece labels**." | `PR#17` | `PR#17` body: "This **supersedes the Western piece labels** accepted in PR #15." `PRODUCT` now lists **piece style** and **piece symbols**; `INTERACT` l.94 records that icons replace the Latin initials. A settled item silently changed content. |
| **T3** | `SURVEY C4` — "Sound and haptics must be optional, but Settings has no place for them." | `PR#15` | `PRODUCT` Settings list now carries "a sound toggle and a separate haptics toggle, the latter offered only where the hardware supports haptics." |
| **T4** | `SURVEY C2` — proposes making a second Undo snap the running animation to its end. | `PR#16`, **decided against the survey** | `INTERACT` Motion: "a new action does not interrupt a running transition… an Undo transition must therefore complete within 250 ms for one ply and 600 ms for a decision cycle." The conflict was resolved by a duration budget, not by interruption. Do not re-open as if undecided. |
| **T5** | `SURVEY D6` — Red = solid disc, Black = outlined disc, as *the* treatment. | `PR#16` | Explicitly rejected as the sole construction ("that reasoning over-counts"); it survives as **高对比**, one of three user-selectable styles. |
| **T6** | `SURVEY D1` (character discs as the only piece treatment) and `SURVEY D5` (Latin `a`–`g`/`1`–`7` user notation) | `PR#17` | Symbols became a separate setting (汉字 default / 图标); user-visible notation became traditional Xiangqi notation, with canonical coordinates retained for archives, fixtures, and the core interface. |
| **T7** | `SURVEY D22` — `zh-Hans` only | `PR#15` | `INTERACT` Localization: "The supported languages are Simplified Chinese and English." This is what *created* Q57. |
| **T8** | `SURVEY D7` — iPad defaults to a top tab bar, sidebar one tap away | `PR#18`, contradicted | `INTERACT`: "Navigation uses one adaptive container, presenting as a tab bar at narrow widths and as a sidebar at wide ones… rather than device identity." iPad landscape is a wide width, so it gets a sidebar. Only "whether the user may switch" survives, inside Q29. |
| **T9** | `ISSUE2` open items "Define navigation presentation on each device class and window size" and "Define the visual system for the board, pieces, coordinates, colors, typography, themes, and exact state treatments" | `PR#16`, `PR#17`, `PR#18` — **partially** | Navigation: the container, the width-driven rule, orientation, and the two layout shapes are accepted; only the numeric breakpoints and the optional switch remain (Q29, Q30). Visual system: geometry, three styles with measurable constraints, symbols, and notation are accepted; values, typography, themes, and state treatments remain (Q34, Q36, Q37, Q38). The issue checklist has not been updated since PR #15 — **PRs #16, #17, and #18 have no comment on issue #2 at all.** |

Also closed without ever appearing on the issue checklist: **captured pieces are not displayed**
(`PR#18`, now in `PRODUCT` and `INTERACT`).

## A.3 Reverse traps — treated as settled, but no contract states it

| # | Believed settled | What the contracts actually say | Consequence |
|---|---|---|---|
| **R1** | The testing gates added by PRs #13–#18 ("New gates for…") | `TESTING` status line: **"Draft validation proposal. Nothing in this document is normative until its status or an individual section is explicitly marked accepted."** No section is marked accepted. | No validation requirement in the project is currently binding. Q60. |
| **R2** | The repository restructure to `core/ apple/ windows/` is the agreed next engineering step | `ARCH` status line: "The repository restructuring steps **remain draft until reviewed**." `ARCH` also routes the Xcode-project move through the protected-settings review in `AGENTS.md`. | The next engineering step is not authorised by an accepted contract. Q22. |
| **R3** | Engine packaging is settled | `ENGINE` status line: "**Packaging mechanics and the memory-pressure lifecycle remain draft.**" | Q09–Q13 are not "polish"; they are the unaccepted half of that contract. |
| **R4** | The fork is pinned | `ENGINE` requires "Engine source revisions, patches, build inputs, variant configuration, networks, and hashes **must be pinned reproducibly**." Fork revision `77d602e0` exists only in an issue comment, and `AGENTS.md` forbids tracking progress in repository documents. | A manifest format must be decided before the pin can live anywhere legitimate. Q10. |
| **R5** | Resignation is fully specified | `PRODUCT` accepts resign; `CORE` defines `mxq_game_resign` with reason `resignation`; `DATA` enforces its cross-field rules. But `INTERACT` never places a resign control and never gives its confirmation copy — the string 认输 appears **nowhere** in `docs/`, while every comparable confirmation has exact accepted Chinese copy. | Q43 + Q32. Not in any `Need to discuss`. |
| **R6** | Result and end-reason wording is settled | `DATA` freezes the serialized vocabulary (`checkmate`, `stalemate`, `perpetual-check`, `perpetual-chase`, `threefold-repetition`, `mutual-*`, `resignation`, `ended-early`). The only accepted *displayed* strings are 红方获胜 / 黑方获胜 / 和棋, "a reason", and one illustrative metadata line containing 将死. | Q43. The result card and every History row need this. |
| **R7** | Settings is implementable | `PRODUCT` enumerates six accepted preferences. `DATA` leaves their location open and notes "Local preferences are not in schema version 1." `CORE` v1 — 53 functions, "accepted interface contract" — contains **no** settings or preferences function. | Choosing "shared store" requires an additive C-API group not in the accepted v1 inventory. Q18. |
| **R8** | Mutual perpetual check and check-over-chase have no 7×7 construction | `RULES` l.102 states exactly that, and `ISSUE2c` (PR #13) repeats it. `RECON §1` **refutes both**, with verified constructions: `3c3/7/2k3C/3n3/4N2/7/3K3 w` (in check at all nine plies) and `3k3/7/1r3N1/7/7/2K4/3C3 w` (checker loses, with a cannon-deleted control). | An accepted contract now contains a factually false claim. Fix it with Q08. |
| **R9** | The piece characters are verified | `INTERACT` verifies font resolution on macOS only and says "The equivalent confirmation on iOS and iPadOS is a required device check." `SURVEY §12.1` flags 俥 / 傌 / 砲 specifically. | A required device check, not an open question — but it gates the piece work and is easy to forget. |
| **R10** | `RECON` is a finished analysis | It contains two unresolved placeholders, `RESULT_PLACEHOLDER` (§6) and `RESULT_D6_PLACEHOLDER` (§D6), for the discovered-check-gap reachability search. `r-p4c.out` shows the search still at 0 hits after ~7 500 sampled positions. | The `P5` patch decision (Q06) rests on an unfinished search. Decide it as "patch anyway, one line" or wait — but know the evidence is incomplete. |

---

# B. The survey's D1–D26 and C1–C8, graded

## B.1 Decisions D1–D26

| # | Subject | Verdict |
|---|---|---|
| D1 | Piece rendering: character discs as text | **Partially superseded** — `PR#17`. Characters are now the *default* of a two-option symbols setting (汉字 / 图标), not the only treatment. "Rendered as text, composed at runtime" survives. |
| D2 | Which piece characters | **Superseded with a correction** — `PR#15`. Accepted: 帅/将, 俥/**车**, 傌/**马**, 炮/砲, 兵/卒. The survey paired a simplified Red general with traditional Black 車/馬; checking the normative source showed Red forms are script-invariant while Black forms follow the script. |
| D3 | Board as intersections, palace diagonals | **Superseded (accepted as proposed)** — `PR#17`, plus the additions the survey did not raise: no river band, no starting-point marks, half-cell margin. |
| D4 | Coordinates always shown, outer margin, following the flip, no Settings toggle | **Partially superseded** — `PR#17` accepts file numbers in the outer margin following the orientation, and adds that **ranks carry no labels**. The "no Settings toggle" half is *re-opened*: `INTERACT` now asks "Decide whether file numbers may be hidden" (Q36). |
| D5 | Latin `a`–`g` / `1`–`7` as the user's notation | **Superseded** — `PR#17`. Traditional Xiangqi notation for board edges and move list; canonical coordinates retained for storage and exchange only. |
| D6 | Red solid disc / Black outlined disc | **Superseded** — `PR#16`. Explicitly rejected as the universal construction; retained as the **高对比** style. |
| D7 | iPad default navigation = top tab bar | **Superseded** — `PR#18`. One adaptive container chosen by width: tab bar narrow, sidebar wide. Only "may the user switch?" survives inside Q29. |
| D8 | Cap the board edge at 720 pt | **Still live** — Q31. No contract mentions any maximum, and no `Need to discuss` item tracks it. |
| D9 | Result-card material and placement | **Still live** — Q33 (fit) and Q53 (material). |
| D10 | Persistent 将军 token in the status element | **Still live** — Q42. `FABLE §2.2 S6` designs it; nothing accepts it. |
| D11 | Unavailable-input feedback = 150 ms status pulse | **Still live** — Q38. `FABLE §2.2 S9` proposes a 140 ms acknowledgment beat instead. |
| D12 | Save-failure copy 无法保存这一步，请重试。 | **Still live** — Q38/Q43. The *behaviour* is accepted (`PR#14`); the string is not. |
| D13 | Six sound events | **Still live** — Q49. |
| D14 | Five haptics, iPhone only | **Partially superseded** — `PR#16` fixed the illegal-tap weight (lightest selection tick, never the warning pattern), overturning the survey's warning haptic. The event list and the iPhone-only scope remain live — Q50. |
| D15 | Settings gains 音效 and 触感反馈 | **Superseded (accepted)** — `PR#15`; now in `PRODUCT`. |
| D16 | Hover preview of legal destinations | **Still live** — Q39. `FABLE §2.2 S11` deliberately does not depend on it. |
| D17 | Four custom VoiceOver rotors | **Still live** — Q51. |
| D18 | VoiceOver reading order follows the flip | **Still live** — Q51. |
| D19 | Board does not scale with Dynamic Type | **Still live** — Q52. The deviation is not recorded anywhere. |
| D20 | Help: one sheet, seven topics, FEN diagrams | **Still live** — Q46. |
| D21 | Help context landing | **Still live** — Q46. |
| D22 | `zh-Hans` only | **Superseded** — `PR#15`: Simplified Chinese **and English**, Chinese as source. |
| D23 | Result wording table (将死 / 困毙 / 长将 / 长捉 / …) | **Still live and under-tracked** — Q43. `DATA` froze the machine identifiers, which makes the display table more urgent, not less. Note 困毙 would be the display term for the fixture reason `stalemate`, which in this ruleset is a **loss**, not a draw. |
| D24 | ⌘Z = 悔棋, Redo removed from the Edit menu | **Still live, untracked** — Q54. |
| D25 | Board never mirrors under RTL | **Still live, untracked, currently moot** — Q56. |
| D26 | Autoplay silent | **Still live** — Q49. |

Summary of D1–D26: **7 superseded or accepted** (D2, D3, D5, D6, D7, D15, D22), **3 partially
superseded** (D1, D4, D14), **16 still live** (D8–D13, D16–D21, D23–D26).

## B.2 Conflicts C1–C8

| # | Subject | Verdict |
|---|---|---|
| C1 | "Liquid Glass is required" invites over-application | **Still live** — Q53. `INTERACT § Platform visual language` is unchanged; the proposed rewording and the exclusion list were never applied. |
| C2 | Board input blocked for an Undo animation | **Resolved, against the survey** — `PR#16` / `INTERACT § Motion`. The hold is deliberate; the mitigation is a 250 ms / 600 ms duration budget. See T4. |
| C3 | Autoplay waits for each animation | **Still live** — Q48. Unchanged in `INTERACT § History replay`. Note that C2's resolution sets a precedent for deciding it the same way. |
| C4 | Sound and haptics optional, but Settings has no place for them | **Resolved** — `PR#15`. See T3. |
| C5 | Help reachable from the game screen vs. macOS toolbar-help guidance | **Still live** — Q46. The proposed reading ("reachable without leaving the game screen", satisfied on macOS by the 帮助 menu) was never recorded. |
| C6 | Silent rejection of unavailable input | **Still live** — Q38/Q42. Two competing proposals now exist: `SURVEY D11` (status pulse) and `FABLE S9` (140 ms acknowledgment beat + lightest tick). |
| C7 | The board ignores Dynamic Type | **Still live** — Q52. Neither the deviation nor its justification appears in any contract. |
| C8 | "Text must not be embedded in visual assets" forecloses a commissioned piece set | **Substantially resolved, wording not applied** — `PR#15` and `PR#17` made piece characters *game content* excluded from localization, and icons "game presentation… they do not change with the interface language". The conflict is dissolved; the survey's specific remedy ("state that pieces are composed at runtime from shapes plus a text glyph") is still unstated, and it matters for Q35 (a commissioned icon set must carry no text). |

Summary: 2 resolved (C2, C4), 1 substantially resolved (C8), 5 still live (C1, C3, C5, C6, C7).

## B.3 Survey §12 — ungrounded items

None of these are decisions; they are verification obligations that gate decisions. Carry them
into the sessions that need them: §12.1 CJK font on iOS/iPadOS → R9 / Q34; §12.2 motion
durations → Q48; §12.3 window minimums → Q30; §12.4 iPadOS breakpoints → Q29; §12.5 SF Symbol
names → Q35/Q54; §12.6 Liquid Glass under Increase Contrast → Q53; §12.7 VoiceOver grid
granularity → Q51; §12.8 Chinese glyph convention → closed by `PR#15`; §12.9 sound design →
Q49.

---

# C. Proposed discussion order

Each session is a set that must be decided together because deciding one member constrains the
others. Sessions are ordered by downstream unblocking.

### Session 1 — Perpetual-check and perpetual-chase adjudication
**Questions:** Q01, Q02, Q03, Q04, Q05, Q06, Q07, Q08.
**Why first:** the fork is about to be patched anyway for recoverable Hash. Every chase-rule
decision here is a fork patch (`P1` pinned-attacker, `P2` flying-general pin, `P3` window
parity, `P4` mutual-chase reporting, `P5` discovered-check mask). Deciding them now makes them
one fork pass instead of two, and the rules facade — the core's first correctness-critical
component — cannot be written before them. `RECON §4` already supplies contract-ready prose for
all six rules and `RECON §5` a validated 36-fixture slate, so this session is mostly ratification
plus six genuinely two-sided calls (`RECON §7 D1–D6`).
**Deliverable:** `xiangqi-rules.md` — rewrite of *Move-count, repetition, perpetual check, and
perpetual chase*, correction of the false non-constructibility claim in *Conformance fixtures*
(R8), and clearing of its whole `Need to discuss`; `fixtures/rules/` — 36 new fixtures;
`fixtures/rules/README.md` — the `mx-mix-*` area; `engine-integration.md` — the fork-patch
boundary, and strike the resolved fixture-validation item (T1).

### Session 2 — Engine packaging, pinning, and lifecycle
**Questions:** Q09, Q10, Q11, Q23, Q12, Q13, Q14, Q15 (macOS half).
**Why second:** Q09's patch boundary is only decidable once Session 1 fixes the patch set. Until
the manifest format (Q10) and the static-library target (Q23) exist, the core cannot legitimately
consume the fork at all, and the fork revision has no lawful home.
**Deliverable:** `engine-integration.md` — *Packaging and NNUE* and the memory-pressure lifecycle
move from draft to accepted; a new pinned-input manifest (format shared with the fork repo);
`core-interface.md` — the pre-start ordering note resolved; a fork-side static-library target.

### Session 3 — Core, data, and repository structure
**Questions:** Q18, Q21, Q22, Q16, Q17, Q19, Q24.
**Why third:** Q22 authorises the agreed next engineering step, and Q21 must be settled before
the first core test is written. Q18 may force an additive C-API group, which is far cheaper
decided before `mxq.h` exists than after.
**Deliverable:** `architecture.md` — *Repository layout and build* moves from draft to accepted,
plus the test-framework choice; `game-data.md` — a Settings-location section (and a key-value
table if core-owned); `core-interface.md` — a settings function group if needed, plus the
capacity constants and the diagnostics decision; `product.md` — the "fully offline" definition.

### Session 4 — Layout, shell, and the Play control inventory
**Questions:** Q29, Q30, Q31, Q32, Q26, Q33, Q52.
**Why fourth:** this is the first UI session and it gates every screen. Q26 (a direct End Game
action) and Q32 (the control inventory) must be decided together — one determines whether the
other's cluster has three controls or four — and Q33 and Q52 both consume the space the shell
leaves over.
**Deliverable:** `interaction-design.md` — *Orientation and layout* gains the numeric
breakpoints, window minimums, board maximum, and panel contents; *Board and game interaction*
gains the control inventory; `product.md` — the End Game scope decision if it adds a capability.

### Session 5 — The board's visual system
**Questions:** Q34, Q38, Q36, Q51, Q35, Q37, Q39.
**Why fifth:** Q34 (style values) and Q38 (marker vocabulary) are one problem — `FABLE §1`
proves it, deriving every marker dimension from the cell pitch and requiring style rings to stay
inside the disc edge while marker rings stay outside it. Q51 belongs here rather than in a later
accessibility session because a 49-element VoiceOver board is a rendering-architecture decision,
not a label pass. `FABLE` is the input document and stops at §2.6, so it needs finishing or
replacing.
**Deliverable:** `interaction-design.md` — concrete values under *Piece styles*, a new board
marker-vocabulary section, the file-number and typography system, and the VoiceOver board model;
`testing.md` — the contrast and legibility measurements that verify them.

### Session 6 — Notation, status, and every user-visible string
**Questions:** Q40, Q41, Q42, Q43.
**Why sixth:** the result card, History rows, and the move list all consume the same wording
table (Q43), and the notation oracle (Q41) is simultaneously a design approval and a test
fixture. Q42 needs Session 4's panel decision and Session 5's marker ink.
**Deliverable:** `interaction-design.md` — the notation rules for the open cases, the approved
oracle table, the turn-status specification, and a complete result/end-reason/resignation copy
table cross-checked against `game-data.md`'s closed vocabulary.

### Session 7 — Secondary surfaces and system states
**Questions:** Q44, Q45, Q46, Q47, Q54, Q59.
**Deliverable:** `interaction-design.md` — History list and import flows, the low-memory notice,
Help structure and entry points (including the macOS placement reading), the state matrix, the
menu-bar and keyboard inventory, and whether style/symbol names are user-facing.

### Session 8 — Motion, sound, and haptics
**Questions:** Q48, Q49, Q50, Q53.
**Why here:** these need physical devices, and Q53 (Liquid Glass under accessibility settings) is
a device-verification question by the survey's own admission (§12.6). Grouping them means one
device session rather than three.
**Deliverable:** `interaction-design.md` — the timing table, the sound-event and haptic-event
lists, and the Liquid Glass behaviour rules plus the "required" rewording.

### Session 9 — Validation contract
**Questions:** Q60, Q61, Q62, Q63, Q64, Q65, Q66, Q67.
**Why not earlier:** the gates accumulate as sessions 1–8 land, so accepting `testing.md` once at
the end costs less than accepting it repeatedly. But Q61 (verified build commands) should be
pulled forward and settled as soon as any code exists.
**Deliverable:** `testing.md` — status changes from *Draft validation proposal* to accepted, with
commands, matrix, CI workflows, thresholds, and retention rules filled in.

### Session 10 — English build and localization
**Questions:** Q57, Q58, Q25.
**Deliverable:** `interaction-design.md` — the approved English copy table and terminology;
`testing.md` — the localization review process; `product.md` — the language-control decision.

### Session 11 — Windows
**Questions:** Q20, Q27, Q55, Q15 (Windows half).
**Deliverable:** `architecture.md`, `product.md`, `interaction-design.md`, `testing.md` — the
Windows toolchain, distribution, frontend conventions, and validation.

### Parked
Q28 (historical position — an explicit MVP exclusion), Q19 (setup-legality predicate — gated on a
future archive version), Q37 (extra board themes), Q56 (RTL).

---

# D. Implementation-readiness verdict

## D.1 Must be decided before the corresponding work starts

The project's agreed next engineering steps are (1) the fork's recoverable-Hash change and a
static-library build target, then (2) the repository restructure toward `core/ apple/ windows/`.
Measured against those:

| Before this task | Decide | Because |
|---|---|---|
| **Any further fork patching** | Session 1 (Q01–Q08) | Five of the six patch candidates (`P1`–`P5`) are rules decisions. Landing recoverable Hash alone means a second fork pass, a second review, and a second revision to pin. Recoverable Hash itself needs no new decision — it is already an accepted requirement in `ENGINE` — so it can proceed in the same branch once the chase patches are chosen. |
| **The static-library target and any core linkage** | Q09, Q10, Q23 | The variant identifier and configuration filename are compiled-in inputs, and `MxqVersion` is contractually required to report the pinned fork revision, variant identifier, and NNUE hash. Without a manifest format there is nowhere legitimate to record `77d602e0`. |
| **The repository restructure** | Q22, Q21 | `architecture.md` marks the restructure steps draft, and the Xcode-project move is a protected-settings change under `AGENTS.md`. The test-framework choice determines what `core/` contains on day one. |
| **First core code (rules facade)** | Session 1 + Q21 | The facade is gated by the fixtures; writing it against 16 fixtures when 36 more are pending is rework. |
| **First core code (store / session)** | Q18, Q14 | Q18 may add a C-API group; Q14 fixes the create/prepare/resolve/search order that `mxq_game_create` and `mxq_engine_*` must implement. |
| **App shell and navigation** | Q29, Q30, Q52 | Breakpoints, window minimums, and the Dynamic Type stance are structural, not cosmetic. |
| **Play screen** | Q32, Q26, Q33 | The control inventory determines the cluster; the End Game question determines whether it has an extra control. |
| **Board view** | Q34, Q38, Q51 | Marker geometry, style values, and the VoiceOver element model are one rendering architecture. |
| **Move list, result card, History rows** | Q40, Q41, Q43 | These need the notation rules, the approved oracle, and the display wording. |
| **Any claim that validation passed** | Q60, Q61 | `testing.md` is wholly non-normative today. |

## D.2 Can be decided in parallel with early implementation

- **Q11, Q13, Q15 (macOS), Q16, Q17** — engine packaging detail and capacity constants; the
  contracts already say these are to be finalised against measurement.
- **Q24, Q59** — small product and naming calls with no structural consequence.
- **Q35, Q36, Q37, Q39** — the 汉字 symbol set is the default and can ship before icons exist;
  file-number visibility, themes, and hover preview are additive.
- **Q44, Q45, Q46, Q47, Q54** — secondary surfaces; the flows behind them are already accepted
  behaviour, only their presentation is open.
- **Q48, Q49, Q50, Q53** — all require physical devices, so they naturally lag the first build.
- **Q62–Q66** — validation breadth, which grows with the code.

## D.3 Deferred by phase

- **English build:** Q57, Q58, Q25. The Chinese build is fully specified; the English one is not.
  Nothing else waits on these.
- **Windows:** Q20, Q27, Q55, Q15 (Windows probe). Apple ships first by accepted contract.
- **First TestFlight candidate:** Q67, plus the GPLv3 notice and corresponding-source
  preparation already required by `ENGINE`.
- **Parked:** Q19, Q28, Q37, Q56.

## D.4 Housekeeping that should happen regardless of any decision

1. Strike the resolved item from `engine-integration.md`'s `Need to discuss` (T1).
2. Correct `xiangqi-rules.md`'s claim that mutual perpetual check and check-over-chase have no
   7×7 construction (R8) — it is now demonstrably false.
3. Update issue #2: it has had no comment since PR #15, so PRs #16, #17, and #18 are unrecorded,
   and the ticked "Western piece labels" entry is superseded (T2, T9).
4. Record the pinned fork revision somewhere that is neither an issue comment nor a progress log
   in a contract (R4) — this is exactly what Q10 exists to enable.
