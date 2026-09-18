#!/usr/bin/env bash
# Copyright (c) 2026 Microchip Technology Inc
# SPDX-License-Identifier: MIT
#
# Build the Flappy Microchip example for the PIC64GX1000 Curiosity Kit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck disable=SC1091
. "${REPO_ROOT}/setup/common/versions.env"

WORKSPACE="${WORKSPACE:-${HOME}/pic64gx-zephyr}"
SDK_DIR="${SDK_DIR:-${HOME}/zephyr-sdk-${ZEPHYR_SDK_VERSION}}"
APP_SOURCE="${REPO_ROOT}/examples/flappy-microchip/source"
BUILD_DIR="${BUILD_DIR:-${WORKSPACE}/build/flappy-microchip}"
PRISTINE=always

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --workspace DIR   Zephyr workspace (default: ${WORKSPACE})
  --sdk-dir DIR     Zephyr SDK (default: ${SDK_DIR})
  --app DIR         Application source tree (default: repo example)
  --build-dir DIR   Build output (default: ${BUILD_DIR})
  --incremental     Do not wipe the build directory first
  -h, --help        Show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --workspace) WORKSPACE="$2"; BUILD_DIR="${WORKSPACE}/build/flappy-microchip"; shift 2 ;;
        --sdk-dir) SDK_DIR="$2"; shift 2 ;;
        --app) APP_SOURCE="$2"; shift 2 ;;
        --build-dir) BUILD_DIR="$2"; shift 2 ;;
        --incremental) PRISTINE=never; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown option $1" >&2; exit 2 ;;
    esac
done

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

WEST="${WORKSPACE}/.venv/bin/west"
APP="${APP_SOURCE}/demos/pic64_smp_hello"

[ -x "${WEST}" ] || die "west not found at ${WEST}. Run setup/linux/setup.sh first."
[ -d "${APP}" ] || die "application not found: ${APP}"
[ -d "${WORKSPACE}/zephyr" ] || die "Zephyr tree missing at ${WORKSPACE}/zephyr. Run setup/linux/setup.sh first."

if [ ! -d "${WORKSPACE}/zephyr/boards/microchip/pic64gx_curiosity_kit" ]; then
    die "board pic64gx_curiosity_kit missing from the Zephyr tree.
It was introduced in Zephyr v4.4.0; setup/common/versions.env pins ${ZEPHYR_REVISION}.
Re-run setup/linux/setup.sh to correct the checkout."
fi

export ZEPHYR_BASE="${WORKSPACE}/zephyr"
export ZEPHYR_SDK_INSTALL_DIR="${SDK_DIR}"
export ZEPHYR_TOOLCHAIN_VARIANT=zephyr

info "Building ${BOARD_TARGET}"
"${WEST}" build \
    -b "${BOARD_TARGET}" \
    -d "${BUILD_DIR}" \
    -p "${PRISTINE}" \
    "${APP}"

ELF="${BUILD_DIR}/zephyr/zephyr.elf"
[ -f "${ELF}" ] || die "build finished but ${ELF} is missing"

printf '\n\033[32mBuild complete\033[0m\n  %s (%s bytes)\n\n' "${ELF}" "$(stat -c%s "${ELF}" 2>/dev/null || stat -f%z "${ELF}")"
echo "Next: ./setup/linux/payload.sh"
