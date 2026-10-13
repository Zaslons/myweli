# The shared App Review demo account cannot delete itself

| | |
|---|---|
| **Status** | **Approved** (owner, 2026-10-13: the recommendation of [app-store-forms.md](app-store-forms.md) §13.1 point 3 — a server-side refusal for the demo identity) — **built 2026-10-13** on `fix/demo-account-deletion-lock`. **Not merged, not deployed.** What was run and what was not: §9.1. The amended review notes are valid only once production serves the lock (§10). |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-10-13 |
| **PRD ref / phase** | Store submission (App Review 5.1.1(v) — account deletion; guideline 2.1 — a working demo account) · V1 |
| **ROADMAP entry** | [2026-10-13-demo-account-deletion-lock](../roadmap/entries/2026-10-13-demo-account-deletion-lock.md) |
| **Related** | [backend-demo-review-account.md](backend-demo-review-account.md) (the demo account, threat T69) · [pro-account-deletion-export.md](pro-account-deletion-export.md) (the deletion flow, threat T53) · [app-store-forms.md](app-store-forms.md) §8, §14 · [play-store-forms.md](play-store-forms.md) §2 |
| **Skills checked** | myweli-backend-guardrails · myweli-dev-guardrails · myweli-web-guardrails · myweli-verification-guardrails |

## 1. Goal & scope

**Goal.** The demo identity `revue@myweli.test` is printed in the App Store
and Play review notes. The Pro app offers account deletion (Profil >
« Supprimer mon compte », type `SUPPRIMER` — App Review 5.1.1(v) requires it).
A reviewer who tries that feature on the shared account must get a clear
refusal, on every day of the week, and the account must survive.

**Why it matters.** Nothing recreates the identity (§2). One deletion ends
every later review: the next sign-in with the credentials in the notes
answers `provider_not_found`, which App Review reads as guideline 2.1 (« we
were unable to sign in with the demo account »).

**In scope.**

- Server: one refusal in `ProviderAccountService.deleteAccount`, mapped by
  `DELETE /me/provider` to 403 `demo_account_locked`.
- Pro app: the Profil screen shows « Compte de démonstration — cette action
  est désactivée. » on that code. The entry stays visible and enabled.
- Web Pro dashboard: the same sentence in « Compte ».
- Contract, threat model (T69, T53), the demo and deletion specs, the review
  notes of both stores.

**Out of scope, with reasons.**

- **Hiding or disabling « Supprimer mon compte » for the demo account.**
  Decided against: the reviewer must see that deletion exists. The refusal
  comes after the `SUPPRIMER` confirmation.
- **The weekly reset recreating a lost identity.** Still not built (§12 Q1).
  This slice removes the only product path that loses it.
- **The consumer app.** Not concerned (§7.3).
- **An admin override.** There is none, on purpose (§6.4).

**Fit.** `routes → services → repositories`: the rule lives in the service,
the route only maps a code to a status. No new endpoint, no schema change,
no migration, no new configuration.

## 2. What is wrong today (verified 2026-10-13, commit `ec96ae25`)

Read in the code, then observed by running the new tests against the
unchanged code.

**The lines that let the demo identity be deleted.**

- `backend/lib/src/provider_account_service.dart:47-118`, `deleteAccount`.
  The account is loaded at `:48`; an unknown account is refused at `:49`
  (`forbidden`). The only other refusal is `:69` (`future_bookings`). **No
  line reads the account's e-mail.** From `:79` the method unpublishes every
  owned salon, erases the KYC objects (`:94-103`), deletes the device tokens
  and notifications (`:109-110`), revokes the memberships (`:114`) and
  deletes the identity with all its sessions (`:116`).
- `backend/routes/me/provider/index.dart:134-144`, `_delete`. It maps
  `future_bookings` to 409 and everything else to 403 `forbidden`. The checks
  before it (`:37-47`) are « a token » and « role `provider` ».
- `backend/lib/src/demo/demo_reset_service.dart:193-218`. The weekly reset
  regenerates four bookings at −3, −1, **+1** and **+2** days. Only the last
  two can trip the agenda gate, and only until they are in the past: from a
  reset at time T, until T + 2 days at 16:00 UTC. That is about two and a
  half days out of seven.
- And the gate is not a lock even on those days. Its refusal tells the user
  what to do (« Terminez ou annulez vos rendez-vous à venir avant de
  supprimer votre compte. »), and the demo account can complete or cancel its
  own two bookings from the agenda.

**Observed, before the fix** (`dart test test/provider_account_service_test.dart
test/me_provider_test.dart`, the new tests on the unchanged service):

| test | expected | got |
|---|---|---|
| service — the demo identity is refused | `ok: false` | `ok: true` — the account was deleted |
| service — same, with an upcoming booking | `demo_account_locked` | `future_bookings` |
| handler — `DELETE /me/provider` as the demo identity | 403 | **204** |
| handler — same, with an upcoming booking | 403 | 409 |

**Nothing recreates the identity.** Observed with a throw-away probe on the
in-memory repositories (not committed): after the three writes a deletion
makes, the salon's owner row reads `role=owner status=revoked
email=revue@myweli.test`; the reset at +7 days **runs** (`ran=true`, four
bookings regenerated on a salon nobody can open); `accountByEmail` answers
null; a new capture answers `demo_account_missing`. The reset's safety check
(`_demoOwned`) reads the owner row whatever its status, and both
`listForProvider` implementations return rows of every status
(`membership_repository.dart:195-210`,
`db/postgres_membership_repository.dart:51-60`) — so production behaves the
same. *The Postgres half is read in the SQL, not run.*

This also corrects [backend-demo-review-account.md](backend-demo-review-account.md)
§9, which said the reset « probably keeps restoring an orphaned salon
(INFERRED) »: it does.

## 3. API & contract

No new endpoint. `DELETE /me/provider` gains one answer.

| caller | status | body |
|---|---|---|
| no token | 401 | `{ "error": "unauthorized" }` |
| a token whose role is not `provider` | 403 | `{ "error": "forbidden" }` |
| a provider token whose account no longer exists | 403 | `{ "error": "forbidden" }` |
| **the demo identity** | **403** | **`{ "error": "demo_account_locked" }`** |
| any other account with upcoming pending/confirmed bookings in a salon it owns | 409 | `{ "error": "future_bookings" }` |
| any other account | 204 | — |
| any verb other than `GET` / `DELETE` | 405 | `{ "error": "method_not_allowed" }` |

Only the bold row is new. The demo refusal is evaluated **right after the
account is loaded and before the agenda gate**, like the other demo locks:
the answer is the same seven days out of seven, and nothing after that point
is read or written.

`docs/api/openapi.yaml`: the operation's description gains the refusal, and
its 403 stops being a bare `$ref` to the shared `Forbidden` (which names no
code) — it lists `forbidden` and `demo_account_locked`. The response schema
is the existing `Error`. `web/lib/api/schema.ts` is regenerated with
`npm run gen:api`.

Clients: `ProServiceInterface.deleteProviderAccount()` (app) and
`deleteProAccount()` (web) already return the machine code; neither changes
shape.

## 4. Data model

Nothing. No table, no column, no migration, no flag. The identity itself is
the marker (`kDemoProviderEmail`, a compile-time constant in the RFC 2606
`.test` TLD), so there is no flag an operator can forget to set or set on a
real account.

## 5. Architecture & patterns

- **In the service, not the route** — the reason every other demo lock gives:
  no future caller can route around it. `ProviderAccountService.deleteAccount`
  is the only caller of `ProviderAuthRepository.deleteAccount` (the identity
  delete); a test pins that (§9).
- **Keyed on the calling account's own e-mail** — `isDemoIdentity(account.email
  ?? '')`. The caller is the subject here, as for salon creation
  (`SalonDirectoryService.createSalon`). Publish, invitations and the offer
  change key on the *salon's* owner row instead, because their subject is a
  salon.
- **The same helper as every other lock**: trimmed, case-insensitive, exact
  match — never a suffix test. An account with no e-mail is not the demo.
- **Independent of the sign-in seam.** The lock reads a constant, not
  `DEMO_PROVIDER_CODE`. With the seam switched off nobody can sign in as the
  demo account, and a session that already exists still gets the 403.

## 6. Security & authz

### 6.1 Who can call it

Unchanged: a provider access token, self-scoped (the account comes from the
token, never from the client). Deny by default.

### 6.2 Threat-model delta

- **T69** (store-review demo account). The account is an ordinary provider
  account with **five** capabilities subtracted, none added. The fifth is
  deleting itself. The four others, read in the code on 2026-10-13: publish
  (`SalonProvisioningService.publish`), team invitation (`TeamService.invite`),
  offer choice or switch (`SalonSubscriptionService.chooseOffer`), salon
  creation (`SalonDirectoryService.createSalon`). All five answer 403
  `demo_account_locked` from the service.
- **T53** (provider account deletion). One more refusal, evaluated first.
  Everything else about the deletion is unchanged.

Residual, stated: the lock protects the identity from the product. It does
not protect it from an operator working in the database, and the reset still
does not recreate it (§12 Q1).

### 6.3 Bypasses checked (2026-10-13, by reading the code)

| question | finding |
|---|---|
| Can the demo account's e-mail be changed, which would make `isDemoIdentity` false? | **No.** `ProviderAuthRepository` has no verb that writes `email` after creation. Every `UPDATE provider_users` in `backend/lib` sets `provider_id`, `google_sub` / `apple_sub` with `email_verified`, `email_verified`, `kyc_docs` or `verification_status` — never `email` (`db/postgres_provider_auth_repository.dart:21, 165, 215, 532, 577`). No route patches a provider account. |
| Can an Apple or Google identity be linked to it, or merged with it? | Linking exists (`loginWithSocial`): it attaches a `sub` to the account whose e-mail the identity provider reports as **verified**. It never rewrites `email`, so the lock would hold even then. And no provider can verify `revue@myweli.test` — a `.test` address cannot receive the confirmation mail. |
| Is there another route that deletes or anonymises a provider account? | **No.** `ProviderAccountService.deleteAccount` is the only caller of `ProviderAuthRepository.deleteAccount`, and `DELETE /me/provider` is its only caller. The admin console has no provider-account deletion (it can suspend and restore a *salon*). |
| Consumer `DELETE /me` with a provider token? | 403 `forbidden` — the route requires role `user` (`routes/me/index.dart`). |
| Admin `DELETE /admin/users/{id}/erase` with a provider account id? | 404 — `UserErasureService` loads a consumer `users` row first and stops when there is none. |
| Data-export or erasure endpoints? | The Pro export is assembled client-side from scoped reads; there is no server erasure endpoint other than the two above. |
| Can the demo owner drop its own owner membership? | No — 403 `owner_protected` (`TeamService`). |
| What does the weekly reset do if the identity is missing? | It keeps resetting the orphaned salon and never recreates the identity (§2). A capture answers `demo_account_missing`. |

Nothing in this class was found that needed a fix beyond the lock itself.

### 6.4 What an admin can still do

The admin console never deleted provider accounts, and still does not. It
can suspend or restore the demo salon (audited), record a payment, review its
KYC, and capture the demo snapshot. To take the demo account out of service
on purpose there are two ways, both untouched by this lock: unset
`DEMO_PROVIDER_CODE` (nobody can sign in; reversible — the designed off
switch), or a deliberate database operation by the owner. There is no
« force » parameter on the route: an override reachable with the public
credential would be the same hole.

### 6.5 Privacy

The lock makes one account undeletable through the API. That account is not
a person: the address cannot exist. Account deletion (AUTH-004, App Review
5.1.1(v)) still works for every real account, and the review notes say how
to test it.

## 7. Behaviour on each surface

### 7.1 Pro app (iPhone and Android, no platform branch)

1. Profil > « Supprimer mon compte ». **Visible and enabled for the demo
   account**, like for anyone.
2. The dialog « Supprimer votre compte ? », with the type-to-confirm field.
   The user types `SUPPRIMER` and taps « Supprimer définitivement ».
3. The server answers 403 `demo_account_locked`. The app shows an **error
   snackbar** on the Profil screen — the pattern the screen already uses for
   `future_bookings` ([SYSTEM.md](SYSTEM.md) §15: the dialog is closed by
   then, so the feedback belongs to the screen; a snackbar is a live region,
   so VoiceOver and TalkBack read it):

   > Compte de démonstration — cette action est désactivée.

   The sentence is the existing constant `demoAccountLockedMessage`
   (`mobile/lib/core/utils/team_error_messages.dart`) — never retyped.
4. The user **stays signed in**, on Profil. Nothing local is cleared. A
   second attempt gets the same answer.

The screen maps the **code**, not the service's message — as it does for
`future_bookings`.

**No new build is needed for the sentence to appear.** `ApiProService` has
mapped `demo_account_locked` to this sentence for every call since the
companion path (2026-10-05), and the Profil screen shows the service's
message when it does not know the code. Build 577 was built from `d2fb12c6`;
`mobile/lib` is identical at `ec96ae25`. A test drives the unchanged screen
through the real `ApiProService` over a stubbed HTTP 403 (§9). *Source-level
evidence — not observed on a device.*

### 7.2 Web Pro dashboard (`/pro/profil`, « Compte »)

The demo credential signs in on the web too. Same flow: « Supprimer mon
compte » → type `SUPPRIMER` → « Supprimer définitivement » → the same
sentence in the section's existing `role="alert"` paragraph. The page stays,
the session cookies stay (the BFF clears them only on 204).

The sentence lives once on the web, in the shared code → copy table
(`web/lib/pro/team.ts`), and a test compares it to the app's constant.
Because the table gains the code, the two web surfaces that already render
through it — the invite dialog and « Ajouter un salon » — now say the demo
sentence too, instead of « Une erreur est survenue. Réessayez. ». The web's
publish card and offer page have their own mappings and are unchanged (§12
Q3).

### 7.3 Consumer app and public site — not concerned

`DELETE /me/provider` is a Pro route: a consumer token gets 403 `forbidden`
before any account is read. The consumer deletion is `DELETE /me`, which
erases a row of the `users` table; the demo identity is a row of
`provider_users`, and there is no consumer demo account (the consumer app is
browsable signed out, [backend-demo-review-account.md](backend-demo-review-account.md)
§1). `AuthProvider.deleteAccount` and `ApiAuthService.deleteAccount` (the
consumer path) are untouched.

### 7.4 Admin console

No surface changes (§6.4).

## 8. States & edge cases

| case | what happens |
|---|---|
| demo account, upcoming bookings in the agenda | 403 `demo_account_locked` — not the 409 |
| demo account, empty agenda | 403 `demo_account_locked` |
| the stored address in another case, or with spaces around it | still the demo identity (`isDemoIdentity` trims and lowercases) |
| a near-miss address (`revue@myweli.test.fr`, `xrevue@…`, `revue+1@…`) | not the demo identity — deleted like any account |
| an account with no e-mail | deleted like any account |
| a real account with upcoming bookings | 409 `future_bookings`, the existing sentence |
| a team member deleting their own account | unchanged |
| network failure | the existing « Connexion au serveur impossible » |
| `DEMO_PROVIDER_CODE` unset | nobody can sign in as the demo account; an existing session still gets the 403 |
| an app build older than the companion path (before 2026-10-05) | would show « Une erreur est survenue. » — no such build is in review |
| the demo account retries | the same answer, nothing accumulates (no write on that path) |

## 9. Testing plan

Each new guard is watched red by a mutation on committed work; the list is
in the commit messages and in the roadmap entry.

- **Service** (`backend/test/provider_account_service_test.dart`): the demo
  identity is refused and nothing is mutated — the account, its KYC rows and
  objects, the salon status, the rebuild notifier, the owner membership, the
  device token, the notification, the session; **the same rows under another
  address are erased** (the control: the address is the only difference);
  the refusal holds with and without upcoming bookings; case and whitespace
  variants; near-miss addresses still delete; an account with no e-mail
  still deletes; an unknown account is still `forbidden`.
- **Handler** (`backend/test/me_provider_test.dart`): 403 and the exact
  envelope for the demo identity, with and without upcoming bookings; 204 for
  another account; 409 `future_bookings` unchanged; 401 without a token; 403
  `forbidden` for a consumer token and for a vanished account; 405 for
  `POST`, `PUT`, `PATCH`.
- **Contract** (`backend/test/contract/demo_account_deletion_lock_contract_test.dart`):
  the document names `demo_account_locked` on the operation and on its 403.
- **Inventory** (`backend/test/demo/demo_locks_inventory_test.dart`): the
  services that answer `demo_account_locked` are exactly the five listed in
  the header of `demo_seam.dart`, and the identity delete has no caller
  outside `ProviderAccountService`.
- **App** (`mobile/test/widget/pro_profile_delete_account_test.dart`, on both
  platforms): the sentence on that code even when the service sends another
  message; still signed in, still on Profil, the entry still there; the
  `future_bookings` sentence, a generic failure and a success (sign-out, the
  login screen) as controls; and the unchanged screen through the real
  `ApiProService` over HTTP 403. `mobile/test/unit/api_pro_service_test.dart`:
  the service maps the code.
- **Web** (`web/tests/compte-danger-section.test.tsx`): the sentence on that
  code, announced, owner and member variants; controls for `future_bookings`,
  three generic failures and a success; and the BFF route — the refusal
  passed through with no `Set-Cookie`, the cookies cleared on 204 as the
  control. `web/tests/pro-team.test.ts`: the shared table and its parity
  with the app's constant. `web/tests/equipe-invite.test.tsx` and
  `web/tests/add-salon.test.tsx`: the two surfaces that render through the
  table now say the demo sentence.
- **Review notes** (`mobile/test/infra/app_review_notes_test.dart`): the
  block pasted into App Store Connect stays under 4,000 bytes, its stated
  counts are the real ones, and it quotes the sentence the app shows.

### 9.1 What was run on 2026-10-13, and what was not

**Run, and green** — targeted tests only (the machine is shared):

- backend: the four files above, `test/demo/`, `test/contract/`, and the
  `/me` neighbours; `dart analyze --fatal-infos --fatal-warnings` 0; format
  clean.
- mobile: the Profil deletion screen test (six cases on two platforms), the
  API service, the error table, the Profil role test, the review-notes
  guard; `flutter analyze` 0; format clean.
- web: the section and BFF test, the shared table, the member Profil, the
  invite dialog, « Ajouter un salon »; `tsc --noEmit` 0; `next lint` clean
  on the touched files; `schema.ts` regenerated by `npm run gen:api`.

**Watched red** — 51 mutations, each on committed work, then restored; the
list is in the five commit messages. Backend 24 (among them: the lock
removed — 9 tests red; moved after the agenda gate — exactly the two « with
upcoming bookings » tests; every account refused — 21 red; and seven single
stray writes placed before the lock, one per « nothing is mutated »
assertion). Mobile 8. Web 11. Review notes 8, one of which replays the
2026-10-11 defect (the block edited, its stated weight not).

Before the fix, on the unchanged code: the service and handler tests of §2
red; the Profil test keyed on the code red on both platforms; and the
Profil test through the real `ApiProService` **green** — the evidence for
« no new build is needed » (§7.1).

One assertion has no mutation of its own: « the session is alive ». Its
control shows the same refresh failing after a real deletion.

**Not run** — and nothing here claims them: the full backend, mobile and web
suites; the Postgres repositories (Docker); Playwright and Lighthouse; the
goldens (no rendering changes: the snackbar and the web alert already exist,
only their text differs for one code). CI runs them on the pull request.

**Not observed** — the sentence on a real iPhone; the lock on a deployed
server (nothing is deployed); the reset's behaviour on Postgres once the
identity is gone (read in the SQL, run on the in-memory repositories only).

## 10. Rollout

1. **Merge** the pull request once CI is green (the owner merges).
2. **The image is built on merge. Staging is retired today**
   (`infra/gcp/staging.state` reads `absent`): a merge builds and pushes the
   image and prints the tag to promote, and deploys nothing. There is no
   staging rehearsal of this change.
3. **Production is a manual dispatch** of « Deploy — backend (Cloud Run) »
   with the typed confirmation. It needs the owner's explicit go; a green CI
   is not one.
4. **Verify production without risking the account** (§10.1).
5. **Only then** do the amended review notes go to App Store Connect and the
   Play Console ([app-store-forms.md](app-store-forms.md) §8,
   [play-store-forms.md](play-store-forms.md) §2). Until production serves
   the guard, the previous notes stay: the amended ones tell the reviewer the
   demo account cannot be deleted, which is false until step 3.

No app release is required (§7.1). No flag, no configuration, no migration,
nothing to roll back but the image.

### 10.1 Verifying production — the oracle that cannot destroy the account

**Do not press « Supprimer définitivement » on the demo account to see what
happens.** If the deploy did not take, that one tap deletes it.

The lock answers **before** the agenda gate, and the old code answers
`future_bookings` **without deleting anything** when an upcoming booking
exists. So, with an upcoming booking in place, both answers are safe and
they differ:

1. Confirm the deploy: the workflow run succeeded for `production`, and the
   revision serving 100 % of the traffic is the image built from the merge
   commit.
2. The owner signs in as the demo account on the TestFlight build. Nobody
   else signs in as the demo account for this check.
3. In the agenda, create a manual booking for **tomorrow** (« Nouveau
   rendez-vous »). A manual booking is `confirmed`. Check that it is on the
   agenda.
4. Within the same minute: Profil > « Supprimer mon compte » > `SUPPRIMER` >
   « Supprimer définitivement ».
   - « Compte de démonstration — cette action est désactivée. » → **the
     guard is live.**
   - « Terminez ou annulez vos rendez-vous à venir avant de supprimer votre
     compte. » → **the old code is still serving.** Nothing was deleted. Stop
     and look at the deploy.
5. Cancel the test booking, or leave it: the next weekly reset wipes the
   agenda.
6. The control, on a **fresh** account (Sign in with Apple, « Créer un
   compte »): delete it end to end. It must sign out to the login screen —
   deletion still works for everyone else, which is what the reviewer is
   asked to test.

Residual risk of step 4: the credential is public, so someone else could
cancel the booking between steps 3 and 4. It matters only if the deploy also
failed. Hence « within the same minute », and step 1 first.

## 11. Definition of done

- [x] `dart format` clean · `dart analyze --fatal-infos --fatal-warnings` 0 ·
      `flutter analyze` 0 · web typecheck and lint clean (2026-10-13).
- [ ] The full suites green — **on CI, not run here**.
- [x] Every new guard watched red (§9.1).
- [x] Contract, threat model (T69, T53), both demo/deletion specs, both
      stores' notes and the roadmap entry on the same branch.
- [x] Spec cross-linked from the service, the route, the seam, the screen,
      the service interface, the web section, the BFF route, the web client
      and the contract.
- [ ] Pull request opened and merged — **the owner**.
- [ ] Deployed to production with the owner's go, verified per §10.1 — **not
      done from this branch**.
- [ ] Amended review notes in App Store Connect and the Play Console —
      **owner, after the deploy**.

## 12. Open questions

1. **A lost identity is still not recreated.** The lock closes the product
   path. An out-of-band loss (a database operation, a restore) still leaves
   a salon the reset keeps restoring and nobody can open. Recovery is manual:
   register again with the fixed code, curate, recapture
   ([backend-demo-review-account.md](backend-demo-review-account.md) §9).
   Should the reset re-provision the identity? Not built; not needed for the
   submission.
2. **The reset does not restore the account row.** KYC documents a reviewer
   uploads from Profil > « Vérification », and the resulting verification
   status, survive every reset. Different class (junk that persists, not a
   lost account). Recorded, not changed.
3. **Two web surfaces still show a generic error on a demo refusal**: the
   publish card (« La mise en ligne a échoué. Réessayez. »,
   `GoLiveCard.tsx`) and the offer page (`AbonnementClient.tsx`). The app
   shows the demo sentence on both. Small, and outside this slice.
4. **A recurring production check of the lock** would need the demo code in
   CI. Not proposed: the code would have to live in a second place.
