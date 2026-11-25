# Search that searches, and the Ivorian categories (A4) — design spec

| | |
|---|---|
| **Status** | **Approved by the owner on 2026-11-25** (« Approve as recommended »: the nine recommendations of §11, BACKLOG decisions 228–236). An independent reader checked it once against the code: 13 findings, each re-read in the code, then folded in (§12). Nothing is built yet. Next, each on the owner's word: this spec's merge (#859); A4-api, the backend's `q`, and its deploy; then A4, then A4w (§9). |
| **Owner** | Sadreddine |
| **Last updated** | 2026-11-25 |
| **PRD ref / phase** | FR-DISC-003 (category browse), FR-DISC-004 (search by name, service and locality, French-aware), FR-DISC-005 (the map's commune awareness), FR-DISC-007 (sort and filter) · V1 · BACKLOG B0.10 (decision 160, Track A), B12.8 |
| **Module** | `client-app` (discovery), with `public-api` (`GET /providers`) and `public-web` (`/recherche`, A4w, decision 233) |
| **ROADMAP entry** | [2026-11-24-consumer-search-spec.md](../roadmap/entries/2026-11-24-consumer-search-spec.md) |
| **Skills checked** | myweli-dev-guardrails ✓ · myweli-backend-guardrails ✓ (A4-api) · myweli-web-guardrails ✓ (parity read; A4w, decision 233) · myweli-verification-guardrails ✓ |
| **Read at** | `main` `7d5d9645`. Every « today » below was read in the code on 2026-11-24, with its file and line. |
| **Related** | [consumer-app-release-audit.md](consumer-app-release-audit.md) §2.1, gaps 11, 20 and 22, §7 A4 · [discovery-sort-filter.md](discovery-sort-filter.md) (sort, « Disponible aujourd’hui », filter before paging) · [web-m8-1-discovery.md](web-m8-1-discovery.md) and [web-search-funnel-parity.md](web-search-funnel-parity.md) (the website's search) · [twin-fidelity-survey.md](twin-fidelity-survey.md) (A-P3: `q` unescaped; the both-twins rule) · [provider-category-column.md](provider-category-column.md) (B16.1: a salon's category may not reach the column the filter reads; spec #857 and fix #860 merged; the fix reaches production with a backend deploy, on the owner's word) · [SYSTEM.md](SYSTEM.md) §12 (states), §13 (a11y), §15 (feedback) |

---

## 1. Goal & scope

**The person types what they want and finds it.** « tresses », « manucure », « Beauté Divine », « Cocody »: the app shows the salons that match, as they type, with the categories of an Ivorian salon, and as many salons as there are.

Today none of that is true (audit §2.1):
- **The search bar does not search.** « Rechercher un salon… » only opens the salon list (`home_screen.dart:121-123`, `widgets/home/search_bar.dart`). The list has no text field. The server has taken `q` since B1 (`backend/routes/providers/index.dart:24`).
- **Four generic categories.** The home chips are « Tous », « Barbier », « Salon », « Spa » (`widgets/home/category_chips.dart:12-17`). The server and the Pro editor know five: `salon`, `barber`, `spa`, `nails`, `massage` (`core/constants/salon_categories.dart:5-11`). A `nails` or `massage` salon cannot be reached by category in the app.
- **Twenty salons at most.** The app never asks for page 2 (`provider_provider.dart:133-140`; `api_provider_service.dart:30-31`), and it throws away the server's `total`.
- **The map does not say what it shows:** page 1 of the chosen commune, with no sign of the filter (`map_screen.dart:71`, `:373-386`), and no loading, empty or error state for its salons.

**In scope:**
- **A4-api (backend):** what `q` matches (§3).
- **A4 (app):**
  - a search field on the salon list, searching as the person types;
  - the five category chips, on the home and the list;
  - « Afficher plus de salons »;
  - every state;
  - the home, the list and the map each reading their own salons (§2.7);
  - the map showing its commune, with its own states.
- **A4w (website), decision 233:** « Afficher plus », and the count from `total`. The « Onglerie » chip's `nail` → `nails` is already fixed and merged (#861, its own session); A4w does not repeat it (Q6).

**Out of scope:**
- **Typo tolerance** (Q1 keeps it for later).
- **Maquillage and Sourcils & cils as salon categories** (Q2).
- **Recent searches and suggestions.**
- **The map's location request and its Settings path** (gap 22's first half, A6).
- **The category column on Postgres** (B16.1, the currency session's: spec #857 and fix #860 merged): until the fix is deployed, a salon that changed its category is filtered under its old one, on every surface.
- **The website's own search flow** (B12.7: a typed commune that is not picked, « Coiffure » as text).

---

## 2. UX & flows

### Today (read on 2026-11-24)

| Where | What happens | Code |
|---|---|---|
| Home, « Rechercher un salon… » | opens « Salons & Barbiers », no text field anywhere | `home_screen.dart:121-123` |
| Home, a category chip | opens the list with `?category=barber` (or `salon`, `spa`) | `category_chips.dart:46-51` |
| The list | commune pill, « Trier », « Disponible aujourd’hui », grid/list toggle; no categories, no field; 20 salons; the count is the salons on screen | `provider_list_screen.dart:82-178`, `:51-56` |
| The list, empty | « Aucun salon trouvé » / « Essayez de modifier vos critères de recherche » — there are no criteria to change | `:244-254` |
| Home, « Près de vous » | the SAME list as the salon list (`provider.providers`) | `home_screen.dart:442-466` |
| The map | `loadProviders()` again — the same list, reset to no category | `map_screen.dart:71` |
| « Mes rendez-vous » | loads that same list if it is empty | `my_bookings_screen.dart:64-66` |

**A defect found while reading, fixed by A4 (§2.7):** the three discovery screens share one list and one `_selectedCategory` (`provider_provider.dart:124-129`).
- **Tap « Barbier » on the home, then go back:** « Près de vous » now shows barbers only, under its unchanged title.
- **Change the commune on the home after that:** it reloads barbers, since `setCommune` keeps `_selectedCategory` (`:182`).
- **Open the map:** it resets the category and replaces the list again.
- **The sort and « Disponible aujourd’hui » leak the same way** (`:137-138`): a sort chosen on the list reorders the home's « Près de vous », and « Disponible aujourd’hui » empties the map of every salon without a slot today.
- **That list is also a fallback for other screens.** `AppointmentCard` (`widgets/booking/appointment_card.dart:42`) and the home's « Derniers rendez-vous » (`home_screen.dart:325`) look a booking's salon up in it, as decision 199 kept. `providerForMap` searches it first (`provider_provider.dart:313`). A review's new figures are patched into it (`:363-366`, `:409`). And `loadProviders` writes the salon page's `_isLoading` and `_error` (`:125-127`, `:153`), so a list read ending during a salon read can show that salon page an error that was the list's.

### 2.1 The flow

1. **Home → « Rechercher un salon… »** opens « Salons & Barbiers » with the keyboard up and the cursor in the search field.
2. **The person types.** At 2 letters or more, 350 ms after the last key, the list asks the server (§2.3). The keyboard's « Rechercher » key searches at once and lowers the keyboard.
3. **The results replace the list** under a count: « 12 salons à Cocody ».
4. **A category chip, the commune pill, « Trier » or « Disponible aujourd’hui »** narrows the same search. The text stays.
5. **At the end of the list, « Afficher plus de salons »** brings the next 20 (Q4).
6. **A salon, then back:** the list is where it was — text, filters, scroll and the pages already shown.
7. **Leaving the list** (back to the home): the search is forgotten. The home's « Près de vous » never shows a search's results (§2.7).

**Home → a category chip** opens the same screen with that chip on and the keyboard down. The field is empty and ready.

### 2.2 The list screen

From top to bottom:
1. **The app bar:** « Salons & Barbiers », as today (A15: no actions).
2. **The search field** (new): a magnifier, the hint « Salon, prestation ou commune », and, while it holds text, a clear button (✕, 48 × 48, tooltip « Effacer la recherche »).
   - It is `AppTextField`'s look. `AppTextField` (`widgets/common/app_text_field.dart:17-53`) gains what it lacks today: `textInputAction`, `onSubmitted`, `autofocus`, `helperText`, a screen-reader label apart from the hint, and `maxLength` with the counter hidden (it would show « 0/100 »).
   - Its other callers keep their defaults.
3. **The commune row,** as today: the pill on the left; the count on the right (§2.5).
4. **The category chips** (new here; the same strip as the home's, §2.4). The chosen one is lit; « Tous » when none.
5. **The filter row,** as today: « Trier », « Disponible aujourd’hui », the grid/list toggle.
6. **The results,** then « Afficher plus de salons » while more exist.

### 2.3 What « searching » does

- **Debounce:** 350 ms after the last change. **Minimum:** 2 letters after trimming. Below that, no request; the field shows a helper line, « Tapez au moins 2 lettres », and the previous results stay.
- **Clearing the field** (✕, or deleting every letter) searches at once without text.
- **The keyboard's « Rechercher »** searches at once (no 350 ms) and lowers the keyboard.
- **Only the latest search may write the list.** Each read carries a number; an answer for an older number is dropped. Typing « tre », then « tresses », can no longer end on « tre »'s salons. The pattern is the slot picker's (`widgets/booking/slot_picker.dart:41`, `_reqId`).
- **While a new search is out, the results already shown stay,** as `AppAsyncView` keeps content through a reload (SYSTEM §12.1). The count line reads « Recherche… » until the answer: static text, nothing that moves (§9.1). The skeleton shows only when there is nothing yet. A list that blinks to a skeleton on every key is worse on a slow phone.
- **« Afficher plus » belongs to one search.** It is disabled while a new search is out, and a page answered for an older search is dropped like any stale answer.
- **A pull to refresh during the 350 ms wait** cancels the wait and searches the field's current text.
- **The text is cleaned before it is sent:** trimmed, runs of spaces made one, control characters removed. A tab typed or pasted would otherwise get a 400 from the server (`query_sanity.dart:75-79`).
- **What the text matches is the server's** (§3, Q1). The app sends the trimmed text and never filters on its own.

### 2.4 The categories (Q2)

The same five as the Pro editor, the server and the website, with « Tous » first:

| Chip | Server value | Icon |
|---|---|---|
| Tous | none | `all_inclusive` |
| Coiffure | `salon` | `face` |
| Barbier | `barber` | `content_cut` |
| Onglerie | `nails` | `back_hand` |
| Spa | `spa` | `spa` |
| Massage | `massage` | `self_improvement` |

- **The chip labels are the website's short labels.** The salon page keeps `salonCategories`' longer ones (« Salon de coiffure », « Massage & bien-être »).
- **One list, `discoveryCategories` in `core/constants/salon_categories.dart`,** carries the key, both labels, the chip's icon and the map marker's icon and colour, so none can drift. Today the map has a third list of its own (`widgets/map/salon_map_marker.dart:8-12`, `core/theme/category_colors.dart:10-15`), without `nails` or `massage`, and with another icon for `salon`.
- **An unknown `?category=`** (the website's old `nail`, a stale link) is ignored: the list opens on « Tous ».
- **This is less than the audit's row A4 asked.** It names « the PRD Appendix A chips », and FR-DISC-003 says « not generic ». Q2 asks the owner to accept the five shared categories now, and to decide the Appendix's other groups apart.
- **On the home,** a chip opens the list with it on (§2.1).
- **On the list,** a chip narrows the search in place. Tapping the lit chip, or « Tous », removes the category.
- **Maquillage, Sourcils & cils** (PRD Appendix A) are not salon categories anywhere. A4 reaches them by search, since `q` matches service names (§3).

### 2.5 The count

- **From the server's `total`, not the salons on screen:** « 1 salon », « 42 salons », « 42 salons à Cocody ». Today the count stops at 20.
- **It is announced** to a screen reader once each search has answered, not on every key. It is announced with `SemanticsService.announce`, since a live region says nothing when the count does not change between two searches.
- **Hidden while the first page is loading, or when there is nothing** (the empty state says it).
- **At 200 %,** the count moves to its own line under the commune pill when the row cannot hold both. Today the row is a `Row(spaceBetween)` with the count at its full width (`provider_list_screen.dart:105-121`), so a long count could push the pill under A12's 8-character floor. A new rule for that row, with its test.

### 2.6 « Afficher plus de salons » (Q4)

- **A button at the end of the list,** shown while `page × 20 < total`. Tapping it asks for the next page and appends it.
- **While it loads,** the button becomes a loader in its place: no skeleton, and the list stays.
- **If the next page fails,** the button's place says « Impossible d’afficher la suite. » with « Réessayer ». The salons already shown stay.
- **A salon already shown is not shown twice.** Appended pages are de-duplicated by id. A4-api also gives every order a final tiebreak on the id (§3), so pages no longer shift.
- **A new search, a filter or a pull-to-refresh** starts again at page 1.
- **Grid view** has the same button, full width, after the grid.

### 2.7 Each screen reads its own salons

- **The home's « Près de vous »:** the chosen commune only, relevance, page 1. It never takes a category, a text, a sort or « Disponible aujourd’hui ». It stays `ProviderProvider.providers`, so the fallbacks that read that list keep working: `AppointmentCard`, the home's « Derniers rendez-vous », and « Mes rendez-vous », which loads it when it is empty (`my_bookings_screen.dart:64-66`, decision 199).
- **The list:** its own search state (text, category, pages), created with the screen and disposed with it. The sort and « Disponible aujourd’hui » are Q9's.
- **The map:** the chosen commune only, up to 50 salons, in a list of its own (§2.8).
- **The commune stays one shared, saved choice,** as today (`provider_provider.dart:160-182`). Changing it anywhere reloads the home's « Près de vous », the map and an open list.
  - **An open list reloads only when the commune actually changed.** It keeps the commune it last applied and compares it. `ProviderProvider` notifies on every salon read and review (`provider_provider.dart:241`, `:266`, `:300`, `:397`, `:475`), so a list reloading on each notification would go back to page 1 each time a salon is opened from it, and break §2.1 step 6.
- **Each list has its own loading and error flags.** None writes the salon page's `isLoading` or `error` any more.
- **Every copy of a salon is patched.** `providerForMap` looks in the home list, the map's list and an open search (`:313`). A review's new figures reach all three (`:363-366`, `:409`), through the figures sink the review sheet already passes.

### 2.8 The map says its commune (gap 22, its A4 half)

- **A commune pill at the top,** the list's `CommunePill`: « Cocody », or « Toutes les communes ». Tapping it opens the same picker.
- **Its salons:** the chosen commune, with coordinates (publishing requires a pin, `salon_provisioning_service.dart:204-207`), up to 50, the server's largest page. The map reads `searchProviders` with a page size of 50, which carries `total`.
- **When there are more than 50,** a line under the pill says:
  - with no commune: « 50 salons sur 63 affichés — choisissez une commune »;
  - with one: « 50 salons sur 63 à Cocody affichés ».
- **Loading:** a small « Chargement des salons… » pill under the commune pill. The map itself shows at once.
- **Error:** a banner « Impossible d’afficher les salons. » with « Réessayer ». The map stays usable.
- **Empty:** « Aucun salon à Cocody » with « Toutes les communes »; with no commune, « Aucun salon sur la carte pour l’instant ». **Not shown while a focused salon is on the map** (opened from a salon page, `focusProviderId`): its pin may be in another commune, and the map is then not empty.
- **The location banner** (`_locationError`, `map_screen.dart:465-498`) stays as it is and sits below these. A6 rewrites it.

### 2.9 All states (the list)

| State | What shows |
|---|---|
| First load | the skeleton, as today |
| A new search out, results shown | the results; the count line reads « Recherche… » |
| Results | the count, the cards, « Afficher plus de salons » while more exist |
| Next page out | the cards, a loader in the button's place |
| Next page failed | the cards, « Impossible d’afficher la suite. » + « Réessayer » |
| First page failed | `AppAsyncView`'s error (the sentence of `app-failure-messages.md`) with « Réessayer » |
| Empty | the most specific sentence, §2.10 |
| Offline | the failure sentence « Pas de connexion. Réessayez. », as every read |
| 1 letter typed | the helper line; the previous results stay |

### 2.10 Empty: one sentence, one way out

**First: is any salon public at all?** When the home's unfiltered featured read has answered with nothing, every empty search shows the last row below, whatever the filters. In production today all nine salons are drafts (B16.1 §2.4), and « Vérifiez l’orthographe » or « Essayez une autre commune » would then be false. If that read failed, the rows below apply as usual.

Otherwise, checked in this order; the first that holds is shown. The action removes the narrowing named:

| Active | Title | Description | Action |
|---|---|---|---|
| a text | Aucun résultat pour « tresses » | Vérifiez l’orthographe, ou cherchez une prestation : « tresses », « manucure »… | Effacer la recherche |
| « Disponible aujourd’hui » | Aucun salon disponible aujourd’hui | Les autres jours ont peut-être de la place. | Retirer ce filtre |
| a category | Aucun salon dans cette catégorie à Cocody *(« à … » only with a commune)* | Essayez une autre catégorie. | Toutes les catégories |
| a commune | Aucun salon à Cocody | Essayez une autre commune. | Voir toutes les communes *(today's)* |
| nothing | Aucun salon pour l’instant | Aucun salon n’accepte encore de réservations sur MyWeli. | — |

The last row is production today. It says only what is true (A1's rule), and it no longer tells the person to change criteria they cannot see.

### Edge cases

- **Very long text:** capped at 100 characters in the field (`maxLength`, with no counter shown). The server also ignores more (§3).
- **Only spaces:** treated as empty.
- **Accents:** « beaute » finds « Beauté », and « coiffure » finds « Coiffure » (§3, Q1).
- **A text and a commune at once:** both apply. « Cocody » typed while the commune is Marcory finds salons whose address mentions Cocody within Marcory, usually none. The empty state then offers « Effacer la recherche ». The commune is a filter; the text never changes it.
- **Pull to refresh:** page 1 again, the same search.
- **The commune changed while « Afficher plus » is out:** the new search's number makes that page stale; it is dropped.
- **The screen closed while a read is out:** the controller drops the answer and never notifies after dispose.
- **« Disponible aujourd’hui » with a text:** each search computes today's slots for every matched salon (`discovery-sort-filter.md:41`). The debounce keeps that to one computation per pause.
- **Rotation or a split screen:** the state lives in the screen's controller and survives a rebuild.
- **Low-end Android:**
  - one request per pause in typing, not per key;
  - 20 cards per page;
  - images lazy, as today;
  - no request below 2 letters.
- **Long French at 200 %:** the field grows (no fixed height). The chip strip scrolls. The count wraps under the pill when the row is full, the A12 rule of that row.

### Copy, all of it

| Where | Text |
|---|---|
| Home bar (unchanged) | Rechercher un salon… |
| Field hint | Salon, prestation ou commune |
| Field, screen-reader label | Rechercher un salon |
| Clear button tooltip | Effacer la recherche |
| Helper, 1 letter | Tapez au moins 2 lettres |
| Count | 1 salon · N salons · N salons à {commune} · Recherche… (while a new search is out) |
| Chips | Tous · Coiffure · Barbier · Onglerie · Spa · Massage |
| More | Afficher plus de salons |
| More failed | Impossible d’afficher la suite. · Réessayer |
| Map, loading | Chargement des salons… |
| Map, error | Impossible d’afficher les salons. · Réessayer |
| Map, more than 50 | 50 salons sur {total} affichés — choisissez une commune · 50 salons sur {total} à {commune} affichés |
| Map, empty | Aucun salon à {commune} · Toutes les communes / Aucun salon sur la carte pour l’instant |
| Empty states | §2.10 |

---

## 3. API & contract — A4-api (Q1)

`GET /providers` keeps its shape: `{items, page, pageSize, total}`. **What changes is what `q` matches**, on both twins (the both-twins rule, twin-fidelity-survey.md):

| | Today | A4-api |
|---|---|---|
| Fields | name, description, address (`providers_repository.dart:239-243`; `postgres_providers_repository.dart:47-52`) | name, description, address, **commune**, and the names of the salon's **active services** |
| Case | ignored | ignored |
| Accents | **significant:** « beaute » misses « Beauté » | **ignored** on both sides of the comparison |
| Spaces | kept as sent; « tresses » with a trailing space misses | trimmed; runs of spaces become one |
| `%` and `_` | wildcards on Postgres, so `q=_` lists every salon (survey A-P3, B16.8) | escaped: they match themselves |
| Length | unbounded | the first 100 characters; an empty text is no filter |
| Several words | one substring | **unchanged:** one substring. « tresses cocody » matches a salon only if those words appear together. Matching each word separately is typo tolerance's PR. |
| Order | no tiebreak: equal salons can change places between pages | every order ends on the salon id (both twins) |

**How, on Postgres:**
- The `unaccent` extension, through one migration: `CREATE EXTENSION IF NOT EXISTS unaccent`. The app's role already creates `btree_gist` the same way (`backend/lib/src/db/migrations.dart:276`).
- The comparison applies `lower(unaccent(…))` to both sides.
- Services are matched with an `EXISTS` on `provider_services` where `active`.

**In memory:**
- The same fields, **each matched on its own.** Today the twin glues name, description and address into one string (`providers_repository.dart:240-243`), so a text spanning two fields matches there and not on Postgres. A contract case pins it.
- The same folding, from `backend/lib/src/slug.dart:4-34`'s table, extended to what `unaccent` folds and a phone types: `’` (iOS's smart apostrophe), `œ`, `æ`. A contract case runs each against both twins, so a difference fails on CI's Postgres.

**The tiebreak** goes where the orders are: the shared `sortProviders` (`backend/lib/src/provider_discovery.dart:10-26`), and both twins' default order.

**The contract** (`docs/api/openapi.yaml:1730-1760`):
- `q`'s description names its fields and its folding;
- the 100-character cap;
- the tiebreak.

The drift the read found is fixed at the same time:
- `page` and `pageSize` are clamped, not refused;
- `availableToday` is only `true`;
- an unknown `sort` falls back to relevance;
- the 400 and 405 responses are listed.

**The app's service interface:**
- **A new `searchProviders(ProviderQuery)`** answers `ApiResponse<ProviderPage>`: the items, the page, the page size and `total`. The list and the map use it.
- **`getProviders` stays** for the featured carousel and « Près de vous », until a later cleanup.
- **The mock** pages, counts and folds exactly like A4-api, with latency, an error switch and an empty case.

---

## 4. Data model

- **No new table and no new column.**
- **One migration:** the `unaccent` extension (A4-api).
- **The app:**
  - `ProviderPage` (immutable, equatable);
  - `ProviderQuery` (text, category, commune, sort, availableToday, page);
  - `discoveryCategories` (key, chip label, icon), next to `salonCategories`.

## 5. Architecture & patterns

- **Layering, as everywhere:** `models → services (interface + mock + api) → providers → screens`.
- **The list's state:** a `SalonSearchController` (`ChangeNotifier`), created by `ProviderListScreen` and disposed with it. It holds:
  - the text, the category and the filters;
  - the pages;
  - the request number;
  - `isLoading` / `isLoadingMore` / `error` / `moreError`.
- **The commune** stays on `ProviderProvider` (shared, saved). The controller listens, and reloads only when the commune differs from the one it last applied (§2.7).
- **`ProviderProvider` keeps:**
  - the home's « Près de vous » (commune only);
  - the featured carousel;
  - the map's salons, in a list of their own;
  - the salon page's slot.

  `loadProviders({category, searchQuery})` loses both parameters, and `_selectedCategory` goes: the defect of §Today. Its reads stop writing the salon page's `_isLoading` and `_error`.
- **Tests that move with it:** `discovery_sort_filter_test.dart:53-60` (the sort and the filter on `ProviderProvider`), `test/a11y/layout_test.dart:860` and `:921`, `submit_review_sheet_test.dart:144`, `salon_location_map_test.dart:685-699` (`providerForMap`), and the consumer goldens (`consumer_screens_golden_test.dart`, `consumer_truth_golden_test.dart`).
- **The debounce** is a `Timer` in the controller, cancelled on dispose. **The request number** is the slot picker's `_reqId` pattern (`slot_picker.dart:41`; also `pro_journal_provider.dart:92`).
- **Routing:** `/providers?category=nails` (from the home's chips) and `/providers?focus=search` (from the home's bar) open the same screen. The query parameters are read once, at creation.

## 6. Security & privacy

- **`q` is a bound parameter,** never SQL text. A4-api escapes `%` and `_` (closing B16.8's half that `q` owns). The query middleware already refuses control characters (`query_sanity.dart:46-54`).
- **Nothing new is stored:** the search is not saved on the device or the server. The app's Sentry setup strips breadcrumbs, and the Cloudflare Worker in front of the API logs no query (checked by the independent reading).
- **The search text reaches Cloud Run's request logs for 30 days.** The URL holds `q`, as the website's `/recherche` already does: BACKLOG B0.15, **decision 55, still open**. A4 makes the app send it too. Q8 asks whether A4 waits for that decision; it matters to the consumer store packet's privacy label (B3: « Search History »).

## 7. Performance

- **One request per pause in typing:** 350 ms, 2 letters minimum. 20 salons per page; 50 on the map.
- **The server still loads the whole matched set and slices it in Dart** (`postgres_providers_repository.dart:47-50`, no SQL `LIMIT`). That is fine at launch scale (9 salons in production, all drafts). A SQL `LIMIT` with a `COUNT(*)` is recorded as a follow-up for when salons number in the hundreds, not built here.
- **`unaccent` on every row** of a small table costs nothing measurable. An index on the folded name is part of the same follow-up.

## 8. Testing plan

**A4-api (both twins, one contract test run against each):**
- **Matching:**
  - each field matches (name, description, address, commune, an active service; an inactive service does not);
  - « beaute » finds « Beauté », « COIFFURE » finds « coiffure »;
  - spaces are trimmed and collapsed;
  - `_` and `%` match themselves;
  - a 150-character text behaves as its first 100.
- **Order:** two salons with equal ratings keep one order across pages 1 and 2.
- **Contract:** the response matches `openapi.yaml`.
- **Red first, on committed code:** every case above against today's code, each with its failure text recorded; then mutations of each folding step, the escape and the tiebreak.

**A4 (app):**
- **Unit:**
  - `SalonSearchController`: debounce, the 2-letter floor, the keyboard's search, the stale answer dropped, pages appended and de-duplicated;
  - `page × 20 < total` and the « more » failure keeping page 1;
  - the empty-state order of §2.10, with « nothing public » first;
  - the commune change reloading, and a salon read (a notification with the same commune) NOT reloading;
  - a stale « Afficher plus » page dropped after a new search;
  - the text cleaned (spaces, control characters) before it is sent;
  - an unknown `?category=` opening on « Tous ».
- **Widget:**
  - the list's field, clear button, chips and count;
  - « Afficher plus » in list and grid;
  - every row of §2.9 and §2.10;
  - the home's « Près de vous » unchanged after a category, a sort or « Disponible aujourd’hui » on the list (the defect, red first);
  - `AppointmentCard`'s fallback still finding the salon after a search on the list;
  - a review's figures reaching a card in an open search;
  - a salon page's error never set by a list read;
  - the map's pill, its 50-line, and its three states.
- **A11y:**
  - 48 × 48 on the clear button and « Afficher plus »;
  - the field's label;
  - the count's live region;
  - the screen at 200 % at 360 wide, the count moving under the pill;
  - `labeledTapTargetGuideline` on the list.
- **Goldens (Linux, opened one by one):**
  - the list with text and results;
  - the list empty with a text;
  - « Afficher plus »;
  - the map with its pill;
  - each at 1× and at 360 × 200 %.
- **Mutations:** each rule above, watched red, listed in the commit messages.

**A4-api, added by the independent reading:** a text spanning two fields does not match on either twin; `’`, `œ`, `æ` fold alike on both.

**A4w (decision 233):** `/recherche`'s « Afficher plus » and the count from `total`, e2e for each. (The « Onglerie » chip and its `/onglerie` landing pages were fixed in #861, §11 Q6.)

## 9. Rollout & scope discipline

**Three PRs, in this order (Q7):**
1. **A4-api:** the backend. There is no staging (`infra/gcp/staging.state` reads `absent`), so its migration first runs in production, on a `deploy-backend.yml` dispatch with the owner's word. Deployed, it also changes what `/recherche` finds on the website: accents and services, for the better.
2. **A4:** the app. Merging deploys nothing. **Its consumer build waits for A4-api in production** (Q7): the field's hint promises « prestation ou commune », and the empty state suggests searching a service. On today's server both would be false (A1's rule).
3. **A4w** (decision 233). Its merge is a production deploy of `myweli.com`. The `nail` key (`web/lib/landing.ts:17`) was fixed in #861, with the `/onglerie` landing pages that read it.

**B16.1** (the category column: spec #857 and fix #860 merged) is not a prerequisite for building A4, but its deploy is for the category chips to be right in production. Its session owns it.

**Not in V1 scope, recorded:** typo tolerance, recent searches, suggestions, Maquillage and Sourcils & cils as categories, a SQL `LIMIT`.

## 10. Definition of done

- Each PR's tests, mutations and goldens of §8.
- `flutter analyze` 0; `dart analyze` 0; typecheck and lint clean.
- The contract updated with A4-api.
- A4-api deployed and read back on the production API: the migration's log line on the new revision, and `/providers?q=beaute` answering 200.
  - **The matching itself cannot be observed in production** while no salon is public: every answer is empty, before and after. Until then, the evidence is the contract suite on CI's Postgres. That limit is written in the PR, not glossed.
  - Once a salon is public, the read-back is its name typed without accents, with a control (a text that must not match).
- The audit's gaps 11 and 20, and gap 22's commune half, marked closed in its progress line.
- One roadmap entry per PR.

## 11. Open questions (each with a recommendation) — answered 2026-11-25, all nine as recommended

**Q1. What should the search match (A4-api)?** [decision 228]
- *Recommended:*
  - the salon's name, description, address and commune, and its active services' names;
  - case and accents ignored;
  - spaces trimmed;
  - `%`/`_` escaped;
  - every order ending on the id.
- **Typo tolerance** (FR-DISC-004's « typo-tolerant ») later, in its own PR. It needs a similarity measure (`pg_trgm`) matched on both twins, and the launch has nine salons.
- → ✅ **Decision 228, as recommended** (2026-11-25).
- *The alternative:* send today's `q` from the app unchanged. Then « beaute » misses « Beauté », and « manucure » misses every salon that offers one but does not write it in its description.

**Q2. Which categories?** [decision 229]
- **This departs from the approved audit row A4,** which names « the PRD Appendix A chips » (decision 160), and from FR-DISC-003's « not generic ».
- *Recommended:* the five the server, the Pro editor and the website already share — Coiffure, Barbier, Onglerie, Spa, Massage — with « Tous ».
- Maquillage and Sourcils & cils are reached by search (their services' names) until a salon can choose them. Adding them is one change across the server's PATCH list, the Pro editor, the app and the website: its own decision.
- *The alternative:* the PRD's eight top-level groups. That needs those new salon categories first.
- → ✅ **Decision 229, as recommended** (2026-11-25).

**Q3. Search as the person types, or only on « Rechercher »?** [decision 230]
- *Recommended:* as they type — 350 ms after the last key, from 2 letters — with the keyboard's « Rechercher » searching at once. The audit's A4 says « debounced ». On a phone the keyboard hides half the screen, so seeing results while typing is the point.
- *The alternative:* the website's way, on submit only.
- → ✅ **Decision 230, as recommended** (2026-11-25).

**Q4. More than 20 salons: a button, or loading on scroll?** [decision 231]
- *Recommended:* « Afficher plus de salons », a button. The person decides what the next page costs on a mobile data plan. It is reachable by a screen reader and a keyboard, and testable.
- *The alternative:* loading the next page near the end of the list.
- → ✅ **Decision 231, as recommended** (2026-11-25).

**Q5. The map: its commune pill, its own states, up to 50 salons with a line when there are more?** [decision 232]
- *Recommended:* yes, as §2.8.
- *The alternative:* all of a commune's salons, several requests. Not needed at launch scale.
- → ✅ **Decision 232, as recommended** (2026-11-25).

**Q6. The website's half (A4w)?** [decision 233]
- *Recommended:* yes, its own PR after A4:
  - « Afficher plus » on `/recherche`;
  - the count from `total` (it stops at 24 today).
- **The « Onglerie » chip is not A4w's.** It sent `nail`, so it could never find a salon; B16.1 §12 found it. Its own session fixed it, merged as #861 on 2026-11-24.
- Its merge is a production deploy.
- → ✅ **Decision 233, as recommended** (2026-11-25).

**Q7. The order: A4-api, then A4, then A4w — and A4's consumer build waits for A4-api in production?** [decision 234]
- *Recommended:* yes to both. The field's hint and the empty state promise services and communes, which only A4-api's server finds (§9).
- B16.1 stays with its own session, before release.
- → ✅ **Decision 234, as recommended** (2026-11-25).

**Q8. Does A4 wait for decision 55** (search text in Google Cloud's request logs, B0.15)? [decision 235]
- *Recommended:* no. The website already sends `q` the same way, and A4 changes nothing about where it is kept.
- Decision 55's answer then covers both, and the consumer store packet (B3) declares what it decides.
- → ✅ **Decision 235, as recommended** (2026-11-25).

**Q9. The sort and « Disponible aujourd’hui »: for the session, or for one visit to the list?** [decision 236]
- Today they last the whole session, and leak into the home and the map (§Today). Once the list has its own state, they could reset each time it opens.
- *Recommended:* keep them for the session, as today, but on the list only. The person who chose « Mieux notés » finds it again; the home and the map ignore it.
- *The alternative:* each visit starts on « Pertinence », without the filter.
- → ✅ **Decision 236, as recommended** (2026-11-25).

## 12. The independent reading (2026-11-24)

A reviewer told to refute the spec read it against the code: 13 findings. Each was re-read in the code, then folded in:

1. **A list listening to `ProviderProvider` would reload on every salon read** (it notifies on each, `:241`…`:475`), losing its pages. It now reloads only when the commune changed (§2.7).
2. **The map's « 50 sur 63 » needs `total`,** which `getProviders` drops. The map now uses `searchProviders` (§2.8, §3).
3. **The hint and the empty state would be false on today's server.** A4's consumer build now waits for A4-api in production (§9, Q7).
4. **The shared list is a fallback** for `AppointmentCard`, the home's « Derniers rendez-vous » and « Mes rendez-vous » (decision 199). « Près de vous » stays that list; the earlier draft wanted « Mes rendez-vous » to stop reading it (§2.7).
5. **Other readers of that list:** `providerForMap`, the review figures, and the salon page's flags written by list reads. They are named, each gets a rule, and the tests that move are listed (§2.7, §5).
6. **The leak is wider than the category:** the sort and « Disponible aujourd’hui » too. Keeping them is Q9.
7. **`AppTextField` lacks what the field needs;** the parameters to add are listed (§2.2).
8. **The twins already differ:** in memory, the fields are glued into one string. Matching is now per field, and the fold is pinned against `unaccent` with `’`, `œ`, `æ` (§3).
9. **There is no staging,** so the migration first runs in production; the precedent is cited. §10's « if one is public » check could not fail, and is replaced by what can be observed, with the limit said (§9, §10).
10. **The tiebreak belongs in the shared `sortProviders`** as well as the twins' default order (§3).
11. **With no public salon, the empty states would be false.** The « Aucun salon pour l’instant » row now comes first whenever nothing is public (§2.10).
12. **Smaller:**
    - the map's « choisissez une commune » with a commune already chosen;
    - the count row at 200 %;
    - the map's third category list;
    - a pattern name that no longer exists (`slotsRequestId`).
13. **Edge cases:**
    - « Afficher plus » during a new search;
    - a pull during the debounce;
    - notifying after dispose;
    - an unknown category;
    - control characters;
    - the map's empty banner over a focused salon;
    - an unchanged count not re-announced;
    - the progress bar (now static text);
    - the slot cost of « Disponible aujourd’hui »;
    - the `/onglerie` landing pages;
    - `/recherche` changing when A4-api deploys.
