# A Pro account-deletion page for Google Play (B0.19)

| | |
|---|---|
| **Module** | web — one public, static page for salon accounts: `/pro/suppression-compte`, the URL Play's Data safety form takes as « URL de suppression » for MyWeli Pro |
| **Status** | **Approved 2026-11-13 (decisions 137–140); the French copy of §5.1 approved by the owner as written on 2026-11-13 (« Approve as written », after reading it in full).** The answers are folded into §5–§12. **Built 2026-11-14** on `feat/web-pro-account-deletion` (S1, stacked on this spec's docs PR, #790); not merged — §11's order holds. Review findings folded in 2026-11-13, then a second review's the same day (Review log, end); of the four questions it raised (§12), **R1 and R2 were answered on 2026-11-13 (decisions 141–143)**, and decision 144 (the App Store label's « Search History ») came from the same drafts; R3 and R4 stay open |
| **Owner** | the project owner: the sign-off on §5 sentence by sentence, every merge and every production or console step |
| **Last updated** | 2026-11-14 |
| **PRD ref / phase** | FR-AUTH-005 [V1] « Account deletion & data export request (store-policy + data-law compliance) » (`docs/PRD.md:344`) · V1 · Android release, before android-play-release step 7 |
| **BACKLOG item** | B0.19 · decisions 137–140 · its two gates: B0.22 (the backend erase gaps, [pro-deletion-erase-gaps.md](pro-deletion-erase-gaps.md)) and B0.23 (the privacy policy's correction) · since decision 141, also B0.25's server half ([admin-pro-account-erase.md](admin-pro-account-erase.md)) · filed: B0.24–B0.28 · R8 of [pro-android-signup.md](pro-android-signup.md) (§6.3 `:586-600`, R8 `:1000`, §9.2 row `:859`, at docs PR 0b's head) · bounded by decision 73 |
| **ROADMAP entry** | [2026-11-13-pro-account-deletion-spec.md](../roadmap/entries/2026-11-13-pro-account-deletion-spec.md) |
| **Related** | [play-store-forms.md](play-store-forms.md) §0.1 `:111`, §1 `:187`, §4 `:358-362`, §7.3 `:642-645` · [android-play-release.md](android-play-release.md) §4 step 7 · [pro-deletion-erase-gaps.md](pro-deletion-erase-gaps.md) (B0.22, the backend half of decision 137) · [pro-account-deletion-export.md](pro-account-deletion-export.md) (the deletion it documents) · [demo-account-deletion-lock.md](demo-account-deletion-lock.md) · [legal-l1.md](legal-l1.md) (`LegalPage`) · [app-review-round-2.md](app-review-round-2.md) §5 (the five pages) · [web-pro-access.md](web-pro-access.md) (`ProAuthHeader`) · the read-only audit of 2026-11-13 (session notes, not in the repo) |
| **Skills checked** | myweli-web-guardrails (invoked for this spec) · [WEB.md](../WEB.md) · [WEB-SYSTEM.md](WEB-SYSTEM.md) §4, §9, §12–§15 · [SYSTEM.md](SYSTEM.md) §12, §13.2, §13.3, §17 · myweli-verification-guardrails' marking rule applied (not invoked) |

**Legend.** OBSERVED = read in the code at `main` `d19655bd` for this spec. INFERRED = reasoned from
what was read. UNVERIFIED = not readable from here. Every audit fact this spec relies on was
re-read; the audit's two summarizing reads of Play's help page were not repeated (no network).
Every `file:line` is at `d19655bd`, except `pro-android-signup.md`, which docs PR 0b edits and
which is cited at 0b's head (`docs/play-release-order`, `287c701f`); the BACKLOG, which this
spec's own PR edits, is cited by item and decision number instead.

## 1. Goal & scope

**Goal.** A Pro whose phone no longer has MyWeli Pro can find, on the web, how to delete their
salon account and what that deletion does, and can do it there. Play takes that page's URL.

**The one rule: a page no app opens and none of the five links to.** It lives under `/pro/`, so
decision 73 does not bind it (it is not one of the five store-linked pages) and it may lead to
`/pro/connexion`. It never enters `LEGAL_ROUTES`, so the five's footers do not change.

**In scope:** the page; a route record and its own date; a small widening of `LegalPage`;
`PRO_AUTH` in `SiteChrome`; a shared sign-in-methods helper read by `ProLoginOptions` and the page
(§7); the Lighthouse configs and their budget test (§9); sitemap and `llms.txt` (indexed, decision
140); `?suite=profil` on the Pro sign-in (decision 140); the tests of §10; the docs of §11.

**Out of scope:** any backend change in this PR. The erase gaps are B0.22 (decision 137,
[pro-deletion-erase-gaps.md](pro-deletion-erase-gaps.md)), a backend PR and a deploy of their own
that gate this page's merge and android-play-release step 7 (§11). Filed, not built here: a purge
decision (B0.24, decision 138), an admin « erase a Pro account » tool (B0.25, decision 139; *2026-11-13:*
its server half gates this page since decision 141, §11 step 3a),
« Supprimer mon compte » on the revoked path (B0.26, decision 139), deleting a salon's photos at
the deletion (B0.27, decision 137), stating the backups (B0.28, decision 140). Also out: the Pro
app and its five getters; any edit to the five pages in this PR (the policy's correction is B0.23,
its own PR); the deletion UI itself (`CompteDangerSection`, the app dialog), which stays as is.

## 2. What exists (OBSERVED, cited)

### 2.1 `/suppression-compte` cannot serve a Pro

- It renders through `LegalPage` from `LEGAL_ROUTES` (`web/app/suppression-compte/page.tsx:14,69`;
  `web/lib/legal.ts:72-80`). Its web path is the client « Mon compte » (`page.tsx:35,62,93-95`).
- Pro and client accounts are separate identities: `provider_users`
  (`backend/lib/src/db/migrations.dart:101`) vs `users`. A Pro following that page reaches the
  wrong account. Its Pro paragraph (`page.tsx:176-186`) gives the rule, not a path.
- It is one of the five pages both apps open (`web/lib/storeLinkedPages.ts:17-23`; `app_config.dart:111`).
  Decision 73 bars any `/pro…` or `/professionnels…` href on them (`web/tests/store-linked-pages.test.tsx:55-56,213-217`;
  `web/tests/e2e/store-linked-pages.spec.ts:18,52-61`).
- Play's form today holds `https://myweli.com/suppression-compte` (`play-store-forms.md:111,360`),
  recorded as « couvre les comptes professionnels », true of one paragraph only.

### 2.2 How a Pro deletes today

| | App (MyWeli Pro) | Website (Espace Pro) |
|---|---|---|
| Reach | owner: Accueil's account icon, tooltip « Profil » (`dashboard_screen.dart:153`); staff: the « Profil » tab (`staff_home_screen.dart:55`) | `/pro/connexion` → sidebar or « Ouvrir le menu » (`ProShell.tsx:103`) → « Profil » (`web/lib/pro/nav.ts:35`) |
| Entry | « Supprimer mon compte », under « Déconnexion » (`pro_profile_screen.dart:350,362`) | section « Compte », last on Profil (`CompteDangerSection.tsx:179,223`; `ProfilClient.tsx:137,407`) |
| Confirm | « Tapez SUPPRIMER pour confirmer » (`confirm_dialog.dart:210`; word at `pro_profile_screen.dart:405`) → « Supprimer définitivement » (`:399`) | « … Tapez SUPPRIMER pour confirmer. » (`CompteDangerSection.tsx:229-230`) → « Supprimer définitivement » (`:252`) |
| Refusals | `future_bookings` → « Terminez ou annulez vos rendez-vous à venir avant de supprimer votre compte. » (`pro_profile_screen.dart:416-418`); demo → « Compte de démonstration — cette action est désactivée. » | the same two sentences (`CompteDangerSection.tsx:26-35`; `web/lib/pro/team.ts:54-55`) |
| After | sign-out → `/pro/login` (`pro_profile_screen.dart:426-427`) | BFF clears the Pro cookies on 204 only (`web/app/api/pro/account/route.ts:14`) → `/pro/connexion` (`CompteDangerSection.tsx:174`) |
| Export | owner only: « Mes données » (`pro_profile_screen.dart:301-306`) | owner only: « Exporter (JSON) » (`CompteDangerSection.tsx:190`; gated `ProfilClient.tsx:409`) |

Signed out, `/pro/profil` bounces to `/pro/connexion` (`ProfilClient.tsx:88-90`), and a sign-in
lands on `/pro` or `/pro?salon=`, never back on Profil (`ProConnexionClient.tsx:24-26,35,53`).

### 2.3 What `DELETE /me/provider` does (`backend/lib/src/provider_account_service.dart`)

1. The demo identity → 403 `demo_account_locked`, nothing written (`:112`).
2. **Owned salons only** (`:116-122`): any `pending`/`confirmed` booking dated after now → 409
   `future_bookings` (`:126-135`). A member who owns no salon is never refused for bookings.
3. Each owned salon: `status → draft` (`:148`; hidden everywhere by T51, comment `:136`); phone,
   address, WhatsApp, Mobile Money number and operator cleared, deposit off (`:82-89,153`); a
   pending validation request deleted and admin notes cleared (`:158-159`); the last reported
   place forgotten (`:163`). **Not cleared:** the map pin (`latitude`, `longitude`), `commune`,
   `city` and `areaId`. `_erasedContact` (`:82-89`) holds none of them, although the salon's
   « place » of decision 129 (salon-go-live Q6, capped by decision 133) is exactly `latitude,
   longitude, address, commune, areaId, phoneNumber` (`provider_catalog_service.dart:74-82`,
   « (Q6) ») and the pin is an editable salon field (`:192-204`). Play's Data safety declares the pin as « Position exacte », public
   (`play-store-forms.md:383`). OBSERVED. **Decision 137:** B0.22 adds the pin to
   `_erasedContact`. *Engineering consequence, not part of the answer:* nothing else joins it, so
   the commune, the city and `areaId` stay, and the page says the commune and the city are kept.
4. KYC objects deleted, best effort, **only the keys listed in `kyc_docs` at that moment**
   (`:174-183`). A re-submit (supported after a rejection) replaces the list
   (`kyc_service.dart:69-72,96-112`; `postgres_provider_auth_repository.dart:480-484`) and
   deletes only the `pending/` copies (`upload_verification_service.dart:176-180`), never the
   superseded `kyc/{accountId}/…` object. The R2 manifest requires a lifecycle rule on `pending/`
   only (`infra/cloudflare/r2-manifest.json:44-48`); it is a floor, never a copy of the live
   configuration (`:11-12`), so whether the live bucket holds any other rule is UNVERIFIED
   (`95-verify-r2.sh` would read it, on the owner's yes). No rule the repo requires collects a
   replaced document: it outlives the deletion, with no limit known (OBSERVED in code; the live
   rules UNVERIFIED). Production held 0 KYC documents on 2026-11-12 (B0.20's read-only count),
   so nothing is orphaned yet (INFERRED). **Decision 137:** B0.22
   deletes the superseded objects at the re-submit, best effort: a delete that fails there (or a
   lost race's promoted copy whose delete fails) leaves an unreferenced private object that the
   later account deletion no longer lists. The page's KYC caveat covers both moments (§5.1).
   Device tokens, notifications and idempotency keys deleted (`:189-191`). Apple authorization
   revoked, never blocking (`:197`).
5. One transaction deletes the refresh tokens, the e-mail codes and the `provider_users` row
   (name, e-mail, `google_sub`, `apple_sub`, `kyc_docs`: `migrations.dart:101-113,557-559`;
   `postgres_provider_auth_repository.dart:622-650`); memberships go by cascade, then `:215`.
6. A re-hide catches a salon that went live in the window (`:225-235`). Route: 204
   (`backend/routes/me/provider/index.dart:153-170`).

**Kept (INFERRED from what the code does not touch):** the owned salon rows and everything under
them (services, hours, staff, photos, appointments, client file, reviews, subscription, a decided
validation), the commune and the city included, and the pin until B0.22 is live (step 3). That
includes the salon's free-text **description**: editable (`provider_catalog_service.dart:192-204`),
it may hold a phone number or a first name, and `_erasedContact` (`:82-89`) does not touch it
(OBSERVED).

- **The photo files stay public.** Gallery and logo uploads go to `StorageBucket.public` under the
  salon id (`upload_signing_service.dart:158-173`). Play declares gallery, logo, before/after and
  team photos as public (`play-store-forms.md:384`). Nothing in `provider_account_service.dart`
  touches the public bucket (OBSERVED). A photo URL served before the deletion still loads after
  it (INFERRED). These files are neither « dans notre base » nor hidden. **Decision 137:** the
  page says they stay reachable at their existing address (Q12 (d)); deleting them at the
  deletion (Q12 (c)) is filed as B0.27.
- **`provider_audit_log`** (`migrations.dart:616-624`) holds opaque ids and roles
  (`team_service.dart:226,273,407`). It **also** holds the free text typed into the Clients
  search, with the tag filter and the page: `clients.list` writes `meta {query, tag, page}`
  (`clients/clients_service.dart:96-104`), and `clients.view` writes the client id
  (`:178-183`). Each row carries its time (`created_at`). OBSERVED. Data safety says that search
  text is « gardé 30 jours dans les journaux de requêtes » (`play-store-forms.md:386`). That holds
  for the request logs, not for this table. **Decision 137:** that line is corrected, with B0.23.
- **Pending invitations to the account's e-mail.** A `provider_members` row is one per (salon,
  email), with `account_id` NULL while the invitation is pending (`migrations.dart:707-725`). The
  deletion removes `WHERE account_id = @a` (`postgres_membership_repository.dart:300-305`), and
  0038's cascade follows `account_id` only (`migrations.dart:1076-1080`). So another salon's
  unaccepted invitation keeps the address until that salon withdraws it (withdrawing deletes such
  a row: `postgres_membership_repository.dart:289-295`). OBSERVED.
- **The admin `audit_log`** (`migrations.dart:307-317`, « Append-only record of every privileged
  admin action », with a free-text `reason`) outlives the deletion, keyed to the deleted ids.
  `kyc.reject` stores the admin's written reason about the person's identity documents
  (`admin/admin_kyc_service.dart:155-162`: `targetType 'provider_account'`, `reason:
  reason.trim()`), the same reason that goes from `provider_users.rejection_reason`
  (`migrations.dart:110`) with the row. `provider.suspend` stores a suspension's reason against
  the salon (`admin/admin_provider_service.dart:111-120`). B0.18 logs only the code of a salon
  refusal for exactly this reason (`validation/salon_validation_service.dart:269-270`); KYC
  rejections were not changed. OBSERVED. The page lists it as kept with no limit set (decision
  138's wording), and B0.24's scope covers it.
- **A member's collaborator profile.** A member can be linked to one of the salon's collaborators
  (`access/team_service.dart:82,208`, `artistId`). That profile (name, photo; team photos are
  public, `play-store-forms.md:384`) belongs to the salon: the deletion removes the membership,
  never the salon's collaborators, so on a member-only salon it stays public until the salon
  removes it (INFERRED: member-only salons are never touched, `provider_account_service.dart:116-122`).

**No purge exists:** « purge » appears in `backend/lib` only in `security/origin_front_door.dart`
(OBSERVED, grep -i). **Decision 138:** the page says no retention limit is set yet; B0.24 decides
a purge before production access (android-play-release step 10).

Other members' accounts are untouched, and **they keep the hidden salon** (OBSERVED in code, not
run). `GET /me/provider` resolves a member's salon from the active
membership and never reads the salon's `status` (`backend/routes/me/provider/index.dart:80-113`).
`MembershipService.can`/`memberOf` gate on the member row alone (`access/membership_service.dart:16-40`),
and hiding applies to anonymous reads only (`salon_visibility.dart`, header). So managers and staff
still open the salon, its agenda and its client file in MyWeli Pro, each within their role. A
runtime read is not done here (no network).

**Outside the rows:** request logs 30 days, published and guarded
(`infra/gcp/logging-manifest.json:42-47`; `backend/test/infra/log_retention_test.dart:50-100`).
Cloud SQL backups « 7 retained » + 7-day PITR exist only as prose (`docs/DEPLOYMENT.md:66-67`),
UNVERIFIED in production; **decision 140:** not stated on the page; B0.28 states them after a
read-only describe and a manifest. **Copies outside the database:** the place-change e-mails
already sent to MyWeli's admin inbox (decisions 127, 129, 133) carry a validated salon's address,
phone and pin, before and after (`validation/salon_place_notice_service.dart:27-32`,
`email/salon_validation_emails.dart:159-175`), and stay in that inbox; the page discloses them.
The e-mail provider's send logs (Resend) and Sentry's events: retention UNVERIFIED, so the page
states neither, as decision 140 treats the backups; raised to the owner (§12, R4).

**Three facts that shape the copy:** no admin route erases a Pro account (`backend/routes/admin/`
holds only `users/[id]/erase.dart`, consumer: its `:8`); the e-mail code reaches any Pro
account by its e-mail, whatever method created it (`postgres_provider_auth_repository.dart:195`
`WHERE lower(email) = @e`; the request does not reveal whether an account exists,
`backend/routes/auth/provider/email/otp/request.dart:14-17`); and **a revoked member cannot reach
Profil**. With memberships but none active, `GET /me/provider` answers 403 `not_a_member`
(`backend/routes/me/provider/index.dart:23-26,93-100`). On the website the dashboard's probe then
asks for the account's pending invitations; with none, it signs the user out to
`/pro/connexion?motif=acces-retire` (`web/components/pro/ProMembershipContext.tsx:45-50,341-342`).
A new sign-in lands on `/pro` and is probed again (`ProConnexionClient.tsx:53`). The app signs
out the same way (`mobile/lib/providers/pro_auth_provider.dart:424-428`). `DELETE /me/provider`
needs no membership (`provider_account_service.dart:91-122`), but no screen reaches it for
these users. OBSERVED. So there is no self-service deletion for them (INFERRED). **Decision 139:**
the page sends them to support@myweli.com, each request handled by hand in production on the
owner's yes; the admin erase tool (B0.25) and « Supprimer mon compte » on the revoked path (B0.26)
are filed.

**The by-hand erase (decision 139): what it must reproduce.** No written procedure exists (grep of
`docs/`: none), and every step below lives only in `ProviderAccountService.deleteAccount`
(`provider_account_service.dart:91-236`). A plain SQL delete would skip most of them, and the
person would get an erase that differs from the one « Ce qui est supprimé » describes. So a
support erase **runs that method itself for the account id**, with production's wiring, never
SQL by hand. In order: the demo lock (`:112`); the bookings gate on owned salons (`:116-135`; a
refused request is answered with the refusal sentence); for each owned salon, `draft`,
`_erasedContact` (the pin too once B0.22 is live), the pending validation and the admin notes,
the place notice (`:145-164`); the web rebuild (`:166-168`); the KYC objects (`:174-183`); device
tokens, notifications and idempotency keys (`:189-191`); the Apple revoke (`:197`); the
identity's transaction (refresh tokens, e-mail codes, the row, `:199`); the memberships (`:215`);
the re-hide (`:225-235`). Before it, the requester is verified as the account's holder: a
request from the account's own address, or, for a person who lost that address, the check the
« can't sign in » answer promises (§5.1), which the procedure defines. **How it is run** (for example a one-off entrypoint in the
production image, or B0.25's tool) is written as a procedure and approved by the owner **before
S1 merges** (§11 step 5), because the page promises this erase from its first day. An
engineering consequence of decision 139, raised to the owner (§12, R1). *(2026-11-13, decisions
141–142: B0.25's server half, [admin-pro-account-erase.md](admin-pro-account-erase.md), and its
written procedure, approved before B0.23.)*

### 2.4 Found while specifying (not B0.19)

- The privacy policy (one of the five) tells Pros too « sur le web, depuis Mon compte »
  (`web/app/politique-confidentialite/page.tsx:285-291`), which is the client account. Its
  « Conservation » opens with « Nous conservons vos données tant que votre compte existe »
  (`:304`) and its list (`:302-310`) omits a deleted owner's salon, which this page says is kept
  with no limit. play-store-forms makes the published policy the source of truth for Data
  safety: « un formulaire qui les contredit est un rejet » (`play-store-forms.md:7`). Before
  validating, the Data safety preview is read beside the policy, and « les trois doivent raconter
  la même histoire » (`:404-406`). So this is **not** a side note: it was Q11, and its correction
  is B0.23 (decision 137), which gates android-play-release step 7 (§11). Constraints, OBSERVED: the policy is one of the five,
  so no `/pro…` href (decision 73) and no `SALON_WORDS` text, « Espace pro » included
  (`web/tests/e2e/store-linked-pages.spec.ts:19,57-58`); it is frozen during Apple reviews; and a
  substantive change bumps `LEGAL_UPDATED_AT` under its rule (`web/lib/legal.ts:100-130`).
  · `web/public/llms.txt:32` says « no crash reporting »; the policy discloses Sentry
  (`politique-confidentialite/page.tsx:100-110`). S1 edits the same file (decision 140), so this
  is put to the owner in S1's scope (§12, R3), not left beside the new line.
  · *True at `d19655bd`, fixed by docs PR 0b:* `android-play-release.md` did not mention the Data
  safety deletion URL; 0b added it to step 7 (`android-play-release.md:169`), and this PR adds
  B0.22, B0.23 and decisions 138 and 140 to steps 7, 8 and 10 (§11).
  · The product name has two casings on this very page: the copy's « Espace Pro » (the h1 of
  `/pro/connexion`, `app/pro/connexion/page.tsx:20`, which the CTA opens) beside « Espace pro » in
  its header (`ProAuthHeader.tsx:26`) and footer (« Connexion Espace pro », `FooterGroups.tsx:13`),
  as in the consumer `Header.tsx:44`. The copy keeps « Espace Pro » (§5.2); harmonizing the three
  components is a one-word web fix of its own, not B0.19's (the header and footer render beyond
  this page).

## 3. Google Play's requirement

**Recorded in the repo (OBSERVED):** the page must name the app or the developer exactly as the
listing does (`play-store-forms.md:642-645`); the listing's name is `MyWeli Pro — Gestion de
salon` (`:187`); the account is personal (`:25`) and the developer name is
UNVERIFIED (`pro-android-signup.md:599-600,1022`); Data safety edits are typed at step 7
(`pro-android-signup.md:859,862-863`); the demo account's deletion is refused by design
(`play-store-forms.md:320`).

**Help 13327111** — read by the audit on 2026-11-13 through a summarizing fetch, not re-read here:
its wording is UNVERIFIED (the owner re-reads it in a browser before step 7,
`pro-android-signup.md:583`). As summarized: it applies when an account can be created in the app
(on Android it can, B0.17); the page loads, references the app or developer name, features the
deletion path prominently, lets the user request deletion (a link, « a customer service email or a
form »), outlines prior steps, does not send the user back to the app, and discloses data kept for
security, fraud or legal reasons. A sign-in in the path is not addressed. « You must also delete
the user data associated with that app account » bears on decision 138 (B0.24 decides a purge
before step 10).

| Requirement (as summarized) | How the page meets it |
|---|---|
| names the app as listed | the lead names « MyWeli Pro — Gestion de salon », read by a test from `play-store-forms.md:187`; the developer name is only compared at step 7 (decision 140) |
| path prominent, works without the app | the first section is the web path, numbered, one CTA to `/pro/connexion?suite=profil` |
| prior steps outlined | the bookings callout above the steps, with the exact refusal sentence |
| deleted / kept disclosed | §5's three lists; the kept salon history says no limit is set yet (decision 138) |
| a support pathway | the e-mail-code fallback, then support@myweli.com (decision 139); for a revoked member, who has no self-service path (§2.3), support@myweli.com too (decision 139) |

## 4. UX & flows

### 4.1 Route and who reaches it

`https://myweli.com/pro/suppression-compte` (decision 140). Reached from Play's Data safety
section and listing, from search (indexed, decision 140), and by typing. **Not** from the apps (two cross-language guards
forbid a sixth link: `store-linked-pages.test.tsx:313-343`, `mobile/test/infra/pro_site_links_test.dart:103-165`),
**not** from the five (decision 73), **not** from the footer (`LEGAL_ROUTES` stays four).

### 4.2 The page, top to bottom

1. `ProAuthHeader`: the lockup home + « Espace pro » (`web/components/pro/ProAuthHeader.tsx:13-27`).
   No client install banner: the only banner is the client app's, and a person leaving is not
   pushed to install. This is an exception to WEB-SYSTEM §13 (« on public + consumer pages »),
   declared here and written into WEB-SYSTEM §13 in S1 (§11).
2. Breadcrumb « Accueil › Supprimer votre compte MyWeli Pro », h1, the page's own date.
3. Lead (answer first), then the client pointer, before anything a client could act on.
4. Callout: owners settle their bookings first.
5. « Sur le web, sans l’application »: four numbered steps, the CTA after step 1, one line on what
   happens; then « Dans l’application MyWeli Pro » and the export callout (owners).
6. What is deleted, what becomes of the salon, what is kept, the « can't sign in » path; two FAQ
   h2s; the privacy line; the footer with its salons' group (`FooterGroups.tsx:32`) and the small
   lockup (`FooterMark.tsx`, any `/pro` path).

**Accepted limit: the footer's « Supprimer mon compte ».** The footer's legal group, kept on purpose
and tested (§10 #13), renders `LEGAL_ROUTES`' « Supprimer mon compte » → `/suppression-compte`
(`web/lib/legal.ts:72-79`; `web/components/SiteFooter.tsx:50-62`, every page). That is the client
page, which leads to « Mon compte ». On the page Play reviews for Pro deletion, a first-person
« Supprimer mon compte » therefore leads to the other account. Relabelling it is not possible here:
`SiteFooter` renders on the five, so a new label changes their served HTML. The mitigation is the
client pointer (§5.1), which says the client page is a different one and is the footer's link.
**Accepted by the owner as a limit (decision 140, Q14 (a)).**

One `h1`, `h2` only (`LegalPage.tsx:93-101`), lists as `<ol>`/`<ul>`, one `<main>`.

### 4.3 States

| State | What happens |
|---|---|
| Signed out (the normal case) | the static page; the CTA opens `/pro/connexion?suite=profil` (decision 140), and the sign-in then lands on `/pro/profil` |
| Signed in as a Pro | the same page: it reads no session, so it cannot fail and caches whole. `/pro/connexion` forwards a signed-in Pro at once (`ProConnexionClient.tsx:32-40`): to `/pro` today, to `/pro/profil` with `?suite=profil` |
| A client by mistake | the pointer under the lead sends them to `/suppression-compte`. If they still sign in on the Pro page with an e-mail that has no Pro account, they read « Compte introuvable. » (`ProLoginOptions.tsx:80`), whose sign-up link (`:246-247`) is today's behaviour, unchanged |
| A member (no owned salon) | the same steps; no export; the bookings gate does not apply to them (§2.3 step 2) |
| A member whose access was revoked | **no self-service path** (§2.3, three facts). Signing in on the website or in the app signs them out again, to `/pro/connexion?motif=acces-retire` with « Votre accès à ce salon a été retiré. » (`web/lib/pro/team.ts:118`), unless an invitation is pending. Profil is never reached. Their `provider_users` account still exists. The page sends them to support@myweli.com (decision 139), and each request is handled by hand in production, on the owner's yes. Offering the deletion on the revoked path itself is filed (B0.26) |
| The demo account | refused after SUPPRIMER with the demo sentence (§2.2), by design |
| JS off | the whole page is served HTML (static; `SiteChrome` renders on the server, INFERRED, proven by §10's JS-off e2e); the CTA is a plain `<a>`. Signing in needs JS (Google/Apple popups, the e-mail form), INFERRED |
| Loading / empty / error | none: no data is read. Next's `not-found`/`error` boundaries are unchanged |

### 4.4 Desktop, 320 px, 200 % text

- **Desktop:** header on `SITE_CONTAINER`; content in `LegalPage`'s `max-w-content` (720 px) reading
  column, `text-bodyLarge` (SYSTEM §10; `LegalPage.tsx:18-21,48`). No second layout.
- **320 px:** below every breakpoint, the same single column (WEB-SYSTEM §9). The CTA is `ButtonLink`
  (`web/components/ButtonLink.tsx`; `min-h-12` from `Button.tsx:12-14`, 48 px, SYSTEM §13.2) with no
  `nowrap`, so its label wraps instead of spilling. The steps' numbers sit outside the text.
- **Reflow at normal text size:** nothing has a fixed height. The type-overflow gate runs the
  page at 375×812, 320×512 and 320×256 (WEB-SYSTEM §9, §14). A 200 % browser zoom at 1280 renders
  640 CSS px, which is the `sm` layout: the live read checks it, but it is **not** doubled text.
- **200 % text is a second input** (WEB-SYSTEM §9, `docs/design/WEB-SYSTEM.md:604-608`): « 320
  at normal size does not cover it ». Register row 38 measured LegalPage pages widening past 320
  in the Android mode: `/politique-confidentialite` at 375, and `/mentions-legales` at 343 because
  of « support@myweli.com » (`mentions-legales/page.tsx:57`, `<A href={supportMailto()}>{SUPPORT.email}</A>`).
  This page prints that address three times (decision 139: the « can't sign in » and the revoked
  paths, and the first FAQ's visible answer) the same way, in the same `max-w-content px-m` column (INFERRED: same widening). So the page joins `type-overflow.spec.ts`'s doubled-text run at
  320×568 in both modes (`DOUBLED_TEXT`, `PHONE_320`, `:1030-1045`). The address is printed by a
  new `Email` element in `LegalPage.tsx`, used only by this page, whose text carries a break point
  after « @ » (`<wbr>`). The shared `A` is **not** changed: it renders on the frozen
  `/mentions-legales`. §10 #14.
- Focus: the global `:focus-visible` ring, DOM tab order, the skip link first (WEB-SYSTEM §5).

## 5. Copy — approved by the owner as written (2026-11-13)

**Status of the words.** Decisions 137–140 chose every variant; the sentences below are the chosen
ones. The owner has **not** approved them yet: each sentence of §5.1 waits for their sign-off, and
S1 is not opened before it (§11).

**Rules.** Vouvoiement; `’` and `…` (SYSTEM §17.1); `&nbsp;` before `; : ? !` and inside « », as
the five do (`politique-confidentialite/page.tsx:107,245,255`: «&nbsp;?&nbsp;», «&nbsp;Continuer
avec Google&nbsp;»). A
label in bold is quoted exactly as on screen (table 5.2). Nothing promises what the server does not
do: no delay that does not exist, no « nous ne pouvons rien restaurer » (backups exist, §2.3), no
« abonnement », offer, trial or price (decision 138), no backup duration (decision 140). (R) = live
wording reused.

### 5.1 The words

> **Title / h1** — Supprimer votre compte MyWeli Pro *(title rendered « … · MyWeli », `web/lib/seo/metadata.ts:10`)*
>
> **Meta description** — Comment supprimer votre compte MyWeli Pro sur le web, sans l’application, et ce que deviennent votre compte, votre salon et vos données.
>
> **Date** — Dernière mise à jour : {the page's own date} (R)
>
> **Lead** — Cette page concerne l’application **MyWeli Pro — Gestion de salon** et l’Espace Pro de myweli.com. Vous pouvez supprimer votre compte vous-même, sur le web, sans l’application et sans nous écrire. Si vous ne pouvez plus ouvrir l’Espace Pro, voyez plus bas.
>
> **Client pointer** — Vous avez aussi un compte client MyWeli, sur myweli.com&nbsp;? Votre compte client est un compte distinct&nbsp;: supprimer l’un ne supprime pas l’autre. Il se supprime depuis une autre page, [Supprimer votre compte](/suppression-compte), celle du lien «&nbsp;Supprimer mon compte&nbsp;» en bas de page.
>
> **Callout** — **Propriétaire d’un salon&nbsp;: terminez ou annulez d’abord ses rendez-vous à venir.** Tant qu’un rendez-vous confirmé ou en attente est à venir dans un salon dont vous êtes propriétaire, la suppression est refusée et vous lisez&nbsp;: «&nbsp;Terminez ou annulez vos rendez-vous à venir avant de supprimer votre compte.&nbsp;» Nous ne voulons pas annuler d’office les réservations de vos clients (R).
>
> **H2 — Sur le web, sans l’application**
> 1. Connectez-vous à l’Espace Pro avec la même méthode que dans l’application&nbsp;: **Continuer avec Google**, **Continuer avec Apple** ou **Continuer avec e-mail**. *(Google and Apple printed only when the shared helper says `/pro/connexion` shows them; see the note below the copy.)*
>    **[ Se connecter à l’Espace Pro ]** → `/pro/connexion?suite=profil`
> 2. Après la connexion, vous arrivez sur **Profil**. Sinon, ouvrez **Profil** dans le menu.
> 3. En bas de la page, dans **Compte**, choisissez **Supprimer mon compte**.
> 4. Tapez **SUPPRIMER**, puis choisissez **Supprimer définitivement**.
>
> La suppression est immédiate et définitive&nbsp;: vous êtes aussitôt déconnecté.
>
> **H2 — Dans l’application MyWeli Pro** — Ouvrez **Profil**&nbsp;: l’icône de compte en haut de l’**Accueil**, ou l’onglet **Profil**. Puis choisissez **Supprimer mon compte** en bas de l’écran. Tapez **SUPPRIMER** et confirmez avec **Supprimer définitivement**.
>
> **Callout** — **Propriétaire d’un salon&nbsp;? Pensez à exporter vos données avant** (R)&nbsp;: dans l’application, **Profil → Mes données**&nbsp;; sur le web, **Profil → Compte → Exporter (JSON)**.
>
> **H2 — Ce qui est supprimé**
> - votre compte MyWeli Pro&nbsp;: votre nom, votre adresse e-mail et le lien avec votre compte Google ou Apple&nbsp;;
> - toutes vos sessions et vos codes de connexion&nbsp;;
> - votre place dans chaque équipe dont vous faisiez partie&nbsp;;
> - les identifiants de vos appareils — **vos notifications s’arrêtent** — et votre historique de notifications (R)&nbsp;;
> - si vous utilisiez Apple, l’autorisation de connexion donnée à MyWeli Pro&nbsp;: nous demandons à Apple de la révoquer&nbsp;;
> - vos pièces d’identité et justificatifs envoyés pour la vérification du compte. Leur effacement est fait **au mieux**&nbsp;: si notre stockage est indisponible lors de la suppression, ou lorsque vous avez remplacé ou renvoyé un document, un fichier peut subsister dans notre stockage privé, jamais publié (R, widened).
>
> **H2 — Ce que devient votre salon** — Chaque salon dont vous êtes propriétaire est retiré du public en quelques minutes&nbsp;: il n’apparaît plus dans les recherches et ne peut plus être réservé. Il est **dépublié** plutôt que détruit, pour que les réservations, avis et fiches passés continuent de se résoudre (R). Chaque salon garde son nom et son historique&nbsp;; ses numéros de téléphone, WhatsApp et Mobile Money, son adresse et son point sur la carte sont effacés, et l’acompte est désactivé. Une demande de mise en ligne «&nbsp;En cours de validation&nbsp;» est retirée. Les autres membres de son équipe gardent leur accès au salon dans MyWeli Pro, selon leur rôle. Les salons dont vous êtes seulement membre de l’équipe ne changent pas.
>
> **H2 — Ce qui est conservé, et combien de temps**
> - l’historique de chaque salon dont vous étiez propriétaire — son nom, sa description, ses prestations, ses horaires, son équipe, ses rendez-vous, son fichier clients et ses avis — reste dans notre base, caché du public, et les membres de son équipe y gardent accès. Aucune durée de conservation n’est fixée à ce jour&nbsp;: il n’est pas effacé automatiquement&nbsp;;
> - sa commune et sa ville restent avec lui, cachées du public&nbsp;;
> - ses photos (galerie, logo, avant/après, photos de l’équipe) ne sont plus affichées au public sur MyWeli (les membres de l’équipe les voient toujours dans MyWeli Pro), mais restent accessibles à leur adresse existante pour qui la connaît. Aucune durée n’est fixée à ce jour&nbsp;;
> - le journal des actions de l’équipe garde des identifiants techniques, les rôles, la date de chaque action et les recherches faites dans **Clients**, sans votre nom ni votre adresse e-mail. Aucune durée n’est fixée à ce jour&nbsp;;
> - le journal des décisions de notre équipe sur votre compte et vos salons — vérification d’identité acceptée ou refusée, avec le motif écrit d’un refus, suspension d’un salon avec son motif. Aucune durée n’est fixée à ce jour&nbsp;;
> - les e-mails reçus par notre équipe lorsqu’un salon validé a changé d’adresse, de téléphone ou de point sur la carte restent dans notre messagerie. Aucune durée n’est fixée à ce jour&nbsp;;
> - votre fiche de collaborateur dans l’équipe d’un salon dont vous êtes seulement membre (nom, photo) appartient à ce salon et reste affichée tant qu’il ne la retire pas&nbsp;;
> - les invitations qu’un autre salon vous avait envoyées et que vous n’aviez pas acceptées restent dans sa liste, avec votre adresse e-mail, jusqu’à ce que ce salon les retire&nbsp;;
> - les journaux de requêtes de notre hébergeur sont supprimés automatiquement au bout de **30 jours** (R).
>
> **H2 — Vous ne pouvez plus vous connecter avec Google ou Apple&nbsp;?** — Saisissez l’adresse e-mail de votre compte dans **Votre e-mail**, puis choisissez **Continuer avec e-mail**&nbsp;: nous envoyons un code à 6 chiffres à cette adresse. Si vous n’avez plus accès à cette adresse, écrivez-nous à [support@myweli.com](mailto:support@myweli.com) avec le nom de votre salon&nbsp;: nous vous répondrons pour vérifier qu’il s’agit bien de votre compte.
>
> **H2 — Votre accès à l’équipe d’un salon a été retiré&nbsp;?** — Sans accès à un salon, l’Espace Pro vous déconnecte (ou ne vous montre que vos invitations) avant que vous ne puissiez ouvrir **Profil**. Écrivez-nous à [support@myweli.com](mailto:support@myweli.com) depuis l’adresse e-mail de votre compte&nbsp;: nous vous répondrons pour confirmer la suppression.
>
> **H2 (FAQ) — Puis-je supprimer mon compte MyWeli Pro sans l’application&nbsp;?** — Oui, si vous pouvez vous connecter à l’Espace Pro&nbsp;: sur myweli.com, ouvrez Profil, puis Supprimer mon compte en bas de la page. Sinon, écrivez-nous à support@myweli.com.
>
> **H2 (FAQ) — Pourquoi la suppression de mon compte est-elle refusée&nbsp;?** — Parce qu’un rendez-vous confirmé ou en attente est encore à venir dans un salon dont vous êtes propriétaire. Terminez-le ou annulez-le, puis recommencez.
>
> **Closing** — Pour le détail de ce que nous traitons et pourquoi, voir la [politique de confidentialité](/politique-confidentialite) (R).

**Notes on the words (not page text).**
- The KYC bullet and the pin in « Ce que devient votre salon » are true only once **B0.22** is live
  ([pro-deletion-erase-gaps.md](pro-deletion-erase-gaps.md)): the pin then goes with the address,
  and a replaced document is deleted at the re-submit, best effort. So the caveat names **both**
  moments a file can survive: the deletion (a failed delete, `provider_account_service.dart:174-183`),
  and a re-submit (a failed delete of the replaced document, or of a refused racing submit's own
  copies, erase-gaps §3.2). Such a file is private, unreferenced, and collected by no rule the
  repo requires (§2.3 step 4). « (R, widened) »: the live caveat (`suppression-compte/page.tsx:125-128`)
  names the first moment only. §11's rule: the page merges only after B0.22 is live, so these are
  the only wordings that ship.
- The salon sentence reuses `/suppression-compte`'s (`page.tsx:183-185`) with « son point sur la
  carte » added (decision 137). `legal.test.tsx:340-354` pins the original on the two existing
  pages; this page gets its own pin (§10 #11).
- Every support address renders through `Email` (§4.4, §7): `supportMailto()` with **no subject**,
  as `/mentions-legales` calls it (`mentions-legales/page.tsx:57`), so no subject line goes out
  that §5.1's sign-off has not covered. The first FAQ's answer names the address too: the FAQ
  array keeps plain text for the JSON-LD, and the visible answer prints the address through
  `Email`, so §10 #14's doubled-text run covers all three.
- « en quelques minutes »: the funnel and the search close at once, but the salon's marketing page
  keeps serving from the ISR cache for up to 300 s (`app/[slug]/page.tsx:21-33`, plus the image
  cache) until it expires or the rebuild lands. « immédiate et définitive » is about the account.
- « Ouvrez Profil » in the app: an owner sees no « Profil » label, only Accueil's account icon,
  whose tooltip is « Profil » (`dashboard_screen.dart:151-154`); staff have the tab
  (`staff_home_screen.dart:55`). The sentence names both.
- The first FAQ answers « Oui, si… » because it feeds the `FAQPage` JSON-LD that search snippets
  show: revoked members and people without their address have no self-service path (§2.3). Its
  question, and so the h2, is unchanged.
- Step 2 follows decision 140's `?suite=profil`: the CTA lands on Profil; the menu line covers a
  sign-in made another way.

**Before B0.22 is live — not shipped under §11's rule.** If the owner ever merges the page before
B0.22 is live (an override of §11), these three replace their counterparts word for word, and a
follow-up PR swaps them back once B0.22 is live and read back:

> - *(« Ce qui est supprimé », last bullet)* les documents de vérification enregistrés sur votre compte au moment de la suppression (pièces d’identité, justificatifs). Leur effacement est fait **au mieux**&nbsp;: si notre stockage est indisponible à cet instant précis, la suppression aboutit quand même, et un fichier peut subsister (R). Un document que vous aviez remplacé avant la suppression n’est pas effacé&nbsp;: il reste dans notre stockage privé, jamais publié.
> - *(« Ce que devient votre salon », the third sentence)* Chaque salon garde son nom et son historique&nbsp;; ses numéros de téléphone, WhatsApp et Mobile Money et son adresse sont effacés, et l’acompte est désactivé (R).
> - *(« Ce qui est conservé », the second bullet)* son point sur la carte, sa commune et sa ville restent avec lui, cachés du public&nbsp;;

**Step 1 names only the methods `/pro/connexion` shows, from one shared helper.** Both social
buttons depend on build-time variables. Google renders only with `NEXT_PUBLIC_GOOGLE_CLIENT_ID`
(`ProLoginOptions.tsx:42,262`) and Apple only with `NEXT_PUBLIC_APPLE_CLIENT_ID` (`:45,289`). The
e-mail button is unconditional (`:336`). Whether Vercel has the Apple variable is UNVERIFIED
(`web-pro-apple.md:5`). A new `web/lib/pro/signInMethods.ts` reads both variables, written as
literal `process.env.NEXT_PUBLIC_*` references so Next inlines them. `ProLoginOptions` and this
static page both read it, so the page names a button only when the same build renders it (§7,
§10 #19). S1's live read signed out confirms the result. With a method absent, step 1 names the
others and e-mail. The e-mail code still reaches an account created with Google or Apple (§2.3),
except a hidden Apple relay address the person does not know (a limit, not written on the page).
The « Vous ne pouvez plus vous connecter avec Google ou Apple ? » h2 refers to the method used in
the app, so it does not depend on the helper.

### 5.2 Every quoted label and its source

| On the page | Website | App |
|---|---|---|
| Continuer avec Google / Apple / e-mail | `GoogleSignInButton.tsx:143` · `AppleSignInButton.tsx:26` · `ProLoginOptions.tsx:336` | `pro_login_screen.dart:314,322,358` |
| Votre e-mail (the field, before « Continuer avec e-mail ») | `ProLoginOptions.tsx:323` (then the button `:336`) | `pro_login_screen.dart:349` (then `:358`) |
| code à 6 chiffres | « Code à 6 chiffres » `ProLoginOptions.tsx:213` | `pro_login_screen.dart:416` |
| Espace Pro | h1 `app/pro/connexion/page.tsx:20`, the page the CTA opens; also `ProSignOutRetry.tsx:44`, `web/lib/pro/landing.ts:60`. **Mismatch on this page:** its header prints « Espace pro » (`ProAuthHeader.tsx:26`) and its footer « Connexion Espace pro » (`FooterGroups.tsx:13`); the copy keeps « Espace Pro » throughout, and harmonizing the components is outside B0.19 (§2.4) | — |
| Accueil (the owner's account icon, tooltip « Profil ») | — | `dashboard_screen.dart:131` (title), `:151-154` (the icon) |
| le menu · Profil | « Ouvrir le menu » `ProShell.tsx:103` · `nav.ts:35`, h1 `ProfilClient.tsx:122,190` | `pro_profile_screen.dart:62` · `dashboard_screen.dart:153` · `staff_home_screen.dart:55` |
| Compte | `CompteDangerSection.tsx:179` | — |
| Supprimer mon compte | `CompteDangerSection.tsx:223` | `pro_profile_screen.dart:362` |
| Tapez SUPPRIMER | `CompteDangerSection.tsx:229-230,249` | `confirm_dialog.dart:210`; `pro_profile_screen.dart:405` |
| Supprimer définitivement | `CompteDangerSection.tsx:252` | `pro_profile_screen.dart:399` |
| définitive · Pensez à exporter vos données avant | `CompteDangerSection.tsx:229-230` | `pro_profile_screen.dart:395-397` |
| Mes données · Exporter (JSON) | — · `CompteDangerSection.tsx:190` | `pro_profile_screen.dart:306` · — |
| the refusal sentence | `CompteDangerSection.tsx:29` | `pro_profile_screen.dart:416-418` |
| En cours de validation | `web/lib/pro/salon-validation.ts:90,157` (decision 132's word) | none found in `mobile/lib` (grep, OBSERVED): the page quotes the website only |
| Clients | `web/lib/pro/nav.ts:25` | — |
| the deleted-owner sentence (reused, « son point sur la carte » added, decision 137) | `app/suppression-compte/page.tsx:183-185` | — |
| Supprimer votre compte (link) · politique de confidentialité | `web/lib/legal.ts:74` · `page.tsx:201` | — |
| « Supprimer mon compte » (the footer's link) | `web/lib/legal.ts:79` (`footerLabel`) | — |
| Votre accès … a été retiré (decision 139, paraphrased, not quoted) | `web/lib/pro/team.ts:118` | — |

Server claims map to §2.3: refused `:116-135`; signed out `route.ts:14`, `pro_profile_screen.dart:426-427`;
deleted `:174-215`; the salon `:148-163` and `_erasedContact` `:82-89`, which B0.22 extends with the
pin (the commune and the city stay);
members keep access `index.dart:80-113`; photos `upload_signing_service.dart:158-173`; the audit
log `clients_service.dart:96-104`; invitations `postgres_membership_repository.dart:300-305`;
replaced KYC: deleted at the re-submit by B0.22, best effort (kept today, `kyc_service.dart:69-72,96-112`);
revoked members `ProMembershipContext.tsx:341-342`, the invitations gate `:304-310`;
« en quelques minutes » `app/[slug]/page.tsx:21-33`; the description `provider_catalog_service.dart:192-204`;
the admin decisions `admin_kyc_service.dart:155-162`, `admin_provider_service.dart:111-120`;
the admin e-mails `salon_place_notice_service.dart:27-32`; the collaborator profile `team_service.dart:82,208`;
kept: no purge; 30 days: the manifest.

## 6. SEO / metadata

- `<title>` and h1 « Supprimer votre compte MyWeli Pro »; the description of §5.1; canonical
  `/pro/suppression-compte`; OG title, description, URL — the same shape as `legalMetadata`
  (`LegalPage.tsx:23-35`).
- **Indexed (decision 140, Q2).** Each `/pro` page sets `robots: { index: false, follow: false }`
  itself (e.g. `app/pro/connexion/page.tsx:9`; WEB.md:195). This page is the exception: a salon
  that uninstalled the app finds it by searching « supprimer compte MyWeli Pro », the only door
  besides Play. It costs a WEB.md:195 exception (written in S1) and a sitemap entry.
- **JSON-LD:** `WebPage` (`dateModified` = the page's own date, never `LEGAL_UPDATED_AT`) and
  `BreadcrumbList`, both from the shell (`LegalPage.tsx:49-62`); `FAQPage` from the two FAQ entries,
  rendered from the same array as the visible h2s, as `/suppression-compte` does (`page.tsx:29-65,69`).
  No `Organization` duplicate (the layout's).
- Indexed, so `app/sitemap.ts` gains one entry beside `LEGAL_ROUTES`' (`:66-71`), yearly, 0.3;
  `llms.txt`'s Legal list gains « Account deletion for MyWeli Pro (salon accounts), on the web:
  /pro/suppression-compte ». `robots.ts` is unchanged (`allow: '/'`).

## 7. Architecture

| File | Change |
|---|---|
| `web/app/pro/suppression-compte/page.tsx` (new) | static (SSG), outside `(dash)` so no `ProMembershipProvider` and no session (`app/pro/(dash)/layout.tsx:10-16`); `metadata`; the copy and the FAQ array; **no `className`** (WEB-SYSTEM §15 row 25); its doc comment links this spec (`docs/design/web-pro-account-deletion.md`); it never imports `LEGAL_UPDATED_AT` (§10 #7) |
| `web/lib/proAccountDeletion.ts` (new) | the route record (`slug`, `h1`, `title`, `description`) and its own `{ iso, label }` date. Not in `legal.ts`'s `LEGAL_ROUTES`, which feeds every footer (`SiteFooter.tsx:51`) and the sitemap |
| `web/components/legal/LegalPage.tsx` | the shell takes a route object and a date (`DocumentPage`). Both the JSON-LD `dateModified` and « Dernière mise à jour » come from that argument, not from `LEGAL_UPDATED_AT`, which today is read directly at `:54` and `:85`. `LegalPage({slug})` and `legalMetadata(slug)` become one-line wrappers that pass `LEGAL_UPDATED_AT`, so the four legal pages render byte-identical. New `Ol`/`Step` (numbered), `Cta` (wraps `ButtonLink`, primary) and `Email` (a `supportMailto()` link whose visible address breaks after « @ » with a `<wbr>`, §4.4), all used only by this page. The shared `A` is unchanged. It stays the only file with a `className` |
| `web/lib/pro/signInMethods.ts` (new) | `{ google, apple }` from literal `process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID` / `NEXT_PUBLIC_APPLE_CLIENT_ID` reads (inlined at build). `ProLoginOptions.tsx:42,45` reads its ids from here, and the page reads its booleans for step 1 (§5.1) |
| `web/components/SiteChrome.tsx` | `PRO_AUTH` (`:12`) gains `/pro/suppression-compte`. **Required, not cosmetic:** `isProRoute` is true for it (`web/lib/proRoute.ts:4-6`), so without the entry `SiteChrome` renders no header at all (`:20-21`) |
| `web/components/pro/ProConnexionClient.tsx` (decision 140) | `?suite=profil`, a fixed code, → `/pro/profil`; any other value → today's `home` (`:24-26`). Never a free URL |
| `web/app/sitemap.ts`, `web/public/llms.txt` (indexed, decision 140) | one entry each |

- **Why `/pro/…`:** `pro` is already a reserved salon slug (`backend/lib/src/slug.dart:59`), so no
  backend PR or deploy; a top-level route would need a `reservedPublicSlugs` entry and a deploy.
  No route conflicts in `app/pro/` (`(dash)`, `apercu`, `connexion`, `inscription`).
- **Outside the five:** `isStoreLinkedPage('/pro/suppression-compte')` is false (exact match,
  `storeLinkedPages.ts:42-45`); the footer keeps its salons' group there (`FooterGroups.tsx:32`).
  None of the five gains a link; `LEGAL_UPDATED_AT` (`legal.ts:127-130`) is not bumped.
- **No backend, no mobile, no OpenAPI change in this PR.** The page states; the server acts, once
  B0.22 is live (the pin, the replaced documents: [pro-deletion-erase-gaps.md](pro-deletion-erase-gaps.md)).
  B0.22 is a backend PR and deploy of its own, B0.23 a text-only web PR of its own; the filed items
  (B0.24–B0.28) are not built here.

## 8. Security & privacy

- No session, cookie, API or BFF read; no form; no PII rendered; nothing reveals whether an e-mail
  has an account (nor does the code request, §2.3). `?suite=` is a fixed code compared for
  equality, never a URL: no open redirect.
- The support link is `supportMailto()` (`web/lib/support.ts:41-44`), the published address with
  no subject (its subject is optional; the page passes none, as `/mentions-legales` does). The developer's personal name is not printed (decision 140, Q8 (a)).
- The Pro service worker has no `fetch` handler (`web/public/pro/push-sw.js:54-100`: install,
  activate, push, notificationclick), so it cannot serve a stale copy under `/pro/`.
- Headers and CSP unchanged (`next.config.mjs:247`, all paths). No new endpoint, so no new STRIDE row.
- The page is a published representation to users and to Google: §10 ties each sentence to code.

## 9. Performance

Static HTML, no data fetch, no image beyond the header lockup (already `priority`). The only JS
change is one string in `SiteChrome`'s set (and `?suite=profil`'s lines in the sign-in's own chunk). Budgets
as `/suppression-compte`: script ≤ 175 KB (WEB-SYSTEM §14, `lighthouserc.json`), LCP = the h1 text,
CLS ≈ 0 (no late content). Lighthouse a11y ≥ 0.95 and SEO ≥ 0.9 as errors (indexed, decision 140).

**The Lighthouse wiring has a trap.** The client page's block is `"matchingUrlPattern":
".*/suppression-compte"`, unanchored at the start, with `categories:seo` ≥ 0.9 as an error
(`web/lighthouserc.json:81,107-112`; the same pattern at `web/tool/lighthouse-production.json:74`).
It also matches `…/pro/suppression-compte`. `cwv-budget.test.ts` only checks that some block
matches each collected URL, with `new RegExp(m.matchingUrlPattern).test(url)` and
`covering.length > 0` (`:79-81`, `:136`). OBSERVED. The page is indexed (decision 140), so the
client block would silently cover a missing Pro block. (Had it been `noindex`, it would have
inherited an SEO error it cannot meet, because a `noindex` page fails `is-crawlable`, INFERRED.)
This is WEB-SYSTEM §15 row 27's trap. So, in both files:

- anchor the client patterns: `127\.0\.0\.1:3000/suppression-compte$` and
  `https://myweli\.com/suppression-compte$`;
- collect the new URL, with its own `/pro/suppression-compte$` block: CWV, script 175 KB, a11y
  0.95 and SEO 0.9, all as errors (indexed, decision 140);
- extend `cwv-budget.test.ts`: each collected URL is matched by **exactly one** block, in both
  files. That holds today: `/` has `…/$` only, `/connexion` has `.*/connexion` only.

## 10. Tests and guards

Each is watched red once on committed code, by the mutation named, before it is trusted.

| # | Guard | Holds | Mutation that turns it red |
|---|---|---|---|
| 1 | `web/tests/pro-account-deletion-page.test.tsx` (new): one h1 | the h1 text | change the route record's `h1` |
| 2 | same: the listing name | page text contains the `Nom de l'app` value parsed from `play-store-forms.md:187` | edit the name in the doc or the page |
| 3 | same: quoted labels exist | each label of §5.2 is in its web and app file, comments stripped (« En cours de validation » web only) | rename « Supprimer définitivement » in `CompteDangerSection.tsx` |
| 4 | same: the refusal sentence | the page's quote equals the string in `CompteDangerSection.tsx:29` and `pro_profile_screen.dart:416-418` | reword either |
| 5 | same: links | CTA is an `<a>` to `/pro/connexion?suite=profil` (decision 140); `/suppression-compte` and `/politique-confidentialite` present; no `/pro/profil` href | point the CTA at `/pro/profil`; drop `?suite=profil` |
| 6 | same: outside the five | not in `STORE_LINKED_PATHS` nor `LEGAL_ROUTES`; `isStoreLinkedPage` false for it and its encodings | add it to `LEGAL_ROUTES` (also reds `legal.test.tsx:423-434`) |
| 7 | same: metadata and the date | canonical; `robots` indexable (decision 140). **The date, three ways**, because « equals the page's own constant » cannot fail: the constant moves both sides, and today it equals `LEGAL_UPDATED_AT` (`legal.ts:127-130`, 2026-11-13). (i) The JSON-LD `dateModified` equals the date in the visible « Dernière mise à jour » line (iso ↔ label). (ii) A source check: neither the page's module nor its `DocumentPage` call references `LEGAL_UPDATED_AT`. (iii) In one render with `LEGAL_UPDATED_AT` mocked to another date, the page's date does not move | drop `alternates`; add `robots: { index: false }`; pass `LEGAL_UPDATED_AT` to the shell, or leave `LegalPage.tsx:54,85` reading it |
| 8 | same: durations | every « N jours » on the page is the manifest's `maxRetentionDays` (read from `infra/gcp/logging-manifest.json`); no other figure, so no 7-day backup line (decision 140) | set the manifest to 14; add « 7 jours » |
| 9 | same: words | no `abonnement|offre|essai|tarif|FCFA` (decision 138) | add « abonnement » |
| 10 | same: no `className` in the page file | the closed-theme defence | add one |
| 11 | `web/tests/legal.test.tsx`: add the page to the glued-word scan (`:298`), and, for the new page's file, a **spacing scan**: a « followed, or a » preceded, by a plain space or a line break fails, and so does a plain space before `; : ? !` (the five's convention, §5 rules). The deleted-owner pin (`:340`) stays as is for the two existing pages. The new page gets its own pin for the choices made (decisions 137–139, and the 2026-11-13 review): the salon sentence with « retiré du public en quelques minutes » and « son adresse et son point sur la carte sont effacés »; the history bullet with « sa description »; the commune-and-city bullet; the photos sentence (Q12 (d)) with « au public » and « les membres de l’équipe les voient toujours »; the KYC bullet in (a)'s widened wording (« lors de la suppression, ou lorsque vous avez remplacé ou renvoyé un document », the page merging after B0.22 is live, §11) and the absence of (b)'s « enregistrés sur votre compte au moment de la suppression » and « n’est pas effacé »; the no-limit sentence of decision 138; the audit-log bullet (« recherches faites dans Clients »); the admin-decisions bullet (« avec le motif écrit d’un refus »); the admin e-mails bullet; the collaborator bullet; the invitations bullet; the members-keep-access sentence; the app sentence (« l’icône de compte en haut de l’Accueil »); the e-mail path in order (« dans Votre e-mail, puis choisissez Continuer avec e-mail »); the revoked sentence (« ne vous montre que vos invitations »); the first FAQ (« Oui, si vous pouvez vous connecter »); and the two support paths | spacing, guillemets included; each pinned sentence | glue a `<strong>`; put a plain space inside « »; edit any pinned sentence |
| 12 | `web/tests/site-chrome.test.tsx`, and `pro-access.test.tsx` P4 (`:93-103`) with the new path added to its list | `ProAuthHeader` on the exact path (banner, `MyWeli — accueil` → `/`, « Espace pro », no « Mon compte »); consumer header elsewhere | remove the path from `PRO_AUTH` |
| 13 | `web/tests/e2e/pro-account-deletion.spec.ts` (new) | 200 signed out at 375 px; one h1; listing name before the first h2; CTA visible, ≥ 48 px, right href; canonical; JSON-LD parses (WebPage, BreadcrumbList, FAQPage); footer has the salons' group and the four legal links. **JS off** (`javaScriptEnabled: false`): h1 and CTA present, and the **header** checked inside its landmark: `getByRole('banner')` exists, contains « Espace pro » and has the `MyWeli — accueil` link to `/`. On raw HTML, check the `<header>` element, not the document: the footer's « Connexion Espace pro » (`FooterGroups.tsx:13`, shown here because `:32`'s `withSalons` is true) would satisfy a document-wide substring check | serve the page without `PRO_AUTH` (`SiteChrome.tsx:20-21` then renders no header); remove the CTA |
| 14 | `axe.spec.ts` (`:155-169` matrix), `type-overflow.spec.ts` (`:90` matrix, normal text), `controls-shape.spec.ts` (`:79`); **and** `type-overflow.spec.ts`'s doubled-text run (`DOUBLED_TEXT`, `PHONE_320`, `:1030-1045`) at 320×568 in both modes (Android `text-size-adjust: 200%`, and the 32 px root): `innerWidth × innerHeight` equals the screen's, no `horizontalOverflow`, and the vacuity check that the text really is doubled | a11y; reflow at 375/320; reflow at 200 % text; control shape | an unlabeled link; a `whitespace-nowrap` CTA; remove the `<wbr>` from `Email` (three places print the address: the two support paths, decision 139, and the first FAQ's visible answer) |
| 15 | `e2e/store-linked-pages.spec.ts`: a **separate** constant `PRO_DELETION = '/pro/suppression-compte'`, checked only in the five's raw-HTML loop (`:57-58`). `SALON_PATHS` (`:18`) is **not** touched: the controls require `/` and `/recherche` to contain every entry (`:95`) and the footer group's hrefs to equal it (`:108-110`, `FooterGroups.tsx:10-14`), so adding the path there turns the job red on its own | the five's raw HTML, RSC payload included, never names the path, even as text. The anchor checks already reject any `/pro/…` link (`:31,74`; `store-linked-pages.test.tsx:55-56,213-217`). The controls `:92-120` stay as they are | write the path as plain text on `/suppression-compte` |
| 16 | indexed (decision 140), so **two new tests** (the existing `served-html.spec.ts` check reads only three-segment URLs, `:29,62`, so it would never see this two-segment path): a unit test in the `tests/sitemap-professionnels.test.ts:27-30` style asserting the `/pro/suppression-compte` row; and an e2e test that takes that exact `<loc>` from `/sitemap.xml`, fetches its path, and asserts 200 and no `robots` `noindex` meta (the `:65-69` regex) | listed, answers, indexable | drop the sitemap row; add `robots: { index: false }` to the page |
| 17 | `lighthouserc.json`, `tool/lighthouse-production.json`, `tests/cwv-budget.test.ts` (§9) | the client patterns anchored; a dedicated `/pro/suppression-compte$` block (SEO as an error: indexed); each collected URL matched by exactly one block, in both files | delete the new block (zero matches → red); unanchor the client pattern again (two → red) |
| 18 | decision 140 (`?suite=profil`): `pro-connexion-salon.test.tsx` | `suite=profil` → `/pro/profil`; `suite=https://…` → `/pro`; `?salon=` unchanged | accept any `suite` value |
| 19 | `web/tests/pro-sign-in-methods.test.ts` (new) | `signInMethods()` for each variable set and unset (four branches); the page's step 1 names « Continuer avec Google » / « Continuer avec Apple » exactly when the helper says so; `ProLoginOptions` reads its ids only through the helper (source check) | unset `NEXT_PUBLIC_APPLE_CLIENT_ID` → the page must stop saying « Continuer avec Apple »; hardcode `true` in the page |
| 20 | B0.23 (decision 137), in its own PR: `web/tests/legal.test.tsx` | the policy no longer sends Pros to « Mon compte » on the web; « Conservation » names a deleted owner's salon, kept with no limit set yet (decision 138), and its photos, still reachable at their address; `LEGAL_UPDATED_AT` bumped; the five's raw HTML is still free of `/pro` and `SALON_WORDS` (`store-linked-pages.spec.ts:57-58`, unchanged) | restore « sur le web, depuis Mon compte » unscoped |

Plus a one-off check recorded in the PR: the four legal pages and `/support` rendered with
`renderToStaticMarkup` on the base and on the branch, diffed, empty (the `LegalPage` refactor).

## 11. Rollout and documents

**The order.** Each step waits for the one before it.

1. **S0 — this spec**, in a docs PR (`docs/pro-account-deletion-page`, stacked on
   `docs/play-release-order`). B0.22's spec ([pro-deletion-erase-gaps.md](pro-deletion-erase-gaps.md))
   and the BACKLOG items ride along. A docs merge can deploy the website (B0.1), so the owner merges.
2. **The owner's sign-off on §5.1, sentence by sentence.** The answers are in (§12); the words
   are not. The sign-off also covers the « Before B0.22 is live » sentences, although they ship
   only if the owner overrides the rule below.
3. **B0.22 — the backend PR, then its production deploy**, each on the owner's yes, read back as
   [pro-deletion-erase-gaps.md](pro-deletion-erase-gaps.md) §9 says. The read-back cannot see
   storage, so **also before S1**: O2's read-only R2 listing of `kyc/` against the stored keys, on
   the owner's yes, or the owner's confirmation that no KYC submission was rejected and
   re-submitted before the deploy (erase-gaps §10, O2). A document replaced before the deploy is
   outside B0.22 and would make the KYC bullet false for that account. *(2026-11-13, decision 143:
   **O1** is settled here too — a read-only count, then those pins erased once on the owner's yes,
   or the gap accepted in writing — because the policy's pin sentences depend on it. Under (b), S1's
   page keeps its approved copy: each of its sentences describes a deletion made from it, after B0.22 is
   live (the rule below), when the pin goes; the policy, which also speaks for owners deleted before the
   deploy, carries the variant ([web-privacy-pro-deletion.md](web-privacy-pro-deletion.md) §2). A
   rewording of the page would be a new sign-off.)*
   - **3a. R1 — the admin erase command** ([admin-pro-account-erase.md](admin-pro-account-erase.md),
     decisions 141–142; B0.25's server half). Its backend PR from `main` merges **before B0.22's** if it
     is ready, and B0.22's deploy then carries both (rolling it back removes both); if not, B0.22 does
     not wait, and R1 deploys alone later. Then its read-back, and **the procedure (its §10) approved
     by the owner, before step 4.** *(Engineering consequence, not part of decision 143: R1's deploy and
     read-back come before step 4 too, so the procedure is approved against routes that answer, and
     B0.23's sentence 2 sends people to support from its first day.)*
4. **B0.23 — the policy PR**, text only, on `/politique-confidentialite`:
   - Pros are no longer sent to the client « Mon compte » on the web.
   - « Conservation » names a deleted owner's salon, kept with no limit set yet (decision 138),
     and its photos, still reachable at their address (Q12 (d)).
   - No `/pro` href and no `SALON_WORDS` text, « Espace pro » included (decision 73).
   - `LEGAL_UPDATED_AT` is bumped under its rule (`web/lib/legal.ts:100-130`); §10 #20 guards it.
   - Its French words go to the owner for sign-off in that PR.
   - The same PR corrects `play-store-forms.md:386` (decision 137): the Clients search text is also
     kept in `provider_audit_log`, with no limit.
   - **An open question for the owner's sign-off in that PR** (§12, R2): the policy's « Vos droits »
     says, for everyone, « Vous pouvez à tout moment … supprimer vos données, sans nous écrire »
     (`politique-confidentialite/page.tsx:284-286`). Under decision 139, Pros who cannot sign in
     and members whose access was removed must write to support@myweli.com. Does « sans nous
     écrire » stay unconditional for Pros? Not decided here; the policy, Data safety and this page
     must tell the same story (`play-store-forms.md:404-406`). *(2026-11-13, decision 143: answered —
     (b), « sans nous écrire » stays and a sentence sends locked-out people to « Aide & Support »,
     with options A and B; the words and tests are [web-privacy-pro-deletion.md](web-privacy-pro-deletion.md).)*
5. **S1 — the page PR** (`feat/web-pro-account-deletion`): §7 and §10, red first, CI green.
   - **Before it merges, the by-hand erase procedure** (§2.3, decision 139): how
     `ProviderAccountService.deleteAccount` is run for one account id in production, written and
     approved by the owner, with whatever it needs built. The page's support paths promise that
     erase from its first day (§12, R1). *(2026-11-13, decisions 141–142: done by step 3a — the
     admin erase command deployed and its procedure approved — before B0.23, so before this PR.)*
   - The live `/pro/connexion` read confirms the sign-in helper's methods (§5.1).
   - The page's doc comment links this spec.
   - Updated in the same PR: WEB-SYSTEM §13 (the install-push exception), §14 (the Lighthouse row
     and the doubled-text run) and §15 row 27 (anchored patterns, exactly one block per URL); and
     WEB.md:195 (the indexed exception, decision 140).
6. **The live read**, signed out, at 375 px and 1280, JS on and off: 200, the h1, the listing name,
   the CTA reaches `/pro/connexion?suite=profil` and then Profil, the canonical, an indexable
   `robots`, and the sitemap row. **The control:** the five fetched raw, with zero
   `/pro/suppression-compte`, zero `/pro/` href, and their footers unchanged.
7. **S2 — the docs PR** (the table below), with the live read's date.
8. **Android-play-release step 7, on the owner's yes, in the pane.** In Data safety, the deletion
   URL `https://myweli.com/pro/suppression-compte` is typed, saved and read back. The developer
   name is compared there (§7.3, decision 140). The Data safety preview is read beside the
   corrected policy and this page (`play-store-forms.md:404-406`). All of this comes before step 8
   (the closed test's review).

**The KYC and pin wording: the rule (decision 137).** Of the two rules, this is the simpler one:
**the page PR merges only once B0.22 is live and read back.** Then one wording ships (§5.1's main
copy), it is pinned once (§10 #11), and no second page PR has to swap sentences. The other rule
would ship (b)'s wording first and change it after the deploy. That costs a second page PR, a
second pin and a second live read, for a page that cannot reach Play before step 7 anyway, while
B0.22 gates step 7 too. If the owner overrides the rule and merges the page first, the sentences
under « Before B0.22 is live » (§5.1) ship word for word, and a follow-up PR swaps them back once
B0.22 is live.

**Merge order** *(re-ordered 2026-11-13, decisions 141–143)*: S0 → sign-off → R1's backend PR
(before B0.22's merge if ready; B0.22 never waits) → B0.22 (merge, then deploy, shared with R1 if R1
merged first, then O1 and O2) → R1 deployed and read back, its procedure approved → B0.23 → S1. The
order approved first was « … → B0.22 → B0.23 → the by-hand procedure → S1 ». B0.23 and S1 do not
depend on each other in code. B0.23 goes first so the policy
and the page tell the same story from the page's first day (`play-store-forms.md:404-406`).

**The two iOS windows.** iOS 0.0.2 will be submitted after B0.18's Pro-app PR and the 0.0.2 bump
(decision 134; android-play-release §4 step 3).
- **The merge hold** (android-play-release step 3 (c), `android-play-release.md:164`): from the
  bump's merge until the iOS 0.0.2 IPA is built, nothing merges, since `release_build.sh` builds
  `origin/main`'s head and decision 119 ships iOS 0.0.2 from the commit right after the bump.
  **B0.22's merge, B0.23 and S1 avoid it.**
- **The Apple review** (B0.1: nothing the reviewer relies on changes during a review). B0.23
  changes one of the five pages; S1 changes `LegalPage.tsx`, the shell four of the five render
  through, and the Pro sign-in (`ProConnexionClient`, `ProLoginOptions` through the helper). So
  **B0.23 and S1 merge before iOS 0.0.2 enters Apple review, or wait until that review ends**,
  and **B0.22 deploys outside any Apple review**: the same rule, worded the same way in
  [pro-deletion-erase-gaps.md](pro-deletion-erase-gaps.md) §9.
- No review and no hold is recorded as active at `d19655bd` (INFERRED); the owner confirms at
  each merge and at the deploy.

**Google's review (decision 140, Q7).** From step 8 (the closed release sent to Google's review)
until Google's decision, this page is frozen, as the five are during Apple's reviews. Written into
android-play-release step 8 by this PR.

**Later text changes (B0.24, B0.27, B0.28).** Once a purge is built (B0.24), or the photos are
deleted at the deletion (B0.27), or the backups are stated (B0.28), this page, the policy's
« Conservation » (with `LEGAL_UPDATED_AT` under its rule) and play-store-forms' Data safety change
together, in text PRs that keep out of the merge hold, the Apple review (the policy) and Google's
review (this page).

| Document | Today | After |
|---|---|---|
| `play-store-forms.md:5,9` | no B0.19 | dated status line; the new web test as a guard |
| `play-store-forms.md:111` (§0.1, a dated record) | the old URL | a dated note, not a rewrite (`pro-android-signup.md:855`, at 0b) |
| `play-store-forms.md:358-362` (§4) | « …suppression-compte, qui répond 200 et couvre les comptes professionnels » | the new URL, read on {date}; the in-app line stays |
| `play-store-forms.md:642-645` (§7.3) | « Elle dit « MyWeli » » | it names « MyWeli Pro — Gestion de salon » + the developer name read at step 7 |
| `pro-android-signup.md:592-600,859,1000` (at 0b) | R8 open | done, with the URL and PR |
| `android-play-release.md` §4 step 7 | B0.19's page live and its URL typed (docs PR 0b); B0.22 deployed and read back, O2 settled, B0.23 merged (this PR, dated 2026-11-13) | each ticked with its PR, deploy and live read |
| `android-play-release.md` §4 step 8 | the page frozen from the release sent to review until Google's decision (decision 140, this PR) | the freeze's start and end recorded |
| `android-play-release.md` §4 step 10 | B0.24's purge decided before applying (decision 138, this PR) | B0.24's decision, and its text PRs (above) |
| BACKLOG B0.19, B0.22, B0.23 | open | status, PRs, deploys, the live reads |
| `play-store-forms.md:386` (Data safety, « Historique des recherches ») | « gardé 30 jours dans les journaux de requêtes » | corrected in B0.23's PR (decision 137): the Clients search text is **also** in `provider_audit_log`, with no limit (§2.3) |
| `play-store-forms.md:383-384` (« Position exacte », « Photos ») | public | after a deletion: the pin erased with the address (B0.22); the photos reachable at their addresses (decision 137) |
| `web/app/politique-confidentialite/page.tsx:285-291,302-310` + `web/lib/legal.ts` `LEGAL_UPDATED_AT` | « sur le web, depuis Mon compte » for all; « tant que votre compte existe » | B0.23, its own PR, gating step 7 |
| `docs/WEB.md:195` | « `/pro/*` is `noindex` » | the exception for this page (decision 140), in S1 |
| `docs/design/WEB-SYSTEM.md` §13 (`:763-774`) | the banner « on public + consumer pages » | the declared exception: no install push on `/pro/suppression-compte` (§4.2) |
| `docs/design/WEB-SYSTEM.md` §14 (`:776-814`) | Lighthouse on `/`, `/connexion`, `/suppression-compte`; doubled text gated on the salon page and the funnel | the new `/pro` block (SEO an error: indexed); the script-weight row lists the page; the doubled-text run lists it |
| `docs/design/WEB-SYSTEM.md` §15 row 27 | one block per collected URL, by « > 0 » | anchored patterns, exactly one block per URL |
| `docs/design/README.md`, `docs/roadmap/entries/` | a row and an entry for this spec (S0) | the row's status; one new entry file per PR |

## 12. Decisions

The owner answered on 2026-11-13, each with the recommendation (BACKLOG decisions 137–140). The
French copy of §5 is **not** part of these answers: it still awaits the sign-off.

| Q | The question | The answer | Decision |
|---|---|---|---|
| Q1 | The route | (a) `/pro/suppression-compte`: no backend slug reservation, no deploy, the Pro chrome | 140 |
| Q2 | Indexed or `noindex` | indexed: a sitemap entry, a `llms.txt` line, the WEB.md:195 exception | 140 |
| Q3 | A deleted owner's salon history | (a) « Say it, decide later »: the page says no retention limit is set yet, with no subscription, offer or trial words; a purge is decided before production access, step 10 (B0.24) | 138 |
| Q4 | State the 7-day backups | no, not now; filed: a read-only Cloud SQL describe and a manifest with its check first (B0.28) | 140 |
| Q5 | The « can't sign in » path | (b) the e-mail code, then support@myweli.com; each request handled by hand in production, on the owner's yes; an admin « erase a Pro account » tool (backend + console) filed (B0.25) | 139 |
| Q6 | Back to Profil after sign-in | yes: `/pro/connexion?suite=profil`, a fixed code | 140 |
| Q7 | Freeze the page during Google's review | yes: from step 8 to Google's decision, as the five are during Apple's | 140 |
| Q8 | The developer name | (a) the page names the app as listed; the developer name is only compared at step 7 | 140 |
| Q9 | `/suppression-compte` | (a) untouched | 140 |
| Q10 | A revoked member's deletion | (a) support@myweli.com, handled by hand, on the owner's yes; the admin tool (B0.25) does **not** gate step 7 (*amended 2026-11-13 by decision 141: its server half does*); (b) « Supprimer mon compte » on the revoked path, filed for later (B0.26) | 139 |
| Q11 | Correct the privacy policy before step 7 | (a) yes: B0.23, a text-only web PR, gating step 7 (§11 step 4) | 137 |
| Q12 | The pin and the photos | (a) the pin erased with the address (B0.22, gating step 7); (d) the photos said reachable at their address; (c), deleting them at the deletion, filed (B0.27). *Engineering consequence, not part of the answer:* the commune and the city are not erased, so the page says they are kept (Q12's original option text is not in the repo) | 137 |
| Q13 | Replaced KYC documents | (a) deleted at the re-submit (B0.22, gating step 7); §11's rule decides which wording ships | 137 |
| Q14 | The footer's « Supprimer mon compte » | (a) accepted as a limit; the client pointer says so | 140 |

**Raised by the second review (2026-11-13), for the owner.** R1 and R2 were answered the same day,
each with the recommendation of its draft (decisions 141–143); R3 and R4 are not answered.

| # | The question | Where | Recommendation |
|---|---|---|---|
| R1 | The by-hand erase procedure (how `deleteAccount` runs for one account id in production) gates S1. An engineering consequence of decision 139, which keeps the admin tool B0.25 off step 7's path, not a change to it | §2.3, §11 step 5 | yes; the procedure can be lighter than B0.25. **✅ Answered 2026-11-13, decisions 141–142:** « Build it first » — B0.25's server half (`DELETE /admin/provider-accounts/{id}/erase` and a read-only lookup), which **amends decision 139**: that half now gates S1 and step 7; and « Approve this check » — a one-time code to the stored address, CONFIRMER, no phone callback ([admin-pro-account-erase.md](admin-pro-account-erase.md); §11 step 3a) |
| R2 | Does the policy's « sans nous écrire » (« Vos droits ») stay unconditional for Pros, given decision 139? | §11 step 4, B0.23 | asked in B0.23's PR, with its French words. **✅ Answered 2026-11-13, decision 143:** (b), it stays, and a sentence sends locked-out people to « Aide & Support », promising a reply; with options A and B ([web-privacy-pro-deletion.md](web-privacy-pro-deletion.md)) |
| R3 | `web/public/llms.txt:32` says « no crash reporting »; the policy discloses Sentry. S1 edits that file | §2.4 | S1 corrects that sentence to match the policy. *2026-11-14: S1 does so (`web/public/llms.txt`, held by `tests/legal.test.tsx` « llms.txt does not deny what we ship either »); the owner's answer to R3 is not recorded here* |
| R4 | The e-mail provider's send logs (Resend) and Sentry's events: retention UNVERIFIED, so not stated, as the backups | §2.3 | a read-only read with B0.28, on the owner's yes |

**Filed, not built by B0.19** (BACKLOG batch 0): B0.24 the purge decision, before step 10; B0.25
the admin « erase a Pro account » tool; B0.26 « Supprimer mon compte » on the revoked path; B0.27 a
salon's public photos deleted at its owner's deletion; B0.28 the backups stated, after a read-only
Cloud SQL describe and a manifest.

## 13. Definition of done

- [ ] Typecheck and lint clean; `next build` succeeds.
- [ ] Every §10 guard in place and **each watched red once** on committed code by its named
      mutation, then green.
- [ ] axe clean on the page (`axe.spec.ts`); reflow clean at 375/320 at normal text size and at
      320×568 with doubled text in both modes; Lighthouse blocks as §9, exactly one per URL.
- [ ] The §5.1 copy signed off by the owner sentence by sentence; the page carries exactly the
      main copy (no `[Q…]` marker, none of the « Before B0.22 is live » sentences, §11's rule).
- [ ] `app/pro/suppression-compte/page.tsx`'s doc comment links this spec; this spec's status
      updated (Built, then Live with the date of the live read).
- [ ] WEB-SYSTEM §13, §14 and §15 row 27, and WEB.md:195, updated in the same PR (§11).
- [ ] B0.22 deployed and read back, O1 settled (a count, then those pins erased once or the gap accepted
      in writing) and O2 settled (the R2 listing or the owner's confirmation), the admin erase command
      deployed and read back and its procedure approved (decisions 141–142), and B0.23
      merged and read live, **before** S1 merges; the
      live read of §11 step 6 done and recorded.
- [ ] B0.22's merge, B0.23 and S1 outside the step 3 (c) merge hold; B0.23 and S1 merged, and
      B0.22 deployed, outside any Apple review (§11).
- [ ] Feature branch and PR; CI green; no Claude attribution; one roadmap entry file.

## Review log

Findings of the 2026-11-13 review, each checked in the code at `d19655bd` before folding.

| # | Finding | Verdict |
|---|---|---|
| 1 | Revoked members have no deletion path; « à tout moment » is unconditional | **Fixed.** OBSERVED `index.dart:93-100`, `ProMembershipContext.tsx:45-50,299-342`, `ProConnexionClient.tsx:53`, `pro_auth_provider.dart:424-428`. §2.3 fact, §4.3 row, lead softened, [Q10 (a)] copy, new Q10 |
| 2 | A replaced KYC document is never deleted | **Fixed.** OBSERVED `kyc_service.dart:69-72,96-112`, `upload_verification_service.dart:176-180`, `provider_account_service.dart:174-183`, `r2-manifest.json:44-48`. §2.3 step 4, bullet split (a)/(b), new Q13, §10 #11 |
| 3 | The pin, commune and city are kept; the photos stay public | **Fixed.** OBSERVED `_erasedContact` `:82-89`, `provider_catalog_service.dart:75-82,192-204`, `upload_signing_service.dart:158-173`, `play-store-forms.md:383-384`. §2.3, §5.1 kept list, new Q12, §10 #11, §11 rows |
| 4 | The audit log keeps the Clients search text, with no limit | **Fixed.** OBSERVED `clients_service.dart:96-104,178-183`, no purge (grep). Bullet reworded, §2.3, `play-store-forms.md:386` added to §11. Not folded into Q3, which stays unchanged |
| 5 | The policy contradicts the page and gates Play | **Fixed.** OBSERVED `politique-confidentialite/page.tsx:285-291,304`, `play-store-forms.md:7,404-406`. New Q11, gate before step 7, §11 row, §10 #20. Added constraint: the policy is one of the five, so no « Espace pro » text (`SALON_WORDS`) |
| 6 | Members keep access to the hidden salon | **Fixed.** Traced in code (no runtime read): `index.dart:80-113` never reads the salon's status, `membership_service.dart:16-40`. §2.3 no longer UNVERIFIED; the sentence added to §5.1 |
| 7 | Invitations keep the e-mail | **Fixed.** OBSERVED `postgres_membership_repository.dart:300-305`, `migrations.dart:707-725,1076-1080`. Listed under « conservé » |
| 8 | The client app is on no store | **Fixed.** OBSERVED in the BACKLOG: decision 51 and B0.10's « MyWeli (client): later ». Client pointer reworded |
| 9 | The footer's « Supprimer mon compte » leads to the client page | **Fixed.** OBSERVED `legal.ts:72-79`, `SiteFooter.tsx:50-62`. §4.2 accepted limit, pointer names it, new Q14 for the sign-off |
| 10 | « demande de mise en ligne » is not decision 132's word | **Fixed.** OBSERVED decision 132, `salon-validation.ts:90,157`. Copy uses « En cours de validation »; §5.2 row; there is no app equivalent in `mobile/lib` |
| 11 | Guard 15 would break the controls | **Fixed.** OBSERVED `store-linked-pages.spec.ts:18,57-58,95,108-110`. Separate `PRO_DELETION` constant |
| 12 | The client page's Lighthouse pattern also matches the new page | **Fixed.** OBSERVED `lighthouserc.json:81,107-112`, `lighthouse-production.json:74`, `cwv-budget.test.ts:79-81,136`. §9, §10 #17 with mutations. That LHCI applies every matching block is INFERRED |
| 13 | 200 % text is not covered | **Fixed.** OBSERVED WEB-SYSTEM `:604-608`, row 38. One correction to the finding's evidence: `type-overflow.spec.ts` does have the doubled modes (`DOUBLED_TEXT`, `:1030-1045`, salon page only), not only `salon-page.spec.ts` / `funnel-bar.spec.ts`. §4.4, §7 `Email`, §10 #14 reuse it |
| 14 | Guard 7 cannot fail | **Fixed.** OBSERVED `LegalPage.tsx:54,85`, `legal.ts:127-130`. Three assertions |
| 15 | Guard 13's « Espace pro » check is vacuous | **Fixed.** OBSERVED `FooterGroups.tsx:13,32`, `SiteChrome.tsx:20-21`. Scoped to the banner; P4 list (`pro-access.test.tsx:93-103`) in #12 |
| 16 | Guard 16 has no list to extend | **Fixed.** OBSERVED `served-html.spec.ts:29,62,65-69`. Two new tests |
| 17 | Sign-in buttons depend on env, unguarded | **Fixed.** OBSERVED `ProLoginOptions.tsx:42,45,262,289,336` (Google's branch is `:262`, not `:261`). Shared helper, §7, §10 #19 |
| 18 | Template rows, DoD, cross-link, WEB-SYSTEM rows missing | **Fixed.** Owner and PRD ref (FR-AUTH-005, `PRD.md:344`) rows, §13 DoD, S1 cross-link, §11 rows for WEB-SYSTEM §13/§14/§15 row 27 |

None was rejected. Two evidence details were corrected (#13, #17); the findings themselves held.

**2026-11-13, the owner's answers folded (decisions 137–140).** Each was the recommendation
(§12). Every bracketed variant of §5.1 now holds the chosen wording: Q3 (a) without subscription
words, Q5 (b), Q10 (a), Q12 (a) with the pin among what is erased and (d) for the photos, Q13 (a).
Q4's backup bullet is dropped. Step 2 follows `?suite=profil`. §11 now gives the order (S0 → copy
sign-off → B0.22 → B0.23 → S1), the KYC and pin wording rule and the Apple-review window. §12
became « Decisions ». B0.22's spec, [pro-deletion-erase-gaps.md](pro-deletion-erase-gaps.md), was
written beside this one. The French copy itself is still a draft until the owner signs it off.

**2026-11-13, later:** the owner read §5.1 in full and answered « Approve as written ». The copy is frozen; a change to it is a new sign-off.

**2026-11-13, a second review (26 findings across this spec, B0.22's, the BACKLOG and
android-play-release), each checked in the code before folding.** Fixed here: the KYC caveat names
both moments a file can survive (the deletion, a re-submit); the admin `audit_log` (a KYC
refusal's written reason, a suspension's reason), the salon's description, a member's
collaborator profile and the admin place-change e-mails are listed as kept (§2.3, §5.1); the
by-hand erase must run `deleteAccount` itself, and its procedure gates S1 (§2.3, §11, R1); the
e-mail path in the screen's order (« Votre e-mail », then « Continuer avec e-mail »); the photos
« au public », members still see them; the app's Profil reached by Accueil's icon or the tab;
`supportMailto()` with no subject; `&nbsp;` inside « » and a spacing scan (§10 #11); « Espace
Pro » kept, the header and footer mismatch recorded (§2.4, §5.2); O2 settled before S1; the
first FAQ conditioned (« Oui, si… »); « en quelques minutes » for the public salon; the
invitations gate in the revoked sentence; android-play-release steps 7, 8 and 10 dated (this PR);
the merge hold of step 3 (c) beside the Apple review, one wording with B0.22's spec; §2.4's stale
bullet dated and the pro-android-signup cites moved to 0b's head; B0.23's « sans nous écrire »
question (R2); the follow-up text PRs of B0.24, B0.27 and B0.28 (§11); `llms.txt` (R3); the
manifest read as a floor (live R2 rules UNVERIFIED); decision 129, not 123, for the place keys;
decision 137's commune-and-city clause moved to an engineering consequence. In B0.22's spec: a
refused submit deletes only its promoted keys that the locked list does not hold (test 9). None
was rejected.

**2026-11-14, a review of this branch (19 findings; 3 on this spec), each checked before folding; none
rejected.** The header and §1 name B0.25's server half as a gate (decision 141). §11 step 3 says what S1's
page says under O1 (b): its approved copy, since it speaks of a deletion made after B0.22 is live; the
policy carries the variant. Step 3a records R1's deploy and read-back before B0.23 as an engineering
consequence, the rule the merge order already gave; BACKLOG, the policy's spec and the roadmap entry now
say the same. The DoD names O1's settlement apart from O2's.
