import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const routerMock = { replace: vi.fn(), push: vi.fn() };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  useSearchParams: () => new URLSearchParams(),
}));

import { LoginOptions } from '../components/auth/LoginOptions';
import { ProLoginOptions } from '../components/pro/ProLoginOptions';
import { ProRegisterClient } from '../components/pro/ProRegisterClient';
import { codeRefusal, sendRefusal } from '../lib/auth/otp-failure';
import { resetLocalitiesClientCache } from '../lib/use-localities';
import { fixtureTree } from './localities.test';

/// docs/design/web-client-polish.md §2.1 (B5.1, Q1) — the sign-in says what
/// happened. Before: every refusal of a code that was not « compte
/// suspendu » (or, Pro, « aucun compte ») was « Code incorrect ou expiré. »
/// under the field — a rate limit, an outage, a broken answer; and every
/// refused « send me a code » was « E-mail invalide ou envoi impossible. ».
/// Now each code keeps the app's own sentence under the field, and what is
/// not the code's fault is said under the form.

const OFFLINE = 'Pas de connexion. Réessayez.';
const GENERIC = 'Une erreur est survenue. Réessayez.';
const TOO_MANY = 'Trop de tentatives. Réessayez plus tard.';
const TOO_MANY_CODES = 'Trop de demandes de code. Réessayez plus tard.';
const BAD_EMAIL = 'Saisissez une adresse e-mail valide.';

/// What the code's refusals say, under the field (the app's words).
const UNDER_THE_CODE: [number, string, string][] = [
  [400, 'otp_invalid', 'Code incorrect.'],
  [400, 'invalid_input', 'Code incorrect.'],
  [400, 'otp_expired', 'Code expiré. Demandez un nouveau code.'],
  [400, 'otp_none', 'Aucun code actif. Demandez un nouveau code.'],
  [400, 'otp_locked', 'Trop de tentatives. Demandez un nouveau code.'],
];
/// What is not the code's fault, under the form.
const UNDER_THE_FORM: [number | 'throw', string, string][] = [
  [429, 'rate_limited', TOO_MANY],
  [500, 'internal_error', GENERIC],
  [502, 'login_failed', GENERIC],
  [503, 'storage_unavailable', GENERIC],
  ['throw', '', OFFLINE],
];
/// « Send me a code »: the e-mail's fault, or the form's.
const SEND_REFUSALS: [number | 'throw', string, 'email' | 'form', string][] = [
  [400, 'invalid_email', 'email', BAD_EMAIL],
  [429, 'otp_resend_limit', 'form', TOO_MANY_CODES],
  [429, 'rate_limited', 'form', TOO_MANY],
  [500, 'internal_error', 'form', GENERIC],
  ['throw', '', 'form', OFFLINE],
];

type Answer = { status: number; body: unknown } | 'throw';

function mockFetch(routes: Record<string, Answer>) {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      if (url === '/api/localities') {
        return new Response(JSON.stringify(fixtureTree), { status: 200 });
      }
      const a = routes[url];
      if (!a) return new Response('{}', { status: 404 });
      if (a === 'throw') throw new TypeError('Failed to fetch');
      return new Response(JSON.stringify(a.body), { status: a.status });
    }),
  );
}

const answer = (status: number | 'throw', error: string): Answer =>
  status === 'throw' ? 'throw' : { status, body: { error } };

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  resetLocalitiesClientCache();
});

/// Under the field: tied to it, and said nowhere else.
function expectUnderField(field: HTMLElement, sentence: string) {
  expect(field).toHaveAttribute('aria-invalid', 'true');
  const id = field.getAttribute('aria-describedby')!.split(' ')[0];
  expect(document.getElementById(id)!.textContent).toBe(sentence);
  expect(screen.getAllByText(sentence)).toHaveLength(1);
}

/// Under the form: announced, and the field is not accused.
function expectUnderForm(field: HTMLElement, sentence: string) {
  const said = screen.getByText(sentence);
  expect(said.closest('[role="alert"]')).not.toBeNull();
  expect(field).not.toHaveAttribute('aria-invalid');
}

describe('the table (lib/auth/otp-failure.ts)', () => {
  it('each code refusal: where, and what', () => {
    for (const [status, error, sentence] of UNDER_THE_CODE) {
      expect(codeRefusal({ status, error })).toEqual({ field: 'code', message: sentence });
    }
    for (const [status, error, sentence] of UNDER_THE_FORM) {
      expect(codeRefusal({ status: status === 'throw' ? 0 : status, error })).toEqual({
        field: null,
        message: sentence,
      });
    }
    expect(codeRefusal({ status: 403, error: 'account_suspended' })).toEqual({
      field: null,
      message: 'Compte suspendu.',
    });
    // An unknown code is never blamed on the field.
    expect(codeRefusal({ status: 400, error: 'something_new' })).toEqual({
      field: null,
      message: GENERIC,
    });
  });

  it('each send refusal: where, and what', () => {
    for (const [status, error, where, sentence] of SEND_REFUSALS) {
      expect(sendRefusal({ status: status === 'throw' ? 0 : status, error })).toEqual({
        field: where === 'email' ? 'email' : null,
        message: sentence,
      });
    }
  });
});

/// The two sign-ins: the same steps, their own BFF routes.
const SIGN_INS = [
  {
    name: 'the client sign-in',
    base: '/api/auth/email',
    show: () => render(<LoginOptions onSuccess={vi.fn()} />),
  },
  {
    name: 'the salon sign-in',
    base: '/api/pro/auth/email',
    show: () => render(<ProLoginOptions onSuccess={vi.fn()} />),
  },
];

for (const s of SIGN_INS) {
  describe(`${s.name} — « Se connecter »`, () => {
    async function verifyAnswered(a: Answer) {
      mockFetch({
        [`${s.base}/request`]: { status: 202, body: { expiresInSeconds: 300 } },
        [`${s.base}/verify`]: a,
      });
      s.show();
      fireEvent.change(screen.getByLabelText('Votre e-mail'), {
        target: { value: 'awa@salon.ci' },
      });
      fireEvent.click(screen.getByRole('button', { name: 'Continuer avec e-mail' }));
      const code = await screen.findByLabelText('Code à 6 chiffres');
      fireEvent.change(code, { target: { value: '123456' } });
      fireEvent.click(screen.getByRole('button', { name: 'Se connecter' }));
      return code;
    }

    for (const [status, error, sentence] of UNDER_THE_CODE) {
      it(`${status} ${error} → « ${sentence} » under the code`, async () => {
        const code = await verifyAnswered(answer(status, error));
        await screen.findByText(sentence);
        expectUnderField(code, sentence);
      });
    }

    for (const [status, error, sentence] of UNDER_THE_FORM) {
      it(`${status} ${error} → « ${sentence} » under the form — the code is not accused`, async () => {
        const code = await verifyAnswered(answer(status, error));
        await screen.findByText(sentence);
        expectUnderForm(code, sentence);
        expect(screen.queryByText(/Code incorrect/)).toBeNull();
      });
    }
  });

  describe(`${s.name} — « Continuer avec e-mail »`, () => {
    for (const [status, error, where, sentence] of SEND_REFUSALS) {
      it(`${status} ${error} → « ${sentence} » under the ${where === 'email' ? 'e-mail' : 'form'}`, async () => {
        mockFetch({ [`${s.base}/request`]: answer(status, error) });
        s.show();
        const email = screen.getByLabelText('Votre e-mail');
        fireEvent.change(email, { target: { value: 'awa@salon.ci' } });
        fireEvent.click(screen.getByRole('button', { name: 'Continuer avec e-mail' }));
        await screen.findByText(sentence);
        if (where === 'email') expectUnderField(email, sentence);
        else expectUnderForm(email, sentence);
        expect(screen.queryByText(/envoi impossible/)).toBeNull();
      });
    }
  });
}

describe('the salon’s sign-up', () => {
  function fillTheForm() {
    fireEvent.change(screen.getByLabelText('Nom de l’entreprise'), {
      target: { value: 'Salon Awa' },
    });
    fireEvent.change(screen.getByLabelText('Adresse'), {
      target: { value: 'Rue des Jardins, Cocody' },
    });
    fireEvent.change(screen.getByLabelText('Votre e-mail'), {
      target: { value: 'awa@salon.ci' },
    });
    fireEvent.change(screen.getByLabelText('Téléphone du salon'), {
      target: { value: '+2250707123456' },
    });
  }

  async function registerAnswered(a: Answer) {
    mockFetch({
      '/api/pro/auth/email/request': { status: 202, body: { expiresInSeconds: 300 } },
      '/api/pro/auth/register': a,
    });
    render(<ProRegisterClient />);
    fillTheForm();
    fireEvent.click(screen.getByRole('button', { name: 'Recevoir un code' }));
    const code = await screen.findByLabelText('Code à 6 chiffres');
    fireEvent.change(code, { target: { value: '123456' } });
    fireEvent.click(screen.getByRole('button', { name: 'S’inscrire' }));
    return code;
  }

  for (const [status, error, sentence] of UNDER_THE_CODE) {
    it(`« S’inscrire » ${status} ${error} → « ${sentence} » under the code`, async () => {
      const code = await registerAnswered(answer(status, error));
      await screen.findByText(sentence);
      expectUnderField(code, sentence);
    });
  }

  for (const [status, error, sentence] of UNDER_THE_FORM) {
    it(`« S’inscrire » ${status} ${error} → « ${sentence} » under the form`, async () => {
      const code = await registerAnswered(answer(status, error));
      await screen.findByText(sentence);
      expectUnderForm(code, sentence);
    });
  }

  it('CONTROL — « compte existant » and the phone keep their places', async () => {
    const code = await registerAnswered({ status: 409, body: { error: 'provider_exists' } });
    const said = 'Un compte existe déjà pour cette identité. Connectez-vous.';
    await screen.findByText(said);
    expectUnderForm(code, said);
  });

  for (const [status, error, where, sentence] of SEND_REFUSALS) {
    it(`« Recevoir un code » ${status} ${error} → « ${sentence} » under the ${where === 'email' ? 'e-mail' : 'form'}`, async () => {
      mockFetch({ '/api/pro/auth/email/request': answer(status, error) });
      render(<ProRegisterClient />);
      fillTheForm();
      fireEvent.click(screen.getByRole('button', { name: 'Recevoir un code' }));
      await screen.findByText(sentence);
      const email = screen.getByLabelText('Votre e-mail');
      if (where === 'email') expectUnderField(email, sentence);
      else expectUnderForm(email, sentence);
      expect(screen.queryByText('Envoi du code impossible. Réessayez.')).toBeNull();
    });
  }
});
