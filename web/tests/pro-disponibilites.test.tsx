import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const routerMock = { replace: vi.fn(), push: vi.fn(), refresh: vi.fn() };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));

import { DisponibilitesClient } from '../components/pro/DisponibilitesClient';

/// The FIRST component test for `DisponibilitesClient` (A14d).
///
/// The file had none — only `pro-availability.test.ts`, which tests `toApi` in
/// isolation. That is exactly how the `setBase` staleness below survived: it
/// lives in the component, and nothing rendered the component.
///
/// Stubs `fetch` rather than mocking `lib/api/pro`, matching
/// `catalogue-editor.test.tsx`. A first draft module-mocked the API layer and
/// left a path unstubbed that re-rendered until the vitest worker died.
const AVAILABILITY = {
  providerId: 'p1',
  weeklySchedule: {
    '0': [{ startTime: '09:00', endTime: '17:00', isAvailable: true }],
  },
  // TWO windows on Monday. The second is the « extra » `daysToSchedule`
  // preserves from `base` (it keeps `slice(1)`), and it is the ONLY thing a
  // stale `base.breaks` can lose — a first draft of this file used a single
  // window, so mutating the fix back did not redden it. Row 67, caught by
  // mutating rather than by trusting.
  breaks: {
    '0': [
      { startTime: '12:00', endTime: '13:00' },
      { startTime: '15:00', endTime: '15:30' },
    ],
  },
  blockedDates: [] as string[],
  bufferMinutes: 10,
  bookingHorizonDays: 365,
  minimumNoticeMinutes: 60,
};

/// Every availability body the component PUT, in order.
const sent: Record<string, unknown>[] = [];

function mockFetch() {
  sent.length = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      if (url === '/api/pro/me') {
        return new Response(
          JSON.stringify({
            account: { id: 'acc-1', email: 'x@salon.test' },
            provider: {
              id: 'p1',
              name: 'Beauté Divine',
              status: 'active',
              availability: AVAILABILITY,
            },
          }),
          { status: 200 },
        );
      }
      if (url === '/api/pro/disponibilites') {
        const body = JSON.parse(String(init?.body ?? '{}')) as {
          availability?: Record<string, unknown>;
        };
        sent.push(body.availability ?? {});
        return new Response('{}', { status: 200 });
      }
      return new Response('{}', { status: 404 });
    }),
  );
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe('DisponibilitesClient — the bookable window (A14d)', () => {
  it('saves the horizon and the delay the pro picked', async () => {
    mockFetch();
    render(<DisponibilitesClient />);
    await screen.findByText('Fenêtre de réservation');

    fireEvent.click(screen.getByRole('button', { name: '3 mois' }));
    fireEvent.click(screen.getByRole('button', { name: '12 h' }));
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));

    await waitFor(() => expect(sent).toHaveLength(1));
    expect(sent[0].bookingHorizonDays).toBe(90);
    expect(sent[0].minimumNoticeMinutes).toBe(720);
  });

  it('a SECOND save still carries the window AND the breaks', async () => {
    // **The window must survive a SECOND save**, which is the assertion that
    // matters: `save()` stores its own request object into `base`, so a field
    // that does not ride inside it is read back stale on the next save.
    // Falsifiable — dropping `bookingHorizonDays` from that object reddens
    // both tests with « expected 365 to be 90 ».
    //
    // **The `breaks` assertion below is a characterisation, NOT a gate, and
    // that is a correction worth recording.** `save()` used to merge `breaks`
    // into the request only (`{ ...obj, breaks }`) while storing the un-merged
    // object, which reads like the same staleness. It is not observable:
    // `toApi` returns `{ ...base }`, so the stored object always carries SOME
    // breaks value, and the only thing a stale one costs is the `slice(1)`
    // extras — which no control on this screen can edit, since the break
    // editor writes the FIRST window per day and nothing else. Mutating the
    // fix back leaves this test green, twice over, and it was only by mutating
    // that the claim fell apart. The fix is kept because `base` diverging from
    // the server is worth closing on its own; it is not kept on the strength
    // of a test that cannot see it.
    mockFetch();
    render(<DisponibilitesClient />);
    await screen.findByText('Fenêtre de réservation');

    fireEvent.click(screen.getByRole('button', { name: '3 mois' }));
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));
    await waitFor(() => expect(sent).toHaveLength(1));

    fireEvent.click(screen.getByRole('button', { name: '12 h' }));
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));
    await waitFor(() => expect(sent).toHaveLength(2));

    expect(sent[1].bookingHorizonDays).toBe(90);
    expect(sent[1].minimumNoticeMinutes).toBe(720);
    expect(
      (sent[1].breaks as Record<string, unknown[]> | undefined)?.['0'],
      'characterisation only — see the note above; stays green pre-fix',
    ).toHaveLength(2);
  });
});
