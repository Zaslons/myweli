import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../../lib/bff-pro';

const ROLES = new Set(['manager', 'reception', 'staff']);

/// Pro BFF: change a member's role (team access R5a). Owner stays untouchable
/// server-side (owner_protected).
export async function PATCH(
  req: NextRequest,
  { params }: { params: { memberId: string } },
) {
  const { role, artistId } = await req.json().catch(() => ({}));
  if (!ROLES.has(role)) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, `/me/provider/members/${params.memberId}`, {
      method: 'PATCH',
      body: JSON.stringify({ role, artistId }),
    }),
  );
}
