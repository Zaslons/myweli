# « Mes données » refuses instead of handing over a copy with holes (web + app)

| | |
|---|---|
| **Status** | **Built** on `fix/consumer-export-completeness` (2026-10-16). Applies the owner's decision for the salon export ([web-pro-export-completeness.md](web-pro-export-completeness.md) §3, PR Zaslons/myweli#618: refuse, don't mark) to the consumer export. The French copy in §4 is new and is the part to review. Not merged, not deployed. |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-10-16 |
| **PRD ref / phase** | FR-AUTH-005 (data export) · V1 · parity 11.2 |
| **Related** | [web-pro-export-completeness.md](web-pro-export-completeness.md) (the same defect, salon side; §8 named this one as its follow-up) · [consumer-favorites.md](consumer-favorites.md) (the hydrated `/me/favorites`, Decision C) · [SYSTEM.md](SYSTEM.md) §12 (an error state is a way out) |
| **Skills checked** | myweli-web-guardrails · myweli-dev-guardrails |

## 1. The defect (verified in the code on 2026-10-16, `main` at `8258d42a`)

The consumer export assembles one JSON document (profile, appointments,
favourites) on the device. Both surfaces made the same mistake as the salon
export: a read that failed became an empty section, and the screen offered the
result as the user's data.

### Web: `web/components/account/DataExportClient.tsx`

1. **A failed read becomes an empty section.** `getMe()` is checked, but
   `listAppointments()` and `getFavorites()` come out of a `Promise.all`
   whose `status` is never read: `setAppointments(appts.items)`,
   `favs.favorites.map(...)`. In `web/lib/api/account.ts` both helpers turn a
   non-200 into an empty list (`items: []`, `favorites: []`). The page then
   shows « Rendez-vous 0 » or « Favoris 0 » and offers « Télécharger (JSON) »
   with `"appointments": []` or `"favorites": []`.
2. **A 200 whose body never arrived whole is also an empty list.** Both
   helpers parse with `res.json().catch(() => ({}))`, then read
   `body.items ?? []`. When the connection drops after the headers (a 200)
   and before the end of the body, `res.json()` rejects; the catch turns
   that into `{}`, and the helper returns `{ status: 200, items: [] }`. A
   status check alone would not catch this one. The BFF itself always sends
   the array on a 200 (`enrichAppointments`, the favourites route), so an
   array that is missing in the browser means the body was lost on the way.
3. **A thrown fetch leaves the page on the spinner.** `load()` has no
   `try`. If `getMe()` or one of the two list reads throws (network down),
   the promise rejects unhandled and `setLoading(false)` is never reached.
   The page stays on `<Loading>` until a reload, with no message and no
   retry.
4. **A session that ends between reads becomes an empty section.** A 401 is
   handled for `getMe()` only. A 401 on the appointments or favourites read
   goes out as an empty list, like any other failure.
5. **A refused clipboard is unhandled.** `navigator.clipboard.writeText` can
   reject (permission, an unfocused document, no clipboard on an insecure
   origin). Nothing catches it and nothing tells the user.

### App: `mobile/lib/screens/profile/data_export_screen.dart`

6. **A failed read becomes an empty section.** The screen awaits
   `AppointmentProvider.loadAppointments()` and
   `FavoritesProvider.loadFavorites()`, and then reads their lists. Neither
   method throws: on a failed response or an exception, each sets `error` and
   resets its list to `[]`. The screen's `catch` never runs, so it never
   reads `error`, and it shows « 0 Rendez-vous » or « 0 Favoris » and offers
   « Copier mes données (JSON) ».
7. **The favourites are not read, they are remembered.**
   `loadFavorites()` returns early when the same user already has a non-empty
   list in memory. The export then copies the list from earlier in the
   session, and misses a favourite added since on another device (the web).
   A plain status check would make this worse: the early return keeps an
   old `error` (a failed heart tap sets it), so the export would be refused
   on every attempt until the next successful toggle.
8. **A favourite's name depends on a second, unchecked read.** The screen
   maps favourite ids to names through the discovery list
   (`ProviderProvider.providers`, loaded if empty). That list excludes salons
   that stopped (`draft`, `suspended`), and when its own read fails it is
   empty. In both cases the export writes the salon's **id** where its name
   belongs. The favourites read already carries each salon, name included,
   hydrated by the server (Decision C, [consumer-favorites.md](consumer-favorites.md)).
9. **A refused clipboard is unhandled.** `Clipboard.setData` can throw a
   `PlatformException`. Nothing catches it, and the « Données copiées »
   success snack is never reached, so the tap does nothing visible.
10. **An account without a phone cannot open the screen at all.** Found
    while writing the tests, not reported by the sweep. The profile line
    reads `profile['phoneNumber'] as String`, but `User.phoneNumber` has
    been optional since the auth overhaul (identity = email). The login's
    mandatory phone step is screen state only: the session is saved before
    it, and no router redirect enforces it. So a client who signs in with
    Google or by email and leaves the app at that step comes back signed in
    with no phone, and Profil → « Mes données » throws a `_TypeError` in
    `build`. It is in the screen this change rewrites and it blocks the whole
    export, so it is fixed here: the line shows `email ?? phoneNumber`, the
    web's « Profil » row.

### Not a defect: pagination

The salon export stopped at 20 clients (its §5). Neither consumer read is
paginated. `GET /appointments` for a user returns every row
(`listForUser` has no `LIMIT`; the route answers `page: 1`,
`pageSize: items.length`, `total: items.length`), and `GET /me/favorites`
returns the whole list (`favorites` has no `LIMIT`; one `byIds` hydration).
Nothing to walk, nothing truncated.

## 2. Parity

The two surfaces already shared a failure state for the profile read (web
`ErrorState` « Chargement impossible. », app `EmptyState` « Chargement
impossible »), with a retry. This change routes **every** failed read to that
state, on both surfaces, and makes it say which data is missing.

The surfaces still differ in one way, unchanged here: the web offers
« Télécharger (JSON) » and « Copier », the app offers only « Copier mes
données (JSON) ». So the way out of a refused clipboard differs (§4).

## 3. Decision: refuse, don't mark

Same decision as the salon export ([web-pro-export-completeness.md](web-pro-export-completeness.md) §3),
and the same reasons apply with more force here:

- **Every read is the user's own data**, read with their own session. A
  failure is either transient (5xx, network, a body lost on the way), so a
  retry can succeed (§12 allows a retry only then), or the session ending,
  which goes to sign-in.
- **The reader is a client, not a developer.** « Rendez-vous 0 » next to a
  download button reads as « you have no bookings ». A marker inside a JSON
  file they may never open does not undo that.

The page loads its data before it offers anything, so the refusal is the
page's error state: neither « Télécharger » nor « Copier » is rendered.

## 4. UX and copy

| State | Web (`/mon-compte/donnees`) | App (« Mes données ») |
|---|---|---|
| Loading | `<Loading>` (unchanged). | `LoadingIndicator` (unchanged). |
| A read fails (non-200 other than 401, a thrown fetch, or a 200 whose list did not arrive) | `ErrorState`, h1 « Mes données », the message below, « Réessayer ». No download, no copy. | `EmptyState` « Chargement impossible », the message below, « Réessayer ». No copy. |
| The session is over (401 on any read) | `router.replace('/connexion?returnTo=/mon-compte/donnees')` (the existing `getMe()` path, now for every read). | Unchanged: the app has no per-screen 401 path; the consumer session is handled app-wide. |
| The clipboard is refused | Under the buttons, `role="alert"`: « La copie a échoué. Téléchargez le fichier avec « Télécharger (JSON) ». » The download needs no clipboard permission. The line clears on the next copy or download. | Error snack: « La copie a échoué. Réessayez. » The app has no download; the button stays, and a `PlatformException` from the clipboard is not a permanent state. |
| Success | Unchanged. | Unchanged (the favourite names now come from the favourites read itself, §1 point 8). |

**The refusal message** (both surfaces, the same sentence):

> Impossible de charger {sections}. Vos données ne sont proposées que
> complètes : vérifiez votre connexion et réessayez.

`{sections}` names each section that failed, in a fixed order: « votre
profil » (web only: the app reads the profile from the signed-in session, not
from a request), « vos rendez-vous », « vos favoris ». Two are joined with
« et », three with « , » then « et ». Example: « Impossible de charger vos
rendez-vous et vos favoris. Vos données… ».

## 5. How it is built

### Web

- `lib/account/export.ts` gains `exportFailureMessage(failed)` and
  `EXPORT_COPY_FAILED`, pure and unit-tested, the consumer twins of the
  salon export's helpers.
- `lib/api/account.ts`: `listAppointments()` and `getFavorites()` answer
  `status: 502` when a 200's body does not parse or carries no array (§1
  point 2). Every other caller already checks `status === 200`
  (`AccountClient`, `SalonVisitsCard`, `RechercheClient`, `FavoriteButton`),
  so for them a lost body now reads as the failure it is, rather than as an
  empty list.
- `DataExportClient.load()` runs the three reads with
  `Promise.allSettled` (a fetch that throws is one failed section, not a
  rejection that leaves the spinner up), redirects on any 401, and otherwise
  either renders the summary or the refusal naming each failed section.
  `copy()` catches a refused clipboard.

### App

- `core/utils/data_export.dart` gains `DataExportSection`,
  `dataExportFailureMessage(failed)` and `kDataExportCopyFailed`.
- `FavoritesProvider.loadFavorites(userId, {bool force = false})`: `force`
  skips the in-memory early return, so the read happens and `error` is reset
  (§1 point 7). Every existing caller keeps the cache.
- `DataExportScreen._load()` awaits both loads, then reads each provider's
  `error`. Each provider sets its list and its `error` together on every
  completion, so `error == null` means the list is a successful answer. Any
  error → the refusal. Favourite names come from
  `FavoritesProvider.favoriteProviders` (the server-hydrated salons), and the
  screen no longer reads `ProviderProvider`.
- `_copy()` catches a `PlatformException` from the clipboard.
- The profile line shows `email ?? phoneNumber` (§1 point 10).

## 6. Tests (each watched red against `main` before the fix)

`web/tests/data-export-client.test.tsx`:

- The appointments read answers 500 → the refusal names « vos rendez-vous »,
  « Réessayer » is offered, neither « Télécharger (JSON) » nor « Copier » is
  rendered.
- The favourites read answers 503 → « vos favoris ».
- Both fail → « vos rendez-vous et vos favoris ».
- The appointments fetch **throws** → the refusal, not the spinner.
- The profile fetch **throws** → « votre profil », not the spinner.
- The appointments read is a 200 whose body breaks mid-stream → the refusal;
  the same for the favourites read.
- The favourites read answers 401 → `/connexion?returnTo=/mon-compte/donnees`.
- « Réessayer » after a failure reads again; with every read at 200 the
  summary and the buttons appear.
- The clipboard rejects → the copy sentence, announced; no « Copié ✓ »; the
  download still works and clears the line.
- CONTROL: a clipboard that accepts → « Copié ✓ », no alert.
- CONTROL: every read 200 → the counts, and the downloaded file carries every
  appointment and every favourite.

`web/tests/account-export.test.ts`: the refusal's wording for one, two and
three sections, in the fixed order whatever order they failed in.

`mobile/test/widget/data_export_screen_test.dart`:

- The appointments read fails → « Chargement impossible », the sentence names
  « vos rendez-vous », « Réessayer », no copy button.
- The favourites read fails → « vos favoris ».
- The appointments read throws → the refusal.
- Favourites loaded earlier in the session, one added since on the server →
  the export copies both (a fresh read, not the memory).
- A favourite salon missing from the discovery list (stopped) → its **name**
  is copied, not its id.
- « Réessayer » after a failure reads again and offers the copy.
- An account with no phone (email sign-in) → the screen renders, its email
  on the profile line, the copy offered.
- The clipboard throws → « La copie a échoué. Réessayez. », no success snack.
- CONTROL: every read succeeds → the counts, the success snack, and the
  copied JSON carries every appointment and every favourite name.

`mobile/test/unit/data_export_test.dart`: the sentence for one, two and
three sections, in the fixed order.

e2e (Playwright, the stub API): `account.spec.ts` already opens the page
through the real BFF routes and checks « Télécharger (JSON) » is offered. It
is the CONTROL for the stricter body check in `lib/api/account.ts`: the BFF's
real answers still parse as a whole read. 9/9 green.

**Watched red against `main` (2026-10-16).** Web: 10 of the 12 component
tests red (no refusal, the spinner left up by a thrown read, the summary
offered after a lost body, no redirect on a favourites 401, no clipboard
line), the 2 CONTROLs green. App: 8 of the 9 widget tests red (the refusal
never shown, `['Salon Excellence']` from memory instead of two salons,
`stopped-salon` copied instead of « Salon Fermé », the `_TypeError` for a
phoneless account, the unhandled `PlatformException`), the CONTROL green.
The wording tests fail to compile against `main` (the helpers are new).

**Mutations (2026-10-16, on committed code): 20 run, 20 red.** Each was
applied to the committed fix, its targeted tests run, and the file restored
from git. Web: the appointments status ignored; the favourites status
ignored; a 401 redirect only on the profile read; `Promise.all` back; the
profile not named; a silent clipboard failure; the download not clearing the
copy line; a lost appointments body read as an empty list, and the same for
the favourites; sections not reordered; « et » for every join. App: the
appointments `error` ignored; the favourites `error` ignored; the favourites
from memory (`force` dropped at the call, and ignored in the provider);
favourites copied by id; a silent clipboard failure; the `as String` back;
sections not reordered; « et » for every join. The first run had **one
survivor**: no test sent the favourites read a lost body. That test was
added, watched red against `main`, and the mutation re-run red.

## 7. Follow-ups (not in this change)

- **Web « Mon compte »** (`AccountClient`) reads the favourites without
  checking the status (`setFavorites(f.favorites)`): a failed favourites read
  shows « Aucun favori » to a user who has some. Same defect class, on a
  screen that is not the export.
- **App salon export** (`ProDataExportScreen`) — already listed in
  [web-pro-export-completeness.md](web-pro-export-completeness.md) §8.

## 8. Rollout

- **No contract change, no backend change.**
- **Web:** Vercel deploys it at merge.
- **App:** ships with the next store build.
