import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../lib/bff-pro';

/// Pro BFF: take the salon live (docs/design/pro-salon-lifecycle.md). The
/// client sends its own providerId; the backend enforces ownership (T50) and
/// recomputes the go-live gate server-side.
export async function POST(req: NextRequest) {
  const { providerId } = await req.json().catch(() => ({}));
  if (!providerId) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, `/providers/${providerId}/publish`, {
      method: 'POST',
    }),
  );
}
