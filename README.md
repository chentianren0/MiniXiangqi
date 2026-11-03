# Star River

Star River (闲敲棋子) is a native board-game app for iPhone, iPad and Mac. It carries five games — **Xiangqi**, **Mini Xiangqi**, **Jieqi**, **Gomoku** and **Renju** — and plays them offline against an on-device AI, in Free Play, or against another person nearby or online.

The app is on the App Store under the [GNU General Public License version 3](LICENSE); the listing links this repository as its source.

## Building

1. Install CMake and Ninja, which build the C++ core under `core/`.
2. Run `./build-core-xcframework.sh`, and run it again whenever anything under `core/` changes.
3. Open `MiniXiangqi.xcodeproj` and build the `MiniXiangqi` scheme.

[#280](https://github.com/chentianren0/MiniXiangqi/issues/280) turns the core into a Swift package and replaces these steps.

Tests: run the `MiniXiangqi` scheme's Test action in Xcode; the core's own tests run with `ctest`, as [core/README.md](core/README.md) describes.

The Mini Xiangqi network is the project's own, trained by the public pipeline at [`chentianren0/minixiangqi-nnue`](https://github.com/chentianren0/minixiangqi-nnue).

## Documentation

- [Product](docs/product.md) — what the app does and does not do.
- [Xiangqi and Mini Xiangqi rules](docs/xiangqi-rules.md) and [Jieqi rules](docs/jieqi-rules.md).
- [Game data](docs/game-data.md) — game files, History, import and export.

The 4.0 plan is [#285](https://github.com/chentianren0/MiniXiangqi/issues/285).
