# Flappy Microchip

Flappy Microchip is the reference example for the **Zephyr in Action**
challenge.

It shows one way to combine:

- Microchip PIC64GX Curiosity Kit hardware
- Zephyr RTOS
- Zephyr SMP on the U54 cores
- LVGL graphics
- GPIO button input
- HDMI output
- an HSS payload booted from an SD card

The game starts directly after boot. Press SW2 to start or flap. Press SW2
again after game over to restart.

## Try it without a build environment

Use the included `payload.bin` and flash it with:

```powershell
& ".\tools\flash_sdcard.ps1" `
  -DiskNumber <SD_CARD_NUMBER> `
  -PayloadPath ".\examples\flappy-microchip\payload.bin"
```

See [BUILD_WINDOWS.md](../../BUILD_WINDOWS.md) for the optional native Windows
build instructions.

## What this example is for

This example demonstrates the complete path from a Zephyr application to a
bootable PIC64GX SD-card image. It is intentionally small enough to explain in
a workshop and visible enough to attract a few humans away from the coffee.

It is not the challenge solution. Teams can use it as a technical reference,
then build a different visitor experience.

## Source

The application source is maintained in the PIC64GX Zephyr application
repository. The patch in this directory contains the Flappy Microchip changes.
The organizer must provide access to the source repository for teams that want
to rebuild or modify the example.
