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
/// person's to fix by choosing another image, `blocked` by choosing another
/// browser, so each has its own sentence; `failed` keeps the sentence each
/// surface already shows. `aborted`: the page was left — nothing to say.
export type ProUploadFailure = 'unreadable' | 'too_large' | 'blocked' | 'failed' | 'aborted';
export type ProUpload = { ok: true; url: string } | { ok: false; reason: ProUploadFailure };

/// The sentences of §2.6 (web-pro-upload-resize.md). « image », not
/// « photo », because the logo says the same.
export const UPLOAD_UNREADABLE_MESSAGE =
  'Cette image n’a pas pu être lue. Choisissez une image JPEG, PNG ou WebP.';
export const UPLOAD_TOO_LARGE_MESSAGE =
  'Cette image est trop grande pour être préparée ici. Choisissez une image plus petite.';
/// The browser alters what a canvas gives back (anti-fingerprinting): the
/// photo would arrive blank or as noise (web-pro-upload-resize.md §2.6).
export const UPLOAD_BLOCKED_MESSAGE =
  'Votre navigateur empêche de préparer cette image. Essayez avec un autre navigateur.';

/// The sentence for a failed upload: one of those above, else the
/// surface's own (« Échec de l’envoi », « Échec de l’envoi du logo. »…).
export function uploadFailureMessage(reason: ProUploadFailure, fallback: string): string {
  if (reason === 'unreadable') return UPLOAD_UNREADABLE_MESSAGE;
  if (reason === 'too_large') return UPLOAD_TOO_LARGE_MESSAGE;
  if (reason === 'blocked') return UPLOAD_BLOCKED_MESSAGE;
  return fallback;
}

/// The app's `ImageCompressor` seam: tests inject a fake (jsdom has no canvas).
/// `signal`: aborted when the page that asked is left — nothing is signed or
/// sent after that (review F3: leaving Médias while a photo was being
/// prepared still put it in the public gallery).
export type ProUploadDeps = {
  compress?: (file: File) => Promise<PrepareResult>;
  signal?: AbortSignal;
};

const FAILED: ProUpload = { ok: false, reason: 'failed' };
const ABORTED: ProUpload = { ok: false, reason: 'aborted' };

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
  reason: 'unreadable' | 'too_large' | 'blocked' | 'failed',
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
  { compress = compressForUpload, signal }: ProUploadDeps,
): Promise<ProUpload> {
  const prepared = await compress(file);
  if (signal?.aborted) return ABORTED;
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
  // Left while the signature was out: the photo is not sent.
  if (signal?.aborted) return ABORTED;

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
export function uploadLogoImage(file: File, deps: ProUploadDeps = {}): Promise<ProUpload> {
  return uploadProImage(file, 'logo', deps);
}

/// Médias photos (the first is the salon cover), before/after, staff photos.
export function uploadGalleryImage(file: File, deps: ProUploadDeps = {}): Promise<ProUpload> {
  return uploadProImage(file, 'gallery', deps);
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
