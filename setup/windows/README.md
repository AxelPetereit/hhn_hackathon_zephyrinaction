# Windows Setup

From a fresh Windows 10 or 11 machine to a booting PIC64GX1000 Curiosity Kit.

Everything runs in native PowerShell. WSL is not required.

## What you need

- Windows 10 or 11, 64-bit
- About 15 GB free disk space (Zephyr tree, SDK, build output)
- A microSD card and a card reader
- The PIC64GX1000 Curiosity Kit, an HDMI monitor and a USB-C power supply
- Administrator rights, but only for the flash step

## Quick path: flash the pre-built image

If you just want to see the example run, skip the toolchain entirely.

Open PowerShell **as Administrator**, then:

```powershell
cd C:\path\to\Zephyr_HelloFPGA
Set-ExecutionPolicy -Scope Process Bypass -Force
.\setup\windows\flash.ps1 -List
```

Find your card in the list, then:

```powershell
.\setup\windows\flash.ps1 -DiskNumber 2      # use your own number
```

Insert the card into the board, connect HDMI, power on.

## Full path: build from source

### 1. Setup

Open a normal (non-elevated) PowerShell in the repository root:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\setup\windows\setup.ps1
```

This installs the host tools with winget, creates a Python virtual environment
with `west`, fetches Zephyr at the pinned revision, installs the Zephyr SDK
riscv64 toolchain and the HSS payload generator, then runs the payload generator
self-test.

Expect 15 to 30 minutes and several hundred megabytes of downloads on the first
run. The script is safe to re-run; completed steps are skipped.

Useful options:

```powershell
.\setup\windows\setup.ps1 -DryRun            # show what would happen
.\setup\windows\setup.ps1 -SkipHostTools     # corporate image already has them
.\setup\windows\setup.ps1 -Workspace D:\zephyr
```

If winget has just installed tools, **close the window and open a new
PowerShell** so that `PATH` is refreshed, then run setup again.

### 2. Build

```powershell
.\setup\windows\build.ps1
```

Produces `%USERPROFILE%\pic64gx-zephyr\build\flappy-microchip\zephyr\zephyr.elf`.

Use `-Incremental` to skip the pristine rebuild while iterating.

### 3. Create the payload image

```powershell
.\setup\windows\payload.ps1
```

Writes `examples\flappy-microchip\payload.bin`.

To prove that the portable Python generator agrees with the official tool on
your own build:

```powershell
.\setup\windows\payload.ps1 -Compare
```

### 4. Flash the SD card

```powershell
.\setup\windows\flash.ps1 -List
```

```powershell
# Administrator PowerShell
.\setup\windows\flash.ps1 -DiskNumber 2
```

The script refuses disks flagged as boot or system, refuses a disk holding the
Windows drive, checks the payload magic before writing anything, locks and
dismounts the card's volumes, and reads the data back to verify it. You still
have to type `YES`, and you still have to check the disk number.

## Where things end up

```
%USERPROFILE%\pic64gx-zephyr\              workspace
%USERPROFILE%\pic64gx-zephyr\.venv\        Python venv with west
%USERPROFILE%\pic64gx-zephyr\zephyr\       Zephyr tree at the pinned revision
%USERPROFILE%\pic64gx-zephyr\build\        build output
%USERPROFILE%\zephyr-sdk-1.0.1\            Zephyr SDK
%USERPROFILE%\hss-payload-generator-*\     HSS payload generator
```

`pic64gx-env.ps1` is written into the workspace. Dot-source it if you want to
call `west` by hand:

```powershell
. $HOME\pic64gx-zephyr\pic64gx-env.ps1
west build -b pic64gx_curiosity_kit/pic64gx1000/u54/smp examples\flappy-microchip\source\demos\pic64_smp_hello
```

## Serial console

The example prints to UART0 at **115200 8N1**. Find the port:

```powershell
Get-CimInstance Win32_SerialPort | Select-Object DeviceID, Description
```

The Curiosity Kit exposes several serial ports over its USB debug connection.
UART0 is usually the lowest-numbered one. Connect with PuTTY, Tera Term, or:

```powershell
# plink, part of PuTTY
plink -serial COM4 -sercfg 115200,8,n,1,N
```

## Troubleshooting

**`winget` is not recognised.** Install *App Installer* from the Microsoft
Store, then open a new PowerShell.

**`cannot be loaded because running scripts is disabled`.** Run
`Set-ExecutionPolicy -Scope Process Bypass -Force` first. It applies only to
that window.

**Setup says a command is missing right after installing it.** winget does not
update `PATH` in the running process. Close the window, open a new one, re-run.

**`west build` fails with a board not found error.** The board
`pic64gx_curiosity_kit` only exists from Zephyr v4.4.0 onwards. If your workspace
was created earlier against a different revision, delete
`%USERPROFILE%\pic64gx-zephyr` and run setup again.

**CMake complains about a path length limit.** Move the workspace somewhere
short, for example `-Workspace C:\zp`. Windows path limits still bite deep build
trees.

**The flash script cannot open the physical drive.** Close Explorer windows and
anything else touching the card, then retry. Antivirus software sometimes holds a
handle on removable media as well.

**The board shows nothing on HDMI.** Check that the monitor is on the right
input, then try a 1280x720 capable display; that is the resolution the example's
device tree overlay configures. Use the UART console to see whether Zephyr booted
at all.

**`payload.ps1` reports the two generators disagree.** Do not flash that image.
Capture the output and report it, that would be a real bug.
