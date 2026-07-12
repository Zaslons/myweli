import { type NextRequest } from 'next/server';
import { callApiPro, respondPro } from '../../../../../../lib/bff-pro';

/// Pro BFF: resend a pending invitation (team access R5a). The per-invitation
/// resend budget is enforced server-side (429 invite_rate_limited).
export async function POST(
  req: NextRequest,
  { params }: { params: { memberId: string } },
) {
  return respondPro(
    await callApiPro(req, `/me/provider/members/${params.memberId}/resend`, {
      method: 'POST',
    }),
  );
}
