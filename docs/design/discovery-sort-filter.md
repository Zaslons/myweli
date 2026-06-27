# Discovery sort & filter (FR-DISC-007)

| | |
|---|---|
| **Requirement** | FR-DISC-007 (sort & filter: rating, price, availability, commune, home-service) |
| **Phase** | Phase 3 — backend build + integration (discovery) |
| **Status** | Spec; building. PR1 backend · PR2 app. |
| **Decision** | Sort (Pertinence / Mieux notés / Prix croissant) **+ "Disponible aujourd'hui"** (signed off 2026-06-27). Commune already shipped. **À domicile = V2** (deferred — no model field). |

## 1. Goal & scope
Let consumers **sort** the provider list and filter to salons **available today**.
Commune is already a first-class facet. Home-service ("à domicile") is **V2** and
out of scope (the model has no home-service flag; à-domicile is deferred).

## 2. Endpoint — `GET /providers` (additive params)
- `sort`: `relevance` (default) | `rating` | `price`.
  - **relevance** — featured first, then rating (the repository's existing order).
  - **rating** — rating desc.
  - **price** — by **min active service price** asc; salons with no priced
    service sort last.
- `availableToday`: `true` → keep only salons with **≥1 free slot today** (future
  times), computed via the existing `SlotService`.
- Existing `q` / `commune` / `category` / `page` / `pageSize` unchanged.

Order of operations in the route: `query` → (optional) **availableToday filter**
(via `SlotService`) → **sort** → paginate. (Filtering before paging keeps `total`
correct.)

## 3. Impl / layering
- **`sortProviders(list, sort)`** — a **pure** function in `lib/src/provider_discovery.dart`
  (unit-tested): relevance (identity), rating desc, price asc (min service price,
  no-price → last). No SQL/`dart_frog`.
- **Route** (`routes/providers/index.dart`) — reads the two params; when
  `availableToday`, filters `all` via `SlotService.availableSlots(providerId,
  today)` (`slots` non-empty); then `sortProviders`; then paginates. `SlotService`
  is already in the request context.
- **No repository change** — the repo keeps returning relevance order; sort +
  filter compose in the route over the full matched set.

## 4. Performance
`availableToday` runs one slot computation per **matched** provider (before
paging). Fine at V1 commune scale (tens of salons); if the matched set grows,
add a cheap "open today?" pre-check or cache. Documented as a known cost.

## 5. App (PR2)
- `ProviderProvider`: `sort` + `availableToday` state; `getProviders(sort,
  availableToday)` through the interface → API + mock.
- Filter bar: a **"Trier"** pill → a "Trier par" bottom sheet (radio: Pertinence
  / Mieux notés / Prix croissant) + a **"Disponible aujourd'hui"** toggle chip.
  Re-query on change; reuse the empty/loading/error states. Tokens, French.
- Mock: sort + `availableToday` applied client-side over the mock providers
  (mock availability already exists) so demo mode behaves like the API.

## 6. Tests
- `sortProviders`: rating desc · price asc (min service price; no-price last) ·
  relevance = identity.
- Route: `sort=rating`/`price` order; `availableToday=true` filters out a salon
  with no slots today (injected providers + `SlotService`); paging + `total`.
- App: provider state forwards `sort`/`availableToday`; the sheet/toggle re-query.

## 7. Rollout
Pure feature, flag-free, no migration. Defaults (`relevance`, no availability
filter) keep the current behaviour unchanged.
