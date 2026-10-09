#!/bin/bash
# Empaqueta Circuit Maker para Windows (x64) y genera windows/Circuit-Maker-Windows.zip.
# Funciona desde macOS: no necesita Wine.
set -euo pipefail
cd "$(dirname "$0")"

ELECTRON_VERSION=44.7.0
VERSION=$(node -p "require('./app/package.json').version")

npm install --no-audit --no-fund --silent

# Iconos a partir del icono de la app de Mac.
if [ ! -f icon.ico ] || [ ../Resources/AppIcon.icns -nt icon.ico ]; then
    TMP=$(mktemp -d)
    sips -s format png ../Resources/AppIcon.icns --out "$TMP/icon.png" >/dev/null
    for s in 16 32 48 256; do sips -z $s $s "$TMP/icon.png" --out "$TMP/$s.png" >/dev/null; done
    cp "$TMP/256.png" app/icon.png
    node make-ico.mjs icon.ico "$TMP/16.png" "$TMP/32.png" "$TMP/48.png" "$TMP/256.png"
    rm -rf "$TMP"
fi

rm -rf dist
npx electron-packager app "Circuit Maker" \
    --platform=win32 --arch=x64 \
    --electron-version="$ELECTRON_VERSION" \
    --app-version="$VERSION" --build-version="$VERSION" \
    --icon=icon.ico --asar --overwrite --out=dist \
    --win32metadata.ProductName="Circuit Maker" \
    --win32metadata.FileDescription="Circuit Maker" \
    --win32metadata.CompanyName="ikerdpv" >/dev/null

mv "dist/Circuit Maker-win32-x64" "dist/Circuit Maker"
# Solo hacen falta los idiomas español e inglés de Chromium (ahorra ~45 MB).
find "dist/Circuit Maker/locales" -name '*.pak' ! -name 'en-US.pak' ! -name 'es.pak' ! -name 'es-419.pak' -delete
rm -f Circuit-Maker-Windows.zip
(cd dist && zip -qry -X ../Circuit-Maker-Windows.zip "Circuit Maker")
echo "Listo: windows/Circuit-Maker-Windows.zip (versión $VERSION)"
