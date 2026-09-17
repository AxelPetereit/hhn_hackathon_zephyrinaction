#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/env.sh"

APP_DIR="$PIC64GX_SOURCE_DIR/demos/pic64_smp_hello"

if [[ ! -d "$APP_DIR" ]]; then
    echo "Application not found: $APP_DIR" >&2
    echo "Run: bash scripts/prepare_source.sh" >&2
    exit 1
fi

echo "==> Building Flappy Microchip"
west build \
    -b pic64gx_curiosity_kit/pic64gx1000/u54/smp \
    -d "$PIC64GX_BUILD_DIR" \
    -p always \
    "$APP_DIR"

echo
echo "Build complete: $PIC64GX_BUILD_DIR/zephyr/zephyr.elf"
