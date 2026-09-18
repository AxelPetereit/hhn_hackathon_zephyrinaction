#!/usr/bin/env python3
# Copyright (c) 2026 Microchip Technology Inc
# SPDX-License-Identifier: MIT
#
# Portable HSS payload generator.
#
# This is a clean-room Python implementation of the payload image writer from
# polarfire-soc/hart-software-services (tools/hss-payload-generator), which is
# MIT licensed. It produces byte-identical output to the upstream C tool for the
# ELF payload configurations used by this repository.
#
# Why this exists: the upstream release ships a Windows .exe and a Linux x86_64
# ELF binary. There is no macOS build, and building from source on macOS is
# blocked because it needs libelf/gelf.h from elfutils (Linux-only in Homebrew)
# and a GCC-only -Werror flag set. This script removes that dependency and runs
# the same way on Windows, Linux and macOS with nothing but CPython >= 3.8.
#
# Supported subset (sufficient for PIC64GX Zephyr payloads):
#   set-name, hart-entry-points, payloads with ELF files,
#   exec-addr, owner-hart, secondary-hart, priv-mode, skip-opensbi,
#   allow-reboot, skip-autoboot, payload-name
# Not supported: raw binary blobs, ancilliary-data, secure boot signing.
# Those paths are rejected explicitly rather than written incorrectly.

from __future__ import annotations

import argparse
import re
import struct
import sys
import zlib
from dataclasses import dataclass, field
from pathlib import Path

# ---------------------------------------------------------------------------
# Constants mirrored from include/hss_types.h
# ---------------------------------------------------------------------------

HSS_BOOT_MAGIC = 0xB007C0DE
HSS_BOOT_VERSION = 1
BOOT_IMAGE_MAX_NAME_LEN = 256
MAX_NUM_HARTS = 5  # E51 + 4x U54
NUM_U54 = MAX_NUM_HARTS - 1
PAD_SIZE = 8

BOOT_FLAG_ANCILLIARY_DATA = 0x80
BOOT_FLAG_SKIP_OPENSBI = 0x40
BOOT_FLAG_ALLOW_COLD_REBOOT = 0x20
BOOT_FLAG_ALLOW_WARM_REBOOT = 0x10
BOOT_FLAG_SKIP_AUTOBOOT = 0x08

PRV_U, PRV_S, PRV_M, PRV_ILLEGAL = 0x00, 0x01, 0x03, 0xFF
PRIV_MODES = {"prv_u": PRV_U, "prv_s": PRV_S, "prv_m": PRV_M}

# ELF constants
ELF_MAGIC = b"\x7fELF"
EM_RISCV = 243
ET_EXEC = 2
PT_LOAD = 1
SHT_NOBITS = 8

# struct HSS_BootChunkDesc under #pragma pack(8) on a 64-bit LP64 target:
#   enum HSSHartId owner  -> 4 bytes + 4 padding
#   uintptr_t loadAddr    -> 8
#   uintptr_t execAddr    -> 8
#   size_t size           -> 8
#   uint32_t crc32        -> 4 + 4 trailing padding
# => 40 bytes
CHUNK_FMT = "<IIQQQII"
CHUNK_SIZE = struct.calcsize(CHUNK_FMT)
assert CHUNK_SIZE == 40, CHUNK_SIZE

# struct HSS_BootZIChunkDesc: enum + 4 pad + void* + size_t => 24 bytes
ZI_FMT = "<IIQQ"
ZI_SIZE = struct.calcsize(ZI_FMT)
assert ZI_SIZE == 24, ZI_SIZE

# Per-hart sub-struct of HSS_BootImage:
#   uintptr_t entryPoint -> 8
#   uint8_t privMode     -> 1
#   uint8_t flags        -> 1  (+6 padding to align the following size_t)
#   size_t numChunks     -> 8
#   size_t firstChunk    -> 8
#   size_t lastChunk     -> 8
#   char name[256]       -> 256
# => 296 bytes
HART_FMT = "<QBB6xQQQ{}s".format(BOOT_IMAGE_MAX_NAME_LEN)
HART_SIZE = struct.calcsize(HART_FMT)
assert HART_SIZE == 296, HART_SIZE

# struct HSS_BootImage:
#   uint32_t magic             -> 4
#   uint32_t version           -> 4
#   size_t   headerLength      -> 8
#   uint32_t headerCrc         -> 4 (+4 padding)
#   size_t   chunkTableOffset  -> 8
#   size_t   ziChunkTableOffset-> 8
#   hart[4]                    -> 4 * 296 = 1184
#   char set_name[256]         -> 256
#   size_t bootImageLength     -> 8
#   struct HSS_Signature       -> 48 + 96 = 144
# => 40 + 1184 + 256 + 8 + 144 = 1632
BOOTIMAGE_PREFIX_FMT = "<IIQI4xQQ"
BOOTIMAGE_PREFIX_SIZE = struct.calcsize(BOOTIMAGE_PREFIX_FMT)
assert BOOTIMAGE_PREFIX_SIZE == 40, BOOTIMAGE_PREFIX_SIZE
BOOTIMAGE_SIZE = (
    BOOTIMAGE_PREFIX_SIZE + NUM_U54 * HART_SIZE + BOOT_IMAGE_MAX_NAME_LEN + 8 + 48 + 96
)
assert BOOTIMAGE_SIZE == 1632, BOOTIMAGE_SIZE


def crc32_hss(data: bytes) -> int:
    """CRC32 as used by the HSS tools.

    crc32.c seeds with 0, computes crc = ~seed, folds bytes through the
    standard reflected IEEE 802.3 table, then returns ~crc. That is exactly
    the conventional zlib.crc32 with an initial value of 0.
    """
    return zlib.crc32(data) & 0xFFFFFFFF


def pad_len(size: int, pad: int = PAD_SIZE) -> int:
    return (((size + (pad - 1)) // pad) * pad) - size


def c_str(text: str, size: int) -> bytes:
    """Emulate strncpy into a fixed char[size] buffer, NUL padded."""
    raw = text.encode("utf-8", errors="replace")[: size - 1]
    return raw + b"\x00" * (size - len(raw))


class PayloadError(RuntimeError):
    pass


# ---------------------------------------------------------------------------
# Minimal ELF reader (64-bit and 32-bit, little and big endian)
# ---------------------------------------------------------------------------


@dataclass
class ElfSection:
    name: str
    sh_type: int
    sh_addr: int
    sh_offset: int
    sh_size: int


@dataclass
class ElfSegment:
    p_type: int
    p_vaddr: int
    p_memsz: int


class ElfFile:
    def __init__(self, path: Path):
        self.path = path
        self.data = path.read_bytes()
        if len(self.data) < 64 or self.data[:4] != ELF_MAGIC:
            raise PayloadError("{}: not an ELF object".format(path))

        ei_class = self.data[4]
        ei_data = self.data[5]
        if ei_class not in (1, 2):
            raise PayloadError("{}: invalid ELF class {}".format(path, ei_class))
        self.is64 = ei_class == 2
        self.end = "<" if ei_data == 1 else ">"

        if self.is64:
            (
                self.e_type,
                self.e_machine,
                _e_version,
                self.e_entry,
                e_phoff,
                e_shoff,
                _e_flags,
                _e_ehsize,
                e_phentsize,
                e_phnum,
                e_shentsize,
                e_shnum,
                e_shstrndx,
            ) = struct.unpack_from(self.end + "HHIQQQIHHHHHH", self.data, 16)
        else:
            (
                self.e_type,
                self.e_machine,
                _e_version,
                self.e_entry,
                e_phoff,
                e_shoff,
                _e_flags,
                _e_ehsize,
                e_phentsize,
                e_phnum,
                e_shentsize,
                e_shnum,
                e_shstrndx,
            ) = struct.unpack_from(self.end + "HHIIIIIHHHHHH", self.data, 16)

        if self.e_machine != EM_RISCV:
            raise PayloadError(
                "{}: machine type is {}, only RISC-V payloads are supported".format(
                    path, self.e_machine
                )
            )
        if self.e_type != ET_EXEC:
            raise PayloadError(
                "{}: ELF type is {}, only executable payloads are supported".format(
                    path, self.e_type
                )
            )

        self.segments = self._read_segments(e_phoff, e_phentsize, e_phnum)
        self.sections = self._read_sections(e_shoff, e_shentsize, e_shnum, e_shstrndx)

    def _read_segments(self, off: int, entsize: int, num: int):
        out = []
        for i in range(num):
            base = off + i * entsize
            if self.is64:
                p_type = struct.unpack_from(self.end + "I", self.data, base)[0]
                p_vaddr = struct.unpack_from(self.end + "Q", self.data, base + 16)[0]
                p_memsz = struct.unpack_from(self.end + "Q", self.data, base + 40)[0]
            else:
                p_type = struct.unpack_from(self.end + "I", self.data, base)[0]
                p_vaddr = struct.unpack_from(self.end + "I", self.data, base + 8)[0]
                p_memsz = struct.unpack_from(self.end + "I", self.data, base + 20)[0]
            out.append(ElfSegment(p_type, p_vaddr, p_memsz))
        return out

    def _read_sections(self, off: int, entsize: int, num: int, shstrndx: int):
        raw = []
        for i in range(num):
            base = off + i * entsize
            if self.is64:
                sh_name, sh_type = struct.unpack_from(self.end + "II", self.data, base)
                sh_addr = struct.unpack_from(self.end + "Q", self.data, base + 16)[0]
                sh_offset = struct.unpack_from(self.end + "Q", self.data, base + 24)[0]
                sh_size = struct.unpack_from(self.end + "Q", self.data, base + 32)[0]
            else:
                sh_name, sh_type = struct.unpack_from(self.end + "II", self.data, base)
                sh_addr = struct.unpack_from(self.end + "I", self.data, base + 12)[0]
                sh_offset = struct.unpack_from(self.end + "I", self.data, base + 16)[0]
                sh_size = struct.unpack_from(self.end + "I", self.data, base + 20)[0]
            raw.append((sh_name, sh_type, sh_addr, sh_offset, sh_size))

        strtab = b""
        if 0 <= shstrndx < len(raw):
            _n, _t, _a, s_off, s_size = raw[shstrndx]
            strtab = self.data[s_off : s_off + s_size]

        out = []
        for sh_name, sh_type, sh_addr, sh_offset, sh_size in raw:
            end = strtab.find(b"\x00", sh_name)
            name = strtab[sh_name : end if end >= 0 else None].decode(
                "utf-8", errors="replace"
            )
            out.append(ElfSection(name, sh_type, sh_addr, sh_offset, sh_size))
        return out

    def section_bytes(self, section: ElfSection) -> bytes:
        return self.data[section.sh_offset : section.sh_offset + section.sh_size]


# ---------------------------------------------------------------------------
# Config parsing
#
# The upstream tool uses libyaml. We deliberately do not depend on PyYAML so
# that the script runs on a bare CPython install. The HSS config format is a
# tiny, well known subset: a few top level keys plus flow mappings. We parse
# that subset directly and reject anything we do not understand.
# ---------------------------------------------------------------------------


@dataclass
class PayloadSpec:
    path: str
    exec_addr: int = 0
    owner: int = 0
    secondary: list = field(default_factory=list)
    priv_mode: int = PRV_M
    skip_opensbi: bool = False
    skip_autoboot: bool = False
    allow_cold_reboot: bool = False
    allow_warm_reboot: bool = False
    payload_name: str = ""


@dataclass
class Config:
    set_name: str = ""
    set_name_overridden: bool = False
    entry_points: dict = field(default_factory=dict)
    payloads: list = field(default_factory=list)


_HART_RE = re.compile(r"^u54_([1-4])$", re.IGNORECASE)


def _strip_quotes(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
        return value[1:-1]
    return value


def _split_flow_items(body: str) -> list:
    """Split 'a: 1, b: 2' on top level commas, respecting quotes and braces."""
    items, buf, depth, quote = [], [], 0, None
    for ch in body:
        if quote:
            buf.append(ch)
            if ch == quote:
                quote = None
            continue
        if ch in "'\"":
            quote = ch
            buf.append(ch)
        elif ch in "{[":
            depth += 1
            buf.append(ch)
        elif ch in "}]":
            depth -= 1
            buf.append(ch)
        elif ch == "," and depth == 0:
            items.append("".join(buf))
            buf = []
        else:
            buf.append(ch)
    if "".join(buf).strip():
        items.append("".join(buf))
    return items


_WIN_DRIVE_RE = re.compile(r"^[A-Za-z]:[\\/]")


def _split_key_value(text: str):
    """Split 'key: value' at the separating colon.

    Payload keys are file paths, and on Windows those start with a drive letter
    such as C:/build/zephyr.elf. A naive split on the first colon would yield the
    key "C", so skip a leading drive-letter colon. Quoted keys are handled by
    finding the closing quote first.
    """
    stripped = text.lstrip()
    offset = len(text) - len(stripped)

    # quoted key: 'some: path': value
    if stripped[:1] in "'\"":
        quote = stripped[0]
        end = stripped.find(quote, 1)
        if end > 0:
            rest = stripped[end + 1 :]
            colon = rest.find(":")
            if colon >= 0:
                return (
                    text[: offset + end + 1],
                    ":",
                    rest[colon + 1 :],
                )
        return text, "", ""

    search_from = 2 if _WIN_DRIVE_RE.match(stripped) else 0
    colon = stripped.find(":", search_from)
    if colon < 0:
        return text, "", ""
    return text[: offset + colon], ":", stripped[colon + 1 :]


def _parse_int(value: str) -> int:
    text = _strip_quotes(value)
    return int(text, 0)


def _parse_bool(value: str) -> bool:
    text = _strip_quotes(value).lower()
    if text in ("true", "yes"):
        return True
    if text in ("false", "no", ""):
        return False
    try:
        return int(text, 0) != 0
    except ValueError:
        return False


def _hart_index(token: str) -> int:
    match = _HART_RE.match(_strip_quotes(token))
    if not match:
        raise PayloadError("illegal hart token >>{}<<".format(token))
    return int(match.group(1))


def _apply_payload_attr(spec: PayloadSpec, key: str, value: str) -> None:
    key = key.strip().lower()
    if key == "exec-addr":
        spec.exec_addr = _parse_int(value)
    elif key == "owner-hart":
        spec.owner = _hart_index(value)
    elif key == "secondary-hart":
        spec.secondary.append(_hart_index(value))
    elif key == "priv-mode":
        token = _strip_quotes(value).lower()
        if token not in PRIV_MODES:
            raise PayloadError("unknown priv mode >>{}<<".format(value))
        spec.priv_mode = PRIV_MODES[token]
    elif key == "skip-opensbi":
        spec.skip_opensbi = _parse_bool(value)
    elif key == "skip-autoboot":
        spec.skip_autoboot = _parse_bool(value)
    elif key == "allow-reboot":
        token = _strip_quotes(value).lower()
        if token == "cold":
            spec.allow_cold_reboot = True
        elif token == "warm":
            spec.allow_warm_reboot = True
        else:
            raise PayloadError("unknown allow-reboot value >>{}<<".format(value))
    elif key == "payload-name":
        spec.payload_name = _strip_quotes(value)
    elif key == "ancilliary-data":
        raise PayloadError(
            "ancilliary-data is not supported by this portable generator; "
            "use the upstream hss-payload-generator for that configuration"
        )
    else:
        raise PayloadError("unknown payload attribute >>{}<<".format(key))


def parse_config(path: Path) -> Config:
    cfg = Config()
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()

    section = None  # None | "payloads"
    pending: PayloadSpec | None = None
    pending_indent = 0

    idx = 0
    while idx < len(lines):
        raw = lines[idx]
        idx += 1

        # strip comments that are not inside quotes
        cleaned, quote = [], None
        for ch in raw:
            if quote:
                cleaned.append(ch)
                if ch == quote:
                    quote = None
                continue
            if ch in "'\"":
                quote = ch
                cleaned.append(ch)
            elif ch == "#":
                break
            else:
                cleaned.append(ch)
        line = "".join(cleaned).rstrip()
        if not line.strip():
            continue

        indent = len(line) - len(line.lstrip())
        stripped = line.strip()

        # close an open block-style payload once indentation drops back
        if pending is not None and indent <= pending_indent:
            cfg.payloads.append(pending)
            pending = None

        if indent == 0:
            section = None

        key, sep, value = _split_key_value(stripped)
        if not sep:
            raise PayloadError("cannot parse config line: {!r}".format(raw))
        key = key.strip()
        value = value.strip()
        lkey = key.lower()

        if indent == 0 and lkey == "set-name":
            cfg.set_name = _strip_quotes(value)
            cfg.set_name_overridden = True
            continue

        if indent == 0 and lkey == "hart-entry-points":
            body = value.strip()
            if not (body.startswith("{") and body.endswith("}")):
                raise PayloadError("hart-entry-points must be a flow mapping")
            for item in _split_flow_items(body[1:-1]):
                hkey, hsep, hval = _split_key_value(item)
                if not hsep:
                    raise PayloadError("cannot parse hart entry >>{}<<".format(item))
                cfg.entry_points[_hart_index(hkey)] = _parse_int(hval)
            continue

        if indent == 0 and lkey == "payloads":
            section = "payloads"
            continue

        # attributes of an open block-style payload are more deeply indented
        if pending is not None:
            _apply_payload_attr(pending, key, value)
            continue

        if section == "payloads":
            spec = PayloadSpec(path=_strip_quotes(key))
            body = value.strip()
            if body.startswith("{"):
                # inline flow mapping, possibly spanning several lines
                while body.count("{") > body.count("}") and idx < len(lines):
                    body += " " + lines[idx].strip()
                    idx += 1
                if not body.endswith("}"):
                    raise PayloadError(
                        "unterminated flow mapping for payload >>{}<<".format(spec.path)
                    )
                for item in _split_flow_items(body[1:-1]):
                    akey, asep, aval = _split_key_value(item)
                    if not asep:
                        raise PayloadError(
                            "cannot parse payload attribute >>{}<<".format(item)
                        )
                    _apply_payload_attr(spec, akey, aval)
                cfg.payloads.append(spec)
            elif body == "":
                pending = spec
                pending_indent = indent
            else:
                raise PayloadError(
                    "unexpected value for payload >>{}<<: {!r}".format(spec.path, body)
                )
            continue

        raise PayloadError("unexpected config line: {!r}".format(raw))

    if pending is not None:
        cfg.payloads.append(pending)

    if not cfg.payloads:
        raise PayloadError("no payloads defined in {}".format(path))

    return cfg


# ---------------------------------------------------------------------------
# Image construction
# ---------------------------------------------------------------------------


@dataclass
class Hart:
    entry_point: int = 0
    priv_mode: int = PRV_ILLEGAL
    flags: int = 0
    num_chunks: int = 0
    first_chunk: int = 0
    last_chunk: int = 0
    name: str = ""


@dataclass
class Chunk:
    owner: int
    exec_addr: int
    size: int
    crc32: int
    payload: bytes
    load_addr: int = 0


@dataclass
class ZiChunk:
    owner: int
    exec_addr: int
    size: int


def _concatenate(
    existing: str, extra: str, limit: int = BOOT_IMAGE_MAX_NAME_LEN
) -> str:
    """Mirror concatenate() from yaml_parser.c: snprintf into n-1 chars."""
    return (existing + extra)[: limit - 1]


def build_image(cfg: Config, base_dir: Path) -> bytes:
    harts = [Hart() for _ in range(NUM_U54)]
    for hart_no, entry in cfg.entry_points.items():
        harts[hart_no - 1].entry_point = entry

    # yaml_parser() seeds set_name before parsing
    set_name = cfg.set_name if cfg.set_name_overridden else "PolarFireSOC-HSS::"

    chunks: list[Chunk] = []
    zi_chunks: list[ZiChunk] = []

    # Mirrors the static override_set_name_flag in yaml_parser.c. It is sticky:
    # once set-name or any payload-name has been seen, no further payload name is
    # ever appended to set_name, including for later payloads.
    name_override = cfg.set_name_overridden

    for spec in cfg.payloads:
        if not spec.owner:
            raise PayloadError("payload >>{}<< has no owner-hart".format(spec.path))

        if spec.payload_name:
            name_override = True
        if not name_override:
            set_name = _concatenate(set_name, spec.path)

        owner = spec.owner
        harts[owner - 1].priv_mode = spec.priv_mode
        for sec in spec.secondary:
            if harts[sec - 1].priv_mode == PRV_ILLEGAL:
                harts[sec - 1].priv_mode = spec.priv_mode
            elif harts[sec - 1].priv_mode != spec.priv_mode:
                raise PayloadError(
                    "U54_{} priv mode already set to {}, cannot set to {}".format(
                        sec, harts[sec - 1].priv_mode, spec.priv_mode
                    )
                )

        label = spec.payload_name or spec.path
        if harts[owner - 1].name:
            harts[owner - 1].name = _concatenate(harts[owner - 1].name, "+")
        harts[owner - 1].name = _concatenate(harts[owner - 1].name, label)

        elf_path = Path(spec.path)
        if not elf_path.is_absolute():
            elf_path = (base_dir / elf_path).resolve()
        if not elf_path.is_file():
            raise PayloadError("payload file not found: {}".format(elf_path))

        elf = ElfFile(elf_path)
        if spec.exec_addr:
            sys.stderr.write(
                "NOTICE: {}: ignoring >>exec-addr=0x{:x}<< as payload is an ELF file\n\n".format(
                    spec.path, spec.exec_addr
                )
            )

        first_chunk = len(chunks)
        if harts[owner - 1].num_chunks == 0 and harts[owner - 1].first_chunk == 0:
            harts[owner - 1].first_chunk = first_chunk

        # Upstream walks every program header and, for each, every section that
        # falls inside it. A section covered by two PT_LOAD segments is emitted
        # twice; we reproduce that ordering exactly.
        for seg in elf.segments:
            lo, hi = seg.p_vaddr, seg.p_vaddr + seg.p_memsz
            for sec in elf.sections:
                if not (sec.sh_addr >= lo and (sec.sh_addr + sec.sh_size) <= hi):
                    continue
                if seg.p_type != PT_LOAD:
                    continue
                if sec.sh_type != SHT_NOBITS:
                    blob = elf.section_bytes(sec)
                    if not blob:
                        continue
                    if len(blob) != sec.sh_size:
                        raise PayloadError(
                            "{}: truncated section {}".format(elf_path, sec.name)
                        )
                    # generate_add_chunk() skips zero-sized chunks
                    chunks.append(
                        Chunk(
                            owner=owner,
                            exec_addr=sec.sh_addr,
                            size=sec.sh_size,
                            crc32=crc32_hss(blob),
                            payload=blob,
                        )
                    )
                else:
                    zi_chunks.append(
                        ZiChunk(owner=owner, exec_addr=sec.sh_addr, size=sec.sh_size)
                    )

        harts[owner - 1].last_chunk = len(chunks) - 1
        harts[owner - 1].num_chunks = (
            harts[owner - 1].last_chunk - harts[owner - 1].first_chunk + 1
        )

        flags = 0
        if spec.skip_opensbi:
            flags |= BOOT_FLAG_SKIP_OPENSBI
        if spec.allow_cold_reboot:
            flags |= BOOT_FLAG_ALLOW_COLD_REBOOT | BOOT_FLAG_ALLOW_WARM_REBOOT
        elif spec.allow_warm_reboot:
            flags |= BOOT_FLAG_ALLOW_WARM_REBOOT
        if spec.skip_autoboot:
            flags |= BOOT_FLAG_SKIP_AUTOBOOT
        harts[owner - 1].flags = flags
        for sec_hart in spec.secondary:
            harts[sec_hart - 1].flags = flags

    # ---- layout -----------------------------------------------------------
    num_chunks = len(chunks)
    num_zi = len(zi_chunks)

    header_padded = BOOTIMAGE_SIZE + pad_len(BOOTIMAGE_SIZE)
    chunk_table_offset = header_padded
    chunk_table_bytes = (num_chunks + 1) * CHUNK_SIZE
    chunk_table_padded = chunk_table_bytes + pad_len(chunk_table_bytes)
    zi_table_offset = chunk_table_offset + chunk_table_padded
    zi_table_bytes = (num_zi + 1) * ZI_SIZE
    zi_table_padded = zi_table_bytes + pad_len(zi_table_bytes)
    blobs_start = zi_table_offset + zi_table_padded

    cumulative = 0
    for chunk in chunks:
        chunk.load_addr = blobs_start + cumulative + pad_len(cumulative)
        cumulative += chunk.size + pad_len(chunk.size)

    header_length = blobs_start
    boot_image_length = blobs_start + cumulative

    # ---- serialise --------------------------------------------------------
    def pack_header(header_crc: int) -> bytes:
        out = bytearray()
        out += struct.pack(
            BOOTIMAGE_PREFIX_FMT,
            HSS_BOOT_MAGIC,
            HSS_BOOT_VERSION,
            header_length,
            header_crc,
            chunk_table_offset,
            zi_table_offset,
        )
        for hart in harts:
            # Harts that no payload claims keep PRV_ILLEGAL (0xff), exactly as
            # yaml_parser.c leaves them after initialisation.
            out += struct.pack(
                HART_FMT,
                hart.entry_point,
                hart.priv_mode,
                hart.flags,
                hart.num_chunks,
                hart.first_chunk,
                hart.last_chunk,
                c_str(hart.name, BOOT_IMAGE_MAX_NAME_LEN),
            )
        out += c_str(set_name, BOOT_IMAGE_MAX_NAME_LEN)
        out += struct.pack("<Q", boot_image_length)
        out += b"\x00" * (48 + 96)  # unsigned image: empty signature
        assert len(out) == BOOTIMAGE_SIZE, len(out)
        return bytes(out)

    body = bytearray()
    for chunk in chunks:
        body += struct.pack(
            CHUNK_FMT,
            chunk.owner,
            0,
            chunk.load_addr,
            chunk.exec_addr,
            chunk.size,
            chunk.crc32,
            0,
        )
    body += struct.pack(CHUNK_FMT, 0, 0, 0, 0, 0, 0, 0)  # sentinel
    body += b"\x00" * pad_len(chunk_table_bytes)

    for zi in zi_chunks:
        body += struct.pack(ZI_FMT, zi.owner, 0, zi.exec_addr, zi.size)
    body += struct.pack(ZI_FMT, 0, 0, 0, 0)  # sentinel
    body += b"\x00" * pad_len(zi_table_bytes)

    assert len(body) + header_padded == blobs_start, (len(body), blobs_start)

    for chunk in chunks:
        body += chunk.payload
        body += b"\x00" * pad_len(chunk.size)

    # headerCrc is computed over the header with headerCrc itself still zero,
    # then the header is rewritten (generate_payload.c does exactly this).
    header_crc = crc32_hss(pack_header(0))
    image = bytearray()
    image += pack_header(header_crc)
    image += b"\x00" * pad_len(BOOTIMAGE_SIZE)
    image += body

    assert len(image) == boot_image_length, (len(image), boot_image_length)
    return bytes(image)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Portable HSS payload generator (pure Python, no libelf).",
    )
    parser.add_argument("-c", "--config", required=True, help="HSS YAML configuration")
    parser.add_argument("output", help="output payload image")
    parser.add_argument(
        "--relative-to",
        default=None,
        help="base directory for relative payload paths (default: config directory)",
    )
    parser.add_argument(
        "-d", "--dump", action="store_true", help="print a summary of the written image"
    )
    args = parser.parse_args(argv)

    config_path = Path(args.config)
    if not config_path.is_file():
        sys.stderr.write("error: config not found: {}\n".format(config_path))
        return 1

    base_dir = Path(args.relative_to) if args.relative_to else config_path.parent

    try:
        cfg = parse_config(config_path)
        image = build_image(cfg, base_dir.resolve())
    except PayloadError as exc:
        sys.stderr.write("error: {}\n".format(exc))
        return 1

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(image)

    print("Payload written: {} ({} bytes)".format(out_path, len(image)))
    if args.dump:
        magic, version, header_len, header_crc, chunk_off, zi_off = struct.unpack_from(
            BOOTIMAGE_PREFIX_FMT, image, 0
        )
        print("  magic              0x{:08x}".format(magic))
        print("  version            {}".format(version))
        print("  headerLength       0x{:x}".format(header_len))
        print("  headerCrc          0x{:08x}".format(header_crc))
        print("  chunkTableOffset   0x{:x}".format(chunk_off))
        print("  ziChunkTableOffset 0x{:x}".format(zi_off))
    return 0


if __name__ == "__main__":
    sys.exit(main())
