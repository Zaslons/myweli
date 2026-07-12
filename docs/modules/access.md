# Module: Team access (RBAC) — `access`

> **Build sign-off 2026-07-11 (user):** promoted from V2 to **pre-launch**.
> Decisions locked:
> - Invitation TTL **7 days**, resendable · **four presets** (Réception ships
>   now) · go-live/unpublish stays **owner-only**.
> - **Pricing pivot (supersedes the PRD freemium):** no free operating tier.
>   Registration lands in a free, time-unlimited **SETUP state** (build the
>   fiche/catalogue — salon unpublished, no bookings, no team). Publishing
>   requires an active offer: **Pro (5 places) · Business (15) · Réseau
>   (multi-salons, per-salon custom pricing « Nous contacter »)** — final
>   ladder 2026-07-11 (Solo dropped; Pro is the entry point — revisit its
>   price with the solo segment in mind). Seats count owner + active +
>   invited; picking an offer starts its **3 mois offerts** (one trial per
>   salon). **Offers/trials hang on the SALON, not the account** (multi-salon
>   ready from R2). Prices = config/display copy (« à confirmer »; billing
>   stays « Nous contacter », no custody).
> - **Expiry:** warnings J-14/J-7/J-1 → **7 jours de grâce** → the salon is
>   **UNPUBLISHED** (no new bookings; the app, journal, existing bookings and
>   data export all keep working — never a data lockout) → admin marks the
>   manual payment → republished. Enforcement **config-driven** (lenient
>   during the cold-start). Team invites require an active offer.
> - Existing salons at migration: grandfathered with a fresh 3-month trial.
>
> Slices R1–R6 (see §10); R2 carries the offer selection + expiry mechanics +
> the admin « marquer payé / prolonger » action. **R6 (pre-launch, after R5)
> = multi-salons**: the « Mes salons » switcher (app + web), « Ajouter un
> salon » (Réseau-gated; each new salon = own setup state / offer / trial /
> publish gate), verified-badge inheritance from the account's KYC, deletion
> unpublishes ALL owned salons. Data is already per-salon (`provider_id`
> everywhere); memberships are per (account, salon) — no data-splitting work.
> Cross-salon consolidated reporting + shared client files stay V3.

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
| `salon.publish` | Take the salon live / unpublish (sign-off 2026-07-11: owner-only) |

New modules add capabilities (e.g. V3 `inventory.manage`, `payroll.view`);
members inherit sane defaults from their preset — this is why overrides are
stored as **sparse deltas**, never a materialized full list.

### 2.2 The presets

| Capability | **Propriétaire** | **Manager** | **Réception** | **Collaborateur** |
|---|---|---|---|---|
| `journal.view.all` / `manage.all` | ✅ | ✅ | ✅ | — |
| `journal.view.own` / `manage.own` | ✅ | ✅ | ✅ | ✅ |
| `clients.view` | ✅ | ✅ | ✅ | — |
| `catalogue.manage` | ✅ | ✅ | — | — |
| `availability.manage` | ✅ | ✅ | — | — |
| `profile.manage` | ✅ | ✅ | — | — |
| `medias` (in `catalogue.manage`) | ✅ | ✅ | — | — |
| `finances.view` | ✅ | — | — | — |
| `deposit.manage` | ✅ | — | — | — |
| `members.manage` | ✅ | — | — | — |
| `subscription.manage` | ✅ | — | — | — |
| `salon.publish` | ✅ | — | — | — |

- **Propriétaire**: exactly one per salon (the registering account). Cannot be
  revoked, demoted, or edited by anyone else (owner-protected actions).
  Ownership transfer = a dedicated, owner-initiated flow (V3, with re-auth).
- **Manager**: runs the salon day-to-day; sees no money figures, touches no
  settings that move money, cannot manage the team. (Mirrors Booksy's Manager
  minus finances; a V3 override can grant `finances.view` per person.)
- **Collaborateur**: REQUIRES an `artist_id` link at invite time. Their app is
  « ma journée » — own calendar, mark own bookings done. Nothing else.
- **Réception** (sign-off 2026-07-11: ships NOW): the front desk — the whole
  journal + the fichier clients, no catalogue/settings/money. `role='reception'`.
- **Effective capabilities** = preset ∪ grants − denies (overrides V3-editable,
  V2 rows always empty).

### 2.3 Post-design drift (verified 2026-07-11 — the build handles these)

1. **Salon self-provisioning** (lifecycle program, 2026-07-10):
   `GET /me/provider` auto-creates a draft salon for accounts without one.
   Guard: provision ONLY when the account holds **no membership anywhere**;
   members resolve their salon via the membership row.
2. **Account deletion T53** (PR #221): deleting an account must also revoke
   its memberships; an OWNER's deletion takes the staff memberships down with
   the salon; a member's own deletion touches nothing salon-side.
3. The ownership checks to swap live in ~7 services (catalog, dashboard,
   earnings, journal, clients, appointments, provisioning) — the
   `membershipOf()` refactor is contained.
4. The table below says `provider_accounts`; the real table is
   **`provider_users`**.
5. The login bridge (`202 {invitations}`) has THREE identity routes to touch:
   google, email-OTP verify, phone-OTP verify (dormant).

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
  *Build note (R4a): deferred — capability misses return the uniform
  `forbidden`; the only distinct code is `not_a_member` on `GET /me/provider`
  (the revoked-mid-session signal). Revisit if a client ever needs to tell
  the two apart per-route.*
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

> **Built (R5a+R5b, 2026-07-12 — docs/design/web-team-access-r5.md).** Notes
> locked at build: the web member Profil is the SLIM personal view (identity +
> role chip + salon + « Supprimer mon compte » — deletion parity for all;
> the salon-data export stays `profile.manage`); the web `not_a_member`
> probe cadence = every navigation (the membership context re-fetches
> `/api/pro/me` per pathname change).

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
| A1/R1 | ~~Migration + membership model + middleware swap (owner-only behavior unchanged — pure refactor, zero UX change)~~ ✅ done 2026-07-11 (PR feat/team-access-r1-foundation; + the provisioning guard, deletion revocation and `salon.publish`) | pre-launch |
| A2/R2 | Invites + accept flow + presets enforcement + audit + tests — **R2a (offers/seats server side) ✅ 2026-07-11 · R2b (invitations API + login bridge) ✅ 2026-07-12 · R3 (pro APP: Équipe screen, login « Invitations » step, offer picker, publish-gate mirror) ✅ 2026-07-12** (docs/design/team-access-r3-app.md); web screens **R5a ✅ 2026-07-12** | pre-launch |
| A3/R4 | Role-shaped experience ✅ — **R4a (backend: membership-aware /me/provider + `not_a_member` + T40 own-scope enforcement w/ off-day contact masking) ✅ 2026-07-12 · R4b (app: role-gated dashboard/profil, the Collaborateur « Ma journée » 3-tab shell, revoked-mid-session sign-out, mock role demos) ✅ 2026-07-12** (docs/design/team-access-r4-role-shaped-app.md); web own-calendar **R5b ✅ 2026-07-12** (docs/design/web-team-access-r5.md — **the R5 web-parity pair is complete**) | pre-launch |
| A4 | Seats gate (config-off until pricing) | V2, flag-hidden |
| A5/R6 | **Multi-salons** (pre-launch, sign-off 2026-07-11): switcher + « Ajouter un salon » + Réseau gating + badge inheritance — **R6a (backend: the `?salonId=` selector via `salonForRequest`, GET/POST /me/salons, KYC badge fan-out, deletion across all owned salons; threat T55) ✅ 2026-07-12 · R6b (app: the « Mes salons » switcher — tappable dashboard header + Profil row + picker sheet —, `ProSalonScope` per-salon state reset, session-persisted selection w/ silent per-salon-403 fallback, « Ajouter un salon » flow → onboarding, the 15-screen `activeSalonId` sweep) ✅ 2026-07-13 · R6c (web: the sidebar « Mes salons » switcher, the validated `myweli_pro_salon` httpOnly cookie + BFF `?salonId=` threading, the switch-epoch page remount, /pro/salons/nouveau + the Réseau CTA) ✅ 2026-07-13 — **A5/R6 COMPLETE; the team-access module is fully built (R1→R6) across backend, app and web** | pre-launch |
| A6 | Override matrix UI + owner transfer + audit viewer | V3 |

Each slice still gets its `docs/design/` spec + sign-off before code (rule).

## 11. Open questions (to resolve at build sign-off)

1. ~~Included free seats~~ **Resolved (2026-07-11, superseded same day by
   the pricing pivot): Solo 1 / Pro 5 / Business 15 (active+invited incl.
   owner); 3 mois offerts per offer; expiry → grace → unpublish (see the
   sign-off block).**
2. ~~Does a Collaborateur see client contact details on their OWN bookings?~~
   **Resolved (2026-07-08, clients §11.2): yes — name + phone on own bookings
   of the SAME DAY only; masked elsewhere; the full base stays behind
   `clients.view` (audited).**
3. ~~Invitation TTL~~ **Resolved (2026-07-11): 7 days, resendable.**
4. Manager + `finances.view` demand — decide only from real salon feedback,
   as a V3 override, not a preset change.
