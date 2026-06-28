import type { NextRequest } from 'next/server';
import { callApiPro, respondPro } from '../../../../../../lib/bff-pro';

/// Pro BFF: short-lived signed URL of the client's deposit justificatif
/// (salon-side private view; server scopes it to the owner).
export async function GET(
  req: NextRequest,
  { params }: { params: { id: string } },
) {
  return respondPro(
    await callApiPro(req, `/appointments/${params.id}/deposit-screenshot`),
  );
}
