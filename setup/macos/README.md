# macOS Setup

From a fresh Mac to a booting PIC64GX1000 Curiosity Kit.

## Apple Silicon only

These scripts require an **M1 or newer Mac**. Zephyr SDK 1.0.1 publishes only
`zephyr-sdk-1.0.1_macos-aarch64_*`; there is no macOS x86_64 build. The setup
script checks `uname -m` and stops with an explanation rather than failing
halfway through a download.

On an Intel Mac, use [../linux/README.md](../linux/README.md) in a VM,
[../windows/README.md](../windows/README.md), or a `linux/amd64` container.

## Read this before you start

The official `hss-payload-generator` has **no macOS build**. The upstream release
ships a Windows `.exe` and a Linux x86_64 ELF binary, nothing else. Compiling it
here is not practical either: it needs `libelf`/`gelf.h` from elfutils, and the
Homebrew `elfutils` formula is Linux-only, while the Makefile uses GCC-specific
flags with `-Werror` that Apple clang rejects.

macOS therefore uses `setup/common/hss_payload.py`, a pure-Python reimplementation
that needs nothing but the standard library. Its output is verified byte for byte
against the official tool. You can check that yourself at any time:

```bash
~/pic64gx-zephyr/.venv/bin/python setup/common/tests/run_tests.py
```

Everything else, including the Zephyr build itself, is fully native.

## What you need

- Apple Silicon Mac (M1 or newer) running a recent macOS
- About 15 GB free disk space
- Homebrew, from https://brew.sh
- Xcode command line tools: `xcode-select --install`
- A microSD card and a card reader
- The PIC64GX1000 Curiosity Kit, an HDMI monitor and a USB-C power supply

## Quick path: flash the pre-built image

```bash
./setup/macos/flash.sh --list
```

Identify your card, then:

```bash
sudo ./setup/macos/flash.sh --device /dev/disk4    # use your own number
```

Insert the card into the board, connect HDMI, power on.

## Full path: build from source

### 1. Dry run first

Because this path has had the least real-hardware exposure, start with:

```bash
./setup/macos/setup.sh --dry-run
```

It prints every action without changing anything. If that looks sane, continue.

### 2. Setup

```bash
./setup/macos/setup.sh
```

This installs the host tools with Homebrew, creates a Python virtual environment
with `west`, fetches Zephyr at the pinned revision, installs the Zephyr SDK
riscv64 toolchain, clears the Gatekeeper quarantine attribute from the downloaded
toolchain, then runs the payload generator self-test.

Expect 15 to 30 minutes on the first run. The script is safe to re-run.

Useful options:

```bash
./setup/macos/setup.sh --skip-host-tools     # Homebrew packages already present
./setup/macos/setup.sh --workspace ~/work/zephyr
```

If Homebrew has just installed tools, open a new terminal so `PATH` picks up
`/opt/homebrew/bin`, then run setup again.

### 3. Build

```bash
./setup/macos/build.sh
```

Produces `~/pic64gx-zephyr/build/flappy-microchip/zephyr/zephyr.elf`.

Use `--incremental` to skip the pristine rebuild while iterating.

### 4. Create the payload image

```bash
./setup/macos/payload.sh
```

Writes `examples/flappy-microchip/payload.bin`.

To run the generator test suite before producing the image:

```bash
./setup/macos/payload.sh --self-test
```

### 5. Flash the SD card

```bash
./setup/macos/flash.sh --list
```

That runs `diskutil list external physical`. Match the size to your card, then:

```bash
sudo ./setup/macos/flash.sh --device /dev/disk4
```

Pass the **whole disk** (`/dev/disk4`), not a slice (`/dev/disk4s1`). You may
give either `/dev/disk4` or `/dev/rdisk4`; the script uses the raw `rdisk` node
internally because it is dramatically faster.

The script refuses any disk `diskutil` reports as internal, refuses slices,
checks the payload magic before writing, checks the card is large enough,
unmounts the disk, reads the data back to verify it, and ejects the card when
done. You still have to type `YES`.

## Where things end up

```
~/pic64gx-zephyr/              workspace
~/pic64gx-zephyr/.venv/        Python venv with west
~/pic64gx-zephyr/zephyr/       Zephyr tree at the pinned revision
~/pic64gx-zephyr/build/        build output
~/zephyr-sdk-1.0.1/            Zephyr SDK
```

There is no HSS generator directory; the Python implementation lives in the
repository at `setup/common/hss_payload.py`.

`pic64gx-env.sh` is written into the workspace. Source it to call `west` by hand:

```bash
. ~/pic64gx-zephyr/pic64gx-env.sh
west build -b pic64gx_curiosity_kit/pic64gx1000/u54/smp \
  examples/flappy-microchip/source/demos/pic64_smp_hello
```

## Serial console

The example prints to UART0 at **115200 8N1**. Find the port:

```bash
ls /dev/tty.usb* /dev/cu.usb*
```

Use the `cu.*` node for terminal programs. Connect with:

```bash
screen /dev/cu.usbserial-XXXX 115200
# leave screen with: Ctrl-A then k, then y
```

or install a nicer client:

```bash
brew install minicom
minicom -D /dev/cu.usbserial-XXXX -b 115200
```

If no `usbserial` device appears, the board's debug interface may need an FTDI or
Silicon Labs driver, depending on the bridge chip fitted to your kit.

## Troubleshooting

**`brew: command not found`.** Install Homebrew from https://brew.sh, then open a
new terminal.

**Setup says a command is missing right after Homebrew installed it.** Open a new
terminal so `PATH` includes `/opt/homebrew/bin`, then re-run.

**`xcode-select: error: command line tools are not installed`.** Run
`xcode-select --install` and let it finish.

**The toolchain will not run, macOS says it cannot be verified.** Gatekeeper
quarantined the download. Setup clears the attribute automatically; if it still
happens:

```bash
xattr -dr com.apple.quarantine ~/zephyr-sdk-1.0.1
```

Then allow it once under System Settings, Privacy & Security.

**`unsupported architecture x86_64`.** You are on an Intel Mac. There is no macOS
x86_64 Zephyr SDK. Use Linux, Windows or a container.

**`west build` reports the board was not found.** `pic64gx_curiosity_kit` only
exists from Zephyr v4.4.0 onwards. If your workspace was created earlier against
a different revision, remove `~/pic64gx-zephyr` and run setup again.

**`diskutil unmountDisk` fails.** Something is holding the volume. Close Finder
windows and Disk Utility, then retry. Spotlight indexing a freshly inserted card
can also hold it briefly.

**`dd: /dev/rdisk4: Permission denied`.** Run the command with `sudo`. On recent
macOS you may also need to grant your terminal Full Disk Access under System
Settings, Privacy & Security.

**The board shows nothing on HDMI.** Check the monitor input, then try a
1280x720 capable display; that is the resolution the example's device tree
overlay configures. Use the UART console to see whether Zephyr booted at all.

## What has and has not been tested

The payload generator is verified on this platform's code path: it was executed
with the real 5.8 MB `zephyr.elf` and produced an image with the same
`headerCrc` as the official tool.

The shell scripts passed shellcheck, a BSD versus GNU flag audit, a `diskutil`
output parser test against real sample output, and an argument handling test.
Every Homebrew formula and download URL was checked against the live APIs.

They have **not** been executed on real Apple hardware. Please run
`./setup/macos/setup.sh --dry-run` and then the full setup on one Mac before the
hackathon, and report anything that differs.
