import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
// Stable object: the load effects depend on [router].
const routerMock = { replace };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));
// MapLibre (LocationPicker) is browser-only — stub the dynamic import out.
vi.mock('next/dynamic', () => ({ default: () => () => null }));

import { AcompteClient } from '../components/pro/AcompteClient';
import { ProfilClient } from '../components/pro/ProfilClient';
import { resetLocalitiesClientCache } from '../lib/use-localities';
import { fixtureTree } from './localities.test';

/// Pro « Profil » (Téléphone, WhatsApp) and « Acompte » (Numéro Mobile Money)
/// — docs/design/phone-national-length.md §2.5. Both copied the generic
/// E.164 regex, which lets 7 digits after +225 through (10 digits after the
/// +), and named the fault in a form-level line. The rule is now the shared
/// one, and the fault sits UNDER its field, tied to it (§14 rule 1, §6).
const TEN = 'Le numéro doit comporter 10 chiffres après +225.';

const PROVIDER = {
  id: 'p1',
  name: 'Beauté Divine',
  status: 'active',
  countryCode: 'CI',
  phoneNumber: '+2250700000000',
  whatsapp: '',
  category: 'salon',
};

/// Every mutation the page sends, in order.
const sent: { url: string; method: string; body: Record<string, unknown> }[] = [];

function mockFetch() {
  sent.length = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const method = init?.method ?? 'GET';
      if (method !== 'GET') {
        sent.push({ url, method, body: JSON.parse(String(init?.body ?? '{}')) });
        return new Response('{}', { status: 200 });
      }
      if (url === '/api/pro/me') {
        return new Response(
          JSON.stringify({
            account: { id: 'acc1', verificationStatus: 'verified' },
            provider: PROVIDER,
          }),
          { status: 200 },
        );
      }
      if (String(url).startsWith('/api/pro/acompte')) {
        return new Response(
          JSON.stringify({
            depositRequired: true,
            depositPercentage: 0.3,
            cancellationWindowHours: 24,
            mobileMoneyOperator: 'wave',
            mobileMoneyNumber: '+2250700000000',
          }),
          { status: 200 },
        );
      }
      if (url === '/api/localities') {
        return new Response(JSON.stringify(fixtureTree), { status: 200 });
      }
      return new Response('{}', { status: 404 });
    }),
  );
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  resetLocalitiesClientCache();
  replace.mockReset();
});

/// The fault is under the field and programmatically tied to it.
function expectFieldFault(input: HTMLElement, message: string) {
  expect(input).toHaveAttribute('aria-invalid', 'true');
  const id = input.getAttribute('aria-describedby');
  expect(id).toBeTruthy();
  expect(document.getElementById(id!)).toHaveTextContent(message);
}

describe('ProfilClient — Téléphone and WhatsApp', () => {
  it('7 digits after +225 are refused under « Téléphone » — nothing is saved', async () => {
    mockFetch();
    render(<ProfilClient />);
    const phone = await screen.findByLabelText('Téléphone');
    fireEvent.change(phone, { target: { value: '+2250700000' } });
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));

    await screen.findByText(TEN);
    expectFieldFault(phone, TEN);
    expect(sent).toHaveLength(0);
  });

  it('WhatsApp is optional but checked once typed, under its own field', async () => {
    mockFetch();
    render(<ProfilClient />);
    const whatsapp = await screen.findByLabelText('WhatsApp (optionnel)');
    fireEvent.change(whatsapp, { target: { value: '+2250505' } });
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));

    await screen.findByText(TEN);
    expectFieldFault(whatsapp, TEN);
    expect(screen.getByLabelText('Téléphone')).not.toHaveAttribute('aria-invalid');
    expect(sent).toHaveLength(0);
  });

  it('spaced numbers are sent bare; a lone « +225 » WhatsApp is cleared', async () => {
    mockFetch();
    render(<ProfilClient />);
    fireEvent.change(await screen.findByLabelText('Téléphone'), {
      target: { value: '+225 07 07 12 34 56' },
    });
    fireEvent.change(screen.getByLabelText('WhatsApp (optionnel)'), {
      target: { value: '+225' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));

    await waitFor(() => expect(sent).toHaveLength(1));
    expect(sent[0].url).toBe('/api/pro/profil');
    expect(sent[0].body.profile).toMatchObject({
      phoneNumber: '+2250707123456',
      whatsapp: null,
    });
  });
});

describe('the +225 prefix is on screen — a local number is the right one', () => {
  // The review's case: a pro types « 07 07 12 34 56 » the usual way. In a
  // bare text input that was refused as « valide » with no hint; the shared
  // PhoneField shows +225, so the local digits complete a correct number
  // (parity with the app — docs/design/phone-national-length.md §12).
  it('an empty WhatsApp opens on +225, and the local digits typed after it are sent as +225…', async () => {
    mockFetch();
    render(<ProfilClient />);
    const whatsapp = (await screen.findByLabelText(
      'WhatsApp (optionnel)',
    )) as HTMLInputElement;
    expect(whatsapp.value.replace(/\s/g, '')).toBe('+225');

    fireEvent.change(whatsapp, {
      target: { value: `${whatsapp.value} 07 07 12 34 56` },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));

    await waitFor(() => expect(sent).toHaveLength(1));
    expect(sent[0].body.profile).toMatchObject({ whatsapp: '+2250707123456' });
  });
});

describe('AcompteClient — Numéro Mobile Money', () => {
  it('7 digits after +225 are refused under the field — nothing is saved', async () => {
    mockFetch();
    render(<AcompteClient />);
    const number = await screen.findByLabelText('Numéro Mobile Money');
    fireEvent.change(number, { target: { value: '+2250700000' } });
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));

    await screen.findByText(TEN);
    expectFieldFault(number, TEN);
    expect(sent).toHaveLength(0);
  });

  it('a spaced number is sent bare', async () => {
    mockFetch();
    render(<AcompteClient />);
    fireEvent.change(await screen.findByLabelText('Numéro Mobile Money'), {
      target: { value: '+225 07 07 12 34 56' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));

    await waitFor(() => expect(sent).toHaveLength(1));
    expect(sent[0].body.policy).toMatchObject({
      mobileMoneyNumber: '+2250707123456',
    });
  });
});
