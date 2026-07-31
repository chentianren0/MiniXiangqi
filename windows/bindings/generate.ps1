<#
.SYNOPSIS
Regenerate MiniXiangqi.Core/Generated/Mxq.g.cs from core/include/mxq.h.

.DESCRIPTION
docs/core-interface.md makes mxq.h the single input both platform bindings are
generated from. On Windows the generator is ClangSharp, pinned in
windows/.config/dotnet-tools.json and restored by this script, driven by the
option set in bindings/mxq.rsp.

The output is committed, so that building the frontend needs neither the
generator nor a C toolchain. Run this after any change to mxq.h and commit what
it writes; a Mxq.g.cs that differs from what this script produces is a
transcription of the header rather than the header.

.EXAMPLE
pwsh windows/bindings/generate.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$windowsRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repoRoot = (Resolve-Path (Join-Path $windowsRoot '..')).Path

$header = Join-Path $repoRoot 'core\include\mxq.h'
$output = Join-Path $windowsRoot 'MiniXiangqi.Core\Generated\Mxq.g.cs'
$options = Join-Path $PSScriptRoot 'mxq.rsp'

if (-not (Test-Path $header)) { throw "The public header was not found at $header." }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $output)

Push-Location $windowsRoot
try {
    & dotnet tool restore
    if ($LASTEXITCODE -ne 0) { throw 'dotnet tool restore failed.' }

    & dotnet tool run ClangSharpPInvokeGenerator -- `
        "@$options" `
        --file $header `
        --output $output
    if ($LASTEXITCODE -ne 0) { throw 'ClangSharpPInvokeGenerator failed.' }
}
finally {
    Pop-Location
}

Write-Host ''
Write-Host "Wrote $output"
Write-Host 'MXQ_BINDINGS_OK'
