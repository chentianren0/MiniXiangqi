# Testing

This document owns the validation categories, fixture expectations, and release gates: which evidence a change or build of the Mini Xiangqi application requires. It does not record individual run results, run commands, or work status; those belong in the CI workflows, the platform READMEs, and GitHub Issues.

> **Status: binding**, except for the thresholds this document names as owed — performance, memory, energy and thermal figures per AI profile, and the retained-evidence list for a distribution candidate.

## Toolchain and destinations

### Apple

- Xcode 27 beta at `/Applications/Xcode-beta.app`, build `27A5228h`, Swift 6. It is selected per invocation through `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`: do not change global `xcode-select`, and do not silently validate with another Xcode.
- iOS, iPadOS, and macOS 26.6 deployment targets. iOS shares macOS's figure rather than reaching lower: the app is built on the Liquid Glass controls that arrive with 26, the prebuilt core is compiled at 26.5, and a floor beneath the library the app links would only invite a linker warning about a slice it can already run on.
- Apple-silicon macOS; `x86_64` is not supported on macOS.
- **iOS evidence is taken on a current iPhone — iPhone 17 or iPhone 17 Pro — and a current iPad — iPad Air or iPad Pro.** The phone gives the compact-width evidence and the iPad the regular-width evidence in both orientations, which is every arrangement the layout has. Both named phones are **402 points** wide, and that width is the point of them: a *larger* phone is a different compact width and does not stand in for it, any more than an older or smaller one does. Layout evidence names the device it was taken on.
- **One simulator is booted at a time.** Several at once puts a development Mac under memory pressure, which is a poor way to measure an app about memory.

Both test bundles declare `iphoneos iphonesimulator macosx`, and what differs between the platforms is which suites the bundle carries there. The unit bundle runs on both an iOS Simulator and macOS: what it measures — the layout-shape rule, the memory probe, the contrast ratios, the rendered board — is about the platform it runs on, so running it on one platform is evidence about one platform.

The UI bundle carries two sets of suites that are not ports of each other, and the platform is declared **per file** rather than by the target. The macOS suites — `PlayScreenUITests`, `PlayHomeUITests`, `HistoryScreenUITests`, `SettingsScreenUITests`, `HumanVersusAIUITests` — are `#if os(macOS)`: they drive a window, naming a size and reading the frame back, and a window is what iOS has not got. The phone suites — `PhonePlayUITests`, `PhoneSettingsUITests` — are `#if os(iOS)`, and they ask the questions only a phone can answer: that a 402-point phone takes the **stacked** arrangement, that Mini Xiangqi holds its 44-point pitch floor and Xiangqi its 34-point floor, that the 49 or 90 hit cells are real and non-overlapping, that two taps make a move, that the 棋谱 record comes up over the board on demand and goes away again, that portrait remains fixed, that the result flow reaches a filed record, and that the 触感 row agrees with the hardware. A destination therefore selects its own suites, and `LaunchPreferences` keeps the hermetic-launch table single rather than letting two copies drift.

What the phone suites deliberately leave alone: how a landing feels in the hand, and any measurement of latency, memory, energy or thermals. Both belong to the owner's device pass, and a Simulator is the wrong instrument for either.

Build and run operations live in [`apple/README.md`](../apple/README.md).

### Shared core and Windows

- The shared core builds and its tests run on every development platform without a frontend.
- The core's Windows compiler is pinned in `pinned-inputs.json`, one entry per architecture: Visual Studio 2026 Community with the MSVC v14.51 toolset and the Windows 11 SDK on `x64`, and the CI runner's own MSVC v14.44 on `ARM64`. The frontend's half of that toolchain — Windows App SDK version, .NET version, and the deployment flags — is pinned by the packaging build, `windows/package-zip.ps1`. The manifest records what a build measured rather than what it intends; what no build measured stays unestablished, and the entry says which fields those are.
- **`ARM64` is a CI-only build.** No developer machine compiles that architecture, so a validation claim about `ARM64` cites a CI run rather than a developer run. That is the one place this document's developer-runs-are-the-evidence rule does not reach, and it says so rather than pretending the two are the same.
- `.github/workflows/core-suites.yml` runs the core suites in both configurations, on a pinned macOS runner and two pinned Windows runners, `x64` and `ARM64`, each pinned to the newest image GitHub hosts rather than the oldest that still works, so that CI tracks this project's toolchain instead of trailing it. What CI proves is that the core compiles and its suites pass on a machine other than the one the change was written on; reproducing the pinned build is a developer-machine claim on `x64`, and on `ARM64` there is no developer machine for it to be one on.
- CI results supplement, and do not replace, the release gates below. Windows build, packaging, and smoke operations live in [`windows/README.md`](../windows/README.md).

## Validation principles

- Select tests from the contract changed, not only from the files edited.
- Keep rules, domain, persistence, engine, and UI tests independently runnable where practical.
- Prefer deterministic, behavior-focused fixtures over snapshots of incidental implementation details.
- Report exact commands, environment, results, and anything not run.
- Keep raw logs, measurements, and historical run results outside this document.

## Change-to-validation expectations

### Shared core

- Core changes run the core test suite — rules fixtures, archive codec, library store, and search facade — on at least one Apple platform and on Windows.
- Run that suite in **both** a debug and a release configuration. Neither is a superset of the other: the programming errors in [core-interface.md](core-interface.md)'s error taxonomy assert where `NDEBUG` is undefined and return their code where it is defined, so a release run is the only one that can observe those codes and a debug run is the only one that exercises the assertions — and the vendored engine's own assertions are live only in the first.
- Verify the one shared core test runner executes the approved fixtures identically on every development platform, without a frontend.
- Store changes verify the transactional invariants: single active game, atomic archive-and-clear, no partial import, and deletion rollback.
- Archive changes verify cross-platform round-trips and version dispatch, including rejection of unsupported versions.
- C-interface changes verify both platform bindings against the threading and error contract in [core-interface.md](core-interface.md).

### Product and interaction

- Review affected product and interaction contracts.
- Exercise the complete affected user flow for each affected game on the smallest relevant iPhone layout, an iPad layout, and a supported macOS window size.
- Verify iPhone stays in portrait when rotated and shows no orientation prompt, while iPad adapts to every orientation and to full-screen and windowed sizes including the system tiling configurations.
- Verify the layout shape is selected by the available space rather than by device identity, so a resized macOS window and a windowed iPad reach the same arrangement at the same size — including the tall, narrow macOS window that stacks. Verify one navigation container serves all three platforms, in the presentation each platform gives it.
- Verify each game's board fits both the available width and the remaining height at every supported size, never overflowing a short window.
- Verify Mini Xiangqi stays at or above a 44-point pitch and Xiangqi at or above 34 points. Every hit element is its actual disjoint cell — never an overlapping 44-point overlay on Xiangqi — and one location addresses only one point. Chrome tightens before either board, and resizable-window floors protect both profiles. Include a Mac at its largest-text display setting.
- Verify the pre-start preview shrinks as needed so the setup controls always fit, including when a creation-failure error is shown.
- Verify no captured-piece display appears in either layout shape.
- Verify the play controls are 悔棋 · 判和 · 认输 · 翻转棋盘 in human-versus-AI, 悔棋 · 判和 · 翻转棋盘 in Free Play, and the transport plus 翻转棋盘 in replay; and that a finished game carries 悔棋 · the concluding action · 翻转棋盘 in both modes. What bounds the play cluster is judgement rather than a count — small and calm, neither crowding the screen nor reading strangely — and it is judged from a rendered screen; replay's transport is not part of it. Verify the flip is presentation only in every mode: it changes no game state, takes no tint, and is never disabled.
- Verify 认输 presents 认输？ / 认输后本局将记为你落败。 with 取消 and 认输; that confirming records a human loss and an immutable History record; that cancelling changes nothing; and that it is absent in Free Play and replay.
- Verify the shared maximum width footprint: Mini Xiangqi stops at pitch 102 and width 714, Xiangqi at pitch 79 and width 711; surplus space goes to the surrounding layout.
- Verify the move list is permanently visible in the side-by-side layout and reachable on demand in the stacked layout, without either the board or the controls losing space by default.
- Inspect light and dark appearances, text expansion, interruption, error, and destructive-action states.
- Verify that a new installation defaults to **我先手** and **标准**, while Settings can persist **AI 先手**, **随机**, and any accepted AI level as later setup defaults.
- Verify that entering human-versus-AI setup creates a fresh in-memory draft, per-game changes never update Settings, leaving discards the draft, and reopening reloads current Settings defaults.
- Verify that the setup board is a noninteractive preview, no active game or resolved Random side exists before **开始对局**, and the created game freezes the resolved side, level identifier, and exact `movetime`. Random previews Red at the bottom and flips only after successful creation resolves to **AI 先手**.
- Verify the Play root has no board and offers four rows in two headed sections, in order: **象棋** then **迷你象棋**, each **人机对弈** then **自由对弈**. Every row opens setup carrying that exact game. With an active game, the **当前对局** metadata begins with its game and **回到对局** restores it exactly; launch still resumes directly, leaving ends nothing, and a filed game is not current.
- With any active game, verify all four rows remain available and immediately present the same save-and-continue confirmation with factual old-game metadata. Cover a cross-game switch as well as old-mode and new-mode combinations, an ordinary ongoing game, a claimable but unclaimed neutral repetition, and an unconfirmed natural terminal result.
- Verify the exact fixed copy: **开始新对局？**, metadata header **当前对局**, **这盘对局将按当前状态保存到历史。**, **取消**, and **保存并继续**. Verify that only metadata changes and that no separate Undo or draw-claim action appears in this confirmation.
- Verify factual metadata in this order: game, mode, human side when applicable, ongoing side to move or terminal result and reason, claim availability, and move count.
- Verify automatic classification: an ordinary ongoing game is saved as ended early without a competitive result; an unclaimed claimable repetition is also saved as ended early rather than as a draw; and an unconfirmed natural terminal game retains its actual result and exact termination reason.
- Verify that Cancel discards the temporarily selected destination, preserves the active game exactly, and leaves its normal Undo or draw-claim controls available.
- Verify that both modes of both games open a pre-start state, visibly name the selected game, and create no active game before **开始对局**. Free Play uses a noninteractive, Red-bottom preview with no turn status, shows **你将控制红黑双方，红方先行。**, and presents no configurable setup fields.
- After successful **保存并继续**, verify that leaving either pre-start state creates no game and the old game remains immutable History.
- Verify that a failed archive-and-clear operation presents **无法保存对局**, **当前对局仍然保留。请重试。**, **取消**, and **重试**; preserves the old active game; creates no new game; and never enters a pre-start state. Verify Retry repeats the atomic operation and Cancel discards the temporary destination.
- Verify that insufficient AI resources, AI unavailability, and active-game persistence failures create no game or persistent game-library change. The pre-start state remains retryable, and a human-versus-AI Random choice remains unresolved.
- Test double **开始对局**, leaving while creation is in progress, and late completion for both modes. Only one current setup-session request may commit; leaving invalidates it and creates no game.
- Verify the turn-status matrix for Red and Black, human and AI ownership, AI thinking, Free Play, unavailable input, and replay progress.
- Verify the natural-result notice before and after saving, including **保存**, **保存并开始新对局**, **回放**, **完成**, the absence of **悔棋** on the notice and its presence in the cluster, and the absence of a Play Again action. Verify it is dismissible by its own close control, by the cancel key, and by a click on the board; that closing it decides nothing, leaving the result on the turn status, Undo available while the result is unconfirmed, and the concluding action in the cluster; and that it does not present itself again for the same result. Verify that a game already filed is not filed again by **完成** or by the cluster's **开始新对局**.
- Verify the threefold notice, **继续对局**, **以和棋结束**, and retained non-blocking **可判和** affordance in both play modes.
- Verify manual replay navigation and single-speed autoplay, including animation completion, manual-navigation pause, board-flip pause, background pause, end-of-game stop, and Reduce Motion behavior.
- Verify pinned-first and newest-within-group History ordering, mixed-game rows whose metadata begins with game identity, read-only game content, one-game import and export, duplicate navigation, conflict rejection, and the absence of Move, folders, bulk deletion, search, filters, tags, game grouping, and game editing.
- Verify that the History row's date and time are produced without the app writing a date or time pattern, so the 12- or 24-hour clock follows the locale and the reader's own system setting. This one fails silently — a hand-written pattern looks right on the machine it was written on — and is cheap to gate.
- Verify that the row omits the human side in Free Play and omits the end reason exactly where the result word already carries it, and that a resignation keeps its reason.
- Verify partial and complete leading and trailing swipes, action order, icon-and-text labels, Share and Delete colors, immediate Pin or Unpin, full-swipe Delete, and pointer, keyboard, and VoiceOver equivalents.
- Verify **删除前确认** defaults on and governs every Delete entry point — the visible action, the complete swipe, the context menu, the keyboard, and the screen-reader custom action. Test the accepted confirmation copy, Cancel, confirmed deletion, immediate deletion when disabled, persistence failure, and the absence of deletion Undo or Recently Deleted.
- Verify the accepted insufficient-memory title, message, Cancel, and Retry actions. Cancel creates or changes no active game; Retry obtains a fresh budget without automatic cleanup or a smaller Hash.

### Rules

- Run the approved conformance fixtures in `fixtures/rules/` for movement, general safety, check, mate, stalemate, repetition, perpetual check, and perpetual chase — each under the ruleset it declares, both games in one run.
- Verify every ply's legal set, resulting position, check state, and final result where applicable.
- Verify that the custom variant has no move-count draw, that Xiangqi's draws at the hundredth capture-free ply and not earlier, and that both recognize the neutral draw outcome on the third occurrence for search.
- Verify that the app-visible rules boundary exposes claim eligibility on that occurrence, continuing keeps the game active, and only an explicit claim commits the draw.
- Verify that a unilateral perpetual violation becomes terminal automatically at the third sustained occurrence, is attributed to the violating side, and is presented through the standard natural-result flow rather than a claim.
- Verify unilateral perpetual-check loss, unilateral perpetual-chase loss, mutual same-class draw, check-versus-chase precedence, and general and soldier chase-target exclusion.
- Verify the accepted interpretations: a side alternating check and chase commits neither violation and reaches a neutral claimable repetition; a chase renews when the chasing piece attacks the target from the square it now occupies having not attacked it from that square before, so that stepping away from a target while still attacking it renews while advancing toward it along an existing line does not; and a chase whose target's only defender is a general is adjudicated on the flying-generals condition alone, degrading to a claimable repetition rather than a loss.
- Verify adjudication does not depend on side-to-move parity: enter one repeating sequence by a quiet move from each side in turn, and confirm the same verdict at the same occurrence, including that a mutual perpetual chase is a draw rather than a loss for the side that did not enter it.
- Verify check outranks chase unconditionally, including when the checking side is also chasing and when both sides are chasing.
- Run the same accepted history fixtures against the app-visible adjudicator and the engine search configuration. The engine may use a terminal or draw-valued representation for search while the app exposes a claim, but position identity, repetition occurrence, and draw classification must agree, and an engine search result must not auto-commit the app-visible draw.
- Add a minimized failing fixture before changing an accepted rule interpretation.

### Game data

- Test the single-active-game invariant, automatic state-derived classification, atomic old-game archive-and-clear operation, and separate later game creation from both pre-start states.
- Verify that neither pre-start state creates store or archive data, changes the active-game reference, or survives leaving or app termination.
- Save each durable transition, reopen the store, and verify exact resume state.
- Test repeated Free Play undo by ply and repeated human-versus-AI undo by decision cycle, including cancellation while the AI is thinking.
- Verify that undo persists only the retained main line, provides no redo, and remains available after a natural result only until result confirmation or successful **保存并继续**.
- Test persistence and relaunch of an active game whose current history makes a neutral repetition draw claimable, plus the transition from claimable active game to immutable draw record.
- Test pin-state persistence, History sorting, replay, permanent deletion, deletion failure rollback, ended-early records, confirmed resignation, and immutable game content.
- Test that a store or an archive recording any version but the defined one is refused, and that nothing migrates it: one version is defined on each axis, per [game-data.md](game-data.md), and a test that named an older shape would be the only thing in the repository that did.
- Round-trip exported files across iOS, iPadOS, macOS, and Windows.
- Verify the same game's canonical content bytes and content hash are byte-identical across platforms, and that export, import, and re-export reproduce identical canonical content.
- Verify the store's schema-enforced invariants directly: History content immutability outside pin state, the single active game, archive-and-clear ordering, and the result vocabulary constraints.
- Test a failed per-move commit: the move does not occur, the game remains at the pre-move committed state, and the accepted brief save-failure feedback appears.
- Test every import limit boundary and each rejection class, including the distinct created-by-a-newer-version message for unsupported archive versions.
- Verify that one-file, one-game import always creates immutable History and never creates or replaces the active game.
- Return the existing record for the same stable identity and game content. Reject the same identity with different content, plus oversized, malformed, unsupported, inconsistent, and partially valid imports, without partial persistence.

### Engine integration

- Verify initialization, capability checks, option application, legal proposed moves, cancellation, teardown, and stale-result rejection.
- Test missing, corrupted, incompatible, and incorrectly named engine or NNUE assets.
- Verify the configured NNUE fingerprint and positive load signal before search; a filename alone is not sufficient.
- Verify **快速**, **标准**, and **深思** use `go movetime 1000`, `go movetime 3000`, and `go movetime 5000`, respectively, and that **标准** is the new-install default.
- Verify every level applies the accepted shared search profile and differs only in `go movetime`.
- Verify the applied `Threads` value equals the active processor count reported by the device at engine initialization.
- Test the accepted Hash budget at and around the 4 GiB cap, 50%-of-physical-memory boundary, 20%-or-128-MiB reserve boundary, 64 MiB rounding boundary, and 256 MiB minimum.
- Record and verify the actual UCI Hash value applied on each representative device. Test a zero probe value, a rounded budget below 256 MiB, exactly 256 MiB, allocation failure, and operation without the increased-memory entitlement.
- Verify each platform's memory probe — `os_proc_available_memory()` on iOS and iPadOS, and the selected system-availability probes on macOS and Windows — against the accepted budget boundaries on real hardware.
- Below the minimum, verify that the engine is not initialized, no smaller Hash or special automatic cleanup is attempted, and Retry uses a fresh available-memory value.
- Compare engine behavior with accepted rules fixtures wherever search consumes terminal adjudication.
- Measure whole-game playing behavior, latency, memory, energy, and thermal behavior of the accepted 1-, 3-, and 5-second profiles on representative supported devices. Any retuning is an explicit later product decision rather than an automatic response to diagnostic NPS or depth.
- Verify that the app remains functional when increased memory is unavailable and treats `os_proc_available_memory()` as changing advisory information rather than a target to consume.
- Verify that the platform's suspension signal — scene backgrounding on iOS and iPadOS, sleep, termination, or memory pressure on macOS and Windows — cancels any search and releases the transposition table, and that merely losing window focus on macOS or Windows does not.
- Verify a result from a search cancelled that way is discarded as a superseded request, since no mutation occurred and the position revision still matches.
- Verify the engine is re-prepared only when a search is owed, and not on resuming replay, Free Play, a confirmed result, a game awaiting the user's move, or no active game at all.
- Verify suspension during an in-flight game creation invalidates the attempt, releases anything prepared, creates no game, and prevents a late completion from committing.
- Verify that re-preparation can fail, leaving the game active, saved, and resumable with the AI unable to move.
- Verify a memory-pressure notification takes the same cancel-and-release path and never shrinks Hash in place.
- Verify the preparation ordering prepare → resolve → create → search at each failure point: a preparation failure creates nothing and resolves no Random side; a persistence failure releases the prepared engine and creates nothing; and leaving mid-attempt invalidates it and prevents a late completion from committing.
- Verify that an allocation failure at a budget of at least 256 MiB presents the accepted **无法启动 AI 对手** notice unchanged, that Retry re-probes and recalculates, and that no smaller Hash is substituted.
- Verify that a missing or hash-mismatched network prevents the AI from starting with no fallback to a different evaluation, that the failure is detected during preparation rather than by the engine's own fatal path, and that Free Play, History, replay, import, and export still work.
- Verify the build fails rather than packaging when any hash in `pinned-inputs.json` does not match, and that the packaged engine artifact is the static library built from the pinned revision and flags.
- Verify the variant `minixiangqiaxf` and built-in `minixiangqi` can both be selected in one build, and that `minixiangqiaxf` and built-in `xiangqi` — the two the product plays — can be configured one after the other in one process, in both directions and with no teardown between.
- Verify the engine's effective NNUE state is on after configuration, not merely that the network file exists — a basename that does not begin with the variant identifier disables NNUE silently and the engine plays on classical evaluation.
- Verify the complete approved fixture set passes against the pinned fork build named in `pinned-inputs.json`, and that the fork's own suite still passes, before that revision is packaged.

### UI, accessibility, sound, and haptics

- Test VoiceOver labels, values, actions, order, and an end-to-end nonvisual board interaction.
- Test keyboard and pointer behavior where supported.
- Test Increase Contrast, Differentiate Without Color, Reduce Motion, and Reduce Transparency.
- Verify that sound, haptics, color, motion, and visual effects are never the sole carrier of required information.
- Verify all fourteen accepted piece characters resolve to the same Chinese font family as one another at every weight used, with matching advance widths and no per-character size compensation, on each supported platform.
- Verify that Red and Black remain distinguishable without color in every accepted piece style, with each symbol set, in light and dark appearance and under Increase Contrast.
- Verify all seven icons are unmistakable from one another at both games' smallest supported pitch, with particular attention to chariot against cannon and to the new advisor and elephant.
- Measure each style's three contrast requirements against their stated minimums — symbol against its disc face, disc boundary against that style's own board surface, and the side-carrying channel — in normal viewing and again with resting shadows removed, confirming no style depends on a shadow.
- Verify a held piece still reads as raised under Reduce Motion, and that no piece style suppresses the lift.
- Verify the capture ring stays distinguishable from any ring belonging to the selected piece style.
- Verify the illegal-square haptic uses the lightest selection-weight feedback, is distinguishable from the save-failure warning, and that Undo transitions complete within their accepted durations.
- Once a second piece style exists and the preference with it, verify that the piece-style preference persists, applies immediately, and changes presentation only, leaving game content, archives, and notation identical across styles.
- Verify every Settings preference persists in the platform's own preference system and survives relaunch, that none is written to the shared store, and that changing one never alters an active game or any History record.
- Verify a game created from the pre-start draft freezes the first-mover choice and AI level supplied at creation, and that changing either Settings default afterwards leaves the created and archived game untouched.
- Verify the app follows the operating system's language selection, including through an Apple per-app language change, and that it offers no interface-language control of its own.
- Run the localization evidence [copy.md](copy.md) § The localization process requires: the Double-Length and Bounded String pseudolanguage passes, the smoke flows in both Simplified Chinese and English, and the mechanical check that the copy contract and the String Catalog agree in both languages.
- Verify the sound, haptics, and piece-symbols settings persist, take effect immediately, and that the haptics setting is unavailable rather than inert on hardware without haptics.
- Verify the grid and palace diagonals are stroked identically, that the outer boundary is a single line, and that both reach 3:1 against each style's board surface. Verify Mini Xiangqi has no river and Xiangqi interrupts only the inner file lines between ranks 5 and 6.
- Verify both numeral strips are present with seven entries per edge in Mini Xiangqi and nine in Xiangqi, that each faces the player whose numerals it shows, that they follow orientation, share a baseline and weight, and reach 4.5:1 against the board surface and 7:1 under Increase Contrast.
- Verify both numeral strips are shown together or hidden together, that they are hidden at accessibility text sizes, and that the layout still satisfies its accepted bounds when they are.
- Verify the AI's piece departs no earlier than the compose-beat floor after the player's move has finished animating, including after a capture, that a slower search is unaffected, and that AI activity appears only once the search passes the accepted threshold.
- Verify input arriving during a committing transition is discarded rather than queued, that presentational transitions re-target, and that a board flip requested mid-transition is applied afterwards.
- Verify Reduce Motion replaces position, scale and rotation with a crossfade while leaving opacity, colour, stroke and shadow animations, ordering, and every state intact, and confirm specifically that the check pulse is removed while the check rings, the 将军 token, and the illegal-tap response all still deliver their states without animation.
- Verify feedback reporting an event fires when the event completes, and that feedback answering a touch — selection, an illegal tap, refused input, a failed save — leads the animation drawn in reply.
- Verify no tinted glass appears during play, and that at most one tinted element is visible in any state.
- Verify each custom glass surface under Reduce Transparency, Increase Contrast, both together, and dark appearance, confirming that the surface's material and border change while its position and size never do.
- Verify each board is drawn as intersections with outer points on its border lines, 49 points for Mini Xiangqi and 90 for Xiangqi. Palace diagonals meet at the palace centre at grid stroke weight; Mini's grid is unbroken, Xiangqi's river breaks only the inner file lines; no starting points are marked and edge discs are never clipped.
- Verify every board marker — legal-move dot, capture ring, last-move markers, and check treatment — stays legible against each style's own board surface.
- Verify the board-metric rules on a rendered board: no piece style's decoration touches the marker band, no game-state marker's ink touches a disc face at the disc's largest, and no marker leaves its own cell at rest or at any moment of its animation. A dragged piece is exempt only while dragged.
- Verify no resident surface intersects the board block, that a user-summoned sheet may cover it, and that the natural-result notice may stand in front of the board, leaving the position undimmed beneath it and fully visible the moment it is put away.
- Verify each style's marker ink meets both accepted strengths — active at 4.5:1 and record at 3:1 — against that style's own board surface, with shadows excluded, in light and dark appearance, and that record ink is promoted to active values under Increase Contrast. **The second measurement, against the pointer hover fill composited over that surface, is Windows's alone**, because the fill is: a platform that draws no hover fill has no composite to measure against.
- Verify every game-state marker renders identically with Differentiate Without Color enabled and disabled, the keyboard focus ring excepted.
- Verify an illegal tap and an invalid drop draw no board mark: with a piece selected the legal destinations pulse once and the selection survives, and with nothing selected the turn status beats instead.
- Verify the illegal-tap response survives Reduce Motion as a single non-animated state change of the legal destinations, and confirm it on a Mac, where no haptic exists to carry it.
- Verify the per-ply save-failure capsule shows **无法保存这一步，请重试。** for a failed user move or Undo only, that no capsule appears when the failed save is the AI's reply, and that a failed draw claim, resignation, or result confirmation uses the **无法保存对局** presentation instead.
- Verify the board is never dimmed while the AI is thinking or after a result is confirmed, and that a tap on a replay board produces no visual or haptic response at all.
- Verify the **将军** token is present during play for exactly as long as the side to move is in check, and absent in replay, where there is no side-to-move line. Verify the check rings hide while a checked general is selected or dragged and return when it is released, including after an abandoned drag, and that they are therefore always visible in replay.
- Verify last-move brackets mark the move that produced the position on screen: they follow an Undo to the move that is now last rather than remaining on the discarded one, they move with each step of replay navigation in both directions, and no brackets appear at an initial position.
- Verify that the piece-style, piece-symbols, and user-visible-notation choices change presentation only: game content, archives, and canonical notation are unaffected, and History records are identical whichever is selected.
- Verify traditional notation against the approved clause table carried by `MoveNotationTests`, covering both games' seven or nine files; each side's own numerals; 进 and 退 carrying a rank count for chariot, cannon, soldier and general but a destination file for horse, advisor and elephant; the existing tandem forms; captures; and moves involving rank 10. A notation change that no clause catches is a missing clause.
- Verify WXF against `WXFNotationTests`, covering K, A, E, R, H, C and P; files 1–7 in Mini Xiangqi and 1–9 in Xiangqi from each side's own right; the existing direction, value, tandem, indexed and capture clauses; both sides' frames; and rank-10 moves. The only tolerated Fairy-Stockfish divergence remains the recorded unconditional-marker class.
- Verify the numeral strips follow the notation preference and game: both edges Arabic with WXF selected, Red's Chinese with 中文, each side numbering from its own right, seven entries for Mini Xiangqi and nine for Xiangqi, with equal visual weight.
- Verify unavailable hardware and muted-audio behavior.

## Build and distribution gates

A distribution candidate — TestFlight on Apple platforms, or the Windows zip or Store package — requires:

- successful builds for every supported configuration on the distributed platform, which on Windows means **both architectures**, since each is a separate artifact that a separate machine runs;
- passing shared-core tests plus targeted unit, integration, persistence, import and export, rules, engine, and critical UI tests;
- no unresolved data-loss, illegal-move, rules-result, engine-termination, or migration failure;
- verified GPLv3 and license inputs, carried in the artifact where the artifact is one somebody is handed: the Windows zip contains the project's own `LICENSE` and a notice naming Fairy-Stockfish with the pinned fork revision, SQLite's public-domain dedication, the Microsoft redistributables it carries, and — not a third-party input, and named there because it is where a reader looks for it — the neural network, with its filename, byte length, SHA-256 and the pipeline revision that produced it. **The Store package is a distribution under this same clause and carries the same two documents**, generated by the same script from the same manifest; only the sentence about which Microsoft runtime is installed rather than carried differs between them, and "the Microsoft redistributables it carries" is read against what the package actually holds;
- **the bundled network's verified pinned hash, in every distribution without exception**, so that an absent network is damage rather than a case a recipient has instructions for;
- for the Windows zip, a run of the headless harness against the **unpacked zip exactly as produced**, with nothing added to it, rather than against the build tree the zip was made from;
- manual smoke testing of new game, resume, undo, end, history replay, deletion, export, import, and settings on each distributed platform.

## Thresholds not yet set

These are named so a reader knows the gate above is incomplete, not to authorize a value:

- performance, memory, energy, and thermal thresholds for each AI profile;
- how the accepted import validation time budget is measured and enforced on each platform;
- which evidence a distribution candidate must retain, and which critical flows require UI automation rather than structured manual review;
- the physical-device matrix a candidate must be exercised on. The simulator pair and the macOS host are settled above; on Windows, `ARM64` exists on a machine that runs the product and does not build it, so what a candidate is exercised on there is the artifact rather than a build tree.
