import type { NextRequest } from 'next/server';
import { callApiPro, respondPro } from '../../../../../lib/bff-pro';

/// Pro BFF: « Tout marquer comme lu » (self-scoped).
export async function POST(req: NextRequest) {
  return respondPro(
    await callApiPro(req, '/me/notifications/read-all', { method: 'POST' }),
  );
}
