import type { NextRequest } from 'next/server';
import { callApiPro, respondPro } from '../../../../lib/bff-pro';

/// Pro BFF: the salon member's in-app notification feed
/// (docs/design/web-pro-notifications.md §5) — the same self-scoped
/// `/me/notifications` the pro app reads. The feed is per ACCOUNT, not per
/// salon: no `salonId` is added (each row's route names its salon).
export async function GET(req: NextRequest) {
  return respondPro(await callApiPro(req, '/me/notifications'));
}
