import { beforeEach, describe, expect, it, vi } from 'vitest';
import { loadScript } from '../lib/loadScript';

/// **The retry after a failed load, which is the whole reason this helper
/// exists — and which its first version got wrong.**
///
/// The rejected promise was evicted from the in-flight cache but the dead
/// `<script>` tag was left in the document. The next call found that tag, saw no
/// `dataset.loaded` marker, and subscribed to `load`/`error` — events that had
/// already fired, with listeners registered `{ once: true }`. The promise never
/// settled, so `GoogleSignInButton` stayed in `phase === 'loading'` with its
/// button `disabled`, and the Apple path (same helper) never reached the
/// `finally` that clears `busy`. The sign-in card looked alive and did nothing.
///
/// Reachable whenever the first load fails — offline, a blocked host, an ad
/// blocker — which is exactly when a person taps again.
/// `inFlight` is module state and survives between cases — a shared src makes
/// the second test read the first one's cached promise, append nothing, and
/// fail for a reason that has nothing to do with what it is testing. One src
/// per case.
let n = 0;
const nextSrc = () => `https://example.test/thing-${n++}.js`;

/// jsdom does not fetch scripts, so nothing ever dispatches. This makes the
/// appended tag behave like a real one: `outcome` decides which event fires.
function autoDispatch(outcome: 'load' | 'error') {
  return vi
    .spyOn(document.head, 'appendChild')
    .mockImplementation(((node: Node) => {
      Object.getPrototypeOf(document.head).appendChild.call(document.head, node);
      queueMicrotask(() => node.dispatchEvent(new Event(outcome)));
      return node;
    }) as typeof document.head.appendChild);
}

/// A hang is the failure mode under test, so it must be turned into a rejection
/// rather than allowed to stall the suite.
function within(ms: number, p: Promise<unknown>) {
  return Promise.race([
    p,
    new Promise((_, rej) => setTimeout(() => rej(new Error('HUNG')), ms)),
  ]);
}

describe('loadScript', () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    document.head.querySelectorAll('script').forEach((s) => s.remove());
  });

  /// **The behaviour.** Deliberately asserts only that the retry SETTLES —
  /// nothing about how. There are two independent defences (the tag is dropped
  /// at failure, and a corpse found later is discarded), and pinning either one
  /// here would make this test fail when the OTHER is removed, reporting a
  /// hang that did not happen. The defences get their own tests below.
  it('A RETRY AFTER A FAILURE IS A REAL ATTEMPT, NOT A HANG', async () => {
    const SRC = nextSrc();
    const first = autoDispatch('error');
    await expect(loadScript(SRC)).rejects.toThrow('script_load_failed');
    first.mockRestore();

    autoDispatch('error');
    await expect(
      within(1000, loadScript(SRC)),
      'the second attempt hung instead of failing — the caller awaits forever '
        + 'and its button stays disabled for the life of the page',
    ).rejects.toThrow('script_load_failed');
  });

  /// Defence one, on its own: nothing dead is left behind to be found.
  it('the failed tag is discarded at failure', async () => {
    const SRC = nextSrc();
    autoDispatch('error');
    await expect(loadScript(SRC)).rejects.toThrow();
    expect(document.querySelector(`script[src="${SRC}"]`)).toBeNull();
  });

  /// Defence two, on its own: a corpse that got there some other way — an
  /// external tag, or a future change that stops cleaning up — is discarded
  /// rather than subscribed to.
  it('a pre-existing dead tag is discarded, not awaited', async () => {
    const SRC = nextSrc();
    const corpse = document.createElement('script');
    corpse.src = SRC; // no dataset.loaded, and nothing is awaiting it
    document.head.appendChild(corpse);

    autoDispatch('load');
    await expect(
      within(1000, loadScript(SRC)),
      'subscribed to a tag whose load/error already fired',
    ).resolves.toBeUndefined();
  });

  it('and a retry can SUCCEED after a failure', async () => {
    const SRC = nextSrc();
    const first = autoDispatch('error');
    await expect(loadScript(SRC)).rejects.toThrow();
    first.mockRestore();

    autoDispatch('load');
    await expect(within(1000, loadScript(SRC))).resolves.toBeUndefined();
  });

  it('resolves immediately for an already-loaded tag', async () => {
    const SRC = nextSrc();
    autoDispatch('load');
    await loadScript(SRC);
    // Second call takes the marker branch: no new tag, no waiting on events
    // that will never fire again.
    await expect(within(1000, loadScript(SRC))).resolves.toBeUndefined();
    expect(document.querySelectorAll(`script[src="${SRC}"]`)).toHaveLength(1);
  });

  it('concurrent callers share one download', async () => {
    const SRC = nextSrc();
    const spy = autoDispatch('load');
    const [a, b] = [loadScript(SRC), loadScript(SRC)];
    await Promise.all([a, b]);
    expect(a).toBe(b);
    expect(spy).toHaveBeenCalledTimes(1);
  });
});
