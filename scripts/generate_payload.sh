#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/env.sh"

APP_DIR="$PIC64GX_SOURCE_DIR/demos/pic64_smp_hello"
ELF="$PIC64GX_BUILD_DIR/zephyr/zephyr.elf"
BUILD_PAYLOAD="$PIC64GX_BUILD_DIR/zephyr/payload.bin"
OUTPUT="${PAYLOAD_OUT:-$ROOT/payload.bin}"

if [[ ! -x "$HSS_GENERATOR" ]]; then
    echo "HSS payload generator not found: $HSS_GENERATOR" >&2
    echo "Run: bash scripts/setup_zephyr.sh" >&2
    exit 1
fi

if [[ ! -f "$ELF" ]]; then
    echo "Zephyr ELF not found: $ELF" >&2
    echo "Run: bash scripts/build_flappy.sh" >&2
    exit 1
fi

if [[ ! -f "$APP_DIR/hss-payload.yaml" ]]; then
    echo "HSS configuration not found: $APP_DIR/hss-payload.yaml" >&2
    exit 1
fi

TMP_YAML="$(mktemp --suffix=.yaml)"
trap 'rm -f "$TMP_YAML"' EXIT

# The source example contains a user-specific example path. Generate a local
# copy instead of changing the checked-out source repository.
sed -E "s|^  .*/zephyr/build/pic64_smp_hello/zephyr/zephyr.elf:|  $ELF:|" \
    "$APP_DIR/hss-payload.yaml" > "$TMP_YAML"

echo "==> Generating HSS payload"
mkdir -p "$(dirname "$BUILD_PAYLOAD")" "$(dirname "$OUTPUT")"
"$HSS_GENERATOR" -c "$TMP_YAML" "$BUILD_PAYLOAD"
cp "$BUILD_PAYLOAD" "$OUTPUT"

echo "Payload ready: $OUTPUT"
