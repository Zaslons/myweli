import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const routerMock = { replace: vi.fn(), push: vi.fn(), refresh: vi.fn() };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));

import { DisponibilitesClient } from '../components/pro/DisponibilitesClient';

/// Split working hours and bulk blocked dates on « Disponibilités »
/// (docs/design/web-pro-availability-ranges.md) — what the page shows, and
/// what it SENDS.

const W = (hhmm: string) => `2024-01-01T${hhmm}:00.000Z`;

type Avail = {
  providerId: string;
  weeklySchedule: Record<string, { startTime: string; endTime: string; isAvailable?: boolean }[]>;
  breaks: Record<string, unknown[]>;
  blockedDates: string[];
  bufferMinutes: number;
  bookingHorizonDays: number;
  minimumNoticeMinutes: number;
};

let availability: Avail;
let putStatus = 200;
const sent: Avail[] = [];

beforeEach(() => {
  availability = {
    providerId: 'p1',
    weeklySchedule: {
      // Closed at noon — the salon the web used to show as « 9h–12h ».
      '0': [
        { startTime: W('09:00'), endTime: W('12:00'), isAvailable: true },
        { startTime: W('14:00'), endTime: W('18:00'), isAvailable: true },
      ],
      '1': [{ startTime: W('09:00'), endTime: W('18:00'), isAvailable: true }],
    },
    breaks: {},
    blockedDates: [],
    bufferMinutes: 10,
    bookingHorizonDays: 365,
    minimumNoticeMinutes: 60,
  };
  putStatus = 200;
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
              timezone: 'Africa/Abidjan',
              availability,
            },
          }),
          { status: 200 },
        );
      }
      if (url === '/api/pro/disponibilites') {
        const body = JSON.parse(String(init?.body ?? '{}')) as { availability: Avail };
        sent.push(body.availability);
        return new Response('{}', { status: putStatus });
      }
      return new Response('{}', { status: 404 });
    }),
  );
});

afterEach(() => {
  cleanup();
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

async function open() {
  render(<DisponibilitesClient />);
  await screen.findByText('Fenêtre de réservation');
}

const pageSave = () =>
  fireEvent.click(screen.getAllByRole('button', { name: 'Enregistrer' }).at(-1)!);

describe('§1.3 — a date the APP blocked no longer breaks the page', () => {
  it('the page opens and names the day (it threw « Invalid time value »)', async () => {
    availability.blockedDates = ['2026-12-25T00:00:00.000Z'];
    await open();
    expect(screen.getByText('25 décembre 2026')).toBeInTheDocument();
  });
});

describe('§2.1 — every range of a day, on screen and editable', () => {
  it('Lundi shows its afternoon; editing it is what the save sends', async () => {
    await open();
    const afternoon = screen.getByLabelText('Lundi, plage 2, début');
    expect(afternoon).toHaveValue('14:00');
    fireEvent.change(afternoon, { target: { value: '15:00' } });
    pageSave();
    await waitFor(() => expect(sent).toHaveLength(1));
    expect(sent[0].weeklySchedule['0']).toEqual([
      { startTime: W('09:00'), endTime: W('12:00'), isAvailable: true },
      { startTime: W('15:00'), endTime: W('18:00'), isAvailable: true },
    ]);
  });

  it('« Ajouter une plage » proposes one hour after the last, four hours long', async () => {
    await open();
    // Mardi 9h–18h → the next range would start at 19:00: add on a Mardi
    // trimmed to the morning first.
    fireEvent.change(screen.getByLabelText('Mardi fin'), { target: { value: '12:00' } });
    fireEvent.click(screen.getByRole('button', { name: 'Ajouter une plage le mardi' }));
    expect(screen.getByLabelText('Mardi, plage 2, début')).toHaveValue('13:00');
    expect(screen.getByLabelText('Mardi, plage 2, fin')).toHaveValue('17:00');
  });

  it('« Retirer » the last range closes the day', async () => {
    await open();
    fireEvent.click(screen.getByRole('button', { name: 'Retirer la plage 1 du mardi' }));
    pageSave();
    await waitFor(() => expect(sent).toHaveLength(1));
    expect(sent[0].weeklySchedule['1']).toEqual([]);
  });

  it('two overlapping ranges are refused — nothing is sent (H4)', async () => {
    await open();
    fireEvent.change(screen.getByLabelText('Lundi, plage 2, début'), { target: { value: '11:00' } });
    pageSave();
    expect(await screen.findByText('Lundi : deux plages se chevauchent.')).toBeInTheDocument();
    expect(sent).toHaveLength(0);
  });

  it('the help line (H5)', async () => {
    await open();
    expect(screen.getByText('Fermé à midi ? Ajoutez une deuxième plage.')).toBeInTheDocument();
  });
});

describe('§2.2 — blocked dates, the app’s flow', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-10-19T10:00:00.000Z'));
  });

  it('pick several days → the confirmation names the direction → ONLY the dates are written', async () => {
    await open();
    // An unsaved hours edit must neither be written nor lost by the dates.
    fireEvent.change(screen.getByLabelText('Mardi fin'), { target: { value: '17:00' } });

    fireEvent.click(screen.getByRole('button', { name: 'Gérer les dates bloquées' }));
    const dialog = await screen.findByRole('dialog', { name: 'Jours bloqués' });
    expect(within(dialog).getByText('Touchez les jours à bloquer.')).toBeInTheDocument();
    // The past is not selectable.
    expect(within(dialog).getByRole('button', { name: '18 octobre 2026' })).toBeDisabled();

    fireEvent.click(within(dialog).getByRole('button', { name: '25 octobre 2026' }));
    fireEvent.click(within(dialog).getByRole('button', { name: '26 octobre 2026' }));
    expect(within(dialog).getByRole('button', { name: '25 octobre 2026' })).toHaveAttribute('aria-pressed', 'true');
    expect(within(dialog).getByText('2 dates bloquées')).toBeInTheDocument();
    expect(within(dialog).getByText('2 ajoutées')).toBeInTheDocument();

    fireEvent.click(within(dialog).getByRole('button', { name: 'Enregistrer' }));
    expect(within(dialog).getByText('Bloquer ces dates ?')).toBeInTheDocument();
    expect(
      within(dialog).getByText('Votre salon n’acceptera aucune réservation pendant ces 2 journées.'),
    ).toBeInTheDocument();
    fireEvent.click(within(dialog).getByRole('button', { name: 'Bloquer 2\u00a0dates' }));

    await waitFor(() => expect(sent).toHaveLength(1));
    // Salon midnight in UTC — the app's format (Abidjan = UTC).
    expect(sent[0].blockedDates).toEqual(['2026-10-25T00:00:00.000Z', '2026-10-26T00:00:00.000Z']);
    // The SAVED hours, not the staged edit.
    expect(sent[0].weeklySchedule['1']).toEqual(availability.weeklySchedule['1']);
    expect(await screen.findByText('2 dates bloquées')).toBeInTheDocument();
    expect(screen.queryByRole('dialog')).toBeNull();
    // The staged edit is still staged.
    expect(screen.getByLabelText('Mardi fin')).toHaveValue('17:00');
  });

  it('closing with changes asks first', async () => {
    await open();
    fireEvent.click(screen.getByRole('button', { name: 'Gérer les dates bloquées' }));
    const dialog = await screen.findByRole('dialog', { name: 'Jours bloqués' });
    fireEvent.click(within(dialog).getByRole('button', { name: '25 octobre 2026' }));
    fireEvent.click(within(dialog).getByRole('button', { name: 'Annuler' }));
    expect(within(dialog).getByText('Abandonner les modifications ?')).toBeInTheDocument();
    fireEvent.click(within(dialog).getByRole('button', { name: 'Abandonner' }));
    expect(screen.queryByRole('dialog')).toBeNull();
    expect(sent).toHaveLength(0);
  });

  it('a failed write keeps the dialog open and says why', async () => {
    putStatus = 500;
    await open();
    fireEvent.click(screen.getByRole('button', { name: 'Gérer les dates bloquées' }));
    const dialog = await screen.findByRole('dialog', { name: 'Jours bloqués' });
    fireEvent.click(within(dialog).getByRole('button', { name: '25 octobre 2026' }));
    fireEvent.click(within(dialog).getByRole('button', { name: 'Enregistrer' }));
    fireEvent.click(within(dialog).getByRole('button', { name: 'Bloquer' }));
    expect(await within(dialog).findByText('L’enregistrement a échoué. Réessayez.')).toBeInTheDocument();
  });

  it('« Débloquer » on a row confirms, then writes the list without it', async () => {
    availability.blockedDates = ['2026-12-25', '2026-12-31T00:00:00.000Z'];
    await open();
    fireEvent.click(screen.getByRole('button', { name: 'Débloquer le 25 décembre 2026' }));
    const confirm = await screen.findByRole('dialog', { name: 'Débloquer cette date ?' });
    expect(
      within(confirm).getByText('Le 25 décembre 2026, votre salon acceptera de nouveau des réservations.'),
    ).toBeInTheDocument();
    fireEvent.click(within(confirm).getByRole('button', { name: 'Débloquer' }));
    await waitFor(() => expect(sent).toHaveLength(1));
    // Untouched entry byte-identical.
    expect(sent[0].blockedDates).toEqual(['2026-12-31T00:00:00.000Z']);
  });
});
