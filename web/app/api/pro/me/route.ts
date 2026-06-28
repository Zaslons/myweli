import type { NextRequest } from 'next/server';
import { callApiPro, respondPro } from '../../../../lib/bff-pro';

/// Pro BFF: the signed-in provider's account + managed salon (session check).
export async function GET(req: NextRequest) {
  return respondPro(await callApiPro(req, '/me/provider'));
}
