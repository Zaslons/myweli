import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
// Stable object: the load effect depends on [router].
const routerMock = { replace };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));

import { AcompteClient } from '../components/pro/AcompteClient';
import { resetLocalitiesClientCache } from '../lib/use-localities';
import { fixtureTree } from './localities.test';

/// docs/design/web-pro-deposit-app-rules.md — the app's deposit rules and
/// explanations on the web (owner decision 2026-10-20): the slider, the
/// example, « MyWeli ne le traite pas », the cancellation policy and its three
/// choices. A value saved before (1–100 %, 0–720 h) is shown as it is.

const PROVIDER = {
  id: 'p1',
  name: 'Beauté Divine',
  status: 'active',
  countryCode: 'CI',
  category: 'salon',
};

const POLICY = {
  depositRequired: true,
  depositPercentage: 0.45,
  cancellationWindowHours: 24,
  mobileMoneyOperator: 'wave',
  mobileMoneyNumber: '+2250700000000',
};

/// One answer to a GET: a status (200 serves `body`), or a dropped connection.
type Answer = { status: number; body?: unknown } | 'throw';

/// Every mutation the page sends, in order.
const sent: { url: string; method: string; body: Record<string, unknown> }[] = [];

/// `me` / `policy`: the answers to GET /api/pro/me and the Acompte GET, in
/// order — running out serves the salon and [POLICY]. `put`: the answers to
/// the saves, in order — running out is a 200.
function mockFetch({
  me = [],
  policy = [],
  put = [],
}: { me?: Answer[]; policy?: Answer[]; put?: Answer[] } = {}) {
  sent.length = 0;
  const meAnswers = [...me];
  const policyAnswers = [...policy];
  const putAnswers = [...put];
  const answer = (a: Answer | undefined, fallback: unknown) => {
    if (a === 'throw') throw new TypeError('Failed to fetch');
    if (!a) return new Response(JSON.stringify(fallback), { status: 200 });
    return new Response(JSON.stringify(a.body ?? { error: 'internal' }), {
      status: a.status,
    });
  };
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const method = init?.method ?? 'GET';
      if (method !== 'GET') {
        sent.push({ url, method, body: JSON.parse(String(init?.body ?? '{}')) });
        return answer(putAnswers.shift(), {});
      }
      if (url === '/api/pro/me') {
        return answer(meAnswers.shift(), {
          account: { id: 'acc1', verificationStatus: 'verified' },
          provider: PROVIDER,
        });
      }
      if (String(url).startsWith('/api/pro/acompte')) {
        return answer(policyAnswers.shift(), POLICY);
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

const slider = () => screen.getByRole('slider', { name: 'Pourcentage de l’acompte' });
const save = () => fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));

describe('AcompteClient — the app’s rules', () => {
  it('a slider 5–80 % by 5, its value beside it — no free field any more', async () => {
    mockFetch();
    render(<AcompteClient />);
    await screen.findByText('Limite les rendez-vous manqués');
    expect(slider()).toHaveAttribute('min', '5');
    expect(slider()).toHaveAttribute('max', '80');
    expect(slider()).toHaveAttribute('step', '5');
    expect(slider()).toHaveValue('45');
    expect(slider()).toHaveAttribute('aria-valuetext', '45 %');
    expect(screen.getByText('45 %')).toBeInTheDocument();
    expect(screen.queryByRole('textbox', { name: /Pourcentage/ })).toBeNull();
    expect(screen.queryByRole('textbox', { name: /annulation/ })).toBeNull();
  });

  it('the example follows the slider, and the save sends it', async () => {
    mockFetch();
    render(<AcompteClient />);
    await screen.findByText('Exemple sur une prestation de 20 000 FCFA');
    const rows = () => screen.getByTestId('deposit-example').textContent ?? '';
    expect(rows()).toMatch(/Acompte sur votre Mobile Money\s*9\s?000 FCFA/);
    expect(rows()).toMatch(/Solde au salon\s*11\s?000 FCFA/);
    fireEvent.change(slider(), { target: { value: '30' } });
    expect(screen.getByText('30 %')).toBeInTheDocument();
    expect(rows()).toMatch(/6\s?000 FCFA/);
    expect(rows()).toMatch(/14\s?000 FCFA/);
    save();
    await waitFor(() => expect(sent).toHaveLength(1));
    expect(sent[0].body.policy).toMatchObject({ depositPercentage: 0.3 });
  });

  it('the two explanations of the app', async () => {
    mockFetch();
    render(<AcompteClient />);
    expect(await screen.findByText('Recevoir l’acompte')).toBeInTheDocument();
    expect(
      screen.getByText(
        'Le client envoie l’acompte directement sur ce compte Mobile Money. MyWeli ne le traite pas.',
      ),
    ).toBeInTheDocument();
    expect(screen.getByText('Politique d’annulation')).toBeInTheDocument();
    expect(
      screen.getByText(
        'Au-delà de ce délai avant le rendez-vous, le client peut annuler et garder son acompte ; en deçà, l’acompte n’est pas remboursé.',
      ),
    ).toBeInTheDocument();
  });

  it('the delay is one of 12 / 24 / 48 h — 48 h is sent', async () => {
    mockFetch();
    render(<AcompteClient />);
    const group = await screen.findByRole('radiogroup', { name: 'Politique d’annulation' });
    const choices = within(group).getAllByRole('radio');
    expect(choices.map((c) => c.closest('label')?.textContent)).toEqual(['12 h', '24 h', '48 h']);
    expect(within(group).getByRole('radio', { name: '24 h' })).toBeChecked();
    fireEvent.click(within(group).getByRole('radio', { name: '48 h' }));
    save();
    await waitFor(() => expect(sent).toHaveLength(1));
    expect(sent[0].body.policy).toMatchObject({ cancellationWindowHours: 48 });
  });

  it('a delay from before (72 h) is a fourth choice, checked — and kept by a save', async () => {
    mockFetch({ policy: [{ status: 200, body: { ...POLICY, cancellationWindowHours: 72 } }] });
    render(<AcompteClient />);
    const group = await screen.findByRole('radiogroup', { name: 'Politique d’annulation' });
    expect(within(group).getByRole('radio', { name: '72 h' })).toBeChecked();
    save();
    await waitFor(() => expect(sent).toHaveLength(1));
    expect(sent[0].body.policy).toMatchObject({ cancellationWindowHours: 72 });
  });

  it('a percentage from before (100 %) is shown as it is, the thumb at its end — and kept by a save', async () => {
    mockFetch({ policy: [{ status: 200, body: { ...POLICY, depositPercentage: 1 } }] });
    render(<AcompteClient />);
    await screen.findByText('100 %');
    expect(slider()).toHaveValue('80');
    expect(slider()).toHaveAttribute('aria-valuetext', '100 %');
    save();
    await waitFor(() => expect(sent).toHaveLength(1));
    expect(sent[0].body.policy).toMatchObject({ depositPercentage: 1 });
  });

  it('…until the slider is moved', async () => {
    mockFetch({ policy: [{ status: 200, body: { ...POLICY, depositPercentage: 1 } }] });
    render(<AcompteClient />);
    await screen.findByText('100 %');
    fireEvent.change(slider(), { target: { value: '75' } });
    expect(screen.getByText('75 %')).toBeInTheDocument();
    save();
    await waitFor(() => expect(sent).toHaveLength(1));
    expect(sent[0].body.policy).toMatchObject({ depositPercentage: 0.75 });
  });
});

/// docs/design/backend-integrity-batch6.md §2.5 (B6.5, decision 19): one range
/// on the server too, and an operator removed from the catalogue said where it
/// belongs — never a bar saying « L’enregistrement a échoué ».
describe('AcompteClient — the server’s range and catalogue', () => {
  const PERCENT = 'Choisissez un pourcentage entre 5 et 80 %.';
  const OPERATOR = 'Cet opérateur n’est plus proposé. Choisissez-en un autre.';
  const operator = () => screen.getByRole('combobox', { name: 'Opérateur Mobile Money' });

  function describedText(el: HTMLElement): string {
    const id = el.getAttribute('aria-describedby') ?? '';
    return document.getElementById(id)?.textContent ?? '';
  }

  it('invalid_percentage → under the slider, tied to it', async () => {
    mockFetch({ put: [{ status: 400, body: { error: 'invalid_percentage' } }] });
    render(<AcompteClient />);
    await screen.findByText('Limite les rendez-vous manqués');
    save();
    await screen.findByText(PERCENT);
    expect(slider()).toHaveAttribute('aria-invalid', 'true');
    expect(describedText(slider())).toBe(PERCENT);
    expect(screen.queryByText('L’enregistrement a échoué. Réessayez.')).toBeNull();

    // Moving the slider takes the fault away.
    fireEvent.change(slider(), { target: { value: '30' } });
    expect(screen.queryByText(PERCENT)).toBeNull();
    expect(slider()).not.toHaveAttribute('aria-invalid');
  });

  it('operator_unavailable → under the operator, tied to it', async () => {
    mockFetch({ put: [{ status: 400, body: { error: 'operator_unavailable' } }] });
    render(<AcompteClient />);
    await screen.findByText('Limite les rendez-vous manqués');
    await waitFor(() => expect(operator()).toBeEnabled());
    save();
    await screen.findByText(OPERATOR);
    expect(operator()).toHaveAttribute('aria-invalid', 'true');
    expect(describedText(operator())).toBe(OPERATOR);
    expect(screen.queryByText('L’enregistrement a échoué. Réessayez.')).toBeNull();

    fireEvent.change(operator(), { target: { value: 'orange' } });
    expect(screen.queryByText(OPERATOR)).toBeNull();
  });

  it('a value saved before the range (0,4 %) is saved as it is — never '
    + '« Pourcentage invalide (1–100 %) »', async () => {
    mockFetch({ policy: [{ status: 200, body: { ...POLICY, depositPercentage: 0.004 } }] });
    render(<AcompteClient />);
    await screen.findByText('0,4 %');
    save();
    await waitFor(() => expect(sent).toHaveLength(1));
    expect(sent[0].body.policy).toMatchObject({ depositPercentage: 0.004 });
    expect(screen.queryByText(/Pourcentage invalide/)).toBeNull();
  });
});

