# =====================================================================
# windows_build.ps1 — entry point for Route A (x64 Windows). Edit the variables below to your own, then right-click "Run as administrator",
#   Requirements: x64 Windows (administrator), built-in dism/bcdboot/diskpart, qemu-img (QEMU for Windows; when it is
#   missing the build offers to install it with winget -- set QEMU_IMG_INSTALL=1 to skip the question).
#   Usage:  powershell -ExecutionPolicy Bypass -File windows_build.ps1
# =====================================================================
$ErrorActionPreference = 'Stop'
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    # Relaunch elevated. UAC starts the child in System32 whatever the caller's directory was, so hand the
    # current directory over on the command line and cd back to it before the script runs.
    $cwd = (Get-Location).ProviderPath.Replace("'", "''")
    $me = $PSCommandPath.Replace("'", "''")
    Start-Process powershell "-NoExit -ExecutionPolicy Bypass -Command `"Set-Location -LiteralPath '$cwd'; & '$me'`"" -Verb RunAs
    exit
}



if (-not $env:SRC_ISO)       { $env:SRC_ISO = "%USERPROFILE%\Downloads\SW_DVD9_Win_Pro_11_25H2_Arm64_English_Pro_Ent_EDU_N_MLF_X24-13111.ISO" }
# $env:IMAGE_INDEX = "1"
if (-not $env:OUT_QCOW)      { $env:OUT_QCOW = "win11-droidvm-final.qcow2" }
if (-not $env:OUT_VMPKG)     { $env:OUT_VMPKG = "win11-droidvm-final.vmpkg" }
if (-not $env:DRIVERS_DIR)   { $env:DRIVERS_DIR = "https://github.com/HuJK/gunyah-guest-drivers-windows/releases/download/dev/gunyah-arm64-drivers.zip" }
if (-not $env:OPENSSH_SRC)   { $env:OPENSSH_SRC = "https://github.com/PowerShell/Win32-OpenSSH/releases/download/10.0.0.0p2-Preview/OpenSSH-ARM64-v10.0.0.0.msi" }

if (-not $env:DVM_USERNAME)      { $env:DVM_USERNAME = "USER" }
if (-not $env:DVM_PASSWORD)      { $env:DVM_PASSWORD = "DroidVM" }
if (-not $env:SSH_PUBKEY)        { $env:SSH_PUBKEY = "ssh-ed25519 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA root@ReplaceMe" }

if (-not $env:DISK_SIZE_MB)      { $env:DISK_SIZE_MB = "40960" }   # 40GB
if (-not $env:VMPKG_COMPRESSION) { $env:VMPKG_COMPRESSION = "auto" }
if (-not $env:EMS_SAC_SOURCE)    { $env:EMS_SAC_SOURCE = "online" }

if (-not $env:DRIVER_DIR)     { $env:DRIVER_DIR = "ZIP/drivers" }
if (-not $env:DRIVER_INSTALL) { $env:DRIVER_INSTALL = "NetKVM rdmapool pvmpower vioinput viostor vioscsi viosnd viofs" }
if (-not $env:DRIVER_CERT)    { $env:DRIVER_CERT = "ZIP/DroidVM_Test.cer" }

$env:PATH        = "C:\Program Files\qemu;" + $env:PATH
if (-not $env:QEMU_IMG_INSTALL) { $env:QEMU_IMG_INSTALL = "1" }




# OUT_VMPKG / OUT_QCOW = "1" (CI style) -> use the default file names
if ($env:OUT_VMPKG -match '^(1|true|yes|on)$') { $env:OUT_VMPKG = "win11-droidvm-final.vmpkg" }
if ($env:OUT_QCOW  -match '^(1|true|yes|on)$') { $env:OUT_QCOW  = "win11-droidvm-final.qcow2" }

Write-Host "==== DroidVM Windows builder (DISM offline driver injection) ====" -ForegroundColor Cyan
& "$PSScriptRoot\windows\build.ps1"
