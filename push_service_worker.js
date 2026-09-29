/* Hama Work Web Push service worker */
self.addEventListener('push', function (event) {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch (_) {
    payload = { body: event.data ? event.data.text() : '' };
  }

  const title = payload.title || 'Hama Work';
  const options = {
    body: payload.body || 'You have a new Hama Work notification.',
    icon: payload.icon || './icons/Icon-192.png',
    badge: payload.badge || './icons/Icon-192.png',
    tag: payload.tag || ('hama-' + Date.now()),
    renotify: true,
    data: payload.data || {}
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', function (event) {
  event.notification.close();

  const data = event.notification.data || {};
  const targetType = data.targetType;
  const targetId = data.targetId;

  let route = '#/notifications';
  if (targetType === 'task' && targetId) {
    route = '#/tasks/' + encodeURIComponent(targetId);
  } else if (targetType === 'message' && targetId) {
    route = '#/messages/' + encodeURIComponent(targetId);
  }

  // Build the URL from the service-worker scope so GitHub Pages repositories
  // such as /HamaFood/ continue to work correctly.
  const targetUrl = new URL(route, self.registration.scope).href;

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then(function (clientList) {
        for (const client of clientList) {
          if ('focus' in client) {
            client.focus();
            if ('navigate' in client) return client.navigate(targetUrl);
          }
        }
        if (self.clients.openWindow) return self.clients.openWindow(targetUrl);
      })
  );
});
