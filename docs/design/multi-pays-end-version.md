# Multi-pays — the end version, built (MP1 → MP2 → MP3) — program design spec

> The full activation of [modules/multi-pays.md](../modules/multi-pays.md):
> the locality tree becomes seeded DATA served by the API, the salon derives
> its timezone/currency/operator catalog from its locality, every surface
> renders in the salon's own timezone and currency, and the SEO landings move
> to the nested Planity tree with permanent redirects. After this program,
> **entering any market = seeding rows + the §8 checklist** — no code sweep.

| | |
|---|---|
| **Status** | **Approved — in build** (user decision 2026-07-14: build all four dimensions now, ahead of the wave triggers; nested URLs now; three PRs) |
| **Owner** | Sadreddine |
| **Last updated** | 2026-07-14 |
| **Module / phase** | `multi-pays` (cross-cutting) — supersedes the wave-gated §10 of the module doc |
| **Predecessor** | [timezone-salon-time.md](timezone-salon-time.md) (slice 1, Built — the seams this program threads values through) |
| **Slices** | **MP1** backend (`feat/multi-pays-mp1-backend`) → **MP2** mobile → **MP3** web — each green/mergeable alone |
| **Skills checked** | myweli-dev-guardrails · myweli-backend-guardrails · myweli-web-guardrails |

## 1. Goal & scope

**Goal:** make every market fact DATA. One authoritative locality tree
(country → city → area) seeded server-side; the salon points at an **area**
and the server derives — and owns — its `commune`/`city` display names,
`citySlug`, `countryCode`, **`timezone`** (from the city) and **`currency`**
(from the country). Clients fetch `GET /localities` for pickers, filters, SEO
landings and operator catalogs; they never hardcode a market fact again
(multi-pays §9 guardrail, already grep-pinned).

**In scope:** the four tables + seed (CI only), `GET /localities`, per-salon
timezone through ALL backend day-math + client display, per-salon currency
stamped on financial records + threaded through display, the per-country
Mobile-Money operator catalog (validation + rendering), `areaId` write paths
with legacy self-heal, the nested SEO landing tree with permanent redirects,
reserved-slug protection, contract + threat model.

**Out of scope:** any non-CI seed row (markets arrive as data per the module
doc's §8 checklist); i18n (francophone-only stands); admin locality-management
UI (changes are migrations reviewed like code — revisit when a second market
actually lands).

## 2. The data model (MP1)

Migration **`0030_localities_and_salon_market`** — reference tables only (no
`providers` columns; the five salon fields ride the `data` jsonb):

| Table | Columns |
|---|---|
| `countries` | `code` PK · `name` · `currency` · `phone_prefix` · `active` |
| `cities` | `id` PK · `country_code` FK · `name` · `slug` · `timezone` (IANA) · `lat` · `lng` · `active` · UNIQUE(country_code, slug) |
| `areas` | `id` PK · `city_id` FK · `name` · `slug` · `label_kind` (commune\|quartier\|arrondissement) · `lat` · `lng` · `active` · UNIQUE(city_id, slug) |
| `momo_operators` | `country_code` FK · `id` · `label` · `deep_link_kind` · `active` · PK(country_code, id) |

**Seed (CI):** `CI` (Côte d'Ivoire · XOF · +225) → operators `wave` (Wave,
deep_link_kind `wave`) · `orangeMoney` (Orange Money) · `mtnMoMo` (MTN MoMo) ·
`moov` (Moov Money) → city `abidjan` (Abidjan · `Africa/Abidjan` ·
5.336, −4.026) → the 11 communes (ids = slugs: cocody, marcory, plateau,
yopougon, treichville, adjame, abobo, koumassi, port-bouet, attecoube,
bingerville) with the centroids from the app's historical constants,
`label_kind = 'commune'`.

**Salon market fields** (in `data` jsonb, server-owned): `areaId`, `citySlug`,
`countryCode`, `timezone`, `currency` (+ the existing `commune`/`city` display
names now DERIVED from the area on any areaId write).
`backfillSalonMarketIfNeeded` runs at boot after the seed: for every provider
lacking `timezone`, slug-match `commune` → area (accent/case-insensitive via
`slug.dart`), set the five fields (areaId null on a miss — logged), idempotent.

**`GET /localities`** — public, parameterless, `Cache-Control: public,
max-age=3600`:

```json
{ "countries": [ { "code": "CI", "name": "Côte d'Ivoire", "currency": "XOF",
    "phonePrefix": "+225",
    "operators": [ { "id": "wave", "label": "Wave", "deepLinkKind": "wave" }, … ],
    "cities": [ { "id": "abidjan", "slug": "abidjan", "name": "Abidjan",
      "timezone": "Africa/Abidjan", "lat": 5.336, "lng": -4.026,
      "areas": [ { "id": "cocody", "slug": "cocody", "name": "Cocody",
        "labelKind": "commune", "lat": 5.36, "lng": -4.0083 }, … ] } ] } ] }
```

## 3. Timezone — per-salon, end to end (MP1 backend · MP2/MP3 display)

- Backend gains **`package:timezone`** and `lib/src/salon_time.dart`
  (`initSalonTime` idempotent + lazily guarded, `locationOf` with Abidjan
  fallback, `sameSalonDay`, `salonDayBoundsUtc`, `salonWallClockToUtc`,
  `salonDayKey`). Threaded through: the slot engine (the `?date=` calendar day
  IS the salon's day; slot instants = weekly-hour wall-minutes in the salon
  tz), the arrive `not_today` gate, journal `dayFor` + off-day contact
  masking, dashboard buckets, and the messaging templates (`{date}`/`{time}`
  render salon wall-clock). Admin analytics stays platform-UTC by design.
  **Bit-identical for `Africa/Abidjan` salons** — proven by the untouched
  existing suites; a Libreville (UTC+1) fixture proves the difference.
- Clients: the seam helpers gain/use a `tz` argument fed by
  `provider.timezone` (consumer: the viewed salon; pro: the active salon via
  the new `/me/provider` carrier). The `Africa/Abidjan` constants become
  fallbacks only. `SalonTimeHint`'s country label goes dynamic.
- Timezone stays **immutable self-serve** (derived on areaId writes;
  support-mediated once bookings exist — T57).

## 4. Currency — stamped + threaded (MP1 backend · MP2/MP3 display)

`providers.currency` derived from the country at creation/areaId-write;
appointments stamped `currency` at create; the earnings response carries
`currency`; the consumer appointment enrichment carries
`providerTimezone`/`providerCurrency`. Message bodies render « FCFA » for
XOF/XAF (fixing the hardcoded « XOF » label in `booking_notifier`). Clients
pass the salon's currency into the already-parameterized formatters.

## 5. Operators — catalog-driven (MP1 validation · MP2/MP3 rendering)

`momo_operators` per country; deposit-policy validation checks the salon
COUNTRY's catalog (identical behavior for CI's four); the OpenAPI operator
enum widens to `string` (wire values unchanged); clients render pickers,
labels and the Wave deep link from `deepLinkKind` — the client enum retires.

## 6. Geography on the clients (MP2 mobile · MP3 web)

- **Mobile:** new `LocalityServiceInterface` + Mock/Api + `LocalityProvider`
  (lazy fetch + cache, four states); the commune picker renders the tree
  (still RETURNS the name — the `?commune=` filter contract is unchanged);
  « Près de moi » resolves against area centroids from data; pro profile /
  registration / add-salon write `areaId`; `communes.dart` demotes to the
  mock seed.
- **Web:** `lib/api/localities.ts` (server-side, revalidate 3600); the
  hardcoded commune list dies; **nested landings** `/coiffure` →
  `/coiffure/abidjan` → `/coiffure/abidjan/cocody` (categories AND services),
  flat slugs `permanentRedirect` to nested (Next 308 ≡ 301 for SEO), sitemap
  emits the tree, 3-level breadcrumbs, `priceCurrency`/`addressCountry` from
  salon data, home directory + internal links from data, forms get the
  locality picker, `AcompteClient` operators from the catalog.

## 7. Security & authz (threat-model deltas T56/T57)

- **T56 — `GET /localities`**: read-only, zero PII, parameterless, process-
  cached + `Cache-Control` (CDN-absorbable). No write endpoint exists —
  changes are migrations reviewed like code. Clients build Mobile-Money deep
  links ONLY from the closed `deepLinkKind` vocabulary, never from a URL
  field — a poisoned label can never redirect a payment.
- **T57 — salon market attributes**: `areaId` validated against ACTIVE areas
  (400 `invalid_area`); `timezone`/`currency` are server-derived and IGNORED
  if client-sent; currency stamps financial records at write (immutable
  self-serve — the Fresha rule); timezone changes once bookings exist stay
  support-mediated; day-gate authority stays server-side (T41/T43 unchanged,
  now per-salon tz).
- **Reserved slugs**: provider slug generation refuses the taxonomy roots
  (5 categories + 13 services + city slugs) so a salon named « Coiffure » can
  never shadow `/coiffure`.

## 8. Compat story (why each slice is independently shippable)

MP1 is additive: jsonb fields + a new endpoint; tz threading is bit-identical
at UTC+0; the notifier « XOF » → « FCFA » is display copy. Legacy clients keep
sending commune names — accepted and self-healed to `areaId` on slug match;
already-published salons are never re-gated (the hardened publish gate applies
to NEW publishes and self-heals matching names first). `web/lib/api/schema.ts`
regenerates inside MP1 (CI drift gate) with zero behavior change; deposit wire
strings never change. MP3 ships redirects + nested pages + nested sitemap in
ONE deploy.

## 9. Testing plan

- **MP1:** `salon_time_test` (Abidjan ≡ UTC · Libreville UTC+1 · unknown-tz
  fallback); `localities_test` (tree golden on both repos · 200 + cache
  header · 405); **the Libreville end-to-end arc** (slots: 09:00 wall =
  08:00Z + the today-gate flips at 23:00Z; arrive `not_today` at the
  Libreville boundary; journal day + masking; dashboard buckets; notifier
  text renders the wall-clock + FCFA); the backfill matrix
  (Adjame/Adjamé/«cocody »/garbage → set/set/set/null, idempotent); security
  negatives (forged areaId → 400; client-sent tz/currency ignored; publish
  gate blocks unmatched commune under `profile`); deposit-policy re-sourced
  (same four pass, unknown still 400); earnings `currency`. Existing suites
  untouched and green.
- **MP2:** seam tests + Libreville; salon-switch refetch of
  tz/currency; picker returns names + writes areaId; catalog-rendered
  operator chips + deep link; hint label; pins extended (no `Africa/Abidjan`
  literal outside the seam; no `abidjanCommunes` import outside the mock).
- **MP3:** nested builders/parsers; **e2e 308 assertions** (`/coiffure-cocody`
  → `/coiffure/abidjan/cocody`); the `/[provider]/reserver` precedence guard;
  reserved-slug unit guard; a Libreville/XAF stub provider rendering
  wall-clock + FCFA; jsonld priceCurrency XAF case; pins extended.
- Test-date hygiene: no fixed calendar dates anywhere.

## 10. Definition of done (per slice)

- [ ] MP1: analyze 0 · format · full backend suite · boot smoke (+
      `/localities`) · contract + schema.ts regen in-PR · T56/T57 rows ·
      docs refreshed.
- [ ] MP2: analyze 0 · full mobile suite · APK size delta noted (tzdata) ·
      pins extended.
- [ ] MP3: typecheck/lint/build/vitest/e2e (nested + 308 + precedence) ·
      Lighthouse budgets hold.
- [ ] Each PR: CI green → USER merges before the next slice starts; spec
      section flipped to Built per slice.

## 11. Open questions

None — scope, URL nesting and slicing decided by the user 2026-07-14
(all four dimensions · nest now with permanent redirects · three PRs).
