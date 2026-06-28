import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../../../lib/bff-pro';

/// Pro BFF: update / delete a team member (backend enforces ownership).
export async function PATCH(
  req: NextRequest,
  { params }: { params: { artistId: string } },
) {
  const { providerId, artist } = await req.json().catch(() => ({}));
  if (!providerId || !artist) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, `/providers/${providerId}/artists/${params.artistId}`, {
      method: 'PATCH',
      body: JSON.stringify(artist),
    }),
  );
}

export async function DELETE(
  req: NextRequest,
  { params }: { params: { artistId: string } },
) {
  const providerId = req.nextUrl.searchParams.get('providerId');
  if (!providerId) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, `/providers/${providerId}/artists/${params.artistId}`, {
      method: 'DELETE',
    }),
  );
}
