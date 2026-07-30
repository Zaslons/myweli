import { describe, expect, it } from 'vitest';
import {
  MAX_TAGS,
  PRESET_TAGS,
  maskPhone,
  noShowBadge,
  noShowLabel,
  telHref,
  toggleTag,
  validateTag,
  waHref,
} from '../lib/pro/clients';

// Module `clients` C1b (docs/design/clients-c1.md §6) — pure domain helpers.
describe('clients — phone masking + contact links', () => {
  it('masks to « +225 07 •• •• •89 » shape; full number stays on the card', () => {
    expect(maskPhone('+2250700000089')).toBe('+225 07 •• •• •89');
    expect(maskPhone(null)).toBe('');
    expect(maskPhone('123')).toBe('123'); // too short to mask meaningfully
  });

  it('tel: and wa.me links (digits only for WhatsApp)', () => {
    expect(telHref('+2250700000089')).toBe('tel:+2250700000089');
    expect(waHref('+225 07 00 00 00 89')).toBe(
      'https://wa.me/2250700000089',
    );
  });
});

describe('clients — the no-show badge (decision §11.3)', () => {
  it('nothing at 0, neutral at 1, red from 2', () => {
    expect(noShowBadge(0)).toBe('none');
    expect(noShowBadge(undefined)).toBe('none');
    expect(noShowBadge(1)).toBe('neutral');
    expect(noShowBadge(2)).toBe('red');
    expect(noShowBadge(5)).toBe('red');
  });

  it('labels agree in number', () => {
    expect(noShowLabel(1)).toBe('1 absence');
    expect(noShowLabel(3)).toBe('3 absences');
  });
});

describe('clients — tags (decision §11.1)', () => {
  it('the three starter presets ship first', () => {
    expect(PRESET_TAGS).toEqual(['VIP', 'Fidèle', 'À risque']);
  });

  it('validates length 1–24', () => {
    expect(validateTag('VIP')).toBe(true);
    expect(validateTag('  ')).toBe(false);
    expect(validateTag('x'.repeat(25))).toBe(false);
  });

  it('toggleTag adds, removes, and enforces the cap of 10', () => {
    expect(toggleTag([], 'VIP')).toEqual(['VIP']);
    expect(toggleTag(['VIP'], 'VIP')).toEqual([]);
    const full = Array.from({ length: MAX_TAGS }, (_, i) => `t${i}`);
    expect(toggleTag(full, 'nouveau')).toBeNull(); // cap
    expect(toggleTag(full, 't3')).toHaveLength(MAX_TAGS - 1); // removal ok
    expect(toggleTag([], 'x'.repeat(25))).toBeNull(); // invalid
  });
});
