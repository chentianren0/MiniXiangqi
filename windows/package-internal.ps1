<#
.SYNOPSIS
Build the complete internal package: the same zip CI builds, with the AI's
network file in it.

.DESCRIPTION
There are two Windows distributions and the difference between them is one file
and a licensing line.

  package-zip.ps1        the public-safe zip. Everything except the NNUE
                         network, plus a NETWORK.md naming the file its holder
                         must add. This is what CI builds and uploads.

  package-internal.ps1   this. The same layout, the same code path — it *is*
                         package-zip.ps1, called with the bytes — with the
                         network verified and placed, named -internal.

**Why the split exists.** Bundling the pinned network for internal testers is
accepted (docs/engine-integration.md's NNUE handling policy). What is not is a
public location: the network's origin and redistribution licence have never been
established, and that document makes establishing them a mandatory gate for any
distribution beyond internal testing. This repository is public, and a GitHub
Actions artifact on a public repository can be downloaded by any logged-in
GitHub account — so the automatically published zip cannot carry the network
whatever anybody intends, and it does not. A package built here, on a machine
the owner controls, and handed to a tester directly is the other case, and it
carries it.

So: **this zip does not go anywhere public.** Not a release attachment, not an
artifact, not a shared link that does not know who is on the other end. Its own
NETWORK.md and README.md say so too, for whoever opens it later without this
script in front of them.

Nothing here uploads anything. It writes one file to disk and stops.

.PARAMETER NnueSource
The pinned NNUE network's bytes. Required, and verified against
pinned-inputs.json's byte length and SHA-256 before anything is packaged;
neither is restated here. Defaults to the development VM's copy.

.PARAMETER Architecture
x64 or arm64, defaulting to the machine this runs on. It must match the
architecture windows/build-core-dll.ps1 last staged, which the packaging build
checks rather than trusts.

.PARAMETER Configuration
The MSBuild configuration to publish. Release by default.

.PARAMETER OutputDirectory
Where the zip is written. windows/dist by default, which .gitignore covers.

.EXAMPLE
pwsh windows/build-core-dll.ps1 -NnueSource C:\mxq\control\nnue\minixiangqi-12c45d5da817.nnue
pwsh windows/package-internal.ps1

Two commands, in that order, from the repository root. The first builds the core
for this machine's architecture and stages its verified assets; the second
publishes the frontend over it and packages the result. Run them with `pwsh`
rather than `powershell` — an SSH session on the development VM lands in Windows
PowerShell 5.1, where `&&` is not a statement separator; use `;` there, or start
`pwsh` first.
#>
[CmdletBinding()]
param(
    [string] $NnueSource = 'C:\mxq\control\nnue\minixiangqi-12c45d5da817.nnue',
    [ValidateSet('x64', 'arm64')]
    [string] $Architecture = $(if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }),
    [string] $Configuration = 'Release',
    [string] $OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $NnueSource)) {
    throw ("No NNUE network at $NnueSource. This script exists to produce the *complete* package, so " +
           "there is nothing useful for it to do without the bytes; pass -NnueSource, or run " +
           "package-zip.ps1 if the public-safe zip is what you wanted.")
}

$arguments = @{
    Architecture  = $Architecture
    NnueSource    = (Resolve-Path $NnueSource).Path
    Configuration = $Configuration
}
if ($OutputDirectory) { $arguments['OutputDirectory'] = $OutputDirectory }

& (Join-Path $PSScriptRoot 'package-zip.ps1') @arguments
