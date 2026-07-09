import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../../../lib/bff-pro';

const ALLOWED = new Set(['accept', 'reject', 'complete', 'no-show', 'arrive']);

/// Pro BFF: a lifecycle action on the salon's booking (server enforces ownership
/// + valid transition). Bodyless POST.
export async function POST(
  req: NextRequest,
  { params }: { params: { id: string; action: string } },
) {
  if (!ALLOWED.has(params.action)) {
    return NextResponse.json({ error: 'invalid_action' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, `/appointments/${params.id}/${params.action}`, {
      method: 'POST',
    }),
  );
}
