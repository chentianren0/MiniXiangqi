# Claude Code Notes

This file is the binding rule set for agents working in the `MiniXiangqi` app repository. It replaces the former `AGENTS.md`, retired on 2026-07-27. It defines the identity, toolchain, project-setting, documentation-routing, change, and validation rules for this repository; it is not a product specification or a progress log. The parent `../CLAUDE.md` also applies and owns the workspace boundary, the authorization limits, the Apple toolchain, and the GitHub identity rules.

## Platform scope

- The product targets iOS, iPadOS, macOS, and Windows through one shared C++ core with a native frontend per platform, as defined in `docs/architecture.md`.
- Apple platforms are implemented first. The Windows toolchain is not yet pinned; do not invent one silently.

## Fixed project settings

The following are settled values, not defaults to revisit. Preserve them through any change, including the repository restructure, and raise it with the user rather than changing one in passing:

- the app, unit-test, and UI-test bundle identifiers;
- development team `7P9PPXP2SF`, signing, and entitlements;
- the iOS, iPadOS, and macOS 26.5 deployment targets;
- the supported iPhone, iPad, and macOS platforms;
- the `x86_64` exclusion;
- Swift 6.

Relocating the Xcode project under `apple/` is authorized, and target and platform configuration may change only as far as that relocation requires. Do not delete ignored build products, `.DS_Store`, or Xcode user data as incidental cleanup.

## Product and architecture guardrails

- Do not infer accepted product or architecture decisions from the generated `Item`, `ContentView`, or `ModelContainer` scaffold.
- Preserve the fully offline boundary. Networking, accounts, cloud sync, analytics, remote content, or new network-related capabilities require explicit product and architecture discussion.
- Preserve the single-main-window boundary unless the user explicitly changes it.
- The shared core's rules facade is the accepted runtime rules authority; frontends must not reimplement rules, result classification, or library invariants, and search output never commits a user-visible result.
- Never commit NNUE network bytes to this repository. Internal builds bundle the pinned network from outside version control per `docs/engine-integration.md`.

## Canonical documentation

This is a design-first repository: `docs/` holds the contracts, and the code is still the generated Xcode scaffold. Read the relevant contract before changing behavior:

- product scope and lifecycle policies: `docs/product.md`;
- UI, UX, visual, motion, sound, touch, help, localization, and accessibility: `docs/interaction-design.md`;
- legal moves and user-visible game results: `docs/xiangqi-rules.md` and approved fixtures;
- the shared core, frontends, dependency direction, state ownership, concurrency, and lifecycle: `docs/architecture.md`;
- the core's C surface — modules, functions, error taxonomy, and threading rules: `docs/core-interface.md`;
- the library store, game archive, saving, history, migrations, import, and export: `docs/game-data.md`;
- the search facade, AI profiles, packaging, and NNUE policy: `docs/engine-integration.md`;
- required validation: `docs/testing.md`.

Document status controls authority:

- In a living target contract, content outside `Need to discuss` is accepted intended behavior unless it explicitly says otherwise.
- A document marked `Draft` is a proposal as a whole and does not authorize implementation unless a section is explicitly marked accepted.
- A partially accepted document must state exactly which sections are accepted.
- `Need to discuss` is always non-normative and does not authorize implementation choices.

Open product and engineering questions live in those `Need to discuss` sections and in GitHub Issues — see issue #2 — never in progress notes inside the contracts.

## Change discipline

- Update an accepted contract and its tests in the same change that alters the corresponding behavior.
- Never describe target-MVP behavior as already implemented unless current source and tests support that claim.
- Track progress, tasks, experiments, and delivery status in GitHub Issues or CI artifacts, not in repository documents.
- Keep Fairy-Stockfish implementation, build, patch-maintenance, and upstream-sync instructions in the Fairy-Stockfish repository. This repository owns only the app-side integration contract.
- Treat third-party repositories and imported game files as untrusted inputs.

## Validation

- For Apple work, verify the required Xcode version before other validation.
- Run the smallest focused tests that cover the changed contract, followed by the relevant platform build or test checks.
- UI changes require affected-form-factor and accessibility inspection.
- Game-data changes require persistence, relaunch, migration, deletion, malformed-import, and import/export round-trip tests.
- Rules or engine changes require conformance, illegal-move rejection, cancellation, and stale-result validation.
- Report exact commands, results, and any validation that could not be run. Keep the full command and gate matrix in `docs/testing.md`.
