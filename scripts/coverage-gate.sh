#!/usr/bin/env bash
# 100% line-coverage gate for the lib (pure logic) layer.
# Instrumented swift build → run --selftest → check the llvm-cov report.
# UI, HID/BLE subscription and git/gh execution are side-effect layers and excluded.
set -euo pipefail
cd "$(dirname "$0")/.."

LIB_FILES=(
  BatteryForecast BatteryModel CheatsheetGenerator Geometry
  InferenceEngine Insights KeycodeTable KeymapEditor KeymapModel KeymapParser ProfileMarker Stats
)

TMP="${TMPDIR:-/tmp}/roba-hud-coverage"
mkdir -p "$TMP"

echo "==> instrumented build"
swift build -Xswiftc -profile-generate -Xswiftc -profile-coverage-mapping >/dev/null
BIN=.build/debug/RoBaHUD

echo "==> selftest under coverage"
LLVM_PROFILE_FILE="$TMP/cov.profraw" "$BIN" --selftest >/dev/null

xcrun llvm-profdata merge -sparse "$TMP/cov.profraw" -o "$TMP/cov.profdata"
xcrun llvm-cov report "$BIN" -instr-profile="$TMP/cov.profdata" > "$TMP/report.txt"

fail=0
for f in "${LIB_FILES[@]}"; do
  row=$(grep -E "(^|/)${f}\.swift" "$TMP/report.txt" | head -1 || true)
  if [[ -z "$row" ]]; then
    echo "GATE FAIL: ${f}.swift is missing from the report"
    fail=1
    continue
  fi
  pct=$(echo "$row" | awk '{print $10}' | tr -d '%')
  if [[ "$pct" != "100.00" ]]; then
    echo "GATE FAIL: ${f}.swift lines=${pct}% (100.00% required)"
    fail=1
  else
    echo "  ok  ${f}.swift 100.00%"
  fi
done

if [[ $fail -ne 0 ]]; then
  echo "coverage gate FAILED"
  exit 1
fi
echo "coverage gate OK (lib ${#LIB_FILES[@]} files @ 100% lines)"
