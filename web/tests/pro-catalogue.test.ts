import { describe, expect, it } from 'vitest';
import {
  type ArtistForm,
  type ServiceForm,
  buildArtistPayload,
  buildServicePayload,
  validateArtist,
  validateService,
} from '../lib/pro/catalogue';

const base: ServiceForm = {
  name: 'Tresses',
  description: 'Pose de tresses',
  price: '15000',
  priceMax: '25000',
  durationMinutes: '120',
  active: true,
  artistIds: [],
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
      artistIds: [],
    });
  });
});

describe('pro catalogue — artists', () => {
  const a: ArtistForm = { name: 'Awa', specialization: 'Tresses', workingHours: {} };

  it('requires a name', () => {
    expect(validateArtist({ ...a, name: ' ' })).toMatch(/nom/i);
    expect(validateArtist(a)).toBeNull();
  });

  it('nulls an empty specialization', () => {
    expect(buildArtistPayload({ name: 'Koffi', specialization: '', workingHours: {} })).toEqual({
      name: 'Koffi',
      specialization: null,
      workingHours: {},
    });
  });
});

it('audit 3.1: artistIds ride the service payload', () => {
  expect(
    buildServicePayload({ ...base, artistIds: ['a1', 'a2'] }).artistIds,
  ).toEqual(['a1', 'a2']);
  expect(buildServicePayload(base).artistIds).toEqual([]);
});

it('audit 3.4: workingHours ride the artist payload ({} = inherit)', () => {
  const wh = { '0': [{ startTime: '10:00', endTime: '17:00' }] };
  expect(
    buildArtistPayload({ name: 'Awa', specialization: '', workingHours: wh })
      .workingHours,
  ).toEqual(wh);
  expect(
    buildArtistPayload({ name: 'Awa', specialization: '', workingHours: {} })
      .workingHours,
  ).toEqual({});
});
