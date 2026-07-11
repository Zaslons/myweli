# Pro account deletion + data export (audit 11.5 — the store-review requirement)

**Status:** Built (PR fix/pro-account-deletion-export) · **Audit:**
[parity-audit-modules-2026-07.md](parity-audit-modules-2026-07.md) module 11 ·
**Contract:** `DELETE /me/provider` added (204/401/403/409) ·
**Threat model:** new row (self-scoped destructive endpoint).

## Goal & scope

The last open audit item: salon accounts can delete themselves and export
their data on BOTH surfaces (AUTH-004/005 for pros — required before store
review). Mirrors the consumer flows adapted to salon semantics.

## Deletion — `DELETE /me/provider` (backend)

Provider-authenticated, self-scoped (the account and its salon come from the
token, never the client):

1. **Future-bookings gate** — pending/confirmed bookings in the future →
   **409 `future_bookings`**: the salon settles its agenda first (reject or
   complete from the journal). No surprise mass-cancellations of consumers'
   plans at launch.
2. **Unpublish, don't destroy, the salon** — `status → 'draft'`: T51 already
   hides drafts from discovery, by-slug, the sitemap and booking, while
   appointments/reviews/CRM keep resolving for consumers and the admin
   (referential integrity; the salon record is business history, the ACCOUNT
   is the identity being erased).
3. **Erase the identity** — new `ProviderAuthRepository.deleteAccount`:
   the `provider_users` row (KYC docs live on it), the email-OTP rows and
   EVERY refresh token of the account go; all sessions die. Private KYC
   storage objects are uuid-named and unreachable once the rows are gone
   (object deletion = deferred storage-lifecycle hardening, noted in T-row).

Errors: anon → 401 · non-provider/unlinked → 403 · future bookings → 409.

## Export — client-side assembly (both surfaces, no new endpoint)

Mirrors the consumer export design: the owner's existing scoped reads are
assembled into one JSON — profile + services + artists + hours + deposit
policy + the salon's appointments + the client base (the salon's own CRM
records) + earnings. App: an export screen with « Copier » (and share);
web: `/pro/profil` gains « Exporter mes données (JSON) » (download + copier).

## UX

- **App** (`pro_profile_screen`): « Mes données » row → the export screen;
  « Supprimer mon compte » (danger zone) → double-confirm dialog
  (« Cette action est définitive. Votre salon sera retiré de MyWeli. Pensez
  à exporter vos données avant. ») → 409 → « Terminez ou annulez vos
  rendez-vous à venir avant de supprimer votre compte. » → success → logout
  → login screen.
- **Web** (`/pro/profil`): a « Compte » danger section — export buttons +
  the type-SUPPRIMER confirmation (the consumer AccountClient pattern);
  BFF `DELETE /api/pro/account` clears the pro session cookies.

## Tests

- Backend: delete → 204, salon hidden from discovery/by-slug, account gone,
  refresh replay fails; future booking → 409; consumer token → 403;
  handler 401/405.
- App: widget — the danger flow (dialog → mocked service → logout routing);
  unit — the service seam.
- Web unit: export assembly; e2e — export button + type-SUPPRIMER flow →
  /pro/connexion (stub DELETE), 409 copy path.
