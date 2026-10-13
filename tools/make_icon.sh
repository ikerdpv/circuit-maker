#!/bin/bash
# Regenera Resources/AppIcon.icns y los iconos de la versión web a partir de tools/MakeIcon.swift.
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

# Iconos de la versión web (PWA)
sips -z 192 192 "$TMP/icon.png" --out web/icon-192.png >/dev/null
sips -z 512 512 "$TMP/icon.png" --out web/icon-512.png >/dev/null
"$TMP/makeicon" "$TMP/maskable.png" --maskable
sips -z 512 512 "$TMP/maskable.png" --out web/icon-maskable-512.png >/dev/null
rm -rf "$TMP"
echo "Iconos generados: Resources/AppIcon.icns y web/icon-*.png"
