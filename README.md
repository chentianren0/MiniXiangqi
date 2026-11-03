# Star River

Star River (闲敲棋子) is a native board-game app for iPhone, iPad and Mac. It carries five games — **Xiangqi**, **Mini Xiangqi**, **Jieqi**, **Gomoku** and **Renju** — and plays them offline against an on-device AI, in Free Play, or against another person nearby or online.

The app is on the App Store under the [GNU General Public License version 3](LICENSE); the listing links this repository as its source.

## Building

Open `MiniXiangqi.xcodeproj` and build the `MiniXiangqi` scheme. Xcode alone is enough: the C++ core is the local Swift package in [`core/`](core/README.md), which Xcode builds with the app.

Tests: the `MiniXiangqi` scheme's Test action runs the app's tests; the core's run with `swift test` in `core/`, or from Xcode with `core/Package.swift` open.

The Mini Xiangqi network is the project's own, trained by the public pipeline at [`chentianren0/minixiangqi-nnue`](https://github.com/chentianren0/minixiangqi-nnue).

## Documentation

- [Product](docs/product.md) — what the app does and does not do.
- [Xiangqi and Mini Xiangqi rules](docs/xiangqi-rules.md) and [Jieqi rules](docs/jieqi-rules.md).
- [Game files](docs/game-data.md) — the format History exports and imports.
