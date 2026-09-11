Set-StrictMode -Version Latest

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

    return $subLabel
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

function Show-MainWizard {
    Initialize-WinForms

    $form = New-WizardForm "PS4 Linux Setup" 760 540
    Add-WizardHeader $form "PS4 Linux Setup" "Prepare an external USB drive for PS4 Linux."

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
    $internal.Text = "Internal"
    $internal.Location = New-Object System.Drawing.Point(355, 32)
    $internal.Size = New-Object System.Drawing.Size(310, 82)
    $internal.Enabled = $false
    $group.Controls.Add($internal)

    $manual = New-Object System.Windows.Forms.Button
    $manual.Text = "Manual External`n`nRequires WSL,  Coming soon"
    $manual.Location = New-Object System.Drawing.Point(20, 130)
    $manual.Size = New-Object System.Drawing.Size(310, 82)
    $manual.Enabled = $false
    $group.Controls.Add($manual)

    $wsl = Test-WSLInstalled
    $status = New-Object System.Windows.Forms.Label
    if ($wsl) {
        $status.Text = "WSL detected. Manual External will be enabled when implemented."
    } else {
        $status.Text = "WSL not detected. Manual External is disabled."
    }
    $status.Location = New-Object System.Drawing.Point(355, 145)
    $status.Size = New-Object System.Drawing.Size(310, 55)
    $status.ForeColor = [System.Drawing.Color]::DimGray
    $group.Controls.Add($status)

    $exit = New-Object System.Windows.Forms.Button
    $exit.Text = "Exit"
    $exit.Location = New-Object System.Drawing.Point(28, 430)
    $exit.Size = New-Object System.Drawing.Size(100, 34)
    $exit.Add_Click({ $form.Close() })
    $form.Controls.Add($exit)

    [void]$form.ShowDialog()
}

Export-ModuleMember -Function *
