import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const routerMock = { replace: vi.fn(), push: vi.fn(), refresh: vi.fn() };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));
vi.mock('next/dynamic', () => ({ default: () => () => null }));

type Outcome =
  | { ok: true; url: string }
  | { ok: false; reason: 'unreadable' | 'too_large' | 'blocked' | 'failed' | 'aborted' };
type Deps = { signal?: AbortSignal };
let outcome: Outcome = { ok: false, reason: 'failed' };
/// When set, the upload waits for it — the busy state while a photo is being
/// prepared and sent, and leaving the page meanwhile.
let hold: Promise<void> | null = null;
const uploadGalleryImage = vi.fn(async (_file: File, _deps?: Deps) => {
  if (hold) await hold;
  return outcome;
});
const uploadLogoImage = vi.fn(async (_file: File, _deps?: Deps) => {
  if (hold) await hold;
  return outcome;
});
// The real sentences and their mapping; only the network half is replaced.
vi.mock('../lib/pro/upload', async (importActual) => ({
  ...(await importActual<typeof import('../lib/pro/upload')>()),
  uploadGalleryImage: (file: File, deps?: Deps) => uploadGalleryImage(file, deps),
  uploadLogoImage: (file: File, deps?: Deps) => uploadLogoImage(file, deps),
}));

function held(): () => void {
  let release: () => void = () => {};
  hold = new Promise<void>((resolve) => {
    release = resolve;
  });
  return () => {
    hold = null;
    release();
  };
}

import { CatalogueClient } from '../components/pro/CatalogueClient';
import { MediasClient } from '../components/pro/MediasClient';
import { ProfilClient } from '../components/pro/ProfilClient';

/// docs/design/web-pro-upload-resize.md §2.3/§2.6 — the two new sentences,
/// each on the surface's existing channel: Médias (photos and before/after) →
/// the toast (`role="status"`); Catalogue's staff photo and Profil's logo →
/// their `role="alert"`. A plain failure keeps the sentence each said before.

const UNREADABLE = 'Cette image n’a pas pu être lue. Choisissez une image JPEG, PNG ou WebP.';
const TOO_LARGE = 'Cette image est trop grande pour être préparée ici. Choisissez une image plus petite.';
const BLOCKED = 'Votre navigateur empêche de préparer cette image. Essayez avec un autre navigateur.';

const OWNER_CAPS = [
  'journal.view.all',
  'journal.manage.all',
  'clients.view',
  'catalogue.manage',
  'availability.manage',
  'profile.manage',
  'finances.view',
  'deposit.manage',
  'members.manage',
  'subscription.manage',
  'salon.publish',
];

beforeEach(() => {
  hold = null;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      if (url === '/api/pro/me') {
        return new Response(
          JSON.stringify({
            account: { id: 'acc-1', email: 'x@salon.test' },
            provider: {
              id: 'p1',
              name: 'Beauté Divine',
              status: 'active',
              imageUrls: ['https://cdn/a.jpg'],
              beforeAfters: [],
              services: [],
              artists: [],
            },
            membership: { role: 'owner', capabilities: OWNER_CAPS },
          }),
          { status: 200 },
        );
      }
      if (url === '/api/pro/medias/gallery') return new Response('{}', { status: 200 });
      return new Response('{}', { status: 404 });
    }),
  );
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  uploadGalleryImage.mockClear();
  uploadLogoImage.mockClear();
});

const pick = (input: Element) =>
  fireEvent.change(input, { target: { files: [new File(['x'], 'IMG.heic', { type: 'image/heic' })] } });

const REASONS = (failed: string) =>
  [
    ['unreadable', UNREADABLE],
    ['too_large', TOO_LARGE],
    ['blocked', BLOCKED],
    ['failed', failed],
  ] as const;

/// The toast's pill: an error wears `bg-error` and stays 6 s (SYSTEM §15).
const pill = (sentence: string) => screen.getByText(sentence, { selector: '[role=status] > div' });

describe('Médias → Photos: the toast', () => {
  for (const [reason, sentence] of REASONS('Échec de l’envoi')) {
    it(`${reason} → « ${sentence} », as an error`, async () => {
      outcome = { ok: false, reason };
      render(<MediasClient />);
      await screen.findByText('Couverture');
      pick(document.querySelector('input[type=file]')!);
      await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent(sentence));
      expect(pill(sentence).className).toContain('bg-error');
      expect(uploadGalleryImage).toHaveBeenCalledTimes(1);
    });
  }

  it('while the photo is prepared and sent: « Téléversement… », the input disabled — until it is done', async () => {
    outcome = { ok: true, url: 'https://cdn/new.jpg' };
    const done = held();
    render(<MediasClient />);
    await screen.findByText('Couverture');
    const input = document.querySelector('input[type=file]') as HTMLInputElement;
    pick(input);
    expect(await screen.findByText('Téléversement…')).toBeInTheDocument();
    expect(input).toBeDisabled();
    await act(async () => done());
    await waitFor(() => expect(screen.getByText('Ajouter une photo')).toBeInTheDocument());
    expect(document.querySelector('input[type=file]')).not.toBeDisabled();
  });

  // Review F3: the photo was still added to the public gallery after Médias
  // had been left.
  it('Médias left while the photo is on its way: the upload is told, nothing is saved', async () => {
    outcome = { ok: true, url: 'https://cdn/new.jpg' };
    const done = held();
    const { unmount } = render(<MediasClient />);
    await screen.findByText('Couverture');
    pick(document.querySelector('input[type=file]')!);
    await waitFor(() => expect(uploadGalleryImage).toHaveBeenCalledTimes(1));
    const signal = uploadGalleryImage.mock.calls[0][1]?.signal;
    expect(signal?.aborted).toBe(false);
    unmount();
    expect(signal?.aborted).toBe(true);
    await act(async () => done());
    await new Promise((r) => setTimeout(r, 20));
    const calls = (fetch as unknown as { mock: { calls: [string][] } }).mock.calls.map(([u]) => u);
    expect(calls).not.toContain('/api/pro/medias/gallery');
  });

  it('not left (the control): the uploaded photo is saved to the gallery', async () => {
    outcome = { ok: true, url: 'https://cdn/new.jpg' };
    render(<MediasClient />);
    await screen.findByText('Couverture');
    pick(document.querySelector('input[type=file]')!);
    await waitFor(() => {
      const calls = (fetch as unknown as { mock: { calls: [string][] } }).mock.calls.map(([u]) => u);
      expect(calls).toContain('/api/pro/medias/gallery');
    });
  });

  // §2.7: the input is disabled while it works, which leaves the focus on the
  // page (Chromium — measured by the review, and by pro-upload.spec.ts); it
  // comes back when it is done. jsdom does not move the focus off a disabled
  // control, so here the focus is simply on the page while it works.
  it('the focus comes back to the input when the upload ends, if it had been lost', async () => {
    outcome = { ok: false, reason: 'unreadable' };
    const done = held();
    render(<MediasClient />);
    await screen.findByText('Couverture');
    const input = document.querySelector('input[type=file]') as HTMLInputElement;
    pick(input);
    await screen.findByText('Téléversement…');
    expect(document.activeElement).toBe(document.body);
    await act(async () => done());
    await waitFor(() => expect(document.activeElement).toBe(input));
  });

  it('…and stays where the person put it meanwhile', async () => {
    outcome = { ok: false, reason: 'unreadable' };
    const done = held();
    render(<MediasClient />);
    await screen.findByText('Couverture');
    const input = document.querySelector('input[type=file]') as HTMLInputElement;
    pick(input);
    await screen.findByText('Téléversement…');
    const tab = screen.getByRole('button', { name: 'Avant / Après' });
    tab.focus();
    await act(async () => done());
    await screen.findByText('Ajouter une photo');
    expect(document.activeElement).toBe(tab);
  });
});

describe('Médias → Avant / Après: the toast', () => {
  for (const [reason, sentence] of REASONS('Échec de l’envoi')) {
    it(`${reason} → « ${sentence} », as an error, and the pair cannot be added`, async () => {
      outcome = { ok: false, reason };
      render(<MediasClient />);
      await screen.findByText('Couverture');
      fireEvent.click(screen.getByRole('button', { name: 'Avant / Après' }));
      pick(document.querySelectorAll('input[type=file]')[0]);
      await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent(sentence));
      expect(pill(sentence).className).toContain('bg-error');
      expect(screen.getByRole('button', { name: 'Ajouter la paire' })).toBeDisabled();
    });
  }

  // The review: nothing showed while a side was on its way; the app shows
  // « Envoi… » and holds its add button.
  it('while « Avant » is on its way: it says « Téléversement… », both pickers wait', async () => {
    outcome = { ok: true, url: 'https://cdn/avant.jpg' };
    const done = held();
    render(<MediasClient />);
    await screen.findByText('Couverture');
    fireEvent.click(screen.getByRole('button', { name: 'Avant / Après' }));
    const [avant, apres] = Array.from(document.querySelectorAll('input[type=file]')) as HTMLInputElement[];
    pick(avant);
    expect(await screen.findByText('Téléversement…')).toBeInTheDocument();
    expect(avant).toBeDisabled();
    expect(apres).toBeDisabled();
    expect(screen.getByText('Après')).toBeInTheDocument();
    expect(document.activeElement).toBe(document.body);
    await act(async () => done());
    expect(await screen.findByText('Avant ✓')).toBeInTheDocument();
    expect(avant).not.toBeDisabled();
    expect(apres).not.toBeDisabled();
    await waitFor(() => expect(document.activeElement).toBe(avant));
  });
});

async function openStaffForm() {
  render(<CatalogueClient />);
  fireEvent.click(await screen.findByRole('button', { name: 'Employés' }));
  fireEvent.click(screen.getByRole('button', { name: 'Ajouter un employé' }));
}

describe('Catalogue → Employés → photo: the alert', () => {
  for (const [reason, sentence] of REASONS('Échec de l’envoi de la photo.')) {
    it(`${reason} → « ${sentence} », right under the photo button`, async () => {
      outcome = { ok: false, reason };
      await openStaffForm();
      pick(screen.getByLabelText('Photo de l’employé'));
      const alert = await screen.findByRole('alert');
      expect(alert).toHaveTextContent(sentence);
      // Its own line under the button, not the form's message after the hours
      // (below the fold at 320 px with doubled text — the review).
      const row = screen.getByRole('button', { name: 'Ajouter une photo' }).parentElement!;
      expect(row.nextElementSibling).toBe(alert);
    });
  }

  it('while the photo is prepared and sent: the button is busy, then free again', async () => {
    outcome = { ok: true, url: 'https://cdn/staff.jpg' };
    const done = held();
    await openStaffForm();
    pick(screen.getByLabelText('Photo de l’employé'));
    const button = screen.getByRole('button', { name: /Ajouter une photo/ });
    await waitFor(() => expect(button).toHaveAttribute('aria-busy', 'true'));
    expect(button).toBeDisabled();
    expect(document.activeElement).toBe(document.body);
    await act(async () => done());
    const changed = await screen.findByRole('button', { name: 'Changer la photo' });
    expect(changed).not.toBeDisabled();
    await waitFor(() => expect(document.activeElement).toBe(changed));
  });

  it('the form closed while the photo is on its way: the upload is told', async () => {
    outcome = { ok: true, url: 'https://cdn/staff.jpg' };
    const done = held();
    await openStaffForm();
    pick(screen.getByLabelText('Photo de l’employé'));
    await waitFor(() => expect(uploadGalleryImage).toHaveBeenCalledTimes(1));
    const signal = uploadGalleryImage.mock.calls[0][1]?.signal;
    expect(signal?.aborted).toBe(false);
    fireEvent.click(screen.getByRole('button', { name: 'Annuler' }));
    expect(signal?.aborted).toBe(true);
    await act(async () => done());
  });
});

describe('Profil → logo: the alert', () => {
  for (const [reason, sentence] of REASONS('Échec de l’envoi du logo.')) {
    it(`${reason} → « ${sentence} »`, async () => {
      outcome = { ok: false, reason };
      render(<ProfilClient />);
      await screen.findByLabelText('Nom du salon');
      pick(screen.getByLabelText('Logo du salon'));
      expect(await screen.findByRole('alert')).toHaveTextContent(sentence);
      expect(uploadLogoImage).toHaveBeenCalledTimes(1);
    });
  }

  it('while the logo is prepared and sent: the button is busy; the focus comes back to it', async () => {
    outcome = { ok: false, reason: 'too_large' };
    const done = held();
    render(<ProfilClient />);
    await screen.findByLabelText('Nom du salon');
    const button = screen.getByRole('button', { name: /Ajouter un logo/ });
    pick(screen.getByLabelText('Logo du salon'));
    await waitFor(() => expect(button).toHaveAttribute('aria-busy', 'true'));
    expect(document.activeElement).toBe(document.body);
    await act(async () => done());
    expect(await screen.findByRole('alert')).toHaveTextContent(TOO_LARGE);
    await waitFor(() => expect(document.activeElement).toBe(button));
  });

  it('Profil left while the logo is on its way: the upload is told', async () => {
    outcome = { ok: true, url: 'https://cdn/logo.jpg' };
    const done = held();
    const { unmount } = render(<ProfilClient />);
    await screen.findByLabelText('Nom du salon');
    pick(screen.getByLabelText('Logo du salon'));
    await waitFor(() => expect(uploadLogoImage).toHaveBeenCalledTimes(1));
    const signal = uploadLogoImage.mock.calls[0][1]?.signal;
    unmount();
    expect(signal?.aborted).toBe(true);
    await act(async () => done());
  });

  it('success stages the logo (« Changer le logo »), no alert', async () => {
    outcome = { ok: true, url: 'https://cdn/logo.jpg' };
    render(<ProfilClient />);
    await screen.findByLabelText('Nom du salon');
    pick(screen.getByLabelText('Logo du salon'));
    expect(await screen.findByRole('button', { name: 'Changer le logo' })).toBeInTheDocument();
    expect(screen.queryByRole('alert')).toBeNull();
  });
});
