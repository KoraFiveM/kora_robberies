#!/usr/bin/env bash
# Runs every kora_robberies smoke test with plain Lua (no FiveM, no database)
# and syntax-checks every Lua file. Exits non-zero on any failure.
#
# The shared mocks come from the sibling ../kora_lib/test checkout.
set -uo pipefail
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$dir/.." || exit 1
lua_bin="${LUA:-lua5.4}"
luac_bin="${LUAC:-luac5.4}"
status=0
suites=0

for file in "$dir"/smoke/*.lua; do
    echo "== $(basename "$file" .lua) =="
    suites=$((suites + 1))
    if ! "$lua_bin" "$file"; then status=1; fi
    echo
done

echo "== luac -p =="
while IFS= read -r file; do
    if ! "$luac_bin" -p "$file" 2>/dev/null; then
        echo "LUAC FAIL $file"
        status=1
    fi
done < <(find . -name '*.lua' -not -path './.git/*' | sort)

echo "-- ran $suites suite(s) --"
exit "$status"
