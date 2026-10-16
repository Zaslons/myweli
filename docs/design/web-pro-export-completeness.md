# The salon data export refuses instead of shipping a file with holes (web)

| | |
|---|---|
| **Status** | **Approved** (owner, 2026-10-16): refuse rather than mark (§3), owner-only like the app (§6), and the backend sort tiebreaker in the same change (§5). Built on `fix/pro-export-completeness`. Not merged, not deployed. |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-10-16 |
| **PRD ref / phase** | AUTH-005 for pros (data export) · V1 |
| **Related** | [pro-account-deletion-export.md](pro-account-deletion-export.md) (the export as designed) · [web-team-access-r5.md](web-team-access-r5.md) §6 and [team-access-r4-role-shaped-app.md](team-access-r4-role-shaped-app.md) (who may export) · threat **T39** ([BACKEND.md](../BACKEND.md)) · [SYSTEM.md](SYSTEM.md) §12 (an error state is a way out) |
| **Skills checked** | myweli-web-guardrails · myweli-backend-guardrails · myweli-verification-guardrails |

## 1. The defect (verified in the code on 2026-10-16)

A read-only sweep reported it. Every point below was re-read on `main`
(`8258d42a`) before this spec was written.

1. **A failed read becomes an empty section.**
   `CompteDangerSection.assembleJson()` runs `listProAppointments()`,
   `listClients()` and `getEarnings()` in a `Promise.all` and never reads a
   `status`. Each helper in `web/lib/api/pro.ts` turns a non-200 into
   « nothing »: `items: []` for the appointments, no `list` for the clients
   (read as `?? []`), and no `earnings` (read as `?? null`). The salon gets
   `"appointments": []`, `"clients": []` or `"earnings": null`, which looks
   exactly like a salon with no bookings, no clients or no revenue.
2. **A thrown fetch leaves the button stuck.** A network failure rejects
   `Promise.all`, so `download()` and `copy()` never reach
   `setExporting(false)`. Both buttons stay disabled, the download one reads
   « Préparation… » until the page reloads, and the rejection goes unhandled.
3. **The client file stops at 20.** `listClients(providerId)` sends no
   `page` or `pageSize`, so the backend's default of 20 applies
   (`routes/providers/[id]/clients/index.dart`, clamped to 50 in
   `ClientsService.list`). A salon with 21 clients exports 20, and nothing
   says so. This is defect 1 again, in a quieter form.
4. **The web shows the export to Managers; the app does not.** The web gates
   it on `profile.manage` (the full Profil view, `ProfilClient.tsx`), which
   the Manager preset holds. The app gates « Mes données » on `salon.publish`
   (`pro_profile_screen.dart`, since R4b), so only the owner sees it. R4,
   [web-team-access-r5.md](web-team-access-r5.md) §6 (« data export stays
   owner-only ») and T39 (« later: owner-only + audited ») all say owner-only.
   A Manager has no `finances.view`, so their earnings read answers 403 on
   every attempt. Today that 403 goes out as `"earnings": null`. Once
   defect 1 is fixed, it would refuse their export every time.
5. **A refused clipboard is unhandled.** `navigator.clipboard.writeText`
   can reject (permission, an unfocused document), and nothing catches it.

## 2. What the app does (parity)

`ProDataExportScreen` (mobile) makes five reads. **One** of them, the salon
read, fails the export: the screen shows « Chargement impossible » and
« Réessayer ». The other four fall back to an empty list (the screen's own
comment says so), and its clients read also stops at page 1.

So the web follows the app's **failure UX** (refuse, then retry) and its
**gate** (`salon.publish`). The app's four silent fallbacks and its 20-client
cap are the same defect, and get their own follow-up (§8).

## 3. Decision: refuse, don't mark

When a read fails, no file is produced. The section says which data could not
be loaded, and the export buttons are the retry.

Why this and not a file with a « section indisponible » marker:

- **With the owner-only gate (§6), every read is one the caller is entitled
  to.** Any failure is either transient (5xx, network), so a retry can
  succeed and §12 allows one, or the session ending (401), which goes to
  sign-in. The marker only made sense for a section the caller can *never*
  read (a Manager's revenue). The gate removes that case.
- **The reader is a salon owner, not a developer.** A marker sits inside a
  JSON file they may never open. A file with a hole looks like a complete
  file, and that is the defect.
- **The app already refuses** on its one hard-failing read.

## 4. UX and copy

| State | What the section shows |
|---|---|
| Idle | Unchanged. |
| Preparing | Both buttons disabled; the download one reads « Préparation… » (unchanged). |
| A read fails (non-200 other than 401, or a thrown fetch) | No file and no clipboard write. Under the row, `role="alert"`: **« Export interrompu : impossible de charger {sections}. Aucun fichier n'a été créé. Réessayez. »** The buttons are enabled again; they are the retry. The alert clears when the next attempt starts. |
| The session is over (401 on any read) | `router.replace('/pro/connexion')`, the dashboard's pattern for an expired session. |
| The browser refuses the copy | **« La copie a échoué. Téléchargez le fichier avec « Exporter (JSON) ». »** The way out leads somewhere: the download needs no clipboard permission. |
| Success | Unchanged. |

`{sections}` names each section that failed, in a fixed order: « les
rendez-vous », « le fichier clients », « les revenus ». Two are joined with
« et », three with « , » then « et ». Example: « …impossible de charger le
fichier clients et les revenus. »

## 5. The client file: walk every page

- `pageSize=50` (the server's maximum), from page 1 to ⌈total / 50⌉.
- **Consistency check:** every page must report the same `total`, and the
  number of distinct client ids collected must equal it. If not, the export
  is refused for « le fichier clients ». An offset walk over a list that
  changes during the walk (a client added, a visit completed and the list
  re-sorted) can repeat a row or skip one, and a silent skip is defect 1
  again.
- Each page read is audited server-side as a client-list read (T39/T46), so
  the trail shows the export walking the base.

**The backend sort gets a tiebreaker, in this change.** The clients list
ordered by `last_visit_at DESC NULLS LAST, created_at DESC`, with no unique
last key. Migration 0024 back-filled clients in a single transaction, so those
rows share one `created_at`, and the ones without a completed visit also share
a NULL `last_visit_at`. Postgres may return tied rows in a different order on
each `OFFSET`, so a walk could repeat one and skip another. The consistency
check would turn that into a refusal, but a salon with such ties would be
refused on every retry: a dead end with a button on it (§12). So `id` becomes
the final sort key, in both the Postgres and the in-memory repository. The
Clients page's own « page suivante » had the same defect and is fixed by the
same line.

## 6. Who sees the export

The export row shows if and only if `hasCap(membership, 'salon.publish')`,
which is the app's gate. A Manager keeps the full Profil editor and account
deletion, and loses only the export buttons, as in the app. An account
without a membership row keeps it (`hasCap` → true, unchanged).

This gate is UI-only. A Manager can still read each client through the API
they are allowed to use. T39's server-side mitigation is the per-read audit,
not this button.

## 7. Tests (each one watched red against `main` before the fix)

`web/tests/compte-danger-section.test.tsx`:

- The clients read answers 500 → no file is made (`URL.createObjectURL` is
  never called), the alert names « le fichier clients », and both buttons
  are enabled again.
- The appointments fetch **throws** → the same, naming « les rendez-vous »;
  the download button is not stuck on « Préparation… ».
- Copy, with the earnings read at 503 → the clipboard is never written.
- Any read answers 401 → `/pro/connexion`, no file.
- 120 clients over three pages → the export holds all 120.
- `total` changes between pages → refused, « le fichier clients ».
- The clipboard rejects → the copy sentence.
- CONTROL: every read 200 → one file, every section filled.

`backend/test/db/postgres_repositories_test.dart` and
`backend/test/clients_test.dart`:

- Clients tied on both sort keys, inserted out of id order → each list comes
  back in id order, and a walk with `pageSize: 2` returns every id exactly
  once.

`web/tests/pro-profil-member.test.tsx`:

- Manager (`profile.manage`, no `salon.publish`) → the full editor and
  deletion, no export.
- CONTROL: owner → the export is offered.

`web/tests/pro-export.test.ts`: the refusal's wording for one, two and three
sections; `wholeClientBase` on a whole walk, an empty base, a moved `total`,
a repeated row, and a walk that falls short.

e2e (Playwright, the stub API): `roles.spec.ts` checks that the Manager sees
the full editor and no export. `pro.spec.ts` has the owner download the file
through the real BFF routes, and checks that every section is filled. That
one is a CONTROL for the happy path: it passes on `main` too, because the
stub answers every read.

**Mutations (2026-10-16, on committed code): 17 run, 17 red.** Each was
applied to the committed fix, its targeted tests run, and the file restored
from git. Web: the gate back to `profile.manage`; the appointments status
ignored; no 401 redirect; the alert not cleared on retry; a silent clipboard
failure; a thrown read rejecting the export again; the walk stopping one page
short; `pageSize` dropped from the first call, and from `listClients`; no
`total` consistency check; no distinct-count check; sections not reordered;
« et » used for every join; an empty walk accepted. Backend: Postgres without
the `id` key; the in-memory twin without the `id` key, and without
`created_at`. Planning the run found three guards that would have let a
mutation through, and each was fixed before it ran: no test sent the
appointments read a non-200; no test had a `total` that moved while the ids
still added up; and the in-memory « newest created » fixture had ids that
sorted the same way as the dates.

## 8. Follow-ups (not in this change)

- **App:** `ProDataExportScreen` refuses on any failed read and walks every
  client page.
- **Consumer export** (web `DataExportClient`, app `DataExportScreen`): the
  web one also leaves its appointments and favourites reads unchecked.
  Verify both, then apply the same treatment.

## 9. Rollout

- **No contract change.** The list's shape is the same; only the order of
  tied rows becomes defined.
- **Web:** Vercel deploys it at merge.
- **Backend:** the next production deploy, with the owner's go. Until then,
  a salon with tied clients may see the export refused for « le fichier
  clients ». The web change ships the refusal; the backend change removes
  its cause. Deploying the server first avoids that window.
