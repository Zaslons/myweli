# Purge a deleted owner's salon after a set time (B0.24)

| | |
|---|---|
| **Module** | backend — a salon purge on the daily maintenance cron (`POST /internal/cron/maintenance`), a stamp in `ProviderAccountService.deleteAccount`, migration `0046`; then three text PRs (web, privacy policy, Play's Data safety record) |
| **Status** | **Approved 2026-11-20: the owner answered Q1–Q6 « Approve as recommended », decisions 153–158 (§11).** Nothing built, nothing migrated, nothing deployed; each next step waits for the owner's yes (§10, §12). *2026-11-20: production counted read-only (§6.6 step 1): 3 salons with no owner, no member row and no shared file.* An independent review against the code found 7 problems in the first draft, all folded in (§13). Decision 138 filed this item; android-play-release step 10 needs it **decided** (this spec answered), not built |
| **Owner** | the project owner: the answers, the merge, every production read, the deploy, and the switch from rehearsals to real purges, each on the owner's yes |
| **Last updated** | 2026-11-20 |
| **PRD ref / phase** | FR-AUTH-005 [V1] (`docs/PRD.md:344`, account deletion) · V1 · gates android-play-release step 10 (decided, not built) |
| **BACKLOG item** | B0.24 · decision 138 (and 137, 139, 140, 142, 143, 144 for what the texts say today) · touches B0.27 (photos) and B0.28 (backups) |
| **ROADMAP entry** | [2026-11-20-deleted-owner-salon-purge-spec.md](../roadmap/entries/2026-11-20-deleted-owner-salon-purge-spec.md) |
| **Skills checked** | myweli-dev-guardrails · myweli-backend-guardrails · myweli-verification-guardrails (all invoked for this spec) · [BACKEND.md](../BACKEND.md) §1–§4, §7 |
| **Related** | [pro-account-deletion-export.md](pro-account-deletion-export.md) (the deletion) · [pro-deletion-erase-gaps.md](pro-deletion-erase-gaps.md) (B0.22: the pin, O1's production count) · [admin-pro-account-erase.md](admin-pro-account-erase.md) (B0.25: the support erase) · [web-pro-account-deletion.md](web-pro-account-deletion.md) (`/pro/suppression-compte`) · [web-privacy-pro-deletion.md](web-privacy-pro-deletion.md) (B0.23: « Conservation ») · [play-store-forms.md](play-store-forms.md) §4 (Data safety) · [infra-cron-maintenance.md](infra-cron-maintenance.md) · [backend-provider-deletion-member-fk.md](backend-provider-deletion-member-fk.md) · [pro-rejoin-gate.md](pro-rejoin-gate.md) |

OBSERVED = read in the code at `main` `be2c44b3` (this branch adds no code). INFERRED = reasoned from
it. UNVERIFIED = not readable from here (production, R2, a console).

## 1. Goal & scope

**Goal.** Today a deleted owner's salon, and everything under it, is hidden and kept with no limit, and
`/pro/suppression-compte` says so (`web/app/pro/suppression-compte/page.tsx:232-241`). Decision 138
answered « Say it, decide later » and filed this item before production access. This spec sets **how
long**, **what goes**, **what the members who keep the salon lose**, and **how the purge runs safely on
real production data**.

**In scope:**
- the inventory of what a deleted owner's salon holds (§2), each line read in the migrations and the code;
- the duration (§3);
- what the purge removes, changes and leaves (§4), and who loses what (§5);
- the mechanism, its idempotency and its guard against a live salon (§6);
- the texts that change once it runs (§10).

**Out of scope:**
- the KYC objects of the deleted owner: erased at the deletion itself, best effort (`provider_account_service.dart:187-200`); keyed by the account, not the salon;
- B0.27, the photos deleted **at** the deletion: it stays filed; this purge bounds how long they live (§4.4);
- B0.28, the backups: the texts keep saying nothing about them (decision 140);
- the e-mails in the admin mailbox (place changes, decision 133): out of any code's reach (§4.5);
- a person's traces in **other, live** salons (a collaborator card, an invitation): unchanged, as the page says;
- an ownership transfer: none exists (§2.5).

**Architecture.** Backend only, in the existing layers:
- a `SalonPurgeService`, with no SQL and no `dart_frog`;
- behind it, a `SalonPurgeRepository` interface, with a Postgres twin and an in-memory twin;
- a fifth task on `MaintenanceTick`;
- one new `StorageService` method, to list a prefix.

No new route, and no client change.

## 2. What exists today (OBSERVED)

### 2.1 What an owner's deletion does to each owned salon

`ProviderAccountService.deleteAccount` (`backend/lib/src/provider_account_service.dart:111-254`):
- refuses the demo account (`:132-134`) and any owned salon with a booking ahead (`:142-152`);
- sets each owned salon to `draft` (`:165`);
- merges `_erasedContact` into it: phone, address, WhatsApp, Mobile Money number and operator, deposit off, the pin (`:85-94`, `:170`);
- deletes a pending validation and clears the admin's notes (`:175-176`), and forgets the place notice (`:180`);
- erases the KYC objects (`:191-200`);
- deletes the owner's devices, feed and idempotency keys (`:206-208`), revokes Apple (`:214`);
- deletes the identity (`:216`), so 0038's cascade removes the owner's membership rows (`:232`, `migrations.dart:1075-1080`);
- re-hides any salon that came back (`:243-252`).

**It records no date and no owner.** Afterwards, the only sign that a salon lost its owner is an
absence: no `provider_users.provider_id` link to it and no active `owner` row in `provider_members`. The
same two-part definition is `ownedSalonIds` (`:102-109`). **No table says when the owner left.** The
support erase writes `provider_account.erase` in `audit_log` (`admin/admin_provider_account_service.dart:165-174`);
a self-service deletion writes nothing.

### 2.2 Every table under a salon

Every table that names a salon, read in `backend/lib/src/db/migrations.dart` (0001 to 0045, the last
migration). « On delete » is what a `DELETE FROM providers` would do to it.

| Table (migration, line) | Linked to the salon by | On delete of the salon | What it holds |
|---|---|---|---|
| `providers` (0001 `:50-59`; 0012 `:351-353`; 0021 `:497`; 0044 `:1216`) | `id` | — | name, description, category, commune, rating, slug, status, `featured`, `suspended_from`; `data` jsonb (stored as a jsonb **string**, pro-deletion-erase-gaps §9): the gallery `imageUrls`, `beforeAfters`, `artists` (names, `imageUrl`), `logoUrl`, city, `areaId`, market facts |
| `provider_users.provider_id` (0003 `:111`) | the owner's scalar link, no FK | nothing | gone with the owner's account; a member's account never carries it |
| `provider_services` (0005 `:154-166`) | FK | cascade | the catalogue |
| `provider_availability`, `provider_working_hours`, `provider_breaks`, `provider_blocked_dates` (0005 `:171-203`) | FK | cascade | hours, breaks, closed days |
| `reviews` (0007 `:227-241`; 0011 `:326-327`) | FK | cascade | each client's name (`user_name`), text, rating, artist name, `photo_urls` |
| `review_reports` (0011 `:330-340`; 0041 `:1132-1133`) | FK to `reviews` | cascade | reports on those reviews, by clients or by the salon itself (`reporter_kind = 'salon'`) |
| `salon_validations`, `salon_validation_events` (0044 `:1183-1210`) | FK | cascade | the validation state and history (the notes already cleared at the deletion) |
| `salon_place_notices` (0045 `:1234-1241`) | FK | cascade | already deleted at the deletion (`:180`) |
| `provider_members` (0027 `:711-726`) | FK, **no ON DELETE** | **refuses** (23503) while a row exists | the team: each member's e-mail, role, artist link, `invited_by`, dates; invitations to third parties' addresses |
| `provider_subscriptions`, `subscription_notices` (0028 `:749-766`) | FK, **no ON DELETE** | **refuses** | the offer, trial and paid-until dates |
| `appointments` (0002 `:69-86`; 0009, 0025, 0026) | `provider_id`, no FK | nothing | every booking: the client's `user_id`, or `'manual'` with `client_name`, `client_phone`; `notes`; `deposit_screenshot_url`; artist, services, prices, dates |
| `appointment_reminders` (0016 `:420-425`) | FK to `appointments` | cascade with the booking | reminder log |
| `disputes` (0014 `:368-378`) | FK to `appointments` | cascade with the booking | MyWeli's written `reason` and `resolution` on a booking |
| `salon_clients` (0024 `:586-596`) | `provider_id`, no FK | nothing | the client file: name, phone, tags, last visit |
| `salon_client_notes` (0024 `:604-611`) | FK to `salon_clients` | cascade with the card | the team's notes on a client, with the author's account id |
| `provider_audit_log` (0024 `:616-624`) | `provider_id`, no FK | nothing | the team's actions: actor account id, action, target, `meta`, with the **Clients search text** in `meta.query` (`clients/clients_service.dart:96-104`) |
| `favorites` (0006 `:212-217`) | `provider_id`, no FK | nothing | clients who saved the salon |
| `demo_snapshot` (0036 `:1024-1029`) | `provider_id`, no FK | nothing | the demo salon only, never a deleted owner's |

**Three tables refuse** the salon's delete: `provider_members`, `provider_subscriptions` and
`subscription_notices`. No other foreign key references `providers(id)`.

`provider_audit_log`'s actions, all written by the salon's own team:
- `clients.list` (with `query`, `tag` and `page`), `clients.view`, `client.phone_changed` (`clients_service.dart:99`, `:181`, `:372`);
- `members.invite`, `.role_change`, `.revoke`, `.resend`, `.accept`, `.decline` (`access/team_service.dart:222-430`).

Its only reader, `entriesFor`, has no route (grep: no caller outside the repository). The log is written,
never shown.

### 2.3 Rows about the salon that are not keyed by it

- **The members' notification feed.** Each row names the salon through its route:
  - a salon event writes `/pro/appointment/{id}?salon={providerId}` for each member (`messaging/salon_notifier.dart:93-95`, `:132-138`);
  - a validation decision writes `/pro/onboarding?salon={providerId}` (`validation/salon_decision_notifier.dart:70-71`);
  - the salon is the route's last parameter in both, and the body names a date, never a client (`:253-281`);
  - **an exception:** an event whose booking has no id writes `/pro/appointments`, with no salon in it (`:95`).
- **The clients' notification feed.** A booking event writes a row with the route `/bookings`
  (`messaging/booking_notifier.dart:81-87`). No database key links it to the salon, but its text can
  name the salon.
- **The admin `audit_log`** (0010 `:309-318`) is « append-only » by convention
  (`admin/audit_log_repository.dart:1`, `:11`; no UPDATE or DELETE anywhere, grep). Its rows about the
  account and its salons:

| Target | Actions (file:line) | Written `reason` |
|---|---|---|
| `provider_account` = the owner's id | `kyc.approve` (`admin_kyc_service.dart:129`), `kyc.reject` (`:157`), `provider_account.erase` (`admin_provider_account_service.dart:167`) | `kyc.reject`: the written refusal. `provider_account.erase`: a code from a closed list, plus the case number in `metadata` |
| `provider` = the salon's id | `provider.suspend` (`admin_provider_service.dart:113`), `provider.restore` (`:152`), `provider.feature` (`:196`), `subscription.paid` (`:221`), `salon.approve` (`salon_validation_service.dart:135`), `salon.refuse` (`:273`) | `provider.suspend`: the written motive. `subscription.paid`: optional, the console sends none (`mobile/lib/services/admin/admin_service.dart:169`). `salon.refuse`: a code in `metadata`, never the note |
| `appointment` = one of its bookings | `dispute.open` (`dispute_service.dart:45`) | the dispute's motive |
| `dispute` = a dispute on one | `dispute.resolve` (`:114`) | the resolution |
| `review` = one of its reviews | `review.hide` (`moderation_service.dart:108`), `.restore` (`:125`), `.dismiss_reports` (`:145`) | `review.hide`: the motive |

- **The members' own accounts** (`provider_users`): their own; kept.
- **Elsewhere, outside the database:** the request logs, 30 days (decision 55); Sentry; the admin
  mailbox's place-change e-mails (decision 133); the backups (B0.28, prose only).

### 2.4 Files in R2

The upload purposes and their prefixes (`backend/lib/src/upload_signing_service.dart:24-36`):

| Prefix | Bucket | Whose | Referenced by |
|---|---|---|---|
| `gallery/{providerId}/…` | public (CDN) | the salon | `imageUrls`, `beforeAfters[].before/after`, `artists[].imageUrl` in `providers.data` (`provider_catalog_service.dart:478-561`, `:585-623`, `:689-695`). The salon's only photo purpose besides the logo, so before/after and team photos land here too |
| `logo/{providerId}/…` | public | the salon | `logoUrl` (`:244`) |
| `review/{userId}/…` | public | a client | `reviews.photo_urls` of the salon's reviews |
| `deposit/{userId}/…` | private | a client | `appointments.deposit_screenshot_url` of the salon's bookings |
| `kyc/{accountId}/…` | private | the owner | erased at the deletion, best effort (§1, out of scope) |
| `pending/…` | as above | — | unclaimed uploads, collected after a day by R2's lifecycle rule (`infra/cloudflare/r2-manifest.json:44-48`) |

Three facts the purge must respect:
- **A photo removed from the gallery is never deleted from storage.** The only `deleteObject` or
  `presignDelete` callers are the deposit, the upload promotion's `pending/` sources, the KYC, the
  deletion's KYC, the demo reset and the consumer erasure (grep). So `gallery/{providerId}/` can hold
  objects that nothing references, still public at their address (INFERRED).
- **A salon can reference a file under another salon's prefix.** A gallery save promotes any `pending/`
  key without checking that it is under the saving salon's own prefix (`promotedKey`,
  `upload_verification_service.dart:338-345`, used at `provider_catalog_service.dart:541-552`). The app's
  own comment records that a multi-salon owner's logo once landed in the default salon's folder
  (`mobile/lib/services/api/api_image_upload_service.dart:63-67`). Whether production holds such a
  cross-reference is UNVERIFIED.
- **`StorageService` cannot list a prefix** (`storage/storage_service.dart:45-109`: put, get, delete, size, copy).

### 2.5 What a deleted owner's salon is, between the deletion and a purge

- **Hidden.** It is `draft` (T51), out of discovery and the website; no online booking.
- **It can never go live again.** Going live needs an active owner row, checked under lock
  (`db/postgres_salon_validation_repository.dart:211-221`), and so does lifting a suspension back to
  live (`admin/admin_provider_service.dart:163-172`). No ownership transfer exists: `owner` is not an
  invitable role (`access/team_service.dart:54-58`, `:122`), and an owner row is protected (`:453-454`).
- **Its members keep working in it**, by role (the page says so, `page.tsx:225-227`): the agenda, manual
  bookings, the client file. They cannot export it: the export is the owner's (`salon.publish`,
  `pro-account-deletion-export.md:10`).
- **Its clients still see their bookings there.** `GET /appointments` enriches every booking with the
  salon's name, status and contact, whatever its status (`appointments/appointment_enrichment.dart:5-22`, `:65-90`).
- **« No owner » does not only mean « owner deleted ».** A salon passes through the same state for an
  instant while it is created:
  - between `createSalon` and `linkProvider` at sign-up (`salon_provisioning_service.dart:150-166`);
  - between `createSalon` and `ensureOwner` in « Ajouter un salon » (`access/salon_directory_service.dart:197-216`).

  It stays in that state for good if sign-up's provisioning fails after `createSalon`, which the route
  calls « tolerable » (`routes/auth/provider/register.dart:197-199`); the self-heal then creates another
  salon. Such an orphan was never owned, and is empty (INFERRED).
- **Production, last read 2026-11-14** (B0.22's O1, read-only, `pro-deletion-erase-gaps.md:208-212`):
  6 salons, all drafts, 3 with no owner left. *2026-11-20: read again, 8 salons, all drafts, still 3
  with no owner (§6.6 step 1).*

## 3. How long — the options

It is not a legal deadline: no text is cited for any duration (as for decision 142's delays). The backups
(B0.28) are not named.

| Option | For | Against |
|---|---|---|
| **(a) 30 days** | the shortest; matches the support erase's 30 days (decision 142) | members have 4 weeks to finish their bookings and copy what they need, with no export; a dispute on a recent booking may come later |
| **(b) 90 days** — *recommended* | members finish the salon's last bookings and keep the client file long enough to move on; a client's complaint on a last booking or deposit surfaces well inside it; still a real limit, short enough to state on the page | 90 days of third parties' data (the client file) with no owner |
| **(c) 1 year** | the longest working window for the team | a client file with no owner for a year, little reason given; the hardest to justify on the page |
| **(d) No limit** | today's state; nothing to build | not a purge: the page keeps saying « aucune durée », and Data safety keeps « sans durée fixée » |

**Recommended: 90 days** (Q1). **The clock starts only when real purges are on** (§6.2):
- for a deletion made while they are on, the clock starts at the deletion, and the members are told
  that day (Q4);
- for a salon whose owner left before (three on 2026-11-14), it starts the day real purges are switched
  on: later than the real deletion, never earlier.

No date is ever promised while the job only rehearses.

## 4. What the purge removes

The purge is per salon, in one database transaction (§6.3), then its files, then a second pass the next
day.

### 4.1 Rows deleted

| What | How |
|---|---|
| the salon (`providers`), with its catalogue, hours, breaks, closed days, reviews and their reports, validation state and history, place notice | `DELETE FROM providers`; the rest by their cascades (§2.2) |
| its bookings, past **and ahead**, with their reminders and disputes | `DELETE FROM appointments WHERE provider_id` (no FK, so explicitly); the two cascade. A booking ahead does not postpone the purge (§5.1) |
| its client file, with the notes | `DELETE FROM salon_clients WHERE provider_id`; notes cascade |
| its team log, search text included | `DELETE FROM provider_audit_log WHERE provider_id` |
| its offer and its notices | `DELETE FROM provider_subscriptions`, `subscription_notices WHERE provider_id` (they refuse the salon's delete otherwise) |
| the clients' favourites of it | `DELETE FROM favorites WHERE provider_id` |
| its invitations to addresses with no account | `DELETE FROM provider_members WHERE provider_id AND status = 'invited' AND account_id IS NULL`: third parties' addresses |
| the feed rows about it | `DELETE FROM notifications` where `user_id` is any account that holds a row in this salon's team, in any status, and the route's last parameter is `salon={id}` (§2.3). Rows with the route `/pro/appointments` name no salon and stay |

Under Q3 (b) instead, the bookings of platform clients (`user_id <> 'manual'`) stay; see §5.2.

### 4.2 Rows changed, not deleted

**The members' rows are revoked, not deleted.** This covers the active rows, and the invitations that
carry an `account_id`: `status = 'revoked'`, `revoked_at = now()`.
- **Why not delete them.** A member whose rows are all deleted would hold **no** membership. At their next
  sign-in, `GET /me/provider` would then create a new empty salon for them (the self-heal,
  `routes/me/provider/index.dart:74-92`; its guard is `hasAnyMembership`,
  `access/membership_service.dart:91-92`). That is the very defect the guard prevents.
- **Invitations too.** A re-invited former member's invitation keeps their `account_id`, for that exact
  reason (`db/postgres_membership_repository.dart:138-161`). That is why `decline` revokes it rather than
  deleting it (`:276-297`); the purge does the same.
- **What the member gets instead.** A revoked row gives the existing `403 not_a_member`
  (`index.dart:93-100`). Both apps then show the person's invitations if they have any, and otherwise
  sign them out with « Votre accès à ce salon a été retiré » (pro-rejoin-gate).
- **What the kept rows hold:** the member's own address and role, and a dangling `provider_id`. They go
  with the member's account (0038's cascade).
- **What this needs:** `provider_members`' foreign key on `provider_id` dropped (§6.2).
- **The readers that meet such a row** tolerate a missing salon (the review, §13):
  - `GET /me/salons` skips it (`salon_directory_service.dart:61-64`);
  - the admin lookup reads salons by id and shows what exists (`admin_provider_account_service.dart:84-108`);
  - invitation cards fall back to « Salon » (`team_service.dart:340-344`).

**The admin `audit_log`'s written reasons are erased, the rows kept** (Q6). The action, the target, the
time, the actor and the codes in `metadata` stay. The reasons go by two rules:
- **About the salon:** in the purge's transaction, `reason = NULL` on every row whose target is the salon,
  one of its bookings, one of its disputes or one of its reviews (§2.3).
- **About the deleted account** (a `kyc.reject`): a daily statement, independent of any salon. It sets
  `reason = NULL` on `provider_account` rows whose account no longer exists in `provider_users`, once the
  row is older than the retention. The reason is thus erased **at most** 90 days after the deletion,
  sooner when the decision was older. It needs no record of who the owner was.
- **Kept:** `provider_account.erase`, whose reason is a closed code.

The admin console shows « — » for an empty reason (INFERRED, checked at build).

### 4.3 The Clients search text

The search text goes with the salon's log (§4.1). **Q5** asks whether to go further: in **every** salon,
the search text (`meta.query` of `clients.list`) erased after 90 days, the row kept. Without it, Data
safety still says « sans durée fixée » for two cases:
- live salons;
- a member who deleted their account, in a salon that lives on.

### 4.4 Files deleted

**The candidates:**
- every key listed under the salon's two public prefixes, `gallery/{providerId}/` and `logo/{providerId}/`.
  This is a listing, not just the document's URLs, because removed photos stay there (§2.4). It needs
  `StorageService.listKeys(prefix, bucket)`, an S3 `ListObjectsV2` on R2 (INFERRED feasible: the R2
  client already signs S3 requests);
- every key the salon's document references, wherever it lives;
- the clients' files that the deleted rows referenced: each review photo (`review/` prefix only) and each
  deposit proof (`deposit/` prefix only, deposit bucket), read from the rows inside the transaction.
  Under Q3 (b), the kept bookings keep their deposit proofs.

**The rule:** a candidate is deleted **only if no other salon's document references its URL**. The URL
is looked up in every other `providers.data`, read through the stored string (as B0.22's read-back had to
be). A salon can reference another salon's prefix (§2.4), and a live salon's photo must never go with a
purged one. A key kept for that reason is reported (`keptShared`), and never deleted later by this job.

**Not deleted:**
- `pending/`: the lifecycle rule collects it;
- `kyc/`: the deletion erases it;
- any prefix but these four, and any bucket but these two.

**The CDN** may serve a deleted public photo from its cache for a while: the cache lifetime is
UNVERIFIED. B0.27 (the photos at the deletion itself) stays filed.

### 4.5 What the purge leaves, and why

| Left | Why |
|---|---|
| the clients' feed rows (route `/bookings`), and the members' rows with the route `/pro/appointments` | no key links them to the salon (§2.3); each belongs to its account and is deleted with it |
| the members' accounts, devices, preferences | their own; untouched |
| the admin's `provider_account.erase` row | the only record the identity existed, with no personal data (decision 141) |
| a file another salon references | it is that salon's photo too (§4.4) |
| the admin mailbox's place-change e-mails | in a mailbox, not the database; the texts keep « aucune durée » for them. A mailbox rule is a separate item if wanted |
| the request logs (30 days), Sentry, the backups | their own retention; the texts name the logs and not the backups (decision 140, B0.28) |
| `outbound_messages` | keyed by phone, and messaging is off in production |

## 5. Who loses what

### 5.1 The members who kept the salon

**At the purge, each member loses, for good:**
- access to the salon in MyWeli Pro, on the app and the website;
- its agenda: every booking, past **and ahead**. A walk-in client booked after the date loses the
  booking, so the members have to tell them;
- its client file and their notes;
- the catalogue, the hours and the team roster, with their own collaborator card;
- its reviews, its photos and its offer;
- their notifications about it.

**They keep** their account, their other salons and their invitations. At their next sign-in with no
other salon, the apps show their invitations, or sign them out with « Votre accès à ce salon a été
retiré » (§4.2). To delete their account after that, they write to support (decision 139), like anyone
whose access was removed.

**Why a booking ahead does not postpone the purge.** A postponement would let any member put off the
purge for good: the booking window reaches 365 days by default and 730 at most
(`appointments/booking_window.dart:7`, `:23`). The members are told the date twice instead (Q4). **Only
an open dispute postpones a purge.** That is MyWeli's own case, which MyWeli closes. The purge then
waits for the dispute to close, and the job reports the salon every day until it does.

**Before the purge,** the members cannot export the salon (the export is the owner's) and cannot take it
over (there is no transfer).

**Q4 — are they told?**
- (a) an e-mail when the clock starts, naming the date, and a reminder 7 days before *(recommended)*;
- (b) the first e-mail only;
- (c) none.

Under (c), their bookings ahead are deleted with no warning.

The draft (French, for sign-off in the backend PR):

> **Objet :** {Salon} sera supprimé le {date}
>
> Bonjour,
>
> Le propriétaire du salon {Salon} a supprimé son compte MyWeli Pro. Le salon n’est plus visible du
> public et ne reçoit plus de réservations en ligne.
>
> Vous gardez votre accès au salon dans MyWeli Pro, selon votre rôle, jusqu’au {date}. Ce jour-là, le
> salon sera supprimé définitivement : son agenda, y compris les rendez-vous prévus après cette date,
> son fichier clients, ses prestations, son équipe, ses avis et ses photos. Pensez à prévenir les
> clients concernés.
>
> Votre compte MyWeli Pro n’est pas supprimé. Pour le supprimer aussi : Profil → Supprimer mon compte.
>
> — L’équipe MyWeli

**The reminder:** « {Salon} sera supprimé dans 7 jours », with the same body.

**Who receives them:**
- only the salon's **active** members, and only at an e-mail address: a phone-registered owner's row
  holds a phone in `email` (`salon_notifier.dart:121-122`);
- `{date}` is the due day in the salon's timezone, as in « 18 février 2027 ».

### 5.2 The clients

**Q3** — the salon's bookings and reviews hold the clients' data too (their name, review, deposit proof):
- **(a) deleted with the salon** *(recommended)*. The booking leaves the client's « Mes rendez-vous »,
  the review their reviews, with the review photos and deposit proofs. One sentence in the privacy policy
  says so. Nothing to change in the apps.
- **(b) kept in the client's history.** The salon gone, `providerName` is null
  (`appointment_enrichment.dart:68`) and the apps print « Salon » (`mobile/lib/core/constants/unnamed_salon.dart:10`,
  `web/lib/salon-name.ts:8`), with no service names. A booking with no salon must then be walked through
  on both apps and the website (detail, rebook, reschedule, calendar), and may need an app release.
  Reviews go anyway (their FK cascades).

## 6. The mechanism

### 6.1 A scheduled job or an admin action

| Option | For | Against |
|---|---|---|
| **(a) A daily job on the maintenance cron** — *recommended* | keeps the page's promise without anyone remembering; one place for the rule; the cron's alert sees a failure (a 500) | a mistake runs unattended, hence the rehearsal and the guard (§6.5, §6.6) |
| **(b) An admin action, per salon, on the owner's yes** | a human reads each salon first | the promise depends on a person each time; no console screen exists for it (B0.25's console is still filed) |

**Recommended (Q2): (a), shipped as a rehearsal.** Every night it runs the real purge of every salon with
no owner, in a transaction that is **always rolled back**, and reports what each statement would have
done. It purges for real only after the owner reads those reports and says yes. Its first real run is
limited to one salon (§6.6).

### 6.2 Data model — migration `0046_salon_purge`

```sql
CREATE TABLE IF NOT EXISTS salon_purge_queue (
  provider_id       text PRIMARY KEY,   -- no FK: outlives the salon until its files are gone
  owner_erased_at   timestamptz NOT NULL,  -- when the owner was deleted, or when the job first saw no owner
  clock_started_at  timestamptz,        -- NULL until real purges are on; due = this + the retention
  reminder_sent_at  timestamptz,        -- Q4 (a)
  rows_purged_at    timestamptz,        -- the transaction committed (§6.3 step 4)
  pending_objects   jsonb NOT NULL DEFAULT '[]'  -- [{bucket, key}] still to delete
);
ALTER TABLE provider_members DROP CONSTRAINT IF EXISTS provider_members_provider_id_fkey;
-- Only under Q5 (a): the daily scrub reads by date, not by salon.
CREATE INDEX IF NOT EXISTS provider_audit_log_query_scrub_idx
  ON provider_audit_log (created_at) WHERE action = 'clients.list' AND meta ? 'query';
```

- **The constraint's name** is the one 0027's inline `REFERENCES` produced (`<table>_<column>_fkey`), as
  0038 read for `account_id` (`migrations.dart:1069-1071`). Confirmed at build from the 23503 the test
  database raises (INFERRED until then).
- **No owner id is kept.** The account's reasons are erased by their own rule (§4.2).
- **Rollback-safe.**
  - The table is additive: an older image never reads it.
  - Dropping the key widens what is allowed: an older image never deletes a salon.
  - An older image's deletion stamps nothing; the job's step 1 then records that salon the day it sees it.

**The deletion stamps each owned salon.** In `deleteAccount`, after the identity's delete succeeds
(`:216`):
```sql
INSERT … ON CONFLICT (provider_id) DO UPDATE SET
  owner_erased_at = EXCLUDED.owner_erased_at,
  clock_started_at = EXCLUDED.clock_started_at,
  reminder_sent_at = NULL
```
- `clock_started_at` is `now()` when real purges are on (`SALON_PURGE_MODE=execute`, read from the same
  environment), and NULL otherwise.
- **The deletion overwrites.** It is the authoritative event, so a row left by a creation's ownerless
  instant (§2.5) never keeps a stale date.
- **Best effort.** A failure is caught, and the job records the salon anyway (step 1).
- **Q4 (a)'s first e-mail** goes from here, only when the clock started, to the salon's active members.
  Best effort, never blocking the deletion.

### 6.3 The job, per run

**Modes,** from `SALON_PURGE_MODE`:
- `off`;
- `rehearse`, the default when unset;
- `execute`.

**Settings:**
- the retention is a code constant, `kSalonPurgeRetention = Duration(days: 90)` (or Q1's answer). A test
  pins it against the texts once they change;
- at most `SALON_PURGE_MAX_PER_RUN` salons per run: 10 by default, 1 for the first real run;
- it runs **last** in `MaintenanceTick.run`, after the four existing tasks, so a failure never stops
  the security prunes.

**The time budget.** The job `myweli-maintenance` has a 180 s attempt deadline and no retries; « the
next tick is the retry » (`infra/gcp/99-scheduler-jobs.sh:23-25`, `:42`).
- No new salon starts after 60 s of the purge's own time, and no new file deletion after 90 s.
- Whatever is left waits for the next day, and the response says how much.
- A salon is either wholly purged in its transaction or not at all; only files carry over.

**The steps.** « Ownerless » below means: no `provider_users.provider_id` link, no active `owner` row,
and not the demo salon (`demo_snapshot.provider_id`).

0. **Drop stale rows.** A queue row not yet purged is deleted, and reported as `unqueued`, when its salon
   has an owner again or no longer exists. This clears a salon caught in a creation's ownerless instant
   (§2.5) within a day.
1. **Record and start clocks** (`execute` only).
   - An ownerless salon not in the queue joins it, with `owner_erased_at` and `clock_started_at` = `now()`.
   - A queued row with no clock (stamped while the job only rehearsed) gets `clock_started_at = now()`.
   - Each started clock sends Q4's first e-mail.
   - When rehearsing, nothing is written; the response lists `wouldRecord`.
2. **Remind** (Q4 (a), `execute` only). For each row due within 7 days, not reminded, and still ownerless
   (re-checked): claim it (`UPDATE … SET reminder_sent_at = now() WHERE reminder_sent_at IS NULL RETURNING`),
   then send. At most once; a lost e-mail is not resent.
3. **Choose.** Rows with `rows_purged_at IS NULL` and `clock_started_at < now() - retention`, oldest
   first, up to the limit. The candidate query joins `providers` and requires a status other than
   `active`, and ownerless.
4. **Purge one salon, in one transaction:**
   1. lock its queue row `FOR UPDATE SKIP LOCKED` (a concurrent run skips it), then the salon row
      `FOR UPDATE`;
   2. **the tripwire** (§6.5): re-check the guards on the locked rows, in Dart, independently of step 3's SQL;
   3. **postpone** a salon with an open dispute, without failing: it is reported as `postponed` and
      tried again the next day. A booking ahead does **not** postpone (§5.1);
   4. read the ids and the keys: its bookings, disputes and reviews; the review photos and deposit proofs;
      the URLs in its document;
   5. erase the salon's `audit_log` reasons (§4.2);
   6. revoke the members' rows and the invitations with an account; delete the others (§4.2);
   7. delete the rows (§4.1), the salon last;
   8. write `audit_log` `salon.purge`, actor `system:salon-purge`, target the salon, `metadata` = the
      counts per table (numbers only);
   9. set `rows_purged_at` and `pending_objects` (the referenced and the clients' keys).
5. **Files**, for rows purged in this run or before:
   - list the two prefixes and add `pending_objects`;
   - drop every key that another salon's document references (§4.4);
   - delete the rest; a missing key counts as deleted.
6. **The next-day pass**, for rows purged **before** this run:
   - run step 4.7's deletes again for that id, to catch a write that slipped in beside the purge (a
     booking or client card created at that moment takes no lock on the salon row);
   - report any row found;
   - once no file is left, delete the queue row.
7. **The deleted accounts' reasons** (§4.2), one statement:
   ```sql
   UPDATE audit_log SET reason = NULL
   WHERE target_type = 'provider_account' AND action <> 'provider_account.erase'
     AND reason IS NOT NULL AND created_at < now() - interval '90 days'
     AND NOT EXISTS (SELECT 1 FROM provider_users u WHERE u.id = audit_log.target_id)
   ```
8. **Q5 (a)'s scrub,** one statement:
   ```sql
   UPDATE provider_audit_log SET meta = meta - 'query'
   WHERE action = 'clients.list' AND meta ? 'query' AND created_at < now() - interval '90 days'
   ```

**`rehearse`** runs steps 0 and 3–4 for **every** ownerless salon, queued or not and due or not, up to
the limit:
- each salon's step 4 transaction executes every statement, then is always **rolled back**;
- the response reports what each statement affected;
- step 5 only lists, steps 6–8 only count, and no e-mail is sent.

So the real purge's statements, and its tripwire, run against the real production rows from the first
night.

**The response** adds `salonPurge`, with ids and counts only (no name, no e-mail):
```
{mode, unqueued, recorded|wouldRecord, clocksStarted, reminded,
 purged|rehearsed: [{id, counts}], postponed: [{id, reason}],
 objectsDeleted, keptShared, objectsLeft, stragglers, reasonsErased, queriesScrubbed, budgetHit}
```

### 6.4 Idempotency

- **The record:** the queue's primary key. The job inserts with `ON CONFLICT DO NOTHING`, and the
  deletion overwrites (§6.2).
- **The rows:** one transaction per salon. A crash rolls it all back, and the next run starts it over
  with the guards re-checked. Once committed, `rows_purged_at` sends later runs to steps 5–6 only.
- **Two runs at once:** Scheduler makes no retries, but a forced run (`gcloud scheduler jobs run`) can
  overlap the daily one. `SKIP LOCKED` on the queue row makes the second skip a salon the first is
  purging.
- **The audit row** is written inside the transaction: once per salon.
- **The files:** deleting a missing key succeeds; the queue row goes only when nothing is left.
- **The e-mails:** the reminder is claimed before it is sent, so it never goes twice; the first e-mail
  goes once per started clock.
- **Steps 6–8:** running them again changes nothing.
- **The rehearsal** writes nothing: it rolls back. Test 8 checks this on every table.

### 6.5 The guard against a live salon

Two independent checks, so that a mistake in one is caught by the other:
1. **The candidate SQL** (§6.3 step 3) cannot select a salon that is `active`, linked, owned by an active
   owner row, or the demo salon.
2. **The tripwire** (step 4.2) re-reads the **locked** rows in Dart. If any of those four holds, it
   **throws**: nothing of that salon is committed, the run stops (no further salon), and the cron answers
   500, which its alert sees.

That state means the predicate is wrong, so the job stops rather than skipping. An open dispute is
different: a legitimate state, so it postpones.

**Two more protections:**
- **A file shared with another salon is never deleted** (§4.4).
- **The rehearsal runs both checks against production every night** before any real purge.

A test makes each check fail alone: with the SQL widened to take an active salon, the tripwire must
throw; with the tripwire removed, the SQL must still exclude it (§9).

### 6.6 Proving it safe on real production data

Each step is on the owner's yes; every read is read-only.

1. **Before the backend PR merges:** a read-only count in Cloud SQL, compared with 2026-11-14's
   (6 salons, 3 with no owner):
   - the ownerless salons, each with its status and its per-table counts (§2.2), beside the total of
     salons and of owned salons;
   - the `audit_log` reasons that §4.2 would erase;
   - the files that two salons both reference. This read lists the URLs in `providers.data`, and the R2
     prefixes with `95-verify-r2.sh`'s read access.

   **✅ Counted 2026-11-20 at 23:26 UTC, on the owner's yes, read-only** (results below, OBSERVED by that
   read).

   *How it read:*
   - **The database:** through the Cloud SQL Auth Proxy on the owner's gcloud login, in a session with
     `default_transaction_read_only=on`, inside `BEGIN READ ONLY … ROLLBACK`.
   - **The control:** a probe write in the same session was refused (« read-only transaction »). The same
     probe went through on a local database without the setting.
   - **R2:** `95-verify-r2.sh` cannot list objects, since wrangler has no object listing. The read
     therefore used the API's own R2 key at the versions `service.yaml` pins, as on 2026-11-09
     (web-pro-upload-resize §11), making only `ListObjectsV2` GET calls. Secrets stayed in memory and
     nothing was printed but aggregates.
   - **The SQL was dry-run first** on a throwaway local database at migration 0045, seeded with a
     production-shaped case. Every count came out as expected, among them a cross-salon photo and a
     search-text row stored as a JSON string.

   **The salons:**

   | | Salons | Status |
   |---|---|---|
   | In all | 8 (6 on 2026-11-14) | all `draft` |
   | With an owner | 5, each with both the link and an active owner row | — |
   | The demo salon | 1 of those 5 (it has an owner) | — |
   | **With no owner** | **3** (as on 2026-11-14) | none suspended, featured or with a `suspended_from` |

   **The 3 ownerless salons**, numbered by `ORDER BY id`:
   - **#1 and #3** hold their salon row only. Every table of §2.2 and §2.3 reads 0 for them, and their
     documents reference no file.
   - **#2** holds 1 availability row, 6 working-hours rows, 5 breaks, 1 team-log row, and a document
     that references 1 photo. That photo is the only object under its two prefixes (55,991 B).
   - **None of them has a member row of any kind,** active, invited or revoked. So Q4's e-mails would
     reach nobody for these three, and §4.2's revocation finds nothing to revoke.
   - **None of them has** a booking, a review, a dispute, a client card, a subscription, a validation, a
     favourite or a member notification.

   **The admin `audit_log`:** 14 rows in all, none with a written reason. 0 rows target one of the three
   salons, their bookings, disputes or reviews, and 0 deleted-account rows have a reason. §4.2 would
   erase nothing today.

   **The Clients search text (Q5):** 81 `clients.list` rows in all salons, 10 of them with a non-empty
   query, none older than 90 days. The oldest `clients.list` row is from 2026-08-26, so no query can
   reach 90 days before 2026-11-24.

   **The files:**
   - the salons' documents reference 14 distinct keys. None is referenced by two salons, and none sits
     under another salon's prefix. `keptShared` would be empty today;
   - the public bucket holds 20 objects (`gallery/` 17, `logo/` 3; 16 on 2026-11-14). At least 6 of them
     are referenced by no document, all outside the three salons' prefixes (B0.27's photos, INFERRED:
     20 objects against 14 keys);
   - the deposit bucket holds 0 objects.

   **The control:** an owned salon read through the same columns showed 5 services, 6 working-hours
   rows, 1 active member, 1 subscription and 5 bookings.

   **What the backend PR takes from this:**
   - **`audit_log.metadata` is a JSON string in all 14 rows.** `->`, `?` and `-` read nothing on a string.
     So the rehearsal reads and the `salon.purge` read-back (steps 3 and 5) decode it first, with
     `#>> '{}'`, as `providers.data` already needs.
   - **`provider_audit_log.meta` is an object in all 106 rows,** so §6.3 step 8's `meta ? 'query'` and
     `meta - 'query'` work on today's rows. A row stored as a string would escape both silently, as the
     local dry run showed. So the PR adds a test that pins the writer's encoding (§9).
   - **Step 3's rehearsal counts must equal the per-salon counts above,** for the salons still without
     an owner.
2. **In CI**, a production-shaped fixture on real Postgres. It holds:
   - a live salon, an owned draft, and an orphan from a failed sign-up;
   - a suspended salon with no owner, and the demo salon;
   - a salon with no owner and an open dispute;
   - one not yet due, and one due;
   - a photo two salons share.

   Only the due salon may change. Every other salon's fingerprint (each table's rows for it, hashed) is
   identical before and after, and so is the shared photo.
3. **After the deploy,** at least 7 nightly rehearsals are read.
   - Each one's `rehearsed` counts must equal step 1's count for the same salons.
   - A read-only fingerprint of every salon, taken before and after one rehearsal, must be unchanged,
     which proves the rollback.
   - Nothing is due during this time, because no clock has started (§3).
4. **Switch to `execute` with `SALON_PURGE_MAX_PER_RUN=1`**, on the owner's yes. Step 1 starts the
   clocks, and the members are told (Q4).
5. **The first real purge, 90 days later, read back:**
   - the salon's id is absent from every table of §2.2;
   - every other salon's fingerprint is unchanged (the same read before and after);
   - the R2 listing of its two prefixes holds only the `keptShared` keys;
   - the `salon.purge` row is there.

   The next night's pass is read too. Then the limit is raised, on the owner's yes.
6. **The way back** from a mistaken purge is a restore from backup only. That is 7 days of point-in-time
   recovery, per `docs/DEPLOYMENT.md:67`, UNVERIFIED (B0.28). Hence steps 1–5.

### 6.7 Where it sits

- **`backend/lib/src/maintenance/salon_purge_service.dart`:** the steps, the modes, the budget and the
  tripwire. No SQL.
- **`SalonPurgeRepository`** (interface):
  - `PostgresSalonPurgeRepository`: one transaction per salon, every statement of §4, and the rehearsal's
    rollback;
  - an in-memory twin over the in-memory repositories, for the service tests.
- **`StorageService.listKeys`:** R2 and the fake.
- **`MaintenanceTick`** gains a fifth task. `dependencies.dart` wires it, pinned by a wiring test.
- **`ProviderAccountService`** gains the stamp and Q4's notifier, both optional and wired, like its
  other optional dependencies (`:53-74`).
- **`TeamService.accept` hardened.** It dereferences the invitation it just checked (`team_service.dart:392`,
  `byId(...)!`). An invitation the purge deletes between the two reads would give a 500; the backend PR
  answers « invitation not found » instead.
- **The admin console's label** `'salon.purge': 'Salon purgé'`, in `mobile/lib/screens/admin/widgets/audit_actions.dart`.
  `validation_labels_test.dart` reads the backend's writers. The label reaches the console with the next
  admin deploy, which is the owner's step; until then the console shows the raw code.

## 7. Security — threat model ([BACKEND.md](../BACKEND.md) §7)

| Row | Delta written in the backend PR |
|---|---|
| **T84 (new): the salon purge** | **T:** a wrong predicate deletes a live salon, or a file another salon uses → two independent checks, a tripwire that stops the run, the shared-file rule, nightly rehearsals rolled back and read before any real run, a first real run limited to one. **R:** `salon.purge` in `audit_log`, counts in the response. **I:** the response and logs carry ids and counts, never a name, e-mail or phone. **E:** no new route; the existing cron authentication (`cron_auth.dart`) |
| **T53** (account deletion) | « each owned salon is queued for a purge after the retention; once real purges are on, its active members are e-mailed (Q4) » |
| **`audit_log`** | its first UPDATE: `reason = NULL` only. It touches the purged salon's targets, and the `provider_account` rows of accounts that no longer exist, past the retention. It runs only from the job. Rows are never deleted |

## 8. Performance

- **Volume:** daily at 03:30 UTC, at most 10 salons, inside the time budget of §6.3 (60 s for salons,
  90 s for files, under the job's 180 s deadline). Today there are 3 candidates (2026-11-14).
- **Indexes:** every per-salon read uses an existing one: `appointments_provider_date_idx`,
  `salon_clients_list_idx`, `provider_audit_log_idx`, `reviews_provider_idx`, `provider_members_provider`,
  `notifications_user_idx`.
- **Accepted scans:**
  - `favorites` (primary key `user_id, provider_id`) and `audit_log`'s targets have no index for this
    read. Both are small tables, so a scan per purged salon is accepted;
  - the shared-file rule reads every salon's document once per run. That is 6 salons today, and is
    revisited past a few thousand.
- **Locks:** the rehearsal holds row locks on a hidden salon for the length of its rolled-back
  transaction, a few hundred milliseconds at 03:30 (INFERRED; measured in CI). Network calls (R2) run
  after the transaction, never inside a lock.
- **Q5's scrub** uses its partial index. The index is built at boot under the 60 s statement timeout
  (`migrations.dart:1347`); the table is small today.

## 9. Tests — red first, each watched red on committed code

| # | Test | Mutation that turns it red |
|---|---|---|
| 1 | due salon purged: every §4.1 table empty for it, members and account-bearing invitations revoked, other invitations gone, reasons null, `salon.purge` written once | skip one table; delete members instead of revoking |
| 2 | not due (89 days after the clock started) → untouched | `<=` vs `<`; retention ignored |
| 3 | active salon in the queue → the tripwire throws, nothing committed, later salons not processed | drop the tripwire |
| 4 | the SQL widened to active salons → the tripwire still stops it | — (the pair of 3) |
| 5 | an owned salon (link, or active owner row) in the queue → tripwire | check only the link |
| 6 | the demo salon → never recorded, never purged | drop the `demo_snapshot` exclusion |
| 7 | an open dispute → `postponed`, untouched; a booking ahead → purged with the rest | postpone on bookings; purge despite the dispute |
| 8 | rehearsal → every table's fingerprint and the queue unchanged, no e-mail; its counts equal `execute`'s on the same fixture | commit instead of rolling back |
| 9 | two runs at once → one purge, one `salon.purge` row | drop `SKIP LOCKED` |
| 10 | a crash after the rows (storage down) → the next run deletes the files and, a run later, the queue row | delete the queue row before the files |
| 11 | a revoked member, and a re-invited one, then sign in → `GET /me/provider` 403 `not_a_member`, no salon created; `GET /me/salons` and the admin lookup tolerate the dangling row | delete their rows |
| 12 | files: only the four prefixes and the referenced keys; a key outside them is never deleted | drop the prefix filter |
| 13 | a photo the purged salon and a live salon both reference → kept, reported `keptShared` | drop the shared-file rule |
| 14 | a salon queued during a creation's instant, then owned → `unqueued` the next run; its owner's later deletion overwrites the date | drop step 0; `DO NOTHING` in the stamp |
| 15 | `deleteAccount` stamps each owned salon, with the clock only in `execute`; a member-only salon is not stamped | start the clock while rehearsing |
| 16 | e-mails: none while rehearsing; one at the clock's start, one reminder, never twice; a salon owned again gets no reminder; phone-only rows skipped | send while rehearsing; claim after sending; skip the re-check |
| 17 | the next-day pass deletes a booking inserted after the purge's transaction | skip the pass |
| 18 | a deleted account's `kyc.reject` reason, 91 days old → null; a live account's → kept; `provider_account.erase` → kept | drop the `NOT EXISTS` |
| 19 | Q5: a 91-day `clients.list` loses `query`, keeps `tag` and `page`; an 89-day one keeps it | wrong key removed |
| 20 | the time budget: with an injected clock past 60 s, no new salon starts; past 90 s, no new file deletion; the rest is reported and done the next run | ignore the clock |
| 21 | an invitation deleted between `accept`'s two reads → no 500 | restore the `!` |
| 22 | wiring: the tick runs the purge last; production wires the repository and storage | remove the task |
| 23 | the fingerprint fixture (§6.6 step 2, Postgres in CI) | any extra `WHERE`-less delete |
| 24 | *Added 2026-11-20 (§6.6 step 1's count):* `clients.list`'s writer stores `meta` as a JSON object on real Postgres (`jsonb_typeof = 'object'`), so test 19's scrub reaches it | store `meta` as a string |

Then:
- the full backend suite;
- `dart format`, and `dart analyze --fatal-infos --fatal-warnings` = 0;
- the contract tests: no path changes, and `openapi.yaml` gains only a description sentence on
  `DELETE /me/provider`.

## 10. Rollout, and the text PRs that follow

1. **This spec**, on the owner's answers (§11). The answers become decisions in BACKLOG, B0.24 is
   updated, and android-play-release step 10's B0.24 condition is met (decided). *Done 2026-11-20:
   decisions 153–158, in PR #821.*
2. **The read-only count** (§6.6 step 1), on the owner's yes.
3. **The backend PR**, from `main`. It holds:
   - the code, migration 0046 and the tests;
   - the T84 and T53 rows, and the `openapi.yaml` sentence;
   - the admin label, and `// Design:` links here.

   It merges on the owner's word, outside any merge hold.
4. **The deploy**, on the owner's yes (`deploy-backend.yml`, `image_tag` = the merge commit), outside any
   Apple review. Read back:
   - the revision at 100 %;
   - « Production checks » green;
   - the next maintenance run's response holds `salonPurge` in `rehearse`.
5. **The rehearsal reads**, then `execute` limited to 1, then the first purge read back, then the limit
   raised (§6.6 steps 3–5), each on the owner's yes.
6. **The text PRs.** They come only once `execute` is on, since a page never promises a purge that is not
   running. Each stays outside the freezes then in force: Google's reviews for `/pro/suppression-compte`
   (decision 140), Apple's for the policy. The drafts below use 90 days, under Q3 (a), Q4 (a), Q5 (a) and
   Q6 (a); the final words are signed off in each PR.

   **`/pro/suppression-compte`.** Its own date, `PRO_ACCOUNT_DELETION_UPDATED_AT`
   (`web/lib/proAccountDeletion.ts:24-27`), moves.
   - « Ce que devient votre salon », the members' sentence → « Les autres membres de son équipe gardent
     leur accès au salon dans MyWeli Pro, selon leur rôle, jusqu’à sa suppression définitive ; nous les
     prévenons par e-mail. »
   - « Ce qui est conservé », the end of the first item → « … et les membres de son équipe y gardent
     accès. **Il est supprimé définitivement 90 jours après la suppression de votre compte** (ou, si un
     litige sur l’un de ses rendez-vous est en cours, une fois ce litige clos), avec ses rendez-vous,
     son fichier clients et ses avis ; »
   - the commune and the city → « … cachées du public, et supprimées avec lui ; »
   - the photos → « … restent accessibles à leur adresse existante pour qui la connaît, jusqu’à la
     suppression du salon ; »
   - the team log → « … sans votre nom ni votre adresse e-mail. Il est supprimé avec le salon, et le
     texte d’une recherche est effacé au bout de 90 jours ; »
   - MyWeli's decision log → « … suspension d’un salon avec son motif. Les motifs écrits sont effacés au
     plus tard 90 jours après la suppression de votre compte ; la trace de chaque décision, sans motif,
     est conservée ; »
   - unchanged: the admin's e-mails, the collaborator card, the invitations, the 30 days of logs.

   **The privacy policy, « Conservation »** (`web/app/politique-confidentialite/page.tsx:319-356`).
   `LEGAL_UPDATED_AT` becomes the merge day, with its dated note in `web/lib/legal.ts:154`, under its rule.
   - The professional paragraph: « Aucune durée de conservation n’est fixée à ce jour : ces informations
     ne sont pas effacées automatiquement » becomes two sentences:
     - « Le salon et ses photos sont supprimés 90 jours après la suppression du compte, et les motifs
       écrits de nos décisions au plus tard à cette date ; la trace de chaque décision, sans motif, est
       conservée. »
     - « Les e-mails reçus par notre équipe, l’invitation et la fiche de collaborateur restent jusqu’à ce
       qu’ils soient retirés. »
   - The team log paragraph → « … Il est supprimé avec le salon, et le texte recherché est effacé au bout
     de 90 jours. Le texte recherché peut être le nom ou le numéro d’un client. »
   - For clients (Q3 (a)), one sentence in the first paragraph: « Si un salon est supprimé, vos
     rendez-vous et vos avis chez lui le sont avec lui. »

   **play-store-forms §4, « Historique des recherches »** (`docs/design/play-store-forms.md:596`):
   - « sans durée fixée à ce jour, y compris après la suppression du compte (décision 138 ; une purge
     sera décidée par B0.24) » → « effacé au bout de 90 jours dans le journal, qui est supprimé avec le
     salon 90 jours après la suppression du compte de son propriétaire » (décision N).
   - Play's Data safety form asks no duration (INFERRED), so nothing new is typed. Whether the console
     needs any change is read at that step, UNVERIFIED.

## 11. Open questions for the owner

Each has a recommendation; « Approve as recommended » answers all six.

**Answered 2026-11-20: « Approve as recommended », all six** (BACKLOG §2): Q1 → decision 153, Q2 → 154,
Q3 → 155, Q4 → 156, Q5 → 157, Q6 → 158. The « Under Q3 (b) » notes elsewhere in this spec describe the
option not taken. Q4's wording (§5.1) is still signed off in the backend PR.

| # | Question | Options | Recommended |
|---|---|---|---|
| **Q1** | How long is a deleted owner's salon kept? | (a) 30 days · (b) 90 days · (c) 1 year · (d) no limit (no purge) | **(b) 90 days**, counted from the owner's deletion. For a salon whose owner left before real purges are on, it is counted from the day they are switched on (§3) |
| **Q2** | How does the purge run? | (a) a daily job: nightly rehearsals rolled back, then real purges on your yes, the first limited to one salon · (b) an admin action per salon, each on your yes | **(a)** (§6.1, §6.6) |
| **Q3** | The clients' bookings and reviews at a purged salon? | (a) deleted with the salon, with review photos and deposit proofs; the policy says so · (b) the bookings kept in the client's history as « Salon », which needs the apps and site checked, maybe a release | **(a)** (§5.2) |
| **Q4** | Are the members who keep the salon told? | (a) an e-mail when the clock starts, with the date, and a reminder 7 days before · (b) the first e-mail only · (c) none, the pages say it; their bookings ahead are then deleted unannounced | **(a)**, with §5.1's wording, signed off in the backend PR |
| **Q5** | The Clients search text in **live** salons? | (a) erased after 90 days in every salon, the action row kept, so Data safety names one duration · (b) only with a purged salon | **(a)** (§4.3) |
| **Q6** | MyWeli's decision log about the account and its salons? | (a) the written reasons erased, the rows kept (who, what, when, codes) · (b) the rows deleted too | **(a)**: the log stays append-only in substance, and a decision stays accountable without its motive (§4.2) |

## 12. Definition of done (for the build, after the answers)

- [x] Decisions recorded in BACKLOG; B0.24 and android-play-release step 10 updated; this spec → Approved
      (2026-11-20, decisions 153–158, PR #821).
- [ ] Backend PR: the tests of §9 red first then green, `dart analyze` = 0, format clean, the contract
      sentence, T84 and T53, the admin label, `// Design:` links.
- [ ] The production count, the deploy, the rehearsal reads, `execute` limited to 1, the first purge read
      back: each on the owner's yes, each recorded.
- [ ] The three text PRs, after `execute` is on, outside the freezes.
- [ ] Feature branches and PRs; CI green; no Claude attribution.

## 13. Review log

**2026-11-20, an independent review of the first draft against the code** (a separate agent, read-only,
told to refute). Each finding was re-read in the code before it was folded in.

1. **A salon with an owner could be purged.** A salon has no owner for an instant while it is created
   (§2.5). Queued in that instant, it was never dropped, and a later deletion kept the stale date. Now:
   step 0 drops such rows, the deletion overwrites the date, and the reminder re-checks.
2. **Deleting invitations brought the self-heal back.** A re-invited former member's invitation carries
   their `account_id`, and deleting it left them with no row. Now those invitations are revoked, as
   `decline` does (§4.2).
3. **Listing whole prefixes could delete a live salon's photo.** A gallery save does not check the
   prefix, so a salon can reference another salon's file. Now the shared-file rule applies (§4.4).
4. **A booking ahead could postpone the purge for good,** with bookings up to 730 days out. Now only an
   open dispute postpones (§5.1).
5. **The dry run never exercised the purge, and the e-mails promised a date while nothing purged.** Now
   the rehearsal runs every statement and rolls back. The clock and the e-mails start only in `execute`
   (§3, §6.2, §6.3).
6. **The account's reasons needed an owner id the job could not know.** Now they are erased by their own
   rule (§4.2, step 7), and no owner id is kept.
7. **Smaller fixes:**
   - two citations corrected (going live; the self-heal's lines);
   - `provider_users.provider_id` added to §2.2;
   - the next-day pass catches a write made beside the purge;
   - feed rows are matched for any account in the team, revoked members included;
   - the clients' feed text can name the salon;
   - `TeamService.accept`'s `!` is hardened.
