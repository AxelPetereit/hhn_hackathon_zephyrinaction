![Microchip Logo](assets/logo.png "Microchip Technology")

# Zephyr in Action

## Build an Interactive Edge Experience with Microchip Hardware and Zephyr RTOS

Dear hackers,

This repository is the starting point for the **Zephyr in Action** hackathon
challenge. Build something that makes people stop, interact and ask how it
works.

Your solution can be a game, puzzle, installation, demo or another short
interactive experience. The idea is simple: make Zephyr RTOS tangible and make
Microchip hardware part of the experience, not just part of the slide deck.

## Start here

1. Read the [challenge brief](CHALLENGE.md).
2. Set up your machine with the [environment setup guides](setup/README.md).
   Windows, Linux and macOS are all covered, with one script per step.
3. Try the [Flappy Microchip example](examples/flappy-microchip/README.md).

The example is there to show one possible direction. Please do not build a
second Flappy Bird unless you have a truly convincing reason. The hackathon is
about ideas, not about producing the 47th bird clone.

## Fastest possible start

A pre-built example image is included. You can flash it without installing
Zephyr or a toolchain at all.

**Windows** (PowerShell as Administrator):

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\setup\windows\flash.ps1 -List
.\setup\windows\flash.ps1 -DiskNumber <SD_CARD_NUMBER>
```

**Linux**:

```bash
./setup/linux/flash.sh --list
sudo ./setup/linux/flash.sh --device /dev/sdX
```

**macOS**:

```bash
./setup/macos/flash.sh --list
sudo ./setup/macos/flash.sh --device /dev/diskN
```

Connect the SD card to the PIC64GX Curiosity Kit, connect HDMI and power on.
The board should boot the example. That is the quick path. The toolchain is
only needed when you want to change or build firmware.

The flash scripts refuse system disks, check the payload before writing and
verify the data afterwards. You still have to confirm the target yourself.

## Repository contents

```text
README.md                         This overview
CHALLENGE.md                      Challenge brief and rules
setup/                            Environment setup for Windows, Linux, macOS
BUILD_WINDOWS.md                  Older Windows-only notes, superseded by setup/
examples/flappy-microchip/        Optional reference example
tools/                            Older Windows workshop scripts
assets/                           Repository images and branding
```

## Platform support

All three desktop platforms are supported, with the same pinned toolchain and
the same four steps on each. See [setup/README.md](setup/README.md).

| Platform | Status |
|---|---|
| Windows 10/11 x86_64 | Native PowerShell, no WSL needed |
| Linux x86_64 / aarch64 | Verified end to end on Ubuntu 24.04 |
| macOS Apple Silicon | Native build; payload uses the portable generator |
| macOS Intel | Not supported: no macOS x86_64 Zephyr SDK exists |

One platform difference worth knowing: the official HSS payload generator has no
macOS build, so the repository includes a portable Python implementation whose
output is verified byte for byte against the official tool. Details in
[setup/README.md](setup/README.md).

## What you need for hardware testing

- Microchip PIC64GX Curiosity Kit
- HDMI monitor, preferably 1280x720
- microSD card and card reader
- USB-UART cable for optional console output

The challenge itself does not require a display on the board. A board can be a
headless device and communicate with a PC application through UART, USB,
Bluetooth, Wi-Fi or Ethernet.

## License and source access

The Flappy Microchip application source is included in this repository. The
patch next to it documents the original example change set. The upstream
Microchip repository is only needed if the source snapshot should be updated.
