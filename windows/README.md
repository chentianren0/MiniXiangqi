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
| `build-core-dll.ps1` | builds `mxqcore.dll` and stages the engine's assets and the C++ runtime into `artifacts/` |
| `package-zip.ps1` | the direct distribution: publishes, checks the network it carries, and writes the zip |
| `package-msix.ps1` | the [Store package](#the-store-package): builds the unsigned `.msix`, then unpacks it and checks what the Store would read |
| `New-DistributionNotices.ps1` | writes `LICENSE` and `NOTICE.md` into either distribution, from `pinned-inputs.json` |
| `Get-PeMachine.ps1` | one PE-header reader, dot-sourced by the three scripts above that ask what architecture a binary is |
| `make-app-icon.py` | builds `MiniXiangqi.ico` and the package's `Images/` from the icon design's 1024 px export |
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
unpackaged Win32 app has no equivalent, so a file is what there is, and the zip's app —
a `WindowsPackageType` `None` build with no package identity — has no `ApplicationData`
to reach for even if it wanted one. **The Store package now does, and this class did not
change.** A packaged app's writes under `LOCALAPPDATA` are redirected by Windows into the
package's own writable location, so the two channels keep separate preferences from
identical code and neither knows it. Making that explicit is a change to one class rather
than to a contract, because the key and the vocabulary are the interface, not the file;
whether it is worth making is [`docs/architecture.md`](../docs/architecture.md)'s open
question, not this file's. A write lands atomically — a sibling temporary file moved
over the old one — so a process that dies mid-write leaves the previous preferences rather
than a truncated object every later read would answer "nothing is stored" to. What has not
changed is the key or the vocabulary: those are the interface between the screen that
writes a preference and the surface that reads one, and they are what lets a preference set
in one frontend mean the same thing in the other.

## The icon

The app's icon is **derived rather than drawn**. The design is the Apple side's Icon
Composer document, `apple/AppIcon.icon`; the owner exports a flat 1024×1024 PNG from it;
and [`make-app-icon.py`](make-app-icon.py) turns that one image into everything Windows
asks for. Only the last link of that chain is in this repository — the first is the Apple
app's document and the second is a four-megabyte intermediate nobody edits — so the script
is the paper trail, and regenerating after a design change is one command with the new
export.

It writes two things, because the two distributions ask the question differently.
`MiniXiangqi.App/MiniXiangqi.ico` is what the **executable** carries and is all the zip
has. `MiniXiangqi.App/Images/` is what the **Store package** carries: thirty PNGs, one per
qualifier, because a package declares its images in the manifest and the shell resolves
each one through the resource index by the display's scale or the size a caller asked for
— so a package needs one file per frame rather than one container holding them all. The
directory is included only by a packaged build, so nothing about it can reach the zip;
[The Store package](#the-store-package) says what is in it and why those sizes.

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
rather than remembered. **Backgrounding needs no code**: a desktop app has no
platform suspension whether it is packaged or not — the lifecycle manager suspends UWP
apps, and a full-trust packaged desktop app is exempt from it exactly as the zip's app is
outside it — losing focus is not one — which is what
`apple/MiniXiangqi/Play/Suspension.swift` says about macOS — and a game still being played
is still heard, with the volume mixer where somebody who wants it quieter goes.

## Continuous integration

[`.github/workflows/windows-frontend.yml`](../.github/workflows/windows-frontend.yml)
builds the core with `MXQ_BUILD_SHARED_LIBRARY=ON`, regenerates the bindings and fails
on any difference from what is committed, compares the four sound samples against the
Apple bundle's, builds every project, runs the smoke harness against `docs/copy.md`,
renders the board, builds the distribution zip, and builds the Store package. It uploads
four artifacts on every run — the board renders, the zip per architecture, the `.msix`
per architecture, and the `.msixupload` that carries both packages to Partner Center —
and it takes no secrets: the network the AI needs is in the checkout, and the package is
unsigned because the Store signs what it accepts.

**It is a matrix over two architectures**, each on its own native runner: `windows-2025`
for `x64` and `windows-11-arm` for `ARM64`. Three steps run on `x64` only, and the
workflow says why where they are — the bindings check and the sound comparison are
source-level checks that a second architecture would repeat rather than extend, and the
renders are pictures of a board no dimension of which depends on the instruction set.
Everything that could differ by architecture — the C++ build, every managed build, the
harness, the publish, the zip and the Store package — runs on both. `fail-fast` is off on
both matrices: one architecture failing is a finding about that architecture, and the
other's result beside it is what says whether it is architecture-specific.

**One job is not in the matrix**, and it is the only one that could not be: `store-package`
waits for both legs, downloads the two `.msix` artifacts they uploaded, and zips them into
the single `.msixupload` a Store submission takes. It compiles nothing and proves nothing
about either package — the legs did that — beyond reopening the archive it just wrote and
reading back that it holds exactly the two packages, at the root, where the Store looks.

The core's own suites on `ARM64` are in [`core-suites.yml`](../.github/workflows/core-suites.yml)
rather than here. What decides a job's home is which changes should start it: that
workflow starts on `core/`, `fixtures/` and `.gitattributes`, and this one does not, so a
fixtures change that broke the engine on `ARM64` and nowhere else would have gone unseen
if the job had lived here.

The bindings check is the obligation issue #80 carried from #85's verify: a `Mxq.g.cs`
that differs from what the generator writes is a transcription of the header rather than
the header, and the DLL export path and the bindings can no longer drift silently.

**A `v*` tag makes a release out of the same run.**
[`release.yml`](../.github/workflows/release.yml) builds nothing of its own: it calls the
workflow above, so a release is the ordinary build with the ordinary proofs rather than a
second definition of them, and then attaches five of that run's artifacts — the two zips,
the two `.msix`, and the `.msixupload` — to a **draft** release on the tag, with generated
notes as the starting point. The assets are those files themselves rather than the
artifact wrappers described [above](#the-distribution), so a release download is the zip
and not a zip around it. It stops at a draft deliberately: this repository has release
immutability enabled, so publishing freezes both the assets and the tag, and that click is
the owner's to make after running the thing. Before either runner starts, it also refuses
a tag whose version and `Package.appxmanifest`'s disagree — `v1.6` means `1.6.0.0` — since
a release page and the package hanging off it should not answer *which version is this*
two different ways.

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

**There are two distributions and this is the first of them.** The zip is the direct
download — unpack, run, nothing installed — and [The Store package](#the-store-package)
below is the other. They are two deployment shapes of one app from one project, switched
by one MSBuild property, and neither is the other's fallback. Everything in this section
describes the zip.

[`package-zip.ps1`](package-zip.ps1) is that build, and one zip per architecture is what
it produces (issue #80, owner decision, 2026-07-30). It publishes `MiniXiangqi.App` and
`MiniXiangqi.Smoke` self-contained into one directory — they share every runtime file,
this app's own assemblies, the core DLL and the asset directory, so publishing them
apart would ship two .NET runtimes to prove one works — writes the licence and the
notes, and zips the result under one top-level folder.

**Self-contained means three things, and the third is the one people forget.**
`--self-contained` carries the .NET runtime. `WindowsAppSDKSelfContained`, which the
unpackaged build sets, carries the Windows App Runtime. Neither carries the *Visual C++*
runtime, and `mxqcore.dll` is MSVC's output linked against it dynamically.

**That third runtime now arrives with the core rather than being fetched here**, and the
move is worth a sentence because it changed which script owns it.
[`build-core-dll.ps1`](build-core-dll.ps1) stages `vcruntime140*.dll` and `msvcp140*.dll`
beside `mxqcore.dll` in `windows/artifacts/`, reading each candidate's own PE machine type
to decide which files are this architecture's; [`CoreArtifacts.targets`](CoreArtifacts.targets)
copies them into every executable's output the way it copies the core; and this script
only checks that they arrived. The runtime belongs to the DLL that links it, so putting it
on the same path is what stops the two coming from different builds — and it is the only
arrangement that also reaches the Store package, whose payload is a build output that no
script gets to add files to after the fact. App-local deployment of those DLLs is what the
Visual Studio redistributable terms permit, and the zip's `NOTICE.md` records it. With all
three runtimes in place, "unpack and run" needs no install of any kind; what the machine
still needs is Windows 11 and the matching architecture.

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

Both documents come from [`New-DistributionNotices.ps1`](New-DistributionNotices.ps1),
which the Store package's build calls too. **They are not a courtesy.** `mxqcore.dll`
carries Fairy-Stockfish, this application is GPL-3.0 because of it, and
[`docs/architecture.md`](../docs/architecture.md)'s rule is that a public repository's CI
artifacts are a distribution channel and are governed as one — so every artifact either
build uploads is a conveyance that has to carry its licence. One section of `NOTICE.md`
differs between the two, and exactly one: the zip carries the Windows App Runtime and the
package takes it as a framework dependency the Store installs. **The machine-learning
components are named in both**, because the measurement says they are in both — a licence
document that under-reports what a GPL artifact carries is the failure this document is
against, and that is what the store-package section said until the first packaged run was
read back.

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

## The Store package

The Microsoft Store is the intended public channel for Windows (owner decision,
2026-07-31), and [`package-msix.ps1`](package-msix.ps1) is the build that produces what is
submitted to it: **one unsigned `.msix` per architecture**, and a `.msixupload` holding
both, which is what a single Store submission takes.

```powershell
pwsh windows\build-core-dll.ps1
pwsh windows\package-msix.ps1
```

The same first command as the zip, over the same staged core. In CI both packaging builds
run in the same job for exactly that reason: the C++ is compiled once and the two
distributions are two shapes of one build.

### There is no certificate, and there never will be

This is the fact the whole arrangement rests on, and it is the one the project had wrong
until 2026-07-31. `docs/product.md` and `docs/architecture.md` both used to defer MSIX on
the cost of "a signing certificate to obtain and keep". **A package accepted by the Store
is signed by the Store**, with Microsoft's own certificate, after acceptance. So a package
built for submission is *supposed* to be unsigned, `AppxPackageSigningEnabled=false` is
what says so, and there is no key to obtain, store, rotate, expire or leak. That is why
this build needs no secret, why CI runs it on a public repository's pull requests, and why
a fork's pull request builds it too.

The consequence for anyone holding the artifact: an unsigned `.msix` **cannot be
double-clicked to install**. The owner's own check before a submission is a registered
install from an unpacked layout, which needs Developer Mode and no certificate either —
[Checking a package on a machine](#checking-a-package-on-a-machine) below.

### One project, two shapes, one switch

There is no packaging project. `MiniXiangqi.App.csproj` builds both distributions, and
`MxqPackaged` chooses:

| | not set (the default) | `MxqPackaged=true` |
|---|---|---|
| `WindowsPackageType` | `None` | absent — the vocabulary's own way of saying "packaged" |
| Windows App SDK | self-contained, in the folder | a framework dependency the Store installs |
| .NET | self-contained | self-contained |
| `Package.appxmanifest`, `Images\` | removed from the item set | included |
| built by | `package-zip.ps1` | `package-msix.ps1` |

**The switch is this way round on purpose.** Everything the zip depends on is either
unconditional or under the default, so a build that forgets the property builds the zip's
shape; a build that gets it wrong fails on the MSIX side, where a failure is a red CI leg
rather than a quietly different download. The zip's evidence is unchanged by any of it:
the workflow still unpacks the artifact it built and runs the harness from inside it.

The one asymmetry worth stating is .NET's. The Windows App SDK can be a framework
dependency because a framework package for it exists in the Store; **there is no way for an
MSIX to declare a dependency on the .NET runtime**, so a framework-dependent .NET app in a
package installs and then fails to start wherever that runtime is absent, with nothing to
say why. So .NET travels, and `package-msix.ps1` checks for `hostfxr.dll` and `coreclr.dll`
in the unpacked package rather than trusting a command line.

**What framework-dependence actually sheds is narrower than it sounds, and the difference
is measured rather than argued.** What leaves is the Windows App Runtime itself:
`Microsoft.ui.xaml.dll` is not in the payload and neither is
`Microsoft.WindowsAppRuntime.dll`, leaving the two Bootstrap DLLs that reach the framework
package the Store installs. What does **not** leave is the machine-learning components the
SDK depends on and this app never loads: `onnxruntime.dll`,
`Microsoft.ML.OnnxRuntime.dll` and `DirectML.dll` are extracted out of the `.msix` on both
architectures. This section claimed the opposite until the first packaged run's own
`makeappx unpack` listing was read, and the package's `NOTICE.md` names them for exactly
the reason the zip's does — large, present, and otherwise unaccounted for. The deployment
mode changed which runtime is *installed*, not which redistributables travel.

### The three placeholders

`Package.appxmanifest` carries `MXQPLACEHOLDER` in three fields, and they are deliberately
not plausible:

| Manifest field | Where the real value comes from |
|---|---|
| `Identity/@Name` | Partner Center → the app → **View app identity details** → `Package/Identity/Name` |
| `Identity/@Publisher` | the same page's `Package/Identity/Publisher`, a full `CN=…` string |
| `Properties/PublisherDisplayName` | the same page's publisher display name |

All three are assigned when the app's name is reserved, and a package whose identity does
not match the reservation is rejected at upload — so a plausible-looking guess would buy
nothing and cost a reader the ability to tell. **Nothing else changes when they land**: not
the project, not the scripts, not CI. Three string edits, and the next build is the same
build.

`Version` is hardcoded — `1.6.0.0` — and bumped by hand, in a commit, before the release
tag it belongs to is pushed. CI does not stamp it: the Store refuses a version that is not
higher than the last accepted one and reserves the fourth part for itself, and a version
that moves on every run is a version nobody chose. What CI does is compare, because the
tag names the same number: `vX.Y` is `X.Y.0.0` and `vX.Y.Z` is `X.Y.Z.0`, and
[`release.yml`](../.github/workflows/release.yml) stops a release whose two answers
differ. `DisplayName` is **Xiangqi Master**, the owner's provisional choice
(2026-07-31); the reservation fixes the name finally, in the same act as the identity.

### What the manifest declares, and what it deliberately does not

`Windows.Desktop` at `MinVersion` `10.0.22000.0` — Windows 11's first build, the product
floor, and **the same number as `TargetPlatformMinVersion` in the project file**. The two
answer different questions — what the compiler allows, and which machines the Store offers
the app to — and disagreeing would offer the app to a machine it was not built against.

Both languages are declared **explicitly** rather than with the template's `x-generate`.
That value tells the packaging build to declare one `Resource` per language it found
*qualified resources* for, and this app has none: its bilingualism is a C# string table
selected from `CurrentUICulture` ([Strings](#strings)), not a set of `.resw` files. So
`x-generate` would find English alone and publish an app that says it speaks one language,
which is what a Chinese-language customer would be shown. `en-US` is first, and first is
the package's default (owner decision).

`runFullTrust` is the only capability, and it is the one every packaged desktop app
declares — it is what says this is a Win32 process rather than a sandboxed UWP one.
**`internetClient` is absent and its absence is the point**: the app never touches the
network, so declaring it would be a permission shown on the listing page for something the
app does not do, and unjustifiable in a submission review.

Deliberately absent as well: no `DefaultTile` and so no wide or small tile, no
`SplashScreen` (a UWP element a packaged desktop app neither needs nor uses), no lock-screen
or badge declaration. `BackgroundColor` is `transparent`, because the icon is a shaped disc
drawn on transparency and a colour there would put a square plate behind a round icon.

The images the manifest names resolve through the package's resource index rather than
existing at the literal paths it gives: the manifest says `Images\StoreLogo.png` and the
package holds `StoreLogo.scale-100.png` and its four siblings. There are thirty of them —
three logos at the five display scales, plus `Square44x44Logo` at five target sizes in
plain, unplated and light-unplated forms — and [the icon](#the-icon) says where they come
from. `make-app-icon.py` enforces the rules that are each a named certification failure:
every frame LANCZOS-resized from the 1024 px original rather than from a larger frame,
half-up rounding of the scale arithmetic, the exact pixel size each qualifier declares,
never a `scale-` and a `targetsize-` in one filename, and every file under 200 KB.

### What the build checks, and why it unpacks what it just built

**The manifest in this repository is not the manifest that ships.** The packaging build
rewrites it — filling `ProcessorArchitecture` from `/p:Platform`, resolving
`$targetnametoken$`, adding the Windows App SDK framework dependency — and what the Store
reads is the generated `AppxManifest.xml` inside the package. Checking the source manifest
would be checking our own input, so `package-msix.ps1` unpacks the package with `makeappx`
and asserts against what came out: the architecture this leg claims, a four-part version
whose revision is 0, the Windows 11 floor, both languages, `runFullTrust` and only
`runFullTrust`, a Windows App Runtime dependency, and an image for every one the manifest
names.

Then, on the unpacked tree, the things whose absence is silent until somebody installs it:
a resource index and at least one `.xbf`, without which the app dies before its first
window exactly as the zip once did; `mxqcore.dll`, `vcruntime140.dll`, `hostfxr.dll` and
`coreclr.dll`; `sounds\`; `assets\` holding the variant configuration and the network under
the names `pinned-inputs.json` pins; `LICENSE` and `NOTICE.md`; and a PE machine-type sweep
over every `.dll` and `.exe`, because an ARM64 package that quietly resolved x64 natives
builds, uploads, passes certification and fails on every machine it is for.

**The two documents have to be written before the build, not after it**, and that is the
one place the packaged shape forced a change to how the zip works. The zip's build writes
them into the staged directory once everything else is there; a package's payload is a
build output, computed while MSBuild runs, so a script cannot add to it afterwards without
making the package something other than what the build produced. So
`New-DistributionNotices.ps1` runs first, writes into a directory named by `MxqNoticesDir`,
and the project includes that directory as package content — which is also why the
generation moved out of `package-zip.ps1` into a script the two builds share.

`makeappx` is found by globbing the installed Windows SDKs rather than by naming a build,
for the same reason `build-core-dll.ps1` locates MSVC through `vswhere`: the SDK moves with
every runner image and a hard-coded path fails a long way from its cause. MSBuild is found
the same way — Visual Studio's own packaging targets are what produce an `.msix`, and the
.NET CLI does not carry them, which is why this one script uses `msbuild.exe` where
everything else here uses `dotnet`.

`UapAppxPackageBuildMode` is `SideloadOnly`, not `StoreUpload`. `StoreUpload` would also
ask the build for a symbol package — `mspdbcmf`, and a failure on a hosted runner — to
produce the same two packages plus an `.appxsym` that is documented as optional. The
`.msixupload` is built directly instead, which is Microsoft's own documented "create your
upload file manually": a plain zip with each architecture's `.msix` **at the archive root**.
The `store-package` job writes it, reopens it, and reads back that it holds exactly two
entries, both `.msix`, both at the root — because "I wrote a zip" and "the zip is what the
Store needs" are different claims, and a submission rejected for its shape costs a round
trip through Partner Center to discover.

### Checking a package on a machine

An unsigned package cannot be installed by double-clicking it, and no certificate is
needed to try it anyway. With **Developer Mode** on (Settings → System → For developers),
unpack the package and register the layout in place:

```powershell
makeappx unpack /p MiniXiangqi-windows-x64.msix /d layout
Add-AppxPackage -Register .\layout\AppxManifest.xml
```

The app then appears in Start under its `DisplayName` and runs from that folder;
`Remove-AppxPackage` by package full name takes it away again. This is a real install of
the real package, not a rehearsal of one — the manifest, the identity, the tile assets and
the resource index are all the ones the Store would read.

**A machine that has only ever run the zip will need the Windows App Runtime once.** The
zip carries its own copy and installs nothing; the package deliberately does not, and
takes the framework dependency the Store would satisfy automatically. Registering a layout
by hand does not, so install the Windows App SDK runtime for the machine's architecture
first — the redistributable installer from the Windows App SDK downloads page — and it is a
one-time thing, not a per-package one.

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

**`packaging_flags` now has two halves for the same reason it exists at all.** Its flat
fields were the whole of it while there was one distribution, and they describe the zip:
unpackaged, `WindowsPackageType` `None`, self-contained on both counts. `store_package`
beside them describes the Store's shape — packaged, `WindowsPackageType` absent, .NET
self-contained and the Windows App SDK not, unsigned because the Store signs — and carries
its own `established` flag for the same reason. Two of its fields could only be answered by
a run and were null until the first one: the Windows App Runtime framework the generated
manifest asks the Store to install, read out of the unpacked package, and the MSBuild each
leg used. **The ARM64 leg's MSBuild warns** — `NETSDK1233`, "Targeting .NET 10.0 or higher
in Visual Studio 2022 17.14 is not supported", on every project — and that is recorded
there rather than worked around: it is a support position, and the package that leg
produced passed every assertion made against it. Everything else in the entry is a decision
rather than a measurement, and is there so that "how does the Store copy differ" is
answerable without reading a project condition.
