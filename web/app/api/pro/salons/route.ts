import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../lib/bff-pro';

/// Pro BFF: « Mes salons » (module `access` R6).
///
/// GET — every salon the account belongs to (owned first) + the
/// SERVER-computed `canAddSalon` gate.
export async function GET(req: NextRequest) {
  return respondPro(await callApiPro(req, '/me/salons'));
}

const TYPES = new Set(['salon', 'barber', 'spa', 'nailSalon', 'massage', 'other']);

/// POST — « Ajouter un salon » (Réseau-gated server-side, T55): 201 the new
/// draft salon's entry · 403 `reseau_required` · 409 `salon_limit`.
export async function POST(req: NextRequest) {
  const { businessName, businessType, phoneNumber, address } = await req
    .json()
    .catch(() => ({}));
  if (
    typeof businessName !== 'string' ||
    businessName.trim() === '' ||
    !TYPES.has(businessType)
  ) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, '/me/salons', {
      method: 'POST',
      body: JSON.stringify({
        businessName: businessName.trim(),
        businessType,
        ...(typeof phoneNumber === 'string' && phoneNumber.trim() !== ''
          ? { phoneNumber: phoneNumber.trim() }
          : {}),
        ...(typeof address === 'string' && address.trim() !== ''
          ? { address: address.trim() }
          : {}),
      }),
    }),
  );
}
