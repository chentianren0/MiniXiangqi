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

### Rules

- Run approved conformance fixtures for movement, king safety, check, mate, stalemate, repetition, perpetual check, and perpetual chase.
- Verify every ply's legal set, resulting position, check state, and final result where applicable.
- Add a minimized failing fixture before changing an accepted rule interpretation.

### Game data

- Test the single-active-game invariant and atomic active-game replacement.
- Save each durable transition, recreate the container, and verify exact resume state.
- Test history sorting, replay, deletion, undo persistence, and completed-record immutability.
- Test every released SwiftData schema migration and archive-format migration from file-backed fixtures.
- Round-trip exported files across iOS, iPadOS, and macOS.
- Reject oversized, malformed, unsupported, inconsistent, and partially valid imports without partial persistence, and test repeated imports against the accepted duplicate policy.

### Engine integration

- Verify initialization, capability checks, option application, legal proposed moves, cancellation, teardown, and stale-result rejection.
- Test missing, corrupted, incompatible, and incorrectly named engine or NNUE assets.
- Compare engine behavior with accepted rules fixtures wherever search consumes terminal adjudication.
- Measure latency, memory, energy, and thermal behavior on representative supported devices before fixing AI profiles.

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
