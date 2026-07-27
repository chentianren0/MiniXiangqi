# Testing

This document is for engineers, reviewers, and internal TestFlight release testers who need to know which evidence is required for a Mini Xiangqi change or build. It owns durable validation categories, fixture expectations, and release gates. It does not record individual run results, implementation progress, temporary experiments, or work status; those belong in CI artifacts and GitHub Issues.

> **Status: Draft validation proposal.** Nothing in this document is normative until its status or an individual section is explicitly marked accepted. Add exact commands and thresholds only after they have been verified with the required Xcode and representative devices. Items under **Need to discuss** are non-normative.

## Required toolchain

- Xcode 27 beta at `/Applications/Xcode-beta.app`.
- Developer directory: `/Applications/Xcode-beta.app/Contents/Developer`.
- Expected build: `27A5228h`.
- Swift 6.
- iOS, iPadOS, and macOS 26.5 targets.
- Apple-silicon macOS; `x86_64` is not supported.

Every validation session begins by checking:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -version
```

Do not change global `xcode-select`, and do not silently validate with another Xcode.

## Validation principles

- Select tests from the contract changed, not only from the files edited.
- Keep rules, domain, persistence, engine, and UI tests independently runnable where practical.
- Prefer deterministic, behavior-focused fixtures over snapshots of incidental implementation details.
- Report exact commands, environment, results, and anything not run.
- Keep raw logs, measurements, and historical run results outside this document.

## Change-to-validation expectations

### Product and interaction

- Review affected product and interaction contracts.
- Exercise the complete affected user flow on the smallest relevant iPhone layout, an iPad layout, and a supported macOS window size.
- Inspect light and dark appearances, text expansion, interruption, error, and destructive-action states.
- Verify that a new installation defaults to **我先手** and **标准**, while Settings can persist **AI 先手**, **随机**, and any accepted AI level as later setup defaults.
- Verify that entering human-versus-AI setup creates a fresh in-memory draft, per-game changes never update Settings, leaving discards the draft, and reopening reloads current Settings defaults.
- Verify that the setup board is a noninteractive preview, no active game or resolved Random side exists before **开始对局**, and the created game freezes the resolved side, level identifier, and exact `movetime`. Random previews Red at the bottom and flips only after successful creation resolves to **AI 先手**.
- With an active game, verify that tapping either **Human versus AI** or **Free Play** immediately presents the replacement confirmation with old-game metadata. Cancel preserves the active game; confirmation atomically records it as ended early before continuing.
- Verify the exact replacement copy: **结束未完成的对局？**, **继续后，上方显示的对局将提前结束并保存到历史。**, **取消**, and **结束并继续**.
- Verify that a natural result awaiting confirmation cannot enter replacement; the user must first select **悔棋** or **结束对局**.
- Verify that both modes open a pre-start state and create no active game before **开始对局**. Free Play uses a noninteractive, Red-bottom preview with no turn status, shows **你将控制红黑双方，红方先行。**, and presents no configurable setup fields.
- After confirmed replacement, verify that leaving either pre-start state creates no game and the old game remains immutable History.
- Verify that a failed archive-and-clear replacement preserves the old active game and never enters a pre-start state.
- Verify that insufficient AI resources, AI unavailability, and active-game persistence failures create no game or persistent game-library change. The pre-start state remains retryable, and a human-versus-AI Random choice remains unresolved.
- Test double **开始对局**, leaving while creation is in progress, and late completion for both modes. Only one current setup-session request may commit; leaving invalidates it and creates no game.
- Verify the turn-status matrix for Red and Black, human and AI ownership, AI thinking, Free Play, unavailable input, and replay progress.
- Verify the natural-result card before and after confirmation, including **悔棋**, **结束对局**, **回放**, **完成**, outside-dismissal rejection, and the absence of a Play Again action.
- Verify the threefold notice, **继续对局**, **以和棋结束**, and retained non-blocking **可判和** affordance in both play modes.
- Verify manual replay navigation and autoplay at 0.5×, 1×, and 2×, including animation completion, manual-navigation pause, board-flip pause, background pause, end-of-game stop, and Reduce Motion behavior.
- Verify pinned-first and newest-within-group History ordering, accepted row metadata, read-only game content, one-game import/export, duplicate navigation, conflict rejection, and the absence of Move, folders, bulk deletion, search, filters, tags, and game editing.
- Verify partial and complete leading and trailing swipes, action order, icon-and-text labels, Share and Delete colors, immediate Pin or Unpin, full-swipe Delete, and pointer, keyboard, and VoiceOver equivalents.
- Verify **删除前确认** defaults on and governs both the visible Delete action and complete swipe. Test the accepted confirmation copy, Cancel, confirmed deletion, immediate deletion when disabled, persistence failure, and the absence of deletion Undo or Recently Deleted.
- Verify the accepted insufficient-memory title, message, Cancel, and Retry actions. Cancel creates or changes no active game; Retry obtains a fresh budget without automatic cleanup or a smaller Hash.

### Rules

- Run approved conformance fixtures for movement, king safety, check, mate, stalemate, repetition, perpetual check, and perpetual chase.
- Verify every ply's legal set, resulting position, check state, and final result where applicable.
- Verify that the target custom variant has no move-count draw and recognizes the neutral draw outcome on the third occurrence for search.
- Verify that the app-visible rules boundary exposes claim eligibility on that occurrence, continuing keeps the game active, and only an explicit claim commits the draw.
- Verify unilateral perpetual-check loss, unilateral perpetual-chase loss, mutual same-class draw, check-versus-chase precedence, and king and soldier chase-target exclusion.
- Run the same accepted history fixtures against the app-visible adjudicator and the engine search configuration. The engine may use a terminal or draw-valued representation for search while the app exposes a claim, but position identity, repetition occurrence, and draw classification must agree, and an engine search result must not auto-commit the app-visible draw.
- Add a minimized failing fixture before changing an accepted rule interpretation.

### Game data

- Test the single-active-game invariant, atomic old-game end-and-clear operation, and separate later game creation from both pre-start states.
- Verify that neither pre-start state creates SwiftData model or archive data, changes `activeGame`, or survives leaving or app termination.
- Save each durable transition, recreate the container, and verify exact resume state.
- Test repeated Free Play undo by ply and repeated human-versus-AI undo by decision cycle, including cancellation while the AI is thinking.
- Verify that undo persists only the retained main line, provides no redo, and remains available after a natural result only until result confirmation.
- Test persistence and relaunch of an active game whose current history makes a neutral repetition draw claimable, plus the transition from claimable active game to immutable draw record.
- Test pin-state and delete-confirmation preference persistence, History sorting, replay, permanent deletion, deletion failure rollback, ended-early records, confirmed resignation, and immutable game content.
- Test every released SwiftData schema migration and archive-format migration from file-backed fixtures.
- Round-trip exported files across iOS, iPadOS, and macOS.
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
- Record and verify the actual UCI Hash value applied on each representative device. Test `os_proc_available_memory() == 0`, a rounded budget below 256 MiB, exactly 256 MiB, allocation failure, and operation without the increased-memory entitlement.
- Below the minimum, verify that the engine is not initialized, no smaller Hash or special automatic cleanup is attempted, and Retry uses a fresh available-memory value.
- Compare engine behavior with accepted rules fixtures wherever search consumes terminal adjudication.
- Measure whole-game playing behavior, latency, memory, energy, and thermal behavior of the accepted 1-, 3-, and 5-second profiles on representative supported devices. Any retuning is an explicit later product decision rather than an automatic response to diagnostic NPS or depth.
- Verify that the app remains functional when increased memory is unavailable and treats `os_proc_available_memory()` as changing advisory information rather than a target to consume.

### UI, accessibility, sound, and haptics

- Test VoiceOver labels, values, actions, order, and an end-to-end nonvisual board interaction.
- Test keyboard and pointer behavior where supported.
- Test Increase Contrast, Differentiate Without Color, Reduce Motion, and Reduce Transparency.
- Verify that sound, haptics, color, motion, and visual effects are never the sole carrier of required information.
- Verify unavailable hardware and muted-audio behavior.

## Build and TestFlight gates

An internal TestFlight candidate requires:

- successful builds for the supported iOS/iPadOS and macOS configurations;
- passing targeted unit, integration, persistence, import/export, rules, engine, and critical UI tests;
- no unresolved data-loss, illegal-move, rules-result, engine-termination, or migration failure;
- verified GPLv3 and third-party source, license, and asset provenance for packaged dependencies;
- manual smoke testing of new game, resume, undo, end, history replay, deletion, export, import, and settings on each supported platform.

## Need to discuss

> The following questions are non-normative and are not implementation requirements.

- Verify and record the exact simulator and macOS build/test commands.
- Select the supported simulator, physical-device, and macOS validation matrix.
- Define performance, memory, energy, and thermal thresholds for each AI profile.
- Define localization languages and the localization review process.
- Define which critical flows require UI automation versus structured manual review.
- Define import size, nesting, move-count, and processing-time limits.
- Define which evidence must be retained for an internal TestFlight candidate.
