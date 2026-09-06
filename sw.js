// DropBridge service worker — just enough to make the app installable
// and to survive a flaky connection. It deliberately does NOT cache your
// shared items: those must always come fresh from Supabase.
const CACHE = "dropbridge-shell-v1";
const SHELL = [
  "./",
  "./index.html",
  "./icon-192.png",
  "./icon-512.png",
  "./apple-touch-icon.png",
  "./manifest.webmanifest",
];

self.addEventListener("install", (e) => {
  e.waitUntil(
    caches.open(CACHE)
      // A missing file shouldn't abort the whole install.
      .then((c) => Promise.allSettled(SHELL.map((u) => c.add(u))))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;

  const url = new URL(req.url);
  // Anything that isn't our own origin (Supabase, CDNs) goes straight to
  // the network — never serve someone's data from a cache.
  if (url.origin !== self.location.origin) return;

  // Network first, so a redeploy is picked up immediately; fall back to
  // the cached shell when offline.
  e.respondWith(
    fetch(req)
      .then((res) => {
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(req, copy)).catch(() => {});
        return res;
      })
      .catch(() => caches.match(req).then((hit) => hit || caches.match("./index.html"))),
  );
});
