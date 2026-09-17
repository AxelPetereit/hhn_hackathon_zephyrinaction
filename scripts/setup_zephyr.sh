#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VENV="${ZEPHYR_VENV:-$HOME/.zephyrenv}"
WORKSPACE="${ZEPHYR_WORKSPACE:-$HOME/zephyr}"
SDK_DIR="${ZEPHYR_SDK_INSTALL_DIR:-$HOME/zephyr-sdk-1.0.1}"
SDK_VERSION="1.0.1"
SDK_URL="https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${SDK_VERSION}/zephyr-sdk-${SDK_VERSION}_linux-x86_64_minimal.tar.xz"
HSS_DIR="${HSS_DIR:-$HOME/hss-payload-generator}"
HSS_VERSION="${HSS_VERSION:-2026.04.1}"
HSS_URL="https://github.com/polarfire-soc/hart-software-services/releases/download/v${HSS_VERSION}/hss-payload-generator-v${HSS_VERSION}.zip"

echo "==> Installing Ubuntu packages"
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    cmake \
    device-tree-compiler \
    file \
    git \
    gperf \
    ninja-build \
    python3-dev \
    python3-pip \
    python3-venv \
    unzip \
    wget \
    xz-utils

echo "==> Creating Python environment: $VENV"
if [[ ! -f "$VENV/bin/activate" ]]; then
    python3 -m venv "$VENV"
fi
source "$VENV/bin/activate"
python -m pip install --upgrade pip
python -m pip install west

echo "==> Creating west workspace: $WORKSPACE"
if [[ ! -f "$WORKSPACE/.west/config" ]]; then
    if [[ -d "$WORKSPACE" ]] && [[ -n "$(ls -A "$WORKSPACE")" ]]; then
        echo "Workspace exists and is not a west workspace: $WORKSPACE" >&2
        echo "Choose another ZEPHYR_WORKSPACE or remove the incomplete directory." >&2
        exit 1
    fi
    west init "$WORKSPACE"
fi

cd "$WORKSPACE"
echo "==> Downloading Zephyr modules"
west update --narrow --fetch-opt=--depth=1
python -m pip install -r zephyr/scripts/requirements.txt

echo "==> Installing Zephyr SDK $SDK_VERSION"
if [[ ! -x "$SDK_DIR/setup.sh" ]]; then
    tmp_sdk="$(mktemp --suffix=.tar.xz)"
    trap 'rm -f "$tmp_sdk"' EXIT
    wget -q --show-progress -O "$tmp_sdk" "$SDK_URL"
    tar xf "$tmp_sdk" -C "$HOME"
    "$SDK_DIR/setup.sh" -t riscv64-zephyr-elf -h -c
    rm -f "$tmp_sdk"
    trap - EXIT
else
    echo "SDK already exists: $SDK_DIR"
fi

echo "==> Installing HSS payload generator"
HSS_BIN="$HSS_DIR/hss-payload-generator/hss-payload-generator/binaries/hss-payload-generator"
if [[ ! -x "$HSS_BIN" ]]; then
    tmp_hss="$(mktemp --suffix=.zip)"
    trap 'rm -f "$tmp_hss"' EXIT
    mkdir -p "$HSS_DIR"
    wget -q --show-progress -O "$tmp_hss" "$HSS_URL"
    python3 -c "import zipfile; zipfile.ZipFile('$tmp_hss').extractall('$HSS_DIR')"
    rm -f "$tmp_hss"
    trap - EXIT
fi

if [[ ! -x "$HSS_BIN" ]]; then
    chmod +x "$HSS_BIN"
fi

echo
echo "Setup complete. Next:"
echo "  bash $ROOT/scripts/prepare_source.sh"
echo "  source $ROOT/scripts/env.sh"
