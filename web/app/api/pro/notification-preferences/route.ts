import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../lib/bff-pro';

/// Pro BFF: the member's own notification preferences
/// (docs/design/salon-email-alerts.md §5) — the self-scoped
/// `/me/notification-preferences` on the PRO session. Per account, not per
/// salon: no salon is added.
export async function GET(req: NextRequest) {
  return respondPro(await callApiPro(req, '/me/notification-preferences'));
}

/// Web Pro writes « Alertes par e-mail » and nothing else: whatever else a
/// body carries is not forwarded, so this door cannot switch a member's push
/// or reminders off.
export async function PUT(req: NextRequest) {
  const body = await req.json().catch(() => null);
  if (typeof body?.emailAlerts !== 'boolean') {
    return NextResponse.json({ error: 'invalid_body' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, '/me/notification-preferences', {
      method: 'PUT',
      body: JSON.stringify({ emailAlerts: body.emailAlerts }),
    }),
  );
}
