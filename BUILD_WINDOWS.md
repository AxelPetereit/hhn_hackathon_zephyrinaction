# Native Windows Setup

This is the optional build path for teams that want to compile Zephyr code.
You do not need this setup to try the pre-built example.

The instructions use PowerShell and do not require WSL or Ubuntu.

## 1. Install host tools

Open PowerShell as a normal user. Install the required tools with `winget`:

```powershell
winget install --id Kitware.CMake --exact
winget install --id Ninja-build.Ninja --exact
winget install --id oss-winget.gperf --exact
winget install --id Python.Python.3.12 --exact
winget install --id Git.Git --exact
winget install --id oss-winget.dtc --exact
winget install --id wget --exact
winget install --id 7zip.7zip --exact
```

Close and reopen PowerShell after the installation.

Python 3.12 is recommended. Newer Python versions may work, but the Zephyr
documentation warns that some Python packages can fail with newer versions.

## 2. Install Zephyr and the tools

From the repository root, run:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\tools\setup_windows.ps1
```

The setup script creates a Python virtual environment, installs `west`, gets
the Zephyr modules, installs the Zephyr SDK and downloads the Windows HSS
payload generator.

The first setup downloads several hundred megabytes. That is normal. It is a
toolchain, not a small breakfast cereal.

## 3. Get the example source

The example application is stored in the PIC64GX Zephyr application repository.
The organizer must provide Git access to that repository.

```powershell
git clone https://bitbucket.microchip.com/scm/fpga-mcx/pic64gx-zephyr.git `
  "$HOME\pic64gx-zephyr"
cd "$HOME\pic64gx-zephyr"
git am "C:\path\to\hhn_hackathon_zephyrinaction\examples\flappy-microchip\flappy-working-v1.patch"
```

Replace `C:\path\to\hhn_hackathon_zephyrinaction` with the actual location of
this workshop repository.

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

The script creates a local HSS configuration with the correct Windows path.
You do not need to edit a Linux path such as `/home/m77107`.

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
