#requires -Version 5.1
<#
    PS4 Linux Setup Wizard
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:Modules = Join-Path $Script:Root "modules"

Import-Module (Join-Path $Script:Modules "UI.psm1") -Force
Import-Module (Join-Path $Script:Modules "Downloads.psm1") -Force
Import-Module (Join-Path $Script:Modules "Drives.psm1") -Force
Import-Module (Join-Path $Script:Modules "AutomaticExternal.psm1") -Force
Import-Module (Join-Path $Script:Modules "ManualExternal.psm1") -Force
Import-Module (Join-Path $Script:Modules "Internal.psm1") -Force

if (-not (Test-IsAdministrator)) {
    Show-ErrorBox "PS4 Linux Setup must be run as Administrator.`n`nRight-click Setup.ps1 and choose 'Run with PowerShell', or start PowerShell as Administrator."
    exit 1
}

Show-MainWizard
