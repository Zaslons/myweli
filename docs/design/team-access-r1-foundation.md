# Team access R1 — the membership foundation (module `access`, slice A1)

**Status:** Built (PR feat/team-access-r1-foundation) · **Module doc:**
[modules/access.md](../modules/access.md) (sign-off 2026-07-11 recorded
there) · **Zero UX change** — after this slice every existing salon behaves
exactly as before; the machinery for R2 (invitations) is in place.

## Goal & scope

Introduce the membership layer the whole module stands on, and move every
tenant-ownership decision onto it — while the only members that exist are
the backfilled owners (full capabilities), so behavior is provably unchanged.

Out of scope (R2+): invitations, the login bridge, seat caps, any UI.

## Pieces

1. **Capabilities + presets** (`lib/src/access/capabilities.dart`) — the §2.1
   capability constants and the §2.2 four-preset map (Propriétaire / Manager /
   Réception / Collaborateur) in ONE file; `capabilitiesFor(role)`. Includes
   the new **`salon.publish`** (owner-only — the capability form of the
   "go-live is owner-only" sign-off; the publish route checks it).
2. **Membership model + repos** (`lib/src/access/membership_repository.dart`
   + `db/postgres_membership_repository.dart`) — the §3 row (with
   `provider_users` naming), InMemory + Postgres, resolution by
   `(accountId, providerId)` and `activeSalonFor(accountId)`.
3. **Migration `0027_provider_members`** — table + indexes +
   `UNIQUE (provider_id, email)` + **backfill**: one `role='owner'`,
   `status='active'` row per `provider_users` row with a linked salon.
4. **MembershipService** (`lib/src/access/membership_service.dart`) —
   `can(accountId, providerId, capability)` (deny by default, `active` only)
   and `activeSalonFor(accountId)`; resolved **per request**, never cached
   across requests (revocation immediacy, §4).
5. **Owner rows going forward** — `SalonProvisioningService` writes the owner
   membership when it links a salon (register + self-heal), idempotently.
6. **The provisioning guard** (drift §2.3-1) — `ensureSalon` provisions ONLY
   when the account holds no membership anywhere: an invited staff account
   (R2) must never get a salon auto-created.
7. **Deletion semantics** (drift §2.3-2) — `ProviderAccountService` revokes
   every membership of the account being deleted (owner or member).
8. **The ownership swap** — the `_owns(account.providerId == id)` idiom in
   catalog / dashboard / earnings / journal / clients services and the
   route-level `account.providerId` resolutions move onto
   `MembershipService.can(...)` with the RIGHT capability per operation
   (catalogue.manage, availability.manage, profile.manage, deposit.manage,
   finances.view, journal.view.all/manage.all, clients.view) — so R2+ adds
   roles without re-touching them. Dashboard/earnings revenue fields start
   respecting `finances.view` (field-level gating, §4) — invisible today
   since owners hold every capability.

## Tests (REQUIRED)

- Preset map == the §2.2 table, exactly (all four roles).
- Resolution: owner active → full caps · unknown/revoked/invited → deny.
- Guard: an account with a membership never triggers provisioning.
- Deletion revokes memberships.
- Every existing suite stays green (the zero-change proof).

## Threat model

No new endpoints. T36–T40 land with R2; this slice only re-plumbs existing
authorization onto the resolver (same deny-by-default posture).
