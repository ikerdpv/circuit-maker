// Proceso principal de Electron: ventana + actualizaciones automáticas desde GitHub Releases.
const { app, BrowserWindow, Menu, dialog, ipcMain, shell } = require('electron');
const path = require('path');
const fs = require('fs');
const os = require('os');
const { spawn } = require('child_process');

const REPO = 'ikerdpv/circuit-maker';
const ASSET = 'Circuit-Maker-Windows.zip';

let win = null;
let updating = false;

function createWindow() {
  win = new BrowserWindow({
    width: 1320,
    height: 840,
    minWidth: 1000,
    minHeight: 620,
    title: 'Circuit Maker',
    icon: path.join(__dirname, 'icon.png'),
    autoHideMenuBar: true,
    webPreferences: { preload: path.join(__dirname, 'preload.js') },
  });
  Menu.setApplicationMenu(null);
  win.loadFile(path.join(__dirname, 'index.html'));
  // Los enlaces externos se abren en el navegador.
  win.webContents.setWindowOpenHandler(({ url }) => { shell.openExternal(url); return { action: 'deny' }; });
}

app.whenReady().then(() => {
  createWindow();
  // Al iniciar, busca actualizaciones en segundo plano.
  setTimeout(() => checkForUpdates(false), 2500);
});

app.on('window-all-closed', () => app.quit());

ipcMain.handle('app-version', () => app.getVersion());
ipcMain.handle('check-updates', () => checkForUpdates(true));

// ----------------------------------------------------------------
// Actualizaciones
// ----------------------------------------------------------------

/** "1.2.10" > "1.2.9" */
function isNewer(a, b) {
  const pa = a.split('.').map(n => parseInt(n, 10) || 0);
  const pb = b.split('.').map(n => parseInt(n, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const x = pa[i] || 0, y = pb[i] || 0;
    if (x !== y) return x > y;
  }
  return false;
}

function sendStatus(text) {
  if (win && !win.isDestroyed()) win.webContents.send('update-status', text);
}

async function checkForUpdates(manual) {
  if (updating) return;
  // En desarrollo (sin empaquetar) solo se busca si se pide a mano.
  if (!app.isPackaged && !manual) return;
  try {
    // github.com/<repo>/releases/latest redirige a .../releases/tag/vX.Y.Z.
    // Se usa en lugar de la API porque la API limita a 60 consultas por hora por IP.
    const res = await fetch(`https://github.com/${REPO}/releases/latest`, { method: 'HEAD', headers: { 'User-Agent': 'CircuitMaker' } });
    if (!res.ok) throw new Error(`No se pudo conectar con GitHub (error ${res.status}).`);
    const m = /\/releases\/tag\/(v[^/?#]+)/i.exec(res.url);
    if (!m) throw new Error('Todavía no hay ninguna versión publicada.');
    const tag = decodeURIComponent(m[1]);
    const latest = tag.replace(/^v/i, '');
    const current = app.getVersion();
    const asset = { browser_download_url: `https://github.com/${REPO}/releases/download/${tag}/${ASSET}` };

    if (!isNewer(latest, current)) {
      if (manual) {
        await dialog.showMessageBox(win, { type: 'info', message: 'Circuit Maker está al día', detail: `Tienes la última versión (${current}).` });
      }
      return;
    }

    const { response } = await dialog.showMessageBox(win, {
      type: 'info',
      buttons: ['Actualizar ahora', 'Más tarde'],
      defaultId: 0,
      cancelId: 1,
      message: `Hay una versión nueva de Circuit Maker (${latest})`,
      detail: `Tienes la ${current}. Se descargará e instalará sola, y la app se reiniciará.`,
    });
    if (response !== 0) return;
    await installUpdate(asset);
  } catch (e) {
    updating = false;
    if (win && !win.isDestroyed()) win.setProgressBar(-1);
    sendStatus('');
    if (manual) dialog.showErrorBox('No se pudo actualizar', String(e.message || e));
    else console.warn('Actualización:', e);
  }
}

async function installUpdate(asset) {
  updating = true;
  const installDir = path.dirname(process.execPath);
  const exeName = path.basename(process.execPath);

  // Comprueba que se puede escribir en la carpeta de la app.
  try {
    fs.accessSync(installDir, fs.constants.W_OK);
  } catch {
    throw new Error(`No tengo permiso para escribir en ${installDir}. Mueve la carpeta de Circuit Maker a otra ubicación (por ejemplo, Documentos) y vuelve a intentarlo.`);
  }

  // Descarga con progreso.
  const res = await fetch(asset.browser_download_url, { headers: { 'User-Agent': 'CircuitMaker' } });
  if (!res.ok || !res.body) throw new Error(`No se pudo descargar la actualización (error ${res.status}).`);
  const total = Number(res.headers.get('content-length')) || 0;
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'circuitmaker-update-'));
  const zip = path.join(work, 'update.zip');
  const file = fs.createWriteStream(zip);
  let got = 0;
  const reader = res.body.getReader();
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    got += value.length;
    if (!file.write(Buffer.from(value))) await new Promise(r => file.once('drain', r));
    if (total) {
      win.setProgressBar(got / total);
      sendStatus(`Descargando actualización… ${Math.round(got / total * 100)} %`);
    }
  }
  await new Promise((resolve, reject) => file.end(err => (err ? reject(err) : resolve())));
  sendStatus('Instalando actualización…');

  // Script que espera a que la app se cierre, sustituye los archivos y la vuelve a abrir.
  const ps1 = path.join(work, 'update.ps1');
  fs.writeFileSync(ps1, [
    'param([int]$ProcId, [string]$Zip, [string]$Work, [string]$Dest, [string]$Exe)',
    "$ErrorActionPreference = 'Stop'",
    'try { Wait-Process -Id $ProcId -Timeout 60 -ErrorAction SilentlyContinue } catch {}',
    'Start-Sleep -Milliseconds 800',
    "$x = Join-Path $Work 'x'",
    'New-Item -ItemType Directory -Force -Path $x | Out-Null',
    'try { & tar.exe -xf $Zip -C $x; $ok = ($LASTEXITCODE -eq 0) } catch { $ok = $false }',
    'if (-not $ok) { Expand-Archive -LiteralPath $Zip -DestinationPath $x -Force }',
    '$src = Get-ChildItem -LiteralPath $x -Directory | Select-Object -First 1',
    'if (-not $src) { $src = Get-Item -LiteralPath $x }',
    'for ($i = 0; $i -lt 10; $i++) {',
    "  try { Copy-Item -Path (Join-Path $src.FullName '*') -Destination $Dest -Recurse -Force; break }",
    '  catch { Start-Sleep -Seconds 1 }',
    '}',
    'Start-Process -FilePath (Join-Path $Dest $Exe)',
    'Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue',
  ].join('\r\n'), 'utf8');

  const child = spawn('powershell.exe', [
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ps1,
    '-ProcId', String(process.pid), '-Zip', zip, '-Work', work, '-Dest', installDir, '-Exe', exeName,
  ], { detached: true, stdio: 'ignore', windowsHide: true });
  child.unref();
  app.quit();
}
