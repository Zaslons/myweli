import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/// docs/design/upload-resave-stale-pending.md — the 2026-11-13 production
/// refusals on « Médias ».
///
/// A new photo goes up under `pending/…`. The save MOVES it to its final
/// address, DELETES the pending object, and answers with what it stored. The
/// page kept its own list instead, so the next save re-sent the dead pending
/// address and was refused (400 `upload_not_found`) — every add after the
/// first in a page visit, while the thumbnail pointed at the deleted object.
///
/// Every mock server before this one answered `{}` and accepted anything, so
/// no test could see it. This one behaves like production did: it promotes a
/// pending address ONCE and refuses it if it comes back.

const routerMock = { replace: vi.fn(), push: vi.fn(), refresh: vi.fn() };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));
// MapLibre (Profil's LocationPicker) is browser-only — stub the dynamic import.
vi.mock('next/dynamic', () => ({ default: () => () => null }));

const CDN = 'https://cdn.myweli.com';
let uploads = 0;
let kycUploads = 0;
let logoUploads = 0;
vi.mock('../lib/pro/upload', async (importActual) => ({
  ...(await importActual<typeof import('../lib/pro/upload')>()),
  uploadGalleryImage: async () => ({
    ok: true,
    url: `${CDN}/pending/gallery/p1/n${++uploads}.jpg`,
  }),
  uploadLogoImage: async () => ({
    ok: true,
    url: `${CDN}/pending/logo/p1/l${++logoUploads}.png`,
  }),
  uploadKycDocument: async (file: File) => ({
    key: `pending/kyc/acc-1/d${++kycUploads}.jpg`,
    fileName: file.name,
  }),
}));

import { MediasClient } from '../components/pro/MediasClient';
import { ProfilClient } from '../components/pro/ProfilClient';
import { VerificationClient } from '../components/pro/VerificationClient';
import { resetLocalitiesClientCache } from '../lib/use-localities';
import { fixtureTree } from './localities.test';

const A = `${CDN}/gallery/p1/a.jpg`;
const PAIR0 = { before: `${CDN}/ba/p1/b0.jpg`, after: `${CDN}/ba/p1/a0.jpg` };

/// The server, as production behaved on 2026-11-13: a stored value passes; a
/// pending one is promoted ONCE (its object is deleted); anything else — a
/// pending value already promoted, above all — is refused.
function strictServer<T extends string>(initial: T[]) {
  let stored: string[] = [...initial];
  const consumed = new Set<string>();
  return {
    get stored() {
      return stored;
    },
    save(sent: string[]): { status: number; body: unknown; out?: string[] } {
      const out: string[] = [];
      const fresh: string[] = [];
      for (const u of sent) {
        if (stored.includes(u)) {
          out.push(u);
        } else if (u.includes('pending/') && !consumed.has(u)) {
          fresh.push(u);
          out.push(u.replace('pending/', ''));
        } else {
          return {
            status: 400,
            body: { error: u.includes('pending/') ? 'upload_not_found' : 'invalid_input' },
          };
        }
      }
      fresh.forEach((u) => consumed.add(u));
      stored = out;
      return { status: 200, body: null, out };
    },
  };
}

let gallery = strictServer([A]);
let pairUrls = strictServer<string>([PAIR0.before, PAIR0.after]);
let storedPairs: { before: string; after: string }[] = [PAIR0];
const galleryPuts: string[][] = [];
const pairPuts: { before: string; after: string }[][] = [];
let meCalls = 0;
/// When set, the gallery answers 200 with no list (a stripped answer).
let galleryAnswersEmpty = false;

beforeEach(() => {
  uploads = 0;
  kycUploads = 0;
  logoUploads = 0;
  gallery = strictServer([A]);
  pairUrls = strictServer<string>([PAIR0.before, PAIR0.after]);
  storedPairs = [PAIR0];
  galleryPuts.length = 0;
  pairPuts.length = 0;
  meCalls = 0;
  galleryAnswersEmpty = false;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      if (url === '/api/pro/me') {
        meCalls += 1;
        return json(200, {
          account: { id: 'acc-1', email: 'x@salon.test', businessType: 'other' },
          provider: {
            id: 'p1',
            name: 'Beauté Divine',
            imageUrls: gallery.stored,
            beforeAfters: storedPairs,
          },
        });
      }
      if (url === '/api/pro/medias/gallery') {
        const sent = JSON.parse(String(init?.body)).imageUrls as string[];
        galleryPuts.push(sent);
        const r = gallery.save(sent);
        if (r.status !== 200) return json(r.status, r.body);
        return galleryAnswersEmpty ? json(200, {}) : json(200, { imageUrls: r.out });
      }
      if (url === '/api/pro/medias/before-after') {
        const sent = JSON.parse(String(init?.body)).beforeAfters as {
          before: string;
          after: string;
        }[];
        pairPuts.push(sent);
        const r = pairUrls.save(sent.flatMap((p) => [p.before, p.after]));
        if (r.status !== 200) return json(r.status, r.body);
        storedPairs = sent.map((_, i) => ({ before: r.out![i * 2], after: r.out![i * 2 + 1] }));
        return json(200, { beforeAfters: storedPairs });
      }
      return json(404, {});
    }),
  );
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  resetLocalitiesClientCache();
});

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status });
}

const pick = (input: Element) =>
  fireEvent.change(input, {
    target: { files: [new File(['x'], 'p.jpg', { type: 'image/jpeg' })] },
  });
const shown = () => Array.from(document.querySelectorAll('img')).map((i) => i.getAttribute('src'));
const notBusy = () =>
  waitFor(() =>
    expect(document.querySelector('input[type=file]') as HTMLInputElement).toBeEnabled(),
  );

describe('Médias keeps what the server STORED — never its own pending addresses', () => {
  it('a SECOND add in the same visit is saved, and carries the first photo’s stored address', async () => {
    render(<MediasClient />);
    await screen.findByText('Couverture');
    pick(document.querySelector('input[type=file]')!);
    await waitFor(() => expect(galleryPuts).toHaveLength(1));
    await notBusy();

    pick(document.querySelector('input[type=file]')!);
    await waitFor(() => expect(galleryPuts).toHaveLength(2));
    expect(galleryPuts[1]).toEqual([
      A,
      `${CDN}/gallery/p1/n1.jpg`, // stored — not `${CDN}/pending/gallery/p1/n1.jpg`
      `${CDN}/pending/gallery/p1/n2.jpg`,
    ]);
    await waitFor(() =>
      expect(gallery.stored).toEqual([A, `${CDN}/gallery/p1/n1.jpg`, `${CDN}/gallery/p1/n2.jpg`]),
    );
    expect(screen.queryByText('Échec de l’envoi')).toBeNull();
    expect(meCalls, 'the answer carried the list: no second read').toBe(1);
  });

  it('the just-added thumbnail shows the stored address, not the deleted pending object', async () => {
    render(<MediasClient />);
    await screen.findByText('Couverture');
    pick(document.querySelector('input[type=file]')!);
    await waitFor(() => expect(shown()).toContain(`${CDN}/gallery/p1/n1.jpg`));
    expect(shown().some((s) => s?.includes('/pending/'))).toBe(false);
  });

  it('a move after an add sends the stored addresses (every write re-sends the list)', async () => {
    render(<MediasClient />);
    await screen.findByText('Couverture');
    pick(document.querySelector('input[type=file]')!);
    await waitFor(() => expect(galleryPuts).toHaveLength(1));
    await notBusy();
    fireEvent.click(screen.getAllByRole('button', { name: 'Descendre' })[0]);
    await waitFor(() => expect(galleryPuts).toHaveLength(2));
    expect(galleryPuts[1]).toEqual([`${CDN}/gallery/p1/n1.jpg`, A]);
    expect(screen.queryByText('Échec du déplacement')).toBeNull();
  });

  it('a 200 that carries no list reads the salon back instead of keeping the pending address', async () => {
    galleryAnswersEmpty = true;
    render(<MediasClient />);
    await screen.findByText('Couverture');
    expect(meCalls).toBe(1);
    pick(document.querySelector('input[type=file]')!);
    await waitFor(() => expect(meCalls).toBe(2));
    await notBusy();
    pick(document.querySelector('input[type=file]')!);
    await waitFor(() => expect(galleryPuts).toHaveLength(2));
    expect(galleryPuts[1]).toEqual([
      A,
      `${CDN}/gallery/p1/n1.jpg`,
      `${CDN}/pending/gallery/p1/n2.jpg`,
    ]);
  });

  it('Avant / Après: a second pair carries the first pair’s stored addresses', async () => {
    render(<MediasClient />);
    await screen.findByText('Couverture');
    fireEvent.click(screen.getByRole('button', { name: 'Avant / Après' }));

    async function addPair() {
      const inputs = document.querySelectorAll('input[type=file]');
      pick(inputs[0]);
      pick(inputs[1]);
      const add = screen.getByRole('button', { name: 'Ajouter la paire' });
      await waitFor(() => expect(add).toBeEnabled());
      fireEvent.click(add);
    }

    await addPair();
    await waitFor(() => expect(pairPuts).toHaveLength(1));
    await waitFor(() => expect(storedPairs).toHaveLength(2));
    await addPair();
    await waitFor(() => expect(pairPuts).toHaveLength(2));
    expect(pairPuts[1][1]).toEqual({
      before: `${CDN}/gallery/p1/n1.jpg`,
      after: `${CDN}/gallery/p1/n2.jpg`,
    });
    await waitFor(() => expect(storedPairs).toHaveLength(3));
    expect(screen.queryByText('Échec de l’enregistrement')).toBeNull();
    expect(meCalls, 'the answer carried the pairs: no second read').toBe(1);
  });
});

describe('Vérification keeps the documents the server STORED', () => {
  /// `answer`: the submit's answer carries the stored documents, or says
  /// nothing of them (the page must then read the status back).
  async function twoSubmits(answer: 'documents' | 'nothing') {
    const kyc = strictServer<string>([]);
    let docs: { type: string; fileName?: string; key: string }[] = [];
    const posts: { type: string; key: string }[][] = [];
    let statusReads = 0;
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string, init?: RequestInit) => {
        if (url === '/api/pro/me') {
          return json(200, {
            account: { id: 'acc-1', email: 'x@salon.test', businessType: 'other' },
            provider: { id: 'p1', name: 'Beauté Divine' },
          });
        }
        if (url === '/api/pro/kyc' && init?.method === 'POST') {
          const sent = JSON.parse(String(init.body)).documents as typeof docs;
          posts.push(sent);
          const r = kyc.save(sent.map((d) => d.key));
          if (r.status !== 200) return json(r.status, r.body);
          docs = sent.map((d, i) => ({ ...d, key: r.out![i] }));
          return json(200, answer === 'documents' ? { status: 'pending', documents: docs } : { status: 'pending' });
        }
        if (url === '/api/pro/kyc') {
          statusReads += 1;
          return json(200, { status: posts.length ? 'pending' : 'rejected', documents: docs });
        }
        return json(404, {});
      }),
    );

    render(<VerificationClient />);
    pick(await screen.findByLabelText('Pièce d’identité (CNI / passeport)'));
    pick(await screen.findByLabelText('Photo du visage'));
    // Re-queried each time: reading the status back redraws the page.
    const submit = () => screen.getByRole('button', { name: 'Soumettre pour vérification' });
    await waitFor(() => expect(submit()).toBeEnabled());
    fireEvent.click(submit());
    await waitFor(() => expect(posts).toHaveLength(1));
    await screen.findByText('Documents soumis pour vérification');

    // Replace the selfie, submit again — what the rejection banner invites.
    pick(await screen.findByLabelText('Photo du visage'));
    await waitFor(() => expect(submit()).toBeEnabled());
    fireEvent.click(submit());
    await waitFor(() => expect(posts).toHaveLength(2));
    expect(posts[1].find((d) => d.type === 'idCard')?.key).toBe('kyc/acc-1/d1.jpg');
    await waitFor(() =>
      expect(docs.map((d) => d.key).sort()).toEqual(['kyc/acc-1/d1.jpg', 'kyc/acc-1/d3.jpg']),
    );
    expect(screen.queryByText('L’envoi a échoué. Réessayez.')).toBeNull();
    // The answer's documents are used as they are: no second read when it has them.
    expect(statusReads).toBe(answer === 'documents' ? 1 : 3);
  }

  it('a second submit in the same visit carries the stored keys, and is accepted', () =>
    twoSubmits('documents'));

  it('an answer without the documents reads the status back — never keeps the pending keys', () =>
    twoSubmits('nothing'));
});

describe('Profil keeps the logo the server STORED', () => {
  /// `answer`: what the profile PATCH answers — the stored provider, or `{}`
  /// (an answer that says nothing, so the page must read the salon back).
  async function twoSaves(answer: 'provider' | 'nothing') {
    const logo = strictServer<string>([]);
    let provider = {
      id: 'p1',
      name: 'Beauté Divine',
      status: 'active',
      countryCode: 'CI',
      phoneNumber: '+2250700000000',
      whatsapp: '',
      category: 'salon',
      logoUrl: null as string | null,
    };
    const patches: Record<string, unknown>[] = [];
    let salonReads = 0;
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string, init?: RequestInit) => {
        if (url === '/api/pro/me') {
          salonReads += 1;
          return json(200, { account: { id: 'acc-1', verificationStatus: 'verified' }, provider });
        }
        if (url === '/api/localities') return json(200, fixtureTree);
        if (url === '/api/pro/profil') {
          const sent = JSON.parse(String(init?.body)).profile as Record<string, unknown>;
          patches.push(sent);
          const raw = sent.logoUrl as string;
          let stored: string | null = null;
          if (raw) {
            const r = logo.save([raw]);
            if (r.status !== 200) return json(r.status, r.body);
            stored = r.out![0];
          }
          provider = { ...provider, name: String(sent.name), logoUrl: stored };
          return json(200, answer === 'provider' ? provider : {});
        }
        return json(404, {});
      }),
    );

    render(<ProfilClient />);
    pick(await screen.findByLabelText('Logo du salon'));
    await waitFor(() => expect(shown()).toContain(`${CDN}/pending/logo/p1/l1.png`));
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));
    await waitFor(() => expect(patches).toHaveLength(1));
    await waitFor(() => expect(shown()).toContain(`${CDN}/logo/p1/l1.png`));

    fireEvent.change(screen.getByLabelText('Nom du salon'), { target: { value: 'Beauté Divine 2' } });
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));
    await waitFor(() => expect(patches).toHaveLength(2));
    expect(patches[1].logoUrl).toBe(`${CDN}/logo/p1/l1.png`);
    await waitFor(() => expect(provider.name).toBe('Beauté Divine 2'));
    expect(screen.queryByText('L’enregistrement a échoué. Réessayez.')).toBeNull();
    // The answer's logo is used as it is: no second read when it has one.
    expect(salonReads).toBe(answer === 'provider' ? 1 : 3);
  }

  it('a second save in the same visit (a name change) carries the stored logo, and is accepted', () =>
    twoSaves('provider'));

  it('an answer that says nothing reads the salon back — never keeps the pending logo', () =>
    twoSaves('nothing'));
});
