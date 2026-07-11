import { describe, expect, it } from 'vitest';
import {
  type ArtistForm,
  type ServiceForm,
  buildArtistPayload,
  buildServicePayload,
  serviceToForm,
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
  hasVariants: false,
  variantCourt: '',
  variantMoyen: '',
  variantLong: '',
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
      durationVariants: {},
    });
  });

  // Audit 3.2 — the app's semantics: toggle off clears; on keeps filled keys.
  it('variants: toggle off → {}, even with leftover text', () => {
    expect(
      buildServicePayload({ ...base, variantCourt: '60' }).durationVariants,
    ).toEqual({});
  });

  it('variants: only the filled, positive-integer keys ride', () => {
    expect(
      buildServicePayload({
        ...base,
        hasVariants: true,
        variantCourt: '60',
        variantMoyen: '',
        variantLong: 'abc',
      }).durationVariants,
    ).toEqual({ court: 60 });
  });
});

it('audit 3.2: serviceToForm prefills the variant editor', () => {
  const f = serviceToForm({
    id: 's1',
    name: 'Tresses',
    durationVariants: { court: 60, long: 180 },
  });
  expect(f.hasVariants).toBe(true);
  expect(f.variantCourt).toBe('60');
  expect(f.variantMoyen).toBe('');
  expect(f.variantLong).toBe('180');
  expect(serviceToForm({ id: 's2', name: 'Soin' }).hasVariants).toBe(false);
});

describe('pro catalogue — artists', () => {
  const a: ArtistForm = { name: 'Awa', specialization: 'Tresses', imageUrl: null, workingHours: {} };

  it('requires a name', () => {
    expect(validateArtist({ ...a, name: ' ' })).toMatch(/nom/i);
    expect(validateArtist(a)).toBeNull();
  });

  it('nulls an empty specialization', () => {
    expect(
      buildArtistPayload({
        name: 'Koffi',
        specialization: '',
        imageUrl: null,
        workingHours: {},
      }),
    ).toEqual({
      name: 'Koffi',
      specialization: null,
      imageUrl: null,
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
  const f = { name: 'Awa', specialization: '', imageUrl: null };
  expect(buildArtistPayload({ ...f, workingHours: wh }).workingHours).toEqual(
    wh,
  );
  expect(buildArtistPayload({ ...f, workingHours: {} }).workingHours).toEqual(
    {},
  );
});

it('audit 3.5: the avatar rides the artist payload', () => {
  expect(
    buildArtistPayload({
      name: 'Awa',
      specialization: '',
      imageUrl: 'https://cdn.stub/gallery/p1/avatar.jpg',
      workingHours: {},
    }).imageUrl,
  ).toBe('https://cdn.stub/gallery/p1/avatar.jpg');
});
