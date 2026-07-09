import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../../../lib/bff-pro';

/// Pro BFF: reschedule a booking (journal J1 drag). `newDateTime` + optional
/// `artistId` (column change); the backend re-validates the slot + artist
/// ownership.
export async function POST(
  req: NextRequest,
  { params }: { params: { id: string } },
) {
  const { newDateTime, artistId } = await req.json().catch(() => ({}));
  if (!newDateTime) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, `/appointments/${params.id}/reschedule`, {
      method: 'POST',
      body: JSON.stringify({ newDateTime, ...(artistId ? { artistId } : {}) }),
    }),
  );
}
