import * as Sentry from '@sentry/nextjs';

/// What a `prepare` report says (web-pro-upload-resize.md §6.4).
export type PrepareFailureDetail = {
  reason: 'unreadable' | 'too_large' | 'blocked' | 'failed';
  /// The picked file's `type` as the browser gave it; `uploadInputType` keeps
  /// it only when it is MIME-shaped.
  inputType: string;
  megapixels: '<12' | '12-24' | '24-50' | '50-64' | '>64' | 'unknown';
};

/// A browser-given MIME type, kept only when it looks like one
/// (`image/heic`), else `unknown` — a tag must never carry anything a person
/// typed or named.
export function uploadInputType(type: string): string {
  const t = type.trim().toLowerCase();
  return /^[a-z]{1,32}\/[a-z0-9.+-]{1,64}$/.test(t) ? t : 'unknown';
}

/// Reports a failed browser upload, because nothing else does.
///
/// **The gap this closes, found while pointing Vercel Previews at staging.**
/// Every browser upload — gallery, before/after, KYC, deposit proof, review
/// photos — PUTs **directly to Cloudflare R2** with a presigned URL, not
/// through our API. R2's CORS allowlist is exact-match per bucket, and
/// staging's is `["http://localhost:3000"]`, so on a preview (a fresh Vercel
/// hostname per deployment) every one of those PUTs is refused by the browser
/// before it leaves.
///
/// The user does see « Le téléversement a échoué. » — the callers handle a
/// `null`. **We** saw nothing: no log, no Sentry event, no metric. So "uploads
/// are broken on every preview" would have looked exactly like "nobody tried",
/// and the same blindness covers a real production upload failure.
///
/// A browser cannot read a CORS rejection — `fetch` rejects with an opaque
/// `TypeError` and no status — so [stage] and the presence of a status are the
/// signal: a `put` failure with **no** status is the CORS shape, a `put`
/// failure **with** one is storage answering (403 = signature, 501 = a POST
/// where R2 wants a PUT). That distinction is the whole point of recording it.
///
/// **`prepare`** (docs/design/web-pro-upload-resize.md §6.4) is the browser
/// failing to prepare a Pro photo before anything is signed: it carries the
/// reason, the picked file's MIME type and its size in coarse megapixel bands —
/// enough to learn whether HEIC actually arrives before buying a decoder, and
/// nothing about the person: **never the file name**, never pixels or bytes.
/// It is a `warning`, not an `error`: every HEIC picked in Chrome lands here,
/// the person was told what to do, and nothing of ours broke (review F9).
export function reportUploadFailure(
  stage: 'sign' | 'put' | 'response' | 'prepare',
  purpose: string,
  detail?: { status?: number; cause?: unknown; prepare?: PrepareFailureDetail },
): void {
  const status = detail?.status;
  const likelyCors = stage === 'put' && status === undefined;
  const prepare = detail?.prepare;
  Sentry.captureMessage(`upload_failed:${purpose}:${stage}`, {
    level: stage === 'prepare' ? 'warning' : 'error',
    tags: {
      upload_stage: stage,
      upload_purpose: purpose,
      // Deliberately a tag: this is the field you group by when asking
      // "is storage refusing us, or is the browser?".
      upload_likely_cors: String(likelyCors),
      ...(prepare
        ? {
            upload_prepare_reason: prepare.reason,
            upload_input_type: uploadInputType(prepare.inputType),
            upload_megapixels: prepare.megapixels,
          }
        : {}),
    },
    // No file name, no URL, no bytes — `lib/sentry-scrub.ts` strips the request
    // anyway, and an upload's filename is user content.
    extra: { status: status ?? null },
  });
}

/// `fetch` that never throws, so a CORS rejection becomes a reportable outcome
/// rather than an unhandled rejection that the caller's `catch` turns into the
/// same generic `null`.
export async function putToStorage(
  url: string,
  init: RequestInit,
  purpose: string,
): Promise<boolean> {
  let res: Response;
  try {
    res = await fetch(url, init);
  } catch (cause) {
    // The CORS case lands here: opaque TypeError, no status to report.
    reportUploadFailure('put', purpose, { cause });
    return false;
  }
  if (!res.ok) {
    reportUploadFailure('put', purpose, { status: res.status });
    return false;
  }
  return true;
}
