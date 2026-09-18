#!/usr/bin/env python3
# Copyright (c) 2026 Microchip Technology Inc
# SPDX-License-Identifier: MIT
#
# Build synthetic RISC-V ET_EXEC ELF files for testing hss_payload.py against
# the upstream hss-payload-generator. These are not runnable images; they only
# need a valid enough structure for the payload generator to walk.

from __future__ import annotations

import struct
import sys
from pathlib import Path

EM_RISCV = 243
ET_EXEC = 2
PT_LOAD = 1
SHT_PROGBITS = 1
SHT_NOBITS = 8
SHT_STRTAB = 3
SHF_ALLOC = 0x2
SHF_EXECINSTR = 0x4
SHF_WRITE = 0x1

EHDR_SIZE = 64
PHDR_SIZE = 56
SHDR_SIZE = 64


def build_elf(sections, segments, entry=0x80000000):
    """sections: list of (name, sh_type, addr, size, flags)
    segments: list of (p_type, vaddr, memsz)
    """
    names = [""] + [s[0] for s in sections] + [".shstrtab"]
    shstrtab = bytearray()
    offsets = {}
    for name in names:
        offsets[name] = len(shstrtab)
        shstrtab += name.encode() + b"\x00"

    num_sections = len(sections) + 2  # NULL + payload sections + shstrtab
    body_start = EHDR_SIZE + len(segments) * PHDR_SIZE

    # lay out section data
    data_blobs = []
    cursor = body_start
    sec_records = []
    for idx, (name, sh_type, addr, size, flags) in enumerate(sections):
        if sh_type == SHT_NOBITS:
            sec_records.append((name, sh_type, addr, cursor, size, flags))
            continue
        blob = bytes(((idx * 37 + i * 11) & 0xFF) for i in range(size))
        data_blobs.append((cursor, blob))
        sec_records.append((name, sh_type, addr, cursor, size, flags))
        cursor += size

    shstrtab_off = cursor
    data_blobs.append((shstrtab_off, bytes(shstrtab)))
    cursor += len(shstrtab)

    # align section header table
    pad = (8 - (cursor % 8)) % 8
    if pad:
        data_blobs.append((cursor, b"\x00" * pad))
        cursor += pad
    shoff = cursor

    out = bytearray()
    out += b"\x7fELF" + bytes([2, 1, 1, 0]) + b"\x00" * 8
    out += struct.pack(
        "<HHIQQQIHHHHHH",
        ET_EXEC,
        EM_RISCV,
        1,
        entry,
        EHDR_SIZE if segments else 0,
        shoff,
        0,
        EHDR_SIZE,
        PHDR_SIZE,
        len(segments),
        SHDR_SIZE,
        num_sections,
        num_sections - 1,  # shstrndx
    )

    for p_type, vaddr, memsz in segments:
        out += struct.pack(
            "<IIQQQQQQ", p_type, 0x5, 0, vaddr, vaddr, memsz, memsz, 0x1000
        )

    for off, blob in sorted(data_blobs):
        if len(out) < off:
            out += b"\x00" * (off - len(out))
        out[off : off + len(blob)] = blob

    if len(out) < shoff:
        out += b"\x00" * (shoff - len(out))

    # NULL section
    out += b"\x00" * SHDR_SIZE
    for name, sh_type, addr, off, size, flags in sec_records:
        out += struct.pack(
            "<IIQQQQIIQQ",
            offsets[name],
            sh_type,
            flags,
            addr,
            off,
            0 if sh_type == SHT_NOBITS else size,
            0,
            0,
            8,
            0,
        )
        # sh_size lives at a fixed slot; patch NOBITS size back in
        if sh_type == SHT_NOBITS:
            out[-64 + 32 : -64 + 40] = struct.pack("<Q", size)
    out += struct.pack(
        "<IIQQQQIIQQ",
        offsets[".shstrtab"],
        SHT_STRTAB,
        0,
        0,
        shstrtab_off,
        len(shstrtab),
        0,
        0,
        1,
        0,
    )
    return bytes(out)


CASES = {
    # simple: one segment, one code section, one bss
    "simple.elf": (
        [
            (".text", SHT_PROGBITS, 0x80000000, 0x200, SHF_ALLOC | SHF_EXECINSTR),
            (".bss", SHT_NOBITS, 0x80000200, 0x100, SHF_ALLOC | SHF_WRITE),
        ],
        [(PT_LOAD, 0x80000000, 0x300)],
    ),
    # multi segment with several progbits and nobits, odd sizes to exercise padding
    "multi.elf": (
        [
            (".text", SHT_PROGBITS, 0x80000000, 0x155, SHF_ALLOC | SHF_EXECINSTR),
            (".rodata", SHT_PROGBITS, 0x80000160, 0x33, SHF_ALLOC),
            (".data", SHT_PROGBITS, 0x80001000, 0x7, SHF_ALLOC | SHF_WRITE),
            (".bss", SHT_NOBITS, 0x80001008, 0x2001, SHF_ALLOC | SHF_WRITE),
            (".noinit", SHT_NOBITS, 0x80004000, 0x40, SHF_ALLOC | SHF_WRITE),
        ],
        [
            (PT_LOAD, 0x80000000, 0x200),
            (PT_LOAD, 0x80001000, 0x3010),
            (PT_LOAD, 0x80004000, 0x40),
        ],
    ),
    # a section covered by two overlapping segments, plus a zero-size section
    "overlap.elf": (
        [
            (".text", SHT_PROGBITS, 0x80000000, 0x80, SHF_ALLOC | SHF_EXECINSTR),
            (".empty", SHT_PROGBITS, 0x80000080, 0x0, SHF_ALLOC),
            (".data", SHT_PROGBITS, 0x80000090, 0x11, SHF_ALLOC | SHF_WRITE),
            (".bss", SHT_NOBITS, 0x800000B0, 0x9, SHF_ALLOC | SHF_WRITE),
        ],
        [
            (PT_LOAD, 0x80000000, 0x100),
            (PT_LOAD, 0x80000000, 0x100),
            (0x6474E551, 0x80000000, 0x100),  # PT_GNU_STACK, must be ignored
        ],
    ),
}


def main() -> int:
    out_dir = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, (sections, segments) in CASES.items():
        path = out_dir / name
        path.write_bytes(build_elf(sections, segments))
        print("wrote {} ({} bytes)".format(path, path.stat().st_size))
    return 0


if __name__ == "__main__":
    sys.exit(main())
