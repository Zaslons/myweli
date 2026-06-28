# Web M8.3 — account extras: rebook · laisser un avis · favoris

| | |
|---|---|
| **Requirement** | FR-WEB-MP-002; closes parity gap **G4** ([web-parity-audit.md](web-parity-audit.md)). **Last web slice.** |
| **Mirrors (flow)** | app `my_bookings` (rebook), `appointment_detail` (review), `favorites_screen`. |
| **Surface** | `web/` consumer pages + consumer BFF — **no backend change** (endpoints exist). |
| **Status** | **Built** — rebook + review (on `/mon-compte/[id]` completed) + favoris (account section + provider-page heart); 3 unit + 3 e2e; no backend change. **Closes G4 → M8 + the web epic complete.** |

## 1. Three pieces (all reuse existing endpoints via the consumer BFF)
### Rebook — « Réserver à nouveau »
On a **completed/past** booking (`/mon-compte/[id]` + the Passés card) → a link to
`/(providerSlug)/reserver` (re-enters the M5 funnel). No API.

### Laisser un avis
On `/mon-compte/[id]` when `status === 'completed'`: a **rating (1–5 étoiles) +
texte** form → `POST /api/appointments/[id]/review` → `POST /appointments/{id}/review`
(server derives provider/artist/verified; resubmit replaces; recomputes ratings).
Show « Votre avis » with a thank-you on success.

### Favoris
- **`/mon-compte` Favoris section** — `GET /api/me/favorites` → `{providerIds}`,
  **enriched server-side** to full providers → `ProviderCard` grid + remove (cœur).
- **Favorite toggle** (cœur) on the **provider page** — a client island: reads the
  user's favorites (if signed in) for initial state; toggle → `POST`/`DELETE
  /api/me/favorites/[providerId]`; **not signed in → `/connexion?returnTo=`**.

## 2. BFF (consumer `callApi`, self-scoped server-side)
- `POST /api/appointments/[id]/review`
- `GET /api/me/favorites` (enriches ids → provider summaries, server-side fetch)
- `POST` / `DELETE /api/me/favorites/[providerId]`
All authed; the principal is the server's (a user only ever touches their own).

## 3. States
Review: form · submitting · success (merci) · error · validation (rating required).
Favoris: loading · empty ("Aucun favori — explorez les salons") · error · success.
Toggle: optimistic; 401 → redirect to `/connexion`.

## 4. Security / perf
httpOnly cookies; favorites/review are self-scoped server-side (the API enforces).
Favorite toggle on the public provider page = a small client island (the page stays
SSG; the island fetches client-side). `/mon-compte*` noindex.

## 5. Tests
- **Unit:** review form validation (rating 1–5 required); favorites toggle state
  reducer (optimistic add/remove); star input.
- **e2e:** completed booking → leave a review → merci; `/mon-compte` Favoris shows a
  favorited salon + remove; provider page heart → (logged in) toggles. Stub:
  `/appointments/{id}/review`, `/me/favorites`(+id) POST/DELETE.

## 6. Open questions (proposed defaults)
- **OQ-M8.3-1** Favoris = a **section on `/mon-compte`** (vs a separate route) → default.
- **OQ-M8.3-2** Favorite toggle on the **provider page** now; on discovery
  `ProviderCard` = **deferred** (optional) → default.
- **OQ-M8.3-3** Review entry = **`/mon-compte/[id]` for completed** bookings → default.
