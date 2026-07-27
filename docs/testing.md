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
- Verify the turn-status matrix for Red and Black, human and computer ownership, computer thinking, Free Play, unavailable input, and replay progress.
- Verify the natural-result card before and after confirmation, including **悔棋**, **结束对局**, **回放**, **完成**, outside-dismissal rejection, and the absence of a Play Again action.
- Verify the threefold notice, **继续对局**, **以和棋结束**, and retained non-blocking **可判和** affordance in both play modes.
- Verify manual replay navigation and autoplay at 0.5×, 1×, and 2×, including animation completion, manual-navigation pause, board-flip pause, background pause, end-of-game stop, and Reduce Motion behavior.

### Rules

- Run approved conformance fixtures for movement, king safety, check, mate, stalemate, repetition, perpetual check, and perpetual chase.
- Verify every ply's legal set, resulting position, check state, and final result where applicable.
- Verify that the target custom variant has no move-count draw and recognizes the neutral draw outcome on the third occurrence for search.
- Verify that the app-visible rules boundary exposes claim eligibility on that occurrence, continuing keeps the game active, and only an explicit claim commits the draw.
- Verify unilateral perpetual-check loss, unilateral perpetual-chase loss, mutual same-class draw, check-versus-chase precedence, and king and soldier chase-target exclusion.
- Run the same accepted history fixtures against the app-visible adjudicator and the engine search configuration. The engine may use a terminal or draw-valued representation for search while the app exposes a claim, but position identity, repetition occurrence, and draw classification must agree, and an engine search result must not auto-commit the app-visible draw.
- Add a minimized failing fixture before changing an accepted rule interpretation.

### Game data

- Test the single-active-game invariant and atomic active-game replacement.
- Save each durable transition, recreate the container, and verify exact resume state.
- Test repeated Free Play undo by ply and repeated human-versus-computer undo by decision cycle, including cancellation while the computer is thinking.
- Verify that undo persists only the retained main line, provides no redo, and remains available after a natural result only until result confirmation.
- Test persistence and relaunch of an active game whose current history makes a neutral repetition draw claimable, plus the transition from claimable active game to immutable draw record.
- Test history sorting, replay, deletion, ended-early records, confirmed resignation, and completed-record immutability.
- Test every released SwiftData schema migration and archive-format migration from file-backed fixtures.
- Round-trip exported files across iOS, iPadOS, and macOS.
- Reject oversized, malformed, unsupported, inconsistent, and partially valid imports without partial persistence, and test repeated imports against the accepted duplicate policy.

### Engine integration

- Verify initialization, capability checks, option application, legal proposed moves, cancellation, teardown, and stale-result rejection.
- Test missing, corrupted, incompatible, and incorrectly named engine or NNUE assets.
- Verify the configured NNUE fingerprint and positive load signal before search; a filename alone is not sufficient.
- Verify every level applies the accepted shared search profile and differs only in `go movetime`.
- Verify the applied `Threads` value equals the active processor count reported by the device at engine initialization.
- Test the accepted Hash budget at and around the 4 GiB cap, 50%-of-physical-memory boundary, 20%-or-1-GiB reserve boundary, and 64 MiB rounding boundary.
- Record and verify the actual UCI Hash value applied on each representative device. Once the low-memory fallback is approved, test `os_proc_available_memory() == 0`, a budget below 64 MiB, allocation failure, and operation without the increased-memory entitlement.
- Compare engine behavior with accepted rules fixtures wherever search consumes terminal adjudication.
- Measure latency, memory, energy, and thermal behavior of the accepted resource policy on representative supported devices before fixing exact AI `movetime` profiles.
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
