# App consumer auth — Google + Apple + Email OTP (auth overhaul, Phase 3)

| | |
|---|---|
| **Requirement** | FR-AUTH-001/002 (consumer app login) — mobile slice of [auth-social-email.md](auth-social-email.md) (backend P1 ✅ #166, web P2 ✅ #167) |
| **Phase** | Auth overhaul Phase 3 (consumer app, `main.dart`). Pro app = Phase 4. |
| **Status** | **Built** (2026-07-02) — decisions: Apple seam flag-hidden · dormant phone screens kept · clean outlined Google button (**+ the official multicolor « G » added 2026-07-03** — Google branding guidelines; shared `GoogleGLogo` widget, also on the pro login/register buttons) |
| **Depends on** | Live backend `POST /auth/google` · `/auth/email/otp/*` · `PATCH /me` (behind `AUTH_METHODS=google,apple,email`); Google client IDs (created 2026-07-02 — web/Android/iOS); **Apple deferred** (no Developer Program yet — decision 2026-07-02) |
| **Cross-refs** | [DESIGN-STANDARDS.md](DESIGN-STANDARDS.md) · [web-auth-social.md](web-auth-social.md) (flow parity) · `lib/services/interfaces/auth_service_interface.dart` |

## 1. Goal & scope
Replace the consumer app's **phone-OTP login** with **Google Sign-In + Email OTP** (+ a **flag-hidden Apple seam** for the store phase), mirroring the web flow (memory `web-mirror-app-flow`): sign in → **mandatory contact phone** when the account has none → continue to `returnTo`. Phone becomes contact data (editable in the profile, « Non vérifié »).

**In scope:** `AuthServiceInterface` + mock + API impls, `User` model update, new `LoginScreen` (+ email-code step + phone step), router swap at `/login`, profile contact-phone edit, platform config (Android/iOS Google), tests.
**Out of scope:** pro app login (Phase 4 — untouched); Apple *activation* (seam ships flag-off; store phase flips it); deleting the dormant phone-OTP screens (kept for the Termii-era phone-*verification* reuse).

## 2. What does NOT change (why this slice is contained)
- **Booking flow is untouched.** The app already gates booking/favorites/bookings via `/login?returnTo=…` — unlike the web there's no inline OTP to replace. Only the login destination changes.
- **Session model unchanged:** `ApiAuthService` already stores the AuthSession tokens in `flutter_secure_storage` and refreshes; the new endpoints return the same `AuthSession` shape.
- `returnTo` continuity, push-registration seam, account deletion — all unchanged.

## 3. Service layer (interface → mock → api; pattern: existing auth methods)
```dart
// AuthServiceInterface — additions (phone sendOtp/verifyOtp stay, dormant):
Future<ApiResponse<User>> signInWithGoogle();            // native flow → idToken → POST /auth/google
Future<ApiResponse<User>> signInWithApple();             // seam; flag-gated UI
Future<ApiResponse<String>> requestEmailOtp(String email);   // devCode when backend != prod
Future<ApiResponse<User>> verifyEmailOtp(String email, String code);
Future<ApiResponse<User>> updateUser({String? name, String? email, String? avatarUrl, String? phone}); // + phone
```
- **Api impl:** `google_sign_in` (^6) yields the **ID token** (with `serverClientId` = the **web** client ID, so the token's `aud` is in the backend allowlist) → `POST /auth/google {idToken}` → parse AuthSession exactly like `verifyOtp` today. Email OTP → the two new endpoints. `updateUser` passes `phone` to `PATCH /me`.
- **Mock impl:** simulated latency + failure paths; `123456` verifies; a mock Google user (`mock.google@myweli.test`); first login returns `phoneNumber: null` so the phone step is exercised in dev/tests.
- **`User` model** mirrors the API DTO: `phoneNumber` → **nullable**, + `phoneVerified`, + `authProvider` (equatable/fromJson/toJson updated — ripples through mock data fixed at build).

## 4. UX (per DESIGN-STANDARDS — tokens only, four states, French)
### `LoginScreen` (replaces `PhoneLoginScreen` at `/login`; same entry points/returnTo)
```
[vertical lockup SVG — existing brand asset]
Bienvenue
Connectez-vous pour réserver en quelques secondes.
[ Continuer avec Google ]        ← outlined AppButton style (flag: shown when configured)
[ Continuer avec Apple ]         ← black, HIDDEN until FeatureFlags.appleSignIn
────────── ou ──────────
[ Votre e-mail            ]
[ Continuer avec e-mail   ]      ← primary
CGU line (existing copy)
```
- **Email code step** (same screen, step state — mirrors web): « Entrez le code reçu par e-mail à {email} » + 6-digit field + « Se connecter » + « Changer d'e-mail » + devCode hint when returned.
- **Mandatory phone step** (blocking, after ANY login where `user.phoneNumber == null`): « Votre numéro de téléphone » + « Le salon l'utilise pour vous contacter. » + `PhoneNumberField` (existing intl picker) + « Continuer » → `updateUser(phone:)` → then `returnTo`.
- States: per-action loading (AppButton `isLoading` → mark_loader), French errors (« Connexion Google impossible. », « Code incorrect ou expiré. », « Compte suspendu. », « Numéro invalide. »), Google-cancel = silent.
- **Profile** (`edit_profile_screen`): add contact-phone field (PhoneNumberField, prefilled) + « Non vérifié » helper when `phoneVerified == false` — parity with web.

## 5. Platform config (no secrets — all public identifiers)
- **Android:** nothing in-repo — Google matches `com.myweli.app` + the registered SHA‑1 (debug SHA‑1 added 2026-07-02; release SHA‑1 at store time). `serverClientId` passed in code via `AppConfig` (`--dart-define=GOOGLE_SERVER_CLIENT_ID=…`, default = the real web ID — it's public).
- **iOS:** `Info.plist` gains `GIDClientID` (the iOS client ID) + the **reversed client ID** URL scheme (`com.googleusercontent.apps.731308991240-ah75c2…`).
- **Apple:** `sign_in_with_apple` package + `FeatureFlags.appleSignIn = bool.fromEnvironment('APPLE_SIGN_IN')` (default **false**). The iOS *capability/entitlement* is added at the store phase with the Developer account (store rule 4.8 makes Apple mandatory on iOS once Google ships there — tracked for that phase).

## 6. Security
- Tokens only ever in `flutter_secure_storage` (existing path). The Google ID token transits once to the backend — never stored, never logged.
- The **backend** is the verifier (JWKS/aud/iss — T31); the app treats the returned AuthSession as the only truth.
- Inputs validated client-side (email format, E.164 via the picker) + server re-validates.
- No new secrets: client IDs are public identifiers via `--dart-define`.

## 7. Tests
- **Unit:** mock-service flows (email OTP happy/wrong-code/lockout passthrough, Google returns user, updateUser phone); `AuthProvider` new methods (loading/error/user states); `User` model round-trip with new fields.
- **Widget:** `LoginScreen` — options state, email→code step, **mandatory phone step shown when the mock user lacks a phone**, error banners, Apple button hidden by default.
- Full `flutter analyze` 0 + suite green; consistency sweep (DESIGN-STANDARDS §6).

## 8. Rollout
1. Ship on mocks + API impls together (flag `useApiBackend` decides, as today) — feature branch → PR → CI → user merges.
2. Dev verification on device: `flutter run --release -t lib/main.dart --dart-define=USE_API_BACKEND=true --dart-define=API_BASE_URL=https://api.myweli.com` → real Google sign-in against prod (Android uses the debug SHA‑1 → works now; iOS needs the plist entries in this PR).
3. Store phase later: release-key SHA‑1 added to the Android client; Apple capability + `APPLE_SIGN_IN=true`.

## 9. Open questions (for sign-off)
1. **Apple seam now, flag-hidden** (recommended — store phase becomes an env flip) vs skip all Apple code until then?
2. **Dormant phone screens:** keep `phone_login_screen`/`otp_verify_screen` as unrouted files for the Termii verification reuse (recommended) vs delete now?
3. **Google button style:** clean outlined button with text only (recommended — native branding rules are laxer than web; official G glyph asset can be added later) vs bundle the official Google logo asset now?
