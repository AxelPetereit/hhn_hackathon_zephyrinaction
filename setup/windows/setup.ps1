# Copyright (c) 2026 Microchip Technology Inc
# SPDX-License-Identifier: MIT
#
# PIC64GX Zephyr hackathon environment setup for Windows.
#
# Installs host tools via winget, creates a Python venv with west, fetches a
# pinned Zephyr tree, installs the Zephyr SDK riscv64 toolchain and the HSS
# payload generator.
#
# Safe to re-run: every step is skipped if it is already satisfied.
#
# Run from the repository root in a normal (non-elevated) PowerShell:
#   Set-ExecutionPolicy -Scope Process Bypass -Force
#   .\setup\windows\setup.ps1

[CmdletBinding()]
param(
    [string]$Workspace = (Join-Path $HOME "pic64gx-zephyr"),
    [string]$SdkDirectory,
    [string]$HssDirectory,
    [switch]$SkipHostTools,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # Invoke-WebRequest is far faster without it

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$commonDir = Join-Path $repoRoot "setup\common"
. (Join-Path $commonDir "versions.ps1")
$pins = Get-PinnedVersions

if (-not $SdkDirectory) { $SdkDirectory = Join-Path $HOME "zephyr-sdk-$($pins.SdkVersion)" }
if (-not $HssDirectory) { $HssDirectory = Join-Path $HOME "hss-payload-generator-$($pins.HssVersion)" }

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  ok $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "  !! $msg" -ForegroundColor Yellow }
function Die($msg) { Write-Host "error: $msg" -ForegroundColor Red; exit 1 }

function Test-Cmd($name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
}

# ---------------------------------------------------------------------------

Write-Step "Checking platform"
if (-not [Environment]::Is64BitOperatingSystem) {
    Die "a 64-bit Windows installation is required"
}
$arch = $env:PROCESSOR_ARCHITECTURE
if ($arch -ne "AMD64") {
    Write-Warn "Processor architecture is $arch. The Zephyr SDK ships only a windows-x86_64 bundle."
    Write-Warn "On Windows on ARM it will run through emulation, which is slow but generally works."
}
Write-Ok "Windows $([Environment]::OSVersion.Version) on $arch"

Write-Step "Pinned versions"
Write-Host "  Zephyr      $($pins.ZephyrRevision)"
Write-Host "  Zephyr SDK  $($pins.SdkVersion) ($($pins.SdkToolchain))"
Write-Host "  HSS tool    $($pins.HssVersion)"
Write-Host "  Board       $($pins.BoardTarget)"

# ---------------------------------------------------------------------------

if (-not $SkipHostTools) {
    Write-Step "Installing host tools with winget"
    if (-not (Test-Cmd "winget")) {
        Die @"
winget was not found. Install 'App Installer' from the Microsoft Store, then
re-run this script. If your machine image already has the Zephyr host tools,
you can instead run:
  .\setup\windows\setup.ps1 -SkipHostTools
"@
    }

    $packages = @(
        @{ Command = "git";   Id = "Git.Git" },
        @{ Command = "cmake"; Id = "Kitware.CMake" },
        @{ Command = "ninja"; Id = "Ninja-build.Ninja" },
        @{ Command = "gperf"; Id = "oss-winget.gperf" },
        @{ Command = "dtc";   Id = "oss-winget.dtc" },
        @{ Command = "7z";    Id = "7zip.7zip" },
        @{ Command = "py";    Id = "Python.Python.3.12" }
    )

    foreach ($pkg in $packages) {
        if (Test-Cmd $pkg.Command) {
            Write-Ok "$($pkg.Command) already installed"
            continue
        }
        if ($DryRun) {
            Write-Host "  would install $($pkg.Id)"
            continue
        }
        Write-Host "  installing $($pkg.Id)..."
        & winget install --id $pkg.Id --exact --source winget `
            --accept-source-agreements --accept-package-agreements --disable-interactivity
        # winget returns 0x8A150061 (-1978335135) when the package is already present
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335135) {
            Write-Warn "winget exited with $LASTEXITCODE for $($pkg.Id); will verify below"
        }
        Refresh-Path
    }
    Refresh-Path
} else {
    Write-Step "Skipping host tools as requested"
}

Write-Step "Verifying required commands"
Refresh-Path
$missing = @()
foreach ($cmd in @("git", "cmake", "ninja", "gperf", "dtc", "7z", "py")) {
    if (-not (Test-Cmd $cmd)) { $missing += $cmd }
}
if ($missing.Count -gt 0) {
    Die @"
missing required commands: $($missing -join ', ')

If winget has just installed them, close this PowerShell window and open a new
one so that PATH is refreshed, then re-run the script.
"@
}

$cmakeVersion = ((& cmake --version) | Select-Object -First 1) -replace '^cmake version\s+', ''
$cmakeParts = $cmakeVersion.Split('.')
if ([int]$cmakeParts[0] -lt 3 -or ([int]$cmakeParts[0] -eq 3 -and [int]$cmakeParts[1] -lt 20)) {
    Die "cmake $cmakeVersion is too old; Zephyr needs 3.20 or newer"
}
Write-Ok "cmake $cmakeVersion, ninja $((& ninja --version))"

# ---------------------------------------------------------------------------

Write-Step "Creating Python virtual environment"
$venv = Join-Path $Workspace ".venv"
$python = Join-Path $venv "Scripts\python.exe"
$west = Join-Path $venv "Scripts\west.exe"

if (-not (Test-Path -LiteralPath $python)) {
    if ($DryRun) {
        Write-Host "  would create venv at $venv"
    } else {
        New-Item -ItemType Directory -Force -Path $Workspace | Out-Null

        # Prefer the pinned Python; fall back to whatever py -3 offers.
        $created = $false
        foreach ($pyArgs in @(@("-$($pins.PythonPreferred)"), @("-3"))) {
            try {
                & py @pyArgs -m venv $venv 2>&1 | Out-Null
                if (Test-Path -LiteralPath $python) { $created = $true; break }
            } catch { }
        }
        if (-not $created) {
            Die "could not create a Python virtual environment. Check that 'py -0p' lists a usable Python 3."
        }
        Write-Ok "venv created at $venv"
    }
} else {
    Write-Ok "venv already present"
}

if (-not $DryRun) {
    $pyVersion = (& $python --version) -replace 'Python\s+', ''
    if ([version]($pyVersion -replace '([0-9]+\.[0-9]+\.[0-9]+).*', '$1') -lt [version]"3.10") {
        Die "the virtual environment uses Python $pyVersion; Zephyr needs 3.10 or newer"
    }
    & $python -m pip install --quiet --upgrade pip
    & $python -m pip install --quiet west
    if (-not (Test-Path -LiteralPath $west)) { Die "west was not installed into $venv" }
    Write-Ok "python $pyVersion, west $((& $west --version) -replace '.*\s','')"
}

# ---------------------------------------------------------------------------

Write-Step "Fetching Zephyr $($pins.ZephyrRevision)"
$westConfig = Join-Path $Workspace ".west\config"
if (-not (Test-Path -LiteralPath $westConfig)) {
    if ($DryRun) {
        Write-Host "  would run west init --mr $($pins.ZephyrRevision) $Workspace"
    } else {
        & $west init --mr $pins.ZephyrRevision $Workspace
        if ($LASTEXITCODE -ne 0) { Die "west init failed" }
        Write-Ok "workspace initialised at revision $($pins.ZephyrRevision)"
    }
} else {
    Write-Ok "workspace already initialised"
}

if (-not $DryRun) {
    Push-Location $Workspace
    try {
        & $west update --narrow --fetch smart
        if ($LASTEXITCODE -ne 0) { Die "west update failed" }
        & $west zephyr-export | Out-Null
        & $python -m pip install --quiet -r (Join-Path $Workspace "zephyr\scripts\requirements.txt")
    } finally {
        Pop-Location
    }
    Write-Ok "Zephyr modules and Python requirements ready"

    # The board this project targets was only added in Zephyr v4.4.0.
    $boardDir = Join-Path $Workspace "zephyr\boards\microchip\pic64gx_curiosity_kit"
    if (-not (Test-Path -LiteralPath $boardDir)) {
        Die @"
board pic64gx_curiosity_kit not found in $Workspace\zephyr.

This board was added in Zephyr v4.4.0. setup\common\versions.env pins
$($pins.ZephyrRevision), which does contain it, so this usually means the
workspace was created earlier against a different revision. Delete
$Workspace and re-run this script.
"@
    }
    Write-Ok "board pic64gx_curiosity_kit present"
}

# ---------------------------------------------------------------------------

Write-Step "Installing Zephyr SDK $($pins.SdkVersion)"
$sdkMarker = Join-Path $SdkDirectory "cmake\Zephyr-sdkConfig.cmake"
if (-not (Test-Path -LiteralPath $sdkMarker)) {
    $sdkArchive = "zephyr-sdk-$($pins.SdkVersion)_windows-x86_64_minimal.7z"
    $sdkUrl = "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v$($pins.SdkVersion)/$sdkArchive"
    $sdkTmp = Join-Path $env:TEMP $sdkArchive

    if ($DryRun) {
        Write-Host "  would download $sdkUrl"
        Write-Host "  would extract to $(Split-Path -Parent $SdkDirectory)"
    } else {
        if (-not (Test-Path -LiteralPath $sdkTmp)) {
            Write-Host "  downloading $sdkArchive (about 100 MB)..."
            Invoke-WebRequest -Uri $sdkUrl -OutFile $sdkTmp
        }
        $sdkParent = Split-Path -Parent $SdkDirectory
        New-Item -ItemType Directory -Force -Path $sdkParent | Out-Null
        & 7z x $sdkTmp "-o$sdkParent" -y | Out-Null
        if ($LASTEXITCODE -ne 0) { Die "extracting $sdkArchive failed" }
        if (-not (Test-Path -LiteralPath $SdkDirectory)) {
            Die "the SDK did not extract to $SdkDirectory"
        }
        Write-Ok "SDK extracted to $SdkDirectory"
    }
} else {
    Write-Ok "SDK already present at $SdkDirectory"
}

if (-not $DryRun) {
    # SDK 1.0.x installs toolchains under gnu\<triple>\bin; older layouts used
    # <triple>\bin. Search instead of assuming.
    function Find-Gcc {
        $candidates = @(
            (Join-Path $SdkDirectory "gnu\$($pins.SdkToolchain)\bin\$($pins.SdkToolchain)-gcc.exe"),
            (Join-Path $SdkDirectory "$($pins.SdkToolchain)\bin\$($pins.SdkToolchain)-gcc.exe")
        )
        foreach ($c in $candidates) {
            if (Test-Path -LiteralPath $c) { return $c }
        }
        $found = Get-ChildItem -Path $SdkDirectory -Filter "$($pins.SdkToolchain)-gcc.exe" `
            -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.FullName }
        return $null
    }

    $gcc = Find-Gcc
    if (-not $gcc) {
        Write-Step "Registering SDK and fetching the $($pins.SdkToolchain) toolchain"
        $setupCmd = Join-Path $SdkDirectory "setup.cmd"
        if (Test-Path -LiteralPath $setupCmd) {
            Push-Location $SdkDirectory
            try {
                & cmd /c "setup.cmd -t $($pins.SdkToolchain) -c" | Out-Null
            } finally {
                Pop-Location
            }
        }
        $gcc = Find-Gcc
    }
    if (-not $gcc) {
        Die "toolchain $($pins.SdkToolchain) not found below $SdkDirectory"
    }
    Write-Ok "toolchain $(((& $gcc --version) | Select-Object -First 1))"

    # Register the SDK with CMake so that west build finds it without env vars.
    $cmakePkg = Join-Path $HOME ".cmake\packages\Zephyr-sdk"
    if (-not (Test-Path -LiteralPath $cmakePkg)) {
        $setupCmd = Join-Path $SdkDirectory "setup.cmd"
        if (Test-Path -LiteralPath $setupCmd) {
            Push-Location $SdkDirectory
            try { & cmd /c "setup.cmd -c" | Out-Null } finally { Pop-Location }
        }
    }
}

# ---------------------------------------------------------------------------

Write-Step "Installing HSS payload generator $($pins.HssVersion)"
$hssExe = Get-ChildItem -Path $HssDirectory -Filter "hss-payload-generator*.exe" `
    -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $hssExe) {
    $hssArchive = "hss-payload-generator-$($pins.HssVersion).zip"
    $hssUrl = "https://github.com/polarfire-soc/hart-software-services/releases/download/$($pins.HssVersion)/$hssArchive"
    $hssTmp = Join-Path $env:TEMP $hssArchive

    if ($DryRun) {
        Write-Host "  would download $hssUrl"
    } else {
        if (-not (Test-Path -LiteralPath $hssTmp)) {
            Invoke-WebRequest -Uri $hssUrl -OutFile $hssTmp
        }
        New-Item -ItemType Directory -Force -Path $HssDirectory | Out-Null
        Expand-Archive -LiteralPath $hssTmp -DestinationPath $HssDirectory -Force
        $hssExe = Get-ChildItem -Path $HssDirectory -Filter "hss-payload-generator*.exe" `
            -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $hssExe) { Die "hss-payload-generator.exe not found below $HssDirectory" }
    }
}
if (-not $DryRun) {
    Write-Ok "HSS generator at $($hssExe.FullName)"
}

# ---------------------------------------------------------------------------

Write-Step "Verifying the payload generator"
if (-not $DryRun) {
    $testScript = Join-Path $commonDir "tests\run_tests.py"
    $log = Join-Path $env:TEMP "hss_selftest.log"
    & $python $testScript --reference $hssExe.FullName *> $log
    $summary = (Get-Content $log | Select-Object -Last 1)
    if ($LASTEXITCODE -eq 0) {
        Write-Ok $summary
    } else {
        Write-Warn "payload generator self-test reported failures, see $log"
    }
}

# ---------------------------------------------------------------------------

Write-Step "Writing environment helper"
if (-not $DryRun) {
    $envScript = Join-Path $Workspace "pic64gx-env.ps1"
    @"
# Generated by setup\windows\setup.ps1. Dot-source this for manual builds.
`$env:ZEPHYR_BASE = "$(Join-Path $Workspace 'zephyr')"
`$env:ZEPHYR_SDK_INSTALL_DIR = "$SdkDirectory"
`$env:ZEPHYR_TOOLCHAIN_VARIANT = "zephyr"
`$env:Path = "$(Join-Path $venv 'Scripts');`$env:Path"
"@ | Set-Content -LiteralPath $envScript -Encoding utf8
    Write-Ok "wrote $envScript"
}

Write-Host ""
Write-Host "Setup complete." -ForegroundColor Green
Write-Host ""
Write-Host "  Workspace     $Workspace"
Write-Host "  Zephyr        $(Join-Path $Workspace 'zephyr') ($($pins.ZephyrRevision))"
Write-Host "  SDK           $SdkDirectory"
Write-Host "  Board target  $($pins.BoardTarget)"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  .\setup\windows\build.ps1              build the example"
Write-Host "  .\setup\windows\payload.ps1            create payload.bin"
Write-Host "  .\setup\windows\flash.ps1 -List        find your SD card"
Write-Host "  .\setup\windows\flash.ps1 -DiskNumber N    (run as Administrator)"
Write-Host ""
