# Search that searches, and the Ivorian categories (A4) — design spec

| | |
|---|---|
| **Status** | **Approved by the owner on 2026-11-25** (« Approve as recommended »: the nine recommendations of §11, BACKLOG decisions 228–236). An independent reader checked it once against the code: 13 findings, each re-read in the code, then folded in (§12). The spec merged as `ed60594c` (#859). **A4-api built on 2026-11-25** on the owner's « Yes, build A4-api » (§3.1), **merged** as `351568e3` (#864), **deployed** the same day (`myweli-api-00059-w28`, image `351568e`) and **read back** in production (§10: every search answers 200, the monitor 11 of 11; the matching itself waits for a public salon). **A4 built on 2026-11-25** on the owner's « Yes, start A4 » (§3.2), **merged on 2026-11-26** as `f49de03d` (#878; tree equal to the tested head `45237409`). It reaches people with the next consumer build, on the owner's word. **A4w built on 2026-11-26** on the owner's « Yes, build it » (§3.3); not merged. Its merge deploys `myweli.com`, on the owner's word. |
| **Owner** | Sadreddine |
| **Last updated** | 2026-11-26 |
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
- **The category column on Postgres** (B16.1, the currency session's: spec #857, fix #860): **deployed 2026-11-25** (`myweli-api-00058-tnp`), and its read after found no salon whose column differs from its document (records #862).
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

### 3.1 As built (A4-api, 2026-11-25)

- **Where each step runs.** `backend/lib/src/search_text.dart` cleans the text once, in Dart, for both twins: white space (the no-break space included) collapsed and trimmed, then the first 100 characters **counted as runes**, so an emoji at the cut stays whole. Postgres folds with `lower(unaccent(…))` (`kProviderSearchCondition`, `postgres_providers_repository.dart`); the in-memory twin folds with `foldSearchText` and matches with `salonMatchesSearch`.
- **Folded first, escaped after — found while building.** `unaccent` turns a full-width `＿`, `％` or `＼` into `_`, `%` or `\`. An escape run before the fold never sees them, so `q=＿` would have listed every salon, the very defect §3 closes. The SQL folds the parameter, then escapes `\`, `%` and `_` (`ESCAPE '\'`). A contract case holds both orders apart. BACKEND.md §3.4 states the rule.
- **The in-memory fold's table is PostgreSQL's own.** `backend/tool/search_fold_table.dart` reads every code point `unaccent()` changes from a real PostgreSQL and writes `lib/src/search_fold_table.dart`: 1,650 entries from PostgreSQL 16.14, combining accents included (a decomposed « é » folds to « e »). Not the slug table: it holds 29 lower-case letters.
- **Held to the database by two Postgres tests:** the table equals `unaccent()` entry for entry over every code point, and `foldSearchText` equals `lower(unaccent())` over Basic Latin to the combining marks, Latin Extended Additional, General Punctuation and the full-width forms. **The limit, measured:** over the whole Basic Multilingual Plane, Dart's `toLowerCase` leaves 186 characters upper case that PostgreSQL lower-cases (Cherokee, Georgian Mtavruli, Latin Extended-D, a few Cyrillic and Coptic letters). None is a letter of French or of the Latin alphabets of Côte d'Ivoire's languages (ɛ, ɔ and ŋ agree). Only the in-memory twin has that limit, and it never serves production.
- **The order:** Postgres `ORDER BY featured DESC, rating DESC, id COLLATE "C"` (`kProviderDiscoveryOrder`), byte order, which the in-memory `String.compareTo` gives for these ASCII ids; `sortProviders` breaks rating and price ties on the id. The contract's order case depends on where Postgres stores the rows, and passed once without the tiebreak, so the constant is also tested on rows of the test's own, out of id order.
- **White space, on both sides** (found by the review below): the salon's own text has its runs of white space collapsed with the class the search was cleaned with (`kSearchSpaces`: Dart's `\s` written out, because Postgres's own `\s` follows the locale and leaves out the no-break spaces). « Beauté␣␣Divine », a narrow no-break space before « : », a line break in a description: all found.
- **The pattern is built once per query** (an uncorrelated subquery), not once per row.
- **A text with nothing left once folded** (a lone combining accent) is no filter on both twins, as an empty one.
- **Mutations, each watched red** (26, on committed code): the escape before the fold, no escape, either side not unaccented, the commune or the active flag left out (both twins), a service matched to any salon, the salon's spaces not collapsed (both twins), the class without the narrow no-break space, the fields glued, a missing field read as « null », each tiebreak removed, the id without `COLLATE "C"`, `query()` with an ORDER BY of its own, spaces not collapsed in the search, a cut by UTF-16 units, no cut, lower case before the table, one table entry removed, no lower case, the route dropping `q`; and migration `0051` removed (on a fresh database: `function unaccent(text) does not exist`).
- **The independent review (2026-11-25)**, told to refute it: nothing blocks the merge. Two findings to fix, both folded in: a service's name could have listed every salon with nothing to catch it (the `EXISTS`'s correlation; a control salon now), and the salon's own spaces were never collapsed. Nits folded in: the pattern per row, the empty fold, two comments that overclaimed, `query()`'s own order and the order across pages untested. **One suspicion, unverified:** Postgres's `lower()` follows the database's `LC_CTYPE`; under `C`, « Ɔ » stays « Ɔ ». Cloud SQL's default is `en_US.UTF8` and nothing here reads production, so the read after the deploy includes `SELECT datctype FROM pg_database WHERE datname = current_database()`, on the owner's word (§10).
- **Migration `0051_unaccent`:** `CREATE EXTENSION IF NOT EXISTS unaccent`. Additive and rollback-safe: an older image never calls it. `unaccent` is a trusted extension since PostgreSQL 13, and the app's user already created `btree_gist` the same way (`0009`). That the production user may create it is **inferred, not observed** (nothing here reads Cloud SQL). If it may not, the new revision fails at boot and never takes traffic; the old one keeps serving.
- **Not changed:** `listForAdmin(q:)` and the clients list keep their unescaped `ILIKE` (B16.8, B16.7). Several words remain one text.

---

### 3.2 As built (A4, the app, 2026-11-25)

Built on the owner's « Yes, start A4 », branch `feat/a4-app-search` from `main` `da5faa09`.

- **Where each part lives.**
  - The list's own state: `SalonSearchController` (`lib/providers/salon_search_controller.dart`), created and disposed with `ProviderListScreen`.
  - The one category list: `discoveryCategories` (`core/constants/salon_categories.dart`), which `salonCategories`, `categoryColor` and `salonCategoryIcon` now read. Held by a test to the server's PATCH list and to the website's `landing.ts` labels.
  - The read: `searchProviders(ProviderQuery)` → `ProviderPage` with `total` (interface, API, mock). `getProviders` stays for the carousel and « Près de vous ».
  - The text cleaned in the app as the server cleans it (`core/utils/search_text.dart`): a tab or a line break becomes a space, the other control characters go.
  - The mock matches each field on its own, folds with the server's own `unaccent` table restricted to Latin (744 entries, generated from `backend/lib/src/search_fold_table.dart` and held to it by a test), pages, clamps and counts like A4-api. It has an error switch (`failSearches`) and an empty case (`salons: []`).
- **Decisions taken while building, inside the spec:**
  - **An open search is reached through `ProviderProvider`, not the review sheet's sink.** The sheet opens from the salon page or « Mes rendez-vous », which do not hold the list's controller. So the controller attaches itself as a `SalonCopyHolder` while it lives: `providerForMap` finds a salon in it, and a review's figures reach its card.
  - **A new search that fails empties the list**, so the error shows: the previous search's salons would answer a text the person no longer reads. The same search pulled again and failed keeps them (SYSTEM §12.1).
  - **The map's failed read empties the map's list too:** the pill names a commune whose salons the map could not get.
  - **The featured read no longer writes the salon page's `isLoading` either** — the same leak as the list's, in the carousel.
  - **The map's markers for `nails` and `massage` are unchanged:** the shop glyph in ink, as on the website's `SalonPin`. The one list carries them as they were; giving them an accent is a SYSTEM §3.6 change, with the website.
  - **The Pro editor's category order follows the one list**, which is the website's: Coiffure, Barbier, Onglerie, Spa, Massage (it was salon, barber, spa, nails, massage).
- **Found while building, each by a test:**
  - **The field's name.** A `Semantics(textField: true)` around the field made a second node above the text field's, read twice. A plain `Semantics(label:)` merges into the field's own node: « Rechercher un salon » first, the hint after it, and the name kept once text is typed.
  - **The map's empty banner overflowed** at 390dp: « Toutes les communes » beside « Aucun salon à Cocody ». The status banners now put their action under the sentence. The location banner is unchanged (A6 rewrites it).
- **The defect, red first.** `home_nearby_leak_test.dart` was written against `main` (`da5faa09`) with only the screens and the real `/providers` route, and failed there three times. After « Barbier » on the list, « Près de vous » showed the two barbers. After « Mieux notés », the home was reordered by rating. After « Disponible aujourd’hui » (added after the review, the clock on a Monday), it showed the two salons open that day. It passes on the branch.
- **The independent review** (one reader, told to refute, given the code and not this section): one blocker and eight smaller findings, each re-read in the code, then fixed with a test (`936b19e3`).
  - **Blocker: no room for the results while typing on a small phone.** The field, the pill, the chips and the filters were a fixed header over an `Expanded` list. On a 360 × 640 phone at 2× with the keyboard up (280dp), the header took the whole height: « A RenderFlex overflowed by 36 pixels » at one letter, and the results got 0dp after. This is the moment the results are the point (§11 Q3). **The screen is now one scroll view**: the header scrolls away with the results, and a drag lowers the keyboard. The keyboard test was watched red on `11b6f8e9` (the 36px overflow), passes at 1× and 2× now, and its 1× run is the control.
  - **`AppAsyncView`'s sliver mode asserted on any `EmptyState`.** `SliverFillRemaining(hasScrollBody: false)` asks its child for an intrinsic height, and `EmptyState` is a `LayoutBuilder`. The home's sliver never met it, because its empty state is a bare `Text`. The same extent (the viewport minus the slivers before it) is now given without asking, so the home renders identically.
  - **No skeleton over an empty answer.** A key typed under « Aucun résultat pour … » blinked the skeleton in and out. The empty sentence now stays, with « Recherche… » above it. The error stays until the next answer, so « Réessayer » shows the skeleton and not the error.
  - **Every answer is announced, and only on its own screen.** A pull that failed and kept its salons showed nothing; it is now announced. « Liste mise à jour » is no longer said on top of each answer. An answer that arrives under another screen (a commune chosen on the map) is not read over it.
  - **« Disponible aujourd’hui » leaked into the home too.** Both tests were watched red against `main` `da5faa09` with the clock on a Monday, when two seeded salons are closed:
    - « Près de vous » became [provider2, provider3];
    - a booking without its own salon name lost « Salon Excellence ».
  - **Smaller gaps, each closed by a test:**
    - a text with « Disponible aujourd’hui » or a category: the text's row comes first (§2.10);
    - « Afficher plus de salons » checked loading, not merely gone;
    - exactly one full page offers nothing more;
    - a review posted while a search is open moves its card from « (89) » to « (90) ».
  - **The map's « Chargement des salons… » is not a live region.** The map announces the outcome: the failure, the empty commune, the 50 line.
  - **Hygiene:**
    - `search_text.dart`'s white-space class held ten invisible characters. It is now written with escapes and pinned to the server's `kSearchSpaces`.
    - The mock's relevance comment now says it is the seed order: a `Provider` carries no `featured` flag to rank by. Both sorts are tested.
    - The search goldens now skip off Linux, as every other golden file does.
- **Tests that moved** (§5): the sort test left `ProviderProvider` for the controller; `provider_provider_test` now asserts that a list failure is the list's error, not the salon page's; the map test's fake answers `searchProviders`; the grid is a `SliverGrid` (a `GridView` has no footer); the Play listing test reads the new category format; the chips take `onSelected`. After the review, the goldens scroll the page's one vertical scroll view.
- **Mutations: 48, each watched red on committed code** (a script applies one, runs the tests that guard it, restores the file from git, and reports a mutation whose text it cannot find as no result, never as a pass):
  - **the search:**
    - the 350 ms wait;
    - the 2-letter floor;
    - a stale first page, or a stale « Afficher plus » page, written;
    - the append's de-duplication;
    - `page × 20 <= total`;
    - « Afficher plus » during a new search;
    - a reload on every notification;
    - control characters kept;
    - a failed new search keeping the old salons;
    - emptying the field not searching;
    - dispose still listening;
  - **the leak:**
    - the home taking the list's sort;
    - a list read writing the salon page's error;
    - `providerForMap` and a review's figures skipping an open search, in the unit and on a drawn card;
  - **the screen:**
    - « nothing public » never shown;
    - the empty rows out of order, and the text's row losing to « Disponible aujourd’hui » or to a category;
    - the count taken from the cards;
    - the count row back to a `Row`;
    - the field unnamed;
    - an unknown `?category=` kept;
    - `?focus=search` ignored;
    - the counter drawn;
    - an announcement on every notification;
  - **the review's fixes:**
    - the skeleton over an empty answer;
    - the error cleared at the start of a search;
    - « Réessayer » leaving the error standing;
    - a failed pull not announced;
    - « Liste mise à jour » said again;
    - an answer read over another screen;
    - « Afficher plus » never loading;
    - `AppAsyncView`'s sliver fill back to `SliverFillRemaining`, or filling nothing;
    - the white space drifting from the server's;
    - « Recherche… » over the error view, or only over salons;
  - **the map:**
    - the empty banner over a focused salon;
    - 20 salons instead of 50;
    - the loading pill announced;
    - a read for the same commune asked again while one is out;
  - **the data:**
    - an inactive service matching;
    - `total` read as 0 when missing;
    - `massage` dropped from the taxonomy.

  **Two did not go red the first time, and each was a finding:**
  - **M20** (the map's « commune changed? » check deleted) did not fail; it **hung the test isolate for 20 hours**. `loadMapSalons` notifies, and a listener that reloads on every notification called it from inside itself without end: in the app, a frozen screen. A read already out for the same commune is now not asked again (`486e9e8f`, guarded by M46). With M20 applied, the map asks twice and the test fails in 4 s.
  - **M25** (`total` read as 0 when missing) stayed green. Its test sent a body without `page` either, so it failed on `page` whatever `total` did. The body now holds everything but `total`.
- **Goldens, authored on Linux by `goldens.yml` and each opened:**
  - **8 new**, each at 390 × 1× and at the floor, 360 × 200 %: `consumer_search_results`, `consumer_search_empty`, `consumer_search_more` and `consumer_map_commune`.
  - **2 changed:** `consumer_home` and its 360 × 200 % twin, for the chips (« Tous, Coiffure, Barbier, Onglerie… » where « Tous, Barbier, Salon, Spa » was).
  - **79 byte-identical.**
  - **Three runs:**
    - **The first** (45813232558) drew Beauté Divine's card without its photo at 1×. The photos decode off the fake clock, and only the second picture found the photo in the cache. The pictures now precache their asset photos.
    - **The second** (45813754123) failed on the map. Real async time let `flutter_map` open its tile cache, which needs `path_provider`. The map picture shows no photo and no longer waits for one.
    - **The third** (45814252477) is the committed set. The old home picture's blank photos predate A4.
- **Not done here:** the consumer build, its upload and its release, each on the owner's word; A4w (the website), next.

### 3.3 A4w, the website (designed and built 2026-11-26)

Decision 233's half: « Afficher plus » and the count from `total` on `/recherche`. This section is the web detail §2 leaves open; it follows the app's flow (§2.5, §2.6, §2.1 step 6), in the website's own layout.

**Today** (read on `main` `89ff92ca`):
- **One page of 24, read on the server.** `/recherche` renders on demand (`force-dynamic`) and reads one page of 24 (`app/recherche/page.tsx:40-47`). `searchProviders` keeps only `items` (`lib/api/providers.ts:74-98`), so `total` is dropped.
- **The count stops at 24.** It is `results.length`, drawn as « N salons ».
- **No way past the 24th salon.**
- **The browser never calls the API host.** Every browser read goes through a same-origin `/api/*` route handler. `lib/api/client.ts` is `server-only`, and the API's CORS allowlist rests on that.

**What changes:**
1. **The count is the server's `total`:** « 42 salons ». Hidden when there is nothing, since the empty state says it, as today.
2. **« Afficher plus de salons »:** a secondary `Button`, full width, after the rows, shown while `pages × 24 < total`.
   - **A tap reads the next page** through a new same-origin route, `GET /api/recherche`. It is named after the page it serves: `app/api/providers` must not exist, a pin of the by-id proxy it once held (`no-public-provider-read.test.ts`). It forwards only `q`, `category`, `commune`, `sort`, `availableToday` and `page`, and fixes `pageSize` at 24 itself. A lost body is 502, as `/api/availability` does.
   - **While it loads,** the button shows its spinner (`isLoading`, `aria-busy`) and the rows stay.
   - **If it fails,** its place says « Impossible d’afficher la suite. » with « Réessayer », the app's words. The rows stay.
   - **Appended rows are de-duplicated by id.**
   - **What starts again at page 1:** a new search, a chip, « Trier » and « Disponible aujourd’hui » each navigate, as today.
3. **« Retour » from a salon, and a reload, show the same rows** (§2.1 step 6, the app's rule):
   - each page read writes `pages=N` into the address (`history.replaceState(null, …)`, no navigation, so Next's router learns it);
   - the server then reads page 1, then pages 2 to N in parallel, up to 10 pages (240 salons), and never past the last page page 1's `total` says exists. A later page that fails shows the pages read before it, with the button for the rest;
   - the address and the rows are kept in step. If the address asks for more pages than are shown, it comes down to them; this is a soft « Retour » after a header search, whose first answer Next keeps. If it asks for fewer after « Afficher plus », the same search was asked again, and the list starts again;
   - `pages` outside 1–10, or not a number, is read as 1;
   - a shared link opens the same list.
4. **The map shows every row,** the appended ones included, and refits to them, as it does today for its first page. The card and marker sync needs a marker for every card.
5. **After a page lands:**
   - the focus moves to the first new salon's link, so a keyboard user continues where the new rows start;
   - a polite status says « 24 salons de plus, 48 sur 63 » (WEB-SYSTEM §7).

**Edge cases:**
- **A salon published, or moved up the ranking, between two pages** pushes the rest down by one: the de-duplication keeps it from showing twice. **One unpublished** pulls the rest up, and one salon is skipped, as in the app. Paging by offset cannot see that. The newest page's `total` decides whether the button stays.
- **Ten pages read,** with more left: the button reads the eleventh page as usual. Only the address stops at `pages=10`, so a reload shows 240.
- **On a phone,** the floating « Carte » rides over the rows while scrolling and stops under the button at the end (B11.5).

**Security:**
- The route forwards an allowlist of parameters, and sends no cookie.
- The server validates the text (100 characters, no control character, A4-api).
- `q` already sits in the address and in Cloud Run's logs (B0.15, decision 55).

**Performance:**
- No new read before a tap.
- The client component is already on the page.
- A reload with `pages=N` makes 1 read, then at most N − 1 in parallel, and none past the last page. Each read loads every matching salon, and with « Disponible aujourd’hui » checks each one's slots (`backend/routes/providers/index.dart`), so a typed `pages=10` over 20 salons is one read.

**Tests:**
- **Unit (RTL):**
  - the count from `total`;
  - the button at `pages × 24 < total` and gone at `=`;
  - the append and its de-duplication;
  - the loading state;
  - the failure and « Réessayer »;
  - the focus and the status;
  - `pages` in the address.
- **The route:**
  - its allowlist;
  - `page` forwarded and `pageSize` fixed;
  - a lost body is 502.
- **The page:** `pages` clamped to 1–10, with N reads.
- **e2e,** with the stub paging 30 salons:
  - « 30 salons »;
  - « Afficher plus » shows 30 rows and the button goes;
  - a failing second page shows the message and « Réessayer »;
  - a reload with `pages=2` shows 30;
  - « Retour » from a salon, with no reload, shows 30;
  - « Retour » after a header search: the address and the rows agree;
  - axe on `/recherche` with the button.
- **Mutations:** each rule above, watched red.

**As built** (branch `feat/a4w-web-search`, `ce976e8e`, then the review's fixes in `9c6c9656`):
- **Found by its own test, red first:** a page answered after a new search was rightly not appended, but it still wrote `pages=2` into the new search's address.
- **The route is `/api/recherche`,** not `/api/providers/search`: `no-public-provider-read.test.ts` pins that `app/api/providers` does not exist.
- **The independent review** (one reader, told to refute): no blocker, six findings. Each was re-read in the code, the first in Next 14.2.35's own source, and fixed with a test.
  1. **Next never learned the address.** It was written with `history.state`, whose `__NA` mark makes Next's patched `replaceState` skip its router. It is written with `null` now, and the address is kept in step with the rows (item 3).
  2. **A typed `pages=10` made ten full reads,** and one failed page failed the whole search. The reads are now bounded by `total`, and a later page that fails leaves the pages before it (item 3).
  3. **The focus moved even when the person had moved it.** Now it moves only from the button, or from the page the busy button let go. A page that adds nothing says « Aucun salon de plus, … ».
  4. **The stale-page guard read a ref set in an effect,** after Next had already written the new search's address. It is set while rendering now.
  5. **Lists are told apart by a token,** not by the `results` array a soft « Retour » brings back. An older read no longer holds the button or lands unasked.
  6. **The duplicate's cause was backwards** in a comment and a test (the edge cases above).

  The review also found missing tests, all written: the `null` state, the status region present before its text, the route's `no-store`, and « Retour » without a reload and after a header search.
- **Mutations: 37, each watched red on committed code.** 36 are unit-level. The 37th, the map showing only the first page, is caught by the e2e.
  - **Two did not go red the first time:**
    - **W24** (the address written with `history.state` again): jsdom's state is `null`, so the mutant passed `null` too. The test now starts from an entry carrying `__NA`.
    - **Reading the router's address instead of `location`:** the e2e passed too. Reading `location` stays, called a precaution, not a rule.
- **Checks:** the full web unit suite (3371 pass), typecheck and lint clean, and 14 e2e tests including axe.

**Rollout:**
- **Its merge is a production deploy of `myweli.com`** (Vercel), on the owner's word.
- **Read back on `myweli.com` after:** `/recherche` renders and the count shows.
- **« Afficher plus » cannot be seen in production** until more than 24 salons are public. Today none is.

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

**B16.1** (the category column: spec #857, fix #860) is not a prerequisite for building A4; its deploy was for the category chips to be right in production, and it is done (2026-11-25, `myweli-api-00058-tnp`, records #862).

**Not in V1 scope, recorded:** typo tolerance, recent searches, suggestions, Maquillage and Sourcils & cils as categories, a SQL `LIMIT`.

## 10. Definition of done

- Each PR's tests, mutations and goldens of §8.
- `flutter analyze` 0; `dart analyze` 0; typecheck and lint clean.
- The contract updated with A4-api.
- A4-api deployed and read back on the production API: the migration's log line on the new revision, and `/providers?q=beaute` answering 200.
  - **The matching itself cannot be observed in production** while no salon is public: every answer is empty, before and after. Until then, the evidence is the contract suite on CI's Postgres. That limit is written in the PR, not glossed.
  - Once a salon is public, the read-back is its name typed without accents, with a control (a text that must not match).
  - **A4-api's read adds the database's `datctype`** (read-only, on the owner's word): `en_US.UTF8` confirms that `lower()` lower-cases « Ɔ », « Ɛ » and « Ŋ » as the tests assume (§3.1, the review's suspicion).
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
