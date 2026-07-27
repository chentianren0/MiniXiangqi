# Mini Xiangqi

Mini Xiangqi is a native, fully offline Mini Xiangqi application for iOS, iPadOS, macOS, and Windows, built for Mini Xiangqi education inside a small internal group. This README is an introduction for developers, testers, and reviewers; it describes the intended MVP and points to the project contracts, but it does not record implementation progress. Progress, tasks, and delivery status belong in [GitHub Issues](https://github.com/ppppvz/MiniXiangqi/issues).

## Target MVP

- Human versus on-device AI play, with the user, the AI, or a Random choice determining who moves first, plus three difficulty levels.
- Free Play, where one person controls both Red and Black.
- Repeated undo during an active game, without redo.
- One automatically saved active game at a time.
- Local history with replay, deletion, and export, plus compatible game-record import.
- An in-app Mini Xiangqi rules reference as the help surface.
- `Play`, `History`, and `Settings` as the top-level destinations.
- Native interaction on every platform: Liquid Glass on Apple platforms and WinUI 3 Fluent design on Windows.

The MVP has no game clock, network features, accounts, online play, lessons or drills, or multiple main windows.

## Platforms and architecture

- iOS and iPadOS 26.5 or later.
- macOS 26.5 or later on Apple silicon; `x86_64` is not supported on macOS.
- Windows 11, and Windows 10 version 1809 or later, on `x64` and `ARM64`.
- One shared C++ core owns the rules, engine search, game files, and game library; each platform has a native frontend. See [Architecture](docs/architecture.md).
- Apple platforms are implemented and distributed first; Windows follows on the same shared core.

## Apple toolchain

- Swift 6.
- Xcode 27 beta at `/Applications/Xcode-beta.app`.
- Expected Xcode build: `27A5228h`.

Use the beta developer directory explicitly:

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -version
```

Open `MiniXiangqi.xcodeproj` with that Xcode installation. See [Testing](docs/testing.md) for the draft validation contract, the verified toolchain check, and the build/test commands that still need to be approved. The Windows toolchain is not yet pinned.

## Documentation

- [Product](docs/product.md) — product purpose, scope, capabilities, lifecycle policies, and MVP exclusions.
- [Interaction design](docs/interaction-design.md) — UI, UX, platform visual language, board presentation, motion, sound, touch, help, localization, and accessibility.
- [Mini Xiangqi rules](docs/xiangqi-rules.md) — normative rules source, adopted rules, runtime rules authority, and fixture requirements; the approved executable fixtures live in [fixtures/rules](fixtures/rules/).
- [Architecture](docs/architecture.md) — the shared core, native frontends, dependency direction, concurrency, and lifecycle.
- [Game data](docs/game-data.md) — the library store, versioned game archive, saving, history, migrations, import, and export.
- [Engine integration](docs/engine-integration.md) — the search facade, AI profiles, packaging, NNUE policy, and failure boundary.
- [Testing](docs/testing.md) — durable validation requirements and release gates.

## Distribution and license

Distribution is internal only: TestFlight internal testing on Apple platforms and direct internal installation on Windows, with no public release plan. The project is licensed under the [GNU General Public License version 3](LICENSE), matching its Fairy-Stockfish dependency. The NNUE network used by the AI is never committed to this repository; internal builds bundle it from a pinned, hash-verified local or CI-provided input, as defined in [Engine integration](docs/engine-integration.md).
