// Service worker : l'app s'ouvre même hors connexion.
// Pages et scripts : réseau d'abord (pour recevoir les mises à jour et config.js), cache en secours.
// Images et vidéos : cache d'abord.
const CACHE = 'incubo-v4';
const ASSETS = ['/', '/index.html', '/manifest.webmanifest', '/icons/icon-192.png', '/icons/icon-512.png'];
self.addEventListener('install', e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS))); self.skipWaiting(); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k))))); self.clients.claim(); });
self.addEventListener('fetch', e => {
  const req = e.request, url = new URL(req.url);
  if (req.method !== 'GET' || url.origin !== location.origin) return;           // Supabase et CDN : jamais en cache ici
  const fresh = req.mode === 'navigate' || /\.(html|js|json|webmanifest)$/.test(url.pathname);
  if (fresh) {
    e.respondWith(fetch(req).then(res => { const c = res.clone(); if (res.ok) caches.open(CACHE).then(k => k.put(req, c)); return res; })
      .catch(() => caches.match(req).then(r => r || caches.match('/index.html'))));
  } else {
    e.respondWith(caches.match(req).then(hit => hit || fetch(req).then(res => { const c = res.clone(); if (res.ok) caches.open(CACHE).then(k => k.put(req, c)); return res; })));
  }
});
