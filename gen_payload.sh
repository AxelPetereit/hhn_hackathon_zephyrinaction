#!/bin/bash
set -e

HSS_GEN=~/hss-payload-generator/hss-payload-generator/binaries/hss-payload-generator
YAML=~/zephyr_git/pic64gx-zephyr/demos/pic64_smp_hello/hss-payload.yaml
OUT=~/zephyr/build/pic64_smp_hello/zephyr/payload.bin

echo "=== Generating HSS payload ==="
"$HSS_GEN" -c "$YAML" "$OUT"
echo "GEN_OK"
ls -lh "$OUT"
