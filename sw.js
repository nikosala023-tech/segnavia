/* Service worker: app shell offline + cache delle tessere mappa già viste. */
const SHELL = 'segnavia-shell-v1';
const TILES = 'segnavia-tiles-v1';
const ASSETS = ['./', 'index.html', 'styles.css', 'app.js', 'manifest.webmanifest', 'vendor/leaflet.js', 'vendor/leaflet.css', 'vendor/jszip.min.js',
  'fonts/barlow-condensed-latin-500-normal.woff2', 'fonts/barlow-condensed-latin-600-normal.woff2', 'fonts/barlow-condensed-latin-700-normal.woff2',
  'fonts/manrope-latin-400-normal.woff2', 'fonts/manrope-latin-500-normal.woff2', 'fonts/manrope-latin-600-normal.woff2', 'fonts/manrope-latin-700-normal.woff2', 'fonts/manrope-latin-800-normal.woff2',
  'icons/icon-192.png', 'icons/icon-512.png'];
self.addEventListener('install', e => { e.waitUntil(caches.open(SHELL).then(c => c.addAll(ASSETS)).then(() => self.skipWaiting())); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== SHELL && k !== TILES).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET') return;
  const isTile = /tile\.opentopomap\.org|tile\.openstreetmap\.org|waymarkedtrails\.org|arcgisonline\.com/.test(url.host);
  if (isTile) {
    e.respondWith(caches.open(TILES).then(async c => {
      const hit = await c.match(e.request); if (hit) return hit;
      try { const r = await fetch(e.request); if (r.ok || r.type === 'opaque') { c.put(e.request, r.clone()); trim(c); } return r; } catch { return hit || Response.error(); }
    }));
    return;
  }
  if (url.origin === location.origin) {
    // rete prima per l'app (aggiornamenti immediati), cache se offline
    e.respondWith(fetch(e.request).then(r => { const cp = r.clone(); caches.open(SHELL).then(c => c.put(e.request, cp)); return r; }).catch(() => caches.match(e.request).then(r => r || caches.match('index.html'))));
  }
});
let trimming = false;
async function trim(c) {
  if (trimming) return; trimming = true;
  try { const keys = await c.keys(); if (keys.length > 3000) for (const k of keys.slice(0, keys.length - 2500)) await c.delete(k); } finally { trimming = false; }
}
