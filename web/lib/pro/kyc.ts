import type { components } from '../api/schema';

/// Pure rules for the pro « Vérification » page
/// (docs/design/web-pro-kyc.md §3) — the app's `kyc_document.dart`,
/// unit-tested.

export type KycStatus = components['schemas']['KycStatus'];
export type KycDocument = components['schemas']['KycDocument'];
export type KycDocType = KycDocument['type'];

export const KYC_DOC_TYPES: { type: KycDocType; label: string }[] = [
  { type: 'idCard', label: 'Pièce d’identité (CNI / passeport)' },
  { type: 'selfie', label: 'Photo du visage' },
  { type: 'businessRegistration', label: 'Registre de commerce (RCCM)' },
  { type: 'addressProof', label: 'Justificatif d’adresse' },
];

/// The app's `isKycDocumentRequired`: ID + selfie always; the RCCM unless the
/// business is `other` (freelancers à domicile) — a missing/unknown
/// businessType stays conservative (required); address proof always optional.
export function isKycDocRequired(
  type: KycDocType,
  businessType: string | null | undefined,
): boolean {
  switch (type) {
    case 'idCard':
    case 'selfie':
      return true;
    case 'businessRegistration':
      return businessType !== 'other';
    case 'addressProof':
      return false;
  }
}

export function hasRequiredDocs(
  documents: { type: KycDocType }[],
  businessType: string | null | undefined,
): boolean {
  const present = new Set(documents.map((d) => d.type));
  return KYC_DOC_TYPES.filter((d) => isKycDocRequired(d.type, businessType))
    .every((d) => present.has(d.type));
}

/// The app's submit gate: required docs present and not already verified.
export function canSubmitKyc(input: {
  documents: { type: KycDocType }[];
  businessType: string | null | undefined;
  status: KycStatus['status'];
  busy: boolean;
}): boolean {
  return (
    input.status !== 'verified' &&
    !input.busy &&
    hasRequiredDocs(input.documents, input.businessType)
  );
}

export const KYC_ACCEPT =
  'image/jpeg,image/png,image/webp,application/pdf';
