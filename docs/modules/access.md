# Module: Team access (RBAC) — `access`

| | |
|---|---|
| **Module** | `access` — [docs/MODULES.md](../MODULES.md) §11 |
| **YCLIENTS analog** | Пользователи и доступ (users & access) — preset roles seeding a rights matrix |
| **Status** | **Module doc written** (2026-07-07) — awaiting sign-off; build is a V2 slice (triggered by the first real salon asking for staff logins, or the staff-seats add-on) |
| **Depends on** | Pro auth overhaul (✅ P4, PRs #166–#172) — email/Google identity, invitations ride on it · `catalogue` artists (✅) |
| **Feeds** | `clients` (access audit) · `payroll` (staff↔artist link) · `network` (multi-salon memberships) · staff-seats monetization (PRD §226) |
| **Decisions locked (2026-07-07 discussion)** | Preset roles, NOT a custom role builder (market-validated: Booksy/Fresha/YCLIENTS all preset-first) · capability-based enforcement · per-request resolution (instant revocation) · YCLIENTS's Specialist↔employee auto-link copied verbatim · override matrix deferred to V3 |

## 1. Vision & YCLIENTS reference

Today one salon = one login (the owner). This module turns the salon into a
**team**: the owner invites members by email, each member gets their own login
(Google / email OTP — never shared credentials), and what a member sees and does
is governed by a **preset role**. It must feel like YCLIENTS's user management
— assign a role, sensible rights apply automatically, a specialist sees only
their own day — but **configured in three taps on a phone**, not a desktop
rights matrix (our market: no trained receptionists, no Academy).

What we copy from YCLIENTS:
- **Role presets auto-apply recommended rights** (their «рекомендованные права
  будут выставлены в соответствии с ролью»).
- **Specialist ↔ employee-record binding**: a Collaborateur's login is linked to
  an artist record at invite time → "my calendar only" works with zero config.
- **Client-data access tracking** (YCLIENTS and Booksy both log staff reads of
  the client base) — a real selling point: « votre fichier client ne part pas
  avec un employé ».

What we deliberately do NOT copy (yet):
- The per-user rights **matrix UI** — V3, exposed only when modules multiply
  (inventory, payroll, finances) give it something to control. The *storage*
  for it ships in V2 (sparse overrides), so V3 is a settings screen, not a
  migration.
- Login+password — our identity layer (Google / email OTP) is strictly better.

## 2. Roles & capabilities

### 2.1 The capability list (the unit of enforcement)

Routes NEVER check a role name — they check a capability. Presets are a
server-side `role → Set<Capability>` map in **one file**.

| Capability | Governs |
|---|---|
| `journal.view.all` | See the whole salon's bookings/calendar |
| `journal.manage.all` | Accept/reject/cancel/complete/no-show/reschedule/manual-book for any booking |
| `journal.view.own` | See own (linked artist's) bookings only |
| `journal.manage.own` | Complete / no-show own bookings |
| `clients.view` | The salon client base (`clients` module) — **every read audited** |
| `catalogue.manage` | Services, artist records, media (gallery/before-after) |
| `availability.manage` | Salon hours, breaks, buffers |
| `profile.manage` | Salon public profile (PATCH /providers/{id} allowlist) |
| `finances.view` | Revenue figures (earnings, dashboard revenue card) |
| `deposit.manage` | Deposit policy settings (percentage, MoMo number) |
| `members.manage` | Invite / revoke / change roles (this module's own surface) |
| `subscription.manage` | Plan & billing |

New modules add capabilities (e.g. V3 `inventory.manage`, `payroll.view`);
members inherit sane defaults from their preset — this is why overrides are
stored as **sparse deltas**, never a materialized full list.

### 2.2 The presets

| Capability | **Propriétaire** | **Manager** | **Collaborateur** |
|---|---|---|---|
| `journal.view.all` / `manage.all` | ✅ | ✅ | — |
| `journal.view.own` / `manage.own` | ✅ | ✅ | ✅ |
| `clients.view` | ✅ | ✅ | — |
| `catalogue.manage` | ✅ | ✅ | — |
| `availability.manage` | ✅ | ✅ | — |
| `profile.manage` | ✅ | ✅ | — |
| `medias` (in `catalogue.manage`) | ✅ | ✅ | — |
| `finances.view` | ✅ | — | — |
| `deposit.manage` | ✅ | — | — |
| `members.manage` | ✅ | — | — |
| `subscription.manage` | ✅ | — | — |

- **Propriétaire**: exactly one per salon (the registering account). Cannot be
  revoked, demoted, or edited by anyone else (owner-protected actions).
  Ownership transfer = a dedicated, owner-initiated flow (V3, with re-auth).
- **Manager**: runs the salon day-to-day; sees no money figures, touches no
  settings that move money, cannot manage the team. (Mirrors Booksy's Manager
  minus finances; a V3 override can grant `finances.view` per person.)
- **Collaborateur**: REQUIRES an `artist_id` link at invite time. Their app is
  « ma journée » — own calendar, mark own bookings done. Nothing else.
- **Réception** (deferred preset): `journal.*.all` + `clients.view`, no
  catalogue/settings. Add only when a salon asks — three presets to start.
- **Effective capabilities** = preset ∪ grants − denies (overrides V3-editable,
  V2 rows always empty).

## 3. Data model

```sql
CREATE TABLE provider_members (
  id            TEXT PRIMARY KEY,
  provider_id   TEXT NOT NULL REFERENCES providers(id),
  account_id    TEXT REFERENCES provider_accounts(id), -- NULL while invited
  email         TEXT NOT NULL,                -- invitation key, lowercased
  role          TEXT NOT NULL,                -- 'owner' | 'manager' | 'staff'
  artist_id     TEXT REFERENCES artists(id),  -- REQUIRED when role='staff'
  status        TEXT NOT NULL,                -- 'invited' | 'active' | 'revoked'
  grants        JSONB NOT NULL DEFAULT '[]',  -- V3 overrides (sparse)
  denies        JSONB NOT NULL DEFAULT '[]',
  invited_by    TEXT,                         -- member id of the inviter
  invited_at    TIMESTAMPTZ NOT NULL,
  accepted_at   TIMESTAMPTZ,
  revoked_at    TIMESTAMPTZ,
  UNIQUE (provider_id, email)
);
-- + partial unique: one active owner per provider
-- + index on (account_id, status), (provider_id, status)
```

- **Migration**: for every existing provider account, insert an `owner` row
  (`status=active`, email from the account). `provider_accounts.provider_id`
  stays during transition as a derived convenience; **memberships become the
  source of truth** for "which salon(s) does this account act for".
- **Multi-salon ready**: nothing above is 1:1 — one account may hold
  memberships in several salons (`network` module later). V2 UX assumes one
  (no salon switcher yet); the API already returns a list.

## 4. Authorization mechanics

- **JWT unchanged** (`role=provider`, sub=account id). The salon-role is
  **resolved per request** from the active membership row — firing someone is
  effective on their very next request, no stale-token window (15-min tokens
  would otherwise keep a revoked member inside).
- One shared middleware helper replaces today's `account.providerId` lookup:
  `membershipOf(principal, providerId) → (member, capabilities)` — deny by
  default; `status != active` → 403 `not_a_member`.
- **Capability check** = one line per route: `requires(caps, 'catalogue.manage')`
  → 403 `capability_required` (machine code; FR message app-side).
- **Own-scope enforcement**: `journal.*.own` filters by the member's
  `artist_id` **server-side** (client never passes it).
- **Field-level gating**: dashboard/earnings responses **omit** revenue fields
  when the caller lacks `finances.view` (UI hides the card when absent —
  four-states rule: absence is a valid state, not an error).
- **Audit**: reuse the admin `audit_log` pattern → `member_audit` events:
  invite / accept / revoke / role-change / **clients.view reads** (actor member
  id, target, timestamp). Owner-visible screen in V3; stored from day one.

## 5. UX — complete flows (pro app first, web pro mirrors)

### 5.1 Owner: Équipe (new screen, `screens/provider/team/`)

Entry: pro Profil → « Équipe » (icon `group`). States: loading (BrandLoader) /
empty / error / list.

- **Empty state**: illustration + « Invitez votre équipe » + copy: « Chaque
  membre a son propre accès. Les collaborateurs ne voient que leur propre
  planning. » CTA « Inviter un membre ».
- **List**: member rows — avatar initials, name/email, chip role
  (« Propriétaire » gold · « Manager » black · « Collaborateur » outline),
  linked artist name for staff, status badge « Invitation envoyée » for pending.
  Owner row pinned first, no actions on it.
- **Invite flow (bottom sheet, 3 steps in one sheet)**:
  1. E-mail (validated, lowercased; duplicate → « Cette personne est déjà dans
     l'équipe »).
  2. Rôle — two cards with plain-French capability summaries: Manager: « Gère
     les rendez-vous, le catalogue et les disponibilités. Ne voit pas les
     revenus. » · Collaborateur: « Voit uniquement son propre planning. »
  3. If Collaborateur → « Associer à un membre de l'équipe » (artist picker;
     required; offer « + Créer une fiche » inline if the artist record doesn't
     exist yet).
  Submit → « Invitation envoyée à {email} » snackbar; branded invitation email
  (Resend, same template family as OTP): « {Salon} vous invite à rejoindre son
  équipe sur MyWeli Pro ».
- **Member actions** (sheet on tap): « Changer le rôle » (owner-only,
  confirmation) · « Renvoyer l'invitation » (pending only, resend-budget
  applies) · « Révoquer l'accès » (destructive confirm: « {Name} perdra
  immédiatement l'accès à {Salon}. Son compte MyWeli n'est pas supprimé. »).
- **Seats**: banner when > included seats (launch: owner + 2 free) —
  « Sièges supplémentaires » hooks the subscription add-on (billing deferred
  like the rest of `finance`; the gate ships OFF via config until pricing).

### 5.2 Invitee: joining WITHOUT creating a salon (critical path)

The pro login is LOGIN-ONLY and register creates a *salon* — an invited staff
member must do neither. The invitation bridges it:

1. Invitee gets the email → opens MyWeli Pro (store link in the email) →
   signs in with **Google or email code** (the normal login screen).
2. Backend: identity verified, **no provider account** → BEFORE returning
   `provider_not_found`, check pending invitations by **verified email**.
   Match → `202 { invitations: [...] }` (a new lightweight response).
3. App shows « Invitations » step: card « {Salon} vous invite comme
   {Rôle} » → « Rejoindre » → account auto-created (no business fields),
   membership `active`, session issued → lands on the role-appropriate home.
   « Refuser » → invitation declined (owner sees it).
4. No pending invitation → today's behavior (`provider_not_found` → « Créer un
   compte » = register a salon). An account holding BOTH a salon and
   memberships is fine (model supports it).

### 5.3 The member experience (role-shaped app)

- **Manager**: identical pro app minus — no Revenus card (field absent), no
  Acompte/Abonnement/Équipe in Profil (entries hidden by capability, and the
  routes 403 anyway — UI gating is convenience, server is authority).
- **Collaborateur**: the app **reshapes**: home = « Ma journée » (own
  appointments timeline), tabs reduced to Journée · Calendrier (own) · Profil
  (personal only: name, avatar, logout). Actions on a booking: « Terminé » /
  « Non présenté ». Copy grounds the boundary: header shows « {Salon} — votre
  planning ».
- **Revoked mid-session**: next API call 403 `not_a_member` → global handler
  signs out with « Votre accès à {Salon} a été retiré. » (no dead-end screens).

### 5.4 Web pro parity

Same flows on `/pro/equipe` (list, invite modal, actions) and the invitation
step in `/pro/connexion`; Collaborateur web = own-calendar view. Ships in the
same V2 slice (web parity rule).

## 6. API slice (contract sketch — the build slice locks DTOs in openapi.yaml)

| Endpoint | Cap | Notes |
|---|---|---|
| `GET /me/provider/members` | `members.manage` | list incl. pending |
| `POST /me/provider/members` | `members.manage` | `{email, role, artistId?}` → 201 invited; 409 `member_exists`; invite rate-limit → 429 |
| `PATCH /me/provider/members/{id}` | `members.manage` | role/artist change; owner row → 403 `owner_protected` |
| `POST /me/provider/members/{id}/revoke` | `members.manage` | idempotent |
| `POST /me/provider/members/{id}/resend` | `members.manage` | resend budget shared with email-OTP mechanics |
| `GET /me/provider/invitations` | (any pro identity) | pending invites for the caller's verified email |
| `POST /me/provider/invitations/{id}/accept` | — | creates account if needed → returns ProviderSession |
| `POST /me/provider/invitations/{id}/decline` | — | |
| Login change | — | verified identity + no account + pending invites → `202 {invitations}` instead of 404 |

Existing pro endpoints: swap `account.providerId` for the membership helper +
per-route capability. **Contract updates in the same PR as the code** (rule).

## 7. Security & threat-model deltas (add to BACKEND.md §7 at build)

| # | Asset / surface | Threat | Mitigation |
|---|---|---|---|
| T36 | Membership roles | **E** — member self-escalates / edits owner | `members.manage` = owner-only at V2; owner row immutable to others (`owner_protected`); role changes audited |
| T37 | Invitations | **S/DoS** — invite spam; inviting a victim email to phish | Invite rate-limit per salon/day; invitee must explicitly accept after authenticating the email (invitation ≠ access); revocable; audited |
| T38 | Session vs revocation | **E** — fired member keeps 15-min token | Membership resolved **per request** (never cached in the JWT) → revocation immediate |
| T39 | Client base | **I** — staff scrapes/export the client file | `clients.view` capability + every read audited (`member_audit`); export owner-only when `clients` ships |
| T40 | Own-scope | **T** — staff reads colleagues' bookings by id | `journal.*.own` filtered by server-resolved `artist_id`; cross-artist → 403; REQUIRED negative tests |

Standard gates apply: deny-by-default, boundary validation (email, role enum,
artist ownership — the artist must belong to the same salon), no enumeration
(invitation responses don't reveal whether the email has a MyWeli account),
structured logs without PII.

## 8. Performance

Membership resolution adds one indexed lookup per pro request — cache the
`(account_id, provider_id) → member` row per-request (context), not
cross-request (revocation immediacy is the point). Capability math is in-memory
set ops. No new N+1: member list joins artists in one query. Budgets unchanged.

## 9. Testing (REQUIRED, per backend guardrails)

- Unit: preset maps (exact table §2.2), effective-caps (grants/denies),
  membership resolution incl. revoked/invited.
- Handler: every new endpoint success + 401/403/404/409/429 + 405.
- **Security negatives**: T36–T40 each (staff→manager endpoint 403; revoked →
  403 next request; cross-artist 403; owner-protected 403; invite flood 429;
  cross-salon artist link 400/403).
- Contract tests vs openapi.yaml; app: mock realism (latency/error/pagination),
  provider tests for the new ProTeamProvider, widget tests (Équipe list/empty/
  invite sheet; « Ma journée » for staff), e2e web (invite → accept → role-shaped
  dashboard on the stub API).

## 10. Rollout & phasing

| Slice | Contents | Phase |
|---|---|---|
| A1 | Migration + membership model + middleware swap (owner-only behavior unchanged — pure refactor, zero UX change) | V2 opener (low-risk, can ship early) |
| A2 | Invites + accept flow + Équipe screens (app + web) + presets enforcement + audit + tests | V2 core |
| A3 | Collaborateur « Ma journée » app reshape + web own-calendar | V2 |
| A4 | Seats gate (config-off until pricing) | V2, flag-hidden |
| A5 | Override matrix UI + Réception preset + owner transfer + audit viewer | V3 |

Each slice still gets its `docs/design/` spec + sign-off before code (rule).

## 11. Open questions (to resolve at build sign-off)

1. Included free seats: owner + 2 proposed — confirm number at pricing time.
2. ~~Does a Collaborateur see client contact details on their OWN bookings?~~
   **Resolved (2026-07-08, clients §11.2): yes — name + phone on own bookings
   of the SAME DAY only; masked elsewhere; the full base stays behind
   `clients.view` (audited).**
3. Invitation TTL (proposed 7 days, resendable) — confirm.
4. Manager + `finances.view` demand — decide only from real salon feedback,
   as a V3 override, not a preset change.
