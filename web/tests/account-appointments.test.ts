import { describe, expect, it } from 'vitest';
import {
  type Appointment,
  canCancel,
  canReschedule,
  categorize,
  filterByTab,
  statusLabelFr,
} from '../lib/account/appointments';

const mk = (status: string): Appointment => ({
  id: status,
  status,
  appointmentDate: '2026-12-01T09:00:00.000Z',
  providerId: 'p1',
});

describe('account appointment helpers', () => {
  it('categorizes statuses into tabs', () => {
    expect(categorize('pending')).toBe('upcoming');
    expect(categorize('confirmed')).toBe('upcoming');
    expect(categorize('completed')).toBe('past');
    expect(categorize('cancelled')).toBe('cancelled');
    expect(categorize('noShow')).toBe('cancelled'); // canonical camelCase
    expect(categorize('no_show')).toBe('cancelled'); // alias
  });

  it('filters by tab', () => {
    const items = [mk('pending'), mk('completed'), mk('cancelled')];
    expect(filterByTab(items, 'upcoming')).toHaveLength(1);
    expect(filterByTab(items, 'past')).toHaveLength(1);
    expect(filterByTab(items, 'cancelled')).toHaveLength(1);
  });

  it('allows cancel only for pending/confirmed', () => {
    expect(canCancel(mk('pending'))).toBe(true);
    expect(canCancel(mk('confirmed'))).toBe(true);
    expect(canCancel(mk('completed'))).toBe(false);
    expect(canCancel(mk('cancelled'))).toBe(false);
  });

  it('labels statuses in French', () => {
    expect(statusLabelFr('confirmed')).toBe('Confirmé');
    expect(statusLabelFr('noShow')).toBe('Absent'); // app label
  });
});

it('canReschedule: pending/confirmed AND future only (parity 1.1)', () => {
  const future = new Date(Date.now() + 86400000).toISOString();
  const past = new Date(Date.now() - 86400000).toISOString();
  const base = { id: 'a1', providerId: 'p1', appointmentDate: future };
  expect(canReschedule({ ...base, status: 'confirmed' })).toBe(true);
  expect(canReschedule({ ...base, status: 'pending' })).toBe(true);
  expect(canReschedule({ ...base, status: 'completed' })).toBe(false);
  expect(
    canReschedule({ ...base, status: 'confirmed', appointmentDate: past }),
  ).toBe(false);
});
