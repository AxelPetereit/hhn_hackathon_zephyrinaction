# Copyright (c) 2026 Microchip Technology Inc
# SPDX-License-Identifier: MIT
#
# Turn the built zephyr.elf into an HSS payload image.
#
# Uses the official hss-payload-generator.exe by default, and can also use the
# portable Python implementation in setup\common\hss_payload.py. Both produce
# semantically identical images; -Compare proves it on your own build.

[CmdletBinding()]
param(
    [string]$Workspace = (Join-Path $HOME "pic64gx-zephyr"),
    [string]$HssDirectory,
    [string]$ApplicationSource,
    [string]$BuildDirectory,
    [string]$OutputPath,
    [ValidateSet("auto", "upstream", "python")]
    [string]$Generator = "auto",
    [switch]$Compare
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$commonDir = Join-Path $repoRoot "setup\common"
. (Join-Path $commonDir "versions.ps1")
$pins = Get-PinnedVersions

if (-not $HssDirectory) { $HssDirectory = Join-Path $HOME "hss-payload-generator-$($pins.HssVersion)" }
if (-not $ApplicationSource) { $ApplicationSource = Join-Path $repoRoot "examples\flappy-microchip\source" }
if (-not $BuildDirectory) { $BuildDirectory = Join-Path $Workspace "build\flappy-microchip" }
if (-not $OutputPath) { $OutputPath = Join-Path $repoRoot "examples\flappy-microchip\payload.bin" }

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg) { Write-Host "  ok $msg" -ForegroundColor Green }
function Die($msg) { Write-Host "error: $msg" -ForegroundColor Red; exit 1 }

$elf = Join-Path $BuildDirectory "zephyr\zephyr.elf"
$sourceConfig = Join-Path $ApplicationSource "demos\pic64_smp_hello\hss-payload.yaml"

if (-not (Test-Path -LiteralPath $elf)) {
    Die "$elf not found. Run .\setup\windows\build.ps1 first."
}
if (-not (Test-Path -LiteralPath $sourceConfig)) {
    Die "HSS configuration not found: $sourceConfig"
}

$python = Join-Path $Workspace ".venv\Scripts\python.exe"
if (-not (Test-Path -LiteralPath $python)) {
    $fallback = Get-Command python -ErrorAction SilentlyContinue
    if ($fallback) { $python = $fallback.Source } else { $python = $null }
}

# The shipped config names the payload "zephyr.elf". Rewrite that key to the
# absolute path of the ELF we just built. Forward slashes keep the YAML scalar
# free of backslash escaping problems.
New-Item -ItemType Directory -Force -Path $BuildDirectory | Out-Null
$localConfig = Join-Path $BuildDirectory "hss-payload.local.yaml"
$elfForYaml = ((Resolve-Path -LiteralPath $elf).Path) -replace '\\', '/'
$config = Get-Content -Raw -LiteralPath $sourceConfig
$config = [regex]::Replace($config, "(?m)^(\s+).*zephyr\.elf:", ('${1}' + $elfForYaml + ':'))
Set-Content -LiteralPath $localConfig -Value $config -Encoding ascii

if (-not (Select-String -LiteralPath $localConfig -SimpleMatch "$elfForYaml`:" -Quiet)) {
    Die "failed to rewrite the ELF path in $localConfig"
}

$hssExe = Get-ChildItem -Path $HssDirectory -Filter "hss-payload-generator*.exe" `
    -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

# Runs a native command and returns its combined output.
#
# Necessary because with $ErrorActionPreference = 'Stop', Windows PowerShell 5.1
# turns *any* stderr output from a native command into a terminating error. Both
# payload generators legitimately print an informational NOTICE to stderr when
# the config supplies exec-addr for an ELF payload, which would otherwise abort
# a perfectly successful run. Only the exit code decides success here.
function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )

    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath $FilePath -ArgumentList $Arguments `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile

        Get-Content -LiteralPath $stdoutFile -ErrorAction SilentlyContinue |
            ForEach-Object { Write-Host "  $_" }

        $errText = @(Get-Content -LiteralPath $stderrFile -ErrorAction SilentlyContinue)
        if ($proc.ExitCode -ne 0) {
            if ($errText.Count -gt 0) {
                $errText | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
            }
            Die "$FailureMessage (exit code $($proc.ExitCode))"
        }
        # Informational notices on a successful run are shown but not fatal.
        $errText | Where-Object { $_.Trim() -ne "" } |
            ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    } finally {
        Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-Upstream([string]$out) {
    if (-not $hssExe) {
        Die "hss-payload-generator.exe not found below $HssDirectory. Run .\setup\windows\setup.ps1 first."
    }
    # The payload path must be the last argument; the tool documents that
    # requirement explicitly for Windows.
    Invoke-Native -FilePath $hssExe.FullName `
        -Arguments @("-c", $localConfig, $out) `
        -FailureMessage "HSS payload generation failed."
}

function Invoke-Python([string]$out) {
    if (-not $python) { Die "no Python interpreter available" }
    Invoke-Native -FilePath $python `
        -Arguments @((Join-Path $commonDir "hss_payload.py"), "-c", $localConfig, $out) `
        -FailureMessage "portable payload generation failed."
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath) | Out-Null

if ($Compare) {
    Write-Step "Generating with both implementations"
    $upstreamOut = Join-Path $BuildDirectory "payload.upstream.bin"
    $pythonOut = Join-Path $BuildDirectory "payload.python.bin"
    Invoke-Upstream $upstreamOut
    Invoke-Python $pythonOut
    Invoke-Native -FilePath $python `
        -Arguments @((Join-Path $commonDir "tests\compare_payloads.py"), $upstreamOut, $pythonOut) `
        -FailureMessage "the two generators disagree; do not flash this image"
    Copy-Item -Force -LiteralPath $upstreamOut -Destination $OutputPath
    Write-Ok "payload written to $OutputPath"
    exit 0
}

switch ($Generator) {
    "upstream" {
        Write-Step "Generating payload with the official generator"
        Invoke-Upstream $OutputPath
    }
    "python" {
        Write-Step "Generating payload with the portable Python generator"
        Invoke-Python $OutputPath
    }
    "auto" {
        if ($hssExe) {
            Write-Step "Generating payload with the official generator"
            Invoke-Upstream $OutputPath
        } else {
            Write-Step "Official generator unavailable, using the portable Python generator"
            Invoke-Python $OutputPath
        }
    }
}

if (-not (Test-Path -LiteralPath $OutputPath)) { Die "payload was not produced" }

# Sanity check the HSS magic so a broken image never reaches the SD card.
#
# Compared as raw bytes on purpose: in Windows PowerShell 5.1 the literal
# 0xB007C0DE is a negative Int32, so an integer comparison against a UInt32
# would never match.
$head = [System.IO.File]::ReadAllBytes($OutputPath)[0..3]
$magicHex = ($head[3], $head[2], $head[1], $head[0] |
    ForEach-Object { $_.ToString('x2') }) -join ''
if ($magicHex -ne 'b007c0de') {
    Die "payload magic is 0x$magicHex, expected 0xb007c0de"
}

$size = (Get-Item -LiteralPath $OutputPath).Length
Write-Host ""
Write-Host "Payload ready" -ForegroundColor Green
Write-Host "  $OutputPath ($size bytes, magic 0x$magicHex)"
Write-Host ""
Write-Host "Next: .\setup\windows\flash.ps1 -List"
