/// The salon's browser notifications — the rules, free of any browser or
/// Firebase detail so they test without either (the glue is
/// `browser-push-deps.ts`). Design: docs/design/web-pro-browser-push.md —
/// owner decisions 2026-10-20: like the app (the band once, then the
/// Notifications row), computers only, the words of §9.

export type PushPermission = 'default' | 'granted' | 'denied';

export type FirebaseWebConfig = {
  apiKey: string;
  projectId: string;
  appId: string;
  messagingSenderId: string;
  vapidKey: string;
};

/// The Firebase web app's five values — public by nature (§5) — or null
/// when any is missing: the feature then hides itself (no band, no row), as
/// the Apple button does without its client id. Each name is written out:
/// Next inlines `process.env.NEXT_PUBLIC_*` only when spelled literally.
export function firebaseWebConfig(): FirebaseWebConfig | null {
  const c: FirebaseWebConfig = {
    apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY?.trim() ?? '',
    projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID?.trim() ?? '',
    appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID?.trim() ?? '',
    messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID?.trim() ?? '',
    vapidKey: process.env.NEXT_PUBLIC_FIREBASE_VAPID_KEY?.trim() ?? '',
  };
  return Object.values(c).every((v) => v !== '') ? c : null;
}

/// A phone, where the notifications are the app's (Q3). The browser's own
/// answer when it gives one (`userAgentData.mobile`), else the user agent: a
/// tablet (Android without « Mobile », an iPad that says Macintosh) counts as
/// a computer.
export function isPhoneDevice(nav: {
  userAgent?: string;
  userAgentData?: { mobile?: boolean };
}): boolean {
  if (typeof nav.userAgentData?.mobile === 'boolean') return nav.userAgentData.mobile;
  return /Mobi|iPhone|iPod|Windows Phone/i.test(nav.userAgent ?? '');
}

/// The three things a browser needs. An iPhone's Safari has no `PushManager`
/// unless the site was added to the home screen.
export function supportsBrowserPush(win: unknown): boolean {
  if (!win || typeof win !== 'object') return false;
  const w = win as { Notification?: unknown; PushManager?: unknown; navigator?: { serviceWorker?: unknown } };
  return Boolean(w.Notification && w.PushManager && w.navigator?.serviceWorker);
}

/// What the row says (§3), in its order of precedence: a phone before
/// « unsupported » (an iPhone has no PushManager, and « the app does it » is
/// the useful sentence there).
export type PushRowState = 'hidden' | 'phone' | 'unsupported' | 'blocked' | 'on' | 'off';

export function pushRowState(s: {
  configured: boolean;
  phone: boolean;
  supported: boolean;
  permission: PushPermission;
  switchedOff: boolean;
}): PushRowState {
  if (!s.configured) return 'hidden';
  if (s.phone) return 'phone';
  if (!s.supported) return 'unsupported';
  if (s.permission === 'denied') return 'blocked';
  if (s.permission === 'granted' && !s.switchedOff) return 'on';
  return 'off';
}

/// The band asked, whatever the answer — never shown again on this browser
/// (the app's « demandé » flag).
export const PUSH_ASKED_KEY = 'myweli_pro_push_asked';
/// The member switched this browser off: neither sign-in nor the row turns
/// it back on by itself.
export const PUSH_OFF_KEY = 'myweli_pro_push_off';

export type KeyStore = {
  get(key: string): string | null;
  set(key: string, value: string): void;
  remove(key: string): void;
};

/// `localStorage`, every access guarded: a private window, blocked site data
/// or a thumbnail capture can throw, and none of this may break a page.
export function safeLocalStore(): KeyStore {
  return {
    get: (k) => {
      try {
        return window.localStorage.getItem(k);
      } catch {
        return null;
      }
    },
    set: (k, v) => {
      try {
        window.localStorage.setItem(k, v);
      } catch {
        /* nothing to keep it in */
      }
    },
    remove: (k) => {
      try {
        window.localStorage.removeItem(k);
      } catch {
        /* nothing to remove */
      }
    },
  };
}

/// The browser and Firebase as the rules see them.
export type BrowserPushDeps = {
  supported(): boolean;
  phone(): boolean;
  permission(): PushPermission;
  /// The browser's own question. Only ever called from a click.
  requestPermission(): Promise<PushPermission>;
  /// This browser's FCM token (the service worker registered first).
  token(): Promise<string>;
  /// Forget the token on Firebase's side (the push subscription goes).
  dropToken(): Promise<void>;
  /// `POST /api/pro/devices` — true when the server registered it.
  register(token: string): Promise<boolean>;
  /// `DELETE /api/pro/devices` — true when the server removed it.
  unregister(token: string): Promise<boolean>;
  store: KeyStore;
};

export function rowStateOf(deps: BrowserPushDeps | null): PushRowState {
  if (!deps) return 'hidden';
  return pushRowState({
    configured: true,
    phone: deps.phone(),
    supported: deps.supported(),
    permission: deps.permission(),
    switchedOff: deps.store.get(PUSH_OFF_KEY) === '1',
  });
}

/// The Accueil band (Q2): a computer that can, has not answered the browser,
/// and was never asked here.
export function bandOffered(deps: BrowserPushDeps | null): boolean {
  if (!deps) return false;
  return (
    !deps.phone() &&
    deps.supported() &&
    deps.permission() === 'default' &&
    deps.store.get(PUSH_ASKED_KEY) !== '1'
  );
}

export type EnableOutcome = 'on' | 'blocked' | 'dismissed' | 'failed';

/// « Activer » / the switch turned on: the browser's question if it has not
/// been answered, then this browser's token to the server. A failure leaves
/// the row reading off — never a switch that says on over nothing.
export async function enableBrowserPush(deps: BrowserPushDeps): Promise<EnableOutcome> {
  deps.store.set(PUSH_ASKED_KEY, '1');
  let permission = deps.permission();
  if (permission === 'default') {
    permission = await deps.requestPermission().catch((): PushPermission => 'default');
  }
  if (permission === 'denied') return 'blocked';
  if (permission !== 'granted') return 'dismissed';
  try {
    const ok = await deps.register(await deps.token());
    if (!ok) throw new Error('not registered');
    deps.store.remove(PUSH_OFF_KEY);
    return 'on';
  } catch {
    deps.store.set(PUSH_OFF_KEY, '1');
    return 'failed';
  }
}

/// The switch turned off: the server forgets this browser first — if it
/// cannot, the switch stays on, since alerts would keep coming.
export async function disableBrowserPush(deps: BrowserPushDeps): Promise<'off' | 'failed'> {
  try {
    if (!(await deps.unregister(await deps.token()))) return 'failed';
  } catch {
    return 'failed';
  }
  deps.store.set(PUSH_OFF_KEY, '1');
  await deps.dropToken().catch(() => {});
  return 'off';
}

/// At sign-in (the shell's mount), as the app does: a browser already
/// permitted, and not switched off here, registers again — never a question.
/// Also how a token Firebase rotated reaches the server.
export async function registerIfGranted(deps: BrowserPushDeps | null): Promise<void> {
  if (!deps || deps.phone() || !deps.supported() || deps.permission() !== 'granted') return;
  if (deps.store.get(PUSH_OFF_KEY) === '1') return;
  try {
    await deps.register(await deps.token());
  } catch {
    /* best-effort, like the app */
  }
}

/// Before the session goes (§2.6): a shared salon computer stops receiving a
/// signed-out member's alerts. The switch is left as it was — signing in
/// again re-registers, as in the app. Bounded: a sign-out never waits on
/// Firebase for more than [ms].
export async function unregisterBeforeSignOut(
  deps: BrowserPushDeps | null,
  ms = 3000,
): Promise<void> {
  if (!deps || deps.phone() || !deps.supported() || deps.permission() !== 'granted') return;
  if (deps.store.get(PUSH_OFF_KEY) === '1') return;
  const work = (async () => {
    try {
      await deps.unregister(await deps.token());
    } catch {
      /* best-effort */
    }
  })();
  let timer: ReturnType<typeof setTimeout> | undefined;
  await Promise.race([
    work,
    new Promise<void>((r) => {
      timer = setTimeout(r, ms);
    }),
  ]);
  clearTimeout(timer);
}
