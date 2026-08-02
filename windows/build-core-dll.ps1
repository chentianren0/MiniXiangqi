<#
.SYNOPSIS
Build the shared core as mxqcore.dll and stage it, with the engine's assets,
under windows/artifacts/.

.DESCRIPTION
The C# projects consume the core as a prebuilt DLL beside a prebuilt asset
directory, exactly as the Apple app consumes a prebuilt XCFramework: run this
before building anything under windows/, and again after any change under
core/. Nothing it writes is in version control.

What it produces:

  windows/artifacts/mxqcore.dll      the C ABI, with the rules and search
                                     facades compiled in
  windows/artifacts/mxqcore.pdb      its symbols
  windows/artifacts/msvcp140*.dll    the Visual C++ runtime mxqcore.dll links
  windows/artifacts/vcruntime140*.dll  against, from the redistributable of the
  windows/artifacts/concrt140.dll    toolset that just compiled it
  windows/artifacts/assets/          the asset directory MxqCoreConfig points
                                     at: the pinned variant configuration and
                                     both NNUE networks under their bundled names

The C++ runtime is staged here, beside the core, because it belongs to the core:
mxqcore.dll is MSVC's output and links it dynamically, so the runtime is a
property of the DLL this script just built rather than of any particular way of
packaging it. Staging it here means windows/CoreArtifacts.targets carries it
into every executable's output the same way it carries mxqcore.dll, and both
packaging builds get it for free — the zip, which used to fetch it itself, and
the Store package, whose payload is a build output that no script gets to add
files to afterwards.

The asset directory is copied from the staging the core's own CMake performs,
which verifies both networks' byte lengths and SHA-256 values against pinned-inputs.json
before writing a byte. Staging it a second time here would mean verifying it a
second time, or not verifying it at all. windows/package-zip.ps1 is the
packaging build, and it ships this staging for the same reason: the assets in
the zip are the bytes that were verified rather than a second uncontrolled copy.

.PARAMETER Configuration
The CMake build type. RelWithDebInfo by default.

.PARAMETER Architecture
x64 or arm64, defaulting to the machine this runs on. Each writes the same
windows/artifacts/, so the directory holds one architecture's core at a time;
the build tree is per-architecture, so switching back does not recompile.

.PARAMETER NnueSource
An override for the Mini Xiangqi NNUE network's bytes, defaulting to the MXQ_NNUE_SOURCE
environment variable and then to nothing at all — in which case core/CMakeLists.txt
uses the network in the repository, which is the ordinary case and needs no
argument. Pass this only to build against a candidate network that has not been
committed yet.

.PARAMETER XiangqiNnueSource
The corresponding override for standard Xiangqi, defaulting to
MXQ_XIANGQI_NNUE_SOURCE and otherwise to the committed network.

.PARAMETER BuildDirectory
The CMake build tree. core/.build-windows-<architecture> by default, which
.gitignore covers.

.EXAMPLE
pwsh windows/build-core-dll.ps1
#>
[CmdletBinding()]
param(
    [ValidateSet('RelWithDebInfo', 'Debug', 'Release', 'MinSizeRel')]
    [string] $Configuration = 'RelWithDebInfo',
    [ValidateSet('x64', 'arm64')]
    [string] $Architecture = $(if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }),
    [string] $NnueSource = $env:MXQ_NNUE_SOURCE,
    [string] $XiangqiNnueSource = $env:MXQ_XIANGQI_NNUE_SOURCE,
    [string] $BuildDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# One PE reader for the three scripts that ask what architecture a binary is.
# This one asks it of the Visual C++ redistributable, below.
. (Join-Path $PSScriptRoot 'Get-PeMachine.ps1')

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $BuildDirectory) {
    $BuildDirectory = Join-Path $repoRoot "core\.build-windows-$Architecture"
}

# The MSVC environment. Located rather than assumed: the toolset moves with
# every Visual Studio update, and a hard-coded path fails a long way from its
# cause. pinned-inputs.json records the builds that established the core's
# Windows toolchains under windows.toolchain_core.
#
# The component and the environment script are the architecture's own. On an
# ARM64 host vcvarsarm64.bat is the native ARM64 toolset — host ARM64, target
# ARM64 — rather than a cross build; the cross-compiling script from an x64 host
# is vcvarsamd64_arm64.bat and is deliberately not what this reaches for, since
# every machine this runs on builds for itself.
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) {
    throw "vswhere.exe not found at $vswhere; install Visual Studio with the C++ desktop workload."
}
$component = if ($Architecture -eq 'arm64') {
    'Microsoft.VisualStudio.Component.VC.Tools.ARM64'
} else {
    'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
}
$vsPath = & $vswhere -latest -products * -requires $component -property installationPath
if (-not $vsPath) {
    throw "No Visual Studio installation with the $Architecture C++ toolset was found (looked for $component)."
}
$vcvarsName = if ($Architecture -eq 'arm64') { 'vcvarsarm64.bat' } else { 'vcvars64.bat' }
$vcvars = Join-Path $vsPath "VC\Auxiliary\Build\$vcvarsName"
if (-not (Test-Path $vcvars)) {
    throw "$vcvarsName not found at $vcvars."
}

Write-Host "Importing the $Architecture developer environment from $vcvars"
cmd /c "`"$vcvars`" >nul 2>&1 && set" | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') {
        Set-Item -Path "env:$($matches[1])" -Value $matches[2]
    }
}

# vcvars puts the compiler on PATH and stops there. CMake and Ninja are separate
# installations on a developer machine and are usually already on PATH; on a
# hosted runner they may only exist inside the Visual Studio installation, which
# ships both and adds neither. Falling back to those rather than failing is what
# makes this script run unchanged on a machine somebody else provisioned.
$vsCMake = Join-Path $vsPath 'Common7\IDE\CommonExtensions\Microsoft\CMake'
foreach ($tool in @(@{ Name = 'cmake'; Path = (Join-Path $vsCMake 'CMake\bin') },
                    @{ Name = 'ninja'; Path = (Join-Path $vsCMake 'Ninja') })) {
    if (-not (Get-Command $tool.Name -ErrorAction SilentlyContinue)) {
        if (Test-Path $tool.Path) {
            Write-Host "$($tool.Name) is not on PATH; using Visual Studio's at $($tool.Path)"
            $env:PATH = "$($tool.Path);$env:PATH"
        } else {
            throw "$($tool.Name) is on neither PATH nor $($tool.Path); install it, or install the Visual Studio CMake component."
        }
    }
}

# A source override is passed only when one was asked for. Left alone, CMake's
# own defaults are both networks in core/assets, which is what every ordinary
# build wants; passing paths here unconditionally would make this script a
# second source of their locations.
$configureOptions = @(
    "-DCMAKE_BUILD_TYPE=$Configuration"
    '-DMXQ_ENABLE_RULES_FACADE=ON'
    '-DMXQ_BUILD_SHARED_LIBRARY=ON'
    '-DBUILD_TESTING=OFF'
    # An override belongs to this invocation, not to the architecture's reused
    # CMake cache. Unset both first; the -D below restores only one explicitly
    # supplied now, while CMake supplies the committed default for the other.
    '-UMXQ_NNUE_SOURCE'
    '-UMXQ_XIANGQI_NNUE_SOURCE'
)
if ($NnueSource) {
    Write-Host "Overriding the Mini Xiangqi network with $NnueSource"
    $configureOptions += "-DMXQ_NNUE_SOURCE=$($NnueSource -replace '\\', '/')"
}
if ($XiangqiNnueSource) {
    Write-Host "Overriding the Xiangqi network with $XiangqiNnueSource"
    $configureOptions += "-DMXQ_XIANGQI_NNUE_SOURCE=$($XiangqiNnueSource -replace '\\', '/')"
}

Write-Host "Configuring $BuildDirectory ($Configuration, $Architecture)"
& cmake -S (Join-Path $repoRoot 'core') -B $BuildDirectory -G Ninja @configureOptions
if ($LASTEXITCODE -ne 0) { throw 'CMake configuration failed.' }

Write-Host 'Building mxq_core_shared'
& cmake --build $BuildDirectory --target mxq_core_shared
if ($LASTEXITCODE -ne 0) { throw 'The shared core failed to build.' }

$artifacts = Join-Path $repoRoot 'windows\artifacts'
$artifactAssets = Join-Path $artifacts 'assets'
$null = New-Item -ItemType Directory -Force -Path $artifactAssets

# Any network already here goes before the staged one is copied in. This
# directory accumulates rather than being rebuilt, so when the bundled network's
# name changes — as it did when the project's own network replaced the community
# one — a copy beside the old one leaves two, and windows/package-zip.ps1 would
# refuse the publish that came from it. Removing them here means the refusal
# never has to happen; the count check there stays as the guarantee.
Get-ChildItem -Path $artifactAssets -Filter '*.nnue' -File -ErrorAction SilentlyContinue |
    ForEach-Object {
        Write-Host "Removing a previously staged network: $($_.Name)"
        Remove-Item $_.FullName -Force
    }

$dll = Join-Path $BuildDirectory 'shared\mxqcore.dll'
if (-not (Test-Path $dll)) { throw "mxqcore.dll was not produced at $dll." }
Copy-Item $dll $artifacts -Force
$pdb = Join-Path $BuildDirectory 'shared\mxqcore.pdb'
if (Test-Path $pdb) { Copy-Item $pdb $artifacts -Force }

# ---------------------------------------------------------------------------
# The Visual C++ runtime, beside the core that links it
# ---------------------------------------------------------------------------
#
# mxqcore.dll is MSVC's output and links the C++ runtime dynamically, so a
# machine with no Visual Studio and no redistributable installed cannot load it.
# Neither self-contained mode carries it: --self-contained carries the .NET
# runtime and WindowsAppSDKSelfContained carries the Windows App Runtime, and
# the C++ runtime is neither.
#
# It is staged here rather than added by a packaging script because it belongs
# to the DLL above. windows/CoreArtifacts.targets then copies it into every
# executable's output beside mxqcore.dll, which is what makes it reach both
# distributions by the same route the core does — including the Store package,
# whose payload is a build output that nothing gets to add files to after the
# fact. windows/package-zip.ps1 used to fetch these itself; it now checks that
# they arrived.
#
# Each candidate's own PE machine type decides whether it is copied, rather than
# the folder it sits in. That is not belt and braces — the arm64 redistributable
# folder really does contain an x64 binary. `vcruntime140_1.dll` implements the
# x64 exception unwinder, ARM64 has no use for it, and Microsoft ships an x64
# copy under VC\Redist\MSVC\<version>\arm64\Microsoft.VC143.CRT anyway for the
# emulation and ARM64EC cases. Trusting the folder name put it in an ARM64 zip;
# reading each file is what stops that happening rather than being caught later.

$crtNames = @('msvcp140.dll', 'msvcp140_1.dll', 'msvcp140_2.dll',
              'msvcp140_atomic_wait.dll', 'msvcp140_codecvt_ids.dll',
              'vcruntime140.dll', 'vcruntime140_1.dll', 'concrt140.dll')

# Whatever this directory holds from an earlier architecture goes first, for the
# same reason the networks above do: this directory accumulates, the two
# architectures' sets are not the same set — vcruntime140_1.dll is in the x64
# one and not the arm64 one — and a file left behind is a file the next build
# ships. It would be caught by the machine-type sweep in the packaging build,
# which is a long way from here to find out.
Get-ChildItem -Path $artifacts -Filter '*.dll' -File -ErrorAction SilentlyContinue |
    Where-Object { $crtNames -contains $_.Name } |
    ForEach-Object {
        Write-Host "Removing a previously staged runtime file: $($_.Name)"
        Remove-Item $_.FullName -Force
    }

$expectedMachine = Get-PeMachineForArchitecture -Architecture $Architecture
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
    throw ("No Visual C++ $Architecture redistributable was found under $redistRoot. Install the " +
           "C++ redistributable component for this architecture; mxqcore.dll links the C++ runtime " +
           "dynamically and neither distribution runs on a clean machine without it.")
}

Write-Host "Staging the Visual C++ runtime from $crtSource"
foreach ($name in $crtNames) {
    $source = Join-Path $crtSource $name
    # The set differs by architecture and by toolset version. Anything the
    # redistributable does not carry for this architecture is something this
    # architecture does not need.
    if (-not (Test-Path $source)) { continue }
    $machine = Get-PeMachine -Path $source
    if ($machine -ne $expectedMachine) {
        Write-Host ("  skipped $name — it is $(Get-PeMachineName $machine) in the $Architecture " +
                    "redistributable, so it is not this architecture's")
        continue
    }
    Copy-Item $source $artifacts -Force
    Write-Host "  staged $name"
}
if (-not (Test-Path (Join-Path $artifacts 'vcruntime140.dll'))) {
    throw ("vcruntime140.dll is not in $crtSource, so nothing here can load mxqcore.dll on a machine " +
           "without Visual Studio. Check the C++ redistributable component for $Architecture.")
}

# The staged, verified two-game asset directory. Configuration warns and stages
# nothing when either network is missing or does not match its pins, so an incomplete staging
# directory here means exactly that, and is reported rather than shipped past.
$staged = Join-Path $BuildDirectory 'test-assets-xiangqi'
$stagedFiles = @()
if (Test-Path $staged) { $stagedFiles = @(Get-ChildItem -File $staged) }
if ($stagedFiles.Count -lt 3) {
    throw ("The core did not stage the variant configuration and both verified networks in $staged. " +
           "A network is missing or does not match the byte length and SHA-256 pinned-inputs.json pins. " +
           "The configure log above says which.")
}
$stagedFiles | ForEach-Object { Copy-Item $_.FullName $artifactAssets -Force }

Write-Host ''
Write-Host "Architecture:     $Architecture"
Write-Host "Core DLL:         $(Join-Path $artifacts 'mxqcore.dll')"
Write-Host "C++ runtime:      $(($crtNames | Where-Object { Test-Path (Join-Path $artifacts $_) }) -join ', ')"
Write-Host "Asset directory:  $artifactAssets"
Get-ChildItem -File $artifactAssets | ForEach-Object {
    Write-Host ("  {0}  {1:N0} bytes" -f $_.Name, $_.Length)
}
Write-Host ''
Write-Host 'MXQ_CORE_DLL_OK'
