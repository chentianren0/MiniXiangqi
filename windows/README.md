# Windows frontend

The WinUI 3 frontend, over the same shared core as the Apple frontend.

Not yet started. Apple platforms are implemented and distributed first. What has landed
is underneath it: the shared core compiles and its suites pass under MSVC, in both the
debug and the release configuration, and the core's Windows toolchain is pinned in
[`pinned-inputs.json`](../pinned-inputs.json) by the build that produced them. The
frontend's half of that toolchain — Windows App SDK, .NET, and the packaging flags — is
still unpinned, and waits for the packaging build that will establish it rather than
being decided in advance.

The target is Windows 11 on `x64`; `ARM64` returns when there is real hardware to test
it on (owner decisions, 2026-07-30). Product behaviour and persisted meaning are
identical to the Apple frontend; only presentation follows the platform, using Fluent
materials, navigation and context menus rather than recreated Apple styling.
