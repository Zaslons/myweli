/* The Pro area's service worker (scope /pro/) — the salon's browser
 * notifications. Design: docs/design/web-pro-browser-push.md §5.
 *
 * It does two things and nothing else: show a push, and open its booking on a
 * click. **No cache and no fetch handler**: it can never serve a stale page.
 *
 * The push is the salon notifier's FCM message, exactly what the app gets:
 * `notification` { title, body } (no client name or phone — threat T58) and
 * `data` { event, appointmentId, providerId, route }. `route` is the APP's
 * path and is never followed: the web link is BUILT from the two ids, each
 * checked against a pattern, so a message can only ever open a booking of
 * the Pro area or its list.
 */

var ID = /^[A-Za-z0-9_-]{1,128}$/;
var LIST = '/pro/rendez-vous';
var BOOKING = /^\/pro\/rendez-vous\/[A-Za-z0-9_-]{1,128}\?salon=[A-Za-z0-9_-]{1,128}$/;

function bookingUrl(data) {
  var id = data && data.appointmentId;
  var salon = data && data.providerId;
  if (typeof id === 'string' && ID.test(id) && typeof salon === 'string' && ID.test(salon)) {
    return LIST + '/' + id + '?salon=' + salon;
  }
  return LIST;
}

self.addEventListener('install', function (event) {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', function (event) {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('push', function (event) {
  var payload = {};
  try {
    payload = (event.data && event.data.json()) || {};
  } catch (e) {
    payload = {};
  }
  var n = payload.notification || {};
  var data = payload.data || {};
  var tag =
    typeof data.event === 'string' && typeof data.appointmentId === 'string'
      ? data.event + ':' + data.appointmentId
      : undefined;
  event.waitUntil(
    Promise.all([
      // A browser requires every push to show something — an unreadable one
      // still says who it is from.
      self.registration.showNotification(n.title || 'MyWeli Pro', {
        body: n.body || '',
        icon: '/android-chrome-192.png',
        tag: tag,
        data: { url: bookingUrl(data) },
      }),
      // An open tab re-reads the feed now, not in its next 60 s.
      self.clients
        .matchAll({ type: 'window', includeUncontrolled: true })
        .then(function (tabs) {
          tabs.forEach(function (tab) {
            tab.postMessage({ type: 'myweli-pro-push' });
          });
        }),
    ]),
  );
});

self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  var wanted = event.notification.data && event.notification.data.url;
  var url = typeof wanted === 'string' && BOOKING.test(wanted) ? wanted : LIST;
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (tabs) {
      var pro = tabs.find(function (tab) {
        try {
          // The Pro area, not /professionnels.
          var path = new URL(tab.url).pathname;
          return path === '/pro' || path.indexOf('/pro/') === 0;
        } catch (e) {
          return false;
        }
      });
      if (!pro) return self.clients.openWindow(url);
      return pro
        .focus()
        .then(function () {
          return pro.navigate(url);
        })
        .catch(function () {
          return self.clients.openWindow(url);
        });
    }),
  );
});
