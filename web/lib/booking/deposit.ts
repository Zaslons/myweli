import { readJson, send } from '../api/network';
import { putToStorage, reportUploadFailure } from '../upload-telemetry';
/// Consumer deposit-proof upload (module online-booking K2 — the app's
/// pay-later flow on web): 1) the BFF presigns a private deposit upload
/// (`/api/uploads/sign?purpose=deposit`; the key is server-scoped to the
/// caller's own prefix), 2) the bytes POST
/// **directly to storage** (never through our API), 3) the opaque key is
/// attached to the booking via `POST /api/appointments/{id}/deposit`.
/// Unit-tested with a mocked fetch.

type SignResponse = {
  method?: string;
  uploadUrl?: string;
  headers?: Record<string, string>;
  key?: string;
};

/// The upload's outcome. `offline`: the presign got no answer — the person's
/// network, not the file — so the sheet says « Pas de connexion », never
/// « Vérifiez l'image » (docs/design/web-consumer-network-failure.md §3.2).
export type DepositUpload =
  | { ok: true; key: string }
  | { ok: false; offline: boolean };

export async function uploadDepositProof(file: File): Promise<DepositUpload> {
  const signRes = await send('/api/uploads/sign', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    // Explicit. This used to send no purpose at all and rely on the BFF
    // COERCING an unknown value to `deposit` — which meant a typo anywhere
    // else silently signed a deposit too. The BFF now rejects, so every caller
    // says what it wants.
    body: JSON.stringify({ contentType: file.type, purpose: 'deposit' }),
  });
  // No answer from our own BFF (same origin) is the person's network — not
  // storage refusing us nor a CORS rule, which is what the telemetry exists
  // to find: not reported (as the pro presign, web-pro-network-failure.md §5).
  if (signRes.status === 0) return { ok: false, offline: true };
  if (!signRes.ok) {
    reportUploadFailure('sign', 'deposit', { status: signRes.status });
    return { ok: false, offline: false };
  }
  const sign = await readJson<SignResponse>(signRes);
  if (!sign?.uploadUrl || !sign.key) {
    reportUploadFailure('response', 'deposit');
    return { ok: false, offline: false };
  }

  // Raw PUT, not a multipart POST: Cloudflare R2 does not implement presigned
  // POST and answers one with 501 NotImplemented. The signature covers these
  // headers, so send exactly them — a different content-type than the one
  // signed is a 403 from storage.
  // docs/design/backend-r2-presigned-put.md
  const ok = await putToStorage(
    sign.uploadUrl,
    { method: sign.method ?? 'PUT', headers: sign.headers ?? {}, body: file },
    'deposit',
  );
  // Storage returns 200 on a successful PUT. A refused or rejected PUT is
  // reported by `putToStorage`, and cannot be told from a dropped connection.
  if (!ok) return { ok: false, offline: false };
  return { ok: true, key: sign.key };
}

export async function attachDepositProof(
  appointmentId: string,
  screenshotKey: string,
): Promise<{ ok: boolean; status: number; error?: string }> {
  const res = await send(`/api/appointments/${appointmentId}/deposit`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ screenshotKey }),
  });
  if (res.ok) return { ok: true, status: res.status };
  const body = (await res.json().catch(() => ({}))) as { error?: string };
  return { ok: false, status: res.status, error: body.error };
}
