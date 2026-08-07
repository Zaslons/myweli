import type { NextRequest } from 'next/server';
import { callApiPro, respondPro } from '../../../../lib/bff-pro';

/// Pro BFF: the salon's reviews page (« Avis », docs/design/web-pro-reviews.md).
///
/// **The salon comes from the token now, not from the browser.** This used to
/// forward whatever `providerId` the client sent to the PUBLIC
/// `/providers/{id}/reviews`, which is unauthenticated and checks nothing —
/// the pro surface was reading its own reviews through the anonymous door.
/// PR1b moved four surfaces off that door and its source pin could not see
/// this one, because the leak crossed a service boundary rather than a
/// directory one. Decision C closes the public reviews route, and a `draft`
/// salon can hold reviews (T53 erasure, T54 billing unpublish), so the owner
/// being asked to pay would otherwise lose this page.
export async function GET(req: NextRequest) {
  const p = req.nextUrl.searchParams;
  const page = p.get('page') ?? '1';
  // `salonId` is the R6 selector the whole /me/* family accepts; an invalid
  // one is a uniform 403 upstream, never an oracle (T55).
  const salonId = p.get('salonId');
  const qs = new URLSearchParams({ page, pageSize: '50' });
  if (salonId) qs.set('salonId', salonId);
  return respondPro(await callApiPro(req, `/me/provider/reviews?${qs}`));
}
