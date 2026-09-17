#!/bin/bash
set -e

HSS_URL="https://github.com/polarfire-soc/hart-software-services/releases/download/v2026.04.1/hss-payload-generator-v2026.04.1.zip"
DEST="$HOME/hss-payload-generator"

echo "[1/3] Downloading HSS Payload Generator..."
mkdir -p "$DEST"
wget -q --show-progress -O /tmp/hss-payload-generator.zip "$HSS_URL"

echo "[2/3] Extracting with Python..."
python3 -c "
import zipfile, os
with zipfile.ZipFile('/tmp/hss-payload-generator.zip') as z:
    z.extractall('$DEST')
print('Extracted OK')
"
rm /tmp/hss-payload-generator.zip

echo "[3/3] Finding binary..."
find "$DEST" -name "hss-payload-generator" -type f
echo "HSS_GENERATOR_OK"
