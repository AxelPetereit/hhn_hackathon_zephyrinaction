# Copyright (c) 2026 Microchip Technology Inc
# SPDX-License-Identifier: MIT
#
# Write the HSS payload to the SD card payload partition.
#
# The HSS bootloader expects the payload image at sector 139264 (LBA 0x22000).
# This writes at a raw offset; it does not create or use a filesystem.
#
# Must run as Administrator. Refuses boot and system disks. Read the target
# summary before typing YES.
#
#   .\setup\windows\flash.ps1 -List
#   .\setup\windows\flash.ps1 -DiskNumber 2

[CmdletBinding(DefaultParameterSetName = "Flash")]
param(
    [Parameter(ParameterSetName = "List", Mandatory = $true)]
    [switch]$List,

    [Parameter(ParameterSetName = "Flash", Mandatory = $true)]
    [ValidateRange(0, 255)]
    [int]$DiskNumber,

    [Parameter(ParameterSetName = "Flash")]
    [string]$PayloadPath,

    [Parameter(ParameterSetName = "Flash")]
    [ValidateRange(0, [int]::MaxValue)]
    [int]$SectorOffset = -1,

    [Parameter(ParameterSetName = "Flash")]
    [switch]$Yes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
. (Join-Path $repoRoot "setup\common\versions.ps1")
$pins = Get-PinnedVersions

if ($SectorOffset -lt 0) { $SectorOffset = $pins.PayloadSector }
if (-not $PayloadPath) { $PayloadPath = Join-Path $repoRoot "examples\flappy-microchip\payload.bin" }

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Die($msg) { Write-Host "error: $msg" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------

if ($List) {
    Write-Step "Disks (the SD card is usually USB or SD bus type, and not boot/system)"
    Get-Disk | Sort-Object Number | Format-Table -AutoSize `
        Number, FriendlyName, BusType,
        @{ Name = "Size(GB)"; Expression = { [math]::Round($_.Size / 1GB, 1) } },
        IsBoot, IsSystem, OperationalStatus
    Write-Host ""
    Write-Host "Pick the Number column value that matches your card's size and bus type." -ForegroundColor Yellow
    exit 0
}

# ---------------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $PayloadPath -PathType Leaf)) {
    Die @"
payload not found: $PayloadPath

Run .\setup\windows\payload.ps1, or point -PayloadPath at the pre-built image
in examples\flappy-microchip\payload.bin.
"@
}

# Refuse to write anything that is not an HSS payload image.
#
# Compare the raw little-endian bytes rather than an integer. In Windows
# PowerShell 5.1 the literal 0xB007C0DE is an Int32 with the value -1341669154,
# so comparing it against a UInt32 from BitConverter is always unequal and would
# reject every valid payload.
$payload = [System.IO.File]::ReadAllBytes($PayloadPath)
if ($payload.Length -lt 4) { Die "$PayloadPath is too small to be a payload" }
$magicHex = ($payload[3], $payload[2], $payload[1], $payload[0] |
    ForEach-Object { $_.ToString('x2') }) -join ''
if ($magicHex -ne 'b007c0de') {
    Die "$PayloadPath is not an HSS payload (magic 0x$magicHex, expected 0xb007c0de)"
}

$disk = $null
try { $disk = Get-Disk -Number $DiskNumber -ErrorAction Stop } catch { }
if (-not $disk) { Die "no disk with number $DiskNumber. Run .\setup\windows\flash.ps1 -List" }

# Target safety is checked before the privilege check on purpose: picking the
# wrong disk number is the dangerous mistake, and the user should be told that
# immediately rather than after they have re-opened an elevated shell.
if ($disk.IsBoot -or $disk.IsSystem) {
    Die @"
refusing to write to disk $DiskNumber ($($disk.FriendlyName)).

It is flagged IsBoot=$($disk.IsBoot) IsSystem=$($disk.IsSystem), which means it
is this computer's system disk, not your SD card.

Run .\setup\windows\flash.ps1 -List and pick the removable disk.
"@
}

# Also refuse if any volume on the disk holds the Windows directory.
$windowsDrive = ($env:SystemDrive).TrimEnd(':')
$partitions = @(Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue)
foreach ($p in $partitions) {
    if ($p.DriveLetter -and "$($p.DriveLetter)" -eq $windowsDrive) {
        Die "refusing to write: disk $DiskNumber contains the Windows drive $windowsDrive`:"
    }
}

$needed = [int64]$SectorOffset * 512 + $payload.Length
if ($disk.Size -lt $needed) {
    Die "card is too small: needs $needed bytes, has $($disk.Size)"
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Die @"
raw disk writes require Administrator rights.

Close this window, start PowerShell with 'Run as administrator', then:
  cd $repoRoot
  Set-ExecutionPolicy -Scope Process Bypass -Force
  .\setup\windows\flash.ps1 -DiskNumber $DiskNumber
"@
}

Write-Host ""
Write-Host "=== PIC64GX payload flash ===" -ForegroundColor Cyan
Write-Host ("  Disk          {0}  \\.\PhysicalDrive{0}" -f $DiskNumber)
Write-Host ("  Model         {0}" -f $disk.FriendlyName)
Write-Host ("  Bus type      {0}" -f $disk.BusType)
Write-Host ("  Size          {0} bytes ({1} GB)" -f $disk.Size, [math]::Round($disk.Size / 1GB, 1))
Write-Host ("  Partitions    {0}" -f $partitions.Count)
Write-Host ("  Payload       {0} ({1} bytes)" -f $PayloadPath, $payload.Length)
Write-Host ("  Start sector  {0} (byte offset {1})" -f $SectorOffset, ([int64]$SectorOffset * 512))
Write-Host ""

if ($disk.BusType -notin @("USB", "SD", "MMC")) {
    Write-Host "Warning: bus type is $($disk.BusType), not USB/SD/MMC. Double-check this is your card." -ForegroundColor Yellow
    Write-Host ""
}

if (-not $Yes) {
    $answer = Read-Host "This overwrites data on disk $DiskNumber. Type YES to continue"
    if ($answer -ne "YES") { Die "aborted" }
}

# ---------------------------------------------------------------------------

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;

public static class RawDisk {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr CreateFileW(
        string lpFileName, uint dwDesiredAccess, uint dwShareMode,
        IntPtr lpSecurityAttributes, uint dwCreationDisposition,
        uint dwFlagsAndAttributes, IntPtr hTemplateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool WriteFile(IntPtr hFile, byte[] lpBuffer, uint nNumberOfBytesToWrite,
        out uint lpNumberOfBytesWritten, IntPtr lpOverlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool ReadFile(IntPtr hFile, byte[] lpBuffer, uint nNumberOfBytesToRead,
        out uint lpNumberOfBytesRead, IntPtr lpOverlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetFilePointerEx(IntPtr hFile, long liDistanceToMove,
        out long lpNewFilePointer, uint dwMoveMethod);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool FlushFileBuffers(IntPtr hFile);

    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    static extern bool DeviceIoControl(IntPtr hDevice, uint dwIoControlCode,
        IntPtr lpInBuffer, uint nInBufferSize, IntPtr lpOutBuffer, uint nOutBufferSize,
        out uint lpBytesReturned, IntPtr lpOverlapped);

    const uint GENERIC_READ  = 0x80000000;
    const uint GENERIC_WRITE = 0x40000000;
    const uint FILE_SHARE_READ  = 0x00000001;
    const uint FILE_SHARE_WRITE = 0x00000002;
    const uint OPEN_EXISTING = 3;
    const uint NO_BUFFERING  = 0x20000000;
    const uint WRITE_THROUGH = 0x80000000;
    const uint FSCTL_LOCK_VOLUME     = 0x00090018;
    const uint FSCTL_DISMOUNT_VOLUME = 0x00090020;
    static readonly IntPtr INVALID = new IntPtr(-1);

    // Locks and dismounts a volume so the filesystem driver stops writing behind
    // our back. The handle must stay open to hold the lock.
    public static IntPtr LockVolume(string volumePath) {
        IntPtr h = CreateFileW(volumePath, GENERIC_READ | GENERIC_WRITE,
            FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
        if (h == INVALID) {
            Console.WriteLine("  " + volumePath + ": open failed (" + Marshal.GetLastWin32Error() + "), skipping");
            return IntPtr.Zero;
        }
        uint br;
        bool locked = DeviceIoControl(h, FSCTL_LOCK_VOLUME, IntPtr.Zero, 0, IntPtr.Zero, 0, out br, IntPtr.Zero);
        bool dismounted = DeviceIoControl(h, FSCTL_DISMOUNT_VOLUME, IntPtr.Zero, 0, IntPtr.Zero, 0, out br, IntPtr.Zero);
        Console.WriteLine("  " + volumePath + ": lock=" + (locked ? "ok" : "failed") +
                          " dismount=" + (dismounted ? "ok" : "failed"));
        return h;
    }

    static IntPtr OpenDisk(string device) {
        IntPtr h = CreateFileW(device, GENERIC_READ | GENERIC_WRITE,
            FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING,
            NO_BUFFERING | WRITE_THROUGH, IntPtr.Zero);
        if (h == INVALID)
            throw new IOException("CreateFile(" + device + ") failed: " + Marshal.GetLastWin32Error());
        return h;
    }

    public static int WriteAtSector(string device, byte[] data, long sectorOffset, int sectorSize) {
        // Unbuffered writes must be a whole number of sectors, so pad the tail.
        int padded = ((data.Length + sectorSize - 1) / sectorSize) * sectorSize;
        byte[] buf = new byte[padded];
        Array.Copy(data, buf, data.Length);

        IntPtr h = OpenDisk(device);
        try {
            long pos;
            if (!SetFilePointerEx(h, sectorOffset * sectorSize, out pos, 0))
                throw new IOException("seek failed: " + Marshal.GetLastWin32Error());
            uint written;
            if (!WriteFile(h, buf, (uint)buf.Length, out written, IntPtr.Zero))
                throw new IOException("write failed: " + Marshal.GetLastWin32Error());
            FlushFileBuffers(h);
            if (written != buf.Length)
                throw new IOException("short write: " + written + " of " + buf.Length);
            return (int)written;
        } finally {
            CloseHandle(h);
        }
    }

    public static byte[] ReadAtSector(string device, long sectorOffset, int byteCount, int sectorSize) {
        int padded = ((byteCount + sectorSize - 1) / sectorSize) * sectorSize;
        byte[] buf = new byte[padded];

        IntPtr h = OpenDisk(device);
        try {
            long pos;
            if (!SetFilePointerEx(h, sectorOffset * sectorSize, out pos, 0))
                throw new IOException("seek failed: " + Marshal.GetLastWin32Error());
            uint read;
            if (!ReadFile(h, buf, (uint)buf.Length, out read, IntPtr.Zero))
                throw new IOException("read failed: " + Marshal.GetLastWin32Error());
            if (read < byteCount)
                throw new IOException("short read: " + read + " of " + byteCount);
            byte[] result = new byte[byteCount];
            Array.Copy(buf, result, byteCount);
            return result;
        } finally {
            CloseHandle(h);
        }
    }
}
'@

$device = "\\.\PhysicalDrive$DiskNumber"
$sectorSize = 512
try {
    $logical = (Get-Disk -Number $DiskNumber).LogicalSectorSize
    if ($logical -gt 0) { $sectorSize = [int]$logical }
} catch { }

Write-Step "Locking volumes on disk $DiskNumber"
$handles = New-Object System.Collections.Generic.List[IntPtr]
foreach ($p in $partitions) {
    if ($p.DriveLetter) {
        $h = [RawDisk]::LockVolume("\\.\$($p.DriveLetter):")
        if ($h -ne [IntPtr]::Zero) { $handles.Add($h) }
    }
    $uid = $null
    try { $uid = ($p | Get-Volume -ErrorAction SilentlyContinue).UniqueId } catch { }
    if ($uid) {
        $h = [RawDisk]::LockVolume($uid.TrimEnd('\'))
        if ($h -ne [IntPtr]::Zero) { $handles.Add($h) }
    }
}
if ($handles.Count -eq 0) { Write-Host "  no mounted volumes to lock" }

try {
    Write-Step "Writing payload at sector $SectorOffset"
    $written = [RawDisk]::WriteAtSector($device, $payload, $SectorOffset, $sectorSize)
    Write-Host "  wrote $written bytes ($($payload.Length) payload + $($written - $payload.Length) padding)"

    Write-Step "Verifying written data"
    $readback = [RawDisk]::ReadAtSector($device, $SectorOffset, $payload.Length, $sectorSize)
    $mismatch = -1
    for ($i = 0; $i -lt $payload.Length; $i++) {
        if ($payload[$i] -ne $readback[$i]) { $mismatch = $i; break }
    }
    if ($mismatch -ge 0) {
        Die "read-back verification failed at byte $mismatch; the card may be faulty or write-protected"
    }

    Write-Host ""
    Write-Host "SD card flashed and verified." -ForegroundColor Green
    Write-Host ""
    Write-Host "Insert the card into the PIC64GX Curiosity Kit, connect HDMI, power on."
    Write-Host "For console output: 115200 8N1 on the board's UART0."
    Write-Host ""
} catch {
    Die $_.Exception.Message
} finally {
    foreach ($h in $handles) { [void][RawDisk]::CloseHandle($h) }
    if ($handles.Count -gt 0) { Write-Host "Volume handles released." -ForegroundColor DarkGray }
}
