import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import type { NextRequest } from 'next/server';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
const routerMock = { replace };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
}));

import { DELETE } from '../app/api/pro/account/route';
import { CompteDangerSection } from '../components/pro/CompteDangerSection';
import type { ProProfile } from '../lib/api/pro';
import { DEMO_ACCOUNT_LOCKED_MESSAGE } from '../lib/pro/team';

/// « Compte » on /pro/profil when the server REFUSES the deletion — the
/// shared store-review demo account cannot delete itself (403
/// `demo_account_locked`). The demo credential signs in on the web too, so
/// the dashboard has to say the same sentence as the app, and leave the
/// session alone. Design: docs/design/demo-account-deletion-lock.md §7.2.

const FUTURE_BOOKINGS =
  'Terminez ou annulez vos rendez-vous à venir avant de supprimer votre compte.';
const GENERIC = 'La suppression a échoué. Réessayez.';

const profile = {
  account: { id: 'acc-1', email: 'owner@salon.test' },
  provider: { id: 'p1', name: 'Maison Nala', status: 'draft' },
  membership: { role: 'owner', capabilities: ['profile.manage'] },
} as unknown as ProProfile;

/// The BFF's answer to `DELETE /api/pro/account`.
function serverAnswers(status: number, body?: unknown) {
  const calls: { url: string; method: string }[] = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      calls.push({ url, method: init?.method ?? 'GET' });
      return new Response(body === undefined ? null : JSON.stringify(body), {
        status,
      });
    }),
  );
  return calls;
}

/// The user's three gestures: the entry, the word, the button.
async function confirmDeletion() {
  fireEvent.click(screen.getByText('Supprimer mon compte'));
  fireEvent.change(screen.getByLabelText('Confirmation de suppression'), {
    target: { value: 'SUPPRIMER' },
  });
  fireEvent.click(screen.getByText('Supprimer définitivement'));
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
});

describe('CompteDangerSection — a refused deletion', () => {
  it('the entry is offered, as a real button, before anything is sent', () => {
    const calls = serverAnswers(204);
    render(<CompteDangerSection profile={profile} />);

    const entry = screen.getByRole('button', { name: 'Supprimer mon compte' });
    expect((entry as HTMLButtonElement).disabled).toBe(false);
    expect(calls).toEqual([]);
  });

  it('demo_account_locked → the demo sentence, announced; the page and the session stay', async () => {
    const calls = serverAnswers(403, { error: 'demo_account_locked' });
    render(<CompteDangerSection profile={profile} />);

    await confirmDeletion();

    const alert = await screen.findByRole('alert');
    expect(alert.textContent).toBe(DEMO_ACCOUNT_LOCKED_MESSAGE);
    expect(calls).toEqual([{ url: '/api/pro/account', method: 'DELETE' }]);
    // Not signed out: no navigation, and the confirmation is still open —
    // the user can read the refusal next to the field they just filled.
    expect(replace).not.toHaveBeenCalled();
    expect(screen.getByLabelText('Confirmation de suppression')).toBeTruthy();
    expect(screen.queryByText(FUTURE_BOOKINGS)).toBeNull();
    expect(screen.queryByText(GENERIC)).toBeNull();
  });

  it('the member variant (no export) says the same sentence', async () => {
    serverAnswers(403, { error: 'demo_account_locked' });
    render(<CompteDangerSection profile={profile} exportEnabled={false} />);

    await confirmDeletion();

    expect((await screen.findByRole('alert')).textContent).toBe(
      DEMO_ACCOUNT_LOCKED_MESSAGE,
    );
    expect(replace).not.toHaveBeenCalled();
  });

  it('CONTROL — future_bookings keeps its own sentence', async () => {
    serverAnswers(409, { error: 'future_bookings' });
    render(<CompteDangerSection profile={profile} />);

    await confirmDeletion();

    expect((await screen.findByRole('alert')).textContent).toBe(
      FUTURE_BOOKINGS,
    );
    expect(replace).not.toHaveBeenCalled();
  });

  it.each([
    ['403 forbidden', 403, { error: 'forbidden' }],
    ['500 with no code', 500, {}],
    ['403 with no body', 403, undefined],
  ])('CONTROL — %s is the generic failure, never the demo sentence', async (_label, status, body) => {
    serverAnswers(status as number, body);
    render(<CompteDangerSection profile={profile} />);

    await confirmDeletion();

    expect((await screen.findByRole('alert')).textContent).toBe(GENERIC);
    expect(replace).not.toHaveBeenCalled();
  });

  it('CONTROL — a deletion the server accepts leaves for /pro/connexion', async () => {
    // Without this, « the page stays » above would be true of a section
    // that never navigates.
    serverAnswers(204);
    render(<CompteDangerSection profile={profile} />);

    await confirmDeletion();

    await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro/connexion'));
    expect(screen.queryByRole('alert')).toBeNull();
  });
});

/// The data export (docs/design/web-pro-export-completeness.md). The file is
/// the salon's copy of its own data, and a salon owner reads `[]` as « no
/// clients », not « the read failed ». So a section that could not be
/// loaded makes NO file: the row says which data is missing, and the
/// buttons are the retry (§3–§4). The client file is walked page by page,
/// and a walk that does not add up is refused too (§5).

const CLIENTS_FAILED =
  "Export interrompu : impossible de charger le fichier clients. Aucun fichier n'a été créé. Réessayez.";
const APPOINTMENTS_FAILED =
  "Export interrompu : impossible de charger les rendez-vous. Aucun fichier n'a été créé. Réessayez.";
const EARNINGS_FAILED =
  "Export interrompu : impossible de charger les revenus. Aucun fichier n'a été créé. Réessayez.";
const ALL_FAILED =
  "Export interrompu : impossible de charger les rendez-vous, le fichier clients et les revenus. Aucun fichier n'a été créé. Réessayez.";
const COPY_FAILED =
  'La copie a échoué. Téléchargez le fichier avec « Exporter (JSON) ».';

type Answer = { status: number; body?: unknown } | 'throw';

function client(i: number) {
  return {
    id: `sc${i}`,
    displayName: `Cliente ${i}`,
    phone: null,
    tags: [],
    linked: false,
    createdAt: '2026-01-01T00:00:00.000Z',
    visits: 1,
    noShows: 0,
  };
}

/// One page of `total` clients, `size` per page, ids numbered from 1.
function clientPage(page: number, total: number, size = 50) {
  const from = (page - 1) * size;
  const items = [];
  for (let i = from + 1; i <= Math.min(from + size, total); i++) {
    items.push(client(i));
  }
  return { status: 200, body: { items, page, pageSize: size, total } };
}

const OK_APPOINTMENTS: Answer = {
  status: 200,
  body: {
    items: [
      {
        id: 'b1',
        appointmentDate: '2026-10-01T09:00:00.000Z',
        status: 'completed',
        totalPrice: 15000,
      },
    ],
  },
};
const OK_EARNINGS: Answer = {
  status: 200,
  body: {
    totalEarnings: 15000,
    transactions: [
      {
        id: 't1',
        appointmentId: 'b1',
        amount: 15000,
        date: '2026-10-01T09:00:00.000Z',
        status: 'completed',
      },
    ],
  },
};

/// The three reads the export makes, each answered on its own.
function exportReads(
  opts: {
    appointments?: Answer;
    clients?: Answer | ((page: number) => Answer);
    earnings?: Answer;
  } = {},
) {
  const urls: string[] = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      urls.push(url);
      const u = new URL(url, 'http://web.test');
      let answer: Answer;
      if (u.pathname === '/api/pro/appointments') {
        answer = opts.appointments ?? OK_APPOINTMENTS;
      } else if (u.pathname === '/api/pro/clients') {
        const page = Number(u.searchParams.get('page') ?? '1');
        const c = opts.clients ?? ((p: number) => clientPage(p, 1));
        answer = typeof c === 'function' ? c(page) : c;
      } else if (u.pathname === '/api/pro/earnings') {
        answer = opts.earnings ?? OK_EARNINGS;
      } else {
        answer = { status: 404, body: {} };
      }
      if (answer === 'throw') throw new TypeError('Failed to fetch');
      return new Response(
        answer.body === undefined ? null : JSON.stringify(answer.body),
        { status: answer.status },
      );
    }),
  );
  return urls;
}

/// What a download would hand the browser, and what a copy would write.
function watchOutputs(opts: { clipboardRejects?: boolean } = {}) {
  const createObjectURL = vi.fn(() => 'blob:export');
  const revokeObjectURL = vi.fn();
  Object.assign(URL, { createObjectURL, revokeObjectURL });
  const anchorClick = vi
    .spyOn(HTMLAnchorElement.prototype, 'click')
    .mockImplementation(() => {});
  const writeText = vi.fn(async (_text: string) => {
    if (opts.clipboardRejects) throw new DOMException('denied', 'NotAllowedError');
  });
  Object.defineProperty(navigator, 'clipboard', {
    value: { writeText },
    configurable: true,
  });
  return { createObjectURL, anchorClick, writeText };
}

function exportButton() {
  return screen.getByRole('button', { name: /Exporter \(JSON\)|Préparation…/ });
}

describe('CompteDangerSection — the export refuses instead of shipping holes', () => {
  afterEach(() => {
    vi.restoreAllMocks();
    // jsdom has neither; the stubs must not leak into the next file.
    delete (URL as unknown as Record<string, unknown>).createObjectURL;
    delete (URL as unknown as Record<string, unknown>).revokeObjectURL;
    delete (navigator as unknown as Record<string, unknown>).clipboard;
  });

  it('a clients read that fails makes no file, says which data, and the buttons come back', async () => {
    exportReads({ clients: { status: 500, body: {} } });
    const out = watchOutputs();
    render(<CompteDangerSection profile={profile} />);

    fireEvent.click(exportButton());

    expect((await screen.findByRole('alert')).textContent).toBe(CLIENTS_FAILED);
    expect(out.createObjectURL).not.toHaveBeenCalled();
    expect(out.anchorClick).not.toHaveBeenCalled();
    expect(exportButton().textContent).toBe('Exporter (JSON)');
    expect((exportButton() as HTMLButtonElement).disabled).toBe(false);
    expect(
      (screen.getByRole('button', { name: 'Copier' }) as HTMLButtonElement)
        .disabled,
    ).toBe(false);
  });

  it('a read that THROWS is refused too — the button is not left on « Préparation… »', async () => {
    exportReads({ appointments: 'throw' });
    const out = watchOutputs();
    render(<CompteDangerSection profile={profile} />);

    fireEvent.click(exportButton());

    expect((await screen.findByRole('alert')).textContent).toBe(
      APPOINTMENTS_FAILED,
    );
    expect(out.createObjectURL).not.toHaveBeenCalled();
    expect(exportButton().textContent).toBe('Exporter (JSON)');
    expect((exportButton() as HTMLButtonElement).disabled).toBe(false);
  });

  it('an appointments read answering 500 is refused — its empty list is not « no bookings »', async () => {
    exportReads({ appointments: { status: 500, body: {} } });
    const out = watchOutputs();
    render(<CompteDangerSection profile={profile} />);

    fireEvent.click(exportButton());

    expect((await screen.findByRole('alert')).textContent).toBe(
      APPOINTMENTS_FAILED,
    );
    expect(out.createObjectURL).not.toHaveBeenCalled();
  });

  it('copy: a failed earnings read writes nothing to the clipboard', async () => {
    exportReads({ earnings: { status: 503 } });
    const out = watchOutputs();
    render(<CompteDangerSection profile={profile} />);

    fireEvent.click(screen.getByRole('button', { name: 'Copier' }));

    expect((await screen.findByRole('alert')).textContent).toBe(EARNINGS_FAILED);
    expect(out.writeText).not.toHaveBeenCalled();
    expect(screen.queryByText('Copié ✓')).toBeNull();
  });

  it('two failed reads are both named, in the section order', async () => {
    exportReads({ earnings: { status: 500 }, clients: { status: 502 } });
    watchOutputs();
    render(<CompteDangerSection profile={profile} />);

    fireEvent.click(exportButton());

    expect((await screen.findByRole('alert')).textContent).toBe(
      "Export interrompu : impossible de charger le fichier clients et les revenus. Aucun fichier n'a été créé. Réessayez.",
    );
  });

  it('a session that ended (401) goes to sign-in, with no file and no alert', async () => {
    exportReads({ clients: { status: 401, body: { error: 'unauthorized' } } });
    const out = watchOutputs();
    render(<CompteDangerSection profile={profile} />);

    fireEvent.click(exportButton());

    await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro/connexion'));
    expect(out.createObjectURL).not.toHaveBeenCalled();
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('the retry works: the alert clears and the file is made once the reads answer', async () => {
    let clientsUp = false;
    exportReads({
      clients: (p) => (clientsUp ? clientPage(p, 1) : { status: 500, body: {} }),
    });
    const out = watchOutputs();
    render(<CompteDangerSection profile={profile} />);

    fireEvent.click(exportButton());
    expect((await screen.findByRole('alert')).textContent).toBe(CLIENTS_FAILED);

    clientsUp = true;
    fireEvent.click(exportButton());

    await waitFor(() => expect(out.createObjectURL).toHaveBeenCalledTimes(1));
    expect(out.anchorClick).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('the client file is walked to its end: 120 clients over three pages, all exported', async () => {
    const urls = exportReads({ clients: (p) => clientPage(p, 120) });
    const out = watchOutputs();
    render(<CompteDangerSection profile={profile} />);

    fireEvent.click(screen.getByRole('button', { name: 'Copier' }));

    await waitFor(() => expect(out.writeText).toHaveBeenCalledTimes(1));
    const doc = JSON.parse(out.writeText.mock.calls[0][0]);
    expect(doc.clients).toHaveLength(120);
    expect(new Set(doc.clients.map((c: { name: string }) => c.name)).size).toBe(120);
    const pages = urls
      .filter((u) => u.startsWith('/api/pro/clients'))
      .map((u) => new URL(u, 'http://web.test').searchParams);
    expect(pages.map((q) => [q.get('page'), q.get('pageSize')])).toEqual([
      ['1', '50'],
      ['2', '50'],
      ['3', '50'],
    ]);
  });

  it('a base that changed during the walk (total moved) is refused, not half-exported', async () => {
    exportReads({
      clients: (p) => (p === 1 ? clientPage(1, 60) : clientPage(2, 61)),
    });
    const out = watchOutputs();
    render(<CompteDangerSection profile={profile} />);

    fireEvent.click(screen.getByRole('button', { name: 'Copier' }));

    expect((await screen.findByRole('alert')).textContent).toBe(CLIENTS_FAILED);
    expect(out.writeText).not.toHaveBeenCalled();
  });

  it('a walk that repeats a client (and so misses one) is refused', async () => {
    exportReads({
      clients: (p) => {
        const page = clientPage(p, 60);
        // Page 2 starts with page 1's last row: a row slid across the
        // boundary, so another one slid out of reach.
        if (p === 2) {
          (page.body.items as unknown[])[0] = client(50);
        }
        return page;
      },
    });
    const out = watchOutputs();
    render(<CompteDangerSection profile={profile} />);

    fireEvent.click(screen.getByRole('button', { name: 'Copier' }));

    expect((await screen.findByRole('alert')).textContent).toBe(CLIENTS_FAILED);
    expect(out.writeText).not.toHaveBeenCalled();
  });

  it('a clipboard the browser refuses says so, and points at the download', async () => {
    exportReads();
    watchOutputs({ clipboardRejects: true });
    render(<CompteDangerSection profile={profile} />);

    fireEvent.click(screen.getByRole('button', { name: 'Copier' }));

    expect((await screen.findByRole('alert')).textContent).toBe(COPY_FAILED);
    expect(screen.queryByText('Copié ✓')).toBeNull();
  });

  // docs/design/export-unreadable-200.md §4: a 200 without its list lost it
  // on the way (the server always sends it). Before, an appointments `{}`
  // shipped `"appointments": []` with no alert, and an earnings `{}` broke the
  // assembly with nothing said — the button just came back.
  it.each([
    ['appointments', APPOINTMENTS_FAILED],
    ['earnings', EARNINGS_FAILED],
  ] as const)('the %s answering 200 `{}` is refused: no file, the message', async (read, message) => {
    exportReads({ [read]: { status: 200, body: {} } });
    const out = watchOutputs();
    render(<CompteDangerSection profile={profile} />);

    fireEvent.click(exportButton());

    expect((await screen.findByRole('alert')).textContent).toBe(message);
    expect(out.createObjectURL).not.toHaveBeenCalled();
    expect(out.anchorClick).not.toHaveBeenCalled();
    expect(exportButton().textContent).toBe('Exporter (JSON)');
  });

  it('CONTROL — the clients answering 200 `{}` is refused (the walk already needs its `pageSize`)', async () => {
    exportReads({ clients: { status: 200, body: {} } });
    const out = watchOutputs();
    render(<CompteDangerSection profile={profile} />);

    fireEvent.click(exportButton());

    expect((await screen.findByRole('alert')).textContent).toBe(CLIENTS_FAILED);
    expect(out.createObjectURL).not.toHaveBeenCalled();
  });

  // §2.3: whatever still breaks while the file is assembled is a refusal
  // with the export's message — it cannot say which data was wrong, so it
  // names them all — never a silent no-file.
  it('a file that cannot be assembled is refused with the message, and the buttons come back', async () => {
    exportReads();
    const out = watchOutputs();
    const broken = {
      ...profile,
      provider: { ...profile.provider, services: 'x' },
    } as unknown as ProProfile;
    render(<CompteDangerSection profile={broken} />);

    fireEvent.click(exportButton());

    expect((await screen.findByRole('alert')).textContent).toBe(ALL_FAILED);
    expect(out.createObjectURL).not.toHaveBeenCalled();
    expect(out.anchorClick).not.toHaveBeenCalled();
    expect(exportButton().textContent).toBe('Exporter (JSON)');
    expect((exportButton() as HTMLButtonElement).disabled).toBe(false);
  });

  it('the same through « Copier »: a booking the file cannot hold writes nothing', async () => {
    exportReads({ appointments: { status: 200, body: { items: [null] } } });
    const out = watchOutputs();
    render(<CompteDangerSection profile={profile} />);

    fireEvent.click(screen.getByRole('button', { name: 'Copier' }));

    expect((await screen.findByRole('alert')).textContent).toBe(ALL_FAILED);
    expect(out.writeText).not.toHaveBeenCalled();
    expect(screen.queryByText('Copié ✓')).toBeNull();
  });

  it('CONTROL — every read answers: one file, every section filled, no alert', async () => {
    exportReads();
    const out = watchOutputs();
    render(<CompteDangerSection profile={profile} />);

    fireEvent.click(screen.getByRole('button', { name: 'Copier' }));

    await waitFor(() => expect(out.writeText).toHaveBeenCalledTimes(1));
    const doc = JSON.parse(out.writeText.mock.calls[0][0]);
    expect(doc.appointments).toHaveLength(1);
    expect(doc.clients).toHaveLength(1);
    expect(doc.earnings).toEqual({ totalEarnings: 15000, transactions: 1 });
    expect(screen.queryByRole('alert')).toBeNull();

    fireEvent.click(exportButton());
    await waitFor(() => expect(out.createObjectURL).toHaveBeenCalledTimes(1));
    expect(out.anchorClick).toHaveBeenCalledTimes(1);
  });
});

describe('DELETE /api/pro/account (the BFF)', () => {
  function proRequest(): NextRequest {
    const cookies: Record<string, string> = {
      myweli_pro_at: 'access',
      myweli_pro_rt: 'refresh',
    };
    return {
      cookies: {
        get: (k: string) => (cookies[k] ? { value: cookies[k] } : undefined),
      },
    } as unknown as NextRequest;
  }

  function backendAnswers(status: number, body?: unknown) {
    const calls: { url: string; method?: string; auth?: string }[] = [];
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string, init?: RequestInit) => {
        calls.push({
          url: String(url),
          method: init?.method,
          auth: (init?.headers as Record<string, string> | undefined)
            ?.authorization,
        });
        return new Response(
          body === undefined ? null : JSON.stringify(body),
          { status },
        );
      }),
    );
    return calls;
  }

  it('passes the demo refusal through as it came, and leaves the session cookies alone', async () => {
    const calls = backendAnswers(403, { error: 'demo_account_locked' });

    const res = await DELETE(proRequest());

    expect(res.status).toBe(403);
    expect(await res.json()).toEqual({ error: 'demo_account_locked' });
    expect(res.headers.get('set-cookie')).toBeNull();
    expect(calls).toHaveLength(1);
    expect(calls[0].url).toMatch(/\/me\/provider$/);
    expect(calls[0].method).toBe('DELETE');
    expect(calls[0].auth).toBe('Bearer access');
  });

  it('CONTROL — on 204 the pro session cookies are cleared', async () => {
    backendAnswers(204);

    const res = await DELETE(proRequest());

    expect(res.status).toBe(204);
    const cleared = res.headers.get('set-cookie') ?? '';
    expect(cleared).toContain('myweli_pro_at=;');
    expect(cleared).toContain('myweli_pro_rt=;');
  });
});
