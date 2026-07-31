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
  windows/artifacts/assets/          the asset directory MxqCoreConfig points
                                     at: the pinned variant configuration and
                                     the NNUE network under its bundled name

The asset directory is copied from the staging the core's own CMake performs,
which verifies the network's byte length and SHA-256 against pinned-inputs.json
before writing a byte. Staging it a second time here would mean verifying it a
second time, or not verifying it at all. windows/package-zip.ps1 is the
packaging build, and it starts from this staging for the same reason: it removes
the network from what it ships rather than staging an unverified copy.

.PARAMETER Configuration
The CMake build type. RelWithDebInfo by default.

.PARAMETER Architecture
x64 or arm64, defaulting to the machine this runs on. Each writes the same
windows/artifacts/, so the directory holds one architecture's core at a time;
the build tree is per-architecture, so switching back does not recompile.

.PARAMETER NnueSource
The pinned NNUE network's bytes. Defaults to the MXQ_NNUE_SOURCE environment
variable, and then to the workspace location core/CMakeLists.txt expects. The
bytes are in no repository; see docs/engine-integration.md.

.PARAMETER BuildDirectory
The CMake build tree. core/.build-windows-<architecture> by default, which
.gitignore covers.

.EXAMPLE
pwsh windows/build-core-dll.ps1 -NnueSource C:\mxq\control\nnue\minixiangqi-12c45d5da817.nnue
#>
[CmdletBinding()]
param(
    [ValidateSet('RelWithDebInfo', 'Debug', 'Release', 'MinSizeRel')]
    [string] $Configuration = 'RelWithDebInfo',
    [ValidateSet('x64', 'arm64')]
    [string] $Architecture = $(if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }),
    [string] $NnueSource = $env:MXQ_NNUE_SOURCE,
    [string] $BuildDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $BuildDirectory) {
    $BuildDirectory = Join-Path $repoRoot "core\.build-windows-$Architecture"
}
if (-not $NnueSource) {
    $NnueSource = Join-Path $repoRoot '.git\minixiangqi-control\nnue\minixiangqi-12c45d5da817.nnue'
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

$cmakeNnue = $NnueSource -replace '\\', '/'

Write-Host "Configuring $BuildDirectory ($Configuration, $Architecture)"
& cmake -S (Join-Path $repoRoot 'core') -B $BuildDirectory -G Ninja `
    "-DCMAKE_BUILD_TYPE=$Configuration" `
    '-DMXQ_ENABLE_RULES_FACADE=ON' `
    '-DMXQ_BUILD_SHARED_LIBRARY=ON' `
    '-DBUILD_TESTING=OFF' `
    "-DMXQ_NNUE_SOURCE=$cmakeNnue"
if ($LASTEXITCODE -ne 0) { throw 'CMake configuration failed.' }

Write-Host 'Building mxq_core_shared'
& cmake --build $BuildDirectory --target mxq_core_shared
if ($LASTEXITCODE -ne 0) { throw 'The shared core failed to build.' }

$artifacts = Join-Path $repoRoot 'windows\artifacts'
$artifactAssets = Join-Path $artifacts 'assets'
$null = New-Item -ItemType Directory -Force -Path $artifactAssets

$dll = Join-Path $BuildDirectory 'shared\mxqcore.dll'
if (-not (Test-Path $dll)) { throw "mxqcore.dll was not produced at $dll." }
Copy-Item $dll $artifacts -Force
$pdb = Join-Path $BuildDirectory 'shared\mxqcore.pdb'
if (Test-Path $pdb) { Copy-Item $pdb $artifacts -Force }

# The staged, verified asset directory. Configuration warns and stages nothing
# when the network is missing or does not match its pins, so an empty staging
# directory here means exactly that, and is reported rather than shipped past.
$staged = Join-Path $BuildDirectory 'test-assets'
$stagedFiles = @()
if (Test-Path $staged) { $stagedFiles = @(Get-ChildItem -File $staged) }
if ($stagedFiles.Count -lt 2) {
    throw ("The core staged no verified assets in $staged. The NNUE network at " +
           "$NnueSource is missing, or does not match the byte length and SHA-256 " +
           "pinned-inputs.json pins. Re-run with -NnueSource pointing at the pinned bytes.")
}
$stagedFiles | ForEach-Object { Copy-Item $_.FullName $artifactAssets -Force }

Write-Host ''
Write-Host "Architecture:     $Architecture"
Write-Host "Core DLL:         $(Join-Path $artifacts 'mxqcore.dll')"
Write-Host "Asset directory:  $artifactAssets"
Get-ChildItem -File $artifactAssets | ForEach-Object {
    Write-Host ("  {0}  {1:N0} bytes" -f $_.Name, $_.Length)
}
Write-Host ''
Write-Host 'MXQ_CORE_DLL_OK'
