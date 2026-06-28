import type { NextRequest } from 'next/server';
import { callApiPro, respondPro } from '../../../../lib/bff-pro';

/// Pro BFF: the signed-in provider's plan & trial status (read-only).
export async function GET(req: NextRequest) {
  return respondPro(await callApiPro(req, '/me/subscription'));
}
