/// Browser image upload for the pro Médias editors:
/// 1) ask the pro BFF to presign (`/api/pro/uploads/sign`),
/// 2) POST the bytes **directly to storage** (R2; never through our API),
/// 3) return the public URL to save on the gallery/before-after.
/// Unit-tested with a mocked fetch.

type SignResponse = {
  method?: string;
  uploadUrl?: string;
  fields?: Record<string, string>;
  publicUrl?: string;
};

export async function uploadGalleryImage(file: File): Promise<string | null> {
  const signRes = await fetch('/api/pro/uploads/sign', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ contentType: file.type, purpose: 'gallery' }),
  });
  if (!signRes.ok) return null;
  const sign = (await signRes.json().catch(() => ({}))) as SignResponse;
  if (!sign.uploadUrl || !sign.publicUrl) return null;

  const form = new FormData();
  for (const [k, v] of Object.entries(sign.fields ?? {})) form.append(k, v);
  form.append('file', file);

  const up = await fetch(sign.uploadUrl, {
    method: sign.method ?? 'POST',
    body: form,
  });
  if (!up.ok) return null; // storage POST returns 2xx (e.g. 204)
  return sign.publicUrl;
}
