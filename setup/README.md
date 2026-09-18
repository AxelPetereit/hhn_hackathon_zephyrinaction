# Environment Setup

Everything needed to go from a fresh machine to a booting PIC64GX1000 Curiosity
Kit, on Windows, Linux or macOS.

Pick your platform:

| Platform | Guide | Scripts |
|---|---|---|
| Windows 10/11 | [windows/README.md](windows/README.md) | PowerShell |
| Linux (Ubuntu, Fedora, Arch, openSUSE) | [linux/README.md](linux/README.md) | bash |
| macOS (Apple Silicon) | [macos/README.md](macos/README.md) | bash |

Every platform runs the same four steps:

```
setup     install toolchain, fetch Zephyr, install SDK
build     compile the example for the board
payload   wrap zephyr.elf into an HSS boot image
flash     write the image to the SD card at sector 139264
```

If you only want to run the pre-built example, skip straight to the flash step.
The repository ships a ready `examples/flappy-microchip/payload.bin`.

## Pinned versions

All three platforms read `common/versions.env`, so everyone on the team gets the
same toolchain. Change a version there, never in the individual scripts.

| What | Version | Why this one |
|---|---|---|
| Zephyr | `v4.4.2` | `boards/microchip/pic64gx_curiosity_kit` only exists from **v4.4.0** onwards. An unpinned `west init` can land on a tree that cannot build this project at all. |
| Zephyr SDK | `1.0.1` | The version Zephyr v4.4.2 asks for in its `SDK_VERSION` file. |
| SDK toolchain | `riscv64-zephyr-elf` | The only one PIC64GX needs; installing all of them wastes several GB. |
| HSS payload generator | `v2026.04.1` | Latest release that ships a payload generator archive. |
| Board target | `pic64gx_curiosity_kit/pic64gx1000/u54/smp` | Four U54 harts, SMP, running from cached DDR at `0x80000000`. |
| Payload sector | `139264` (LBA `0x22000`) | Where the HSS bootloader looks for the payload image. |

## Platform differences that actually matter

**There is no macOS build of the official HSS payload generator.** The upstream
release contains exactly two binaries: `hss-payload-generator.exe` for Windows
and a Linux x86_64 ELF. Building it from source on a Mac fails because it needs
`libelf`/`gelf.h` from elfutils, and the Homebrew `elfutils` formula is
Linux-only (`requirements: linux`, no macOS bottles). The Makefile is also
GCC-specific with `-Werror`, using flags Apple clang does not recognise
(`-Wold-style-declaration`, `-Wimplicit-fallthrough=5`, `-ftrapv`).

So `common/hss_payload.py` exists: a pure-Python, standard-library-only
implementation of the payload writer. It runs identically on all three
platforms. Its output is verified byte for byte against the official tool, see
[Verification](#verification) below.

**Intel Macs are not supported.** Zephyr SDK 1.0.1 publishes
`zephyr-sdk-1.0.1_macos-aarch64_*` only, with no macOS x86_64 build. The macOS
setup script detects this and stops with an explanation rather than failing
halfway through. Use Linux, Windows or a container instead.

## Verification

The payload generator has a test suite. It runs automatically during setup and
you can run it any time:

```bash
# Linux / macOS
~/pic64gx-zephyr/.venv/bin/python setup/common/tests/run_tests.py

# Windows
& "$HOME\pic64gx-zephyr\.venv\Scripts\python.exe" setup\common\tests\run_tests.py
```

Add `--reference <path to hss-payload-generator>` for a differential test that
builds the same configurations with the official tool and requires identical
output. Setup does this for you on Windows and Linux.

If you change any of the setup scripts, run everything at once before pushing:

```bash
./setup/common/tests/run_all.sh
```

That covers bash syntax, shellcheck, a GNU versus BSD portability scan, the
macOS-specific logic checks and the generator test suite. It needs `shellcheck`
for the linting stage and skips it cleanly if that is not installed.

What was actually checked while writing these scripts:

- **Linux**: setup, build, payload and flash executed end to end on Ubuntu
  24.04. The build produced a 5.8 MB `zephyr.elf` (557 targets, 41.25% of the
  2 MB RAM region). The flash step was rehearsed against a loop device, with a
  byte-exact read-back at sector 139264 and a confirmation that the preceding
  sector stayed untouched.
- **Windows**: payload generation run against a real `zephyr.elf`, producing an
  image with the same `headerCrc` as the official tool. All flash safety checks
  exercised: system disk refusal, unknown disk, non-payload file, missing file.
- **macOS**: cannot be executed here. Verified by shellcheck, `bash -n`, a
  `diskutil` output parser test against real sample output, BSD `dd` and BSD
  `stat` flag checks, and by running the payload script with Darwin stubbed so
  the real code path executes. Every Homebrew formula and download URL was
  checked against the live APIs. **Run `./setup/macos/setup.sh --dry-run` on a
  real Mac before the hackathon.**
- **CMake 4**: Homebrew now ships CMake 4.4.3 while Zephyr only requires 3.20.
  Because CMake 4 removed compatibility with old policy versions, the full build
  was repeated with CMake 4.4.3 to confirm Zephyr v4.4.2 still builds. It does.

### About the "raw byte differences" in the comparison

The comparison output mentions a handful of raw byte differences that are
normalised away. That is expected and harmless.

`struct HSS_BootChunkDesc` has 4 bytes of padding after its `owner` field and 4
more after `crc32`. The upstream C tool writes these descriptors from partially
initialised stack memory, so the padding contains leftover stack garbage that
differs per platform and per run:

```
Windows build of the official tool : 0a 00 00 00
Linux build (this repo's payload)  : fc 7f 00 00   <- a stack address fragment
```

The padding belongs to no struct field, the HSS bootloader never reads it, and
`headerCrc` covers only the header, not the chunk tables. The Python generator
writes deterministic zeros there. Everything that carries meaning, including the
`headerCrc`, matches exactly.

## Directory layout

```
setup/
  README.md                     this file
  common/
    versions.env                the single source of truth for pinned versions
    versions.ps1                reads versions.env from PowerShell
    hss_payload.py              portable HSS payload generator
    tests/
      run_all.sh                runs every check below
      run_tests.py              generator test suite (88 checks)
      compare_payloads.py       semantic diff of two payload images
      make_test_elf.py          synthetic RISC-V ELF builder for the tests
      syntax_check.sh           bash syntax, shellcheck, portability scan
      macos_logic_check.sh      macOS-specific logic checks
  windows/  setup.ps1  build.ps1  payload.ps1  flash.ps1  README.md
  linux/    setup.sh   build.sh   payload.sh   flash.sh   README.md
  macos/    setup.sh   build.sh   payload.sh   flash.sh   README.md
```

## Relation to `tools/`

The older scripts in `tools/` still work for Windows and are kept so existing
instructions do not break. `setup/windows/` supersedes them: it pins the Zephyr
revision, handles the SDK 1.0.1 directory layout, refuses to write to system
disks and verifies the data it wrote. Prefer `setup/` for new work.
