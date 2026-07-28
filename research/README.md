# Design research archive

Everything the Mini Xiangqi design work produced between 2026-07-26 and 2026-07-28, preserved here because it lived only in the workspace and would otherwise have been unrecoverable.

**This branch is not meant to be merged.** Its pull request is opened and closed so that GitHub retains the content and its description; `main` stays clean. Nothing here is a contract — the contracts are in `docs/`, and where the two disagree, `docs/` wins.

## What is worth reading

- **`layout-budget.md`** — the measured device list from CoreSimulator runtime bounds, a measured 83 pt navigation container, corrected iPhone mini dimensions, and per-device vertical budgets. Expensive to reproduce, and needed whenever the Apple frontend's layout is settled.
- **`rules-edge-cases-reconciliation.md`** — the reconciliation of two independent rule designs against the engine, executed rather than argued. It is the evidence behind the accepted rule interpretations and behind the fork's patch list P0–P5.
- **`investigate-chase-window-parity.md`** — the independent investigation of the repetition-window parity defect, including the measurement that 20 of 26 entry moves turn a required draw into a decisive loss.
- **`evidence/`** — the retained snapshot of the normative rules source, whose SHA-256 `xiangqi-rules.md` cites. This is the only material here that an accepted contract points at directly.
- **`parts-678-agenda.md`** and **`audit-*.md`** — the remaining design questions and a four-lens audit of every merged contract. Three of its findings are real and unfixed: a naturally terminal position still reports legal continuations, so an imported archive can continue past a completed loss and be recorded as ended early; a damaged installation is routed to an engine-unavailable path that does not exist; and engine preparation after an ordinary resume is undefined.
- **`apple-ui-design-survey.md`** — the original Apple platform survey. Substantially superseded, but it is where several accepted decisions started.

## What is not here

Thirteen copies of the Fairy-Stockfish source tree and their compiled artifacts, roughly 45 MB. They are reproducible from the revision pinned in `pinned-inputs.json` and carry no information the pin does not.

## What to distrust

The UI design written without anything rendered — the layout schemes, the secondary-surface designs, and the VoiceOver model. They were argued in prose about screens nobody had seen, and the layout work failed review three times before being withdrawn. Read them as notes, not as conclusions.
