# Windows frontend

The WinUI 3 frontend, over the same shared core as the Apple frontend. What is here
is the core built as a DLL, C# declarations generated from `core/include/mxq.h`, the
Play destination — the home where what to play is chosen, each mode's pre-start state,
and the board with a live game against the AI — and two headless harnesses that are how
any of it is verified on a machine nobody is logged into. History and replay, the
Settings screen, the stacked layout that narrow windows take on the other platforms, and
the packaging build are later pull requests.

The target is Windows 11 on `x64`; `ARM64` returns when there is real hardware to test
it on (owner decisions, 2026-07-30). Product behaviour and persisted meaning are
identical to the Apple frontend; only presentation follows the platform, using Fluent
materials, navigation and context menus rather than recreated Apple styling.

## Layout

| | |
|---|---|
| `build-core-dll.ps1` | builds `mxqcore.dll` and stages the engine's assets into `artifacts/` |
| `bindings/` | the ClangSharp recipe and the script that runs it |
| `MiniXiangqi.Core/` | the generated declarations and the thin helpers over them |
| `MiniXiangqi.Play/` | the board's vocabulary and geometry, the destination's flows and the play screen's logic, and the string table — no UI framework at all |
| `MiniXiangqi.Board/` | the board picture, in Win2D |
| `MiniXiangqi.Smoke/` | the headless harness — this project's evidence |
| `MiniXiangqi.Shots/` | the offscreen board renders |
| `MiniXiangqi.App/` | the WinUI 3 window |

The split between `MiniXiangqi.Play` and `MiniXiangqi.App` is the load-bearing one, and
it exists for the reason [Verifying without a screen](#verifying-without-a-screen)
gives: a WinUI 3 process cannot be launched over SSH, so anything that lives in the
window can be run on no machine this project owns. Which page is showing, what a mode
entry does, what `开始对局` creates and in which order, what a click on a point means,
which controls each mode offers, when the machine thinks and what happens when it
answers are therefore plain objects with no window attached — `PlayFlow` and
`PlaySession` — and `MiniXiangqi.Smoke` drives all of it. The window turns that state
into XAML and turns XAML's events back into calls on it, and holds nothing else.

`PlayFlow` is the Play destination: the home, the two pre-start states, the board, and
every path between them, including the one save-and-continue confirmation, the accepted
creation ordering, and both forms of the insufficient-memory refusal. The game lives on
it rather than on the board page, so walking to the home and back neither resumes the
game again nor brings back a result notice the player has already put away.

## Building

The core is consumed as a prebuilt DLL beside a prebuilt asset directory, exactly as
the Apple app consumes a prebuilt XCFramework and for the same reason: producing it
during the build would put a multi-minute C++ compile inside every C# build. So, from
the repository root, and again after any change under `core/`:

```powershell
pwsh windows\build-core-dll.ps1 -NnueSource <path to the pinned network>
dotnet build windows\MiniXiangqi.slnx -c Release
```

The network's bytes are in no repository ([`docs/engine-integration.md`](../docs/engine-integration.md));
`-NnueSource` names where they are, and CMake verifies their byte length and SHA-256
against [`pinned-inputs.json`](../pinned-inputs.json) before staging anything. Building
the C# projects without having run the script first fails with a message that says so
rather than producing an executable that cannot find its core.

## Regenerating the bindings

`MiniXiangqi.Core/Generated/Mxq.g.cs` is generated from `core/include/mxq.h` and
committed, so that building the frontend needs neither the generator nor a C toolchain.
After any change to `mxq.h`, regenerate it and commit what comes out:

```powershell
pwsh windows\bindings\generate.ps1
```

The generator is ClangSharp, pinned in [`.config/dotnet-tools.json`](.config/dotnet-tools.json)
and restored by that script; its option set is [`bindings/mxq.rsp`](bindings/mxq.rsp), one
option per line with a comment on each. The tool's version is stamped into the output's
`[assembly: GeneratedCode]`, so a file and the generator that wrote it cannot drift apart
silently.

## What the boundary actually looks like in C#

`docs/core-interface.md` promised ClangSharp-generated declarations, `[LibraryImport]`
P/Invoke, an `[UnmanagedCallersOnly]` static callback, and every struct blittable by
construction. Built, all of that holds except the `[LibraryImport]` spelling. What each
shape came out as:

- **`size_t` is `nuint`.** ClangSharp's default remappings cover `size_t`, `ptrdiff_t`
  and the exact-width `stdint` types, so the pointer-width types stay pointer-width and
  nothing in the binding restates a size.
- **Fixed-capacity `char` arrays are C# 12 inline arrays** — `[InlineArray(96)] struct
  { sbyte e0; }` for `MxqPosition.fen`, and so on. They are values inside their owning
  struct, convert to `Span<sbyte>` for free, and need no `fixed` block to read. This is
  what `-c codegen=latest` buys: the older codegen levels spell them as `fixed` buffers,
  which is the shape a hand-written binding gets wrong.
- **The search callback is an unmanaged function pointer.** `MxqSearchCallback` becomes
  `delegate* unmanaged[Cdecl]<MxqSearchResult*, void*, void>`, which an
  `[UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvCdecl) })]` static method
  binds to directly — no delegate, no `GCHandle` on the callback itself, nothing to keep
  alive. The core delivers it on its own engine thread, a thread the runtime did not
  create; the harness confirms it arrives on a managed thread that is neither the caller's
  nor a pool thread.
- **Every value struct is blittable**, and the bindings assembly carries
  `[assembly: DisableRuntimeMarshalling]`, so nothing in it can quietly acquire a
  marshalling stub.
- **The enum typedefs are `int`.** `MxqStatus`, `MxqColor`, `MxqGameState` and the rest
  are `int32_t` typedefs plus named constants in the header rather than C enum types — a
  deliberate choice, so that a value the caller's build does not know about is a defined
  value of the type. In C# that means they arrive as plain `int` with the constants on
  the `Mxq` class, and a `[NativeTypeName("MxqStatus")]` attribute recording which
  vocabulary an `int` belongs to. C# enums would read better; they would also make an
  unknown value undefined behaviour in a `switch`, which is the thing the header refused.
- **`[DllImport]`, not `[LibraryImport]`.** ClangSharp 21.1.8.4 has no `LibraryImport`
  mode: `--library-path` is documented as "the string to use in the DllImport attribute",
  and there is no generation feature for the other. The two cannot both be had from the
  generator, and generation is the half worth keeping — it is what stops 54 signatures
  from being transcribed by hand. The generated declarations are
  `[DllImport("mxqcore", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]`,
  which under `DisableRuntimeMarshalling` performs no marshalling either. `core-interface.md`
  is amended to say so. Hand-written platform P/Invokes are a different case and do use
  `[LibraryImport]`: see `WindowsMemoryProbe`, where it matters, because
  `DisableRuntimeMarshalling` stops `DllImport` from honouring `SetLastError` while
  `LibraryImport`'s generated stub reads the error explicitly.

Two behaviours of the boundary that a binding gets wrong if it assumes otherwise:

- **The count probe answers `MXQ_ERR_ARG_BUFFER_TOO_SMALL`, not `MXQ_OK`.** The first
  half of the two-call buffer protocol — a NULL buffer with `cap` 0 — asks for a count,
  and the call reports that the buffer could not hold the answer, with the count written
  and `required_size` set. That status is routine rather than a programming error, and
  it is the ordinary answer; only an empty list returns `MXQ_OK`, because then a cap of 0
  really was enough. A binding that treats every non-`MXQ_OK` status as a failure fails
  on the most common call in the interface. `MxqCall.CheckCountProbe` is where this is
  handled once.
- **`MxqError.detail` is only meaningful when the core filled it.** The struct is a
  caller-supplied out-parameter; a status that arrived without one being filled leaves
  whatever the field held. `MxqCall` reads the detail only when `MxqError.status` matches
  the status the function returned.

## The DLL, and what it exports

`MXQ_BUILD_SHARED_LIBRARY` adds `mxq_core_shared` to the core's CMake: the same
translation units compiled again with `MXQ_BUILD_SHARED` defined, which is the switch
`mxq.h` already carries — it turns `MXQ_API` into `__declspec(dllexport)` under MSVC.

CMake's `WINDOWS_EXPORT_ALL_SYMBOLS` was the alternative and was rejected on the
merits. The header marks the export macro on its 54 functions and on nothing else, so
the macro produces a DLL whose exported surface is exactly the contract; exporting all
symbols would instead publish everything the link pulled in, which here is the whole
vendored Fairy-Stockfish fork and the whole SQLite amalgamation — components
`docs/architecture.md` requires to stay invisible through `mxq.h`. `dumpbin /exports`
on the built DLL reports 54 symbols and no others.

## The board

The board is drawn with **Win2D** — `Microsoft.Graphics.Canvas` — rather than with XAML
shapes, and `MiniXiangqi.Board`'s `BoardPainter` is the whole of it: one function of a
`BoardScene`, a `BoardGeometry` and a `BoardStyle`, which the window's `CanvasControl`
and the offscreen render harness call alike.

Three reasons, the third decisive. The board is a picture rather than forty-nine views:
a grid, two palaces, up to twenty-four discs and four families of state marker, every
dimension of them derived from one cell pitch, and
[`docs/interaction-design.md`](../docs/interaction-design.md) states the marker
vocabulary in strokes, radii and dash patterns rather than in elements — immediate-mode
drawing takes that description literally. A retained XAML tree would instead have to be
diffed against the position on every change, and would put the geometry in two places.
And Win2D can draw offscreen, in a process with no window, which is the only way this
repository can show what the Windows board looks like at all.

Everything the picture is made of — the pitch, the disc diameter, every stroke and
radius, the 传统 colours — is `apple/MiniXiangqi/Board/`'s, to the digit. The contract
fixes the relationships and the contrast gates and says plainly that the exact
dimensions are settled against a rendered board; they were settled once, on one, and the
board is one shared visual identity across platforms.

Two things differ from the Mac, both consequences of the Windows MVP's move record being
the core's canonical coordinate text: the edges carry the canonical coordinates rather
than the file-numeral strips, and there are four strips rather than two. The contract
carries that as a Windows clause under **User-visible notation**.

## Verifying without a screen

**A WinUI 3 process cannot be launched over SSH.** An SSH session lands in session 0,
which has no interactive desktop. The process starts and then fail-fasts: exception
`0xc0000602`, `STATUS_FAIL_FAST_EXCEPTION`, faulting module `Microsoft.UI.Input.dll` —
the Windows App SDK's own input stack, not this repository's code.

That is the constraint the whole frontend is shaped around, and it has two answers.

### The harness plays the game

`MiniXiangqi.Smoke` runs headlessly, so it runs over SSH on a machine nobody is logged
into. It exercises every shape the boundary has — the queries callable before
initialisation, the memory probe and the engine plan, both halves of the buffer
protocol, the error taxonomy with its detail strings, a real search delivered through
the `[UnmanagedCallersOnly]` callback, the archive blob, the History readback, and the
wrapper the window uses — and then it plays.

Sections 17 to 21 are the play screen's.

**17** checks the string table against [`docs/copy.md`](../docs/copy.md): every key this
frontend shows is a row of the contract, and both languages of it match. That is one
direction of the agreement check the localization process asks for, and only one — the
reverse, that no user-facing key in the contract is absent here, cannot apply while
Windows implements sixty-six of the contract's rows and the Apple frontend implements
the rest. It becomes checkable when the Windows frontend is complete, and it is not
checked before then rather than checked against a number somebody has to keep adjusting.

**18** plays a whole game against the AI through `PlaySession` — every move committed by
clicking a point and then another point, exactly as the window's board does it, the AI
answering through the same marshalled callback — to a conclusion or a move cap, and then
takes the concluding action. **19** plays Free Play through the same session and taps an
illegal point to confirm it moves nothing and cancels nothing. **20** shuffles two cannons
into a threefold repetition and claims it. **21** is the pair of races a confirmation and
a search can arrive in either order: Undo while the AI is thinking, and 认输 confirmed
with a 深思 search genuinely in flight.

Sections 22 to 27 are the destination's. **22** reads the two Settings defaults from the
keys they are stored under and checks the fallbacks. **23** walks the home to a mode
entry to the pre-start state to a created game, and checks what leaving the pre-start
page discards and what an abandoned attempt commits. **24** presents the
save-and-continue confirmation over an active game, cancels it, answers it, and reads the
filed record's classification back. **25** finishes a game and takes both concluding
actions — 开始新对局 opening that game's own mode's pre-start state, 完成 returning to the
home. **26** and **27** are the insufficient-memory refusal in both of its forms,
pre-start and mid-game, reached by handing the frontend a probe that reports a starved
machine so that the core's own budget arithmetic answers the refusal rather than a stub
standing in for it.

```powershell
windows\MiniXiangqi.Smoke\bin\Release\net10.0-windows\MiniXiangqi.Smoke.exe --copy-table docs\copy.md
```

It prints a checked line per claim, a count, and `MXQ_SMOKE_OK`, and it exits non-zero
if anything failed.

### The renders show the board

`MiniXiangqi.Shots` draws the board to PNG files, offscreen, with no window. The picture
is `BoardPainter.Draw` — the window's own — and the scene is `PlaySession`'s, reached by
clicking points through the same `Tap` the window calls, so every marker in every
picture is the core's own answer about a real position. No placement, legal-move set or
check state is written out by hand: a board picture that showed a destination the rules
do not offer would be worse than no picture.

```powershell
windows\MiniXiangqi.Shots\bin\Release\net10.0-windows10.0.26100.0\win-x64\MiniXiangqi.Shots.exe --out shots
```

**The committed renders are evidence, not goldens.** Nothing compares them to anything:
a runner-image font update, a Direct2D change, or a different WARP version would move
pixels in them and no gate would notice. They say what the board looked like on the run
that produced them, which is what a reviewer with no desktop needs; a comparison gate
would be a different thing, and it would need a tolerance and a rule about what a
legitimate change looks like before it was worth having.

**It does not run over SSH either, and for a different reason.** Win2D needs a Direct2D
device, and Direct2D refuses in session 0: every way into `CanvasDevice` answers
`DXGI_ERROR_NOT_CURRENTLY_AVAILABLE` (`0x887A0022`) there — the parameterless one, the
forced-software one, the shared one, and `CreateFromDirect3D11Device` over a device the
same process just made — while raw `D3D11CreateDevice` on WARP succeeds in that same
process at feature level 11_0. So it is the graphics stack's session rule rather than
the absence of a GPU, and the harness says `MXQ_SHOTS_UNAVAILABLE` and exits 2 rather
than pretending. A GitHub Actions Windows runner has a console session, and Win2D works
there, which is why the CI job is what produces the committed pictures under
`docs/evidence/`.

### What is still only proved by building

The XAML, and the wiring between it and the session: the layout, the alerts, the result
notice's surface, the Fluent materials, and the pointer and Narrator behaviour of the
forty-nine point elements. Seeing those needs an RDP session.

**That is where the one reported interaction defect lived.** Selecting a piece appeared
to need a double click, where the contract's board selects in one. A point's tap reached
the board's own background handler behind the point's `Click`, so the cancel arrived
immediately behind the selection the same click had made; the filter that should have
stopped it tested `OriginalSource.Tag`, and a point's `Button` is templated down to a
bare `Border` with no `Tag`, so it could never match. The double click worked because the
second tap of a double tap raises `DoubleTapped` rather than `Tapped` — no cancel
followed it. `BoardView` now stops the tap at the point that owns it and walks the visual
tree in the filter besides. Which of those two is load-bearing depends on whether this
platform routes a tap past a `Button` that has already handled the pointer press, which
is exactly the class of question this section is about.

## Preferences

The pre-start controls are initialized afresh from the persistent Settings defaults on
every entry to the page, so this frontend reads two of them —
`defaults.firstMover` and `defaults.aiLevel`, with the vocabularies and the
absent-means-this fallbacks `apple/MiniXiangqi/Settings/Preferences.swift` records. It
**writes none of them**: the Settings screen is the next pull request and it owns
writing.

Where they are kept on Windows is the smallest answer that works — a JSON object of
string values at `%LOCALAPPDATA%\MiniXiangqi\preferences.json`, read at the moment of use
and never cached, absent or malformed reading as "nothing is stored". The Apple frontend
has `UserDefaults`; an unpackaged Win32 app has no equivalent it can reach without
deciding the packaging question this repository has parked. The Settings pull request may
keep that storage or replace it. What it may not change is the key or the vocabulary:
those are the interface between the screen that writes a preference and the surface that
reads one, and they are what lets a preference set in one frontend mean the same thing in
the other.

## Continuous integration

[`.github/workflows/windows-frontend.yml`](../.github/workflows/windows-frontend.yml)
builds the core with `MXQ_BUILD_SHARED_LIBRARY=ON`, fetches the pinned network with the
same script the core suites use, regenerates the bindings and fails on any difference
from what is committed, builds every project, runs the smoke harness against
`docs/copy.md`, and renders the board. It uploads the renders on every run.

The bindings check is the obligation issue #80 carried from #85's verify: a `Mxq.g.cs`
that differs from what the generator writes is a transcription of the header rather than
the header, and the DLL export path and the bindings can no longer drift silently.

## Strings

`MiniXiangqi.Play/Text/Strings.cs` holds every string this frontend shows, keyed exactly
as [`docs/copy.md`](../docs/copy.md) keys it, with the normative Chinese and its approved
English side by side. The language is the operating system's — the app offers no
interface-language control of its own — which .NET resolves as `CurrentUICulture` from
the system's language preference list.

It is a table in C# rather than a `.resw` and a PRI because resource packaging belongs to
the packaging build, which does not exist yet and which this pull request should not
answer for twice; because an unpackaged app's resource lookup is a deployment question
rather than a copy question; and because the render harness has to read the table without
a XAML resource context. The smoke harness checks it against the contract, so it cannot
drift from `docs/copy.md` silently either.

## Not pinned yet

The frontend's half of the Windows toolchain — the Windows App SDK version, the .NET
version, and the packaging flags — is still unpinned in
[`pinned-inputs.json`](../pinned-inputs.json), and `docs/architecture.md` keeps that
question open until a packaging build establishes it. The versions this skeleton names
(Windows App SDK 2.3.1, .NET 10) are what it was built with, not a pin: the app is
unpackaged (`WindowsPackageType` `None`) and carries the Windows App SDK
self-contained, so that a machine which has never installed the Windows App Runtime can
still run what it built. A packaging build will decide all of that properly.
