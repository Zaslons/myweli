import { registerProDevice, unregisterProDevice } from '../api/pro';
import {
  type BrowserPushDeps,
  type FirebaseWebConfig,
  type PushPermission,
  firebaseWebConfig,
  isPhoneDevice,
  safeLocalStore,
  supportsBrowserPush,
} from './browser-push';

/// The browser and Firebase behind the rules of `browser-push.ts`
/// (docs/design/web-pro-browser-push.md §5). Null when the Firebase web app
/// is not configured — or on the server: the feature then does not exist.
///
/// **Firebase is loaded only when a token is needed** (a click on
/// « Activer », a sign-in on a browser already permitted, a sign-out) —
/// never on a public page, never in the Pro area's first load.

export const PUSH_SW_URL = '/pro/push-sw.js';
export const PUSH_SW_SCOPE = '/pro/';

let cached: BrowserPushDeps | null | undefined;

export function getBrowserPushDeps(): BrowserPushDeps | null {
  if (typeof window === 'undefined') return null;
  if (cached !== undefined) return cached;
  const config = firebaseWebConfig();
  cached = config ? browserDeps(config) : null;
  return cached;
}

function browserDeps(config: FirebaseWebConfig): BrowserPushDeps {
  return {
    supported: () => supportsBrowserPush(window),
    phone: () =>
      isPhoneDevice(
        navigator as Navigator & { userAgentData?: { mobile?: boolean } },
      ),
    permission: () => {
      try {
        return Notification.permission as PushPermission;
      } catch {
        return 'default';
      }
    },
    requestPermission: async () =>
      (await Notification.requestPermission()) as PushPermission,
    token: async () => {
      const registration = await activeRegistration(
        await navigator.serviceWorker.register(PUSH_SW_URL, { scope: PUSH_SW_SCOPE }),
      );
      // **The e2e build only**: a headless browser has no push service to
      // subscribe to, so its build names a token instead. Unset in every real
      // build — the branch is then dead code the minifier drops.
      const e2eToken = process.env.NEXT_PUBLIC_E2E_PUSH_TOKEN;
      if (e2eToken) return e2eToken;
      const { getToken } = await import('@firebase/messaging');
      return getToken(await messaging(config), {
        vapidKey: config.vapidKey,
        serviceWorkerRegistration: registration,
      });
    },
    dropToken: async () => {
      if (process.env.NEXT_PUBLIC_E2E_PUSH_TOKEN) return;
      const { deleteToken } = await import('@firebase/messaging');
      await deleteToken(await messaging(config));
    },
    register: async (token) => (await registerProDevice(token)).ok,
    unregister: async (token) => (await unregisterProDevice(token)).ok,
    store: safeLocalStore(),
  };
}

/// How long a first « Activer » waits for the worker to install.
const ACTIVATION_MS = 10_000;

/// **Firebase waits for an ACTIVE worker only when it registers its own**
/// (`registerDefaultSw` → `waitForRegistrationActive`, @firebase/messaging
/// 0.13.3); a registration handed to it is used as it is, and
/// `pushManager.subscribe` on a worker still installing throws. On a first
/// « Activer » `register()` answers before the install finishes — so the
/// very first try would have failed. Bounded, so the row can say so.
function activeRegistration(
  registration: ServiceWorkerRegistration,
): Promise<ServiceWorkerRegistration> {
  if (registration.active) return Promise.resolve(registration);
  const incoming = registration.installing ?? registration.waiting;
  if (!incoming) return Promise.reject(new Error('no service worker'));
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('service worker not active')), ACTIVATION_MS);
    incoming.onstatechange = () => {
      if (incoming.state !== 'activated') return;
      incoming.onstatechange = null;
      clearTimeout(timer);
      resolve(registration);
    };
  });
}

async function messaging(config: FirebaseWebConfig) {
  const [{ getApps, initializeApp }, { getMessaging }] = await Promise.all([
    import('@firebase/app'),
    import('@firebase/messaging'),
  ]);
  const app =
    getApps()[0] ??
    initializeApp({
      apiKey: config.apiKey,
      projectId: config.projectId,
      appId: config.appId,
      messagingSenderId: config.messagingSenderId,
    });
  return getMessaging(app);
}
