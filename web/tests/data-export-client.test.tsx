import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
const routerMock = { replace };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
}));

import { DataExportClient } from '../components/account/DataExportClient';

/// « Mes données » (/mon-compte/donnees) refuses instead of offering a copy
/// with holes: a read that fails is never shown, downloaded or copied as an
/// empty section. Design: docs/design/consumer-export-completeness.md.

const TAIL =
  'Vos données ne sont proposées que complètes : vérifiez votre connexion et réessayez.';
const APPOINTMENTS_FAILED = `Impossible de charger vos rendez-vous. ${TAIL}`;
const FAVORITES_FAILED = `Impossible de charger vos favoris. ${TAIL}`;
const BOTH_FAILED = `Impossible de charger vos rendez-vous et vos favoris. ${TAIL}`;
const PROFILE_FAILED = `Impossible de charger votre profil. ${TAIL}`;
const COPY_FAILED =
  'La copie a échoué. Téléchargez le fichier avec « Télécharger (JSON) ».';

/// A read's answer: a status and a JSON body, a fetch that throws, or a 200
/// whose body breaks after the headers (a connection dropped mid-body).
type Answer = { status: number; body?: unknown } | 'throw' | 'broken-body';

const OK_ME: Answer = {
  status: 200,
  body: { id: 'u1', name: 'Awa', email: 'awa@example.com' },
};
const OK_APPOINTMENTS: Answer = {
  status: 200,
  body: {
    items: [
      {
        id: 'a1',
        providerId: 'p1',
        appointmentDate: '2026-11-01T09:00:00.000Z',
        status: 'confirmed',
        totalPrice: 15000,
      },
      {
        id: 'a2',
        providerId: 'p2',
        appointmentDate: '2026-09-01T09:00:00.000Z',
        status: 'completed',
        totalPrice: 8000,
      },
    ],
  },
};
const OK_FAVORITES: Answer = {
  status: 200,
  body: {
    favorites: [
      { id: 'p1', name: 'Beauté Divine' },
      { id: 'p9', name: 'Salon Fermé', status: 'suspended' },
    ],
  },
};

function brokenBody(): Response {
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(new TextEncoder().encode('{"items":[{"id":"a1"'));
      controller.error(new TypeError('network error'));
    },
  });
  return new Response(stream, { status: 200 });
}

/// The three reads the page makes, each answered on its own.
function reads(
  opts: { me?: Answer; appointments?: Answer; favorites?: Answer } = {},
) {
  const urls: string[] = [];
  const fetchMock = vi.fn(async (url: string) => {
    urls.push(url);
    let answer: Answer;
    if (url === '/api/me') answer = opts.me ?? OK_ME;
    else if (url === '/api/appointments') {
      answer = opts.appointments ?? OK_APPOINTMENTS;
    } else if (url === '/api/me/favorites') {
      answer = opts.favorites ?? OK_FAVORITES;
    } else answer = { status: 404, body: {} };
    if (answer === 'throw') throw new TypeError('Failed to fetch');
    if (answer === 'broken-body') return brokenBody();
    return new Response(
      answer.body === undefined ? null : JSON.stringify(answer.body),
      { status: answer.status },
    );
  });
  vi.stubGlobal('fetch', fetchMock);
  return urls;
}

/// What a download would hand the browser, and what a copy would write.
function watchOutputs(opts: { clipboardRejects?: boolean } = {}) {
  const blobs: Blob[] = [];
  const createObjectURL = vi.fn((b: Blob) => {
    blobs.push(b);
    return 'blob:export';
  });
  const revokeObjectURL = vi.fn();
  Object.assign(URL, { createObjectURL, revokeObjectURL });
  const anchorClick = vi
    .spyOn(HTMLAnchorElement.prototype, 'click')
    .mockImplementation(() => {});
  const writeText = vi.fn(async (_text: string) => {
    if (opts.clipboardRejects) {
      throw new DOMException('denied', 'NotAllowedError');
    }
  });
  Object.defineProperty(navigator, 'clipboard', {
    value: { writeText },
    configurable: true,
  });
  return { blobs, createObjectURL, anchorClick, writeText };
}

function blobText(b: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result));
    r.onerror = () => reject(r.error);
    r.readAsText(b);
  });
}

/// The refusal is the page's error state: the message, a retry, and nothing
/// to take away.
async function expectRefusal(message: string) {
  expect((await screen.findByRole('alert')).textContent).toBe(message);
  expect(screen.getByRole('heading', { level: 1 }).textContent).toBe(
    'Mes données',
  );
  expect(screen.getByRole('button', { name: 'Réessayer' })).toBeTruthy();
  expect(screen.queryByRole('button', { name: 'Télécharger (JSON)' })).toBeNull();
  expect(screen.queryByRole('button', { name: 'Copier' })).toBeNull();
  expect(screen.queryByText('Chargement…')).toBeNull();
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  replace.mockReset();
  // jsdom has neither; the stubs must not leak into the next test.
  delete (URL as unknown as Record<string, unknown>).createObjectURL;
  delete (URL as unknown as Record<string, unknown>).revokeObjectURL;
  delete (navigator as unknown as Record<string, unknown>).clipboard;
});

describe('DataExportClient — a failed read is refused, never an empty section', () => {
  it('appointments 500 → the refusal names « vos rendez-vous », nothing to download or copy', async () => {
    reads({ appointments: { status: 500, body: {} } });
    const out = watchOutputs();
    render(<DataExportClient />);

    await expectRefusal(APPOINTMENTS_FAILED);
    expect(out.createObjectURL).not.toHaveBeenCalled();
    expect(out.writeText).not.toHaveBeenCalled();
    expect(replace).not.toHaveBeenCalled();
  });

  it('favourites 503 → « vos favoris »', async () => {
    reads({ favorites: { status: 503 } });
    render(<DataExportClient />);

    await expectRefusal(FAVORITES_FAILED);
  });

  it('both fail → both named, in the file order', async () => {
    reads({
      favorites: { status: 500, body: {} },
      appointments: { status: 502, body: {} },
    });
    render(<DataExportClient />);

    await expectRefusal(BOTH_FAILED);
  });

  it('the appointments fetch THROWS → the refusal, not an endless spinner', async () => {
    reads({ appointments: 'throw' });
    render(<DataExportClient />);

    await expectRefusal(APPOINTMENTS_FAILED);
  });

  it('the profile fetch THROWS → « votre profil », not an endless spinner', async () => {
    reads({ me: 'throw' });
    render(<DataExportClient />);

    await expectRefusal(PROFILE_FAILED);
  });

  it('a 200 whose body breaks mid-stream is a failed read, not « 0 rendez-vous »', async () => {
    reads({ appointments: 'broken-body' });
    render(<DataExportClient />);

    await expectRefusal(APPOINTMENTS_FAILED);
  });

  it('the same for the favourites: a lost body is not « 0 favoris »', async () => {
    reads({ favorites: 'broken-body' });
    render(<DataExportClient />);

    await expectRefusal(FAVORITES_FAILED);
  });

  it('a 401 on the favourites read → sign-in, back here after', async () => {
    reads({ favorites: { status: 401, body: { error: 'session_expired' } } });
    const out = watchOutputs();
    render(<DataExportClient />);

    await waitFor(() =>
      expect(replace).toHaveBeenCalledWith(
        '/connexion?returnTo=/mon-compte/donnees',
      ),
    );
    expect(screen.queryByRole('button', { name: 'Télécharger (JSON)' })).toBeNull();
    expect(out.createObjectURL).not.toHaveBeenCalled();
  });

  it('« Réessayer » reads again; once every read answers, the copy is offered', async () => {
    reads({ appointments: { status: 500, body: {} } });
    render(<DataExportClient />);
    await expectRefusal(APPOINTMENTS_FAILED);

    const urls = reads();
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));

    expect(
      await screen.findByRole('button', { name: 'Télécharger (JSON)' }),
    ).toBeTruthy();
    expect(urls).toEqual(
      expect.arrayContaining(['/api/me', '/api/appointments', '/api/me/favorites']),
    );
    expect(screen.queryByRole('alert')).toBeNull();
  });
});

describe('DataExportClient — the clipboard', () => {
  it('a refused clipboard says so, points at the download, and never says « Copié ✓ »', async () => {
    reads();
    const out = watchOutputs({ clipboardRejects: true });
    render(<DataExportClient />);

    fireEvent.click(await screen.findByRole('button', { name: 'Copier' }));

    expect((await screen.findByRole('alert')).textContent).toBe(COPY_FAILED);
    expect(out.writeText).toHaveBeenCalledTimes(1);
    expect(screen.queryByText('Copié ✓')).toBeNull();
    // The way out still works: the download needs no clipboard.
    fireEvent.click(screen.getByRole('button', { name: 'Télécharger (JSON)' }));
    expect(out.createObjectURL).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('CONTROL — a clipboard that accepts says « Copié ✓ », no alert', async () => {
    reads();
    const out = watchOutputs();
    render(<DataExportClient />);

    fireEvent.click(await screen.findByRole('button', { name: 'Copier' }));

    expect(await screen.findByText('Copié ✓')).toBeTruthy();
    expect(screen.queryByRole('alert')).toBeNull();
    const doc = JSON.parse(out.writeText.mock.calls[0][0]);
    expect(doc.appointments).toHaveLength(2);
  });
});

describe('DataExportClient — CONTROL: every read answers', () => {
  it('the counts, and a file holding every appointment and favourite', async () => {
    reads();
    const out = watchOutputs();
    render(<DataExportClient />);

    fireEvent.click(
      await screen.findByRole('button', { name: 'Télécharger (JSON)' }),
    );

    expect(screen.getByText('Rendez-vous').nextSibling?.textContent).toBe('2');
    expect(screen.getByText('Favoris').nextSibling?.textContent).toBe('2');
    expect(out.createObjectURL).toHaveBeenCalledTimes(1);
    expect(out.anchorClick).toHaveBeenCalledTimes(1);
    const doc = JSON.parse(await blobText(out.blobs[0]));
    expect(doc.profile.id).toBe('u1');
    expect(doc.appointments.map((a: { id: string }) => a.id)).toEqual([
      'a1',
      'a2',
    ]);
    expect(doc.favorites).toEqual(['Beauté Divine', 'Salon Fermé']);
    expect(screen.queryByRole('alert')).toBeNull();
  });
});
