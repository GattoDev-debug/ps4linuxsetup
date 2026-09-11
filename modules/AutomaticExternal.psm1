Set-StrictMode -Version Latest

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