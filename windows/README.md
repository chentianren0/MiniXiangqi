# Windows frontend

The WinUI 3 frontend, over the same shared core as the Apple frontend. What is here
is the core built as a DLL, C# declarations generated from `core/include/mxq.h`, the
Play destination — the home where what to play is chosen, each mode's pre-start state,
and the board with a live game against the AI — the History destination with its
step-through viewer and its import, the Settings destination and the board's four
voices, two headless harnesses that are how any of it is verified on a machine
nobody is logged into, and the packaging build that turns all of it into the zip
somebody is given. The stacked layout that narrow windows take on the other platforms
is a later pull request.

The target is Windows 11 on `x64` and `ARM64`. `ARM64` came off the list on 2026-07-30
for want of hardware to test it on and returned on 2026-07-31 when that condition was
met; both are built, exercised and distributed on the same terms, each on its own native
CI runner. Product behaviour and persisted meaning are identical to the Apple frontend;
only presentation follows the platform, using Fluent materials, navigation and context
menus rather than recreated Apple styling.

## Layout

| | |
|---|---|
| `build-core-dll.ps1` | builds `mxqcore.dll` and stages the engine's assets into `artifacts/` |
| `package-zip.ps1` | the packaging build: publishes, checks the network it carries, and writes the distribution zip |
| `make-app-icon.py` | builds `MiniXiangqi.ico` from the icon design's 1024 px export |
| `bindings/` | the ClangSharp recipe and the script that runs it |
| `MiniXiangqi.Core/` | the generated declarations and the thin helpers over them |
| `MiniXiangqi.Play/` | the board's vocabulary and geometry, every destination's logic, the sound decision and the four samples, and the string table — no UI framework at all |
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

`HistoryFlow` is its counterpart: the list of filed games in the core's own order, one
record's read-only `ReplayViewer`, the deletion gate, pin and unpin, and both interchange
paths. `SettingsScreen` is the third and the smallest: the preferences the app keeps, read
from and written to one file. The three destinations share a core and a preference store
and nothing else — a game stays active whichever one is on screen — and the shell above
them is a `NavigationView` in its Auto display mode, which is this platform's own
adaptation rather than one the app selected. Its **settings item is the container's own**,
turned on with `IsSettingsVisible`: the platform's gear, in the platform's place at the
foot of the pane. The one thing the app supplies about it is its word, from `nav.settings`,
because that row is the string of record for this destination's name.

## History, the viewer, and interchange

Three things about them are decisions rather than transcriptions, and each is argued where
it is made.

- **The viewer is a step-through and nothing more**, which is issue #80's owner-decided
  trim: History and reading Mac-saved games are the stage's promise and they stay, while
  the motion language and the autoplay transport are what the trim defers. So four
  transport controls rather than five, no autoplay, no pause, and a step is the same
  presentational cut a jump is. `docs/interaction-design.md` § History replay carries the
  Windows clause that says so. Everything the section says replay *shows* is unchanged.
- **Every position is `mxq_game_position_at`.** The viewer asks the core what the position
  *was* at the ply it is showing, on the detached read-only session
  `mxq_store_history_open` returned, and never applies or unapplies a move to work one out.
  The record's own result and reason come from the store's summary rather than from the
  replayed position, because a resignation and an ended-early record are not properties of
  a position at all.
- **共享 is a Save As**, and **the History row's date is numeric on every day**. Both are
  Windows clauses in `docs/interaction-design.md` § History library with the reasoning:
  Windows' share UI is not where anyone goes to hand somebody a file; and no formatter an
  app composes dates with has a relative form — the shell's `SHFormatDateTime` does, and is
  callable, but it formats from the *user locale* rather than the app's own language and
  takes no format control, so it can give neither the right language nor the four-digit
  year the clause asks for.

The 删除前确认 preference is read from `deleteConfirmation.enabled`, which is
`apple/MiniXiangqi/Settings/Preferences.swift`'s key and its Bool vocabulary. Absent means
on, and so does anything this reader cannot make sense of: **false is the dangerous answer
on this key**, because it deletes a game without asking. The Settings destination writes
it, and the harness closes that circle over one file on disk.

## Building

The core is consumed as a prebuilt DLL beside a prebuilt asset directory, exactly as
the Apple app consumes a prebuilt XCFramework and for the same reason: producing it
during the build would put a multi-minute C++ compile inside every C# build. So, from
the repository root, and again after any change under `core/`:

```powershell
pwsh windows\build-core-dll.ps1
dotnet build windows\MiniXiangqi.slnx -c Release
```

The NNUE network needs no argument: it is in this repository at `core/assets`
([`docs/engine-integration.md`](../docs/engine-integration.md)), and CMake verifies its
byte length and SHA-256 against [`pinned-inputs.json`](../pinned-inputs.json) before
staging anything. `-NnueSource` is still there as an override, for trying a candidate
network that has not been committed yet. Building the C# projects without having run the
script first fails with a message that says so rather than producing an executable that
cannot find its core.

**Both commands build for the machine they are run on**, which is the whole of the
architecture story on a developer machine. `build-core-dll.ps1` takes `-Architecture`
and `Directory.Build.props` derives `MxqRuntimeIdentifier` from `PROCESSOR_ARCHITECTURE`,
so an x64 machine produces an x64 core and an x64 frontend with no argument, and an
ARM64 machine produces ARM64 ones. To build for the other architecture:

```powershell
pwsh windows\build-core-dll.ps1 -Architecture arm64
dotnet build windows\MiniXiangqi.slnx -c Release -p:MxqRuntimeIdentifier=win-arm64
```

The second half of that cross-builds happily; the first half needs the ARM64 MSVC
toolset installed, and produces a DLL the machine that built it cannot load. `artifacts/`
holds one architecture's core at a time — whichever the script last built — while the
CMake build trees are per-architecture, so switching back does not recompile. In CI the
question does not arise: each runner is the architecture it builds for.

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

### The window's floor, and the board that will not fit

`MiniXiangqi.Play/Board/BoardSpace.cs` holds both, and holds them there rather than in
the window so that the harness can run them. `WindowFloor` derives every figure from the
board's own geometry: the block at the accepted 44-point pitch is **340** square — 340
rather than the Mac's 308, because this board carries the coordinates on four edges — the
air around it is 24 a side, the panel beside it 260, the navigation row above every page
44, and the shell's compact rail 48. The content floor is **648 by 388** and the window's
is **696 by 432**, in device-independent pixels.

**The shell's pane cannot squeeze the board below that**, and the arithmetic that says so
is checked rather than asserted. `NavigationView` is left in its Auto display mode — the
app decides none of it — so the numbers are the platform's: a full-width inline pane
appears only at or above the expanded threshold of 1008, and 1008 minus the 320 that pane
measures leaves 688 of content, which clears the 648 floor with room over. Below that
threshold the pane is a 48-point rail, and *opening* it overlays the content rather than
taking width from it. So the floor pays for the rail, which is the arrangement that
actually costs it width, and pays nothing for a pane it can never meet. **That is the
answer to the tour's "reachable via the expanded navigation pane": under the platform's
own defaults it is not** — and the notice below is what stands under the residue instead
of a bigger floor nobody needs.

**The floor also allows for the window frame.** `PreferredMinimumWidth` answers
`WM_GETMINMAXINFO`, which is about the *window* rectangle — resize borders and title bar
included — while everything XAML lays out is inside the client area, so a floor set from
the content alone stops the resize while the board still has less room than it asked for.
`MainWindow` measures the frame as `AppWindow.Size` minus `AppWindow.ClientSize`, both
documented in physical pixels, and adds it to the scaled content floor. It is read on
every recomputation, because it moves with the display scale exactly as the content does.

**What the owner's tour actually hit was those two faults compounding, and the pane was
not involved.** The floor was short by the frame, so the client area at the hard minimum
put the board host under the 340 the block needs. `BoardGeometry.Fitting` then refused,
as it should — a board under the accepted floor is a decision and it declines to make one
quietly — and the window's old answer to a refusal was to draw the board at the floor
anyway. That fallback assigned a pitch-44 geometry which is **the same value `BoardView`
is constructed with**, so the setter's equality guard returned early and the view was
never given a width or a height. Unsized inside a `Grid` and centred, it measured nothing
and painted nothing: a board page with no board on it and nothing said. `BoardView` now
states its size in its own constructor, which makes the invariant the class's rather than
the caller's, and the guard goes back to being about the work.

**And under both of them, a board that cannot be drawn says so.** `BoardSpace` answers
with the geometry **or** with `board.tooSmall`, the window draws whichever it got, and
all three board hosts do it — including the pre-start preview, which the contract exempts
from the floor so that it can yield space to the setup controls, and which on this
frontend has nothing to yield to because those controls are a fixed 260-point panel. It
is the floor under the residue the arithmetic cannot reach — a display scale that rounds
badly, a platform default that moves — rather than the fix for what the tour found.

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
Windows implements part of the contract's rows and the Apple frontend implements the
rest. It becomes checkable when the Windows frontend is complete, and it is not checked
before then rather than checked against a count somebody has to keep adjusting — a count
this paragraph used to carry and which the History destination immediately made stale.

**18** plays a whole game against the AI through `PlaySession` — every move committed by
clicking a point and then another point, exactly as the window's board does it, the AI
answering through the same marshalled callback — to a conclusion or a move cap, and then
takes the concluding action. It also presses **翻转棋盘**, which this mode now carries
(owner recommendation, 2026-07-31), and checks the claim the flip makes: the orientation
turns over while the position, the ply count, the record, the side to move and whose turn
it is to click are all exactly what they were — and then that the orientation is still
turned over after every move and every reply that followed. **19** plays Free Play through
the same session, makes the same presentation-only claim about its own flip, and taps an
illegal point to confirm it moves nothing and cancels nothing. **20** shuffles two cannons
into a threefold repetition and claims it. **21** is the pair of races a confirmation and
a search can arrive in either order: Undo while the AI is thinking, and 认输 confirmed
with a 深思 search genuinely in flight.

Sections 22 to 28 are the Play destination's. **22** reads the two Settings defaults, both
through stand-in stores that prove the fallbacks and through `FilePreferenceStore` over a
real file on disk, which is the reader every pre-start entry actually runs: a stored name
read back, an absent file, a malformed one, and a value of the wrong kind. **23** walks
the home to a mode entry to the pre-start state to a created game, and checks what
leaving the pre-start page discards and what an abandoned attempt commits. **24** presents
the save-and-continue confirmation over an active game, cancels it, answers it, and reads
the filed record's classification back. **25** finishes a game and takes both concluding
actions — 开始新对局 opening that game's own mode's pre-start state, 完成 returning to the
home — and, because it is the only place two games exist one after the other, turns the
first game's board over and checks that the second starts the right way up. **26** and **27** are the insufficient-memory refusal in both of its forms,
pre-start and mid-game, reached by handing the frontend a probe that reports a starved
machine so that the core's own budget arithmetic answers the refusal rather than a stub
standing in for it. **28** is 无法开始对局, reached the same way in spirit: a game left
standing in the library so that `mxq_game_create` answers
`MXQ_ERR_STATE_ACTIVE_GAME_EXISTS`, which is a route the flow's own
release-before-open invariant makes unreachable in the app — what it runs is the
**answer** to a refused creation, which had no run at all, and `Create`'s catch does not
discriminate between refusals.

Sections 29 to 35 are the History destination's. **29** is the screen every new
installation opens on: a store directory that has never been written, read as an empty
library rather than as a failure, with neither section and the two accepted lines.
**30** files a resignation and an ended-early Free Play game, reads the list back through
both halves of the buffer protocol, and states the row vocabulary — the mode, the human's
side where there is one, the result, the reason where the result does not already carry it,
and the move count — then pins a record and watches it move between the two sections, and
then drives **历史未能载入** by opening a record identifier the store never issued.
**31** opens the viewer and walks it: every transport control, both ends, a move selected
from the list, the orientation control, and the read-only board's own emptiness. **32** is
删除 on both sides of 删除前确认, including the file-backed reader every deletion actually
runs and the switch being flipped between two deletions on one destination, which is what
"read at the moment of use" means. **33** exports a filed game to a real `.mxq` on disk and
imports it back, once unchanged, once with its `started_at` shifted, once with its archive
version bumped, and four times as a file that cannot be read, then refuses an export and
confirms it left no file of nothing behind and that neither a deletion nor a second export
begins while one is in flight; **34** deletes the record and puts the same game back from
the file written before it went, which is the interchange promise end to end. **35** files
201 games so that `AllHistory`'s paging loop runs at an offset past the first page — the
one branch a small library never reaches, and one that would otherwise first execute on
somebody's real library.

Sections 36 and 37 are the Settings destination's and the board's four voices'. **36 closes
the preference circle over one file on disk**: the screen writes, the raw JSON is read back
so that the *key* and the *vocabulary* rather than an agreement between two of our own types
are what is checked, and then the reader section 22 proved opens a pre-start draft on it —
first directly, then through a real `PlayFlow` walking the home to a mode entry to a
pre-start page. It also states the two things a shared preference file makes possible to get
wrong: a preference this platform has no surface for is left exactly as it was by a write,
and a preference changed underneath the screen is what the screen shows next. It also
drives the no-alert design rather than describing it — a file standing where the directory
should be refuses every write deterministically, and both halves of the snap-back are
checked. **37 states
the sound event-mapping seam**: the precedence rule over its whole truth table, the 声音
gate honoured at the moment of use and flipped between two landings on one object, and then
a real Free Play game in which every landing is checked against what the board itself says
happened — the piece that was standing on the destination, and the position that arrived —
rather than against the rule under test. A move taken back, a claimed draw and a
resignation are asked separately, because the played game cannot ask for them. What the
harness cannot say is whether the four voices *sound* right; that is an ear's answer and it
is the owner's tour, and section 37 prints as much.

**38 is the board's own space**, and it opens no core because it needs none. It reads the
window floor back out of the geometry it is derived from — the 340-point block, the 648 by
388 content, the 696 by 432 window — checks that the board fits at exactly the accepted
pitch in the room the floor promises it, checks that the shell's own expanded-pane
arithmetic leaves more content than the floor asks for, and then drives the geometry one
point under the block so that the refusal fires. What it asserts about the refusal is that
no board is drawn at all and that the state publishes `board.tooSmall` in both languages —
a key with no row answers with itself, which is the one thing that value can never
legitimately be. It is the run behind the owner's tour finding, and the numbers it reads
used to be unreachable literals inside the window.

**Two import answers have no seam, and are stated as the mapping they are.** 历史中有一盘
损坏的棋 needs a stored record whose own bytes no longer decode, and 无法保存导入的对局 needs
the store to refuse a write; producing either would mean reaching around the core into its
database or standing in for the call under test. `HistoryFlow.AnswerFor` is therefore a
pure function of the status and its domain, and the harness states the whole of the mapping
over it — all seven answers, including an unknown status inside each known domain — while
driving five of them through the core besides.

**What is still unrun is named rather than dressed up.** The accepted **无法保存对局** retry
after a refused archive — `FlowAlert.ArchiveFailed` — needs `mxq_store_archive_and_clear`
itself to fail, and **无法删除这盘棋** needs `mxq_store_history_delete` to. There is no
honest seam for either: the memory probe seam feeds a real input to real code, and a store
seam would be a stand-in replacing the call under test. What is checked instead is that the
path around each is right — the game stays active and the retry repeats the same atomic
archive; the record stays in the list and the retry repeats the same deletion — by reading,
not by running. The bounded-retry exhaustion in `AllHistory` is a third of the same kind:
it needs another writer to win three races in a row against a single-threaded reader.

**Three known gaps, stated rather than closed.**

- **`HistoryFlow.ExportRefused` is read nowhere in the window.** 共享 on Windows is a Save
  As, and the save dialog is what reports a place it could not write to — so the case this
  flag is left for is an `mxq_store_export` that failed over a path the dialog accepted,
  and there it is currently silent. Answering it means choosing a presentation the accepted
  flow does not have, which is a design decision rather than a wiring one. What the failure
  path does do is delete the empty file the picker created, so no `.mxq` of nothing is left
  under a name somebody would try to import.
- **One damaged record blanks the whole list.** `mxq_store_history_page` answers about a
  page, not about a row: a record whose blob no longer decodes fails the call, and the
  interface offers no way to ask for the rest of the page without it. Reading the library
  one `mxq_store_history_get` at a time to find the bad one would be re-deriving the list
  operation the core owns, and would still have nothing useful to say about the row it
  found. So 历史未能载入 is what shows, which is exactly true, with the core's own
  diagnostic beneath it.
- **The two file pickers** — see below.

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

**Every render is drawn on every run; only new pixels are committed.** A pull request
that adds a scene adds a picture under `docs/evidence/pr<number>/`, and one that draws the
same board a committed picture already shows commits nothing — the run is what proves the
scene, and a second byte-identical copy of a file already in the repository would be
weight rather than evidence. The pre-start previews are exactly that case: a pre-start
preview is the frozen initial board, so they come out identical to `start-large` and
`start-flipped`, and the claim they carry is about which code produced them rather than
about what they look like.

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
notice's surface, the Fluent materials, the shell's own pane and its settings item, the
History list's rows and their context menus, the Settings destination's three cards, and
the pointer and Narrator behaviour of the forty-nine point elements. Seeing those needs an
RDP session.

**The play-control cluster's fourth button and the too-small line are the newest two**,
and the split between what runs and what does not is the usual one. Which controls the
cluster carries, what each one does, and what the flip does and does not change are
`PlaySession`'s and are run in sections 18, 19 and 25; the four buttons standing in a
260-point column is XAML. The decision to show a line instead of a board, and the line
itself, are `BoardSpace`'s and are run in section 38; the line centred in the space the
board would have taken is XAML. Both are on the owner's zip check.

**Two more belong on that list, and both are in the window rather than beside it.** The
**frame allowance** — the window floor adding `AppWindow.Size` minus `AppWindow.ClientSize`
to the scaled content floor — is arithmetic over two values only a real window has, so
nothing here can run it; what a zip check sees is whether the window can still be dragged
down to a size that clips the board. And **`BoardView` taking its size in its own
constructor** is the same: it is a XAML `Grid` subclass, it needs the WinUI runtime to
exist at all, and the fault it fixes showed only as a board that measured 0 by 0 on a
screen. Dragging the window to its hard minimum and seeing a board there is the check both
of them want.

**The four voices are the same case with a second reason.** Which voice a landing asks for
is run headlessly in section 37; whether it is *heard*, and whether what is heard is right,
needs an audio endpoint and an ear. The development VM has neither — an SSH session lands
in session 0, and nothing there renders audio — so the audible half is the owner's tour,
stated as such rather than dressed up.

**The two file pickers are the same case, and are the one part of the import and export
paths a harness cannot drive.** `FileOpenPicker` and `FileSavePicker` need the window's
own handle, so they live in `MainWindow` and nowhere else; everything on either side of
them — the size gate, the read, every answer the core gives, the encode, the write, and
the suggested filename — is `HistoryFlow`'s and is run headlessly against real files.

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

## Settings, and the preferences it writes

The Settings destination draws **three of the Mac's four groups**, and every absence is
issue #80's owner-decided trim rather than a design change — `docs/product.md` § Product
navigation carries the Windows Settings scope with the reasoning for each. 棋盘 is absent
with both of its rows: the move record here is the core's own coordinate text in both
languages so 记谱法 has nothing to choose between, and only the 汉字 set is drawn so
棋子符号 is a preference with one option. 触感 is absent because it is **not for the MVP**,
which is a narrower claim than it looks and is worth stating exactly: Windows *does* have a
touchpad counterpart to the Mac's system haptic performer —
`Windows.Devices.Haptics.InputHapticsManager`, UniversalApiContract 19 with Windows 11
24H2, whose `HapticDeviceType` names Touchpad and Mouse and which answers `IsSupported()`
and `IsHapticDevicePresent()` before `TrySendHapticWaveform` plays anything. It is
experimental, gated to 24H2 and later, and the hardware is rare, so shipping the switch now
would ship one that does nothing on nearly every machine — which the contract forbids for
the same reason it forbids a switch with no API behind it. The row is removed rather than
greyed out, exactly as it is on an iPad, and if it is ever offered here iOS's ask-the-device
rule carries over unchanged: `IsSupported()` plus `IsHapticDevicePresent()` is that question
in Windows' own words. **Both accepted footers survive**, so the two-footer rule reads the
same here as it does on the Mac.

The Fluent adaptation is one rule applied three times: **a group is a card**. A grouped
`Form` section on macOS supplies a header above and a footer below; Windows has no grouped
Form and its own settings idiom is a caption-weight header, a card carrying the rows, and
a caption beneath — so one section becomes one header, one card, one footer, and the rows
inside a card are divided by the same hairline the Play home puts between its two mode
entries. The Community Toolkit's `SettingsCard` is the packaged form of exactly this and
was declined as a dependency for four rows, since the vocabulary it would bring is the
theme resources this window already draws from. The two switches carry no On/Off content:
a bare switch is what Windows 11's own Settings shows, and the words the framework would
otherwise put there are copy `docs/copy.md` does not own. Narrator is unaffected — a
toggle reports its state through the toggle pattern, in the screen reader's own words —
and each control's accessibility name is its row label, which is the basic labelling
issue #80 settles this platform at.

**Every control shows what is *stored*, not what was last asked for.** `SettingsScreen`
holds no state: its four properties read the store each time they are asked. Two things
fall out of that and both are wanted. A write the file system refused leaves the control
where it was, which is the truth and needs no alert — there is no accepted copy for one,
and inventing a preference-failure alert would be inventing a contract. And a preference
changed underneath the screen is picked up on the next refresh without a relaunch, which
is the same read-at-the-moment-of-use rule the sound gate and the deletion gate run under.

**That is a deliberate divergence from the Mac**, which mirrors each value into `@State`
and so shows what was *asked for*. It is confined to a failure mode the two platforms do
not share equally — a `UserDefaults` write barely has one, a file write has disk, quota and
permissions behind it. The snap-back has two halves and both are load-bearing: the screen
reads the stored value, and `Changed` is raised **whether or not the write landed**, which
is the only thing that redraws the control back to it. Announcing only on success would
leave a switch showing a value nobody stored, silently, so §36 drives a refused write —
a file standing where the directory should be — rather than describing one.

This frontend now reads **four** preferences and writes those same four —
`defaults.firstMover`, `defaults.aiLevel`, `sound.enabled` and
`deleteConfirmation.enabled` — with the vocabularies and the absent-means-this fallbacks
`apple/MiniXiangqi/Settings/Preferences.swift` records. The three it has no surface for —
`notation.style`, `pieces.symbols`, `haptics.enabled` — are neither read nor written, and
a write here **preserves them**: the file is read, modified and written back, so a
preference set on another machine is not deleted by a screen that draws four rows.

Where they are kept on Windows is the smallest answer that works — a JSON object at
`%LOCALAPPDATA%\MiniXiangqi\preferences.json`, read at the moment of use and never cached,
absent or malformed reading as "nothing is stored". A flag is read as a JSON boolean first
and as the string spelling of one after that, because a file a Settings screen writes and
a person may edit can honestly hold either. The Apple frontend has `UserDefaults`; an
unpackaged Win32 app has no equivalent, and the packaging build settled that this app
stays unpackaged — a zip of a `WindowsPackageType` `None` build has no package identity
and so no `ApplicationData` to reach — rather than changing the answer. If MSIX is ever
taken up, moving preferences into the packaged store is a change to one class rather than
to a contract, because the key and the vocabulary are the interface, not the file. A write lands atomically — a sibling temporary file moved
over the old one — so a process that dies mid-write leaves the previous preferences rather
than a truncated object every later read would answer "nothing is stored" to. What has not
changed is the key or the vocabulary: those are the interface between the screen that
writes a preference and the surface that reads one, and they are what lets a preference set
in one frontend mean the same thing in the other.

## The icon

`MiniXiangqi.App/MiniXiangqi.ico` is the app's icon, and it is **derived rather than
drawn**. The design is the Apple side's Icon Composer document, `apple/AppIcon.icon`;
the owner exports a flat 1024×1024 PNG from it; and [`make-app-icon.py`](make-app-icon.py)
turns that one image into the eight sizes Windows asks for. Only the last link of that
chain is in this repository — the first is the Apple app's document and the second is a
four-megabyte intermediate nobody edits — so the script is the paper trail, and
regenerating after a design change is one command with the new export.

The eight entries are 16, 20, 24, 32, 48, 64, 128 and 256 pixels: 16 with 20 and 24 for
the title bar and the scaled variants a high-DPI machine picks up, 32 for the taskbar and
ordinary Explorer, and the rest for the larger shell views. **256 is PNG-compressed and
the seven below it are uncompressed DIB entries**, which is the conventional layout and
the reason the container is written by hand rather than by Pillow's one-call ICO writer:
that writer encodes every entry the same way, and PNG entries at small sizes are handled
by the modern shell but not by every older path that may still ask for a 32-pixel icon.
Every size is resized from the 1024 original with LANCZOS rather than from the size above
it, so no downscaling error compounds. The disc reads as a red disc at 16 and the 帥
becomes legible around 32, which is what those sizes are for.

Two places show it and both are set, because they are different questions.
`ApplicationIcon` in the project file puts the icon in the **executable's resources** —
Explorer, a shortcut, a pinned taskbar entry, and the folder somebody unpacks the zip
into. The **running window's** icon is the `AppWindow`'s, and an unpackaged app has no
package manifest to declare it in, so `MainWindow` calls `AppWindow.SetIcon` with the
copy of the same file that sits beside the executable. One file answers both, so the two
can never show different pictures; if that copy is missing the window keeps the
framework's default and nothing else changes, since a picture is not worth a launch
failure.

## The four voices

The board plays one sound per landing, chosen by what the landing means, in the accepted
order of precedence — conclusion, then capture, then check, then the plain landing. The
samples are `apple/Sounds/generate.py`'s own, the project's four generated voices from
Stage 2: no third-party audio, nothing to attribute, and re-tuning is a parameter edit and
one run of that script. The four files under `MiniXiangqi.Play/Sounds/` are byte-identical
to the four under `apple/MiniXiangqi/Sounds/`, and the CI job compares their hashes so the
two bundles cannot drift apart quietly. They are copied rather than referenced across the
trees because a cross-tree csproj reference would make this build depend on the Apple app's
own directory layout, and the two frontends are deliberately disjoint.

**The decision and the playing are split**, exactly as everything else here is.
`MiniXiangqi.Play/Motion/Feedback.cs` holds the rule — a pure function of the position that
arrived, so the harness can play a game and state which event asked for which voice on a
machine with no audio device — and `MiniXiangqi.App/BoardSoundPlayer.cs` holds the thing
that makes a noise. **The audible half is the owner's tour**: a harness can say *which*
voice, and only an ear can say the voices are right.

The playing is **winmm's `PlaySound` over an image of the WAV already in memory**, which
is what `System.Media.SoundPlayer` does underneath — taken directly because the package
that carries `SoundPlayer` drags `System.Drawing` behind it into an app that draws with
Win2D, and because hand-written platform P/Invokes are already this frontend's established
shape (`WindowsMemoryProbe`). The samples are 16-bit PCM by construction, so there is no
file to open, no source to resolve and no decoder to build at the landing; the buffers live
in the pinned object heap, because `SND_ASYNC` returns before the sound has finished and
the pointer has to stay good. `MediaPlayer` was the alternative and is the wrong shape — a
full media pipeline per instance for a 110 ms uncompressed knock — and `AudioGraph` is the
right answer for audio that overlaps, which by contract this never does: one sound per
landing, and a committing transition runs to completion. `SND_NODEFAULT` is not optional:
without it a sample the driver would not play falls back to the *system default sound*, so
a missing file would answer a move with Windows' own ding.

**Two silences are decisions.** Settings itself is silent — sound is an event of the board,
and a screen that clicked back at every switch would be the app talking about itself — and
the step-through viewer is silent because a Windows step is the presentational cut a jump
already is, and `docs/interaction-design.md` § History replay's own Windows clause says a
cut has no landing. Neither type holds a `Feedback` at all, which is how that is enforced
rather than remembered. **Backgrounding needs no code**: an unpackaged desktop app has no
platform suspension, losing focus is not one — which is what
`apple/MiniXiangqi/Play/Suspension.swift` says about macOS — and a game still being played
is still heard, with the volume mixer where somebody who wants it quieter goes.

## Continuous integration

[`.github/workflows/windows-frontend.yml`](../.github/workflows/windows-frontend.yml)
builds the core with `MXQ_BUILD_SHARED_LIBRARY=ON`, regenerates the bindings and fails
on any difference from what is committed, compares the four sound samples against the
Apple bundle's, builds every project, runs the smoke harness against `docs/copy.md`,
renders the board, and builds the distribution zip. It uploads the renders and the zip
on every run, and it takes no secrets: the network the AI needs is in the checkout.

**It is a matrix over two architectures**, each on its own native runner: `windows-2025`
for `x64` and `windows-11-arm` for `ARM64`. Three steps run on `x64` only, and the
workflow says why where they are — the bindings check and the sound comparison are
source-level checks that a second architecture would repeat rather than extend, and the
renders are pictures of a board no dimension of which depends on the instruction set.
Everything that could differ by architecture — the C++ build, every managed build, the
harness, the publish and the zip — runs on both. `fail-fast` is off on both matrices:
one architecture failing is a finding about that architecture, and the other's result
beside it is what says whether it is architecture-specific.

The core's own suites on `ARM64` are in [`core-suites.yml`](../.github/workflows/core-suites.yml)
rather than here. What decides a job's home is which changes should start it: that
workflow starts on `core/`, `fixtures/` and `.gitattributes`, and this one does not, so a
fixtures change that broke the engine on `ARM64` and nowhere else would have gone unseen
if the job had lived here.

The bindings check is the obligation issue #80 carried from #85's verify: a `Mxq.g.cs`
that differs from what the generator writes is a transcription of the header rather than
the header, and the DLL export path and the bindings can no longer drift silently.

## Strings

`MiniXiangqi.Play/Text/Strings.cs` holds every string this frontend shows, keyed exactly
as [`docs/copy.md`](../docs/copy.md) keys it, with the normative Chinese and its approved
English side by side. The History destination and its viewer added no key to that
contract: every string they say was already a row of it, including the twelve it then
marked *(proposed)* — the two section headers, the empty state's pair, the
deletion-failure pair, the History-read failure title, the replay progress line, and the
four transport labels this viewer has. **Those twelve are accepted now**: the owner's
Windows tour passed on them and the copy delegation makes routine copy correctness the
lead's to decide (owner, 2026-07-31, issue #80), so the markers are off.
`replay.autoplay` and `replay.pause` keep theirs and keep their absence here, because the
trim removed their control. **The
Settings destination added none either, and shipped no proposed row**: its eight strings —
`nav.settings`, the four `settings.defaults.*`, `settings.sound.label` and the two
`settings.confirmDelete.*` — are all accepted, and the six option words its two pickers
offer are the pre-start page's own `setup.` rows, keyed once for both screens. The four
rows it does not ship are the ones its trim removed: `settings.section.board`,
`settings.symbols.*`, `settings.notation.*` and `settings.haptics.label`. The language is
the operating system's — the app offers no interface-language control of its own — which
.NET resolves as `CurrentUICulture` from the system's language preference list.

**One key is this frontend's own addition to the contract**: `board.tooSmall`, the line a
board host shows when there is no room for a board. It is the second Windows-first row
after `control.close`, and for the same shape of reason — this is the platform where a
window is dragged against a navigation container that changes width with it. The row and
its reasoning are in `docs/copy.md` § When there is no room for the board; the state that
publishes it is [above](#the-windows-floor-and-the-board-that-will-not-fit).

It is a table in C# rather than a `.resw` and a PRI, and the packaging build did not
change that. The render harness has to read the table with no XAML resource context, and
the smoke harness checks it against the contract, so it cannot drift from `docs/copy.md`
silently either.

**This section used to say that a PRI is a resource system for a *packaged* app and that
an unpackaged zip made resource lookup a deployment question rather than a copy
question. That was wrong, and it was wrong in the direction that cost a working
distribution.** An unpackaged WinUI 3 app has a PRI and depends on it completely: the
index named after the executable, `MiniXiangqi.App.pri`, is what `InitializeComponent`
resolves `ms-appx:///App.xaml` and `ms-appx:///MainWindow.xaml` through. It is very much
a copy question — see [the distribution](#the-distribution), where not copying it is the
whole of a defect. A `.resw` would still be the wrong shape for this table, for the
render-harness reason above; the sentence about PRIs was arguing for a right conclusion
from a false premise.

## The distribution

[`package-zip.ps1`](package-zip.ps1) is the packaging build, and one zip per architecture
is the accepted MVP distribution (issue #80, owner decision, 2026-07-30; MSIX and its
signing-certificate story are the post-MVP upgrade). It publishes `MiniXiangqi.App` and
`MiniXiangqi.Smoke` self-contained into one directory — they share every runtime file,
this app's own assemblies, the core DLL and the asset directory, so publishing them
apart would ship two .NET runtimes to prove one works — writes the licence and the
notes, and zips the result under one top-level folder.

**Self-contained means three things, and the third is the one people forget.**
`--self-contained` carries the .NET runtime. `WindowsAppSDKSelfContained`, which the
projects already set, carries the Windows App Runtime. Neither carries the *Visual C++*
runtime, and `mxqcore.dll` is MSVC's output linked against it dynamically — so the script
ensures `vcruntime140*.dll` and `msvcp140*.dll` are in the directory, taking them from
the Visual Studio redistributable if the publish did not already produce them, and says
which of the two happened. App-local deployment of those DLLs is what the Visual Studio
redistributable terms permit, and the zip's `NOTICE.md` records it. With all three in
place, "unpack and run" needs no install of any kind; what the machine still needs is
Windows 11 and the matching architecture.

**And a fourth thing, which is not a runtime at all and is the one that actually broke.**
`dotnet publish` does not carry an unpackaged WinUI 3 app's own compiled XAML. Two files
answer for it and neither reaches a publish by default:

- **`MiniXiangqi.App.pri`**, the resource index every `ms-appx:` lookup goes through. The
  SDK writes it straight into `$(TargetDir)`, so a *build* output has it because it was
  written there; nothing represents it as an MSBuild item, and publish copies items.
- **`App.xbf` and `MainWindow.xbf`**, the markup compiler's output. The SDK target that
  copies them beside the executable hooks `GetCopyToOutputDirectoryItems` — the build copy
  pipeline — and nothing hooks the publish one.

Without the index the app dies on launch with a stowed exception (`0xc000027b`) inside
`Microsoft.UI.Xaml.dll` the instant `App.xaml` is asked for: a busy cursor, then nothing.
`MiniXiangqi.App.csproj` fixes both — `EnableMsixTooling` for the index, which is the
property the WinUI templates set and whose entire effect on this publish is that one
file, and an `MxqPublishCompiledXaml` target for the `.xbf` — and `package-zip.ps1`
checks the staged tree for them before it zips anything. The reasons are written at both
places. **The build tree was never evidence for the zip on this point**: it runs because
it was built, and this is precisely the class of thing that is only wrong after a
publish.

**The network is in the zip, and the zip is the whole app.** *(2026-07-31.)* It used to be
the one thing deliberately left out: this repository is public, a GitHub Actions artifact
on a public repository can be downloaded by any logged-in GitHub account, and the network
then bundled was community-trained with a redistribution licence nobody had established.
The network [`docs/engine-integration.md`](../docs/engine-integration.md) now records is
this project's own, so there is nothing the artifact cannot carry and no second, more
complete package to build.

What survives that change is the check, inverted. The publish copies the verified asset
directory — the staging CMake produced, not a second uncontrolled copy — and the script
then confirms the network is in it and *is* the network: exactly one `.nnue`, under the
manifest's name, at the manifest's byte length, with the manifest's SHA-256. The failure
it guards is the quiet one. A network that is absent, renamed or damaged does not crash
anything: the AI declines to start, every other feature works, and whoever unpacked the
zip has no way to know why. Name matters as much as bytes, because the engine restricts
NNUE to the matching variant by the file's leading name and ignores a mismatch in silence.

`NOTICE.md` names Fairy-Stockfish with the pinned fork revision, SQLite's public-domain
dedication, the Microsoft redistributables, and the network — which filename, which byte
length, which SHA-256, and which pipeline revision produced it — all generated from
[`pinned-inputs.json`](../pinned-inputs.json) rather than transcribed, so the note and
the manifest cannot disagree. `LICENSE` is the repository's own GPL-3.0. There is no
`NETWORK.md`: it existed to describe a file that was not in the zip.

**The zip is proved runnable rather than assumed to be.** The workflow unpacks the
artifact it just built into a directory of its own and runs the `MiniXiangqi.Smoke.exe`
that came out of the zip against the zip's own layout: its own core DLL, its own assets,
its own network, its own runtime, at the paths somebody who unpacked it would have, with
nothing from the build tree on that path and nothing added to it. That last clause is new
and is worth the sentence — the run used to need the network dropped in first, so what it
exercised was the zip plus a step, and it now exercises the zip. The harness is in the zip
for the reader's sake as much as CI's: it is how somebody finds out whether their copy
is sound before they sit down with it.

**Runnable, and the word has a limit worth stating.** What that run proves is the layer
the harness touches: the core DLL loads from the unpacked folder, the C++ runtime is
there, the assets and the network are found at the paths a person would have. It has no
window and no XAML, which is what lets it run on a runner with no desktop — and means it
passed, 361 checks and no failures, on a zip whose app could not open a window at all.
The app's own launch is not something a headless run can reach on Windows, because a
WinUI process cannot open one in session 0 at all
([above](#the-windows-floor-and-the-board-that-will-not-fit) has the fuller version). So
the layer above the harness is held by construction instead — the two checks named under
[Self-contained](#the-distribution), which fail the build rather than the launch — and by
somebody running the unpacked exe with a desktop in front of them. That last step is a
person's, it is the only proof of it there is, and a zip that has not had it is a zip
whose window is unproven however green the run was.

The script also reads the PE machine type of every binary in the tree and fails if one is
not the target architecture. A `win-arm64` publish that quietly resolved an x64 native
package would otherwise produce a zip that builds, uploads and fails on the only machines
it is for — and nothing headless would notice, because the natives it would be wrong
about are Win2D's and the Windows App SDK's, which only a window loads.

`actions/upload-artifact` wraps whatever it is given in a zip of its own, so the download
is a zip containing `MiniXiangqi-windows-<arch>.zip`. That is the cost of the artifact
being byte-for-byte the file the job proved, rather than a repackaging of the directory
it proved; the alternative uploads a tree and proves a different thing than it ships.

### Building a distribution by hand

The zip anybody is given comes from CI, and building one locally is the same two
commands the workflow runs, from the repository root and in this order:

```powershell
pwsh windows\build-core-dll.ps1
pwsh windows\package-zip.ps1
```

There used to be a second entry point here, `package-internal.ps1`, and a section
explaining the line between two zips. Both are gone. The line was a licensing one — the
published zip could not carry the community-trained network, a hand-built one for
internal testers could — and with a network this project owns there is nothing to draw
it around. One script, one zip, one complete application, and CI's own artifact is it.

Use `pwsh` rather than `powershell`: Windows PowerShell 5.1 — the default in some shells and
SSH sessions — does not accept `&&` as a statement separator; `;` is, or start `pwsh` first.

## What the packaging build pinned, and what it did not

[`pinned-inputs.json`](../pinned-inputs.json)'s Windows entry has two toolchain fields
because the core's compiler and the frontend's packaging stack become known at different
times. `toolchain_core` was filled on 2026-07-30 by the first Windows core build, and now
has an `ARM64` sibling filled by the first one on that architecture. `toolchain` was null
until this packaging build ran, and now carries what it measured: the Windows App SDK and
Win2D versions, the .NET SDK and runtime, the target framework, the deployment flags, and
the runtime identifiers.

What it did **not** establish stays unestablished, and the entry's `established` flag
stays `false` because of them: `engine_defines`, `engine_flags`, `sqlite_defines` and
`sqlite_flags` describe how the *core* is compiled, and the packaging build publishes a
frontend over a core somebody else already built. Filling them from
`build-core-dll.ps1`'s command line would record a developer build's flags in fields that
describe a packaging build, which is exactly the confusion that entry is shaped to avoid.
