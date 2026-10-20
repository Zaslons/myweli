import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  type BrowserPushDeps,
  type KeyStore,
  type PushPermission,
  PUSH_ASKED_KEY,
  PUSH_OFF_KEY,
  bandOffered,
  disableBrowserPush,
  enableBrowserPush,
  firebaseWebConfig,
  isPhoneDevice,
  pushRowState,
  registerIfGranted,
  supportsBrowserPush,
  unregisterBeforeSignOut,
} from '../lib/pro/browser-push';

/// docs/design/web-pro-browser-push.md — the salon's browser notifications:
/// the band once (Q2, like the app), the row's states (§3), computers only
/// (Q3), and the four moves — switch on, switch off, re-register at sign-in,
/// unregister before sign-out.

function memoryStore(init: Record<string, string> = {}): KeyStore & { data: Record<string, string> } {
  const data = { ...init };
  return {
    data,
    get: (k) => data[k] ?? null,
    set: (k, v) => {
      data[k] = v;
    },
    remove: (k) => {
      delete data[k];
    },
  };
}

function fakeDeps(over: Partial<BrowserPushDeps> & { perm?: PushPermission; answer?: PushPermission } = {}) {
  let perm: PushPermission = over.perm ?? 'default';
  const calls: string[] = [];
  const deps: BrowserPushDeps & { calls: string[]; store: ReturnType<typeof memoryStore> } = {
    calls,
    supported: () => true,
    phone: () => false,
    permission: () => perm,
    requestPermission: vi.fn(async () => {
      calls.push('request');
      perm = over.answer ?? 'granted';
      return perm;
    }),
    token: vi.fn(async () => {
      calls.push('token');
      return 'tok-1';
    }),
    dropToken: vi.fn(async () => {
      calls.push('drop');
    }),
    register: vi.fn(async (t: string) => {
      calls.push(`register:${t}`);
      return true;
    }),
    unregister: vi.fn(async (t: string) => {
      calls.push(`unregister:${t}`);
      return true;
    }),
    ...over,
    store: (over.store as ReturnType<typeof memoryStore>) ?? memoryStore(),
  };
  return deps;
}

describe('firebaseWebConfig — the five public values, or nothing', () => {
  afterEach(() => vi.unstubAllEnvs());
  const all = {
    NEXT_PUBLIC_FIREBASE_API_KEY: 'k',
    NEXT_PUBLIC_FIREBASE_PROJECT_ID: 'myweli',
    NEXT_PUBLIC_FIREBASE_APP_ID: '1:2:web:3',
    NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID: '2',
    NEXT_PUBLIC_FIREBASE_VAPID_KEY: 'BPub',
  };

  it('all five set → the config', () => {
    for (const [k, v] of Object.entries(all)) vi.stubEnv(k, v);
    expect(firebaseWebConfig()).toEqual({
      apiKey: 'k',
      projectId: 'myweli',
      appId: '1:2:web:3',
      messagingSenderId: '2',
      vapidKey: 'BPub',
    });
  });

  it('any one missing or blank → null (the feature hides itself)', () => {
    for (const missing of Object.keys(all)) {
      for (const [k, v] of Object.entries(all)) vi.stubEnv(k, k === missing ? ' ' : v);
      expect(firebaseWebConfig(), missing).toBeNull();
    }
  });
});

describe('isPhoneDevice (Q3: computers only)', () => {
  it('the browser’s own answer wins when it gives one', () => {
    expect(isPhoneDevice({ userAgent: 'iPhone', userAgentData: { mobile: false } })).toBe(false);
    expect(isPhoneDevice({ userAgent: 'Macintosh', userAgentData: { mobile: true } })).toBe(true);
  });

  it('otherwise the user agent: phones yes, computers and tablets no', () => {
    const phones = [
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148',
      'Mozilla/5.0 (Linux; Android 14; SM-A146B) AppleWebKit/537.36 Chrome/130.0 Mobile Safari/537.36',
    ];
    const computers = [
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0 Safari/537.36',
      'Mozilla/5.0 (Linux; Android 14; SM-X210) AppleWebKit/537.36 Chrome/130.0 Safari/537.36',
    ];
    for (const ua of phones) expect(isPhoneDevice({ userAgent: ua }), ua).toBe(true);
    for (const ua of computers) expect(isPhoneDevice({ userAgent: ua }), ua).toBe(false);
  });
});

describe('supportsBrowserPush', () => {
  it('needs Notification, PushManager and a service worker', () => {
    const full = { Notification: {}, PushManager: {}, navigator: { serviceWorker: {} } };
    expect(supportsBrowserPush(full)).toBe(true);
    expect(supportsBrowserPush({ ...full, PushManager: undefined })).toBe(false);
    expect(supportsBrowserPush({ ...full, Notification: undefined })).toBe(false);
    expect(supportsBrowserPush({ ...full, navigator: {} })).toBe(false);
    expect(supportsBrowserPush(undefined)).toBe(false);
  });
});

describe('pushRowState (§3)', () => {
  const base = {
    configured: true,
    phone: false,
    supported: true,
    permission: 'default' as PushPermission,
    switchedOff: false,
  };
  it('not configured → no row at all', () => {
    expect(pushRowState({ ...base, configured: false })).toBe('hidden');
  });
  it('a phone says the app does it — before « unsupported » (an iPhone has no PushManager)', () => {
    expect(pushRowState({ ...base, phone: true, supported: false })).toBe('phone');
  });
  it('unsupported, blocked, on, off', () => {
    expect(pushRowState({ ...base, supported: false })).toBe('unsupported');
    expect(pushRowState({ ...base, permission: 'denied' })).toBe('blocked');
    expect(pushRowState({ ...base, permission: 'granted' })).toBe('on');
    expect(pushRowState({ ...base, permission: 'granted', switchedOff: true })).toBe('off');
    expect(pushRowState(base)).toBe('off');
  });
});

describe('bandOffered (Q2: once, like the app)', () => {
  it('a computer that can, has not answered, and was never asked', () => {
    expect(bandOffered(fakeDeps())).toBe(true);
  });
  it('never when unconfigured, on a phone, unable, answered, or already asked', () => {
    expect(bandOffered(null)).toBe(false);
    expect(bandOffered(fakeDeps({ phone: () => true }))).toBe(false);
    expect(bandOffered(fakeDeps({ supported: () => false }))).toBe(false);
    expect(bandOffered(fakeDeps({ perm: 'granted' }))).toBe(false);
    expect(bandOffered(fakeDeps({ perm: 'denied' }))).toBe(false);
    expect(bandOffered(fakeDeps({ store: memoryStore({ [PUSH_ASKED_KEY]: '1' }) }))).toBe(false);
  });
});

describe('enableBrowserPush', () => {
  it('asks the browser, then registers THIS browser’s token', async () => {
    const d = fakeDeps({ store: memoryStore({ [PUSH_OFF_KEY]: '1' }) });
    expect(await enableBrowserPush(d)).toBe('on');
    expect(d.calls).toEqual(['request', 'token', 'register:tok-1']);
    expect(d.store.data[PUSH_OFF_KEY]).toBeUndefined();
    expect(d.store.data[PUSH_ASKED_KEY]).toBe('1');
  });

  it('already permitted → no second question', async () => {
    const d = fakeDeps({ perm: 'granted' });
    expect(await enableBrowserPush(d)).toBe('on');
    expect(d.calls).toEqual(['token', 'register:tok-1']);
  });

  it('refused → blocked, nothing registered; closed without an answer → dismissed', async () => {
    const no = fakeDeps({ answer: 'denied' });
    expect(await enableBrowserPush(no)).toBe('blocked');
    expect(no.register).not.toHaveBeenCalled();
    const later = fakeDeps({ answer: 'default' });
    expect(await enableBrowserPush(later)).toBe('dismissed');
    expect(later.register).not.toHaveBeenCalled();
    // Either way, the band never comes back.
    expect(later.store.data[PUSH_ASKED_KEY]).toBe('1');
  });

  it('no token, or the server refuses → failed, and the row reads off', async () => {
    const noToken = fakeDeps({
      token: vi.fn(async () => {
        throw new Error('push service error');
      }),
    });
    expect(await enableBrowserPush(noToken)).toBe('failed');
    expect(noToken.store.data[PUSH_OFF_KEY]).toBe('1');
    const refused = fakeDeps({ register: vi.fn(async () => false) });
    expect(await enableBrowserPush(refused)).toBe('failed');
    expect(refused.store.data[PUSH_OFF_KEY]).toBe('1');
  });
});

describe('disableBrowserPush', () => {
  it('unregisters this browser, then forgets the token', async () => {
    const d = fakeDeps({ perm: 'granted' });
    expect(await disableBrowserPush(d)).toBe('off');
    expect(d.calls).toEqual(['token', 'unregister:tok-1', 'drop']);
    expect(d.store.data[PUSH_OFF_KEY]).toBe('1');
  });

  it('the server refuses → failed, and the switch stays on (it would lie)', async () => {
    const d = fakeDeps({ perm: 'granted', unregister: vi.fn(async () => false) });
    expect(await disableBrowserPush(d)).toBe('failed');
    expect(d.store.data[PUSH_OFF_KEY]).toBeUndefined();
    expect(d.dropToken).not.toHaveBeenCalled();
  });
});

describe('registerIfGranted — at sign-in, never a question', () => {
  it('permitted and not switched off here → registered', async () => {
    const d = fakeDeps({ perm: 'granted' });
    await registerIfGranted(d);
    expect(d.calls).toEqual(['token', 'register:tok-1']);
  });

  it('switched off here, not yet answered, a phone, unconfigured → nothing', async () => {
    for (const d of [
      fakeDeps({ perm: 'granted', store: memoryStore({ [PUSH_OFF_KEY]: '1' }) }),
      fakeDeps({ perm: 'default' }),
      fakeDeps({ perm: 'granted', phone: () => true }),
    ]) {
      await registerIfGranted(d);
      expect(d.calls).toEqual([]);
    }
    await expect(registerIfGranted(null)).resolves.toBeUndefined();
  });

  it('a failure stays quiet', async () => {
    const d = fakeDeps({
      perm: 'granted',
      token: vi.fn(async () => {
        throw new Error('x');
      }),
    });
    await expect(registerIfGranted(d)).resolves.toBeUndefined();
  });
});

describe('unregisterBeforeSignOut — a shared computer stops receiving', () => {
  it('a registered browser is unregistered (the switch is left as it was)', async () => {
    const d = fakeDeps({ perm: 'granted' });
    await unregisterBeforeSignOut(d);
    expect(d.calls).toEqual(['token', 'unregister:tok-1']);
    expect(d.store.data[PUSH_OFF_KEY]).toBeUndefined();
  });

  it('nothing to do when it never registered', async () => {
    for (const d of [
      fakeDeps({ perm: 'default' }),
      fakeDeps({ perm: 'granted', store: memoryStore({ [PUSH_OFF_KEY]: '1' }) }),
    ]) {
      await unregisterBeforeSignOut(d);
      expect(d.calls).toEqual([]);
    }
    await expect(unregisterBeforeSignOut(null)).resolves.toBeUndefined();
  });

  it('never holds the sign-out longer than its bound, never throws', async () => {
    vi.useFakeTimers();
    try {
      const hung = fakeDeps({ perm: 'granted', token: vi.fn(() => new Promise<string>(() => {})) });
      const done = vi.fn();
      void unregisterBeforeSignOut(hung, 3000).then(done);
      await vi.advanceTimersByTimeAsync(2999);
      expect(done).not.toHaveBeenCalled();
      await vi.advanceTimersByTimeAsync(1);
      expect(done).toHaveBeenCalled();
    } finally {
      vi.useRealTimers();
    }
    const broken = fakeDeps({
      perm: 'granted',
      unregister: vi.fn(async () => {
        throw new Error('offline');
      }),
    });
    await expect(unregisterBeforeSignOut(broken)).resolves.toBeUndefined();
  });
});
