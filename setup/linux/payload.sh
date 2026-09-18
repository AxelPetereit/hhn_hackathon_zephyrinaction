#!/usr/bin/env bash
# Copyright (c) 2026 Microchip Technology Inc
# SPDX-License-Identifier: MIT
#
# Turn the built zephyr.elf into an HSS payload image.
#
# Uses the official hss-payload-generator when it is available, otherwise the
# portable Python implementation in setup/common/hss_payload.py. Both produce
# semantically identical images; see setup/common/tests/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMMON_DIR="${REPO_ROOT}/setup/common"

# shellcheck disable=SC1091
. "${COMMON_DIR}/versions.env"

WORKSPACE="${WORKSPACE:-${HOME}/pic64gx-zephyr}"
HSS_DIR="${HSS_DIR:-${HOME}/hss-payload-generator-${HSS_VERSION}}"
BUILD_DIR="${BUILD_DIR:-${WORKSPACE}/build/flappy-microchip}"
OUTPUT="${OUTPUT:-${REPO_ROOT}/examples/flappy-microchip/payload.bin}"
APP_SOURCE="${REPO_ROOT}/examples/flappy-microchip/source"
GENERATOR=auto

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --build-dir DIR   Zephyr build directory (default: ${BUILD_DIR})
  --output FILE     Payload image path (default: ${OUTPUT})
  --generator WHICH auto | upstream | python (default: auto)
  --compare         Build with both generators and diff the result
  -h, --help        Show this help
EOF
}

COMPARE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --build-dir) BUILD_DIR="$2"; shift 2 ;;
        --output) OUTPUT="$2"; shift 2 ;;
        --generator) GENERATOR="$2"; shift 2 ;;
        --compare) COMPARE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown option $1" >&2; exit 2 ;;
    esac
done

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ok\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

ELF="${BUILD_DIR}/zephyr/zephyr.elf"
SRC_CONFIG="${APP_SOURCE}/demos/pic64_smp_hello/hss-payload.yaml"

[ -f "${ELF}" ] || die "${ELF} not found. Run setup/linux/build.sh first."
[ -f "${SRC_CONFIG}" ] || die "HSS configuration not found: ${SRC_CONFIG}"

PY="${WORKSPACE}/.venv/bin/python"
[ -x "${PY}" ] || PY="$(command -v python3)"
[ -n "${PY}" ] || die "no python3 available"

# The shipped config names the payload "zephyr.elf". Rewrite that key to the
# absolute path of the ELF we just built, so the generator finds it regardless of
# the working directory.
LOCAL_CONFIG="${BUILD_DIR}/hss-payload.local.yaml"
mkdir -p "${BUILD_DIR}"
ELF_ABS="$(cd "$(dirname "${ELF}")" && pwd)/$(basename "${ELF}")"
sed -E "s|^([[:space:]]+).*zephyr\.elf:|\1${ELF_ABS}:|" "${SRC_CONFIG}" > "${LOCAL_CONFIG}"

if ! grep -qF "${ELF_ABS}:" "${LOCAL_CONFIG}"; then
    die "failed to rewrite the ELF path in ${LOCAL_CONFIG}"
fi

HSS_BIN="$(find "${HSS_DIR}" -type f -name 'hss-payload-generator' 2>/dev/null | head -n1 || true)"

gen_upstream() {
    local out="$1"
    [ -n "${HSS_BIN}" ] || die "official hss-payload-generator not found below ${HSS_DIR}"
    [ -x "${HSS_BIN}" ] || chmod +x "${HSS_BIN}"
    "${HSS_BIN}" -c "${LOCAL_CONFIG}" "${out}"
}

gen_python() {
    local out="$1"
    "${PY}" "${COMMON_DIR}/hss_payload.py" -c "${LOCAL_CONFIG}" "${out}"
}

mkdir -p "$(dirname "${OUTPUT}")"

if [ "${COMPARE}" -eq 1 ]; then
    info "Generating with both implementations"
    gen_upstream "${BUILD_DIR}/payload.upstream.bin"
    gen_python "${BUILD_DIR}/payload.python.bin"
    "${PY}" "${COMMON_DIR}/tests/compare_payloads.py" \
        "${BUILD_DIR}/payload.upstream.bin" "${BUILD_DIR}/payload.python.bin"
    cp -f "${BUILD_DIR}/payload.upstream.bin" "${OUTPUT}"
    ok "payload written to ${OUTPUT}"
    exit 0
fi

case "${GENERATOR}" in
    upstream)
        info "Generating payload with the official generator"
        gen_upstream "${OUTPUT}"
        ;;
    python)
        info "Generating payload with the portable Python generator"
        gen_python "${OUTPUT}"
        ;;
    auto)
        if [ -n "${HSS_BIN}" ] && [ "$(uname -m)" = "x86_64" ]; then
            info "Generating payload with the official generator"
            gen_upstream "${OUTPUT}"
        else
            info "Official generator unavailable, using the portable Python generator"
            gen_python "${OUTPUT}"
        fi
        ;;
    *)
        die "unknown --generator value: ${GENERATOR}"
        ;;
esac

[ -f "${OUTPUT}" ] || die "payload was not produced"

SIZE="$(stat -c%s "${OUTPUT}" 2>/dev/null || stat -f%z "${OUTPUT}")"
MAGIC="$(od -An -tx4 -N4 "${OUTPUT}" | tr -d ' \n')"
[ "${MAGIC}" = "b007c0de" ] || die "payload magic is 0x${MAGIC}, expected 0xb007c0de"

printf '\n\033[32mPayload ready\033[0m\n  %s (%s bytes, magic 0x%s)\n\n' "${OUTPUT}" "${SIZE}" "${MAGIC}"
echo "Next: ./setup/linux/flash.sh --list"
