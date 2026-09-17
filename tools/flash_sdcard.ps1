[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(0, 255)]
    [int]$DiskNumber,

    [Parameter(Mandatory = $false)]
    [string]$PayloadPath,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, [int]::MaxValue)]
    [int]$SectorOffset = 139264
)

# Flash the Zephyr HSS payload to the PIC64GX SD card payload partition.
# Run as Administrator. Double-check DiskNumber. The wrong disk is not a fun demo.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class RawDisk {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr CreateFile(
        string lpFileName, uint dwDesiredAccess, uint dwShareMode,
        IntPtr lpSecurityAttributes, uint dwCreationDisposition,
        uint dwFlagsAndAttributes, IntPtr hTemplateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool WriteFile(
        IntPtr hFile, byte[] lpBuffer, uint nNumberOfBytesToWrite,
        out uint lpNumberOfBytesWritten, IntPtr lpOverlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetFilePointerEx(
        IntPtr hFile, long liDistanceToMove,
        out long lpNewFilePointer, uint dwMoveMethod);

    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    static extern bool DeviceIoControl(
        IntPtr hDevice, uint dwIoControlCode,
        IntPtr lpInBuffer, uint nInBufferSize,
        IntPtr lpOutBuffer, uint nOutBufferSize,
        out uint lpBytesReturned, IntPtr lpOverlapped);

    const uint GENERIC_WRITE         = 0x40000000;
    const uint GENERIC_READ          = 0x80000000;
    const uint FILE_SHARE_READ       = 0x00000001;
    const uint FILE_SHARE_WRITE      = 0x00000002;
    const uint OPEN_EXISTING         = 3;
    const uint NO_BUFFERING          = 0x20000000;
    const uint WRITE_THROUGH         = 0x80000000;
    const uint FSCTL_LOCK_VOLUME     = 0x00090018;
    const uint FSCTL_DISMOUNT_VOLUME = 0x00090020;

    // Opens + locks a volume, returns the handle (caller must CloseHandle when done)
    public static IntPtr LockVolume(string volumePath) {
        IntPtr h = CreateFile(volumePath,
            GENERIC_READ | GENERIC_WRITE,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);

        if (h == new IntPtr(-1)) {
            Console.WriteLine("  Open " + volumePath + " failed (" + Marshal.GetLastWin32Error() + "), skipping.");
            return IntPtr.Zero;
        }

        uint br;
        bool locked = DeviceIoControl(h, FSCTL_LOCK_VOLUME,
            IntPtr.Zero, 0, IntPtr.Zero, 0, out br, IntPtr.Zero);
        bool dismounted = DeviceIoControl(h, FSCTL_DISMOUNT_VOLUME,
            IntPtr.Zero, 0, IntPtr.Zero, 0, out br, IntPtr.Zero);

        Console.WriteLine("  " + volumePath + " -> lock=" + (locked?"OK":"FAIL") + " dismount=" + (dismounted?"OK":"FAIL"));
        return h;  // keep open to hold the lock
    }

    public static void WriteAtSector(string device, byte[] data, long sectorOffset, int sectorSize = 512) {
        int paddedLen = ((data.Length + sectorSize - 1) / sectorSize) * sectorSize;
        byte[] buf = new byte[paddedLen];
        Array.Copy(data, buf, data.Length);

        IntPtr h = CreateFile(device,
            GENERIC_READ | GENERIC_WRITE,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            IntPtr.Zero, OPEN_EXISTING,
            NO_BUFFERING | WRITE_THROUGH,
            IntPtr.Zero);

        if (h == new IntPtr(-1))
            throw new IOException("CreateFile failed: " + Marshal.GetLastWin32Error());

        try {
            long newPos;
            if (!SetFilePointerEx(h, sectorOffset * sectorSize, out newPos, 0))
                throw new IOException("Seek failed: " + Marshal.GetLastWin32Error());

            uint written;
            if (!WriteFile(h, buf, (uint)buf.Length, out written, IntPtr.Zero))
                throw new IOException("WriteFile failed: " + Marshal.GetLastWin32Error());

            Console.WriteLine("Written " + written + " bytes (" + data.Length + " payload + " + (written - data.Length) + " padding)");
        } finally {
            CloseHandle(h);
        }
    }
}
'@

if ([string]::IsNullOrWhiteSpace($PayloadPath)) {
    $PayloadPath = Join-Path $PSScriptRoot "..\examples\flappy-microchip\payload.bin"
}

if (-not (Test-Path -LiteralPath $PayloadPath -PathType Leaf)) {
    throw "Payload file not found: $PayloadPath"
}

$device = "\\.\PhysicalDrive$DiskNumber"

Write-Host "=== PIC64GX Zephyr Payload - SD Card Flash ===" -ForegroundColor Cyan
Write-Host "Disk:    $device  |  Offset: sector $SectorOffset" -ForegroundColor Cyan
Write-Host ""

$disk = Get-Disk -Number $DiskNumber
Write-Host "Target: $($disk.FriendlyName) ($([math]::Round($disk.Size / 1GB, 1)) GB)" -ForegroundColor Yellow

$confirm = Read-Host "`nType YES to flash"
if ($confirm -ne "YES") { Write-Host "Aborted." -ForegroundColor Red; exit 1 }

$payload = [System.IO.File]::ReadAllBytes($payloadPath)
Write-Host "Payload: $($payload.Length) bytes" -ForegroundColor Green

# Lock all volumes on this disk - keep handles open to hold the locks
Write-Host "Locking volumes (holding handles open)..." -ForegroundColor Yellow
$handles = New-Object System.Collections.Generic.List[IntPtr]

$partitions = Get-Partition -DiskNumber $diskNumber -ErrorAction SilentlyContinue
foreach ($p in $partitions) {
    if ($p.DriveLetter) {
        $h = [RawDisk]::LockVolume("\\.\$($p.DriveLetter):")
        if ($h -ne [IntPtr]::Zero) { $handles.Add($h) }
    }
    $uid = $p | Get-Volume -ErrorAction SilentlyContinue | Select-Object -ExpandProperty UniqueId -ErrorAction SilentlyContinue
    if ($uid) {
        $h = [RawDisk]::LockVolume($uid.TrimEnd('\'))
        if ($h -ne [IntPtr]::Zero) { $handles.Add($h) }
    }
}

try {
    Write-Host "Writing payload..." -ForegroundColor Yellow
    [RawDisk]::WriteAtSector($device, $payload, $SectorOffset)
    Write-Host ""
    Write-Host "SD card flashed successfully!" -ForegroundColor Green
    Write-Host "Insert the card into the PIC64GX board, connect HDMI and power on." -ForegroundColor Cyan
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    exit 1
} finally {
    # Release all volume locks
    foreach ($h in $handles) { [RawDisk]::CloseHandle($h) }
    Write-Host "Volume handles released." -ForegroundColor Gray
}
