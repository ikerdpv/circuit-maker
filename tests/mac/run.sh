#!/bin/bash
# Compila una versión de prueba de la app de Mac y la ejecuta con tests/mac/SelfTest.swift.
# La app se abre unos segundos, se prueba a sí misma y se cierra. Resultado en pantalla.
set -euo pipefail
cd "$(dirname "$0")/../.."
if [ -d /Library/Developer/CommandLineTools ]; then export DEVELOPER_DIR=/Library/Developer/CommandLineTools; fi

APP="$(mktemp -d)/Circuit Maker Test.app"
mkdir -p "$APP/Contents/MacOS"
sed -e 's/<string>com.iker.circuitmaker<\/string>/<string>com.iker.circuitmaker.selftest<\/string>/' Resources/Info.plist > "$APP/Contents/Info.plist"
swiftc -swift-version 5 -parse-as-library -D SELFTEST -target "$(uname -m)-apple-macos14.0" \
    Sources/*.swift tests/mac/SelfTest.swift -o "$APP/Contents/MacOS/CircuitMaker"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

OUT="$(mktemp)"
rm -f "$OUT"
open -W --env SELFTEST_OUT="$OUT" "$APP"
cat "$OUT"
rm -rf "$(dirname "$APP")"
grep -q "^TODO BIEN" "$OUT"
