#!/usr/bin/env bash
# Copyright (c) 2026 Microchip Technology Inc
# SPDX-License-Identifier: MIT
#
# Write the HSS payload to the SD card payload partition.
#
# The HSS bootloader expects the payload image at sector 139264 (LBA 0x22000).
# This writes at a raw offset, it does not create or use a filesystem.
#
# Refuses to touch anything that looks like a system disk. Read the target
# summary before typing YES.

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
Usage: $(basename "$0") --device /dev/sdX [options]
       $(basename "$0") --list

Options:
  --device DEV      Target block device, for example /dev/sdb or /dev/mmcblk0
  --payload FILE    Payload image (default: ${PAYLOAD})
  --sector N        Start sector (default: ${SECTOR}, LBA 0x22000)
  --list            Show removable block devices and exit
  --yes             Skip the interactive confirmation (for scripted use)
  -h, --help        Show this help

Pass the whole disk, not a partition. /dev/sdb is right, /dev/sdb1 is wrong.
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

# GNU coreutils uses stat -c, BSD/macOS uses stat -f
file_size() { stat -c%s "$1" 2>/dev/null || stat -f%z "$1"; }

if [ "${DO_LIST}" -eq 1 ]; then
    info "Block devices (removable ones are the likely SD card)"
    if command -v lsblk >/dev/null 2>&1; then
        lsblk -d -o NAME,SIZE,TYPE,RM,HOTPLUG,MODEL,TRAN
        echo
        echo "RM=1 or HOTPLUG=1 usually means removable. Match the size to your card."
    else
        die "lsblk not available; install util-linux"
    fi
    exit 0
fi

[ -n "${DEVICE}" ] || { usage >&2; die "--device is required"; }
[ -f "${PAYLOAD}" ] || die "payload not found: ${PAYLOAD}
Run setup/linux/payload.sh, or point --payload at the pre-built image."

# magic check: refuse to write something that is not an HSS payload
MAGIC="$(od -An -tx4 -N4 "${PAYLOAD}" | tr -d ' \n')"
[ "${MAGIC}" = "b007c0de" ] || die "${PAYLOAD} is not an HSS payload (magic 0x${MAGIC}, expected 0xb007c0de)"

[ -b "${DEVICE}" ] || die "${DEVICE} is not a block device"

# Reject partitions: writing at sector 139264 of a partition is not what we want.
# Loop devices are allowed so that the flash path can be rehearsed against an
# image file (see setup/common/tests/, and --list will not show them).
if command -v lsblk >/dev/null 2>&1; then
    DEV_TYPE="$(lsblk -ndo TYPE "${DEVICE}")"
    case "${DEV_TYPE}" in
        disk|loop) : ;;
        *)
            die "${DEVICE} is a ${DEV_TYPE}, not a whole disk.
Pass the disk itself, for example /dev/sdb rather than /dev/sdb1."
            ;;
    esac
fi

# Safety: refuse if the device or any of its partitions hosts /, /boot or /home.
PROTECTED=""
while read -r src target; do
    case "${target}" in
        /|/boot|/boot/efi|/home|/usr|/var)
            case "${src}" in
                "${DEVICE}"*) PROTECTED="${PROTECTED} ${target}" ;;
            esac
            ;;
    esac
done < <(findmnt -rn -o SOURCE,TARGET 2>/dev/null || true)

if [ -n "${PROTECTED}" ]; then
    die "refusing to write: ${DEVICE} currently hosts${PROTECTED}.
That is a system disk, not your SD card."
fi

if [ "$(id -u)" -ne 0 ]; then
    die "raw device writes need root. Re-run with sudo:
  sudo $0 --device ${DEVICE}"
fi

SIZE_BYTES="$(blockdev --getsize64 "${DEVICE}")"
MODEL="$(lsblk -ndo MODEL "${DEVICE}" 2>/dev/null || echo unknown)"
RM_FLAG="$(lsblk -ndo RM "${DEVICE}" 2>/dev/null || echo '?')"
PAYLOAD_SIZE="$(file_size "${PAYLOAD}")"
NEEDED=$(( SECTOR * 512 + PAYLOAD_SIZE ))

echo
echo "=== PIC64GX payload flash ==="
printf '  Device        %s\n' "${DEVICE}"
printf '  Model         %s\n' "${MODEL:-unknown}"
printf '  Size          %s bytes (%.1f GB)\n' "${SIZE_BYTES}" "$(awk "BEGIN{print ${SIZE_BYTES}/1000000000}")"
printf '  Removable     %s\n' "${RM_FLAG}"
printf '  Payload       %s (%s bytes)\n' "${PAYLOAD}" "${PAYLOAD_SIZE}"
printf '  Start sector  %s (byte offset %s)\n' "${SECTOR}" "$(( SECTOR * 512 ))"
echo

if [ "${RM_FLAG}" != "1" ]; then
    printf '\033[33mWarning: %s is not flagged removable. Double-check this is your SD card.\033[0m\n\n' "${DEVICE}"
fi

[ "${SIZE_BYTES}" -ge "${NEEDED}" ] || die "card is too small: needs ${NEEDED} bytes, has ${SIZE_BYTES}"

if [ "${ASSUME_YES}" -eq 0 ]; then
    printf 'This overwrites data on %s. Type YES to continue: ' "${DEVICE}"
    read -r answer
    [ "${answer}" = "YES" ] || die "aborted"
fi

# Unmount any mounted partitions of this device so the kernel does not fight us.
info "Unmounting partitions on ${DEVICE}"
while read -r part; do
    if findmnt -rn -S "${part}" >/dev/null 2>&1; then
        umount "${part}" && echo "  unmounted ${part}"
    fi
done < <(lsblk -lnpo NAME "${DEVICE}" | tail -n +2)

info "Writing payload at sector ${SECTOR}"
dd if="${PAYLOAD}" of="${DEVICE}" bs=512 seek="${SECTOR}" conv=fsync status=progress
sync

info "Verifying written data"
TMP_READBACK="$(mktemp)"
trap 'rm -f "${TMP_READBACK}"' EXIT
dd if="${DEVICE}" of="${TMP_READBACK}" bs=512 skip="${SECTOR}" count=$(( (PAYLOAD_SIZE + 511) / 512 )) status=none

if cmp -n "${PAYLOAD_SIZE}" "${PAYLOAD}" "${TMP_READBACK}" >/dev/null 2>&1; then
    printf '\n\033[32mSD card flashed and verified.\033[0m\n'
else
    die "read-back verification failed; the card may be faulty or write-protected"
fi

cat <<EOF

Insert the card into the PIC64GX Curiosity Kit, connect HDMI, power on.
For console output: 115200 8N1 on the board's UART0.

EOF
