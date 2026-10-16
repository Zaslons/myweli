import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  type ProfileForm,
  buildProfilePayload,
  profilePhoneChecks,
  profileToForm,
  validateProfile,
} from '../lib/pro/profile';
import { uploadLogoImage } from '../lib/pro/upload';
import {
  DEFAULT_DEPOSIT_PERCENT,
  type DepositForm,
  buildDepositPayload,
  depositToForm,
  validateDeposit,
  validateDepositNumber,
} from '../lib/pro/deposit';

/// The phone rule's sentences (docs/design/phone-national-length.md §2.1).
const TEN = 'Le numéro doit comporter 10 chiffres après +225.';
const REQUIRED = 'Saisissez un numéro de téléphone.';
const INVALID = 'Saisissez un numéro de téléphone valide.';

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
  it('requires a name (the phones are checked under their own fields)', () => {
    expect(validateProfile(profile)).toBeNull();
    expect(validateProfile({ ...profile, name: ' ' })).toMatch(/nom/i);
  });

  it('Téléphone is required, WhatsApp optional — and a +225 number has 10 digits', () => {
    const { phoneNumber, whatsapp } = profilePhoneChecks;
    expect(phoneNumber('+2250700000000')).toBeNull();
    // The old regex let 7 digits after +225 through (10 digits after the +).
    expect(phoneNumber('+2250700000')).toBe(TEN);
    expect(phoneNumber('')).toBe(REQUIRED);
    expect(phoneNumber('+225')).toBe(REQUIRED);
    expect(phoneNumber('0700')).toBe(INVALID);
    expect(whatsapp('')).toBeNull();
    expect(whatsapp('+225')).toBeNull();
    expect(whatsapp('+2250700000')).toBe(TEN);
    expect(whatsapp('abc')).toBe(INVALID);
  });

  it('sends the numbers bare: separators stripped, a lone +225 WhatsApp cleared', () => {
    const payload = buildProfilePayload({
      ...profile,
      phoneNumber: ' +225 07 07 12 34 56 ',
      whatsapp: '+225',
    });
    expect(payload.phoneNumber).toBe('+2250707123456');
    expect(payload.whatsapp).toBeNull();
    expect(
      buildProfilePayload({ ...profile, whatsapp: '+225 05 05 05 05 05' }).whatsapp,
    ).toBe('+2250505050505');
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

  it('requires %, operator when required', () => {
    expect(validateDeposit({ ...on, percent: '0' })).toMatch(/pourcentage/i);
    expect(validateDeposit({ ...on, operator: '' })).toMatch(/opérateur/i);
  });

  it('the Mobile Money number (checked under its field): required with a deposit, +225 = 10 digits', () => {
    const required = { required: true };
    expect(validateDepositNumber('+2250700000000', required)).toBeNull();
    expect(validateDepositNumber('+225 07 00 00 00 00', required)).toBeNull();
    expect(validateDepositNumber('+2250700000', required)).toBe(TEN);
    expect(validateDepositNumber('07', required)).toBe(INVALID);
    expect(validateDepositNumber('', required)).toBe(REQUIRED);
    expect(validateDepositNumber('+225', required)).toBe(REQUIRED);
  });

  it('deposits off: the number is optional — but one that is kept is still judged', () => {
    // docs/design/phone-leftovers.md §6: kept and sent whatever the switch
    // says, so the same rule holds it; only emptiness is allowed.
    const optional = { required: false };
    expect(validateDepositNumber('', optional)).toBeNull();
    expect(validateDepositNumber('+225', optional)).toBeNull();
    expect(validateDepositNumber('+2250700000000', optional)).toBeNull();
    expect(validateDepositNumber('+2250700000', optional)).toBe(TEN);
    expect(validateDepositNumber('07', optional)).toBe(INVALID);
  });

  it('sends the Mobile Money number bare', () => {
    expect(
      buildDepositPayload({ ...on, number: '+225 07 07 12 34 56' }, 0.3).mobileMoneyNumber,
    ).toBe('+2250707123456');
  });

  it('window must be 0..720', () => {
    expect(validateDeposit({ ...on, windowHours: '999' })).toMatch(/annulation/i);
    expect(validateDeposit({ required: false, percent: '', windowHours: '24', operator: '', number: '' })).toBeNull();
  });

  it('builds fraction payload; deposits off KEEP the operator, the percentage and the number', () => {
    expect(buildDepositPayload(on, 0.5)).toEqual({
      depositRequired: true,
      depositPercentage: 0.3,
      cancellationWindowHours: 24,
      mobileMoneyOperator: 'wave',
      mobileMoneyNumber: '+2250700000000',
    });
    // docs/design/acompte-off-parity.md D1 — the PUT replaces the whole
    // policy: off sent `null` / `0` and erased the operator a client still
    // owing a deposit is shown. The app sends what it holds; so does the web.
    // (The number: phone-leftovers.md §6.)
    expect(buildDepositPayload({ ...on, required: false }, 0.5)).toEqual({
      depositRequired: false,
      depositPercentage: 0.3,
      cancellationWindowHours: 24,
      mobileMoneyOperator: 'wave',
      mobileMoneyNumber: '+2250700000000',
    });
    // No operator chosen is null, switch on or off.
    expect(
      buildDepositPayload({ ...on, required: false, operator: '' }, 0.5).mobileMoneyOperator,
    ).toBeNull();
    // Empty (or a lone calling code) is no number: null, switch on or off.
    expect(
      buildDepositPayload({ ...on, required: false, number: '' }, 0.5).mobileMoneyNumber,
    ).toBeNull();
    expect(
      buildDepositPayload({ ...on, required: false, number: '+225' }, 0.5).mobileMoneyNumber,
    ).toBeNull();
  });

  it('deposits off, a hidden percentage that fails its rule: the last loaded or saved one is sent', () => {
    // Decision 1: the field is hidden while off — a fault the salon cannot
    // see must neither block the save nor change the stored percentage.
    for (const percent of ['', '  ', 'abc', '0', '-5', '101', '150']) {
      const off = { ...on, required: false, percent };
      expect(validateDeposit(off), percent).toBeNull();
      expect(buildDepositPayload(off, 0.45).depositPercentage, percent).toBe(0.45);
    }
  });

  it('the percentage is sent from the field exactly when it passes the rule validateDeposit applies (1–100)', () => {
    // One rule, two readers: what the switch-on check accepts is what the
    // payload takes from the field — on or off.
    for (const percent of ['1', '30', '55', '100']) {
      expect(validateDeposit({ ...on, percent }), percent).toBeNull();
      for (const required of [true, false]) {
        expect(
          buildDepositPayload({ ...on, required, percent }, 0.45).depositPercentage,
          `${percent} ${required}`,
        ).toBe(Number(percent) / 100);
      }
    }
    // Below 1 is refused as its message says (« 1–100 % »): '0.4' passed the
    // old `> 0` check, was stored as 0.004, read back as « 0 » and refused —
    // a policy the web wrote and could not save again.
    for (const percent of ['', 'abc', '0', '0.4', '0.99', '101']) {
      expect(validateDeposit({ ...on, percent }), percent).toMatch(/pourcentage/i);
      expect(
        buildDepositPayload({ ...on, required: false, percent }, 0.45).depositPercentage,
        percent,
      ).toBe(0.45);
    }
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

  it('depositToForm: a stored 0 (or none) is « not chosen yet » — the form proposes 30', () => {
    // docs/design/acompte-off-parity.md decision 2: every new salon is
    // created at 0, which the switch-on check refuses.
    const at = (depositPercentage: number | null | undefined) =>
      depositToForm({
        depositRequired: false,
        depositPercentage: depositPercentage as number,
        cancellationWindowHours: 24,
      }).percent;
    expect(at(0)).toBe('30');
    expect(at(null)).toBe('30');
    expect(at(undefined)).toBe('30');
    expect(depositToForm(undefined).percent).toBe('30');
    expect(String(DEFAULT_DEPOSIT_PERCENT)).toBe('30');
    // A chosen percentage is the salon's, off or on.
    expect(at(0.4)).toBe('40');
  });

  it('depositToForm keeps a stored percentage to the hundredth — an untouched save writes back what it read', () => {
    // Deposits off now send the field back (decision 1), so a rounded read
    // would rewrite a policy nobody touched: 0.125 read as « 13 » saved 0.13.
    const at = (depositPercentage: number) =>
      depositToForm({ depositRequired: false, depositPercentage, cancellationWindowHours: 24 })
        .percent;
    expect(at(0.125)).toBe('12.5');
    expect(at(0.29)).toBe('29');
    expect(at(0.57)).toBe('57');
    // What the app's slider writes (0.05 + 12 × 0.05 in floating point).
    expect(at(0.6499999999999999)).toBe('65');
    expect(at(1)).toBe('100');
    // Written by another client below the web's floor: shown as it is, not
    // as a « 0 » — and refused by the switch-on check, like any value < 1.
    expect(at(0.004)).toBe('0.4');
    expect(validateDeposit({ ...on, percent: at(0.004) })).toMatch(/pourcentage/i);
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
