import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../../lib/bff-pro';

type Params = { params: { clientId: string } };

/// Pro BFF: the client card (GET, audited read) + its edits (PATCH): the tag
/// set and, on a guest card, the number (docs/design/phone-leftovers.md §8).
export async function GET(req: NextRequest, { params }: Params) {
  const { clientId } = params;
  const providerId = req.nextUrl.searchParams.get('providerId');
  if (!providerId) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, `/providers/${providerId}/clients/${clientId}`, {
      method: 'GET',
    }),
  );
}

/// `{ providerId, tags?, phone? }` — at least one of the two. Only what was
/// sent crosses (a phone edit never re-sends a stale tag set, and the other way
/// round); the value is the server's to judge — an empty phone crosses and is
/// refused there (`invalid_phone`). The answer is passed through as it is: the
/// 409 `client_exists` carries the `clientId` of the card holding the number.
export async function PATCH(req: NextRequest, { params }: Params) {
  const { clientId } = params;
  const { providerId, tags, phone } = await req.json().catch(() => ({}));
  const hasTags = tags !== undefined && tags !== null;
  const hasPhone = phone !== undefined && phone !== null;
  if (
    !providerId ||
    (!hasTags && !hasPhone) ||
    (hasTags && !Array.isArray(tags)) ||
    (hasPhone && typeof phone !== 'string')
  ) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, `/providers/${providerId}/clients/${clientId}`, {
      method: 'PATCH',
      body: JSON.stringify({
        ...(hasTags ? { tags } : {}),
        ...(hasPhone ? { phone } : {}),
      }),
    }),
  );
}
