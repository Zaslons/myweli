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
/// **A rejection is deliberately not cached**, so a retry is a real attempt
/// rather than a replay of the old failure — and the failed TAG is discarded
/// with it, or the retry finds a corpse and hangs instead.
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
      // Already finished: `load` will never fire again, hence the marker.
      if (existing.dataset.loaded === 'true') return resolve();

      // **A tag that is neither loaded nor in flight is a corpse, and
      // subscribing to it hangs forever.** `inFlight` was checked above and
      // missed, so nothing is awaiting this element; its `load`/`error` pair
      // already fired and both listeners were registered `{ once: true }`.
      // Attaching new ones waits for events that can never come again: the
      // promise never settles, the caller's `catch` never runs, and a button
      // that awaits it stays disabled for the life of the page.
      //
      // That is precisely the failure this file exists to remove, and its
      // first version shipped with it — the rejected promise was evicted from
      // the cache while the dead tag was left in the document, so the SECOND
      // tap after any failed load hung. Reachable whenever the first load
      // fails: offline, a blocked host, an ad blocker — which is exactly when
      // someone taps again.
      existing.remove();
    }
    const s = document.createElement('script');
    s.src = src;
    s.async = true;
    // Removed at failure, not merely skipped later: a dead tag left in the
    // document is what the `existing` branch above has to defend against, and
    // the narrower the window in which one exists, the better.
    s.addEventListener(
      'load',
      () => {
        s.dataset.loaded = 'true';
        resolve();
      },
      { once: true },
    );
    s.addEventListener(
      'error',
      () => {
        s.remove();
        fail();
      },
      { once: true },
    );
    document.head.appendChild(s);
  });

  inFlight.set(src, p);
  p.catch(() => inFlight.delete(src));
  return p;
}
