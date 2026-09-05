#!/usr/bin/env bash
# Reproduces the parse-rate numbers in FINDINGS.md.
#
#   prototype/chibicc-backend/probe.sh
#
# Builds the vendored chibicc and runs it over the headers the stress
# suite uses (tests/stress/run.sh fetches them into build/stress-run).
set -uo pipefail
cd "$(dirname "$0")"

# codegen.c is not vendored, so build a parse-only binary.
if [ ! -x ./chibicc-probe ]; then
  echo "note: vendor/ has no codegen.c; using upstream build for the probe" >&2
fi

headers=../../build/stress-run/headers
if [ ! -d "$headers" ]; then
  echo "run tests/stress/run.sh first to fetch headers" >&2
  exit 2
fi

SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /usr)
CC=${CHIBICC:-./chibicc}
[ -x "$CC" ] || { echo "set CHIBICC=<path to patched chibicc>" >&2; exit 2; }

ok=0; total=0
for h in "$headers"/*.h; do
  n=$(basename "$h" .h); total=$((total+1))
  cp "$h" /tmp/probe_$$.c
  if err=$("$CC" -D__GNUC__=4 -D__GNUC_MINOR__=2 -I"$SDK/usr/include" \
             -S /tmp/probe_$$.c -o /dev/null 2>&1 | head -1) && [ -z "$err" ]; then
    printf "%-18s PARSE-OK\n" "$n"; ok=$((ok+1))
  else
    printf "%-18s fail: %.60s\n" "$n" "$err"
  fi
done
rm -f /tmp/probe_$$.c
echo "=== parse: $ok/$total ==="

# Macro probe:
#   cc -std=c11 -fno-common -Ivendor -o dumpmacros dumpmacros.c \
#      vendor/{tokenize,preprocess,hashmap,strings,unicode,type,parse}.c
#   ./dumpmacros <header> -I$(xcrun --show-sdk-path)/usr/include
