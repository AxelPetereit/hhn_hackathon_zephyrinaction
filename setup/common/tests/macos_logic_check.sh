#!/usr/bin/env bash
# Copyright (c) 2026 Microchip Technology Inc
# SPDX-License-Identifier: MIT
#
# Checks the macOS-specific logic that cannot be exercised by simply running the
# scripts on a non-Mac host.
#
# What this does verify:
#   - the diskutil output parser extracts the right fields from real sample output
#   - the device name normalisation and slice rejection behave as intended
#   - dd is invoked with flags that exist in BSD dd
#   - the scripts refuse non-Darwin hosts rather than doing something unsafe
#   - no GNU-only utility flags are used
#
# What it cannot verify: that Homebrew, diskutil and the Zephyr SDK behave as
# documented on a real Mac. Run setup/macos/setup.sh --dry-run there first.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MACOS_DIR="${REPO_ROOT}/setup/macos"
FAILED=0

pass() { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAILED=1; }

# ---------------------------------------------------------------------------

echo "[diskutil output parser]"

# Real-world shape of `diskutil info diskN` for an SD card in a USB reader.
SAMPLE=$(cat <<'EOF'
   Device Identifier:         disk4
   Device Node:               /dev/disk4
   Whole:                     Yes
   Part of Whole:             disk4

   Device / Media Name:       Generic STORAGE DEVICE

   Volume Name:               Not applicable (no file system)
   Mounted:                   Not applicable (no file system)
   File System:               None

   Content (IOContent):       FDisk_partition_scheme
   OS Can Be Installed:       No
   Media Type:                Generic
   Protocol:                  USB
   SMART Status:              Not Supported

   Disk Size:                 31.9 GB (31914983424 Bytes) (exactly 62333952 512-Byte-Units)
   Device Block Size:         512 Bytes

   Removable Media:           Removable
   Media Removal:             Software-Activated

   Solid State:               Info not available
   Virtual:                   No
   Hardware AES Support:      No

   Internal:                  No
   OS 9 Drivers:              No
   Low Level Format:          Not supported
EOF
)

# This is the exact awk program used by setup/macos/flash.sh.
parse_field() {
    printf '%s\n' "$SAMPLE" | awk -F': *' -v key="$1" '
        { gsub(/^ +| +$/, "", $1) }
        $1 == key { print $2; exit }
    '
}

got=$(parse_field "Internal")
[ "$got" = "No" ] && pass "Internal parses as '$got'" || fail "Internal parsed as '$got', expected 'No'"

got=$(parse_field "Whole")
[ "$got" = "Yes" ] && pass "Whole parses as '$got'" || fail "Whole parsed as '$got', expected 'Yes'"

got=$(parse_field "Removable Media")
[ "$got" = "Removable" ] && pass "Removable Media parses as '$got'" || fail "Removable Media parsed as '$got'"

got=$(parse_field "Device / Media Name")
[ "$got" = "Generic STORAGE DEVICE" ] && pass "Device / Media Name parses (contains a slash in the key)" \
    || fail "Device / Media Name parsed as '$got'"

got=$(parse_field "Disk Size")
case "$got" in
    "31.9 GB (31914983424 Bytes)"*) pass "Disk Size parses as '$got'" ;;
    *) fail "Disk Size parsed as '$got'" ;;
esac

# The byte-count extraction used for the capacity check
bytes=$(printf '%s' "$got" | sed -nE 's/.*\(([0-9]+) Bytes\).*/\1/p')
[ "$bytes" = "31914983424" ] && pass "byte count extracted as $bytes" || fail "byte count extracted as '$bytes'"

# An internal disk must be detected as such
INTERNAL_SAMPLE="   Internal:                  Yes"
got=$(printf '%s\n' "$INTERNAL_SAMPLE" | awk -F': *' -v key="Internal" '
    { gsub(/^ +| +$/, "", $1) } $1 == key { print $2; exit }')
[ "$got" = "Yes" ] && pass "internal disk detected as '$got'" || fail "internal disk parsed as '$got'"

# ---------------------------------------------------------------------------

echo
echo "[device name normalisation]"

normalise() {
    local dev="$1" id
    id="$(basename "$dev")"
    id="${id#r}"
    printf '%s' "$id"
}

for pair in "/dev/disk4:disk4" "/dev/rdisk4:disk4" "disk4:disk4" "/dev/disk11:disk11" "/dev/rdisk11:disk11"; do
    input="${pair%%:*}"; want="${pair##*:}"
    got="$(normalise "$input")"
    [ "$got" = "$want" ] && pass "$input -> $got" || fail "$input -> $got, expected $want"
done

is_slice() {
    case "$1" in
        *s[0-9]*) return 0 ;;
        *) return 1 ;;
    esac
}
is_slice "disk4s1" && pass "disk4s1 recognised as a slice" || fail "disk4s1 not recognised as a slice"
is_slice "disk4s10" && pass "disk4s10 recognised as a slice" || fail "disk4s10 not recognised as a slice"
is_slice "disk4" && fail "disk4 wrongly treated as a slice" || pass "disk4 correctly treated as a whole disk"

# A non-disk argument must be refused
looks_like_disk() {
    case "$1" in
        disk[0-9]*) return 0 ;;
        *) return 1 ;;
    esac
}
looks_like_disk "disk4" && pass "disk4 accepted as a disk node" || fail "disk4 rejected"
looks_like_disk "sdb" && fail "sdb wrongly accepted on macOS" || pass "Linux-style sdb rejected"

# ---------------------------------------------------------------------------

echo
echo "[BSD dd flags]"

# BSD dd has no status=progress and no conv=fsync. It uses iseek/oseek in
# addition to skip/seek. Using a GNU-only flag would fail at runtime on a Mac.
if grep -qE 'status=progress' "${MACOS_DIR}/flash.sh"; then
    fail "flash.sh uses status=progress, which BSD dd does not support"
else
    pass "no status=progress in the macOS flash script"
fi

if grep -qE 'conv=fsync' "${MACOS_DIR}/flash.sh"; then
    fail "flash.sh uses conv=fsync, which BSD dd does not support"
else
    pass "no conv=fsync in the macOS flash script"
fi

if grep -qE 'dd .*oseek=' "${MACOS_DIR}/flash.sh"; then
    pass "write uses oseek (portable across BSD and GNU dd)"
else
    fail "write does not use oseek"
fi

if grep -qE 'dd .*iseek=' "${MACOS_DIR}/flash.sh"; then
    pass "read-back uses iseek"
else
    fail "read-back does not use iseek"
fi

if grep -q '/dev/r\${DISK_ID}' "${MACOS_DIR}/flash.sh" || grep -q 'RAW="/dev/r' "${MACOS_DIR}/flash.sh"; then
    pass "raw /dev/rdiskN node used for the transfer"
else
    fail "raw disk node is not used; writes would be needlessly slow"
fi

# ---------------------------------------------------------------------------

echo
echo "[platform guards]"

for f in "${MACOS_DIR}/setup.sh" "${MACOS_DIR}/flash.sh"; do
    if grep -q 'uname -s.*Darwin' "$f"; then
        pass "$(basename "$f") refuses non-Darwin hosts"
    else
        fail "$(basename "$f") has no Darwin guard"
    fi
done

if grep -q 'arm64' "${MACOS_DIR}/setup.sh"; then
    pass "setup.sh checks for Apple Silicon"
else
    fail "setup.sh does not check the architecture"
fi

# The SDK asset name must be one that actually exists in the release.
if grep -q 'macos-aarch64_minimal.tar.xz' "${MACOS_DIR}/setup.sh"; then
    pass "SDK archive name matches a real release asset"
else
    fail "SDK archive name does not match the published assets"
fi

# macOS has curl in the base system but not wget. Only actual invocations matter,
# so ignore comments before matching.
if grep -vE '^\s*#' "${MACOS_DIR}/setup.sh" | grep -qE '(^|[;&|]|\brun )\s*wget\b'; then
    fail "setup.sh calls wget, which is not part of a stock macOS"
else
    pass "downloads use curl, which ships with macOS"
fi

# Gatekeeper will block the freshly downloaded toolchain otherwise.
if grep -q 'com.apple.quarantine' "${MACOS_DIR}/setup.sh"; then
    pass "setup.sh clears the Gatekeeper quarantine attribute"
else
    fail "setup.sh does not handle the Gatekeeper quarantine attribute"
fi

# ---------------------------------------------------------------------------

echo
echo "[no GNU-only utility flags]"

for f in "${MACOS_DIR}"/*.sh; do
    name="$(basename "$f")"
    bad=""
    grep -qE '\bgrep -P\b' "$f" && bad="${bad} grep -P;"
    grep -qE '\breadlink -f\b' "$f" && bad="${bad} readlink -f;"
    grep -qE '\bsed -i\b' "$f" && bad="${bad} sed -i;"
    grep -qE '\bcp --' "$f" && bad="${bad} cp long options;"
    grep -qE '\bdate -d\b' "$f" && bad="${bad} date -d;"
    grep -qE '\bmktemp --' "$f" && bad="${bad} mktemp long options;"
    if [ -n "$bad" ]; then
        fail "${name}:${bad}"
    else
        pass "${name} uses no GNU-only flags"
    fi
done

# ---------------------------------------------------------------------------

echo
echo "[argument handling]"

# Every script must reject an unknown option instead of silently ignoring it.
for f in "${MACOS_DIR}"/*.sh; do
    name="$(basename "$f")"
    if grep -qE 'unknown option' "$f"; then
        pass "${name} rejects unknown options"
    else
        fail "${name} silently ignores unknown options"
    fi
done

# --help must work without touching the system. Run it with a stubbed uname so a
# non-Darwin host can still reach the help text.
STUB="$(mktemp -d)"
cat > "${STUB}/uname" <<'EOF'
#!/bin/sh
case "$1" in
  -s) echo Darwin ;;
  -m) echo arm64 ;;
  *) echo Darwin ;;
esac
EOF
cat > "${STUB}/sw_vers" <<'EOF'
#!/bin/sh
echo 15.0
EOF
chmod +x "${STUB}/uname" "${STUB}/sw_vers"

for f in "${MACOS_DIR}"/*.sh; do
    name="$(basename "$f")"
    if out=$(PATH="${STUB}:${PATH}" bash "$f" --help 2>&1) && printf '%s' "$out" | grep -q "Usage:"; then
        pass "${name} --help prints usage"
    else
        fail "${name} --help did not print usage"
    fi
done

# A missing --device must be an error, not a write to something arbitrary.
if out=$(PATH="${STUB}:${PATH}" bash "${MACOS_DIR}/flash.sh" 2>&1); then
    fail "flash.sh without --device exited successfully"
else
    if printf '%s' "$out" | grep -q -- "--device is required"; then
        pass "flash.sh without --device is refused"
    else
        fail "flash.sh without --device failed for the wrong reason: $(printf '%s' "$out" | tail -1)"
    fi
fi

# A Linux-style device name must be refused rather than acted upon.
out=$(PATH="${STUB}:${PATH}" bash "${MACOS_DIR}/flash.sh" --device /dev/sdb --yes 2>&1)
if printf '%s' "$out" | grep -qE "does not look like a macOS disk node|is not an HSS payload|payload not found"; then
    pass "flash.sh refuses a Linux-style device name"
else
    fail "flash.sh accepted /dev/sdb: $(printf '%s' "$out" | tail -1)"
fi

rm -rf "${STUB}"

# ---------------------------------------------------------------------------

echo
if [ "${FAILED}" -eq 0 ]; then
    printf '\033[32mAll macOS logic checks passed.\033[0m\n'
    printf 'Note: these are static and simulated checks. Run\n'
    printf '  ./setup/macos/setup.sh --dry-run\n'
    printf 'on a real Apple Silicon Mac to confirm the environment.\n'
else
    printf '\033[31mmacOS logic checks reported problems.\033[0m\n'
fi
exit "${FAILED}"
