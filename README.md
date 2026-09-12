# Information


This tool streamlines the process of installing Linux on your PS4.

Currently available on Windows for now.

Features include:

- [x] Internal installation
- [ ] Manual external installation
- [x] Scripted external installation

Features are always being added, So why not stick around?
# How to use

## From build
1. Open **Powershell** (preferably as **Administrator**, but optional)
2. Run `irm https://gatto.fae5.de/ps4linux/get.ps1 | iex`

## From source
1. Download source code.
2. Run `Setup.ps1` as **Administrator**.

# Sample screenshots

![Header: PS4 Linux Setup, SubHeader: Prepare PS4 Linux. Setup configuration, Automatic External, formats a usb drive and copies the required files. Internal, uses ftp to transfer required files. Manual External, Requires WSL to trnasfer required files. (disabled)](/screenshots/mainscreen.png)
![Select the folder containing the kernel, initramfs, and distro archive.](/screenshots/fileselect.png)
![Select your USB drive](/screenshots/driveselect.png)
