import { type NextRequest, NextResponse } from 'next/server';
import { callApi, respond } from '../../../../../lib/bff';

/// BFF: leave a review on the caller's own completed booking (server derives
/// provider/artist/verified; resubmit replaces).
export async function POST(
  req: NextRequest,
  { params }: { params: { id: string } },
) {
  const { rating, text, photoUrls } = await req.json().catch(() => ({}));
  if (typeof rating !== 'number') {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respond(
    await callApi(req, `/appointments/${params.id}/review`, {
      method: 'POST',
      // photoUrls (parity 2.13) — the API re-validates count + entries.
      body: JSON.stringify({ rating, text, photoUrls }),
    }),
  );
}
