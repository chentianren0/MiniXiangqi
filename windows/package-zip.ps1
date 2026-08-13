<#
.SYNOPSIS
Build the Windows distribution: one zip somebody unpacks and runs.

.DESCRIPTION
The zip is the direct distribution for Windows: download, unpack, run, nothing
installed (issue #80, owner decision, 2026-07-30). This script is that build. It
runs on a developer machine and in .github/workflows/windows-frontend.yml, which
is where the artifact anybody downloads comes from.

It is not the only one any more. windows/package-msix.ps1 beside it builds the
Store package from the same core, the same publish inputs and the same project,
switched by MxqPackaged; the two are different deployment shapes of one app and
neither is the other's fallback. Nothing here knows about that one, which is
deliberate — this script's inputs and its output are exactly what they were.

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
    assets/                    the pinned variant configuration and both AI
                               networks
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

That network is gone. Both networks the two-game app uses are committed in this
repository under their established licences, and this build carries them like
every other asset. So there is one artifact, it is complete, and nobody
unpacking it has a file to go and find.

What survives from the old arrangement is the check, inverted. The publish copies
the asset directory windows/build-core-dll.ps1 staged — the verified one — and
this script then confirms both networks are there and are the networks: the exact
set of .nnue names, lengths, and SHA-256 values the manifest records.
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

# What architecture a binary actually is, read from its PE header rather than
# inferred from where it was found. One reader, shared with
# windows/build-core-dll.ps1 and windows/package-msix.ps1, because a
# disagreement between the three would be a distribution that builds and does
# not run.
. (Join-Path $PSScriptRoot 'Get-PeMachine.ps1')

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
$networkEntries = @($manifest.network.PSObject.Properties |
    Where-Object { -not $_.Name.StartsWith('_') } |
    ForEach-Object { $_.Value })

$staging = Join-Path $OutputDirectory $productName
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path $staging

$expectedMachine = Get-PeMachineForArchitecture -Architecture $Architecture

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
# Both networks are in here, checked rather than assumed
# ---------------------------------------------------------------------------
#
# The publish above copied the asset directory windows/build-core-dll.ps1
# staged, and that directory is the verified one: CMake checked both networks'
# byte lengths and SHA-256 values against pinned-inputs.json before writing them, and
# staged nothing that failed. Shipping that staging rather than assembling a
# second one is what keeps the zip's assets the bytes that were verified.
#
# Checking them again here is not the same check twice. What CMake verified was
# the file it was given; what this verifies is the file that survived a publish,
# a copy and whatever an MSBuild pipeline did in between — and the failure it
# catches is silent in a way the others are not. An app whose game network is absent,
# renamed or corrupt does not crash: the AI refuses to start, every other
# feature works, and the person who unpacked it has no way to know why. So:
# exactly the manifest's .nnue set, under its names, at its lengths, with its
# hashes. No value is restated here — all three come from the
# manifest, as docs/architecture.md's input rule requires.

$stagedAssets = Join-Path $staging 'assets'
Write-Host ''
Write-Host 'Checking the networks the zip carries'
$networks = @(Get-ChildItem -Path $stagedAssets -Filter '*.nnue' -File -ErrorAction SilentlyContinue)
if ($networks.Count -ne $networkEntries.Count) {
    $found = if ($networks.Count -eq 0) { 'none' } else { ($networks | ForEach-Object { $_.Name }) -join ', ' }
    throw ("Expected $($networkEntries.Count) .nnue files in $stagedAssets; found $($networks.Count) " +
           "($found). Re-run windows/build-core-dll.ps1 rather than shipping a zip whose AI may not start.")
}
foreach ($network in $networkEntries) {
    $matching = @($networks | Where-Object { $_.Name -ceq $network.filename })
    if ($matching.Count -ne 1) {
        throw ("The staged networks do not contain the exact case-sensitive name $($network.filename). " +
               "A renamed network is silently ignored by the engine.")
    }

    $stagedNetwork = $matching[0]
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
}
Write-Host '  names, lengths and hashes all match pinned-inputs.json'

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
# This used to be the script that fetched them, from whichever redistributable
# the build machine carried. It is now a check, because the fetching moved to
# windows/build-core-dll.ps1 and the runtime arrives here the way mxqcore.dll
# does — staged beside the core it belongs to, carried into the output by
# windows/CoreArtifacts.targets, copied into this publish as an item.
#
# The move was forced by the Store package, whose payload is a build output that
# no script gets to add files to afterwards; a copy step here could only ever
# have fixed the zip. What the zip gets out of it is that the runtime is now on
# the same path as the core that needs it, so the two cannot come from different
# builds. The message below is the one this branch always printed for the case
# where the publish already had them, and it is now the only case there is.
#
# Which files are the right ones is decided where they are staged, by reading
# each candidate's PE machine type: the set is not the same on both
# architectures, because the arm64 redistributable's vcruntime140_1.dll is an
# x64 binary. So this asks only for what every architecture must have. The
# machine-type sweep below reads all of them anyway.

$crtNames = @('msvcp140.dll', 'msvcp140_1.dll', 'msvcp140_2.dll',
              'msvcp140_atomic_wait.dll', 'msvcp140_codecvt_ids.dll',
              'vcruntime140.dll', 'vcruntime140_1.dll', 'concrt140.dll')
$present = @($crtNames | Where-Object { Test-Path (Join-Path $staging $_) })
foreach ($required in @('vcruntime140.dll', 'msvcp140.dll')) {
    if ($present -notcontains $required) {
        throw ("$required is not in the published output. mxqcore.dll links the C++ runtime " +
               "dynamically and nothing else in this build carries it, so the zip would fail to load " +
               "the core on any machine without Visual Studio. windows/build-core-dll.ps1 stages the " +
               "runtime beside the core and windows/CoreArtifacts.targets copies it; run that script " +
               "for -Architecture $Architecture and publish again.")
    }
}
Write-Host "The Visual C++ runtime was already in the published output: $($present -join ', ')"

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
    $machine = Get-PeMachine -Path $file.FullName
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
        $wrong += "$($file.Name): $(Get-PeMachineName $machine)"
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
# LICENSE and NOTICE.md are written by windows/New-DistributionNotices.ps1,
# which the Store package's build also calls: both distributions carry the same
# two documents, both are conveyances of GPL-licensed software, and the reasons
# are argued there rather than twice. Only the README below is this
# distribution's own, because only it is about unpacking a folder.

Write-Host ''
Write-Host 'Writing the licence and the attribution note'
& (Join-Path $PSScriptRoot 'New-DistributionNotices.ps1') -Destination $staging -Shape zip

Set-Content -Path (Join-Path $staging 'README.md') -Encoding UTF8 -Value @"
# Star River for Windows ($Architecture)

A native app for Xiangqi and Mini Xiangqi: play either against the AI
or in Free Play, with a saved history you can replay, export and import. Everything happens
on this machine — the app never uses the network.

## Running it

Unpack this folder anywhere you can write to, and run **``MiniXiangqi.App.exe``**.
There is nothing to install: the .NET runtime, the Windows App Runtime and the
Visual C++ runtime are all in this folder.

This is the whole app. Nothing is missing from it and there is nothing to add:
the AI's two neural networks are in ``assets`` with everything else, and ``NOTICE.md``
says what they are and where they came from.

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
