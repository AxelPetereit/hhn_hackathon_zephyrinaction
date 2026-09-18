#!/usr/bin/env bash
# Copyright (c) 2026 Microchip Technology Inc
# SPDX-License-Identifier: MIT
#
# PIC64GX Zephyr hackathon environment setup for macOS (Apple Silicon).
#
# Installs host tools via Homebrew, creates a Python venv with west, fetches a
# pinned Zephyr tree and installs the Zephyr SDK riscv64 toolchain.
#
# One important difference from Windows and Linux: there is no macOS build of the
# official hss-payload-generator. The upstream release ships a Windows .exe and a
# Linux x86_64 ELF binary only, and building it from source needs libelf/gelf.h
# from elfutils, which Homebrew provides for Linux only. This setup therefore
# uses the portable generator in setup/common/hss_payload.py, which produces
# semantically identical images (verified against the official tool, see
# setup/common/tests/).
#
# Safe to re-run: every step is skipped if it is already satisfied.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMMON_DIR="${REPO_ROOT}/setup/common"

# shellcheck disable=SC1091
. "${COMMON_DIR}/versions.env"

WORKSPACE="${WORKSPACE:-${HOME}/pic64gx-zephyr}"
SDK_DIR="${SDK_DIR:-${HOME}/zephyr-sdk-${ZEPHYR_SDK_VERSION}}"
SKIP_HOST_TOOLS=0
DRY_RUN=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --workspace DIR      Zephyr workspace (default: ${WORKSPACE})
  --sdk-dir DIR        Zephyr SDK location (default: ${SDK_DIR})
  --skip-host-tools    Do not install Homebrew packages
  --dry-run            Print what would happen, change nothing
  -h, --help           Show this help

Pinned versions (setup/common/versions.env):
  Zephyr      ${ZEPHYR_REVISION}
  Zephyr SDK  ${ZEPHYR_SDK_VERSION} (${ZEPHYR_SDK_TOOLCHAIN})
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --workspace) WORKSPACE="$2"; shift 2 ;;
        --sdk-dir) SDK_DIR="$2"; shift 2 ;;
        --skip-host-tools) SKIP_HOST_TOOLS=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown option $1" >&2; usage >&2; exit 2 ;;
    esac
done

info()  { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()    { printf '\033[32m  ok\033[0m %s\n' "$*"; }
warn()  { printf '\033[33m  !!\033[0m %s\n' "$*" >&2; }
die()   { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

run() {
    if [ "${DRY_RUN}" -eq 1 ]; then
        printf '  would run: %s\n' "$*"
    else
        "$@"
    fi
}

# ---------------------------------------------------------------------------

info "Checking platform"
[ "$(uname -s)" = "Darwin" ] || die "this script is for macOS; use setup/linux or setup/windows instead"

ARCH="$(uname -m)"
if [ "${ARCH}" != "arm64" ]; then
    die "unsupported architecture ${ARCH}.

The Zephyr SDK ${ZEPHYR_SDK_VERSION} ships only a macos-aarch64 bundle; there is
no macOS x86_64 build. On an Intel Mac, use one of:
  - a Linux machine or VM with setup/linux/setup.sh
  - a Windows machine with setup/windows/setup.ps1
  - Docker with a linux/amd64 image"
fi
ok "macOS $(sw_vers -productVersion) on ${ARCH}"

# ---------------------------------------------------------------------------

if [ "${SKIP_HOST_TOOLS}" -eq 0 ]; then
    info "Installing host tools with Homebrew"
    if ! command -v brew >/dev/null 2>&1; then
        die "Homebrew was not found.

Install it from https://brew.sh, then open a new terminal and re-run this
script. If your Mac already has the Zephyr host tools, use:
  ./setup/macos/setup.sh --skip-host-tools"
    fi

    # Zephyr host dependencies. curl and git come with macOS and the Xcode command
    # line tools, so they are not installed here.
    BREW_PKGS="cmake ninja gperf dtc ccache qemu python@${PYTHON_PREFERRED}"
    # shellcheck disable=SC2086
    run brew install ${BREW_PKGS}
    ok "Homebrew packages installed"
else
    info "Skipping host tools as requested"
fi

info "Verifying required commands"
MISSING=""
for cmd in git cmake ninja gperf dtc curl tar; do
    command -v "${cmd}" >/dev/null 2>&1 || MISSING="${MISSING} ${cmd}"
done
if [ -n "${MISSING}" ]; then
    die "missing required commands:${MISSING}

If Homebrew has just installed them, open a new terminal so that PATH picks up
/opt/homebrew/bin, then re-run this script."
fi

CMAKE_VER="$(cmake --version | head -n1 | awk '{print $3}')"
CMAKE_MAJOR="${CMAKE_VER%%.*}"
CMAKE_REST="${CMAKE_VER#*.}"
CMAKE_MINOR="${CMAKE_REST%%.*}"
if [ "${CMAKE_MAJOR}" -lt 3 ] || { [ "${CMAKE_MAJOR}" -eq 3 ] && [ "${CMAKE_MINOR}" -lt 20 ]; }; then
    die "cmake ${CMAKE_VER} is too old, Zephyr needs 3.20 or newer"
fi
ok "cmake ${CMAKE_VER}, ninja $(ninja --version)"

# Xcode command line tools provide git, make and the system clang that some
# module build steps rely on.
if ! xcode-select -p >/dev/null 2>&1; then
    die "Xcode command line tools are missing. Install them with:
  xcode-select --install"
fi
ok "Xcode command line tools at $(xcode-select -p)"

# ---------------------------------------------------------------------------

info "Creating Python virtual environment"
VENV="${WORKSPACE}/.venv"

pick_python() {
    local candidate
    for candidate in \
        "$(brew --prefix 2>/dev/null)/opt/python@${PYTHON_PREFERRED}/bin/python${PYTHON_PREFERRED}" \
        "python${PYTHON_PREFERRED}" \
        python3; do
        if command -v "${candidate}" >/dev/null 2>&1; then
            command -v "${candidate}"
            return 0
        fi
    done
    return 1
}

if [ ! -x "${VENV}/bin/python" ]; then
    HOST_PY="$(pick_python)" || die "no usable python3 found"
    run mkdir -p "${WORKSPACE}"
    run "${HOST_PY}" -m venv "${VENV}"
    if [ "${DRY_RUN}" -eq 0 ]; then
        [ -x "${VENV}/bin/python" ] || die "python -m venv did not create ${VENV}"
    fi
    ok "venv created from ${HOST_PY}"
else
    ok "venv already present"
fi

PY="${VENV}/bin/python"
WEST="${VENV}/bin/west"

if [ "${DRY_RUN}" -eq 0 ]; then
    "${PY}" -m pip install --quiet --upgrade pip
    "${PY}" -m pip install --quiet west
    [ -x "${WEST}" ] || die "west was not installed into ${VENV}"
    ok "$("${PY}" --version), west $("${WEST}" --version | awk '{print $NF}')"
fi

# ---------------------------------------------------------------------------

info "Fetching Zephyr ${ZEPHYR_REVISION}"
if [ ! -f "${WORKSPACE}/.west/config" ]; then
    run "${WEST}" init --mr "${ZEPHYR_REVISION}" "${WORKSPACE}"
    ok "workspace initialised at revision ${ZEPHYR_REVISION}"
else
    ok "workspace already initialised"
fi

if [ "${DRY_RUN}" -eq 0 ]; then
    ( cd "${WORKSPACE}" && "${WEST}" update --narrow --fetch smart )
    ( cd "${WORKSPACE}" && "${WEST}" zephyr-export )
    "${PY}" -m pip install --quiet -r "${WORKSPACE}/zephyr/scripts/requirements.txt"
    ok "Zephyr modules and Python requirements ready"

    if [ ! -d "${WORKSPACE}/zephyr/boards/microchip/pic64gx_curiosity_kit" ]; then
        die "board pic64gx_curiosity_kit not found in ${WORKSPACE}/zephyr.

This board was added in Zephyr v4.4.0. setup/common/versions.env pins
${ZEPHYR_REVISION}, which does contain it, so the workspace was probably created
earlier against another revision. Remove ${WORKSPACE} and re-run this script."
    fi
    ok "board pic64gx_curiosity_kit present"
fi

# ---------------------------------------------------------------------------

info "Installing Zephyr SDK ${ZEPHYR_SDK_VERSION}"
if [ ! -f "${SDK_DIR}/cmake/Zephyr-sdkConfig.cmake" ]; then
    SDK_ARCHIVE="zephyr-sdk-${ZEPHYR_SDK_VERSION}_macos-aarch64_minimal.tar.xz"
    SDK_URL="https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${ZEPHYR_SDK_VERSION}/${SDK_ARCHIVE}"
    TMP_SDK="$(mktemp -d)"
    trap 'rm -rf "${TMP_SDK}"' EXIT

    info "Downloading ${SDK_ARCHIVE} (about 100 MB)"
    # curl is always present on macOS; wget is not guaranteed
    run curl -fL --progress-bar -o "${TMP_SDK}/${SDK_ARCHIVE}" "${SDK_URL}"

    run mkdir -p "$(dirname "${SDK_DIR}")"
    run tar -xf "${TMP_SDK}/${SDK_ARCHIVE}" -C "$(dirname "${SDK_DIR}")"

    if [ "${DRY_RUN}" -eq 0 ]; then
        [ -d "${SDK_DIR}" ] || die "the SDK did not extract to ${SDK_DIR}"
        ( cd "${SDK_DIR}" && ./setup.sh -t "${ZEPHYR_SDK_TOOLCHAIN}" -c )
    fi
    rm -rf "${TMP_SDK}"
    trap - EXIT
    ok "SDK installed at ${SDK_DIR}"
else
    ok "SDK already present at ${SDK_DIR}"
fi

if [ "${DRY_RUN}" -eq 0 ]; then
    # SDK 1.0.x puts toolchains in gnu/<triple>/bin; older layouts used
    # <triple>/bin. Search rather than assume.
    find_gcc() {
        local candidate
        for candidate in \
            "${SDK_DIR}/gnu/${ZEPHYR_SDK_TOOLCHAIN}/bin/${ZEPHYR_SDK_TOOLCHAIN}-gcc" \
            "${SDK_DIR}/${ZEPHYR_SDK_TOOLCHAIN}/bin/${ZEPHYR_SDK_TOOLCHAIN}-gcc"; do
            if [ -x "${candidate}" ]; then
                printf '%s' "${candidate}"
                return 0
            fi
        done
        find "${SDK_DIR}" -type f -name "${ZEPHYR_SDK_TOOLCHAIN}-gcc" 2>/dev/null | head -n1
    }

    GCC="$(find_gcc)"
    if [ -z "${GCC}" ]; then
        info "Fetching ${ZEPHYR_SDK_TOOLCHAIN} toolchain"
        ( cd "${SDK_DIR}" && ./setup.sh -t "${ZEPHYR_SDK_TOOLCHAIN}" -c )
        GCC="$(find_gcc)"
    fi
    [ -n "${GCC}" ] || die "toolchain ${ZEPHYR_SDK_TOOLCHAIN} not found below ${SDK_DIR}"

    # Gatekeeper quarantines downloaded binaries. Clear the attribute so the
    # toolchain can run without a per-binary security prompt.
    if command -v xattr >/dev/null 2>&1; then
        xattr -dr com.apple.quarantine "${SDK_DIR}" 2>/dev/null || true
    fi

    if ! "${GCC}" --version >/dev/null 2>&1; then
        die "the toolchain at ${GCC} will not execute.

macOS may have blocked it. Try:
  xattr -dr com.apple.quarantine ${SDK_DIR}
and allow it under System Settings > Privacy & Security if prompted."
    fi
    ok "toolchain $("${GCC}" --version | head -n1)"
fi

# ---------------------------------------------------------------------------

info "Payload generator"
cat <<'EOF'
  The official hss-payload-generator has no macOS build: the upstream release
  contains a Windows .exe and a Linux x86_64 ELF binary only, and compiling it
  here would need libelf/gelf.h from elfutils, which Homebrew supports on Linux
  only. This setup uses setup/common/hss_payload.py instead. It is a pure
  standard-library implementation whose output is verified byte for byte against
  the official tool.
EOF

if [ "${DRY_RUN}" -eq 0 ]; then
    if "${PY}" "${COMMON_DIR}/tests/run_tests.py" > /tmp/hss_selftest.log 2>&1; then
        ok "$(tail -n1 /tmp/hss_selftest.log)"
    else
        warn "payload generator self-test reported failures, see /tmp/hss_selftest.log"
    fi
fi

# ---------------------------------------------------------------------------

info "Writing environment file"
if [ "${DRY_RUN}" -eq 0 ]; then
    ENV_FILE="${WORKSPACE}/pic64gx-env.sh"
    cat > "${ENV_FILE}" <<EOF
# Generated by setup/macos/setup.sh. Source this before building by hand.
export ZEPHYR_BASE="${WORKSPACE}/zephyr"
export ZEPHYR_SDK_INSTALL_DIR="${SDK_DIR}"
export ZEPHYR_TOOLCHAIN_VARIANT=zephyr
export PATH="${VENV}/bin:\${PATH}"
EOF
    ok "wrote ${ENV_FILE}"
fi

cat <<EOF

Setup complete.

  Workspace     ${WORKSPACE}
  Zephyr        ${WORKSPACE}/zephyr (${ZEPHYR_REVISION})
  SDK           ${SDK_DIR}
  Board target  ${BOARD_TARGET}

Next steps:

  ./setup/macos/build.sh              build the example
  ./setup/macos/payload.sh            create payload.bin
  ./setup/macos/flash.sh --list       find your SD card
  sudo ./setup/macos/flash.sh --device /dev/rdiskN

EOF
