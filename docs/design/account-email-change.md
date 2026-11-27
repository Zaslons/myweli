# An account's e-mail changes only when it is proven (B16.3)

| | |
|---|---|
| **Module** | identity & auth (a cross-cutting foundation, [MODULES.md](../MODULES.md)): the consumer `users` store (`AuthRepository`, both twins), `PATCH /me`, two new routes under `/me/email`, the `User` DTO, the error reporter, and the consumer app's profile edit |
| **Status** | **Approved 2026-11-26.** Written on the owner's « Yes, spec B16.3 »; the owner answered the six questions of §11 at once, « Approve as recommended »: decisions 260–265 in BACKLOG, batch 16 (#879). Read once by an independent reviewer told to refute it against the code: 20 findings, each re-read in the code, then folded in (§13). **B16.3a (the backend) built 2026-11-26** on the owner's « Yes, build B16.3a » (§8.4), **merged** as `dabcbda4` (#886); **read before the deploy** (decision 263, §9.1): no account holds an unproven address, no Sentry report carries one; **deployed** 2026-11-26 (`myweli-api-00063-clx`, image `dabcbda`) and read back; the Cloudflare edge rule carries `/me/email/` since the same night; **read after** the same night (§9 step 4): the same counts, no unproven address, no Sentry issue since the deploy. **B16.3b (the app) built 2026-11-27** on the owner's « Yes, build B16.3b » (§8.5): red first, green, read once by an independent reviewer, 39 mutations red; **merged** 2026-11-27 (#892, `2a4a3982`). It reaches people with the next consumer app build. |
| **Owner** | the project owner: the answers, then each build, merge, read and deploy, each on the owner's word |
| **Last updated** | 2026-11-27 |
| **PRD ref / phase** | FR-AUTH-004 (profile: name, optional e-mail, photo) · threat model T32, T33, T34 · V1 |
| **ROADMAP entry** | [2026-11-26-account-email-change-spec.md](../roadmap/entries/2026-11-26-account-email-change-spec.md) |
| **Skills checked** | myweli-dev-guardrails · myweli-backend-guardrails · myweli-verification-guardrails · [BACKEND.md](../BACKEND.md) §3, §5 (decision 223), §7 (T32, T33, T34) · [SYSTEM.md](SYSTEM.md) §14 (forms), §15 |
| **Related** | [twin-fidelity-survey.md](twin-fidelity-survey.md) §2.3 (where this was found, B-P2-a) and §6 (decision 219) · [auth-social-email.md](auth-social-email.md) §4 (the link rule), §5 (`PATCH /me`) · [consumer-app-release-audit.md](consumer-app-release-audit.md) (the consumer app, not yet released) · [web-flow-audit-2026-11.md](web-flow-audit-2026-11.md) C10 (the website's e-mail editing, not built) |

---

## 1. Goal & scope

**What the survey found** (§2.3, decision 219: « a taken email answers 409 »). `PATCH /me` with an e-mail another account uses answers a 500 in production, and the in-memory twin hands the address to the editing account, so a test could « prove » that B's sign-in reaches A.

**What this spec found next to it, proven on both twins (§2.4), and worse.** The profile's e-mail is written as typed, unproven, and both sign-ins find an account by its e-mail **whether or not that account ever proved it**:
- **The trap.** A signed-in person types an address nobody uses yet, say a friend's, into their own profile. The day that address's owner signs in to MyWeli, **they land in the first person's account**:
  - by e-mail code, or with a provider the first person does not use: **both keep access** to one account, the first through their own Google or Apple sign-in. Each sees the other's bookings, favourites and phone number;
  - in Postgres, with the same provider as the first person: the owner's sign-in **replaces** the first person's Google or Apple link, so the owner gets the account and everything in it, and the first person's next sign-in makes a new, empty account. The in-memory twin keeps both links instead: a twin difference.
- **The cut-off.** An account that signs in by e-mail code and clears its e-mail field has no way back: its next code sign-in creates a new, empty account.
- **The 500 tells a third party.** In production the 500 is reported to Sentry, and the report carries Postgres's detail, « Key (lower(email))=(…) already exists »: **the other person's address**, which the error scrubber does not touch (§2.6).

**Who can reach it today.** In production, any signed-in consumer, through the website's `PATCH /api/me`, which forwards the body as it is (`web/app/api/me/route.ts:12-17`), or the API directly. The website itself offers no e-mail field (C10). The consumer app does, on « Modifier le profil », but it is not released (UNVERIFIED: whether test builds are in anyone's hands).

**What this cannot undo.** A trap that has already sprung looks like any other account: the owner's sign-in marked the address proven, and nothing records where an address came from. Those accounts stay as they are; §9's read counts only the traps not yet sprung.

**Goal.**
- An address finds an account only once that account has proven it, by a code sent to it or by Google or Apple asserting it.
- A person changes their account's address by proving the new one; a taken address is said only to whoever proves it.
- No profile edit removes an account's only way to sign in; a session alone cannot quietly move an account's sign-in elsewhere (Q6).
- Both twins answer the same; a contract holds them (decision 223).

**In scope:**
- the sign-ins' find-by-address rule, in `verifyEmailOtp` and `loginWithSocial`, on both twins (Q1);
- the e-mail change: two routes, a repository method on both twins, `PATCH /me` no longer changing the address, `emailVerified` on `User` (Q2, Q3, Q6);
- the error reporter scrubbing Postgres's detail (§2.6);
- the consumer app's « Modifier le profil » and a change screen (§5.4);
- the contract (and the website's generated `schema.ts`), BACKEND.md §7 (T33 corrected, one new row), auth-social-email.md §4–§5.

**Out of scope:**
- the website's e-mail editing (C10, B12.7): when it is built, it uses §3's routes;
- MyWeli Pro: `provider_users` has no e-mail change path (read: `postgres_provider_auth_repository.dart` writes only `email_verified`);
- the admin console, which reads and searches addresses but never writes one;
- the phone's twin of the trap, held shut by `AUTH_METHODS` (§12).

---

## 2. What exists today (OBSERVED)

### 2.1 Where an address is written

| Writer | What it writes | Proven? |
|---|---|---|
| `verifyEmailOtp` (sign-in by code) | finds an account by `lower(email)`, else creates one with the address | ✅ the code proves the inbox, and an account found unproven is **marked proven** (`postgres_auth_repository.dart:166-171`) |
| `loginWithSocial` (Google, Apple) | by `sub`; else, when the provider says the address is verified, finds an account by `lower(email)` **whatever its own `email_verified`** and sets the provider's `sub` column on it, **replacing** any sub already there (`:195-209`); else creates one (`:214-227`) | ✅: the Google route refuses a token without a verified address (`id_token_verifier.dart:129-131`, `requireVerifiedEmail: true` at `:175`), and Apple addresses are always verified (`:152`). The found account's own flag is never read |
| `updateUser` (`PATCH /me`) | the address as typed, normalised (trim, lower case), `email_verified = false` when it changed; `''` clears it (`:336-355`) | ❌ never |

The in-memory twin does the same through its `_usersByEmail` map (`auth_repository.dart:362-418`, `:506-514`), with two differences: a taken address is handed over instead of refused, and a second sub is **added** beside the first (`:402`) instead of replacing it.

### 2.2 The route and the clients

- **`PATCH /me`** (`routes/me/index.dart:37-93`) reads `email` and passes it to `updateUser`: no format check (`isValidEmail` exists, `validators.dart:30`, and the sign-in routes use it), no check that the address is free, no catch. A `23505` from the unique index on `lower(email)` (`migrations.dart:526-527`, partial: `WHERE email IS NOT NULL`) escapes to the observability middleware: a 500 envelope and an error report (§2.6).
- It promotes a new avatar **before** `updateUser`, so a PATCH that fails on its e-mail leaves the promoted photo unreferenced (§12).
- **The consumer app** sends `email` on **every** save of « Modifier le profil », the field's text, changed or not (`edit_profile_screen.dart:142-146`, `api_auth_service.dart:415-426`). An account with no address sends `''` (`:73`). The field is optional (`Validators.optionalEmail`), so emptying it sends `''` too. A refusal code the app does not know shows the generic sentence (`_messageFor`, `api_auth_service.dart:1015`).
- **The website** sends only `name` and `phone` (`web/lib/api/account.ts:144-150`, `web/lib/auth/client.ts:64-70`), but its BFF forwards any body.
- **`User` carries no `emailVerified`** (`AuthUser.toJson`, `auth_repository.dart:138-148`; the contract's `User` schema). The app shows the phone's « Non vérifié », and cannot show the address's.
- **Nothing mails a consumer at their profile address** except a sign-in code, sent to the address typed at sign-in. Salon alerts and invitations go to members of a salon (`salon_notifier.dart`, `team_service.dart`). The address is the sign-in identity and a line on the profile, nothing else.

### 2.3 What the threat model says

- **T33** (BACKEND.md §7): « An unverified/self-asserted email **never links** — it creates a separate account at worst. » True of the address a provider asserts. **False of the address an account holds:** `PATCH /me` stores a self-asserted address, and both sign-ins find it (this PR marks T33 so).
- **T32:** e-mail code requests answer the same whether or not the address has an account (« no enumeration »). A `409 email_taken` answered to anyone signed in would be the enumeration T32 closes.
- **A suspended account** is refused only at sign-in (`_loginAs`, `auth_repository.dart:425`; `postgres_auth_repository.dart:275`); a live session keeps working.

### 2.4 Proven on both twins

A throwaway probe (`AuthRepository` on both twins; Postgres on a fresh local database with every migration), deleted after, with the database. Addresses unique per run. The probe calls the repository: P6 is reachable there only (§2.1).

| Case | In memory | Postgres |
|---|---|---|
| P1 · A takes B's address | succeeds; **B's next code sign-in reaches A** | **throws `23505`** (a 500 at the route); B reaches B |
| P1b · the same, upper case and spaces around | the same as P1 | the same as P1 (normalised first) |
| P2 · A (Google) types an address nobody uses; its owner signs in by code | **the owner reaches A's account**; A's Google sign-in still reaches it; the address now shows as proven | **the same** |
| P3 · A (Apple) types it; its owner signs in with Google | **reaches A's account**; A's Apple sign-in still reaches it | **the same** |
| P4 · control: no profile change; the owner signs in by code | a separate account | a separate account |
| P5 · an e-mail-code account clears its address, then signs in by code | **a new, empty account** | **the same** |
| P6 · repository only: an unverified Google address another account H holds | a new account; **H's next code sign-in reaches it** | throws `23505` |

P4 is the probe's control: the same sign-in, without the profile change, reaches a separate account, so P2 and P3 are the profile change's doing. **Read, not probed:** with A and the owner on the **same** provider, Postgres's link replaces A's sub (`:201-206`), the in-memory twin adds a second one (`:402`).

### 2.5 Why no test saw it

- The twin's tests for `updateUser` assert what it does: that a change resets the flag (`auth_social_email_test.dart:206`) and that `''` clears (`auth_repository_test.dart:151`, `postgres_repositories_test.dart:2025`). None signs in afterwards.
- The link tests (`auth_social_email_test.dart`) link to accounts created proven. None links to an account whose address was typed, or one that already has a sub.

### 2.6 What the 500 sends to Sentry

- Postgres's `ServerException.toString()` appends ` detail: $detail` (package `postgres` 3.5.12, `exceptions.dart:159-163`); for this index the detail names the address.
- Sentry stores `throwable.toString()` as the exception's value (`sentry` 9.26.0, `sentry_exception_factory.dart:61-63`).
- `scrubEvent` clears the request and the breadcrumbs, never an exception's value (`error_reporter.dart:84-118`).
- Production sets `SENTRY_DSN` (`infra/gcp/service.yaml:240-242`). So each P1 in production has sent the taken address to Sentry. How many happened: not read (Q4).

### 2.7 Rate limits on code requests

- The per-IP limits cover `/auth/` and `/admin/auth/` only, in the server (`isIpLimitedPath`, `origin_front_door.dart:60-61`) and at Cloudflare's edge (`infra/cloudflare/96-api-front-door.sh:332`).
- Per address: the resend budget. Globally: the `cold` send budget (`send_budget.dart`), which every sign-in code shares.
- A route under `/me/` that sends codes would get neither per-IP limit: one account could mail any inbox, and drain the `cold` budget that every sign-in needs.

---

## 3. API & contract

### 3.1 Two new routes (Q2)

Both:
- a consumer token (`role == 'user'`; another role → `403 forbidden`); a suspended account → `403 account_suspended` (the sign-in's code);
- `404 auth_method_disabled` while `AUTH_METHODS` excludes `email`, as the sign-in routes;
- per IP: `isIpLimitedPath` and the edge rule both gain `/me/email/`; per account: a bucket through `allowUnderLimit` (`identity_limits.dart:217`), its ceiling set at the build. Over either → `429 rate_limited`;
- the account is the principal's, never an id from the body; `405` on another verb.

**`POST /me/email/otp/request`** `{ email }` — sends a code to the new address, and, when Q6's check applies, a code to the current one.

| Answer | When |
|---|---|
| `202 { expiresInSeconds, devCode?, currentCodeSent }` | sent, or declined by the send budget (the same answer, as the sign-in route). `currentCodeSent`: whether a code also went to the current address (Q6) |
| `400 invalid_body` · `400 invalid_email` | not JSON · not an address (`isValidEmail`) |
| `409 email_unchanged` | it is already this account's **proven** address. An address of its own that is unproven is accepted: this is how it gets proven |
| `429 otp_resend_limit` · `429 rate_limited` | the address's resend budget · the per-IP or per-account limit |

- **The same answer whether or not the address has an account** (T32). Taken is said at the verify, to the inbox's owner (Q3).
- The code is the sign-in's: the same table (`email_otp_codes`, keyed by the address), TTL, attempts, resends, send class (`cold`: someone typed the address), template and refund on a declined send. A code proves an inbox, whatever it is then used for. One consequence, accepted: a sign-in code and a change code for one address are the same code.
- `devCode` in dev only (`echoesOtpDevCode`). No smoke seam: nothing outside a test changes an address.

**`POST /me/email/otp/verify`** `{ email, code, currentCode? }` — proves it and sets it.

| Answer | When |
|---|---|
| `200 User` | the address is now this account's, proven |
| `400 invalid_body` · `400 invalid_input` | not JSON · not an address or not a code (`isValidEmail`, `isValidOtpCode`: one code for both, as the sign-in's verify, `routes/auth/email/otp/verify.dart:25-28`) |
| `400 otp_invalid` · `otp_expired` · `otp_none` · `otp_locked` | the new address's code refused: the sign-in's codes, each a `400` as there (`responses.dart:125-131`) |
| `400 current_otp_invalid` · `current_otp_expired` · `current_otp_none` · `current_otp_locked` | Q6's code for the current address refused, or missing when required |
| `409 email_taken` | another account has **proven** this address |
| `403 account_suspended` · `404 not_found` | suspended · the account vanished |

- On `409 email_taken` the code is **not consumed**: its owner can still sign in with it within its 5 minutes (T35's precedent for `provider_not_found`). Still TTL- and attempt-bounded.
- On `200`, in one transaction (§5.3): the codes consumed; any other account holding the address **unproven** loses it (`email = NULL`); this account's address set, `email_verified = true`.

### 3.2 `PATCH /me` (Q2)

- `email` is normalised (trim, lower case; `''` reads as no address) and compared with the stored address, read the same way. **Equal: accepted**, nothing changes. The app sends `email` on every save, `''` for an account without one, and keeps working.
- **Different: `409 email_change_requires_code`**, before anything is written, the avatar's promotion included.
- Absent: as today.
- The contract: `email`'s description, and `409` among `PATCH /me`'s responses.

### 3.3 `User` gains `emailVerified`

`AuthUser.toJson`, the contract's `User`, and the app's `User` model. The website regenerates `schema.ts` (CI's drift check). A reader that ignores unknown fields is unaffected.

### 3.4 Sign-in: no new route, no new answer

`/auth/email/otp/verify`, `/auth/google`, `/auth/apple` answer as today. What changes is which account they reach (§5.1).

---

## 4. Data model

No migration. `users.email`, `users.email_verified`, `google_sub`, `apple_sub` and their partial unique indexes stay. The rules of §5 keep one address on at most one account, as the index already does.

---

## 5. Architecture & design

### 5.1 An address belongs to whoever proved it (Q1)

**Sign-in by code** (`verifyEmailOtp`, address X proven by the code):
1. **Find** the account whose address is X **and proven**. Found: sign in.
2. **Otherwise take, then create:** any account holding X unproven loses it (`UPDATE users SET email = NULL WHERE lower(email) = @e AND NOT email_verified`), then a new account is created with X, proven. The branch that marked a found unproven account proven (`:166-171`) goes.

**Sign-in with Google or Apple** (`loginWithSocial`, sub S for provider P, verified address X):
1. **By sub.** An account with S: sign in. If it holds X unproven, mark it proven (an account proving its own address). It takes nothing from other accounts.
2. **Find** the account whose address is X **and proven**:
   - its P sub empty: link S to it, as today;
   - its P sub set to **another** sub: **never replace it.** The sign-in creates a new account without an address (Q1 states the alternative: refuse it).
3. **Otherwise take, then create,** as for a code.

**Keep out (repository contract).** An unverified address, which no route passes today (§2.1), is stored on a new account only when no account holds it; otherwise the account is created without one (P6).

**The order makes each rule carry weight:** the find filters on `email_verified` before any take, so dropping the filter reaches the unproven holder, and §8.3's mutation goes red.

**What the holder of an unproven address keeps:** their account, their sessions, their Google or Apple sign-in. They lose only the address they never proved. An account whose **only** sign-in was that address (an e-mail-code account that once changed it through `PATCH /me`) loses its way in: if its holder signs in by code at that address, they get a new account. §9's read counts them; the way back for such a person is §9's merge path.

**Why not the alternatives (Q1):**
- **The prover takes the whole account** (revoking the holder's other sign-ins and sessions): it hands the prover everything the holder put in it.
- **Clear the unproven addresses once, by migration, and keep the sign-in as is:** after Q2 no route writes an unproven address, so this closes today's unsprung traps too. But the find stays the only barrier, and nothing guards a future writer that stores one. Defence in depth is the recommendation's reason, not a gap in this option.

### 5.2 Changing an address: proven, through a code (Q2, Q6)

A repository method on both twins, beside `verifyEmailOtp`:

```dart
/// Proves [email] by [code] (and the current address by [currentCode] when
/// Q6's check applies), then makes it [userId]'s address (B16.3, §3.1).
Future<EmailChangeResult> changeEmail(
  String userId,
  String email,
  String code, {
  String? currentCode,
});
```

`EmailChangeResult` is `ok` with the user, a refusal of either code, `emailTaken`, `suspended` or `notFound`.

`updateUser` stops taking `email`: the parameter goes. `PATCH /me` compares, then answers §3.2.

### 5.3 One transaction, and the code used once

In Postgres, `changeEmail` runs in one transaction:
1. the account read `FOR UPDATE`; suspended → `suspended`;
2. the holder of the address read; a **proven** holder other than this account → `emailTaken`, nothing consumed;
3. each code **consumed in the transaction**, by a `DELETE … WHERE email = @e AND code_hash = @h AND expires_at > now() RETURNING`. Today's `_checkOtpIn` runs on the pool, outside any transaction, and its delete checks nothing (`postgres_auth_repository.dart:237-272`). With one code now redeemable at two routes, the check and the consumption become one statement. A miss falls back to the attempt accounting of today. The provider twin's `consume: false` variant (`provider_auth_repository.dart:642-650`) is the model for leaving it unconsumed on `emailTaken`;
4. the take, then the set.

The partial unique index stays the last guard: a race that slips past step 2 throws `23505`, mapped to `emailTaken`. The in-memory twin runs the same steps with no `await` between them.

### 5.4 The app: « Modifier le profil » and « Changer d'adresse e-mail »

Design to [SYSTEM.md](SYSTEM.md) §14 (errors under their field, submit disabled only while submitting, focus follows the first error) and §15 (outcomes). The code step reuses the sign-in's words and parts: « Entrez le code reçu par e-mail à {adresse}. » (`login_screen.dart:453`), « Renvoyer le code ({n}s) » on its 60-second cooldown (`:487`, `app_constants.dart:16`), `sign_in_refusal.dart` for the code's refusals, and `kNoConnectionMessage` (« Pas de connexion. Réessayez. », `failure_messages.dart:9`) for a failed request.

**« Modifier le profil »** (`edit_profile_screen.dart`):
- The e-mail text field becomes a row: « Adresse e-mail », the address (or « Aucune adresse »), and « Modifier » (a 48 px target, its label read with the row).
- **Proven:** under it, « Vous pouvez aussi vous connecter avec un code envoyé à cette adresse. »
- **Unproven** (`emailVerified: false`): « Non vérifiée », as the phone's « Non vérifié », and « Vérifier » (the change screen, the address filled in, straight to its code).
- Save sends `name` and `phone`, and `email` exactly as stored (or nothing): never a changed one.

**« Changer d'adresse e-mail »**, a pushed screen, two steps:

1. **The address.** Field « Nouvelle adresse e-mail » (e-mail keyboard; `AppTextField` gains an `autofillHints` parameter), button « Recevoir un code ». Under the button, always: « Vous ne pourrez plus vous connecter par code avec votre ancienne adresse. »
   - Not an address: under the field, « Saisissez une adresse e-mail valide. »
   - `409 email_unchanged`: under the field, « C'est déjà votre adresse. »
   - `429`: under the button, « Trop de demandes de code. Réessayez plus tard. »
2. **The code.** « Entrez le code reçu par e-mail à {nouvelle adresse}. », the code field, « Confirmer », « Renvoyer le code », and « Changer d’e-mail » back to step 1, as at sign-in.
   - **When Q6's check applies** (`currentCodeSent`): a second field, « Entrez le code reçu à votre adresse actuelle, {adresse}. »; each code's refusals under its own field.
   - **`409 email_taken`**, in the screen's `InlineFeedback`: « Cette adresse est déjà celle d'un autre compte MyWeli. Pour l'utiliser, connectez-vous avec elle. » Under it, a separate button « Choisir une autre adresse » (step 1, field cleared): `InlineFeedback` has no action slot (`inline_feedback.dart:23`).
3. **Done:** back to « Modifier le profil », the row shows the new address; snackbar « Adresse e-mail mise à jour. Connectez-vous désormais avec celle-ci. »

**Every state:** sending and confirming show the button's progress, disabled only while in flight; a failed request keeps what was typed and says `kNoConnectionMessage` in the `InlineFeedback`; back from step 2 returns to step 1 with the address kept; an answer that arrives after the account changed is discarded (the guard of `updateUser`, `auth_provider.dart:382`). Long French strings wrap; at 200 % text, « Confirmer » stays reachable.

**What the app adds:** `requestEmailChange` and `confirmEmailChange` on `AuthServiceInterface`, the mock (latency, `email_taken`, the code's refusals) and the API service; `emailVerified` on `User`; the two codes `email_change_requires_code` and `email_taken` in `_messageFor`.

### 5.5 Contracts on both twins (decision 223)

One contract file, run on both twins:
- P1 (`changeEmail` → `emailTaken`, B still reaches B), P2 and P3 (the owner reaches a separate account; A keeps theirs and its sign-in), P5 (no path clears an address), P6 (repository: no address on the new account; H reaches H);
- the sub rules: by sub first, its own unproven address marked proven; a proven holder with a sub for the same provider is never relinked (both twins: replaced in Postgres today, added in memory);
- `changeEmail`'s answers, Q6's second code, the unconsumed code on `emailTaken`, and the race (two transactions, as the refresh-rotation tests' `pool2`, `postgres_repositories_test.dart:2034`: one gets `ok`, the other `emailTaken`).

### 5.6 Layering

Routes parse, authorise (role, method gate, limits) and map answers; the repository owns the rules and the transaction. No service layer is added: the sign-in routes call the repository the same way.

### 5.7 The error reporter

`scrubEvent` strips the ` detail: …` part of a Postgres exception's value (it names the row's key), keeping the code and the message, which name only the constraint. A test sends a `23505` through it and asserts the address is gone.

---

## 6. Security & authz

- **T33 corrected:** an address finds an account only where the account proved it; a proof takes an unproven address from its holder; a sub is never replaced.
- **New row, T86: an account's e-mail change** (S/E/I/D):
  - taking an address by typing it: closed (§5.1, §5.2);
  - learning which addresses have accounts: closed (`email_taken` only to the inbox's owner; requests answer alike);
  - being cut off by clearing: closed (no clearing path);
  - **a session thief moving the sign-in to their own inbox** (a stolen refresh token, a borrowed unlocked phone): for an account whose only sign-in is its address, that is a permanent takeover, and the real owner's next code sign-in makes an empty account. Q6;
  - mailing codes to inboxes one does not own, and draining the `cold` budget: per-IP and per-account limits (§3.1);
  - a suspended account's session changing its address to escape the ban: refused (`403 account_suspended`).
- **Sentry:** the taken address no longer leaves in a 500's report (§5.7).
- Never logged: the codes, the addresses. The request log keeps the method and the path only (`request_middleware.dart:93-102`).

---

## 7. Performance

One indexed read and at most two indexed writes per sign-in or change, in one transaction. The added `email_verified` filter narrows rows the unique index already narrows to one.

---

## 8. Testing plan — red first, on committed code

### 8.1 Red first, for the stated reasons

- **Through the routes**, on today's code (the methods §5.2 adds do not exist yet):
  - `PATCH /me` with another account's address: today `500` in Postgres (the `23505`) and `200` in memory; wanted `409 email_change_requires_code`;
  - with `''` on an account that has one: today `200` (P5), wanted `409`;
  - with the same address, and `''` on an account without one: `200` before and after.
- **Through the sign-ins**, on both twins: P2 and P3 (the owner reaches A's account, wanted a separate one); the same-provider case (Postgres replaces A's sub, memory adds one; wanted: never relinked).
- **The scrubber:** a `23505` event keeps the address (wanted: gone).

### 8.2 Green

- The contract (§5.5) on both twins; the two routes' handler tests (every answer of §3.1, `403` for a pro token, `403` suspended, `401` without a token, `404 auth_method_disabled`, `429` per account, the principal's id used whatever the body says, `405`); `PATCH /me`'s cases; the sign-in suites.
- The three tests that change or clear an address through `updateUser` (§2.5) move to `changeEmail`.
- The app: widget tests for the row (proven, unproven, none) and both steps (every refusal under its field or in the `InlineFeedback`, focus on the first error, 200 % text), `edit_profile_screen_test.dart` updated, a golden of each step generated by the workflow.

### 8.3 Mutations, on committed code, each with its failure text

- Drop `AND email_verified` from the code sign-in's find: P2 red (the owner reaches A).
- Drop it from the social find: P3 red.
- Drop `AND NOT email_verified` from the take: a proven holder loses its address; the contract's « B still reaches B » red.
- Drop the take: in Postgres the owner's sign-in throws `23505`; in memory « A no longer holds X » red.
- Relink over an existing sub: the same-provider case red.
- Consume the code on `emailTaken`: a sign-in with that code fails, red.
- Accept a different address in `PATCH /me`: the route case red.
- Skip Q6's second code: its case red.
- The in-memory twin hands over a taken address again: P1 red in memory only.

### 8.4 As built (B16.3a, 2026-11-26)

Branch `feat/b16-3a-email-proven` from `main` (`2b8dd96b`). The tests red first (`259901c9`), then the fix (`0e7d201f`), the 429 inventory (`efa9c05d`), one assertion a mutation asked for (`e5b7cf0e`), the independent review's fixes (`e750987c`), the held transactions released at teardown (`7850eea5`).

- **Red first,** on today's code, for the reasons of §8.1 (`account_email_contract.dart`, run on both twins; the scrubber):
  - **in memory, 11 red:** [P1], [P1b], [P5] (`PATCH /me` 200, wanted 409); [P2], [P3], [same provider], [never relinked] (the owner lands in the account that typed or proved the address); [by sub first] (the own address stays unproven); [P6], [P6b] (an unverified address stored though held); and the scrubber (the address survives);
  - **on Postgres, a fresh database, 11 red:** [P1], [P1b] (the route throws `UniqueViolationException`: the 500); [P5]; [P2], [P3], [same provider] (Postgres replaced A's sub), [never relinked], [by sub first]; [P6], [P6b] (the sign-in throws `23505`); a real `23505`'s `toString()` names the address and survives the scrubber.
  - Green before and after: the own address re-sent, `''` without an address, the empty-sub link, [P4] the control, a proven holder's next sign-in.
- **The code:**
  - `AuthRepository` (both twins): the sign-in rules of §5.1; `changeEmail` and `emailIsOnlySignIn`; `updateUser` without `email`; `User.toJson` with `emailVerified`; the in-memory twin's test seam `plantUnprovenEmailForTest` (the contract's way to set a trap, as Postgres does by SQL);
  - `EmailChangeService` (`lib/src/auth/email_change_service.dart`): the per-account bucket, the sends and their refund, the notice (`account_email_emails.dart`);
  - `routes/me/email/otp/request.dart`, `verify.dart`; `PATCH /me`'s comparison, before the avatar's promotion;
  - `isIpLimitedPath` and the edge rule's script (`96-api-front-door.sh`) gain `/me/email/`;
  - `scrubEvent` strips ` detail: …` from every exception value (`stripDatabaseDetail`);
  - the contract, `schema.ts` regenerated; BACKEND.md T33 and T86; auth-social-email.md §4–§5.
- **Green:** the contract on both twins (27 cases; on Postgres 33, with the change race, the real-`23505` scrubs and the three concurrent cases of the review); the two routes' handler tests (25, every answer of §3.1, the bodies checked against `openapi.yaml`); the full backend suite on a fresh database (3338 passed, 2 skipped, after the review); analyze 0, format clean; the website's `tsc` clean.
  - The full suite's first run had two reds, both the 429 inventory (`rate_limited_status_test.dart`) doing its job: the request route named no `rate_limited`, and the verify route was an undeclared error map with a 400 fallback. Fixed in `efa9c05d`.
- **Mutations, on committed code, each with its failure text** (`b163_mut.py`, every one applied exactly once and the tree clean after). **36, every one red; none survives.**

| Mutation | Twin | Red | Text |
|---|---|---|---|
| drop `AND email_verified` from the code sign-in's find | both | [P2] | `expected not 'user_…' \| actual 'user_…'` (the owner reaches A) |
| drop it from the social find | both | [P3] | the same |
| drop the take | both | [P2] | memory: `expected null \| actual 'x.…'` (A still holds X); Postgres: the sign-in throws `23505` |
| relink over an existing sub | both | [never relinked] | `expected not 'user_…'` |
| consume the code on `email_taken` | both | [P1] taken | `expected true \| actual <false>` (the owner's sign-in fails) |
| accept a different address in `PATCH /me` | — | [P1], [P1b], [P5] | `expected <409> \| actual <200>` |
| skip the check before the avatar (`email != null && false`) | — | the same three | the same |
| skip decision 265's second code | both | 265 | `expected 'current_otp_none' \| actual <null>` |
| the in-memory twin hands a proven address over | memory | [P1] taken | `expected 'email_taken' \| actual <null>` |
| drop the by-sub proof (the `UPDATE`; the copy on the answer) | both | [by sub first] | `expected true \| actual <false>` |
| store an unverified address though held | both | [P6], [P6b] | memory: `expected null`; Postgres: throws `23505` |
| `emailIsOnlySignIn` ignoring links | memory | the Google change | `expected false \| actual <true>` |
| rethrow the race's `23505` | Postgres | [race] | throws `UniqueViolationException` |
| the notice to an unproven address | memory + route | « Vérifier », « no notice » | `expected null \| actual 'x.…'` |
| the scrubber leaves the detail | — | the scrub test | the address in the value |
| `/me/email/` out of `isIpLimitedPath` | — | the front door's scope | `expected <429> \| actual <200>` |
| drop `AND NOT email_verified` from the take | Postgres | [race take] | `email_taken` expected, the change succeeds: the holder that proved X loses it |
| no re-run on `40P01` | Postgres | [deadlock] | the change throws: a 500 |
| no re-run on a raced `23505` in the code sign-in | Postgres | [race insert] | the sign-in throws: a 500 |
| the scrubber's old pattern (stop at the next ` constraint `) | — | the « Failing row » case | the phone and the address after the word survive |
| the scrubber without the exact removal | Postgres | the real `23505` | ` table: users` stripped too |
| a 429 when the current address's resend budget is spent | — | « still 202 » | `expected <202> \| actual <429>` |
| no `email_unchanged` · the new code sent `warm` · no per-account limit · no role check · `email_taken` as 400 | — | each its route test | `<409>`/`<202>` · `cold`/`warm` · `<429>`/`<202>` · `<403>`/`<404>` · `<409>`/`<400>` |

  - **The take's filter is a guard, not defence in depth** (the first draft of this section called it redundant and its mutation a survivor; the independent review refuted that): a holder that proves X while a change or a sign-in takes it is re-read by the waiting `UPDATE`, now proven, and skipped. Without the filter its proven address is cleared. `[race take]` holds that transaction open and pins it.
  - **The harness found a hang, not a red:** under M8-pg the `[deadlock]` test's premise failed and left its side transaction open, and closing that pool waited for ever. Every test that holds a transaction on a second pool now releases it at teardown (`7850eea5`).
  - **One mutation aimed wrong, then fixed:** dropping only the copy of `emailVerified` onto the answered `AuthUser` stayed green on Postgres, because the test read the stored row. The sign-in's answer did carry `false`, so the test now asserts the answer too (`e5b7cf0e`), and both that mutation and the one dropping the `UPDATE` go red.
- **Where the build departs from §3–§5, and why:**
  - **A thin service, `EmailChangeService`** (§5.6 said none): the per-account limit needs the `RateLimiter`, which only services receive, as the booking and review services do.
  - **The new code is checked before the holder is read** (§5.3 listed the holder at step 2): reading it first would have answered `email_taken` to anyone, code or no code, against decision 262. Taken is said only once the code is right.
  - **A row lock, not one `DELETE … RETURNING`** (§5.3): each code row is read `FOR UPDATE` in the transaction, checked, and deleted only once every check passed. Just as atomic, and it is what lets the two codes of decision 265 be checked before either is consumed. The sign-in's verify runs the same check inside its consuming transaction, so one code cannot be redeemed at both routes.
  - **The race the index catches** is not two changes (they queue on the code row; the second answers `otp_none`) but a change against another account committing the address, a sign-in creating it. Tested with a held transaction.
  - **`email_unchanged` at the verify too,** and **`currentDevCode`** in dev (a dev build needs the second code as much as the first).
  - **The notice goes only to a proven old address:** an unproven one may be a stranger's inbox.
  - **The account is locked `FOR NO KEY UPDATE`, and a transaction Postgres aborts is re-run** (the review): a change locks the account, then the code rows; a code sign-in locks the code row, then the account (its take, or the key-share lock its refresh token's foreign key takes, which `FOR UPDATE` blocks and `FOR NO KEY UPDATE` does not). `_retried` re-runs the sign-ins and the change on `40P01`, and the sign-ins on a raced `23505` too (another account committed the address after the find), three runs at most; each run rolled back whole, a code's consumption included. Pinned by `[deadlock]` and `[race insert]`.
  - **The scrubber is exact** (the review): the pattern stopped at the next ` constraint ` or ` table: `, which a « Failing row contains » detail can hold, and the rest of the row went out. With the `ServerException` at hand, its `detail` is removed verbatim; otherwise everything from ` detail: ` on goes.
  - **The current address's resend budget spent is not a refusal** (the review): a live code then sits in that inbox, and a 429 there followed a code already sent to the new address. `202`, `currentCodeSent: true`.
  - **The per-account ceiling is a constant,** `kEmailChangeLimit` (10 an hour, one bucket for both routes), not a `LIMIT_*` variable: nothing has measured it, and a variable no manifest sets is a number nobody reads.
- **Not done here, for the record:**
  - **The edge rule was not applied by the build.** `96-api-front-door.sh` carries `/me/email/`; it took effect when its rule step was re-run, on the owner's word, after the deploy (§9.1).
  - **The identity-limit alert's text** (`92-identity-limit-alert.sh`) does not list the `email:` bucket; a refusal still writes its `rate_limited bucket=email:…` line.
  - **Decision 265 counts a Google or Apple link as another way in even while `AUTH_METHODS` disables that provider** (the review). Production enables both (`google,apple,email`, `infra/gcp/service.yaml`); the day one is switched off, its linked accounts change their address without the second code.
  - The phone path keeps `_checkOtpIn` (dormant, one route).

### 8.5 As built (B16.3b, the app, 2026-11-27)

Branch `feat/b16-3b-email-change-app` from `main` (`7f08c725`). The tests red first (`98c73cda`), then the build (`8abb2e68`, `54087019`), a vacuous assertion replaced (`b96cd7c7`), the row's layout after the first picture (`ba1a9f40`), the independent review's fixes (`43fd24d1`), the goldens (`c70a2e3a`).

- **Red first,** on today's code, through the real `ApiAuthService` over a fake HTTP client (`edit_profile_email_row_test.dart`, `user_email_verified_test.dart`), **10 red**, each for its reason: Save's `PATCH /me` body was `['name', 'email', 'phone']` (an edited address met `409 email_change_requires_code` as the generic sentence); no « Adresse e-mail » row, no « Non vérifiée », no « Aucune adresse », no « Modifier » or « Vérifier »; `User` dropped `emailVerified` (`null` four times). One of them first counted every `TextField` (the phone field holds one) and was corrected to count `AppTextField` before the build: it was red on the old code for that reason too.
- **The code:**
  - `User.emailVerified`; `EmailChangeRequest` (`expiresInSeconds`, `currentCodeSent`, the dev codes);
  - `AuthServiceInterface.requestEmailChange` / `confirmEmailChange`; **`updateUser` loses `email`** in the interface, the API service, the mock and the provider, as the backend's did — no screen can send a changed address;
  - the API service: the two routes through the refreshing client, the answered `User` adopted and merged into the stored session, and words for `email_taken` (`kEmailTakenMessage`), `email_unchanged`, `email_change_requires_code`, the four `current_otp_*`, `rate_limited`;
  - the mock answers as the server: one code per address shared with the sign-in, `email_unchanged`, the new code checked first, `email_taken` with the code left for its owner, decision 265's second code, the take from an unproven holder — and its sign-ins find only a proven address, a Google or Apple account by its link first;
  - `AuthProvider`: the two steps, an answer for an account no longer signed in dropped, the request in hand reset with the account;
  - « Modifier le profil »: the row (§5.4), Save with `name` and `phone` only;
  - `EmailChangeScreen` (`/profile/edit/email`, `?verifier=1` for « Vérifier »): §5.4's two steps and every state;
  - `sign_in_refusal.dart`: `currentCodeFieldFault`, `changeEmailFieldFault`; `AppTextField.autofillHints`;
  - `errorFromResponse`: a 429 with no JSON — Cloudflare's own limit on `/auth/`, `/admin/auth/` and `/me/email/` (« error code: 1015 », §9.1) — reads as `rate_limited`.
- **Where the build departs from §5.4, and why:**
  - **The title is « Adresse e-mail »**, not « Changer d’adresse e-mail »: `a15_titles_test` found it does not fit a pushed bar at 360 dp × 2× (SYSTEM.md §13.3). The row that opens it says the same words.
  - **The row's label sits above, full width; « Modifier » goes under the address when the two cannot share a line.** Seen in the first Linux golden: beside « Modifier » the label broke inside « e-mail » and the address on three lines (§13.3: the control beside a value moves first). Gated by `expectNoMidWordBreak` with the real font. An address wider than the whole line at 200 % — « awa.kone@exemple.ci » measures 328 px of 312 — breaks at its punctuation: no layout has more to give. *(Corrected 2026-11-27: it broke where the line ran out — « awa.kone@exemple. » / « ci » — and only looked like punctuation; since §12's fix it breaks before its « @ ».)*
  - **« Vous ne pourrez plus vous connecter par code avec votre ancienne adresse. » shows only when the current address is proven** (§5.4 said « always »): with no address, or an unproven one, no old address signs anyone in, and the line would be false.
  - **« Vérifier » sends the code at once** (« straight to its code »); a refusal leaves the address step with its fault. **Its success says « Adresse e-mail vérifiée. »**: the address did not change.
  - **Two code fields carry two names**, « Code de la nouvelle adresse » and « Code de l’adresse actuelle »; one field keeps the sign-in's « Code à 6 chiffres ». At 200 % the two names end in Flutter's declared ellipsis (a mobile opt-out, §13.3); the sentence above each field names it in full, and a screen reader hears the whole name.
  - **The button that spins is the request's** (« Recevoir un code », « Confirmer » or « Renvoyer le code »); all are disabled while one runs.
  - **429 words:** at the request, `otp_resend_limit` and `rate_limited` say §5.4's « Trop de demandes de code. Réessayez plus tard. »; at the verify, `rate_limited` says « Trop de tentatives. Réessayez plus tard. » — which the sign-in screens now say too, where they said the generic sentence.
  - **New sentences** (for the owner's review in the PR): `email_change_requires_code` « Changez votre adresse e-mail avec « Modifier » : un code vous sera envoyé. » (an older build only); `current_otp_none` « Aucun code actif pour votre adresse actuelle. Demandez un nouveau code. », `current_otp_expired` « Le code de votre adresse actuelle a expiré. Demandez un nouveau code. », `current_otp_locked` « Trop de tentatives pour le code de votre adresse actuelle. Demandez un nouveau code. », `current_otp_invalid` « Code de votre adresse actuelle incorrect. » — each said in the form only when the second field is not on screen; under it, the sign-in's words.
  - **`emailVerified` absent reads as « proven » when an address is there.** Only a session stored by an earlier build lacks the field (the server sends it on every `User` since B16.3a); every address in production was proven at both of §9.1's reads, and no route writes an unproven one since. Read as unproven, the row would say « Non vérifiée » to everyone who updates. Pinned both ways. A rollback to an image before B16.3a would read every address as proven.
  - **The implied back arrow stays** on the code step (`canPop: false`): Flutter still draws it and it calls `maybePop`, which the screen turns into the address step. A first reading took a failed `pageBack()` for its absence; `pageBack` looks for an English « Back » tooltip, and a probe measured the arrow there.
- **Green:** the red-first file; `email_change_screen_test` (26 runs: every state of §5.4, focus on the first fault, the second code, « taken » and its way on, back, the cooldown, « Vérifier », a sign-in or a sign-out over the screen, 48 px on both steps, 200 % text, the merged nodes); the real route (2); the API service (17); the mock (12); the provider (8); the model (4); `api_errors` (the edge's 429); the three goldens (Linux). The full app suite on the reviewed code (`43fd24d1`): 4,411 passed, 92 skipped (the goldens, off Linux); analyze 0; format clean. Its first full run had one red, the title gate doing its job (above).
- **Mutations, on committed code, each with its failure text** (`b163b_mut.py`, each applied exactly once, the tree clean after). **39, every one red; none survives.** Two re-aimed after the review moved their lines (a non-applying mutation is no result), and one (the « ancienne adresse » line always shown) first went red in one test only: the « Vérifier » test asserted the line's absence on the code step, where it never shows, and an unproven address now checks it on the address step.

| Mutation | Red |
|---|---|
| `'email': ''` back in `PATCH /me`'s body | the API body · Save sends no address |
| `fromJson` ignores the field · absent reads unproven · `toJson` drops it | the model |
| the proven line always · no « Non vérifiée » block · « Vérifier » without `?verifier=1` · the row not merged | the row, its semantics, « Vérifier » |
| « Modifier » back beside the address | `expectNoMidWordBreak`: 174 px of 185 |
| the old-address line always · the second code ignored · « taken » without its way on · « Choisir » keeping the address · the current code's fault under the new code · the 429s generic · back on the code step pops · back while a request runs · no cooldown · no auto-send · « vérifiée » never said | each its screen test |
| the screen's account guard · its signed-out back · a resend's fault on a field off screen · a `current_` fault with no second field | each its screen test |
| the route ignores `?verifier` | the real route |
| the provider's account guard · the request kept across accounts | the provider |
| `currentCode` always sent · no session merge · `email_taken` generic · the edge's 429 generic | the API service · `api_errors` |
| the mock consumes on « taken » · finds an unproven holder · no link first · decision 265 skipped, or by sign-up | the mock (and the screen's two-code tests) |
| no `current_` field fault · `email_unchanged` not the field's · no autofill hint | each its screen test |

- **Read once by an independent reviewer, told to refute it against the spec and the server, at `54087019`:** nothing blocking; every answer of both routes and of `PATCH /me` found placed and worded. Fixed (`43fd24d1`): the mock found Google and Apple accounts by address only, and its decision 265 asked by sign-up, not by link; Cloudflare's own 429 said the generic sentence; the resend read the field, not the address the code went to; signed out on the code step, back first went to a hidden step; and tests for each guard it found unexercised. Already fixed by then: the vacuous « Vérifier » assertion (`b96cd7c7`). Recorded, not changed: below.
- **Looked at the pictures** (`consumer_edit_profile_email_w360_x2`, `consumer_email_change_address_w360_x2`, `consumer_email_change_codes_w360_x2`, Linux, 360 dp × 2×): the first run showed the row's broken label (fixed) and caught the floating label mid-animation (the test now lets it finish). Only these three images moved; the other 89 are byte-identical.
- **Not done here, for the record:**
  - **« Vérifier » sends a code each time the screen opens**, as the sign-in does: opened often within a code's five minutes, the address's resend budget answers « Trop de demandes de code » while a valid code sits in the inbox.
  - **At 200 %, the code step's sentence breaks a long address inside a word** (« awa.kon / e.nouvelle@exemple. / ci »), as the sign-in's identical sentence does: the address follows « à » on a line already started. §12. *(Fixed since, 2026-11-27: §12.)*
  - The website's e-mail editing (C10) stays out of scope; when built, it uses §3's routes.
- **Merged** 2026-11-27 10:24 UTC on the owner's « Yes, when green » (#892, squashed as `2a4a3982`; tree `bb835294` equal to the tested head `236b57df`, 13 checks of 13, no attribution). The Security check had failed on another branch's test fixtures (gitleaks reads every branch's history); that session renamed them, and a re-run found no leaks. `main` was merged in twice on the way (#890, #891), the conflicts each side's own row in the specs index.

---

## 9. Rollout & scope discipline

1. **Answers** (§11), then the build, in two PRs on the owner's word (Q5):
   - **B16.3a, backend:** §3, §5.1–§5.3, §5.5, §5.7, the contract and `schema.ts`, the edge rule's expression, BACKEND.md §7, auth-social-email.md;
   - **B16.3b, the app:** §5.4.
2. **Read production before the deploy** (Q4), read-only, the usual method (the Auth Proxy, a read-only session, a probe write refused), counts only:
   - consumer accounts, by `auth_provider`;
   - those holding an **unproven** address, by `auth_provider` and by whether they also have a Google or Apple sub;
   - accounts with no address, no Google and no Apple sub, by `auth_provider` (the legacy phone accounts land here too, so P5's cut-off is the `email` ones);
   - **and, on the owner's word, Sentry:** how many events carry `users_email_lower_key` (the P1s that sent an address there), to delete.
   If the read finds e-mail-code accounts holding an unproven address, the owner chooses, before the deploy:
   - deploy as is: such a person proves the address in the app once B16.3b ships (« Vérifier »), and until then a code sign-in at that address gives them a new account;
   - handle each one (the counts are expected tiny);
   - or hold B16.3a's deploy until B16.3b ships.
   **The merge path,** for a person who already got the empty account: delete the empty account, then prove the address on the old one (« Vérifier »).
3. **Deploy B16.3a** on the owner's word. Nothing runs at the deploy: an unproven address is taken only when someone proves it. Until B16.3b ships, an app build that edits the address gets the generic sentence; the consumer app is not released.
4. **Read after,** on the owner's word: the same counts; no new unproven address; no new Sentry event with an address.

**Rollback.** No migration. An older image finds unproven addresses again and lets `PATCH /me` write them: today's state, the trap included. Addresses proven through `/me/email` stay proven.


### 9.1 As run (2026-11-26)

- **Merge.** #886 squashed as `dabcbda4`, 20:58 UTC, on the owner's « Yes, merge it »: parent `2b8dd96b` (#879, this spec), tree `f82fa5a2` equal to the tested head `6fd6ad41`, 12 checks of 12, no attribution. The merge's run built and pushed the image: « staging absent — promote with image_tag=dabcbda ».
- **Read before the deploy** (step 2, decision 263), on the owner's « Yes, run the read »: the Auth Proxy, a read-only session and `BEGIN READ ONLY … ROLLBACK`, a probe write refused, counts only; the queries rehearsed first on a local fixture of 8 known rows, every count matched by hand.

| What | Production |
|---|---|
| Consumer accounts | 9 — Google 7, Apple 1, e-mail code 1; all `active` |
| Holding an address | 9, **all proven** |
| Holding an **unproven** address | **0** — no trap is set |
| Whose only sign-in is an unproven address | **0** — §9's three options do not arise |
| No address and no Google or Apple sub (P5's cut-off) | 0 |
| Google subs · Apple subs · both | 7 · 1 · 0 |
| An address not in lower case | 0 |

- **Sentry** (the same step), read-only, the owner's signed-in session in the built-in browser: the `SENTRY_AUTH_TOKEN` (the `symbol-upload` organisation token) cannot read issues (403). Sentry keeps 30 days (a 90-day window is clamped to 30). The control, `"underlying socket"`, finds MYWELI-BACKEND-7; `users_email_lower_key`, `UniqueViolationException` and `"duplicate key"` find **nothing**, across all projects: nothing to delete within what Sentry keeps. Older than 30 days: not visible there (UNVERIFIED that none remains; the retention says deleted).
- **Deploy** (step 3), on the owner's « Yes, deploy it »: run 45903188551, `--ref main` (`5b0bbeee`, only docs since `dabcbda4`), `environment=production confirm=deploy image_tag=dabcbda`; success.
  - Serving `myweli-api-00063-clx`, 100 %, latest ready, commit label `dabcbda`, created 22:12:29 UTC.
  - The run verified the serving image as index `sha256:82597effb00f…`; the revision runs its linux/amd64 child `sha256:16efb1386ff5…`, read from the registry's index.
  - Rollback target: `myweli-api-00062-f5c` (R2, `306a5d5`, an ancestor of `dabcbda4`).
- **Read back:** `/health` 200, env `prod`, on `api.myweli.com` and on the Cloud Run address; `GET /me/email/otp/request` and `/verify` 405 against a 404 for `/me/email/otp/nonexistent`, and `POST /me/email/otp/request` without a token 401; the revision's only WARNING+ lines are those four probes' request logs; production-checks run 45903535104, 12 checks of 12.
- **The edge rule,** on the owner's « Yes, re-run it »: only steps 1 (token and zone) and 5 (the rule) of `96-api-front-door.sh`, its own lines (steps 2–4, the Worker redeploy, its secret and DNS, not run: not asked).
  - Before (a GET): `/auth/` or `/admin/auth/`, block, 10 per 10 s per IP, timeout 10.
  - The ownership check passed, the PUT applied, the script read it back (rule `e3a6edbb…`); a second GET shows `… or starts_with(http.request.uri.path, "/me/email/")`, the numbers unchanged.
  - At the edge: 12 GETs to `/me/email/otp/request` in a burst — 1 to 10 answered 405 by the origin, 11 and 12 answered 429 `error code: 1015` by Cloudflare, not the app's JSON 429.
- **Read after** (step 4), on the owner's « Yes, run the read », 23:55 UTC, 1 h 43 min after the deploy, `myweli-api-00063-clx` still serving: the same read-only session, a probe write refused, counts only; step 2's queries plus two (the accounts created since the deploy; the newest account's time), those two rehearsed first on a local fixture of 4 known rows, every count matched by hand.
  - The database: every count of step 2's table **unchanged** — 9 consumer accounts, all holding a proven address, **none unproven**, none cut off, none in mixed case. **No account created since the deploy;** the newest dates from 2026-11-25 18:16 UTC.
  - Sentry, all projects and environments, every state: **no issue** between the deploy and the read. The control, the same view over the two days before the deploy, lists four (web issues). Over 30 days, 17 issues, as at step 2, none a `23505`.
  - The request logs since the deploy, counted by path and status: no sign-in (`/auth/*`: 0); on `/me/email/`, only the read back's and the edge's probes; no warning or error from the application.
  - **What it shows, and what it cannot:** nothing moved, and nothing carried an address to Sentry. No sign-in, account creation or address change reached production in that window, so no real person has gone through the new rules yet; `/me/email/` has no caller until B16.3b.
---

## 10. Definition of done (for the build)

- [ ] §8.1 red for the stated reasons, then green; §8.3's mutations red with their texts.
- [ ] Full backend suite green; analyze 0; format clean. The web's generated `schema.ts` without drift. The app: analyze 0, the widget tests, the goldens.
- [ ] The contract (`openapi.yaml`: the two routes, `PATCH /me`'s `email` and `409`, `User.emailVerified`); the edge rule; BACKEND.md §7 (T33, T86); auth-social-email.md §4–§5; this spec's status; BACKLOG B16.3; the index row; a roadmap entry each.
- [ ] Feature branch and PR each; CI green; owner-authored, no attribution.

---

## 11. Questions for the owner — answered 2026-11-26, « Approve as recommended » (decisions 260–265)

Numbered from **260**, after batch 18's 255–259.

**Q1. Who reaches an account by its e-mail?**
- **Recommended: only an account that proved the address** (a code, or Google or Apple asserting it). A proof takes an unproven address from whoever holds it. A Google or Apple link never replaces an account's existing link for that provider: such a sign-in gets a new account without the address (§5.1). Closes every unsprung trap, with no migration. → ✅ **Decision 260.**
- Or the same, but a sign-in that would replace a link is refused, with a sentence to sign in by code instead (a new refusal on both sign-in screens, app and website).
- Or the prover takes the whole account, revoking its holder's other sign-ins and sessions.
- Or clear the unproven addresses once, by migration, and keep the sign-in as is.

**Q2. How does an address change?**
- **Recommended: by proving the new one,** a code sent to it (§3.1, §5.2, §5.4); `PATCH /me` no longer changes or clears it; `User` gains `emailVerified`, so the app can show and prove an unproven address. → ✅ **Decision 261.**
- Or not at all: the address shows read-only, and `PATCH /me` refuses a change. Smallest; a person who wants another address starts a new account.
- Or the survey's fix alone: `PATCH /me` answers `409 email_taken`, and the address stays unproven (Q1 then carries it all, and T32's enumeration opens).

**Q3. When is a taken address said?**
- **Recommended: at the code's verification only,** so only the inbox's owner learns it, and the code stays valid for their sign-in (§3.1). → ✅ **Decision 262.**
- Or at the request: anyone signed in learns whether an address has an account (T32).

**Q4. Read production before the deploy?**
- **Recommended: yes,** read-only, counts only (§9 step 2), and Sentry for the reports that carry an address: it shows whether a trap is set today, whether an account's only sign-in is an unproven address (you then choose among §9's three options), and how many reports to delete. → ✅ **Decision 263.**
- Or deploy without reading.

**Q5. When, and in how many PRs?**
- **Recommended: now, as a P1** (a security fix reachable through the website today), **in two PRs:** the backend first (B16.3a), then the app (B16.3b); each build, merge and deploy on your word. The website's e-mail editing (C10) uses the routes when it is built. → ✅ **Decision 264.**
- Or one PR with both.

**Q6. May a session alone change the address an account signs in with?**
- **Recommended: not when the address is the account's only sign-in.** For an account with a proven address and no Google or Apple link, the change also takes a code sent to the current address (§3.1's `currentCode`). After every change, a notice goes to the old address: « L'adresse de votre compte MyWeli a été changée. Si ce n'est pas vous, écrivez à support@myweli.com. » (its own address, so the `warm` class). → ✅ **Decision 265.**
- Or the notice only: a session alone changes the address, and the old address learns of it.
- Or a session alone, as account deletion today (`DELETE /me` asks for no code either).

---

## 12. Found next to it

- **A PATCH that fails after the avatar's promotion leaves the photo unreferenced** (§2.2). This build moves the e-mail refusal before the promotion; the route's one other late failure is `not_found`, an account deleted under the request. Not decided here.
- **The phone's twin of the trap.** `verifyOtp` finds an account by `phone_number` whatever `phone_verified` says (`postgres_auth_repository.dart:392-405`, `auth_repository.dart:565-571`), and `PATCH /me` writes the phone unproven. Only `AUTH_METHODS` holds it shut (phone sign-in is dormant, T34). **A condition for ever turning phone sign-in back on:** the same rule as §5.1, for the phone.
- **`PATCH /me` with a provider's token** answers `404 not_found` (pros are not in `users`). Harmless; the new routes answer `403`.
- **At 200 %, « Entrez le code reçu par e-mail à {adresse}. » broke a long address inside a word** — ✅ **fixed 2026-11-27** on the owner's approval, the profile row included (PR #895, branch `fix/code-sent-to-address-breaks`; SYSTEM.md §13.3, §21 row 99).
  - **The mechanism, as measured** (real font, 360 dp × 2×, a 312 px line), not as this line first put it. A short address was never cut: the engine moves a word that fits a line to the next one whole (« awa@exemple.ci », 248 px). What broke was any address wider than a line, which at that size is about 18 characters and so most real addresses. It began on the line « à » had started and was cut where that line ran out (« par e-mail à aminata. » / « kone@exemple.ci. »). Alone on a line it was still cut mid-word (« aminata.kone@exem » / « ple.ci. »). So a line of its own was needed, but was not enough on its own.
  - **Now:**
    - `CodeSentTo` draws the sentence, then the address on a line of its own, in ink, with no period drawn. A screen reader hears one node, the sentence as it was.
    - `Formatters.breakableEmail` lets the address break only before its « @ » or a « . » of its name part (« aminata.kone » / « @exemple.ci »).
  - **Sites:** five. The sign-in; the Pro sign-in; the Android Pro sign-up (the same sentence, found while checking); the change's two sentences (the second loses its drawn comma and keeps it spoken); and « Modifier le profil »'s row.
  - **Verified:**
    - red first on all five sites;
    - the full app suite: 4,520 passed, 98 skipped;
    - three Linux goldens, each looked at;
    - 24 mutations on committed code, all red. The seam check first survived: on correct code it has nothing to catch. It is now held by four falsifiers, wrong drawings each made to fail the gate for its own reason.
  - **Still open:** a name part or a domain longer than a line still breaks inside, and no layout has more to give. The website's two sign-ins say the same sentence (`LoginOptions.tsx`, `ProLoginOptions.tsx`).

---

## 13. Review log

- 2026-11-26 — drafted: the code read, P1–P6 proven on both twins (§2.4), the probe and its database deleted.
- 2026-11-26 — **read once by an independent reviewer, told to refute it against the code.** 20 findings (2 blocking, 14 should-fix, 4 nits), each re-read in the code before being folded in:
  - **Blocking:**
    - « the Google 500 » cannot happen through a route: the Google token check refuses an unverified address (401), and Apple addresses are always verified. P6 is now repository-only, and Q1's third option is rejected for the right reason;
    - a session alone could move an account's sign-in to the thief's inbox: Q6.
  - **Should-fix:**
    - Postgres replaces a sub where the twin adds one (P3's same-provider case, a twin difference);
    - a sub is never replaced (the Google Workspace lock-out);
    - the sub-first order, so an account's own unproven address is not taken from it;
    - sprung traps are undetectable;
    - the new routes sat outside every per-IP limit;
    - the find-then-take order, so the find's filter carries weight and its mutation can fail;
    - the red-first plan through the routes;
    - `''` for an account without an address;
    - `emailVerified` on `User`;
    - `kNoConnectionMessage`;
    - the « ancienne adresse » line;
    - suspended accounts;
    - the 23505 detail reaching Sentry (§2.6, §5.7);
    - §9's options and the merge path.
  - **Nits:** the code checked and consumed in one statement (§5.3); the sign-in step's own words and widgets; the phone's twin (§12); line references, `devCode` in dev only, and `schema.ts`.
- 2026-11-26, answered: « Approve as recommended », all six (decisions 260–265, batch 16 in the BACKLOG). B16.3 is a P1, built in two PRs, the backend first; each build, merge, read and deploy on the owner's word.
- 2026-11-26 — **B16.3a built** (§8.4), on the owner's « Yes, build B16.3a »: red first on both twins, green.
- 2026-11-26 — **B16.3a read once by an independent reviewer, told to refute it against the code.** No rule broken, no twin difference, no enumeration. Found, each re-read in the code and fixed: the take's filter is a real guard (a concurrent proof), and §8.4's first draft said otherwise; a deadlock between a change and a code sign-in; a raced insert answering 500; the scrubber's pattern cut short by the detail; a 429 after a code had gone out; seven missing route and contract tests; two comments. Then 36 mutations, every one red.
- 2026-11-27 — **B16.3b built** (§8.5), on the owner's « Yes, build B16.3b »: red first (10), green; the title shortened and the row laid out again after the gate and the first picture; 39 mutations red.
- 2026-11-27 — **B16.3b read once by an independent reviewer, told to refute it against the spec and the server.** Nothing blocking. Fixed: the mock's link-first sign-in and its decision 265 by link, the edge's 429, the resend's address, the signed-out back, and tests for every guard found unexercised; one vacuous assertion was already replaced.
- 2026-11-27 — §12's address line fixed (branch `fix/code-sent-to-address-breaks`): its mechanism measured first, corrected in §12 and §8.5, then built on the owner's approval.
