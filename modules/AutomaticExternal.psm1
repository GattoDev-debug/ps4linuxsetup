Set-StrictMode -Version Latest

function Show-ProgressWindow([string]$Title, [string]$Message, [scriptblock]$Action) {
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

    # Shared state object - property writes on this DO propagate
    # out of the timer's event-handler scope.
    $state = [pscustomobject]@{
        Result = $null
        Error  = $null
    }

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 100
    $timer.Add_Tick({
        $timer.Stop()
        try {
            $state.Result = & $Action
        }
        catch {
            $state.Error = $_.Exception.Message
        }
        $form.Close()
    })
    $timer.Start()

    [void]$form.ShowDialog()

    if ($state.Error) {
        throw $state.Error
    }

    return $state.Result
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

                # Store the actual result on the Form object.
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

function Show-FilesSummary($Files) {
    $text = @"
Files found:

psxitarch:
  $($Files.Psxitarch)

initramfs:
  $($Files.Initramfs)

kernel:
  $($Files.BzImage)

These files will be copied to the root of the USB drive.
"@
    return Confirm-Box $text "Verify PS4 Linux files"
}

function Show-CompletionPage($Volume) {
    $drive = "$($Volume.DriveLetter):"
    $form = New-WizardForm "PS4 Linux Setup - Complete" 760 500
    Add-WizardHeader $form "Setup complete" "Your external PS4 Linux drive is ready."

    $text = @"
The drive has been prepared successfully.

Drive:
  $drive

Files on the root:
  bootargs.txt
  bzImage
  initramfs.cpio.gz
  psxitarch.tar.xz / psxitarch.tar.gz

bootargs.txt contains:
  amdgpu.dc=0

Next:

1. Safely remove the drive.
2. Plug it into your PS4.
3. Open the PS4 web browser.
4. Run a Linux payload from:
   webkitty.arabpixel.net

The automatic setup portion is finished.

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

function Start-AutomaticExternal {
    try {
        $files = Show-FilesPage

        if ($null -eq $files) {
            return
        }

        if (-not (Show-FilesSummary $files)) {
            return
        }

        $disk = Show-DriveSelection

        if ($null -eq $disk) {
            return
        }

        if (-not (Confirm-DiskDestruction $disk)) {
            return
        }

        $volume = Show-ProgressWindow `
            "Preparing USB drive" `
            "Erasing the selected disk and creating an MBR/FAT32 partition..." `
            { Format-PS4LinuxDisk $disk }

        Show-ProgressWindow `
            "Copying PS4 Linux" `
            "Copying bzImage, initramfs, distro archive, and bootargs.txt..." `
            {
                Copy-LinuxFilesToDrive $volume $files
            } | Out-Null

        $verified = Test-PS4LinuxDrive $volume $files

        if (-not $verified) {
            throw "Verification failed."
        }

        Show-CompletionPage $volume
    }
    catch {
        Show-ErrorBox @"
Setup failed:

$($_.Exception.Message)

Location:
$($_.InvocationInfo.PositionMessage)

Stack:
$($_.ScriptStackTrace)
"@
    }
}

Export-ModuleMember -Function *