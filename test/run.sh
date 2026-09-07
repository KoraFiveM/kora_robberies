#!/usr/bin/env bash
set -uo pipefail
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
status=0
for file in "$dir"/smoke/*.lua; do
  echo "== $(basename "$file" .lua) =="
  if ! ( cd "$dir/.." && "${LUA:-lua5.4}" "$file" ); then status=1; fi
done
exit "$status"
