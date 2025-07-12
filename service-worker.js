const CACHE_NAME = 'dfpwm-player-v1';
const ASSETS = [
  '/',
  '/index.html',
  '/manifest.json',
  '/icon-192.png',
  '/icon-512.png',
  // any other scripts/CSS you need
];

self.addEventListener('install', evt => {
  evt.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(ASSETS))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', evt => {
  evt.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', evt => {
  // network-first for dynamic WS traffic, but fallback to cache for static files
  if (ASSETS.includes(new URL(evt.request.url).pathname)) {
    evt.respondWith(
      caches.match(evt.request).then(cached =>
        cached || fetch(evt.request)
      )
    );
  } else {
    evt.respondWith(fetch(evt.request));
  }
});
