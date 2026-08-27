import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  type ProfileForm,
  buildProfilePayload,
  profileToForm,
  validateProfile,
} from '../lib/pro/profile';
import { uploadLogoImage } from '../lib/pro/upload';
import {
  type DepositForm,
  buildDepositPayload,
  depositToForm,
  validateDeposit,
} from '../lib/pro/deposit';

const profile: ProfileForm = {
  name: 'Beauté Divine',
  description: 'Salon',
  address: 'Cocody',
  areaId: null,
  commune: 'Cocody',
  city: 'Abidjan',
  phoneNumber: '+2250700000000',
  whatsapp: '',
  category: 'salon',
  latitude: null,
  longitude: null,
  logoUrl: null,
};

describe('pro profile form', () => {
  it('requires a name + valid E.164 phone', () => {
    expect(validateProfile(profile)).toBeNull();
    expect(validateProfile({ ...profile, name: ' ' })).toMatch(/nom/i);
    expect(validateProfile({ ...profile, phoneNumber: '0700' })).toMatch(/téléphone/i);
    expect(validateProfile({ ...profile, whatsapp: 'abc' })).toMatch(/whatsapp/i);
  });

  it('builds an allowlisted payload, nulls empty optionals', () => {
    expect(buildProfilePayload({ ...profile, whatsapp: '', city: '' })).toEqual({
      name: 'Beauté Divine',
      description: 'Salon',
      address: 'Cocody',
      commune: 'Cocody',
      city: null,
      phoneNumber: '+2250700000000',
      whatsapp: null,
      category: 'salon',
      logoUrl: '',
    });
  });

  it('the logo rides the staged payload; none staged sends \'\' (clear/no-op)', () => {
    // salon-logo.md §4: '' clears server-side, and re-sending the stored URL
    // is a promotion no-op — so the payload ALWAYS carries the field.
    const url = 'https://cdn.example/logo/p1/1.jpg';
    expect(buildProfilePayload({ ...profile, logoUrl: url }).logoUrl).toBe(url);
    expect(buildProfilePayload(profile).logoUrl).toBe('');
  });

  it('profileToForm carries the stored logoUrl', () => {
    expect(profileToForm({ logoUrl: 'https://cdn.example/l.jpg' }).logoUrl).toBe(
      'https://cdn.example/l.jpg',
    );
    expect(profileToForm({}).logoUrl).toBeNull();
  });

  it('an areaId REPLACES the name fields — the server derives them (MP3)', () => {
    const payload = buildProfilePayload({ ...profile, areaId: 'marcory' });
    expect(payload.areaId).toBe('marcory');
    expect('commune' in payload).toBe(false);
    expect('city' in payload).toBe(false);
    // No areaId (legacy / tree-down fallback) → the free-text path stands.
    expect(buildProfilePayload(profile).commune).toBe('Cocody');
    expect('areaId' in buildProfilePayload(profile)).toBe(false);
  });

  it('profileToForm carries the stored areaId (MP3)', () => {
    expect(profileToForm({ areaId: 'cocody' }).areaId).toBe('cocody');
    expect(profileToForm({}).areaId).toBeNull();
  });

  it('the map pin rides along only once PLACED (paired — L1)', () => {
    const placed = buildProfilePayload({
      ...profile,
      latitude: 5.36,
      longitude: -3.99,
    });
    expect(placed.latitude).toBe(5.36);
    expect(placed.longitude).toBe(-3.99);
    // Unplaced → the keys are absent (the backend requires the pair).
    const unplaced = buildProfilePayload(profile);
    expect('latitude' in unplaced).toBe(false);
    expect('longitude' in unplaced).toBe(false);
  });

  it('profileToForm fills from a provider record', () => {
    expect(profileToForm({ name: 'X', phoneNumber: '+2250700000001' })).toMatchObject({
      name: 'X',
      phoneNumber: '+2250700000001',
      whatsapp: '',
    });
  });
});

describe('pro deposit form', () => {
  const on: DepositForm = {
    required: true,
    percent: '30',
    windowHours: '24',
    operator: 'wave',
    number: '+2250700000000',
  };

  it('valid when required + complete', () => {
    expect(validateDeposit(on)).toBeNull();
  });

  it('requires %, operator, number when required', () => {
    expect(validateDeposit({ ...on, percent: '0' })).toMatch(/pourcentage/i);
    expect(validateDeposit({ ...on, operator: '' })).toMatch(/opérateur/i);
    expect(validateDeposit({ ...on, number: '07' })).toMatch(/numéro/i);
  });

  it('window must be 0..720', () => {
    expect(validateDeposit({ ...on, windowHours: '999' })).toMatch(/annulation/i);
    expect(validateDeposit({ required: false, percent: '', windowHours: '24', operator: '', number: '' })).toBeNull();
  });

  it('builds fraction payload; clears MoMo when not required', () => {
    expect(buildDepositPayload(on)).toEqual({
      depositRequired: true,
      depositPercentage: 0.3,
      cancellationWindowHours: 24,
      mobileMoneyOperator: 'wave',
      mobileMoneyNumber: '+2250700000000',
    });
    expect(buildDepositPayload({ ...on, required: false })).toMatchObject({
      depositRequired: false,
      depositPercentage: 0,
      mobileMoneyOperator: null,
      mobileMoneyNumber: null,
    });
  });

  it('depositToForm converts fraction → percent', () => {
    expect(
      depositToForm({
        depositRequired: true,
        depositPercentage: 0.25,
        cancellationWindowHours: 48,
      }).percent,
    ).toBe('25');
  });
});

describe('uploadLogoImage', () => {
  afterEach(() => vi.restoreAllMocks());

  it('signs with purpose=logo → PUTs bytes → returns publicUrl', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            method: 'PUT',
            uploadUrl: 'https://r2/upload',
            headers: { 'content-type': 'image/jpeg' },
            publicUrl: 'https://cdn/logo/p1/1.jpg',
          }),
          { status: 200 },
        ),
      )
      .mockResolvedValueOnce(new Response(null, { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    const file = new File(['x'], 'l.jpg', { type: 'image/jpeg' });
    expect(await uploadLogoImage(file)).toBe('https://cdn/logo/p1/1.jpg');
    expect(String(fetchMock.mock.calls[0][0])).toContain('/api/pro/uploads/sign');
    // The purpose IS the storage namespace (salon-logo.md §5) — never gallery.
    expect(
      JSON.parse(fetchMock.mock.calls[0][1]?.body as string).purpose,
    ).toBe('logo');
  });

  it('returns null when the storage PUT fails', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({ uploadUrl: 'https://r2/u', publicUrl: 'https://cdn/x' }),
          { status: 200 },
        ),
      )
      .mockResolvedValueOnce(new Response(null, { status: 403 }));
    vi.stubGlobal('fetch', fetchMock);
    const file = new File(['x'], 'l.jpg', { type: 'image/jpeg' });
    expect(await uploadLogoImage(file)).toBeNull();
  });
});
