// Service worker de Circuit Maker.
// Con conexión sirve siempre la última versión publicada; sin conexión, la copia guardada.
const CACHE = 'circuit-maker';
const FILES = ['./', 'manifest.webmanifest', 'icon.png', 'icon-192.png', 'icon-512.png', 'icon-maskable-512.png'];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE)
      .then(c => c.addAll(FILES.map(f => new Request(f, { cache: 'no-cache' }))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== location.origin) return;
  e.respondWith(networkFirst(e));
});

async function networkFirst(e) {
  const req = e.request;
  const cache = await caches.open(CACHE);
  // Cualquier navegación dentro de la app es la misma página.
  const key = req.mode === 'navigate' ? './' : req.url;
  const cached = await cache.match(key, { ignoreSearch: true });
  // 'no-cache' obliga a comprobar con el servidor, así una versión nueva llega al abrir la app.
  const fresh = fetch(req.url, { cache: 'no-cache' }).then(res => {
    if (res.ok) cache.put(key, res.clone());
    return res;
  });
  if (!cached) return fresh;
  e.waitUntil(fresh.catch(() => {}));
  // Con copia guardada, se espera a la red 3 s como mucho.
  const timeout = new Promise(resolve => setTimeout(() => resolve(null), 3000));
  try {
    return (await Promise.race([fresh, timeout])) || cached;
  } catch {
    return cached;
  }
}
