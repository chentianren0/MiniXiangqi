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

## Building

Requires Xcode, plus CMake and Ninja for the shared core. Open `MiniXiangqi.xcodeproj` in Xcode; see [Testing](docs/testing.md) for the validation contract.

The core is a prebuilt dependency, not something the app build produces. Build it first, and again whenever anything under `core/` changes:

```sh
./build-core-xcframework.sh
```

That compiles the core for every platform and architecture the app runs on — see [Architectures](#architectures) — packages the three as `Generated/MiniXiangqiCore.xcframework`, packs the bundled variant configuration and every pinned network into `MiniXiangqi/Resources/engine-assets.mxqpack`, and records a digest of what it built from. Then build or run the `MiniXiangqi` scheme as usual.

**Every network is in the repository**, at `core/assets/`, beside the variant configuration they are loaded with and already under the names the engine's variant-matching rule requires — so the script packs each under its own name, and nothing has to be told where the bytes are. It verifies each network's byte length and SHA-256 against `pinned-inputs.json` before packing it: that is what catches an `MXQ_NNUE_SOURCE` or `MXQ_XIANGQI_NNUE_SOURCE` override pointed at the wrong bytes, and damaged weights have no other symptom. Absence or a mismatch stops the script rather than producing an app whose AI is quietly a different opponent. The app's `Check the shared core is current` phase refuses a build unless the pack is the one the generator recorded and nothing sits beside it in `Resources`, for the same reason.

**The app ships a pack rather than the files** because three of the networks are published files that other apps embedding the same engines carry byte-for-byte, and App Review compares binaries across developers. `MiniXiangqi/Core/AssetPack.swift` is the format and the reasoning; `AssetPackTool` is the packer, compiled from that same file by the script; and at start-up the app stages the directory the core reads from the pack into its own caches, where the core verifies every file against its pins exactly as it did when they were bundled loose.

The framework is signed with this machine's first Apple Development identity if it has one, because Xcode stops at an unsigned framework with a trust prompt. On a machine with no identity it is left unsigned and the script says so; the prompt's `Accept Unsigned` is the right answer for an artifact you just built yourself.

It cannot be folded into the app's build. Xcode plans its build graph before any phase runs, so the task that extracts the library the app links takes the framework as it stood beforehand: a framework rebuilt mid-build is picked up only by the *next* build, silently. The app's `Check the shared core is current` phase exists to make that impossible — it compares a digest of the core's sources against the one recorded at package time and fails the build, naming the command to run. It compares content rather than timestamps, because switching branches rewinds modification times and would make a stale core look fresh.

## Architectures

Physical platforms carry both `arm64` and `arm64e`; the Simulator carries `arm64` alone. That holds
for the app and for every slice of the prebuilt core. The unit bundle is the exception, and the table
records what the project actually resolves rather than what the policy asks for.

| Target | macOS | iOS device | iOS Simulator |
| --- | --- | --- | --- |
| `MiniXiangqi` | `arm64` `arm64e` | `arm64` `arm64e` | `arm64` |
| `MiniXiangqiTests` | `arm64` `arm64e` | `arm64` | `arm64` |
| `MiniXiangqiUITests` | `arm64` `arm64e` | `arm64` | `arm64` |
| `MiniXiangqiCore.xcframework` | `arm64` `arm64e` | `arm64` `arm64e` | `arm64` |

`arm64e` is the pointer-authentication architecture, and the app asks for it by asking for Enhanced
Security: `ENABLE_ENHANCED_SECURITY` turns on `ENABLE_POINTER_AUTHENTICATION`, which adds `arm64e` to
`ARCHS_STANDARD` as a cohort architecture. So the app states no `ARCHS` of its own — it excludes
`x86_64` and inherits the rest, and Xcode drops `arm64e` from Simulator builds itself, there being no
such runtime. Test bundles get no Enhanced Security, so their `ARCHS_STANDARD` is `arm64 x86_64` and
cannot express the policy; both set `ARCHS[sdk=macosx*]` explicitly. The unit bundle needs its
`arm64e` slice to run at all, because the host app launches `arm64e` on Apple silicon and can only
inject a bundle whose architecture matches.

**That `arm64e` slice is macOS's alone, because the override that produces it is keyed to
`sdk=macosx*`.** On `iphoneos` the unit bundle resolves to `ARCHS = arm64` while the app it hosts in
resolves to `arm64 arm64e`, so the same host/bundle mismatch the macOS override exists to prevent is
live on a physical iPhone or iPad: the bundle cannot inject into an `arm64e` host there. It does not
bite today, because the iOS runs are on the Simulator, where the app is `arm64` too. The fix belongs
to whichever PR first runs this suite on a device — the on-device measurement the probe still owes —
because that is where it can be seen to work rather than argued to.

There are no dashes left in the table: both bundles now declare
`iphoneos iphonesimulator macosx`.

The **unit bundle** was AppKit-bound — `NSColor` for the contrast measurements, `NSBitmapImageRep` for
the rendered snapshots — and Stage 6's iOS pass made those three call sites cross-platform, so it now
declares `iphoneos iphonesimulator macosx` and runs on an iOS Simulator. That is what makes the iOS
memory probe and the layout-shape rule testable on the platform they are about, rather than only on
the one the app was first written for.

The **UI bundle** declared `macosx` alone until the iOS suite existed to justify widening it, and the
reason it did is still true of its five original suites: they drive windows — `-mxq-window`,
`NSScreen`, the measured minimum window size — and window geometry is the thing iOS has not got.
What changed is that an honest iOS suite now exists beside them rather than instead of them. The
platform is declared **per file**: the five window suites are `#if os(macOS)`, the two phone suites —
`PhonePlayUITests` and `PhoneSettingsUITests`, about the stacked shape and touch — are
`#if os(iOS)`, and each destination runs its own and nothing else. Widening the one bundle rather
than adding a second target is what keeps `LaunchPreferences` a single file: it carries the
hermetic-launch table both sets of suites read, and two copies of that table would drift. See
[`docs/testing.md`](docs/testing.md) for what each set covers and the command each is run with.

The `arm64e` question above does not arise for this bundle. A UI-test bundle is not injected into the
app: Xcode builds it a runner app of its own and drives the app under test from a separate process,
so there is no host whose architecture it has to match.

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
