/// The salon's notification center on the web — the pure half. Unit-tested
/// (tests/pro-notifications.test.ts). Design: docs/design/web-pro-notifications.md.

import type { AppNotification } from '../account/notifications';

/// How often the dashboard re-reads the feed while its tab is VISIBLE
/// (§3.2). A salon keeps this page open all day and the web has no push.
export const PRO_NOTIFICATIONS_POLL_MS = 60_000;

/// A feed route as path + query — a relative app path only (`/…`, never
/// `//host` or a full URL). Parsed by hand: a placeholder origin for `URL`
/// would be a third-party origin in the source (the CSP pin).
function parse(
  route: string | null | undefined,
): { path: string; query: URLSearchParams } | null {
  if (!route || !route.startsWith('/') || route.startsWith('//')) return null;
  const [path, query = ''] = route.split('?', 2);
  return { path, query: new URLSearchParams(query) };
}

/// The salon a feed row is about (`?salon=` — R6), or null.
export function salonOf(route: string | null | undefined): string | null {
  return parse(route)?.query.get('salon') || null;
}

/// The routes `SalonNotifier` writes (the pro APP's paths) → the web's
/// (§3.5). The salon rides along: the detail switches to it first (§3.4).
/// Anything else → no link.
export function proWebRouteFor(route: string | null | undefined): string | null {
  const parsed = parse(route);
  if (!parsed) return null;
  if (parsed.path === '/pro/appointments') return '/pro/rendez-vous';
  const m = /^\/pro\/appointment\/([^/]+)$/.exec(parsed.path);
  if (!m) return null;
  const id = encodeURIComponent(m[1]);
  const salon = parsed.query.get('salon');
  return salon
    ? `/pro/rendez-vous/${id}?salon=${encodeURIComponent(salon)}`
    : `/pro/rendez-vous/${id}`;
}

/// The badge: the number, capped.
export function badgeLabel(unread: number): string {
  return unread > 99 ? '99+' : String(unread);
}

/// The doors' accessible name — it carries the count the badge shows.
export function unreadLabel(unread: number): string {
  if (unread <= 0) return 'Notifications';
  return `Notifications, ${unread} non lue${unread > 1 ? 's' : ''}`;
}

/// The unread rows of [next] the previous fetch did not have. The FIRST
/// fetch (`previous` null) has no « new » rows, and a row that comes back
/// unread after a refused local write is not new either: arrival is about
/// ids, never about the count going up.
export function newUnreadIds(
  previous: readonly AppNotification[] | null,
  next: readonly AppNotification[],
): string[] {
  if (previous === null) return [];
  const seen = new Set(previous.map((n) => n.id));
  return next.filter((n) => !n.read && !seen.has(n.id)).map((n) => n.id);
}

/// What the polite live region says about [count] arrivals.
export function arrivalAnnouncement(count: number): string {
  if (count <= 0) return '';
  return count === 1
    ? '1 nouvelle notification'
    : `${count} nouvelles notifications`;
}

/// The tab title with the count in front — « (3) Pro — Aujourd’hui » —
/// replacing any count already there, removing it at zero. Idempotent, so
/// the observer that re-applies it after a navigation cannot loop.
export function withUnreadPrefix(title: string, unread: number): string {
  const bare = title.replace(/^\(\d+\+?\)\s/, '');
  return unread > 0 ? `(${badgeLabel(unread)}) ${bare}` : bare;
}
