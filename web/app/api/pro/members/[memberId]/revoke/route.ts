import { type NextRequest } from 'next/server';
import { callApiPro, respondPro } from '../../../../../../lib/bff-pro';

/// Pro BFF: revoke a member's access (team access R5a). Immediate server-side
/// (threat T38); the MyWeli account itself is untouched.
export async function POST(
  req: NextRequest,
  { params }: { params: { memberId: string } },
) {
  return respondPro(
    await callApiPro(req, `/me/provider/members/${params.memberId}/revoke`, {
      method: 'POST',
    }),
  );
}
