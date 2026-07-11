import type { NextRequest } from 'next/server';
import { callApiPro, respondPro } from '../../../../lib/bff-pro';
import { clearProSessionCookies } from '../../../../lib/session';

/// Pro BFF: delete the provider ACCOUNT (audit 11.5 — AUTH-004 for pros).
/// Self-scoped server-side (T53); 409 `future_bookings` when the agenda
/// isn't settled. On success the pro session cookies die with the account.
export async function DELETE(req: NextRequest) {
  const result = await callApiPro(req, '/me/provider', { method: 'DELETE' });
  const res = respondPro(result);
  if (result.status === 204) clearProSessionCookies(res);
  return res;
}
