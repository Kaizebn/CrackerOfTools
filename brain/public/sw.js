// BRAIN service worker — caches the app shell so it works offline after the
// first visit. Only same-origin GETs are cached; the AI model download
// (Hugging Face / jsDelivr) and API calls (Anthropic / OpenRouter) are left
// untouched so they always go to the network.
const CACHE = 'brain-cache-v1';

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // ignore cross-origin (models, APIs)

  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const cached = await cache.match(req);
    if (cached) {
      // Refresh in the background (stale-while-revalidate).
      fetch(req).then((res) => { if (res && res.ok) cache.put(req, res.clone()); }).catch(() => {});
      return cached;
    }
    try {
      const res = await fetch(req);
      if (res && res.ok && res.type === 'basic') cache.put(req, res.clone());
      return res;
    } catch (err) {
      // Offline fallback to the cached app shell for navigations.
      if (req.mode === 'navigate') {
        const shell = (await cache.match('./')) || (await cache.match('index.html'));
        if (shell) return shell;
      }
      throw err;
    }
  })());
});
