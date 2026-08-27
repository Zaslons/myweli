import { describe, expect, it } from 'vitest';
import { timeOfDay } from '../lib/time-of-day';
import { timeOfDay as reExported } from '../lib/pro/availability';

/// The neutral-module move (fix/web-hours-format): the PUBLIC page and the
/// JSON-LD now read the same parser the pro editor always used.
describe('timeOfDay', () => {
  it('reads the digits after the T — never a Date, never the timezone', () => {
    expect(timeOfDay('2024-01-01T09:00:00.000Z')).toBe('09:00');
    expect(timeOfDay('2024-01-01T18:30:00.000Z')).toBe('18:30');
  });

  it('tolerates a legacy bare HH:mm; refuses garbage with the empty string', () => {
    expect(timeOfDay('09:00')).toBe('09:00');
    expect(timeOfDay('garbage')).toBe('');
    expect(timeOfDay('')).toBe('');
  });

  it('the pro module re-exports the SAME function — no fork to drift', () => {
    expect(reExported).toBe(timeOfDay);
  });
});
