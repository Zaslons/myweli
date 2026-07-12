import { NextResponse, type NextRequest } from 'next/server';
import { proLoginViaBackend } from '../../../../../../lib/auth-bff';

/// Pro BFF: accept an invitation from the LOGIN bridge (team access R5a).
/// Identity proof travels with the call (Google idToken OR the unconsumed
/// email+code pair from the 202 step); a 200/201 is a flat ProviderSession —
/// proLoginViaBackend cookies it exactly like a login.
export async function POST(req: NextRequest) {
  const { invitationId, idToken, email, code } = await req
    .json()
    .catch(() => ({}));
  if (!invitationId || (!idToken && !(email && code))) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return proLoginViaBackend('/auth/provider/invitations/accept', {
    invitationId,
    idToken,
    email,
    code,
  });
}
