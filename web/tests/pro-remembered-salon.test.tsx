import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const routerMock = { replace: vi.fn() };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));

import { ProLoginOptions } from '../components/pro/ProLoginOptions';
import { ProRegisterClient } from '../components/pro/ProRegisterClient';
import type { KeyStore } from '../lib/pro/browser-push';
import {
  forgetSalon,
  rememberSalon,
  rememberedSalon,
} from '../lib/pro/remembered-salon';
import { signOutPro } from '../lib/pro/sign-out';
import { resetLocalitiesClientCache } from '../lib/use-localities';
import { fixtureTree } from './localities.test';

/// docs/design/web-pro-truthful-failure.md §2.4 (B4.4, decision 14) — the
/// salon this browser last acted in, kept so that « Votre accès à {salon} a
/// été retiré. » still names it after a reload, as the app does. Its public
/// name and id only; gone at every sign-out AND every sign-in, so it can only
/// ever name a salon of the account now signed in.

const SALON = { id: 'p1', name: 'Beauté Divine' };

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  routerMock.replace.mockReset();
  resetLocalitiesClientCache();
  window.localStorage.clear();
});

describe('the remembered salon', () => {
  it('kept, read back, forgotten', () => {
    expect(rememberedSalon()).toBeNull();
    rememberSalon(SALON);
    expect(rememberedSalon()).toEqual(SALON);
    forgetSalon();
    expect(rememberedSalon()).toBeNull();
  });

  it('nothing but the id and the public name is kept', () => {
    rememberSalon({ ...SALON, ...{ email: 'salon@example.com' } } as typeof SALON);
    expect(JSON.parse(window.localStorage.getItem('myweli_pro_last_salon')!)).toEqual(SALON);
  });

  it('a salon without a name replaces the one kept before — never a name for '
    + 'the wrong salon', () => {
    rememberSalon(SALON);
    rememberSalon({ id: 'p2', name: '' });
    expect(rememberedSalon()).toBeNull();
    expect(window.localStorage.getItem('myweli_pro_last_salon')).toBeNull();
  });

  it('what is not a salon reads as nothing — never a name made of it', () => {
    for (const stored of ['{', '"Beauté Divine"', '{"id":"p1"}', '{"id":1,"name":2}', 'null']) {
      window.localStorage.setItem('myweli_pro_last_salon', stored);
      expect(rememberedSalon()).toBeNull();
    }
  });

  it('a browser that keeps nothing (private window, blocked site data) breaks nothing', () => {
    const blocked: KeyStore = {
      get: () => {
        throw new Error('SecurityError');
      },
      set: () => {
        throw new Error('SecurityError');
      },
      remove: () => {
        throw new Error('SecurityError');
      },
    };
    expect(() => rememberSalon(SALON, blocked)).not.toThrow();
    expect(rememberedSalon(blocked)).toBeNull();
    expect(() => forgetSalon(blocked)).not.toThrow();
  });
});

describe('the remembered salon goes at every sign-out and every sign-in', () => {
  const answer = (logout: number) =>
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string) =>
        url === '/api/pro/auth/logout'
          ? new Response('{}', { status: logout })
          : new Response('{}', { status: 404 }),
      ),
    );

  it('a sign-out that lands → forgotten', async () => {
    rememberSalon(SALON);
    answer(200);
    expect(await signOutPro()).toBe('ok');
    expect(rememberedSalon()).toBeNull();
  });

  it('a sign-out that did NOT land (the session still lives) → kept, so a reload still names it', async () => {
    rememberSalon(SALON);
    answer(500);
    expect(await signOutPro()).not.toBe('ok');
    expect(rememberedSalon()).toEqual(SALON);
  });

  it('a sign-in → forgotten, before the dashboard opens', async () => {
    rememberSalon(SALON);
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string) => {
        if (url === '/api/pro/auth/email/request') {
          return new Response(JSON.stringify({ expiresInSeconds: 300 }), { status: 202 });
        }
        if (url === '/api/pro/auth/email/verify') return new Response('{}', { status: 200 });
        return new Response('{}', { status: 404 });
      }),
    );
    const onSuccess = vi.fn(() => {
      expect(rememberedSalon()).toBeNull();
    });
    render(<ProLoginOptions onSuccess={onSuccess} />);
    fireEvent.change(screen.getByLabelText('Votre e-mail'), {
      target: { value: 'gerant@salon.ci' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Continuer avec e-mail' }));
    fireEvent.change(await screen.findByLabelText('Code à 6 chiffres'), {
      target: { value: '123456' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Se connecter' }));

    await waitFor(() => expect(onSuccess).toHaveBeenCalled());
    expect(rememberedSalon()).toBeNull();
  });

  it('a refused sign-in → kept (nobody new signed in)', async () => {
    rememberSalon(SALON);
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string) => {
        if (url === '/api/pro/auth/email/request') {
          return new Response(JSON.stringify({ expiresInSeconds: 300 }), { status: 202 });
        }
        if (url === '/api/pro/auth/email/verify') {
          return new Response(JSON.stringify({ error: 'otp_invalid' }), { status: 400 });
        }
        return new Response('{}', { status: 404 });
      }),
    );
    render(<ProLoginOptions onSuccess={vi.fn()} />);
    fireEvent.change(screen.getByLabelText('Votre e-mail'), {
      target: { value: 'gerant@salon.ci' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Continuer avec e-mail' }));
    fireEvent.change(await screen.findByLabelText('Code à 6 chiffres'), {
      target: { value: '000000' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Se connecter' }));

    await screen.findByText('Code incorrect.');
    expect(rememberedSalon()).toEqual(SALON);
  });

  it('a new salon’s sign-up → forgotten', async () => {
    rememberSalon(SALON);
    const calls: string[] = [];
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string) => {
        calls.push(url);
        if (url === '/api/localities') {
          return new Response(JSON.stringify(fixtureTree), { status: 200 });
        }
        if (url === '/api/pro/auth/email/request') {
          return new Response(JSON.stringify({ expiresInSeconds: 300 }), { status: 202 });
        }
        if (url === '/api/pro/auth/register') return new Response('{}', { status: 201 });
        return new Response('{}', { status: 404 });
      }),
    );
    render(<ProRegisterClient />);
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
    fireEvent.click(screen.getByRole('button', { name: 'Recevoir un code' }));
    fireEvent.change(await screen.findByLabelText('Code à 6 chiffres'), {
      target: { value: '123456' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'S’inscrire' }));

    await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith('/pro'));
    expect(calls).toContain('/api/pro/auth/register');
    expect(rememberedSalon()).toBeNull();
  });
});
