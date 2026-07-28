# Windows frontend

The WinUI 3 frontend, over the same shared core as the Apple frontend.

Not yet started. Apple platforms are implemented and distributed first, and the Windows
toolchain is not yet pinned — an open item in [`docs/architecture.md`](../docs/architecture.md),
with [`docs/testing.md`](../docs/testing.md) recording that no Windows validation claim may be
made until it is.

Product behaviour and persisted meaning are identical to the Apple frontend; only
presentation follows the platform, using Fluent materials, navigation and context menus
rather than recreated Apple styling.
