# Testing

This document owns which evidence a change or build of the Star River application requires: the validation categories, fixture expectations, and release gates. It does not record run results, run commands, work status, or environment snapshots — CI workflows, the platform READMEs, GitHub Issues, and the build's own pinned inputs own those. It also does not restate what the product's contracts bind: a test cites the owning contract directly, and a checklist standing between them would be a third statement of one truth, stale the day either moves.

> **Status: binding**, except for the thresholds the final section names as owed.

## Where evidence is taken

- The unit bundle runs on an iOS Simulator and on macOS, and what it measures — layout shapes, memory probes, contrast, the rendered board — is about the platform it runs on, so a run on one platform is evidence about that platform.
- UI suites declare their platform per file, not by target: macOS suites drive a window, naming a size and reading frames back, and phone suites answer what only a phone can — the stacked arrangement, the pitch floors, real disjoint hit cells, portrait. A destination therefore selects its own suites, and `LaunchPreferences` keeps the hermetic-launch table single rather than letting two copies drift. The suite census is the tree itself.
- iOS layout evidence is taken on a current compact-width iPhone and a current iPad, and names its device: compact width is a specific number of points, and a phone of a different width is a different case, not a stand-in. One simulator is booted at a time.
- What a simulator cannot prove is not claimed from one: feel, latency, memory, energy, thermals, and the radio belong to device passes, and driven runs on real devices are reserved for what only devices prove — protocol, transport, radio, and lifecycle behavior.
- The Apple toolchain and its selection are the workspace's own rule — `DEVELOPER_DIR` per invocation, never a change to the global `xcode-select`. Deployment targets, the pinned core toolchains, and the pinned engine inputs live in the project and `pinned-inputs.json`: the build is their record, not this document.
- The shared core builds and its tests run on every development platform without a frontend. Windows `ARM64` is CI-only — no developer machine compiles it — so a validation claim about it cites a CI run, the one place the developer-runs-are-the-evidence rule does not reach. CI supplements the gates below and replaces none of them.

## Validation principles

- Select tests from the contract changed, not only from the files edited.
- Keep rules, domain, persistence, engine, and UI tests independently runnable where practical.
- Prefer deterministic, behavior-focused fixtures over snapshots of incidental implementation details.
- Test length is never a reason to omit necessary evidence. Add and run a long test when it is the smallest honest way to protect load-bearing behavior. The run budget limits duplicate execution, not test scope: one completed passing run of each affected suite under the current code and conditions is sufficient, and an unchanged green suite is not run again. After code, tests, or relevant conditions change, run the affected suites once. Diagnose a failed or interrupted run before retrying it.
- A test finds a control by identifier, never by label: a label is copy and changes with the language, and an identifier does not.
- Report exact commands, environment, results, and anything not run.
- Keep raw logs, measurements, and historical run results outside this document.

## What a change owes

One entry per domain: the evidence a change there requires, and the testing-specific rules no other document states. What the behavior must be is the owning contract's, and the tests cite it directly.

- **Shared core.** The core suite — every game's rules fixtures, the archive codec, the library store, the search facade — on at least one Apple platform and on Windows, in **both** a debug and a release configuration: the programming errors in [core-interface.md](core-interface.md)'s taxonomy assert where `NDEBUG` is undefined and return their codes where it is defined, so neither configuration is a superset of the other, and the vendored engines' own assertions are live only in the first.
- **Rules.** The conformance fixtures in `fixtures/rules/` for every game the change touches, each under the ruleset it declares, with every ply's legal set, resulting position, check state, and final result verified. A minimized failing fixture lands before an accepted interpretation changes. Wherever search consumes terminal adjudication, the same fixtures run against the app-visible adjudicator and the engine configuration, and the two must agree on position identity, repetition occurrence, and classification — without an engine result auto-committing a claim the contract leaves to the player.
- **Game data.** The store's schema-enforced invariants — the single active game, History immutability outside pin state, atomic archive-and-clear, no partial import, deletion rollback — plus cross-platform round-trips with byte-identical canonical content and hash, and the one-defined-version refusal on each axis, per [game-data.md](game-data.md): nothing migrates, and a test that named an older shape would be the only thing in the repository that did.
- **Engines.** Each embedded engine is verified through the app's own boundary: initialization, capability checks and option application, cancellation, suspension, teardown, stale-result rejection, and the memory-budget boundaries on real hardware. A network or weights file is proven effective by its fingerprint and the engine's own positive load signal, never by filename alone. A pinned-input hash mismatch fails the build rather than packaging.
- **Product, interaction, and accessibility.** The complete affected flow for each affected game, on the smallest relevant iPhone layout, an iPad layout, and a supported macOS window — in light and dark appearance, under the accessibility settings the contracts name, with localization evidence in both languages plus the pseudolanguage passes and the mechanical both-languages catalog check. What the screens must show and say is [interaction-design.md](interaction-design.md)'s and [product.md](product.md)'s to state; the visual specifics those contracts leave to a rendered board are judged from one, by the owner.

## Build and distribution gates

A distribution candidate — TestFlight on Apple platforms, or the Windows zip or Store package — requires:

- successful builds for every supported configuration on the distributed platform, which on Windows means both architectures, each a separate artifact that a separate machine runs;
- passing shared-core tests plus targeted unit, integration, persistence, import and export, rules, engine, and critical UI tests;
- no unresolved data-loss, illegal-move, rules-result, engine-termination, or version-validation failure;
- verified license inputs, carried in every artifact somebody is handed: the project's own `LICENSE`, and the generated notice naming each vendored engine at its pinned revision and each bundled network with the filename, byte length, SHA-256, and provenance the manifest records;
- every bundled network's verified pinned hash, in every distribution without exception, so that an absent network is damage rather than a case a recipient has instructions for;
- for the Windows zip, a run of the headless harness against the unpacked zip exactly as produced, with nothing added to it, rather than against the build tree the zip was made from;
- manual smoke testing of new game, resume, undo, end, history replay, deletion, export, import, and settings on each distributed platform.

## Thresholds not yet set

Named so a reader knows the gates above are incomplete, not to authorize a value:

- performance, memory, energy, and thermal thresholds for each AI profile;
- how the accepted import validation time budget is measured and enforced on each platform;
- which evidence a distribution candidate must retain, and which critical flows require UI automation rather than structured manual review;
- the physical-device matrix a distribution candidate must be exercised on.
