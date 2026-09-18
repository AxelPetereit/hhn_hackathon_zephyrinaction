# Copyright (c) 2026 Microchip Technology Inc
# SPDX-License-Identifier: MIT
#
# Reads setup/common/versions.env so that the PowerShell scripts use exactly the
# same pinned versions as the Linux and macOS scripts. Keep the values in the
# .env file, not here.

Set-StrictMode -Version Latest

function Get-PinnedVersions {
    [CmdletBinding()]
    param(
        [string]$Path = (Join-Path $PSScriptRoot "versions.env")
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Version pin file not found: $Path"
    }

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if ($trimmed -eq "" -or $trimmed.StartsWith("#")) { continue }
        $idx = $trimmed.IndexOf("=")
        if ($idx -lt 1) { continue }
        $key = $trimmed.Substring(0, $idx).Trim()
        $val = $trimmed.Substring($idx + 1).Trim()
        $values[$key] = $val
    }

    foreach ($required in @(
        "ZEPHYR_REVISION",
        "ZEPHYR_SDK_VERSION",
        "ZEPHYR_SDK_TOOLCHAIN",
        "BOARD_TARGET",
        "PAYLOAD_SECTOR",
        "HSS_VERSION",
        "PYTHON_PREFERRED"
    )) {
        if (-not $values.ContainsKey($required)) {
            throw "Version pin file $Path is missing $required"
        }
    }

    return [pscustomobject]@{
        ZephyrRevision    = $values["ZEPHYR_REVISION"]
        SdkVersion        = $values["ZEPHYR_SDK_VERSION"]
        SdkToolchain      = $values["ZEPHYR_SDK_TOOLCHAIN"]
        BoardTarget       = $values["BOARD_TARGET"]
        PayloadSector     = [int]$values["PAYLOAD_SECTOR"]
        HssVersion        = $values["HSS_VERSION"]
        PythonPreferred   = $values["PYTHON_PREFERRED"]
    }
}
