Set-StrictMode -Version Latest

function Get-PhysicalDrives {
    $disks = Get-Disk | Sort-Object Number
    return @($disks | ForEach-Object {
        [pscustomobject]@{
            Number = [int]$_.Number
            FriendlyName = if ($_.FriendlyName) { $_.FriendlyName } else { "Unknown disk" }
            SizeGB = [math]::Round($_.Size / 1GB, 1)
            BusType = [string]$_.BusType
            PartitionStyle = [string]$_.PartitionStyle
            OperationalStatus = [string]$_.OperationalStatus
            IsBoot = [bool]$_.IsBoot
            IsSystem = [bool]$_.IsSystem
            IsReadOnly = [bool]$_.IsReadOnly
        }
    })
}

function Format-SizeGB([double]$GB) {
    return ("{0:N1} GB" -f $GB)
}

function Show-DriveSelection {
	$form = New-WizardForm "PS4 Linux Setup - Select Drive" 820 610

	$null = Add-WizardHeader `
		$form `
		"Select your USB drive" `
		"Only continue after connecting the drive you want to erase."

	$list = New-Object System.Windows.Forms.ListView
	$list.Location = New-Object System.Drawing.Point(28, 120)
	$list.Size = New-Object System.Drawing.Size(740, 275)
	$list.View = "Details"
	$list.FullRowSelect = $true
	$list.GridLines = $true

	[void]$list.Columns.Add("Disk", 55)
	[void]$list.Columns.Add("Name", 260)
	[void]$list.Columns.Add("Size", 100)
	[void]$list.Columns.Add("Bus", 90)
	[void]$list.Columns.Add("Style", 90)
	[void]$list.Columns.Add("Status", 120)

	$form.Controls.Add($list)

	$refresh = New-Object System.Windows.Forms.Button
	$refresh.Text = "Refresh"
	$refresh.Location = New-Object System.Drawing.Point(28, 410)
	$refresh.Size = New-Object System.Drawing.Size(100, 34)
	$form.Controls.Add($refresh)

	$populate = {
		$list.Items.Clear()

		foreach ($d in Get-PhysicalDrives) {
			$item = New-Object System.Windows.Forms.ListViewItem([string]$d.Number)

			[void]$item.SubItems.Add($d.FriendlyName)
			[void]$item.SubItems.Add((Format-SizeGB $d.SizeGB))
			[void]$item.SubItems.Add($d.BusType)
			[void]$item.SubItems.Add($d.PartitionStyle)
			[void]$item.SubItems.Add($d.OperationalStatus)

			# Store the actual disk object on the ListView item.
			$item.Tag = $d

			if ($d.IsBoot -or $d.IsSystem) {
				$item.ForeColor = [System.Drawing.Color]::DarkRed
			}

			[void]$list.Items.Add($item)
		}
	}

	$refresh.Add_Click($populate)
	& $populate

	$cancel = New-Object System.Windows.Forms.Button
	$cancel.Text = "Cancel"
	$cancel.Location = New-Object System.Drawing.Point(540, 500)
	$cancel.Size = New-Object System.Drawing.Size(100, 34)

	$cancel.Add_Click({
		$form.Tag = "CANCELLED"
		$form.Close()
	})

	$form.Controls.Add($cancel)

	$ok = New-Object System.Windows.Forms.Button
	$ok.Text = "Select"
	$ok.Location = New-Object System.Drawing.Point(660, 500)
	$ok.Size = New-Object System.Drawing.Size(108, 34)

	$ok.Add_Click({
		if ($list.SelectedItems.Count -ne 1) {
			Show-ErrorBox "Select exactly one disk."
			return
		}

		$disk = $list.SelectedItems[0].Tag

		if ($disk.IsBoot -or $disk.IsSystem) {
			Show-ErrorBox "The selected disk is marked as a Windows boot/system disk and cannot be used by this wizard."
			return
		}

		if ($disk.IsReadOnly) {
			Show-ErrorBox "The selected disk is read-only."
			return
		}

		# Store the disk object directly on the form.
		$form.Tag = $disk
		$form.DialogResult = "OK"
		$form.Close()
	})

	$form.Controls.Add($ok)

	[void]$form.ShowDialog()

	if ($form.Tag -eq "CANCELLED") {
		return $null
	}

	if ($null -eq $form.Tag) {
		return $null
	}

	return $form.Tag
}

function Confirm-DiskDestruction($Disk) {
    $message = @"
WARNING: EVERYTHING ON THIS DISK WILL BE ERASED.
Type ERASE in the box to continue.

Disk $($Disk.Number)
Name: $($Disk.FriendlyName)
Size: $($Disk.SizeGB) GB
Bus: $($Disk.BusType)
Current partition style: $($Disk.PartitionStyle)

The wizard will:
  - remove the existing partition table
  - create an MBR partition table
  - create one partition
  - format it as FAT32

This cannot be undone.


"@

    $form = New-WizardForm "Confirm disk erase" 700 440
    Add-WizardHeader $form "Final disk confirmation" "This operation is destructive."

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $message
    $label.Location = New-Object System.Drawing.Point(30, 115)
    $label.Size = New-Object System.Drawing.Size(630, 190)
    $label.Font = New-Object System.Drawing.Font("Consolas", 10)
    $form.Controls.Add($label)

    $box = New-Object System.Windows.Forms.TextBox
    $box.Location = New-Object System.Drawing.Point(30, 315)
    $box.Size = New-Object System.Drawing.Size(630, 30)
    $form.Controls.Add($box)

    $result = $false
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = "Cancel"
    $cancel.Location = New-Object System.Drawing.Point(420, 360)
    $cancel.Size = New-Object System.Drawing.Size(100, 34)
    $cancel.Add_Click({ $form.Close() })
    $form.Controls.Add($cancel)

    $erase = New-Object System.Windows.Forms.Button
    $erase.Text = "Erase disk"
    $erase.Location = New-Object System.Drawing.Point(540, 360)
    $erase.Size = New-Object System.Drawing.Size(120, 34)
    $erase.Add_Click({
        if ($box.Text -cne "ERASE") {
            Show-ErrorBox "Type ERASE exactly to confirm."
            return
        }
        $result = $true
        $form.Close()
    })
    $form.Controls.Add($erase)

    [void]$form.ShowDialog()
    return $result
}

function Invoke-DiskpartScript([string[]]$Lines) {
    $path = Join-Path $env:TEMP ("ps4linux-diskpart-" + [guid]::NewGuid().ToString("N") + ".txt")
    try {
        [IO.File]::WriteAllLines($path, $Lines)
        $output = & diskpart.exe /s $path 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "DiskPart failed.`n`n$output"
        }
        return $output
    } finally {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

function Format-PS4LinuxDisk($Disk) {
	$n = $Disk.Number

	$diskpart = @(
		"select disk $n"
		"attributes disk clear readonly"
		"clean"
		"convert mbr"
		"create partition primary"
		"select partition 1"
		"format fs=fat32 quick label=PS4LINUX"
		"assign"
		"exit"
	)

	$script = $diskpart -join "`r`n"
	$temp = [System.IO.Path]::GetTempFileName()

	try {
		Set-Content -LiteralPath $temp -Value $script -Encoding ASCII

		$output = diskpart.exe /s $temp 2>&1

		if ($LASTEXITCODE -ne 0) {
			throw "diskpart failed:`r`n$($output -join "`r`n")"
		}
	}
	finally {
		Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
	}

	# Give Windows a moment to notice the new partition.
	Start-Sleep -Seconds 2

	# Refresh the disk/volume information.
	$diskAfter = Get-Disk -Number $n -ErrorAction Stop

	if ($diskAfter.IsOffline) {
		$null = Set-Disk -Number $n -IsOffline $false
	}

	$volume = Get-Partition -DiskNumber $n |
		Where-Object { $_.Type -ne "Reserved" } |
		Get-Volume |
		Where-Object { $_.FileSystem -eq "FAT32" } |
		Select-Object -First 1

	if ($null -eq $volume) {
		throw "The FAT32 partition was created, but Windows could not find its volume."
	}

	if ([string]::IsNullOrWhiteSpace([string]$volume.DriveLetter)) {
		throw "The FAT32 volume was created, but Windows did not assign a drive letter."
	}

	return $volume
}

function Copy-LinuxFilesToDrive($Volume, $Files) {
    $letter = "$($Volume.DriveLetter):"
    if (-not $Volume.DriveLetter) {
        throw "The new FAT32 volume has no drive letter."
    }

    Copy-Item -LiteralPath $Files.BzImage -Destination (Join-Path $letter "bzImage") -Force
    Copy-Item -LiteralPath $Files.Initramfs -Destination (Join-Path $letter "initramfs.cpio.gz") -Force
    Copy-Item -LiteralPath $Files.Psxitarch -Destination (Join-Path $letter (Split-Path $Files.Psxitarch -Leaf)) -Force

    Set-Content -LiteralPath (Join-Path $letter "bootargs.txt") -Value "amdgpu.dc=0" -NoNewline -Encoding ascii
}

function Test-PS4LinuxDrive($Volume, $Files) {
    $root = "$($Volume.DriveLetter):"
    $expectedDistro = Split-Path $Files.Psxitarch -Leaf
    $required = @(
        "bootargs.txt",
        "bzImage",
        "initramfs.cpio.gz",
        $expectedDistro
    )

    foreach ($name in $required) {
        $p = Join-Path $root $name
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
            return $false
        }
    }

    $bootargs = Get-Content -LiteralPath (Join-Path $root "bootargs.txt") -Raw
    return ($bootargs.Trim() -eq "amdgpu.dc=0")
}

function Eject-PS4LinuxDrive($Volume) {
    $letter = $Volume.DriveLetter
    if (-not $letter) { return }

    # Remove the drive letter first, then tell Windows to eject the physical disk.
    $diskNumber = (Get-Partition -DriveLetter $letter).DiskNumber
    try {
        $volume | Get-Partition | Remove-PartitionAccessPath -AccessPath "$letter`:\" -ErrorAction Stop
    } catch {
        # If the access path cannot be removed, still attempt the eject below.
    }

    $disk = Get-Disk -Number $diskNumber
    $disk | Set-Disk -IsOffline $true -ErrorAction SilentlyContinue
}

Export-ModuleMember -Function *
