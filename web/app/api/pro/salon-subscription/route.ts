import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../lib/bff-pro';

/// Pro BFF: the salon's offer state (team access R5a — the pricing pivot).
/// 404 `no_offer` = the free SETUP state, passed through for the client.
export async function GET(req: NextRequest) {
  const providerId = req.nextUrl.searchParams.get('providerId');
  if (!providerId) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, `/providers/${providerId}/subscription`),
  );
}

const TIERS = new Set(['pro', 'business', 'reseau']);

/// Pick/switch the offer. First choice starts the ONE 3-month trial
/// (409 `trial_used` on a re-attempt); switches keep the trial clock.
export async function PUT(req: NextRequest) {
  const { providerId, tier } = await req.json().catch(() => ({}));
  if (!providerId || !TIERS.has(tier)) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, `/providers/${providerId}/subscription`, {
      method: 'PUT',
      body: JSON.stringify({ tier }),
    }),
  );
}
