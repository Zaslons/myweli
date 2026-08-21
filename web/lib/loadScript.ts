/// Loads a third-party `<script>` on demand, once.
///
/// **Extracted because there were three copies** — one private to
/// `LoginOptions.tsx` and two inlined verbatim in the pro components — and all
/// three shared a defect their own callers had to work around.
///
/// **The defect: the old check was `document.querySelector('script[src=…]')`,
/// which asks whether a TAG EXISTS, not whether it has LOADED.** A second
/// caller arriving while the first script was still in flight resolved
/// immediately with `window.google` still undefined. Every call site survived
/// only by null-checking the global afterwards — a mitigation repeated three
/// times for a bug that belongs here. This version listens to the existing
/// tag's `load` event instead, and memoises the promise so concurrent callers
/// share one download.
///
/// **A rejection is deliberately not cached.** Caching it would let one network
/// blip disable the sign-in button for the rest of the session, with a retry
/// that silently returns the old failure.
const inFlight = new Map<string, Promise<void>>();

export function loadScript(src: string): Promise<void> {
  const cached = inFlight.get(src);
  if (cached) return cached;

  const p = new Promise<void>((resolve, reject) => {
    const fail = () => reject(new Error('script_load_failed'));
    const existing = document.querySelector<HTMLScriptElement>(
      `script[src="${src}"]`,
    );
    if (existing) {
      // Added by someone else (or by a previous, evicted promise). If it has
      // already finished, `load` will never fire again — hence the marker.
      if (existing.dataset.loaded === 'true') return resolve();
      existing.addEventListener('load', () => resolve(), { once: true });
      existing.addEventListener('error', fail, { once: true });
      return;
    }
    const s = document.createElement('script');
    s.src = src;
    s.async = true;
    s.addEventListener(
      'load',
      () => {
        s.dataset.loaded = 'true';
        resolve();
      },
      { once: true },
    );
    s.addEventListener('error', fail, { once: true });
    document.head.appendChild(s);
  });

  inFlight.set(src, p);
  p.catch(() => inFlight.delete(src));
  return p;
}
