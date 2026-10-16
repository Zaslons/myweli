# The salon data export refuses instead of handing over a file with holes (app Pro)

| | |
|---|---|
| **Status** | **Built** 2026-10-16 on `fix/app-pro-export-completeness`. Not merged, not released. The decisions are the owner's, taken for the web on 2026-10-16 ([web-pro-export-completeness.md](web-pro-export-completeness.md) §3, §5, §6); this is the app half §8 there names. |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-10-16 |
| **PRD ref / phase** | AUTH-005 for pros (data export) · V1 |
| **Module** | `access` (who may export) · `clients` (the client file walk) |
| **Related** | [web-pro-export-completeness.md](web-pro-export-completeness.md) (the web twin, PR #618) · [pro-account-deletion-export.md](pro-account-deletion-export.md) (the export as designed) · [team-access-r6-multi-salons.md](team-access-r6-multi-salons.md) §6 (`activeSalonId`) · threat **T39** ([BACKEND.md](../BACKEND.md)) · [SYSTEM.md](SYSTEM.md) §12 (an error state is a way out), §17.1 (`’`) |
| **Skills checked** | myweli-dev-guardrails · myweli-verification-guardrails |

## 1. The defect (verified in the code on 2026-10-16, `main` at `8258d42a`)

`ProDataExportScreen._load` (`mobile/lib/screens/provider/profile/pro_data_export_screen.dart`)
makes five reads and assembles the JSON the salon copies.

1. **Four failed reads became empty sections.** Only the salon read
   (`getMyProvider`) failed the export. `getProviderServices`,
   `proArtistService.getArtists`, `getProviderAppointments` and
   `proClientsService.listClients` were read as `data ?? const []`, so an
   error answer exported `"services": []`, `"artists": []`,
   `"appointments": []` or `"clients": []`, and the count rows said
   « 0 ». The screen's own comment admitted it (« the other four soft-fail
   to an empty list »).
2. **The client file stopped at 20.** `listClients(providerId)` sent
   `page=1` and no `pageSize`, so the server default of 20 applied
   (`routes/providers/[id]/clients/index.dart`; `ClientsService.list` clamps
   to 50). A salon with 21 clients exported 20, and the « Clients » row
   said 20.
3. **Found while verifying 1 and 2: three reads went to the wrong salon
   after a switch.** The salon id was `account?.providerId ?? account?.id`.
   R6 swept the screens' `provider?.providerId` reads to `activeSalonId`,
   but this one reads through a local named `account` and slipped past the
   sweep pin (`multi_salon_test.dart`). `getMyProvider` and
   `getProviderAppointments` follow the switched-to salon (the session's
   `?salonId=`); services, team and clients went to the account's default
   salon. An owner of two salons (Réseau) who switched to the second got its
   listing and bookings with the first salon's catalogue, team and client
   file. The fallback to `account.id` was wrong too: an account id is not a
   salon id.

Not a defect, checked: the four reads cannot fail **by design** for the one
caller who sees the export. The entry is gated on `salon.publish`
(`pro_profile_screen.dart`), held by the owner preset only
(`presetCapabilitiesFor`), and the owner holds `catalogue.manage` (services,
team) and `clients.view`. `ProviderCatalogService.listServices` /
`listArtists` read the salon with `byId`, which does not filter on status, so
a draft salon is read like a published one. A refusal is therefore always
transient (5xx, network, a throw) and a retry can succeed — the condition
under which the web spec §3 chose refusal.

## 2. Decision: refuse, don't mark (the web's, applied here)

Any of the five reads failing, or a client walk that does not add up → no
export: nothing is shown to copy, and the screen says which data could not be
loaded. « Réessayer » is the way out. Same reasons as the web (§3 there): a
salon owner reads `[]` as « no clients », not « the read failed »; the gate
removes the only case where a marker made sense.

No session redirect: the web sends a 401 to sign-in, but the app's idiom is
the refreshing client — a rejected refresh clears the session and the app
falls back to sign-in. A 401 here is one more failed read.

## 3. UX and copy

| State | Screen |
|---|---|
| Loading | `LoadingIndicator` (unchanged). The five reads now run **in parallel** (they were one after another), like the web's `Promise.allSettled`; the client pages stay one after another, since each needs page 1's `total`. Safe since 2026-10-11: concurrent 401s across the three services' `RefreshingHttpClient`s share one refresh (`_inflight`, keyed by the session store — [session-refresh.md](session-refresh.md)). Each read is settled on its own: an error answer or a throw is one failed section, never a rejection of the whole load. |
| A read fails | `EmptyState`, `Icons.wifi_off` (the house idiom for « Chargement impossible »), title **« Chargement impossible »**, description **« Export interrompu : impossible de charger {sections}. Vérifiez votre connexion et réessayez. »**, action **« Réessayer »** (re-runs every read). No count rows, no copy button. |
| No account in the session (unchanged) | The same state with the old description, « Vérifiez votre connexion et réessayez. » — there is no section to name. |
| Success | Unchanged: the intro, the four count rows (now the whole client base), « Copier mes données (JSON) ». |

`{sections}` names each failed section in the file's order: « la fiche du
salon », « les services », « l’équipe », « les rendez-vous », « le fichier
clients ». Two are joined with « et »; three or more with « , » then « et »
— the web's rule (`exportFailureMessage`). Example: « Export interrompu :
impossible de charger les services et le fichier clients. Vérifiez votre
connexion et réessayez. »

The web's middle sentence (« Aucun fichier n’a été créé. ») is not carried
over: in the app nothing is produced before every read succeeds (the copy
button only appears then), so there is no file or clipboard write to deny.
The app's existing connection hint stays in its place.

## 4. The client file: walk every page

- `pageSize=50` (the server's maximum), page 1 to ⌈total / pageSize⌉, where
  `pageSize` is **the server's echo** on page 1 (the size its offsets used),
  not the one asked for. A page 1 without a positive `pageSize` refuses.
- Every page must report the same `total`, and the distinct client ids
  collected must equal it — `wholeClientBase` in
  `core/utils/data_export.dart`, the twin of the web's. Otherwise the export
  is refused for « le fichier clients ».
- A page that fails (error answer or throw) refuses the same way.
- **Depends on #618's backend tiebreaker.** The clients list sorts by
  `last_visit_at DESC NULLS LAST, created_at DESC`; #618 adds `id` as the
  last key. Until that ships, rows tied on both keys (migration 0024's
  back-fill) can repeat across pages and the check refuses — every retry,
  for such a salon. Deploying the server first avoids that window.

Contract: `ProClientsServiceInterface.listClients` gains an optional
`pageSize` (absent = the server default, so the Clients screen is
unchanged); `SalonClientsPage` gains the echoed `pageSize` (nullable: a page
built without one is never walked). The mock honours `pageSize` with the
server's clamp (1–50, default 20) and echoes it. No API change.

## 5. Security

- The entry stays `ProCap.salonPublish` (owner-only, T39). The gate is UI
  convenience; each read is authorised and the client-list reads audited
  server-side (T46), so the trail shows the export walking the base.
- The salon id is `ProAuthProvider.activeSalonId`, the one every other pro
  screen uses (R6).
- Nothing new is stored or logged.

## 6. Tests (red first against `main`)

`mobile/test/widget/pro_data_export_screen_test.dart`:

- CONTROL: every read succeeds → the counts, the copy button, and the
  copied JSON holds every section.
- Each of the five reads answering an error → « Chargement impossible »,
  the sentence naming that section, no copy button.
- A read that **throws** (the clients read) → the same, naming « le fichier
  clients ».
- Two failed reads → named in file order, joined with « et ».
- Retry after a failure → the export.
- 120 clients over three pages of 50 → all 120 counted and copied, and the
  pages were asked with `pageSize=50`.
- `total` moves between pages → refused, « le fichier clients ».
- A middle page fails → refused.
- After switching to the second salon → services, team and clients are
  read for the switched-to salon.

`mobile/test/unit/data_export_test.dart`: `wholeClientBase` (a whole walk,
an empty base, a moved total, a repeated row, a short walk, no pages) and
`proExportFailureMessage` (one, two, three sections; order).

`mobile/test/unit/pro_clients_test.dart`: `listClients` sends `pageSize`
when given and omits it otherwise; `SalonClientsPage` parses `pageSize`;
the mock honours and clamps it.

## 7. Rollout

App release (the next Pro build). No contract or backend change here; the
backend half is #618's tiebreaker (§4).

## 8. Follow-ups (not in this change)

- **The R6 sweep pin is a string match** (`provider?.providerId`) and a
  local alias dodged it (§1.3). `team_screen.dart` still reads
  `account?.providerId` as a presence check; worth a look with a pin that
  does not depend on a variable's name.
- **Consumer export** (app `DataExportScreen`, web `DataExportClient`): the
  web spec's §8 already lists it.
