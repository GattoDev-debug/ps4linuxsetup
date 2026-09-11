Set-StrictMode -Version Latest

# ------------------------------------------------------------------
# Low-level FTP helpers
# ------------------------------------------------------------------

function New-FtpRequest([string]$Url, [string]$Method) {
    $req = [System.Net.FtpWebRequest]::Create($Url)
    $req.Method = $Method
    $req.Credentials = New-Object System.Net.NetworkCredential("anonymous", "")
    $req.UseBinary = $true
    $req.UsePassive = $true
    $req.KeepAlive = $false
    $req.Timeout = 30000
    return $req
}

function Test-FtpReachable([string]$Host, [int]$Port) {
    # Plain TCP connect test.
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($Host, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(3000)) {
            $client.Close()
            return $false
        }
        $client.EndConnect($iar)
        $client.Close()
        return $true
    }
    catch {
        return $false
    }
}

function Ensure-FtpDirectory([string]$Host, [int]$Port, [string]$Path) {
    # Walk the tree and create each segment that doesn't exist.
    $segments = $Path.Trim('/') -split '/'
    $current  = ""

    foreach ($seg in $segments) {
        if ([string]::IsNullOrWhiteSpace($seg)) { continue }
        $current = "$current/$seg"

        $url = "ftp://${Host}:$Port$current"
        try {
            $req  = New-FtpRequest $url ([System.Net.WebRequestMethods+Ftp]::MakeDirectory)
            $resp = $req.GetResponse()
            $resp.Close()
        }
        catch [System.Net.WebException] {
            # 550 usually means "already exists".
            # Anything else is a real failure.
            $msg = $_.Exception.Message
            if ($msg -notmatch "550") {
                throw "Could not create FTP directory '$current': $msg"
            }
        }
    }
}

function Send-FtpFile([string]$Host, [int]$Port, [string]$LocalFile, [string]$RemotePath) {
    if (-not (Test-Path -LiteralPath $LocalFile -PathType Leaf)) {
        throw "Local file not found: $LocalFile"
    }

    $url = "ftp://${Host}:$Port$RemotePath"
    $req = New-FtpRequest $url ([System.Net.WebRequestMethods+Ftp]::UploadFile)

    $stream = [System.IO.File]::OpenRead($LocalFile)
    try {
        $req.ContentLength = $stream.Length
        $rs = $req.GetRequestStream()
        try {
            $stream.CopyTo($rs)
        }
        finally {
            $rs.Close()
        }
    }
    finally {
        $stream.Close()
    }

    $resp = $req.GetResponse()
    $resp.Close()
}

# ------------------------------------------------------------------
# Connection page
# ------------------------------------------------------------------

function Show-InternalConnectionPage {
    $form = New-WizardForm "PS4 Linux Setup - Internal" 760 400
    Add-WizardHeader $form "Connect to your PS4" `
        "Make sure your PS4 is running a Linux payload with FTP enabled."

    $y = 130

    $lblHost = New-Object System.Windows.Forms.Label
    $lblHost.Text = "PS4 IP address:"
    $lblHost.Location = New-Object System.Drawing.Point(30, $y)
    $lblHost.Size = New-Object System.Drawing.Size(180, 26)
    $form.Controls.Add($lblHost)

    $hostBox = New-Object System.Windows.Forms.TextBox
    $hostBox.Location = New-Object System.Drawing.Point(220, $y)
    $hostBox.Size = New-Object System.Drawing.Size(200, 30)
    $hostBox.Text = "192.168.1."
    $form.Controls.Add($hostBox)

    $y += 45

    $lblPort = New-Object System.Windows.Forms.Label
    $lblPort.Text = "FTP port:"
    $lblPort.Location = New-Object System.Drawing.Point(30, $y)
    $lblPort.Size = New-Object System.Drawing.Size(180, 26)
    $form.Controls.Add($lblPort)

    $portBox = New-Object System.Windows.Forms.TextBox
    $portBox.Location = New-Object System.Drawing.Point(220, $y)
    $portBox.Size = New-Object System.Drawing.Size(100, 30)
    $portBox.Text = "2121"
    $form.Controls.Add($portBox)

    $statusY = $y + 60
    $status = New-Object System.Windows.Forms.Label
    $status.Location = New-Object System.Drawing.Point(30, $statusY)
    $status.Size = New-Object System.Drawing.Size(680, 60)
    $status.ForeColor = [System.Drawing.Color]::DimGray
    $form.Controls.Add($status)

    $test = New-Object System.Windows.Forms.Button
    $test.Text = "Test connection"
    $test.Location = New-Object System.Drawing.Point(30, 320)
    $test.Size = New-Object System.Drawing.Size(150, 34)
    $test.Add_Click({
        $status.Text = "Testing..."
        $status.ForeColor = [System.Drawing.Color]::DimGray

        $h = $hostBox.Text.Trim()
        $p = 0
        if (-not [int]::TryParse($portBox.Text.Trim(), [ref]$p)) {
            $status.Text = "Port must be a number."
            $status.ForeColor = [System.Drawing.Color]::Red
            return
        }

        if (Test-FtpReachable $h $p) {
            $status.Text = "Connected."
            $status.ForeColor = [System.Drawing.Color]::Green
        }
        else {
            $status.Text = "Could not connect. Check the IP, port, and that a payload with FTP is running."
            $status.ForeColor = [System.Drawing.Color]::Red
        }
    })
    $form.Controls.Add($test)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = "Cancel"
    $cancel.Location = New-Object System.Drawing.Point(500, 320)
    $cancel.Size = New-Object System.Drawing.Size(100, 34)
    $cancel.Add_Click({
        $form.Tag = "CANCELLED"
        $form.Close()
    })
    $form.Controls.Add($cancel)

    $next = New-Object System.Windows.Forms.Button
    $next.Text = "Continue"
    $next.Location = New-Object System.Drawing.Point(610, 320)
    $next.Size = New-Object System.Drawing.Size(100, 34)
    $next.Add_Click({
        $h = $hostBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($h)) {
            Show-ErrorBox "Enter the PS4 IP address."
            return
        }

        $p = 0
        if (-not [int]::TryParse($portBox.Text.Trim(), [ref]$p)) {
            Show-ErrorBox "Port must be a number."
            return
        }

        $form.Tag = [pscustomobject]@{
            Host = $h
            Port = $p
        }
        $form.Close()
    })
    $form.Controls.Add($next)

    [void]$form.ShowDialog()

    # Explicit handling of every exit path. If Tag is a string (i.e.
    # "CANCELLED") or null, return $null. Only return the object if it
    # actually has the properties we expect.
    $tag = $form.Tag
    if ($null -eq $tag)          { return $null }
    if ($tag -is [string])       { return $null }
    if (-not $tag.PSObject.Properties['Host']) { return $null }
    if (-not $tag.PSObject.Properties['Port']) { return $null }

    return $tag
}

# ------------------------------------------------------------------
# Main flow
# ------------------------------------------------------------------

function Start-InternalSetup {
    try {
        # --- pick files ---------------------------------------------
        $files = Show-FilesPage
        if ($null -eq $files) { return }

        if (-not (Show-FilesSummary $files)) { return }

        # --- ask for connection details -----------------------------
		$conn = Show-InternalConnectionPage
		if ($null -eq $conn) { return }


		$ftpHost = [string]$conn.Host
        $ftpHost = [string]$conn.Host
        $ftpPort = [int]$conn.Port

        if ([string]::IsNullOrWhiteSpace($ftpHost)) {
            Show-ErrorBox "No PS4 IP address was provided."
            return
        }

        # --- decide the remote distro filename up front ------------
        $distroName = Split-Path $files.Psxitarch -Leaf
        if ($distroName -notmatch '^psxitarch\.tar\.(gz|xz)$') {
            $distroName = if ($distroName -match '\.xz$') { "psxitarch.tar.xz" } else { "psxitarch.tar.gz" }
        }

        # --- build the bootargs temp file up front -----------------
        $bootargsTmp = Join-Path $env:TEMP ("ps4linux-bootargs-" + [guid]::NewGuid().ToString("N") + ".txt")
        Set-Content -LiteralPath $bootargsTmp -Value "amdgpu.dc=0" -NoNewline -Encoding ascii

        # --- cache the file paths as locals too --------------------
        $bzImage   = [string]$files.BzImage
        $initramfs = [string]$files.Initramfs
        $distro    = [string]$files.Psxitarch

        try {
            # The action block closes over $ftpHost, $ftpPort, $bzImage,
            # $initramfs, $bootargsTmp, $distro, $distroName. Because
            # Show-ProgressWindow (the inline version) runs the action
            # in the same session state, all of those are visible.
            $null = Show-ProgressWindow `
                "Uploading to PS4" `
                "Copying kernel, initramfs, and distro to your PS4's internal storage..." `
                {
                    Ensure-FtpDirectory $ftpHost $ftpPort "/data/linux/boot"
                    Send-FtpFile $ftpHost $ftpPort $bzImage   "/data/linux/boot/bzImage"
                    Send-FtpFile $ftpHost $ftpPort $initramfs "/data/linux/boot/initramfs.cpio.gz"
                    Send-FtpFile $ftpHost $ftpPort $bootargsTmp "/data/linux/boot/bootargs.txt"

                    Ensure-FtpDirectory $ftpHost $ftpPort "/user/system/boot"
                    Send-FtpFile $ftpHost $ftpPort $distro "/user/system/boot/$distroName"
                }
        }
        finally {
            Remove-Item -LiteralPath $bootargsTmp -Force -ErrorAction SilentlyContinue
        }

        # --- done ---------------------------------------------------
        Show-InfoBox @"
Internal setup complete.

Files uploaded to:
  /data/linux/boot/
    bzImage
    initramfs.cpio.gz
    bootargs.txt

  /user/system/boot/
    $distroName

You can now boot Linux on your PS4 using your usual payload.
"@
    }
    catch {
        Show-ErrorBox @"
Internal setup failed:

$($_.Exception.Message)

Origin:
$($_.ScriptStackTrace)

Stack:
$($_.ScriptStackTrace)
"@
    }
}

Export-ModuleMember -Function *