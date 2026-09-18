#!/usr/bin/env bash
# Copyright (c) 2026 Microchip Technology Inc
# SPDX-License-Identifier: MIT
#
# Turn the built zephyr.elf into an HSS payload image on macOS.
#
# Always uses the portable generator setup/common/hss_payload.py, because the
# upstream hss-payload-generator has no macOS build. Its output is verified
# against the official tool by setup/common/tests/run_tests.py.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMMON_DIR="${REPO_ROOT}/setup/common"

# shellcheck disable=SC1091
. "${COMMON_DIR}/versions.env"

WORKSPACE="${WORKSPACE:-${HOME}/pic64gx-zephyr}"
BUILD_DIR="${BUILD_DIR:-${WORKSPACE}/build/flappy-microchip}"
OUTPUT="${OUTPUT:-${REPO_ROOT}/examples/flappy-microchip/payload.bin}"
APP_SOURCE="${REPO_ROOT}/examples/flappy-microchip/source"
SELFTEST=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --build-dir DIR   Zephyr build directory (default: ${BUILD_DIR})
  --output FILE     Payload image path (default: ${OUTPUT})
  --self-test       Run the generator test suite first
  -h, --help        Show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --build-dir) BUILD_DIR="$2"; shift 2 ;;
        --output) OUTPUT="$2"; shift 2 ;;
        --self-test) SELFTEST=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown option $1" >&2; exit 2 ;;
    esac
done

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ok\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

file_size() { stat -f%z "$1" 2>/dev/null || stat -c%s "$1"; }

ELF="${BUILD_DIR}/zephyr/zephyr.elf"
SRC_CONFIG="${APP_SOURCE}/demos/pic64_smp_hello/hss-payload.yaml"

[ -f "${ELF}" ] || die "${ELF} not found. Run setup/macos/build.sh first."
[ -f "${SRC_CONFIG}" ] || die "HSS configuration not found: ${SRC_CONFIG}"

PY="${WORKSPACE}/.venv/bin/python"
if [ ! -x "${PY}" ]; then
    PY="$(command -v python3 || true)"
fi
[ -n "${PY}" ] || die "no python3 available"

if [ "${SELFTEST}" -eq 1 ]; then
    info "Running payload generator self-test"
    "${PY}" "${COMMON_DIR}/tests/run_tests.py" | tail -n 3
fi

# The shipped config names the payload "zephyr.elf". Rewrite that key to the
# absolute path of the ELF we just built.
#
# BSD sed needs an argument for -i, GNU sed must not have one, so write to a new
# file instead of editing in place.
mkdir -p "${BUILD_DIR}"
LOCAL_CONFIG="${BUILD_DIR}/hss-payload.local.yaml"
ELF_ABS="$(cd "$(dirname "${ELF}")" && pwd)/$(basename "${ELF}")"
sed -E "s|^([[:space:]]+).*zephyr\.elf:|\1${ELF_ABS}:|" "${SRC_CONFIG}" > "${LOCAL_CONFIG}"

grep -qF "${ELF_ABS}:" "${LOCAL_CONFIG}" || die "failed to rewrite the ELF path in ${LOCAL_CONFIG}"

mkdir -p "$(dirname "${OUTPUT}")"

info "Generating payload with the portable generator"
"${PY}" "${COMMON_DIR}/hss_payload.py" -c "${LOCAL_CONFIG}" "${OUTPUT}"

[ -f "${OUTPUT}" ] || die "payload was not produced"

# Verify the HSS magic. od output format is stable across BSD and GNU for this.
MAGIC="$(od -An -tx4 -N4 "${OUTPUT}" | tr -d ' \n')"
[ "${MAGIC}" = "b007c0de" ] || die "payload magic is 0x${MAGIC}, expected 0xb007c0de"

printf '\n\033[32mPayload ready\033[0m\n  %s (%s bytes, magic 0x%s)\n\n' \
    "${OUTPUT}" "$(file_size "${OUTPUT}")" "${MAGIC}"
echo "Next: ./setup/macos/flash.sh --list"
