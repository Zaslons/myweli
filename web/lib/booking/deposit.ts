/// Consumer deposit-proof upload (module online-booking K2 — the app's
/// pay-later flow on web): 1) the BFF presigns a private deposit upload
/// (`/api/uploads/sign`, purpose fixed server-side), 2) the bytes POST
/// **directly to storage** (never through our API), 3) the opaque key is
/// attached to the booking via `POST /api/appointments/{id}/deposit`.
/// Unit-tested with a mocked fetch.

type SignResponse = {
  method?: string;
  uploadUrl?: string;
  fields?: Record<string, string>;
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

  const form = new FormData();
  for (const [k, v] of Object.entries(sign.fields ?? {})) form.append(k, v);
  form.append('file', file);

  const up = await fetch(sign.uploadUrl, {
    method: sign.method ?? 'POST',
    body: form,
  });
  if (!up.ok) return null; // storage POST returns 2xx (e.g. 204)
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
