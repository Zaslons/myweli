# R6 — the acting salon's facts, not the account's — design spec

| | |
|---|---|
| **Status** | **Built** 2026-10-16 on `fix/r6-salon-facts` — approved by the owner the same day (§11) |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-16 |
| **PRD ref / phase** | Team access R6 (multi-salons) · V1 |
| **ROADMAP entry** | `docs/roadmap/entries/2026-10-16-r6-salon-fact-reads.md` (added with the build) |
| **Module** | Accès & équipe (docs/MODULES.md) |
| **Skills checked** | myweli-dev-guardrails · SYSTEM.md §11, §12, §13, §17 read |
| **Parent** | [team-access-r6-multi-salons.md](team-access-r6-multi-salons.md) §6 · sibling of [r6-salon-id-pin.md](r6-salon-id-pin.md) §4 (Zaslons/myweli#625) |

## 1. Goal & scope

R6 lets an owner switch salons. `ProAuthProvider` describes the **acting** salon
(`activeSalonId`, `activeSalon` — the `GET /me/provider` salon payload — and
`salonName`), while `auth.provider` (`ProviderUser`) is the **account**: one
person, whose `providerId` is only the *default* salon. #625 fixed the reads of
salon **ids**; this part fixes the reads of salon **facts** that still come
from the account.

### 1.1 What is wrong, and a second reason it is wrong

After `switchSalon('provider2')` the demo owner (Jean, `jean@salon-excellence.test`)
sees, in « Profil », **Salon Excellence · Barbier · Cocody · +225 07 11 22 33 44**
— his default salon — while every other screen acts in **Beauté Divine**.

The account fields are worse than "the default salon's": they are a
**registration-time copy**. `provider_accounts.business_name` is written once,
at sign-up (`postgres_provider_auth_repository.dart`, INSERT only — nothing ever
updates it), and the salon is created *from* it
(`SalonProvisioningService.ensureSalon`). From then on the salon's name, address,
phone and category live on the salon and are edited in « Profil du salon ». So
**even a one-salon owner** who renames their salon keeps seeing the old name in
the « Profil » header, forever. The fix below covers both: salon facts come from
the salon, always.

### 1.2 The sweep — every `ProviderUser` field read in `lib/screens`, `lib/widgets`, `lib/providers` (+ `lib/core`)

Read in context, by field. `.providerId` reads are #625's and are not repeated here.

| Site | Field(s) | Account or salon fact? | Verdict |
|---|---|---|---|
| `pro_profile_screen.dart` — owner header | `businessName`, `businessType`, `address`, `phoneNumber` | **Salon** (the card describes the business) | **Wrong** — §2.1 |
| `team_screen.dart:84` — member-actions sheet | `businessName` → « {email} perdra immédiatement l’accès à {salon} » | **Salon** | **Wrong** — a destructive confirm naming the wrong salon. §2.2 |
| `pro_auth_provider.dart:197` — `salonName` fallback | `businessName` when no membership | Salon | **Wrong after a switch** (only reachable with no membership cached) — §2.3 |
| `pro_profile_screen.dart` — « Vérification » row | `verificationStatus` | **Account** (KYC) | Correct — §1.3 |
| `deposit_settings_screen.dart:205` — deposit gate | `verificationStatus` | **Account** | Correct — §1.3 |
| `pro_onboarding_provider.dart:106,119` | `verificationStatus` (fallback), `businessType` (required KYC docs) | **Account** | Correct — KYC is the account's |
| `pro_kyc_screen.dart:97,132,136` | `businessType` → required documents | **Account** | Correct — same |
| `add_salon_screen.dart:67` | `phoneNumber` → prefill of the NEW salon's phone | **Account** (the owner's number as a default, editable) | Correct — a prefill, not a display of a salon fact |
| `pro_profile_screen.dart` — member header | `name`, `email` | **Account** (the person) | Correct — salon line already reads `salonName` |
| `core/utils/data_export.dart` | `account` block | **Account** (labelled as such; the `salon` block reads the salon) | Correct |

`lib/widgets/` holds no `ProviderUser` read. The web has no « Profil » owner
header; its Acompte gate reads the account's KYC like the app (correct, §1.3).

### 1.3 Verification is per ACCOUNT — and that is right where it is shown

Checked in the backend, not assumed:

- `GET/POST /me/kyc` is self-scoped to `principal.userId` — the account.
- `POST /admin/kyc/{accountId}/approve|reject` sets `provider_accounts.verification_status`,
  then `_fanOutBadge` writes `verified` onto **every salon the account owns**
  (the scalar link ∪ active `owner` rows). `POST /me/salons` inherits the badge
  at creation. Owner rows are only ever created by provisioning
  (`ensureOwner`), never by an invitation.
- The deposit gate (`updateDepositPolicy`) checks the **caller's** account
  KYC; `deposit.manage` is owner-only.

Both app sites are gated to owners of the acting salon (« Vérification » on
`salon.publish`, Acompte on `deposit.manage`). In every salon where they
render, the account's status **is** that salon's badge — and it is richer
(`pending` / `rejected` + reason) than the salon's boolean `verified`. Their
copy already says « compte » (« Compte vérifié », « vérification de votre
compte », « Vérifier mon compte »). **No change**; a test pins the decision
(§8) so nobody "fixes" it to `activeSalon.verified`.

### 1.4 Out of scope

- Caching `activeSalon` in the persisted session (it would make the header
  offline-proof but carries the whole salon document; a separate decision).
- The service-layer salon resolution (`ApiProArtistService._providerId()`) —
  #625 §4's other follow-up, its own slice.
- Any backend change: none is needed.

## 2. UX & flows

### 2.1 « Profil » — the owner header describes the acting salon

**Entry points:** the « Profil » tab; returning to it after a switch (« Mes
salons » row or the dashboard « Bienvenue » header) or after saving « Profil
du salon ».

**Source:** `auth.activeSalon` — `name`, `category`, `address`, `phoneNumber`.
The name falls back to `auth.salonName` (membership — cached in the session,
so present at cold start and offline).

**Copy** (aligned with the editor « Profil du salon », which is where these
facts are changed):

| Row | Before | After |
|---|---|---|
| Name | « Nom de l’entreprise » | **« Nom du salon »** |
| Type | « Type d’entreprise » — the account's `BusinessType` label | **« Catégorie »** — the salon's category, with the editor's labels: Salon de coiffure · Barbier · Spa · Onglerie · Massage & bien-être |
| Address | « Adresse » — hidden when the account has none | « Adresse » — hidden when the salon's is empty (a fresh draft) |
| Phone | « Téléphone » — raw `+2250711223344` | « Téléphone » — `Formatters.formatPhoneNumber` (`+225 07 11 22 33 44`, §17); hidden when empty |

A category outside the five (a legacy seed) hides its row rather than print a key.

**States** (§12):

| State | When | Renders |
|---|---|---|
| **Success** | `activeSalon != null` | the four rows above, for the acting salon |
| **Loading** | `activeSalon == null && auth.isLoading` (cold start before `GET /me/provider` lands) | the name (from `salonName`) + three **skeleton** bars for the rows (`surfaceVariant`, `radiusSmall`, no text — the card's shape is known, §12). One `Semantics` label on the group: « Chargement des informations du salon ». |
| **Unavailable** | `activeSalon == null && !auth.isLoading` (offline cold start, or the probe failed) | the name + `textSecondary` line « Les informations du salon n’ont pas pu être chargées. Vérifiez votre connexion. » + a text button **« Réessayer »** (≥48dp) → `auth.refreshMembership()`; while it runs, the loading state — the card keeps its own `_retrying` flag, because `refreshMembership` raises no `isLoading` (only the cold start and a switch do). A retry *can* succeed here (the network comes back), so §12's rule allows it. |
| **Switching** | `switchSalon` in flight | unchanged: the previous salon stays shown until the switch succeeds; `membership` and `activeSalon` are replaced in the same `notifyListeners`, so the card never mixes two salons. A refused switch leaves the previous salon. |

Empty is not a state here: an owner always has an acting salon.

**Never the account fields as a fallback.** They are a registration-time copy
(§1.1): showing them while loading would flash a possibly-stale name, then
correct it — the exact defect, for a second.

### 2.2 « Équipe » — the member-actions sheet names the acting salon

`_openActionsSheet` reads `auth.salonName` instead of
`provider?.businessName ?? 'votre salon'`. The revoke confirm then reads
« awa@… perdra immédiatement l’accès à **Beauté Divine**. » when acting in
provider2. (`salonName` already falls back to « votre salon ».)

### 2.3 `ProAuthProvider.salonName` — the fallback chain

`membership.salonName` → the account's `businessName` **only while the
default salon is the acting one** (`selectedSalonId == null` and a salon
resolved: the salon the copy was made from) → « votre salon ». After a switch
the account's name is never the answer.

*Built without the `activeSalon.name` step first written here:* the salon
payload and the membership come from the same `GET /me/provider` response
(`MyProviderInfo.membership` is required) and are assigned together on every
path, so the step could never answer — mutation M11 survived because it was
dead code, and the code went rather than a contrived test.

### 2.4 Saving « Profil du salon » refreshes the acting salon

Today nothing refreshes `activeSalon` or `membership.salonName` after a save,
so a rename shows the old name in « Profil », « Mes salons » and the dashboard
header until the next cold start. On a successful save the screen calls
`auth.refreshMembership()` and `auth.loadMySalons()` (not awaited — the screen
pops at once, the header updates when the probe lands, a few hundred ms). A
failed refresh keeps the previous values; the next probe corrects them.

### 2.5 Accessibility (§13)

Rows are wrapping `Text` in a `Column` (no fixed heights — 200% safe); the
skeleton carries no text and one semantics label; « Réessayer » is an
`AppButton(type: text)` at the 48dp floor; meaning never by colour alone.

## 3. API & contract

None. `GET /me/provider` already returns `salon` (the acting salon) with
`name`, `category`, `address`, `phoneNumber`; `PATCH` of the salon profile is
unchanged.

## 4. Data model

None.

## 5. Architecture & patterns

- `salonCategories` moves from `pro_salon_profile_screen.dart` to
  `lib/core/constants/salon_categories.dart`, with `salonCategoryLabel(String)
  → String?` — one taxonomy for the editor and the header (§11 « reuse before
  you build »).
- The owner header becomes a private `_SalonCard` widget in
  `pro_profile_screen.dart` reading `ProAuthProvider` — no new provider or
  service. `_getBusinessTypeLabel` goes (its only caller was the header).

## 6. Security & authz

No change to any permission. Display only; the server stays the authority on
every write (`?salonId=` is revalidated server-side, T55). No PII moves.

## 7. Performance

One extra `GET /me/provider` + `GET /me/salons` after a salon-profile save —
the same pair a switch already costs. No new work on the « Profil » build.

## 8. Testing plan

**Red first**, new file `mobile/test/widget/salon_fact_reads_test.dart`
(harness: Jean signs in by email, `auth.switchSalon('provider2')` in
`tester.runAsync`, as in #625's `salon_id_reads_test.dart`):

1. **« Profil » after a switch** shows « Beauté Divine », « Salon de coiffure »,
   « Marcory, Zone 4 », « +225 05 44 55 66 77 » — and none of Salon Excellence /
   Barbier / Cocody / +225 07 11 22 33 44. *(Red today.)*
2. **« Profil » without a switch, after a rename** of provider1 through the
   salon-profile save: the header shows the new name. *(Red today — §1.1.)*
3. **Loading**: `activeSalon` null while loading → skeleton semantics label,
   no account field. **Unavailable**: `getMyProvider` failing → the sentence +
   « Réessayer »; tapping it with the service healed → the success rows.
4. **« Équipe » revoke confirm** after a switch names « Beauté Divine ».
   *(Red today.)*
5. **`salonName`** with no membership: the account name when not switched,
   « votre salon » when switched (unit).
6. **The kept decision (§1.3)**: after a switch to provider2 (owned), the
   « Vérification » row still reads the **account's** status, and the Acompte
   banner follows the account's KYC — set the account `pending` with provider2
   `verified: true` → « En attente de vérification » and the banner shows.
7. Existing suites: `pro_profile_role_test`, `pro_profile_delete_account_test`,
   `team_screen_test`, `pro_salon_profile_form_test`, `deposit_settings_screen_test`, `multi_salon_test`.
   Goldens: no golden covers the « Profil » header; `pro_team` does not open
   the sheet — CI runs them anyway.

### 8.1 What was run

**Red first** (commit `69d1db32`, against `main`'s code): 6 red, 2 green.
Every red failed on the account's name — « Salon Excellence » found where
« Beauté Divine » (or « Excellence Prestige ») belonged — except « Équipe »,
whose confirmation did not contain « l’accès à Beauté Divine. ». The two
greens are the ones meant to be green before and after: `salonName` for the
default salon, and the verification pin (§1.3 — a kept decision, not a fix).

**Mutations** on the committed fix, each alone, then `git checkout`:

| # | Mutation | Red in |
|---|---|---|
| M1 | name ← the account's `businessName` | switch · rename · cold start · offline |
| M2 | category ← the account's `businessType` | switch · cold start · offline |
| M3 | address ← the account's | switch · cold start · offline |
| M4 | phone ← the account's | switch · cold start · offline |
| M5 | name while loading ← `businessName`, not `salonName` | cold start · offline |
| M6 | loading shows the account's address instead of the skeleton | cold start · offline |
| M7 | unavailable shows the skeleton forever (no way out) | offline |
| M8 | « Réessayer » raises no loading shape | offline |
| M9 | the sheet ← `businessName` | « Équipe » |
| M10 | `salonName` ← the account's name even after a switch | `salonName`, switched |
| M11 | `salonName` without the `activeSalon.name` step | **survived** — dead code, removed (§2.3) |
| M12 | no refresh after a salon-profile save | rename |
| M13 | « Vérification » ← `activeSalon.verified` | the verification pin |
| M14 | the Acompte lock ← `activeSalon.verified` | the verification pin |

**13 of 13 red** once M11's code was gone; M6 is from the second pass (the
first one's mutation text did not compile — a harness slip, not a result).

**Suites** (local, final code): `salon_fact_reads_test` + 21 neighbouring files
(R6/auth units, Profil role + deletion, Équipe, Acompte, salon profile form,
onboarding, dashboard, rejoin, revoked session, staff shell, picker, add
salon) — 212 passing. `pro_profile_role_test` changed for the new label
(« Nom du salon », both the owner's presence and the member's absence).
`flutter analyze` 0, `dart format` clean. Not run locally: the full suite and
the goldens (CI runs both; no golden renders the Profil card). Not seen on a
device.

## 9. Rollout & scope discipline

Ships with the app; no flag. V1; R6 is built.

## 10. Definition of done

- [x] `flutter analyze` = 0 · `dart format` clean · the suites above green (§8.1).
- [x] Red-first record + mutation record (§8.1, and the PR).
- [x] Roadmap entry file; this spec → Built; README index row.
- [ ] Feature branch + PR; CI green; commits authored by the user, no Claude attribution.

## 11. Decisions (owner, 2026-10-16)

1. **Labels**: « Nom du salon » / « Catégorie » — the editor's words.
2. **Unavailable state**: the name + the sentence + « Réessayer ».
3. **Verification & Acompte stay account-level** (§1.3), pinned by a test.
