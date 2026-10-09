#!/bin/bash
# Regenera Resources/AppIcon.icns a partir de tools/MakeIcon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d /Library/Developer/CommandLineTools ] && export DEVELOPER_DIR=/Library/Developer/CommandLineTools
TMP=$(mktemp -d)
swiftc tools/MakeIcon.swift -o "$TMP/makeicon"
"$TMP/makeicon" "$TMP/icon.png"
SET="$TMP/AppIcon.iconset"; mkdir -p "$SET"
for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
rm -rf "$TMP"
echo "Icono generado: Resources/AppIcon.icns"
