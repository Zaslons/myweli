import { putToStorage, reportUploadFailure } from '../upload-telemetry';
/// Browser image upload for the pro Médias editors:
/// 1) ask the pro BFF to presign (`/api/pro/uploads/sign`),
/// 2) POST the bytes **directly to storage** (R2; never through our API),
/// 3) return the public URL to save on the gallery/before-after.
/// Unit-tested with a mocked fetch.

type SignResponse = {
  method?: string;
  uploadUrl?: string;
  headers?: Record<string, string>;
  publicUrl?: string;
  key?: string;
};

/// The salon's brand mark — the gallery helper's shape with its OWN purpose
/// (the purpose string is the storage namespace; salon-logo.md §5) and its
/// own telemetry surface, so a CORS or signature failure names the feature.
export async function uploadLogoImage(file: File): Promise<string | null> {
  const signRes = await fetch('/api/pro/uploads/sign', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ contentType: file.type, purpose: 'logo' }),
  });
  if (!signRes.ok) {
    reportUploadFailure('sign', 'logo', { status: signRes.status });
    return null;
  }
  const sign = (await signRes.json().catch(() => ({}))) as SignResponse;
  if (!sign.uploadUrl || !sign.publicUrl) {
    reportUploadFailure('response', 'logo');
    return null;
  }
  const ok = await putToStorage(
    sign.uploadUrl,
    { method: sign.method ?? 'PUT', headers: sign.headers ?? {}, body: file },
    'logo',
  );
  if (!ok) return null;
  return sign.publicUrl;
}

export async function uploadGalleryImage(file: File): Promise<string | null> {
  const signRes = await fetch('/api/pro/uploads/sign', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ contentType: file.type, purpose: 'gallery' }),
  });
  if (!signRes.ok) {
    reportUploadFailure('sign', 'gallery', { status: signRes.status });
    return null;
  }
  const sign = (await signRes.json().catch(() => ({}))) as SignResponse;
  if (!sign.uploadUrl || !sign.publicUrl) {
    reportUploadFailure('response', 'gallery');
    return null;
  }

  // Raw PUT, not a multipart POST: Cloudflare R2 does not implement presigned
  // POST and answers one with 501 NotImplemented. The signature covers these
  // headers, so send exactly them — a different content-type than the one
  // signed is a 403 from storage.
  // docs/design/backend-r2-presigned-put.md
  const ok = await putToStorage(
    sign.uploadUrl,
    { method: sign.method ?? 'PUT', headers: sign.headers ?? {}, body: file },
    'gallery',
  );
  if (!ok) return null; // storage returns 200 on a successful PUT
  return sign.publicUrl;
}

/// KYC document upload (docs/design/web-pro-kyc.md): same presign +
/// direct-to-storage POST, but `purpose=kyc` → a PRIVATE bucket under the
/// caller's `kyc/{accountId}/` prefix; only the opaque key comes back.
export async function uploadKycDocument(
  file: File,
): Promise<{ key: string; fileName: string } | null> {
  const signRes = await fetch('/api/pro/uploads/sign', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ contentType: file.type, purpose: 'kyc' }),
  });
  if (!signRes.ok) {
    reportUploadFailure('sign', 'kyc', { status: signRes.status });
    return null;
  }
  const sign = (await signRes.json().catch(() => ({}))) as SignResponse;
  if (!sign.uploadUrl || !sign.key) {
    reportUploadFailure('response', 'kyc');
    return null;
  }

  // Raw PUT, not a multipart POST: R2 does not implement presigned POST (501
  // NotImplemented). The signature covers these headers — send exactly them.
  // docs/design/backend-r2-presigned-put.md
  const ok = await putToStorage(
    sign.uploadUrl,
    { method: sign.method ?? 'PUT', headers: sign.headers ?? {}, body: file },
    'kyc',
  );
  if (!ok) return null;
  return { key: sign.key, fileName: file.name };
}
