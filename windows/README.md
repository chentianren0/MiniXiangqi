# Windows frontend

The WinUI 3 frontend, over the same shared core as the Apple frontend. What is here
is the core built as a DLL, C# declarations generated from `core/include/mxq.h`, the
Play destination — the home where what to play is chosen, each mode's pre-start state,
and the board with a live game against the AI — the History destination with its
step-through viewer and its import, the Settings destination and the board's four
voices, and two headless harnesses that are how any of it is verified on a machine
nobody is logged into. The stacked layout that narrow windows take on the other
platforms, and the packaging build, are later pull requests.

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
Windows implements part of the contract's rows and the Apple frontend implements the
rest. It becomes checkable when the Windows frontend is complete, and it is not checked
before then rather than checked against a count somebody has to keep adjusting — a count
this paragraph used to carry and which the History destination immediately made stale.

**18** plays a whole game against the AI through `PlaySession` — every move committed by
clicking a point and then another point, exactly as the window's board does it, the AI
answering through the same marshalled callback — to a conclusion or a move cap, and then
takes the concluding action. **19** plays Free Play through the same session and taps an
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
home. **26** and **27** are the insufficient-memory refusal in both of its forms,
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
and a preference changed underneath the screen is what the screen shows next. **37 states
the sound event-mapping seam**: the precedence rule over its whole truth table, the 声音
gate honoured at the moment of use and flipped between two landings on one object, and then
a real Free Play game in which every landing is checked against what the board itself says
happened — the piece that was standing on the destination, and the position that arrived —
rather than against the rule under test. A move taken back, a claimed draw and a
resignation are asked separately, because the played game cannot ask for them. What the
harness cannot say is whether the four voices *sound* right; that is an ear's answer and it
is the owner's tour, and section 37 prints as much.

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
棋子符号 is a preference with one option. 触感 is absent because the platform gives an
application no way to drive the machine's own hardware, which
`docs/interaction-design.md` § Sound and haptics settles as the Windows answer — the row
is removed rather than greyed out, exactly as it is on an iPad. **Both accepted footers
survive**, so the two-footer rule reads the same here as it does on the Mac.

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
unpackaged Win32 app has no equivalent it can reach without deciding the packaging
question this repository has parked. The Settings pull request kept that storage rather
than replacing it: it is the reader three surfaces already run against and the harness
already proves, and a packaging build changing where preferences live is a change to one
class rather than to a contract. A write lands atomically — a sibling temporary file moved
over the old one — so a process that dies mid-write leaves the previous preferences rather
than a truncated object every later read would answer "nothing is stored" to. What has not
changed is the key or the vocabulary: those are the interface between the screen that
writes a preference and the surface that reads one, and they are what lets a preference set
in one frontend mean the same thing in the other.

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
builds the core with `MXQ_BUILD_SHARED_LIBRARY=ON`, fetches the pinned network with the
same script the core suites use, regenerates the bindings and fails on any difference
from what is committed, compares the four sound samples against the Apple bundle's,
builds every project, runs the smoke harness against `docs/copy.md`, and renders the
board. It uploads the renders on every run.

The bindings check is the obligation issue #80 carried from #85's verify: a `Mxq.g.cs`
that differs from what the generator writes is a transcription of the header rather than
the header, and the DLL export path and the bindings can no longer drift silently.

## Strings

`MiniXiangqi.Play/Text/Strings.cs` holds every string this frontend shows, keyed exactly
as [`docs/copy.md`](../docs/copy.md) keys it, with the normative Chinese and its approved
English side by side. The History destination and its viewer added no key to that
contract: every string they say was already a row of it, including the ones it marks
*(proposed)* — the two section headers, the empty state's pair, the deletion-failure pair,
the History-read failure title, and the transport's labels — which this frontend now ships
and which `docs/copy.md` § Need to discuss asks the owner to approve. The two rows it does
not ship are `replay.autoplay` and `replay.pause`, whose control the trim removed. **The
Settings destination added none either, and shipped no proposed row**: its eight strings —
`nav.settings`, the four `settings.defaults.*`, `settings.sound.label` and the two
`settings.confirmDelete.*` — are all accepted, and the six option words its two pickers
offer are the pre-start page's own `setup.` rows, keyed once for both screens. The four
rows it does not ship are the ones its trim removed: `settings.section.board`,
`settings.symbols.*`, `settings.notation.*` and `settings.haptics.label`. The language is
the operating system's — the app offers no interface-language control of its own — which
.NET resolves as `CurrentUICulture` from the system's language preference list.

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
