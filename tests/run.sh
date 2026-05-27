#!/usr/bin/env bash
# Compile every regression case under tests/regressions/. Exits non-zero
# if any case fails to compile (= a compiler regression).
#
# Each subdirectory of tests/regressions/ is itself a Nar package
# (`<dir>/nar.json`). The `lunar` CLI is asked to compile the package
# with that name; success ⇒ regression not reproducing.

set -u

cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$(pwd)"
REPO_ROOT="$(cd "$ROOT/.." && pwd)"

CASES_DIR="$ROOT/tests/regressions"
LUNAR_CLI="$ROOT/cli/init.lua"

fail=0
for dir in "$CASES_DIR"/*/; do
    pkg="$(basename "$dir")"
    binar="$(mktemp -t lunar-regression.XXXXXX.binar)"
    if lua "$LUNAR_CLI" -b "$binar" \
            -D "$CASES_DIR" -D "$REPO_ROOT" \
            -p "$pkg" \
            >/tmp/lunar-regression-stdout 2>/tmp/lunar-regression-stderr; then
        echo "ok    $pkg"
    else
        echo "FAIL  $pkg"
        echo "  --- stderr ---"
        sed 's/^/  /' /tmp/lunar-regression-stderr
        fail=1
    fi
    rm -f "$binar"
done

if [ $fail -ne 0 ]; then
    exit 1
fi

