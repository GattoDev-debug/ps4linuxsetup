#Requires -Version 5.1
<#
    PS4 Linux Setup - one-line bootstrap
    Usage:  irm https://gatto.fae5.de/ps4linux/ps1 | iex
#>

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

# ------------------------------------------------------------------
$BaseUrl    = "https://gatto.fae5.de/ps4linux"
$InstallDir = Join-Path $env:LOCALAPPDATA "PS4LinuxSetup"
# ------------------------------------------------------------------

try {
    # --- fetch the manifest -----------------------------------------
    $manifestUrl = "$BaseUrl/info.txt"
    $manifestRaw = (Invoke-WebRequest -Uri $manifestUrl -UseBasicParsing).Content

    $Files = $manifestRaw -split "`r?`n" |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith("#") }

    if (-not $Files -or $Files.Count -eq 0) {
        throw "Manifest at $manifestUrl is empty or could not be parsed."
    }

    # --- clean + stage install dir ----------------------------------
    if (Test-Path -LiteralPath $InstallDir) {
        Remove-Item -LiteralPath $InstallDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

    # --- download each file -----------------------------------------
    foreach ($rel in $Files) {
        $url  = "$BaseUrl/$rel"
        $dest = Join-Path $InstallDir ($rel -replace '/', '\')
        $dir  = Split-Path -Parent $dest

        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    }

    $setup = Join-Path $InstallDir "Setup.ps1"
    if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) {
        throw "Setup.ps1 was not downloaded. Is it listed in info.txt?"
    }

    # --- hidden VBS launcher so no console shows behind the GUI -----
    $vbsPath = Join-Path $InstallDir "launch.vbs"
    $vbs = @"
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$setup""", 0, True
"@
    Set-Content -LiteralPath $vbsPath -Value $vbs -Encoding ASCII

    # --- hidden watcher: launch elevated, then delete folder --------
    $watcherLines = @(
        "Start-Process -FilePath 'wscript.exe' -ArgumentList '$vbsPath' -Verb RunAs -Wait"
        "Start-Sleep -Milliseconds 800"
        "Remove-Item -LiteralPath '$InstallDir' -Recurse -Force -ErrorAction SilentlyContinue"
    )
    $watcher = $watcherLines -join "; "

    Start-Process -FilePath "powershell.exe" `
        -ArgumentList @("-NoProfile", "-WindowStyle", "Hidden", "-Command", $watcher) `
        -WindowStyle Hidden | Out-Null

    Start-Sleep -Milliseconds 500
}
catch {
    Write-Host ""
    Write-Host "  Something went wrong:" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Read-Host "  Press Enter to exit"
}
finally {
    exit
}