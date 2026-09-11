Set-StrictMode -Version Latest

$Script:PsxitarchUrl = "https://mega.nz/file/kS0CwBLJ#I2GtfEZ0HigRyoSoHnBWGH85NqTnNCOUHIBvxlQmUZM"
$Script:InitramfsUrl = "https://github.com/DionKill/ps4-linux-tutorial/blob/main/PS4%20Linux/initramfs.zip"
$Script:BzImageUrl = "https://gitlab.com/rmuxnet/linux/-/releases"

function Test-WSLInstalled {
    try {
        $null = Get-Command wsl.exe -ErrorAction Stop
        $result = & wsl.exe --status 2>$null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Open-DownloadSources {
    Start-Process $Script:PsxitarchUrl
    Start-Process $Script:InitramfsUrl
    Start-Process $Script:BzImageUrl
}

function Find-LinuxFiles([string]$Folder) {
    if (-not (Test-Path -LiteralPath $Folder -PathType Container)) {
        throw "Folder does not exist: $Folder"
    }

    $psx = Get-ChildItem -LiteralPath $Folder -File |
        Where-Object { $_.Name -match '^psxitarch\.tar\.(xz|gz)$' } |
        Select-Object -First 1

    $init = Get-ChildItem -LiteralPath $Folder -File |
        Where-Object { $_.Name -ieq 'initramfs.cpio.gz' } |
        Select-Object -First 1

    $kernel = Get-ChildItem -LiteralPath $Folder -File |
        Where-Object { $_.Name -ieq 'bzImage' } |
        Select-Object -First 1

    [pscustomobject]@{
        Folder = $Folder
        Psxitarch = if ($psx) { $psx.FullName } else { $null }
        Initramfs = if ($init) { $init.FullName } else { $null }
        BzImage = if ($kernel) { $kernel.FullName } else { $null }
    }
}

function Get-MissingLinuxFiles($Files) {
    $missing = @()
    if (-not $Files.Psxitarch) { $missing += "psxitarch.tar.xz or psxitarch.tar.gz" }
    if (-not $Files.Initramfs) { $missing += "initramfs.cpio.gz" }
    if (-not $Files.BzImage) { $missing += "bzImage" }
    return $missing
}

function Show-DownloadInstructions {
    Show-InfoBox @"
Download sources:

psxitarch:
$Script:PsxitarchUrl

initramfs:
$Script:InitramfsUrl

After extracting initramfs.zip, locate:
External HDD\<southbridge>\initramfs.cpio.gz

bzImage:
$Script:BzImageUrl

The wizard will let you select the folder containing the final three files.
"@
    Open-DownloadSources
}

Export-ModuleMember -Function *
