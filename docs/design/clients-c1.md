# Clients C1 — the salon client base (list · card · notes · tags · badge)

| | |
|---|---|
| **Module** | `clients` — slice **C1** of [docs/modules/clients.md](../modules/clients.md) (Signed off 2026-07-08; §11 decisions apply) |
| **Status** | **Built** (2026-07-08) — C1a backend (#184) · C1b web (#185) · C1c app |
| **Scope** | Data model + backfill · pro « Clients » list/search/card/tags/notes · manual add · read audit · no-show badge on the pro booking views — **app + web + backend** |
| **Out of scope** | Journal-grid integration (C2, ships with J1) · guest→user auto-link (C3, needs Termii) · import/export & segments (C4) · staff visibility rules (activate with `access`; C1 is owner-only like every pro surface today) |
| **Cross-refs** | [MODULES.md](../MODULES.md) §4 · [journal.md](../modules/journal.md) (badge, future grid) · [access.md](../modules/access.md) (capability names, audit reuse) · `docs/api/openapi.yaml` (updated in the same PRs) |

## 1. Goal

Give every salon its **automatic CRM**: a « Clients » section listing everyone
who ever booked (marketplace users + walk-in guests), with a client card
(salon-scoped stats, visit history, authored notes, tags) and the no-show badge
at the accept moment. Zero data entry required — bookings build it.

## 2. Data model (backend PR)

**Migration `0024_salon_clients`:**

```sql
CREATE TABLE salon_clients (
  id            TEXT PRIMARY KEY,
  provider_id   TEXT NOT NULL REFERENCES providers(id),
  user_id       TEXT REFERENCES users(id),      -- NULL = guest
  display_name  TEXT NOT NULL,
  phone         TEXT,                           -- E.164; guests: NOT NULL
  tags          TEXT[] NOT NULL DEFAULT '{}',
  last_visit_at TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX ON salon_clients (provider_id, user_id) WHERE user_id IS NOT NULL;
CREATE UNIQUE INDEX ON salon_clients (provider_id, phone)  WHERE phone   IS NOT NULL;
CREATE INDEX ON salon_clients (provider_id, last_visit_at DESC NULLS LAST);

CREATE TABLE salon_client_notes (
  id                 TEXT PRIMARY KEY,
  client_id          TEXT NOT NULL REFERENCES salon_clients(id) ON DELETE CASCADE,
  author_account_id  TEXT NOT NULL,
  body               TEXT NOT NULL,             -- app-validated ≤500
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE provider_audit_log (               -- generic; `access` A2 reuses it
  id           TEXT PRIMARY KEY,
  provider_id  TEXT NOT NULL,
  actor_account_id TEXT NOT NULL,
  action       TEXT NOT NULL,                   -- 'clients.list' | 'clients.view'
  target_id    TEXT,                            -- client id (NULL for list)
  meta         JSONB NOT NULL DEFAULT '{}',     -- e.g. {"query":"aï"}
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ON provider_audit_log (provider_id, created_at DESC);
```

**Backfill (inside 0024):** one row per distinct booking client —
- `user_id` bookings → user rows (`display_name` = user name, `phone` = the
  user's phone **only if verified** — the T33/T49 bar);
- guest bookings (`client_phone` set, no user) → guest rows;
- collision (guest phone == a user's **verified** phone at the same salon) →
  single user row (guest history resolves to it) — the C3 rule applied at
  backfill;
- `last_visit_at` = latest completed appointment.

**Resolution rule (query-time, no appointment column):** an appointment
belongs to a client by `user_id`, else by `client_phone`. Stats (visits =
completed count · spent = completed price sum · no-shows · cancellations) are
**computed** salon-scoped aggregates; supporting composite index on
`appointments (provider_id, user_id)` and `(provider_id, client_phone)`.

## 3. API contract (locked in `openapi.yaml`, same PR)

All under provider auth + ownership (`account.providerId == {id}` else 403 —
T45); capability name `clients.view` used in code from day one (owner-only
until `access`). **List and card reads write `provider_audit_log`** (T46/T39).

| Endpoint | Behavior |
|---|---|
| `GET /providers/{id}/clients?query=&tag=&page=&pageSize=` | Paginated `{items,page,pageSize,total}`, `pageSize` clamp ≤50, default 20; sort `last_visit_at DESC NULLS LAST`; `query` matches name prefix/substring or phone suffix (≥2 chars); audited |
| `POST /providers/{id}/clients` | `{name, phone, note?}` — phone REQUIRED E.164 (§11.4), name non-empty; duplicate phone → **409 `client_exists` + `{clientId}`**; 201 SalonClient |
| `GET /providers/{id}/clients/{clientId}` | SalonClient + `stats{visits,spentFcfa,noShows,cancellations}` + `upcoming?` (next non-terminal booking summary); audited |
| `GET /providers/{id}/clients/{clientId}/visits?page=` | Salon-scoped appointment history (paginated, newest first) |
| `PATCH /providers/{id}/clients/{clientId}` | `{tags}` — ≤10 tags, each 1–24 chars, trimmed, deduped → 400 `invalid_tags` |
| `POST /providers/{id}/clients/{clientId}/notes` | `{body}` ≤500 chars → 400 `note_too_long`; author = principal (server-resolved); 201 |
| `DELETE /providers/{id}/clients/{clientId}/notes/{noteId}` | Author or owner; else 403 |

**Pro appointment payloads** (provider-role `GET /appointments` + detail) gain
`salonClientId` and `clientNoShowCount` (server-computed) → powers the badge
and links the detail to the card. Consumer payloads unchanged (no leak).

DTOs: `SalonClient{id, userId?, displayName, phone?, tags[], lastVisitAt?,
linked}` (`linked` = has userId → the « MyWeli » badge) · `SalonClientNote{id,
authorName, body, createdAt}` · `ClientStats` · regenerated web types
(`npm run gen:api`).

## 4. Backend layering

`routes/providers/[id]/clients/…` (thin: parse → ownership → delegate → shape)
→ **`ClientsService`** (dedupe-on-create, tag/note validation, audit emission,
stats assembly) → **`ClientsRepository`** interface (+ in-memory for tests,
Postgres impl). Mirrors the existing repository pattern
(`providers_repository.dart`). No route touches SQL; no service imports
dart_frog.

## 5. UX — app (pro)

**Entry:** new dashboard tile « Clients » (icon `people`, same GridView group
as Rendez-vous) → route `/pro/clients` (go_router, pushed).

**Liste (`ClientListScreen`):**
- AppBar « Clients » + search `AppTextField` (« Nom ou téléphone… »,
  debounce 300 ms, server-side).
- Tag chips row: « Tous » · VIP · Fidèle · À risque · custom tags present in
  the salon's base (from a lightweight `tags` aggregation on page 1 response).
- Rows: initials avatar (AppColors token bg) · name · masked phone
  (`+225 07 •• •• •89`) · « {n} visites · dernière {il y a 3 j} » ·
  tag chips · red dot when noShows ≥ 2 · « MyWeli » mark when `linked`.
- Infinite scroll (paginated); pull-to-refresh = BrandRefresh.
- **States:** loading skeleton (BrandLoader) · educational empty (« Vos clients
  apparaîtront ici automatiquement après leur première réservation. » + CTA
  « + Ajouter un client ») · search empty (« Aucun client pour “{q}” ») ·
  error + retry.
- FAB/action « + Ajouter un client » → bottom sheet: name (required),
  `PhoneNumberField` (required), note optionnelle → 409 → toast « Ce numéro
  existe déjà » + opens the existing card.

**Fiche client (`ClientDetailScreen`, `/pro/clients/:id`):**
- Header: name · tags (tap → edit sheet with preset + custom chips) · phone
  row with **Appeler** / **WhatsApp** actions (url_launcher `tel:`/`wa.me`) ·
  « MyWeli » badge when linked.
- Stats strip (4 tiles): Visites · Dépensé (formatFcfa) · Absences ·
  Dernière visite.
- « Prochain rendez-vous » card when `upcoming` (taps to appointment detail).
- Notes: newest-first list (author + relative date), « + Ajouter une note »
  (sheet, 500-char counter), delete via long-press (author/owner), helper copy
  « Visible uniquement par votre équipe. »
- Historique des visites: paginated list using the journal status chips.
- Bottom CTA « Nouveau rendez-vous » → `/pro/appointment/new` prefilled
  (name+phone via extra).
- All four states on every async section.

**Badge (story #5):** pro appointment list rows + detail header show
« {n} absence(s) » — neutral chip at 1, `AppColors.error` chip at ≥2 (§11.3);
nothing at 0. Detail links « Voir la fiche » → client card.

**Layering:** `ProClientsServiceInterface` + mock (latency/pagination/409/
empty/error realism) + API impl · `ProClientsProvider` (ChangeNotifier:
list state, search, card state, mutations) · screens in
`screens/provider/clients/`. The flag-hidden `features/client_database_screen`
placeholder is retired (route now real).

## 6. UX — web (`/pro/clients`, new dash section)

Mirrors the app flow, desktop-adapted (sidebar nav entry « Clients »):
- List = table (Nom · Téléphone · Visites · Dernière visite · Absences ·
  Tags) with the same search + tag chips above; pagination « Charger plus »;
  same four states + educational empty.
- Card at `/pro/clients/[id]`: two-column desktop layout (identity+notes left,
  stats+history right); phone shown with `tel:`/`wa.me` links; « Nouveau
  rendez-vous » CTA **added 2026-07-10** — opens the manual-booking dialog
  pre-picked with the client
  ([web-manual-booking.md](web-manual-booking.md); deferral closed).
- Accept flow on `/pro/rendez-vous/[id]`: same badge chip next to the client
  name.
- Data via the typed generated client through the existing pro BFF/session
  pattern; no tokens in JS; e2e stub extended (`/providers/:id/clients…`).

## 7. Security (threat rows T45–T49 land in BACKEND.md §7, backend PR)

- Ownership on every route (cross-salon → 403) — T45; REQUIRED negatives.
- Reads audited (`provider_audit_log`) — T46; pageSize clamp; search
  rate-limited by the standard route limiter.
- Notes: length cap, server-resolved author, never logged, never
  consumer-visible — T47.
- Account deletion → anonymize `salon_clients` in the same transaction
  (user_id NULL, name « Client », phone NULL) — T48; REQUIRED test.
- Backfill/link merges on **verified** phone only — T49.
- No enumeration: 404 for foreign/unknown client ids (not 403 detail).

## 8. Performance

List p95 < 150 ms (indexed sort + trigram/prefix search); card = 3 scoped
aggregates on composite indexes; app list virtualized (builder), initials
avatars (no images); web table paginated — CWV budgets hold (no new public JS).

## 9. Tests

- **Backend:** ClientsService/repo units (dedupe, tags/notes validation,
  stats math incl. guest-by-phone resolution, backfill incl. verified-merge +
  collision, anonymization); handler tests per endpoint (2xx + 400/401/403/
  404/409 + 405); audit-row assertions on reads; contract tests; T45–T49
  negatives.
- **App:** mock-realism; ProClientsProvider units; widget tests — list (four
  states, search, chips, 409 toast), card (stats, notes add/delete, history),
  badge on appointment row/detail; goldens for card header + status/tag chips.
- **Web:** RTL units (table, search, empty states, badge); Playwright e2e —
  list → search → card → add note → back; add-client modal incl. duplicate;
  accept screen shows the badge (stub data includes a 2-no-show client).

## 10. Rollout — three PRs under this spec

| PR | Contents | Gate |
|---|---|---|
| C1a backend | Migration 0024 + backfill · repos/service/routes · appointment payload fields · openapi + regenerated web types · threats in BACKEND.md | analyze 0 · full backend suite green |
| C1b web | `/pro/clients` list+card · add-client modal · badge on rendez-vous detail · stub + e2e | tsc/lint · unit · e2e green |
| C1c app | Tile + routes + service/provider/screens · badge · tests | analyze 0 · full mobile suite green |

Each PR: conventional commit `feat(clients): …`, no attribution, CI green,
user merges. After C1c: ROADMAP entry + MODULES.md §4 status + this spec →
**Built**; design/README indexed now.

## 11. Open questions

None — all product decisions were resolved at the module-doc sign-off
(clients §11, 2026-07-08). Implementation latitude within the design
standards (exact spacing, chip colors from tokens, debounce value) stays with
the build.
