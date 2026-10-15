import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
// Stable object: the load effect depends on [router].
const routerMock = { replace };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));

import { AddSalonClient } from '../components/pro/AddSalonClient';
import { DEMO_ACCOUNT_LOCKED_MESSAGE } from '../lib/pro/team';
import { resetLocalitiesClientCache } from '../lib/use-localities';
import { fixtureTree } from './localities.test';

/// Team access R6c — « Ajouter un salon »: validation, the Réseau gate copy
/// (+ CTA), and the happy path (create → select → the draft dashboard).
/// Multi-pays MP3: the locality picker rides the form (optional — the
/// publish gate enforces).

const ME = {
  account: { id: 'acc1', phoneNumber: '+2250700000000' },
  provider: { id: 'p1', name: 'Beauté Divine' },
};

function mockFetch(opts: { addStatus: number; addBody: unknown }) {
  const calls: { url: string; body?: Record<string, unknown> }[] = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      calls.push({
        url,
        body: init?.body ? JSON.parse(init.body as string) : undefined,
      });
      if (url === '/api/pro/me') {
        return new Response(JSON.stringify(ME), { status: 200 });
      }
      if (url === '/api/pro/salons') {
        return new Response(JSON.stringify(opts.addBody), {
          status: opts.addStatus,
        });
      }
      if (url === '/api/pro/salons/select') {
        return new Response(JSON.stringify(ME), { status: 200 });
      }
      if (url === '/api/localities') {
        return new Response(JSON.stringify(fixtureTree), { status: 200 });
      }
      return new Response('{}', { status: 404 });
    }),
  );
  return calls;
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  resetLocalitiesClientCache();
  replace.mockReset();
});

describe('AddSalonClient', () => {
  it('an empty name blocks the submit client-side', async () => {
    mockFetch({ addStatus: 201, addBody: {} });
    render(<AddSalonClient />);
    await screen.findByText('Ajouter un salon');
    // The button is disabled while the name is empty.
    expect(
      (screen.getByRole('button', { name: 'Créer le salon' }) as HTMLButtonElement)
        .disabled,
    ).toBe(true);
  });

  it('reseau_required → the shared copy + the offer CTA', async () => {
    mockFetch({ addStatus: 403, addBody: { error: 'reseau_required' } });
    render(<AddSalonClient />);
    await screen.findByText('Ajouter un salon');

    fireEvent.change(screen.getByPlaceholderText('Ex : Salon Excellence Yopougon'), {
      target: { value: 'Salon Trois' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Créer le salon' }));

    expect(
      await screen.findByText(/offre Réseau est requise/),
    ).toBeTruthy();
    const cta = screen.getByRole('link', { name: 'Passer à l’offre Réseau' });
    expect(cta.getAttribute('href')).toBe('/pro/abonnement');
    expect(replace).not.toHaveBeenCalled();
  });

  it('demo_account_locked → the demo sentence, and no offer CTA', async () => {
    // Same table, same code (docs/design/demo-account-deletion-lock.md §7.2).
    mockFetch({ addStatus: 403, addBody: { error: 'demo_account_locked' } });
    render(<AddSalonClient />);
    await screen.findByText('Ajouter un salon');

    fireEvent.change(screen.getByPlaceholderText('Ex : Salon Excellence Yopougon'), {
      target: { value: 'Salon Trois' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Créer le salon' }));

    // The constant, not a retyped copy: tests/pro-team.test.ts holds it to
    // the app's sentence, character for character.
    expect(await screen.findByText(DEMO_ACCOUNT_LOCKED_MESSAGE)).toBeTruthy();
    expect(screen.queryByRole('link', { name: 'Passer à l’offre Réseau' })).toBeNull();
    expect(replace).not.toHaveBeenCalled();
  });

  it('success → create, SELECT the new salon, land on /pro', async () => {
    const calls = mockFetch({
      addStatus: 201,
      addBody: {
        salon: {
          salonId: 'p4',
          salonName: 'Salon Trois',
          role: 'owner',
          salonStatus: 'draft',
          verified: true,
        },
      },
    });
    render(<AddSalonClient />);
    await screen.findByText('Ajouter un salon');

    fireEvent.change(screen.getByPlaceholderText('Ex : Salon Excellence Yopougon'), {
      target: { value: 'Salon Trois' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Créer le salon' }));

    await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro'));
    const add = calls.find(
      (c) => c.url === '/api/pro/salons' && c.body !== undefined,
    );
    expect(add?.body).toMatchObject({
      businessName: 'Salon Trois',
      businessType: 'salon',
    });
    const select = calls.find((c) => c.url === '/api/pro/salons/select');
    expect(select?.body).toEqual({ salonId: 'p4' });
  });

  it('a server invalid_phone answers UNDER « Téléphone du salon », not « Réessayez »', async () => {
    // POST /me/salons gained its 400 invalid_phone on this branch
    // (docs/design/phone-national-length.md §2.4). Defence in depth: the
    // client rule matches the server's, so only drift or a bypass reaches it —
    // and then the fault is the field's (§14 rule 1), never a retry that
    // cannot succeed.
    mockFetch({ addStatus: 400, addBody: { error: 'invalid_phone' } });
    render(<AddSalonClient />);
    await screen.findByText('Ajouter un salon');
    const phone = await waitFor(() => {
      const el = screen.getByLabelText('Téléphone du salon') as HTMLInputElement;
      expect(el).not.toBeDisabled();
      return el;
    });

    fireEvent.change(screen.getByPlaceholderText('Ex : Salon Excellence Yopougon'), {
      target: { value: 'Salon Trois' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Créer le salon' }));

    const fault = await screen.findByText('Saisissez un numéro de téléphone valide.');
    expect(phone).toHaveAttribute('aria-invalid', 'true');
    expect(phone.getAttribute('aria-describedby')).toContain(fault.id);
    expect(screen.queryByText('Une erreur est survenue. Réessayez.')).toBeNull();
    expect(replace).not.toHaveBeenCalled();
  });

  it('the account phone prefill is what the field SHOWS — and what is sent', async () => {
    // PhoneField reads `initialValue` once, at mount; the account phone
    // arrives later. The field used to show a bare « +225 » while the submit
    // carried the account number — a value the owner never saw.
    const calls = mockFetch({
      addStatus: 201,
      addBody: {
        salon: {
          salonId: 'p4',
          salonName: 'Salon Trois',
          role: 'owner',
          salonStatus: 'draft',
          verified: true,
        },
      },
    });
    render(<AddSalonClient />);
    await waitFor(() =>
      expect(
        (screen.getByLabelText('Téléphone du salon') as HTMLInputElement).value.replace(
          /\D/g,
          '',
        ),
      ).toBe('2250700000000'),
    );

    fireEvent.change(screen.getByPlaceholderText('Ex : Salon Excellence Yopougon'), {
      target: { value: 'Salon Trois' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Créer le salon' }));

    await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro'));
    const add = calls.find(
      (c) => c.url === '/api/pro/salons' && c.body !== undefined,
    );
    expect(add?.body).toMatchObject({ phoneNumber: '+2250700000000' });
  });

  it('a short prefilled account phone is flagged under the field that SHOWS it', async () => {
    // docs/design/phone-national-length.md §1.5: no such number is stored
    // today, but one would be named — not hidden behind an empty-looking field.
    ME.account.phoneNumber = '+2250700000';
    try {
      const calls = mockFetch({ addStatus: 201, addBody: {} });
      render(<AddSalonClient />);
      await waitFor(() =>
        expect(
          (screen.getByLabelText('Téléphone du salon') as HTMLInputElement).value.replace(
            /\D/g,
            '',
          ),
        ).toBe('2250700000'),
      );
      fireEvent.change(screen.getByPlaceholderText('Ex : Salon Excellence Yopougon'), {
        target: { value: 'Salon Trois' },
      });
      fireEvent.click(screen.getByRole('button', { name: 'Créer le salon' }));

      await screen.findByText('Le numéro doit comporter 10 chiffres après +225.');
      expect(screen.getByLabelText('Téléphone du salon')).toHaveAttribute(
        'aria-invalid',
        'true',
      );
      expect(calls.some((c) => c.url === '/api/pro/salons' && c.body)).toBe(false);
    } finally {
      ME.account.phoneNumber = '+2250700000000';
    }
  });

  it('a picked area rides the create as areaId (multi-pays MP3)', async () => {
    const calls = mockFetch({
      addStatus: 201,
      addBody: {
        salon: {
          salonId: 'p4',
          salonName: 'Salon Trois',
          role: 'owner',
          salonStatus: 'draft',
          verified: true,
        },
      },
    });
    render(<AddSalonClient />);
    await screen.findByText('Ajouter un salon');

    fireEvent.change(screen.getByPlaceholderText('Ex : Salon Excellence Yopougon'), {
      target: { value: 'Salon Trois' },
    });
    // The picker loads the tree, then the commune select appears.
    const areaSelect = await screen.findByLabelText('Commune');
    fireEvent.change(areaSelect, { target: { value: 'marcory' } });
    fireEvent.click(screen.getByRole('button', { name: 'Créer le salon' }));

    await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro'));
    const add = calls.find(
      (c) => c.url === '/api/pro/salons' && c.body !== undefined,
    );
    expect(add?.body).toMatchObject({ areaId: 'marcory' });
  });
});
