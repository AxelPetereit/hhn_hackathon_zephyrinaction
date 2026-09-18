#!/usr/bin/env bash
# Copyright (c) 2026 Microchip Technology Inc
# SPDX-License-Identifier: MIT
#
# PIC64GX Zephyr hackathon environment setup for Linux.
#
# Installs host tools, creates a Python venv with west, fetches a pinned Zephyr
# tree, installs the Zephyr SDK riscv64 toolchain and the HSS payload generator.
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
HSS_DIR="${HSS_DIR:-${HOME}/hss-payload-generator-${HSS_VERSION}}"
SKIP_HOST_TOOLS=0
DRY_RUN=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --workspace DIR      Zephyr workspace (default: ${WORKSPACE})
  --sdk-dir DIR        Zephyr SDK location (default: ${SDK_DIR})
  --hss-dir DIR        HSS payload generator location (default: ${HSS_DIR})
  --skip-host-tools    Do not install distro packages
  --dry-run            Print what would happen, change nothing
  -h, --help           Show this help

Pinned versions (setup/common/versions.env):
  Zephyr      ${ZEPHYR_REVISION}
  Zephyr SDK  ${ZEPHYR_SDK_VERSION} (${ZEPHYR_SDK_TOOLCHAIN})
  HSS tool    ${HSS_VERSION}
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --workspace) WORKSPACE="$2"; shift 2 ;;
        --sdk-dir) SDK_DIR="$2"; shift 2 ;;
        --hss-dir) HSS_DIR="$2"; shift 2 ;;
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
ARCH="$(uname -m)"
case "${ARCH}" in
    x86_64)  SDK_HOST="linux-x86_64" ;;
    aarch64) SDK_HOST="linux-aarch64" ;;
    *) die "unsupported architecture ${ARCH}; the Zephyr SDK ships only linux-x86_64 and linux-aarch64" ;;
esac
ok "Linux ${ARCH} -> SDK bundle ${SDK_HOST}"

if [ "${ARCH}" != "x86_64" ]; then
    warn "The official HSS payload generator binary is x86_64 only."
    warn "On this machine the portable generator setup/common/hss_payload.py will be used instead."
fi

# ---------------------------------------------------------------------------

if [ "${SKIP_HOST_TOOLS}" -eq 0 ]; then
    info "Installing host tools"
    if command -v apt-get >/dev/null 2>&1; then
        PKGS="git cmake ninja-build gperf ccache dfu-util device-tree-compiler wget \
python3-dev python3-venv python3-pip python3-setuptools python3-tk python3-wheel \
xz-utils file make gcc libsdl2-dev libmagic1 curl"
        run sudo apt-get update
        # shellcheck disable=SC2086
        run sudo apt-get install -y ${PKGS}
    elif command -v dnf >/dev/null 2>&1; then
        run sudo dnf install -y git cmake ninja-build gperf ccache dfu-util dtc wget \
            python3-devel python3-pip python3-tkinter xz file make gcc SDL2-devel curl
    elif command -v pacman >/dev/null 2>&1; then
        run sudo pacman -Syu --needed --noconfirm git cmake ninja gperf ccache dfu-util \
            dtc wget python python-pip python-setuptools python-wheel tk xz file make \
            gcc sdl2 curl
    elif command -v zypper >/dev/null 2>&1; then
        run sudo zypper install -y git cmake ninja gperf ccache dfu-util dtc wget \
            python3-devel python3-pip python3-tk xz file make gcc libSDL2-devel curl
    else
        warn "No supported package manager found (apt/dnf/pacman/zypper)."
        warn "Install the Zephyr host dependencies manually, then re-run with --skip-host-tools."
    fi
    ok "Host tools step finished"
else
    info "Skipping host tools as requested"
fi

info "Verifying required commands"
MISSING=""
for cmd in git cmake python3 tar xz wget; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        MISSING="${MISSING} ${cmd}"
    fi
done
# ninja may be installed as ninja-build on some distros
if ! command -v ninja >/dev/null 2>&1 && ! command -v ninja-build >/dev/null 2>&1; then
    MISSING="${MISSING} ninja"
fi
if [ -n "${MISSING}" ]; then
    die "missing required commands:${MISSING}"
fi

CMAKE_VER="$(cmake --version | head -n1 | awk '{print $3}')"
ok "cmake ${CMAKE_VER}, python3 $(python3 --version 2>&1 | awk '{print $2}')"

# Zephyr needs CMake >= 3.20
CMAKE_MAJOR="${CMAKE_VER%%.*}"
CMAKE_REST="${CMAKE_VER#*.}"
CMAKE_MINOR="${CMAKE_REST%%.*}"
if [ "${CMAKE_MAJOR}" -lt 3 ] || { [ "${CMAKE_MAJOR}" -eq 3 ] && [ "${CMAKE_MINOR}" -lt 20 ]; }; then
    die "cmake ${CMAKE_VER} is too old, Zephyr needs 3.20 or newer"
fi

# ---------------------------------------------------------------------------

info "Creating Python virtual environment"
VENV="${WORKSPACE}/.venv"
if [ ! -x "${VENV}/bin/python" ]; then
    run mkdir -p "${WORKSPACE}"
    if ! run python3 -m venv "${VENV}"; then
        die "python3 -m venv failed; install the python3-venv package and retry"
    fi
    ok "venv created at ${VENV}"
else
    ok "venv already present"
fi

PY="${VENV}/bin/python"
WEST="${VENV}/bin/west"

if [ "${DRY_RUN}" -eq 0 ]; then
    "${PY}" -m pip install --quiet --upgrade pip
    "${PY}" -m pip install --quiet west
    ok "west $("${WEST}" --version 2>&1 | awk '{print $NF}') installed"
else
    printf '  would run: %s -m pip install west\n' "${PY}"
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
else
    printf '  would run: west update && west zephyr-export\n'
fi

# Confirm the board this project needs actually exists in the fetched tree.
BOARD_DIR="${WORKSPACE}/zephyr/boards/microchip/pic64gx_curiosity_kit"
if [ "${DRY_RUN}" -eq 0 ]; then
    if [ ! -d "${BOARD_DIR}" ]; then
        die "board pic64gx_curiosity_kit not found in ${WORKSPACE}/zephyr.
The pinned revision ${ZEPHYR_REVISION} should contain it. This board was added
in Zephyr v4.4.0, so anything older will not work."
    fi
    ok "board pic64gx_curiosity_kit present"
fi

# ---------------------------------------------------------------------------

info "Installing Zephyr SDK ${ZEPHYR_SDK_VERSION}"
# Zephyr-sdkConfig.cmake only exists once the bundle has been extracted, so it is
# a reliable "already installed" marker. setup.sh alone is not: it ships inside
# the archive, so testing for it would wrongly skip a partial install.
if [ ! -f "${SDK_DIR}/cmake/Zephyr-sdkConfig.cmake" ]; then
    SDK_ARCHIVE="zephyr-sdk-${ZEPHYR_SDK_VERSION}_${SDK_HOST}_minimal.tar.xz"
    SDK_URL="https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${ZEPHYR_SDK_VERSION}/${SDK_ARCHIVE}"
    TMP_SDK="$(mktemp -d)"
    trap 'rm -rf "${TMP_SDK}"' EXIT

    info "Downloading ${SDK_ARCHIVE} (about 100 MB)"
    run wget -q --show-progress -O "${TMP_SDK}/${SDK_ARCHIVE}" "${SDK_URL}"

    run mkdir -p "$(dirname "${SDK_DIR}")"
    run tar -xf "${TMP_SDK}/${SDK_ARCHIVE}" -C "$(dirname "${SDK_DIR}")"

    if [ "${DRY_RUN}" -eq 0 ]; then
        [ -d "${SDK_DIR}" ] || die "SDK did not extract to ${SDK_DIR}"
        ( cd "${SDK_DIR}" && ./setup.sh -t "${ZEPHYR_SDK_TOOLCHAIN}" -c )
    fi
    ok "SDK installed at ${SDK_DIR}"
    rm -rf "${TMP_SDK}"
    trap - EXIT
else
    ok "SDK already present at ${SDK_DIR}"
fi

if [ "${DRY_RUN}" -eq 0 ]; then
    # SDK 1.0.x places toolchains under gnu/<triple>/bin. Older layouts used
    # <triple>/bin directly. Search rather than assume.
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
    ok "toolchain $("${GCC}" --version | head -n1)"
fi

# ---------------------------------------------------------------------------

info "Installing HSS payload generator"
if [ "${ARCH}" = "x86_64" ]; then
    HSS_BIN="$(find "${HSS_DIR}" -type f -name 'hss-payload-generator' 2>/dev/null | head -n1 || true)"
    if [ -z "${HSS_BIN}" ]; then
        HSS_ARCHIVE="hss-payload-generator-${HSS_VERSION}.zip"
        HSS_URL="https://github.com/polarfire-soc/hart-software-services/releases/download/${HSS_VERSION}/${HSS_ARCHIVE}"
        TMP_HSS="$(mktemp -d)"
        run wget -q -O "${TMP_HSS}/${HSS_ARCHIVE}" "${HSS_URL}"
        run mkdir -p "${HSS_DIR}"
        if command -v unzip >/dev/null 2>&1; then
            run unzip -q -o "${TMP_HSS}/${HSS_ARCHIVE}" -d "${HSS_DIR}"
        else
            run "${PY}" -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" \
                "${TMP_HSS}/${HSS_ARCHIVE}" "${HSS_DIR}"
        fi
        rm -rf "${TMP_HSS}"
        if [ "${DRY_RUN}" -eq 0 ]; then
            HSS_BIN="$(find "${HSS_DIR}" -type f -name 'hss-payload-generator' | head -n1 || true)"
            [ -n "${HSS_BIN}" ] || die "hss-payload-generator not found below ${HSS_DIR}"
            chmod +x "${HSS_BIN}"
        fi
    fi
    if [ "${DRY_RUN}" -eq 0 ]; then
        ok "HSS generator at ${HSS_BIN}"
    fi
else
    ok "Skipping upstream HSS binary on ${ARCH}; the portable Python generator will be used"
fi

# ---------------------------------------------------------------------------

info "Verifying the portable payload generator"
if [ "${DRY_RUN}" -eq 0 ]; then
    TEST_ARGS=""
    if [ "${ARCH}" = "x86_64" ] && [ -n "${HSS_BIN:-}" ]; then
        TEST_ARGS="--reference ${HSS_BIN}"
    fi
    # shellcheck disable=SC2086
    if "${PY}" "${COMMON_DIR}/tests/run_tests.py" ${TEST_ARGS} >/tmp/hss_selftest.log 2>&1; then
        ok "$(tail -n1 /tmp/hss_selftest.log)"
    else
        warn "payload generator self-test reported failures, see /tmp/hss_selftest.log"
    fi
fi

# ---------------------------------------------------------------------------

info "Writing environment file"
ENV_FILE="${WORKSPACE}/pic64gx-env.sh"
if [ "${DRY_RUN}" -eq 0 ]; then
    cat > "${ENV_FILE}" <<EOF
# Generated by setup/linux/setup.sh. Source this before building by hand.
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

  ./setup/linux/build.sh              build the example
  ./setup/linux/payload.sh            create payload.bin
  ./setup/linux/flash.sh --list       find your SD card
  sudo ./setup/linux/flash.sh --device /dev/sdX

EOF
