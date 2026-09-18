#!/usr/bin/env bash
# Copyright (c) 2026 Microchip Technology Inc
# SPDX-License-Identifier: MIT
#
# Static checks for the setup scripts: bash syntax, shellcheck when present, and
# a scan for constructs that break on macOS (BSD userland) but work on Linux.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FAILED=0

pass() { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAILED=1; }
skip() { printf '  \033[33mSKIP\033[0m %s\n' "$*"; }

SCRIPTS=$(find "${REPO_ROOT}/setup" -name '*.sh' -type f | sort)

echo "[bash syntax]"
for f in ${SCRIPTS}; do
    if out=$(bash -n "$f" 2>&1); then
        pass "$(basename "$(dirname "$f")")/$(basename "$f")"
    else
        fail "$(basename "$f"): ${out}"
    fi
done

echo
echo "[shellcheck]"
if command -v shellcheck >/dev/null 2>&1; then
    for f in ${SCRIPTS}; do
        if out=$(shellcheck -S warning -e SC1091 "$f" 2>&1); then
            pass "$(basename "$(dirname "$f")")/$(basename "$f")"
        else
            fail "$(basename "$f")"
            echo "${out}" | sed 's/^/        /'
        fi
    done
else
    skip "shellcheck not installed"
fi

echo
echo "[macOS portability]"
# stat -c is GNU only; BSD stat uses -f. Scripts must handle both or avoid stat.
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for f in ${SCRIPTS}; do
    name="$(basename "$(dirname "$f")")/$(basename "$f")"
    # The scripts in tests/ contain the very patterns searched for here, and they
    # only ever run on a developer machine, not as part of a participant setup.
    if [ "$(dirname "$f")" = "${TESTS_DIR}" ]; then
        skip "${name} (test helper, contains the search patterns itself)"
        continue
    fi
    problems=""

    # stat must either not be used, or be used with both spellings on one line
    # (either order: GNU-first for Linux scripts, BSD-first for macOS scripts)
    if grep -qE '\bstat -[cf]' "$f"; then
        if ! grep -qE 'stat -c[^|]*\|\|[^|]*stat -f|stat -f[^|]*\|\|[^|]*stat -c' "$f"; then
            problems="${problems} stat used without a GNU/BSD fallback;"
        fi
    fi
    # GNU sed -i needs no argument, BSD sed -i requires one
    if grep -qE "sed -i[^.']" "$f"; then
        problems="${problems} sed -i (differs GNU vs BSD);"
    fi
    if grep -qE '\breadlink -f\b' "$f" && [[ "$f" == *macos* ]]; then
        problems="${problems} readlink -f (not on older macOS);"
    fi
    if grep -qE '\bgrep -P\b' "$f"; then
        problems="${problems} grep -P (not in BSD grep);"
    fi

    if [ -n "${problems}" ]; then
        fail "${name}:${problems}"
    else
        pass "${name}"
    fi
done

echo
echo "[shebang and permissions]"
for f in ${SCRIPTS}; do
    name="$(basename "$(dirname "$f")")/$(basename "$f")"
    head -n1 "$f" | grep -q '^#!/usr/bin/env bash$' \
        && pass "${name} shebang" \
        || fail "${name} shebang is $(head -n1 "$f")"
done

echo
if [ "${FAILED}" -eq 0 ]; then
    printf '\033[32mAll static checks passed.\033[0m\n'
else
    printf '\033[31mStatic checks reported problems.\033[0m\n'
fi
exit "${FAILED}"
