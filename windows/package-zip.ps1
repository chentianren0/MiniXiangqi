<#
.SYNOPSIS
Build the Windows distribution: one zip somebody unpacks and runs.

.DESCRIPTION
The accepted MVP distribution for Windows is a CI-built zip (issue #80, owner
decision, 2026-07-30; MSIX and its signing-certificate story are the post-MVP
upgrade). This script is that build. It runs on a developer machine and in
.github/workflows/windows-frontend.yml, which is where the artifact anybody
downloads comes from.

Run windows/build-core-dll.ps1 first, for the same architecture: the core is
consumed as a prebuilt DLL beside a prebuilt asset directory, and this script
publishes on top of that rather than compiling C++ itself.

WHAT THE ZIP CONTAINS, AND THE ONE THING IT DELIBERATELY DOES NOT

  MiniXiangqi-windows-<arch>/
    MiniXiangqi.App.exe        the app, carrying its own icon
    MiniXiangqi.Smoke.exe      the self-check, and the reason the zip can be
                               proved runnable rather than assumed to be
    MiniXiangqi.ico            the same icon as a file, which is what the running
                               window's AppWindow.SetIcon takes
    mxqcore.dll                the shared core
    *.dll                      the .NET runtime, the Windows App SDK, Win2D,
                               the Visual C++ runtime, and this app's own
                               assemblies — self-contained, so the machine that
                               unpacks it installs nothing
    assets/                    the pinned variant configuration
    sounds/                    the board's four voices
    LICENSE                    GPL-3.0, this project's own
    NOTICE.md                  what else is inside and under what terms
    NETWORK.md                 the one file that is missing, and how to add it
    README.md                  what this is and how to run it

TWO ZIPS, ONE CODE PATH

Run with no -NnueSource, this produces the **public-safe** zip: everything above
except the NNUE network, which is what CI builds and uploads. Run with one, it
produces the **complete internal** package instead, the same layout with the
network placed in assets/ and a NETWORK.md that says it is there.

The distinction is a licensing one and not a technical one. Bundling the pinned
network for internal testers is accepted (docs/engine-integration.md); what is
barred is a *public* location, and this repository is public, so **a GitHub
Actions artifact on it is downloadable by any logged-in GitHub account** and
carrying the network there would be a distribution beyond internal testing —
the exact expansion that document makes a licensing gate for, which nobody has
passed. A zip built on a machine the owner controls and handed to a tester is
not that.

So the order below is deliberate and is the thing to check when reading it:
the publish's network is removed and the whole staged tree is then checked
three ways — by name, by exact byte length, and by content for anything that
matches the length — **before** anything is placed back. Both modes run that
check on an identical tree. Only after it passes does the internal mode verify
the bytes it was handed against the manifest and place them, visibly and on its
own. CI calls this script without -NnueSource and therefore cannot produce an
internal package however it is invoked; windows/package-internal.ps1 is the
entry point that does, and exists so the intent is legible at the call site.

.PARAMETER Architecture
x64 or arm64, defaulting to the machine this runs on. It must match the
architecture windows/build-core-dll.ps1 last staged, which is checked rather
than trusted: every native binary in the published tree has its PE machine type
read and compared.

.PARAMETER NnueSource
The pinned NNUE network's bytes. Absent — which is how CI calls this — the zip
is the public-safe one. Given, the bytes are verified against
pinned-inputs.json's byte length and SHA-256 and placed in the zip, and the
result is named -internal. Wrong bytes are a hard stop, not a warning.

.PARAMETER Configuration
The MSBuild configuration to publish. Release by default.

.PARAMETER OutputDirectory
Where the zip is written. windows/dist by default, which .gitignore covers.

.PARAMETER Revision
The commit this was built from, stamped into the zip's README.md and into an
internal package's filename. Defaults to GITHUB_SHA and then to git rev-parse
HEAD.

.EXAMPLE
pwsh windows/build-core-dll.ps1 -NnueSource <path to the pinned network>
pwsh windows/package-zip.ps1
#>
[CmdletBinding()]
param(
    [ValidateSet('x64', 'arm64')]
    [string] $Architecture = $(if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }),
    [string] $NnueSource,
    [string] $Configuration = 'Release',
    [string] $OutputDirectory,
    [string] $Revision
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$rid = "win-$Architecture"
$productName = "MiniXiangqi-windows-$Architecture"
$internal = [bool] $NnueSource

if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot 'windows\dist' }
if (-not $Revision) { $Revision = $env:GITHUB_SHA }
if (-not $Revision) {
    $Revision = (& git -C $repoRoot rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) { $Revision = 'unknown' }
}

$manifest = Get-Content (Join-Path $repoRoot 'pinned-inputs.json') -Raw | ConvertFrom-Json
$network = $manifest.network
$fork = $manifest.fork
$variant = $manifest.variant
$sqlite = $manifest.sqlite

$staging = Join-Path $OutputDirectory $productName
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path $staging

# What architecture a binary actually is, read from its PE header rather than
# inferred from where it was found. Used twice below: once to decide which
# Visual C++ runtime files belong in this zip, and once to check that every
# binary in it does.
function Get-PeMachine([string] $path) {
    $stream = [System.IO.File]::OpenRead($path)
    try {
        $reader = New-Object System.IO.BinaryReader($stream)
        if ($stream.Length -lt 0x40) { return $null }
        $stream.Position = 0
        if ($reader.ReadUInt16() -ne 0x5A4D) { return $null }   # MZ
        $stream.Position = 0x3C
        $peOffset = $reader.ReadUInt32()
        if ($peOffset + 6 -gt $stream.Length) { return $null }
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) { return $null } # PE\0\0
        return $reader.ReadUInt16()
    } finally {
        $stream.Dispose()
    }
}

$expectedMachine = if ($Architecture -eq 'arm64') { 0xAA64 } else { 0x8664 }
$machineNames = @{ 0x014C = 'x86'; 0x8664 = 'x64'; 0xAA64 = 'ARM64'; 0x01C4 = 'ARM' }

# ---------------------------------------------------------------------------
# Publish
# ---------------------------------------------------------------------------
#
# Both executables publish into one directory. They share every runtime file,
# every one of this app's own assemblies, the core DLL and the asset directory,
# so publishing them separately would mean shipping two copies of a .NET runtime
# to prove one of them works.
#
# Self-contained on both counts. --self-contained carries the .NET runtime;
# WindowsAppSDKSelfContained, which both projects already set, carries the
# Windows App Runtime. Between them the machine that unpacks this needs no
# install, which is what "unzip and run" has to mean to be worth saying.

foreach ($project in @('MiniXiangqi.App', 'MiniXiangqi.Smoke')) {
    Write-Host "Publishing $project ($rid, $Configuration)"
    & dotnet publish (Join-Path $repoRoot "windows\$project\$project.csproj") `
        -c $Configuration `
        -r $rid `
        --self-contained true `
        -p:MxqRuntimeIdentifier=$rid `
        -o $staging `
        --nologo
    if ($LASTEXITCODE -ne 0) { throw "Publishing $project failed." }
}

# ---------------------------------------------------------------------------
# The app can find its own XAML, checked rather than assumed
# ---------------------------------------------------------------------------
#
# This check exists because its absence shipped a zip that could not open a
# window. `dotnet publish` does not carry an unpackaged WinUI 3 app's compiled
# XAML — neither the resource index ms-appx: lookups resolve through nor the
# .xbf the markup compiler produces — because both reach a *build* output by
# being written or copied there and the publish pipeline copies items instead.
# MiniXiangqi.App.csproj now makes both travel, at length and with the reasons;
# this is the check that they did, on the tree that is about to be zipped.
#
# It is here rather than left to the app's own tests because nothing else in
# this build can see it. The smoke harness runs from this same layout and passes
# without any of these files: it has no window, no XAML and no framework beyond
# the runtime, which is what lets it run over SSH and is exactly why a green
# harness said nothing about the one thing that was broken. A publish that
# quietly stopped carrying these would otherwise be found by a person
# double-clicking the exe, which is what happened on 2026-07-31.

Write-Host ''
Write-Host 'Checking that the app can find its own XAML'
$priName = 'MiniXiangqi.App.pri'
$priPath = Join-Path $staging $priName
$xbf = @(Get-ChildItem -Path $staging -Filter '*.xbf' -File -ErrorAction SilentlyContinue)
if (-not (Test-Path $priPath)) {
    throw ("$priName is not in the published tree. It is the resource index an unpackaged WinUI 3 app " +
           "resolves ms-appx:///App.xaml through, and without it MiniXiangqi.App.exe dies on launch with " +
           "a stowed exception inside Microsoft.UI.Xaml.dll before any window appears. Publishing it " +
           "depends on EnableMsixTooling in MiniXiangqi.App.csproj; check that it is still set.")
}
if ($xbf.Count -eq 0) {
    throw ("No compiled XAML (.xbf) is in the published tree. App.xaml and MainWindow.xaml compile to " +
           "these, MiniXiangqi.App.csproj's MxqPublishCompiledXaml target is what carries them into a " +
           "publish, and a zip without them is one no test here can tell apart from a working zip until " +
           "somebody launches it.")
}
Write-Host ("  {0}  {1:N0} bytes" -f $priName, (Get-Item $priPath).Length)
Write-Host ("  {0} compiled XAML file(s): {1}" -f $xbf.Count, (($xbf | ForEach-Object { $_.Name }) -join ', '))

# ---------------------------------------------------------------------------
# The network comes out
# ---------------------------------------------------------------------------
#
# The publish above copied the asset directory windows/build-core-dll.ps1
# staged, and that directory is the verified one — it holds the network, because
# every other thing that consumes it needs the network. Removing it here rather
# than staging assets a second time keeps one verified staging in the project
# instead of two, and means the variant configuration in the zip is the same
# bytes CMake checked against pinned-inputs.json.

$stagedAssets = Join-Path $staging 'assets'
$removed = @(Get-ChildItem -Path $stagedAssets -Filter '*.nnue' -File -ErrorAction SilentlyContinue)
foreach ($file in $removed) {
    Write-Host ("Removing the network from the distribution: {0} ({1:N0} bytes)" -f $file.Name, $file.Length)
    Remove-Item $file.FullName -Force
}
if ($removed.Count -eq 0) {
    throw ("No NNUE network was found in $stagedAssets to remove. The published tree should have " +
           "contained one, because windows/build-core-dll.ps1 stages the verified network beside the " +
           "variant configuration and refuses to finish without it. Something changed upstream of this " +
           "script; stop rather than shipping a zip whose asset staging is not the verified one.")
}

# ---------------------------------------------------------------------------
# The Visual C++ runtime
# ---------------------------------------------------------------------------
#
# mxqcore.dll is MSVC's output and links the C++ runtime dynamically, so a
# machine with no Visual Studio and no redistributable installed cannot load it.
# "Unzip and run needs no installs" is only true if that runtime travels in the
# zip, so it does: app-local deployment of these DLLs is what the Visual Studio
# redistributable licence permits, and NOTICE.md records it.
#
# Copied only where the publish did not already produce them, and what happened
# is printed either way, because "the Windows App SDK brought its own" and "we
# added them" are different facts about the same directory.
#
# Each candidate's own PE machine type decides whether it is copied, rather than
# the folder it sits in. That is not belt and braces — the arm64 redistributable
# folder really does contain an x64 binary. `vcruntime140_1.dll` implements the
# x64 exception unwinder, ARM64 has no use for it, and Microsoft ships an x64
# copy under VC\Redist\MSVC\<version>\arm64\Microsoft.VC143.CRT anyway for the
# emulation and ARM64EC cases. Trusting the folder name put it in an ARM64 zip;
# the machine-type check further down caught it. Reading each file is what stops
# it being caught rather than avoided.

$crtNames = @('msvcp140.dll', 'msvcp140_1.dll', 'msvcp140_2.dll',
              'msvcp140_atomic_wait.dll', 'msvcp140_codecvt_ids.dll',
              'vcruntime140.dll', 'vcruntime140_1.dll', 'concrt140.dll')
$missing = @($crtNames | Where-Object { -not (Test-Path (Join-Path $staging $_)) })
if ($missing.Count -eq 0) {
    Write-Host 'The Visual C++ runtime was already in the published output.'
} else {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { throw "vswhere.exe not found at $vswhere." }
    $vsPath = & $vswhere -latest -products * -property installationPath
    if (-not $vsPath) { throw 'No Visual Studio installation was found.' }

    $redistRoot = Join-Path $vsPath 'VC\Redist\MSVC'
    $crtSource = $null
    if (Test-Path $redistRoot) {
        foreach ($version in (Get-ChildItem -Directory $redistRoot | Sort-Object Name -Descending)) {
            $candidate = Get-ChildItem -Directory (Join-Path $version.FullName $Architecture) `
                -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue
            if ($candidate) { $crtSource = $candidate[0].FullName; break }
        }
    }
    if (-not $crtSource) {
        throw ("The published output is missing $($missing -join ', ') and no Visual C++ $Architecture " +
               "redistributable was found under $redistRoot. Install the C++ redistributable component " +
               "for this architecture; a zip without it is not one that runs on a clean machine.")
    }

    Write-Host "Taking the Visual C++ runtime from $crtSource"
    foreach ($name in $missing) {
        $source = Join-Path $crtSource $name
        # The set differs by architecture and by toolset version. Anything the
        # redistributable does not carry for this architecture is something this
        # architecture does not need.
        if (-not (Test-Path $source)) { continue }
        $machine = Get-PeMachine $source
        if ($machine -ne $expectedMachine) {
            $named = if ($machineNames.ContainsKey([int]$machine)) { $machineNames[[int]$machine] } else { "0x{0:X4}" -f $machine }
            Write-Host "  skipped $name — it is $named in the $Architecture redistributable, so it is not this architecture's"
            continue
        }
        Copy-Item $source $staging -Force
        Write-Host "  added $name"
    }
    if (-not (Test-Path (Join-Path $staging 'vcruntime140.dll'))) {
        throw "vcruntime140.dll reached neither the publish nor the redistributable copy; the zip would not run."
    }
}

# ---------------------------------------------------------------------------
# The network is not in here, checked rather than assumed
# ---------------------------------------------------------------------------
#
# Three ways, because one removal above is a line of code and this is the
# constraint the whole design turns on. By name, by exact byte length, and — for
# anything that matches the length — by content. A renamed network is caught by
# the second, a network hidden inside another file's name by the third.

Write-Host ''
Write-Host 'Checking that no NNUE network reached the distribution'
$leaks = @()
foreach ($file in Get-ChildItem -Path $staging -Recurse -File) {
    if ($file.Extension -eq '.nnue') {
        $leaks += "$($file.FullName): a .nnue file"
        continue
    }
    if ($file.Length -eq $network.byte_length) {
        $hash = (Get-FileHash $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -eq $network.sha256) {
            $leaks += "$($file.FullName): the pinned network's bytes under another name"
        } else {
            Write-Host "  $($file.Name) is the network's size but not its bytes ($hash)"
        }
    }
}
if ($leaks.Count -gt 0) {
    throw ("The NNUE network reached the distribution, which must never happen: this artifact is " +
           "downloadable by any GitHub account. " + ($leaks -join '; '))
}
Write-Host '  no .nnue file, and nothing with the pinned network''s length or bytes'

# ---------------------------------------------------------------------------
# Every native binary is this architecture, checked rather than assumed
# ---------------------------------------------------------------------------
#
# A win-arm64 publish that quietly resolved an x64 native package would produce
# a zip that builds, uploads and fails on the only machines it is for. The PE
# header answers it for every file in the tree, which also covers the ones no
# test loads: Win2D's and the Windows App SDK's natives are in the zip because
# the window needs them, and nothing headless would notice their absence.

Write-Host ''
Write-Host "Checking that every native binary is $Architecture"
$native = 0
$hybrid = @()
$wrong = @()
$binaries = @(Get-ChildItem -Path $staging -Recurse -File |
    Where-Object { $_.Extension -eq '.dll' -or $_.Extension -eq '.exe' })
foreach ($file in $binaries) {
    $machine = Get-PeMachine $file.FullName
    if ($null -eq $machine) { continue }
    # A managed assembly built AnyCPU reports x86 in this field and is not a
    # native binary; only the ones that report a 64-bit machine are the question,
    # and every native this ships is 64-bit.
    if ($machine -eq 0x014C) { continue }

    # ARM64EC companions. The Windows App SDK publishes a handful of `_ec` DLLs
    # into its win-x64 output — this build's is
    # Microsoft.Windows.Workloads.Resources_ec.dll — and an ARM64EC image
    # declares machine ARM64 while being the thing that lets an x64 process run
    # efficiently on an ARM64 machine. They are Microsoft's to ship beside their
    # x64 binaries, so they are counted and named rather than removed or failed
    # on; what would be wrong is an ARM64 binary that is not one of these.
    if ($file.BaseName.EndsWith('_ec')) {
        $hybrid += $file.Name
        continue
    }

    $native++
    if ($machine -ne $expectedMachine) {
        $name = if ($machineNames.ContainsKey([int]$machine)) { $machineNames[[int]$machine] } else { "0x{0:X4}" -f $machine }
        $wrong += "$($file.Name): $name"
    }
}
if ($wrong.Count -gt 0) {
    throw ("These binaries are not $Architecture, so this zip would not run on the machines it is for: " +
           ($wrong -join '; '))
}
Write-Host "  $native binaries, all $Architecture"
if ($hybrid.Count -gt 0) {
    Write-Host "  $($hybrid.Count) ARM64EC companion(s) from the Windows App SDK: $($hybrid -join ', ')"
}

# ---------------------------------------------------------------------------
# The network goes back in, for an internal package only
# ---------------------------------------------------------------------------
#
# This is the one step the two modes do not share, and it is deliberately after
# both checks rather than before them: what those checks establish is that the
# *published tree* carries no network, which is a fact about the build and is
# equally worth having in either mode. Anything in assets/ from here on is
# something this block put there, in the open, having verified it.
#
# The bytes are checked against pinned-inputs.json exactly as core/CMakeLists.txt
# checks them, and for the same reason: an internal package with the wrong
# network is an opponent nobody can tell is wrong. Neither value is restated
# here — both come from the manifest.

if ($internal) {
    Write-Host ''
    Write-Host 'Placing the network for an internal package'
    if (-not (Test-Path $NnueSource)) {
        throw "No NNUE network at $NnueSource. An internal package is the complete app; without those bytes it is the public zip under a misleading name."
    }
    $given = Get-Item $NnueSource
    if ($given.Length -ne $network.byte_length) {
        throw ("$NnueSource is $('{0:N0}' -f $given.Length) bytes; pinned-inputs.json pins the network at " +
               "$('{0:N0}' -f $network.byte_length). Refusing to package unverified bytes.")
    }
    $givenHash = (Get-FileHash $NnueSource -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($givenHash -ne $network.sha256) {
        throw ("$NnueSource hashes to $givenHash; pinned-inputs.json pins $($network.sha256). " +
               "Refusing to package unverified bytes.")
    }
    Copy-Item $NnueSource (Join-Path $stagedAssets $network.filename) -Force
    Write-Host ("  $($network.filename)  {0:N0} bytes  sha256 {1}" -f $given.Length, $givenHash)
    Write-Host '  verified against pinned-inputs.json before it was copied'
}

# ---------------------------------------------------------------------------
# The documents
# ---------------------------------------------------------------------------
#
# NETWORK.md and NOTICE.md are generated from pinned-inputs.json rather than
# written by hand, because docs/architecture.md's input rule cuts both ways: a
# hash or a revision restated anywhere is a second place for it to be wrong, and
# a distribution that tells somebody the wrong SHA-256 is worse than one that
# tells them nothing.
#
# They are written last so that they describe the directory as it now is. A
# NETWORK.md telling somebody to go and find a file that is sitting beside it
# would be the one kind of wrong that costs a reader more than saying nothing.

Copy-Item (Join-Path $repoRoot 'LICENSE') (Join-Path $staging 'LICENSE') -Force

$networkPath = "$productName\assets\$($network.filename)"

if ($internal) {

Set-Content -Path (Join-Path $staging 'NETWORK.md') -Encoding UTF8 -Value @"
# The network file is already here

This is a **complete internal package**: the neural network the AI evaluates
with is in it, at ``assets\$($network.filename)``, and there is nothing to add.
Unpack it and run ``MiniXiangqi.App.exe``.

| | |
|---|---|
| File name | ``$($network.filename)`` |
| Size | $('{0:N0}' -f $network.byte_length) bytes |
| SHA-256 | ``$($network.sha256)`` |

Those are the values ``pinned-inputs.json`` pins, and the packaging build
verified the file against both before putting it here. If you want to confirm
it survived the copy:

``````powershell
Get-FileHash .\assets\$($network.filename) -Algorithm SHA256
``````

Or run ``MiniXiangqi.Smoke.exe``, which opens the real core, plays whole games
against the AI and prints ``MXQ_SMOKE_OK`` at the end if everything is in place.

## Why this file exists at all

The build this repository publishes automatically does **not** contain the
network. Its artifacts are downloadable by anyone with a GitHub account, and the
network's redistribution licence has never been established, so it is kept out
of anything public and named instead. Packages built by hand for internal
testers — this one — carry it, which is what the licence position allows and
what makes this the complete app.

**So do not put this zip anywhere public**, or attach it to anything that is.
Hand it to internal testers directly.
"@

} else {

Set-Content -Path (Join-Path $staging 'NETWORK.md') -Encoding UTF8 -Value @"
# The one file that is not in here

This app plays against you with a neural-network evaluation, and **that network
file is not in this zip**. Everything else is. Until you add it, the app opens
and works — Free Play, History, replay, import, export and Settings are all
unaffected — but **the AI will not start**, and starting a Human-versus-AI game
will fail.

The network is not here because this project's source repository is public and
the network's redistribution licence has never been established. It is not ours
to hand out, so it travels to you separately.

## What to add

| | |
|---|---|
| File name | ``$($network.filename)`` |
| Size | $('{0:N0}' -f $network.byte_length) bytes exactly |
| SHA-256 | ``$($network.sha256)`` |

**The file name matters.** The engine restricts a network to the matching
variant by the name's leading part, and a renamed file is ignored silently while
the app still reports that the network is in use. Copy it under exactly the name
above.

## Where it goes

Beside the variant configuration, in the ``assets`` folder next to the app:

``````text
$productName\
  MiniXiangqi.App.exe
  assets\
    $($variant.filename)
    $($network.filename)   <-- here
``````

## How to check you got it right

Run ``MiniXiangqi.Smoke.exe`` from this folder. It is the same self-check this
build runs in CI: it opens the real core, reads the staged network, plays whole
games against the AI and prints a count of checks and failures. The last line is
``MXQ_SMOKE_OK`` when everything is right. It takes a few minutes and needs no
window.

If you would rather check by hand, PowerShell will tell you the hash:

``````powershell
Get-FileHash .\assets\$($network.filename) -Algorithm SHA256
``````

## What it looks like when the file is missing or wrong

The app starts normally. Starting a Human-versus-AI game raises a failure
notice, and resuming a saved AI game shows "The AI can't start right now" on the
board with a Try Again that will keep failing. Neither message names this file
today. Add the network and the AI starts.
"@

}

Set-Content -Path (Join-Path $staging 'NOTICE.md') -Encoding UTF8 -Value @"
# Mini Xiangqi — licences and attribution

Mini Xiangqi is licensed under the **GNU General Public License version 3**. The
full text is in ``LICENSE`` beside this file. The project's source is at
<https://github.com/ppppvz/MiniXiangqi>.

This build contains the following third-party components.

## Fairy-Stockfish — GPL-3.0

The move generation, search and evaluation come from Fairy-Stockfish, which is
licensed under the GNU General Public License version 3 — the same licence this
application is under, and the reason it is under it.

| | |
|---|---|
| Source | <$($fork.repository)> |
| Revision | ``$($fork.revision)`` |
| Upstream | <$($fork.upstream_repository)> |
| Upstream base | ``$($fork.upstream_base_revision)`` |

The exact sources this binary was built from are **in this project's own
repository**, named at the top of this file, under
``core/third_party/fairy-stockfish/upstream`` — a verbatim copy of the fork
revision above, with ``SOURCES.sha256`` beside it listing the SHA-256 of every
file in it. The fork URL above is where that copy came from; the path is this
project's. Carrying the sources rather than only linking to somebody else's
server is what makes the corresponding source available even if the fork moves.

$(if ($internal) {
"The neural network the evaluation loads is a separate input with its own
provenance, and is not covered by this notice. It is in this package because
this package is for internal testers; see ``NETWORK.md``."
} else {
"The neural network the evaluation loads is **not** part of this distribution and
is not covered by this notice; see ``NETWORK.md``."
})

## SQLite — public domain

The game library is stored in SQLite $($sqlite.version), whose authors have
dedicated it to the public domain. There is no licence text to carry;
<https://sqlite.org/copyright.html> is the statement.

## Microsoft components — redistributable binaries

This is a self-contained build, so it carries Microsoft's runtimes beside the
app rather than requiring them to be installed:

- the **.NET runtime**, MIT licensed;
- the **Windows App SDK** and **WinUI 3**, redistributed under the Microsoft
  Software Licence terms that accompany them. Its self-contained deployment also
  brings the machine-learning components it depends on — ``onnxruntime.dll``,
  ``DirectML.dll`` and their companions — which this application never loads;
  they are covered by those same accompanying terms and are listed here because
  they are large, present, and would otherwise go unexplained;
- **Win2D** (``Microsoft.Graphics.Win2D``), MIT licensed;
- the **Microsoft Visual C++ runtime** (``vcruntime140*.dll``,
  ``msvcp140*.dll``), redistributed under the Visual Studio licence terms that
  permit app-local deployment.

## Sounds

The board's four voices are this project's own, generated by a script in the
source repository. There is no third-party audio here and nothing to attribute.
"@

Set-Content -Path (Join-Path $staging 'README.md') -Encoding UTF8 -Value @"
# Mini Xiangqi for Windows ($Architecture)

A native Mini Xiangqi app for learning the game: play against the AI or in Free
Play, with a saved history you can replay, export and import. Everything happens
on this machine — the app never uses the network.

## Running it

Unpack this folder anywhere you can write to, and run **``MiniXiangqi.App.exe``**.
There is nothing to install: the .NET runtime, the Windows App Runtime and the
Visual C++ runtime are all in this folder.

$(if ($internal) {
"This is a complete internal package — the AI's network file is in it and there
is nothing to add. ``NETWORK.md`` says what it is and why the automatically
published build does not carry it. **Do not put this zip anywhere public.**"
} else {
"**Read ``NETWORK.md`` first.** One file is deliberately missing from this zip,
and the AI cannot start until you add it. Everything else works without it."
})

## What this machine needs

- **Windows 11.** Windows 10 left Microsoft support in October 2025 and is not a
  target.
- **This architecture: $Architecture.** An x64 build also runs on an ARM64
  machine under Windows' own emulation, more slowly; an ARM64 build runs only on
  an ARM64 machine.

## Checking the install

``MiniXiangqi.Smoke.exe`` is a self-check with no window. It opens the real core,
plays whole games against the AI and prints ``MXQ_SMOKE_OK`` at the end if
everything is in place. It takes a few minutes, and it is the quickest way to
find out whether this copy is sound before anybody sits down with it.

## Licences

GPL-3.0. ``LICENSE`` is the full text and ``NOTICE.md`` says what else is in
here and under what terms.

---

Built from ``$Revision``, $(Get-Date -Format 'yyyy-MM-dd').
"@

# ---------------------------------------------------------------------------
# The zip
# ---------------------------------------------------------------------------
#
# ZipFile rather than Compress-Archive: includeBaseDirectory puts everything
# under one folder, so unpacking this into a downloads directory produces one
# directory rather than several hundred loose files.
#
# The two modes differ in the zip's name and in nothing else, so an internal
# package unpacks to the same folder with the same contents plus one file. The
# name carries the short revision because an internal package is handed over by
# hand and there is otherwise nothing on it to say which build it is; the public
# one does not need it, because the run that produced it is its provenance.

if (-not ('System.IO.Compression.ZipFile' -as [type])) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
}
$zipName = if ($internal) {
    $short = if ($Revision.Length -ge 7) { $Revision.Substring(0, 7) } else { $Revision }
    "$productName-internal-$short.zip"
} else {
    "$productName.zip"
}
$zipPath = Join-Path $OutputDirectory $zipName
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $staging, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $true)

$files = @(Get-ChildItem -Path $staging -Recurse -File)
$unpacked = ($files | Measure-Object -Property Length -Sum).Sum
$zip = Get-Item $zipPath

Write-Host ''
Write-Host ("Kind:             {0}" -f $(if ($internal) { 'complete internal package — keep it off public locations' } else { 'public-safe, without the network' }))
Write-Host "Distribution:     $zipPath"
Write-Host ("Zipped:           {0:N0} bytes" -f $zip.Length)
Write-Host ("Unpacked:         {0:N0} bytes in {1:N0} files" -f $unpacked, $files.Count)
Write-Host ("SHA-256:          {0}" -f (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLowerInvariant())
# What is actually in it, at a size somebody can read. A self-contained .NET
# publish carries a satellite-resource directory per culture — around ninety of
# them, two files each — and listing those one to a line buries the ten things a
# reader of this log is looking for. They are kept rather than trimmed with
# SatelliteResourceLanguages: they are the framework's own text in the user's
# language, this app's normative language is Chinese, and trimming a localized
# resource to save a download is the wrong trade in an app whose whole subject
# is read in characters.
Write-Host ''
Write-Host 'Top level:'
$cultures = @()
foreach ($entry in Get-ChildItem -Path $staging | Sort-Object PSIsContainer, Name) {
    if (-not $entry.PSIsContainer) {
        Write-Host ("  {0,-34} {1,13:N0} bytes" -f $entry.Name, $entry.Length)
        continue
    }
    $inner = @(Get-ChildItem -Path $entry.FullName -Recurse -File)
    $bytes = ($inner | Measure-Object -Property Length -Sum).Sum
    # A culture directory is named like a culture and holds only resources.
    if ($entry.Name -match '^[a-z]{2,3}(-[A-Za-z]+)+$') {
        $cultures += [pscustomobject]@{ Files = $inner.Count; Bytes = [long] $bytes }
        continue
    }
    Write-Host ("  {0,-34} {1,13:N0} bytes in {2} files" -f "$($entry.Name)\", $bytes, $inner.Count)
}
if ($cultures.Count -gt 0) {
    $cultureBytes = ($cultures | Measure-Object -Property Bytes -Sum).Sum
    $cultureFiles = ($cultures | Measure-Object -Property Files -Sum).Sum
    Write-Host ("  {0,-34} {1,13:N0} bytes in {2} files" `
        -f "$($cultures.Count) localized resource dirs", $cultureBytes, $cultureFiles)
}

# The five biggest single files, which is how a size question gets answered
# without reading five hundred lines.
Write-Host ''
Write-Host 'Largest files:'
foreach ($file in ($files | Sort-Object Length -Descending | Select-Object -First 5)) {
    $relative = $file.FullName.Substring($staging.Length).TrimStart('\')
    Write-Host ("  {0,-34} {1,13:N0} bytes" -f $relative, $file.Length)
}

Write-Host ''
Write-Host 'MXQ_PACKAGE_OK'
