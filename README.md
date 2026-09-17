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
2. Check the [Windows setup guide](BUILD_WINDOWS.md) only if you need to build
   Zephyr code.
3. Try the [Flappy Microchip example](examples/flappy-microchip/README.md).

The example is there to show one possible direction. Please do not build a
second Flappy Bird unless you have a truly convincing reason. The hackathon is
about ideas, not about producing the 47th bird clone.

## Fastest possible start

A pre-built example image is included. You can flash it without installing
Zephyr, Python or WSL.

Open PowerShell as Administrator and list the disks:

```powershell
Get-Disk | Format-Table Number,FriendlyName,BusType,Size,IsBoot,IsSystem
```

Then flash the supplied image. Replace `<SD_CARD_NUMBER>` with the number of
the SD card you identified:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
& ".\tools\flash_sdcard.ps1" `
  -DiskNumber <SD_CARD_NUMBER> `
  -PayloadPath ".\examples\flappy-microchip\payload.bin"
```

Connect the SD card to the PIC64GX Curiosity Kit, connect HDMI and power on.
The board should boot the example. That is the quick path. The toolchain is
only needed when you want to change or build firmware.

## Repository contents

```text
README.md                         This overview
CHALLENGE.md                      Challenge brief and rules
BUILD_WINDOWS.md                  Native Windows setup
examples/flappy-microchip/        Optional reference example
tools/                            Small, focused workshop tools
assets/                           Repository images and branding
```

## Platform support

The recommended participant setup is **native Windows** with PowerShell.
Zephyr provides Windows host tools, the Zephyr SDK has a Windows bundle and
the HSS payload generator provides Windows binaries.

WSL and Ubuntu are optional fallback paths, not a requirement for this
challenge.

## What you need for hardware testing

- Microchip PIC64GX Curiosity Kit
- HDMI monitor, preferably 1280x720
- microSD card and card reader
- USB-UART cable for optional console output

The challenge itself does not require a display on the board. A board can be a
headless device and communicate with a PC application through UART, USB,
Bluetooth, Wi-Fi or Ethernet.

## License and source access

The Flappy Microchip example uses an application repository that may require
Microchip Git access. The pre-built image can be used without that access.
The organizer should provide source access to teams that want to build or
modify the example.
