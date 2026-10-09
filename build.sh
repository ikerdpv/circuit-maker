#!/bin/bash
# Compila Circuit Maker y genera "build/Circuit Maker.app".
set -euo pipefail
cd "$(dirname "$0")"

# Usa las Command Line Tools si existen (no requieren aceptar la licencia de Xcode).
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Library/Developer/CommandLineTools ]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi

APP="build/Circuit Maker.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -parse-as-library \
    -target "$(uname -m)-apple-macos14.0" \
    Sources/*.swift \
    -o "$APP/Contents/MacOS/CircuitMaker"

cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Listo: $APP"
