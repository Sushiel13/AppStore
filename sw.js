// Retired service worker. Older visits installed a caching worker that could keep
// serving stale pages. This version clears every cache, unregisters itself and
// reloads open tabs, so browsers always fetch the latest site from the server.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", e => {
  e.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.map(k => caches.delete(k)));
    await self.registration.unregister();
    const clients = await self.clients.matchAll({ type: "window" });
    clients.forEach(c => c.navigate(c.url));
  })());
});
