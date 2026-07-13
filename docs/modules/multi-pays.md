# MyWeli — Multi-pays (marchés · fuseaux · devises · opérateurs) — `multi-pays`

**The end version for every market beyond Côte d'Ivoire, decided 2026-07-13**
after verified research on how the references do it (YCLIENTS, Fresha, Booksy,
Planity — §0). The purpose of this document is **end-version readiness**:
MyWeli anticipates these dimensions **structurally** (named seams, one rule,
one first slice) so that every future market lands as **seed data + one
contained slice** — never an archaeology dig through a hundred screens.

Nothing here is built ahead of need (V1 discipline). This document, the seams
in §9, and the first slice ([design/timezone-salon-time.md](../design/timezone-salon-time.md))
**are** the readiness.

| | |
|---|---|
| **Status** | 📘 End version agreed (2026-07-13) · slice 1 (salon time) built 2026-07-13 · **FULL MACHINERY BUILD in progress (user decision 2026-07-14): MP1 backend → MP2 mobile → MP3 web** — see [design/multi-pays-end-version.md](../design/multi-pays-end-version.md) |
| **Module slug** | `multi-pays` (cross-cutting — every module stands on it, like identity/design/security) |
| **First slice** | [design/timezone-salon-time.md](../design/timezone-salon-time.md) — the salon-time seam |
| **Companions** | [MODULES.md](../MODULES.md) · [ROADMAP.md](../ROADMAP.md) · [PRD.md](../PRD.md) (CI scope) · module [`network`](../MODULES.md) (V3 layer above) |
| **The guardrail** | §9 — mirrored in [DESIGN-STANDARDS §4](../design/DESIGN-STANDARDS.md), [WEB.md §3](../WEB.md), [BACKEND.md §2](../BACKEND.md) |

---

## 0. What the references do (verified 2026-07-13)

| | Geography | Timezone | Currency | The lesson |
|---|---|---|---|---|
| **YCLIENTS** | City catalog is a first-class record; the branch picks its **city**; district/metro sub-geography on contacts | The city **drives the branch's time** (« город — влияет на время в вашем филиале ») + placement on catalog sites; date/time *format* is a separate setting | Per-country pricing/fiscal modules | **The locality is the root entity** — timezone and marketplace placement are *derived*, never picked raw |
| **Fresha** | Per-location address/geo | **Explicit per-location timezone setting** | **Fixed at account creation per country — unchangeable** (a change requires a new account) | Currency is a birth attribute, not a setting |
| **Booksy** | Per-venue | Timezone change is **support-mediated**, not self-serve | Country-fixed | Once bookings exist, time is too dangerous to self-serve |
| **Planity** | Data-driven page tree: `/coiffeur` → `/coiffeur/paris-75` → `/coiffeur/paris-75/75008-paris-8eme` → salon | *Never built it* | *Never built it* | **Expanded only inside one homogeneous zone** (France → Germany #2 → Belgium #2, 40k+ salons, all CET + EUR) — sequencing can defer machinery |

**MyWeli's synthesis: architecture like YCLIENTS, sequencing like Planity.**
Build the locality-root model on paper + seams now, expand first through the
homogeneous zone (UTC+0 · XOF · francophone), and flip each piece of machinery
only at the wave that needs it (§7).

Sources: blog.click.ru/management/kak-nastroit-yclients · support.yclients.com
· fresha.com help center (41-update-your-business-details,
486-update-your-calendar-time-and-date-settings) · support.booksy.com article
16539665393170 · planity.com/coiffeur/paris-75 (+ /75008-paris-8eme) ·
usine-digitale.fr (Planity série C 45 M€) · maddyness.com (Planity rentable,
2026-07).

---

## 1. The end version at a glance — the locality root

A salon picks **one locality** at creation. Everything market-specific is
**derived** from it — the salon never picks a timezone, a currency, or an
operator list directly:

```
locality (commune/quartier)
  └─ city ──────── timezone (IANA) · map center · SEO landing family · catalog placement
       └─ country ─ currency (ISO 4217) · MoMo operator catalog · SMS route + sender ID
                    · phone prefix · KYC document types · legal entity / CGU
```

Launching a market = inserting rows + walking the §8 checklist. No screen
changes hands.

---

## 2. Geography — the locality tree

**End state:** three seeded tables (data, not code):

| Table | Fields | Notes |
|---|---|---|
| `countries` | `code` (ISO-3166), `name`, `currency` (ISO 4217), `phonePrefix`, `active` | Wave 0 = `CI` |
| `cities` | `id`, `countryCode`, `name`, `slug`, **`timezone` (IANA)**, `lat`, `lng`, `active` | Timezone lives HERE (the YCLIENTS rule) |
| `areas` | `id`, `cityId`, `name`, `slug`, `labelKind` (`commune` \| `quartier` \| `arrondissement`), `lat`, `lng`, `active` | Wave 0 seed = the 11 Abidjan communes |

- The salon references its **area** (`areaId` + denormalized name for query
  speed); today's `businessCommune` string migrates into that reference when
  the tables land (second city).
- The tree powers: the discovery commune filter, « Près de moi » resolution,
  the map center/zoom, the registration picker, widget/catalog placement, and
  the **SEO landing families**.
- **URLs:** the Planity tree (`/tresses` → `/tresses/abidjan` →
  `/tresses/abidjan/cocody`) with **permanent redirects from every flat
  slug** — *user decision 2026-07-14: nested NOW (MP3), ahead of the
  second-city trigger; redirects + nested sitemap ship in one deploy.*
- **Today's seed (the seam):** `mobile/lib/core/constants/communes.dart`
  (`abidjanCommunes`), the web landing taxonomy (`web/lib/landing.ts`,
  `discovery.ts`, `service-landing.ts`), backend commune validation
  (provisioning/repository). One list per surface, referenced everywhere,
  hardcoded nowhere else.

---

## 3. Timezone — salon time, derived, never picked

**The rule: every displayed time and every day boundary is the SALON's time.**
The device timezone is never used for domain logic — only to decide whether to
show the hint.

1. **Storage stays UTC ISO-8601** everywhere (unchanged, [BACKEND.md §2](../BACKEND.md)).
2. **Interpretation is salon-time:** slots, journal day view, « aujourd'hui »,
   same-day gates (`not_today`), masking windows, revenue period buckets, cron
   warning windows, notification texts.
3. The salon's timezone is **derived from its city** — no IANA picker, ever.
   Denormalized onto the salon at creation.
4. Until Wave 2, the derivation is a **single constant** `Africa/Abidjan`
   (= UTC+0 year-round) behind tz-parameterized helpers — **the seam is BUILT
   (2026-07-13)**: `web/lib/time.ts` + `mobile/lib/core/utils/salon_time.dart`
   ([design/timezone-salon-time.md](../design/timezone-salon-time.md)).
5. **Viewer hint:** when the viewer's device offset differs from the salon's,
   surfaces that show bookable/booked times display « Heures affichées : heure
   du salon (Côte d'Ivoire) » (the traveler-in-France case).
6. **Immutable self-serve** (the Booksy rule): once a salon has bookings, a
   timezone change is support-mediated only.
7. IANA identifiers, never raw offsets. No target market observes DST today —
   never rely on that; the IANA database is the authority.

**Wave 2 flip:** add `cities.timezone` → snapshot onto the salon → delete the
constant. The helpers don't change.

---

## 4. Currency — fixed at birth, never converted

1. `providers.currency` (ISO 4217), **derived from the country at creation,
   immutable self-serve** (the Fresha rule — changing it = a new salon).
2. Amounts stay **integers in whole francs**; financial records (ledger rows,
   deposits) are **stamped with the currency at write time**.
3. **Prices are never converted** — a booking is priced and paid in the
   salon's currency, whoever books it.
4. One money formatter per surface (`web/lib/format.ts` `formatFcfa`,
   `mobile/lib/core/utils/formatters.dart`) — each gains a `currency`
   parameter **defaulting to XOF** in the first slice, so no call site is ever
   revisited.
5. **Display:** « FCFA » correctly renders both XOF (UEMOA/BCEAO) and XAF
   (CEMAC/BEAC) — distinct ISO codes, identical value, same colloquial name —
   so visible display work starts only outside the franc zone.
6. Consolidated multi-salon reporting across currencies (module `network`, V3)
   groups by currency — no synthetic totals.

---

## 5. Mobile Money operators — a per-country catalog

1. **End state:** `momo_operators(countryCode, id, label, deepLinkKind, active)`
   as seeded data (CI: Orange Money · MTN MoMo · Moov Money · Wave; Sénégal:
   Wave · Orange Money; Gabon: Airtel Money · Moov; …).
2. The salon's **deposit policy may only reference operators from its
   country's catalog**; labels and deep-link behavior render from the catalog
   (today's seam: `mobile/lib/core/utils/mobile_money.dart` + the
   `MobileMoneyOperator` enum — converts to data in the same slice as the
   first foreign market, not before).
3. **No-custody stays** (PRD OQ-1, user decision): screenshot-based deposit
   proof, MyWeli never holds funds — in every market. No external template
   exists for this; YCLIENTS's per-country fiscal modules are the pattern:
   payment furniture per country, isolated as data.

---

## 6. Cross-cutting seams (already in place — named so they stay honest)

- **Phone:** E.164 validation is country-agnostic ✓; only the input's default
  country flag is per-market UI seed.
- **Messaging:** SMS/WhatsApp routing already sits behind the
  `MessagingProvider` seam — per-country routes + sender IDs slot in there
  (aggregator coverage per market is a checklist item, §8).
- **Auth:** Google/Apple/email OTP — country-agnostic ✓.
- **KYC:** the flow is generic; the accepted **document types** differ per
  country — checklist line, not a build.
- **Language boundary (deliberate):** the end version is **francophone-only**.
  Sénégal, Mali, Burkina, Togo, Bénin, Niger, Gabon, Cameroun all arrive with
  zero i18n. Ghana/Nigeria would mean a full localization program — a separate
  strategic decision, explicitly **out of scope** here.

---

## 7. The waves — what flips when

> **Post-MP1–MP3 (decision 2026-07-14): ALL the machinery below is live with
> CI-only data — every wave becomes a data-only market entry (§8 checklist +
> seed rows). The table is kept as the market map.**

| Wave | Markets | Zone | What their entry needs now |
|---|---|---|---|
| **0 (live)** | Côte d'Ivoire | UTC+0 · XOF | — (the seed) |
| **1** | Sénégal · Mali · Burkina · Togo | UTC+0 · XOF · FR | Seed rows (localities + operators) + SMS route + KYC docs + legal |
| **2** | Bénin · Niger | **UTC+1** · XOF · FR | Same — the per-salon timezone machinery is already live |
| **3** | Gabon · Cameroun (CEMAC) | UTC+1 · **XAF** · FR | Same — per-salon currency + « FCFA » display already cover XAF |

Bénin/Niger were **the trap inside UEMOA** (same XOF, different clock) — the
reason timezone machinery was built before any expansion.

---

## 8. Per-market launch checklist

1. **Localities seed** — cities + areas with the right `labelKind`
   (commune / quartier / arrondissement) and slugs.
2. **Timezone** on the city rows (Wave 2+ — before that, UTC+0 markets need
   nothing).
3. **Currency** on the country row (Wave 3+ — XOF markets need nothing).
4. **Operator catalog** — the market's MoMo operators + deep-link behavior.
5. **SMS/WhatsApp route + sender ID** — aggregator coverage verified
   (`MessagingProvider` config), cost per segment checked.
6. **KYC document types** for the market.
7. **Legal** — entity/registration, CGU/CGV review, data-protection regime.
8. **SEO** — the city's landing family + sitemap entries (nested URLs + 301s
   from the second city onward).
9. **QA pass in salon time** — book/journal/revenue arcs exercised with a
   device clock in a *different* timezone than the salon.

---

## 9. The guardrail — market data lives ONLY in its seams

**Rule (enforced in review):** market-specific facts — localities/communes,
Mobile Money operators, currency, timezone, phone prefixes — live **only** in
their designated seams. Hardcoding one anywhere else fails review, even when
it "works" for Côte d'Ivoire.

| Surface | The seams |
|---|---|
| Mobile (MP2) | **the live tree: `providers/locality_provider.dart` + the `LocalityService` seam** (fed by `GET /localities`) · `core/constants/communes.dart` (**mock seed only**) · `core/utils/mobile_money.dart` · `core/utils/formatters.dart` · `core/utils/salon_time.dart` (`package:timezone`, per-salon `tz`) |
| Web | `lib/landing.ts` / `lib/discovery.ts` / `lib/service-landing.ts` (taxonomy) · `lib/format.ts` · `lib/time.ts` — the locality tree goes live at MP3 |
| Backend (MP1) | `lib/src/localities/` (the seeded tree + `GET /localities`) · `lib/src/salon_time.dart` (`package:timezone`) · UTC storage ([BACKEND.md §2](../BACKEND.md)) |

Mirrored as one rule line in [DESIGN-STANDARDS §4](../design/DESIGN-STANDARDS.md),
[WEB-DESIGN-STANDARDS §5](../design/WEB-DESIGN-STANDARDS.md),
[WEB.md §3](../WEB.md) and [BACKEND.md §2](../BACKEND.md) — that rule is what
keeps the next hundred screens end-version ready.

---

## 10. The machinery build (decision 2026-07-14 — supersedes the wave gating)

The original discipline deferred each mechanism to its wave trigger. **The
user decided on 2026-07-14 to build the complete end version now** — program
spec: [design/multi-pays-end-version.md](../design/multi-pays-end-version.md)
(MP1 backend → MP2 mobile → MP3 web):

- ✅ `countries`/`cities`/`areas` + `momo_operators` tables, seeded (CI) and
  served by public `GET /localities` — MP1.
- ✅ Per-salon `timezone` (city-derived) through ALL backend day-math
  (`package:timezone`) and client display — MP1 + MP2/MP3.
- ✅ Per-salon `currency` (country-derived), stamped on financial records,
  threaded through display — MP1 + MP2/MP3.
- ✅ Operator catalog validation + catalog-driven rendering (client enums
  retire; wire strings unchanged) — MP1 + MP2/MP3.
- ✅ Nested SEO URLs + permanent redirects — MP3.
- ❌ Still no i18n (francophone-only stands) and no non-CI seed rows — **a
  new market is now purely §8 checklist + data.**

Slice-1 foundations (salon time, « FCFA » display, the §9 guardrail pins)
shipped 2026-07-13 via [design/timezone-salon-time.md](../design/timezone-salon-time.md).
