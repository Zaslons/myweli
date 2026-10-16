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

import { AcompteClient } from '../components/pro/AcompteClient';
import { resetLocalitiesClientCache } from '../lib/use-localities';
import { fixtureTree } from './localities.test';

/// Pro « Acompte » — docs/design/acompte-off-parity.md. A failed load showed
/// a blank form (D3) that a save would write over the real policy, and a
/// dropped connection left the page loading for ever; deposits off sent
/// `null` / `0` and erased the operator and the percentage (D1).

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

/// The ErrorState, under the page's own h1 — and nothing a save could
/// overwrite the policy from.
async function expectLoadError() {
  await screen.findByRole('button', { name: 'Réessayer' });
  expect(screen.getByRole('heading', { level: 1, name: 'Acompte' })).toBeInTheDocument();
  expect(screen.getByRole('alert')).toHaveTextContent(
    'Une erreur est survenue. Réessayez.',
  );
  expect(screen.queryByLabelText('Exiger un acompte')).toBeNull();
  expect(screen.queryByRole('button', { name: 'Enregistrer' })).toBeNull();
}

describe('AcompteClient — a failed load is an error, never a blank form', () => {
  for (const status of [403, 500, 502]) {
    it(`the policy GET answers ${status} → ErrorState, no form, no « Enregistrer »`, async () => {
      mockFetch({ policy: [{ status }] });
      render(<AcompteClient />);
      await expectLoadError();
      expect(sent).toHaveLength(0);
    });
  }

  it('the policy fetch throws (no network) → ErrorState, not a spinner for ever', async () => {
    mockFetch({ policy: ['throw'] });
    render(<AcompteClient />);
    await expectLoadError();
  });

  it('the salon fetch throws → ErrorState', async () => {
    mockFetch({ me: ['throw'] });
    render(<AcompteClient />);
    await expectLoadError();
  });

  it('« Réessayer » loads again — and the policy it gets is the one shown', async () => {
    mockFetch({ policy: [{ status: 500 }] });
    render(<AcompteClient />);
    await expectLoadError();

    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    expect(
      await screen.findByLabelText('Pourcentage de l’acompte (%)'),
    ).toHaveValue('45');
    expect(screen.getByLabelText('Exiger un acompte')).toBeChecked();
    expect(screen.getByRole('button', { name: 'Enregistrer' })).toBeInTheDocument();
  });
});

describe('AcompteClient — deposits off keep the operator and the percentage', () => {
  const OFF = { ...POLICY, depositRequired: false };

  it('saved while off: the operator and the percentage held are sent', async () => {
    mockFetch({ policy: [{ status: 200, body: OFF }] });
    render(<AcompteClient />);
    fireEvent.click(await screen.findByRole('button', { name: 'Enregistrer' }));

    await waitFor(() => expect(sent).toHaveLength(1));
    expect(sent[0].body.policy).toEqual(OFF);
  });

  it('a hidden percentage the salon cannot see is wrong: the one loaded is sent', async () => {
    mockFetch({ policy: [{ status: 200, body: OFF }] });
    render(<AcompteClient />);
    const toggle = await screen.findByLabelText('Exiger un acompte');
    fireEvent.click(toggle); // on
    fireEvent.change(screen.getByLabelText('Pourcentage de l’acompte (%)'), {
      target: { value: 'abc' },
    });
    fireEvent.click(toggle); // off — the field and its fault are hidden
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));

    await waitFor(() => expect(sent).toHaveLength(1));
    expect(sent[0].body.policy).toMatchObject({
      depositRequired: false,
      depositPercentage: 0.45,
      mobileMoneyOperator: 'wave',
    });
  });

  it('…and after a save, the one saved', async () => {
    mockFetch({ policy: [{ status: 200, body: OFF }] });
    render(<AcompteClient />);
    const toggle = await screen.findByLabelText('Exiger un acompte');
    fireEvent.click(toggle); // on
    const percent = screen.getByLabelText('Pourcentage de l’acompte (%)');
    fireEvent.change(percent, { target: { value: '60' } });
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));
    await screen.findByText('Acompte enregistré.');
    expect(sent[0].body.policy).toMatchObject({
      depositRequired: true,
      depositPercentage: 0.6,
    });

    fireEvent.change(percent, { target: { value: 'abc' } });
    fireEvent.click(toggle); // off
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));

    await waitFor(() => expect(sent).toHaveLength(2));
    expect(sent[1].body.policy).toMatchObject({
      depositRequired: false,
      depositPercentage: 0.6,
      mobileMoneyOperator: 'wave',
    });
  });
});

describe('AcompteClient — the fallback is what was loaded or SAVED, nothing else', () => {
  const OFF = { ...POLICY, depositRequired: false };

  it('a refused save leaves it where it was', async () => {
    mockFetch({ policy: [{ status: 200, body: OFF }], put: [{ status: 500 }] });
    render(<AcompteClient />);
    const toggle = await screen.findByLabelText('Exiger un acompte');
    fireEvent.click(toggle); // on
    const percent = screen.getByLabelText('Pourcentage de l’acompte (%)');
    fireEvent.change(percent, { target: { value: '60' } });
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));
    expect(await screen.findByRole('alert')).toHaveTextContent(
      'L’enregistrement a échoué. Réessayez.',
    );

    fireEvent.change(percent, { target: { value: 'abc' } });
    fireEvent.click(toggle); // off
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));
    await waitFor(() => expect(sent).toHaveLength(2));
    // 60 was never stored: the server refused it.
    expect(sent[1].body.policy).toMatchObject({ depositPercentage: 0.45 });
  });

  it('never chosen (a stored 0): the 30 on screen is a proposal, not the fallback', async () => {
    mockFetch({ policy: [{ status: 200, body: { ...OFF, depositPercentage: 0 } }] });
    render(<AcompteClient />);
    const toggle = await screen.findByLabelText('Exiger un acompte');
    fireEvent.click(toggle); // on
    const percent = screen.getByLabelText('Pourcentage de l’acompte (%)');
    expect(percent).toHaveValue('30');
    fireEvent.change(percent, { target: { value: 'abc' } });
    fireEvent.click(toggle); // off
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));
    await waitFor(() => expect(sent).toHaveLength(1));
    expect(sent[0].body.policy).toMatchObject({ depositPercentage: 0 });
  });
});

describe('AcompteClient — a save with no network', () => {
  it('says it failed and gives « Enregistrer » back — never a button disabled for ever', async () => {
    mockFetch({ put: ['throw'] });
    render(<AcompteClient />);
    fireEvent.click(await screen.findByRole('button', { name: 'Enregistrer' }));
    expect(await screen.findByRole('alert')).toHaveTextContent(
      'L’enregistrement a échoué. Réessayez.',
    );
    const save = screen.getByRole('button', { name: 'Enregistrer' });
    expect(save).toBeEnabled();

    fireEvent.click(save); // the network is back
    expect(await screen.findByText('Acompte enregistré.')).toBeInTheDocument();
    expect(sent).toHaveLength(2);
  });

  it('a failed save after a successful one: only the failure is said', async () => {
    mockFetch({ put: [{ status: 200, body: {} }, 'throw'] });
    render(<AcompteClient />);
    const save = await screen.findByRole('button', { name: 'Enregistrer' });
    fireEvent.click(save);
    expect(await screen.findByText('Acompte enregistré.')).toBeInTheDocument();

    fireEvent.click(save); // the network drops
    expect(await screen.findByRole('alert')).toHaveTextContent(
      'L’enregistrement a échoué. Réessayez.',
    );
    expect(screen.queryByText('Acompte enregistré.')).toBeNull();
  });
});
