import { type NextRequest, NextResponse } from 'next/server';
import { callApi, respond } from '../../../../../lib/bff';

/// BFF: the caller's own deposit-proof signed URL (parity 1.3 — « Voir ma
/// capture »). Ownership-scoped server-side. `?redirect=1` 307s straight to
/// the short-TTL signed URL so the UI can be a plain new-tab link.
export async function GET(
  req: NextRequest,
  { params }: { params: { id: string } },
) {
  const result = await callApi(
    req,
    `/appointments/${params.id}/deposit-screenshot`,
  );
  if (
    result.status === 200 &&
    req.nextUrl.searchParams.get('redirect') === '1'
  ) {
    const url = (result.body as { url?: string }).url;
    if (url) return NextResponse.redirect(url, 307);
  }
  return respond(result);
}
