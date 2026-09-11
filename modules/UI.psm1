Set-StrictMode -Version Latest

# ------------------------------------------------------------------
# Manifest / update info
# ------------------------------------------------------------------

$Script:ManifestUrl   = "https://gatto.fae5.de/ps4linux/info.txt"
$Script:ManifestCache = $null

function Get-ManifestInfo {
    # Fetches info.txt from the endpoint and returns:
    #   Version   - line 4, expected "# Version X.Y.Z"
    #   Changelog - line 5, expected "# <free text>"
    #   Files     - everything that isn't blank or starting with #
    # Returns $null if the fetch fails or the file is malformed.
    try {
        $raw = (Invoke-WebRequest -Uri $Script:ManifestUrl -UseBasicParsing -TimeoutSec 8).Content
    }
    catch {
        return $null
    }

    $lines = $raw -split "`n" | ForEach-Object { $_.TrimEnd("`r") }

    if ($lines.Count -lt 5) {
        return $null
    }

    $version = $null
    if ($lines[3] -match '^#\s*Version\s+(\S+)\s*$') {
        $version = $Matches[1]
    }

    $changelog = $null
    if ($lines[4] -match '^#\s*(.+?)\s*$') {
        $changelog = $Matches[1]
    }

    $files = @()
    foreach ($line in $lines) {
        $t = $line.Trim()
        if (-not $t) { continue }
        if ($t.StartsWith("#")) { continue }
        $files += $t
    }

    return [pscustomobject]@{
        Version   = $version
        Changelog = $changelog
        Files     = $files
    }
}

function Get-CachedManifestInfo {
    if ($null -eq $Script:ManifestCache) {
        $Script:ManifestCache = Get-ManifestInfo
    }
    return $Script:ManifestCache
}

# ------------------------------------------------------------------
# Basic UI helpers
# ------------------------------------------------------------------

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Initialize-WinForms {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
}

function Show-ErrorBox([string]$Message) {
    Initialize-WinForms
    [void][System.Windows.Forms.MessageBox]::Show(
        $Message, "PS4 Linux Setup", "OK", "Error"
    )
}

function Show-InfoBox([string]$Message) {
    Initialize-WinForms
    [void][System.Windows.Forms.MessageBox]::Show(
        $Message, "PS4 Linux Setup", "OK", "Information"
    )
}

function Confirm-Box([string]$Message, [string]$Title = "Confirm") {
    Initialize-WinForms
    $r = [System.Windows.Forms.MessageBox]::Show(
        $Message, $Title, "YesNo", "Warning"
    )
    return ($r -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Select-Folder([string]$Description = "Select a folder") {
    Initialize-WinForms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    return $null
}

function New-WizardForm([string]$Title, [int]$Width = 760, [int]$Height = 520) {
    Initialize-WinForms
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.StartPosition = "CenterScreen"
    $form.Size = New-Object System.Drawing.Size($Width, $Height)
    $form.MinimumSize = New-Object System.Drawing.Size($Width, $Height)
    $form.MaximizeBox = $false
    $form.FormBorderStyle = "FixedDialog"
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    return $form
}
function Add-WizardHeader($Form, [string]$Title, [string]$Subtitle) {
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = $Title
    $titleLabel.Location = New-Object System.Drawing.Point(28, 22)
    $titleLabel.Size = New-Object System.Drawing.Size(680, 38)
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
    $Form.Controls.Add($titleLabel)

    $subLabel = New-Object System.Windows.Forms.Label
    $subLabel.Text = $Subtitle
    $subLabel.Location = New-Object System.Drawing.Point(30, 66)
    $subLabel.Size = New-Object System.Drawing.Size(680, 42)
    $subLabel.ForeColor = [System.Drawing.Color]::DimGray
    $Form.Controls.Add($subLabel)
}
function Show-CompletionPage($Volume) {
    $form = New-WizardForm "PS4 Linux Setup - Complete" 760 500
    Add-WizardHeader $form "Setup complete" "Your PS4 Linux Install has completed being set up."

    $text = @"
Next:

1. Open the PS4 web browser.
2. Run a Linux payload from:
   webkitty.arabpixel.net

The setup portion is finished.

Thank you for using my tool.
"@

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text
    $label.Location = New-Object System.Drawing.Point(30, 125)
    $label.Size = New-Object System.Drawing.Size(680, 250)
    $label.Font = New-Object System.Drawing.Font("Consolas", 10)
    $form.Controls.Add($label)

    $finish = New-Object System.Windows.Forms.Button
    $finish.Text = "Finish"
    $finish.Location = New-Object System.Drawing.Point(610, 420)
    $finish.Size = New-Object System.Drawing.Size(105, 34)
    $finish.Add_Click({ $form.Close() })
    $form.Controls.Add($finish)

    [void]$form.ShowDialog()
}

function Add-BackButton($Form, [scriptblock]$Action) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = "< Back"
    $b.Location = New-Object System.Drawing.Point(28, 430)
    $b.Size = New-Object System.Drawing.Size(100, 34)
    $b.Add_Click($Action)
    $Form.Controls.Add($b)
    return $b
}

function Add-NextButton($Form, [string]$Text, [scriptblock]$Action) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Location = New-Object System.Drawing.Point(612, 430)
    $b.Size = New-Object System.Drawing.Size(105, 34)
    $b.Add_Click($Action)
    $Form.Controls.Add($b)
    $Form.AcceptButton = $b
    return $b
}

# ------------------------------------------------------------------
# Files pages
# ------------------------------------------------------------------

function Show-FilesSummary($Files) {
    $text = @"
Files found:

psxitarch:
  $($Files.Psxitarch)

initramfs:
  $($Files.Initramfs)

kernel:
  $($Files.BzImage)

These files will be copied.
"@
    return Confirm-Box $text "Verify PS4 Linux files"
}

function Show-FilesPage {
    while ($true) {
        $form = New-WizardForm "PS4 Linux Setup - Files" 760 520

        $null = Add-WizardHeader `
            $form `
            "PS4 Linux files" `
            "Select the folder containing the kernel, initramfs, and distro archive."

        $path = New-Object System.Windows.Forms.TextBox
        $path.Location = New-Object System.Drawing.Point(30, 135)
        $path.Size = New-Object System.Drawing.Size(550, 32)
        $form.Controls.Add($path)

        $browse = New-Object System.Windows.Forms.Button
        $browse.Text = "Browse..."
        $browse.Location = New-Object System.Drawing.Point(590, 133)
        $browse.Size = New-Object System.Drawing.Size(110, 34)

        $browse.Add_Click({
            $chosen = Select-Folder "Select the folder containing PS4 Linux files"

            if ($chosen) {
                $path.Text = $chosen
            }
        })

        $form.Controls.Add($browse)

        $status = New-Object System.Windows.Forms.Label
        $status.Location = New-Object System.Drawing.Point(30, 190)
        $status.Size = New-Object System.Drawing.Size(670, 120)
        $status.Font = New-Object System.Drawing.Font("Consolas", 10)
        $form.Controls.Add($status)

        $download = New-Object System.Windows.Forms.Button
        $download.Text = "I don't have that"
        $download.Location = New-Object System.Drawing.Point(30, 350)
        $download.Size = New-Object System.Drawing.Size(160, 38)

        $download.Add_Click({
            Show-DownloadInstructions
        })

        $form.Controls.Add($download)

        $cancel = New-Object System.Windows.Forms.Button
        $cancel.Text = "Cancel"
        $cancel.Location = New-Object System.Drawing.Point(500, 430)
        $cancel.Size = New-Object System.Drawing.Size(100, 34)

        $cancel.Add_Click({
            $form.Tag = "CANCELLED"
            $form.Close()
        })

        $form.Controls.Add($cancel)

        $next = New-Object System.Windows.Forms.Button
        $next.Text = "Continue"
        $next.Location = New-Object System.Drawing.Point(610, 430)
        $next.Size = New-Object System.Drawing.Size(100, 34)

        $next.Add_Click({
            if ([string]::IsNullOrWhiteSpace($path.Text)) {
                Show-ErrorBox "Select a folder first."
                return
            }

            try {
                $candidate = Find-LinuxFiles $path.Text
                $missing = @(Get-MissingLinuxFiles $candidate)

                if ($missing.Count -gt 0) {
                    $status.Text = "Missing:`r`n - " + ($missing -join "`r`n - ")
                    return
                }

                $form.Tag = $candidate
                $form.Close()
            }
            catch {
                Show-ErrorBox $_.Exception.Message
            }
        })

        $form.Controls.Add($next)

        [void]$form.ShowDialog()

        if ($form.Tag -eq "CANCELLED") {
            return $null
        }

        if ($null -ne $form.Tag) {
            return $form.Tag
        }
    }
}

# ------------------------------------------------------------------
# Progress window
# ------------------------------------------------------------------

function Show-ProgressWindow {
    param(
        [string]$Title,
        [string]$Message,
        [scriptblock]$Action,
        [object[]]$ArgumentList = @()
    )

    $form = New-WizardForm $Title 760 300
    $null = Add-WizardHeader $form $Title $Message

    $status = New-Object System.Windows.Forms.Label
    $status.Location = New-Object System.Drawing.Point(30, 125)
    $status.Size = New-Object System.Drawing.Size(680, 55)
    $status.Text = $Message
    $form.Controls.Add($status)

    $bar = New-Object System.Windows.Forms.ProgressBar
    $bar.Location = New-Object System.Drawing.Point(30, 190)
    $bar.Size = New-Object System.Drawing.Size(680, 25)
    $bar.Style = "Marquee"
    $form.Controls.Add($bar)

    $state = [pscustomobject]@{
        Result = $null
        Error  = $null
    }

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 100
    $timer.Add_Tick({
        $timer.Stop()
        try {
            if ($ArgumentList.Count -gt 0) {
                $state.Result = & $Action @ArgumentList
            }
            else {
                $state.Result = & $Action
            }
        }
        catch {
            $state.Error = $_.Exception.Message
        }
        $form.Close()
    })
    $timer.Start()

    [void]$form.ShowDialog()

    if ($state.Error) { throw $state.Error }
    return $state.Result
}

# ------------------------------------------------------------------
# Main wizard
# ------------------------------------------------------------------

function Show-MainWizard {
    Initialize-WinForms

    # Fetch manifest info once per session. Used for the version label
    # at the bottom, and by the Latest Update button.
    $info = Get-CachedManifestInfo

    $form = New-WizardForm "PS4 Linux Setup" 760 540
    $null = Add-WizardHeader $form "PS4 Linux Setup" "Prepare PS4 Linux."

    $group = New-Object System.Windows.Forms.GroupBox
    $group.Text = "Setup configuration"
    $group.Location = New-Object System.Drawing.Point(28, 125)
    $group.Size = New-Object System.Drawing.Size(690, 245)
    $form.Controls.Add($group)

    $automatic = New-Object System.Windows.Forms.Button
    $automatic.Text = "Automatic External`n`nFormats a USB drive and copies the required files."
    $automatic.Location = New-Object System.Drawing.Point(20, 32)
    $automatic.Size = New-Object System.Drawing.Size(310, 82)
    $automatic.Add_Click({
        $form.Hide()
        try { Start-AutomaticExternal } finally { $form.Close() }
    })
    $group.Controls.Add($automatic)

    $internal = New-Object System.Windows.Forms.Button
    $internal.Text = "Internal`n`nUses FTP to transfer required files."
    $internal.Location = New-Object System.Drawing.Point(355, 32)
    $internal.Size = New-Object System.Drawing.Size(310, 82)
    $internal.Enabled = $true
    $internal.Add_Click({
        $form.Hide()
        try { Start-InternalSetup } finally { $form.Close() }
    })
    $group.Controls.Add($internal)

    $manual = New-Object System.Windows.Forms.Button
    $manual.Text = "Manual External`n`nRequires WSL to transfer required files."
    $manual.Location = New-Object System.Drawing.Point(20, 130)
    $manual.Size = New-Object System.Drawing.Size(310, 82)
    $manual.Enabled = $false
    $group.Controls.Add($manual)

    $wsl = Test-WSLInstalled
    $status = New-Object System.Windows.Forms.Label
    if ($wsl) {
        $status.Text = "WSL detected. Manual External will be enabled when implemented."
    }
    else {
        $status.Text = "WSL not detected. Manual External is disabled."
    }
    $status.Location = New-Object System.Drawing.Point(355, 145)
    $status.Size = New-Object System.Drawing.Size(310, 55)
    $status.ForeColor = [System.Drawing.Color]::DimGray
    $group.Controls.Add($status)

    # --- bottom row buttons -----------------------------------------

    $exit = New-Object System.Windows.Forms.Button
    $exit.Text = "Exit"
    $exit.Location = New-Object System.Drawing.Point(28, 430)
    $exit.Size = New-Object System.Drawing.Size(100, 34)
    $exit.Add_Click({ $form.Close() })
    $form.Controls.Add($exit)

    $source = New-Object System.Windows.Forms.Button
    $source.Text = "Source Code"
    $source.Location = New-Object System.Drawing.Point(136, 430)
    $source.Size = New-Object System.Drawing.Size(120, 34)
    $source.Add_Click({
        Start-Process "https://github.com/GattoDev-Debug/PS4LinuxSetup"
    })
    $form.Controls.Add($source)

    $update = New-Object System.Windows.Forms.Button
    $update.Text = "Latest Update"
    $update.Location = New-Object System.Drawing.Point(264, 430)
    $update.Size = New-Object System.Drawing.Size(130, 34)
    $update.Add_Click({
        $update.Enabled = $false
        $update.Text = "Checking..."

        try {
            # Bust the cache so the user always sees the freshest info.
            $Script:ManifestCache = $null
            $fresh = Get-CachedManifestInfo

            if ($null -eq $fresh) {
                Show-InfoBox "Could not fetch update information.`n`nCheck your internet connection and try again."
                return
            }

            if (-not $fresh.Version -and -not $fresh.Changelog) {
                Show-InfoBox "The server's manifest does not include version or changelog info."
                return
            }

            $v = if ($fresh.Version)   { $fresh.Version }   else { "(unknown)" }
            $c = if ($fresh.Changelog) { $fresh.Changelog } else { "(no changelog provided)" }

            Show-InfoBox @"
Latest update:

$c

Version: $v
"@
        }
        finally {
            $update.Text = "Latest Update"
            $update.Enabled = $true
        }
    })
    $form.Controls.Add($update)

    # --- version label at the bottom --------------------------------

    $versionText = if ($info -and $info.Version) {
        "Version $($info.Version)"
    } else {
        "Version unknown"
    }

    $versionLabel = New-Object System.Windows.Forms.Label
    $versionLabel.Text = $versionText
    $versionLabel.AutoSize = $false
    $versionLabel.TextAlign = "MiddleCenter"
    $versionLabel.Location = New-Object System.Drawing.Point(28, 478)
    $versionLabel.Size = New-Object System.Drawing.Size(690, 22)
    $versionLabel.ForeColor = [System.Drawing.Color]::DimGray
    $versionLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.Controls.Add($versionLabel)

    [void]$form.ShowDialog()
}

Export-ModuleMember -Function *