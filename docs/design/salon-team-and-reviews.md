# MyWeli (client) — the salon page's team, and every review (A5)

| | |
|---|---|
| **Module** | discovery (the salon page, `/provider/:id`), with `public-api` (`GET /providers/{id}/reviews`, A5-api) and `public-web` (`/{slug}`, A5w); the booking hub of both (a specialist chosen first, §2.4) |
| **Status** | **Written 2026-11-27**, on the owner's « Yes, start A5 ». Read once by an independent reviewer told to refute it: no blocker, 18 findings, each re-read in the code, then taken in (§12). Seven questions for the owner (§11, decisions 277–283, open). No code before the answers. |
| **Last updated** | 2026-11-27 |
| **Audit** | [consumer-app-release-audit.md](consumer-app-release-audit.md) row **A5** (Track A, §7): gap **18** (« No staff section on the salon page; reviews capped at 5 », §2.2). Also §2.2's third « missing » line (a guest's « Signaler », §2.6 here) and §2.10's « the web has, the app lacks: the staff section » |
| **BACKLOG** | B0.10 (the audit's Track A, decision 160) |
| **PRD ref / phase** | V1 · **FR-DISC-006** (« staff/artists … reviews summary + list ») · FR-REV-002 (the verified badge, on the website too) · FR-REV-003 (per-stylist attribution) · FR-REV-005 (report, a guest included) · FR-BOOK-001…006 (the hub, §2.4) |
| **Read at** | `main` `2e148f89`. Every « today » below was read in the code on 2026-11-27, with its file and line. |
| **Related** | [consumer-reviews.md](consumer-reviews.md) (the reviews model: per visit, artist-attributed; the shared page slot) · [salon-reviews-summary.md](salon-reviews-summary.md) (the server's `summary`, Pro's « Avis ») · [consumer-search.md](consumer-search.md) §2.6 and §3.3 (« Afficher plus », decision 231; A4w's same-origin route) · [consumer-signin-push.md](consumer-signin-push.md) (A3: `openSignIn`, `SignInReason`) · [pro-artists.md](pro-artists.md) (who the team is) · [pro-salon-lifecycle.md](pro-salon-lifecycle.md) B4/B5 (the owner's « Aperçu ») · [SYSTEM.md](SYSTEM.md) §12 (states), §13 (a11y), §15 (feedback) · [WEB-SYSTEM.md](WEB-SYSTEM.md) §4–§8 |
| **Skills checked** | myweli-dev-guardrails ✓ · myweli-web-guardrails ✓ (parity read; A5w) · myweli-backend-guardrails (A5-api, at its build) · myweli-verification-guardrails (at each claim) |

---

## 0. Today (read on `main` `2e148f89`)

**The salon page in the app** (`mobile/lib/screens/providers/provider_detail_screen.dart`):
- **No team.** The screen never reads `p.artists`. Its sections, in order: « Vos rendez-vous ici » (:513), « Services » (:638), « Contact » (:696), « Photos » (:939), « Avant / Après » (:1002), « Avis » (:1008), « À propos » (:1149). The data is there: `GET /providers/{id}` carries `artists[]` with `name`, `imageUrl`, `specialization`, `rating` and `reviewCount` (`docs/api/openapi.yaml`, `Artist`), and `Provider.artists` reads them (`models/provider.dart:34`, `:283`).
- **Five reviews, and no way to the rest.** `p.reviews.take(5)` (:1037). The read embeds the latest 10 (`backend/routes/providers/[id]/index.dart:38-41`). A salon with 40 reviews shows 5 and its count.
- **A guest's « Signaler »** gets a snackbar, « Connectez-vous pour signaler un avis. », with no way to sign in (:204-208). A3 made sign-in a pushed screen with a reason line (`core/auth/open_sign_in.dart`); this path was not moved to it.

**The review list the app could use, and doesn't.** `ReviewServiceInterface.getProviderReviews` exists (`services/interfaces/review_service_interface.dart`), with a real `ApiReviewService` (`services/api/api_review_service.dart:69-84`). Nothing calls it. As written it:
- keeps only `items` and drops `total`, so no « more » can be decided;
- does not catch a failed connection (a bare `_client.get`), unlike the salon list (`api_provider_service.dart`: `try … networkError()`);
- has no `readOrUnreadable` for a body that does not read.

A 404 (the salon no longer public, Decision C) already carries `not_found`, through `errorFromResponse` (:79, `api_errors.dart`).

**The booking hub, when a specialist is chosen first.** It takes `artistId` (`core/router/app_router.dart:89`; `booking_hub_screen.dart:126-128`), as rebook uses it.
- **The specialist rows fade** (opacity 0.45, disabled) when they cannot do the ticked services (:674-691), **with no word why**.
- **The services never dim.** Instead, ticking a service the chosen specialist does not do **drops the specialist without a word** (:519-531). The website does the same (`web/lib/booking/state.ts:231-234`).
- **The capability rule** is one rule on three sides: the app's `_artistCanDoServices` (:214-226), the website's `artistCanDoServices` (`state.ts:151-162`) and the server's (`backend/lib/src/slot_service.dart:250-253`). A selection holding any unrestricted service (no `artistIds`) accepts every specialist.
- **An `artistId` sent alone is not checked in the app.** The hub checks the prefill against the salon only when services come with it (`if (!mounted || !prefilled) return;`, :141). A removed member's id then stays in the draft: the card says « Pas de préférence » (:189-192) while the id goes to the slots and to the booking (:359, :412). The website checks it in every case (`BookingFlow.tsx:133`).
- **Arriving with a specialist is not « specialist first ».** The entry point starts empty, and the first service tap sets it to « services » (:504-506). The earliest-slot proposal wants « specialist first » (:559, :815). The website is the same (`initialHubState`, `shouldAutoPickEarliest`).
- **Inactive services are listed.** The app shows every service, on the salon page (`provider_detail_screen.dart:673`) and in the hub (:495). The public read sends them with `active: false`. The website hides them (`BookingFlow.tsx:203`, `ServiceList.tsx:12`), and the server refuses them at booking (`booking_service.dart:192`).

Today only rebook reaches the silent drop. A « Réserver avec Awa » would reach it every day.

**The server.**
- `GET /providers/{id}/reviews?page=&pageSize=` is public and paged (`backend/routes/providers/[id]/reviews/index.dart`). Its page size is clamped to 50 (`reviews_service.dart:218`). It answers `{items, page, pageSize, total}`, with no `summary`; only Pro's `GET /me/provider/reviews` sends one (`salon-reviews-summary.md`).
- **Pages are ordered by `created_at` alone** (`db/postgres_reviews_repository.dart:60`), with no tiebreak.
- **A review written again moves to the top:** the upsert rewrites `created_at` (`:27-31`). So a page boundary can move while someone reads.

**The website** (`web/components/provider/ProviderView.tsx`, `ReviewList.tsx`):
- **« Équipe »** (:197-213): names and specialties as plain text. No photo, no rating, and no way to book with someone, although the funnel takes `?artist=` (`app/[slug]/reserver/page.tsx:47-54`).
- **Reviews:** the 10 embedded, with no way to the rest.
- **Each review** shows its author, stars, text, photos, date and « Signaler ». It does not show « avec {artiste} » or the verified badge, which the app shows (`widgets/review/review_tile.dart`: « Réservation vérifiée », « avec … »).
- A guest's « Signaler » already gets a sign-in link (`ReviewList.tsx`, `state === 'auth'`).

**The owner's « Aperçu »** (both apps: `salon_preview_screen.dart`, `SalonPreviewClient`):
- It reads `GET /me/provider`, which embeds **no reviews** (`salon_preview_screen.dart:34-40`).
- So a live salon's preview shows its count and no review. Today that also means no « Signaler » can be tapped there. The Pro app has no consumer `AuthProvider`, so one would throw.

---

## 1. Goal & scope

**Before booking, the person sees who works there and can choose them, and can read every review, not only the latest five.**

**In scope:**
- **A5-api (backend), if Q4:**
  - the public list sends the salon's `summary` (average, count, the 5 → 1 split) with every page, as Pro's route does;
  - its order ends on the id.
- **A5 (app):**
  - an « Équipe » section on the salon page; each person leads to the booking hub with them chosen (Q1);
  - « Voir les N avis » under the five, opening a screen with the summary and every review, page by page (Q3);
  - the hub, with a specialist chosen, dims the services they do not do, instead of dropping them, and says why a specialist is faded (Q2);
  - an `artistId` sent alone is checked against the team, and counts as « specialist first » (§2.4);
  - the salon page and the hub list **active services only**, as the website and the server already do. Found by the review (§12); the team and dimming rules need one list;
  - a guest's « Signaler » signs in over the page, then reports (Q5).
- **A5w (website), if Q6:**
  - the same team rows, with « Réserver » to `/{slug}/reserver?artist=`;
  - « Afficher plus d’avis » in place;
  - each review gains « avec {artiste} » and « Réservation vérifiée »;
  - the funnel dims as the app's hub (Q2).

**Out of scope:**
- **A page per team member** (bio, portfolio, their own reviews) and **filtering reviews by specialist or by star.** Both need more than today's data. Each would be its own decision.
- **Sorting reviews** (newest first only, as today).
- **The salon's reply to a review** (FR-REV-004, V2).
- **How the reviewer's name is shown** (today: the account's full name, `reviews_service.dart:188`). It is the same on five reviews or fifty. Seen in passing, §13.
- **Pro's own « Avis »** (it lists the first 50 and stops: Pro, not A5).

---

## 2. UX & flows

### 2.1 The flow

1. The person opens a salon. Under « Services », **« Équipe »** shows who works there: photo, name, specialty, their rating.
2. They tap **Awa**. The booking hub opens with **Awa chosen** and the services first. A service Awa does not do is dimmed, with « Pas avec Awa Koné ».
3. Or they scroll to **« Avis »**: the summary, five reviews, then **« Voir les 23 avis »**.
4. The reviews screen opens: the summary with its bars, then the reviews newest first, **« Afficher plus d’avis »** at the end, and **« Réserver »** always at the bottom.
5. « Retour » goes back to the salon page, where they were.

### 2.2 « Équipe » on the salon page (app)

- **Where:** a section card right after « Services », before « Contact ». The person chooses what, then who. Shown when the salon has at least one team member, whatever the number. A one-person salon is still told who will do it.
- **Each person is one row**, at least 48 dp tall, in the salon's own order (`artists[]`, the order Pro keeps):
  - **a 48 dp circle.** It shows the photo (`TimedCachedImage`, cropped) or, with no photo or a photo that fails, the name's first letter on `surfaceVariant`, as `ReviewTile` does;
  - **the name** (`titleSmall`, `textPrimary`, up to 2 lines);
  - **the specialty** when set (`bodySmall`, `textSecondary`, 1 line);
  - **their rating** (`AppRating`, `compact`: « ★ 4,8 (12) ») **only from 1 review.** At 0 reviews nothing is shown: the salon's « Nouveau » would call a ten-year stylist new;
  - **at the end, « Réserver »** (`labelLarge`, `textPrimary`). The whole row is the button.
- **A tap** pushes `/booking?providerId={id}&artistId={artistId}` (Q1).
- **A person who does no active service** gets no « Réserver », and the row is not a button. That happens when every active service lists its people and they are on none. Booking with them would reach a hub where nothing can be ticked (§2.4).
- **Seven or more:** the first five, then **« Voir toute l’équipe (N) »**. It opens the rest in place; the button goes and the focus moves to the sixth person. Six or fewer are all shown (no button that hides one).
- **In the owner's « Aperçu »:** the rows show, without « Réserver » and not as buttons, like the disabled booking bar.

### 2.3 « Avis » on the salon page, and « Voir les N avis » (app)

- **The section keeps what it has:** the rating, « Pas encore d’avis. » at 0, the five latest, « Donner mon avis » when the person has a completed visit.
- **« Voir les {N} avis »**, a secondary full-width button under the five. N is the salon's `reviewCount`.
  - **Shown when** `reviewCount` is more than the reviews shown. It is gone at 5 or fewer, since everything is already there.
  - **Not shown in the « Aperçu »:** there the read embeds no review (§0), and the reviews screen is a client route, absent from MyWeli Pro's router.
- **A tap** pushes `/provider/{id}/avis`.

### 2.4 The hub, with a specialist chosen first (app and website, Q2)

**The rule:** whatever is chosen limits the other side, and says so.

- **Arriving with a specialist** (`artistId` and no service, the team row's link) **is « specialist first »**, on both surfaces. Once a service is ticked, the hub proposes the earliest slot with them, as when the specialist is tapped first inside the hub. Arriving with services too (rebook) is unchanged: straight to the date and time.
- **An `artistId` is checked against the salon's team whenever it is sent,** alone or with services. In the app that check runs today only with services (§0). An unknown id opens on « Pas de préférence ».
- **A service is dimmed** when three things hold: a specialist is chosen (not « Pas de préférence »), the service is not ticked, and ticking it would make the specialist impossible. That is the existing rule (`_artistCanDoServices` / `artistCanDoServices`) over the selection plus that service. So the hub stays in step with the server by construction.
  - A dimmed service shows a second line, **« Pas avec {nom} »**, in `textSecondary`. It is not a button, and its semantics say « non disponible avec {nom} ».
  - **A ticked service is never dimmed;** unticking always works.
  - To book a dimmed service, the person changes the specialist; the « Spécialiste » card is on the same screen.
- **A faded specialist says why:** a second line, **« Ne fait pas cette sélection »**. Today the row only fades (§0), which carries its meaning by opacity alone (SYSTEM §13).
- **When the specialist is still dropped**, it is never silent. The « Spécialiste » card opens with **« {nom} ne fait pas cette sélection. Choisissez un autre spécialiste. »** There are two such cases:
  - unticking the only service that made the specialist possible (a « tous » service ticked beside one restricted to someone else);
  - a rebook prefill whose specialist no longer does those services (the check above tests existence, not capability).
- **The rule's leniency is kept, and recorded** (§13). Once an unrestricted service is ticked, the rule accepts the chosen specialist for every other service, and the server does too (`slot_service.dart:250-253`). The hub follows the server and dims nothing then. Changing the rule is a server decision, not A5's.
- **Unchanged:** the entry order with nothing prefilled, « Pas de préférence », the hair-length choice, and the date and slot checks. None of them touches the specialist (the review read each one).

### 2.5 The reviews screen (app, `/provider/:id/avis`, Q3)

- **The bar:** back arrow, title **« Avis »**.
- **The summary card:**
  - the salon's name, from a copy taken when the screen opens, if the page slot then holds this salon (always, coming from its page; §5);
  - **the average** large (« 4,6 », one star) and **« 23 avis »**;
  - **the five bars** (5 → 1, each with its count), from the server's `summary` (Q4). With no `summary` (a server before A5-api), the average and count come from the salon, and no bars are shown. Bars from one loaded page would describe only that page.
- **The list:** `ReviewTile`, each with « Signaler » (§2.6), newest first, 20 per page.
- **The footer** follows decision 231's pattern (consumer-search.md §2.6):
  - **« Afficher plus d’avis »**, shown while fewer are loaded than the newest `total`;
  - a loader in its place while the next page comes;
  - if that page fails, **« Impossible d’afficher la suite. »** with « Réessayer ». The reviews stay;
  - pages are de-duplicated by id;
  - a screen reader hears « 20 avis de plus, 40 sur 63 ». This is new in the app: its salon list announces only first answers (`provider_list_screen.dart:81-106`). The sentence is the website's (`RechercheClient.tsx`).
- **At the bottom, always: « Réserver »**, full width, pushing `/booking?providerId={id}`. Whoever reads the reviews is deciding.
- **Pull to refresh** starts again at page 1.

**States (SYSTEM §12):**

| State | What shows |
|---|---|
| Loading (page 1) | The bar, a summary skeleton and three review skeletons |
| Success | §2.5 |
| Empty (`total` 0; the reviews were hidden since the count was read) | No summary card (never « ★ 0,0 · 0 avis », `app_rating.dart`), « Pas encore d’avis. », « Réserver » |
| Page 1 failed (connection, server) | `SalonUnavailableView` with the service's own sentence and « Réessayer » (app-failure-messages.md) |
| The salon is no longer public (404, Decision C) | `SalonUnavailableView`'s `not_found`: « Ce salon n’est plus disponible sur MyWeli. » and its way to the salons (`kDiscoverSalonsCta`), as the salon page |
| A later page failed | The footer's line and « Réessayer »; what was read stays |

### 2.6 « Signaler » for a guest (app, Q5)

- **Today:** a snackbar, and nothing else (§0).
- **A5:**
  - a guest's « Signaler » opens the sign-in over the page with a new reason line, **« Connectez-vous pour signaler un avis. »** (`SignInReason.report`);
  - signed in, they are back on the same screen and **the report dialog opens for that review** (reason optional, as today);
  - closed without signing in: back where they were, nothing reported, no snackbar;
  - this is the heart's pattern (A3, `heartAfterSignIn`).
- **The same on the salon page and the reviews screen.**
- **In the « Aperçu »:** no « Signaler » (`onReport` null), as no heart and no « Donner mon avis ».

### 2.7 The website (A5w, Q6)

It follows the app's flow (§2.1) in the website's own layout (web-mirror-app-flow, web-design-latitude).

- **« Équipe »:**
  - the section moves right after « Services », as in the app;
  - each person is a row: photo or initial, name, specialty, rating from 1 review;
  - **« Réserver »** is a link to `/{slug}/reserver?artist={id}`. Its accessible name is « Réserver avec {nom} », with the rest in visually hidden text, so the list's links are told apart (WCAG 2.4.4);
  - no link for a person who does no active service;
  - seven or more: five and « Voir toute l’équipe (N) », as §2.2;
  - in the preview, rows without links.
- **Reviews:**
  - the ten embedded stay;
  - **« Afficher plus d’avis »**, a secondary full-width `Button`, shown while fewer are shown than `total`. It reads the next 10 through a new same-origin route, **`GET /api/avis?salon={id}&page={n}`**. It is not under `app/api/providers`, which `no-public-provider-read.test.ts` forbids. The route:
    - **checks the salon id** with `SALON_ID_PATTERN` (`lib/pro/notifications.ts:28`) and answers 400 otherwise. The id goes into the API's path, and `..` survives `encodeURIComponent`;
    - forwards `page` and fixes `pageSize` at 10, so page 2 starts at the 11th, after the embedded ten (both reads use the same order);
    - sends no cookie, and answers a lost body with 502, as `/api/recherche` does;
    - passes a 404 through. The page then says « Ce salon n’est plus disponible sur MyWeli. » in the button's place, with no « Réessayer »;
  - loading: the button's spinner (`aria-busy`). Failure: « Impossible d’afficher la suite. » with « Réessayer ». Appended reviews are de-duplicated by id;
  - after a page lands: the focus moves to the first new review, only when it was on the button, and a polite status says « 10 avis de plus, 20 sur 63 » (A4w's rules);
  - **the bars:** above the list, from `summary`, read server-side on page render when A5-api is there, otherwise none. **That read fails open:** a missing `summary` or a failed read means no bars, never `unreadable()`, which throws in a production build (`lib/api/public-read.ts:20-26`) and would stop every salon page from building before A5-api;
  - not in the preview (a draft salon's public route answers 404).
- **Each review** gains « avec {artiste} » and « Réservation vérifiée » (the app's words, FR-REV-002/003).
- **The funnel's services** dim as §2.4 (`lib/booking/state.ts` and `BookingFlow`).
- **The JSON-LD stays as it is:** `aggregateRating` and the first five reviews (`lib/seo/jsonld.ts`). Reviews read after a tap are not in the HTML a crawler reads, which is right: the page's figures already describe the salon. Team names are not added to structured data.

### 2.8 Edge cases

- **A review written while someone reads** pushes the list down by one. The de-duplication hides the repeat; one review can then be missed until a refresh, as with paging by offset anywhere (consumer-search.md §3.3).
- **A review hidden by moderation meanwhile** pulls the list up by one. The newest `total` decides whether the button stays.
- **A review written again** (same visit) moves to the top with its new date; the de-duplication keeps it once.
- **The count on the salon page and the screen's `total` disagree** (a review hidden in between): the screen shows the server's newer figures.
- **A team member with no photo, or a photo that fails:** the initial. **A long name:** two lines, then an ellipsis; at 200 % the row grows.
- **A member removed from the salon** while the page was open: the hub drops the unknown `artistId` (checked whenever it is sent, §2.4) and opens on « Pas de préférence ».
- **A member's hours:** with none of their own they take the salon's (`slot_service.dart:261-263`). One whose own hours leave no day is shown and bookable, and the hub says there is no slot, as today.
- **A salon with no team:** no section, as on the website today.
- **A salon with no active service:** no row has « Réserver ».
- **The website's embedded ten** can be up to 300 s old (`revalidate = 300`), which widens the first edge case's window; the de-duplication covers it.

### 2.9 Accessibility (SYSTEM §13, WEB-SYSTEM §4–§8)

- **Team rows** are one button each (≥ 48 dp), labelled « Réserver avec Awa Koné, coiffeuse, note 4,8 sur 5, 12 avis ». The photo is decorative.
- **The summary card** reads « Note moyenne 4,6 sur 5, 23 avis ». Each bar row reads « 5 étoiles : 12 avis », and the bar itself is excluded.
- **At 200 % text** (360 dp): the team row wraps « Réserver » under the name rather than squeezing it; the summary card stacks the bars under the average; the footer's line and its button wrap.
- **The hub's dimmed services** keep 4.5:1 for their second line: it is written in `textSecondary`, not faded with the row.
- **Web:** `<section>` with `<h2>`, `<ul>`/`<li>`, a visible focus ring, axe clean.

### 2.10 Copy, all of it

| Where | French |
|---|---|
| Section title (app, web) | Équipe |
| A team row's action | Réserver |
| A team row's label (semantics; web's accessible name) | Réserver avec {nom}[, {spécialité}][, note {x} sur 5, {n} avis] |
| More than six | Voir toute l’équipe ({N}) |
| Under the five reviews (app) | Voir les {N} avis |
| The reviews screen's title | Avis |
| Its summary (semantics) | Note moyenne {x} sur 5, {n} avis |
| A bar (semantics) | {k} étoiles : {n} avis |
| The footer's button (app, web) | Afficher plus d’avis |
| A later page failed | Impossible d’afficher la suite. · Réessayer |
| Announced after a page | {k} avis de plus, {m} sur {n} |
| No review left | Pas encore d’avis. |
| The bottom button | Réserver |
| A dimmed service | Pas avec {nom} |
| The specialist dropped (the one case) | {nom} ne fait pas cette sélection. Choisissez un autre spécialiste. |
| Sign-in's reason line | Connectez-vous pour signaler un avis. |
| Each review (web, new) | avec {artiste} · Réservation vérifiée |

---

## 3. API & contract — A5-api (Q4)

`GET /providers/{id}/reviews` gains **`summary`**, the `ReviewSummary` Pro's route already sends (`ReviewsService.summary`: average to one decimal, count, the 5 → 1 split, visible reviews only), **on every page**, so the card never describes a page.
- **Contract:** `summary` added to the 200's properties and to `required`; the description says it is the whole salon's. `ReviewSummary`'s own description, « sent with every page of `/me/provider/reviews` » (`openapi.yaml:6409`), names both routes.
- **The website's types are regenerated in the same PR:** CI runs `npm run gen:api` and fails on any diff in `web/lib/api/schema.ts` (`ci.yml:637-638`), on every PR.
- **The order ends on the id** in both twins, the Postgres query (`ORDER BY created_at DESC, id DESC`, both public reads) and the in-memory repository (the both-twins rule).
- **Unchanged:** the 404 for a salon that is not public (Decision C, T51), the clamp at 50, `GET /providers/{id}` embedding 10.
- **Cost:** one aggregate and one split per page read, the same two queries Pro's route makes. Both use the `provider_id` index.
- **Threat model:** no new endpoint and no new field about a person; the split is derived from reviews already public. T51 holds: a draft salon still 404s before any count is read.

**The app's service** (A5): `getProviderReviews` returns a `ReviewPage {items, page, pageSize, total, summary?}`.
- A failed connection becomes `networkError()`.
- A refusal goes through `errorFromResponse` (so a 404 carries `not_found`).
- A body that does not read becomes `readOrUnreadable`, the salon list's three facts (app-failure-messages.md §1.2).
- `summary` is optional on the client, so the app works against a server before A5-api.

**The website:** `/api/avis` (§2.7). The page's server read of `summary` uses `lib/api/public-read.ts`.

## 4. Data model

No migration. `ReviewPage` (app) mirrors `ProviderPage`. `ReviewSummary` (app, `models/review_summary.dart`) is reused.

## 5. Architecture & patterns

- **The reviews screen has its own state:** a screen-scoped `SalonReviewsController` (a `ChangeNotifier`, like A4's `SalonSearchController`) over `ReviewServiceInterface`. It is not `ProviderProvider`, whose one page slot is shared (consumer-reviews.md, « The page slot is not the open salon page »).
- **The salon's name and its fallback figures** are copied from `ProviderProvider` when the screen opens, if its slot holds this salon id, as the salon page keeps its own copy. A later read can empty the slot: « Réserver » opens the hub, and a failed hub read writes `null` into it (`provider_provider.dart:358-367`). Otherwise the title alone and the server's summary.
- **The route:** `/provider/:id/avis`, a sub-route of `/provider/:id`, pushed. It is absent from MyWeli Pro's router, as `/carte` is. MyWeli Pro reaches the salon page's file (the « Aperçu »), so `route_literals_test.dart` needs `/provider/{}/avis` in its `_exempt['pro']` (:323-337), with its reason. A behavioural test holds the reason: the preview shows no button.
- **Shared widgets, extracted rather than copied:**
  - `ReviewSummaryCard`, the average plus the bars, taken out of Pro's `ReviewsScreen` (:131-260) with its 200 % fixes:
    - a mode with no bars (the consumer, before A5-api). Pro keeps its fallback of counting the loaded reviews (`review_card.dart`);
    - stacking the bars under the average at 200 %, which Pro's `Row` does not do today. Pro gains it at 200 %;
    - at 1× Pro shows no visible change: `pro_reviews_w360` stays byte-identical, and the 200 % bar check stays green (`layout_test.dart:843-878`);
  - `TeamMemberRow`;
  - `reportReviewFlow`, the sign-in, then the dialog, then the report, used by both screens. It reads the client's `AuthProvider`, which MyWeli Pro does not register, so it must never run in the « Aperçu ». `onReport` is null there; a test in `salon_preview_test` holds it.
- **The hub's rule** is one function per surface, which already exists: `_artistCanDoServices` / `artistCanDoServices`. The dimming reuses it, and no second rule is written.
- **The mock:**
  - pages, `total` and `summary`;
  - latency;
  - an error on demand and an empty salon;
  - a seeded salon with seven people, for the goldens and the « more » paths.
  - **One rule reconciles it:** in the mock, the screen never contradicts the page. Today a seeded figure stands for reviews the list does not hold (« 120 avis », three listed: `mock_data.dart`, `mock_review_service.dart:36-39`). So the mock generates each seeded salon's missing reviews, deterministically, up to its count, and with its average.

## 6. Security & privacy

- **Nothing new is read about anyone.** Team members' names, photos and specialties are already in the public salon read and on the website; the bars are derived from public reviews.
- **The report** still needs a consumer session (server-checked), and is idempotent per reporter.
- **Sign-in's return** stays in-app (`safeReturnTo`). The dialog reopens only for the review whose « Signaler » was tapped, on the screen that is still there.
- **`/api/avis`** forwards the salon id and the page only, fixes the size, and sends no cookie. The salon id is a path segment on the API side, already public. A non-public salon is 404 from the API, passed through.
- **The preview** never shows a client action (§2.2, §2.3, §2.6).

## 7. Performance

- **The salon page:** nothing new is read; the team is in the same payload. Photos are 48 dp, cached and lazy.
- **The reviews screen:** one read per page (20), built lazily (`SliverList`), photos lazy. No read before the screen opens.
- **Website:** no new read before a tap; `summary` adds nothing to the page's own read when A5-api is absent. With A5-api, one extra server read per ISR render (300 s), or fold it in by asking page 1 at size 10, which also gives `summary`. Decided at build, by measurement.

## 8. Testing plan

**A5-api:**
- `summary` on page 1 and page 3, with hidden reviews excluded;
- the order's tiebreak with equal dates, on both twins (the DB-gated suite);
- the 404 for a draft salon is unchanged;
- the contract test.

**A5 (unit and widget):**
- the controller: page 1, the append and its de-duplication, `total` ending the button, a failed later page keeping the list, the 404, pull to refresh, `summary` absent;
- the service: `networkError`, `not_found`, an unreadable body, `summary` optional;
- the salon page: « Équipe » present at 1 member, absent at 0; seven members give five plus the button, and six give six; a member doing no service has no button; the push carries `artistId`; « Voir les N avis » appears only when `reviewCount` exceeds what is shown, and never in the preview;
- the hub:
  - an `artistId` sent alone and unknown opens on « Pas de préférence » and is not sent;
  - sent alone and known, it counts as specialist first, and the earliest slot is proposed after a service;
  - with a specialist chosen, a service they do not do is dimmed with its line and cannot be ticked, and a ticked service is never dimmed;
  - a faded specialist says why;
  - both remaining drops say so;
  - an inactive service is not listed;
  - rebook is unchanged;
- « Signaler » as a guest: the sign-in with `SignInReason.report`'s line; after signing in, the dialog for that review; closed, nothing;
- the reviews screen with no review: no summary card, never « ★ 0,0 »;
- `route_literals_test` with the new exemption, and `salon_preview_test`: no « Voir les N avis », no « Signaler », no « Réserver » on a team row.

**A5 (a11y and goldens, SYSTEM §20.1):**
- `labeledTapTargetGuideline` on the salon page and the reviews screen;
- 200 % on both at 360 dp;
- new goldens of the reviews screen (success, the footer's failure) and the salon page's « Équipe » at 1× and 200 %;
- **existing goldens that will change:** `consumer_provider_detail`, `…_no_photo` and `…_w360_x2` gain « Équipe » and « Voir les N avis » (the mock's `provider1` has a team and 120 reviews). `consumer_booking_hub` should not change: the mock has no inactive service and no specialist is chosen. This is checked at the build, not assumed;
- Pro's « Avis » goldens byte-identical after the extraction;
- every changed PNG opened.

**A5w:**
- RTL: the rows and their accessible names, the « more » paths (button, append, de-duplication, failure, focus, status), the review's new words, the funnel's dimming in `state.ts`;
- the route: its allowlist, the salon id checked (400 on `..` and others), the fixed size, 502 on a lost body, a 404 passed through to the page's sentence;
- the salon page still builds when the summary read fails or has no `summary`;
- e2e with the stub paging 25 reviews and seven people: « Réserver » lands on the funnel with the person chosen; « Afficher plus d’avis » twice; a failing page; axe on `/{slug}`.

**Mutations** (every new guard watched red on committed code, the list in each commit message):
- `take(5)` without the button;
- the button shown at `reviewCount` = 5;
- no de-duplication;
- `total` ignored;
- the bars drawn from the page;
- the dimming turned off;
- the silent drop restored;
- the preview showing a client action;
- `/api/avis` forwarding `pageSize`;
- the tiebreak removed (A5-api);
- the `artistId` check skipped when it comes alone;
- a ticked service dimmed;
- the summary read failing closed (A5w);
- `schema.ts` left stale (A5-api, the CI diff).

**Device rows** (with the next client build, Track C): a salon with a team. Tap a person, book with them. Open « Voir les N avis », « Afficher plus », report as a guest.

## 9. Rollout & scope discipline

- **Order (Q7): A5-api, then A5, then A5w.** Neither client waits for A5-api's deploy: without `summary` they show no bars and everything else works.
- **A5-api** reaches production with a backend deploy, on the owner's word.
- **A5** reaches people with the next client build (Track C), on the owner's word.
- **A5w's merge is a production deploy of `myweli.com`**, on the owner's word, then read back on `myweli.com`.
- **What production can show today:** one public salon (« test »). « Afficher plus » and seven people need the stub, the mock and the e2e, and are said so in each read-back.
- Each PR has its own French roadmap entry, and none is merged without the owner's word.

## 10. Definition of done

- **App:** `flutter analyze` 0; the full suite green; goldens from `goldens.yml`, each opened.
- **Website:** typecheck, lint, unit, e2e and axe green.
- **Backend:** format, analyze, the DB-gated suite and the contract.
- **The four states** on the reviews screen; French copy as §2.10.
- **Docs:**
  - this spec's « As built »;
  - SYSTEM.md (the new shared widgets in the catalogue);
  - the audit's A5 row and gap 18;
  - PRD FR-DISC-006's note;
  - BACKLOG B0.10's journal and decisions 277–283.

## 11. Questions for the owner (decisions 277–283)

**Q1. What does a tap on a team member do?** [decision 277]
- *Recommended:* it opens the booking hub with them chosen (« Réserver »). It is one tap to book with the person you came for, and the hub and the website's funnel already take a chosen specialist (rebook uses it).
- *Alternatives:* show the team without any action, as the website does today; or a sheet per person with their rating and « Réserver avec … ». The sheet adds a step, and its only new content would be what the row already shows.

**Q2. In the hub, a specialist chosen first: dim the services they don't do?** [decision 278]
- *Recommended:* yes, on both surfaces, with « Pas avec {nom} », by the rule that already fades the specialists, and a faded specialist says why. Arriving from the team row counts as « specialist first », so their earliest slot is proposed. When the specialist must still be dropped, the hub says so (§2.4).
- *Alternative:* leave the hubs as they are. Ticking such a service then drops the person the client just chose, without a word, which « Réserver avec … » would make an everyday path.

**Q3. Every review in the app: a screen of its own, with a button for more?** [decision 279]
- *Recommended:* yes, `/provider/:id/avis`, 20 per page, « Afficher plus d’avis » (decision 231's reasons: the person decides what the next page costs, and it is reachable and testable), with « Réserver » at the bottom.
- *Alternatives:* load more on scroll; or open the rest inside the salon page. The page then grows long and is built all at once on a low-end phone.

**Q4. The rating split (the 5 → 1 bars) for clients: a small server change, A5-api?** [decision 280]
- *Recommended:* yes. The server already computes it for Pro, and the change sends it on the public list and gives the order its tiebreak. It is one backend PR, deployed on the owner's word. Both clients work without it until then.
- *Alternative:* no bars: the average and the count only.

**Q5. A guest taps « Signaler »: sign in, then report?** [decision 281]
- *Recommended:* yes. The sign-in opens over the page with its line, then the report dialog for that review, as the heart does since A3.
- *Alternative:* open the sign-in only, and let them tap « Signaler » again.

**Q6. The website's half, A5w?** [decision 282]
- *Recommended:* yes, its own PR after A5:
  - the team rows with « Réserver »;
  - « Afficher plus d’avis » in place on the salon page, through `/api/avis`. A second page per salon would add a route to the static build, the middleware fallback and the sitemap for the same content, and on a computer the booking panel stays beside the reviews;
  - « avec … » and « Réservation vérifiée » on each review;
  - the funnel's dimming.
- *Alternative:* a page `/{slug}/avis`, like the app's screen.

**Q7. The order, and who waits?** [decision 283]
- *Recommended:* A5-api, then A5, then A5w. No client waits for A5-api's deploy, since the bars appear once it is there.
- *Alternative:* A5 and A5w wait for A5-api in production, so the bars ship with the first build that has the screen.

## 12. Independent review (2026-11-27)

A reviewer told to refute the spec read it against the code. **No blocker; 18 findings**, each re-read in the code, then taken in above.

**Two would have turned a build red as written:**
- the website's summary read through `public-read.ts` fails closed in production, so before A5-api every salon page would have stopped building (§2.7);
- A5-api without regenerating `web/lib/api/schema.ts` fails the web job's contract diff (§3).

**The others:**
1. The app does not check an `artistId` sent alone: a removed member's id would be booked against (§0, §2.4).
2. The dimming had to say « a service not ticked », or it would dim services the specialist does do in an incompatible rebook (§2.4).
3. Arriving from the team row never counted as « specialist first », so Awa's earliest slot was never proposed (§2.4).
4. The app lists inactive services; the website and the server do not. Now in A5's scope (§1).
5. `/api/avis` puts the salon id into a path: checked with `SALON_ID_PATTERN` (§2.7).
6. `route_literals_test` would go red on the new route from the « Aperçu »'s file: an exemption, held by a test (§5).
7. Three existing goldens change, and the mock's « 120 avis » would contradict its own list (§5, §8).
8. The empty screen would have shown « ★ 0,0 · 0 avis », against `app_rating.dart`'s rule (§2.5).
9. Pro's card has no 200 % stacking and no « no bars » mode (§5).
10. §0 said a 404 reached the app as a generic error. It already carries `not_found` (§0).
11. The « N avis de plus » announcement is new in the app, not the salon list's (§2.5).
12. `AppRating` has no `small`: `compact` (§2.2).
13. A member with no hours of their own takes the salon's (§2.8).
14. The reviews screen could lose the salon's name when the hub's read failed: it keeps a copy (§5).
15. The faded specialists never said why: they do now (§2.4).
16. On the website, a 404 from `/api/avis` would have offered « Réessayer » forever, and the embedded ten can be 300 s old (§2.7, §2.8).

**Checked and found true**, among others: every line of §0's salon page, server and website; go_router building only the reviews screen when it is pushed over the salon page; the sign-in popping back to the same screen before it answers; page 2 at size 10 starting at the 11th review; `ReviewsService.summary` reusable as it is.

## 13. Seen in passing (not A5)

- **The capability rule's leniency** (app, website and server, `slot_service.dart:250-253`). A booking holding one unrestricted service accepts any specialist for all its services, including one restricted to someone else. Awa can then be booked for a service only Bintou does. Changing it is a server rule and its own decision; A5 follows it as it is (§2.4).
- **Reviewers' full names are public** (`reviews_service.dart:188`: the account's `name`). Many platforms show « Awa K. ». It is a privacy and product decision, the same on five reviews or fifty.
- **The public review carries `userId`** (`openapi.yaml`, `Review`), an opaque id. It is not shown, but lets someone link one reviewer's reviews across salons. Part of the same decision.
- **Review dates:** the app formats them on the phone's clock (`review_tile.dart`, `formatDateShort`), the website in the salon's (`ReviewList.tsx`, `tz`). They differ only across midnight between time zones.
- **Pro's « Avis »** reads its first 50 reviews and stops (`reviews_screen.dart`).
