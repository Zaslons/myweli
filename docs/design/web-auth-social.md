# Web consumer auth — Google + Apple + Email OTP (auth overhaul, Phase 2)

| | |
|---|---|
| **Requirement** | FR-AUTH (web consumer login) — client slice of [auth-social-email.md](auth-social-email.md) (backend P1 shipped, PR #166) |
| **Phase** | Auth overhaul Phase 2 (web consumer). Pro web = Phase 4 (unchanged here). |
| **Status** | **Draft** — awaiting sign-off |
| **Depends on** | Backend `POST /auth/google` · `/auth/apple` · `/auth/email/otp/*` · `PATCH /me` (phone) — all live behind `AUTH_METHODS` |
| **Cross-refs** | [WEB.md](../WEB.md) (BFF/session rules) · [WEB-DESIGN-STANDARDS.md](WEB-DESIGN-STANDARDS.md) · [web-m5-booking.md](web-m5-booking.md) · [web-m6-account.md](web-m6-account.md) |

## 1. Goal & scope
Replace the web consumer's **phone-OTP login** with **Google + Apple + Email OTP**, everywhere the consumer signs in: `/connexion` and the **booking funnel's confirm step**. Phone becomes an **optional contact field** collected at booking (and editable in the account) via `PATCH /me` — never a login.

**In scope:** consumer BFF routes, the login form component, `/connexion`, `BookingFlow` confirm step, account contact-phone edit, stub-API + e2e + unit tests, Vercel env docs.
**Out of scope:** pro web login (`/pro/connexion` stays phone-OTP until Phase 4 — the provider OTP routes are ungated); mobile app (Phase 3); deleting the old consumer OTP BFF routes (kept until Phase 3 removes the last caller — the app).

## 2. Architecture (unchanged session model)
The **BFF pattern stays exactly as-is** ([web-m5](web-m5-booking.md)): the browser never sees tokens; each new login route calls the backend, then `setSessionCookies()` (httpOnly `myweli_web_at/rt`). The only new inbound data is the **provider token**, which the *backend* verifies against Google/Apple JWKS — the BFF just forwards it.

```
[GIS button]        → credential (ID token) ─┐
[Apple JS popup]    → identityToken + nonce ─┼→ POST /api/auth/{google|apple}   → backend /auth/* → cookies
[email form]        → email → code ──────────┼→ POST /api/auth/email/{request|verify} → backend  → cookies
```

### New BFF routes (mirror `api/auth/verify/route.ts`)
| Route | Body | Backend call |
|---|---|---|
| `POST /api/auth/google` | `{ idToken }` | `/auth/google` → cookies |
| `POST /api/auth/apple` | `{ identityToken, nonce?, fullName? }` | `/auth/apple` → cookies |
| `POST /api/auth/email/request` | `{ email }` | `/auth/email/otp/request` → passthrough (202 + `devCode` off-prod) |
| `POST /api/auth/email/verify` | `{ email, code }` | `/auth/email/otp/verify` → cookies |

All read `body.tokens` (nested AuthSession — the #151 lesson); errors pass through the machine code.

## 3. Identity-provider wiring (client side)
- **Google — GIS (Google Identity Services).** Load `https://accounts.google.com/gsi/client`; render the **official branded button** (`renderButton` — required by Google's branding rules; `locale: 'fr'`, One Tap **off**); callback posts the credential to the BFF. Client ID from **`NEXT_PUBLIC_GOOGLE_CLIENT_ID`** (a public identifier, not a secret).
- **Apple — Sign in with Apple JS.** Load `https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js`; `usePopup: true`; generate a **random nonce** per attempt (sent to Apple; the raw value goes to the BFF for the backend's nonce check). Client ID = the **Service ID** from **`NEXT_PUBLIC_APPLE_CLIENT_ID`**; requires the domain verified with Apple (ops).
- **Graceful degradation:** each button renders **only when its env var is set** — so this slice ships and fully works via **email OTP** before the Google/Apple accounts exist; adding a provider later is env-only. Unconfigured in dev → a quiet hint row is hidden entirely.

## 4. UX (per WEB-DESIGN-STANDARDS: tokens · four states · French)
### `/connexion` (and the identical inline card in the booking funnel)
```
Se connecter
Réservez plus vite avec votre compte.
[ G  Continuer avec Google ]      ← GIS branded button (when configured)
[   Continuer avec Apple  ]      ← Apple JS button (when configured)
──────────── ou ────────────
[ e-mail ______________ ] [Continuer avec e-mail]
   → step 2: « Entrez le code reçu par e-mail » [______] [Se connecter]
      (devCode hint off-prod, as today)
CGU line.
```
- Reuses the existing form idiom (`OtpLoginForm` becomes `LoginOptions` with the email flow embedded; same Button/input classes; states: loading per-button, error banner in French, success → `returnTo`).
- **Copy:** « Continuer avec Google / Apple / e-mail », « Entrez le code reçu par e-mail », errors « Connexion annulée », « Code incorrect ou expiré », « E-mail invalide », « Compte suspendu ».
- `returnTo` continuity unchanged (`ConnexionClient` keeps its open-redirect guard).

### Booking funnel (`BookingFlow` confirm step) — replaces inline phone-OTP
1. Signed-out (checked via the existing `/api/me`): recap + **the same `LoginOptions` card** inline (« Connectez-vous pour confirmer votre réservation ») — after login the flow continues in place (no redirect).
2. Signed-in: recap + **optional contact phone** — « Numéro pour que le salon vous contacte (recommandé) » using the existing `PhoneField`; saved via `PATCH /me` (only when changed/valid) → `createBooking` → done screen (unchanged).
3. Four states; deposit recap unchanged; install push unchanged.

### Account (`/mon-compte` profile)
- Show the login identity (email + « Connecté via Google/Apple/e-mail »).
- **Contact phone** row becomes editable (PhoneField + save via the existing profile PATCH path) with « Non vérifié » subtext when `phoneVerified` is false.

## 5. Security
- Tokens stay server-side (httpOnly cookies); provider tokens transit the BFF once, never stored.
- The backend is the verifier (JWKS/aud/iss/nonce — T31); the BFF adds no trust.
- `returnTo` open-redirect guard kept; `/connexion` stays `noindex`.
- No new secrets in the bundle — both `NEXT_PUBLIC_*` values are public identifiers.

## 6. Tests
- **Unit (RTL):** `LoginOptions` — email happy path, invalid email, wrong code, buttons hidden without env config, per-button loading state; BookingFlow — signed-out shows login, signed-in shows phone + confirm.
- **e2e (Playwright, hermetic):** stub-api gains `/auth/email/otp/request|verify` (+ `/auth/google|apple` accepting any token for completeness) and `PATCH /me`; **all e2e logins switch from phone-OTP to email-OTP** (account, booking, M8.3 specs); booking funnel e2e = services→staff→slot→**email sign-in**→optional phone→confirmed. Google/Apple buttons aren't e2e-drivable (external scripts) — covered by unit render-gating tests.
- Contract types already regenerated (P1).

## 7. Rollout / config
- Ships dark: with no `NEXT_PUBLIC_*` IDs set, the web shows **email-only** login (fully functional — Resend on the backend, devCode off-prod). Google/Apple appear the moment their IDs land in Vercel env.
- Ops (user, guided later): Google Cloud project → **web OAuth client ID** (+ the same value into the backend `GOOGLE_CLIENT_IDS`); Apple **Service ID** + domain verification (+ backend `APPLE_CLIENT_IDS`); **Resend** key + domain (backend). Then Render: `AUTH_METHODS=google,apple,email`.
- Old consumer OTP BFF routes (`/api/auth/request-otp`, `/api/auth/verify`) deleted in Phase 3 when the app stops using phone login (they 404 server-side once `AUTH_METHODS` drops `phone`).

## 8. Open questions (for sign-off)
1. **Account phone edit in this slice** (recommended — small, completes the contact-phone story) or defer to Phase 3?
2. Booking contact phone: **optional with « recommandé »** (recommended) vs required?
3. OK that Google/Apple buttons are env-gated (email-first ship, providers appear when you create the accounts)?
