import { act, cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const routerMock = { replace: vi.fn(), push: vi.fn(), refresh: vi.fn() };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));
// jsdom has no R2: an upload answers this URL.
vi.mock('../lib/pro/upload', () => ({
  uploadGalleryImage: async () => 'https://cdn/new.jpg',
}));

import { MediasClient } from '../components/pro/MediasClient';

/// docs/design/web-pro-medias-like-app.md (owner decision: like the app) —
/// every gesture saves at once, as `pro_photos_screen.dart` /
/// `pro_before_after_screen.dart` do; deleting asks first (the app's words)
/// and can be taken back for 10 s. The web staged everything behind
/// « Enregistrer », deleted without asking, and lost unsaved work on leaving.

const A = 'https://cdn/a.jpg';
const B = 'https://cdn/b.jpg';
const C = 'https://cdn/c.jpg';
const PAIR = { before: 'https://cdn/b1.jpg', after: 'https://cdn/a1.jpg', caption: 'Tresses' };

const gallery: string[][] = [];
const pairs: unknown[][] = [];
let galleryStatus = 200;

beforeEach(() => {
  gallery.length = 0;
  pairs.length = 0;
  galleryStatus = 200;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      if (url === '/api/pro/me') {
        return new Response(
          JSON.stringify({
            account: { id: 'acc-1', email: 'x@salon.test' },
            provider: { id: 'p1', name: 'Beauté Divine', imageUrls: [A, B, C], beforeAfters: [PAIR] },
          }),
          { status: 200 },
        );
      }
      if (url === '/api/pro/medias/gallery') {
        gallery.push(JSON.parse(String(init?.body)).imageUrls);
        return new Response('{}', { status: galleryStatus });
      }
      if (url === '/api/pro/medias/before-after') {
        pairs.push(JSON.parse(String(init?.body)).beforeAfters);
        return new Response('{}', { status: 200 });
      }
      return new Response('{}', { status: 404 });
    }),
  );
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

const shown = () =>
  Array.from(document.querySelectorAll('main img, img')).map((i) => i.getAttribute('src'));
const ready = () => screen.findByText('Couverture');
const tile = (n: number) => screen.getAllByRole('button', { name: 'Supprimer' })[n];

describe('Photos — every gesture saves, as in the app', () => {
  it('no « Enregistrer » any more', async () => {
    render(<MediasClient />);
    await ready();
    expect(screen.queryByRole('button', { name: 'Enregistrer' })).toBeNull();
  });

  it('★ makes a photo the cover — saved at once', async () => {
    render(<MediasClient />);
    await ready();
    fireEvent.click(screen.getAllByRole('button', { name: 'Définir comme photo principale' })[1]);
    await waitFor(() => expect(gallery).toEqual([[C, A, B]]));
  });

  it('« Descendre » — saved at once', async () => {
    render(<MediasClient />);
    await ready();
    fireEvent.click(screen.getAllByRole('button', { name: 'Descendre' })[0]);
    await waitFor(() => expect(gallery).toEqual([[B, A, C]]));
  });

  it('an added photo is saved at once', async () => {
    render(<MediasClient />);
    await ready();
    const input = document.querySelector('input[type=file]') as HTMLInputElement;
    fireEvent.change(input, { target: { files: [new File(['x'], 'p.jpg', { type: 'image/jpeg' })] } });
    await waitFor(() => expect(gallery).toEqual([[A, B, C, 'https://cdn/new.jpg']]));
  });

  it('a refused move puts the photos back and says so (the app’s words)', async () => {
    galleryStatus = 500;
    render(<MediasClient />);
    await ready();
    fireEvent.click(screen.getAllByRole('button', { name: 'Descendre' })[0]);
    expect(await screen.findByText('Échec du déplacement')).toBeInTheDocument();
    expect(shown().slice(0, 3)).toEqual([A, B, C]);
  });
});

describe('Photos — deleting asks first, then can be taken back for 10 s', () => {
  it('the app’s question; « Annuler » takes the focus and sends nothing', async () => {
    render(<MediasClient />);
    await ready();
    fireEvent.click(tile(0));
    const dialog = await screen.findByRole('dialog', { name: 'Supprimer cette photo ?' });
    expect(within(dialog).getByText('Elle disparaîtra de votre galerie publique.')).toBeInTheDocument();
    const cancel = within(dialog).getByRole('button', { name: 'Annuler' });
    expect(cancel).toHaveFocus();
    fireEvent.click(cancel);
    expect(screen.queryByRole('dialog')).toBeNull();
    expect(gallery).toEqual([]);
  });

  it('« Supprimer la photo » saves without it; « Photo supprimée » offers « Annuler », which puts it back', async () => {
    render(<MediasClient />);
    await ready();
    fireEvent.click(tile(0));
    const dialog = await screen.findByRole('dialog', { name: 'Supprimer cette photo ?' });
    fireEvent.click(within(dialog).getByRole('button', { name: 'Supprimer la photo' }));
    await waitFor(() => expect(gallery).toEqual([[B, C]]));
    const status = await screen.findByRole('status');
    await waitFor(() => expect(status).toHaveTextContent('Photo supprimée'));
    fireEvent.click(within(status).getByRole('button', { name: 'Annuler' }));
    await waitFor(() => expect(gallery).toEqual([[B, C], [A, B, C]]));
  });

  it('the undo puts back ONE photo into the gallery as it is now — never a snapshot', async () => {
    render(<MediasClient />);
    await ready();
    fireEvent.click(tile(0)); // delete A
    fireEvent.click(
      within(await screen.findByRole('dialog')).getByRole('button', { name: 'Supprimer la photo' }),
    );
    await waitFor(() => expect(gallery).toHaveLength(1));
    // Then C becomes the cover: [C, B].
    fireEvent.click(screen.getAllByRole('button', { name: 'Définir comme photo principale' })[0]);
    await waitFor(() => expect(gallery).toHaveLength(2));
    expect(gallery[1]).toEqual([C, B]);
    fireEvent.click(within(screen.getByRole('status')).getByRole('button', { name: 'Annuler' }));
    await waitFor(() => expect(gallery).toHaveLength(3));
    expect(gallery[2]).toEqual([A, C, B]);
  });

  it('a refused delete keeps the photo and says so', async () => {
    galleryStatus = 500;
    render(<MediasClient />);
    await ready();
    fireEvent.click(tile(0));
    fireEvent.click(
      within(await screen.findByRole('dialog')).getByRole('button', { name: 'Supprimer la photo' }),
    );
    expect(await screen.findByText('Suppression impossible.')).toBeInTheDocument();
    expect(shown().slice(0, 3)).toEqual([A, B, C]);
  });
});

describe('Avant / Après — the same, for pairs', () => {
  async function openTab() {
    render(<MediasClient />);
    await ready();
    fireEvent.click(screen.getByRole('button', { name: 'Avant / Après' }));
  }

  it('no « Enregistrer »; a pair is saved when added', async () => {
    await openTab();
    expect(screen.queryByRole('button', { name: 'Enregistrer' })).toBeNull();
    const inputs = document.querySelectorAll('input[type=file]');
    const f = () => ({ target: { files: [new File(['x'], 'p.jpg', { type: 'image/jpeg' })] } });
    fireEvent.change(inputs[0], f());
    fireEvent.change(inputs[1], f());
    const add = screen.getByRole('button', { name: 'Ajouter la paire' });
    await waitFor(() => expect(add).toBeEnabled());
    fireEvent.click(add);
    await waitFor(() => expect(pairs).toHaveLength(1));
    expect(pairs[0]).toHaveLength(2);
  });

  it('deleting a pair asks (the app’s words), then « Avant/après supprimé » can be taken back', async () => {
    await openTab();
    fireEvent.click(screen.getByRole('button', { name: 'Supprimer' }));
    const dialog = await screen.findByRole('dialog', { name: 'Supprimer cette paire ?' });
    expect(
      within(dialog).getByText('L’avant/après disparaîtra de votre galerie publique.'),
    ).toBeInTheDocument();
    fireEvent.click(within(dialog).getByRole('button', { name: 'Supprimer la paire' }));
    await waitFor(() => expect(pairs).toEqual([[]]));
    const status = screen.getByRole('status');
    await waitFor(() => expect(status).toHaveTextContent('Avant/après supprimé'));
    fireEvent.click(within(status).getByRole('button', { name: 'Annuler' }));
    await waitFor(() => expect(pairs).toEqual([[], [PAIR]]));
  });
});

describe('the toast with an action stays 10 s (SYSTEM §15: the only route back)', () => {
  it('there at 9.9 s, gone at 10.1 s', async () => {
    const { useToast } = await import('../lib/useToast');
    const { renderHook } = await import('@testing-library/react');
    vi.useFakeTimers();
    try {
      const { result } = renderHook(() => useToast());
      act(() => result.current.show('Photo supprimée', 'success', { label: 'Annuler', onAction: () => {} }));
      act(() => vi.advanceTimersByTime(9900));
      expect(result.current.toast?.message).toBe('Photo supprimée');
      act(() => vi.advanceTimersByTime(200));
      expect(result.current.toast).toBeNull();
    } finally {
      vi.useRealTimers();
    }
  });
});
