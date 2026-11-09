// Design: docs/design/web-pro-upload-resize.md (the preparation, decision 107)
// · docs/design/web-pro-network-failure.md §5 (a sign with no network)
import { compressForUpload, megapixelBucket, type PrepareResult } from '../image/compress';
import { putToStorage, reportUploadFailure } from '../upload-telemetry';
/// Browser image upload for the pro Médias editors:
/// 0) prepare the photo as the app does — short side ≤ 1600, long side
///    ≤ 2400, JPEG 80, orientation applied, no metadata (`lib/image/compress.ts`),
/// 1) ask the pro BFF to presign (`/api/pro/uploads/sign`) — always
///    `image/jpeg`, as the app does,
/// 2) PUT the PREPARED bytes **directly to storage** (R2; never through our API),
/// 3) return the public URL to save on the gallery/before-after.
/// Unit-tested with a mocked fetch and an injected `compress`.

type SignResponse = {
  method?: string;
  uploadUrl?: string;
  headers?: Record<string, string>;
  publicUrl?: string;
  key?: string;
  maxBytes?: number;
};

/// Why a Pro photo did not upload. `unreadable` and `too_large` are the
/// person's to fix by choosing another image, so each has its own sentence;
/// `failed` keeps the sentence each surface already shows.
export type ProUploadFailure = 'unreadable' | 'too_large' | 'failed';
export type ProUpload = { ok: true; url: string } | { ok: false; reason: ProUploadFailure };

/// The two sentences (web-pro-upload-resize.md §2.6). « image », not
/// « photo », because the logo says the same.
export const UPLOAD_UNREADABLE_MESSAGE =
  'Cette image n’a pas pu être lue. Choisissez une image JPEG, PNG ou WebP.';
export const UPLOAD_TOO_LARGE_MESSAGE =
  'Cette image est trop grande pour être préparée ici. Choisissez une image plus petite.';

/// The sentence for a failed upload: one of the two above, else the
/// surface's own (« Échec de l’envoi », « Échec de l’envoi du logo. »…).
export function uploadFailureMessage(reason: ProUploadFailure, fallback: string): string {
  if (reason === 'unreadable') return UPLOAD_UNREADABLE_MESSAGE;
  if (reason === 'too_large') return UPLOAD_TOO_LARGE_MESSAGE;
  return fallback;
}

/// The app's `ImageCompressor` seam: tests inject a fake (jsdom has no canvas).
export type ProUploadDeps = { compress?: (file: File) => Promise<PrepareResult> };

const FAILED: ProUpload = { ok: false, reason: 'failed' };

/// The presign request, to the pro BFF (same origin). No answer — no network
/// — is `null`, the failed upload every caller already shows, never a throw
/// that leaves the photo button spinning. Not reported: a same-origin request
/// that never answers is the person's network, not storage refusing us nor a
/// CORS rule, which is what the telemetry exists to find
/// (docs/design/web-pro-network-failure.md §5).
async function requestSign(
  contentType: string,
  purpose: 'logo' | 'gallery' | 'kyc',
): Promise<Response | null> {
  try {
    return await fetch('/api/pro/uploads/sign', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ contentType, purpose }),
    });
  } catch {
    return null;
  }
}

function reportPrepare(
  purpose: 'gallery' | 'logo',
  reason: ProUploadFailure,
  file: File,
  pixels: number | null,
): void {
  reportUploadFailure('prepare', purpose, {
    prepare: { reason, inputType: file.type, megapixels: megapixelBucket(pixels) },
  });
}

/// Compress, THEN sign — the app's order (`api_image_upload_service.dart`):
/// a file that cannot be read never spends a signature (the logo is signed
/// at 10 per hour).
async function uploadProImage(
  file: File,
  purpose: 'gallery' | 'logo',
  compress: (file: File) => Promise<PrepareResult>,
): Promise<ProUpload> {
  const prepared = await compress(file);
  if (!prepared.ok) {
    reportPrepare(purpose, prepared.reason, file, prepared.pixels);
    return { ok: false, reason: prepared.reason };
  }
  const signRes = await requestSign('image/jpeg', purpose);
  if (!signRes) return FAILED;
  if (!signRes.ok) {
    reportUploadFailure('sign', purpose, { status: signRes.status });
    return FAILED;
  }
  const sign = (await signRes.json().catch(() => ({}))) as SignResponse;
  if (!sign.uploadUrl || !sign.publicUrl) {
    reportUploadFailure('response', purpose);
    return FAILED;
  }
  // The server's advisory cap (5 MiB today): R2 ignores it on a PUT and the
  // claim refuses anything above it, so a larger file is not sent at all.
  // A photo never reaches it (2.44 MB worst case, measured); it stays as the
  // backstop because the number is the server's.
  if (typeof sign.maxBytes === 'number' && sign.maxBytes > 0 && prepared.blob.size > sign.maxBytes) {
    reportPrepare(purpose, 'too_large', file, prepared.pixels);
    return { ok: false, reason: 'too_large' };
  }

  // Raw PUT, not a multipart POST: Cloudflare R2 does not implement presigned
  // POST and answers one with 501 NotImplemented. The signature covers these
  // headers, so send exactly them — a different content-type than the one
  // signed is a 403 from storage.
  // docs/design/backend-r2-presigned-put.md
  const ok = await putToStorage(
    sign.uploadUrl,
    { method: sign.method ?? 'PUT', headers: sign.headers ?? {}, body: prepared.blob },
    purpose,
  );
  if (!ok) return FAILED; // storage returns 200 on a successful PUT
  return { ok: true, url: sign.publicUrl };
}

/// The salon's brand mark — the gallery helper's shape with its OWN purpose
/// (the purpose string is the storage namespace; salon-logo.md §5) and its
/// own telemetry surface, so a CORS or signature failure names the feature.
export function uploadLogoImage(
  file: File,
  { compress = compressForUpload }: ProUploadDeps = {},
): Promise<ProUpload> {
  return uploadProImage(file, 'logo', compress);
}

/// Médias photos (the first is the salon cover), before/after, staff photos.
export function uploadGalleryImage(
  file: File,
  { compress = compressForUpload }: ProUploadDeps = {},
): Promise<ProUpload> {
  return uploadProImage(file, 'gallery', compress);
}

/// KYC document upload (docs/design/web-pro-kyc.md): same presign +
/// direct-to-storage POST, but `purpose=kyc` → a PRIVATE bucket under the
/// caller's `kyc/{accountId}/` prefix; only the opaque key comes back.
/// **Not prepared**: identity papers and PDFs, which the app does not scale down
/// either (web-pro-upload-resize.md §1.3) — the file goes as picked.
export async function uploadKycDocument(
  file: File,
): Promise<{ key: string; fileName: string } | null> {
  const signRes = await requestSign(file.type, 'kyc');
  if (!signRes) return null;
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
