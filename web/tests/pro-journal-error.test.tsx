import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
// Stable object: the load effect depends on [router].
const routerMock = { replace, push: vi.fn(), refresh: vi.fn() };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));

import { RendezVousClient } from '../components/pro/RendezVousClient';

/// docs/design/web-pro-network-failure.md §4 — « Journée », the default view
/// of /pro/rendez-vous. `loadJournal` set the day on a 200 and did NOTHING
/// otherwise: a 500 or a dropped connection left the skeleton for ever, and a
/// failed change of day left the PREVIOUS day's grid under the new date. The
/// app clears the day and shows « Réessayer » (pro_journal_provider.dart).

type Answer = 'throw' | { status: number };

/// The column each date's grid shows: the grid of a date is recognisable by
/// its « Créer un rendez-vous — <name> » cell.
const artistFor = (date: string) => `Awa ${date}`;

/// Every journal date asked for, in order.
const asked: string[] = [];
/// How the journal answers, per call — running out serves the day.
let answers: Answer[] = [];
/// When set, a journal request answers only once it settles.
let hold: Promise<void> | null = null;

function mockFetch(journal: Answer[]) {
  asked.length = 0;
  answers = [...journal];
  hold = null;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      const u = String(url);
      if (u === '/api/pro/me') {
        return new Response(
          JSON.stringify({
            account: { id: 'acc1', email: 'x@salon.test' },
            provider: {
              id: 'p1',
              name: 'Beauté Divine',
              status: 'active',
              timezone: 'Africa/Abidjan',
              currency: 'XOF',
              services: [],
              artists: [],
            },
          }),
          { status: 200 },
        );
      }
      if (u === '/api/pro/appointments') {
        return new Response(JSON.stringify({ items: [] }), { status: 200 });
      }
      if (u.startsWith('/api/pro/journal?')) {
        const date = new URL(u, 'http://x').searchParams.get('date') ?? '';
        asked.push(date);
        const a = answers.shift();
        if (hold) await hold;
        if (a === 'throw') throw new TypeError('Failed to fetch');
        if (a) return new Response('{"error":"internal"}', { status: a.status });
        return new Response(
          JSON.stringify({
            date,
            hours: { open: '09:00', close: '18:00', breaks: [] },
            artists: [{ id: 'ar1', name: artistFor(date) }],
            appointments: [],
          }),
          { status: 200 },
        );
      }
      return new Response('{}', { status: 404 });
    }),
  );
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
});

const cellOf = (date: string) => `Créer un rendez-vous — ${artistFor(date)}`;

/// The section's error state — under the page's own h1, which stays.
async function expectJournalError() {
  expect(await screen.findByRole('button', { name: 'Réessayer' })).toBeInTheDocument();
  expect(screen.getByRole('heading', { level: 1, name: 'Rendez-vous' })).toBeInTheDocument();
  expect(screen.getByRole('alert')).toHaveTextContent('Une erreur est survenue. Réessayez.');
}

describe('Rendez-vous — Journée: a day that fails to load is an error, never a skeleton for ever', () => {
  for (const [what, answer] of [
    ['a 500', { status: 500 }],
    ['a dropped connection', 'throw'],
  ] as const) {
    it(`${what} → the error state; « Réessayer » loads the day`, async () => {
      mockFetch([answer]);
      render(<RendezVousClient />);
      await expectJournalError();
      const day = asked[0];
      expect(screen.queryByRole('button', { name: cellOf(day) })).toBeNull();

      fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
      expect(await screen.findByRole('button', { name: cellOf(day) })).toBeInTheDocument();
      expect(screen.queryByRole('alert')).toBeNull();
      expect(asked).toEqual([day, day]);
    });
  }

  it('a failed change of day does not leave the previous day’s grid under the new date', async () => {
    mockFetch([]);
    render(<RendezVousClient />);
    const first = await screen.findByRole('button', { name: /^Créer un rendez-vous — / });
    const day1 = asked[0];
    expect(first).toHaveAccessibleName(cellOf(day1));

    answers = ['throw'];
    fireEvent.click(screen.getByRole('button', { name: 'Jour suivant' }));
    await expectJournalError();
    const day2 = asked[1];
    expect(day2).not.toBe(day1);
    expect(screen.getByLabelText('Date')).toHaveValue(day2);
    expect(screen.queryByRole('button', { name: cellOf(day1) })).toBeNull();

    // « Réessayer » asks for the day ON SCREEN, not today — and while it
    // loads, the skeleton: never the previous day's grid back for a moment.
    let release!: () => void;
    hold = new Promise<void>((r) => {
      release = r;
    });
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    await waitFor(() => expect(asked).toEqual([day1, day2, day2]));
    expect(screen.queryByRole('alert')).toBeNull();
    expect(screen.queryByRole('button', { name: cellOf(day1) })).toBeNull();

    release();
    expect(await screen.findByRole('button', { name: cellOf(day2) })).toBeInTheDocument();
  });
});
