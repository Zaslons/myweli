import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/// docs/design/web-pro-browser-push.md §5 — the glue to the browser and
/// Firebase. **Found by reading Firebase's own source, 2026-10-20**: it waits
/// for a service worker to become ACTIVE only when it registers its own
/// (`registerDefaultSw` → `waitForRegistrationActive`); a registration passed
/// in (`serviceWorkerRegistration`, ours) is used as it is, and
/// `pushManager.subscribe` on a still-installing worker throws — the very
/// first « Activer » would have said « L’activation a échoué. ». The e2e
/// cannot see it: its build names the token before Firebase is reached.

const getToken = vi.fn(async () => 'fcm-token');
const deleteToken = vi.fn(async () => true);
vi.mock('@firebase/messaging', () => ({
  getMessaging: () => ({}),
  getToken: (...a: unknown[]) => getToken(...(a as [])),
  deleteToken: (...a: unknown[]) => deleteToken(...(a as [])),
}));
vi.mock('@firebase/app', () => ({
  getApps: () => [],
  initializeApp: (c: unknown) => ({ c }),
}));

const ENV = {
  NEXT_PUBLIC_FIREBASE_API_KEY: 'k',
  NEXT_PUBLIC_FIREBASE_PROJECT_ID: 'myweli',
  NEXT_PUBLIC_FIREBASE_APP_ID: '1:2:web:3',
  NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID: '2',
  NEXT_PUBLIC_FIREBASE_VAPID_KEY: 'BPub',
};

type FakeWorker = { state: string; onstatechange: ((e: { target: FakeWorker }) => void) | null };

function installingRegistration() {
  const worker: FakeWorker = { state: 'installing', onstatechange: null };
  const reg = { installing: worker as FakeWorker | null, waiting: null, active: null as FakeWorker | null };
  return {
    reg,
    activate() {
      worker.state = 'activated';
      reg.active = worker;
      reg.installing = null;
      worker.onstatechange?.({ target: worker });
    },
  };
}

async function freshDeps() {
  vi.resetModules();
  const mod = await import('../lib/pro/browser-push-deps');
  return mod.getBrowserPushDeps();
}

describe('browser-push-deps — the token waits for an ACTIVE worker', () => {
  beforeEach(() => {
    for (const [k, v] of Object.entries(ENV)) vi.stubEnv(k, v);
    getToken.mockClear();
  });
  afterEach(() => {
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
  });

  it('registers /pro/push-sw.js at /pro/, and asks Firebase only once it is active', async () => {
    const sw = installingRegistration();
    const register = vi.fn(async () => sw.reg);
    vi.stubGlobal('navigator', { ...navigator, serviceWorker: { register } });
    const deps = await freshDeps();
    const token = deps!.token();
    await new Promise((r) => setTimeout(r, 10));
    expect(register).toHaveBeenCalledWith('/pro/push-sw.js', { scope: '/pro/' });
    expect(getToken).not.toHaveBeenCalled();
    sw.activate();
    expect(await token).toBe('fcm-token');
    expect(getToken).toHaveBeenCalledTimes(1);
    const [, options] = getToken.mock.calls[0] as unknown as [unknown, { vapidKey: string; serviceWorkerRegistration: unknown }];
    expect(options.vapidKey).toBe('BPub');
    expect(options.serviceWorkerRegistration).toBe(sw.reg);
  });

  it('an already-active worker goes straight on', async () => {
    const sw = installingRegistration();
    sw.activate();
    vi.stubGlobal('navigator', { ...navigator, serviceWorker: { register: async () => sw.reg } });
    const deps = await freshDeps();
    expect(await deps!.token()).toBe('fcm-token');
  });

  it('a worker that never activates fails the token (bounded) — the row then says so', async () => {
    vi.useFakeTimers();
    try {
      const sw = installingRegistration();
      vi.stubGlobal('navigator', { ...navigator, serviceWorker: { register: async () => sw.reg } });
      const deps = await freshDeps();
      const token = deps!.token();
      const settled = expect(token).rejects.toThrow();
      await vi.advanceTimersByTimeAsync(10_000);
      await settled;
      expect(getToken).not.toHaveBeenCalled();
    } finally {
      vi.useRealTimers();
    }
  });

  it('not configured → no deps at all', async () => {
    vi.stubEnv('NEXT_PUBLIC_FIREBASE_VAPID_KEY', '');
    expect(await freshDeps()).toBeNull();
  });
});
