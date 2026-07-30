/// Consumer review-photo upload + the form's photo-list rules (parity 2.13).
/// Mirrors the app's submit sheet: ≤3 photos, direct-to-storage upload.
/// Pure list helpers are unit-tested; the upload is the deposit pipeline with
/// `purpose=review` (public — review tiles render the URLs).

export const MAX_REVIEW_PHOTOS = 3;

export function canAddPhoto(urls: string[]): boolean {
  return urls.length < MAX_REVIEW_PHOTOS;
}

export function addPhoto(urls: string[], url: string): string[] {
  return canAddPhoto(urls) ? [...urls, url] : urls;
}

export function removePhoto(urls: string[], index: number): string[] {
  return urls.filter((_, i) => i !== index);
}

type SignResponse = {
  method?: string;
  uploadUrl?: string;
  fields?: Record<string, string>;
  publicUrl?: string;
};

/// Sign (`purpose=review`) → POST the bytes straight to storage → the public
/// URL the review will carry. Null on any failure.
export async function uploadReviewPhoto(file: File): Promise<string | null> {
  const signRes = await fetch('/api/uploads/sign', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ contentType: file.type, purpose: 'review' }),
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
  return up.ok ? sign.publicUrl : null;
}

/// Report a review for moderation (parity 2.14 — FR-REV-005).
export async function reportReview(
  reviewId: string,
  reason?: string,
): Promise<{ ok: boolean; status: number }> {
  const res = await fetch(`/api/reviews/${reviewId}/report`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(reason?.trim() ? { reason: reason.trim() } : {}),
  });
  return { ok: res.ok, status: res.status };
}
