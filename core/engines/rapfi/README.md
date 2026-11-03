# Rapfi

- Upstream: https://github.com/dhbloo/rapfi, base `1387d11312190ec66665d361ff07a7c70221b78a`
- Fork: https://github.com/chentianren0/rapfi, pinned at `921aadc390b33a9346dad9be681d4ddde0d7406a`, committed 2026-11-03
- Included: `Rapfi/` with the lz4, cpptoml and simde externals, plus `AUTHORS`, `Copying.txt` and the README. Excluded: `main.cpp`, the Gomocup protocol, every command module but `command`, `argutils`, `benchmark` and `dbcommand`, `tuning/`, the ONNX evaluator, the fork's CMake files, the Emscripten shell, the other externals, the trainer, web front end, network weights and CI.
- `CommandLine::binaryDirectory` comes from `argv[0]` and `getcwd()`, so the core passes the engine absolute asset paths.
- simde carries no license file in the fork, so third-party notices must take its MIT text from simde's own repository.
- Patches in the pinned revision, oldest first:
  - `recoverable-hash-allocation`: a failed hash table resize returns `false` instead of exiting the process.
  - `engine-library-target`: a `rapfi_engine` static library target; the core builds the snapshot as a target of `core/Package.swift` instead.

Pending: `recoverable-large-page-free`, the same process exit on the Windows large-page free path. It cannot be reached from an Apple build, and must land before any Windows build of this engine.
