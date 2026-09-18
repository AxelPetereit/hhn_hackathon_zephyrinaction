#!/usr/bin/env python3
# Copyright (c) 2026 Microchip Technology Inc
# SPDX-License-Identifier: MIT
#
# Verify the portable Python HSS payload generator.
#
# Two modes:
#   Self-check (always runs, no extra tooling needed)
#       Validates struct sizes and offsets against the values observed in the
#       reference payload.bin shipped with this repository, checks the CRC32
#       implementation, parses the real hss-payload.yaml, and builds images from
#       synthetic RISC-V ELFs to confirm layout and determinism.
#
#   Differential check (runs when --reference points at the upstream tool)
#       Builds the same configurations with the official hss-payload-generator
#       and requires semantically identical output. Uninitialised struct padding
#       is normalised away; see compare_payloads.py for why.
#
# Usage:
#   python3 run_tests.py
#   python3 run_tests.py --reference /path/to/hss-payload-generator

from __future__ import annotations

import argparse
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
COMMON = HERE.parent
REPO = COMMON.parent.parent

sys.path.insert(0, str(COMMON))
sys.path.insert(0, str(HERE))

import hss_payload as hp  # noqa: E402
from compare_payloads import normalise  # noqa: E402
from make_test_elf import CASES, build_elf  # noqa: E402

REAL_CONFIG = (
    REPO
    / "examples"
    / "flappy-microchip"
    / "source"
    / "demos"
    / "pic64_smp_hello"
    / "hss-payload.yaml"
)
REAL_PAYLOAD = REPO / "examples" / "flappy-microchip" / "payload.bin"

PASSED: list[str] = []
FAILED: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        PASSED.append(name)
        print("  PASS  {}".format(name))
    else:
        FAILED.append(name)
        print("  FAIL  {}{}".format(name, (" - " + detail) if detail else ""))


# ---------------------------------------------------------------------------


def test_struct_layout() -> None:
    print("\n[struct layout]")
    check(
        "HSS_BootImage is 1632 bytes", hp.BOOTIMAGE_SIZE == 1632, str(hp.BOOTIMAGE_SIZE)
    )
    check("HSS_BootChunkDesc is 40 bytes", hp.CHUNK_SIZE == 40, str(hp.CHUNK_SIZE))
    check("HSS_BootZIChunkDesc is 24 bytes", hp.ZI_SIZE == 24, str(hp.ZI_SIZE))
    check("per-hart struct is 296 bytes", hp.HART_SIZE == 296, str(hp.HART_SIZE))

    # Cross-check against the shipped reference image, which was produced by the
    # official Linux tool. chunkTableOffset must equal sizeof(HSS_BootImage) and
    # ziChunkTableOffset must follow the chunk table exactly.
    if REAL_PAYLOAD.is_file():
        data = REAL_PAYLOAD.read_bytes()
        magic, _v, header_len, _crc, chunk_off, zi_off = struct.unpack_from(
            hp.BOOTIMAGE_PREFIX_FMT, data, 0
        )
        check("reference payload magic", magic == hp.HSS_BOOT_MAGIC)
        check(
            "reference chunkTableOffset == sizeof(HSS_BootImage)",
            chunk_off == hp.BOOTIMAGE_SIZE,
            "0x{:x} vs 0x{:x}".format(chunk_off, hp.BOOTIMAGE_SIZE),
        )
        num_chunks = (zi_off - chunk_off) // hp.CHUNK_SIZE - 1
        expected_zi = chunk_off + (num_chunks + 1) * hp.CHUNK_SIZE
        expected_zi += hp.pad_len((num_chunks + 1) * hp.CHUNK_SIZE)
        check(
            "reference ziChunkTableOffset follows chunk table",
            zi_off == expected_zi,
            "0x{:x} vs 0x{:x}".format(zi_off, expected_zi),
        )
        # hart[0].name sits at prefix + 40 within the hart struct
        name_off = hp.BOOTIMAGE_PREFIX_SIZE + 40
        end = data.index(b"\x00", name_off)
        name = data[name_off:end].decode("utf-8", "replace")
        check(
            "reference hart[0].name lands at the expected offset",
            name.endswith(".elf"),
            repr(name),
        )
    else:
        print("  SKIP  reference payload.bin not present")


def test_crc32() -> None:
    print("\n[crc32]")
    # The HSS CRC32 is the standard reflected IEEE 802.3 CRC with init 0.
    check("crc32('') == 0", hp.crc32_hss(b"") == 0)
    check(
        "crc32('123456789') == 0xcbf43926",
        hp.crc32_hss(b"123456789") == 0xCBF43926,
        hex(hp.crc32_hss(b"123456789")),
    )
    check(
        "crc32('The quick brown fox jumps over the lazy dog') == 0x414fa339",
        hp.crc32_hss(b"The quick brown fox jumps over the lazy dog") == 0x414FA339,
    )


def test_real_config_parses() -> None:
    print("\n[real hss-payload.yaml]")
    if not REAL_CONFIG.is_file():
        print("  SKIP  {} not present".format(REAL_CONFIG))
        return
    cfg = hp.parse_config(REAL_CONFIG)
    check("set-name parsed", cfg.set_name == "PIC64GX-HSS::ZephyrSMP", cfg.set_name)
    check("four hart entry points", len(cfg.entry_points) == 4, str(cfg.entry_points))
    check(
        "all entry points are 0x80000000",
        all(v == 0x80000000 for v in cfg.entry_points.values()),
    )
    check("exactly one payload", len(cfg.payloads) == 1, str(len(cfg.payloads)))
    spec = cfg.payloads[0]
    check("owner is u54_1", spec.owner == 1, str(spec.owner))
    # This is the important one: the config repeats `secondary-hart` three times.
    # A conventional YAML loader would collapse those duplicate keys and silently
    # drop two harts. libyaml streams events, so all three are honoured.
    check(
        "all three duplicate secondary-hart keys preserved",
        spec.secondary == [2, 3, 4],
        str(spec.secondary),
    )
    check("priv-mode is prv_m", spec.priv_mode == hp.PRV_M, str(spec.priv_mode))
    check("skip-opensbi set", spec.skip_opensbi is True)
    check("allow-reboot cold set", spec.allow_cold_reboot is True)


def test_build_from_synthetic_elfs(tmp: Path) -> dict:
    print("\n[image construction]")
    for name, (sections, segments) in CASES.items():
        (tmp / name).write_bytes(build_elf(sections, segments))

    configs = _write_configs(tmp)
    images = {}

    for label, cfg_path in configs.items():
        cfg = hp.parse_config(cfg_path)
        image = hp.build_image(cfg, tmp)
        images[label] = image

        magic, _v, header_len, header_crc, chunk_off, zi_off = struct.unpack_from(
            hp.BOOTIMAGE_PREFIX_FMT, image, 0
        )
        check("{}: magic correct".format(label), magic == hp.HSS_BOOT_MAGIC)
        check(
            "{}: chunkTableOffset is 8-byte aligned".format(label), chunk_off % 8 == 0
        )
        check(
            "{}: ziChunkTableOffset > chunkTableOffset".format(label),
            zi_off > chunk_off,
        )
        check("{}: headerLength within image".format(label), header_len <= len(image))
        check("{}: image length is a multiple of 8".format(label), len(image) % 8 == 0)

        # headerCrc must validate: recompute over the header with the CRC slot
        # zeroed. headerCrc sits at offset 16 (after magic, version, headerLength);
        # bytes 20..24 are alignment padding for the size_t that follows.
        header = bytearray(image[: hp.BOOTIMAGE_SIZE])
        header[16:20] = b"\x00\x00\x00\x00"
        check(
            "{}: headerCrc validates".format(label),
            hp.crc32_hss(bytes(header)) == header_crc,
        )

        # every chunk's stored crc32 must match its blob, and loadAddr must point
        # at the blob inside the file
        off = chunk_off
        chunk_ok = True
        crc_ok = True
        while off + hp.CHUNK_SIZE <= zi_off:
            owner, _p1, load, _exec, size, crc, _p2 = struct.unpack_from(
                hp.CHUNK_FMT, image, off
            )
            if size == 0:
                break
            blob = image[load : load + size]
            if len(blob) != size:
                chunk_ok = False
            elif hp.crc32_hss(blob) != crc:
                crc_ok = False
            off += hp.CHUNK_SIZE
        check("{}: all chunk blobs inside image".format(label), chunk_ok)
        check("{}: all chunk CRCs match their data".format(label), crc_ok)

        # determinism
        again = hp.build_image(hp.parse_config(cfg_path), tmp)
        check("{}: output is deterministic".format(label), again == image)

    return images


def _write_configs(tmp: Path) -> dict:
    simple = tmp / "simple.yaml"
    simple.write_text(
        "set-name: 'PIC64GX-HSS::ZephyrSMP'\n"
        "hart-entry-points: {u54_1: '0x80000000', u54_2: '0x80000000', "
        "u54_3: '0x80000000', u54_4: '0x80000000'}\n"
        "payloads:\n"
        "  simple.elf:\n"
        "    exec-addr: '0x80000000'\n"
        "    owner-hart: u54_1\n"
        "    secondary-hart: u54_2\n"
        "    secondary-hart: u54_3\n"
        "    secondary-hart: u54_4\n"
        "    priv-mode: prv_m\n"
        "    skip-opensbi: true\n"
        "    allow-reboot: cold\n",
        encoding="utf-8",
    )

    multi = tmp / "multi.yaml"
    multi.write_text(
        "set-name: 'PIC64GX-HSS::Multi'\n"
        "hart-entry-points: {u54_1: '0x80000000', u54_2: '0x80000000', "
        "u54_3: '0x80000000', u54_4: '0x80000000'}\n"
        "payloads:\n"
        "  multi.elf:\n"
        "    exec-addr: '0x80000000'\n"
        "    owner-hart: u54_1\n"
        "    secondary-hart: u54_2\n"
        "    secondary-hart: u54_3\n"
        "    secondary-hart: u54_4\n"
        "    priv-mode: prv_m\n"
        "    skip-opensbi: true\n"
        "    allow-reboot: cold\n",
        encoding="utf-8",
    )

    # Two payloads, flow mappings, payload-name, warm reboot, skip-autoboot,
    # a section covered by two segments, and a hart left unclaimed (PRV_ILLEGAL).
    overlap = tmp / "overlap.yaml"
    overlap.write_text(
        "hart-entry-points: {u54_1: '0x80000000', u54_3: '0xB0000000'}\n"
        "payloads:\n"
        "  overlap.elf: {exec-addr: '0xB0000000', owner-hart: u54_3, "
        "priv-mode: prv_s, allow-reboot: warm, payload-name: 'overlapper'}\n"
        "  multi.elf: {owner-hart: u54_1, secondary-hart: u54_2, "
        "priv-mode: prv_m, skip-opensbi: true, skip-autoboot: true}\n",
        encoding="utf-8",
    )

    # The repository's real config, retargeted at a synthetic ELF.
    real = tmp / "real.yaml"
    if REAL_CONFIG.is_file():
        text = REAL_CONFIG.read_text(encoding="utf-8").replace(
            "zephyr.elf:", "multi.elf:"
        )
        real.write_text(text, encoding="utf-8")
        return {
            "simple": simple,
            "multi": multi,
            "overlap": overlap,
            "real": real,
        }
    return {"simple": simple, "multi": multi, "overlap": overlap}


def test_flag_and_priv_encoding(tmp: Path) -> None:
    print("\n[flags and priv modes]")
    cfg = hp.parse_config(tmp / "overlap.yaml")
    image = hp.build_image(cfg, tmp)

    def hart(idx: int):
        off = hp.BOOTIMAGE_PREFIX_SIZE + idx * hp.HART_SIZE
        entry, priv, flags = struct.unpack_from("<QBB", image, off)
        return entry, priv, flags

    _e1, priv1, flags1 = hart(0)
    _e2, priv2, flags2 = hart(1)
    _e3, priv3, flags3 = hart(2)
    _e4, priv4, flags4 = hart(3)

    check("u54_1 priv is PRV_M", priv1 == hp.PRV_M, hex(priv1))
    check("u54_2 inherits PRV_M as secondary", priv2 == hp.PRV_M, hex(priv2))
    check("u54_3 priv is PRV_S", priv3 == hp.PRV_S, hex(priv3))
    # No payload claims u54_4, so it must stay PRV_ILLEGAL. The C tool leaves the
    # initialised 0xff in place; writing PRV_M here would be wrong.
    check("unclaimed u54_4 stays PRV_ILLEGAL", priv4 == hp.PRV_ILLEGAL, hex(priv4))

    expect_owner = hp.BOOT_FLAG_SKIP_OPENSBI | hp.BOOT_FLAG_SKIP_AUTOBOOT
    check("u54_1 flags skip-opensbi|skip-autoboot", flags1 == expect_owner, hex(flags1))
    check("u54_2 inherits owner flags", flags2 == expect_owner, hex(flags2))
    check(
        "u54_3 flags warm reboot only",
        flags3 == hp.BOOT_FLAG_ALLOW_WARM_REBOOT,
        hex(flags3),
    )
    check("unclaimed u54_4 flags are zero", flags4 == 0, hex(flags4))

    # cold reboot must imply warm reboot
    cfg2 = hp.parse_config(tmp / "simple.yaml")
    image2 = hp.build_image(cfg2, tmp)
    _e, _p, flags = struct.unpack_from("<QBB", image2, hp.BOOTIMAGE_PREFIX_SIZE)
    expect = (
        hp.BOOT_FLAG_SKIP_OPENSBI
        | hp.BOOT_FLAG_ALLOW_COLD_REBOOT
        | hp.BOOT_FLAG_ALLOW_WARM_REBOOT
    )
    check("cold reboot implies warm reboot (flags 0x70)", flags == expect, hex(flags))


def test_windows_style_paths(tmp: Path) -> None:
    print("\n[windows path handling]")
    # A payload key on Windows looks like C:/build/zephyr.elf. Splitting the line
    # at the first colon would make the key "C", so the drive letter must be
    # skipped. This is the exact failure seen when payload.ps1 rewrites the
    # config with an absolute path.
    key, sep, value = hp._split_key_value("  C:/build/zephyr.elf:")
    check(
        "drive-letter key parses",
        key.strip() == "C:/build/zephyr.elf" and sep == ":",
        repr(key),
    )

    key, sep, value = hp._split_key_value(
        "  C:\\build\\zephyr.elf: {owner-hart: u54_1}"
    )
    check(
        "backslash drive-letter key parses",
        key.strip() == "C:\\build\\zephyr.elf"
        and value.strip() == "{owner-hart: u54_1}",
        repr(key),
    )

    key, sep, value = hp._split_key_value("exec-addr: '0x80000000'")
    check(
        "plain key still parses",
        key == "exec-addr" and value.strip() == "'0x80000000'",
        repr(key),
    )

    key, sep, value = hp._split_key_value("'quoted: key': value")
    check("quoted key parses", key.strip() == "'quoted: key'", repr(key))

    # end to end: a config using an absolute Windows-style path
    elf = tmp / "winpath.elf"
    elf.write_bytes(build_elf(*CASES["simple.elf"]))
    win_style = str(elf).replace("\\", "/")
    cfg = tmp / "winpath.yaml"
    # built by concatenation: the flow mapping braces would be read as format
    # placeholders by str.format
    cfg.write_text(
        "set-name: 'PIC64GX-HSS::WinPath'\n"
        "hart-entry-points: {u54_1: '0x80000000'}\n"
        "payloads:\n"
        "  " + win_style + ":\n"
        "    exec-addr: '0x80000000'\n"
        "    owner-hart: u54_1\n"
        "    priv-mode: prv_m\n"
        "    skip-opensbi: true\n",
        encoding="utf-8",
    )
    try:
        parsed = hp.parse_config(cfg)
        ok_path = parsed.payloads[0].path == win_style
        image = hp.build_image(parsed, tmp)
        check("absolute path config parses and builds", ok_path and len(image) > 0)
    except hp.PayloadError as exc:
        check("absolute path config parses and builds", False, str(exc))


def test_rejects_bad_input(tmp: Path) -> None:
    print("\n[error handling]")

    not_elf = tmp / "notanelf.elf"
    not_elf.write_bytes(b"this is not an ELF file at all, not even close")
    cfg = tmp / "bad1.yaml"
    cfg.write_text(
        "hart-entry-points: {u54_1: '0x80000000'}\n"
        "payloads:\n"
        "  notanelf.elf: {owner-hart: u54_1, priv-mode: prv_m}\n",
        encoding="utf-8",
    )
    try:
        hp.build_image(hp.parse_config(cfg), tmp)
        check("rejects non-ELF payload", False, "no error raised")
    except hp.PayloadError:
        check("rejects non-ELF payload", True)

    # x86_64 ELF must be refused: only RISC-V payloads are valid
    x86 = tmp / "x86.elf"
    raw = bytearray(build_elf(*CASES["simple.elf"]))
    raw[18:20] = struct.pack("<H", 0x3E)  # EM_X86_64
    x86.write_bytes(bytes(raw))
    cfg = tmp / "bad2.yaml"
    cfg.write_text(
        "hart-entry-points: {u54_1: '0x80000000'}\n"
        "payloads:\n"
        "  x86.elf: {owner-hart: u54_1, priv-mode: prv_m}\n",
        encoding="utf-8",
    )
    try:
        hp.build_image(hp.parse_config(cfg), tmp)
        check("rejects non-RISC-V ELF", False, "no error raised")
    except hp.PayloadError:
        check("rejects non-RISC-V ELF", True)

    cfg = tmp / "bad3.yaml"
    cfg.write_text(
        "hart-entry-points: {u54_1: '0x80000000'}\n"
        "payloads:\n"
        "  simple.elf: {priv-mode: prv_m}\n",
        encoding="utf-8",
    )
    try:
        hp.build_image(hp.parse_config(cfg), tmp)
        check("rejects payload without owner-hart", False, "no error raised")
    except hp.PayloadError:
        check("rejects payload without owner-hart", True)

    cfg = tmp / "bad4.yaml"
    cfg.write_text(
        "hart-entry-points: {u54_1: '0x80000000'}\n"
        "payloads:\n"
        "  simple.elf: {owner-hart: u54_1, ancilliary-data: foo.dtb}\n",
        encoding="utf-8",
    )
    try:
        hp.parse_config(cfg)
        check("rejects unsupported ancilliary-data", False, "no error raised")
    except hp.PayloadError:
        check("rejects unsupported ancilliary-data", True)

    cfg = tmp / "bad5.yaml"
    cfg.write_text(
        "hart-entry-points: {u54_9: '0x80000000'}\npayloads:\n  simple.elf: {}\n",
        encoding="utf-8",
    )
    try:
        hp.parse_config(cfg)
        check("rejects invalid hart token", False, "no error raised")
    except hp.PayloadError:
        check("rejects invalid hart token", True)

    missing = tmp / "bad6.yaml"
    missing.write_text(
        "hart-entry-points: {u54_1: '0x80000000'}\n"
        "payloads:\n"
        "  does_not_exist.elf: {owner-hart: u54_1}\n",
        encoding="utf-8",
    )
    try:
        hp.build_image(hp.parse_config(missing), tmp)
        check("reports missing payload file", False, "no error raised")
    except hp.PayloadError:
        check("reports missing payload file", True)


def test_against_reference(tmp: Path, reference: Path, images: dict) -> None:
    print("\n[differential vs official hss-payload-generator]")
    print("  tool: {}".format(reference))

    for label in images:
        cfg = tmp / "{}.yaml".format(label)
        if not cfg.is_file():
            continue
        ref_out = tmp / "ref_{}.bin".format(label)
        try:
            proc = subprocess.run(
                [str(reference), "-c", cfg.name, ref_out.name],
                cwd=str(tmp),
                capture_output=True,
                text=True,
                timeout=120,
            )
        except (OSError, subprocess.SubprocessError) as exc:
            check("{}: reference tool runs".format(label), False, str(exc))
            continue

        if proc.returncode != 0 or not ref_out.is_file():
            check(
                "{}: reference tool runs".format(label),
                False,
                (proc.stderr or proc.stdout or "").strip()[:200],
            )
            continue

        ref = ref_out.read_bytes()
        cand = images[label]

        check(
            "{}: same image length".format(label),
            len(ref) == len(cand),
            "{} vs {}".format(len(ref), len(cand)),
        )
        if len(ref) != len(cand):
            continue

        ref_crc = struct.unpack_from(hp.BOOTIMAGE_PREFIX_FMT, ref, 0)[3]
        cand_crc = struct.unpack_from(hp.BOOTIMAGE_PREFIX_FMT, cand, 0)[3]
        check(
            "{}: identical headerCrc".format(label),
            ref_crc == cand_crc,
            "0x{:08x} vs 0x{:08x}".format(ref_crc, cand_crc),
        )

        nref, ncand = normalise(ref), normalise(cand)
        diffs = [i for i in range(len(nref)) if nref[i] != ncand[i]]
        check(
            "{}: byte-identical after padding normalisation".format(label),
            not diffs,
            "{} differences, first at {}".format(len(diffs), diffs[:8]),
        )


# ---------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verify the portable HSS payload generator."
    )
    parser.add_argument(
        "--reference",
        default=None,
        help="path to the official hss-payload-generator for a differential test",
    )
    parser.add_argument(
        "--keep", action="store_true", help="keep the scratch directory"
    )
    args = parser.parse_args()

    print("Portable HSS payload generator test suite")
    print("Python {}".format(sys.version.split()[0]))
    print("Platform {}".format(sys.platform))

    tmp = Path(tempfile.mkdtemp(prefix="hss_payload_test_"))
    try:
        test_struct_layout()
        test_crc32()
        test_real_config_parses()
        images = test_build_from_synthetic_elfs(tmp)
        test_flag_and_priv_encoding(tmp)
        test_windows_style_paths(tmp)
        test_rejects_bad_input(tmp)

        if args.reference:
            ref = Path(args.reference)
            if not ref.is_file():
                found = shutil.which(args.reference)
                ref = Path(found) if found else ref
            if ref.is_file():
                test_against_reference(tmp, ref, images)
            else:
                print("\n[differential vs official hss-payload-generator]")
                print("  SKIP  reference tool not found: {}".format(args.reference))
        else:
            print("\n[differential vs official hss-payload-generator]")
            print("  SKIP  pass --reference <hss-payload-generator> to enable")
    finally:
        if args.keep:
            print("\nscratch directory kept at {}".format(tmp))
        else:
            shutil.rmtree(tmp, ignore_errors=True)

    total = len(PASSED) + len(FAILED)
    print("\n{} passed, {} failed, {} total".format(len(PASSED), len(FAILED), total))
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
