import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import type { NextRequest } from 'next/server';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
const routerMock = { replace };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
}));

import { DELETE } from '../app/api/pro/account/route';
import { CompteDangerSection } from '../components/pro/CompteDangerSection';
import type { ProProfile } from '../lib/api/pro';
import { DEMO_ACCOUNT_LOCKED_MESSAGE } from '../lib/pro/team';

/// « Compte » on /pro/profil when the server REFUSES the deletion — the
/// shared store-review demo account cannot delete itself (403
/// `demo_account_locked`). The demo credential signs in on the web too, so
/// the dashboard has to say the same sentence as the app, and leave the
/// session alone. Design: docs/design/demo-account-deletion-lock.md §7.2.

const FUTURE_BOOKINGS =
  'Terminez ou annulez vos rendez-vous à venir avant de supprimer votre compte.';
const GENERIC = 'La suppression a échoué. Réessayez.';

const profile = {
  account: { id: 'acc-1', email: 'owner@salon.test' },
  provider: { id: 'p1', name: 'Maison Nala', status: 'draft' },
  membership: { role: 'owner', capabilities: ['profile.manage'] },
} as unknown as ProProfile;

/// The BFF's answer to `DELETE /api/pro/account`.
function serverAnswers(status: number, body?: unknown) {
  const calls: { url: string; method: string }[] = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      calls.push({ url, method: init?.method ?? 'GET' });
      return new Response(body === undefined ? null : JSON.stringify(body), {
        status,
      });
    }),
  );
  return calls;
}

/// The user's three gestures: the entry, the word, the button.
async function confirmDeletion() {
  fireEvent.click(screen.getByText('Supprimer mon compte'));
  fireEvent.change(screen.getByLabelText('Confirmation de suppression'), {
    target: { value: 'SUPPRIMER' },
  });
  fireEvent.click(screen.getByText('Supprimer définitivement'));
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
});

describe('CompteDangerSection — a refused deletion', () => {
  it('the entry is offered, as a real button, before anything is sent', () => {
    const calls = serverAnswers(204);
    render(<CompteDangerSection profile={profile} />);

    const entry = screen.getByRole('button', { name: 'Supprimer mon compte' });
    expect((entry as HTMLButtonElement).disabled).toBe(false);
    expect(calls).toEqual([]);
  });

  it('demo_account_locked → the demo sentence, announced; the page and the session stay', async () => {
    const calls = serverAnswers(403, { error: 'demo_account_locked' });
    render(<CompteDangerSection profile={profile} />);

    await confirmDeletion();

    const alert = await screen.findByRole('alert');
    expect(alert.textContent).toBe(DEMO_ACCOUNT_LOCKED_MESSAGE);
    expect(calls).toEqual([{ url: '/api/pro/account', method: 'DELETE' }]);
    // Not signed out: no navigation, and the confirmation is still open —
    // the user can read the refusal next to the field they just filled.
    expect(replace).not.toHaveBeenCalled();
    expect(screen.getByLabelText('Confirmation de suppression')).toBeTruthy();
    expect(screen.queryByText(FUTURE_BOOKINGS)).toBeNull();
    expect(screen.queryByText(GENERIC)).toBeNull();
  });

  it('the member variant (no export) says the same sentence', async () => {
    serverAnswers(403, { error: 'demo_account_locked' });
    render(<CompteDangerSection profile={profile} exportEnabled={false} />);

    await confirmDeletion();

    expect((await screen.findByRole('alert')).textContent).toBe(
      DEMO_ACCOUNT_LOCKED_MESSAGE,
    );
    expect(replace).not.toHaveBeenCalled();
  });

  it('CONTROL — future_bookings keeps its own sentence', async () => {
    serverAnswers(409, { error: 'future_bookings' });
    render(<CompteDangerSection profile={profile} />);

    await confirmDeletion();

    expect((await screen.findByRole('alert')).textContent).toBe(
      FUTURE_BOOKINGS,
    );
    expect(replace).not.toHaveBeenCalled();
  });

  it.each([
    ['403 forbidden', 403, { error: 'forbidden' }],
    ['500 with no code', 500, {}],
    ['403 with no body', 403, undefined],
  ])('CONTROL — %s is the generic failure, never the demo sentence', async (_label, status, body) => {
    serverAnswers(status as number, body);
    render(<CompteDangerSection profile={profile} />);

    await confirmDeletion();

    expect((await screen.findByRole('alert')).textContent).toBe(GENERIC);
    expect(replace).not.toHaveBeenCalled();
  });

  it('CONTROL — a deletion the server accepts leaves for /pro/connexion', async () => {
    // Without this, « the page stays » above would be true of a section
    // that never navigates.
    serverAnswers(204);
    render(<CompteDangerSection profile={profile} />);

    await confirmDeletion();

    await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro/connexion'));
    expect(screen.queryByRole('alert')).toBeNull();
  });
});

describe('DELETE /api/pro/account (the BFF)', () => {
  function proRequest(): NextRequest {
    const cookies: Record<string, string> = {
      myweli_pro_at: 'access',
      myweli_pro_rt: 'refresh',
    };
    return {
      cookies: {
        get: (k: string) => (cookies[k] ? { value: cookies[k] } : undefined),
      },
    } as unknown as NextRequest;
  }

  function backendAnswers(status: number, body?: unknown) {
    const calls: { url: string; method?: string; auth?: string }[] = [];
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string, init?: RequestInit) => {
        calls.push({
          url: String(url),
          method: init?.method,
          auth: (init?.headers as Record<string, string> | undefined)
            ?.authorization,
        });
        return new Response(
          body === undefined ? null : JSON.stringify(body),
          { status },
        );
      }),
    );
    return calls;
  }

  it('passes the demo refusal through as it came, and leaves the session cookies alone', async () => {
    const calls = backendAnswers(403, { error: 'demo_account_locked' });

    const res = await DELETE(proRequest());

    expect(res.status).toBe(403);
    expect(await res.json()).toEqual({ error: 'demo_account_locked' });
    expect(res.headers.get('set-cookie')).toBeNull();
    expect(calls).toHaveLength(1);
    expect(calls[0].url).toMatch(/\/me\/provider$/);
    expect(calls[0].method).toBe('DELETE');
    expect(calls[0].auth).toBe('Bearer access');
  });

  it('CONTROL — on 204 the pro session cookies are cleared', async () => {
    backendAnswers(204);

    const res = await DELETE(proRequest());

    expect(res.status).toBe(204);
    const cleared = res.headers.get('set-cookie') ?? '';
    expect(cleared).toContain('myweli_pro_at=;');
    expect(cleared).toContain('myweli_pro_rt=;');
  });
});
