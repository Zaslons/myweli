# Consumer reviews — design spec

| | |
|---|---|
| **Status** | Built |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-13 (§2 « After Publier » — incl. who takes the re-read's answer, and the two copies it does not reach —, §5 mock — [amounts-that-fit.md](amounts-that-fit.md)) |
| **PRD ref / phase** | Reviews — post-completion + photos · V1 (PRD §8.2) |
| **ROADMAP entry** | Phase 3 — Backend build + integration (added on build) |
| **Skills checked** | myweli-backend-guardrails ✓ + myweli-dev-guardrails (review feed is user-facing) |

## 1. Goal & scope

Put consumer **reviews** on the real backend — review a **completed appointment**, read a provider's reviews — replacing `MockReviewService`, and make the provider's **and each artist's** `rating`/`reviewCount` real (computed from reviews, not seed constants).

**Model (signed off): per-visit, artist-attributed** — like Fresha/Booksy/YCLIENTS. One review **per completed appointment**; the server derives provider, **artist**, **service**, reviewer name, and `verified` **from the appointment** (the client can't forge them). Each review feeds **both** the salon's rating and the performing **artist's** rating. The feed is **flat, newest-first**, each card showing the service + "avec [artiste]".

**In scope:**
- Backend: `POST /appointments/{appointmentId}/review` (consumer-auth; the appointment must be the caller's **and** `completed`) + `GET /providers/{id}/reviews?page=&pageSize=` (public, paginated). New `reviews` table (migration `0007`), `ReviewsRepository` (in-memory + Postgres), `ReviewsService`. Submitting **recomputes the provider's rating + reviewCount and the attributed artist's** rating/reviewCount. The provider **`byId` read embeds the latest 10** reviews; the list `query` does not (no N+1).
- App: `ReviewServiceInterface` → `submitReview(appointmentId, rating, text, photoUrls)` + `getProviderReviews(providerId, {page})`; real `ApiReviewService` under `useApiBackend`. `Review` gains `appointmentId` + `serviceName`.
- Contract + threat model + tests (incl. DB-gated).

**Out of scope:** provider replies; moderation/reporting; standalone artist reviews (attribution only); grouping the feed by user.

**Build:** one PR (backend + app).

## 2. UX & flows
The provider detail screen shows `rating` + `reviewCount` + `reviews.take(5)`; the reviews screen lists them; the post-completion "leave a review" flow submits against the completed appointment. Each review **card** renders: reviewer · rating · date · **service** · **"avec [artiste]"** (when an artist did it) · photos. Flat newest-first; a regular's visits appear as separate dated cards. French copy; the four states already exist.

**After « Publier » (app, 2026-10-13 — [amounts-that-fit.md](amounts-that-fit.md) §2, §5).**
The 201 carries the review and nothing of the salon, so the app works the
figures out, then asks:

1. **At once, without a read** (`ProviderProvider.addReviewLocally`): the
   review is the **first** tile; a visit reviewed again **replaces** its tile
   and keeps the count (matched on a non-empty `appointmentId` — never on the
   review `id`, which the 201 mints anew on a resubmit), a first review of a
   visit adds one. The same `rating` and `reviewCount` go onto every copy of
   the salon in memory — the salon page when it is this salon's, the list, the
   featured list, and the favourites (`FavoritesProvider.patchSalonFigures`,
   handed over by the sheet) — whichever salon page is open, or none.
2. **Then one background read of `GET /providers/{id}`**
   (`rereadSalonAfterReview`): not awaited by the sheet, limited to
   `AppConstants.reviewRereadTimeout` (10 s). An answer puts the server's
   average and count on the list, the featured list and the favourites —
   **whichever salon holds the page slot, or none** — and, when the slot
   holds this salon, replaces it whole: the stored review id comes with it.
   A refusal, a failure or the time limit changes nothing and shows nothing;
   so does an answer that arrives after a later review of the same salon was
   applied.

**The page slot is not « the open salon page ».** It is one, shared, and it
outlives the page that took it: the last salon page, booking hub or booking
confirmation opened holds it for the rest of the session. A review published
from « Mes rendez-vous » of another salon than the slot's is therefore an
ordinary case, not a race. The slot takes the answer only while it actually
holds this salon — not when it holds another, and not when it is empty
because this salon's own read failed or has not answered yet; the lists and
the favourites take it all the same. (As first built, an answer arriving
while another salon held the slot was dropped whole — which lost the server's
figures for every review published after another salon had been opened, and
left « Nouveau » on a favourite held in no list until the app restarted.
Fixed 2026-10-13.)

What step 1 cannot know, and step 2 corrects when its answer is taken: the
average is rebuilt from the stored one-decimal figure, so it can sit 0,1 from
the server's; and an earlier review of the visit that is neither among the ten
embedded reviews nor posted in this session is counted as new. Step 1 counts
from the page's copy first — the only one that embeds reviews —, else the
list's, else the featured list's; it needs one of them: a salon held only as a
favourite moves with step 2 alone. The web form does no arithmetic and is
unchanged.

**Two copies neither step reaches** — each belongs to a screen, not to a
notifier:

- **A salon page covered by another salon's page** (the map's « Voir le
  salon »). It renders its own copy and takes the slot back with it
  ([salon-location-map.md](salon-location-map.md) §2.7): a review applied, or
  an answer taken, while it was covered shows on the lists and not on that
  page until its next read.
- **The map's copy of a centred salon the loaded list does not hold**
  (`MapScreen._focused`). The markers are built from the list rows, which are
  patched, and a sheet opened from one shows that row; `_focused`, used only
  when the list has no row, keeps the figures it was opened with — and a
  sheet already open is not rebuilt.

## 3. API & contract
- **`POST /appointments/{appointmentId}/review`** — **consumer** token. The appointment must belong to the caller (`userId == sub`) and be **`completed`** (→ 403 `forbidden` / `not_completed`). Body: `{ rating:1..5, text, photoUrls? }`. The server derives `providerId`, `artistId`/`artistName`, `serviceName` (from the appointment + the provider's services), `userName` (profile), `verified=true`, `id`, `createdAt`. **One review per appointment** — resubmitting replaces it (upsert on `appointment_id`). → **201** the stored `Review`; recomputes provider + artist ratings.

  **Photos on a resubmit (2026-08-15).** A wholesale replace re-sends urls the
  server itself issued, so a `photoUrls` entry may be either a **new** upload
  (still under `pending/`, which is promoted and stored at its promoted url) or
  **exactly** one already stored on this appointment's review, which passes
  through untouched. Anything else → 400 `invalid_input`. Matching is by
  membership against the stored row, never by shape — a promoted-looking url is
  indistinguishable from one the client invented.

  Two consequences worth stating. **The promotion runs AFTER the ownership and
  status checks**, so a refused request never moves an object out of `pending/`
  (it used to: the block sat above them, and `AppointmentRepository.byId` is not
  ownership-scoped, so any caller could orphan objects nothing collects).
  And **a dropped photo is not deleted** — no save path in this codebase deletes
  a dropped object, and while the forms send an empty list on every resubmit the
  "dropped set" is every photo, involuntarily. Revisit when the forms prefill.

  **The forms do not prefill.** Rating, text and photos all start blank on both
  clients, and no endpoint returns the caller's own review, so "modifier un
  avis" is not a flow that exists — see §9.
- **`GET /providers/{id}/reviews?page=&pageSize=`** — **public**, paginated `{ items, page, pageSize, total }`, newest first; `pageSize` clamped (default 20, max 50).
- **`GET /providers/{id}`** now returns accurate `rating`/`reviewCount` (+ per-artist in `artists[]`) and a **bounded recent `reviews`** array (latest 10).

Errors: 400 `invalid_input`, 401, 403 `forbidden`/`not_completed`, 404 (unknown appointment/provider), 405.

## 4. Data model
New table (migration `0007_reviews`):
```sql
CREATE TABLE IF NOT EXISTS reviews (
  id             text PRIMARY KEY,
  appointment_id text NOT NULL UNIQUE,          -- one review per visit (upsert)
  provider_id    text NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  user_id        text NOT NULL,
  user_name      text NOT NULL,
  rating         smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
  text           text NOT NULL DEFAULT '',
  verified       boolean NOT NULL DEFAULT true,
  artist_id      text,
  artist_name    text,
  service_name   text NOT NULL DEFAULT '',
  photo_urls     jsonb NOT NULL DEFAULT '[]',
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS reviews_provider_idx ON reviews (provider_id, created_at DESC);
```
`rating`/`reviewCount` stay denormalized on the provider (`data` + the indexed `rating` column) and on each artist (in `data.artists[]`) — recomputed on submit so reads/sorting never aggregate on the hot path.

## 5. Architecture & patterns
- **`ReviewsRepository`** (in-memory + Postgres): `upsertByAppointment(review)`, `listForProvider(id, {page,pageSize}) → (items,total)`, `recentForProvider(id, limit)`, `aggregateProvider(id) → (avg,count)`, `aggregateByArtist(id) → {artistId: (avg,count)}`.
- **`ReviewsService.submitForAppointment(userId, appointmentId, {rating,text,photoUrls})`**: load the appointment (`AppointmentRepository.byId`) → 404 if missing; owner check (`userId`) + `status==completed` (→ forbidden/not_completed); resolve `serviceName` from the provider's services for the appointment's `serviceIds`, `artistId`/`artistName` from the appointment; `userName` from `AuthRepository`; build the server-owned `Review`; `upsertByAppointment`; then **recompute** provider rating/count + each artist's via `ProvidersRepository.updateRatings(...)`. `list(id, page)` delegates.
- **`ProvidersRepository.updateRatings(providerId, {rating, reviewCount, artists: {id: (rating,count)}})`** — atomic read-modify-write of `data` (provider rating/count + matching `artists[]` entries) **and** the indexed `rating` column. Mirrors `updateGallery`/deposit.
- **Provider read:** `byId` embeds `recentForProvider(id,10)`; `query` leaves `reviews` empty.
- **Routes:** `routes/appointments/[id]/review.dart` (POST) + `routes/providers/[id]/reviews/index.dart` (GET). DI + middleware provide the repo + service.
- **App:** `ApiReviewService` (consumer session + silent refresh): `submitReview` → `POST /appointments/{id}/review`; `getProviderReviews` → `GET /providers/{id}/reviews`. `Review.toJson/fromJson` (+ `appointmentId`, `serviceName`).
- **App, mock mode (2026-10-13):** `MockReviewService.submitReview` stores the review in `MockData.reviews` — the list the mock salon read answers from — **one per appointment**, and moves the mock salon's `rating`/`reviewCount` with the write (one more for a new visit, none for a visit reviewed again; `core/utils/salon_figures.dart`). It used to append to a list nothing read back, so any read after a submit erased the review. The seeded figures are untouched until a review is posted.

## 6. Validation & authority
- `rating` ∈ 1..5; `text` ≤ 1000 chars (trimmed, may be empty); `photoUrls` ≤ 6, each non-empty ≤ 2048 and origin-allowlisted when public delivery is configured (reuse the gallery rule).
- **Server-owned from the appointment/profile:** `id`, `providerId`, `artistId`/`artistName`, `serviceName`, `userId`, `userName`, `verified`, `createdAt`, and the recomputed ratings. The client supplies only rating/text/photos.

## 7. Security & authz
- `POST` requires a **consumer** token; the **appointment must be the caller's own and completed** (→ 403) — only the real customer of that visit can review it, exactly once (upsert by `appointment_id`). A provider token can't post (no consumer appointment).
- `GET` is public (reviews are public profile content).
- **Threat model:** new **T14** — author identity, `verified`, attribution (artist/service), and the provider+artist ratings are all **server-derived from the owning completed appointment** (no forging a reviewer, a verified badge, an attribution, or a rating); content validated/bounded; photo origins allowlisted like the gallery.

## 8. Performance
- `GET` paginated + indexed (`provider_id, created_at DESC`). Submit: byId + upsert + two aggregates + one provider write, in a tx. `byId` embed = bounded top-10 indexed read; `query` does no per-row review fetch (no N+1). Ratings denormalized → list sort = one indexed column.

## 9. Testing plan
- **Repo (unit + DB-gated):** upsert-by-appointment replaces; `listForProvider` paginates newest-first + total; `aggregateProvider`/`aggregateByArtist` correct.
- **Service (unit):** non-owner / not-completed / unknown appointment → forbidden/not_completed/not_found; happy path sets verified + derived fields + serviceName + recomputes provider **and** artist ratings; resubmit replaces (count steady, rating updated); bad rating/text/photos → invalid_input.
- **Handler:** `POST` → 201; not owner → 403; not completed → 403; unknown appt → 404; bad body → 400; no token → 401; `GET` paginated → 200; bad verb → 405.
- **Read assembly:** after submit, `byId` shows the review + updated provider/artist ratings; `query` reflects the rating without embedding reviews.
- **App:** `submitReview` POSTs + parses; `getProviderReviews` GETs a page; 401 → consumer refresh; `not_completed` surfaced.

## 10. Definition of done
- [ ] `dart format` clean · `dart analyze` 0 (backend + mobile) · tests green (incl. DB-gated).
- [ ] OpenAPI: the two paths + `Review` schema (+ `appointmentId`/`serviceName`); `Provider.reviews` = bounded recent set.
- [ ] Threat model T14; ROADMAP entry; spec cross-linked; status → Built.
- [ ] Feature-branch + PR; CI green; no Claude attribution.

## 11. Decisions (signed off)
1. **Per-completed-appointment reviews, artist-attributed** — one review per visit; the server derives provider/artist/service/reviewer/verified from the appointment; each review feeds **both** the salon's and the artist's rating (no standalone artist reviews). ✓
2. **Post-completion gated** — must be the caller's own `completed` appointment; `verified` always true. ✓
3. **Flat, newest-first feed** with service + artist per card (not grouped-by-user). ✓
4. **Photos accepted now** — `photoUrls` ≤ 6, validated + origin-allowlisted like the gallery (uploaded via the R2 pipeline). ✓

## 9. Open — « modifier un avis » is not a flow

Both forms are write-only: `_selectedRating = 0`, an empty text controller and
`_photoUrls = []` on mobile; `useState(0)/useState('')/useState<string[]>([])`
on web. Neither component can even *receive* an existing review — the mobile
sheet takes providerId/appointmentId/artistName/onSubmitted, the web component
takes `{ appointmentId }`. Every entry point gates on `status == 'completed'`
alone, with no already-reviewed check, and the copy is « Donner mon avis » /
« Laisser un avis » on both. The word « modifier » appears on no review surface.

So a user who reviews twice gets a blank form and retypes rating and text
**because they can see those fields are empty**. Photos are the one field where
the loss is invisible: the form never showed them, so there is no cue to
re-attach, and the submit replaces a populated `photo_urls` with `[]`.

What the app shows AFTER such a second submit is no longer wrong (2026-10-13,
§2): one tile and a steady count, where it used to show both reviews and count
two. The entry points and the blank form are as described here.

Making that work is a **feature, not a bug fix**, and it needs decisions this
spec cannot make alone:

- a read for the caller's own review (`GET /appointments/{id}/review`, mirroring
  the GET+POST shape of `/me/kyc`), plus the client service/mock/BFF wiring;
- an « already reviewed » state on both entry points, and copy for it;
- the photo cap disagreement: the backend allows 6, both clients allow 3;
- whether editing should then delete the photos it drops (see §3).

Deliberately not built alongside the claim-path fix.
