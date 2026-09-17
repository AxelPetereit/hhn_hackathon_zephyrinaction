[CmdletBinding()]
param(
    [string]$Workspace = (Join-Path $HOME "zephyrproject"),
    [string]$ApplicationSource = (Join-Path $HOME "pic64gx-zephyr"),
    [string]$HssDirectory = (Join-Path $HOME "hss-payload-generator-v2026.04.1"),
    [string]$BuildDirectory = (Join-Path $HOME "zephyrproject\build\flappy-microchip"),
    [string]$OutputPath = (Join-Path $PSScriptRoot "..\examples\flappy-microchip\payload.bin")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$elf = Join-Path $BuildDirectory "zephyr\zephyr.elf"
$sourceConfig = Join-Path $ApplicationSource "demos\pic64_smp_hello\hss-payload.yaml"
$payload = Join-Path $BuildDirectory "zephyr\payload.bin"
$hss = Get-ChildItem -Path $HssDirectory -Filter "hss-payload-generator*.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $hss) {
    throw "HSS payload generator not found. Run tools\setup_windows.ps1 first."
}
if (-not (Test-Path $elf)) {
    throw "ELF file not found. Run tools\build_flappy.ps1 first."
}
if (-not (Test-Path $sourceConfig)) {
    throw "HSS configuration not found: $sourceConfig"
}

$localConfig = Join-Path $BuildDirectory "hss-payload.local.yaml"
$elfYaml = $elf -replace "\\", "/"
$config = Get-Content -Raw -Path $sourceConfig
$config = [regex]::Replace($config, "(?m)^  .*/zephyr/build/pic64_smp_hello/zephyr/zephyr.elf:", ("  {0}:" -f $elfYaml))
Set-Content -Path $localConfig -Value $config -Encoding ascii

& $hss.FullName -c $localConfig $payload
if ($LASTEXITCODE -ne 0) {
    throw "HSS payload generation failed."
}

New-Item -ItemType Directory -Force -Path (Split-Path $OutputPath) | Out-Null
Copy-Item -Force $payload $OutputPath
Write-Host "Payload ready: $OutputPath" -ForegroundColor Green
