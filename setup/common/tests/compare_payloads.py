#!/usr/bin/env python3
# Copyright (c) 2026 Microchip Technology Inc
# SPDX-License-Identifier: MIT
#
# Compare two HSS payload images and report semantic differences.
#
# Byte-exact comparison is not meaningful for the upstream C generator. Its
# struct HSS_BootChunkDesc / HSS_BootZIChunkDesc have 4 bytes of padding after
# the `enum HSSHartId owner` field, and the C tool writes those descriptors from
# partially initialised stack storage. The padding therefore contains leftover
# stack garbage that differs per platform and per run:
#
#   Windows build of the official tool : 0a 00 00 00
#   Linux build (this repo's payload)  : fc 7f 00 00   (a stack address fragment)
#
# The padding belongs to no struct field, the HSS bootloader never reads it, and
# headerCrc only covers the header, not the chunk tables. This script normalises
# those padding slots to zero and then requires everything else to match byte
# for byte.

from __future__ import annotations

import struct
import sys
from pathlib import Path

BOOTIMAGE_SIZE = 1632
CHUNK_SIZE = 40
ZI_SIZE = 24
PREFIX_FMT = "<IIQI4xQQ"


def normalise(data: bytes) -> bytes:
    out = bytearray(data)
    magic, version, header_len, header_crc, chunk_off, zi_off = struct.unpack_from(
        PREFIX_FMT, out, 0
    )
    if magic != 0xB007C0DE:
        raise SystemExit("not an HSS payload image (magic 0x{:08x})".format(magic))

    # zero both padding slots in every chunk descriptor: the 4 bytes after
    # `owner`, and the 4 trailing bytes after `crc32`
    off = chunk_off
    while off + CHUNK_SIZE <= zi_off:
        out[off + 4 : off + 8] = b"\x00\x00\x00\x00"
        out[off + 36 : off + 40] = b"\x00\x00\x00\x00"
        off += CHUNK_SIZE

    # and in every ZI chunk descriptor
    off = zi_off
    while off + ZI_SIZE <= header_len:
        out[off + 4 : off + 8] = b"\x00\x00\x00\x00"
        off += ZI_SIZE

    return bytes(out)


def describe(data: bytes) -> str:
    magic, version, header_len, header_crc, chunk_off, zi_off = struct.unpack_from(
        PREFIX_FMT, data, 0
    )
    num_chunks = (zi_off - chunk_off) // CHUNK_SIZE - 1
    num_zi = (header_len - zi_off) // ZI_SIZE - 1
    return (
        "{} bytes, headerLength=0x{:x}, headerCrc=0x{:08x}, "
        "chunks={}, ziChunks={}".format(
            len(data), header_len, header_crc, num_chunks, num_zi
        )
    )


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write("usage: compare_payloads.py <reference.bin> <candidate.bin>\n")
        return 2

    ref_path, cand_path = Path(sys.argv[1]), Path(sys.argv[2])
    ref, cand = ref_path.read_bytes(), cand_path.read_bytes()

    print("reference: {}  {}".format(ref_path.name, describe(ref)))
    print("candidate: {}  {}".format(cand_path.name, describe(cand)))

    if len(ref) != len(cand):
        print("FAIL: length differs ({} vs {})".format(len(ref), len(cand)))
        return 1

    nref, ncand = normalise(ref), normalise(cand)
    diffs = [i for i in range(len(nref)) if nref[i] != ncand[i]]

    raw_diffs = sum(1 for i in range(len(ref)) if ref[i] != cand[i])
    print(
        "raw byte differences:        {} (includes uninitialised struct padding)".format(
            raw_diffs
        )
    )
    print("differences after normalise: {}".format(len(diffs)))

    if diffs:
        print("FAIL: first offsets {}".format(diffs[:20]))
        for off in diffs[:5]:
            lo = max(0, off - 8)
            print(
                "  @0x{:x} ref={} cand={}".format(
                    off, ref[lo : off + 8].hex(" "), cand[lo : off + 8].hex(" ")
                )
            )
        return 1

    print("PASS: payloads are semantically identical")
    return 0


if __name__ == "__main__":
    sys.exit(main())
