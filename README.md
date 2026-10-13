# Circuit Maker

Editor de circuitos eléctricos en modo esquema para **macOS**, **Windows** y **ChromeOS** (o cualquier navegador). Puedes colocar pilas, resistencias, bombillas, interruptores, amperímetros y voltímetros, cambiar sus valores, y la app calcula en tiempo real la tensión, la intensidad y la potencia de cada componente.

- Las bombillas brillan según la potencia que reciben, y se ve la corriente moverse por los cables.
- Los cables se colorean según su tensión (azul = 0 V, rojo = la máxima).
- Avisa de cortocircuitos, de bombillas que se fundirían y de amperímetros mal conectados.
- Puedes deshacer y rehacer, y guardar y abrir circuitos (`.json`, compatibles entre todas las versiones).
- **Se actualiza sola**: al abrirse busca una versión nueva en GitHub y la instala.

## Usarla en el navegador (ChromeOS, Linux, tabletas…)

Abre **https://ikerdpv.github.io/circuit-maker/**. No hay que instalar nada.

Para tenerla como una app más, con su icono y su ventana, y que funcione sin conexión:

- **Chromebook, o Chrome/Edge en cualquier ordenador:** pulsa el icono de instalar que aparece a la derecha de la barra de direcciones, o busca la opción de instalar la página como aplicación en el menú ⋮.
- **iPad:** en Safari, *Compartir → Añadir a pantalla de inicio*.

Se actualiza sola: cada vez que la abres con conexión carga la última versión publicada.

En pantallas táctiles, un dedo hace de ratón (tocar, arrastrar piezas, tender cables), arrastrar con un dedo sobre un hueco vacío desplaza el esquema, y con dos dedos se desplaza y se hace zoom.

## Descargar

Ve a [Releases](https://github.com/ikerdpv/circuit-maker/releases/latest) y descarga:

| Sistema | Archivo | Cómo instalarla |
|---|---|---|
| macOS 14 o posterior | `Circuit-Maker-macOS.zip` | Descomprime el zip y arrastra **Circuit Maker** a *Aplicaciones*. La primera vez macOS dirá que no puede comprobar el desarrollador: ve a *Ajustes del Sistema → Privacidad y seguridad* y pulsa **Abrir igualmente**. |
| Windows 10/11 (64 bits) | `Circuit-Maker-Windows.zip` | Descomprime la carpeta donde quieras (por ejemplo, en *Documentos*) y abre **Circuit Maker.exe**. Si SmartScreen avisa, pulsa *Más información → Ejecutar de todas formas*. |

La app no está firmada con un certificado de pago, por eso salen esos avisos la primera vez. Las actualizaciones posteriores se instalan sin avisos.

## Uso

| Acción | Cómo |
|---|---|
| Colocar una pieza | Elígela en la barra de la izquierda (o con las teclas 1–6) y haz clic en la cuadrícula |
| Tender un cable | Arrastra desde el borne de una pieza hasta otro punto (o usa la herramienta Cable, `W`) |
| Cambiar valores | Selecciona la pieza y edita el panel de la derecha (acepta `4k7`, `10k`, `2,2M`…) |
| Abrir o cerrar un interruptor | Doble clic sobre él, o barra espaciadora |
| Girar / borrar | `R` / `Supr` o `⌫` |
| Deshacer / rehacer | Ctrl+Z / Ctrl+Y (⌘Z / ⇧⌘Z en Mac) |
| Moverse por el esquema (Windows y web) | Rueda del ratón o dos dedos en el panel táctil, botón derecho arrastrando, Ctrl + rueda (o pellizco) para el zoom |

## Desarrollo

```
Sources/            App de Mac (SwiftUI)
Resources/          Info.plist e icono de la app de Mac
windows/app/        App de Windows (HTML + JavaScript dentro de Electron). La misma página es la versión web.
windows/build-windows.sh
web/                Lo que solo necesita la versión web: manifiesto, modo sin conexión e iconos
docs/               Versión web ya montada, que publica GitHub Pages. La genera web/build-web.sh: no la edites a mano
build.sh            Compila la app de Mac en build/
release.sh          Publica una versión nueva para todas las plataformas
```

- **Mac:** `./build.sh` y luego `open "build/Circuit Maker.app"`. Solo hacen falta las Command Line Tools: no hace falta aceptar la licencia de Xcode. Por eso el código no usa `@State`, que es una macro que solo trae Xcode.
- **Windows:** `windows/build-windows.sh` genera `windows/Circuit-Maker-Windows.zip` desde el Mac (hace falta Node.js; no hace falta Wine). Para probarla en el navegador basta con abrir `windows/app/index.html`.
- **Web:** `web/build-web.sh` copia esa misma página a `docs/` y le añade el manifiesto y el *service worker* que la hacen instalable. GitHub Pages publica `docs/` en cuanto se sube a `main`.

El cálculo es un análisis nodal modificado (MNA) en corriente continua: `Sources/Solver.swift` en Mac y la función `solve` de `windows/app/index.html` en Windows.

### Publicar una actualización

```bash
./release.sh 1.1.0 "Qué ha cambiado"
```

El script cambia el número de versión en las dos apps, las compila, regenera la versión web, sube los cambios y crea una *release* en GitHub con los dos zips. La web se actualiza con la subida. Al abrirse, las apps instaladas consultan `releases/latest`. Si encuentran una versión más nueva, preguntan, la descargan, sustituyen los archivos y se reinician.

## Licencia

[MIT](LICENSE): puedes usar, copiar, modificar y distribuir el código libremente, siempre que mantengas el aviso de copyright.
