#!/usr/bin/env bash
# Runs every offline test: the real addon files against stand-ins for the
# game's API. Needs LuaJIT or Lua 5.1 (the game's Lua version).
set -u
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
LUA="$(command -v luajit || command -v lua5.1 || true)"
if [ -z "$LUA" ]; then echo "Install luajit or lua5.1 to run the tests." >&2; exit 2; fi
fail=0
for f in "$ROOT"/Core/*.lua "$ROOT"/Services/*.lua "$ROOT"/UI/*.lua; do
    if command -v luac5.1 >/dev/null; then luac5.1 -p "$f" || { echo "syntax error: $f"; fail=1; }; fi
done
for t in "$ROOT"/tests/test_*.lua; do
    name="$(basename "$t" .lua)"
    if out="$(cd "$ROOT/tests" && "$LUA" "$t" "$ROOT" 2>&1)" && [ "$(printf '%s\n' "$out" | tail -1)" = "OK" ]; then
        echo "ok    $name"
    else
        echo "FAIL  $name"; printf '%s\n' "$out" | tail -8 | sed 's/^/      /'; fail=1
    fi
done
exit $fail
