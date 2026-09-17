[CmdletBinding()]
param(
    [string]$Workspace = (Join-Path $HOME "zephyrproject"),
    [string]$ApplicationSource = (Join-Path $HOME "pic64gx-zephyr"),
    [string]$SdkDirectory = (Join-Path $HOME "zephyr-sdk-1.0.1"),
    [string]$BuildDirectory = (Join-Path $HOME "zephyrproject\build\flappy-microchip")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$west = Join-Path $Workspace ".venv\Scripts\west.exe"
$application = Join-Path $ApplicationSource "demos\pic64_smp_hello"

if (-not (Test-Path $west)) {
    throw "west was not found. Run tools\setup_windows.ps1 first."
}

if (-not (Test-Path $application)) {
    throw "PIC64GX application not found: $application"
}

$env:ZEPHYR_BASE = Join-Path $Workspace "zephyr"
$env:ZEPHYR_SDK_INSTALL_DIR = $SdkDirectory

& $west build `
    -b pic64gx_curiosity_kit/pic64gx1000/u54/smp `
    -d $BuildDirectory `
    -p always `
    $application

if ($LASTEXITCODE -ne 0) {
    throw "Zephyr build failed."
}

Write-Host "Build complete: $(Join-Path $BuildDirectory 'zephyr\zephyr.elf')" -ForegroundColor Green
