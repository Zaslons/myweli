import { describe, expect, it } from 'vitest';
import {
  type ServiceForm,
  buildServicePayload,
  validateService,
} from '../lib/pro/catalogue';

const base: ServiceForm = {
  name: 'Tresses',
  description: 'Pose de tresses',
  price: '15000',
  priceMax: '25000',
  durationMinutes: '120',
  active: true,
};

describe('pro catalogue — validateService', () => {
  it('accepts a valid form', () => {
    expect(validateService(base)).toBeNull();
  });

  it('requires a name', () => {
    expect(validateService({ ...base, name: '  ' })).toMatch(/nom/i);
  });

  it('requires a positive starting price', () => {
    expect(validateService({ ...base, price: '' })).toMatch(/prix/i);
    expect(validateService({ ...base, price: '0' })).toMatch(/prix/i);
  });

  it('rejects priceMax below price', () => {
    expect(validateService({ ...base, priceMax: '10000' })).toMatch(/maximum/i);
  });

  it('requires a positive duration', () => {
    expect(validateService({ ...base, durationMinutes: '' })).toMatch(/durée/i);
  });
});

describe('pro catalogue — buildServicePayload', () => {
  it('coerces types and nulls an empty priceMax', () => {
    expect(buildServicePayload({ ...base, priceMax: '' })).toEqual({
      name: 'Tresses',
      description: 'Pose de tresses',
      price: 15000,
      priceMax: null,
      durationMinutes: 120,
      active: true,
    });
  });
});
