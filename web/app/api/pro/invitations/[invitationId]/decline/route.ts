import { type NextRequest } from 'next/server';
import { callApiPro, respondPro } from '../../../../../../lib/bff-pro';

/// Pro BFF: decline one of MY pending invitations while signed in (team
/// access R5a).
export async function POST(
  req: NextRequest,
  { params }: { params: { invitationId: string } },
) {
  return respondPro(
    await callApiPro(req, `/me/provider/invitations/${params.invitationId}/decline`, {
      method: 'POST',
    }),
  );
}
