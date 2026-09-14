# Star River

Star River (闲敲棋子) is a native, fully offline board-game application for iOS, iPadOS, and macOS, carrying **Xiangqi**, **Mini Xiangqi**, **Jieqi**, **Gomoku** and **Renju**, and built for board-game education inside a small internal group. This README is an introduction for anyone handed the app, and for the developers, testers, and reviewers behind it; it describes the intended MVP and points to the project contracts, but it does not record implementation progress. Progress, tasks, and delivery status belong in [GitHub Issues](https://github.com/chentianren0/MiniXiangqi/issues).

## Get the app

- **macOS, iPhone, and iPad:** the app ships through TestFlight internal testing and the public App Store — the listing states the application's GPLv3 licence and links the complete source (owner decision, 2026-08-04).
- The app is fully offline and collects nothing. The source is this repository — every release is built by CI from the tagged revision — and the licence is the [GNU General Public License version 3](LICENSE).

## Target MVP

- Human versus on-device AI play, with the user, the AI, or a Random choice determining who moves first, plus three difficulty levels.
- Free Play, where one person controls both Red and Black.
- Repeated undo during an active game, without redo.
- One automatically saved active game at a time.
- Local history with replay, deletion, and export, plus compatible game-record import.
- An in-app Mini Xiangqi rules reference as the help surface.
- `Play`, `History`, and `Settings` as the top-level destinations.
- Native interaction: Liquid Glass on every platform.

The MVP has no game clock, network features, accounts, online play, lessons or drills, or multiple main windows.

## Platforms and architecture

- iOS and iPadOS 26.5 or later.
- macOS 26.5 or later on Apple silicon; `x86_64` is not supported on macOS.
- One shared C++ core owns the rules, engine search, game files, and game library; each platform has a native frontend. See [Architecture](docs/architecture.md).
- Windows support ended at v3.0.0. The last version that carried the Windows frontend is archived, read-only, at [chentianren0/MiniXiangqi-Windows](https://github.com/chentianren0/MiniXiangqi-Windows).

## Building for Apple platforms

Open `apple/MiniXiangqi.xcodeproj` in Xcode. See [Testing](docs/testing.md) for the validation contract.

## Documentation

- [Product](docs/product.md) — product purpose, scope, capabilities, lifecycle policies, and MVP exclusions.
- [Mini Xiangqi rules](docs/xiangqi-rules.md) — normative rules source, adopted rules, runtime rules authority, and fixture requirements; the approved executable fixtures live in [fixtures/rules](fixtures/rules/).
- [Jieqi rules](docs/jieqi-rules.md) — the hidden-identity xiangqi: the dealt start, hidden movement and the mandatory flip, who is entitled to know what, the endings, and its own fixture area.
- [BoardGame protocol, version 2](docs/boardgame-protocol-v2.md) — the wire contract two devices play one game over, including the deal handshake a hidden-information game's session opens with.
- [Architecture](docs/architecture.md) — the shared core, native frontends, dependency direction, concurrency, and lifecycle.
- [Core C interface](docs/core-interface.md) — the core's C surface: modules, functions, error taxonomy, threading contract, and versioning.
- [Game data](docs/game-data.md) — the library store, versioned game archive, saving, history, migrations, import, and export.
- [Engine integration](docs/engine-integration.md) — the movement games' engine: the search facade, AI profiles, packaging, NNUE policy, and failure boundary.
- [Placement engine integration](docs/placement-engine-integration.md) — the placement games' engine: its pins, its preflight, the memory policy it shares with the first, and its failure boundary.
- [Jieqi engine integration](docs/jieqi-engine-integration.md) — Jieqi's rules authority: its pin, the rules slice the core compiles, everything the bridge owns because the engine validates nothing, and the dialect it translates into and out of.
- [Testing](docs/testing.md) — durable validation requirements and release gates.

## Distribution and license

Distribution: the app ships through TestFlight internal testing and the public App Store — the listing states the application's GPLv3 licence and links the complete source (owner decision, 2026-08-04). The project is licensed under the [GNU General Public License version 3](LICENSE), matching the engines it embeds, and the app's About screen names each embedded component and its licence.

The NNUE network the AI evaluates with is **this project's own**, trained from zero by the public pipeline at [`chentianren0/minixiangqi-nnue`](https://github.com/chentianren0/minixiangqi-nnue) with no other network as a teacher or a seed. It lives in this repository at `core/assets/`, pinned by byte length and SHA-256 in [`pinned-inputs.json`](pinned-inputs.json) along with its provenance, and every build verifies it before staging it. Every build carries it: there is one artifact and it is the complete application.

It replaced a community-trained network of unestablished origin, and it is weaker — about 300 Elo below it at the app's settings, and far above having no network at all. The trade bought a provenance that can be stated, and [Engine integration](docs/engine-integration.md) records the measurements the swap was accepted on.
