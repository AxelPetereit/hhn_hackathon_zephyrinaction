#!/usr/bin/env bash
# Copyright (c) 2026 Microchip Technology Inc
# SPDX-License-Identifier: MIT
#
# Verifies the line endings that git will actually store.
#
# This matters because the repository is developed on Windows but the shell
# scripts run on Linux and macOS. A CRLF shell script fails with a confusing
# "bad interpreter" error, and a CR at the end of a sourced KEY=value line
# becomes part of the value, silently corrupting it.
#
# Run from the repository root, after staging your changes.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../../.." || exit 1
FAILED=0

pass() { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAILED=1; }

count_cr() {
    git cat-file blob ":$1" 2>/dev/null | tr -cd '\r' | wc -c | tr -d ' '
}

is_staged() {
    git ls-files --error-unmatch "$1" >/dev/null 2>&1
}

echo "[LF required: shell scripts, Python, YAML, versions.env]"
LF_FILES=$(git ls-files 'setup/**/*.sh' 'setup/**/*.py' 'setup/common/versions.env' \
    '*.yaml' '*.yml' 2>/dev/null)
if [ -z "${LF_FILES}" ]; then
    echo "  (nothing staged yet; run git add first)"
fi
for f in ${LF_FILES}; do
    is_staged "$f" || continue
    n=$(count_cr "$f")
    if [ "${n}" = "0" ]; then
        pass "$f"
    else
        fail "$f has ${n} CR bytes in the stored blob"
    fi
done

echo
echo "[CRLF expected: PowerShell scripts]"
for f in $(git ls-files 'setup/**/*.ps1' 2>/dev/null); do
    is_staged "$f" || continue
    n=$(count_cr "$f")
    if [ "${n}" != "0" ]; then
        pass "$f (${n} CR bytes, as configured)"
    else
        # Not fatal: PowerShell reads LF fine. Worth noting though.
        printf '  \033[33mNOTE\033[0m %s is stored with LF; PowerShell accepts it\n' "$f"
    fi
done

echo
echo "[executable bit on shell scripts]"
for f in $(git ls-files 'setup/**/*.sh' 2>/dev/null); do
    mode=$(git ls-files -s "$f" | awk '{print $1}')
    if [ "${mode}" = "100755" ]; then
        pass "$f is executable"
    else
        fail "$f has mode ${mode}, expected 100755 (git update-index --chmod=+x $f)"
    fi
done

echo
echo "[sourced env file parses cleanly]"
# Prove the stored blob can be sourced without CR contamination.
TMP=$(mktemp)
git cat-file blob ":setup/common/versions.env" > "${TMP}" 2>/dev/null
if [ -s "${TMP}" ]; then
    # shellcheck disable=SC1090
    . "${TMP}"
    if [ "${BOARD_TARGET:-}" = "pic64gx_curiosity_kit/pic64gx1000/u54/smp" ]; then
        pass "BOARD_TARGET reads back exactly"
    else
        fail "BOARD_TARGET is [${BOARD_TARGET:-unset}], which suggests CR contamination"
    fi
    if [ "${PAYLOAD_SECTOR:-}" = "139264" ]; then
        pass "PAYLOAD_SECTOR reads back exactly"
    else
        fail "PAYLOAD_SECTOR is [${PAYLOAD_SECTOR:-unset}]"
    fi
    # Arithmetic on the value would fail outright if a CR were attached
    if [ $(( ${PAYLOAD_SECTOR:-0} * 512 )) -eq 71303168 ]; then
        pass "PAYLOAD_SECTOR is usable in arithmetic"
    else
        fail "PAYLOAD_SECTOR is not a clean integer"
    fi
else
    fail "could not read setup/common/versions.env from the index"
fi
rm -f "${TMP}"

echo
if [ "${FAILED}" -eq 0 ]; then
    printf '\033[32mLine endings and permissions are correct.\033[0m\n'
else
    printf '\033[31mLine ending or permission problems found.\033[0m\n'
    printf 'Fix with: git add --renormalize . && git update-index --chmod=+x <script>\n'
fi
exit "${FAILED}"
