<#
.SYNOPSIS
Build the Microsoft Store package: one unsigned .msix per architecture.

.DESCRIPTION
The Store is the intended public channel for Windows (owner decision,
2026-07-31). This script is that build, and windows/package-zip.ps1 beside it
still builds the direct download; the two are different deployment shapes of one
app, from one project, and neither is the other's fallback.

Run windows/build-core-dll.ps1 first, for the same architecture, exactly as the
zip's build needs it: the core is consumed as a prebuilt DLL beside a prebuilt
asset directory and a staged C++ runtime, and this script packages on top of
that rather than compiling C++ itself.

NOTHING HERE SIGNS ANYTHING, AND NOTHING EVER WILL

A package submitted to the Store is signed by the Store, with Microsoft's own
certificate, after it is accepted — so the file this produces is deliberately
unsigned and there is no certificate to obtain, store, rotate or leak. That is
why this script needs no secret and why CI can build it on a public repository.
AppxPackageSigningEnabled=false is the setting that says so.

An unsigned .msix cannot be double-clicked to install. The owner's own check on
a machine before submission is Add-AppxPackage -Register over an unpacked
layout with Developer Mode on, which needs no certificate either;
windows/README.md § The Store package has the commands.

HOW THE PACKAGED SHAPE DIFFERS, AND WHERE THAT IS DECIDED

In MiniXiangqi.App.csproj, under one condition: MxqPackaged. This script is the
only thing that sets it. The packaged side takes the Windows App SDK as a
framework dependency the Store installs rather than a private copy, keeps .NET
self-contained because a package cannot express a .NET dependency, and includes
Package.appxmanifest and Images\ — all of which the unpackaged side removes from
its item set, so the zip's inputs are what they were before any of this existed.

WHY IT UNPACKS WHAT IT JUST BUILT

Because the manifest in this repository is not the manifest that ships. The
packaging build rewrites it — filling ProcessorArchitecture from /p:Platform,
resolving $targetnametoken$, adding the framework dependency the Windows App SDK
declares — and what the Store reads is that generated AppxManifest.xml. Checking
the source manifest would be checking our own input. So the package is unpacked
and every assertion below is made against what came out of it.

The tree assertions are there because each names a failure that is silent until
somebody installs the thing. A package without the resource index or the
compiled XAML installs and dies before its first window. A package whose assets
directory lost the network installs, runs, and declines to think. An ARM64
package that quietly resolved x64 natives builds, uploads, passes certification
and fails on every machine it is for.

.PARAMETER Architecture
x64 or arm64. Decides /p:Platform, the runtime identifier, and what every
binary in the package is checked against.

.PARAMETER Configuration
The MSBuild configuration. Release by default.

.PARAMETER OutputDirectory
Where the .msix is written. windows/dist by default, which .gitignore covers.

.EXAMPLE
pwsh windows/build-core-dll.ps1
pwsh windows/package-msix.ps1
#>
[CmdletBinding()]
param(
    [ValidateSet('x64', 'arm64')]
    [string] $Architecture = $(if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }),
    [string] $Configuration = 'Release',
    [string] $OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The same PE reader windows/build-core-dll.ps1 and windows/package-zip.ps1 use.
. (Join-Path $PSScriptRoot 'Get-PeMachine.ps1')

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$rid = "win-$Architecture"
# MSBuild's platform names are not the runtime identifier's. ARM64 is
# capitalised here because that is the platform name the AppX targets and the
# Visual Studio configurations use; the manifest's ProcessorArchitecture comes
# out of it lower-cased, which is what the assertion below compares against.
$platform = if ($Architecture -eq 'arm64') { 'ARM64' } else { 'x64' }
$project = Join-Path $repoRoot 'windows\MiniXiangqi.App\MiniXiangqi.App.csproj'

if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot 'windows\dist' }
$null = New-Item -ItemType Directory -Force -Path $OutputDirectory
$OutputDirectory = (Resolve-Path $OutputDirectory).Path

$manifest = Get-Content (Join-Path $repoRoot 'pinned-inputs.json') -Raw | ConvertFrom-Json

# ---------------------------------------------------------------------------
# MSBuild
# ---------------------------------------------------------------------------
#
# msbuild.exe rather than `dotnet build`, and located through vswhere rather
# than assumed, the same way windows/build-core-dll.ps1 locates the C++
# toolset. `dotnet build` cannot produce an .msix at all: the packaging targets
# are Visual Studio's, and the -requires filter below is how this asks for an
# installation that has them.
#
# No setup-msbuild action in CI either. Both runner images already carry Visual
# Studio — the zip's build and the core's build depend on that today — so an
# action that puts MSBuild on PATH would add a third-party dependency to obtain
# something already present.

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) {
    throw "vswhere.exe not found at $vswhere; install Visual Studio with the MSBuild component."
}
$msbuild = @(& $vswhere -latest -products * -requires Microsoft.Component.MSBuild `
    -find 'MSBuild\**\Bin\MSBuild.exe')
if ($msbuild.Count -eq 0) {
    throw ('No Visual Studio installation with MSBuild was found. The Store package is built by ' +
           'the packaging targets Visual Studio carries and the .NET CLI does not.')
}
$msbuild = $msbuild[0]
Write-Host "MSBuild: $msbuild"
& $msbuild -version -nologo | Select-Object -Last 1 | ForEach-Object { Write-Host "  version $_" }

$appxDir = Join-Path $OutputDirectory 'msix-build'
if (Test-Path $appxDir) { Remove-Item $appxDir -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path $appxDir

$common = @(
    $project
    "-p:Configuration=$Configuration"
    "-p:Platform=$platform"
    '-p:MxqPackaged=true'
    "-p:MxqRuntimeIdentifier=$rid"
    '-nologo'
    '-v:minimal'
)

Write-Host ''
Write-Host "Restoring MiniXiangqi.App ($platform, $rid)"
& $msbuild @common -t:Restore
if ($LASTEXITCODE -ne 0) { throw 'Restore failed.' }

# UapAppxPackageBuildMode is SideloadOnly rather than StoreUpload deliberately.
# StoreUpload asks the build for a symbol package as well, which drags in
# mspdbcmf and fails on a hosted runner; the upload file the Store wants is a
# zip of the two architectures' .msix and .github/workflows/windows-frontend.yml
# builds it itself, which is Microsoft's own documented manual alternative.
# A .appxsym is optional and we do not ship one.
Write-Host ''
Write-Host "Building the package ($Configuration, $platform)"
& $msbuild @common -t:Build `
    -p:GenerateAppxPackageOnBuild=true `
    -p:AppxBundle=Never `
    "-p:AppxBundlePlatforms=$platform" `
    -p:UapAppxPackageBuildMode=SideloadOnly `
    -p:AppxPackageSigningEnabled=false `
    "-p:AppxPackageDir=$appxDir\"
if ($LASTEXITCODE -ne 0) { throw 'The package build failed.' }

$produced = @(Get-ChildItem -Path $appxDir -Filter '*.msix' -File -Recurse)
if ($produced.Count -ne 1) {
    $found = if ($produced.Count -eq 0) { 'none' } else { ($produced | ForEach-Object { $_.Name }) -join ', ' }
    throw ("Expected exactly one .msix under $appxDir; found $($produced.Count) ($found). More than one " +
           'usually means bundling produced per-architecture packages beside the bundle, which AppxBundle ' +
           'Never is set to prevent.')
}

$msixPath = Join-Path $OutputDirectory "MiniXiangqi-windows-$Architecture.msix"
if (Test-Path $msixPath) { Remove-Item $msixPath -Force }
Move-Item $produced[0].FullName $msixPath

# ---------------------------------------------------------------------------
# What the Store will actually read
# ---------------------------------------------------------------------------
#
# makeappx is found by globbing the installed Windows SDKs rather than by naming
# one: the SDK build moves with every runner image refresh, and a hard-coded
# path fails a long way from its cause. The host's own architecture first —
# an ARM64 machine has a native makeappx and would otherwise run the x64 one
# under emulation — then x64, which every SDK carries.

$kitsBin = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
if (-not (Test-Path $kitsBin)) {
    throw "No Windows SDK was found under $kitsBin; makeappx.exe is what verifies the package."
}
$sdkVersions = @(Get-ChildItem -Path $kitsBin -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
    Sort-Object { [version] $_.Name } -Descending)
$hostFolders = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { @('arm64', 'x64') } else { @('x64') }
$makeappx = $null
foreach ($folder in $hostFolders) {
    foreach ($version in $sdkVersions) {
        $candidate = Join-Path $version.FullName "$folder\makeappx.exe"
        if (Test-Path $candidate) { $makeappx = $candidate; break }
    }
    if ($makeappx) { break }
}
if (-not $makeappx) {
    throw ("makeappx.exe was not found under any of $(($sdkVersions | ForEach-Object { $_.Name }) -join ', ') " +
           "in $kitsBin. It is what unpacks the package so that the manifest the Store reads can be " +
           'checked rather than assumed.')
}
Write-Host ''
Write-Host "Verifying with $makeappx"

$unpacked = Join-Path $appxDir 'unpacked'
if (Test-Path $unpacked) { Remove-Item $unpacked -Recurse -Force }
& $makeappx unpack /p $msixPath /d $unpacked /o
if ($LASTEXITCODE -ne 0) { throw "makeappx could not unpack $msixPath." }

$generated = Join-Path $unpacked 'AppxManifest.xml'
if (-not (Test-Path $generated)) { throw "The package holds no AppxManifest.xml." }
[xml] $appx = Get-Content $generated -Raw
$ns = New-Object System.Xml.XmlNamespaceManager($appx.NameTable)
$ns.AddNamespace('d', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10')
$ns.AddNamespace('uap', 'http://schemas.microsoft.com/appx/manifest/uap/windows10')

$failures = @()

# The architecture, which is the whole reason there are two of these files.
$identity = $appx.SelectSingleNode('/d:Package/d:Identity', $ns)
$declaredArch = $identity.GetAttribute('ProcessorArchitecture')
if ($declaredArch -ne $Architecture) {
    $failures += ("Identity/@ProcessorArchitecture is '$declaredArch'; this leg builds $Architecture. " +
                  'The Store rejects two packages that claim the same architecture and offers nothing ' +
                  'to a machine no package claims.')
}

# The version's shape. The Store refuses a package whose revision part is not 0,
# and refuses one whose version is not higher than the last accepted — the
# second is the owner's to keep track of, the first is arithmetic and belongs
# here.
$version = $identity.GetAttribute('Version')
$parts = @($version -split '\.')
if ($parts.Count -ne 4 -or $parts[3] -ne '0') {
    $failures += ("Identity/@Version is '$version'. A Store package's version is four parts and its " +
                  'fourth — the revision — must be 0; the Store reserves it.')
}

# The Windows 11 floor, which must be the same number as the project's
# TargetPlatformMinVersion. This one is checked here because the manifest is
# what decides which machines are offered the app.
$family = $appx.SelectSingleNode("/d:Package/d:Dependencies/d:TargetDeviceFamily[@Name='Windows.Desktop']", $ns)
if (-not $family) {
    $failures += 'No TargetDeviceFamily named Windows.Desktop. A packaged desktop app declares one.'
} elseif ($family.GetAttribute('MinVersion') -ne '10.0.22000.0') {
    $failures += ("TargetDeviceFamily MinVersion is '$($family.GetAttribute('MinVersion'))'; the product " +
                  'floor is Windows 11, whose first build is 10.0.22000.0, and MiniXiangqi.App.csproj ' +
                  'sets TargetPlatformMinVersion to the same number.')
}

# Both languages. x-generate would have found one, because this app's
# bilingualism is a C# string table rather than qualified resources, and an app
# that says it speaks one language is what a Chinese-language customer would be
# shown.
$languages = @($appx.SelectNodes('/d:Package/d:Resources/d:Resource', $ns) |
    ForEach-Object { $_.GetAttribute('Language') })
foreach ($language in @('en-US', 'zh-Hans')) {
    if ($languages -notcontains $language) {
        $failures += ("The package declares languages $($languages -join ', ') and not $language. " +
                      'Both are declared explicitly in Package.appxmanifest for a reason written there.')
    }
}

# One capability, and it is the one that says this is a Win32 process. Anything
# else is a permission shown to every customer for a thing the app does not do.
$capabilities = @($appx.SelectNodes('/d:Package/d:Capabilities/*', $ns) |
    ForEach-Object { $_.GetAttribute('Name') })
if ($capabilities.Count -ne 1 -or $capabilities[0] -ne 'runFullTrust') {
    $failures += ("The package declares capabilities: $($capabilities -join ', '). runFullTrust is the " +
                  'only one this app is entitled to; it uses no network and no restricted device.')
}

# The Windows App SDK as a dependency rather than as cargo. This is the other
# half of WindowsAppSDKSelfContained=false: the package sheds its private copy
# of the runtime *because* the manifest asks the Store to install the framework.
# If the dependency were missing, the package would install and then fail to
# start on any machine that had never seen the Windows App Runtime, which is
# most of them.
$dependencies = @($appx.SelectNodes('/d:Package/d:Dependencies/d:PackageDependency', $ns))
Write-Host ''
Write-Host 'Framework dependencies the Store will install:'
if ($dependencies.Count -eq 0) { Write-Host '  none' }
foreach ($dependency in $dependencies) {
    Write-Host ("  {0}  min {1}" -f $dependency.GetAttribute('Name'), $dependency.GetAttribute('MinVersion'))
}
$runtimeDependency = @($dependencies |
    Where-Object { $_.GetAttribute('Name') -like 'Microsoft.WindowsAppRuntime*' })
if ($runtimeDependency.Count -eq 0) {
    $failures += ('The manifest declares no Microsoft.WindowsAppRuntime framework dependency. This build ' +
                  'sets WindowsAppSDKSelfContained=false, so the runtime is not in the package either, ' +
                  'and an app that has neither does not start.')
}

# Every image the manifest names. Not at the literal path, because that is not
# how a package carries images: the manifest names Images\StoreLogo.png and the
# package holds Images\StoreLogo.scale-100.png and its four siblings, which the
# shell resolves through the resource index by the display's scale. So each
# declared path is satisfied either by itself or by at least one qualified
# frame, and what satisfied it is printed.
function Resolve-PackagedImage {
    param([string] $Root, [string] $Declared)

    $exact = Join-Path $Root $Declared
    if (Test-Path $exact) { return @{ How = 'the file itself'; Count = 1 } }

    $directory = Join-Path $Root (Split-Path $Declared -Parent)
    if (-not (Test-Path $directory)) { return $null }
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($Declared)
    $extension = [System.IO.Path]::GetExtension($Declared)
    $pattern = '^{0}\.(scale-\d+|targetsize-\d+)' -f [regex]::Escape($stem)
    $variants = @(Get-ChildItem -Path $directory -File |
        Where-Object { $_.Extension -eq $extension -and $_.Name -match $pattern })
    if ($variants.Count -eq 0) { return $null }
    return @{ How = 'qualified frames'; Count = $variants.Count }
}

$declaredImages = @($appx.SelectSingleNode('/d:Package/d:Properties/d:Logo', $ns).InnerText)
$visual = $appx.SelectSingleNode('/d:Package/d:Applications/d:Application/uap:VisualElements', $ns)
foreach ($attribute in @('Square150x150Logo', 'Square44x44Logo')) {
    $declaredImages += $visual.GetAttribute($attribute)
}
Write-Host ''
Write-Host 'Images the manifest names:'
foreach ($declared in $declaredImages) {
    $resolution = Resolve-PackagedImage -Root $unpacked -Declared $declared
    if (-not $resolution) {
        $failures += ("The manifest names $declared and the package holds neither that file nor any " +
                      'scale- or targetsize- frame of it. Run windows/make-app-icon.py with the 1024 px ' +
                      'export to regenerate windows/MiniXiangqi.App/Images.')
        continue
    }
    Write-Host ("  {0,-32} {1} ({2})" -f $declared, $resolution.How, $resolution.Count)
}

if ($failures.Count -gt 0) {
    throw ("The generated manifest is not what this package has to be:" + [Environment]::NewLine +
           '  - ' + ($failures -join ([Environment]::NewLine + '  - ')))
}
Write-Host ''
Write-Host "Identity:         $($identity.GetAttribute('Name'))  $version  $declaredArch"
Write-Host "Publisher:        $($identity.GetAttribute('Publisher'))"
Write-Host "Languages:        $($languages -join ', ')"
Write-Host "Capabilities:     $($capabilities -join ', ')"

# ---------------------------------------------------------------------------
# What is in the package
# ---------------------------------------------------------------------------
#
# Measured on the unpacked tree, not reasoned about from the project file. The
# .pri and the .xbf are here because their absence is precisely the class of
# defect that shipped a zip which could not open a window: the resource index is
# what ms-appx:///App.xaml resolves through and the .xbf is the compiled markup,
# and neither reaches an output by being referenced. If either of these fails,
# the fix is to hook the packaging payload the way MxqPublishCompiledXaml hooks
# publish — not to relax the check.

$missing = @()
$indexes = @(Get-ChildItem -Path $unpacked -Filter '*.pri' -File | ForEach-Object { $_.Name })
if (-not ($indexes -contains 'resources.pri' -or $indexes -contains 'MiniXiangqi.App.pri')) {
    $found = if ($indexes.Count -eq 0) { 'none' } else { $indexes -join ', ' }
    $missing += ("no resource index at the package root (found: $found). ms-appx:///App.xaml resolves " +
                 'through one, and without it the app dies on launch with a stowed exception inside ' +
                 'Microsoft.UI.Xaml.dll before any window appears.')
}
$xbf = @(Get-ChildItem -Path $unpacked -Filter '*.xbf' -File -Recurse)
if ($xbf.Count -eq 0) {
    $missing += ('no compiled XAML (.xbf). App.xaml and MainWindow.xaml compile to these and the app ' +
                 'cannot build its window without them.')
}

foreach ($required in @('mxqcore.dll', 'vcruntime140.dll', 'MiniXiangqi.App.exe')) {
    if (-not (Test-Path (Join-Path $unpacked $required))) {
        $missing += "$required is not in the package."
    }
}

# .NET travels because a package cannot ask for it. hostfxr and coreclr are only
# in an output that was published self-contained, so their presence is the
# check that SelfContained survived the packaging build's own command line.
foreach ($required in @('hostfxr.dll', 'coreclr.dll')) {
    if (-not (Test-Path (Join-Path $unpacked $required))) {
        $missing += ("$required is not in the package, so this is a framework-dependent .NET app. An " +
                     'MSIX cannot declare a dependency on the .NET runtime, so it would install and ' +
                     'fail to start wherever that runtime is absent.')
    }
}

if (-not (Test-Path (Join-Path $unpacked 'sounds'))) {
    $missing += 'sounds\ is not in the package; the board would land every move in silence.'
}

# The assets, by the names pinned-inputs.json pins rather than by names restated
# here. A package whose network is absent or renamed does not crash: the AI
# declines to start, everything else works, and nobody can tell why.
$packagedAssets = Join-Path $unpacked 'assets'
foreach ($asset in @($manifest.variant.filename, $manifest.network.filename)) {
    if (-not (Test-Path (Join-Path $packagedAssets $asset))) {
        $missing += "assets\$asset is not in the package."
    }
}

if ($missing.Count -gt 0) {
    throw ("The package is missing what it needs:" + [Environment]::NewLine +
           '  - ' + ($missing -join ([Environment]::NewLine + '  - ')))
}

# ---------------------------------------------------------------------------
# Every native binary is this architecture
# ---------------------------------------------------------------------------
#
# The same sweep windows/package-zip.ps1 makes over the zip, over the package
# instead, and load-bearing for the same reason: an ARM64 package that quietly
# resolved an x64 native builds, uploads, passes certification and fails on
# every machine it is for. The natives it would be wrong about are Win2D's and
# the Windows App SDK's, which only a window loads, so nothing headless notices.

$expectedMachine = Get-PeMachineForArchitecture -Architecture $Architecture
Write-Host ''
Write-Host "Checking that every binary in the package is $Architecture"
$native = 0
$hybrid = @()
$wrong = @()
foreach ($file in @(Get-ChildItem -Path $unpacked -Recurse -File |
        Where-Object { $_.Extension -eq '.dll' -or $_.Extension -eq '.exe' })) {
    $machine = Get-PeMachine -Path $file.FullName
    if ($null -eq $machine) { continue }
    # A managed assembly built AnyCPU reports x86 here and is not a native
    # binary; every native this ships is 64-bit.
    if ($machine -eq 0x014C) { continue }
    # ARM64EC companions, which the Windows App SDK publishes into its win-x64
    # output. An ARM64EC image declares machine ARM64 while being what lets an
    # x64 process run efficiently on an ARM64 machine, so they are named rather
    # than failed on; what would be wrong is an ARM64 binary that is not one.
    if ($file.BaseName.EndsWith('_ec')) { $hybrid += $file.Name; continue }

    $native++
    if ($machine -ne $expectedMachine) {
        $wrong += "$($file.Name): $(Get-PeMachineName $machine)"
    }
}
if ($wrong.Count -gt 0) {
    throw ("These binaries are not $Architecture, so this package would not run on the machines it is " +
           'for: ' + ($wrong -join '; '))
}
Write-Host "  $native binaries, all $Architecture"
if ($hybrid.Count -gt 0) {
    Write-Host "  $($hybrid.Count) ARM64EC companion(s) from the Windows App SDK: $($hybrid -join ', ')"
}

$package = Get-Item $msixPath
$contents = @(Get-ChildItem -Path $unpacked -Recurse -File)
Write-Host ''
Write-Host "Store package:    $msixPath"
Write-Host ("Packed:           {0:N0} bytes" -f $package.Length)
Write-Host ("Unpacked:         {0:N0} bytes in {1:N0} files" -f `
    (($contents | Measure-Object -Property Length -Sum).Sum), $contents.Count)
Write-Host ("SHA-256:          {0}" -f (Get-FileHash $msixPath -Algorithm SHA256).Hash.ToLowerInvariant())
Write-Host ''
Write-Host 'MXQ_MSIX_OK'
