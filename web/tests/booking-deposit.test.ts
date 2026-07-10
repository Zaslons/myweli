import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  canAttachDeposit,
  rebookHref,
} from '../lib/account/appointments';
import {
  attachDepositProof,
  uploadDepositProof,
} from '../lib/booking/deposit';

/// K2 pay-later on web: the deposit-proof upload client + the mon-compte
/// attach/rebook helpers.

const appt = {
  id: 'appt1',
  status: 'pending',
  appointmentDate: '2026-12-01T09:00:00.000Z',
  providerId: 'p1',
  providerSlug: 'beaute-divine',
  depositAmount: 7500,
} as const;

describe('canAttachDeposit', () => {
  it('pending + deposit due + no proof yet → attachable', () => {
    expect(canAttachDeposit({ ...appt })).toBe(true);
  });

  it('no deposit / already attached / wrong state / salon-entered → not', () => {
    expect(canAttachDeposit({ ...appt, depositAmount: 0 })).toBe(false);
    expect(
      canAttachDeposit({ ...appt, depositScreenshotUrl: 'https://x/p.jpg' }),
    ).toBe(false);
    expect(canAttachDeposit({ ...appt, status: 'confirmed' })).toBe(false);
    expect(canAttachDeposit({ ...appt, salonEntered: true })).toBe(false);
  });
});

describe('rebookHref', () => {
  it('carries the services + stylist prefill', () => {
    expect(
      rebookHref({ ...appt, serviceIds: ['s1', 's2'], artistId: 'a1' }),
    ).toBe('/beaute-divine/reserver?services=s1%2Cs2&artist=a1');
  });

  it('omits empty parts; null without a slug', () => {
    expect(rebookHref({ ...appt })).toBe('/beaute-divine/reserver');
    expect(rebookHref({ ...appt, providerSlug: undefined })).toBeNull();
  });
});

describe('uploadDepositProof + attachDepositProof', () => {
  afterEach(() => vi.restoreAllMocks());

  const file = new File(['x'], 'preuve.jpg', { type: 'image/jpeg' });

  it('signs → POSTs bytes to storage → returns the private key', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            method: 'POST',
            uploadUrl: 'https://r2/upload',
            fields: { k: 'v' },
            key: 'deposit/u1/1.jpg',
          }),
        ),
      )
      .mockResolvedValueOnce(new Response(null, { status: 204 }));
    vi.stubGlobal('fetch', fetchMock);

    expect(await uploadDepositProof(file)).toBe('deposit/u1/1.jpg');
    expect(fetchMock.mock.calls[0][0]).toBe('/api/uploads/sign');
    expect(fetchMock.mock.calls[1][0]).toBe('https://r2/upload');
    expect(fetchMock.mock.calls[1][1]?.body).toBeInstanceOf(FormData);
  });

  it('failed presign or storage POST → null (no attach attempted)', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(new Response(null, { status: 401 })),
    );
    expect(await uploadDepositProof(file)).toBeNull();
  });

  it('attach POSTs the key to the appointment; surfaces the error code', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ id: 'appt1' })))
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ error: 'invalid_state' }), {
          status: 409,
        }),
      );
    vi.stubGlobal('fetch', fetchMock);

    expect(await attachDepositProof('appt1', 'deposit/u1/1.jpg')).toEqual({
      ok: true,
    });
    expect(fetchMock.mock.calls[0][0]).toBe('/api/appointments/appt1/deposit');
    expect(await attachDepositProof('appt1', 'deposit/u1/1.jpg')).toEqual({
      ok: false,
      error: 'invalid_state',
    });
  });
});
