import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../lib/bff-pro';

/// Pro BFF: the salon client base (module clients C1b). GET lists (paginated,
/// `?query=&tag=&page=`); POST adds a client manually. The client sends its
/// own providerId; the backend enforces ownership + audits reads.
export async function GET(req: NextRequest) {
  const p = req.nextUrl.searchParams;
  const providerId = p.get('providerId');
  if (!providerId) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  const qs = new URLSearchParams();
  for (const key of ['query', 'tag', 'page', 'pageSize']) {
    const v = p.get(key);
    if (v) qs.set(key, v);
  }
  const suffix = qs.size ? `?${qs}` : '';
  return respondPro(
    await callApiPro(req, `/providers/${providerId}/clients${suffix}`, {
      method: 'GET',
    }),
  );
}

export async function POST(req: NextRequest) {
  const { providerId, name, phone, note } = await req.json().catch(() => ({}));
  if (!providerId || !name || !phone) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, `/providers/${providerId}/clients`, {
      method: 'POST',
      body: JSON.stringify({ name, phone, ...(note ? { note } : {}) }),
    }),
  );
}
