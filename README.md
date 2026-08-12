# Mini Xiangqi

Mini Xiangqi is a native, fully offline Mini Xiangqi application for iOS, iPadOS, macOS, and Windows, built for Mini Xiangqi education inside a small internal group. This README is an introduction for anyone handed the app, and for the developers, testers, and reviewers behind it; it describes the intended MVP and points to the project contracts, but it does not record implementation progress. Progress, tasks, and delivery status belong in [GitHub Issues](https://github.com/chentianren0/MiniXiangqi/issues).

## Get the app

- **Windows 11 (x64 or ARM):** download the zip for your machine from [the latest release](https://github.com/chentianren0/MiniXiangqi/releases/latest) — `MiniXiangqi-windows-x64.zip` for Intel/AMD machines, `MiniXiangqi-windows-arm64.zip` for ARM machines — unzip it anywhere, open the folder, and run `MiniXiangqi.App.exe`. If Windows SmartScreen warns about an unrecognized app the first time, choose **More info**, then **Run anyway**. There is no installer and no administrator prompt, and deleting the folder removes the app completely. The Microsoft Store is the intended future public channel.
- **macOS, iPhone, and iPad:** the app ships through TestFlight internal testing and the public App Store — the listing states the application's GPLv3 licence and links the complete source (owner decision, 2026-08-04).
- The app is fully offline and collects nothing. The source is this repository — every release is built by CI from the tagged revision — and the licence is the [GNU General Public License version 3](LICENSE); the Windows zip carries `LICENSE` and `NOTICE.md` beside the app.

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
- Windows 11 on `x64` and `ARM64`. Windows 10 left Microsoft support in October 2025 (owner decision, 2026-07-30). `ARM64` came off the list the same day for want of hardware to test it on and returned on 2026-07-31, when that condition was met: it is built, tested and distributed on the same terms as `x64`.
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

Open `apple/MiniXiangqi.xcodeproj` with that Xcode installation. See [Testing](docs/testing.md) for the draft validation contract, the verified toolchain check, and the build/test commands that still need to be approved.

## Windows toolchain

The Windows toolchain is pinned in [`pinned-inputs.json`](pinned-inputs.json), by builds that produced it rather than by intent. The core's half is Visual Studio 2026 Community with the MSVC v14.51 toolset, the Windows 11 SDK, CMake and Ninja, measured once per architecture. The frontend's half — the Windows App SDK version, the .NET version, and the packaging flags — was recorded by the first packaging build, which is [`windows/package-zip.ps1`](windows/package-zip.ps1) running in CI. What that build did not measure is still recorded as unestablished: the engine and SQLite compile flags stay empty, because the packaging build publishes the frontend over a prebuilt core rather than choosing the core's flags.

Build and run the core suites the same way as on macOS, from a shell with the Visual Studio environment loaded:

```bat
call "%ProgramFiles%\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat"
cmake -S core -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DMXQ_ENABLE_RULES_FACADE=ON
cmake --build build
ctest --test-dir build --output-on-failure
```

## Documentation

- [Product](docs/product.md) — product purpose, scope, capabilities, lifecycle policies, and MVP exclusions.
- [Interaction design](docs/interaction-design.md) — UI, UX, platform visual language, board presentation, motion, sound, touch, help, localization, and accessibility.
- [Mini Xiangqi rules](docs/xiangqi-rules.md) — normative rules source, adopted rules, runtime rules authority, and fixture requirements; the approved executable fixtures live in [fixtures/rules](fixtures/rules/).
- [Architecture](docs/architecture.md) — the shared core, native frontends, dependency direction, concurrency, and lifecycle.
- [Core C interface](docs/core-interface.md) — the core's C surface: modules, functions, error taxonomy, threading contract, and versioning.
- [Game data](docs/game-data.md) — the library store, versioned game archive, saving, history, migrations, import, and export.
- [Engine integration](docs/engine-integration.md) — the movement games' engine: the search facade, AI profiles, packaging, NNUE policy, and failure boundary.
- [Placement engine integration](docs/placement-engine-integration.md) — the placement games' engine: its pins, its preflight, the memory policy it shares with the first, and its failure boundary.
- [Testing](docs/testing.md) — durable validation requirements and release gates.

## Distribution and license

Distribution: Apple platforms ship through TestFlight internal testing and the public App Store — the listing states the application's GPLv3 licence and links the complete source (owner decision, 2026-08-04). Windows ships as a CI-built zip published on this repository's [releases](https://github.com/chentianren0/MiniXiangqi/releases) — one per architecture, unpacked and run, with no installer — and the Microsoft Store is the intended public channel (owner decision, 2026-07-31): the Store signs submissions itself, so the signing-certificate concern that once deferred MSIX does not apply. The project is licensed under the [GNU General Public License version 3](LICENSE), matching its Fairy-Stockfish dependency, and the Windows zip carries that licence and an attribution note beside the app.

The NNUE network the AI evaluates with is **this project's own**, trained from zero by the public pipeline at [`chentianren0/minixiangqi-nnue`](https://github.com/chentianren0/minixiangqi-nnue) with no other network as a teacher or a seed. It lives in this repository at `core/assets/`, pinned by byte length and SHA-256 in [`pinned-inputs.json`](pinned-inputs.json) along with its provenance, and every build verifies it before staging it. Every distribution carries it, the Windows zip included: there is one artifact and it is the complete application.

It replaced a community-trained network of unestablished origin, and it is weaker — about 300 Elo below it at the app's settings, and far above having no network at all. The trade bought a provenance that can be stated, and [Engine integration](docs/engine-integration.md) records the measurements the swap was accepted on.
