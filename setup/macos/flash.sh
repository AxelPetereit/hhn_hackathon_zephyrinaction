#!/usr/bin/env bash
# Copyright (c) 2026 Microchip Technology Inc
# SPDX-License-Identifier: MIT
#
# Write the HSS payload to the SD card payload partition on macOS.
#
# The HSS bootloader expects the payload image at sector 139264 (LBA 0x22000).
# This writes at a raw offset; it does not create or use a filesystem.
#
# Refuses internal disks. Read the target summary before typing YES.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck disable=SC1091
. "${REPO_ROOT}/setup/common/versions.env"

PAYLOAD="${PAYLOAD:-${REPO_ROOT}/examples/flappy-microchip/payload.bin}"
DEVICE=""
SECTOR="${PAYLOAD_SECTOR}"
ASSUME_YES=0
DO_LIST=0

usage() {
    cat <<EOF
Usage: $(basename "$0") --device /dev/rdiskN [options]
       $(basename "$0") --list

Options:
  --device DEV      Target whole disk, for example /dev/disk4 or /dev/rdisk4
  --payload FILE    Payload image (default: ${PAYLOAD})
  --sector N        Start sector (default: ${SECTOR}, LBA 0x22000)
  --list            Show external disks and exit
  --yes             Skip the interactive confirmation (for scripted use)
  -h, --help        Show this help

Pass the whole disk, not a slice. /dev/disk4 is right, /dev/disk4s1 is wrong.
The script uses the raw /dev/rdiskN node internally, which is much faster.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --device) DEVICE="$2"; shift 2 ;;
        --payload) PAYLOAD="$2"; shift 2 ;;
        --sector) SECTOR="$2"; shift 2 ;;
        --list) DO_LIST=1; shift ;;
        --yes) ASSUME_YES=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown option $1" >&2; usage >&2; exit 2 ;;
    esac
done

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

file_size() { stat -f%z "$1" 2>/dev/null || stat -c%s "$1"; }

# Reads a single field out of `diskutil info -plist` without needing plistlib.
disk_info() {
    diskutil info "$1" 2>/dev/null | awk -F': *' -v key="$2" '
        { gsub(/^ +| +$/, "", $1) }
        $1 == key { print $2; exit }
    '
}

[ "$(uname -s)" = "Darwin" ] || die "this script is for macOS; use setup/linux/flash.sh instead"

if [ "${DO_LIST}" -eq 1 ]; then
    info "External disks (your SD card should be here)"
    diskutil list external physical
    echo
    echo "If nothing is listed, the card reader may be presenting the card as internal."
    echo "In that case run 'diskutil list' and match the size carefully."
    exit 0
fi

[ -n "${DEVICE}" ] || { usage >&2; die "--device is required"; }
[ -f "${PAYLOAD}" ] || die "payload not found: ${PAYLOAD}
Run setup/macos/payload.sh, or point --payload at the pre-built image."

MAGIC="$(od -An -tx4 -N4 "${PAYLOAD}" | tr -d ' \n')"
[ "${MAGIC}" = "b007c0de" ] || die "${PAYLOAD} is not an HSS payload (magic 0x${MAGIC}, expected 0xb007c0de)"

# Normalise /dev/rdiskN and bare diskN to a diskN identifier.
DISK_ID="$(basename "${DEVICE}")"
DISK_ID="${DISK_ID#r}"

case "${DISK_ID}" in
    disk[0-9]*) : ;;
    *) die "'${DEVICE}' does not look like a macOS disk node. Expected something like /dev/disk4." ;;
esac

# Reject slices: writing at sector 139264 of a partition is not what we want.
case "${DISK_ID}" in
    *s[0-9]*)
        die "${DEVICE} is a slice, not a whole disk.
Pass the disk itself, for example /dev/disk4 rather than /dev/disk4s1."
        ;;
esac

BUFFERED="/dev/${DISK_ID}"
RAW="/dev/r${DISK_ID}"

[ -e "${BUFFERED}" ] || die "${BUFFERED} does not exist. Run $(basename "$0") --list"

INTERNAL="$(disk_info "${DISK_ID}" "Internal")"
REMOVABLE="$(disk_info "${DISK_ID}" "Removable Media")"
MEDIA_NAME="$(disk_info "${DISK_ID}" "Device / Media Name")"
DISK_SIZE_TEXT="$(disk_info "${DISK_ID}" "Disk Size")"
WHOLE="$(disk_info "${DISK_ID}" "Whole")"

if [ "${INTERNAL}" = "Yes" ]; then
    die "refusing to write to ${BUFFERED}: diskutil reports it as an internal disk.

That is very likely this Mac's own storage, not your SD card.
Run $(basename "$0") --list and pick an external disk."
fi

if [ "${WHOLE}" = "No" ]; then
    die "${BUFFERED} is not a whole disk. Pass the parent disk instead."
fi

PAYLOAD_SIZE="$(file_size "${PAYLOAD}")"
NEEDED=$(( SECTOR * 512 + PAYLOAD_SIZE ))

# diskutil reports size in bytes inside parentheses, e.g. "31.9 GB (31914983424 Bytes)"
SIZE_BYTES="$(printf '%s' "${DISK_SIZE_TEXT}" | sed -nE 's/.*\(([0-9]+) Bytes\).*/\1/p')"

echo
echo "=== PIC64GX payload flash ==="
printf '  Device        %s (raw node %s)\n' "${BUFFERED}" "${RAW}"
printf '  Media         %s\n' "${MEDIA_NAME:-unknown}"
printf '  Size          %s\n' "${DISK_SIZE_TEXT:-unknown}"
printf '  Internal      %s\n' "${INTERNAL:-unknown}"
printf '  Removable     %s\n' "${REMOVABLE:-unknown}"
printf '  Payload       %s (%s bytes)\n' "${PAYLOAD}" "${PAYLOAD_SIZE}"
printf '  Start sector  %s (byte offset %s)\n' "${SECTOR}" "$(( SECTOR * 512 ))"
echo

if [ -n "${SIZE_BYTES}" ] && [ "${SIZE_BYTES}" -lt "${NEEDED}" ]; then
    die "card is too small: needs ${NEEDED} bytes, has ${SIZE_BYTES}"
fi

if [ "$(id -u)" -ne 0 ]; then
    die "raw device writes need root. Re-run with sudo:
  sudo $0 --device ${BUFFERED}"
fi

if [ "${ASSUME_YES}" -eq 0 ]; then
    printf 'This overwrites data on %s. Type YES to continue: ' "${BUFFERED}"
    read -r answer
    [ "${answer}" = "YES" ] || die "aborted"
fi

# macOS keeps the volumes mounted and will fight a raw write otherwise.
info "Unmounting ${BUFFERED}"
diskutil unmountDisk "${BUFFERED}" || die "could not unmount ${BUFFERED}"

info "Writing payload at sector ${SECTOR}"
# The raw node bypasses the buffer cache and is dramatically faster. bs=512 with
# seek keeps the offset arithmetic identical to the Linux script.
dd if="${PAYLOAD}" of="${RAW}" bs=512 oseek="${SECTOR}" 2>&1 | tail -n 3
sync

info "Verifying written data"
TMP_READBACK="$(mktemp)"
trap 'rm -f "${TMP_READBACK}"' EXIT
dd if="${RAW}" of="${TMP_READBACK}" bs=512 iseek="${SECTOR}" \
    count=$(( (PAYLOAD_SIZE + 511) / 512 )) 2>/dev/null

if cmp -n "${PAYLOAD_SIZE}" "${PAYLOAD}" "${TMP_READBACK}" >/dev/null 2>&1; then
    printf '\n\033[32mSD card flashed and verified.\033[0m\n'
else
    die "read-back verification failed; the card may be faulty or write-protected"
fi

# Leave the card ejected so it is safe to pull out.
diskutil eject "${BUFFERED}" >/dev/null 2>&1 || true

cat <<EOF

Card ejected. Insert it into the PIC64GX Curiosity Kit, connect HDMI, power on.
For console output: 115200 8N1 on the board's UART0.

EOF
