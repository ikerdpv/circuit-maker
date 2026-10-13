#!/bin/bash
# Genera docs/: la versión web instalable (PWA) que GitHub Pages publica en
# https://ikerdpv.github.io/circuit-maker/ (sirve para ChromeOS y cualquier navegador).
# La página es la misma que usa la app de Windows: windows/app/index.html.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(node -p "require('./windows/app/package.json').version")

rm -rf docs
mkdir docs
# La página lleva dos marcas que solo se rellenan en la versión web: el manifiesto y la versión.
sed -e 's|<!--WEB-HEAD:.*-->|<link rel="manifest" href="manifest.webmanifest">\
<link rel="apple-touch-icon" href="icon-192.png">|' \
    -e "s/const WEB_VERSION = 'dev';/const WEB_VERSION = '$VERSION';/" \
    windows/app/index.html > docs/index.html
grep -q 'rel="manifest"' docs/index.html && grep -q "const WEB_VERSION = '$VERSION';" docs/index.html \
    || { echo "No se pudieron rellenar las marcas en docs/index.html"; exit 1; }
cp windows/app/icon.png web/manifest.webmanifest web/sw.js web/icon-192.png web/icon-512.png web/icon-maskable-512.png docs/
touch docs/.nojekyll   # GitHub Pages: servir los archivos tal cual
echo "Listo: docs/ (versión web $VERSION)"
