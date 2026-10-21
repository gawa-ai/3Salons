// Studio service worker. It only shows alerts (web push) and opens the Studio when one is tapped.
// It does NOT cache pages or data and has no fetch handler, so nothing private is stored on the phone.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let d = {};
  try { d = event.data ? event.data.json() : {}; } catch (e) { d = { body: event.data ? event.data.text() : '' }; }
  const title = String(d.title || 'Shahina Ahmed Studio').slice(0, 120);
  const options = {
    body: String(d.body || '').slice(0, 300),
    icon: '/icon-192.png',
    badge: '/badge-96.png',
    tag: typeof d.tag === 'string' ? d.tag.slice(0, 100) : undefined,
    data: { url: typeof d.url === 'string' ? d.url : '/studio' },
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  // Only ever open a page inside the Studio on our own site.
  let target = new URL('/studio', self.location.origin);
  try {
    const u = new URL(String((event.notification.data && event.notification.data.url) || '/studio'), self.location.origin);
    if (u.origin === self.location.origin && u.pathname.indexOf('/studio') === 0) target = u;
  } catch (e) { /* keep default */ }
  event.waitUntil((async () => {
    const all = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const c of all) {
      if (new URL(c.url).origin === self.location.origin && new URL(c.url).pathname.indexOf('/studio') === 0) {
        await c.focus();
        if ('navigate' in c) { try { await c.navigate(target.href); } catch (e) { /* ignore */ } }
        return;
      }
    }
    await self.clients.openWindow(target.href);
  })());
});
