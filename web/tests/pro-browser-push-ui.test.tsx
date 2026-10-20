import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { BrowserPushDeps, KeyStore, PushPermission } from '../lib/pro/browser-push';

const replace = vi.fn();
const push = vi.fn();
const routerMock = { replace, push };
let pathname = '/pro/notifications';
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => pathname,
}));
vi.mock('next/link', async () => {
  const React = await import('react');
  return {
    default: ({
      href,
      children,
      prefetch: _prefetch,
      ...rest
    }: { href: string; children: React.ReactNode; prefetch?: boolean } & React.AnchorHTMLAttributes<HTMLAnchorElement>) =>
      React.createElement(
        'a',
        { ...rest, href, onClick: (e: React.MouseEvent) => e.preventDefault() },
        children,
      ),
  };
});

// The browser and Firebase, as this test says they are.
let deps: (BrowserPushDeps & { calls: string[]; data: Record<string, string> }) | null = null;
vi.mock('../lib/pro/browser-push-deps', () => ({
  getBrowserPushDeps: () => deps,
}));

import { BrowserPushBand } from '../components/pro/BrowserPushBand';
import { ProLogoutButton } from '../components/pro/ProLogoutButton';
import { ProMembershipProvider } from '../components/pro/ProMembershipContext';
import { ProNotificationsClient } from '../components/pro/ProNotificationsClient';
import { ProShell } from '../components/pro/ProShell';

/// docs/design/web-pro-browser-push.md — the owner's decisions (2026-10-20):
/// like the app (the band once, then the Notifications row), computers only,
/// the words of §9 as written.

function makeDeps(o: {
  perm?: PushPermission;
  answer?: PushPermission;
  phone?: boolean;
  supported?: boolean;
  data?: Record<string, string>;
  tokenFails?: boolean;
  registerOk?: boolean;
  unregisterOk?: boolean;
} = {}) {
  let perm: PushPermission = o.perm ?? 'default';
  const data: Record<string, string> = { ...(o.data ?? {}) };
  const calls: string[] = [];
  const store: KeyStore = {
    get: (k) => data[k] ?? null,
    set: (k, v) => {
      data[k] = v;
    },
    remove: (k) => {
      delete data[k];
    },
  };
  return {
    calls,
    data,
    store,
    supported: () => o.supported ?? true,
    phone: () => o.phone ?? false,
    permission: () => perm,
    requestPermission: async () => {
      calls.push('request');
      perm = o.answer ?? 'granted';
      return perm;
    },
    token: async () => {
      calls.push('token');
      if (o.tokenFails) throw new Error('push service error');
      return 'tok-1';
    },
    dropToken: async () => {
      calls.push('drop');
    },
    register: async (t: string) => {
      calls.push(`register:${t}`);
      return o.registerOk ?? true;
    },
    unregister: async (t: string) => {
      calls.push(`unregister:${t}`);
      return o.unregisterOk ?? true;
    },
  };
}

const OWNER = {
  account: { id: 'acc1', email: 'salon@example.com' },
  provider: { id: 'p1', name: 'Beauté Divine' },
  membership: { role: 'owner', capabilities: ['clients.view', 'profile.manage'] },
};

let feedReads = 0;
const order: string[] = [];

beforeEach(() => {
  deps = null;
  feedReads = 0;
  order.length = 0;
  pathname = '/pro/notifications';
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const u = String(url);
      if (u === '/api/pro/me') return new Response(JSON.stringify(OWNER), { status: 200 });
      if (u === '/api/pro/salons') {
        return new Response(
          JSON.stringify({
            items: [{ salonId: 'p1', salonName: 'Beauté Divine', role: 'owner', salonStatus: 'active' }],
            canAddSalon: false,
          }),
          { status: 200 },
        );
      }
      if (u === '/api/pro/notifications') {
        feedReads++;
        return new Response(JSON.stringify({ items: [] }), { status: 200 });
      }
      if (u === '/api/pro/notification-preferences') {
        return new Response(
          JSON.stringify({ reminders: true, marketing: true, push: true, emailAlerts: true }),
          { status: 200 },
        );
      }
      if (u === '/api/pro/auth/logout' && init?.method === 'POST') {
        order.push('logout');
        return new Response('{}', { status: 200 });
      }
      return new Response('{}', { status: 404 });
    }),
  );
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
  push.mockReset();
});

const BAND_TITLE = 'Activer les notifications';
const BAND_TEXT =
  'Soyez prévenu·e sur cet ordinateur dès qu’un client réserve, reporte, annule ou envoie son acompte, et ne manquez aucune demande.';
const ROW_TITLE = 'Notifications du navigateur';
const ROW_TEXT =
  'Sur cet ordinateur, même quand MyWeli n’est pas ouvert, tant que votre navigateur l’est : nouvelle demande, report, annulation, justificatif d’acompte.';

describe('the Accueil band (Q2: once, like the app)', () => {
  it('a computer that has not answered: the band, its words, « Activer » and « Plus tard »', async () => {
    deps = makeDeps();
    render(<BrowserPushBand />);
    expect(await screen.findByRole('heading', { name: BAND_TITLE })).toBeInTheDocument();
    expect(screen.getByText(BAND_TEXT)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Activer' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Plus tard' })).toBeInTheDocument();
    // Showing it asks nothing: only « Activer » may (a browser buries a
    // prompt no gesture asked for).
    expect(deps.calls).toEqual([]);
  });

  it('« Plus tard » → gone, and never again on this browser; nothing asked', async () => {
    deps = makeDeps();
    const { unmount } = render(<BrowserPushBand />);
    fireEvent.click(await screen.findByRole('button', { name: 'Plus tard' }));
    expect(screen.queryByRole('heading', { name: BAND_TITLE })).toBeNull();
    expect(deps.calls).toEqual([]);
    unmount();
    render(<BrowserPushBand />);
    await new Promise((r) => setTimeout(r, 20));
    expect(screen.queryByRole('heading', { name: BAND_TITLE })).toBeNull();
  });

  it('« Activer » → the browser’s question, this browser registered, then « Notifications activées sur cet ordinateur. »', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    try {
      deps = makeDeps();
      render(<BrowserPushBand />);
      fireEvent.click(await screen.findByRole('button', { name: 'Activer' }));
      expect(await screen.findByRole('status')).toHaveTextContent(
        'Notifications activées sur cet ordinateur.',
      );
      expect(deps.calls).toEqual(['request', 'token', 'register:tok-1']);
      await act(async () => {
        await vi.advanceTimersByTimeAsync(5000);
      });
      expect(screen.queryByText('Notifications activées sur cet ordinateur.')).toBeNull();
    } finally {
      vi.useRealTimers();
    }
  });

  it('refused at the browser’s question → the band goes', async () => {
    deps = makeDeps({ answer: 'denied' });
    render(<BrowserPushBand />);
    fireEvent.click(await screen.findByRole('button', { name: 'Activer' }));
    await waitFor(() => expect(screen.queryByRole('heading', { name: BAND_TITLE })).toBeNull());
  });

  it('the activation fails → it says so, and « Activer » stays to retry', async () => {
    deps = makeDeps({ tokenFails: true });
    render(<BrowserPushBand />);
    fireEvent.click(await screen.findByRole('button', { name: 'Activer' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('L’activation a échoué. Réessayez.');
    expect(screen.getByRole('button', { name: 'Activer' })).toBeInTheDocument();
  });

  it('never on a phone, never unconfigured, never once answered', async () => {
    for (const d of [makeDeps({ phone: true }), null, makeDeps({ perm: 'granted' }), makeDeps({ perm: 'denied' })]) {
      deps = d;
      const { unmount } = render(<BrowserPushBand />);
      await new Promise((r) => setTimeout(r, 20));
      expect(screen.queryByRole('heading', { name: BAND_TITLE })).toBeNull();
      unmount();
    }
  });
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

const rowSwitch = () => screen.findByRole('switch', { name: ROW_TITLE });

describe('« Notifications du navigateur » on the Notifications page (§3)', () => {
  it('above « Alertes par e-mail », under « Préférences », off until asked', async () => {
    deps = makeDeps();
    host();
    const sw = await rowSwitch();
    expect(sw).toHaveAttribute('aria-checked', 'false');
    expect(screen.getByText(ROW_TEXT)).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Préférences' })).toBeInTheDocument();
    const email = await screen.findByRole('switch', { name: 'Alertes par e-mail' });
    expect(sw.compareDocumentPosition(email) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it('on → the browser’s question, then this browser registered', async () => {
    deps = makeDeps();
    host();
    fireEvent.click(await rowSwitch());
    await waitFor(async () => expect(await rowSwitch()).toHaveAttribute('aria-checked', 'true'));
    expect(deps.calls).toEqual(['request', 'token', 'register:tok-1']);
  });

  it('off → this browser unregistered', async () => {
    deps = makeDeps({ perm: 'granted' });
    host();
    await waitFor(() => expect(deps!.calls).toContain('register:tok-1')); // the sign-in re-registration
    deps.calls.length = 0;
    const sw = await rowSwitch();
    expect(sw).toHaveAttribute('aria-checked', 'true');
    fireEvent.click(sw);
    await waitFor(async () => expect(await rowSwitch()).toHaveAttribute('aria-checked', 'false'));
    expect(deps.calls).toEqual(['token', 'unregister:tok-1', 'drop']);
  });

  it('the activation fails → back off, « L’activation a échoué. Réessayez. »', async () => {
    deps = makeDeps({ registerOk: false });
    host();
    fireEvent.click(await rowSwitch());
    expect(await screen.findByText('L’activation a échoué. Réessayez.')).toBeInTheDocument();
    expect(await rowSwitch()).toHaveAttribute('aria-checked', 'false');
  });

  it('switching off fails → still on, « L’enregistrement a échoué. Réessayez. »', async () => {
    deps = makeDeps({ perm: 'granted', unregisterOk: false });
    host();
    fireEvent.click(await rowSwitch());
    expect(await screen.findByText('L’enregistrement a échoué. Réessayez.')).toBeInTheDocument();
    expect(await rowSwitch()).toHaveAttribute('aria-checked', 'true');
  });

  it('refused at the question → the blocked words, no switch', async () => {
    deps = makeDeps({ answer: 'denied' });
    host();
    fireEvent.click(await rowSwitch());
    expect(await screen.findByText('Notifications bloquées pour ce navigateur')).toBeInTheDocument();
    expect(screen.queryByRole('switch', { name: ROW_TITLE })).toBeNull();
  });

  it('blocked: how to allow it again — no switch a page could not honour', async () => {
    deps = makeDeps({ perm: 'denied' });
    host();
    expect(await screen.findByText('Notifications bloquées pour ce navigateur')).toBeInTheDocument();
    expect(
      screen.getByText(
        'Autorisez myweli.com dans les réglages du site (l’icône à gauche de l’adresse), puis rechargez la page, pour être prévenu·e des réservations, reports, annulations et acomptes de vos clients.',
      ),
    ).toBeInTheDocument();
    expect(screen.queryByRole('switch', { name: ROW_TITLE })).toBeNull();
  });

  it('a phone: the app does it (Q3) — no switch', async () => {
    deps = makeDeps({ phone: true });
    host();
    expect(
      await screen.findByText('Sur téléphone, les notifications passent par l’app MyWeli Pro.'),
    ).toBeInTheDocument();
    expect(screen.queryByRole('switch', { name: ROW_TITLE })).toBeNull();
  });

  it('a browser that cannot: says so — no switch', async () => {
    deps = makeDeps({ supported: false });
    host();
    expect(
      await screen.findByText('Ce navigateur ne peut pas afficher de notifications.'),
    ).toBeInTheDocument();
    expect(screen.queryByRole('switch', { name: ROW_TITLE })).toBeNull();
  });

  it('not configured → no row at all', async () => {
    deps = null;
    host();
    await screen.findByRole('switch', { name: 'Alertes par e-mail' });
    expect(screen.queryByText(ROW_TITLE)).toBeNull();
  });
});

describe('the shell: sign-in and an arriving push', () => {
  it('a permitted browser re-registers at sign-in, without a question', async () => {
    deps = makeDeps({ perm: 'granted' });
    host();
    await waitFor(() => expect(deps!.calls).toEqual(['token', 'register:tok-1']));
  });

  it('a push the service worker received → the feed is read at once, not in 60 s', async () => {
    deps = makeDeps({ perm: 'granted' });
    const listeners: ((e: MessageEvent) => void)[] = [];
    vi.stubGlobal('navigator', {
      ...navigator,
      serviceWorker: {
        addEventListener: (_: string, fn: (e: MessageEvent) => void) => listeners.push(fn),
        removeEventListener: () => {},
      },
    });
    host();
    await waitFor(() => expect(feedReads).toBeGreaterThan(0));
    await waitFor(() => expect(listeners.length).toBeGreaterThan(0));
    const before = feedReads;
    act(() => {
      for (const fn of listeners) fn({ data: { type: 'myweli-pro-push' } } as MessageEvent);
    });
    await waitFor(() => expect(feedReads).toBe(before + 1));
    // Any other message is not ours.
    act(() => {
      for (const fn of listeners) fn({ data: { type: 'other' } } as MessageEvent);
    });
    await new Promise((r) => setTimeout(r, 20));
    expect(feedReads).toBe(before + 1);
  });
});

describe('sign-out: a shared computer stops receiving', () => {
  it('this browser is unregistered BEFORE the session goes', async () => {
    deps = makeDeps({ perm: 'granted' });
    const unregister = deps.unregister;
    deps.unregister = async (t) => {
      order.push('unregister');
      return unregister(t);
    };
    render(<ProLogoutButton />);
    fireEvent.click(screen.getByRole('button', { name: /Se déconnecter/ }));
    await waitFor(() => expect(order).toEqual(['unregister', 'logout']));
  });
});
