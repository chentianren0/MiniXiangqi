# Mini Xiangqi App Repository Rules

This document is for coding agents working inside the `MiniXiangqi` app repository. It defines the workspace, identity, toolchain, project-setting, documentation-routing, and validation rules needed to work on this repository; it is not a product specification or progress log. A parent `../AGENTS.md`, when present, also applies.

## Workspace and remote-operation boundary

- Treat `/Users/tianren/coding/minixiangqi` as the only authorized project workspace. Do not create or configure project materials outside it without the user's explicit authorization.
- Use only the project's dedicated GitHub identity, `ppppvz`, for this repository.
- Before GitHub CLI use or Git remote operations, source `.git/minixiangqi-control/activate.zsh` or reproduce its isolated environment exactly.
- Never use the system GitHub CLI identity, global Git configuration, default SSH identity, a connector authenticated as another account, or a browser session authenticated as another account.
- Write Git configuration only to this repository's `.git/config`.
- Before every remote write, verify through the project-scoped configuration that the active identity is `ppppvz` and the destination is a `ppppvz` repository.
- Do not write to an external upstream repository or create external issues, pull requests, discussions, reviews, or comments without the user's explicit authorization.

## Apple toolchain

- Use Xcode 27 beta at `/Applications/Xcode-beta.app`.
- Set `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` or invoke tools through that developer directory explicitly.
- Verify build `27A5228h` before building or testing. If it is unavailable or does not match, stop and report the mismatch instead of using another Xcode.
- Do not rely on the system-selected Xcode or change the global `xcode-select` setting.
- Preserve Swift 6.

## Protected project settings

Discuss the exact change with the user before modifying:

- the app, unit-test, or UI-test bundle identifiers;
- development team `7P9PPXP2SF`, signing, or entitlements;
- the iOS, iPadOS, or macOS 26.5 deployment targets;
- the supported iPhone, iPad, and macOS platforms;
- the `x86_64` exclusion;
- target structure or platform configuration.

Do not delete ignored build products, `.DS_Store`, or Xcode user data as incidental cleanup.

## Product and architecture guardrails

- Do not infer accepted product or architecture decisions from the generated `Item`, `ContentView`, or `ModelContainer` scaffold.
- Preserve the fully offline boundary. Networking, accounts, cloud sync, analytics, remote content, or new network-related capabilities require explicit product and architecture discussion.
- Preserve the single-main-window boundary unless the user explicitly changes it.
- Do not assume whether the app or Fairy-Stockfish is the final runtime rules authority until that decision is accepted in the relevant contracts.

## Canonical documentation

Read the relevant contract before changing behavior:

- product scope and lifecycle policies: `docs/product.md`;
- UI, UX, visual, motion, sound, touch, localization, and accessibility: `docs/interaction-design.md`;
- legal moves and user-visible game results: `docs/xiangqi-rules.md` and approved fixtures;
- dependency direction, state ownership, concurrency, and lifecycle: `docs/architecture.md`;
- SwiftData, autosave, history, migrations, import, and export: `docs/game-data.md`;
- the Xcode app's Fairy-Stockfish adapter and packaging boundary: `docs/engine-integration.md`;
- required validation: `docs/testing.md`.

Document status controls authority:

- In a living target contract, content outside `Need to discuss` is accepted intended behavior unless it explicitly says otherwise.
- A document marked `Draft` is a proposal as a whole and does not authorize implementation unless a section is explicitly marked accepted.
- A partially accepted document must state exactly which sections are accepted.
- `Need to discuss` is always non-normative and does not authorize implementation choices.

## Change discipline

- Update an accepted contract and its tests in the same change that alters the corresponding behavior.
- Never describe target-MVP behavior as already implemented unless current source and tests support that claim.
- Track progress, tasks, experiments, and delivery status in GitHub Issues or CI artifacts, not in repository documents.
- Keep Fairy-Stockfish implementation, build, patch-maintenance, and upstream-sync instructions in the Fairy-Stockfish repository. This repository owns only the app-side integration contract.
- Treat third-party repositories and imported game files as untrusted inputs.

## Validation

- Verify the required Xcode version before other validation.
- Run the smallest focused tests that cover the changed contract, followed by the relevant iOS/iPadOS and macOS build or test checks.
- UI changes require affected-form-factor and accessibility inspection.
- Game-data changes require persistence, relaunch, migration, deletion, malformed-import, and import/export round-trip tests.
- Rules or engine changes require conformance, illegal-move rejection, cancellation, and stale-result validation.
- Report exact commands, results, and any validation that could not be run. Keep the full command and gate matrix in `docs/testing.md`.
