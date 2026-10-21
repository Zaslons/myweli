import type { NextRequest } from 'next/server';
import { callApiPro, respondPro } from '../../../../../../lib/bff-pro';

/// Pro BFF: the salon reports a review of its own salon (B6.6 —
/// docs/design/backend-integrity-batch6.md §2.6). Session-scoped upstream:
/// the salon is the session's (the selection cookie is added by
/// `callApiPro`), never one the browser names; only the reason crosses.
export async function POST(
  req: NextRequest,
  { params }: { params: { id: string } },
) {
  const body = (await req.json().catch(() => ({}))) as { reason?: unknown };
  const reason = typeof body?.reason === 'string' ? body.reason : undefined;
  return respondPro(
    await callApiPro(
      req,
      `/me/provider/reviews/${encodeURIComponent(params.id)}/report`,
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(reason === undefined ? {} : { reason }),
      },
    ),
  );
}
