import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../lib/bff-pro';

/// Pro BFF: the salon's reviews page (« Avis », docs/design/web-pro-reviews.md).
/// Client sends its own providerId (the upstream endpoint is public data);
/// kept behind the pro session like every /api/pro/* surface.
export async function GET(req: NextRequest) {
  const p = req.nextUrl.searchParams;
  const providerId = p.get('providerId');
  if (!providerId) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  const page = p.get('page') ?? '1';
  return respondPro(
    await callApiPro(
      req,
      `/providers/${providerId}/reviews?page=${encodeURIComponent(page)}&pageSize=50`,
    ),
  );
}
