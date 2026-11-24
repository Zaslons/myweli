import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import {
  type Appointment,
  DEPOSIT_SEE_THE_SALON,
  clientStatusSentence,
  communeLine,
  depositState,
  hasPosition,
  salonAddressLines,
} from '../lib/account/appointments';
import { formatDateLongFr } from '../lib/format';
import { directionsTo } from '../lib/provider-summary';

/// docs/design/appointment-detail-complete.md §2.3–§2.7 (A2w, decisions
/// 194–203). The two tables are the SAME files the app's suite reads
/// (`deposit_state_test.dart`, `client_booking_rule_test.dart`): a rule
/// changed on one surface turns that surface red; a row changed in a file
/// turns both red until both follow.

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (f: string) =>
  JSON.parse(readFileSync(join(REPO_ROOT, 'docs/design/fixtures', f), 'utf8')) as {
    rows: Record<string, unknown>[];
  };
const NOW = new Date('2026-11-23T12:00:00.000Z');
const at = (minutes: number) => new Date(NOW.getTime() + minutes * 60_000).toISOString();
const appt = (extra: Partial<Appointment> = {}): Appointment => ({
  id: 'a',
  status: 'confirmed',
  appointmentDate: at(60),
  providerId: 'p1',
  ...extra,
});

describe('the deposit table (deposit-state.json, decision 197)', () => {
  const rows = read('deposit-state.json').rows as {
    status: string;
    minutesFromNow: number;
    proof: boolean;
    label: string;
    sentence: string | null;
    action: string | null;
    balance: boolean;
  }[];

  it('holds every status, both sides of now, and the boundary', () => {
    expect(rows.length).toBeGreaterThanOrEqual(17);
    expect(new Set(rows.map((r) => r.status))).toEqual(
      new Set(['pending', 'confirmed', 'completed', 'noShow', 'cancelled']),
    );
    expect(rows.some((r) => r.minutesFromNow === 0)).toBe(true);
  });

  for (const r of rows) {
    it(`${r.status} at ${r.minutesFromNow} min, proof ${r.proof} → « ${r.label} »`, () => {
      const s = depositState(
        appt({
          status: r.status,
          appointmentDate: at(r.minutesFromNow),
          depositAmount: 5000,
          depositScreenshotUrl: r.proof ? 'deposit/u1/proof.jpg' : null,
        }),
        NOW,
      );
      expect(s).not.toBeNull();
      expect(s!.label).toBe(r.label);
      expect(s!.sentence).toBe(r.sentence);
      expect(s!.action).toBe(r.action);
      expect(s!.showBalance).toBe(r.balance);
    });
  }

  it('no deposit, no block — whatever the status', () => {
    for (const status of ['pending', 'confirmed', 'completed', 'cancelled', 'noShow']) {
      expect(depositState(appt({ status, depositAmount: 0 }), NOW), status).toBeNull();
      expect(depositState(appt({ status }), NOW), status).toBeNull();
    }
  });

  it('never « Acompte confirmé »: a salon confirms a booking, not a payment', () => {
    for (const proof of [true, false]) {
      const s = depositState(
        appt({ depositAmount: 5000, depositScreenshotUrl: proof ? 'p.jpg' : null }),
        NOW,
      )!;
      expect(s.label).not.toBe('Acompte confirmé');
      expect(s.sentence ?? '').not.toContain('confirmé la réception');
    }
    expect(DEPOSIT_SEE_THE_SALON).toContain(' :');
  });
});

describe('the status sentence (client-booking-rule.json, decision 196)', () => {
  const rows = read('client-booking-rule.json').rows as {
    status: string;
    minutesFromNow: number;
    sentence: string | null;
  }[];

  it('every row says its sentence, or none', () => {
    expect(rows.length).toBeGreaterThanOrEqual(13);
    for (const r of rows) {
      expect(Object.keys(r), JSON.stringify(r)).toContain('sentence');
      expect(
        clientStatusSentence(appt({ status: r.status, appointmentDate: at(r.minutesFromNow) }), NOW),
        `${r.status} ${r.minutesFromNow}`,
      ).toBe(r.sentence);
    }
  });
});

describe('« Le salon » (§2.6)', () => {
  it('« commune, ville », and only with a commune', () => {
    expect(communeLine('Cocody', 'Abidjan')).toBe('Cocody, Abidjan');
    expect(communeLine('Cocody', null)).toBe('Cocody');
    expect(communeLine(null, 'Abidjan')).toBeNull();
    expect(communeLine('  ', 'Abidjan')).toBeNull();
  });

  it('the address, then « commune, ville » — not repeated when the address names it', () => {
    const base = { providerCommune: 'Cocody', providerCity: 'Abidjan' };
    expect(salonAddressLines(appt({ ...base, providerAddress: 'Rue des Jardins' }))).toEqual([
      'Rue des Jardins',
      'Cocody, Abidjan',
    ]);
    for (const providerAddress of ['Rue 12, Cocody', 'Rue 12, COCODY', 'Rue 12, Cocôdy']) {
      expect(salonAddressLines(appt({ ...base, providerAddress })), providerAddress).toEqual([
        providerAddress,
      ]);
    }
    // The control: another commune in the address does not hide this one.
    expect(salonAddressLines(appt({ ...base, providerAddress: 'Rue 12, Marcory' }))).toEqual([
      'Rue 12, Marcory',
      'Cocody, Abidjan',
    ]);
    expect(salonAddressLines(appt(base))).toEqual(['Cocody, Abidjan']);
    expect(salonAddressLines(appt({ providerCity: 'Abidjan' }))).toEqual([]);
  });

  it('a position is a pair', () => {
    expect(hasPosition(appt({ providerLatitude: 5.36, providerLongitude: -3.99 }))).toBe(true);
    expect(hasPosition(appt({ providerLatitude: 5.36 }))).toBe(false);
    expect(hasPosition(appt({ providerLatitude: 0, providerLongitude: 0 }))).toBe(true);
    expect(hasPosition(appt())).toBe(false);
  });

  it('« Itinéraire » asks Google Maps for directions to the two numbers', () => {
    expect(directionsTo(5.3599, -3.9871)).toBe(
      'https://www.google.com/maps/dir/?api=1&destination=5.3599,-3.9871',
    );
  });
});

describe('the date with its weekday (§2.4, decision 200)', () => {
  it('reads as the app’s « EEEE d MMMM yyyy », in the salon’s time', () => {
    expect(formatDateLongFr('2026-11-25T09:00:00.000Z')).toBe('mercredi 25 novembre 2026');
    // 23:30 UTC on 31 October is 1 November in Libreville (UTC+1).
    expect(formatDateLongFr('2026-10-31T23:30:00.000Z', 'Africa/Libreville')).toBe(
      'dimanche 1 novembre 2026',
    );
    expect(formatDateLongFr('2026-10-31T23:30:00.000Z')).toBe('samedi 31 octobre 2026');
  });
});
