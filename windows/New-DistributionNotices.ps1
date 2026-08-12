<#
.SYNOPSIS
Write LICENSE and NOTICE.md into a distribution, from pinned-inputs.json.

.DESCRIPTION
Both distributions carry the same two documents and they say the same thing, so
they are written in one place. windows/package-zip.ps1 calls this on the staged
zip directory; windows/package-msix.ps1 calls it before the packaging build,
into a directory MiniXiangqi.App.csproj then includes as package content —
because a package's payload is a build output and nothing may be added to it
afterwards.

THIS IS NOT OPTIONAL AND IT IS NOT A COURTESY

The application is GPL-3.0 because Fairy-Stockfish is, and mxqcore.dll carries
that engine. docs/architecture.md's rule is that a public repository's CI
artifacts are a distribution channel and are governed as one, so every artifact
either of these builds uploads is a conveyance of GPL-licensed software and
must carry the licence with it. A distribution without LICENSE beside it is the
one defect here that is not a build problem.

NOTICE.md is generated rather than written by hand, because docs/architecture.md's
input rule cuts both ways: a hash or a revision restated anywhere is a second
place for it to be wrong, and a distribution that tells somebody the wrong
revision is worse than one that tells them nothing. Every value in it comes from
pinned-inputs.json.

There is no NETWORK.md any more. It existed to tell a reader about a file that
was not in the distribution; both files are in it, so the honest length of that
document is zero. What a reader may still want — which networks, and how to
check they survived the download — belongs in NOTICE.md and the self-check.

.PARAMETER Destination
The directory to write LICENSE and NOTICE.md into. It must exist.

.PARAMETER Shape
Which distribution this is: zip or store-package. One section of NOTICE.md
differs between them and no other does, because one fact differs — the zip
carries the Windows App Runtime and the Store package takes it as a framework
dependency the Store installs. Telling a reader about files that are not there
would be worse than saying nothing.

The machine-learning components are in BOTH sections, because they are in both
distributions. That is measured rather than assumed: the first packaged CI run
extracted onnxruntime.dll, Microsoft.ML.OnnxRuntime.dll and DirectML.dll out of
the .msix itself. Framework-dependence removed the Windows App Runtime — no
Microsoft.ui.xaml.dll and no Microsoft.WindowsAppRuntime.dll are in the package,
only the two Bootstrap DLLs — and it did not remove these. A licence document
that under-reports what a GPL artifact carries is the failure mode this note
exists against, so it says what the package holds and not what the deployment
mode was expected to shed.

.EXAMPLE
pwsh windows/New-DistributionNotices.ps1 -Destination windows/dist/notices -Shape store-package
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Destination,
    [ValidateSet('zip', 'store-package')]
    [string] $Shape = 'zip'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Destination = (Resolve-Path $Destination).Path

$manifest = Get-Content (Join-Path $repoRoot 'pinned-inputs.json') -Raw | ConvertFrom-Json
$projectNetwork = $manifest.network.($manifest.variant.id)
$xiangqiNetwork = $manifest.network.xiangqi
$fork = $manifest.fork
$sqlite = $manifest.sqlite

# The one section that differs, chosen before the note is written rather than
# inside it. A here-string has to close on a line of its own, so this is an
# if/else over two assignments rather than one expression.
if ($Shape -eq 'store-package') {
    $microsoftComponents = @"
This build takes the Windows App Runtime as a framework dependency, which the
Microsoft Store installs, and carries the rest beside the app:

- the **.NET runtime**, MIT licensed. It travels with the application because a
  package cannot declare a dependency on it;
- the **Windows App SDK** and **WinUI 3**, redistributed under the Microsoft
  Software Licence terms that accompany them. The runtime itself is the
  framework package the Store installs rather than a copy in here; what a
  packaged app still carries beside it includes the machine-learning components
  the SDK depends on — ``onnxruntime.dll``, ``Microsoft.ML.OnnxRuntime.dll``,
  ``DirectML.dll`` and their companions — which this application never loads;
  they are covered by those same accompanying terms and are listed here because
  they are large, present, and would otherwise go unexplained;
- **Win2D** (``Microsoft.Graphics.Win2D``), MIT licensed;
- the **Microsoft Visual C++ runtime** (``vcruntime140*.dll``,
  ``msvcp140*.dll``), redistributed under the Visual Studio licence terms that
  permit app-local deployment.
"@
} else {
    $microsoftComponents = @"
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
"@
}

Copy-Item (Join-Path $repoRoot 'LICENSE') (Join-Path $Destination 'LICENSE') -Force

Set-Content -Path (Join-Path $Destination 'NOTICE.md') -Encoding UTF8 -Value @"
# Star River — licences and attribution

Star River is licensed under the **GNU General Public License version 3**. The
full text is in ``LICENSE`` beside this file. The project's source is at
<https://github.com/chentianren0/MiniXiangqi>.

What else is in this build, and under what terms. Both networks below are
named because a reader looking for where the AI's evaluation came from will
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
| File name | ``$($projectNetwork.filename)`` |
| Size | $('{0:N0}' -f $projectNetwork.byte_length) bytes |
| SHA-256 | ``$($projectNetwork.sha256)`` |
| Pipeline | <$($projectNetwork.provenance.pipeline_repository)> |
| Pipeline revision | ``$($projectNetwork.provenance.pipeline_revision)`` |

The pipeline above is public and is the provenance: it generates its own training
data with the engine revision named in this file and the variant configuration
beside the network, and generation 0 was trained from the engine's own classical
evaluation, with no other network as a teacher or a seed at any stage.

The packaging build verified this file against the size and hash above before
putting it here. To confirm it survived the download:

``````powershell
Get-FileHash .\assets\$($projectNetwork.filename) -Algorithm SHA256
``````

## The Xiangqi neural network — $($xiangqiNetwork.license)

Standard Xiangqi uses the network published for that variant by the
Fairy-Stockfish project and trained by $($xiangqiNetwork.provenance.trained_by).
It is redistributed under **$($xiangqiNetwork.license)** rather than claimed as
this project's own work.

| | |
|---|---|
| File name | ``$($xiangqiNetwork.filename)`` |
| Size | $('{0:N0}' -f $xiangqiNetwork.byte_length) bytes |
| SHA-256 | ``$($xiangqiNetwork.sha256)`` |
| Source | <$($xiangqiNetwork.provenance.source_repository)> |
| Source file | <$($xiangqiNetwork.provenance.source_url)> |

The packaging build verifies these bytes too. To confirm them after download:

``````powershell
Get-FileHash .\assets\$($xiangqiNetwork.filename) -Algorithm SHA256
``````

## SQLite — public domain

The game library is stored in SQLite $($sqlite.version), whose authors have
dedicated it to the public domain. There is no licence text to carry;
<https://sqlite.org/copyright.html> is the statement.

## Microsoft components — redistributable binaries

$microsoftComponents

## Sounds

The board's four voices are this project's own, generated by a script in the
source repository. There is no third-party audio here and nothing to attribute.
"@

Write-Host ("  LICENSE    {0:N0} bytes" -f (Get-Item (Join-Path $Destination 'LICENSE')).Length)
Write-Host ("  NOTICE.md  {0:N0} bytes" -f (Get-Item (Join-Path $Destination 'NOTICE.md')).Length)
