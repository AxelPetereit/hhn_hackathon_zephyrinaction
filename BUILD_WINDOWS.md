# Native Windows Setup

This is the optional build path for teams that want to compile Zephyr code.
You do not need this setup to try the pre-built example.

The instructions use PowerShell and do not require WSL or Ubuntu.

## 1. Start the setup

Open PowerShell as a normal user. Windows 10 and 11 usually include `winget`.
Check it with:

```powershell
winget --version
```

If `winget` is missing, install **App Installer** from the Microsoft Store.

Python 3.12 is recommended. Newer Python versions may work, but the Zephyr
documentation warns that some Python packages can fail with newer versions.

## 2. Install Zephyr and the tools

From the repository root, run:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\tools\setup_windows.ps1
```

The setup script installs the host tools through `winget`, creates a Python
virtual environment, installs `west`, gets the Zephyr modules, installs the
Zephyr SDK and downloads the Windows HSS payload generator.

If your company image already contains all host tools, use:

```powershell
.\tools\setup_windows.ps1 -SkipHostTools
```

The first setup downloads several hundred megabytes. That is normal. It is a
toolchain, not a small breakfast cereal.

## 3. Use the included example source

The PIC64GX application source is included in this repository:

```text
examples\flappy-microchip\source
```

No private source clone is needed for the example build. The patch next to the
source is kept as a reference for how the Flappy Microchip changes were made.

## 4. Build the example

Run:

```powershell
.\tools\build_flappy.ps1
```

The build target is:

```text
pic64gx_curiosity_kit/pic64gx1000/u54/smp
```

The ELF file is written to:

```text
$HOME\zephyrproject\build\flappy-microchip\zephyr\zephyr.elf
```

## 5. Create a payload image

Run:

```powershell
.\tools\generate_payload.ps1
```

The generated image is written to:

```text
examples\flappy-microchip\payload.bin
```

The script creates a local HSS configuration with the correct Windows ELF path.
No manual path editing is needed.

## 6. Flash the SD card

List the disks and identify the SD card by its size:

```powershell
Get-Disk | Format-Table Number,FriendlyName,BusType,Size,IsBoot,IsSystem
```

Open PowerShell as Administrator and run:

```powershell
& ".\tools\flash_sdcard.ps1" `
  -DiskNumber <SD_CARD_NUMBER> `
  -PayloadPath ".\examples\flappy-microchip\payload.bin"
```

The script asks for a final `YES` confirmation. Check the disk number twice.
The wrong disk is an impressive demonstration, but not the one we planned.

The payload is written at sector `139264` (LBA `0x22000`).

## Alternative: WSL

WSL remains possible if native Windows causes trouble. The repository no longer
requires it for the normal participant setup.
