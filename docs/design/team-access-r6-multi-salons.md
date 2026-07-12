# Team access R6 — multi-salons (« Mes salons », « Ajouter un salon », badge & deletion fan-out)

| | |
|---|---|
| **Status** | R6a Built (2026-07-12) — R6b (app) next |
| **Owner** | Sadreddine |
| **Last updated** | 2026-07-12 |
| **PRD ref / phase** | Module `access` §10 slice A5/R6 (sign-off 2026-07-11) · pre-launch |
| **ROADMAP entry** | docs/ROADMAP.md — « Team access R6a / R6b / R6c » |
| **Skills checked** | myweli-backend-guardrails (R6a) · myweli-dev-guardrails (R6b) · myweli-web-guardrails (R6c) |

## 1. Goal & scope

R1–R5 shipped the team program; every piece of data already hangs on a
`provider_id` and memberships are per (account, salon). R6 removes the LAST
single-salon assumption and ships, in three PRs:

- **R6a (backend)**: the explicit salon selector (`?salonId=`), the
  « Mes salons » directory (`GET /me/salons`), « Ajouter un salon »
  (`POST /me/salons`, Réseau-gated), KYC verified-badge fan-out across all
  owned salons (both directions), account deletion gating/unpublishing ALL
  owned salons.
- **R6b (Flutter pro app)**: the salon switcher (tappable dashboard header +
  « Mes salons » Profil row + bottom-sheet picker), per-salon state reset on
  switch, the add-salon flow (Réseau card CTA → form → switch → onboarding),
  the `providerId` bypass sweep.
- **R6c (web)**: the sidebar switcher, the `myweli_pro_salon` cookie + BFF
  `?salonId=` threading (16 page clients salon-aware with zero per-page
  edits), `/pro/salons/nouveau`, per-salon stub state + e2e.

**User decisions (2026-07-12):** three sequential PRs · Réseau gate = the
account owns ≥1 salon with a LIVE (trial/paid/grace) Réseau offer · the
switcher lists ALL memberships (owned + member; each salon renders that
salon's role shape) · app switcher = tappable header + Profil row; web = the
sidebar salon block.

Out of scope (V3, per the sign-off): cross-salon consolidated reporting,
shared client files, the override matrix, owner transfer.

## 2. The selection model (D1)

**One primitive** replaces the implicit-salon resolution:
`MembershipService.salonForRequest(accountId, {salonId?})`:

- `salonId` **present** → `memberOf(accountId, salonId)` must return an
  ACTIVE membership (incl. the legacy linked-owner self-heal). No match →
  `null` → the route answers a **uniform 403 `forbidden`** — never-member,
  revoked-there, and nonexistent are indistinguishable (no
  membership-existence oracle, threat T55). Explicit selection never
  auto-provisions.
- `salonId` **absent** → the legacy fallback (`activeSalonFor`: the scalar
  `provider_users.provider_id`, else the first active membership). **100 %
  backward compatible** — pre-R6 clients keep working unchanged.

**`not_a_member` stays RESERVED for the no-param fallback** on
`GET /me/provider` (memberships exist, none active): it is the SESSION-level
« votre accès a été retiré » sign-out signal. A per-salon denial must never
sign a user out of their other salons.

**Family B (implicit-salon) routes gaining the optional `?salonId=`:**
`GET /me/provider` · `GET/POST /me/provider/members` ·
`PATCH /me/provider/members/{id}` + `/revoke` + `/resend` ·
`GET /me/subscription` · `GET /appointments` (pro list) ·
`POST /appointments/{id}/reschedule` · `POST /uploads/sign` (gallery purpose).
`DELETE /me/provider` is account-level (ignores it);
`GET /me/provider/invitations` is email-keyed (unchanged). The
`/providers/{id}/*` family is already multi-salon-capable (per-request
`can(accountId, id, cap)`).

## 3. New endpoints & DTOs (D2/D3)

### GET /me/salons
`{ items: [SalonMembership], canAddSalon: bool }` — ACTIVE memberships only
(no revoked, no pending invitations), owned first then salonName
(case-insensitive), salonId tiebreak.
`SalonMembership = { salonId, salonName, role, salonStatus (draft|active|suspended), verified, imageUrl? }`.
`canAddSalon` is **server-computed** (clients never derive rights): the
account owns ≥1 salon whose offer is live Réseau AND owns < the cap.

### POST /me/salons (« Ajouter un salon »)
Body `{ businessName!, businessType!, phoneNumber?, address? }` (phone
defaults to the account's; type ∈ the registration enum — hoisted to one
source of truth). Flow: validate → gate → create the draft salon
(`createSalon`, slug-unique) → `ensureOwner` membership row → **badge
inheritance** (account `verificationStatus == 'verified'` → salon
`verified: true`) → 201 `{ salon: SalonMembership }`.
**Never touches `account.providerId`** (the scalar stays the default/fallback
salon). **No subscription row** — the new salon is in the free SETUP state;
its own offer (own fresh trial) gates publish & invites.
Errors: 401 · 403 `forbidden` (non-provider) · 403 **`reseau_required`** ·
409 **`salon_limit`** (`maxOwnedSalons = 20`, anti-abuse) · 400
`invalid_input`.

## 4. Fan-outs (D5/D6)

- **KYC (T52)**: `AdminKycService.approve/reject` now loops the owned set —
  {scalar `providerId`} ∪ {active owner membership rows} — writing
  `verified: true|false` on EACH owned salon. Member-only salons untouched.
  Creation-time inheritance (§3) covers salons added after approval.
- **Deletion (T53)**: `deleteAccount` gates `future_bookings` across ALL
  owned salons and unpublishes (status → draft) each. Membership rows still
  revoked via `revokeAllForAccount`; member salons untouched.

## 5. Security / threat model

- **T36 (revised)**: the acting salon DEFAULTS from the caller's membership;
  an explicit `?salonId=` is honored only against a per-request
  ACTIVE-membership check (`salonForRequest`) — a forged/revoked/unknown id
  is a uniform 403 `forbidden`.
- **T53 (revised)**: deletion gates + unpublishes across ALL owned salons.
- **T55 (new)**: cross-salon selection & creation — no membership-existence
  oracle; the Réseau gate and `canAddSalon` are server-computed; the salon
  cap bounds mass-creation; badge inheritance is server-side only.
- No migration: `provider_members` already allows N owner rows per account
  (UNIQUE is (provider_id, email)); `provider_subscriptions` PK is per-salon;
  latest migration stays `0029`.

## 6. Clients (R6b/R6c summaries — detail passes at build time)

- **App**: `_selectedSalonId` (persisted in the session store) overrides
  `activeSalonId`; `switchSalon` = persist + refresh membership + reset ALL
  ~15 per-salon providers + notify; per-salon 403 on a SELECTED salon →
  silent fallback to default (NO sign-out; `not_a_member` keeps the sign-out
  path). The bottom-sheet picker (commune-picker idiom) shows role chips +
  status badges + « Ajouter un salon » when `canAddSalon`. The Réseau offer
  card's « Multi-salons (bientôt disponible) » becomes the CTA. New-salon →
  switch → onboarding checklist (already stateless). The 15
  `provider?.providerId` bypass reads are swept to `activeSalonId`.
- **Web**: httpOnly `myweli_pro_salon` cookie set by a select BFF route;
  `callApiPro` appends `?salonId=` on family-B proxies so all 16 page clients
  become salon-aware with zero per-page edits; the sidebar salon block (all
  roles) is the switcher; `/pro/salons/nouveau` reuses the register business
  fields sans identity.

## 7. Testing

R6a: `salonForRequest` matrix (explicit active/self-heal/revoked/never/
unknown/absent-fallbacks/empty-string) · per-route `?salonId=` success +
forged → 403 + revoked-selected ≠ `not_a_member` · the directory (shape,
ordering, exclusions, `canAddSalon` matrix incl. Réseau-where-only-manager →
false) · add-salon (201 effects, badge inheritance both ways, every gate
negative, the cap, fresh-setup pins: publish missing `offer`, invite
`offer_required`, fresh trial on salon 2) · KYC fan-out (approve/reject, two
owned, member-only untouched) · deletion-all (gate across salons, both
unpublished, member salon untouched) · seats independence (invite into B
never consumes A's cap). Existing 465 stay green (the fallback IS the old
behavior). R6b/R6c: their own detail passes.

## 8. Rollout

R6a → R6b → R6c, each PR CI-green and user-merged before the next. The
backend ships dark (no client sends `salonId` until R6b/R6c). ROADMAP + the
module doc §10 refreshed per PR.

## 9. Open questions

None — the four scoping decisions were taken by the user at plan sign-off
(2026-07-12); everything else is carried from the 2026-07-11 module sign-off.
