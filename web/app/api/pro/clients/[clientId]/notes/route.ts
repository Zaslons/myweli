import { type NextRequest, NextResponse } from 'next/server';
import { idempotencyKeyHeader } from '../../../../../../lib/bff';
import { callApiPro, respondPro } from '../../../../../../lib/bff-pro';

type Params = { params: { clientId: string } };

/// Pro BFF: add an internal note (team-only; author resolved server-side).
export async function POST(req: NextRequest, { params }: Params) {
  const { clientId } = params;
  const { providerId, body } = await req.json().catch(() => ({}));
  if (!providerId || typeof body !== 'string') {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(
      req,
      `/providers/${providerId}/clients/${clientId}/notes`,
      {
        method: 'POST',
        headers: idempotencyKeyHeader(req), // docs/design/write-idempotency.md §4
        body: JSON.stringify({ body }),
      },
    ),
  );
}
