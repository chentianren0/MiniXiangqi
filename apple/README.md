# Apple frontend

The Xcode project and the SwiftUI frontend for iOS, iPadOS and macOS.

The frontend owns presentation, navigation, animation, sound, haptics, localization,
accessibility, platform services, transient UI state, and the persistent Settings
preferences. It does not reimplement rules, result classification, archive parsing, or
library invariants, and it never reaches around the core to its storage or the engine.

Requires the Apple toolchain pinned in [`docs/testing.md`](../docs/testing.md). The code here is still the
generated scaffold: the accepted design lives in [`docs/`](../docs/), and the scaffold's
`Item`, `ContentView` and `ModelContainer` are not evidence of any accepted decision.
