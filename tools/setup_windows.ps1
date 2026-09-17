[CmdletBinding()]
param(
    [string]$Workspace = (Join-Path $HOME "zephyrproject"),
    [string]$SdkDirectory = (Join-Path $HOME "zephyr-sdk-1.0.1"),
    [string]$HssDirectory = (Join-Path $HOME "hss-payload-generator-v2026.04.1")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name. Run the host tool installation in BUILD_WINDOWS.md first."
    }
}

Require-Command "py"
Require-Command "git"
Require-Command "7z"

$venv = Join-Path $Workspace ".venv"
$python = Join-Path $venv "Scripts\python.exe"
$west = Join-Path $venv "Scripts\west.exe"

if (-not (Test-Path $python)) {
    New-Item -ItemType Directory -Force -Path $Workspace | Out-Null
    & py -3.12 -m venv $venv
}

& $python -m pip install --upgrade pip
& $python -m pip install west

if (-not (Test-Path (Join-Path $Workspace ".west\config"))) {
    & $west init -m https://github.com/zephyrproject-rtos/zephyr $Workspace
}

Push-Location $Workspace
try {
    & $west update
    & $python -m pip install -r (Join-Path $Workspace "zephyr\scripts\requirements.txt")
}
finally {
    Pop-Location
}

$sdkSetup = Join-Path $SdkDirectory "setup.cmd"
if (-not (Test-Path $sdkSetup)) {
    $sdkArchive = Join-Path $env:TEMP "zephyr-sdk-1.0.1_windows-x86_64_gnu.7z"
    $sdkUrl = "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v1.0.1/zephyr-sdk-1.0.1_windows-x86_64_gnu.7z"
    Invoke-WebRequest -Uri $sdkUrl -OutFile $sdkArchive
    & 7z x $sdkArchive "-o$HOME" -y
    & $sdkSetup
}

$hssExe = Get-ChildItem -Path $HssDirectory -Filter "hss-payload-generator*.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $hssExe) {
    $hssArchive = Join-Path $env:TEMP "hss-payload-generator-v2026.04.1.zip"
    $hssUrl = "https://github.com/polarfire-soc/hart-software-services/releases/download/v2026.04.1/hss-payload-generator-v2026.04.1.zip"
    Invoke-WebRequest -Uri $hssUrl -OutFile $hssArchive
    New-Item -ItemType Directory -Force -Path $HssDirectory | Out-Null
    Expand-Archive -Path $hssArchive -DestinationPath $HssDirectory -Force
    $hssExe = Get-ChildItem -Path $HssDirectory -Filter "hss-payload-generator*.exe" -Recurse | Select-Object -First 1
}

if (-not $hssExe) {
    throw "The Windows HSS payload generator was not found below $HssDirectory."
}

Write-Host "Setup complete." -ForegroundColor Green
Write-Host "Zephyr workspace: $Workspace"
Write-Host "Zephyr SDK:       $SdkDirectory"
Write-Host "HSS generator:    $($hssExe.FullName)"
