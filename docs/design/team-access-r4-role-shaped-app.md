# Team access R4 — the role-shaped pro app

| | |
|---|---|
| **Status** | Built (R4a + R4b, 2026-07-12) |
| **Owner** | Sadreddine |
| **Last updated** | 2026-07-12 |
| **PRD ref / phase** | Module `access` (docs/modules/access.md §5.3, §10 A3) · pre-launch |
| **ROADMAP entry** | docs/ROADMAP.md — « Team access R4a / R4b » |
| **Skills checked** | myweli-backend-guardrails (R4a) · myweli-dev-guardrails (R4b) |

## 1. Goal & scope

R1–R3 shipped memberships, offers, invitations and the owner's team UI — but every
member still lands in the full owner-shaped app and lives off server 403s. R4
delivers the **role-shaped experience** (§5.3):

- **Manager** — the app minus money/settings: no Revenus (server field-gates →
  absent), no Acompte/Abonnement/Équipe/owner rows.
- **Réception** — the front desk: journal + rendez-vous + fichier clients, nothing
  else.
- **Collaborateur** — the app **reshapes** to « Ma journée »: a 3-tab bottom bar
  (décision utilisateur 2026-07-12) **Journée · Calendrier · Profil**, own
  planning only, actions « Terminé » / « Non présenté », header
  « {Salon} — votre planning », personal profile.
- **Revoked mid-session** — the next failing call signs the member out with
  « Votre accès à {Salon} a été retiré. » (no dead-end screens).

Two PRs: **R4a** (backend + contract — the enablers) then **R4b** (the app).
**R5** = web parity · **R6** = multi-salons. UI gating is convenience; the server
stays the authority everywhere.

## 2. R4a — backend enablers

### 2.1 Membership-aware `GET /me/provider`

The 200 body gains a required `membership` block:

```json
{ "account": {...}, "provider": {...},
  "membership": {
    "role": "staff",
    "capabilities": ["journal.manage.own", "journal.view.own"],
    "artistId": "artist1", "artistName": "Awa"  // staff only
  } }
```

- Owners resolve through the same path (self-heal included) → `role: owner`,
  full capabilities.
- A **revoked** bare member (memberships exist, none active) → 403
  **`not_a_member`** — the machine code the app's revoked handler keys on. A
  truly unlinked account keeps `forbidden`. `capability_required` (module §4
  sketch) stays deferred; capability misses remain uniform `forbidden`.

### 2.2 T40 — own-scope enforcement (one idiom)

`MembershipService.journalScope(accountId, providerId, {required manage})` →
`({bool all, String? ownArtistId})`; deny-by-default falls out of the empty
record (staff with a NULL artistId gets nothing). Call sites:

| Surface | Rule |
|---|---|
| `GET /providers/{id}/journal` | all → whole day; own → entries where `artistId == ownArtistId`, artists column narrowed, **`clientPhone` stripped when the day ≠ today** (same-day contact rule, clients §11.2 / T39) |
| `GET /appointments` (provider) | all → whole list; own → own-artist rows + off-day phone masking |
| `POST /appointments/{id}/complete` · `/no-show` | `all` OR (`manage.own` AND the appointment's artist == own artist) |
| `accept` / `reject` / `arrive` / `reschedule` / manual booking | `journal.manage.all` only (staff actions are exactly Terminé/Non présenté) |
| `GET /providers/{id}/dashboard` | unchanged — `journal.view.all` (staff 403) + `finances.view` field-gating (R1) |

Masking helper: `ClientsService.maskContactsOffDay(appointments, {now})` —
removes `clientPhone` off-day; ids/no-show counts stay (not contact data); the
client card itself remains behind audited `clients.view`.

## 3. R4b — the app

- **`ProMembership`** model (`role`, `capabilities`, `artistId?`, `artistName?`,
  `salonId`, `salonName`) + `ProCap` constants mirroring the backend strings;
  fetched via new `ProServiceInterface.getMyProvider()` (GET /me/provider) after
  login and on every cold start; cached inside the persisted `ProviderSession`
  for instant shaping; `ProAuthProvider.can(cap)` is the single gate helper
  (fallback: legacy owner session → owner-shaped; bare member → minimal).
  `activeSalonId` (= providerId ?? membership.salonId) replaces the wrong
  `providerId ?? id` fallbacks across screens.
- **Dashboard** — nullable revenue (absence = valid state), header
  « Bienvenue, {salonName} », cards gated per capability (réception ⇒ stats +
  Rendez-vous + Clients).
- **Profil** — rows gated (owner: Configurer/Vérification/Mes données ·
  profile.manage: Profil du salon · catalogue.manage: Photos, Avant/Après ·
  members.manage: Équipe · subscription.manage: Abonnement · deposit.manage:
  Acompte); members get a personal header card (name/email, « Salon » row,
  `TeamRoleChip`).
- **Staff shell** — `/pro/staff`: `IndexedStack` + `NavigationBar`
  (Journée · Calendrier · Profil). Journée = the journal screen in own-mode
  (locked artist filter, chips/FAB hidden, gap rows inert, actions Terminé /
  Non présenté only, header « {salonName} — votre planning »); Calendrier = the
  appointment list (server-filtered); Profil = the slim personal profile.
  Splash/login route staff to `/pro/staff`.
- **Revoked handler** — `ProAccessGuard.report(code)` from provider error
  branches → single-flight probe of `getMyProvider()` → `not_a_member` →
  logout + `/pro/login` with « Votre accès à {salonName} a été retiré. ».
- **Mock role simulation** — member accounts seeded (manager `awa.manager@`,
  réception `fatou.reception@`, staff `sonia.staff@` on artist1); mock
  `getMyProvider` derives membership from the roster; role-aware mock
  dashboard/journal/list. providerId is NEVER stamped on member accounts
  (it means salon ownership).

## 4. API & contract (R4a changes)

`/me/provider` 200 `required: [account, provider, membership]` + new
`Membership` schema (`role` enum owner|manager|reception|staff ·
`capabilities: string[]` sorted · `artistId?` · `artistName?`); 403 documents
`not_a_member` vs `forbidden`. Journal + appointments descriptions note the
own-scope filtering and off-day phone masking. Web `gen:api` regen rides R4a.

## 5. Security & authz

- T40 flips to **Implemented**: own-scope is enforced **server-side** by the
  member's `artist_id` (never client-supplied); cross-artist transitions 403;
  REQUIRED negative tests land with the slice.
- T39 hardening: off-day contact masking minimizes staff-visible client PII.
- The revoked signal (`not_a_member`) is only a UX courtesy — revocation is
  already effective per-request (T38).

## 6. Testing

R4a: membership payload per role (owner/manager/staff+artistName/bare-active/
bare-revoked→not_a_member) · own day view (filter, artists narrowed, phone
same-day vs off-day, null-artistId 403, réception full) · transitions (own
complete/no-show OK, foreign 403, accept/reject/arrive 403 for staff) · list
own-filter + masking · dashboard staff 403 · maskContactsOffDay unit tests.
R4b: membership model/session round-trip (incl. legacy JSON), can() fallbacks,
revoked flow, mock role sim; widget suites per role (dashboard/profil/staff
shell/revoked message); existing 472 stay green.

## 7. Rollout

R4a first (contract + enforcement — additive for the app, own-scope only
affects staff tokens which no live client uses yet), then R4b. Docs (this spec,
module §10 A3, BACKEND.md T39/T40, ROADMAP) ride their respective PRs.

## 8. Open questions

None — layout (staff tabs), masking rule, and `not_a_member` semantics were
decided at sign-off.
