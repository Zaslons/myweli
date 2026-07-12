import { type NextRequest } from 'next/server';
import { callApiPro, respondPro } from '../../../../lib/bff-pro';

/// Pro BFF: the signed-in provider's OWN pending invitations (team access
/// R5a) — feeds the dashboard ProInvitationsCard.
export async function GET(req: NextRequest) {
  return respondPro(await callApiPro(req, '/me/provider/invitations'));
}
