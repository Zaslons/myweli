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

const POLICY_ON = {
  depositRequired: true,
  depositPercentage: 0.3,
  cancellationWindowHours: 24,
  mobileMoneyOperator: 'wave',
  mobileMoneyNumber: '+2250700000000',
};

/// `refusals`: the server's answer to each mutation, in order — `null` (or
/// running out) is a 200. `policy`: what the Acompte GET returns.
function mockFetch({
  refusals = [],
  policy = POLICY_ON,
}: {
  refusals?: ({ status: number; error: string } | null)[];
  policy?: Record<string, unknown>;
} = {}) {
  sent.length = 0;
  const answers = [...refusals];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const method = init?.method ?? 'GET';
      if (method !== 'GET') {
        sent.push({ url, method, body: JSON.parse(String(init?.body ?? '{}')) });
        const refusal = answers.shift();
        return refusal
          ? new Response(JSON.stringify({ error: refusal.error }), {
              status: refusal.status,
            })
          : new Response('{}', { status: 200 });
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
        return new Response(JSON.stringify(policy), { status: 200 });
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

/// docs/design/phone-leftovers.md §2 — the server now says WHICH number it
/// refused: `invalid_phone` (Téléphone, Numéro Mobile Money) and
/// `invalid_whatsapp` (the profile's second phone field). Both used to be
/// `invalid_input`, which the pages could only answer with « L’enregistrement
/// a échoué. Réessayez. » — a retry that cannot succeed, nowhere near the field.
const INVALID = 'Saisissez un numéro de téléphone valide.';
const FAILED = 'L’enregistrement a échoué. Réessayez.';

describe('the server’s phone codes land under their fields', () => {
  it('Profil — invalid_phone sits under « Téléphone », WhatsApp untouched', async () => {
    mockFetch({ refusals: [{ status: 400, error: 'invalid_phone' }] });
    render(<ProfilClient />);
    const phone = await screen.findByLabelText('Téléphone');
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));

    await screen.findByText(INVALID);
    expectFieldFault(phone, INVALID);
    expect(screen.getByLabelText('WhatsApp (optionnel)')).not.toHaveAttribute(
      'aria-invalid',
    );
    expect(screen.queryByText(FAILED)).toBeNull();
    expect(sent).toHaveLength(1);
  });

  it('Profil — invalid_whatsapp sits under « WhatsApp », Téléphone untouched', async () => {
    mockFetch({ refusals: [{ status: 400, error: 'invalid_whatsapp' }] });
    render(<ProfilClient />);
    const whatsapp = await screen.findByLabelText('WhatsApp (optionnel)');
    fireEvent.change(whatsapp, { target: { value: '+2250505123456' } });
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));

    await screen.findByText(INVALID);
    expectFieldFault(whatsapp, INVALID);
    expect(screen.getByLabelText('Téléphone')).not.toHaveAttribute('aria-invalid');
    expect(screen.queryByText(FAILED)).toBeNull();
  });

  it('Profil — any other refusal keeps its form-level line', async () => {
    mockFetch({ refusals: [{ status: 400, error: 'invalid_input' }] });
    render(<ProfilClient />);
    const phone = await screen.findByLabelText('Téléphone');
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));

    await screen.findByText(FAILED);
    expect(phone).not.toHaveAttribute('aria-invalid');
  });

  it('Acompte — invalid_phone sits under « Numéro Mobile Money »', async () => {
    mockFetch({ refusals: [{ status: 400, error: 'invalid_phone' }] });
    render(<AcompteClient />);
    const number = await screen.findByLabelText('Numéro Mobile Money');
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));

    await screen.findByText(INVALID);
    expectFieldFault(number, INVALID);
    expect(screen.queryByText(FAILED)).toBeNull();
  });
});

/// docs/design/phone-leftovers.md §6 — deposits OFF. The web sent
/// `mobileMoneyNumber: null` whenever the switch was off: saving the window
/// hours ERASED the salon's number; the app keeps it (parity gap §1.5). The
/// number is now checked when not empty and sent whatever the switch says.
/// The card is hidden while off — so a refusal reveals the field, to give the
/// message a place (the app's `_showNumberWhileOff`), and it goes again once
/// fixed and saved, or as soon as the switch moves.
describe('AcompteClient — deposits off keep the Mobile Money number', () => {
  const OFF = {
    ...POLICY_ON,
    depositRequired: false,
    depositPercentage: 0,
    mobileMoneyNumber: '+2250707123456',
  };

  async function renderOff(
    policy: Record<string, unknown> = OFF,
    refusals: { status: number; error: string }[] = [],
  ) {
    mockFetch({ policy, refusals });
    render(<AcompteClient />);
    await screen.findByLabelText('Exiger un acompte');
    // The switch's card is hidden: no number field while off.
    expect(screen.queryByLabelText('Numéro Mobile Money')).toBeNull();
  }

  it('the stored number is sent, not erased — the field stays hidden', async () => {
    await renderOff();
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));

    await waitFor(() => expect(sent).toHaveLength(1));
    expect(sent[0].body.policy).toMatchObject({
      depositRequired: false,
      mobileMoneyNumber: '+2250707123456',
    });
    await screen.findByText('Acompte enregistré.');
    expect(screen.queryByLabelText('Numéro Mobile Money')).toBeNull();
  });

  it('no stored number is sent as null', async () => {
    await renderOff({ ...OFF, mobileMoneyNumber: null });
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));

    await waitFor(() => expect(sent).toHaveLength(1));
    expect(sent[0].body.policy).toMatchObject({ mobileMoneyNumber: null });
  });

  it('a server invalid_phone reveals the field with the message; a successful save hides it', async () => {
    await renderOff(OFF, [{ status: 400, error: 'invalid_phone' }]);
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));

    const number = await screen.findByLabelText('Numéro Mobile Money');
    expectFieldFault(number, INVALID);
    expect(screen.queryByText(FAILED)).toBeNull();

    // Fixed and saved: the policy is off, so is the card again.
    fireEvent.change(number, { target: { value: '+2250707123457' } });
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));
    await waitFor(() => expect(sent).toHaveLength(2));
    expect(sent[1].body.policy).toMatchObject({
      depositRequired: false,
      mobileMoneyNumber: '+2250707123457',
    });
    await waitFor(() =>
      expect(screen.queryByLabelText('Numéro Mobile Money')).toBeNull(),
    );
  });

  it('the revealed field goes as soon as the switch moves', async () => {
    await renderOff(OFF, [{ status: 400, error: 'invalid_phone' }]);
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));
    await screen.findByLabelText('Numéro Mobile Money');

    const toggle = screen.getByLabelText('Exiger un acompte');
    fireEvent.click(toggle); // on — the switch's own card
    expect(screen.getByLabelText('Numéro Mobile Money')).toBeInTheDocument();
    fireEvent.click(toggle); // off again — one saved policy, one layout
    expect(screen.queryByLabelText('Numéro Mobile Money')).toBeNull();
  });

  it('a stored number the rule refuses is revealed with its fault — nothing is sent', async () => {
    await renderOff({ ...OFF, mobileMoneyNumber: '+2250700000' });
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));

    const number = await screen.findByLabelText('Numéro Mobile Money');
    expectFieldFault(number, TEN);
    expect(sent).toHaveLength(0);
  });
});
