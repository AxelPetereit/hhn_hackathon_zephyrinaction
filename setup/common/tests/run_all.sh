#!/usr/bin/env bash
# Copyright (c) 2026 Microchip Technology Inc
# SPDX-License-Identifier: MIT
#
# Runs every check that does not need real hardware:
#   - bash syntax, shellcheck and GNU/BSD portability of all shell scripts
#   - macOS-specific logic checks
#   - the payload generator test suite, differentially against the official tool
#     when one can be found
#
# Use this before pushing changes to the setup scripts.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TESTS_DIR="${REPO_ROOT}/setup/common/tests"
FAILED=0

section() { printf '\n\033[1;36m%s\033[0m\n' "=== $* ==="; }

section "shell script static checks"
bash "${TESTS_DIR}/syntax_check.sh" || FAILED=1

section "line endings and file modes"
bash "${TESTS_DIR}/check_line_endings.sh" || FAILED=1

section "macOS logic checks"
bash "${TESTS_DIR}/macos_logic_check.sh" || FAILED=1

section "payload generator test suite"
PY="$(command -v python3 || command -v python || true)"
if [ -z "${PY}" ]; then
    printf '  \033[31mFAIL\033[0m no python interpreter found\n'
    FAILED=1
else
    # Prefer a workspace venv if one exists
    for candidate in "${HOME}/pic64gx-zephyr/.venv/bin/python" "${PY}"; do
        if [ -x "${candidate}" ]; then PY="${candidate}"; break; fi
    done

    REF=""
    for dir in "${HOME}"/hss-payload-generator-*; do
        [ -d "${dir}" ] || continue
        found="$(find "${dir}" -type f -name 'hss-payload-generator' 2>/dev/null | head -n1)"
        if [ -n "${found}" ]; then REF="${found}"; break; fi
    done

    if [ -n "${REF}" ]; then
        printf '  using reference tool %s\n' "${REF}"
        "${PY}" "${TESTS_DIR}/run_tests.py" --reference "${REF}" || FAILED=1
    else
        printf '  no official generator found, running self-checks only\n'
        "${PY}" "${TESTS_DIR}/run_tests.py" || FAILED=1
    fi
fi

printf '\n'
if [ "${FAILED}" -eq 0 ]; then
    printf '\033[1;32mAll checks passed.\033[0m\n'
else
    printf '\033[1;31mSome checks failed.\033[0m\n'
fi
exit "${FAILED}"
