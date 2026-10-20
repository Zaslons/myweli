// @vitest-environment node
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { beforeEach, describe, expect, it, vi } from 'vitest';

/// docs/design/web-pro-browser-push.md §5 — the Pro area's service worker,
/// loaded as the browser loads it (the file itself, in a fake worker scope).
/// It shows the push, tells an open tab to re-read the feed, and a click
/// opens the booking in its salon. Nothing else: no cache, no fetch handler.

const SOURCE = readFileSync(join(__dirname, '..', 'public', 'pro', 'push-sw.js'), 'utf8');

type Listener = (e: unknown) => void;

function load() {
  const listeners: Record<string, Listener[]> = {};
  const shown: { title: string; options: Record<string, unknown> }[] = [];
  const posted: unknown[] = [];
  const opened: string[] = [];
  const navigated: string[] = [];
  let windows: { url: string; focused?: boolean }[] = [];
  const self = {
    addEventListener: (type: string, fn: Listener) => {
      (listeners[type] ??= []).push(fn);
    },
    skipWaiting: vi.fn(async () => {}),
    registration: {
      showNotification: vi.fn(async (title: string, options: Record<string, unknown>) => {
        shown.push({ title, options });
      }),
    },
    clients: {
      claim: vi.fn(async () => {}),
      matchAll: vi.fn(async () =>
        windows.map((w) => ({
          url: w.url,
          postMessage: (m: unknown) => posted.push(m),
          focus: vi.fn(async function (this: unknown) {
            w.focused = true;
            return this;
          }),
          navigate: vi.fn(async (u: string) => {
            navigated.push(u);
            return null;
          }),
        })),
      ),
      openWindow: vi.fn(async (u: string) => {
        opened.push(u);
        return null;
      }),
    },
  };
  new Function('self', SOURCE)(self);

  async function fire(type: string, event: Record<string, unknown>) {
    const pending: Promise<unknown>[] = [];
    for (const fn of listeners[type] ?? []) {
      fn({ ...event, waitUntil: (p: Promise<unknown>) => pending.push(p) });
    }
    await Promise.all(pending);
  }

  return {
    listeners,
    shown,
    posted,
    opened,
    navigated,
    setWindows: (w: { url: string }[]) => {
      windows = w;
    },
    push: (payload: unknown) =>
      fire('push', {
        data: payload === undefined ? null : { json: () => payload },
      }),
    click: (data: unknown) =>
      fire('notificationclick', { notification: { data, close: vi.fn() } }),
  };
}

const MESSAGE = {
  notification: {
    title: 'Nouvelle réservation',
    body: 'Nouvelle demande de réservation le 21/10/2026 à 10:00.',
  },
  data: {
    event: 'new_booking',
    appointmentId: 'a1',
    providerId: 'p1',
    route: '/pro/appointment/a1?salon=p1',
  },
};

describe('the Pro service worker', () => {
  let sw: ReturnType<typeof load>;
  beforeEach(() => {
    sw = load();
  });

  it('handles push, notificationclick, install, activate — and NOT fetch', () => {
    expect(Object.keys(sw.listeners).sort()).toEqual(
      ['activate', 'install', 'notificationclick', 'push'].sort(),
    );
  });

  it('a push shows the app’s title and sentence, with the MyWeli icon', async () => {
    await sw.push(MESSAGE);
    expect(sw.shown).toHaveLength(1);
    const [n] = sw.shown;
    expect(n.title).toBe('Nouvelle réservation');
    expect(n.options.body).toBe(MESSAGE.notification.body);
    expect(n.options.icon).toBe('/android-chrome-192.png');
    expect(n.options.data).toEqual({ url: '/pro/rendez-vous/a1?salon=p1' });
    // One notification per event and booking: a repeat replaces, never stacks.
    expect(n.options.tag).toBe('new_booking:a1');
  });

  it('an open MyWeli tab is told to re-read the feed at once', async () => {
    sw.setWindows([{ url: 'https://myweli.com/pro/notifications' }]);
    await sw.push(MESSAGE);
    expect(sw.posted).toEqual([{ type: 'myweli-pro-push' }]);
  });

  it('a push it cannot read still shows something (a browser requires it)', async () => {
    await sw.push(undefined);
    await sw.push({ data: {} });
    expect(sw.shown.map((n) => n.title)).toEqual(['MyWeli Pro', 'MyWeli Pro']);
    expect(sw.shown.every((n) => (n.options.data as { url: string }).url === '/pro/rendez-vous')).toBe(true);
  });

  it('the link is BUILT from the ids — never an address read from the message', async () => {
    for (const data of [
      { appointmentId: 'a1', providerId: 'p1?evil=1' },
      { appointmentId: '../admin', providerId: 'p1' },
      { appointmentId: 'a1' },
      { route: 'https://evil.example/pro', appointmentId: 'a1', providerId: 'https://evil.example' },
    ]) {
      sw = load();
      await sw.push({ notification: { title: 'T', body: 'B' }, data });
      expect((sw.shown[0].options.data as { url: string }).url, JSON.stringify(data)).toBe(
        '/pro/rendez-vous',
      );
    }
  });

  it('a click focuses the MyWeli Pro tab and takes it to the booking', async () => {
    sw.setWindows([
      { url: 'https://myweli.com/salons/abidjan' },
      { url: 'https://myweli.com/pro/rendez-vous' },
    ]);
    await sw.click({ url: '/pro/rendez-vous/a1?salon=p1' });
    expect(sw.navigated).toEqual(['/pro/rendez-vous/a1?salon=p1']);
    expect(sw.opened).toEqual([]);
  });

  it('no Pro tab → a new one at the booking', async () => {
    sw.setWindows([{ url: 'https://myweli.com/' }]);
    await sw.click({ url: '/pro/rendez-vous/a1?salon=p1' });
    expect(sw.opened).toEqual(['/pro/rendez-vous/a1?salon=p1']);
  });

  it('a click whose data is not ours opens the list, nowhere else', async () => {
    await sw.click({ url: 'https://evil.example/' });
    await sw.click(undefined);
    expect(sw.opened).toEqual(['/pro/rendez-vous', '/pro/rendez-vous']);
  });
});
