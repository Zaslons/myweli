import { describe, expect, it } from 'vitest';
import {
  type Appointment,
  canCancel,
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
    expect(categorize('rejected')).toBe('cancelled');
    expect(categorize('no_show')).toBe('cancelled');
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
    expect(statusLabelFr('no_show')).toBe('Absence');
  });
});
