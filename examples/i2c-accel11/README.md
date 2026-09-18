# Accel 11 Click over I2C

Standalone I2C example for the PIC64GX1000 Curiosity Kit. It reads acceleration
from a MikroElektronika **Accel 11 Click** plugged into the mikroBUS header and
prints the samples on the console. No display, no LVGL, no sensor subsystem.

## What is on the Click board

The Accel 11 Click carries a **Bosch BMA456** accelerometer. Its chip ID is
`0x16`. That matters, because Zephyr's in-tree `bma4xx` driver only accepts
`0x12` (BMA422), `0x13` (BMA423) and `0x90` (BMA400). Feed it a BMA456 and it
logs `Chip id (0x16) not supported` and returns `-ENODEV`
(`drivers/sensor/bosch/bma4xx/bma4xx.c:278`).

So this example does not use a sensor driver. It reads and writes the BMA456
registers directly through the Zephyr I2C API. Register addresses, the data bit
layout and the scaling were cross-checked against `bma4xx_defs.h` and
`bma4xx_decoder.c` in the Zephyr tree.

## Wiring

The Accel 11 Click plugs into the mikroBUS header. Match the notch on the Click
board with the silkscreen outline on the Curiosity Kit; only the I2C pins matter
here:

| mikroBUS pin | Signal |
| ------------ | ------ |
| SCL          | I2C clock |
| SDA          | I2C data |
| 3V3 / GND    | Supply |

The I2C address is set by the SDO pin on the Click board: low gives `0x18`
(the factory default), high gives `0x19`. Both are probed, so either works.

## Why the example probes two controllers

The PIC64GX SoC has two I2C controllers, `i2c0` at `0x2010a000` and `i2c1` at
`0x2010b000`. Both are enabled in the board devicetree
(`pic64gx_curiosity_kit_common.dtsi`). Which one actually reaches the mikroBUS
SCL/SDA pins is decided by the Libero FPGA fabric design, and Zephyr has no way
to know that. The board provides no `mikro-bus` devicetree node either.

Rather than guessing, the example tries all four combinations at startup:
`i2c0` and `i2c1`, each at `0x18` and `0x19`. It reads the chip ID register and
uses the first combination that answers with `0x16`.

## Two quirks of the PIC64GX I2C driver

Both are visible in `drivers/i2c/i2c_mchp_mss.c` and both affect user code:

1. **`clock-frequency` from the devicetree is parsed but never applied.** The
   value is stored in the driver config and then ignored. Bus speed comes only
   from `i2c_configure()`, so calling it is mandatory, not a nicety. The example
   does this in `detect()`.

2. **Zero length transfers are rejected with `-EINVAL`.** The driver refuses them
   outright (`mss_i2c_transfer()`, first length check). This breaks the usual
   address scan trick, and it means the Zephyr shell command `i2c scan` reports
   an empty bus even when a device is sitting right there, because `cmd_i2c_scan`
   probes with `len = 0`. Use `i2c read_byte` instead.

## Build and run

```bash
# Linux / WSL
export ZEPHYR_BASE=$HOME/pic64gx-zephyr/zephyr
export ZEPHYR_SDK_INSTALL_DIR=$HOME/zephyr-sdk-1.0.1
export ZEPHYR_TOOLCHAIN_VARIANT=zephyr

$HOME/pic64gx-zephyr/.venv/bin/west build \
  -b pic64gx_curiosity_kit/pic64gx1000/u54/smp \
  -d $HOME/pic64gx-zephyr/build/i2c-accel11 -p always \
  examples/i2c-accel11
```

Then turn the ELF into an HSS payload and write it to the SD card, the same way
as for the Flappy example:

```bash
./setup/linux/payload.sh \
  --build-dir $HOME/pic64gx-zephyr/build/i2c-accel11 \
  --output examples/i2c-accel11/payload.bin
./setup/linux/flash.sh --list
```

Note that `setup/linux/build.sh` is hardwired to the Flappy demo path, so use
`west build` directly as shown above. `payload.sh` reads its YAML from the
Flappy directory too; pass `--build-dir` and `--output` as shown and it produces
a working image, because the payload layout is identical.

## Console

Output goes to **mmuart1 at 115200 8N1**. That is what the board DTS selects for
both `zephyr,console` and `zephyr,shell-uart`. Other documentation in this repo
says UART0, which is wrong for this board target.

## Expected output

With a Click board attached:

```
=== Accel 11 Click (Bosch BMA456) on PIC64GX1000 Curiosity Kit ===

Probing I2C controllers and addresses:
  i2c0  0x18 : BMA456 found, chip ID 0x16

Using i2c0 at address 0x18
Configured: ODR 50 Hz, +/-2 g range
Die temperature: 27 C

Streaming samples (raw counts are 12 bit, -2048..2047):

X      7 (    6 mg)   Y    -12 (  -11 mg)   Z   1021 (  997 mg)
```

At rest on a flat surface, one axis should read roughly 1000 mg and the other two
near zero.

Without a Click board, the probe fails on all four combinations and the example
prints a checklist, then returns from `main()`. It does not spin, so the shell
stays usable on the same console.

## Troubleshooting

If nothing responds, work through the list the firmware prints. The most common
cause is not the software but the FPGA design: if no I2C controller is routed to
the mikroBUS pins, no amount of probing will find the sensor.

To poke the bus by hand, the shell is enabled:

```
device list
i2c read_byte i2c@2010a000 0x18 0x00    # chip ID on controller 0
i2c read_byte i2c@2010b000 0x18 0x00    # chip ID on controller 1
```

A reply of `0x16` confirms a BMA456. A different value means some other chip
answered at that address. An error means nothing is there.

Do not use `i2c scan` here, see quirk 2 above.

## Verification status

Verified on a Linux host (WSL Ubuntu 24.04) against Zephyr v4.4.2:

- builds clean for `pic64gx_curiosity_kit/pic64gx1000/u54/smp`, no warnings,
  154792 bytes RAM (7.38 % of the 2 MB region)
- HSS payload generates with valid magic `0xb007c0de`
- register addresses, the 12-bit left-aligned data layout and the mg scaling
  cross-checked against the Zephyr `bma4xx` sources

**Not verified:** actual I2C bus traffic and sensor readings. No Accel 11 Click
was available during development, so the detection path, the initialisation
sequence and the sample output have never run against real hardware. Treat the
numbers in the example output above as illustrative.
