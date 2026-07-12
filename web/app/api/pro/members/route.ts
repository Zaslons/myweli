import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../lib/bff-pro';
import { validateInviteEmail } from '../../../../lib/pro/team';

/// Pro BFF: the salon roster (team access R5a). The backend resolves the
/// caller's salon from the token and enforces members.manage.
export async function GET(req: NextRequest) {
  return respondPro(await callApiPro(req, '/me/provider/members'));
}

const ROLES = new Set(['manager', 'reception', 'staff']);

/// Invite a member. Email/role validated at the edge; the backend re-checks
/// everything (offer gate, seats, duplicates, artist link).
export async function POST(req: NextRequest) {
  const { email, role, artistId } = await req.json().catch(() => ({}));
  const checked = validateInviteEmail(typeof email === 'string' ? email : '');
  if (!checked.ok || !ROLES.has(role)) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, '/me/provider/members', {
      method: 'POST',
      body: JSON.stringify({ email: checked.email, role, artistId }),
    }),
  );
}
