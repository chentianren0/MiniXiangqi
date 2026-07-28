# MiniXiangqi documentation structure proposal

## Decision

Use a small repository documentation set with one entry point, one agent-control file, and five focused documents:

```text
MiniXiangqi/
├── README.md
├── AGENTS.md
└── docs/
    ├── product-and-interaction.md
    ├── architecture.md
    ├── rules.md
    ├── engine-integration.md
    └── testing.md
```

This is a target structure, not a claim about the current implementation. The repository is presently the generated SwiftUI and SwiftData starter app, with placeholder unit and UI tests. Canonical documentation should be added as decisions become accepted and implemented; the discussion drafts should not be copied into the repository wholesale.

Product and interaction belong together for now because the product is deliberately small and its main policies—one active game, local history, undo, time controls, and offline play—directly determine its flows. The rules, engine boundary, technical architecture, and testing strategy merit separate documents because each has a distinct source of truth and can change independently.

Do not add a general `docs/index.md`; `README.md` is the index. Do not add an ADR directory, contributor guide, release manual, or separate product and interaction files until there is real content or ownership that makes the split useful.

## Responsibilities

### `README.md`: human entry point

Keep the README short enough to scan before opening the project. It should contain:

- what MiniXiangqi is;
- the platforms, languages, game modes, and offline boundary that are actually supported;
- the minimum prerequisites and shortest verified build-and-test path;
- a compact map of the five documents;
- licensing and third-party attribution entry points.

The README should not contain the complete rules, detailed screen flows, module inventory, engine protocol, test matrix, roadmap, or development history. It should describe shipped behavior as shipped behavior and planned behavior as planned behavior; it must not blur the two.

### `AGENTS.md`: operational constraints and routing for coding agents

The future repository-level `AGENTS.md` should be lightweight and contain only information that changes how an agent is allowed or expected to work:

1. A one- or two-sentence repository purpose and scope.
2. Non-negotiable workspace and remote-operation constraints:
   - work only within the authorized project workspace;
   - use only the project identity `ppppvz`;
   - activate the repository-scoped configuration before remote Git or GitHub operations;
   - write Git configuration only locally;
   - treat external repositories as read-only unless the user explicitly authorizes a contribution.
3. Hard-to-infer architectural invariants, especially that the app-owned rules core accepts moves and declares user-visible results, while the search engine may only propose moves and evaluate lines.
4. A source-of-truth map directing agents to the relevant document:
   - product behavior and flows: `docs/product-and-interaction.md`;
   - game semantics: `docs/rules.md` and its executable fixtures;
   - dependency direction and state ownership: `docs/architecture.md`;
   - engine and NNUE boundary: `docs/engine-integration.md`;
   - validation selection: `docs/testing.md`.
5. A compact verification rule: read the relevant contract before changing it, run the smallest tests that cover the changed boundary, and report any validation that could not be run.

`AGENTS.md` should not restate the product specification, teach Swift or SwiftUI, list every source file, embed exact implementation plans, or duplicate build commands maintained in `README.md` or `docs/testing.md`. Agent-specific permission and identity rules belong in `AGENTS.md`; ordinary project orientation belongs in the README; durable product and engineering contracts belong in `docs/`.

### `docs/product-and-interaction.md`: accepted product contract

This document should combine:

- product intent and audience;
- supported and explicitly unsupported capabilities;
- platforms, languages, and offline behavior;
- the persistent product state: at most one active game plus local history;
- new-game, active-game, replacement, completion, replay, and local-two-player flows;
- platform adaptation for iPhone, iPad, and macOS;
- user-visible recovery and destructive-action behavior;
- accessibility and localization expectations that affect interaction.

Write accepted decisions in the present tense. Keep unresolved alternatives in discussion issues or drafts until they are decided. Do not turn this document into a screen-by-screen implementation inventory or a backlog.

Split it into `product.md` and `interaction.md` only if product policy can be understood independently of the interaction flows and either area develops a distinct owner or review cycle. The current scope does not justify that split.

### `docs/architecture.md`: native app boundaries

Describe stable system structure rather than current filenames. It should contain:

- a small context and data-flow diagram;
- the responsibilities and dependency direction of the UI, application/session layer, rules core, persistence, and engine adapter;
- ownership of active-game state, clocks, history, replay, settings, and localization;
- persistence and restoration semantics, including schema migration expectations;
- concurrency and lifecycle rules, including backgrounding and cancellation;
- error propagation at subsystem boundaries;
- how shared behavior remains consistent across iOS, iPadOS, and macOS.

The architecture document should name concrete types or packages only when they are intentional public boundaries. Avoid a type catalog, directory tour, or copied framework documentation; those become stale faster than the design.

### `docs/rules.md`: canonical game semantics

Rules need their own document because user-visible legality and results must remain independent from search-engine behavior. It should contain:

- the normative Mini Xiangqi source and the exact interpretation adopted by the app;
- board coordinates, notation, starting position, pieces, movement, palace, flying-general, horse-leg, and cannon-screen behavior;
- check, mate, stalemate, legal-move rejection, move-count, repetition, perpetual-check, and chase outcomes;
- any deliberate compatibility exception, with a concise rationale;
- stable identifiers linking prose examples to executable conformance fixtures.

The prose and fixtures together form the rules contract. The app must be able to replay and adjudicate those fixtures without consulting the search engine. PyChess or Fairy-Stockfish may be used as compatibility evidence, but agreement with a shared upstream implementation is not independent proof of correctness.

Do not embed lengthy upstream source analysis, volatile source line numbers, or experimental engine output here. When a rule interpretation is unsettled, keep it out of the canonical contract until reviewed.

### `docs/engine-integration.md`: external engine contract

Keep this separate from general architecture because the engine introduces external versioning, asset provenance, native-process failure, licensing, cancellation, and semantic-divergence risks. It should document:

- the engine's bounded role: receive an app-approved position and history, then return analysis or a proposed move;
- the adapter API, position/history encoding, option ownership, and move-validation handoff;
- serialization, thread use, search cancellation, backgrounding, teardown, and stale-result rejection;
- variant configuration and the relationship between user rules and internal engine adjudication;
- NNUE packaging, naming, fingerprint/provenance, load verification, and explicit fallback behavior;
- failure containment: malformed input, unavailable assets, engine termination, timeout, or illegal best move must not corrupt the authoritative game;
- the update procedure and compatibility gates for changing the engine, variant configuration, or network;
- where machine-readable pinned revisions, patches, asset hashes, and licenses live.

Record versions and hashes in build inputs or machine-readable manifests and link to them instead of manually duplicating them in prose. This document should preserve the durable boundary and update policy, not a chronological evaluation log.

### `docs/testing.md`: validation contract

This document should answer what must be checked for each kind of change. It should contain:

- verified local commands and prerequisites;
- a change-to-validation matrix;
- rules conformance and replay fixtures;
- unit tests for state transitions, clocks, persistence, restoration, and migrations;
- engine differential, legality, robustness, cancellation, and negative-load tests;
- UI tests for the critical game lifecycle;
- localization and accessibility checks;
- physical-device timing, memory, energy, and thermal gates when relevant;
- the minimum release gate and what evidence is retained.

Keep durable thresholds and fixture definitions here. Store individual run results, raw transcripts, measurements, and temporary candidate comparisons in CI artifacts or a time-bounded review packet, not in the canonical document. A later performance report should not be appended to `testing.md` as history.

## Source-of-truth boundaries

| Question | Canonical location | Not canonical |
|---|---|---|
| What does the app offer and how does a user move through it? | `docs/product-and-interaction.md` | UI source layout, discussion drafts |
| Is a move legal and what is the game result? | `docs/rules.md` plus conformance fixtures | Search score, engine optional result |
| Which component owns state or may depend on another? | `docs/architecture.md` | A current file tree |
| How may the engine and NNUE interact with the app? | `docs/engine-integration.md` plus pinned build inputs | An upstream README or ad hoc experiment |
| What must pass for a change or release? | `docs/testing.md` plus test and CI definitions | A past run log |
| What may an agent do, and which contract should it read? | `AGENTS.md` | README prose or scattered comments |
| How does a person start and find more detail? | `README.md` | `AGENTS.md` |

When documentation and implementation disagree, do not silently redefine intended behavior from the current code. Identify whether the document is an accepted contract or a stale description, then update the appropriate source and its tests in the same change.

## Maintenance rules

- Give each fact one canonical home and link to it elsewhere.
- Document intent, invariants, interfaces, and failure behavior; let code describe local mechanics.
- Update a contract in the same change that alters the corresponding behavior.
- Prefer executable fixtures and manifests for exact positions, hashes, revisions, and matrices.
- Keep historical investigation, rejected alternatives, progress notes, and raw evidence outside the canonical documentation set.
- Add a document only when it has a distinct audience, authority, or lifecycle.
- Delete obsolete guidance rather than retaining contradictory versions.

## Treatment of the current discussion drafts

- Promote the accepted scope and flows from `product-design-draft.md` into `docs/product-and-interaction.md`. Leave its unresolved questions in discussion until decided.
- Promote only the stable engine authority boundary, packaging constraints, failure model, and update gates from `axf-source-analysis.md` and `axf-evaluation-plan.md`.
- Keep pinned source snapshots, source-line evidence, smoke observations, candidate matrices, and one-off measurements as review evidence. They should not become permanent sections of the README or architecture documents.
- Convert approved rules cases into named executable fixtures and summarize their semantics in `docs/rules.md`; do not make the AXF experiment the rules authority.

This structure is intentionally small. It gives humans a clear entry point, gives agents concise operational context with progressive disclosure, and preserves the few contracts whose confusion would create product or correctness risk.
