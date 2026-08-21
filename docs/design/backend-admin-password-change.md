# Admin password change — design spec

> **Module:** M-admin (admin / ops console) · **Surface:** `backend/`
> **Status:** Built · **Threat model:** [BACKEND.md](../BACKEND.md) §7 T17, **T67**
> **Related:** [admin-console.md](admin-console.md) ·
> [backend-admin-login-throttle.md](backend-admin-login-throttle.md)

## 0. Why this exists — the defect

The launch checklist carries "secrets rotated". For the staff admin credential
that box could have been ticked green over a password that never changed.

`ensureSeedAdmin` is **insert-only**: it `SELECT 1 FROM admins WHERE email = @e`
and returns early if a row exists
([postgres_admin_auth_repository.dart:33](../../backend/lib/src/db/postgres_admin_auth_repository.dart#L33)).
So on any database that already has the admin — which is every database that has
ever booted — changing the `ADMIN_PASSWORD` secret and redeploying **does
nothing**. The service starts, reads the new value, finds the row, and discards
it. Nothing logs, nothing fails, and the operator has every reason to believe
the credential rotated.

**The insert-only behaviour is not the bug.** It is deliberate and pinned twice
(`admin_test.dart:84`, `postgres_admin_auth_test.dart:225`), and it is right: a
seeder that overwrote the hash on every boot would mean anyone who can set an
environment variable can take the admin account, and a rollback to an old
revision would silently restore an old password.

Three things are the bug:

1. **Nothing else can change the password.** There is no route, no tool, no
   path. The only lever is one that does not work.
2. **The documentation says the lever works.** `DEPLOYMENT.md:297` presents
   `ADMIN_EMAIL`/`ADMIN_PASSWORD` as the login credential without saying the
   password half is bootstrap-only, and `service.yaml` mounts it with no note.
3. **The no-op is silent.** A rotation that quietly fails is worse than one that
   errors, because the operator's belief is updated and the system is not.

Patching the seeder to overwrite would fix (1) by reintroducing the risk the
insert-only design exists to avoid. So: **stop rotating staff credentials by
redeploying.** Add the missing route, make the seed's bootstrap-only nature
explicit in code *and* audible at boot, and correct the docs.

## 1. Goal & scope

**Goal.** An authenticated admin can change their own password, over the API,
without a deploy — and the change takes effect everywhere immediately.

**In scope:** `POST /admin/auth/password`; refresh-family revocation on success;
throttling; the boot-time notice when the seed is inert; doc corrections;
contract + threat model.

**Out of scope:** admin self-signup, password *reset* by email (there is no
staff mail flow and one admin exists), a console UI (the ROADMAP holds console
UI as a separate later effort — this is backend-first, as that entry says),
and multi-admin management.

## 2. UX & flows

No user-facing UI in this slice. The operator flow is:

1. `POST /admin/auth/login` → access token.
2. `POST /admin/auth/password` with `{currentPassword, newPassword}` + bearer.
3. Every existing refresh token for that admin dies. Log in again.

## 3. API & contract

`POST /admin/auth/password` — **authenticated** (`role: admin`).

```json
{ "currentPassword": "…", "newPassword": "…" }
```

| Status | Code | When |
|---|---|---|
| 204 | — | changed |
| 400 | `invalid_body` | not JSON |
| 400 | `invalid_input` | missing/non-string field, or `newPassword` shorter than 12 |
| 400 | `password_unchanged` | new equals current |
| 401 | `unauthorized` | no/invalid access token (middleware) |
| 401 | `invalid_credentials` | `currentPassword` wrong |
| 403 | `forbidden` | non-admin principal (middleware) |
| 429 | `locked_out` | too many wrong `currentPassword` attempts |
| 503 | `throttle_unavailable` | throttle store could not answer (fail closed) |

**Note the path.** It lives under `/admin/auth/*`, which the middleware lets
through unauthenticated — so this route **authenticates itself** rather than
inheriting the gate. That is a trap worth naming: see §6.

## 4. Data model

No migration. Writes `admins.password_hash`; deletes the caller's rows from
`admin_refresh_tokens`; appends one `audit_log` row.

The audit entry records `admin.password_changed` with the actor as both actor
and target. **The metadata carries no password material** — not the old hash,
not a prefix, not a length.

## 5. Architecture & patterns

`AdminAuthRepository` gains:

```dart
Future<AdminPasswordChangeResult> changePassword({
  required String adminId,
  required String currentPassword,
  required String newPassword,
});
```

Both implementations (in-memory, Postgres) implement it. The route stays thin:
parse → validate → delegate → shape, matching `login.dart`.

Revocation is `DELETE FROM admin_refresh_tokens WHERE admin_id = @id` in the
same transaction as the hash update, so a crash between them cannot leave the
password changed with old sessions alive.

## 6. Security & authz

- **The current password is required even though the caller is authenticated.**
  Without it, a stolen access token — 15 minutes of access — converts into
  permanent account takeover. With it, the thief must also know the password,
  which is the thing they were trying to obtain.
- **It is throttled**, keyed on the admin's **email** — the same key `login` uses, sharing `LoginThrottle` with
  it. A key of its own would hand a stolen access token a **fresh** five-guess
  budget that login's lockout never sees. Otherwise this route is an oracle that costs one
  stolen access token and is not counted anywhere. **Fail closed**: if the
  throttle store cannot answer, refuse (503), matching `login`.
- **`/admin/auth/*` is exempt from the middleware gate**, because login and
  refresh must be reachable unauthenticated. This route therefore resolves and
  checks the principal *itself*. A test asserts an anonymous call is refused —
  because the natural mistake here is to assume a guard that does not apply.
- **Refresh families are revoked**, so a leaked refresh token dies with the
  rotation. **The current access token is not revoked** and stays valid until
  it expires: access tokens are stateless JWTs and this codebase has no
  denylist. That is a deliberate, bounded (~15 min) residual, written down
  rather than implied.
- **bcrypt** at the same cost as the seeder. The comparison is `BCrypt.checkpw`,
  which is constant-time in the hash comparison.
- **Floor of 12 characters** on the new password. The seed has no floor today;
  this route is the first place the codebase states one.
- **Nothing is logged**: not the password, not its length, not the hash.

**Threat model delta — T67** is added to BACKEND.md §7 (T61 was already taken).

## 7. Performance

Two bcrypt operations (~100 ms each at the default cost) on a route called by
hand a few times a year. No index, no N+1, no budget concern.

## 8. Testing plan

Route + repository, both implementations:

- 204 and the new password logs in · the old one does not
- wrong `currentPassword` → 401, and **counts against the throttle**
- `newPassword` < 12 → 400 · equal to current → 400
- non-JSON → 400 · wrong verb → 405
- **anonymous → 401** and **non-admin token → 403** (the `/admin/auth` exemption)
- refresh tokens issued before the change are **rejected afterwards**
- throttle store unavailable → 503, not 401
- the audit row exists and its metadata contains no password material
- `ensureSeedAdmin` returns **false** when it discards the password and true
  when it creates the admin — the input the boot `NOTICE` keys on. **The print
  itself is not asserted**: it lives inside the boot function, which needs a
  live pool. Said plainly rather than implied by a checkmark.

Each guard is watched red before it is believed.

## 9. Rollout & scope discipline

Ships in one PR with the contract and docs. No migration, so no ordering
constraint with the deploy. After it is live, the credential is rotated
**through the route**, and `ADMIN_PASSWORD` is then rotated too — not because
it takes effect on this database, but so that a fresh database bootstrapped
later does not come up holding the old password.

## 10. Definition of done

- [x] `dart analyze --fatal-infos --fatal-warnings` = 0 · **1177 tests** green
- [x] `openapi.yaml` carries the route
- [x] BACKEND.md §7 gains **T67** (T61 was taken)
- [x] DEPLOYMENT.md, `.env.example` and **both** manifests say bootstrap-only
- [x] every new guard watched red — six mutations, each confirmed red and the
      suite green again afterwards: dropping the self-authentication, dropping
      refresh revocation, not counting a wrong password against the throttle,
      giving the route its own throttle key, dropping the audit write, and
      accepting an unchanged password
- [x] ROADMAP refreshed

## 11. Open questions

- **Password reset if the only admin forgets it.** Today the recovery path is a
  direct `UPDATE admins SET password_hash` via Cloud SQL, which is exactly the
  privileged access this route reduces the need for. Acceptable while there is
  one admin and one operator; revisit when staff accounts are handed out.
- **No access-token denylist.** Bounded at ~15 minutes and written into §6.
