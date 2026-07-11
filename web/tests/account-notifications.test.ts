import { describe, expect, it } from 'vitest';
import {
  type AppNotification,
  unreadCount,
  webRouteFor,
} from '../lib/account/notifications';

describe('webRouteFor (parity 5.1)', () => {
  it('maps the notifier’s app deep link to the web account', () => {
    expect(webRouteFor('/bookings')).toBe('/mon-compte');
    expect(webRouteFor('/bookings/abc')).toBe('/mon-compte');
  });

  it('ignores unknown or missing routes', () => {
    expect(webRouteFor('/whatever')).toBeNull();
    expect(webRouteFor(null)).toBeNull();
    expect(webRouteFor(undefined)).toBeNull();
    expect(webRouteFor('')).toBeNull();
  });
});

describe('unreadCount', () => {
  const n = (id: string, read: boolean): AppNotification => ({
    id,
    type: 'general',
    title: 't',
    body: 'b',
    createdAt: '2026-07-01T10:00:00.000Z',
    read,
  });

  it('counts only unread items', () => {
    expect(unreadCount([n('1', false), n('2', true), n('3', false)])).toBe(2);
    expect(unreadCount([])).toBe(0);
  });
});
