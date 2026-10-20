import type { NextRequest } from 'next/server';
import { callApiPro, respondPro } from '../../../../../../lib/bff-pro';

/// Pro BFF: mark one notification read (self-scoped server-side — another
/// account's id is not this account's to read).
export async function POST(
  req: NextRequest,
  { params }: { params: { id: string } },
) {
  return respondPro(
    await callApiPro(
      req,
      `/me/notifications/${encodeURIComponent(params.id)}/read`,
      { method: 'POST' },
    ),
  );
}
