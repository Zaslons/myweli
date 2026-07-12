import { NextResponse, type NextRequest } from 'next/server';
import { apiBase } from '../../../../../../lib/server-api';

/// Pro BFF: decline an invitation from the LOGIN bridge (team access R5a).
/// Same identity proof as accept, but NEVER a session — plain passthrough.
export async function POST(req: NextRequest) {
  const { invitationId, idToken, email, code } = await req
    .json()
    .catch(() => ({}));
  if (!invitationId || (!idToken && !(email && code))) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  const r = await fetch(`${apiBase}/auth/provider/invitations/decline`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ invitationId, idToken, email, code }),
  });
  const body = await r.json().catch(() => ({}));
  return NextResponse.json(body, { status: r.status });
}
