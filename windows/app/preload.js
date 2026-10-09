// Puente seguro entre la página y el proceso principal.
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('circuitMaker', {
  version: () => ipcRenderer.invoke('app-version'),
  checkForUpdates: () => ipcRenderer.invoke('check-updates'),
  onUpdateStatus: cb => ipcRenderer.on('update-status', (_e, text) => cb(text)),
});
