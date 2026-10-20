import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../lib/bff-pro';

/// Pro BFF: this browser's notification token on the member's PRO session
/// (docs/design/web-pro-browser-push.md §5) — the self-scoped `/me/devices`.
/// **The platform is this door's to say**: a browser is `web`, whatever a
/// body claims — the salon notifier tells the app from browsers by it, and
/// only the app replaces the e-mail alert (owner Q1).

/// The server's own bound (`routes/me/devices`), checked here so a bad token
/// never costs a round trip.
const MAX_TOKEN = 4096;

async function tokenOf(req: NextRequest): Promise<string | null> {
  const body = await req.json().catch(() => null);
  const token = typeof body?.token === 'string' ? body.token.trim() : '';
  return token && token.length <= MAX_TOKEN ? token : null;
}

const invalid = () => NextResponse.json({ error: 'invalid_body' }, { status: 400 });

export async function POST(req: NextRequest) {
  const token = await tokenOf(req);
  if (!token) return invalid();
  return respondPro(
    await callApiPro(req, '/me/devices', {
      method: 'POST',
      body: JSON.stringify({ token, platform: 'web' }),
    }),
  );
}

export async function DELETE(req: NextRequest) {
  const token = await tokenOf(req);
  if (!token) return invalid();
  return respondPro(
    await callApiPro(req, '/me/devices', {
      method: 'DELETE',
      body: JSON.stringify({ token }),
    }),
  );
}
