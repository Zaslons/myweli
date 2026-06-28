# Push notifications (app) — token registration + permission UX

| | |
|---|---|
| **Requirement** | FR-NOTIF-001 (push channel — FCM), app side |
| **Phase** | Phase 4 — productionize integrations (accounts/deploy phase) |
| **Status** | **Built** (consumer, on mocks): seam (`PushNotificationService` + `DeviceRegistrationService`) + `ApiDeviceRegistrationService` (`/me/devices`) + `PushRegistration` coordinator + after-first-booking rationale; analyze 0, +12 tests. The real `firebase_messaging` impl + platform config land in the accounts phase; pro app = #2b. |
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
- **Pro app push** (register/unregister + its own prompt placement) → **#2b**.

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

## 9. Open questions
- Deep-link target per event (tap → screen) — settled with the real plugin.
- Pro-app prompt placement (after first accepted booking?) — **#2b**.
