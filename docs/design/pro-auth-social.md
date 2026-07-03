# Pro auth — Google + Email OTP for salons (auth overhaul, Phase 4)

| | |
|---|---|
| **Requirement** | FR-PRO auth — final slice of [auth-social-email.md](auth-social-email.md) (P1 backend ✅ · P2 web ✅ · P3 app ✅) |
| **Phase** | Auth overhaul Phase 4 — pro backend + pro app + pro web |
| **Status** | **Draft** — awaiting sign-off |
| **Cross-refs** | [app-auth-social.md](app-auth-social.md) · [web-auth-social.md](web-auth-social.md) · `backend/lib/src/auth/provider_auth_repository.dart` · [pro-kyc.md](pro-kyc.md) |

## 1. Goal & scope
Move **salon (pro) auth** off phone-OTP to **Google + Email OTP** (+ the same flag-hidden Apple seam), completing the overhaul and killing the last SMS spend. KYC, onboarding, dashboards, ownership checks — all unchanged (they key on the provider account id, not on how it authenticated).

## 2. The structural difference vs the consumer slice
A consumer login may **auto-create** an account (find-or-create). A salon login must **not** — registration carries required business fields. So:

- **Login** (`POST /auth/provider/google`, `/auth/provider/email/otp/request|verify`): verify identity → find by `google_sub` / **verified email** → ProviderSession. **No account → 404 `provider_not_found`** (the client offers « Créer un compte ») — same code the phone flow uses today.
- **Registration** (`POST /auth/provider/register`, evolved): **identity proof + business fields in ONE request** — either `{idToken, …}` (Google) or `{email, code, …}` (email OTP, code requested via the same request endpoint). Verify identity → create account → session immediately (no second verify step — better than today's register→OTP dance).
  - Fields: `businessName` (req) · `businessType` (req) · **`phoneNumber` (req — salon contact; clients/Myweli must be able to call)** · `address?`.

## 3. Backend
- **`ProviderAuthRepository`** gains: `loginWithSocial(provider, sub, email, …)` (login-only, no create), `requestEmailOtp`/`verifyEmailOtp` variants keyed on a **provider-scoped** table, and `register` gains the identity linkage (`email`, `googleSub?`, `authProvider`). In-memory + Postgres.
- **Migration `0023_provider_auth_social`:** `provider_users` += `email_verified`, `google_sub`, `apple_sub`, `auth_provider`; **unique partial indexes** on `lower(email)`, `google_sub`, `apple_sub` (email = identity now); `phone_number` **keeps NOT NULL** (required contact) but **drops UNIQUE** (no longer identity); new **`provider_email_otp_codes`** table (separate from the consumer one — same rationale as `provider_otp_codes`).
- **Routes:** `/auth/provider/google` · `/auth/provider/email/otp/request` · `/auth/provider/email/otp/verify` (+ apple twin, seam); register reshaped; the existing provider **phone**-OTP routes get the same **`AUTH_METHODS` gate** → with the prod env already `google,apple,email`, pro SMS dies at deploy.
- Same verifiers (`GoogleIdTokenVerifier` etc.), same email provider, same nested **ProviderSession** response shape as today's provider verify. Expired-OTP resend fix inherited (shared mechanics).
- **Threat model T35:** provider social login — same trust boundary as T31/T33 (JWKS verify; link only on a verified email; no auto-create → no ghost salons), plus: registration binds the identity at creation (sub+email unique ⇒ one account per identity).

## 4. Pro app (`main_pro.dart`)
- **`pro_login_screen`** → mirrors the consumer `LoginScreen` (lockup, « Espace Pro », Google + flag-hidden Apple + email→code), with `provider_not_found` → CTA « Créer un compte » → register screen. No mandatory-phone step (registration already requires it).
- **`pro_register_screen`** → keeps business fields + required `PhoneNumberField`, and the identity section becomes: **[Continuer avec Google]** or **email + « Recevoir un code » + code field** → one submit. Old pro OTP screens go dormant (unrouted) like the consumer ones.
- `AuthServiceInterface` pro methods: `signInProviderWithGoogle/Apple`, `requestProviderEmailOtp`, `verifyProviderEmailOtp`, `registerProvider` gains the identity params. `ProviderUser` model += `authProvider` (email exists already).

## 5. Pro web (`/pro/connexion`)
- A pro variant of `LoginOptions` (Google + email; **login-only** — registration stays app-only, unchanged M7 decision) → pro BFF routes `/api/pro/auth/google` + `/api/pro/auth/email/request|verify` → `setProSessionCookies` (`myweli_pro_*`). `provider_not_found` → « Créez votre compte dans l'app MyWeli Pro ». e2e switches the pro login to the email flow.

## 6. Consequence for existing phone-based pro accounts
Pre-launch, the only provider accounts are seed/test ones. After this ships (with `AUTH_METHODS=google,apple,email`), **phone login is gone** — accounts without an email can't sign in and are re-registered. Fine now; noted because post-launch such a switch would need an email-attach migration flow.

## 7. Tests
Backend: register-with-Google / register-with-email-code (success + bad identity + duplicate email/sub), login-only semantics (`provider_not_found`), phone-gate 404, cross-tenant unchanged. App: mock/provider units + pro login/register widget flows. Web: pro LoginOptions unit + pro e2e on email flow. All suites + analyze 0 + contract updated in the same PR.

## 8. Open questions (for sign-off)
1. **Registration phone: required** (recommended — a salon must be reachable) vs optional like consumers?
2. **Gate pro phone-OTP in this same slice** (recommended — prod env already `google,apple,email`; kills ALL SMS spend; test salons re-register) vs keep pro phone until later?
3. **Apple seam for pro too** (recommended — trivial, same flag) vs consumer-only?
