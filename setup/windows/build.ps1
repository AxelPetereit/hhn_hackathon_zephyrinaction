# Copyright (c) 2026 Microchip Technology Inc
# SPDX-License-Identifier: MIT
#
# Build the Flappy Microchip example for the PIC64GX1000 Curiosity Kit.

[CmdletBinding()]
param(
    [string]$Workspace = (Join-Path $HOME "pic64gx-zephyr"),
    [string]$SdkDirectory,
    [string]$ApplicationSource,
    [string]$BuildDirectory,
    [switch]$Incremental
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
. (Join-Path $repoRoot "setup\common\versions.ps1")
$pins = Get-PinnedVersions

if (-not $SdkDirectory) { $SdkDirectory = Join-Path $HOME "zephyr-sdk-$($pins.SdkVersion)" }
if (-not $ApplicationSource) { $ApplicationSource = Join-Path $repoRoot "examples\flappy-microchip\source" }
if (-not $BuildDirectory) { $BuildDirectory = Join-Path $Workspace "build\flappy-microchip" }

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Die($msg) { Write-Host "error: $msg" -ForegroundColor Red; exit 1 }

$west = Join-Path $Workspace ".venv\Scripts\west.exe"
$application = Join-Path $ApplicationSource "demos\pic64_smp_hello"

if (-not (Test-Path -LiteralPath $west)) {
    Die "west not found at $west. Run .\setup\windows\setup.ps1 first."
}
if (-not (Test-Path -LiteralPath $application)) {
    Die "application not found: $application"
}
$zephyrBase = Join-Path $Workspace "zephyr"
if (-not (Test-Path -LiteralPath $zephyrBase)) {
    Die "Zephyr tree missing at $zephyrBase. Run .\setup\windows\setup.ps1 first."
}
if (-not (Test-Path -LiteralPath (Join-Path $zephyrBase "boards\microchip\pic64gx_curiosity_kit"))) {
    Die @"
board pic64gx_curiosity_kit is missing from the Zephyr tree.

It was introduced in Zephyr v4.4.0; setup\common\versions.env pins $($pins.ZephyrRevision).
Re-run .\setup\windows\setup.ps1 to correct the checkout.
"@
}

$env:ZEPHYR_BASE = $zephyrBase
$env:ZEPHYR_SDK_INSTALL_DIR = $SdkDirectory
$env:ZEPHYR_TOOLCHAIN_VARIANT = "zephyr"

$pristine = if ($Incremental) { "never" } else { "always" }

Write-Step "Building $($pins.BoardTarget)"
& $west build `
    -b $pins.BoardTarget `
    -d $BuildDirectory `
    -p $pristine `
    $application

if ($LASTEXITCODE -ne 0) { Die "Zephyr build failed." }

$elf = Join-Path $BuildDirectory "zephyr\zephyr.elf"
if (-not (Test-Path -LiteralPath $elf)) {
    Die "build finished but $elf is missing"
}

$size = (Get-Item -LiteralPath $elf).Length
Write-Host ""
Write-Host "Build complete" -ForegroundColor Green
Write-Host "  $elf ($size bytes)"
Write-Host ""
Write-Host "Next: .\setup\windows\payload.ps1"
