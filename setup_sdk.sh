#!/bin/bash
set -e

# Download Zephyr SDK 1.0.1 minimal installer
SDK_URL="https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v1.0.1/zephyr-sdk-1.0.1_linux-x86_64_minimal.tar.xz"
SDK_DIR="$HOME/zephyr-sdk-1.0.1"

echo "[1/4] Downloading Zephyr SDK 1.0.1 minimal..."
wget -q --show-progress -O /tmp/zephyr-sdk-1.0.1_minimal.tar.xz "$SDK_URL"

echo "[2/4] Extracting SDK..."
mkdir -p "$SDK_DIR"
tar xf /tmp/zephyr-sdk-1.0.1_minimal.tar.xz -C "$HOME"
rm /tmp/zephyr-sdk-1.0.1_minimal.tar.xz

echo "[3/4] Installing RISC-V toolchain (riscv64-zephyr-elf)..."
cd "$SDK_DIR"
./setup.sh -t riscv64-zephyr-elf -h -c

echo "[4/4] SDK setup complete."
echo "SDK_OK"
