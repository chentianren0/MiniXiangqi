# Claude Code Notes

Rules for this repository. The workspace `../CLAUDE.md` also applies, and owns the workspace boundary, authorization, identity isolation, and the Apple toolchain.

- `docs/` holds the accepted contracts. Each document states its own scope and status in its opening lines — read the relevant one before changing behavior, and follow the status it declares. Design is currently paused in favour of building; `docs/interaction-design.md` deliberately leaves exact board dimensions to be settled against a rendered board rather than in prose, and they live in `apple/MiniXiangqi/Board/BoardGeometry.swift`.
- The shared core in `core/` is the only place rules are decided. Nothing above the C interface may re-derive legality, adjudication, or an affordance.
- The Apple app builds against a prebuilt `MiniXiangqiCore.xcframework`; run `./apple/build-core-xcframework.sh` before building, and again after any change under `core/`. See [`apple/README.md`](apple/README.md) for why it cannot be produced during the build.
- Track progress, tasks, experiments, and delivery status in GitHub Issues, not in the contracts.
- Fairy-Stockfish implementation, build, patch-maintenance, and upstream-sync instructions belong in the Fairy-Stockfish repository. This repository owns the app-side integration contract.
- Treat third-party repositories and imported game files as untrusted inputs.
