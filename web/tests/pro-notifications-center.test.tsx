import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
const push = vi.fn();
// STABLE — a fresh object each call churns the membership probe's callback
// (pro-mobile-nav.test.tsx).
const routerMock = { replace, push };
let pathname = '/pro/notifications';
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => pathname,
}));
// A next/link outside an app router throws on click (no router to push to);
// a plain anchor keeps the href under test and swallows jsdom's
// « navigation not implemented ».
vi.mock('next/link', async () => {
  const React = await import('react');
  return {
    default: ({
      href,
      children,
      onClick,
      prefetch: _prefetch,
      ...rest
    }: {
      href: string;
      children: React.ReactNode;
      onClick?: (e: React.MouseEvent<HTMLAnchorElement>) => void;
      prefetch?: boolean;
    } & React.AnchorHTMLAttributes<HTMLAnchorElement>) =>
      React.createElement(
        'a',
        {
          ...rest,
          href,
          onClick: (e: React.MouseEvent<HTMLAnchorElement>) => {
            onClick?.(e);
            e.preventDefault();
          },
        },
        children,
      ),
  };
});

import { ProMembershipProvider } from '../components/pro/ProMembershipContext';
import { ProNotificationsClient } from '../components/pro/ProNotificationsClient';
import { ProShell } from '../components/pro/ProShell';
import { NO_CONNECTION_MESSAGE } from '../lib/api/network';

/// The salon's notification center on the web
/// (docs/design/web-pro-notifications.md): the nav entry and the phone bell
/// with the count, the list, mark-read and its revert, « Tout marquer comme
/// lu », the four states, the salon a row is about, the 60-second refresh
/// that runs only while the tab is visible, the arrival announcement, the
/// tab title.

const OWNER = {
  account: { id: 'acc1', email: 'salon@example.com' },
  provider: { id: 'p1', name: 'Beauté Divine' },
  membership: { role: 'owner', capabilities: ['clients.view', 'profile.manage'] },
};

type Note = {
  id: string;
  type: string;
  title: string;
  body: string;
  createdAt: string;
  read: boolean;
  route: string | null;
};

const BOOKING: Note = {
  id: 'n1',
  type: 'general',
  title: 'Nouvelle réservation',
  body: 'Nouvelle demande de réservation le 28/06/2026 à 14:30.',
  createdAt: '2026-06-28T10:00:00.000Z',
  read: false,
  route: '/pro/appointment/a1?salon=p1',
};
const MOVED: Note = {
  id: 'n2',
  type: 'reschedule',
  title: 'Réservation reportée',
  body: 'Le client a reporté le rendez-vous du 27/06/2026 à 10:00 au 28/06/2026 à 15:30.',
  createdAt: '2026-06-27T10:00:00.000Z',
  read: false,
  route: '/pro/appointment/a2?salon=p2',
};
const OLD: Note = {
  id: 'n3',
  type: 'cancellation',
  title: 'Réservation annulée',
  body: 'Le client a annulé le rendez-vous du 20/06/2026 à 09:00.',
  createdAt: '2026-06-20T10:00:00.000Z',
  read: true,
  route: '/pro/appointment/a3?salon=p1',
};

let feed: Note[] | 'offline' | 'error' = [];
let salons = [{ salonId: 'p1', salonName: 'Beauté Divine', role: 'owner', salonStatus: 'active' }];
let readAnswer = 200;
let feedReads = 0;
const posts: string[] = [];

beforeEach(() => {
  feed = [BOOKING, MOVED, OLD];
  salons = [{ salonId: 'p1', salonName: 'Beauté Divine', role: 'owner', salonStatus: 'active' }];
  readAnswer = 200;
  feedReads = 0;
  posts.length = 0;
  pathname = '/pro/notifications';
  document.title = 'Pro — Notifications';
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const u = String(url);
      if (u === '/api/pro/me') {
        return new Response(JSON.stringify(OWNER), { status: 200 });
      }
      if (u === '/api/pro/salons') {
        return new Response(JSON.stringify({ items: salons, canAddSalon: false }), {
          status: 200,
        });
      }
      if (u === '/api/pro/notifications') {
        feedReads++;
        if (feed === 'offline') throw new TypeError('Failed to fetch');
        if (feed === 'error') return new Response('{}', { status: 500 });
        return new Response(JSON.stringify({ items: feed }), { status: 200 });
      }
      if (init?.method === 'POST' && u.startsWith('/api/pro/notifications/')) {
        posts.push(u);
        return new Response('{}', { status: readAnswer });
      }
      return new Response('{}', { status: 404 });
    }),
  );
});

afterEach(() => {
  cleanup();
  vi.useRealTimers();
  vi.unstubAllGlobals();
  replace.mockReset();
  push.mockReset();
});

function host() {
  return render(
    <ProMembershipProvider>
      <ProShell>
        <ProNotificationsClient />
      </ProShell>
    </ProMembershipProvider>,
  );
}

/// The two doors — the sidebar entry and the phone bar's bell. Waits for
/// BOTH: the bell renders before the sidebar's membership has loaded.
async function doors(name: string) {
  await waitFor(() => expect(screen.getAllByRole('link', { name })).toHaveLength(2));
  return screen.getAllByRole('link', { name });
}

describe('the doors carry the count (§3.1)', () => {
  it('the nav entry AND the phone bell say how many are unread', async () => {
    host();
    const links = await doors('Notifications, 2 non lues');
    expect(links).toHaveLength(2);
    for (const l of links) {
      expect(l).toHaveAttribute('href', '/pro/notifications');
      // The badge shows the number; the name already says it.
      expect(within(l).getByText('2')).toHaveAttribute('aria-hidden', 'true');
    }
  });

  it('nothing unread → the plain name and no badge', async () => {
    feed = [OLD];
    host();
    const links = await doors('Notifications');
    expect(links).toHaveLength(2);
    for (const l of links) expect(within(l).queryByText(/^\d/)).toBeNull();
  });
});

describe('the list (§3.3)', () => {
  it('each row is a LINK to its booking, carrying its salon', async () => {
    host();
    const row = await screen.findByRole('link', { name: /Nouvelle réservation/ });
    expect(row).toHaveAttribute('href', '/pro/rendez-vous/a1?salon=p1');
    expect(screen.getByRole('link', { name: /Réservation reportée/ })).toHaveAttribute(
      'href',
      '/pro/rendez-vous/a2?salon=p2',
    );
    // Unread rows are marked in words, not only in weight.
    expect(within(row).getByLabelText('Non lu')).toBeInTheDocument();
  });

  it('a click marks it read — the POST, and the count drops at once', async () => {
    host();
    fireEvent.click(await screen.findByRole('link', { name: /Nouvelle réservation/ }));
    expect(await doors('Notifications, 1 non lue')).toHaveLength(2);
    expect(posts).toEqual(['/api/pro/notifications/n1/read']);
  });

  it('a refused mark-read puts the row back and says why, under it', async () => {
    vi.mocked(fetch).mockImplementation(async (url, init) => {
      const u = String(url);
      if (init?.method === 'POST') {
        posts.push(u);
        throw new TypeError('Failed to fetch');
      }
      if (u === '/api/pro/notifications') {
        feedReads++;
        return new Response(JSON.stringify({ items: [BOOKING] }), { status: 200 });
      }
      if (u === '/api/pro/me') return new Response(JSON.stringify(OWNER), { status: 200 });
      if (u === '/api/pro/salons') {
        return new Response(JSON.stringify({ items: salons, canAddSalon: false }), { status: 200 });
      }
      return new Response('{}', { status: 404 });
    });
    host();
    fireEvent.click(await screen.findByRole('link', { name: /Nouvelle réservation/ }));
    expect(await screen.findByRole('alert')).toHaveTextContent(NO_CONNECTION_MESSAGE);
    expect(await doors('Notifications, 1 non lue')).toHaveLength(2);
  });

  it('« Tout marquer comme lu » reads them all, then leaves', async () => {
    host();
    fireEvent.click(await screen.findByRole('button', { name: 'Tout marquer comme lu' }));
    expect(await doors('Notifications')).toHaveLength(2);
    expect(posts).toEqual(['/api/pro/notifications/read-all']);
    expect(screen.queryByRole('button', { name: 'Tout marquer comme lu' })).toBeNull();
  });

  it('a multi-salon account sees which salon each row is about', async () => {
    salons = [
      { salonId: 'p1', salonName: 'Beauté Divine', role: 'owner', salonStatus: 'active' },
      { salonId: 'p2', salonName: 'Institut Libreville', role: 'owner', salonStatus: 'active' },
    ];
    host();
    const moved = await screen.findByRole('link', { name: /Réservation reportée/ });
    expect(await within(moved).findByText('Institut Libreville')).toBeInTheDocument();
  });

  it('a one-salon account is not told its own salon on every row', async () => {
    host();
    const row = await screen.findByRole('link', { name: /Nouvelle réservation/ });
    expect(within(row).queryByText('Beauté Divine')).toBeNull();
  });
});

describe('the four states (§4)', () => {
  it('empty → the four events the server sends a salon', async () => {
    feed = [];
    host();
    expect(await screen.findByText('Aucune notification')).toBeInTheDocument();
    expect(
      screen.getByText(
        'Les réservations, reports, annulations et acomptes de vos clients apparaîtront ici.',
      ),
    ).toBeInTheDocument();
  });

  it('no answer → « Pas de connexion », and « Réessayer » reads again', async () => {
    feed = 'offline';
    host();
    expect(await screen.findByText(NO_CONNECTION_MESSAGE)).toBeInTheDocument();
    feed = [BOOKING];
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    expect(await screen.findByRole('link', { name: /Nouvelle réservation/ })).toBeInTheDocument();
  });

  it('there is one h1, in every state', async () => {
    feed = 'error';
    host();
    expect(await screen.findByRole('button', { name: 'Réessayer' })).toBeInTheDocument();
    expect(screen.getAllByRole('heading', { level: 1 })).toHaveLength(1);
  });
});

describe('the count stays current while the tab is open (§3.2)', () => {
  let visibility: DocumentVisibilityState = 'visible';
  beforeEach(() => {
    visibility = 'visible';
    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      get: () => visibility,
    });
  });

  it('every 60 s while visible; never while hidden; at once on return', async () => {
    vi.useFakeTimers({ toFake: ['setInterval', 'clearInterval'] });
    host();
    await doors('Notifications, 2 non lues');
    const afterMount = feedReads;

    visibility = 'hidden';
    act(() => {
      vi.advanceTimersByTime(180_000);
    });
    expect(feedReads).toBe(afterMount);

    visibility = 'visible';
    act(() => {
      document.dispatchEvent(new Event('visibilitychange'));
    });
    await waitFor(() => expect(feedReads).toBe(afterMount + 1));

    act(() => {
      vi.advanceTimersByTime(60_000);
    });
    await waitFor(() => expect(feedReads).toBe(afterMount + 2));
  });

  it('an arrival is announced politely — and the first load is not', async () => {
    vi.useFakeTimers({ toFake: ['setInterval', 'clearInterval'] });
    host();
    await doors('Notifications, 2 non lues');
    const region = screen.getByTestId('pro-notifications-announcer');
    expect(region).toHaveAttribute('role', 'status');
    expect(region).toHaveTextContent('');

    feed = [{ ...BOOKING, id: 'n9' }, BOOKING, MOVED, OLD];
    act(() => {
      vi.advanceTimersByTime(60_000);
    });
    expect(await doors('Notifications, 3 non lues')).toHaveLength(2);
    expect(region).toHaveTextContent('1 nouvelle notification');
  });

  it('the tab title carries the count', async () => {
    host();
    await doors('Notifications, 2 non lues');
    await waitFor(() => expect(document.title).toBe('(2) Pro — Notifications'));
    fireEvent.click(screen.getByRole('button', { name: 'Tout marquer comme lu' }));
    await waitFor(() => expect(document.title).toBe('Pro — Notifications'));
  });
});
