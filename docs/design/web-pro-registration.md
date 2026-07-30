# Web pro registration + the sign-in/sign-up identity matrix

| | |
|---|---|
| **Requirement** | Web↔app parity (memory `web-skill-before-tasks`) — closes the P4 gap: salons discovering myweli.com couldn't register (« créez votre compte dans l'app ») |
| **Status** | **Built** (2026-07-10) — aligned in chat; spec + build in one PR |
| **Scope** | `/pro/inscription` (business fields + Google/email identity, one submit) · pro login links to it (not-found CTA + permanent footer) · consumer connexion copy says sign-in = sign-up · the verified identity matrix documented below · parity follow-ups listed on the ROADMAP |
| **Out of scope** | Backend changes (none needed — `POST /auth/provider/register` is web-ready since P4) · the other parity gaps (web multi-service manual booking, pro reviews, KYC — ROADMAP follow-ups) |
| **Cross-refs** | [pro-auth-social.md](pro-auth-social.md) (P4 semantics) · [auth-social-email.md](auth-social-email.md) (link rules §4) · `docs/BACKEND.md` T31–T35 |

## 1. The identity matrix (verified against code + tests, 2026-07-10)

The user-facing guarantees of the auth system — every cell implemented AND
covered by backend tests:

| Case | Behaviour | Where enforced |
|---|---|---|
| Register with Google → sign in with Google later | Same account (matched by the provider `sub`) | consumer `loginWithSocial` / provider `_bySocial` |
| Registered by **email code** → later signs in with **Google** (same address) | **Accounts link into one** — the Google `sub` attaches to the existing account. Both methods work forever after | link rule §4; consumer T33 test « verified email links » · provider T35 test |
| Registered by **Google** → later signs in with the **email code** | Same account — the code proves inbox ownership, resolves by email | `verifyEmailOtp` → find-by-email |
| A provider asserts an **unverified** email | **Never links** — a separate account is created (consumer) / no link (pro). Prevents account takeover by claiming an address | T33/T35 + negative tests |
| Same email as **consumer AND salon** | Allowed by design — separate account spaces (`users` vs `provider_users`); a stylist can be a client elsewhere | separate tables/endpoints |
| Salon **login** with an unknown identity | Never auto-creates (`provider_not_found`) — registration requires the business fields | P4 login-only rule |
| Consumer **login** with an unknown identity | Auto-creates (find-or-create) — **sign-in IS sign-up** | P1 flow |

UX consequence of the last row: the consumer login page must SAY it («
Se connecter ou créer un compte ») — fixed in this slice.

## 2. `/pro/inscription` (new page, mirrors the app's ProRegisterScreen)

- **Layout**: brand lockup · « Créez votre compte professionnel » ·
  « Rejoignez MyWeli Pro et gérez votre salon. »
- **Business fields** (validated before ANY identity path fires — the backend
  registers identity + salon atomically): Nom de l'entreprise (required) ·
  Type (select: salon/barbier/spa/manucure/massage/autre) · **Téléphone du
  salon (required, international input — the C1/booking dedupe + contact
  key)** · Adresse (optional).
- **Identity section** « Votre identité de connexion »:
  - **S'inscrire avec Google** (GIS button, env-gated like login) → POST
    register `{idToken, …fields}`;
  - or **e-mail** → « Recevoir un code » (the shared
    `/auth/provider/email/otp/request` — same code serves login and register)
    → code field (+ devCode hint off-prod) → « S'inscrire » → POST register
    `{email, code, …fields}`.
- **Result**: 201 → pro httpOnly cookies (same `proLoginViaBackend` helper —
  it keys on the returned token pair, not the status) → `/pro` dashboard.
  Errors: `provider_exists` → « Un compte existe déjà pour cette identité.
  Connectez-vous. » (+ link) · `invalid_phone` · `otp_invalid` · generic.
- All four states; French; tokens; a11y labels; no secrets client-side
  (client IDs are public identifiers).

## 3. Entry points

- `/pro/connexion`: the `provider_not_found` error now links « Créer mon
  compte » → `/pro/inscription` (replaces « créez votre compte dans l'app ») +
  a **permanent** footer « Pas encore de compte ? Créer mon compte ».
- Consumer `/connexion`: heading → « Se connecter ou créer un compte » +
  subtext « Votre compte est créé automatiquement à votre première
  connexion. » (booking-inline LoginOptions untouched).

## 4. Security

Nothing new server-side: the register endpoint already enforces identity
proof (JWKS / hashed OTP), atomic code consumption, unique identity indexes
(`provider_exists`), rate limits, and no enumeration (T31–T35). The web form
adds no client authority — the server re-validates everything. Cookies stay
httpOnly via the BFF.

## 5. Tests

- e2e (stub gains `/auth/provider/register`): register a salon via the email
  path → lands authenticated on `/pro`; duplicate email → `provider_exists`
  message; the login not-found CTA navigates to `/pro/inscription`; consumer
  connexion shows the new copy.
- Unit: form validation helper (fields gate the identity section).
- tsc · lint · build · full suites.

## 6. Parity follow-ups (recorded on the ROADMAP, not built here)

1. Web **multi-service manual booking** (grid quick-create covers single-service).
2. Web **pro reviews** section.
3. Web **KYC/vérification** upload.
4. Consumer **discovery map** view on web.
