import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { useState } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/// The router: `replace('/pro')` drops `?salon=` — as Next re-renders the page
/// with no `salon`, the harness below re-renders the client without it.
let dropSalonParam: (() => void) | null = null;
const replace = vi.fn((url: string) => {
  if (url === '/pro') dropSalonParam?.();
});
const routerMock = { replace };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => '/pro',
}));
vi.mock('../lib/pro/browser-push-deps', () => ({ getBrowserPushDeps: () => null }));

import { AujourdhuiClient } from '../components/pro/AujourdhuiClient';
import {
  ProMembershipProvider,
  useProMembership,
} from '../components/pro/ProMembershipContext';
import { resetLocalitiesClientCache } from '../lib/use-localities';

/// B0.18 on « Aujourd’hui » — docs/design/web-salon-validation.md §4.1–§4.6
/// (parent: salon-go-live-approval.md §6.1, §6.2, §8.4: « a new dashboard test
/// for every state (none exists today) », and `/pro?salon=` switching once,
/// with a two-salon case).

const OWNER = {
  role: 'owner',
  capabilities: [
    'availability.manage', 'catalogue.manage', 'clients.view', 'finances.view',
    'journal.manage.all', 'journal.manage.own', 'journal.view.all', 'journal.view.own',
    'members.manage', 'profile.manage', 'salon.publish', 'subscription.manage',
  ],
};
const MANAGER = {
  role: 'manager',
  capabilities: OWNER.capabilities.filter(
    (c) => !['salon.publish', 'finances.view', 'members.manage', 'subscription.manage'].includes(c),
  ),
};

const COMPLETE = {
  description: 'Un salon.',
  address: 'Rue des Jardins',
  commune: 'Cocody',
  areaId: 'ci-abj-cocody',
  latitude: 5.3,
  longitude: -3.9,
  services: [
    { id: 's1', name: 'A', price: 1, active: true },
    { id: 's2', name: 'B', price: 1, active: true },
    { id: 's3', name: 'C', price: 1, active: true },
  ],
  artists: [],
  imageUrls: ['a', 'b', 'c'],
  availability: { providerId: 'x', weeklySchedule: { '0': [{ startTime: '09:00', endTime: '18:00' }] }, blockedDates: [], bufferMinutes: 0 },
};

type Profile = Record<string, unknown>;
const profile = (
  id: string,
  name: string,
  status: string,
  validation?: unknown,
  membership: unknown = OWNER,
): Profile => ({
  account: { id: `acc-${id}`, businessName: name, phoneNumber: '+2250700000000', email: 'o@salon.test' },
  provider: { id, name, status, timezone: 'Africa/Abidjan', ...COMPLETE },
  membership,
  ...(validation === undefined ? {} : { validation }),
});

const PENDING = { state: 'pending', submittedAt: '2026-11-13T10:00:00Z', wentLive: false };

type Handler = (body: unknown) => Response | Promise<Response>;

/// A small B0.18 BFF: /me answers the SELECTED salon; « Mes salons »; the
/// select (validated, then the cookie); the card's reads; anything else 404.
/// Every call is recorded (`METHOD path`).
function serve(
  salons: Record<string, Profile>,
  {
    selected = Object.keys(salons)[0],
    me,
    select,
    publish,
  }: {
    selected?: string;
    me?: () => Response;
    select?: Handler;
    publish?: Handler;
  } = {},
) {
  const calls: string[] = [];
  const state = { selected };
  const json = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), { status });
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const method = init?.method ?? 'GET';
      const u = String(url);
      calls.push(`${method} ${u}`);
      const body = init?.body ? JSON.parse(String(init.body)) : undefined;
      if (u === '/api/pro/me') return me ? me() : json(200, salons[state.selected]);
      if (u === '/api/pro/salons/select') {
        if (select) return select(body);
        const id = (body as { salonId: string }).salonId;
        if (!salons[id]) return json(403, { error: 'forbidden' });
        state.selected = id;
        return json(200, salons[id]);
      }
      if (u === '/api/pro/salons') {
        return json(200, {
          items: Object.values(salons).map((p) => ({
            salonId: (p.provider as { id: string }).id,
            salonName: (p.provider as { name: string }).name,
            role: 'owner',
            salonStatus: (p.provider as { status: string }).status,
            verified: false,
          })),
          canAddSalon: false,
        });
      }
      if (u === '/api/pro/publish' && publish) return publish(body);
      if (u === '/api/pro/appointments') return json(200, { items: [] });
      if (u === '/api/pro/invitations') return json(200, { invitations: [] });
      if (u.startsWith('/api/pro/dashboard')) return json(200, {});
      if (u.startsWith('/api/pro/acompte')) {
        return json(200, { depositRequired: false, depositPercentage: 0.3, cancellationWindowHours: 24 });
      }
      if (u === '/api/pro/kyc') return json(200, { status: 'pending', documents: [] });
      return json(404, {});
    }),
  );
  const count = (call: string) => calls.filter((c) => c === call).length;
  return { calls, count, state };
}

/// « Aujourd’hui » under the real membership provider, as the dashboard
/// layout mounts it — the provider re-keys the page on a switch. [salon] is
/// the page's `?salon=`, dropped when the client calls `replace('/pro')`.
function Harness({ salon: initial }: { salon?: string }) {
  const [salon, setSalon] = useState(initial);
  dropSalonParam = () => setSalon(undefined);
  return (
    <ProMembershipProvider>
      <AujourdhuiClient salon={salon} />
      <SwitchButton />
    </ProMembershipProvider>
  );
}

/// « Mes salons »'s switch, without the sidebar's chrome.
function SwitchButton() {
  const { switchSalon } = useProMembership();
  return (
    <button type="button" onClick={() => void switchSalon('p1')}>
      test: passer à p1
    </button>
  );
}

beforeEach(() => {
  resetLocalitiesClientCache();
});
afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockClear();
  dropSalonParam = null;
});

const heading = () => screen.findByRole('heading', { level: 1, name: 'Aujourd’hui' });

describe('« Aujourd’hui » — the card in every state (owner)', () => {
  it('a server before B0.18 (no `validation`): today’s card and « Mettre en ligne »', async () => {
    serve({ p1: profile('p1', 'Beauté Divine', 'draft') });
    render(<Harness />);
    expect(await screen.findByRole('button', { name: 'Mettre en ligne' })).toBeTruthy();
    expect(screen.getByText('Votre salon n’est pas encore en ligne')).toBeTruthy();
  });

  it('never asked: « Demander la mise en ligne »', async () => {
    serve({ p1: profile('p1', 'Beauté Divine', 'draft', null) });
    render(<Harness />);
    expect(await screen.findByRole('button', { name: 'Demander la mise en ligne' })).toBeTruthy();
  });

  it('pending: « En cours de validation », no button', async () => {
    serve({ p1: profile('p1', 'Beauté Divine', 'draft', PENDING) });
    render(<Harness />);
    expect(await screen.findByText('En cours de validation')).toBeTruthy();
    expect(await screen.findByText('Demande envoyée le 13 novembre 2026')).toBeTruthy();
    expect(screen.queryByRole('button', { name: /mise en ligne|Mettre en ligne/ })).toBeNull();
  });

  it('refused: the reason and « Renvoyer pour validation »', async () => {
    serve({
      p1: profile('p1', 'Beauté Divine', 'draft', {
        state: 'refused',
        wentLive: false,
        refusal: { code: 'unconfirmed', final: false },
      }),
    });
    render(<Harness />);
    expect(await screen.findByText('Nous n’avons pas pu confirmer l’existence de ce salon.')).toBeTruthy();
    expect(await screen.findByRole('button', { name: 'Renvoyer pour validation' })).toBeTruthy();
  });

  it('suspended, new server: the banner (owner, 2026-11-13 — §9 Q2)', async () => {
    serve({ p1: profile('p1', 'Beauté Divine', 'suspended', null) });
    render(<Harness />);
    expect(await screen.findByText('Votre salon est suspendu')).toBeTruthy();
    expect(screen.getByText('Contactez MyWeli pour en savoir plus.')).toBeTruthy();
  });

  it('suspended, old server: no card at all, as today', async () => {
    serve({ p1: profile('p1', 'Beauté Divine', 'suspended') });
    render(<Harness />);
    await heading();
    await screen.findByText('Rendez-vous du jour');
    // Not the suspended banner — and not today's draft card either (the old
    // server's suspended salon never had one).
    expect(screen.queryByText(/suspendu/)).toBeNull();
    expect(screen.queryByText('Votre salon n’est pas encore en ligne')).toBeNull();
    expect(screen.queryByRole('button', { name: 'Mettre en ligne' })).toBeNull();
    expect(screen.queryByRole('link', { name: 'Aperçu de ma page' })).toBeNull();
  });

  it('live: no card', async () => {
    serve({ p1: profile('p1', 'Beauté Divine', 'active', { state: 'approved', wentLive: true }) });
    render(<Harness />);
    await heading();
    await screen.findByText('Rendez-vous du jour');
    expect(screen.queryByText(/en ligne/)).toBeNull();
  });

  it('a manager (no salon.publish) never gets the card — any state', async () => {
    for (const status of ['draft', 'suspended']) {
      serve({ p1: profile('p1', 'Beauté Divine', status, PENDING, MANAGER) });
      render(<Harness />);
      await heading();
      await screen.findByText('Rendez-vous du jour');
      expect(screen.queryByText('En cours de validation'), status).toBeNull();
      expect(screen.queryByText('Votre salon est suspendu'), status).toBeNull();
      cleanup();
    }
  });
});

describe('« Aujourd’hui » — after the publish', () => {
  it('202: « Demande envoyée… » is said, the card turns pending, the state is re-read', async () => {
    let asked = false;
    const salons = { p1: profile('p1', 'Beauté Divine', 'draft', null) };
    const { count } = serve(salons, {
      me: () =>
        new Response(
          JSON.stringify(asked ? profile('p1', 'Beauté Divine', 'draft', PENDING) : salons.p1),
          { status: 200 },
        ),
      publish: () => {
        asked = true;
        return new Response(JSON.stringify({ validation: PENDING }), { status: 202 });
      },
    });
    render(<Harness />);
    fireEvent.click(await screen.findByRole('button', { name: 'Demander la mise en ligne' }));
    const said = await screen.findByText('Demande envoyée. Nous vous préviendrons de la décision.');
    // In the page's live region, there before the text (WEB-SYSTEM §7).
    expect(said.closest('[role="status"]')).not.toBeNull();
    expect(await screen.findByText('En cours de validation')).toBeTruthy();
    expect(screen.queryByText(/🎉/)).toBeNull();
    // Re-read after the submit (§4.6): /me and « Mes salons ».
    await waitFor(() => expect(count('GET /api/pro/me')).toBeGreaterThanOrEqual(3));
    const salonsReads = count('GET /api/pro/salons');
    expect(salonsReads).toBeGreaterThanOrEqual(3);
  });

  it('202 whose body is unreadable: still « Demande envoyée », and the re-read settles the card', async () => {
    let asked = false;
    serve({ p1: profile('p1', 'Beauté Divine', 'draft', null) }, {
      me: () =>
        new Response(
          JSON.stringify(profile('p1', 'Beauté Divine', 'draft', asked ? PENDING : null)),
          { status: 200 },
        ),
      publish: () => {
        asked = true;
        return new Response('<html>', { status: 202 });
      },
    });
    render(<Harness />);
    fireEvent.click(await screen.findByRole('button', { name: 'Demander la mise en ligne' }));
    expect(
      await screen.findByText('Demande envoyée. Nous vous préviendrons de la décision.'),
    ).toBeTruthy();
    expect(await screen.findByText('En cours de validation')).toBeTruthy();
  });

  it('202 that comes back refused (decided that very moment): no « Demande envoyée »', async () => {
    const refusedNow = { state: 'refused', wentLive: false, refusal: { code: 'photos', final: false } };
    serve({ p1: profile('p1', 'Beauté Divine', 'draft', null) }, {
      publish: () => new Response(JSON.stringify({ validation: refusedNow }), { status: 202 }),
    });
    render(<Harness />);
    fireEvent.click(await screen.findByRole('button', { name: 'Demander la mise en ligne' }));
    expect(await screen.findByText('Mise en ligne refusée')).toBeTruthy();
    expect(screen.queryByText(/Demande envoyée/)).toBeNull();
  });

  it('200 (the old server): today’s « 🎉 » and the card goes', async () => {
    const salons = { p1: profile('p1', 'Beauté Divine', 'draft') };
    serve(salons, {
      publish: () => {
        // The old server's publish goes live at once.
        salons.p1 = profile('p1', 'Beauté Divine', 'active');
        return new Response(JSON.stringify({ id: 'p1', status: 'active' }), { status: 200 });
      },
    });
    render(<Harness />);
    fireEvent.click(await screen.findByRole('button', { name: 'Mettre en ligne' }));
    expect(
      await screen.findByText('🎉 Votre salon est en ligne ! Il apparaît maintenant dans les recherches.'),
    ).toBeTruthy();
    expect(screen.queryByText(/Demande envoyée/)).toBeNull();
    await waitFor(() => expect(screen.queryByRole('button', { name: 'Mettre en ligne' })).toBeNull());
  });

  it('409 validation_refused_final: the page re-reads and shows the final refusal', async () => {
    let refusedFinal = false;
    serve({ p1: profile('p1', 'Beauté Divine', 'draft', null) }, {
      me: () =>
        new Response(
          JSON.stringify(
            profile('p1', 'Beauté Divine', 'draft', refusedFinal
              ? { state: 'refused', wentLive: false, refusal: { code: 'test_salon', final: true } }
              : { state: 'refused', wentLive: false, refusal: { code: 'photos', final: false } }),
          ),
          { status: 200 },
        ),
      publish: () => {
        refusedFinal = true;
        return new Response(JSON.stringify({ error: 'validation_refused_final' }), { status: 409 });
      },
    });
    render(<Harness />);
    fireEvent.click(await screen.findByRole('button', { name: 'Renvoyer pour validation' }));
    expect(
      await screen.findByText('Ce salon est un salon de test : il ne sera pas mis en ligne.'),
    ).toBeTruthy();
    expect(screen.queryByRole('button', { name: 'Renvoyer pour validation' })).toBeNull();
  });
});

describe('« Aujourd’hui » — a decision’s push re-reads the state (§4.6)', () => {
  let sw: EventTarget;
  beforeEach(() => {
    sw = new EventTarget();
    Object.defineProperty(navigator, 'serviceWorker', { value: sw, configurable: true });
  });
  afterEach(() => {
    delete (navigator as { serviceWorker?: unknown }).serviceWorker;
  });
  const post = (data: unknown) =>
    act(() => {
      sw.dispatchEvent(new MessageEvent('message', { data }));
    });

  it('salon.validation.approved → /me again, quietly; the card goes when live', async () => {
    let live = false;
    const { count } = serve({ p1: profile('p1', 'Beauté Divine', 'draft', PENDING) }, {
      me: () =>
        new Response(
          JSON.stringify(
            live
              ? profile('p1', 'Beauté Divine', 'active', { state: 'approved', wentLive: true })
              : profile('p1', 'Beauté Divine', 'draft', PENDING),
          ),
          { status: 200 },
        ),
    });
    render(<Harness />);
    await screen.findByText('En cours de validation');
    const before = count('GET /api/pro/me');
    live = true;
    await post({ type: 'myweli-pro-push', event: 'salon.validation.approved' });
    await waitFor(() => expect(count('GET /api/pro/me')).toBe(before + 1));
    await waitFor(() => expect(screen.queryByText('En cours de validation')).toBeNull());
    // Quietly: the day stays on screen, no skeleton.
    expect(screen.getByRole('heading', { level: 1, name: 'Aujourd’hui' })).toBeTruthy();
  });

  it('a booking’s push, or an old worker’s bare message, re-reads nothing here', async () => {
    const { count } = serve({ p1: profile('p1', 'Beauté Divine', 'draft', PENDING) });
    render(<Harness />);
    await screen.findByText('En cours de validation');
    await waitFor(() => expect(count('GET /api/pro/salons')).toBeGreaterThanOrEqual(2));
    const me = count('GET /api/pro/me');
    await post({ type: 'myweli-pro-push', event: 'new_booking' });
    await post({ type: 'myweli-pro-push' });
    await post({ type: 'other', event: 'salon.validation.approved' });
    await new Promise((r) => setTimeout(r, 30));
    expect(count('GET /api/pro/me')).toBe(me);
  });
});

describe('« Aujourd’hui » — `/pro?salon=` switches once (§4.5)', () => {
  const two = () => ({
    p1: profile('p1', 'Beauté Divine', 'active', { state: 'approved', wentLive: true }),
    p3: profile('p3', 'Institut Belle Vue', 'draft', PENDING),
  });
  const selects = (calls: string[]) => calls.filter((c) => c === 'POST /api/pro/salons/select').length;

  it('another salon of the account → switched, its day shown, the address dropped', async () => {
    const { calls } = serve(two());
    render(<Harness salon="p3" />);
    expect(await screen.findByText('Institut Belle Vue')).toBeTruthy();
    expect(await screen.findByText('En cours de validation')).toBeTruthy();
    expect(selects(calls)).toBe(1);
    await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro', { scroll: false }));
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('already on it → no switch; the address is dropped', async () => {
    const { calls } = serve(two(), { selected: 'p3' });
    render(<Harness salon="p3" />);
    expect(await screen.findByText('En cours de validation')).toBeTruthy();
    await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro', { scroll: false }));
    expect(selects(calls)).toBe(0);
  });

  it('refused → the current salon’s day, saying why — once', async () => {
    const { calls } = serve(two(), {
      select: () => new Response(JSON.stringify({ error: 'forbidden' }), { status: 403 }),
    });
    render(<Harness salon="p3" />);
    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Changement impossible — votre accès à ce salon a peut-être été retiré.',
    );
    expect(screen.getByText('Beauté Divine')).toBeTruthy();
    expect(selects(calls)).toBe(1);
    await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro', { scroll: false }));
  });

  it('no answer → « Pas de connexion. Réessayez. » over the current salon’s day', async () => {
    serve(two(), {
      select: () => {
        throw new TypeError('Failed to fetch');
      },
    });
    render(<Harness salon="p3" />);
    expect(await screen.findByRole('alert')).toHaveTextContent('Pas de connexion. Réessayez.');
    expect(screen.getByText('Beauté Divine')).toBeTruthy();
  });

  it('a server that answers the switch but keeps the old salon → asked ONCE, then why', async () => {
    const salons = two();
    let asked = 0;
    const { calls } = serve(salons, {
      // The select says yes; /me stays on p1 (the selection did not stick).
      // A SECOND ask is refused, so a page without the guard fails this test
      // (two selects) instead of switching for ever.
      select: () =>
        ++asked === 1
          ? new Response(JSON.stringify(salons.p3), { status: 200 })
          : new Response(JSON.stringify({ error: 'forbidden' }), { status: 403 }),
    });
    render(<Harness salon="p3" />);
    expect(await screen.findByRole('alert')).toHaveTextContent('Changement impossible');
    await new Promise((r) => setTimeout(r, 50));
    expect(selects(calls)).toBe(1);
  });

  it('after landing, a switch from « Mes salons » is not pulled back to the notice’s salon', async () => {
    const { calls, state } = serve(two());
    render(<Harness salon="p3" />);
    await screen.findByText('En cours de validation');
    await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro', { scroll: false }));
    fireEvent.click(screen.getByRole('button', { name: 'test: passer à p1' }));
    await waitFor(() => expect(screen.queryByText('Institut Belle Vue')).toBeNull());
    expect(await screen.findByText('Beauté Divine')).toBeTruthy();
    await new Promise((r) => setTimeout(r, 50));
    expect(state.selected).toBe('p1');
    expect(selects(calls)).toBe(2);
  });

  it('anything but a salon id in the address is ignored', async () => {
    const { calls } = serve(two());
    render(<Harness salon="../admin" />);
    await screen.findByText('Beauté Divine');
    await new Promise((r) => setTimeout(r, 30));
    expect(selects(calls)).toBe(0);
    expect(replace).not.toHaveBeenCalled();
  });

  it('signed out → the login, carrying the salon', async () => {
    serve(two(), { me: () => new Response('{}', { status: 401 }) });
    render(<Harness salon="p3" />);
    await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro/connexion?salon=p3'));
  });
});
