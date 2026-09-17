#!/usr/bin/env bash

# Shared environment for the PIC64GX Zephyr workshop.
# This file must be sourced, not executed.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Use: source scripts/env.sh"
    exit 1
fi

WORKSHOP_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export WORKSHOP_ROOT

export ZEPHYR_WORKSPACE="${ZEPHYR_WORKSPACE:-$HOME/zephyr}"
export ZEPHYR_BASE="${ZEPHYR_BASE:-$ZEPHYR_WORKSPACE/zephyr}"
export ZEPHYR_SDK_INSTALL_DIR="${ZEPHYR_SDK_INSTALL_DIR:-$HOME/zephyr-sdk-1.0.1}"
export PIC64GX_SOURCE_DIR="${PIC64GX_SOURCE_DIR:-$HOME/zephyr_git/pic64gx-zephyr}"
export PIC64GX_SOURCE_URL="${PIC64GX_SOURCE_URL:-https://bitbucket.microchip.com/scm/fpga-mcx/pic64gx-zephyr.git}"
export PIC64GX_BUILD_DIR="${PIC64GX_BUILD_DIR:-$ZEPHYR_WORKSPACE/build/pic64_smp_hello}"
export HSS_GENERATOR="${HSS_GENERATOR:-$HOME/hss-payload-generator/hss-payload-generator/binaries/hss-payload-generator}"

ZEPHYR_VENV="${ZEPHYR_VENV:-$HOME/.zephyrenv}"
if [[ ! -f "$ZEPHYR_VENV/bin/activate" ]]; then
    echo "Python environment not found: $ZEPHYR_VENV" >&2
    echo "Run: bash scripts/setup_zephyr.sh" >&2
    return 1
fi

source "$ZEPHYR_VENV/bin/activate"
export PATH="$ZEPHYR_SDK_INSTALL_DIR/gnu/riscv64-zephyr-elf/bin:$PATH"
