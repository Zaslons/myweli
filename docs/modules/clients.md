# Module: Client base (salon CRM) — `clients`

| | |
|---|---|
| **Module** | `clients` — [docs/MODULES.md](../MODULES.md) §4 |
| **YCLIENTS analog** | Клиентская база — profiles, visit history/stats, categories, comments, consent & access tracking |
| **Status** | **Signed off** (2026-07-08) — §11 questions resolved. Today 🟡: clients visible per-booking only; build is ⏳ V2, sequenced **C1 before J1** so the journal grid is client-aware from day one |
| **Depends on** | `journal` (visits are the raw material — ✅ core) · `access` doc (capability `clients.view`, audit — ✅) · consumer identity (verified phone = the linking key — ✅) |
| **Feeds** | `journal` (card density, quick-create, no-show badge) · `marketing` (segments) · `loyalty` (per-client balances) · `analytics` (retention) |

## 1. Vision & YCLIENTS reference

The client base is the salon's **memory**. In YCLIENTS every visit feeds a
client card — visits, spend, no-shows, comments, categories — so the salon
knows « Aïcha, 12 visites, préfère Awa, allergique à l'ammoniaque » before she
sits down. That memory is what makes a software feel indispensable: the salon's
most valuable asset (its client relationships) lives in the product.

MyWeli's twist — and advantage — is that we're a **marketplace**: most clients
are *platform users* with their own accounts, not rows the salon typed in. So
our client base is **derived, not entered**: every booking automatically
builds the salon's CRM. Walk-ins (manual bookings with just name + phone —
`Appointment.clientName/clientPhone`, already live) become **guest clients**,
and when that phone is later verified on a platform account, the records
**link** (same verified-phone rule as the existing visit auto-sync — T33).

**The privacy line (non-negotiable):** a salon sees a client's activity **at
that salon only** — never cross-salon history, never the platform profile.
Notes and tags are the salon's private business records — never shown to the
consumer. Every read of the client base is **audited** (T39).

## 2. Ground truth — what exists today (🟡)

- Bookings carry the client: linked `userId` (marketplace bookings) or
  `clientName`/`clientPhone` (manual/walk-in — live in the model + API).
- Consumer-side visit history + auto-sync on **verified** phone (T33 rule).
- The pro sees client name/phone per booking; **no aggregated view** — the
  flag-hidden placeholder `screens/provider/features/client_database_screen.dart`.
- No salon notes, no tags, no stats, no dedupe of guests.

## 3. User stories (complete set)

**Owner / Manager / Réception (pro app + web)**
1. As an owner, I open **« Clients »** and see everyone who has ever booked —
   marketplace clients and walk-ins together — searchable by name or phone.
2. As an owner, I open a client card and see *at a glance*: visits, total
   spent, last visit, no-shows/cancellations, upcoming booking, full visit
   history **at my salon**.
3. As an owner, I write a note — « Allergique à l'ammoniaque », « Préfère
   Awa » — and it's there the next time she books, with who wrote it and when.
4. As an owner, I tag clients — « VIP », « Fidèle », « À risque » — and filter
   the list by tag (the raw material for `marketing` segments later).
5. As an owner reviewing a **pending booking**, I see « 2 absences » on the
   client before accepting — the no-show badge changes my deposit stance.
6. As a receptionist in the **journal grid**, hovering a block shows the
   client mini-card (visits · spend · no-shows), and the quick-create popover
   **searches existing clients by name/phone before creating a duplicate**.
7. As an owner, I add a client manually (name + phone) *before* any booking —
   my notebook migrates one line at a time.
8. As an owner, I tap the phone icon on the card → call or WhatsApp directly.

**Collaborateur (staff, via `access`)**
9. As an artist, I see client details **only on my own bookings** (per the
   `access` doc decision-pending Q2) — the full client base needs
   `clients.view`, which staff presets don't have; every read that IS allowed
   is audited.

**Consumer (privacy side)**
10. As a client, salons I visit never see my other salons, my email, or my
    platform profile — only what my bookings there revealed.
11. As a client who deletes their MyWeli account, my identity disappears from
    salon records (anonymized), while the salon keeps its anonymous visit
    statistics.

## 4. UX — full specification

### 4.1 « Clients » list (pro app; web mirrors at `/pro/clients`)

Entry: pro bottom-nav/menu « Clients » (replaces the placeholder screen).

- **Header:** search field (« Nom ou téléphone… », debounced, server-side) +
  tag filter chips (« Tous » · VIP · Fidèle · À risque · custom tags).
- **Rows:** avatar initials · name · masked phone (`07 •• •• 89` — full on the
  card) · « {n} visites · dernière {date rel.} » · tag chips · no-show dot
  when > 0. Sort: recent activity (default) | alphabetical.
- **Badges of origin:** small « MyWeli » mark for marketplace clients vs
  nothing for guests — the owner learns the app brings them clients.
- **States:** loading = skeleton rows (BrandLoader) · **empty (educational)**:
  « Vos clients apparaîtront ici automatiquement après leur première
  réservation. » + CTA « + Ajouter un client » · search-no-result: « Aucun
  client pour "{q}" » + same CTA prefilled · error = retry standard.
- **Pagination:** infinite scroll, server pages (guardrail: no unbounded list).
- « **+ Ajouter un client** »: bottom sheet — name (required), phone
  (`PhoneNumberField`, required, dedupe: existing phone → opens the existing
  card with a toast « Ce numéro existe déjà »), optional first note.

### 4.2 Client card (the heart)

- **Header:** name · tags (tap to edit — preset chips + « + personnalisé ») ·
  phone with **call / WhatsApp** action buttons · « MyWeli » badge if linked.
- **Stats strip:** Visites · Dépensé (FCFA formatter) · Absences ·
  Dernière visite. (Server-computed, salon-scoped.)
- **Upcoming:** next booking card if any → taps into the journal detail.
- **Notes:** timestamped list, newest first, each with author (member name —
  ready for `access`; « Vous » until then) · « + Ajouter une note » ·
  author-or-owner can delete. Notes are internal — copy under the field:
  « Visible uniquement par votre équipe. »
- **Visit history:** the salon's own bookings with this client (status chips
  from the journal color language, service, artist, price) — paginated.
- **CTA:** « Nouveau rendez-vous » → manual booking prefilled with the client.
- **Guest→linked merge banner** (when auto-link just happened): « Ce client a
  rejoint MyWeli — historique fusionné. »

### 4.3 Integrations into existing surfaces

- **Journal grid (J1/C2):** block hover/panel shows the mini-card (3 stats +
  last note snippet); quick-create popover = client search-or-create backed by
  this module.
- **Pending booking accept (app + web):** « {n} absences » badge next to the
  client name when n > 0 (story #5) — one line, high leverage.
- **Manual booking:** client field becomes search-or-create (no more blind
  name+phone typing; guests still one-tap).

### 4.4 Dedupe & linking rules

- **Key = phone (E.164).** One client row per (salon, phone); manual add or
  quick-create with an existing phone opens the existing card.
- **Auto-link:** when a platform user **verifies** a phone that matches a
  guest row at a salon → link `user_id`, merge stats/history, keep notes/tags
  (verified-only, same as T33 — an unverified claim never links records).
- **No manual merge UI in C1** (edge case; revisit if support tickets appear).

## 5. Data model

```sql
CREATE TABLE salon_clients (
  id           TEXT PRIMARY KEY,
  provider_id  TEXT NOT NULL REFERENCES providers(id),
  user_id      TEXT REFERENCES users(id),   -- NULL = guest
  display_name TEXT NOT NULL,               -- guest name / cached user name
  phone        TEXT,                        -- E.164; guests: required
  tags         TEXT[] NOT NULL DEFAULT '{}',
  last_visit_at TIMESTAMPTZ,                -- denormalized for list sort
  created_at   TIMESTAMPTZ NOT NULL,
  updated_at   TIMESTAMPTZ NOT NULL,
  UNIQUE (provider_id, user_id),
  UNIQUE (provider_id, phone)
);

CREATE TABLE salon_client_notes (
  id           TEXT PRIMARY KEY,
  client_id    TEXT NOT NULL REFERENCES salon_clients(id),
  author_account_id TEXT NOT NULL,          -- member-ready (access)
  body         TEXT NOT NULL,               -- length-capped (500)
  created_at   TIMESTAMPTZ NOT NULL
);
```

- **Backfill migration:** one row per distinct (provider, user) and
  (provider, guest phone) across historical appointments; `last_visit_at`
  from the latest completed one. Appointments gain nothing — the booking→client
  resolution is by `user_id`/`clientPhone` (+ index).
- **Stats** (visits, spend, no-shows) are **computed** salon-scoped aggregates
  (indexed queries), not stored counters — no drift, and `analytics` reuses
  the same queries. Only `last_visit_at` is denormalized (list sort).
- **Consumer deletion:** on account deletion, `salon_clients.user_id` →
  NULL, `display_name` → « Client », `phone` → NULL; notes/tags kept
  (salon's records, no longer identifying); aggregates survive anonymously.

## 6. API slice (contract locked per-slice in openapi.yaml)

| Endpoint | Cap | Notes |
|---|---|---|
| `GET /providers/{id}/clients?query=&tag=&page=` | `clients.view` | paginated `{items,page,pageSize,total}`; **audited** |
| `POST /providers/{id}/clients` | `clients.view` | manual add `{name, phone, note?}` → 201; existing phone → 409 `client_exists` + id |
| `GET /providers/{id}/clients/{clientId}` | `clients.view` | card: identity + stats + upcoming; **audited** |
| `GET .../clients/{clientId}/visits?page=` | `clients.view` | salon-scoped history |
| `PATCH .../clients/{clientId}` | `clients.view` | tags (validated: ≤10, each ≤24 chars) |
| `POST .../clients/{clientId}/notes` | `clients.view` | body ≤500 chars → 201 |
| `DELETE .../notes/{noteId}` | `clients.view` | author or owner |
| Booking accept payload | — | gains `clientNoShowCount` (server-computed) |

Until `access` ships, `clients.view` = owner (as everything today); the
capability name is used from day one so `access` slots in without route edits.

## 7. Security & threat-model deltas

| # | Surface | Threat | Mitigation |
|---|---|---|---|
| T45 | Client list/card | **I** — cross-salon read of a client base (the salon's most valuable asset) | Ownership boundary on every route (`account.providerId == {id}` → 403); stats/history queries are provider-scoped in SQL, not filtered app-side |
| T46 | List endpoint | **I** — bulk scraping/export of clients | Pagination caps (`pageSize ≤ 50`), rate limit on `query` searches, **every list/card read audited** (actor, target, ts — T39 machinery); no export endpoint in C1 (export = owner-only, later, audited) |
| T47 | Notes | **I/R** — PII/abuse in free text; author spoofing | Length cap, author = server-resolved principal (never client-sent), notes never in logs, never exposed to consumers; deletable by author/owner |
| T48 | Consumer deletion | **I** — deleted user remains identifiable in salon CRMs | Anonymization rule (§5) executed in the same transaction as account deletion; REQUIRED test |
| T49 | Guest→user linking | **S** — attacker claims a phone to inherit a guest's salon history | Link **only on verified phone** (same bar as T33/auto-sync); unverified contact phones never link |

## 8. Performance

List = one indexed query (provider_id, last_visit_at DESC) + tag GIN filter;
card stats = 3 scoped aggregates (composite index on
`appointments(provider_id, user_id/client_phone, status)`), target <150 ms p95.
Search = trigram-or-prefix on display_name + exact/suffix on phone. App list
virtualized, images none (initials avatars) — low-end budget safe.

## 9. Testing

- Backend: unit (dedupe by phone; auto-link on verify — verified-only;
  anonymization); handler (all endpoints success + 401/403/404/409/422 + 405);
  backfill migration test (guests + users + collisions); T45–T49 negatives
  (cross-salon 403 on list/card/visits/notes; scrape rate-limit 429;
  unverified link refused; deletion anonymizes in-tx).
- Contract vs openapi; audit rows asserted on reads.
- App: mock realism (latency/pagination/409); provider tests; widget tests —
  list (all four states + search + tags), card (stats, notes add/delete,
  history), manual-add sheet (dedupe toast); goldens for card header/chips.
- Web: RTL units + e2e on the stub (search → card → note → new booking
  prefilled; accept screen shows the no-show badge).

## 10. Rollout

| Slice | Contents | Sequencing |
|---|---|---|
| C1 | Model + backfill + list/search/card/tags/notes + manual add (app + web) + audit + no-show badge on accept | **Before J1** — the grid is born client-aware |
| C2 | Journal integration: mini-card in the grid panel + quick-create search-or-create | Inside/right after J1 |
| C3 | Guest→user auto-link on phone verification (+ merge banner) | Needs Termii phone verification live |
| C4 | Import (CSV/contacts) & export (owner-only, audited); segments handoff to `marketing` | Later — validate demand first |

Each slice: guardrails skill → `docs/design/clients-<slice>.md` spec → user
sign-off → build (backend → web → app) → tests/CI → PR → ROADMAP + this doc
refreshed. Full-depth rule applies within each slice.

## 11. Decisions (user sign-off, 2026-07-08)

1. **Tag presets: « VIP » · « Fidèle » · « À risque »** + free custom tags
   (≤10/client) — presets teach the feature; custom covers the rest.
2. **Staff & client contact: own bookings, same day only** — name + phone on
   the Collaborateur's OWN bookings of the day (call-about-lateness works;
   harvesting the file doesn't); the full base stays behind `clients.view`,
   audited. **This finalizes `access` §11 Q2.**
3. **No-show badge: from 1 absence, red from 2** — neutral at one, red when
   it's a pattern (the deposit-decision moment).
4. **Phone REQUIRED on manual add** — it's the dedupe and guest→MyWeli linking
   key; unreachable clients are dead data.
5. **Importer deferred** — no CSV/contacts import until 3+ salons ask; manual
   add + automatic accrual from bookings first (C4 revisits).
