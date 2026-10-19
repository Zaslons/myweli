import { describe, expect, it } from 'vitest';
import {
  arrivalAnnouncement,
  badgeLabel,
  newUnreadIds,
  proWebRouteFor,
  salonOf,
  unreadLabel,
  withUnreadPrefix,
} from '../lib/pro/notifications';

/// The salon's notification center on the web — the pure half
/// (docs/design/web-pro-notifications.md §3).

const note = (id: string, read = false, route: string | null = null) => ({
  id,
  type: 'general',
  title: 'Nouvelle réservation',
  body: 'Nouvelle demande de réservation le 28/06/2026 à 14:30.',
  createdAt: '2026-06-28T10:00:00.000Z',
  read,
  route,
});

describe('proWebRouteFor — the routes SalonNotifier writes → the web (§3.5)', () => {
  it('a booking, with its salon carried along', () => {
    expect(proWebRouteFor('/pro/appointment/a1?salon=p2')).toBe(
      '/pro/rendez-vous/a1?salon=p2',
    );
  });

  it('a booking without a salon stays a booking', () => {
    expect(proWebRouteFor('/pro/appointment/a1')).toBe('/pro/rendez-vous/a1');
  });

  it('the list', () => {
    expect(proWebRouteFor('/pro/appointments')).toBe('/pro/rendez-vous');
  });

  it('the id is encoded — a route is server data, never markup', () => {
    expect(proWebRouteFor('/pro/appointment/a 1?salon=p&2')).toBe(
      '/pro/rendez-vous/a%201?salon=p',
    );
  });

  it('anything else → no link', () => {
    for (const r of [null, undefined, '', '/bookings', '/pro/profile', 'https://evil.test/pro/appointments']) {
      expect(proWebRouteFor(r)).toBeNull();
    }
  });
});

describe('salonOf', () => {
  it('reads ?salon=', () => {
    expect(salonOf('/pro/appointment/a1?salon=p2')).toBe('p2');
  });
  it('none → null', () => {
    expect(salonOf('/pro/appointment/a1')).toBeNull();
    expect(salonOf(null)).toBeNull();
  });
});

describe('the count', () => {
  it('badge: the number, capped at 99+', () => {
    expect(badgeLabel(1)).toBe('1');
    expect(badgeLabel(99)).toBe('99');
    expect(badgeLabel(100)).toBe('99+');
  });

  it('the accessible name carries it, in French number agreement', () => {
    expect(unreadLabel(0)).toBe('Notifications');
    expect(unreadLabel(1)).toBe('Notifications, 1 non lue');
    expect(unreadLabel(3)).toBe('Notifications, 3 non lues');
  });
});

describe('arrivals — what the polite region says (§3.2)', () => {
  it('first load → nothing is « new »', () => {
    expect(newUnreadIds(null, [note('n1'), note('n2')])).toEqual([]);
  });

  it('an unread row the last fetch did not have is new', () => {
    const before = [note('n1')];
    expect(newUnreadIds(before, [note('n2'), note('n1')])).toEqual(['n2']);
  });

  it('a row read locally that comes back unread (a refused write) is NOT new', () => {
    expect(newUnreadIds([note('n1', true)], [note('n1', false)])).toEqual([]);
  });

  it('a new row already read elsewhere is not announced', () => {
    expect(newUnreadIds([], [note('n3', true)])).toEqual([]);
  });

  it('the sentence', () => {
    expect(arrivalAnnouncement(0)).toBe('');
    expect(arrivalAnnouncement(1)).toBe('1 nouvelle notification');
    expect(arrivalAnnouncement(3)).toBe('3 nouvelles notifications');
  });
});

describe('the tab title', () => {
  it('prefixes the count, replaces an old one, removes it at zero', () => {
    expect(withUnreadPrefix('Pro — Aujourd’hui', 3)).toBe('(3) Pro — Aujourd’hui');
    expect(withUnreadPrefix('(3) Pro — Aujourd’hui', 1)).toBe('(1) Pro — Aujourd’hui');
    expect(withUnreadPrefix('(3) Pro — Aujourd’hui', 0)).toBe('Pro — Aujourd’hui');
    expect(withUnreadPrefix('(99+) Pro', 120)).toBe('(99+) Pro');
  });

  it('is idempotent — the observer that re-applies it cannot loop', () => {
    const once = withUnreadPrefix('Pro — Avis', 2);
    expect(withUnreadPrefix(once, 2)).toBe(once);
  });
});
