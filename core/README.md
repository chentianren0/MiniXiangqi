# Core

The C++ core behind the app: rules, engine search, the game-file codec and the game library, behind the C interface in `include/mxq.h`.

- `src/` — the implementation.
- `tests/` — the test runner, checked against the fixtures in [`fixtures/`](../fixtures/).
- `assets/` — the variant configuration and the NNUE networks, pinned in `pinned-inputs.json`.
- `third_party/` — the vendored engine forks and SQLite.

Build and test it with CMake and Ninja:

```sh
cmake -S core -B core/.build -G Ninja -DMXQ_ENABLE_RULES_FACADE=ON
cmake --build core/.build
ctest --test-dir core/.build --output-on-failure
```

Without `-DMXQ_ENABLE_RULES_FACADE=ON` the engines are not compiled and the tests that need them report `NOT IMPLEMENTED`. The app links the core as an XCFramework built by [`build-core-xcframework.sh`](../build-core-xcframework.sh).

[#280](https://github.com/chentianren0/MiniXiangqi/issues/280) replaces this with a local Swift package.
