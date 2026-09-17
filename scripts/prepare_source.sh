#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${PIC64GX_SOURCE_DIR:-$HOME/zephyr_git/pic64gx-zephyr}"
SOURCE_URL="${PIC64GX_SOURCE_URL:-https://bitbucket.microchip.com/scm/fpga-mcx/pic64gx-zephyr.git}"
PATCH_FILE="$ROOT/flappy-working-v1.patch"
FLAPPY_COMMIT="5a0c7bee03a70fa342b584fbaecbb6f56a164db9"

if [[ ! -f "$PATCH_FILE" ]]; then
    echo "Patch not found: $PATCH_FILE" >&2
    exit 1
fi

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
    mkdir -p "$(dirname "$SOURCE_DIR")"
    echo "==> Cloning PIC64GX application repository"
    git clone "$SOURCE_URL" "$SOURCE_DIR"
fi

cd "$SOURCE_DIR"

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Source repository has local changes: $SOURCE_DIR" >&2
    echo "Commit or stash them before running this script." >&2
    exit 1
fi

if git cat-file -e "$FLAPPY_COMMIT^{commit}" 2>/dev/null; then
    echo "==> Flappy Microchip commit already exists"
    git checkout --detach "$FLAPPY_COMMIT"
else
    echo "==> Applying Flappy Microchip patch"
    git checkout main
    git am "$PATCH_FILE"
fi

echo "Source ready: $SOURCE_DIR"
