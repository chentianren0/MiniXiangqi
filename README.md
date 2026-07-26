# Mini Xiangqi

Mini Xiangqi is a native, fully offline Mini Xiangqi game for iOS, iPadOS, and macOS. This README is an introduction for developers, testers, and reviewers; it describes the intended MVP and points to the project contracts, but it does not record implementation progress. Progress, tasks, and delivery status belong in [GitHub Issues](https://github.com/ppppvz/MiniXiangqi/issues).

## Target MVP

- Human versus on-device computer play, with color choice and configurable difficulty.
- Local human-versus-human play on one device.
- One-step undo during an active game.
- One automatically saved active game at a time.
- Local history with replay, deletion, and export, plus compatible game-record import.
- `Play`, `History`, and `Settings` as the top-level destinations.
- Native Liquid Glass interaction adapted to each supported Apple platform.

The MVP has no game clock, network features, accounts, online play, or multiple main windows.

## Platforms and toolchain

- iOS and iPadOS 26.5 or later.
- macOS 26.5 or later on Apple silicon; `x86_64` is not supported.
- Swift 6.
- Xcode 27 beta at `/Applications/Xcode-beta.app`.
- Expected Xcode build: `27A5228h`.

Use the beta developer directory explicitly:

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -version
```

Open `MiniXiangqi.xcodeproj` with that Xcode installation. See [Testing](docs/testing.md) for the draft validation contract, the verified toolchain check, and the build/test commands that still need to be approved.

## Documentation

- [Product](docs/product.md) — product scope, capabilities, lifecycle policies, and MVP exclusions.
- [Interaction design](docs/interaction-design.md) — UI, UX, Liquid Glass, board presentation, motion, sound, touch, localization, and accessibility.
- [Mini Xiangqi rules](docs/xiangqi-rules.md) — normative rules source, adopted ordinary rules, fixture requirements, and open adjudication questions.
- [Architecture](docs/architecture.md) — app boundaries, dependency direction, state ownership, concurrency, and lifecycle.
- [Game data](docs/game-data.md) — SwiftData persistence, autosave, history, migrations, import, and export.
- [Engine integration](docs/engine-integration.md) — the app-side Fairy-Stockfish adapter, AI profiles, packaging, and failure boundary.
- [Testing](docs/testing.md) — durable validation requirements and release gates.

## Distribution and license

The MVP is intended for internal TestFlight testing rather than public distribution. The project is licensed under the [GNU General Public License version 3](LICENSE).
