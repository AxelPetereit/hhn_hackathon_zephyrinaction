# Linux Setup

From a fresh Linux machine to a booting PIC64GX1000 Curiosity Kit.

Verified end to end on Ubuntu 24.04 (x86_64). Package installation also covers
Fedora, Arch and openSUSE.

## What you need

- A 64-bit Linux distribution, x86_64 or aarch64
- About 15 GB free disk space
- `sudo` rights for package installation and for writing to the SD card
- A microSD card and a card reader
- The PIC64GX1000 Curiosity Kit, an HDMI monitor and a USB-C power supply

## Quick path: flash the pre-built image

```bash
./setup/linux/flash.sh --list
```

Identify your card, then:

```bash
sudo ./setup/linux/flash.sh --device /dev/sdb    # use your own device
```

Insert the card into the board, connect HDMI, power on.

## Full path: build from source

### 1. Setup

```bash
./setup/linux/setup.sh
```

This installs the Zephyr host dependencies with your distribution's package
manager, creates a Python virtual environment with `west`, fetches Zephyr at the
pinned revision, installs the Zephyr SDK riscv64 toolchain and the HSS payload
generator, then runs the payload generator self-test.

Expect 15 to 30 minutes on the first run. The script is safe to re-run.

Useful options:

```bash
./setup/linux/setup.sh --dry-run             # show what would happen
./setup/linux/setup.sh --skip-host-tools     # dependencies already installed
./setup/linux/setup.sh --workspace /opt/zephyr
```

### 2. Build

```bash
./setup/linux/build.sh
```

Produces `~/pic64gx-zephyr/build/flappy-microchip/zephyr/zephyr.elf`. A
successful build ends with a memory report similar to:

```
Memory region         Used Size  Region Size  %age Used
             RAM:      865112 B         2 MB     41.25%
```

Use `--incremental` to skip the pristine rebuild while iterating.

### 3. Create the payload image

```bash
./setup/linux/payload.sh
```

Writes `examples/flappy-microchip/payload.bin`.

To prove that the portable Python generator agrees with the official tool on
your own build:

```bash
./setup/linux/payload.sh --compare
```

You can also force one implementation:

```bash
./setup/linux/payload.sh --generator python
./setup/linux/payload.sh --generator upstream
```

### 4. Flash the SD card

```bash
./setup/linux/flash.sh --list
```

Look for `RM=1` or `HOTPLUG=1` and match the size to your card, then:

```bash
sudo ./setup/linux/flash.sh --device /dev/sdb
```

Pass the **whole disk** (`/dev/sdb`), not a partition (`/dev/sdb1`).

The script refuses a device whose partitions host `/`, `/boot`, `/home`, `/usr`
or `/var`, refuses partitions, checks the payload magic before writing, checks
the card is large enough, unmounts mounted partitions, and reads the data back to
verify it. You still have to type `YES`.

## Where things end up

```
~/pic64gx-zephyr/              workspace
~/pic64gx-zephyr/.venv/        Python venv with west
~/pic64gx-zephyr/zephyr/       Zephyr tree at the pinned revision
~/pic64gx-zephyr/build/        build output
~/zephyr-sdk-1.0.1/            Zephyr SDK
~/hss-payload-generator-*/     HSS payload generator
```

`pic64gx-env.sh` is written into the workspace. Source it if you want to call
`west` by hand:

```bash
. ~/pic64gx-zephyr/pic64gx-env.sh
west build -b pic64gx_curiosity_kit/pic64gx1000/u54/smp \
  examples/flappy-microchip/source/demos/pic64_smp_hello
```

## Serial console

The example prints to UART0 at **115200 8N1**. Find the port:

```bash
ls -l /dev/serial/by-id/
dmesg | tail -20        # right after plugging the board in
```

Connect with any of:

```bash
picocom -b 115200 /dev/ttyUSB0
screen /dev/ttyUSB0 115200
minicom -D /dev/ttyUSB0 -b 115200
```

If you get a permission error, add yourself to the serial group and log out and
back in:

```bash
sudo usermod -aG dialout "$USER"     # Debian, Ubuntu
sudo usermod -aG uucp "$USER"        # Arch, Fedora
```

## Troubleshooting

**`python3 -m venv` fails.** Install the venv package:
`sudo apt install python3-venv`.

**`cmake` is too old.** Zephyr needs 3.20 or newer. The script checks and stops
with a clear message. On older Debian or Ubuntu releases, use the Kitware APT
repository or download CMake from cmake.org.

**`west build` reports the board was not found.** `pic64gx_curiosity_kit` only
exists from Zephyr v4.4.0 onwards. If your workspace was created earlier against
a different revision, remove `~/pic64gx-zephyr` and run setup again.

**No supported package manager.** The script warns and continues. Install the
Zephyr host dependencies manually, then re-run with `--skip-host-tools`.

**`dd` says the device is busy.** Something still has the card mounted. Check
with `lsblk` and `findmnt`, unmount it, then retry. Desktop auto-mounters like to
re-mount cards the moment they appear.

**The board shows nothing on HDMI.** Check the monitor input, then try a
1280x720 capable display; that is the resolution the example's device tree
overlay configures. Use the UART console to see whether Zephyr booted at all.

**`payload.sh --compare` reports a mismatch.** Do not flash that image. Capture
the output and report it, that would be a real bug.

## Running the flash step against an image file

If you want to rehearse the flash step without a card, the script accepts loop
devices:

```bash
truncate -s 256M /tmp/fakecard.img
LOOP=$(sudo losetup --find --show /tmp/fakecard.img)
sudo ./setup/linux/flash.sh --device "$LOOP" --yes
sudo dd if="$LOOP" bs=512 skip=139264 count=1 status=none | od -An -tx4 -N4
# expect b007c0de
sudo losetup -d "$LOOP"
```
