# « Nouveau » instead of « ★ 0.0 · 0 avis », and the visits card only when it has visits

| | |
|---|---|
| **Status** | **Approved** (owner, 2026-10-13) — building for build 566 |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-10-13 |
| **PRD ref / phase** | Discovery + salon page (consumer app, Pro « Aperçu », web) · V1 |
| **Module** | Salon page / discovery (docs/MODULES.md) |
| **Skills checked** | myweli-dev-guardrails · myweli-web-guardrails · myweli-verification-guardrails |
| **Governs** | `mobile/lib/widgets/common/app_rating.dart` · `provider_detail_screen.dart` · `provider_card.dart` · `map_screen.dart` · `reviews_screen.dart` (Pro) · `web/components/Rating.tsx` · `web/components/provider/Hero.tsx` · `ProviderCard.tsx` · `discovery/ResultsMap.tsx` |

## 1. Goal & scope

Found while shooting the App Store screenshots (2026-10-12,
[pro-app-store-screenshots.md](pro-app-store-screenshots.md) §9): the top of
the salon page, the warmest image in the product, could not be used because
it read « ★ 0.0 · 0 avis » under the name and carried a « Vos rendez-vous ici
— Connectez-vous pour voir vos rendez-vous. » card.

Both are product defects, not screenshot problems:

1. **A salon with no reviews reads « 0.0 ».** Five app sites print
   `rating.toStringAsFixed(1)` and the count unconditionally: the salon header,
   the « Avis » summary, both `ProviderCard` layouts and the map sheet. A new
   salon — every salon at launch — looks like a one-star failure. They also
   print an **anglophone point** (« 4.8 ») on a French product; the web fixed
   that in B6 with `ratingFr` (« 4,8 »). SYSTEM.md §3.5/§11.3 specify a shared
   `AppRating` (« ★ 4,8 (32 avis) ») that **was never built in the app** —
   `web/components/Rating.tsx` calls itself its « web twin ».
   The web, meanwhile, **hides** the rating at 0 reviews (three
   `reviewCount > 0` guards), so app and web disagree.
2. **The visits card is shown to everyone.** On the app, « Vos rendez-vous
   ici » renders for a signed-out client (« Connectez-vous… ») and for a
   signed-in client with no visits (« Aucun rendez-vous dans ce salon. »). The
   web's `SalonVisitsCard` (parity 2.7) renders **nothing** unless a signed-in
   client has bookings there. The Pro « Aperçu » copies the app's signed-out
   rendering verbatim (`salon_preview_test.dart` pins it), so the owner sees a
   sign-in prompt on their own page.

Out of scope: the web's « upcoming or reviewable » filter inside the visits
card (the app keeps listing the 5 latest visits); review moderation; the
JSON-LD `aggregateRating` (already guarded by `reviewCount > 0`, unchanged).

## 2. UX

### 2.1 The rating, everywhere

One component per surface — app `AppRating`, web `Rating` — one rule:

| Reviews | Renders | Accessible label |
|---|---|---|
| ≥ 1 | `★ 4,8 (32 avis)` — or the compact `★ 4,8 (32)` on cards and the map sheet | « Note 4,8 sur 5, 32 avis » |
| 0 | a quiet **« Nouveau »** pill | « Nouveau salon, pas encore d’avis » |

- French comma always (`4,8`), one decimal.
- The star stays decoration (§3.5); the numeral is the information.
- « Nouveau » is a neutral pill — `surfaceVariant` fill, `textSecondary`,
  `labelSmall`, `radiusPill` — not a status colour: it describes the salon,
  it does not warn. Web: `<Chip variant="neutral">` (dense on cards/map).
- « 1 avis » singular is not needed: the count is a number in brackets
  (`(1 avis)` reads correctly in French for one as well — « avis » is
  invariable).

Sites (app): salon header · « Avis » summary (large) · `ProviderCard` list and
grid · map sheet. Pro « Avis » screen: comma only (it already shows an empty
state at 0). Sites (web): `Hero`, `ProviderCard`, `ResultsMap` — they stop
hiding and show « Nouveau ».

### 2.2 The « Avis » section at 0 reviews (app)

The large `★ 0.0 / 0 avis` summary becomes the « Nouveau » pill and the line
« Pas encore d’avis. » (`bodySmall`, `textTertiary`). The « Donner votre
avis » invitation for a client with a reviewable visit is unchanged, so the
first review can still be left from here. (The web hides its whole review
list at 0 and invites from `SalonVisitsCard`; same outcome, different home.)

### 2.3 « Vos rendez-vous ici »

Shown **only** to a signed-in client who has at least one booking at this
salon — exactly the web's rule. Signed out, or signed in with none: the
section is not rendered at all (no title, no card). Owner « Aperçu »: never
rendered (a signed-out client sees nothing, and that is what the preview
shows).

All states: signed out → nothing · signed in, loading → nothing until the
appointments are in (no spinner for an optional card) · signed in, none here →
nothing · signed in, some → the existing card with up to 5 visits and « Voir
tout ».

## 3–6. Contract, data, architecture, security

No API, DTO or backend change: `rating` and `reviewCount` are already on the
provider payload. `AppRating` lives in `widgets/common/` beside the other
shared components; the French decimal goes through a new
`Formatters.formatRating` so no call site formats by hand. No new data, no
authz change.

## 7. Performance

None measurable: a stateless widget replacing a `Row`.

## 8. Testing

- `app_rating_test.dart`: comma (`4,8`), count and compact forms, « Nouveau »
  at 0, semantics labels, no overflow at 360 dp × 200 % text.
- `provider_detail_screen` / `ProviderCard` / map sheet: « Nouveau » for a
  zero-review salon; « 0.0 » is found nowhere (watched red against the old
  code).
- `salon_preview_test.dart`: the preview renders **no** « Vos rendez-vous
  ici » and no « Connectez-vous… » (the old assertion inverts).
- Visits card: signed out → absent; signed in with none → absent; signed in
  with one → present.
- A corpus pin: no `rating.toStringAsFixed(` left in `lib/` outside
  `Formatters` (comments stripped).
- Web: `b6-rating-chip.test.tsx` gains the 0-review case; Hero/ProviderCard/
  ResultsMap render « Nouveau » at 0.
- Goldens regenerated through the Linux workflow; every changed PNG looked at.

## 9. Rollout

One PR (app + web). Web ships on merge (Vercel). The app ships in **build
566**, then App Store screenshot 7 is reshot on the top of the salon page
(cover, logo, name, « Nouveau ») and moved to position 2.

## 10. Definition of done

- [ ] Tests above green; `flutter analyze` 0; web typecheck + lint + tests.
- [ ] Goldens regenerated on Linux and reviewed.
- [ ] SYSTEM.md §11.3 marks `AppRating` built; §3.5 states the 0-review rule.
- [ ] Build 566 on TestFlight; owner check; screenshot 7 reshot.

## 11. Open questions

None.
