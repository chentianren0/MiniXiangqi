<#
.SYNOPSIS
Read what architecture a Windows binary actually is, from its own PE header.

.DESCRIPTION
Dot-sourced rather than run:

    . (Join-Path $PSScriptRoot 'Get-PeMachine.ps1')

Three scripts under windows/ ask this question and they must answer it the same
way, because they are three points on one chain and a disagreement between them
is a package that builds and does not run:

  build-core-dll.ps1   decides which Visual C++ runtime files belong beside the
                       core it just built
  package-zip.ps1      checks that every binary in the zip is the architecture
                       the zip is for
  package-msix.ps1     checks the same thing inside the unpacked Store package

WHY THE HEADER AND NOT THE FOLDER

Because the folder lies. The ARM64 Visual C++ redistributable genuinely contains
an x64 binary: vcruntime140_1.dll is the x64 exception unwinder, ARM64 has no
use for it, and Microsoft ships an x64 copy under
VC\Redist\MSVC\<version>\arm64\Microsoft.VC143.CRT anyway for the emulation and
ARM64EC cases. Trusting the folder name put that file in an ARM64 zip once. The
header is what caught it, and reading the header everywhere is what stops it
being caught rather than avoided.

The reader is deliberately small and total: it opens the file, walks MZ ->
e_lfanew -> PE\0\0, and returns the machine word. Anything that is not a PE
image — a .nnue, an .ini, a text file with a .dll extension — returns $null
rather than throwing, so a caller can sweep a whole directory and let this
function decide what is a binary.
#>

Set-StrictMode -Version Latest

function Get-PeMachine {
    <#
    .SYNOPSIS
    The IMAGE_FILE_HEADER Machine word of a PE image, or $null if the file is
    not one.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    $stream = [System.IO.File]::OpenRead($Path)
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

function Get-PeMachineName {
    <#
    .SYNOPSIS
    A machine word as something a person reads. Unknown values come back as the
    hexadecimal word rather than as "unknown", because the number is what the
    reader would go and look up.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowNull()] $Machine)

    if ($null -eq $Machine) { return 'not a PE image' }
    $names = @{ 0x014C = 'x86'; 0x8664 = 'x64'; 0xAA64 = 'ARM64'; 0x01C4 = 'ARM' }
    if ($names.ContainsKey([int] $Machine)) { return $names[[int] $Machine] }
    return "0x{0:X4}" -f $Machine
}

function Get-PeMachineForArchitecture {
    <#
    .SYNOPSIS
    The machine word this project's architecture names mean. One mapping, so
    that three scripts cannot hold two.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [ValidateSet('x64', 'arm64')] [string] $Architecture)

    if ($Architecture -eq 'arm64') { return 0xAA64 } else { return 0x8664 }
}
