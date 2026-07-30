# Push notifications (app) — token registration + permission UX

| | |
|---|---|
| **Requirement** | FR-NOTIF-001 (push channel — FCM), app side |
| **Phase** | Phase 4 — productionize integrations (accounts/deploy phase) |
| **Status** | ✅ **Built — REAL FCM (2026-07-14).** The seam now runs on `firebase_messaging`: adapter + foreground display + tap→deep-link (incl. the R6 salon switch) + the OS-denied re-enable path + the pro notification centre. Android is verified end-to-end on device; **iOS is code-complete but unbuilt** (no Apple developer account yet — §12). CI stays green with no Firebase config in the repo (§11). |
| **Companion** | Backend foundation: [push-notifications-fcm.md](push-notifications-fcm.md). Runbook: [../DEPLOYMENT.md](../DEPLOYMENT.md). |

## 1. Goal & scope
Wire the consumer app to obtain an FCM device token and register it with the
backend (`POST/DELETE /me/devices`) so the lifecycle pushes the backend already
sends (confirmations/reminders) reach the device. Built **the Myweli way**:
interface + mock by default, real impl behind config — so it runs and is tested
without a Firebase project.

**In scope (this slice, no accounts — CI-safe, fully testable on mocks):**
- A `PushNotificationServiceInterface` (permission + token + token-refresh) with a
  realistic **mock** as the DI default.
- A `DeviceRegistrationServiceInterface` (`register`/`unregister`) with an **api**
  impl (`/me/devices` via the consumer `RefreshingHttpClient`, silent refresh) +
  a mock.
- A `PushRegistration` coordinator: **register-on-login-if-already-granted**,
  **ask-after-first-booking** (rationale → OS prompt → register), **re-register
  on token refresh**, **unregister-on-logout**.
- Permission **rationale sheet** for the ask-after-first-booking moment.
- Unit + widget tests.

**Deferred:**
- **Real `FcmPushNotificationService`** (`firebase_core` + `firebase_messaging`:
  permission, token, `onTokenRefresh`, fore/background message + tap→deep-link)
  and platform config (`google-services.json` / `GoogleService-Info.plist` / web
  config) — needs the Firebase project + the `android/` folder (#3). Accounts
  phase. The DI line swaps mock → Fcm; nothing else changes.
- **Pro app push** — **done (#2b):** a separate `proPushRegistration` scoped to
  the **provider session**, register-on-login / unregister-on-logout via
  `ProAuthProvider`, and the rationale **on the first dashboard visit** (pros
  want new-booking alerts immediately) with pro-specific copy.

## 2. Contract (already shipped)
- `POST /me/devices` `{ token, platform: android|ios|web }` — self-scoped, upsert.
- `DELETE /me/devices` `{ token }` — self-scoped, on logout.

`platform` = `web` when `kIsWeb`, else `android`/`ios` from `Platform`.

## 3. Layering (mirrors the existing services)
```
screens/booking_confirmation ─┐
providers/auth (login/logout) ─┼─► PushRegistration (core/push) ─► PushNotificationService  (Mock | Fcm*)
notification_preferences ─────┘                                  └─► DeviceRegistrationService (Api | Mock)
                                                                        └─► POST/DELETE /me/devices
```
- `PushRegistration` is the only orchestrator; services stay dumb. Idempotent:
  guards a one-time "asked" flag (shared_preferences) so we never nag.
- `PushNotificationService` default = `MockPushNotificationService` (TODO accounts:
  `FcmPushNotificationService`). `DeviceRegistrationService` = api when
  `AppConfig.useApiBackend`, else mock.

## 4. Permission UX (signed off)
- **Ask after the first successful booking** (highest opt-in). At login we only
  *register silently if already granted* — never a cold prompt.
- **Rationale sheet** (reuses the bottom-sheet + `AppButton` + tokens):
  «Activez les notifications pour vos rappels et confirmations de rendez-vous.»
  → **« Activer »** triggers the OS prompt; **« Plus tard »** defers (asked-flag
  set so we don't nag).
- **States:** notDetermined · rationale shown · granted (→ get token → register) ·
  denied (no nag) · alreadyGranted (skip the sheet, register silently). The
  denied→OS-settings re-enable entry lands with the real plugin (accounts phase;
  `openAppSettings` is a no-op against the mock).
- French throughout; design tokens only; no new colors/sizes.

## 5. Security / authz
- Registration is **self-scoped** (the principal = the consumer session's `sub`);
  it rides the existing consumer `RefreshingHttpClient` (no new auth surface).
- The FCM token is **not** a secret/PII; stored only server-side keyed by user.
- No new secrets in the app. `flutter analyze` 0; gitleaks/OSV green.
- Logout unregisters **before** clearing the session (needs a valid token).

## 6. Errors / performance
- All push/registration work is **best-effort** — it never blocks booking, login,
  or logout (caught + logged; failures are silent to the user). Re-tried on the
  next relevant lifecycle event.
- One token, 0–1 registration calls per lifecycle event. No polling.

## 7. Tests
- `MockPushNotificationService`: notDetermined→granted on request; fake token;
  deny path.
- `MockDeviceRegistrationService` / `ApiDeviceRegistrationService` (mocked http):
  register/unregister hit `/me/devices` with the bearer + right body; 401 anon.
- `PushRegistration`: registers when granted; no-op when denied; unregister;
  re-register on refresh; the asked-flag prevents a second prompt.
- Widget: the rationale sheet renders both actions; «Activer» → granted path.

## 8. Rollout
Dev/CI: mock — fully functional + tested. Accounts phase: create Firebase, add
platform config, ship `FcmPushNotificationService`, flip the DI line; then real
tokens register and the backend's pushes/reminders land. Then **#2b** (pro app).

## 9. Open questions — ANSWERED
- Deep-link target per event — **resolved:** the push `data` carries a `route`
  (backend §9). Consumer `/appointment/{id}`; salon `/pro/appointment/{id}?salon=…`.
- Pro-app prompt placement — **resolved (#2b):** first dashboard visit.

---

## 10. The real FCM slice (2026-07-14)

### 10.1 The adapter — `services/push/fcm_push_notification_service.dart`
Implements the unchanged 4-method seam. Two invariants:

- **Lazy.** `FirebaseMessaging` is reached through a *getter*, never a field.
  `PushRegistration`'s constructor subscribes to `onTokenRefresh` from inside
  `ServiceLocator.setup()`, so an eager instance would kill app boot — and the
  four test suites that call `setupDependencyInjection()`.
- **It degrades, it never throws.** Missing config, no APNs token on iOS,
  Firebase not initialized → `notDetermined` / `null` / an empty stream, so
  `PushRegistration` simply no-ops.

**No test may CONSTRUCT it** (its methods need a native Firebase app);
importing the file for the pure `mapAuthorizationStatus` is fine. DI wires it
only when `AppConfig.useApiBackend` is on — which no test sets, so `flutter
test` always keeps the mock. `di_push_wiring_test` pins that.

> **Why not fall back to the mock when Firebase init fails in backend mode?**
> The mock grants on first ask and hands out the literal token
> `mock-fcm-token`, which `PushRegistration` would then POST to the *real*
> `/me/devices`. Degrading inside the adapter is the safe failure.

### 10.2 The brain / bridge split
- `core/push/push_message_handler.dart` — **zero Firebase imports**, fully
  unit-tested: the channel constants, `routeFromPushData` (prefix
  **allowlist** — a malformed or hostile payload can never drive the app to an
  arbitrary destination), `providerIdFromPushData`, and the tap logic.
- `services/push/fcm_message_bridge.dart` — the only file that touches
  `firebase_messaging` + `flutter_local_notifications`. **Never imported by a
  test.**

### 10.3 The four ways a push lands
| Path | Who draws it | Tap |
|---|---|---|
| Foreground | **Android:** us, via `flutter_local_notifications` (FCM draws nothing in front). **iOS:** the system (`setForegroundNotificationPresentationOptions`). | the fln callback / `onMessageOpenedApp` |
| Background | the OS (every push carries a `notification` block) | `onMessageOpenedApp` |
| Killed | the OS, natively — **no Dart runs**, which is why the native config is load-bearing (§11) | `getInitialMessage` |
| The in-app feed | the notification centre | the row's `route` |

The background handler is a dependency-free `@pragma('vm:entry-point')` no-op:
that isolate has no DI, no providers, no router.

### 10.4 The two hard cases
- **Cold start.** A tap can *launch* the app: the router isn't mounted, the
  session isn't restored. The handler **buffers** the payload; the hoisted auth
  provider flushes it the moment we're signed in. Otherwise the splash/login
  redirect would eat the deep link.
- **Multi-salon (R6).** A salon push carries `providerId`, and its route carries
  `?salon=` (so a tapped *feed row* switches too). If it isn't the active salon,
  `ProAuthProvider.switchSalon` runs first — which also resets every
  salon-scoped provider. A refused switch (revoked, unknown) lands on
  `/pro/dashboard` rather than a booking the active scope cannot resolve.

### 10.5 The channel
`kPushChannelId = 'myweli_default'` **must equal** the backend's
`FcmV1PushProvider.androidChannelId` (pinned by a test) and the manifest's
`default_notification_channel_id`. Creating it at boot is what gives our
notifications a name and high importance in the OS settings; without it Android
files them under an unnamed default channel. The status-bar glyph is the
already-staged `ic_stat_myweli`.

> **No `default_notification_color`.** `AppColors.primary` is pure black;
> tinting a black small-icon on Android's dark shade renders it invisible.
> Android's theme-adaptive default is always legible, and we avoid duplicating a
> design token as an XML hex that can drift.

### 10.6 The OS-denied dead end
Once notifications are denied at the system level, **no in-app toggle can bring
them back** — the « Notifications push » switch would sit there looking
functional while every push is dropped. The prefs screen reads the OS permission
and, when denied, shows `PushBlockedBanner` (« Ouvrir les réglages » →
`app_settings`), re-checking on resume so it disappears once the user enables
them. The pro app has no prefs screen, so the same banner sits atop its
notification centre.

### 10.7 The pro notification centre
The dashboard bell was `onPressed: () {}`. It now opens `/pro/notifications`
with an unread badge, fed by the provider-directed events
([push-notifications-fcm.md](push-notifications-fcm.md) §10). The feed body is
the shared `NotificationsList` (four states, pull-to-refresh, tap → mark read +
route); only the chrome differs from the consumer centre.

`/me/notifications` is role-agnostic, so the same `ApiNotificationService` runs
on the provider session (`refreshPath: '/auth/provider/refresh'`).

> **The feed is ACCOUNT-scoped, not salon-scoped.** It's keyed by the token's
> subject, so a multi-salon owner sees one merged feed — the provider is
> therefore NOT `ProSalonScope.track`ed, and a salon switch must not reset it.

## 11. Config strategy — and why CI stays green without it

`Firebase.initializeApp()` takes **no options**: Android reads the flavor's
`google-services.json`, iOS its `GoogleService-Info.plist`.

**Rejected: committed `firebase_options_*.dart`.** On Android, a killed-state
notification is rendered by the native `FirebaseMessagingService` — **no Dart
runs** — so it needs the resources the google-services Gradle plugin generates
from the JSON. Dart-side options cannot supply them, which makes the native
config load-bearing anyway; a second, hand-maintained source of truth would be
pure drift risk. (It also buys nothing in CI: the mobile job runs only
format/analyze/test — it never invokes Gradle.)

So the repo carries **no Firebase config**, and everything still works:
- Gradle applies google-services **conditionally**, only when a flavor's JSON is
  present (the plugin hard-fails otherwise) → a fresh clone builds.
- `initFirebaseForPush()` returns false in demo mode / on web / when config is
  missing → push is simply inert.
- `.gitleaks.toml` **pre-allowlists** the future config paths: Firebase *client*
  config ships inside the app binary and is public by design (its `AIza…` value
  trips the `gcp-api-key` rule). The **server** credential (`FCM_PRIVATE_KEY`)
  is the real secret and lives only in Render's env.

## 12. iOS — code-complete, unbuilt

Shipped: Podfile floor `15.0` (the Firebase iOS SDK's), `Runner.entitlements`
(`aps-environment`), `UIBackgroundModes: remote-notification` in every plist.

**Deliberately untouched:** `project.pbxproj`, the xcconfigs, `AppDelegate.swift`
— iOS cannot be compiled in this slice, and corrupting the project file is
unacceptable. `flutter_local_notifications` is Android-only here by design, so
no Swift change is even required.

Remaining (Xcode + Apple developer account — DEPLOYMENT.md §B4): wire
`CODE_SIGN_ENTITLEMENTS`, add the Push Notifications capability, realign the
bundle IDs (`com.example.*` → `com.myweli.app` / `.pro`), drop in
`GoogleService-Info.plist`, upload the APNs key.
