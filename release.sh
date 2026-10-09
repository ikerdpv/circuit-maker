#!/bin/bash
# Publica una versión nueva de Circuit Maker para Mac y Windows.
#   ./release.sh 1.1.0 "Qué ha cambiado"
# Las apps instaladas la detectan al abrirse y se actualizan solas.
set -euo pipefail
cd "$(dirname "$0")"

V="${1:?Uso: ./release.sh <versión> [\"notas\"]   (por ejemplo: ./release.sh 1.1.0 \"Nuevo componente: LED\")}"
NOTES="${2:-Circuit Maker $V}"
[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "La versión debe tener la forma 1.2.3"; exit 1; }
if [ -d /Library/Developer/CommandLineTools ]; then export DEVELOPER_DIR=/Library/Developer/CommandLineTools; fi
if git rev-parse "v$V" >/dev/null 2>&1; then echo "La versión v$V ya existe."; exit 1; fi

# 1. Número de versión en las dos apps
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $V" Resources/Info.plist
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist) + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" Resources/Info.plist
node -e "const f='windows/app/package.json',p=require('./'+f);p.version='$V';require('fs').writeFileSync(f,JSON.stringify(p,null,2)+'\n')"

# 2. Compilar
./build.sh
rm -f build/Circuit-Maker-macOS.zip
ditto -c -k --keepParent "build/Circuit Maker.app" build/Circuit-Maker-macOS.zip
windows/build-windows.sh

# 3. Subir a GitHub y publicar la versión
git add -A
git commit -m "Versión $V"
git tag "v$V"
git push origin HEAD --tags
gh release create "v$V" build/Circuit-Maker-macOS.zip windows/Circuit-Maker-Windows.zip \
    --title "Circuit Maker $V" --notes "$NOTES"
echo "Publicada la versión $V"
