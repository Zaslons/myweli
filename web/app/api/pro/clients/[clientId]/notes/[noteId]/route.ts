import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../../../../lib/bff-pro';

type Params = { params: { clientId: string; noteId: string } };

/// Pro BFF: delete a note (author or owner).
export async function DELETE(req: NextRequest, { params }: Params) {
  const { clientId, noteId } = params;
  const providerId = req.nextUrl.searchParams.get('providerId');
  if (!providerId) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(
      req,
      `/providers/${providerId}/clients/${clientId}/notes/${noteId}`,
      { method: 'DELETE' },
    ),
  );
}
