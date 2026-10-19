(function () {
  'use strict';

  function base64UrlToUint8Array(base64Url) {
    const padding = '='.repeat((4 - (base64Url.length % 4)) % 4);
    const base64 = (base64Url + padding).replace(/-/g, '+').replace(/_/g, '/');
    const rawData = atob(base64);
    return Uint8Array.from([...rawData].map(ch => ch.charCodeAt(0)));
  }

  async function registration() {
    if (!('serviceWorker' in navigator)) {
      throw new Error('Service workers are not supported by this browser.');
    }
    const reg = await navigator.serviceWorker.register(
      './push_service_worker.js',
      { scope: './' }
    );
    // Ask the browser to check for a newer worker on every startup. This is
    // important after a GitHub Pages deployment: the user's notification
    // permission remains intact, but the service-worker code may have changed.
    try {
      await reg.update();
    } catch (_) {}
    return reg;
  }

  function serializeSubscription(sub) {
    const json = sub.toJSON();
    return {
      endpoint: sub.endpoint,
      expirationTime: sub.expirationTime,
      keys: json.keys || {},
      userAgent: navigator.userAgent
    };
  }

  window.hamaPush = {
    async getPermission() {
      if (!('Notification' in window)) return 'unsupported';
      return Notification.permission;
    },

    async requestPermission() {
      if (!('Notification' in window)) {
        throw new Error('Notifications are not supported by this browser.');
      }
      return await Notification.requestPermission();
    },

    async subscribe(vapidPublicKey) {
      const reg = await registration();
      let sub = await reg.pushManager.getSubscription();
      if (!sub) {
        sub = await reg.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: base64UrlToUint8Array(vapidPublicKey)
        });
      }
      return serializeSubscription(sub);
    },

    async getSubscription() {
      const reg = await registration();
      const sub = await reg.pushManager.getSubscription();
      return sub ? serializeSubscription(sub) : null;
    },

    async isSubscribed(vapidPublicKey) {
      if (!vapidPublicKey || !('PushManager' in window)) return false;
      const reg = await registration();
      const sub = await reg.pushManager.getSubscription();
      return !!sub;
    },

    async unsubscribe() {
      const reg = await registration();
      const sub = await reg.pushManager.getSubscription();
      if (sub) await sub.unsubscribe();
      return true;
    }
  };
})();
