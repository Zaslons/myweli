import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  KYC_DOC_TYPES,
  canSubmitKyc,
  hasRequiredDocs,
  isKycDocRequired,
} from '../lib/pro/kyc';
import { uploadKycDocument } from '../lib/pro/upload';

/// Web pro KYC rules (docs/design/web-pro-kyc.md §3) — the app's
/// kyc_document.dart, ported.

describe('isKycDocRequired', () => {
  it('ID + selfie always; address proof never', () => {
    for (const bt of ['salon', 'other', null, undefined]) {
      expect(isKycDocRequired('idCard', bt)).toBe(true);
      expect(isKycDocRequired('selfie', bt)).toBe(true);
      expect(isKycDocRequired('addressProof', bt)).toBe(false);
    }
  });

  it('RCCM required unless the business is « other » (à domicile)', () => {
    expect(isKycDocRequired('businessRegistration', 'salon')).toBe(true);
    expect(isKycDocRequired('businessRegistration', 'other')).toBe(false);
    // Missing/unknown businessType stays conservative.
    expect(isKycDocRequired('businessRegistration', null)).toBe(true);
    expect(isKycDocRequired('businessRegistration', undefined)).toBe(true);
  });

  it('the catalogue lists the four app types in order', () => {
    expect(KYC_DOC_TYPES.map((d) => d.type)).toEqual([
      'idCard',
      'selfie',
      'businessRegistration',
      'addressProof',
    ]);
  });
});

describe('hasRequiredDocs + canSubmitKyc', () => {
  const idSelfie = [{ type: 'idCard' as const }, { type: 'selfie' as const }];

  it('« other » needs ID + selfie only; salons also need the RCCM', () => {
    expect(hasRequiredDocs(idSelfie, 'other')).toBe(true);
    expect(hasRequiredDocs(idSelfie, 'salon')).toBe(false);
    expect(
      hasRequiredDocs(
        [...idSelfie, { type: 'businessRegistration' as const }],
        'salon',
      ),
    ).toBe(true);
  });

  it('gate: docs present, not verified, not busy', () => {
    const base = {
      documents: idSelfie,
      businessType: 'other',
      status: 'pending' as const,
      busy: false,
    };
    expect(canSubmitKyc(base)).toBe(true);
    expect(canSubmitKyc({ ...base, status: 'rejected' })).toBe(true); // resubmit
    expect(canSubmitKyc({ ...base, status: 'verified' })).toBe(false);
    expect(canSubmitKyc({ ...base, busy: true })).toBe(false);
    expect(canSubmitKyc({ ...base, documents: [] })).toBe(false);
  });
});

describe('uploadKycDocument', () => {
  afterEach(() => vi.restoreAllMocks());

  const file = new File(['x'], 'cni.pdf', { type: 'application/pdf' });

  it('signs with purpose=kyc → POSTs bytes → returns the private key', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            method: 'POST',
            uploadUrl: 'https://r2/upload',
            fields: {},
            key: 'kyc/acc1/1.pdf',
          }),
        ),
      )
      .mockResolvedValueOnce(new Response(null, { status: 204 }));
    vi.stubGlobal('fetch', fetchMock);

    expect(await uploadKycDocument(file)).toEqual({
      key: 'kyc/acc1/1.pdf',
      fileName: 'cni.pdf',
    });
    expect(fetchMock.mock.calls[0][0]).toBe('/api/pro/uploads/sign');
    expect(
      JSON.parse(fetchMock.mock.calls[0][1]?.body as string).purpose,
    ).toBe('kyc');
  });

  it('failed presign → null', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(new Response(null, { status: 403 })),
    );
    expect(await uploadKycDocument(file)).toBeNull();
  });
});
