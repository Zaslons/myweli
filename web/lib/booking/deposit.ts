/// Consumer deposit-proof upload (module online-booking K2 — the app's
/// pay-later flow on web): 1) the BFF presigns a private deposit upload
/// (`/api/uploads/sign`, purpose fixed server-side), 2) the bytes POST
/// **directly to storage** (never through our API), 3) the opaque key is
/// attached to the booking via `POST /api/appointments/{id}/deposit`.
/// Unit-tested with a mocked fetch.

type SignResponse = {
  method?: string;
  uploadUrl?: string;
  headers?: Record<string, string>;
  key?: string;
};

export async function uploadDepositProof(file: File): Promise<string | null> {
  const signRes = await fetch('/api/uploads/sign', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ contentType: file.type }),
  });
  if (!signRes.ok) return null;
  const sign = (await signRes.json().catch(() => ({}))) as SignResponse;
  if (!sign.uploadUrl || !sign.key) return null;

  // Raw PUT, not a multipart POST: Cloudflare R2 does not implement presigned
  // POST and answers one with 501 NotImplemented. The signature covers these
  // headers, so send exactly them — a different content-type than the one
  // signed is a 403 from storage.
  // docs/design/backend-r2-presigned-put.md
  const up = await fetch(sign.uploadUrl, {
    method: sign.method ?? 'PUT',
    headers: sign.headers ?? {},
    body: file,
  });
  if (!up.ok) return null; // storage returns 200 on a successful PUT
  return sign.key;
}

export async function attachDepositProof(
  appointmentId: string,
  screenshotKey: string,
): Promise<{ ok: boolean; error?: string }> {
  const res = await fetch(`/api/appointments/${appointmentId}/deposit`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ screenshotKey }),
  });
  if (res.ok) return { ok: true };
  const body = (await res.json().catch(() => ({}))) as { error?: string };
  return { ok: false, error: body.error };
}
