// SmartSumbong portal: browser alerts (0136). Shows an alert the server pushed, even with the portal closed,
// and a click opens its case. It does nothing else: no caching, no offline pages.
self.addEventListener('push', (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { body: e.data ? e.data.text() : '' }; }
  const at = (p) => new URL(p, self.registration.scope).href;
  e.waitUntil(self.registration.showNotification(d.title || 'SmartSumbong', {
    body: d.body || '',
    icon: at('assets/img/icon-192.png'),
    // one alert per case: a newer one replaces the older and still sounds
    tag: d.tag || undefined,
    renotify: !!d.tag,
    data: { url: d.url || 'notifications.php' },
  }));
});

self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const scope = self.registration.scope;
  let url = new URL((e.notification.data && e.notification.data.url) || 'notifications.php', scope).href;
  if (!url.startsWith(scope)) url = scope + 'notifications.php';   // only ever a portal page
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((tabs) => {
    const tab = tabs.find((t) => t.url.startsWith(scope) && 'focus' in t);
    if (tab) return tab.navigate(url).then((t) => (t || tab).focus());
    return self.clients.openWindow(url);
  }));
});
