import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const routerMock = { replace: vi.fn(), push: vi.fn(), refresh: vi.fn() };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));
vi.mock('next/dynamic', () => ({ default: () => () => null }));

type Outcome = { ok: true; url: string } | { ok: false; reason: 'unreadable' | 'too_large' | 'failed' };
let outcome: Outcome = { ok: false, reason: 'failed' };
const uploadGalleryImage = vi.fn(async (_file: File) => outcome);
const uploadLogoImage = vi.fn(async (_file: File) => outcome);
// The real sentences and their mapping; only the network half is replaced.
vi.mock('../lib/pro/upload', async (importActual) => ({
  ...(await importActual<typeof import('../lib/pro/upload')>()),
  uploadGalleryImage: (file: File) => uploadGalleryImage(file),
  uploadLogoImage: (file: File) => uploadLogoImage(file),
}));

import { CatalogueClient } from '../components/pro/CatalogueClient';
import { MediasClient } from '../components/pro/MediasClient';
import { ProfilClient } from '../components/pro/ProfilClient';

/// docs/design/web-pro-upload-resize.md §2.3/§2.6 — the two new sentences,
/// each on the surface's existing channel: Médias (photos and before/after) →
/// the toast (`role="status"`); Catalogue's staff photo and Profil's logo →
/// their `role="alert"`. A plain failure keeps the sentence each said before.

const UNREADABLE = 'Cette image n’a pas pu être lue. Choisissez une image JPEG, PNG ou WebP.';
const TOO_LARGE = 'Cette image est trop grande pour être préparée ici. Choisissez une image plus petite.';

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

describe('Médias → Photos: the toast', () => {
  for (const [reason, sentence] of [
    ['unreadable', UNREADABLE],
    ['too_large', TOO_LARGE],
    ['failed', 'Échec de l’envoi'],
  ] as const) {
    it(`${reason} → « ${sentence} »`, async () => {
      outcome = { ok: false, reason };
      render(<MediasClient />);
      await screen.findByText('Couverture');
      pick(document.querySelector('input[type=file]')!);
      await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent(sentence));
      expect(uploadGalleryImage).toHaveBeenCalledTimes(1);
    });
  }
});

describe('Médias → Avant / Après: the toast', () => {
  it('too_large → the sentence, and the pair cannot be added', async () => {
    outcome = { ok: false, reason: 'too_large' };
    render(<MediasClient />);
    await screen.findByText('Couverture');
    fireEvent.click(screen.getByRole('button', { name: 'Avant / Après' }));
    pick(document.querySelectorAll('input[type=file]')[0]);
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent(TOO_LARGE));
    expect(screen.getByRole('button', { name: 'Ajouter la paire' })).toBeDisabled();
  });
});

describe('Catalogue → Employés → photo: the alert', () => {
  for (const [reason, sentence] of [
    ['unreadable', UNREADABLE],
    ['too_large', TOO_LARGE],
    ['failed', 'Échec de l’envoi de la photo.'],
  ] as const) {
    it(`${reason} → « ${sentence} »`, async () => {
      outcome = { ok: false, reason };
      render(<CatalogueClient />);
      fireEvent.click(await screen.findByRole('button', { name: 'Employés' }));
      fireEvent.click(screen.getByRole('button', { name: 'Ajouter un employé' }));
      pick(screen.getByLabelText('Photo de l’employé'));
      expect(await screen.findByRole('alert')).toHaveTextContent(sentence);
    });
  }
});

describe('Profil → logo: the alert', () => {
  for (const [reason, sentence] of [
    ['unreadable', UNREADABLE],
    ['too_large', TOO_LARGE],
    ['failed', 'Échec de l’envoi du logo.'],
  ] as const) {
    it(`${reason} → « ${sentence} »`, async () => {
      outcome = { ok: false, reason };
      render(<ProfilClient />);
      await screen.findByLabelText('Nom du salon');
      pick(screen.getByLabelText('Logo du salon'));
      expect(await screen.findByRole('alert')).toHaveTextContent(sentence);
      expect(uploadLogoImage).toHaveBeenCalledTimes(1);
    });
  }

  it('success stages the logo (« Changer le logo »), no alert', async () => {
    outcome = { ok: true, url: 'https://cdn/logo.jpg' };
    render(<ProfilClient />);
    await screen.findByLabelText('Nom du salon');
    pick(screen.getByLabelText('Logo du salon'));
    expect(await screen.findByRole('button', { name: 'Changer le logo' })).toBeInTheDocument();
    expect(screen.queryByRole('alert')).toBeNull();
  });
});
