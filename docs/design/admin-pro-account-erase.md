# Erase a Pro account from the admin API, on a support request (B0.25's server half)

| | |
|---|---|
| **Module** | backend — `DELETE /admin/provider-accounts/{id}/erase` and a read-only `POST /admin/provider-accounts/lookup`; and the written support procedure that uses them (§10) |
| **Status** | **Approved 2026-11-13 (decisions 141, 142) — ~~not built~~ built 2026-11-14 on `feat/admin-pro-account-erase`; not merged, not deployed** (Build log, end). Built from option 1b of the R1 draft (session notes, not in the repo; a review's 15 findings folded in before the owner read it). The French replies of §10.3 were approved by the owner as written on 2026-11-14 (decision 147), in the backend PR (#793). A review of this branch on 2026-11-14 tightened the check, the procedure and the replies (Review log, end); the owner's answers are unchanged |
| **Owner** | the project owner: the merge, the production deploy, the procedure's approval, and every support erase, each on the owner's yes |
| **Last updated** | 2026-11-14 |
| **PRD ref / phase** | FR-AUTH-005 [V1] (`docs/PRD.md:344`) · V1 · gates B0.19's page (S1), and so android-play-release step 7 (decision 141) |
| **BACKLOG item** | B0.25, its server half — decision 141 amends decision 139's « does not gate step 7 » for this half · decision 142 (the check and the procedure) · R1 of [web-pro-account-deletion.md](web-pro-account-deletion.md) §12 |
| **ROADMAP entry** | [2026-11-13-pro-account-deletion-spec.md](../roadmap/entries/2026-11-13-pro-account-deletion-spec.md) |
| **Skills checked** | myweli-backend-guardrails (invoked for this spec) · [BACKEND.md](../BACKEND.md) §1–§3, §7 · myweli-verification-guardrails' marking rule applied (not invoked) |
| **Related** | [web-pro-account-deletion.md](web-pro-account-deletion.md) §2.3, §5.1, §11 · [pro-deletion-erase-gaps.md](pro-deletion-erase-gaps.md) (B0.22, may share the deploy) · [web-privacy-pro-deletion.md](web-privacy-pro-deletion.md) (B0.23, which points people here) · [account-deletion-erasure.md](account-deletion-erasure.md) §12 (the consumer precedent) · [demo-account-deletion-lock.md](demo-account-deletion-lock.md) · [admin-console.md](admin-console.md) |

OBSERVED = read in the code at `main` `d19655bd` (this branch adds no code). INFERRED = reasoned from it.
UNVERIFIED = not readable from here.

## 1. Goal & scope

**Goal.** A Pro who cannot reach « Profil » (no sign-in possible, or a member whose access was removed) is
promised a reply, then, once verified, the same deletion they would have made themselves (web spec §5.1
`:399`, `:401`). Nothing can run that deletion safely today (§2). This adds the smallest safe mechanism and
the procedure that uses it, so the owner never opens the writable database console during an erase.

**In:** the erase route; the lookup; one audit action and its French label; the OpenAPI paths; the
threat-model rows; the procedure (§10) and its French replies. **Out, still in B0.25 (P3, later):** the
console screen (a lookup form, an erase button with a typed confirmation, its UX spec, an admin deploy) and
any step-up password check on both erase routes. **Never:** a change to `deleteAccount`, SQL by hand.

## 2. What exists (OBSERVED)

- **Every step lives in one method:** `ProviderAccountService.deleteAccount`
  (`backend/lib/src/provider_account_service.dart:91-236`) — the demo lock (`:112-114`), the bookings gate
  over every owned salon (`:116-135`), each owned salon to `draft` with `_erasedContact`, its pending
  validation, notes and place notice (`:145-164`), the rebuild (`:166-168`), the KYC objects (`:174-183`),
  devices, notifications, idempotency keys (`:189-191`), the Apple revoke (`:197`), the identity
  (`:199-200`), the memberships (`:215`), the re-hide (`:226-235`). Codes: `forbidden`,
  `demo_account_locked`, `future_bookings` (`:76-79`).
- **Its optional dependencies default to null or Noop** (`:24-45`), so a second construction compiles and
  silently skips devices, notifications, Apple, validations, place notices and the rebuild. Production
  wires them once, in the singleton `providerAccountService` (`backend/lib/src/dependencies.dart:700-718`).
- **The consumer precedent.** `DELETE /admin/users/{id}/erase` (`backend/routes/admin/users/[id]/erase.dart:21-44`)
  delegates to `UserErasureService` and audits `user.erase` **after** success with `metadata: {}`
  (`backend/lib/src/admin/admin_user_service.dart:75-92`; « a tombstone rather than a copy », `:86-89`).
  Not copied: its free-text `reason` (`:83-85`) and its catch-all, which answers 404 **keeping the code**
  (`erase.dart:41-43`). Run once, with curl, on 2026-08-18; the target count nearly included the owner's
  two own accounts, and « Reading the table before deleting from it is the only reason that did not
  happen » (`docs/LAUNCH.md:300-310`).
- **No admin read maps a Pro e-mail or a member to an account.** `accountByEmail` exists (trimmed,
  case-insensitive, `backend/lib/src/auth/provider_auth_repository.dart:196-197`), unexposed;
  `GET /admin/salons/{id}/validation` gives a salon's active owner only. The consumer route answers 404 to
  a Pro id (`docs/design/demo-account-deletion-lock.md:211`).
- **The gate.** `/admin/*` requires `role == admin`, deny by default, before any handler; only `/admin/auth`
  is open (`backend/routes/admin/_middleware.dart:11-24`; T17, `docs/BACKEND.md:439`). One role; seeded
  accounts; a 15-minute access token (`backend/lib/src/admin/admin_auth_repository.dart:50-61`). The per-IP
  limit covers `/auth/` and `/admin/auth/` only (`backend/lib/src/security/origin_front_door.dart:61`).
- **Logging.** No app line for a successful request (`backend/lib/src/observability/request_middleware.dart:59-104`);
  Cloud Run's request log keeps URL and status (INFERRED; UNVERIFIED here); no body is logged. The front
  door forwards a DELETE's body (`infra/cloudflare/worker/api-front-door/src/index.js:104-107`).
- **Guards a new caller trips:** the T69 inventory of `deleteAccount(` callers
  (`backend/test/demo/demo_locks_inventory_test.dart:199-229`); a French label for every admin audit action
  (`mobile/test/unit/validation_labels_test.dart:272-290`, `mobile/lib/screens/admin/widgets/audit_actions.dart:10-33`).

## 3. Contract (`docs/api/openapi.yaml`, tag `admin`, beside `/admin/users/{id}/erase`, `:4473-4505`)

Every non-2xx is the standard envelope `{error, message?}` (`backend/lib/src/responses.dart:8-18`).

### 3.1 `DELETE /admin/provider-accounts/{id}/erase`

DELETE on a sub-path, as the precedent (`erase.dart:15-18`). Body **required**:
`{"confirmEmail": "<stored address>", "reason": "support_no_sign_in" | "support_access_removed", "caseRef": "MWP-7K2Q9D"}`.
Any other key is ignored and stored nowhere: the schema is open, as every request body in the contract is.

- `confirmEmail` — compared trimmed and case-insensitively with the stored e-mail. An **operator-error**
  guard against a wrongly copied id (the 2026-08-18 near-miss), not an attacker guard: any admin reads the
  address through §3.2.
- `reason` — a **closed** code, the page's two support paths. No free text: the audit log is kept with no
  limit, so a typed name would move personal data into it rather than erase it.
- `caseRef` — **required** (decision 142), `^MWP-[A-Z0-9]{6}$`. Not personal data; it ties the lasting
  audit row to the owner's case record (§10.1).

| Outcome | Status | `error` |
|---|---|---|
| erased | **204** | — |
| body missing or not a JSON object, or a field of the wrong JSON type | 400 | `invalid_body` — the code every admin route gives a non-object body, and the one `observabilityMiddleware` gives a field read through `optionalString` (`docs/BACKEND.md` §2, `backend/lib/src/http/body_fields.dart:40`); nothing written |
| a field missing or empty, `reason` outside the set, `caseRef` off pattern | 400 | `invalid_input` — every field read before any is acted on; nothing written |
| no token / not an admin | 401 / 403 | `unauthorized` / `forbidden` (the gate) |
| unknown id; or `deleteAccount` answered `forbidden` (a concurrent call won, §4.3) | 404 | `not_found` |
| `confirmEmail` ≠ the stored e-mail, or no e-mail on file | 409 | `confirmation_mismatch` — nothing written |
| a pending or confirmed booking in the future in an owned salon | 409 | `future_bookings` — no admin override |
| the store-review identity (`revue@myweli.test`, `backend/lib/src/auth/demo_seam.dart:42`) | 403 | `demo_account_locked` — **its own arm**, as in `backend/routes/me/provider/index.dart:160-165` |
| any other verb | 405 | `method_not_allowed` (`responses.dart:40-41`) |

The precedent's catch-all would answer the demo lock as **404** `demo_account_locked`: the right code under
a status that reads « not found ». Each code gets its own arm.

### 3.2 `POST /admin/provider-accounts/lookup`

Read-only. **POST, the address in the body**: a `GET ?email=` would put it in Cloud Run's request log. Body
`{"email": "<address>"}`: not a JSON object, or `email` not a string → 400 `invalid_body`; trimmed,
3–254 characters, one `@`, else 400 `invalid_input`. **Exact match only**
(`accountByEmail`): one account or 404 `not_found`, never a prefix, never a list. 200 answers
`{accountId, email, createdAt, ownedSalons: [{id, name, status}], memberships: [{providerId, salonName, role, status}]}`.

**Why these fields and no others.** `accountId` is what the erase takes; `email` is the **stored** address
the challenge goes to and the `confirmEmail` value; `ownedSalons` is exactly what the erase hides, computed
by `deleteAccount`'s own rule (`:118-122`; since the review, one method both call,
`ProviderAccountService.ownedSalonIds`), so the owner sees the blast radius before the yes;
`memberships` let a revoked member be matched by the salon they name; `createdAt` tells a fresh account from
an old one. **Left out:** the account's name, phone, address, KYC documents and verification state: the
procedure needs none, and every field returned lands in the owner's terminal. **No « has future bookings »
field:** a second definition of the gate would drift from `:126-135`; the erase answers 409 itself. **Not
audited**, like every read-only admin support view (`admin_user_service.dart:42-52`,
`backend/lib/src/admin/admin_provider_service.dart:89-98`).

**Also in the PR:** three schemas (`AdminProviderAccountEraseRequest`, `AdminProviderAccountLookupRequest`,
`AdminProviderAccountLookup`), the 400 of both paths listing `invalid_body` and `invalid_input`, and
`web/lib/api/schema.ts` regenerated (`web/package.json:15`, `gen:api`).
That file is the website's, so the merge also deploys the website, types only (B0.1).

## 4. Architecture

### 4.1 Files
- **`backend/lib/src/admin/admin_provider_account_service.dart`** (new): `lookup(email)` and
  `erase(adminId, id, {confirmEmail, reason, caseRef})`, returning `AdminResult`
  (`backend/lib/src/admin/admin_kyc_service.dart:8`). It holds a `ProviderAccountService` it is **given**,
  plus the auth, membership, providers and audit repositories. It reaches `deleteAccount` only through
  that service: one `deleteAccount(` in the file, on the `ProviderAccountService` field, never on the auth
  repository (test 11). No `dart_frog`, no SQL (BACKEND.md §1).
- **`backend/routes/admin/provider-accounts/[id]/erase.dart`** and **`…/provider-accounts/lookup.dart`**
  (new), thin: verb, body validation, `principalOf(context)!.userId` (the gate guarantees an admin, as
  `erase.dart:31`), delegate, map. No `deleteAccount(` text in either.
- **`backend/lib/src/dependencies.dart`**: one final, `adminProviderAccountService`, constructed **with
  `providerAccountService`**, never a `ProviderAccountService(` of its own. **`backend/routes/_middleware.dart`**:
  one `provider<AdminProviderAccountService>`, beside `AdminUserService` (`:128`).
- **`mobile/lib/screens/admin/widgets/audit_actions.dart`**: `'provider_account.erase': 'Compte Pro effacé'`
  (as `'user.erase': 'Compte client effacé'`, `:27`). It shows after the next admin console deploy.

### 4.2 `erase`, in order
1. `accountById(id)` → null: `not_found`.
2. The stored e-mail is null, or differs from `confirmEmail` (trimmed, lower-cased): `confirmation_mismatch`.
3. `deleteAccount(id)` on the given singleton, **unchanged**: the demo lock, the bookings gate and every step
   of §2 run exactly as for `DELETE /me/provider`. `forbidden` → `not_found`; the two other codes pass through.
4. **On success only:** `append(actorAdminId: adminId, action: 'provider_account.erase', targetType:
   'provider_account', targetId: id, reason: <the closed code>, metadata: {'caseRef': caseRef})`. No e-mail,
   no name, no salon name. A row claiming an erase that did not happen is worse than none
   (`admin_user_service.dart:71-74`).

### 4.3 Repeats and double-submits (INFERRED from `:91-236`)
- **A repeat after success** answers 404 at step 1 and writes nothing. No `Idempotency-Key` is needed: the
  second answer is distinguishable, and the read-back (§10.2 step 8) relies on it.
- **Two concurrent calls** both pass step 1 and both write the salon steps, the same values twice. One
  identity delete wins (`:199-200`); the other gets `forbidden` → 404 and appends nothing. One audit row.
- **A 5xx after the identity delete** leaves the account gone and **no audit row**; a retry answers 404 and
  cannot write it. The case record notes it (§10.2 step 7). Accepted, as the precedent accepts it.

## 5. Data
No migration. One row per erase in `audit_log` (`backend/lib/src/db/migrations.dart:309-318`), read with
`GET /admin/audit?action=provider_account.erase` (`backend/routes/admin/audit/index.dart:15-16`).

## 6. Security — threat model ([BACKEND.md](../BACKEND.md) §7)

| Row | Delta written in the backend PR |
|---|---|
| **T83 (new)** — support erase of a Pro account (`DELETE /admin/provider-accounts/{id}/erase` · `POST /admin/provider-accounts/lookup`) | **S/T/E/I** — a forged request gets someone else's account erased; a stolen admin token erases any Pro; a wrong id erases the wrong person; the lookup leaks addresses. **Mitigations:** identity proven by a one-time code sent only to the stored address and confirmed from it (§10.1, decision 142); the T17 gate; `confirmEmail` against a wrong id; the demo lock and the bookings gate with no override; audited after success with a closed reason and a case number, no PII; the lookup exact-match, POST-bodied, minimal. **Residuals:** one `admin` role; a stolen 15-minute token can erase, as it can already erase a consumer and suspend a salon; no step-up yet (B0.25); a 5xx after the identity delete leaves no row; whoever can read the stored mailbox (for example a salon inbox shared with staff) can confirm |
| **T17** | its audited mutations gain `provider_account.erase` (closed reason, `caseRef`); its read-only views gain the lookup |
| **T53** | a second caller, the admin path, through the same `providerAccountService` singleton (test 11) |
| **T69** | the inventory's expected set gains `lib/src/admin/admin_provider_account_service.dart`; that file's one call is on the service, never on the repository (test 11, since the inventory works per file) |

**Abuse and rate.** No public surface: both routes sit behind the admin gate, which the per-IP limit does
not cover and need not: the token is the control. The lookup answers one exact address; walking it means
guessing addresses one by one, and an admin can already read a salon owner's `email` through
`GET /admin/salons/{id}/validation`. The app logs nothing new; the platform log sees an opaque id in the
erase's path and no body. **Secrets:** none added; the admin password and token live only in the owner's
terminal (§10.2 step 2), never in Claude's, and never in a command's arguments: `ps` shows every
process's arguments to every process of the same macOS user, a Claude session on that Mac included. So
the token and the person's address reach `curl` and `jq` only from builtins, through process substitution
and pipes (§10.1, « Nothing in a command's arguments »).

## 7. Performance
The lookup: one read by e-mail, one membership read, one salon read per membership (a handful). The
erase: `deleteAccount`'s own cost, plus one read and one insert. Rare: 2 Pro accounts in production on
2026-11-12 (BACKLOG B0.20).

## 8. Tests — red first, each watched red once on committed code

`backend/test/admin_provider_account_test.dart` (new; in memory, through the **real** `ProviderAccountService`;
the shape of `backend/test/admin_user_test.dart:78-113`):

| # | Test | Mutation that turns it red |
|---|---|---|
| 1 | erase: 405 on GET, POST, PUT, PATCH; lookup: 405 on GET, DELETE | accept any verb |
| 2 | no token, an expired admin token, an admin token signed with another secret → 401; a provider and a consumer token → 403, per route; the same hand-built admin token unexpired passes (the control) | exempt the new paths in the gate; skip the expiry check; skip the signature check |
| 3 | 204; `accountById` null; each owned salon `draft`, phone, address, WhatsApp and Mobile Money cleared, and the pin (B0.22, merged 2026-11-14 in #791); a **member-only salon untouched** | a hand-written subset instead of `deleteAccount` |
| 4 | one `provider_account.erase` row with that id, that code and `{caseRef}`; its JSON holds neither the e-mail nor the name | `confirmEmail` into `metadata` |
| 5 | another address → 409 `confirmation_mismatch`, nothing written, no row; a case variant of the right one passes | compare without lower-casing |
| 6 | no body, a non-object body, `{"confirmEmail": 5, …}` → 400 `invalid_body`; a missing field, an unknown `reason`, a `caseRef` off pattern → 400 `invalid_input`; the lookup likewise with `email`; nothing written; an unknown key, free text included, is ignored and stored nowhere (the contract's body is open) | `caseRef` optional; a field read with a cast (a 500) |
| 7 | unknown id → 404 `not_found`, no row | answer 403 like `/me/provider` |
| 8 | a future booking → 409 `future_bookings`, the salon still `active`, no row | append before `deleteAccount` |
| 9 | the demo identity → 403 `demo_account_locked`, nothing written, no row | the precedent's catch-all (404) |
| 10 | a second call → 404, still one row | append before step 1 |
| 11 | wiring, the `salon_validation_wiring_test.dart` idiom (comments stripped): the service's construction passes `providerAccountService`; `dependencies.dart` holds one `ProviderAccountService(`; in `admin_provider_account_service.dart`, exactly one `deleteAccount(`, on the `ProviderAccountService` field, and none on a `ProviderAuthRepository`-typed one | construct a fresh one; call `_auth.deleteAccount(id)` in the service |
| 12 | lookup: 200 with exactly §3.2's keys (no `name`, `phoneNumber`, `kycDocs`); a case-insensitive match; 404 otherwise; `ownedSalons` = the salons test 3 sees hidden, a salon linked by the scalar field alone included (no owner row); both read `ProviderAccountService.ownedSalonIds`, the one definition | return `account.toJson()`; drop the scalar link |
| 13 | T69 inventory red until the service file joins its set, with a comment | — (red by construction) |
| 14 | `validation_labels_test.dart` red until the label lands | — (red by construction) |
| 15 | `test/db` (Postgres, `DATABASE_URL` in CI): the erase through the route on a real database, 0038's cascade included (`:202-214`), in **its own database**, created and dropped by the file: on the shared one, `postgres_repositories_test.dart`'s per-test `TRUNCATE … CASCADE` races it | the sibling's `TRUNCATE` in the window (a 404) |
| 16 | contract: both paths, statuses and schemas match the routes | drop the 409 from the contract |

Then the full backend suite, `dart format`, `dart analyze --fatal-infos --fatal-warnings` = 0.

## 9. Rollout

1. This spec, in docs PR #790. The procedure (§10) and its French replies go to the owner with the backend PR.
2. **The backend PR from `main`** (`feat/admin-pro-account-erase`): code, tests, contract, `schema.ts`, the
   T-rows, the label, `// Design:` links, and [demo-account-deletion-lock.md](demo-account-deletion-lock.md)
   §6.3's row « another route that deletes … a provider account? » and §6.4, which say no admin route
   deletes one: they name this route (through the service, so the lock holds) and the invitation-accept
   caller the row already misses (`routes/auth/provider/invitations/accept.dart`). CI green; the owner
   merges **outside the merge hold** of
   android-play-release step 3 (c) and outside any Apple review (the merge deploys the website's types).
3. **The production deploy, on the owner's yes** (`deploy-backend.yml`, `image_tag` = a merge commit),
   outside any Apple review. If it merged before B0.22, **B0.22's deploy carries both**; B0.22 never waits
   for it; if it is not ready by then, it deploys alone later, still before B0.23. **A shared deploy has a
   shared rollback:** rolling it back removes both, and while rolled back
   no pin is erased and no support erase can run.
4. **Read-back, nothing mutated:** the revision at 100 %; `/health` 200; with an admin token (§10.2 step 2's
   sign-in and `adm`), an erase of a
   made-up id with a valid body → the route's JSON 404 `not_found` (not the router's); a lookup of
   `personne@myweli.test` → 404. *Optional, on the owner's yes:* a throwaway Pro account with a salon and
   a pin, erased through the route and read back as §10.2 step 8.
5. **The procedure approved** by the owner, after step 4's read-back and **before B0.23 merges** (decision
   143). *Engineering consequence, not part of the answer:* the deploy and its read-back come before B0.23
   too, so the procedure is approved against routes that answer, and B0.23's sentence 2 sends people to
   support from its first day. Then copied into
   `docs/DEPLOYMENT.md` as « Effacer un compte Pro sur demande au support ». Then S1 (web spec §11).
6. Docs: this spec → Built, then Live; BACKLOG B0.25's server half ticked.

## 10. The written procedure (decision 142)

### 10.1 Rules
- **Who.** The owner, the only admin. Claude may draft a reply or a case summary **from the account id
  and the outcome only**; nobody pastes the person's address, name or messages into a Claude session.
- **Where.** Steps 2–8 in a separate terminal app (Terminal or iTerm), **not** the Claude app's terminal
  panel, which a Claude session can read. Clear its scrollback after each lookup (steps 3 and 5) and at
  the end.
- **Nothing in a command's arguments.** A separate terminal hides the screen, not the processes: while a
  command runs, `ps -axww` shows its arguments to every process of the same macOS user, a Claude session
  on the same Mac included. So the token and the person's address are never in one. The token goes as a
  header that curl reads from a builtin through process substitution (`adm`, step 2:
  `-H @<(printf …)`, curl ≥ 7.55); the address goes into `jq` through a pipe
  (`printf '%s' "$EM" | jq -Rs …`); every authenticated call goes through `adm`, never a hand-typed
  `-H "authorization: Bearer $TOKEN"`. None of the values is exported, since `ps -E` shows a process's
  environment too. Checked on this Mac on 2026-11-14 against a local listener with dummy values: the old
  form's token was in `curl`'s arguments and the address in `jq`'s, and the forms below show neither and
  send the same request.
- **Escalate** (used below): the case leaves these steps; the owner decides it by hand and writes the
  decision, and why, in the case record. Nothing is erased on an escalated case without that line, and
  T0's « au plus tard dans 14 jours » still holds.
- **Two values per case.** `CASE` (`MWP-` + 6 random characters, not secret, in every subject) and `CODE`
  (8 random characters, fresh per case, never derived from `CASE`, written only in T1 and the case
  record), each made in that terminal, never typed by hand:
  ```zsh
  echo "MWP-$(LC_ALL=C tr -dc 'A-HJ-NP-Z2-9' </dev/urandom | head -c 6)"   # CASE
  LC_ALL=C tr -dc 'A-HJ-NP-Z2-9' </dev/urandom | head -c 8; echo            # CODE
  ```
- **Who receives what.** Every message is a **new** message, never « Répondre », so a `Reply-To:` is never
  used. The challenge (T1) goes only to the address **stored on the account**, read from the lookup, never
  to the sender's. The acknowledgement (T0) and a « could not verify » (T4) or « no account » (T5) answer
  go to the sender's address, as new messages; T2 and T3 go to the stored address.
- **No account oracle.** Steps 1–4 run the same day. When the sender's own address is the only thing
  given: T1 to it if it holds an account, else T5. When the person names another address, or a salon:
  T1 goes to the stored address if an account is found, and nothing goes anywhere if none is; either way
  the sender's next message is T4, 14 days after the request that named it (T0's day when it was the
  first), unless the stored address has confirmed by then (T2 then closes the case). Neither the reply
  nor its timing tells the sender whether an account, or a hidden salon, exists.
- **The proof** needs all three: (a) the reply's `From:` is the lookup's `email`, compared
  case-insensitively; (b) it is in T1's thread and carries `CODE` and CONFIRMER, within 14 days of T1;
  (c) once the header is confirmed readable in Outlook, its `Authentication-Results` shows `dmarc=pass`
  or `compauth=pass` **for that address's domain**. Until then, (a) and (b) are the proof, which holds
  because `CODE` went only to the stored mailbox. (b) alone says nothing about the sender: Outlook groups
  messages by subject, and `CASE`, in T0's subject, reached the sender. A reply that misses (a) or (b) is
  not a proof, and the window keeps running. Header results: `fail` → the case is marked forged, nothing
  is erased, and the sender gets T4 when the window closes; `none`, `softfail`, `bestguesspass`, or no
  result for that domain → escalate. **No phone callback.** A person who lost the stored mailbox gets
  T4, and nothing is erased. **Accepted:** whoever can read the stored mailbox (for example a salon inbox
  shared with staff) can confirm.
- **Delays** (the owner's call; no legal deadline claimed): a first reply (T0) within 2 business days;
  every sender hears from us within 14 days of T0, as T0 says; the deletion done within 30 days of the
  confirmation, or, on T3's suspension path, within 30 days of the last appointment.
- **The case record.** Kept by the owner outside the mailbox, **never in git**, with no name and no address:
  `CASE`, dates, the account id, the path (no sign-in / access removed), the proof (« CODE confirmé dans le
  fil de T1 le …, depuis l’adresse enregistrée — en-tête : pass | non lisible »), the owner's yes, the
  outcome, the audit row's time. How long the mailbox thread is kept stays the owner's to decide; T1 and
  T2 tell the person that the thread stays.
- **Once, before the first case.** Whether `support@myweli.com` reaches Apple private-relay addresses (a
  read in Apple's developer account, on the owner's yes; until then a bounce is escalated and nothing is
  erased); whether `Authentication-Results` is readable in Outlook.

### 10.2 Steps
1. **Receive.** Open a case and make `CASE` (§10.1). Move the thread into a « Suppressions Pro » folder.
   Within 2 business days, send **T0** to the sender's address, as a new message. It never says whether
   an account exists. Steps 2–4 follow the same day.
2. **Sign in as admin** (zsh; nothing echoed, nothing in the history; the password never in a command's
   arguments: `printf` is a builtin, so it reaches `jq` through a pipe; stop unless « OK: signed in »;
   the token lasts about 15 minutes; `adm` is `curl` with the token as a header it reads from a builtin,
   so the token is never in an argument either, §10.1):
   ```zsh
   API=https://api.myweli.com
   read -r 'AE?Admin e-mail: '; read -rs 'AP?Admin password: '; echo
   TOKEN=$(printf '%s' "$AP" | jq -Rs --arg e "$AE" '{email:$e,password:.}' \
     | curl -sS -X POST "$API/admin/auth/login" -H 'content-type: application/json' --data @- \
     | jq -r '.accessToken // empty'); unset AP
   [[ -n $TOKEN ]] && echo 'OK: signed in' || echo 'STOP: sign-in failed'
   adm() { curl -sS -H @<(printf 'authorization: Bearer %s\n' "$TOKEN") "$@"; }
   ```
3. **Locate** by the sender's address, or one the person names:
   ```zsh
   read -r 'EM?Address to look up: '
   printf '%s' "$EM" | jq -Rs '{email:.}' | adm -X POST "$API/admin/provider-accounts/lookup" \
     -H 'content-type: application/json' --data @- | jq .
   ```
   By a salon name, each read through `adm` and filtered, never printed whole (the validation view carries
   the owner's name, phone, contact and KYC status, and the salon's address, phone and pin,
   `backend/lib/src/validation/salon_validation_service.dart:370-437`):
   `adm "$API/admin/providers?q=…" | jq '.items[] | {id, name, status}'` → the salon →
   `adm "$API/admin/salons/<id>/validation" | jq '.owner | {accountId, email}'` → this lookup on that
   `email`. The case record takes what it needs; then clear the scrollback.
   **Stop:**
   - the sender's own address is the only thing given, and it holds no account → T5;
   - another address or a salon named → §10.1's « no account oracle »: T1 only if an account is found,
     and T4 to the sender on day 14 whatever was found, a salon name matching nothing included;
   - by a salon name: the validation view shows one active owner only (`activeOwnersOf`, the earliest
     invited, `backend/lib/src/access/membership_repository.dart:125-129`), so a requester who says they
     are not that owner (a member, or one of several owners) → escalate, and no T1 to the owner shown;
   - `revue@myweli.test`, an account with no e-mail, or a member asking for the salon's own data → escalate.
4. **Challenge.** Make `CODE` (§10.1); send **T1** as a new message to the lookup's `email`. Only §10.1's
   proof counts. No proof within 14 days → T4 to the sender, close; a `fail` header → marked forged, T4
   when the window closes; `none`, `softfail` or `bestguesspass` → escalate.
5. **The owner's yes,** right before step 6: sign in again (step 2) and look the stored address up again
   (step 3), since the token lasts minutes and the owned salons may have changed since the challenge.
   The case record lists the owned salons and their status from **this** lookup (then clear the
   scrollback), and gains « Oui — <date> — <accountId> — CODE confirmé dans le fil de T1 le <date>, depuis
   l’adresse enregistrée — en-tête : pass | non lisible ». Without it, no step 6.
6. **Run:**
   ```zsh
   read -r 'ID?Account id: '; read -r 'RS?Reason (support_no_sign_in | support_access_removed): '
   read -r 'CR?Case reference (MWP-XXXXXX): '
   if [[ -z $TOKEN || -z $ID || -z $EM || -z $RS || -z $CR ]]; then echo 'STOP: a value is empty'; else
     printf '%s' "$EM" | jq -Rs --arg r "$RS" --arg c "$CR" '{confirmEmail:., reason:$r, caseRef:$c}' \
       | adm -o /dev/stderr -w '%{http_code}\n' -X DELETE "$API/admin/provider-accounts/$ID/erase" \
         -H 'content-type: application/json' --data @-
   fi
   ```
   **204** → step 8. **401** → the token expired: step 2, then step 6 again. **409 `future_bookings`** →
   T3; on the owner's yes, the admin suspension (`provider.suspend`, no free-text reason) hides the salon
   from discovery, refuses new bookings and starts the website rebuild
   (`backend/lib/src/admin/admin_provider_service.dart:100-110`); run again after the last appointment,
   within 30 days of it. **409 `confirmation_mismatch`** → back to step 3. **403 `demo_account_locked`** →
   stop. **404** → gone already, or a wrong id: look up again. **400** → fix the value. **5xx** → step 7.
7. **After a 5xx,** run the lookup. Still there → retry later (the method converges). 404 → erased **with no
   audit row**: the case record says « effacé ; 5xx à HH:MM ; aucune ligne d’audit ». A retry cannot
   re-fire the website rebuild once the salons read `draft` (`:144-148`); step 8 (f) checks the page.
8. **Read back:** (a) the same DELETE → 404; (b) the lookup → 404; (c) each owned salon,
   `adm "$API/admin/providers/<id>" | jq '{slug, status, phoneNumber, address, whatsapp, latitude, longitude, depositRequired}'`
   (never unfiltered: it carries `recentAppointments`, 20 bookings with clients' names and phone numbers,
   `backend/lib/src/admin/admin_provider_service.dart:89-98`) → `draft`, phone and address empty, the pin
   null once B0.22 is live, deposit off, and the `slug` (f) needs: the salon row and its slug outlive the
   erase, and no other read in these steps gives it; (d)
   `adm "$API/admin/audit?action=provider_account.erase&pageSize=5"`
   → one row with that id, code and `caseRef`, no e-mail (none in step 7's case); (e) public
   `GET $API/providers/<id>` → 404; (f) after about 5 minutes, `https://myweli.com/<slug>`, with (c)'s
   `slug` → 404 (prebuilt pages, `revalidate = 300`, `web/app/[slug]/page.tsx:33`; still there after 10
   minutes → record it, check after the next build). Not observable here: the KYC objects, the Apple
   revoke, the device tokens. Then `unset TOKEN EM ID RS CR AE; unfunction adm` and clear the scrollback.
9. **Reply** with **T2**, a new message to the stored address, once (f) has passed for each owned salon,
   or with T2's « sous peu » sentence for a salon still served (§10.3). **Close** the case record. In the
   repo, only a dated count (« n effacements Pro sur demande au support le … »), no name, no address.

### 10.3 The replies — approved as written 2026-11-14 (decision 147)

French, vouvoiement. The sendable text (the `>` lines) already holds a non-breaking space (U+00A0,
invisible here) before `: ; ? !` and inside « », as the five pages write it: copy it from this file,
never retype it. `{…}` marks a value or a paragraph to fill; the notes under a template are for the owner
and are never sent. `{CASE}` may appear anywhere, `{CODE}` only in T1. The pin sentence holds once B0.22
is live and its O1 settled, which §9 precedes.

**T0 — Accusé de réception** (approved 2026-11-14, decision 147; to the sender's address)
> Objet : Votre demande de suppression de compte MyWeli Pro — réf. {CASE}
>
> Bonjour,
>
> Nous avons bien reçu votre demande de suppression de compte MyWeli Pro. Pour protéger les comptes de nos utilisateurs, nous vérifions d’abord qu’elle vient bien du titulaire du compte. Vous aurez une réponse de notre part au plus tard dans 14 jours. Rien n’est supprimé sans cette vérification.
>
> L’équipe MyWeli

**T1 — Confirmation, à l’adresse enregistrée sur le compte** (approved 2026-11-14, decision 147)
> Objet : Confirmez la suppression de votre compte MyWeli Pro — réf. {CASE}
>
> Bonjour,
>
> Nous avons reçu une demande de suppression du compte MyWeli Pro associé à cette adresse e-mail. Si elle vient de vous, répondez à ce message depuis cette adresse, en y recopiant le code de confirmation {CODE} et le mot CONFIRMER. Ce code n’est envoyé qu’à cette adresse. Ne le communiquez à personne d’autre, pas même à quelqu’un qui dirait travailler pour MyWeli : recopiez-le seulement dans votre réponse à ce message. Sans réponse de votre part dans les 14 jours, la demande est close et rien n’est supprimé.
>
> La suppression est définitive. Votre compte (votre nom, votre adresse e-mail, le lien avec votre compte Google ou Apple), vos sessions, votre place dans chaque équipe et les identifiants de vos appareils sont supprimés. Si vous êtes propriétaire d’un salon, il est retiré du public ; ses numéros de téléphone, WhatsApp et Mobile Money, son adresse et son point sur la carte sont effacés. Tant qu’un rendez-vous confirmé ou en attente est à venir dans ce salon, la suppression est refusée. Après votre confirmation, nous supprimons votre compte au plus tard sous 30 jours, si aucun rendez-vous n’est alors à venir dans un salon dont vous êtes propriétaire. Nos échanges au sujet de cette demande restent dans notre messagerie.
>
> {LIEN}
>
> Si vous n’avez rien demandé, ignorez ce message : votre compte reste tel quel.
>
> L’équipe MyWeli

*Notes, not sent.* `{LIEN}`, once S1 is live (check its date before sending):
> Ce qui est supprimé et ce qui est conservé est décrit ici : https://myweli.com/pro/suppression-compte

Before S1, only once B0.23 has merged:
> Ce qui est supprimé et ce qui est conservé est décrit ici : https://myweli.com/politique-confidentialite

Before both, that paragraph is left out.

**T2 — Suppression faite** (approved 2026-11-14, decision 147; to the stored address)
> Objet : Votre compte MyWeli Pro est supprimé — réf. {CASE}
>
> Bonjour,
>
> Comme vous l’avez demandé et confirmé, nous avons supprimé votre compte MyWeli Pro le {date}. Toutes vos sessions sont fermées, dans l’application comme sur le web. {SALON}
>
> Nos échanges au sujet de cette demande restent dans notre messagerie.
>
> {LIEN}
>
> Ce message clôt votre demande.
>
> L’équipe MyWeli

*Notes, not sent.* `{SALON}`, one sentence per owned salon, nothing for an account that owned none; once
step 8 (f) has passed for it:
> Le salon {nom du salon} est retiré du public.

while step 8 (f) still finds its page:
> Le salon {nom du salon} sera retiré du public sous peu.

`{LIEN}`, under T1's conditions, with T1's link; left out before both:
> Ce que nous conservons, et combien de temps, est décrit ici : {le même lien que T1}

**T3 — Refus : rendez-vous à venir** (approved 2026-11-14, decision 147; to the stored address)
> Objet : Votre demande de suppression — rendez-vous à venir — réf. {CASE}
>
> Bonjour,
>
> Nous n’avons pas pu supprimer votre compte : un rendez-vous confirmé ou en attente est encore à venir dans un salon dont vous êtes propriétaire. Nous ne voulons pas annuler d’office les réservations de vos clients. Terminez ou annulez ces rendez-vous, puis répondez à ce message : nous ferons alors la suppression.
>
> {SUSPENDRE}
>
> L’équipe MyWeli

*Notes, not sent.* `{SUSPENDRE}`, only if the person cannot open their agenda; otherwise left out:
> Nous pouvons suspendre le salon : il est retiré du public et ne reçoit plus de nouvelles réservations. Nous ferons ensuite la suppression après le dernier rendez-vous prévu, le {date}, au plus tard 30 jours après cette date. Répondez « SUSPENDRE » si vous le souhaitez.

**T4 — Vérification impossible** (approved 2026-11-14, decision 147; to the sender's address; never says whether an account exists)
> Objet : Votre demande de suppression de compte MyWeli Pro — réf. {CASE}
>
> Bonjour,
>
> Nous n’avons pas pu vérifier que cette demande vient du titulaire du compte. Pour protéger les comptes de nos utilisateurs, nous ne supprimons aucun compte sans cette vérification.
>
> {SUITE}
>
> L’équipe MyWeli

*Notes, not sent.* `{SUITE}` follows what the person wrote, never what the lookup found. (a) They say
their access to a salon's team was removed:
> Si vous retrouvez l’accès à l’adresse e-mail de votre compte, écrivez-nous depuis cette adresse : nous vous répondrons pour confirmer la suppression.

(b) Every other case:
> Si vous retrouvez l’accès à l’adresse e-mail de votre compte, vous pouvez le supprimer vous-même : sur myweli.com, connectez-vous à l’Espace Pro avec « Continuer avec e-mail » (nous envoyons un code à 6 chiffres à cette adresse), puis ouvrez Profil et choisissez « Supprimer mon compte ».

and, after (b), only once S1 is live (check its date before sending):
> Le détail : https://myweli.com/pro/suppression-compte

**T5 — Aucun compte Pro à cette adresse** (approved 2026-11-14, decision 147; to the sender's address; only when the sender's own address is the only thing given, §10.1)
> Objet : Votre demande de suppression de compte MyWeli Pro — réf. {CASE}
>
> Bonjour,
>
> Aucun compte MyWeli Pro n’est associé à l’adresse depuis laquelle vous nous écrivez. Si votre compte utilise une autre adresse, écrivez-nous depuis celle-ci. Si vous vous étiez connecté avec Apple en masquant votre adresse, votre compte utilise une adresse fournie par Apple, depuis laquelle vous ne pouvez pas nous écrire : connectez-vous avec Apple dans l’application MyWeli Pro ou sur myweli.com, puis supprimez votre compte depuis Profil ; si vous n’y parvenez pas, répondez à ce message en indiquant le nom du salon. Si vous avez un compte client MyWeli, il se supprime depuis une autre page : https://myweli.com/suppression-compte
>
> L’équipe MyWeli

## 11. Later, not here
- **B0.25 (P3):** the console screen; a step-up (the admin password in the erase body, under login's
  throttle, as `POST /admin/auth/password` asks for it, `admin_auth_repository.dart:50-61`) on both erase routes.
- **The owner, later:** how long a support thread is kept (the case record outlives it).

## 12. Definition of done
- [ ] §8's tests, each watched red once by its mutation; the full suite, format and analyze clean.
- [x] The contract, `schema.ts`, T83 and the T17/T53/T69 deltas, and the label in the same PR; `// Design:` links (on the branch, 2026-11-14).
- [ ] Merged outside the merge hold and any Apple review; deployed on the owner's yes; §9 step 4's read-back recorded.
- [ ] §10 and its French replies signed off after §9 step 4's read-back, then in `docs/DEPLOYMENT.md`, before
      B0.23 merges. *(2026-11-14: the replies are approved, decision 147; the procedure itself waits for the
      read-back.)*
- [x] demo-account-deletion-lock.md §6.3 (the row on other deleting routes) and §6.4 updated in the same PR (§9 step 2; on the branch, 2026-11-14).
- [ ] Feature branch and PR; no Claude attribution; one roadmap entry file.

## Review log

**2026-11-14, a review of this branch (19 findings, 11 of them on this spec), each checked in the code at
`d19655bd` before folding; none rejected.** The proof now needs the reply's `From:` to be the stored
address and the DMARC or compauth pass to be for that address's domain, as the R1 draft had it, with
`none`, `softfail` and `bestguesspass` escalated (§10.1); the shared salon mailbox is a named residual
(T83). The sender gets the same reply on the same schedule whatever the lookup finds once another address or a
salon is named, so no reply tells whether an account exists (§10.1, step 3). A body that is not an object,
or a field of the wrong type, is `invalid_body`, as BACKEND.md §2 says (§3, test 6). Test 11 pins the
service's one `deleteAccount(` call to the service field. Every salon-name and salon read is filtered with
`jq`, and a requester who is not the owner the validation view shows is escalated (step 3, step 8). The
yes rests on a fresh sign-in and lookup; 401 has its arm; `CASE` and `CODE` come from a generator; the
password reaches `jq` through a pipe (steps 2, 5, 6). The replies: T3 says the suspended salon leaves
public view; T1 and T2 say the thread stays; T2's salon sentence waits for step 8 (f); T1's policy link
waits for B0.23; T1's 30 days hold only with no appointment ahead, T3's run from the last one, and T0
promises a reply within 14 days; the non-breaking spaces are in the text, and the owner's notes are out of
it (§10.3). §9 step 2 and §12 update demo-account-deletion-lock.md.

## Build log

**2026-11-14, `feat/admin-pro-account-erase`** (stacked on `docs/pro-account-deletion-page`; not merged, not
deployed). Three commits: the code and its tests, the contract, the documents.

- **Built as specified:** both routes, the service, the wiring (one `AdminProviderAccountService`, given
  `providerAccountService`), the `Compte Pro effacé` label, the contract and `web/lib/api/schema.ts`
  (`npm run gen:api`, openapi-typescript 7.13.0 from the lockfile: additions only, `tsc --noEmit` green),
  T83 and the T17/T53/T69 deltas, demo-account-deletion-lock.md §6.3 and §6.4.
- **Tests, red first.** Against stubs (the service throwing, the routes answering 501), 54 of the then 57
  cases of `admin_provider_account_test.dart` were red; the 3 green were the two gate tests (the existing
  `/admin` gate already covers the paths — red only under the mutation) and « neither route names
  `deleteAccount` » (vacuous on a stub). Test 13 (the T69 inventory) went red when the service file gained
  its call; test 14 (`validation_labels_test.dart`) red until the label; the contract test (16) red, all 6,
  before the OpenAPI paths. Test 15 (Postgres) compiles and is skipped here: no `DATABASE_URL` on the Mac,
  so it runs in CI only.
- **Mutations, on committed code:** 19 on the code (§8's column, plus the closed reason, the one-`@` rule,
  the `forbidden` → 404 mapping, owned = every membership, an audited lookup) and 4 on the contract — 23,
  all red. One contract mutation survived its first run: `memberships` dropped from the view's `required`
  (the test read the property names only); the test now pins `required`, and the mutation is red.
- **Choices the spec left open, or where the build differs:**
  - the route checks JSON **types** (`optionalString`, so a wrong type is the outermost middleware's
    400 `invalid_body`); the service checks **values** (`invalid_input`) before any read — so no caller can
    skip them. Both happen before anything is acted on, as §3.1 says;
  - the lookup reads the named salons in **one** `byIds` call, not one per membership (§7; BACKEND.md §4);
  - a salon row that is gone reads `name: null, status: null` in the view (nullable in the contract);
  - `caseRef` is matched strictly, untrimmed (the procedure generates it);
  - a service code no arm maps is **thrown** (a reported 500), never a catch-all;
  - one test beyond §8: **10b**, the loser of two concurrent calls (`deleteAccount` answers `forbidden`)
    → 404 and no row (§4.3);
  - test 3 checked no map pin while B0.22 was not in. *(2026-11-14, after #791 merged: the fixture's salons carry a pin, and
    test 3 checks the owned salons lose it and the member-only salon keeps it.)*
  - **no runbook file**: the procedure stays in §10 and moves to `docs/DEPLOYMENT.md` only once approved
    (§9 step 5).
- **Not run here:** the full backend suite (targeted tests only on this branch: the new files, the T69
  inventory, every test that reads the contract, `test/http`, `test/security`; the full suite is CI's), the
  Postgres test, any deployed read-back (§9 step 4).

**Review, 2026-11-14 (7 findings, each checked in the code first; none rejected).**
- **The procedure kept the token and the address in process arguments.** `curl -H "authorization: Bearer
  $TOKEN"` and `jq --arg e "$EM"` put both where `ps -axww` shows them to every process of the same user.
  Seen on this Mac against a local `nc` with dummy values: the token in `curl`'s arguments, the address
  in `jq`'s. Now `adm` (step 2) sends the header from a builtin's process substitution, the address goes
  through a pipe, and the rule is in §6 and §10.1; the same check shows neither, and `nc` received the
  same request. The admin's own e-mail at sign-in still goes as `--arg e "$AE"`: it is not the person's
  address and not a secret, and it was not in the finding.
- **Step 8 (f) needed a slug no allowed read gave.** (c)'s filter now keeps `slug`. The admin detail is the
  salon's `data`, which carries it (`draftSalonDocument`, `providers_repository.dart:867`); the erase
  keeps the salon row and leaves its slug as it is.
- **Test 15 raced its neighbour on the shared CI database.** Run here for the first time, on a throwaway
  local Postgres 16 container. Committed, it passed alone. With `postgres_repositories_test.dart` at
  `-j 2` it failed 3 runs in 3, a 404 for the 204; the sibling's `TRUNCATE` placed in the window gave the
  same 404 every time. The other direction was worse: on an empty database, test 15's two salons made
  the sibling's `seedProvidersIfEmpty` skip the seed, and 35 of its 190 tests went red. Now the file makes
  its own database and drops it (the `migration_concurrency_test.dart` precedent): 3 concurrent runs in 3
  green (191), the sibling green after it, the shared database left with nothing of it, and the same
  `TRUNCATE`, sent to the shared database inside the window, no longer reaches it.
- **Test 15 left two salons behind.** Fixed by the same change: the dropped database is its cleanup.
- **No expired or forged admin token was tested.** Test 2 gains both, per route (401 `unauthorized`,
  nothing written), plus a control: the same hand-built token, unexpired, passes. Red under « the expiry
  not checked » (2 of 4) and « the signature not checked » (4 of 4).
- **The lookup held a second copy of the owned rule.** Now `ProviderAccountService.ownedSalonIds`, one
  static method that `deleteAccount` and the lookup both call. Test 12 gains a salon linked by the
  scalar field alone: red when the lookup dropped the scalar link, before the change, and red when the
  shared method drops it, after.
- **The contract's erase body claimed `additionalProperties: false`;** the route ignores an unknown key, as
  the other routes do. The schema is now open and says so; the contract test pins that, red against the
  closed schema; test 6 pins that a free-text extra key answers 204 and lands nowhere. `schema.ts`
  regenerated: the description only.
