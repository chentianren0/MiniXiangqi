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

WHAT THE ZIP CONTAINS

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
    assets/                    the pinned variant configuration and the AI's
                               neural network
    sounds/                    the board's four voices
    LICENSE                    GPL-3.0, this project's own
    NOTICE.md                  what else is inside and under what terms
    README.md                  what this is and how to run it

ONE ZIP, AND IT IS THE WHOLE APP

There used to be two, differing in one file: this zip without the NNUE network,
and an internal one with it. The reason was licensing rather than technical — the
network then bundled was community-trained, its redistribution licence was never
established, and a GitHub Actions artifact on a public repository is downloadable
by any logged-in account, so the published zip could not carry it whatever
anybody intended.

That network is gone. The one this project trained is in this repository, ours to
publish, and this build carries it like every other asset. So there is one
artifact, it is complete, and nobody unpacking it has a file to go and find.

What survives from the old arrangement is the check, inverted. The publish copies
the asset directory windows/build-core-dll.ps1 staged — the verified one — and
this script then confirms the network is there and is the network: exactly one
.nnue, the manifest's name, the manifest's byte length, the manifest's SHA-256.
A zip whose AI silently does not start is the failure this guards, and it is
cheaper to catch here than in somebody's hands.

.PARAMETER Architecture
x64 or arm64, defaulting to the machine this runs on. It must match the
architecture windows/build-core-dll.ps1 last staged, which is checked rather
than trusted: every native binary in the published tree has its PE machine type
read and compared.

.PARAMETER Configuration
The MSBuild configuration to publish. Release by default.

.PARAMETER OutputDirectory
Where the zip is written. windows/dist by default, which .gitignore covers.

.PARAMETER Revision
The commit this was built from, stamped into the zip's README.md. Defaults to
GITHUB_SHA and then to git rev-parse HEAD.

.EXAMPLE
pwsh windows/build-core-dll.ps1
pwsh windows/package-zip.ps1
#>
[CmdletBinding()]
param(
    [ValidateSet('x64', 'arm64')]
    [string] $Architecture = $(if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }),
    [string] $Configuration = 'Release',
    [string] $OutputDirectory,
    [string] $Revision
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$rid = "win-$Architecture"
$productName = "MiniXiangqi-windows-$Architecture"

if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot 'windows\dist' }
if (-not $Revision) { $Revision = $env:GITHUB_SHA }
if (-not $Revision) {
    $Revision = (& git -C $repoRoot rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) { $Revision = 'unknown' }
}

$manifest = Get-Content (Join-Path $repoRoot 'pinned-inputs.json') -Raw | ConvertFrom-Json
$network = $manifest.network
$fork = $manifest.fork
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
# The network is in here, checked rather than assumed
# ---------------------------------------------------------------------------
#
# The publish above copied the asset directory windows/build-core-dll.ps1
# staged, and that directory is the verified one: CMake checked the network's
# byte length and SHA-256 against pinned-inputs.json before writing it, and
# staged nothing that failed. Shipping that staging rather than assembling a
# second one is what keeps the zip's assets the bytes that were verified.
#
# Checking them again here is not the same check twice. What CMake verified was
# the file it was given; what this verifies is the file that survived a publish,
# a copy and whatever an MSBuild pipeline did in between — and the failure it
# catches is silent in a way the others are not. An app whose network is absent,
# renamed or corrupt does not crash: the AI refuses to start, every other
# feature works, and the person who unpacked it has no way to know why. So:
# exactly one .nnue, under the manifest's name, at the manifest's length, with
# the manifest's hash. No value is restated here — all three come from the
# manifest, as docs/architecture.md's input rule requires.

$stagedAssets = Join-Path $staging 'assets'
Write-Host ''
Write-Host 'Checking the network the zip carries'
$networks = @(Get-ChildItem -Path $stagedAssets -Filter '*.nnue' -File -ErrorAction SilentlyContinue)
if ($networks.Count -ne 1) {
    $found = if ($networks.Count -eq 0) { 'none' } else { ($networks | ForEach-Object { $_.Name }) -join ', ' }
    throw ("Expected exactly one .nnue in $stagedAssets; found $($networks.Count) ($found). More than one " +
           "usually means windows/artifacts/assets kept a network from an earlier build after the bundled " +
           "name changed — delete windows/artifacts and re-run windows/build-core-dll.ps1, which now clears " +
           "them itself. None means the core staged no network at all, which that script refuses to finish " +
           "without. Either way, stop rather than shipping a zip whose AI may not start.")
}
$stagedNetwork = $networks[0]
# -cne, not -ne: PowerShell's string comparison is case-insensitive by default,
# and the rule this gate defends is not. The engine matches the file's basename
# against the variant identifier case-sensitively, so a network whose name
# differs only in case passes -ne and is then ignored in silence at runtime,
# which is the one failure this whole check exists to catch.
if ($stagedNetwork.Name -cne $network.filename) {
    throw ("The staged network is named $($stagedNetwork.Name); pinned-inputs.json pins $($network.filename). " +
           "The engine restricts NNUE to the matching variant by this basename, and a name that does not " +
           "match disables NNUE silently while the app still reports it in use.")
}
if ($stagedNetwork.Length -ne $network.byte_length) {
    throw ("$($stagedNetwork.Name) is $('{0:N0}' -f $stagedNetwork.Length) bytes; pinned-inputs.json pins " +
           "$('{0:N0}' -f $network.byte_length). Refusing to package unverified bytes.")
}
$stagedHash = (Get-FileHash $stagedNetwork.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
if ($stagedHash -ne $network.sha256) {
    throw ("$($stagedNetwork.Name) hashes to $stagedHash; pinned-inputs.json pins $($network.sha256). " +
           "Refusing to package unverified bytes.")
}
Write-Host ("  {0}  {1:N0} bytes  sha256 {2}" -f $stagedNetwork.Name, $stagedNetwork.Length, $stagedHash)
Write-Host '  name, length and hash all match pinned-inputs.json'

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
# The documents
# ---------------------------------------------------------------------------
#
# NOTICE.md is generated from pinned-inputs.json rather than written by hand,
# because docs/architecture.md's input rule cuts both ways: a hash or a revision
# restated anywhere is a second place for it to be wrong, and a distribution that
# tells somebody the wrong revision is worse than one that tells them nothing.
#
# There is no NETWORK.md any more. It existed to tell a reader about a file that
# was not in the zip; the file is in the zip, so the honest length of that
# document is zero. What a reader may still want — which network, and how to
# check it survived the download — is one row in NOTICE.md and the self-check.

Copy-Item (Join-Path $repoRoot 'LICENSE') (Join-Path $staging 'LICENSE') -Force

Set-Content -Path (Join-Path $staging 'NOTICE.md') -Encoding UTF8 -Value @"
# Mini Xiangqi — licences and attribution

Mini Xiangqi is licensed under the **GNU General Public License version 3**. The
full text is in ``LICENSE`` beside this file. The project's source is at
<https://github.com/ppppvz/MiniXiangqi>.

What else is in this build, and under what terms. One section below is not a
third-party component at all — the neural network is this project's own — and it
is here because a reader looking for where the AI's evaluation came from will
look here first.

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

## The neural network — this project's own

The evaluation the AI thinks with is a neural network this project trained from
zero, and it is not a third-party component: it is covered by the licence at the
top of this file, like the rest of the application. It is in ``assets`` beside
the variant configuration.

| | |
|---|---|
| File name | ``$($network.filename)`` |
| Size | $('{0:N0}' -f $network.byte_length) bytes |
| SHA-256 | ``$($network.sha256)`` |
| Pipeline | <$($network.provenance.pipeline_repository)> |
| Pipeline revision | ``$($network.provenance.pipeline_revision)`` |

The pipeline above is public and is the provenance: it generates its own training
data with the engine revision named in this file and the variant configuration
beside the network, and generation 0 was trained from the engine's own classical
evaluation, with no other network as a teacher or a seed at any stage.

The packaging build verified this file against the size and hash above before
putting it here. To confirm it survived the download:

``````powershell
Get-FileHash .\assets\$($network.filename) -Algorithm SHA256
``````

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

This is the whole app. Nothing is missing from it and there is nothing to add:
the AI's neural network is in ``assets`` with everything else, and ``NOTICE.md``
says what it is and where it came from.

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
# One name, because there is one zip. The -internal- suffix a second, complete
# package used to carry is gone with the package: what it distinguished was
# whether the network was inside, and now it always is.

if (-not ('System.IO.Compression.ZipFile' -as [type])) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
}
$zipPath = Join-Path $OutputDirectory "$productName.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $staging, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $true)

$files = @(Get-ChildItem -Path $staging -Recurse -File)
$unpacked = ($files | Measure-Object -Property Length -Sum).Sum
$zip = Get-Item $zipPath

Write-Host ''
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
