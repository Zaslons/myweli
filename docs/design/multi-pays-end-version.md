# Multi-pays — the end version, built (MP1 → MP2 → MP3) — program design spec

> The full activation of [modules/multi-pays.md](../modules/multi-pays.md):
> the locality tree becomes seeded DATA served by the API, the salon derives
> its timezone/currency/operator catalog from its locality, every surface
> renders in the salon's own timezone and currency, and the SEO landings move
> to the nested Planity tree with permanent redirects. After this program,
> **entering any market = seeding rows + the §8 checklist** — no code sweep.

| | |
|---|---|
| **Status** | ✅ **PROGRAM COMPLETE — MP1 (backend, PR #235) + MP2 (mobile, PR #236) + MP3 (web) BUILT** (user decision 2026-07-14: all four dimensions, ahead of the wave triggers; nested URLs now; three PRs). A new market = the module doc's §8 checklist + seed rows. |
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

- **Mobile (BUILT — MP2):** new `LocalityServiceInterface` + Mock/Api +
  `LocalityProvider` (lazy fetch + cache, four states); the commune picker
  renders the tree (still RETURNS the name — the `?commune=` filter contract
  is unchanged) + writes `areaId` from pro profile / registration /
  add-salon; « Près de moi » resolves against area centroids;
  `communes.dart` demoted to the mock seed (`nearestCommune` deleted). The
  tz seam runs on `package:timezone` (**latest_all** — the MP1 LINK-zone
  lesson) with `{String? tz}` on every helper; pro surfaces read
  `ProAuthProvider.salonTimezone/salonCurrency` (refetched on switch —
  tested), consumer surfaces the viewed provider / the appointment carriers;
  the operator catalog renders pickers, labels and the Wave deep link
  (`deepLinkKindIsWave`); « FCFA » currency threading covers every salon
  money surface (platform billing/admin stay XOF by design); the hint's
  country label is dynamic on all three consumer surfaces; grep pins extended
  (quoted-`Africa/Abidjan` + communes-import).
- **Web (BUILT — MP3):** `lib/api/localities.ts` (openapi-fetch, module
  cache, empty-tree fallback) + `/api/localities` BFF + `lib/use-localities.ts`
  client hook; the hardcoded commune list is GONE — the taxonomy libs
  (`landing.ts`/`service-landing.ts`/`discovery.ts` + the new `taxonomy.ts`)
  stay pure/sync and take geography as parameters. **Nested landings** ship
  as ONE `TaxonomyLandingView` for the three levels of both taxonomies
  (root « {label} en {Pays} » with city cards · city with area chips +
  citywide grid geo-scoped by the salons' own `citySlug` · area = the
  historical landing), each with canonical/OG, noindex-when-empty, visible
  fil d'Ariane + Breadcrumb/ItemList/FAQ JSON-LD; the `[slug]` dispatcher
  resolves taxonomy ROOT → provider → legacy flat slug →
  `permanentRedirect()` (308 ≡ 301) → 404, and `[slug]/[city](/[area])`
  pages 404 off-tree (the static `/reserver` wins by precedence — e2e
  pinned). Sitemap emits the nested tree only; `llms.txt` updated. Per-salon
  tz/currency threaded through EVERY surface: consumer (appointment carriers
  `providerTimezone/-Currency/-CountryCode` stamped in the BFF enrich,
  BookingFlow/account/detail + reschedule pickers), pro (each client reads
  `provider.timezone/currency` off `getMyProvider`; `lib/pro/*` helpers take
  `tz`; `salonWallClockToUtc` retires every hand-built `…:00.000Z` instant —
  journal drops, manual booking, reprogram pre-fills), `priceCurrency`/
  `addressCountry` from salon data, map centers from city centroids
  (`centerOf`), the hint takes `tz` + a dynamic country label. Forms:
  `LocalityPicker` (Ville → commune/quartier, four states, free-text
  self-heal fallback on profil) writes `areaId` on profil/inscription/
  ajouter-un-salon (optional — the publish gate enforces, T57); the salons
  BFF forwards `areaId`; deposit operators come from the salon country's
  catalog (`operatorsFor`), `OPERATORS` deleted, `lib/mobile-money.ts`
  mirrors the app (label lookup + Wave deep link from the closed
  `deepLinkKind` vocabulary — T56, « Payer avec Wave » on the proof sheet).

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
- **MP3 (done):** nested builders/parsers + reserved-slug guard (unit);
  **e2e 308 assertions** (`/coiffure-cocody` → `/coiffure/abidjan/cocody`,
  hyphenated service roots too); the `/[provider]/reserver` precedence guard
  + `[city]` under a provider slug → 404; **the Libreville arc**: stub p3
  « Institut Belle Vue » = GA/Libreville/XAF and appt4 its booking — the
  account renders 10:00 for the 09:00Z instant (Abidjan row stays 09:00 in
  the same list), « FCFA » from XAF, the hint « heure du salon (Gabon) »;
  pro: switching to p3 re-catalogs the deposit operators (Airtel, no Orange);
  jsonld priceCurrency XAF/addressCountry GA case; `salonWallClockToUtc`
  DST-probe; pins extended (no `'Africa/Abidjan'` outside `lib/time.ts`, no
  hand-built `T${…}:00.000Z` instants). 350 unit + 77 e2e green.
- Test-date hygiene: no fixed calendar dates anywhere.

## 10. Definition of done (per slice)

- [ ] MP1: analyze 0 · format · full backend suite · boot smoke (+
      `/localities`) · contract + schema.ts regen in-PR · T56/T57 rows ·
      docs refreshed.
- [x] MP2: analyze 0 · full mobile suite (543) · APK size delta noted
      (tzdata latest_all ≈ 1 MB raw / ~450 KB compressed — the MP1 LINK-zone
      trade) · pins extended.
- [x] MP3: typecheck/lint/build/vitest (350)/e2e (77 — nested + 308 +
      precedence + the Libreville arcs) all green · public pages stay
      SSG/ISR with no new client JS on landings (budgets hold).
- [x] Each PR: CI green → USER merges before the next slice starts; spec
      section flipped to Built per slice.

## 11. Open questions

None — scope, URL nesting and slicing decided by the user 2026-07-14
(all four dimensions · nest now with permanent redirects · three PRs).
