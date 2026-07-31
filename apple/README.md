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

That compiles the core for every platform and architecture the app runs on — see [Architectures](#architectures) — packages the three as `apple/Generated/MiniXiangqiCore.xcframework`, stages the bundled variant configuration and the pinned NNUE network into the app's resources, and records a digest of what it built from. Then build or run the `MiniXiangqi` scheme as usual.

**The network never enters version control.** Its bytes live in the workspace at `.git/minixiangqi-control/nnue/`, or wherever `MXQ_NNUE_SOURCE` points, and the script verifies their byte length and SHA-256 against `pinned-inputs.json` before staging them — under the name the engine's variant-matching rule requires, which is not the name they are stored under. Absence or a mismatch stops the script rather than producing an app whose AI is quietly a different opponent. The app's `Check the shared core is current` phase refuses a build whose network has not been staged, for the same reason.

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

**That `arm64e` slice is macOS's alone, because the override that produces it is keyed to
`sdk=macosx*`.** On `iphoneos` the unit bundle resolves to `ARCHS = arm64` while the app it hosts in
resolves to `arm64 arm64e`, so the same host/bundle mismatch the macOS override exists to prevent is
live on a physical iPhone or iPad: the bundle cannot inject into an `arm64e` host there. It does not
bite today, because the iOS runs are on the Simulator, where the app is `arm64` too. The fix belongs
to whichever PR first runs this suite on a device — the on-device measurement the probe still owes —
because that is where it can be seen to work rather than argued to.

The remaining dash is a platform limit, not an architecture one, and it is the only one left.

The **unit bundle** was AppKit-bound — `NSColor` for the contrast measurements, `NSBitmapImageRep` for
the rendered snapshots — and Stage 6's iOS pass made those three call sites cross-platform, so it now
declares `iphoneos iphonesimulator macosx` and runs on an iOS Simulator. That is what makes the iOS
memory probe and the layout-shape rule testable on the platform they are about, rather than only on
the one the app was first written for.

The **UI bundle** still declares `SUPPORTED_PLATFORMS = macosx`, deliberately. Its AppKit dependency
is not a few call sites but the shape of the suite: it drives windows — `-mxq-window`, `NSScreen`,
the measured minimum window size — and window geometry is the thing iOS does not have. Making it
merely *compile* on iOS would produce a bundle that declares a platform and runs almost nothing on
it, which is a worse claim than the dash. An honest iOS UI suite is a different suite, about the
stacked shape and touch, and it is the next piece of Stage 6's iOS work rather than a port of this
one.
