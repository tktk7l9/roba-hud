#!/usr/bin/env bash
# Builds a release binary and wraps it into a floating-HUD .app bundle.
#
#   ./scripts/package-app.sh            # build into ./RoBaHUD.app
#   ./scripts/package-app.sh --install  # also copy to /Applications
#
# IMPORTANT: the Input Monitoring (TCC) grant sticks to the code-signing
# identity. Run scripts/create-signing-cert.sh once so rebuilds keep the
# grant; with ad-hoc signing every rebuild silently loses it.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="RoBaHUD"
APP="${APP_NAME}.app"

echo "==> swift build -c release"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${APP_NAME}"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "error: built binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

SIGN_ID="RoBaHUD Self-Signed"
# No -v: a self-signed cert is "not trusted" by policy (which excludes it from
# -v) but codesign signs with it fine for local use.
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
    echo "==> codesign ($SIGN_ID — stable identity)"
    codesign --force --deep --sign "$SIGN_ID" "$APP"
else
    echo "==> codesign (ad-hoc — 毎ビルドで Input Monitoring 権限が剥がれます。scripts/create-signing-cert.sh を実行してください)"
    codesign --force --deep --sign - "$APP"
fi

echo "built: $(pwd)/$APP"

if [[ "${1:-}" == "--install" ]]; then
    echo "==> installing to /Applications"
    rm -rf "/Applications/$APP"
    cp -R "$APP" "/Applications/$APP"
    echo "installed: /Applications/$APP"
fi
