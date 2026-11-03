# Rapfi

- Upstream: https://github.com/dhbloo/rapfi, base `3c94c2a976f24a0dd1c5517623e9ab6fffe66bd7`
- Fork: https://github.com/chentianren0/rapfi, pinned at `265b7d66c7b57bbd8689c8dfd1efb4133e02b5ed`, committed 2026-08-12
- Included: `Rapfi/` with the lz4, cpptoml and simde externals, plus `AUTHORS`, `Copying.txt` and the README. Excluded: `main.cpp`, the Gomocup protocol, the command modules and `tuning/`, the ONNX evaluator, the fork's CMake files, the Emscripten shell, the other externals, the trainer, web front end, network weights and CI.
- simde carries no license file in the fork, so third-party notices must take its MIT text from simde's own repository.
- Patches in the pinned revision, oldest first:
  - `recoverable-hash-allocation`: a failed hash table resize returns `false` instead of exiting the process.
  - `engine-library-target`: a `rapfi_engine` static library target; the core builds the snapshot with its own `CMakeLists.txt` instead.

Pending: `recoverable-large-page-free`, the same process exit on the Windows large-page free path. It cannot be reached from an Apple build, and must land before any Windows build of this engine.
