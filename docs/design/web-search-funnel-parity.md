# Web search + booking-funnel parity (P2a — audit 2.1 / 2.2 / 2.10 / 2.11 / 3.2)

**Status:** Built (PR fix/parity-p2a-search-funnel) · **Audit:**
[parity-audit-modules-2026-07.md](parity-audit-modules-2026-07.md) modules 2 + 3 ·
**Contract:** unchanged — `sort`/`availableToday` on `GET /providers`, `notes`
on `POST /appointments` and `durationVariants` on the service DTOs all
pre-existed. **No backend change.**

## Goal & scope

Five web funnel/UX gaps the app already covers:

1. **2.1 « Trier »** — `/recherche` gets the app's sort control
   (`ProviderSort`): **Pertinence · Mieux notés · Prix croissant** as a select
   next to the category chips. SSR: the choice lives in `?sort=` and the page
   refetches server-side (chips already navigate this way). Default =
   `relevance` (the app's default; the page previously hardcoded `rating`).
   Home/landing callers keep their explicit `rating`.
2. **2.2 « Disponible aujourd'hui »** — a one-tap toggle pill (`?dispo=1`)
   riding the existing `availableToday` query param. Active state styled like
   a selected chip.
3. **2.10 booking notes** — the confirm step gains « Notes (optionnel) » (the
   app's field), sent as `notes` through the booking BFF (which now forwards
   it); salons already see notes in the journal.
4. **2.11 mobile-web sticky bar** — on `<lg` the hub's summary becomes the
   app's pinned bottom bar: fixed Total (+ durée) « Confirmer » strip; the
   desktop sticky aside is unchanged (`hidden lg:block` / `lg:hidden` pair);
   the hub gets bottom padding so content never hides behind the bar.
5. **3.2 duration variants** — the web service form gains the app's
   « Durée selon la longueur de cheveux » toggle revealing three minute
   fields (Court / Moyen / Long). Payload semantics mirror the app exactly:
   toggle off → `{}` (clears), on → only the filled keys. The web booking hub
   already renders variants (K2) — salons just couldn't author them on web.

## States & edge cases

- Search controls preserve `q`/`commune`/`category` (and each other) in every
  navigation; the empty-results copy is unchanged.
- Notes: optional, textarea, trimmed; empty → omitted from the payload.
- Sticky bar renders only in the hub phase (confirm/done keep their layouts)
  and only under `lg`; disabled state mirrors `canConfirm`.
- Variants inputs accept blanks (omitted); no new validation (the app allows
  an empty variant map).

## Tests

- **Unit:** `buildServicePayload`/`serviceToForm` variant round-trips
  (off → `{}`, partial → filled keys only).
- **e2e:** /recherche — sort to « Mieux notés » → `?sort=rating` + list still
  renders; « Disponible aujourd'hui » → `?dispo=1` (CARTO tiles aborted as
  everywhere). Booking — mobile viewport: the fixed bar confirms the funnel;
  confirm step: fill « Notes (optionnel) ». Catalogue — toggle variants +
  fill Court.
