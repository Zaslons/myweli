import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/// docs/design/gallery-multi-select.md — « Médias » takes several photos in
/// one pick: one after another (never two prepared at once — a low-end phone's
/// memory), each saved as it lands and kept at the address the server STORED,
/// capped at the room left under 20, and one summary at the end.

const routerMock = { replace: vi.fn(), push: vi.fn(), refresh: vi.fn() };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));

const CDN = 'https://cdn.myweli.com';

/// The fake upload: records the order, how many run at once, and can be held
/// open or told to fail for a file name.
const uploadCalls: string[] = [];
let inFlight = 0;
let maxInFlight = 0;
let failFor: Record<string, 'unreadable' | 'too_large' | 'blocked' | 'failed'> = {};
let hold: { name: string; release: () => void } | null = null;
let holdName: string | null = null;

vi.mock('../lib/pro/upload', async (importActual) => ({
  ...(await importActual<typeof import('../lib/pro/upload')>()),
  uploadGalleryImage: async (file: File, deps: { signal?: AbortSignal } = {}) => {
    uploadCalls.push(file.name);
    inFlight += 1;
    maxInFlight = Math.max(maxInFlight, inFlight);
    try {
      if (file.name === holdName) {
        await new Promise<void>((release) => {
          hold = { name: file.name, release };
        });
      } else {
        await new Promise((r) => setTimeout(r, 5));
      }
      if (deps.signal?.aborted) return { ok: false, reason: 'aborted' };
      const reason = failFor[file.name];
      if (reason) return { ok: false, reason };
      return { ok: true, url: `${CDN}/pending/gallery/p1/${file.name}` };
    } finally {
      inFlight -= 1;
    }
  },
}));

import { MediasClient } from '../components/pro/MediasClient';
import { batchSummary, fitInGallery, overCapMessage } from '../lib/pro/medias';

let stored: string[] = [];
const consumed = new Set<string>();
const puts: string[][] = [];
let refuseSave: number | null = null;

beforeEach(() => {
  uploadCalls.length = 0;
  inFlight = 0;
  maxInFlight = 0;
  failFor = {};
  hold = null;
  holdName = null;
  stored = [`${CDN}/gallery/p1/a.jpg`];
  consumed.clear();
  puts.length = 0;
  refuseSave = null;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      if (url === '/api/pro/me') {
        return json(200, {
          account: { id: 'acc-1' },
          provider: { id: 'p1', name: 'Beauté Divine', imageUrls: stored, beforeAfters: [] },
        });
      }
      if (url === '/api/pro/medias/gallery') {
        const sent = JSON.parse(String(init?.body)).imageUrls as string[];
        puts.push(sent);
        if (refuseSave === puts.length) return json(500, {});
        // As strict as production was before #784: a pending address is moved
        // ONCE; sent again it is refused.
        const out: string[] = [];
        for (const u of sent) {
          if (stored.includes(u)) out.push(u);
          else if (u.includes('/pending/') && !consumed.has(u)) out.push(u.replace('pending/', ''));
          else return json(400, { error: 'upload_not_found' });
        }
        sent.filter((u) => u.includes('/pending/')).forEach((u) => consumed.add(u));
        stored = out;
        return json(200, { imageUrls: out });
      }
      return json(404, {});
    }),
  );
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status });
}
const files = (...names: string[]) => names.map((n) => new File(['x'], n, { type: 'image/jpeg' }));
const input = () => document.querySelector('input[type=file]') as HTMLInputElement;
const pickAll = (...names: string[]) => fireEvent.change(input(), { target: { files: files(...names) } });
const shown = () => Array.from(document.querySelectorAll('img')).map((i) => i.getAttribute('src'));

async function openMedias() {
  render(<MediasClient />);
  await screen.findByText('Couverture');
}

describe('« Ajouter des photos » — several in one pick', () => {
  it('the picker takes several files, under the new label', async () => {
    await openMedias();
    expect(input()).toHaveAttribute('multiple');
    expect(screen.getByText('Ajouter des photos')).toBeInTheDocument();
  });

  it('three photos: one after another in the order picked, each saved with the stored addresses, one summary', async () => {
    await openMedias();
    pickAll('b.jpg', 'c.jpg', 'd.jpg');
    expect(await screen.findByText('3 photos ajoutées.')).toBeInTheDocument();
    expect(uploadCalls).toEqual(['b.jpg', 'c.jpg', 'd.jpg']);
    expect(maxInFlight, 'never two prepared at once').toBe(1);
    expect(puts).toEqual([
      [`${CDN}/gallery/p1/a.jpg`, `${CDN}/pending/gallery/p1/b.jpg`],
      [`${CDN}/gallery/p1/a.jpg`, `${CDN}/gallery/p1/b.jpg`, `${CDN}/pending/gallery/p1/c.jpg`],
      [
        `${CDN}/gallery/p1/a.jpg`,
        `${CDN}/gallery/p1/b.jpg`,
        `${CDN}/gallery/p1/c.jpg`,
        `${CDN}/pending/gallery/p1/d.jpg`,
      ],
    ]);
    expect(shown()).toEqual([
      `${CDN}/gallery/p1/a.jpg`,
      `${CDN}/gallery/p1/b.jpg`,
      `${CDN}/gallery/p1/c.jpg`,
      `${CDN}/gallery/p1/d.jpg`,
    ]);
    expect(input()).toBeEnabled();
  });

  it('says where it is — « Téléversement 2 sur 3… » — and each photo shows as soon as it is saved', async () => {
    holdName = 'c.jpg';
    await openMedias();
    pickAll('b.jpg', 'c.jpg', 'd.jpg');
    expect(await screen.findByText('Téléversement 2 sur 3…')).toBeInTheDocument();
    expect(input()).toBeDisabled();
    await waitFor(() => expect(shown()).toContain(`${CDN}/gallery/p1/b.jpg`));
    await act(async () => hold?.release());
    expect(await screen.findByText('3 photos ajoutées.')).toBeInTheDocument();
  });

  it('more than the room left: the first ones picked, and it says how many were left out', async () => {
    stored = Array.from({ length: 18 }, (_, i) => `${CDN}/gallery/p1/s${i}.jpg`);
    await openMedias();
    pickAll('w.jpg', 'x.jpg', 'y.jpg', 'z.jpg');
    expect(
      await screen.findByText('20 photos maximum : 2 photos n’ont pas été ajoutées.'),
    ).toBeInTheDocument();
    expect(
      await screen.findByText(
        '2 photos ajoutées. 20 photos maximum : 2 photos n’ont pas été ajoutées.',
      ),
    ).toBeInTheDocument();
    expect(uploadCalls).toEqual(['w.jpg', 'x.jpg']);
    expect(stored).toHaveLength(20);
  });

  it('a photo that cannot be read is skipped; the others go on; the summary counts it', async () => {
    failFor = { 'c.heic': 'unreadable' };
    await openMedias();
    pickAll('b.jpg', 'c.heic', 'd.jpg');
    expect(
      await screen.findByText('2 photos ajoutées sur 3. 1 n’a pas pu être envoyée.'),
    ).toBeInTheDocument();
    expect(uploadCalls).toEqual(['b.jpg', 'c.heic', 'd.jpg']);
    expect(puts).toHaveLength(2);
  });

  it('a save the server refuses counts as a photo not added, and the next one still goes', async () => {
    refuseSave = 2;
    await openMedias();
    pickAll('b.jpg', 'c.jpg', 'd.jpg');
    expect(
      await screen.findByText('2 photos ajoutées sur 3. 1 n’a pas pu être envoyée.'),
    ).toBeInTheDocument();
    expect(stored).toEqual([
      `${CDN}/gallery/p1/a.jpg`,
      `${CDN}/gallery/p1/b.jpg`,
      `${CDN}/gallery/p1/d.jpg`,
    ]);
  });

  it('none could be read: one sentence, with what to do', async () => {
    failFor = { 'b.heic': 'unreadable', 'c.heic': 'unreadable' };
    await openMedias();
    pickAll('b.heic', 'c.heic');
    expect(
      await screen.findByText('Aucune photo n’a pu être envoyée. Choisissez des images JPEG, PNG ou WebP.'),
    ).toBeInTheDocument();
    expect(puts).toEqual([]);
  });

  it('leaving Médias mid-way: nothing more is sent; what was saved stays', async () => {
    holdName = 'c.jpg';
    await openMedias();
    pickAll('b.jpg', 'c.jpg', 'd.jpg');
    await screen.findByText('Téléversement 2 sur 3…');
    await waitFor(() => expect(puts).toHaveLength(1));
    cleanup(); // the page is left
    await act(async () => hold?.release());
    await new Promise((r) => setTimeout(r, 30));
    expect(uploadCalls).toEqual(['b.jpg', 'c.jpg']);
    expect(puts).toHaveLength(1);
    expect(stored).toEqual([`${CDN}/gallery/p1/a.jpg`, `${CDN}/gallery/p1/b.jpg`]);
  });

  it('one photo picked: exactly as before — no summary', async () => {
    await openMedias();
    pickAll('b.jpg');
    await waitFor(() => expect(stored).toHaveLength(2));
    await waitFor(() => expect(input()).toBeEnabled());
    expect(screen.queryByText(/ajoutée/)).toBeNull();
    // The toast region is always there (a live region); it says nothing.
    expect(screen.queryByRole('status')?.textContent ?? '').toBe('');
  });
});

describe('the pure rules', () => {
  it('fitInGallery keeps the first ones up to 20', () => {
    expect(fitInGallery([1, 2, 3, 4], 18)).toEqual({ kept: [1, 2], dropped: 2 });
    expect(fitInGallery([1, 2], 0)).toEqual({ kept: [1, 2], dropped: 0 });
    expect(fitInGallery([1], 20)).toEqual({ kept: [], dropped: 1 });
    expect(fitInGallery([1, 2, 3], 17)).toEqual({ kept: [1, 2, 3], dropped: 0 });
  });

  it('overCapMessage agrees with the count', () => {
    expect(overCapMessage(1)).toBe('20 photos maximum : 1 photo n’a pas été ajoutée.');
    expect(overCapMessage(3)).toBe('20 photos maximum : 3 photos n’ont pas été ajoutées.');
  });

  it('batchSummary: none for one; success; partial; none; the shared hint only when shared', () => {
    expect(batchSummary({ total: 1, added: 1, failures: [] })).toBeNull();
    expect(batchSummary({ total: 1, added: 0, failures: ['failed'] })).toBeNull();
    expect(batchSummary({ total: 2, added: 2, failures: [] })).toEqual({
      message: '2 photos ajoutées.',
      kind: 'success',
    });
    expect(batchSummary({ total: 3, added: 1, failures: ['failed', 'failed'] })).toEqual({
      message: '1 photo ajoutée sur 3. 2 n’ont pas pu être envoyées.',
      kind: 'error',
    });
    expect(batchSummary({ total: 2, added: 0, failures: ['too_large', 'too_large'] })?.message).toBe(
      'Aucune photo n’a pu être envoyée. Choisissez des images plus petites.',
    );
    expect(batchSummary({ total: 2, added: 0, failures: ['too_large', 'unreadable'] })?.message).toBe(
      'Aucune photo n’a pu être envoyée.',
    );
    expect(batchSummary({ total: 2, added: 0, failures: ['failed', 'failed'] })?.message).toBe(
      'Aucune photo n’a pu être envoyée.',
    );
  });
});
