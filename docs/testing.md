# Testing

This document is for engineers, reviewers, and internal release testers who need to know which evidence is required for a Mini Xiangqi change or build. It owns durable validation categories, fixture expectations, and release gates. It does not record individual run results, implementation progress, temporary experiments, or work status; those belong in CI artifacts and GitHub Issues.

> **Status: Draft validation proposal.** Nothing in this document is normative until its status or an individual section is explicitly marked accepted. Add exact commands and thresholds only after they have been verified with the required toolchains and representative devices. Items under **Need to discuss** are non-normative.

## Required toolchain

### Apple targets

- Xcode 27 beta at `/Applications/Xcode-beta.app`.
- Developer directory: `/Applications/Xcode-beta.app/Contents/Developer`.
- Expected build: `27A5228h`.
- Swift 6.
- iOS, iPadOS, and macOS 26.5 targets.
- Apple-silicon macOS; `x86_64` is not supported on macOS.

Every Apple validation session begins by checking:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -version
```

Do not change global `xcode-select`, and do not silently validate with another Xcode.

### Shared core and Windows targets

- The shared core builds and its tests run on every development platform without a frontend.
- The core's Windows compiler is pinned in `pinned-inputs.json`, established by a build that produced it: Visual Studio 2026 Community with the MSVC v14.51 toolset and the Windows 11 SDK, on `x64`. The frontend's half of that toolchain — Windows App SDK version, .NET version, and the packaging flags — is still unpinned draft state and must be pinned and verified before any Windows *frontend* or packaging validation claim. Core validation claims on Windows are now available, and the entry below records what was run.
- GitHub Actions CI is the recommended place for long or multi-platform builds and test runs, with pinned inputs; CI results supplement, and do not replace, the release gates below.
- `.github/workflows/core-suites.yml` is that CI: the core suites in both configurations, on a pinned macOS runner and a pinned Windows runner. It runs the GitHub-hosted Windows toolchain rather than the pinned one — Visual Studio 2022 on the `windows-2025` image, against Visual Studio 2026 on the machine the pin was measured on — so what it proves is that the core compiles and passes under both, not that it reproduces the pinned build. Reproducing the pin is a developer-machine claim.

## Validation principles

- Select tests from the contract changed, not only from the files edited.
- Keep rules, domain, persistence, engine, and UI tests independently runnable where practical.
- Prefer deterministic, behavior-focused fixtures over snapshots of incidental implementation details.
- Report exact commands, environment, results, and anything not run.
- Keep raw logs, measurements, and historical run results outside this document.

## Change-to-validation expectations

### Shared core

- Core changes run the core test suite — rules fixtures, archive codec, library store, and search facade — on at least one Apple platform and on Windows.
- Run that suite in **both** a debug and a release configuration. Neither is a superset of the other: the programming errors in `docs/core-interface.md`'s error taxonomy assert where `NDEBUG` is undefined and return their code where it is defined, so a release run is the only one that can observe those codes and a debug run is the only one that exercises the assertions — and the vendored engine's own assertions are live only in the first.
- Verify the one shared core test runner executes the approved fixtures identically on every development platform, without a frontend.
- Store changes verify the transactional invariants: single active game, atomic archive-and-clear, no partial import, and deletion rollback.
- Archive changes verify cross-platform round-trips and version dispatch, including rejection of unsupported versions.
- C-interface changes verify both platform bindings against the threading and error contract in `docs/core-interface.md`.

### Product and interaction

- Review affected product and interaction contracts.
- Exercise the complete affected user flow on the smallest relevant iPhone layout, an iPad layout, and a supported macOS window size.
- Verify iPhone stays in portrait when rotated and shows no orientation prompt, while iPad adapts to every orientation and to full-screen and windowed sizes including the system tiling configurations.
- Verify both the layout shape and the navigation presentation are selected by available width rather than device identity, so a resized macOS window and a windowed iPad reach the same arrangement at the same width, and that one navigation container serves all three platforms.
- Verify the board fits both the available width and the remaining height at every supported size, never overflowing a short window.
- Verify a grid point stays at or above 44 points on every platform, that chrome tightens before the board does, and that each platform's minimum window size prevents either from falling below its floor. Include a Mac at its largest-text display setting, where the window budget is smallest.
- Verify the pre-start preview shrinks as needed so the setup controls always fit, including when a creation-failure error is shown.
- Verify no captured-piece display appears in either layout shape.
- Verify the play controls are 悔棋 · 判和 · 认输 in human-versus-AI with no flip control, 悔棋 · 判和 · 翻转棋盘 in Free Play, and the transport plus 翻转棋盘 in replay. What bounds the play cluster is judgement rather than a count — small and calm, neither crowding the screen nor reading strangely — and it is judged from a rendered screen; replay's transport is not part of it.
- Verify 认输 presents 认输？ / 认输后本局将记为你落败。 with 取消 and 认输; that confirming records a human loss and an immutable History record; that cancelling changes nothing; and that it is absent in Free Play and replay.
- Verify the board core stops growing at 720 points and that surplus space goes to the surrounding layout.
- Verify the move list is permanently visible in the side-by-side layout and reachable on demand in the stacked layout, without either the board or the controls losing space by default.
- Inspect light and dark appearances, text expansion, interruption, error, and destructive-action states.
- Verify that a new installation defaults to **我先手** and **标准**, while Settings can persist **AI 先手**, **随机**, and any accepted AI level as later setup defaults.
- Verify that entering human-versus-AI setup creates a fresh in-memory draft, per-game changes never update Settings, leaving discards the draft, and reopening reloads current Settings defaults.
- Verify that the setup board is a noninteractive preview, no active game or resolved Random side exists before **开始对局**, and the created game freezes the resolved side, level identifier, and exact `movetime`. Random previews Red at the bottom and flips only after successful creation resolves to **AI 先手**.
- Verify that the Play destination's root is the Play home: no board anywhere on it, the game's ways to play as one section, and — with an active game — a **当前对局** card carrying that game's metadata and a **回到对局** that opens the board on the game exactly as it was left. Verify that a launch with a game to resume opens at the board rather than at the home, that leaving the board for the home ends nothing, and that a game already filed is not described as a current game.
- With any active game, verify that tapping either **Human versus AI** or **Free Play** remains available and immediately presents the same save-and-continue confirmation with factual old-game metadata. Cover every old-mode and new-mode combination, an ordinary ongoing game, a claimable but unclaimed neutral repetition, and an unconfirmed natural terminal result.
- Verify the exact fixed copy: **开始新对局？**, metadata header **当前对局**, **这盘对局将按当前状态保存到历史。**, **取消**, and **保存并继续**. Verify that only metadata changes and that no separate Undo or draw-claim action appears in this confirmation.
- Verify factual metadata for mode, human side when applicable, ongoing side to move or terminal result and reason, claim availability, and move count.
- Verify automatic classification: an ordinary ongoing game is saved as ended early without a competitive result; an unclaimed claimable repetition is also saved as ended early rather than as a draw; and an unconfirmed natural terminal game retains its actual result and exact termination reason.
- Verify that Cancel discards the temporarily selected destination, preserves the active game exactly, and leaves its normal Undo or draw-claim controls available.
- Verify that both modes open a pre-start state and create no active game before **开始对局**. Free Play uses a noninteractive, Red-bottom preview with no turn status, shows **你将控制红黑双方，红方先行。**, and presents no configurable setup fields.
- After successful **保存并继续**, verify that leaving either pre-start state creates no game and the old game remains immutable History.
- Verify that a failed archive-and-clear operation presents **无法保存对局**, **当前对局仍然保留。请重试。**, **取消**, and **重试**; preserves the old active game; creates no new game; and never enters a pre-start state. Verify Retry repeats the atomic operation and Cancel discards the temporary destination.
- Verify that insufficient AI resources, AI unavailability, and active-game persistence failures create no game or persistent game-library change. The pre-start state remains retryable, and a human-versus-AI Random choice remains unresolved.
- Test double **开始对局**, leaving while creation is in progress, and late completion for both modes. Only one current setup-session request may commit; leaving invalidates it and creates no game.
- Verify the turn-status matrix for Red and Black, human and AI ownership, AI thinking, Free Play, unavailable input, and replay progress.
- Verify the natural-result notice before and after saving, including **保存**, **保存并开始新对局**, **回放**, **完成**, the absence of **悔棋** on the notice and its presence in the cluster, and the absence of a Play Again action. Verify it is dismissible by its own close control, by the cancel key, and by a click on the board; that closing it decides nothing, leaving the result on the turn status, Undo available while the result is unconfirmed, and the concluding action in the cluster; and that it does not present itself again for the same result. Verify that a game already filed is not filed again by **完成** or by the cluster's **开始新对局**.
- Verify the threefold notice, **继续对局**, **以和棋结束**, and retained non-blocking **可判和** affordance in both play modes.
- Verify manual replay navigation and autoplay at 0.5×, 1×, and 2×, including animation completion, manual-navigation pause, board-flip pause, background pause, end-of-game stop, and Reduce Motion behavior.
- Verify pinned-first and newest-within-group History ordering, accepted row metadata, read-only game content, one-game import/export, duplicate navigation, conflict rejection, and the absence of Move, folders, bulk deletion, search, filters, tags, and game editing.
- Verify that the History row's date and time are produced without the app writing a date or time pattern, so the 12- or 24-hour clock follows the locale and the reader's own system setting. This one fails silently — a hand-written pattern looks right on the machine it was written on — and is cheap to gate.
- Verify that the row omits the human side in Free Play and omits the end reason exactly where the result word already carries it, and that a resignation keeps its reason.
- Verify partial and complete leading and trailing swipes, action order, icon-and-text labels, Share and Delete colors, immediate Pin or Unpin, full-swipe Delete, and pointer, keyboard, and VoiceOver equivalents.
- Verify **删除前确认** defaults on and governs every Delete entry point — the visible action, the complete swipe, the context menu, the keyboard, and the screen-reader custom action. Test the accepted confirmation copy, Cancel, confirmed deletion, immediate deletion when disabled, persistence failure, and the absence of deletion Undo or Recently Deleted.
- Verify the accepted insufficient-memory title, message, Cancel, and Retry actions. Cancel creates or changes no active game; Retry obtains a fresh budget without automatic cleanup or a smaller Hash.

### Rules

- Run the approved conformance fixtures in `fixtures/rules/` for movement, general safety, check, mate, stalemate, repetition, perpetual check, and perpetual chase.
- Verify every ply's legal set, resulting position, check state, and final result where applicable.
- Verify that the target custom variant has no move-count draw and recognizes the neutral draw outcome on the third occurrence for search.
- Verify that the app-visible rules boundary exposes claim eligibility on that occurrence, continuing keeps the game active, and only an explicit claim commits the draw.
- Verify that a unilateral perpetual violation becomes terminal automatically at the third sustained occurrence, is attributed to the violating side, and is presented through the standard natural-result flow rather than a claim.
- Verify unilateral perpetual-check loss, unilateral perpetual-chase loss, mutual same-class draw, check-versus-chase precedence, and king and soldier chase-target exclusion.
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
- Test every released database schema migration and archive-format migration from file-backed fixtures.
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
- Verify each platform's memory probe: `os_proc_available_memory()` on iOS and iPadOS, and the selected system-availability probes on macOS and Windows.
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
- Verify each platform's memory probe against the accepted budget boundaries on real hardware.
- Verify the build fails rather than packaging when any hash in `pinned-inputs.json` does not match, and that the packaged engine artifact is the static library built from the pinned revision and flags.
- Verify the target variant `minixiangqiaxf` and built-in `minixiangqi` can both be selected in one build.
- Verify the engine's effective NNUE state is on after configuration, not merely that the network file exists — a basename that does not begin with the variant identifier disables NNUE silently and the engine plays on classical evaluation.
- Verify the complete approved fixture set passes against the pinned fork build named in `pinned-inputs.json`, and that the fork's own suite still passes, before that revision is packaged.

### UI, accessibility, sound, and haptics

- Test VoiceOver labels, values, actions, order, and an end-to-end nonvisual board interaction.
- Test keyboard and pointer behavior where supported.
- Test Increase Contrast, Differentiate Without Color, Reduce Motion, and Reduce Transparency.
- Verify that sound, haptics, color, motion, and visual effects are never the sole carrier of required information.
- Verify the accepted piece characters all resolve to the same Chinese font family as one another at every weight used, with matching advance widths and no per-character size compensation, on each supported platform.
- Verify that Red and Black remain distinguishable without color in every accepted piece style, with each symbol set, in light and dark appearance and under Increase Contrast.
- Verify every icon is unmistakable from every other at the smallest supported board size, with particular attention to chariot against cannon.
- Measure each style's three contrast requirements against their stated minimums — symbol against its disc face, disc boundary against that style's own board surface, and the side-carrying channel — in normal viewing and again with resting shadows removed, confirming no style depends on a shadow.
- Verify a held piece still reads as raised under Reduce Motion, and that no piece style suppresses the lift.
- Verify the capture ring stays distinguishable from any ring belonging to the selected piece style.
- Verify the illegal-square haptic uses the lightest selection-weight feedback, is distinguishable from the save-failure warning, and that Undo transitions complete within their accepted durations.
- *(Waits with the preference itself — deferred to the post-Windows appearance pass, owner 2026-07-28/29, since a preference with one option is not a preference.)* Verify the piece-style preference persists, applies immediately, and changes presentation only, leaving game content, archives, and notation identical across styles.
- Verify every Settings preference persists in the platform's own preference system and survives relaunch, that none is written to the shared store, and that changing one never alters an active game or any History record.
- Verify a game created from the pre-start draft freezes the first-mover choice and AI level supplied at creation, and that changing either Settings default afterwards leaves the created and archived game untouched.
- Verify the app follows the operating system's language selection, including through an Apple per-app language change, and that it offers no interface-language control of its own.
- Run the localization evidence that [copy.md](copy.md) § The localization process requires: the Double-Length and Bounded String pseudolanguage passes, the smoke flows in both Simplified Chinese and English, and — once the CI workflows below exist — the mechanical check that the copy contract and the String Catalog agree in both languages.
- Verify the sound, haptics, and piece-symbols settings persist, take effect immediately, and that the haptics setting is unavailable rather than inert on hardware without haptics.
- Verify the grid and palace diagonals are stroked identically, that the outer boundary is a single line, and that both reach 3:1 against each style's board surface.
- Verify both numeral strips are present, that each faces the player whose numerals it shows, that they follow the board's orientation, that the two sets share a baseline and read as equal in weight, and that every numeral reaches 4.5:1 against the board surface and 7:1 under Increase Contrast.
- Verify both numeral strips are shown together or hidden together, that they are hidden at accessibility text sizes, and that the layout still satisfies its accepted bounds when they are.
- Verify the AI's piece departs no earlier than the compose-beat floor after the player's move has finished animating, including after a capture, that a slower search is unaffected, and that AI activity appears only once the search passes the accepted threshold.
- Verify input arriving during a committing transition is discarded rather than queued, that presentational transitions re-target, and that a board flip requested mid-transition is applied afterwards.
- Verify Reduce Motion replaces position, scale and rotation with a crossfade while leaving opacity, colour, stroke and shadow animations, ordering, and every state intact, and confirm specifically that the check pulse is removed while the check rings, the 将军 token, and the illegal-tap response all still deliver their states without animation.
- Verify feedback reporting an event fires when the event completes, and that feedback answering a touch — selection, an illegal tap, refused input, a failed save — leads the animation drawn in reply.
- Verify no tinted glass appears during play, and that at most one tinted element is visible in any state.
- Verify each custom glass surface under Reduce Transparency, Increase Contrast, both together, and dark appearance, confirming that the surface's material and border change while its position and size never do.
- Verify the board is drawn as intersections with the outer points on the border lines, the palace diagonals meet at the palace centre at grid stroke weight, the grid is unbroken across the middle of the board, no starting points are marked, and edge discs are never clipped.
- Verify every board marker — legal-move dot, capture ring, last-move markers, and check treatment — stays legible against each style's own board surface.
- Verify the board-metric rules on a rendered board: no piece style's decoration touches the marker band, no game-state marker's ink touches a disc face at the disc's largest, and no marker leaves its own cell at rest or at any moment of its animation. A dragged piece is exempt only while dragged.
- Verify no resident surface intersects the board block, that a user-summoned sheet may cover it, and that the natural-result notice may stand in front of the board, leaving the position undimmed beneath it and fully visible the moment it is put away.
- Verify each style's marker ink meets both accepted strengths — active at 4.5:1 and record at 3:1 — against that style's own board surface and against the pointer hover fill composited over it, with shadows excluded, in light and dark appearance, and that record ink is promoted to active values under Increase Contrast.
- Verify every game-state marker renders identically with Differentiate Without Color enabled and disabled, the keyboard focus ring excepted.
- Verify an illegal tap and an invalid drop draw no board mark: with a piece selected the legal destinations pulse once and the selection survives, and with nothing selected the turn status beats instead.
- Verify the illegal-tap response survives Reduce Motion as a single non-animated state change of the legal destinations, and confirm it on a Mac, where no haptic exists to carry it.
- Verify the per-ply save-failure capsule shows **无法保存这一步，请重试。** for a failed user move or Undo only, that no capsule appears when the failed save is the AI's reply, and that a failed draw claim, resignation, or result confirmation uses the **无法保存对局** presentation instead.
- Verify the board is never dimmed while the AI is thinking or after a result is confirmed, and that a tap on a replay board produces no visual or haptic response at all.
- Verify the **将军** token is present during play for exactly as long as the side to move is in check, and absent in replay, where there is no side-to-move line. Verify the check rings hide while a checked general is selected or dragged and return when it is released, including after an abandoned drag, and that they are therefore always visible in replay.
- Verify last-move brackets mark the move that produced the position on screen: they follow an Undo to the move that is now last rather than remaining on the discarded one, they move with each step of replay navigation in both directions, and no brackets appear at an initial position.
- Verify that the piece-style, piece-symbols, and user-visible-notation choices change presentation only: game content, archives, and canonical notation are unaffected, and History records are identical whichever is selected.
- Verify traditional notation against the approved clause table carried by `MoveNotationTests`, covering: file numbering from each side's own right; each side's own numerals used for every number, with the four-or-more ordinal — Chinese for both sides — as the one exception; 进 and 退 carrying a rank count for the chariot, cannon, soldier, and general but a destination file for the horse; 平 carrying a destination file; 前 or 后 leading the move without a file for two on a file; 前, 中, and 后 for three; 一 to 五 from the front for four or more; the origin file returning after the piece name when more than one file is doubled; and a capture rendering exactly as the quiet move would. That table is the oracle, accepted 2026-07-28: it distils the Part 6 research table — 110 rows over 24 positions, every row engine-checked (`research/p6-notation-oracle.md` §7 on `archive/design-research`) — to one assertion per clause, and a notation change that no clause catches is a missing clause, since the fixtures record only canonical coordinates.
- Verify the WXF rendering against the approved clause table carried by `WXFNotationTests`, covering: the letters K, R, H, C and P for both sides alike; files numbered 1 to 7 from each side's own right in Arabic numerals for both sides; `+`, `-` and `=` for advance, retreat and traverse; a rank count when the move stays on its file and the destination file when it does not, which is the horse's value in both directions and the traverse value for the chariot, cannon, soldier and general, with the rank count checked at every distance a chariot can travel; `+` or `-` after the piece letter in place of the file for two of a type on one file, for chariots, horses, cannons and soldiers alike, including the case where the other piece of the pair could not make the same move and the marker is written anyway, and including a pair beside a lone single on a third file, which is one doubled file and therefore keeps the marker; the index from the front in place of the piece letter with the file kept, at three, four and five on a file and for every index; both files' soldiers indexed within their own file at 2-2 and 3-2 with a soldier elsewhere staying plain; a capture rendering exactly as the quiet move would; and a whole line read end to end whose last move is checkmate and carries no marker. Every clause about the front of a file is verified in both sides' frames, since front means nearer the opponent and the two sides therefore count from opposite ends of the same board. That table is the oracle, and it is also machine-checked: of its 145 rows, 141 render identically in Fairy-Stockfish, which emits WXF for this variant and implements the same indexed/marker/plain condition. The four that differ — two per side — are the unconditional-marker reading recorded in [interaction-design.md](interaction-design.md) § WXF rendering, the one class where the two are designed to disagree, and no divergence outside that class is tolerated.
- Verify the numeral strips follow the notation preference: both edges Arabic with WXF selected, Red's Chinese with 中文, each side numbering from its own right either way, and the two edges reading as equal in weight under both.
- Verify unavailable hardware and muted-audio behavior.

## Build and internal-distribution gates

An internal distribution candidate — TestFlight on Apple platforms, or the internal Windows package — requires:

- successful builds for every supported configuration on the distributed platform;
- passing shared-core tests plus targeted unit, integration, persistence, import/export, rules, engine, and critical UI tests;
- no unresolved data-loss, illegal-move, rules-result, engine-termination, or migration failure;
- verified GPLv3 and third-party source and license inputs, and the bundled network's verified pinned hash per the accepted NNUE handling policy;
- manual smoke testing of new game, resume, undo, end, history replay, deletion, export, import, and settings on each distributed platform.

## Need to discuss

> The following questions are non-normative and are not implementation requirements.

- Verify and record the exact simulator and macOS build/test commands.
- Select the supported simulator, physical-device, macOS, and Windows validation matrix.
- Pin the Windows *frontend* toolchain — Windows App SDK, .NET, packaging flags — and record verified packaging commands. The core's half is pinned and its commands are in the README.
- Decide which artifacts the GitHub Actions workflows retain. The workflows and their pinned inputs are defined in `.github/`; nothing is retained today beyond the run log.
- Define performance, memory, energy, and thermal thresholds for each AI profile.
- Define which critical flows require UI automation versus structured manual review.
- Define how the accepted import validation time budget is measured and enforced on each platform.
- Define which evidence must be retained for an internal distribution candidate.
