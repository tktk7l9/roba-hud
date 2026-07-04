#!/usr/bin/env bash
# lib(純ロジック)層の行カバレッジ 100% ゲート。
# swift build (instrumented) → --selftest 実行 → llvm-cov report を検査。
# UI / HID・BLE購読 / git・gh 実行層は副作用層のため対象外。
set -euo pipefail
cd "$(dirname "$0")/.."

LIB_FILES=(
  BatteryForecast BatteryModel CheatsheetGenerator Geometry
  InferenceEngine Insights KeycodeTable KeymapEditor KeymapModel KeymapParser Stats
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
    echo "GATE FAIL: ${f}.swift がレポートにありません"
    fail=1
    continue
  fi
  pct=$(echo "$row" | awk '{print $10}' | tr -d '%')
  if [[ "$pct" != "100.00" ]]; then
    echo "GATE FAIL: ${f}.swift lines=${pct}% (100.00% 必須)"
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
