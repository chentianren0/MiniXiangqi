# Part 8.3 — What it would take to accept `docs/testing.md`

Research note for the main thread. Workspace-only; authors no contract text. Every recommendation below is a
proposal, not an accepted decision.

Scope: item 8.3 of the parts 6–8 survey — determine exactly what must be true for `docs/testing.md` to stop being
draft, and produce the gap list. Read against all eight accepted contracts at `60fc044` (PR #25 merged; PR #23 is
the only open design PR and nothing in it is accepted).

---

## 0. Method — what I executed, what I read, what I reasoned

**Executed or measured in this session**

- Counted every bullet in `testing.md` with a script: **159 bullets total**, of which **131 are
  change-to-validation gates**, 5 are release gates, 9 are toolchain facts, 5 are validation principles, and 9 are
  its own **Need to discuss** items.
- `ls` of the repository root: **`pinned-inputs.json` does not exist.** `testing.md:142` and `:145` gate on it, and
  release gate `:199` depends on it.
- `fixtures/rules/` contains exactly **16 fixture JSON files plus a README** — the approved set named in
  `xiangqi-rules.md:96-109`. I read every fixture's `title` and `rationale` to establish what is and is not pinned.
- `core/`, `apple/`, `windows/` contain only READMEs plus the generated Xcode scaffold (`Item.swift`,
  `ContentView.swift`, two empty test targets). **No core source and no test runner exist.**
- Grepped `testing.md` for terms. Zero occurrences of: `help`, `offline`, `fuzz`, `sanitiz`, `leak`, `crash`,
  `uuid`, `timestamp`, `mxq_`, `one main window`. Three occurrences of `network`, all of them the NNUE file.
  `layer` matches only inside `player`.
- Read all eight contracts in full at their merged state.
- Searched Apple Developer Documentation for the four mechanisms my recommendations rest on (§8).

**Reasoned, not measured:** the classification of all 131 gates in §1–§4, the unguarded-behaviour list in §5, and
every recommendation. The classification is mine and is meant to be disagreed with bullet by bullet; I give the
line number for each so that is possible.

---

## 1. The verdict, stated first

`testing.md` is much closer to acceptable than its blanket draft status suggests. Of the 131 change-to-validation
gates, my classification is:

| Class | Count | Meaning |
|---|---:|---|
| **E — executable as written** | **99** | The expected value is fixed in an accepted contract. A tester could write the assertion today without asking anyone a question. |
| **M — missing input** | **23** | Names a threshold, command, artefact, device matrix, oracle or design decision that does not exist yet. |
| **D — fully subsumed** | **3** | Another gate already asserts everything this one does. |
| **V — no pass condition** | **6** | A review instruction rather than a gate; nothing is missing, there is simply nothing to fail. |

Per section:

| Section | Bullets | E | M | D | V |
|---|---:|---:|---:|---:|---:|
| Shared core (`:45-49`) | 5 | 3 | 1 | 0 | 1 |
| Product and interaction (`:53-83`) | 31 | 26 | 3 | 0 | 2 |
| Rules (`:87-97`) | 11 | 6 | 4 | 0 | 1 |
| Game data (`:101-115`) | 15 | 11 | 4 | 0 | 0 |
| Engine integration (`:119-145`) | 27 | 20 | 5 | 1 | 1 |
| UI, accessibility, sound, haptics (`:149-190`) | 42 | 33 | 6 | 2 | 1 |

**Three findings drive everything below.**

1. **The status line's own precondition does not block most of the document.** It says: *"Add exact commands and
   thresholds only after they have been verified with the required toolchains and representative devices."* That is
   a drafting instruction about commands and thresholds. 99 of the 131 gates contain neither — they state which
   accepted behaviour must be verified, not how fast or on what hardware. Those gates are not blocked by the
   condition the document sets for itself.
2. **Whole-document acceptance is unreachable on any schedule the project controls.** Two of the 23 blocked gates
   depend on artefacts that cannot exist for a release or more: the Windows toolchain (`:45`, `:109`, `:110`) and a
   second shipped database schema (`:108`, which gates *"every released database schema migration"* when exactly one
   schema version exists). Waiting for whole-document acceptance means every gate added by PRs #13–#25 stays
   non-binding through the entire first implementation push. That is the risk issue #2 flags, and it is real.
3. **The largest problem is not the 23 blocked gates. It is roughly fifty accepted behaviours with no gate at all**
   (§5), including several the accepted contracts explicitly delegate to tests. Five of them are cross-cutting and
   have *zero* mentions anywhere in the document: offline operation, the single main window, Help, crash and
   interruption recovery, and any memory-safety or fuzzing discipline over a C++ core that by contract consumes
   untrusted input.

---

## 2. Gates precise enough to execute as written

**Criterion used:** a competent tester, holding only `testing.md` and the eight accepted contracts, can determine
pass or fail without asking a question. Whether the code exists is a separate axis — none of it exists, and that is
expected of a design-first repository.

The 99 are listed by exception in §3 and §4 (everything not named there is E). Some are unusually strong and are
worth naming because they show what the rest of the document should look like:

- **`:125` — the Hash budget boundaries.** *"at and around the 4 GiB cap, 50%-of-physical-memory boundary,
  20%-or-128-MiB reserve boundary, 64 MiB rounding boundary, and 256 MiB minimum."* Every number is fixed at
  `engine-integration.md:105-107`, and `core-interface.md:129` deliberately makes `mxq_engine_plan` a pure function
  of frontend-supplied probe values *"so every budget boundary in testing.md is testable without an engine."* This
  is the only gate in the document whose testability was designed for by another contract.
- **`:178-181` — the board-metric rules.** `0.40 p` decoration bound, `0.42 p` air gap measured against the disc at
  its largest, `1 p` cell containment through every animation, the three named exemptions, marker ink at 4.5:1 and
  3:1 against the style's own surface *and* against the hover fill composited over it with shadows excluded.
  Reviewable against a screenshot with a ruler.
- **`:67`, `:73`, `:83`, `:184` — the four gates that quote their copy exactly.** These can never drift from
  `interaction-design.md` because they carry the strings.
- **`:132-139` — the suspension, cancellation and preparation-ordering gates.** Precise, including the two
  distinctions that were hardest to get right in the contracts: that losing window focus is not a suspension
  (`:132`), and that a result from a suspension-cancelled search is rejected by cancellation rather than by
  staleness because no mutation occurred (`:133`).
- **`:168-172` — the motion gates.** Seven named travel durations, the 600 ms decision-cycle bound, 340 ms flip,
  the 260 ms compose-beat floor and the 500 ms activity threshold, interruption discard-versus-defer, and the
  lead-versus-report feedback rule.

---

## 3. Gates that name a threshold, command, artefact or decision that does not exist

All 23, with the specific blocker and where the blocker is owned. This is the list that must either be satisfied or
be visibly quarantined before any section containing it can be marked accepted.

| Gate | What it needs | Where that is owned | Reachable when? |
|---|---|---|---|
| `:45` core suite "once the Windows toolchain is pinned" | Windows toolchain pin | `testing.md:30`, `:208`; `architecture.md:86` | After the Windows frontend exists |
| `:54` "smallest relevant iPhone layout", an iPad layout, a macOS window size | The device/window matrix; the narrowest supported iPhone | `testing.md:207`; `interaction-design.md:514` | Now, by decision |
| `:58` "each platform's minimum window size" | The minimum window sizes | `interaction-design.md:514` | Now, by decision (part 4, PR #23 rewrite) |
| `:76` "the turn-status matrix" | The matrix does not exist as an artefact; AI-activity treatment and transient announcements are open | `interaction-design.md:523` | After part 7/8 design |
| `:92` mutual same-class draw; check-versus-chase precedence; **king** chase-target exclusion | Fixtures do not exist | `xiangqi-rules.md:111`, `:121` | After the deferred tranche |
| `:93` the three accepted interpretations (alternation, renewal, general-as-sole-defender) | No fixture pins any of the three. `mx-chs-002` pins a *rook*-defended target, not a general | `xiangqi-rules.md:74-76`, `:80` | After the deferred tranche |
| `:94` parity independence incl. mutual chase as a draw | The fixture `engine-integration.md:45` requires with the parity correction | `engine-integration.md:45` | With the fork patch |
| `:95` check outranks chase unconditionally | No fixture | `xiangqi-rules.md:111` | After the deferred tranche |
| `:108` "every released database schema migration" from file-backed fixtures | A second schema version, and migration fixtures | `game-data.md:161-165` | After a second shipped schema |
| `:109` round-trip across Windows | Windows frontend | `product.md:25` | After Windows |
| `:110` byte-identical canonical content "across platforms" (Windows leg) | Windows core build | `architecture.md:79` | After Windows toolchain |
| `:113` "every import limit boundary" incl. the 2 s validation budget | How the budget is measured and enforced per platform | `testing.md:213`; limit itself fixed at `game-data.md:62` | Now, by decision |
| `:126` "each representative device" | The device matrix | `testing.md:207` | Now, by decision |
| `:130` whole-game latency, memory, energy, thermal | **No thresholds exist at all** | `testing.md:210` | Needs devices + decision |
| `:141` memory probes "on real hardware" | Device matrix; and this is *itself* an open question elsewhere | `engine-integration.md:195` | Needs devices |
| `:142` build fails on a hash mismatch in `pinned-inputs.json` | **The manifest file does not exist** | `engine-integration.md:196` | With the first build |
| `:145` complete fixture set against "the pinned fork build named in `pinned-inputs.json`" | The manifest; and see §4.3 | `engine-integration.md:160-170` | With the first build |
| `:149` VoiceOver labels, values, actions, order, end-to-end nonvisual board interaction | **The board's VoiceOver model is undesigned** | `interaction-design.md:532` (survey 8.1) | After 8.1 |
| `:150` "keyboard and pointer behavior where supported" | Keyboard coverage is undefined; exactly one keyboard command is accepted anywhere (Flip Board, `interaction-design.md:218`) | `interaction-design.md:532` (survey 8.2) | After 8.2 |
| `:155` every icon unmistakable, chariot against cannon | **The icon set does not exist** | `interaction-design.md:518` | After the icon work |
| `:167` strips hidden "at accessibility text sizes" and layout still within bounds | The exact Dynamic Type threshold; the minimum window sizes | `interaction-design.md:529`, `:514` | Now, by decision |
| `:189` traditional notation "against an approved table" | **The oracle table does not exist**; the gate says so itself | `interaction-design.md:520` (survey 6.6) | After 6.5 then 6.6 |
| `:190` "unavailable hardware and muted-audio behavior" | Sound events are undesigned; the haptics half duplicates `:164` | `interaction-design.md:530` | After the sound work |

Also blocked, outside the 131: the **Required toolchain** section's Windows subsection (`:30`, self-declared
"unpinned draft state"), and release gate `:199`'s manifest dependency.

**Seven of the 23 are unblocked by a decision the project can take this week** — `:54`, `:58`, `:113`, `:126`,
`:141`, `:167` and (partly) `:130` all wait on the same two things: a device/window matrix and a threshold set.
That is the cheapest lever in this report.

---

## 4. Duplication, conflict, and under-specification

### 4.1 Fully subsumed (3)

- **`:160` ⊂ `:161` + `:188`.** `:160` asserts the piece-style preference persists, applies immediately, and changes
  presentation only. `:161` already asserts persistence for *every* Settings preference; `:188` already asserts
  presentation-only for piece style, piece symbols *and* notation together. `:160` adds nothing.
- **`:151` ⊂ `:171` + `:175` + `:180` + `:181`.** *"Test Increase Contrast, Differentiate Without Color, Reduce
  Motion, and Reduce Transparency"* is a heading over four gates that already state exact conditions. As a gate it
  has no pass condition; as a heading it is fine.
- **`:129` ⊂ `:96`.** *"Compare engine behavior with accepted rules fixtures wherever search consumes terminal
  adjudication"* is a weaker restatement of `:96`, which already requires the same fixtures against both the
  app-visible adjudicator and the engine search configuration and states exactly what must agree.

### 4.2 Overlap clusters — same assertion in two or three sections

Not strictly duplicates (each has some distinct content) but each asserts a shared core two or three times, in
different sections, at different precision. Every one is a place where a later edit will change one copy.

1. **"Retry re-probes; no smaller Hash; no automatic cleanup"** — `:83` (product), `:128` (engine), `:139` (engine).
   `:139`'s trigger is genuinely different (allocation failure at a *valid* budget, per `engine-integration.md:112`),
   but the shared half is stated three times.
2. **"Leaving invalidates the attempt; a late completion cannot commit"** — `:75` (product), `:135` (engine,
   suspension trigger), `:138` (engine, ordering).
3. **"Creation failure creates no game and no persistent change; Random stays unresolved"** — `:74` and `:138`.
4. **History ordering and row metadata** — `:80` (product) and `:107` (game data).
5. **Import duplicate/conflict** — `:80`, `:114`, `:115`.
6. **Per-move save failure** — `:112` (game data, "the accepted brief save-failure feedback") and `:184` (UI, with
   the exact string and the AI-reply exception). `:184` is strictly better.
7. **Frozen game configuration** — `:65` and `:162`; `:162` sits in the UI section but is a product/interaction gate.
8. **Undo durations** — `:159` (*"within their accepted durations"*) and `:168` (*"within 600 ms"*). Between them
   they still fail to name the 250 ms one-ply bound at `interaction-design.md:416` (see U9).

### 4.3 Conflicts and under-specification (5)

**C1 — Two different bars for the same suite.** `:45` requires core changes to run the core suite *"on at least one
Apple platform"*; `:46` requires the one shared runner to execute the approved fixtures *"identically on every
development platform."* `architecture.md:78` sets the second bar and gives the reason: *"two harnesses would make a
discrepancy between them possible."* The two gates are reconcilable as per-change versus periodic, but the document
never says which applies when, so a change can land under `:45` having never been run under `:46`.

**C2 — No gate names the engine variant the fixtures run under.** `:87`, `:96`, `:129` and `:145` all require the
approved fixtures to pass, and none says whether the run uses `minixiangqiaxf` or built-in `minixiangqi`.
`engine-integration.md:128` states that built-in `minixiangqi` **provably fails** `mx-chs-001` and `mx-chs-004`, and
`:143` requires both variants to be selectable in the same build precisely so the harness can run a variant and its
control side by side. As written, a fixture run is not reproducible from the gate text, and the accepted-baseline
limitation could be reported as a regression or a regression as the baseline limitation.

**C3 — A gate whose precondition is an unapproved contract change.** `:92`–`:95` require verifying outcomes whose
fixtures `xiangqi-rules.md:111` places in the deferred tranche, and `xiangqi-rules.md:121` asks for that tranche to
be approved *"before the rules facade's chase adjudication is relied on beyond the first approved set."* So four
gates in the Rules section cannot pass until a rules-contract change lands. They are not wrong — they are correctly
sequenced after work that has not happened — but they are not gates yet.

**C4 — A gate that is an open question in another contract.** `:141` (*"Verify each platform's memory probe against
the accepted budget boundaries on real hardware"*) is a near-verbatim restatement of
`engine-integration.md:195`, which files it under **Need to discuss** with the note *"the APIs are fixed above,
their measured behavior is not."* One line is normative-in-draft, the other explicitly non-normative. They should
not both exist.

**C5 — CI timing.** `:31` recommends GitHub Actions *"for long or multi-platform builds and test runs"* without
qualification. `architecture.md:79` accepted something narrower and time-bound: developer machines while the project
is Apple-only, CI covering a macOS *and* a Windows runner once Windows implementation begins, because *"CI setup
would otherwise block the first work."* `testing.md` omits the accepted timing.

**Inherited ambiguity, low severity.** `:171` asserts in one sentence both that Reduce Motion leaves *"stroke ...
animations ... intact"* and that *"the check pulse is removed."* The check pulse is a stroke-weight animation
(`interaction-design.md:248`). The gate is self-consistent because it names the exception, but it inherits an
ambiguity that `interaction-design.md:428` also carries; a reader who quotes only half of either sentence gets the
opposite answer.

---

## 5. Accepted behaviour with no gate — the complete list

This is the category that matters most: **an accepted rule with no gate is what silently regresses.** Roughly fifty
items, grouped by owning document. Each gives the accepted rule, why it is a regression surface, and a one-line
proposed gate.

### 5.1 Top ten by regression risk

If only ten gates are added, these are the ten. Reasons: each is accepted in a contract, each is cheap to check,
and each fails silently and expensively.

1. **U1 — offline operation.** 2. **U5 — sanitizers and import fuzzing.** 3. **U4 — crash and interruption
recovery.** 4. **U6 — the move-input happy path.** 5. **U31 — the two invariants `game-data.md` explicitly assigns
to tests.** 6. **U23 — fixture immutability.** 7. **U47 — no NNUE bytes in version control.** 8. **U3 — Help.**
9. **U37 — C API compatibility within a major version.** 10. **U34 — SQLite build and connection settings.**

### 5.2 Cross-cutting — asserted in two or more contracts, gated in none

**U1. Offline operation and the absence of networking.** `product.md:15` (*"fully offline and must not require an
Internet connection"*), `architecture.md:13`, `game-data.md:136` (*"Importing must not contact a server"*),
`game-data.md:169` (no cloud sync, remote storage, or network backup). `testing.md` mentions networking zero times.
This is a defining product property with no gate at all. → *Gate: run the full suite with networking unavailable;
assert no outbound connection during a session covering launch, play, import and export.*

**U2. One main window.** `product.md:26`, `architecture.md:14`, `interaction-design.md:507`. Zero mentions. On
macOS this is a live regression surface (⌘N, File ▸ New, state restoration). → *Gate: on macOS the app offers no
new-window command and restores exactly one main window.*

**U3. Help — the entire surface.** `product.md:12`, `:41`; `interaction-design.md:391-398`. Zero mentions of "help"
in `testing.md`. Three of these are precise and executable today: Help is **reachable from Settings and from the
game screen**, opening it **never modifies the active game**, and returning **restores the exact prior context**.
A fourth is a content mandate: `interaction-design.md:123`, *"There is no river … Help calls it out."* Section
structure and illustrations are open (survey 7.6), but the three behavioural rules are not. → *Gate: both entry
points reachable; the active game's position, revision and status are byte-identical across an open-and-return; the
no-river statement is present.*

**U4. Crash and interruption recovery.** `core-interface.md:238`: *"Termination mid-transaction recovers to the last
committed state through the store's journal."* `game-data.md:70`: *"No accepted-but-unsaved change ever exists."*
Release gate `:198` forbids any *"unresolved data-loss … failure."* `testing.md:103` only reopens a cleanly closed
store. Zero mentions of crash, kill, or interruption. → *Gate: kill the process during a commit at each durable
transition and assert exact recovery to the pre-mutation committed state.*

**U5. Memory safety, leaks, and fuzzing over untrusted input.** `game-data.md:127`: *"Imported files are untrusted
input."* The import surface is a hand-written parser in C++ with explicit structural limits (`game-data.md:62`), and
`core-interface.md:12` defines a pointer lifetime the caller must respect. `testing.md` contains zero occurrences of
sanitizer, fuzz, or leak. This is the single largest control gap for a C++ core. Apple documents the mechanism
(§8.2). → *Gate: a test-plan configuration with ASan + UBSan + TSan + Main Thread Checker; a corpus-based fuzz run
over `mxq_archive_probe`/`validate` with the accepted limits as the only bound.*

### 5.3 `interaction-design.md`

**U6. The move-input happy path.** `interaction-design.md:222-226`, `:231`: tap-to-move and drag-to-move commit
through the same boundary; tapping a movable piece selects and reveals all legal destinations; tapping a legal
destination commits immediately with no confirmation; tapping another movable piece switches selection directly;
tapping the selected piece or outside cancels; dragging beyond the gesture threshold selects; dropping on a legal
destination commits; dropping elsewhere returns to origin. **`testing.md` gates only the failure paths** (`:182`,
`:183`) and the marker envelope (`:178`). The app's most-used interaction has no gate.

**U7. The marker geometry table.** `interaction-design.md:244-253` fixes: selection ring stroke `0.030 p` at
centre-line radius `0.440 p`; destination dot Ø `0.22 p`; capture ring stroke `0.055 p`, outer edge at `0.50 p`,
twelve 18° dashes with 12° gaps, butt caps; last-move brackets arm `0.13 p`, stroke `0.045 p`, inset `0.05 p`; check
rings `0.025 p` at `0.4325 p` and `0.4875 p`; drag origin ring Ø `0.22 p` stroke `0.045 p`; drag lift ×1.10 with a
`0.5 p` touch offset; strengthen at `0.45 p`, release at `0.55 p`; dot grows to `0.33 p`; capture ring thickens to
`0.07 p`; hover fill `0.90 p` square, `0.12 p` radius; focus ring `0.92 p` square, stroke `0.04 p`, `0.14 p` radius,
band `0.44 p`–`0.48 p`. `testing.md:178-181` gates the *envelope* and the contrast, not one of these values. A
refactor moving the dot from `0.22 p` to `0.28 p` passes every gate in the document.

**U8. Layering order.** `interaction-design.md:260` enumerates nine layers and states the reason for one of them:
*"Rings are drawn above resting discs so that no disc can clip one."* No gate. `testing.md:176`'s "edge discs are
never clipped" is about the half-cell margin, not about z-order.

**U9. Three accepted durations and one bound.** Ungated: the selection lift 120–160 ms (`:408`), the capture removal
≈250 ms (`:412`), the Reduce Motion crossfade ceiling of 120 ms (`:428`), and the **one-ply Undo bound of 250 ms**
(`:416`). `testing.md:168` names travel, the 600 ms cycle and the flip; `:159` says only *"their accepted
durations."*

**U10. Replay in the stacked layout shows the move list.** `interaction-design.md:494` makes replay the exception to
the on-demand rule and says the chrome tightens to make room. `testing.md:61` gates the ordinary-play rule only.

**U11. The Play destination.** `interaction-design.md:296`: the Play destination shows the active game's metadata
and a direct **Resume Game** action, identifying at least mode, human side, move count, side to move or result and
reason, and claim availability. `testing.md` gates the *save-and-continue confirmation's* metadata (`:66-68`) and
the store-level resume (`:103`), never this surface. `core-interface.md:185` provides `mxq_store_active_summary`
specifically for it.

**U12. Piece characters as game content.** `interaction-design.md:71`: identical in every supported language, never
translated on the board. `testing.md:163` gates that the app follows the OS language; nothing gates that the board
does not change when it does. Related: the exact accepted codepoints 帅将俥车傌马炮砲兵卒 have no gate, and
`interaction-design.md:70` records that the normative source's own summary table gives 包 rather than 砲 — a
documented, live substitution risk that one assertion would close.

**U13.** Board input under unavailability is rejected *"before visually moving a piece"* (`:234`). `testing.md:185`
gates the no-dimming rule and the replay no-op, not this.

**U14.** The result card's post-confirmation state **已记录到历史** (`:343`) is not named in `:77`; the threefold
notice's exact string **局面已三次重复，可以和棋结束。** (`:350`) is not quoted in `:78`, where four comparable
gates do quote their strings.

**U15.** *"Destructive actions use the system's destructive role rather than a red tint, so red keeps one meaning"*
(`:44`). Ungated; `:174` covers tint during play only.

**U16.** *"Resting shadows are reduced under Increase Contrast"* (`:86`). `testing.md:156` measures with shadows
**removed**, which is a different assertion.

**U17.** A pre-start preview *"shows no game-state markers"* (`:129`). `:59` and `:65` gate the shrink and the
noninteractivity, not this.

**U18.** The marker-coexistence closure at `:262` — that a capture ring never surrounds a checked general, that
last-move brackets never fall on a checked general's cell, that a destination dot and brackets never touch. These
are *derived* claims about reachable positions, and if any is false the marker vocabulary breaks. They are exactly
what a fixture-driven sweep can falsify cheaply.

**U19. Keyboard.** One accepted command exists anywhere in the contracts: Flip Board (`:218`). The focus ring's
geometry is fixed (`:253`). `testing.md:150` is a single unspecified bullet. (Survey 8.2 owns closing the coverage
question; the point here is that even the accepted fragments are ungated.)

**U20.** On **取消** in the insufficient-memory notice, *"the in-memory draft remains while the user stays on that
page"* (`:286`). `testing.md:83` gates only that no game is created or changed.

### 5.4 `xiangqi-rules.md`

**U21. Position identity ignores the counters.** `:38`: two position records denote the same position exactly when
piece placement and side to move are equal. `:37`: the halfmove field drives no rule and *a soldier move does not
reset it.* Repetition detection is built on this. No gate anywhere asserts that a differing halfmove or fullmove
field does not defeat repetition.

**U22. `rules_version` discipline.** `:84` fixes exactly when the version increments and — more testably — when it
must **not** (prose clarification, fixture additions pinning existing behaviour, engine or fork revisions, search
configuration). `testing.md:97` requires a minimized failing fixture before changing an interpretation but never
mentions the version. Archives carry it (`game-data.md:38`), so a missed increment is a permanent misattribution.

**U23. Fixture immutability.** `xiangqi-rules.md:92` and `fixtures/rules/README.md`: *"An accepted fixture's `id`,
position, moves, and assertions are immutable in meaning; a corrected interpretation is a new fixture … not a silent
edit."* This is the project's independent authority, and nothing checks that it has not been edited to match an
engine. A recorded hash per fixture file is a five-line gate.

**U24. King exclusion has no fixture.** `:66` excludes kings **and** soldiers as chase targets; only the soldier
case is pinned (`mx-chs-003`). `engine-integration.md:43` completes the exemption in the discovered-check classifier
path and states plainly that the change *"carries no fixture"* after a 29,500-sample, 11.2-million-cycle search
found no position where the gap changes an outcome. That is an honest reason for no fixture — but `testing.md:92`
gates on king exclusion regardless.

### 5.5 `game-data.md`

**U25.** Timestamps are *"RFC 3339 UTC instants in the exact fixed-width form `YYYY-MM-DDTHH:MM:SS.sssZ`"* (`:38`).
Zero occurrences of "timestamp" in `testing.md`. The format participates in the canonical bytes, so a drift changes
every content hash.

**U26.** `game_id` is *"a version 7 UUID in canonical lowercase text, generated by the core at game creation, frozen
forever, never regenerated on import or export"* (`:56`). Zero occurrences of "uuid". UUIDv7 specifically is a
substitutable detail that nothing would catch.

**U27.** File identity: `.mxq`, UTI `com.ppppvz.minixiangqi.game` conforming to `public.json`, MIME
`application/vnd.minixiangqi.game+json` (`:35`); and *"the in-band type check is the `archive_format` member, exactly
`minixiangqi-game`; the extension and UTI are hints only"* (`:36`). Ungated in both directions: a correctly-named
file with the wrong `archive_format` must be rejected, and a wrongly-named file with the right content must not be.

**U28.** *"No engine, fork, or NNUE identifier is serialized"* (`:40`) — an accepted negative, in tension with how
prominent the engine profile is at `core-interface.md:39`, and therefore a plausible future addition. Ungated.

**U29.** `origin` is *"never hashed, never compared, never trusted, and never used to set the local imported
marker"* (`:41`), and `:52`: *"re-importing one's own exported file after deleting the original yields a record
marked `imported`."* `testing.md:110` covers the hashing half implicitly; the provenance rule is ungated.

**U30. Validation order.** `game-data.md:64` fixes an ordered pipeline and states *"nothing touches the database
until the final stage."* `testing.md:113` requires each rejection **class** and `:115` requires no partial
persistence; nothing requires the reported class to be the **earliest** failing stage. A file that is both oversized
and malformed must fail as oversized, or the created-by-a-newer-version message can be pre-empted by a syntax
complaint — the exact confusion `game-data.md:64` mandates against.

**U31. The two invariants the data contract explicitly assigns to tests.** `game-data.md:144` names three things
*"SQL cannot express"* and calls them *"core logic gated by tests"*: legality of the move line, **derived-column
agreement**, and **ended-early never recording a naturally terminal position**. `testing.md` gates the first for
imports only. The other two have no gate anywhere. This is the clearest instance in the set: an accepted contract
names tests as the enforcement mechanism, and the test contract does not carry them.

**U32.** *"Live local play is not length-limited, and a locally produced game exceeding the import bounds remains
fully playable and replayable — only re-import of its export would be refused"* (`:62`). Ungated, and the obvious
implementation mistake — applying the 10 000-ply import limit to the store — would pass every existing gate.

**U33.** *"A store written by a newer build is refused rather than opened"* (`:161`); `core-interface.md:198`
reserves a store-domain code for it. `testing.md:108` covers forward migration only.

**U34. SQLite build and connection settings** (`:146`): vendored, pinned, floor 3.37.0 for `STRICT`, *"compiled with
the hardened option set and without extension loading"*, connections running *"write-ahead logging with full
synchronous durability and foreign keys on"*, one process, one connection, one serialized writer. Only the hash is
gated, and only once the manifest exists. Durability and hardening settings are precisely the kind of thing a
build-system change silently drops.

**U35.** The **History-added time** versus the game's own date (`:120-121`) — the list sorts by one and displays at
least the other. Ungated, and it is the same distinction the survey flags as an owner question in 7.1.

### 5.6 `core-interface.md` — gated by exactly one bullet (`:49`) plus `:119`

`testing.md:49` delegates the whole 252-line accepted interface contract to *"the threading and error contract in
`docs/core-interface.md`"* with no enumerated conditions. What that leaves ungated:

**U36. Struct and enum discipline** (`:10-11`): three opaque handle types; every value struct beginning with
`uint32_t struct_size`; append-only growth behind that guard; explicit `int32_t` enums; `uint8_t` booleans;
fixed-capacity strings (`MxqMove.text[8]`, FEN capacity 96) so *"every struct is trivially copyable, blittable in C#,
and `Sendable` in Swift."* Blittability and `Sendable` are compile-time checkable and regress the moment someone
adds a pointer field.

**U37. API compatibility within a major version** (`:242`): *"no removals, renames, signature changes, enum
renumbering, struct-field changes, or thread-rule tightening."* A header diff against the previous accepted `mxq.h`
is the standard gate; there is none.

**U38. The rejection ladder** (`:130`): *"cancelled → stale → malformed → illegal"*, **in order**, plus the
deliberate double enforcement of staleness on both the core and frontend sides *"because neither check alone covers
both race directions."* `testing.md:119` names stale rejection alone; `:133` covers one of the two directions.

**U39. The typed refusals.** Six accepted error behaviours, none named in any gate: a second `mxq_core_init` returns
`ALREADY_INITIALIZED` (`:41`); mutations after a terminal commit return `SESSION_ARCHIVED` and the caller still
releases the handle (`:50`); a detected session race returns `CONCURRENT_USE` *"rather than silently serializing"*
(`:235`); anything but the status/blob helpers inside a search callback returns `REENTRANT` (`:236`); engine
reconfiguration returns `SEARCH_IN_PROGRESS` *"rather than stalling"* (`:237`); handles after shutdown return
`INVALID_HANDLE` *"instead of touching freed memory"* (`:238`).

**U40.** Frontends *"must tolerate unknown codes within a known domain (`default:` arm required)"* (`:191`) — a
precisely testable frontend requirement with no gate.

**U41.** *"Programming errors … assert in debug builds, return their code in release builds, and never change
state"* (`:208`). This makes debug and release behaviourally different by contract, and `testing.md` never says
which configuration its tests run in. `:197` requires builds for every configuration; nothing requires **tests** in
more than one.

**U42.** *"`MxqError` detail strings are short English diagnostics, never localized copy, never private game
data"* (`:209`), matching `architecture.md:60`. Privacy-relevant, ungated.

**U43. Test reports must be able to name the build.** `core-interface.md:39`: the engine-profile fields are
*"load-bearing, not diagnostics: conformance depends on a fork build, so every test report and saved diagnostic must
be able to name the build that produced it."* `engine-integration.md:110` repeats it. **`testing.md` imposes no such
requirement on its own reports** — `:38` asks for *"exact commands, environment, results"* without naming the engine
profile. Another contract places a requirement directly on this document's artefacts and this document does not
carry it.

### 5.7 `architecture.md`

**U44. The frontend boundary.** `:38`: *"Frontends must not reimplement rules, result classification, archive
parsing, or library invariants, and must not reach around the core to its storage or the engine."*
`core-interface.md:184`: *"frontends never re-sort."* No gate. This regresses invisibly — a frontend caching legal
moves or re-sorting a History page looks correct until the core changes.

**U45.** *"The core depends on Fairy-Stockfish and SQLite as internal, replaceable components; neither is visible
through the C interface"* (`:45`). A symbol/header check would gate it; there is none.

**U46.** *"Callbacks never mutate frontend state directly"* (`:52`), and the frontend re-enters its main actor
first. Ungated.

### 5.8 `engine-integration.md`

**U47. The repository never contains NNUE bytes.** `:146`: *"The network file is not committed to version control in
any form; it enters builds from a workspace- or CI-provided location."* This is mechanically checkable, genuinely
regressible (one `git add`), and licence-relevant given `:150`'s note that provenance and redistribution licence are
unestablished. No gate.

**U48.** The two Apple entitlements are enabled on the shared target (`:187`). `testing.md:126` tests operation
*without* the increased limit; nothing asserts the entitlements are actually declared in the shipped build.

**U49.** *"`UCI_Elo` … must not be displayed as Mini Xiangqi Elo"* (`:116`) — an accepted absence, ungated.

### 5.9 `product.md`

**U50.** *"Resign is available only in human-versus-AI games"* (`:40`); `core-interface.md:50` makes it *"legal only
in human-versus-AI play"* with a `resign_available` flag. Nothing gates that Free Play offers no resign. Paired with
`interaction-design.md:331` — *"If the AI moved first, its opening move alone cannot be undone"* — also ungated, and
`testing.md:104-105` covers every other undo rule.

---

## 6. What must be true for the status line to change

### 6.1 For whole-document acceptance

All fifteen of these, simultaneously:

1. Windows toolchain pinned and its build/test commands verified (`:30`, `:45`, `:109`, `:110`, `:208`) — **needs
   the Windows frontend to exist.**
2. `pinned-inputs.json` created and consumed by a real build (`:142`, `:145`, `:199`).
3. The deferred rules-fixture tranche approved (`:92`–`:95`).
4. The simulator/device/window matrix selected (`:54`, `:58`, `:126`, `:141`, `:207`).
5. Performance, memory, energy and thermal thresholds defined per AI profile (`:130`, `:210`).
6. The board's VoiceOver interaction model designed (`:149`; survey 8.1).
7. Keyboard coverage defined (`:150`; survey 8.2).
8. The icon set designed (`:155`).
9. The notation oracle table approved (`:189`; survey 6.5 then 6.6).
10. Sound events designed (`:190`).
11. The Dynamic Type hide threshold and the minimum window sizes fixed (`:58`, `:167`).
12. The turn-status matrix written down (`:76`).
13. The import time-budget measurement method defined (`:113`, `:213`).
14. The localization review process defined (`:211`; dual-owned with `interaction-design.md:534` — brief one
    researcher only).
15. Migration fixtures from released schemas (`:108`) — **needs a second shipped schema version.**

Items 1 and 15 are not reachable before artefacts that are a release or more away. **Whole-document acceptance is
therefore not achievable on any schedule the project controls**, and holding the status line until then keeps every
gate added by PRs #13–#25 non-binding through the entire first implementation push.

### 6.2 For section-level acceptance — the recommendation

The document already permits this: *"Nothing in this document is normative until its status **or an individual
section** is explicitly marked accepted."* And the acceptance bar it sets — verify commands and thresholds first —
binds only the gates that contain commands or thresholds, which is 23 of 131.

**Recommended shape.** Within each of the six change-to-validation sections, split the bullets into the accepted
gates and a clearly-labelled **Pending** subsection holding that section's M-class gates, then mark the section
header accepted. Concretely:

| Section | Accept now | Move to that section's *Pending* subsection |
|---|---:|---|
| Validation principles | all 5 | — |
| Shared core | 3 | `:45` (split the Windows clause out), `:49` (expand — see below) |
| Product and interaction | 26 | `:54`, `:58`, `:76` |
| Rules | 6 | `:92`, `:93`, `:94`, `:95` |
| Game data | 11 | `:108`, `:109`, `:113`, `:110`'s Windows leg |
| Engine integration | 20 | `:126`, `:130`, `:141`, `:142`, `:145` |
| UI, accessibility, sound, haptics | 33 | `:149`, `:150`, `:155`, `:167`, `:189`, `:190` |
| Required toolchain | Apple subsection | Windows subsection (already self-declared draft) |
| Build and internal-distribution gates | 4 | the `pinned-inputs.json` clause of `:199` |

This makes **99 gates binding immediately** and leaves 23 visibly non-binding with a named blocker each, which is a
far more honest state than one blanket draft banner over the whole document.

**Four editorial fixes should land with it**, because each is a defect rather than a deferral:

- Delete `:160`, `:151` and `:129` (fully subsumed, §4.1).
- Resolve C1 by saying which bar applies per change and which applies periodically.
- Resolve C2 by naming the engine variant every fixture gate runs under.
- Delete `:141` or `engine-integration.md:195` — one of the two, not both (C4).

**Then add the missing gates**, in the order of §5.1. Adding them is not a precondition for accepting the sections;
it is what makes the accepted sections worth having.

---

## 7. Two structural observations worth recording

**7.1 The document gates behaviour, and almost never gates artefacts.** Every one of U22, U23, U27, U34, U36, U37,
U45, U47 is a repository- or build-level property that a five-line check would hold forever: a hash over the fixture
files, a header diff, a symbol scan, a grep for `.nnue` in the tree, a check of the SQLite compile flags. None
exists. For a project whose independent authority is a directory of JSON files and whose reproducibility rests on a
manifest, artefact-level gates are cheaper and more durable than most of the behavioural ones already written.

**7.2 The Product-and-interaction section has 31 gates and no stated method.** `:212` (*"Define which critical flows
require UI automation versus structured manual review"*) is filed under **Need to discuss**, so the section's 26
executable gates say what to verify and never how. That is survivable — accept them as behavioural requirements now
and let `:212` decide the mechanism later — but it should be stated in the section rather than left implicit, or
every one of those 31 will be read as manual review by default.

---

## 8. Apple documentation, checked and reported honestly

**8.1 Automated accessibility auditing exists and is a real gate.** *Accessibility ▸ Performing accessibility audits
for your app ▸ "Add audits to your UI tests"* documents `performAccessibilityAudit(for:_:)` on `XCUIApplication`,
which *"audits the current screen for accessibility issues the same way that running an audit in Accessibility
Inspector does"* and *"If the UI test finds any audit issues, it automatically fails."* `XCUIAccessibilityAuditType`
publishes the audit types: `action`, `contrast`, `dynamicType`, `elementDetection`, `hitRegion`, `parentChild`,
`sufficientElementDescription`, `textClipped`, `trait`, `all`. Four of those map directly onto accepted criteria —
`contrast` onto the project's contrast numbers, `dynamicType` and `textClipped` onto the numeral-strip and layout
rules, `hitRegion` onto the 44 pt floor. **But the same page states the limit plainly:** eliminating all audit
issues *"doesn't guarantee a fully accessible app"* and *"Always test your app with various assistive apps, such as
VoiceOver."* So the audit is a floor for `:149`/`:151`, never the pass condition — which matches the survey's
finding in 8.1 that the VoiceOver model is ours to design.

**8.2 Sanitizers are configured through test plans, which is exactly the mechanism U5 needs.** *Xcode ▸ Diagnosing
memory, thread, and crash issues early* documents Address Sanitizer, Thread Sanitizer, Main Thread Checker and
Undefined Behavior Sanitizer, and states that *"The `Address Sanitizer`, `Thread Sanitizer`, `Undefined Behavior
Sanitizer`, and `Main Thread Checker` values of a test plan configuration enable these sanitizers during test
runs."* It also notes UBSan *"supports only C-based languages"* — which is fine, because the code that consumes
untrusted input is the C++ core.

**8.3 Performance measurement must be a separate configuration.** *Xcode ▸ Writing and running performance tests ▸
"Configure your scheme and test plan for accurate performance measurements"* says to build for testing using the
**Release** configuration with *"Debug executable"* off, and to *"disable code coverage and the runtime sanitization
options."* This is decisive for two of our gates: `:130`'s measurements and `:168-169`'s durations cannot share a
configuration with the sanitizer run of U5, and `core-interface.md:208`'s assert-in-debug behaviour means U41's
debug-versus-release question has to be answered explicitly rather than inherited.

**8.4 Apple publishes no energy or thermal metric for automated tests.** The complete XCTest metric set
(*XCTest ▸ Performance Tests ▸ Measurement Metrics*) is `XCTClockMetric`, `XCTCPUMetric`, `XCTMemoryMetric`,
`XCTStorageMetric`, `XCTHitchMetric`, `XCTOSSignpostMetric`, `XCTApplicationLaunchMetric`. **There is no energy
metric and no thermal metric.** Thermal state is observable only at runtime through
`ProcessInfo.thermalState` and `thermalStateDidChangeNotification` (*Foundation ▸ ProcessInfo ▸ "Monitor Thermal
State to Adjust App Performance"*), and as an Instruments **Thermal State** instrument (referenced in *visionOS ▸
Analyzing the performance of your visionOS app*, which notes it records device thermal states *"to check if thermal
pressures are throttling performance"*). **Consequence, owned:** `testing.md:130`'s energy and thermal clauses can
never become an automated threshold gate. They are an Instruments-and-device measurement, which is why `:210`'s
threshold question is harder than it looks and why it belongs in §9 below rather than being answered by a designer.

**8.5 The one command in the document is fine, and the ones it lacks are documented.** *Xcode ▸ Running tests and
interpreting results* gives the canonical form `xcodebuild test -scheme SampleApp`; `:206`'s missing commands are
therefore a matter of pinning scheme and destination names, not of research.

**Found nothing for:** a documented approach to verifying an app performs no networking, any Apple guidance on
fuzzing, and anything specific to auditing a board-game grid. Those three are ours.

---

## 9. Open for the owner

Only choices that genuinely need the product owner. Each with its options and what each costs.

**O1. The acceptance shape.**
- *(a) Change nothing.* Every gate added by PRs #13–#25 stays non-binding through the first implementation push;
  the first regression against an accepted contract is caught, if at all, by review rather than by a gate.
- *(b) Accept section by section with a Pending subsection* (§6.2). 99 gates bind immediately; 23 stay visibly
  non-binding with a named blocker each. Costs one editorial pass and commits the project to gates it has not yet
  executed — a gate later found impractical becomes a contract change rather than a draft edit.
- *(c) Accept the whole document as-is.* 23 gates are accepted knowing they cannot pass, which makes "all gates
  pass" a claim nobody can ever make truthfully, and erodes the meaning of the release gates at `:196-200`.
I recommend (b), but the trade in (b) — binding before executing — is the owner's to accept.

**O2. Does the deferred rules-fixture tranche gate the first internal build?**
`xiangqi-rules.md:121` asks for it *"before the rules facade's chase adjudication is relied on beyond the first
approved set."* Whether internal TestFlight counts as "relied on" is not decided anywhere.
- *Yes:* mutual perpetual check, mutual chase, check-over-chase precedence and the parity corner must have approved
  fixtures before any build ships. Costs schedule; the constructions exist (`xiangqi-rules.md:111`), the approval
  does not.
- *No:* internal testers play against an engine whose three accepted interpretations — alternation, renewal, and
  general-as-sole-defender — have no fixture, in a variant whose parity correction is the difference between a draw
  and a wrong-winner loss (`engine-integration.md:45`). The exposure is bounded (`xiangqi-rules.md:74`, `:76` state
  it) but real.

**O3. Do the Windows-dependent gates stay in the normative body?**
Five gates (`:45` in part, `:109`, `:110` in part, plus the toolchain subsection) and two Need-to-discuss items.
- *Stay:* the document can never be accepted whole, and the Windows requirements are impossible to lose.
- *Move to a marked "Windows, deferred" section:* the Apple sections become cleanly acceptable, at the cost that
  re-adding them is a later act of memory rather than an existing obligation.

**O4. Sanitizers and import fuzzing (U5) — pay now or accept the exposure.**
The mechanism is documented (§8.2) and the exposure is a hand-written C++ parser over files the contract calls
untrusted (`game-data.md:127`).
- *Pay now:* a second test-plan configuration and a fuzz harness. Costs engineering time before the first feature
  and slower test runs, and per §8.3 it cannot share a configuration with performance measurement.
- *Accept the exposure:* an internal-only, offline app whose worst realistic case is a crash on a malformed file a
  tester chose to import. Defensible for this distribution model; it should be a decision rather than an omission.

**O5. Is the AI-profile measurement (`:130`) a release gate or a periodic observation?**
Apple publishes no automated energy or thermal metric (§8.4), so as a release gate it means Instruments runs on real
devices for every candidate.
- *Release gate:* manual work per build; strong protection for the 4 GiB Hash policy, which
  `engine-integration.md:114` explicitly says *"must still be checked against memory, energy, thermal, and
  response-time requirements on supported devices."*
- *Periodic observation:* cheap, and the accepted profiles could drift on new hardware unnoticed. Note
  `engine-integration.md:116` already forbids silent retuning either way, so the choice is about detection, not
  about authority to change the profiles.

**O6. How many pending gates may be unexecuted in an internal distribution candidate?**
`:196-200` requires *"passing … critical UI tests"* while `:212` leaves "critical" undefined and `:214` leaves the
evidence question open.
- *Name the blocking subset now* (my suggestion would be: the rules fixtures, the store transactional invariants,
  the import rejection classes, and the engine memory boundaries): a candidate can ship with the other pending gates
  outstanding, and everyone knows which.
- *Leave it open:* the release gate is unenforceable as written, and the first candidate's bar gets decided by
  whoever builds it.

---

# Independent review

Adversarial verification of everything above, against the eight contracts at `60fc044`, the approved fixture
directory, the repository working tree, and Apple Developer Documentation. Method: every contract citation in the
report was opened and compared side by side; every Apple citation was retrieved and its wording compared; the bullet
counts and grep claims were re-executed. What follows is only what is wrong or overstated. Findings are ordered by
severity, not by section.

**What I re-executed and confirms the report.** The bullet census (131 change-to-validation gates of 159 total;
5 + 31 + 11 + 15 + 27 + 42 = 131) and the per-section `E + M + D + V` arithmetic (99 + 23 + 3 + 6 = 131) are exact.
The grep claims are exact: zero occurrences in `testing.md` of `help`, `offline`, `fuzz`, `sanitiz`, `leak`,
`crash`, `uuid`, `timestamp`, `mxq_`, `one main window`; three of `network` (`:140`, `:144`, `:199`), all NNUE;
`layer` only inside `player` (`:166`, `:169`). `pinned-inputs.json` does not exist. `fixtures/rules/` holds exactly
16 JSON fixtures plus the README. `core/`, `apple/`, `windows/` hold only READMEs plus the generated scaffold.
`mx-chs-002`'s defender is a rook, not a general, as claimed. The marker-geometry values quoted in U7 are verbatim
correct against `interaction-design.md:244-253`, as are the durations in U9, the Help rules at `:396`, the layering
at `:260`, the coexistence closure at `:262`, the Hash arithmetic at `engine-integration.md:105-107`, and the
`game-data.md` citations at `:38`, `:56`, `:64`, `:144`, `:146`, `:161`. All five Apple citations exist and say what
is claimed. That is a high accuracy rate; the findings below are the exceptions.

---

## R1 — Finding 1's dichotomy is false by inspection, and it is the foundation of the recommendation

**Severity: High.**

> "That is a drafting instruction about commands and thresholds. 99 of the 131 gates contain neither — they state
> which accepted behaviour must be verified, not how fast or on what hardware."

At least eight gates the report classifies **E** contain a command or a threshold:

- `:122` — a literal command: *"use `go movetime 1000`, `go movetime 3000`, and `go movetime 5000`"*.
- `:125` — *"the 4 GiB cap, 50%-of-physical-memory boundary, 20%-or-128-MiB reserve boundary, 64 MiB rounding
  boundary, and 256 MiB minimum"*.
- `:166` — *"4.5:1 against the board surface and 7:1 under Increase Contrast"*.
- `:168` — *"within 600 ms"*.
- `:178` — *"beyond `0.40 p`"*, *"inside `0.42 p`"*, *"its own `1 p` cell"*.
- `:179` — *"no more than `0.0325 p`"*.
- `:180` — *"active at 4.5:1 and record at 3:1"*.
- `:127` — named platform APIs (`os_proc_available_memory()`).

The report's §2 celebrates `:125` and `:178-181` precisely *for* their numbers, two pages after asserting that the
99 contain none. As written, a reader who checks one gate finds the claim false and stops reading.

**Correction.** The argument is repairable and worth repairing: the status line's precondition plainly concerns
*measured* values — commands that must be run against a toolchain and thresholds that must be observed on a device.
A geometry ratio, a contrast ratio and a UCI option string are design-fixed constants that no device can falsify.
Say that: *"the precondition binds thresholds that must be measured and commands that must be executed against a
toolchain; it does not bind values fixed by design in an accepted contract."* Then the count stands.

---

## R2 — C4 proposes deleting the gate for an accepted requirement; the real duplicate is inside `engine-integration.md`

**Severity: High.**

> "**C4 — A gate that is an open question in another contract.** `:141` … is a near-verbatim restatement of
> `engine-integration.md:195`, which files it under **Need to discuss** … They should not both exist."
> and: "Delete `:141` or `engine-integration.md:195` — one of the two, not both (C4)."

`engine-integration.md:111`, in the **accepted** body, ends: *"Each probe's behavior is verified against the
accepted budget boundaries on its own platform before that platform ships."* That is an accepted normative
requirement, and `testing.md:141` is its testing-side expression. The Need-to-discuss entry at `:195` is a
redundant restatement of `:111` **inside its own document** — that is where the duplication is.

Deleting `testing.md:141` would remove the only gate over an accepted per-platform obligation. The report's §3 row
for `:141` compounds this by naming `engine-integration.md:195` as where the blocker "is owned" and describing the
requirement as "*itself* an open question elsewhere"; it is not, it is accepted at `:111`.

**Correction.** Reclassify `:141` as executable (its expected values are the `:105-107` boundaries, already fixed);
recommend deleting `engine-integration.md:195`, and only that. Cite `:111` in the §3 row.

---

## R3 — Release gate `:199` has no `pinned-inputs.json` clause, and its pass condition already exists

**Severity: High.**

> §0: "release gate `:199` depends on it." §3: "release gate `:199`'s manifest dependency."
> §6.1: "`pinned-inputs.json` created and consumed by a real build (`:142`, `:145`, `:199`)."
> §6.2: Pending — "the `pinned-inputs.json` clause of `:199`".

`testing.md:199` reads in full: *"verified GPLv3 and third-party source and license inputs, and the bundled
network's verified pinned hash per the accepted NNUE handling policy;"*. There is no manifest clause to quarantine.
Worse for the claim, the expected value is published in an accepted contract: `engine-integration.md:149` fixes the
network at *"4,333,499 bytes, SHA-256 `12c45d5da817e7948cc22f2f295a0781dabd379be472006360c36676f1cc09ce`"*. A
release tester can verify that hash today with `shasum -a 256`, with no manifest and no build system.

**Correction.** All five release gates are acceptable now, not four. The manifest dependency belongs to `:142` and
`:145`, which name the file explicitly. Fix §0, §3, §6.1 item 2 and the §6.2 table row.

---

## R4 — `:45` is self-conditioned; it is not blocked by Windows

**Severity: High.**

> §3: "`:45` core suite 'once the Windows toolchain is pinned' | Windows toolchain pin | … | **After the Windows
> frontend exists**". §6.2: Shared core pending — "`:45` (split the Windows clause out)".

`testing.md:45` reads: *"Core changes run the core test suite … on at least one Apple platform and, **once the
Windows toolchain is pinned**, on Windows."* The gate already carries its own condition. A conditional obligation
whose condition is currently false is satisfiable as written today, and becomes binding automatically the day the
toolchain is pinned — which is strictly better than quarantining it, because quarantine requires someone to
remember to un-quarantine it.

**Correction.** `:45` is **E**. Do not split it. Shared core's pending list drops to one entry, and §6.1's
precondition 1 loses `:45`.

---

## R5 — `:108` is vacuously satisfiable, so half the unreachability argument collapses

**Severity: High.**

> "Two of the 23 blocked gates depend on artefacts that cannot exist for a release or more: the Windows toolchain
> (`:45`, `:109`, `:110`) and a second shipped database schema (`:108`, which gates *'every released database
> schema migration'* when exactly one schema version exists)." and §6.1: "Items 1 and 15 are not reachable …
> **Whole-document acceptance is therefore not achievable on any schedule the project controls**."

`:108` gates *"every released database schema migration and archive-format migration from file-backed fixtures."*
With one released schema version and one archive version, that set is empty and the gate passes vacuously. It is
exactly the kind of standing obligation §7.1 argues the document needs more of: cheap now, binding automatically
later, impossible to forget.

Combined with R4, §6.1's fifteen preconditions lose items 1 (in part) and 15 entirely. The unreachability
conclusion still survives on `:109` and `:110`'s Windows leg — but as a much narrower claim: *two* gates, both
naming platform round-trips, block whole-document acceptance. That is still enough to carry the recommendation,
and it is a claim that survives contact with a reader.

---

## R6 — "exactly one keyboard command is accepted anywhere" is false

**Severity: High.**

> §3: "`:150` 'keyboard and pointer behavior where supported' | Keyboard coverage is undefined; **exactly one
> keyboard command is accepted anywhere** (Flip Board, `interaction-design.md:218`)". U19 repeats it.

Three accepted elements exist beyond Flip Board:

- `interaction-design.md:233` — *"Keyboard and VoiceOver use an equivalent select-piece, inspect-destinations, and
  select-destination flow rather than requiring a drag gesture."* That is the entire board input model for keyboard,
  accepted.
- `interaction-design.md:506` — where a platform lacks an idiom, *"the same operations must be exposed through that
  platform's conventional equivalents, such as context menus, hover controls, and **keyboard commands**, without
  changing product capabilities."*
- `interaction-design.md:253` fixes the focus ring's geometry, which the report does cite.

And `testing.md:81` already gates *"pointer, keyboard, and VoiceOver equivalents"* for the History row actions.

**Correction.** `:150`'s blocker is the *completeness* of keyboard coverage, not its absence. The accepted board
flow at `:233` is executable today and should be named in the gate rather than deferred to survey 8.2.

---

## R7 — `:160` is not fully subsumed; deleting it drops "applies immediately" for piece style

**Severity: Moderate-High.**

> "`:161` already asserts persistence for *every* Settings preference; `:188` already asserts presentation-only for
> piece style, piece symbols *and* notation together. `:160` adds nothing."

`:160` asserts three things: persists, **applies immediately**, changes presentation only. `:161` covers persistence
and non-interference. `:188` covers presentation-only. Immediacy is covered by `:164` — *"Verify the sound, haptics,
and piece-symbols settings persist, **take effect immediately**"* — which names sound, haptics and piece **symbols**,
and not piece **style**. Delete `:160` and nothing anywhere requires a piece-style change to take effect without a
relaunch.

**Correction.** Either keep `:160`, or extend `:164` to name piece style before deleting it. As an editorial fix
proposed to land immediately, this one would lose an accepted behaviour.

---

## R8 — `:151` is not fully subsumed, and §8.1 depends on it surviving

**Severity: Moderate-High.**

> §4.1: "`:151` ⊂ `:171` + `:175` + `:180` + `:181`. … As a gate it has no pass condition; as a heading it is fine."
> §8.1: "So the audit is a floor for `:149`/**`:151`**, never the pass condition."

The report proposes deleting `:151` in §4.1 and then, four sections later, assigns it an Apple-documented floor.
Beyond the internal contradiction, the four subsuming gates are all board- and glass-scoped: `:171` is Reduce Motion
over board animations, `:175` is the custom glass surfaces, `:180` and `:181` are marker ink and marker rendering.
`:151` is the only instruction to exercise those four settings anywhere else — Settings, History, the result card,
the move list, the numeral strips.

**Correction.** Rescope `:151` ("outside the board block") rather than deleting it, and reconcile §8.1.

---

## R9 — deleting `:129` removes fixture comparison from the section an engine change selects

**Severity: Moderate.**

> "`:129` ⊂ `:96`. … a weaker restatement of `:96`".

Validation principle `testing.md:35`: *"Select tests from the contract changed, not only from the files edited."*
`:96` lives in **Rules**; `:129` lives in **Engine integration**. A change that touches only the engine — a new fork
revision, a search-configuration change — selects the Engine section. Delete `:129` and that change selects no
fixture comparison at all. The scopes also differ: `:96` says *"the same accepted **history** fixtures"*, `:129`
says *"accepted rules fixtures wherever search consumes terminal adjudication"*, which is not obviously narrower.

**Correction.** Rewrite `:129` as an explicit cross-reference to `:96` rather than deleting it. Note also that
C2 says *"`:87`, `:96`, `:129` and `:145` all require the approved fixtures to pass"* — after the deletion that
becomes three.

---

## R10 — C2 is already answered by an approved artefact the report itself cites

**Severity: Moderate.**

> "**C2 — No gate names the engine variant the fixtures run under.** … As written, a fixture run is not
> reproducible from the gate text, and the accepted-baseline limitation could be reported as a regression."

`xiangqi-rules.md:92` makes the fixture directory's README part of the approved contract (*"that directory's README
defines the schema, the `mx-<area>-NNN` identifier scheme, and the immutability rules"*) — the same README the
report quotes in U23. Its schema section says:

> "`variant` — the ruleset identity the position is defined against; always `minixiangqi`. **This names the Mini
> Xiangqi ruleset of the rules contract, not an engine variant to select**: the engine configuration that must
> satisfy these fixtures, including its chase adjudication, is defined in `docs/engine-integration.md`, and the
> built-in engine variant of the same name does not satisfy every fixture."

So the answer is fixed in an approved artefact, one indirection away, and the misreading C2 fears is explicitly
pre-empted there.

**Correction.** Downgrade C2 from "conflict" to "add the cross-reference so the gate text is self-contained". It is
still worth doing; it is not a defect in the contracts.

---

## R11 — U1's proposed gate would answer an open product question by test

**Severity: Moderate.**

> "→ *Gate: run the full suite with networking unavailable; **assert no outbound connection** during a session
> covering launch, play, import and export.*"

`product.md:108`, under **Need to discuss**: *"Define what 'fully offline' permits for platform-provided local
diagnostics, backup, and other system behavior."* A gate asserting zero outbound connections decides that open
question by assertion, and would fail on system telemetry, crash reporting or device backup that the product may
well permit.

**Correction.** Scope the assertion to connections the **app itself** initiates, and say that the platform-service
boundary is `product.md:108`'s to settle. See also R12 for a cheaper mechanism.

---

## R12 — "found nothing for verifying no networking" misses a documented, enforced, artefact-level mechanism

**Severity: Moderate.** *(Apple citation: verified, and the report's "not found" is too broad.)*

> "**Found nothing for:** a documented approach to verifying an app performs no networking…"

*Security ▸ App Sandbox ▸ Network* and *BundleResources ▸ Security entitlements ▸ Networking* publish
`com.apple.security.network.client`: **"A Boolean value indicating whether your app may open outgoing network
connections."** *Xcode ▸ Configuring the macOS App Sandbox ▸ "Enable access to restricted resources"* documents the
same as the "Outgoing Connections (Client)" checkbox. For a sandboxed macOS app, the absence of that entitlement is
not evidence of no networking — it is *enforcement* of no networking, and it is checkable by reading the signed
entitlements.

This is precisely the artefact-level gate §7.1 argues for, and it is stronger than the runtime observation U1
proposes, because a runtime session samples behaviour while the entitlement constrains it. For the record,
`MiniXiangqi/apple/MiniXiangqi/MiniXiangqi.entitlements` currently declares the two memory entitlements and five
`com.apple.security.hardened-process.*` keys, and **neither** network entitlement.

**Correction.** Propose U1 as *(a)* an entitlements assertion on macOS plus *(b)* the scoped runtime observation for
iOS and iPadOS, where App Sandbox networking is not separately gated. Do not report "nothing found".
*(MetricKit's `MXNetworkTransferMetric` and the Organizer's Battery Usage "Networking" category, both documented
under Xcode ▸ Analyzing your app's battery use, give a field-side cross-check.)*

---

## R13 — U5's single sanitizer configuration cannot do what U5 claims, on the report's own source

**Severity: Moderate.** *(Apple citation: correct as quoted, incomplete as used.)*

> "**U5. Memory safety, leaks, and fuzzing over untrusted input.** … → *Gate: a test-plan configuration with ASan +
> UBSan + TSan + Main Thread Checker*"

The same page the report cites, *Xcode ▸ Diagnosing memory, thread, and crash issues early*, states two things the
report omits:

- **"You can't use Thread Sanitizer to diagnose iOS, iPadOS, tvOS, visionOS, and watchOS apps running on a device.
  Use Thread Sanitizer only on your 64-bit macOS app, or to diagnose your 64-bit iOS … app running in Simulator."**
- **"Address Sanitizer doesn't detect memory leaks, attempts to access uninitialized memory, or integer overflow
  errors. Use Instruments and the other sanitizer tools to find additional errors."**

So one configuration cannot deliver TSan on the platform where the 4 GiB Hash policy actually applies, and nothing
in the proposed gate detects the **leaks** the item's own title promises.

**Correction.** Two configurations minimum (ASan + UBSan + Main Thread Checker everywhere; TSan on macOS and
Simulator), plus a named leak mechanism, or drop "leaks" from the claim. This also strengthens O4: the cost is
higher than "a second test-plan configuration".

---

## R14 — §6.2's split does not dispose of all 131 bullets, and its counts disagree with the text

**Severity: Moderate.**

> "This makes **99 gates binding immediately** and leaves **23** visibly non-binding with a named blocker each."

The §6.2 Pending column contains 24 entries — 2 (`:45`, `:49`) + 3 + 4 + 4 + 5 + 6 — because `:49` is **V**-class,
not **M**. Meanwhile the "Accept now" column equals the **E** counts exactly, so the other five V-class bullets are
neither accepted, nor pending, nor deleted. 99 + 24 + 3 deleted = 126 of 131.

Compounding it, §1 says *"The 99 are listed by exception in §3 and §4 (everything not named there is E)"* — but §3
lists the 23 M and §4 lists the 3 D, and **the six V-class bullets are never enumerated anywhere in the report**. A
reader cannot reconstruct the classification, which is the one thing §0 promises ("meant to be disagreed with
bullet by bullet; I give the line number for each so that is possible").

**Correction.** Name the six V bullets and give each a disposition. My reading of the candidates: `:49`, `:53`,
`:62`, `:97`, and one each in Engine and UI — but the report must say, not me.

---

## R15 — §6.1 treats Need-to-discuss items as preconditions for acceptance, against the precedent of every other contract

**Severity: Moderate.**

> §6.1, "All fifteen of these, simultaneously", includes: 4 (`:207`), 5 (`:210`), 13 (`:213`), **14 ("The
> localization review process defined (`:211`…)")**, and 1 in part (`:208`).

`testing.md:5`: *"Items under **Need to discuss** are non-normative."* And every accepted contract in `docs/` was
accepted **with its Need to discuss section open**: `product.md:103-110` (four items), `architecture.md:82-86`,
`game-data.md:171-175`, `xiangqi-rules.md:115-121` (three), `core-interface.md:247-252` (two),
`engine-integration.md:190-197` (four). Resolving a document's open questions has never been the bar for accepting
that document here.

The real precondition is that a *normative gate* lacks an input — which is true of `:54`/`:126` (needing the
matrix), `:130` (needing thresholds) and `:113` (needing the measurement method), and is why those appear in §3.
Item 14 has no dependent normative gate at all: no gate in `testing.md` turns on the localization review process.

**Correction.** State §6.1 as "the accepted-body gates that lack an input", drop item 14, and drop the
Need-to-discuss line numbers from the others in favour of the gates that depend on them.

---

## R16 — `:155` is misclassified by the report's own criterion

**Severity: Moderate.**

> §2, criterion: "Whether the code exists is a separate axis — none of it exists, and that is expected of a
> design-first repository."
> §3: "`:155` every icon unmistakable, chariot against cannon | **The icon set does not exist** | … | After the icon
> work".

`interaction-design.md:115` fixes the pass condition verbatim and in the accepted body: *"Every icon is
distinguishable from every other at the smallest supported board size. Chariot against cannon is the demanding
pair … the set is not acceptable until those two are unmistakable."* `testing.md:155` restates it. The icon set is
an **artefact that does not exist yet**, exactly like the core, the store and the frontend — the axis §2 declares
separate. No decision is missing.

**Correction.** `:155` is **E**; the UI pending list drops from six to five. (Contrast `:149` and `:189`, where the
missing thing is a *design decision* — the VoiceOver model, the oracle table — and M is right.)

---

## R17 — `:83` does not quote its copy

**Severity: Moderate.**

> "**`:67`, `:73`, `:83`, `:184` — the four gates that quote their copy exactly.** These can never drift from
> `interaction-design.md` because they carry the strings."

`testing.md:83` reads: *"Verify **the accepted** insufficient-memory title, message, Cancel, and Retry actions…"* —
it carries no string at all. The report's own U20 treats `:83` as a by-reference gate. Gates that do carry strings
and are not listed include `:71` (**你将控制红黑双方，红方先行。**), `:78` (**继续对局**, **以和棋结束**, **可判和**)
and `:139` (**无法启动 AI 对手**).

**Correction.** Replace `:83` with `:71` or `:139` in §2.

---

## R18 — §2 credits `:168-172` with numbers those gates do not contain

**Severity: Moderate.**

> "**`:168-172` — the motion gates.** Seven named travel durations, the 600 ms decision-cycle bound, **340 ms flip,
> the 260 ms compose-beat floor and the 500 ms activity threshold**…"

`testing.md:168` names exactly one number: *"a decision-cycle Undo completes within 600 ms"*. Travel is *"the
accepted duration at each of the seven board distances"*; flip is *"its accepted duration"*. `:169` says *"the
compose-beat floor"* and *"the accepted threshold"*. The values 340 ms, 260 ms and 500 ms live at
`interaction-design.md:420`, `:422` and `:424` and appear nowhere in `testing.md`.

**Correction.** This is by-reference gating, which is fine and is what R1 should have said the document mostly does.
Describe it that way rather than implying the numbers are present — otherwise §2's exemplar contradicts §1's census.

---

## R19 — U9's 250 ms claim contradicts the report's own standard

**Severity: Moderate.**

> "**U9.** Ungated: … and the **one-ply Undo bound of 250 ms** (`:416`)."
> §4.2 item 8: "Between them they still fail to name the 250 ms one-ply bound".

`testing.md:159` gates *"that Undo transitions complete within **their accepted durations**"*. The accepted
durations are `interaction-design.md:416`'s *"250 ms for one ply and 600 ms for a decision cycle"*. Under finding
1's own rule — a gate that states which accepted behaviour must be verified is executable — `:159` gates the
250 ms bound. The report cannot classify `:159` as E and simultaneously list its subject as ungated.

**Correction.** Drop the 250 ms bound from U9. The selection lift (120–160 ms, `:408`), the capture removal
(≈250 ms, `:412`) and the Reduce Motion crossfade ceiling (120 ms, `:428`) are genuinely ungated and survive.

---

## R20 — U30's second illustration inverts the accepted validation order it cites

**Severity: Moderate.**

> "A file that is both oversized and malformed must fail as oversized, **or the created-by-a-newer-version message
> can be pre-empted by a syntax complaint — the exact confusion `game-data.md:64` mandates against.**"

`game-data.md:64` orders the stages: *"transport and size; strict UTF-8 and JSON syntax under the structural
limits …; envelope and explicit version dispatch, rejecting … unsupported versions with a distinct
created-by-a-newer-version message that is never presented as corruption;"*. Syntax precedes version dispatch.
A file that is both malformed and declares version 2 **must** fail as malformed — a syntax complaint pre-empting
the version message is the accepted behaviour, not the confusion. What `:64` forbids is presenting a
*successfully-parsed* unsupported version as corruption.

The first example (oversized before malformed) is correct and the underlying gap is real — nothing requires the
reported class to be the earliest failing stage.

**Correction.** Delete the second clause. State the gate as: *the reported rejection class is the earliest failing
stage of `game-data.md:64`'s pipeline, and an unsupported version is never reported as corruption.* As written, the
proposal would have a gate contradict accepted behaviour.

---

## R21 — the `:92` king-exclusion blocker is not the deferred tranche, and the report says so itself

**Severity: Moderate.**

> §3: "`:92` … **king** chase-target exclusion | Fixtures do not exist | `xiangqi-rules.md:111`, `:121` | **After
> the deferred tranche**"
> U24: "`engine-integration.md:43` … states plainly that the change *'carries no fixture'* after a 29,500-sample,
> 11.2-million-cycle search found no position where the gap changes an outcome."

`xiangqi-rules.md:111` names exactly two accepted outcomes without fixtures — a mutual perpetual-check draw and a
mixed check-over-chase sequence. `:121`'s tranche is *"protection variants, interruption, discovered and pinned
attacks, mutual perpetual check, and check-over-chase precedence"*. King chase-target exclusion is in neither list,
and `engine-integration.md:53` says a targeted search found **no** position where the classifier gap changes an
outcome — so a discriminating fixture may not exist to be approved. Approving the tranche will not unblock `:92`.

**Correction.** Say that `:92`'s king leg has no scheduled fixture and may be unfalsifiable by construction; that
is a different disposition from "after the deferred tranche", and it is an owner question in its own right (accept
an ungated clause, or drop the king clause from the gate and rely on `mx-chk-001`/`002`). Related: §6.1 precondition
3 lumps `:94` into the tranche, while §3 correctly assigns it to the fork patch (`engine-integration.md:45`).

---

## R22 — §8.4's "can never" is stronger than the documentation supports

**Severity: Moderate.** *(Apple citations verified; the inference is not.)*

The XCTest metric list is exactly right — I retrieved *XCTest ▸ Performance Tests ▸ Measurement Metrics* and it is
`XCTMetric`, `XCTCPUMetric`, `XCTClockMetric`, `XCTHitchMetric`, `XCTMemoryMetric`, `XCTOSSignpostMetric`,
`XCTStorageMetric`, `XCTApplicationLaunchMetric`. No energy metric, no thermal metric. **Confirmed.**

The consequence drawn is not:

> "`testing.md:130`'s energy and thermal clauses **can never become an automated threshold gate**."

Apple publishes two further mechanisms:

- *Xcode ▸ Analyzing your app's battery use ▸ "Gather power metrics"* maps power-use categories onto **MetricKit**
  metrics — `CPUTimeMetric`, `CPUInstructionsCountMetric`, `PixelLuminanceMetric`, `GPUTimeMetric`, and the network
  transfer metrics — and documents the Organizer's Battery Usage pane with its per-version category breakdown.
  MetricKit payloads arrive programmatically and can be asserted against thresholds.
- *Xcode ▸ Measuring your app's power use with Power Profiler* profiles power impact *"whether or not your device is
  connected to Xcode"*.
- Thermal state is readable **in-process, from a test**, via `ProcessInfo.thermalState` — the very API the report
  cites — so an assertion like "thermal state stays at or below `.fair` through a whole game at 深思" is writable
  today.

**Correction.** "No XCTest metric exists" is the defensible claim and it is enough to make O5 a real question.
"Can never become an automated threshold gate" is not, and O5's framing ("as a release gate it means Instruments
runs on real devices per candidate") overstates the cost by excluding both alternatives.

---

## R23 — §8.1 over-claims the accessibility audit's reach onto a custom-drawn board

**Severity: Low-Moderate.** *(Quotes verified verbatim; the mapping is the problem.)*

Every quoted string in §8.1 is exact, including *"audits the current screen for accessibility issues the same way
that running an audit in Accessibility Inspector does"*, *"If the UI test finds any audit issues, it automatically
fails."*, and the limit *"doesn't guarantee a fully accessible app"* / *"Always test your app with various assistive
apps, such as VoiceOver"*. The audit-type list is exact. **Confirmed.**

> "Four of those map **directly** onto accepted criteria — `contrast` onto the project's contrast numbers,
> `dynamicType` and `textClipped` onto the numeral-strip and layout rules, `hitRegion` onto the 44 pt floor."

Apple defines `contrast` as checking *"sufficient color contrast between overlapping **elements**"* and `hitRegion`
as checking *"whether the size of an **element** is too small for a person to interact with"*. The project's
contrast requirements are between a symbol and its disc face, a disc boundary and that style's board surface, and
marker ink and the board surface (`testing.md:156`, `:180`) — all relations *inside one custom-drawn surface*, not
between accessibility elements. The 44 pt floor is the cell pitch `p` (`interaction-design.md:129`), a drawing
dimension, not an element hit region. Whether the audit sees any of it depends on the board's accessibility element
model, which the report itself (correctly) says is undesigned.

**Correction.** "May map, once the board's element model exists" — and note that `textClipped` and `dynamicType`
over the numeral strips are the two most likely to land, since those are text.

---

## R24 — C1 is overstated

**Severity: Low.**

> "**C1 — Two different bars for the same suite.** … The two gates are reconcilable as per-change versus periodic,
> but the document never says which applies when, so a change can land under `:45` having never been run under
> `:46`."

`:46`'s *"every development platform"* most naturally means the machines the project develops on — macOS now,
macOS and Windows later — which is what `testing.md:29` states as a toolchain fact and what `architecture.md:78`
requires of the runner. `:45`'s *"at least one Apple platform"* names a run destination among iOS, iPadOS and
macOS. Read that way the two are consistent, and in any case `:45` already picks up Windows the moment the toolchain
is pinned (R4), so both bars close on the same event.

**Correction.** Keep the ask — say which bar is per-change and which is periodic — but drop "two different bars"
and the implication of a live gap.

---

## R25 — C5 is an omission the report itself concedes, and §6.2 then quarantines two non-Windows bullets

**Severity: Low.**

C5 is headed as a conflict but ends *"`testing.md` omits the accepted timing"* — which is an omission. `:31`'s *"CI
results supplement, and do not replace, the release gates"* is consistent with `architecture.md:80`'s *"a
convenience rather than a merge gate"*; only the *when* is missing.

Separately, §6.2 moves the whole "Windows subsection" to Pending. That subsection is `:29-31`, of which `:29` (the
core builds and tests on every development platform) and `:31` (GitHub Actions) are not Windows-specific. Only `:30`
self-declares draft state.

**Correction.** Move `:30` alone; fix `:31` in place by adding `architecture.md:79`'s timing.

---

## R26 — citation slips

**Severity: Low.** None changes a conclusion; all would be caught by a reader checking.

- U1 cites `architecture.md:13` for offline. Offline is `:12` (*"All gameplay works offline. Nothing may depend on
  networking or cloud services."*); `:13` is the one-main-window rule.
- U2 cites `architecture.md:14` for one main window. It is `:13`.
- U50: `resign_available` is a `MxqGameStatus` flag at `core-interface.md:101`, not `:50`. The quoted *"legal only
  in human-versus-AI play"* is at `:50` and is correct.
- U43: *"`engine-integration.md:110` repeats it"* — `:110` requires that *a saved diagnostic record* identify the
  configuration, not that a test report do so. The test-report requirement is unique to `core-interface.md:39`,
  which makes U43's underlying point **stronger**, not weaker.
- U24: the *"carries no fixture"* wording and the 29,500-sample / 11.2-million-cycle figures are at
  `engine-integration.md:53`, not `:43`. Both figures are exact.
- C2's bare `:143` reads as `engine-integration.md:143` in context but means `testing.md:143`; and the rationale
  attributed to it (*"so the harness can run a variant and its control side by side"*) is
  `engine-integration.md:132`.
- §5.6 calls `core-interface.md` a "252-line" contract; it is 253.
- U7: *"`testing.md:178-181` gates the *envelope* and the contrast, **not one of these values**"* — `:179` gates the
  table's `0.0325 p` pulse peak. The 0.22 p → 0.28 p example still holds and the point survives.
- Finding 2 says "**Two** of the 23 blocked gates" and then names four (`:45`, `:109`, `:110`, `:108`).

---

## Open questions the report presents as settled, and settled matters it defers

- **Presented as settled, actually open:** none of substance. O1–O6 are correctly identified as owner decisions,
  and the recommendation in O1 is properly labelled as a recommendation. §6.2's *"Recommended shape"* is framed as a
  proposal throughout.
- **Deferred, actually decided:** `:141` (decided at `engine-integration.md:111` — R2); `:45`'s Windows leg
  (self-conditioned — R4); `:108` (vacuous — R5); `:150`'s board flow (decided at `interaction-design.md:233` —
  R6); `:155`'s pass condition (decided at `interaction-design.md:115` — R16); `:199`'s hash value (decided at
  `engine-integration.md:149` — R3). Six of the 23 M-class gates are less blocked than stated, which strengthens
  the report's own recommendation: the pending list is 17, not 23, and the argument for accepting section by
  section gets cheaper.
- **No Chinese copy is proposed anywhere in the report**, so there is nothing to review under that heading. Every
  Chinese string it quotes — **开始新对局？**, **当前对局**, **这盘对局将按当前状态保存到历史。**, **取消**,
  **保存并继续**, **无法保存对局**, **当前对局仍然保留。请重试。**, **重试**, **无法保存这一步，请重试。**,
  **无法启动 AI 对手**, **已记录到历史**, **局面已三次重复，可以和棋结束。**, **继续对局**, **以和棋结束**,
  **可判和**, **将军**, **帅将俥车傌马炮砲兵卒** — matches its source contract character for character.

## Net assessment

The report's central recommendation — accept section by section with a named-blocker Pending subsection — survives
this review, and R3/R4/R5/R6/R16 make it *easier* to adopt than the report claims, not harder. What does not
survive unamended: finding 1 as worded (R1), the C4 deletion (R2), the `:160` deletion (R7), the `:151` deletion
(R8), the U30 gate (R20), the "can never" in §8.4 (R22), and the "nothing found" on networking (R12). Four of the
report's own proposals would, if landed as written, delete or contradict accepted behaviour; those are the items to
fix before any of this reaches contract text.
