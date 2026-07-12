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

/// Team access R6c — « Ajouter un salon »: validation, the Réseau gate copy
/// (+ CTA), and the happy path (create → select → the draft dashboard).

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
      return new Response('{}', { status: 404 });
    }),
  );
  return calls;
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
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
});
