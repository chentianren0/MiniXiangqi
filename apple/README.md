# Apple frontend

The Xcode project and the SwiftUI frontend for iOS, iPadOS and macOS.

The frontend owns presentation, navigation, animation, sound, haptics, localization,
accessibility, platform services, transient UI state, and the persistent Settings
preferences. It does not reimplement rules, result classification, archive parsing, or
library invariants, and it never reaches around the core to its storage or the engine.

Requires the Apple toolchain recorded in [`README.md`](../README.md) and [`docs/testing.md`](../docs/testing.md), plus CMake and Ninja for the shared core.

## Building

The core is a prebuilt dependency, not something the app build produces. Build it first, and again whenever anything under `core/` changes:

```sh
./apple/build-core-xcframework.sh
```

That compiles the core for every platform and architecture the app runs on — see [Architectures](#architectures) — packages the three as `apple/Generated/MiniXiangqiCore.xcframework`, stages the bundled variant configuration into the app's resources, and records a digest of what it built from. Then build or run the `MiniXiangqi` scheme as usual.

The framework is signed with this machine's first Apple Development identity if it has one, because Xcode stops at an unsigned framework with a trust prompt. On a machine with no identity it is left unsigned and the script says so; the prompt's `Accept Unsigned` is the right answer for an artifact you just built yourself.

It cannot be folded into the app's build. Xcode plans its build graph before any phase runs, so the task that extracts the library the app links takes the framework as it stood beforehand: a framework rebuilt mid-build is picked up only by the *next* build, silently. The app's `Check the shared core is current` phase exists to make that impossible — it compares a digest of the core's sources against the one recorded at package time and fails the build, naming the command to run. It compares content rather than timestamps, because switching branches rewinds modification times and would make a stale core look fresh.

## Architectures

Physical platforms carry both `arm64` and `arm64e`; the Simulator carries `arm64` alone. That holds
everywhere — the app, the test bundles, and every slice of the prebuilt core.

| Target | macOS | iOS device | iOS Simulator |
| --- | --- | --- | --- |
| `MiniXiangqi` | `arm64` `arm64e` | `arm64` `arm64e` | `arm64` |
| `MiniXiangqiTests` | `arm64` `arm64e` | — | — |
| `MiniXiangqiUITests` | `arm64` `arm64e` | — | — |
| `MiniXiangqiCore.xcframework` | `arm64` `arm64e` | `arm64` `arm64e` | `arm64` |

`arm64e` is the pointer-authentication architecture, and the app asks for it by asking for Enhanced
Security: `ENABLE_ENHANCED_SECURITY` turns on `ENABLE_POINTER_AUTHENTICATION`, which adds `arm64e` to
`ARCHS_STANDARD` as a cohort architecture. So the app states no `ARCHS` of its own — it excludes
`x86_64` and inherits the rest, and Xcode drops `arm64e` from Simulator builds itself, there being no
such runtime. Test bundles get no Enhanced Security, so their `ARCHS_STANDARD` is `arm64 x86_64` and
cannot express the policy; both set `ARCHS[sdk=macosx*]` explicitly. The unit bundle needs its
`arm64e` slice to run at all, because the host app launches `arm64e` on Apple silicon and can only
inject a bundle whose architecture matches.

The dashes are a platform limit, not an architecture one. The test sources are AppKit-bound —
`NSColor`, `NSBitmapImageRep`, `NSScreen` — so both bundles declare `SUPPORTED_PLATFORMS = macosx`,
and an iOS run destination will not index them. **Stage 6 owns widening this**: its iOS testing pass
makes those sources cross-platform, restores the platform list, and fills in the dashes.
