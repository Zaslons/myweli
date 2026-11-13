/* The Pro area's service worker (scope /pro/) — the salon's browser
 * notifications. Design: docs/design/web-pro-browser-push.md §5.
 *
 * It does two things and nothing else: show a push, and open its booking on a
 * click. **No cache and no fetch handler**: it can never serve a stale page.
 *
 * The push is the salon notifier's FCM message, exactly what the app gets:
 * `notification` { title, body } (no client name or phone — threat T58) and
 * `data` { event, appointmentId, providerId, route }. `route` is the APP's
 * path and is never followed: the web link is BUILT from the ids, each
 * checked against a pattern, so a message can only ever open a booking of
 * the Pro area, its list, or « Aujourd'hui ».
 *
 * B0.18 (docs/design/web-salon-validation.md §4.7): MyWeli's decision on a
 * salon's request — `salon.validation.approved` / `.refused`, data
 * { event, providerId, route } — opens « Aujourd'hui » on that salon
 * (`/pro?salon={providerId}`), which switches to it once.
 */

var ID = /^[A-Za-z0-9_-]{1,128}$/;
var LIST = '/pro/rendez-vous';
var HOME = '/pro';
var BOOKING = /^\/pro\/rendez-vous\/[A-Za-z0-9_-]{1,128}\?salon=[A-Za-z0-9_-]{1,128}$/;
var SALON_HOME = /^\/pro(\?salon=[A-Za-z0-9_-]{1,128})?$/;
var VALIDATION_EVENTS = ['salon.validation.approved', 'salon.validation.refused'];

function isValidationEvent(data) {
  return !!data && VALIDATION_EVENTS.indexOf(data.event) !== -1;
}

function bookingUrl(data) {
  var id = data && data.appointmentId;
  var salon = data && data.providerId;
  if (isValidationEvent(data)) {
    return typeof salon === 'string' && ID.test(salon) ? HOME + '?salon=' + salon : HOME;
  }
  if (typeof id === 'string' && ID.test(id) && typeof salon === 'string' && ID.test(salon)) {
    return LIST + '/' + id + '?salon=' + salon;
  }
  return LIST;
}

/// One notification per subject: a booking's event, or a salon's decision
/// (a second decision replaces the first).
function tagOf(data) {
  if (typeof data.event !== 'string') return undefined;
  if (typeof data.appointmentId === 'string') return data.event + ':' + data.appointmentId;
  if (isValidationEvent(data) && typeof data.providerId === 'string' && ID.test(data.providerId)) {
    return 'salon.validation:' + data.providerId;
  }
  return undefined;
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
  var tag = tagOf(data);
  event.waitUntil(
    Promise.all([
      // A browser requires every push to show something — an unreadable one
      // still says who it is from.
      self.registration.showNotification(n.title || 'MyWeli Pro', {
        body: n.body || '',
        icon: '/android-chrome-192.png',
        tag: tag,
        // A decision replacing an earlier one on the same salon alerts again
        // (renotify needs a tag, or showNotification throws).
        renotify: !!tag && isValidationEvent(data),
        data: { url: bookingUrl(data) },
      }),
      // An open tab re-reads the feed now, not in its next 60 s — and, told
      // the event, « Aujourd'hui » re-reads a salon MyWeli just decided on.
      self.clients
        .matchAll({ type: 'window', includeUncontrolled: true })
        .then(function (tabs) {
          var message = { type: 'myweli-pro-push' };
          if (typeof data.event === 'string') message.event = data.event;
          tabs.forEach(function (tab) {
            tab.postMessage(message);
          });
        }),
    ]),
  );
});

self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  var wanted = event.notification.data && event.notification.data.url;
  var url =
    typeof wanted === 'string' && (BOOKING.test(wanted) || SALON_HOME.test(wanted))
      ? wanted
      : LIST;
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (tabs) {
      var pathOf = function (tab) {
        try {
          return new URL(tab.url).pathname;
        } catch (e) {
          return '';
        }
      };
      // A tab this worker controls first (`/pro/…`): « Aujourd'hui » itself
      // (`/pro`) lies outside the `/pro/` scope, and navigate() rejects an
      // uncontrolled tab — it then still gets the new tab below. The Pro
      // area, not /professionnels.
      var pro =
        tabs.find(function (tab) {
          return pathOf(tab).indexOf('/pro/') === 0;
        }) ||
        tabs.find(function (tab) {
          return pathOf(tab) === '/pro';
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
