import { beforeEach, describe, expect, it, vi } from 'vitest';

const captureMessage = vi.fn();
vi.mock('@sentry/nextjs', () => ({ captureMessage: (...a: unknown[]) => captureMessage(...a) }));

const { putToStorage } = await import('../lib/upload-telemetry');

/// Uploads that fail are reported, and the report says WHICH KIND of failure.
///
/// Found while pointing Vercel Previews at staging. Every browser upload PUTs
/// **directly to Cloudflare R2**, whose CORS allowlist is exact-match per
/// bucket — staging's is `["http://localhost:3000"]`, and Vercel mints a new
/// hostname per deployment. So uploads are refused on every preview.
///
/// The user always saw « Le téléversement a échoué. » — the callers handle the
/// `null`. **We** saw nothing. "Uploads are broken on every preview" and
/// "nobody tried to upload" produced identical telemetry, which is why this
/// went unnoticed while the R2 allowlist sat at localhost for days.
describe('putToStorage reports failures, and distinguishes them', () => {
  beforeEach(() => {
    captureMessage.mockClear();
  });

  it('a CORS rejection is reported as likely-CORS', async () => {
    // A browser cannot read a cross-origin rejection: `fetch` rejects with an
    // opaque TypeError carrying no status. That absence IS the signal.
    vi.stubGlobal(
      'fetch',
      vi.fn().mockRejectedValue(new TypeError('Failed to fetch')),
    );
    const ok = await putToStorage('https://r2.example/x', { method: 'PUT' }, 'gallery');

    expect(ok).toBe(false);
    expect(captureMessage).toHaveBeenCalledTimes(1);
    const [msg, opts] = captureMessage.mock.calls[0] as [string, any];
    expect(msg).toBe('upload_failed:gallery:put');
    expect(opts.tags.upload_likely_cors).toBe('true');
    expect(opts.extra.status).toBeNull();
  });

  it('storage answering with a status is NOT likely-CORS', async () => {
    // 403 = the signature is wrong; 501 = a POST where R2 wants a PUT. Both
    // are our bug, not the browser's — and grouping them with CORS failures
    // would send the next person to the wrong place entirely.
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: false, status: 403 }));
    const ok = await putToStorage('https://r2.example/x', { method: 'PUT' }, 'deposit');

    expect(ok).toBe(false);
    const [msg, opts] = captureMessage.mock.calls[0] as [string, any];
    expect(msg).toBe('upload_failed:deposit:put');
    expect(opts.tags.upload_likely_cors).toBe('false');
    expect(opts.extra.status).toBe(403);
  });

  it('a successful PUT reports nothing', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, status: 200 }));
    expect(await putToStorage('https://r2.example/x', { method: 'PUT' }, 'kyc')).toBe(true);
    expect(captureMessage).not.toHaveBeenCalled();
  });

  it('never puts the file name or the signed URL in the event', async () => {
    // The signed URL carries credentials in its query string and a filename is
    // user content. `lib/sentry-scrub.ts` strips the request, but this event is
    // constructed by hand and would bypass none of it — so assert directly.
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('nope')));
    await putToStorage('https://r2.example/secret?X-Amz-Signature=abc', { method: 'PUT' }, 'kyc');
    const serialized = JSON.stringify(captureMessage.mock.calls[0]);
    expect(serialized).not.toContain('X-Amz-Signature');
    expect(serialized).not.toContain('r2.example');
  });
});
