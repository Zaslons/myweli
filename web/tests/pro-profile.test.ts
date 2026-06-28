import { describe, expect, it } from 'vitest';
import {
  type ProfileForm,
  buildProfilePayload,
  profileToForm,
  validateProfile,
} from '../lib/pro/profile';
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
  commune: 'Cocody',
  city: 'Abidjan',
  phoneNumber: '+2250700000000',
  whatsapp: '',
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
    });
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
