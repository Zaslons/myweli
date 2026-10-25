# What is left, and how we will solve it

| | |
|---|---|
| **Status** | Living list, **snapshot of 2026-10-18** (main at `a91edc66`). Tick or strike an item in the PR that closes it, with the PR number. **Ticked through 2026-10-21:** batch 1 (#665), batch 2 (#666) and batch 3 (#670, #671). |
| **How it was built** | Every item recorded as left to do since 2026-10-13 was collected: the out-of-scope sections of 76 specs and roadmap entries, the follow-up sections of PRs #598–#631, and the six suggested tasks still waiting. That gave 116 raw items. Then **each one was checked against the code on main** (file and line, in the linked sources), not taken from the docs. Duplicates were merged. Five items turned out to be fixed or not defects (§4). Four can only be checked by the owner (batch 10). |
| **Related** | [LAUNCH.md](LAUNCH.md) (the launch gates; not repeated here) · [ROADMAP.md](ROADMAP.md) · [design/README.md](design/README.md) |

## How to read this

- **Priority.**
  - **P1:** users hit it, or the release depends on it.
  - **P2:** real, but rare or limited in impact.
  - **P3:** hygiene, safety nets, or a decision with no live impact.
- **Size.**
  - **S:** one small PR.
  - **M:** one PR with a short spec.
  - **L:** several PRs, usually with a backend deploy.
- **Decision.** These items need your answer first. All the questions are gathered in §2, each with a recommendation.
- **How we work each item.** Unchanged: design spec first, then red-first tests, then mutations, then an adversarial review, then a PR. A backend change also needs a production deploy, and you approve every one.
- **App changes** reach users only with the next build. 0.0.2 waits for Apple's review of 0.0.1.

---

## 1. The plan at a glance

| # | Batch | What it fixes | Priority | Surfaces | Needs you for |
|---|---|---|---|---|---|
| 0 | **Release track** | 0.0.1 through review, device checks, 0.0.2, the store and policy items around them | P1 | release | 5 decisions + the device checks |
| 1 | ✅ **Pro home and journal stay fresh** | « Ma journée » and « Accueil » showing stale statuses and figures, and an error screen with no way out | P1 | app | **Done — #665** (2026-10-21) |
| 2 | ✅ **Lost answers to writes** | A booking saved but reported as failed, then a retry into « slot taken » or a double booking | P2 | web, app, backend | **Done — #666** (2026-10-21) |
| 3 | ✅ **The app says the right thing when something fails** | Raw English exception text, a bare « Erreur », two offline sentences, notification read state | P2 | app (+ web wording) | **Done — #670, #671** (2026-10-21) |
| 4 | **Web Pro is truthful on failure** | False « choose your offer », « no visits », silent reads, stale Calendrier/Liste, demo refusals | P2 | web | 3 decisions |
| 5 | **Client web polish** | Sign-in blaming the code, ♥ edge cases, export edge cases, a toast for favourites | P2–P3 | web | 1 decision |
| 6 | **Backend integrity** | Role gate on booking, invitation accounts, owner contact erasure, demo KYC, deposit range, review reports, Apple token revoke | P2–P3 | backend (+ app, web) | 6 decisions + deploys |
| 7 | **Pro app UI, accessibility and parity** | Contrast, mid-word breaks, empty states, member deletion text, invitations on « Accueil », export earnings | P2–P3 | app | 3 decisions |
| 8 | **Product questions** | Undo, phone editing, offline Profil card, V2 analytics wording, dormant phone sign-in | P3 | — | 5 decisions |
| 9 | **Hygiene, tooling and tests** | Stale docs, release tooling, mocks, test gaps, shared components | P3 | all | 2 decisions |
| 10 | **Only you can check** | App Store Connect state, support inbox, App Preview, production walk-throughs | — | owner | your time |

**Proposed order.**
- **Now:** batch 0 runs on Apple's clock. Batches 1 (#665), 2 (#666), 3 (#670, #671), 4 (#672, #673) and 5 (#674, #675) are done; **batch 6 is the next code slice.**
- **Then:** batch 6 goes out in one or two backend deploys (each one asked for first).
- **When touching an area:** batches 7 and 9.
- **Whenever you answer:** batch 8.

---

## 2. Decisions I need from you

Each question has a recommendation. Answers unblock the item named in brackets.

**Release (batch 0)**
1. **0.0.1 after approval.** Release it at once under LAUNCH §3 (production is stable), or hold it and make 0.0.2, with every fix below, the first public version? Holding costs a second review. *Recommended: release 0.0.1 when §3 allows, ship 0.0.2 with phased release.* [B0.1, B0.3]
2. **Device checks.** Run the §11.6 checklist on build 587 (the one in review) now, and the post-587 checks on 0.0.2? *Recommended: yes, both, because 587 is what Apple sees.* [B0.2]
3. **Privacy policy.** Can it say every processor protects data as well as we do? That means their standard data-processing terms are accepted on our accounts. And do you approve the new wording before it goes live? [B0.4]
4. **Pro iOS update link.** OK to write the App Store link into production now, with both floors left at 0 so nobody is affected? Or wait for the 0.0.1 release? *Recommended: now.* [B0.5]
5. **KYC under an individual Apple account (5.1.1(ix)).** Is the developer account Individual or Organization? If Apple rejects for this, do we hide KYC and deposits on iOS until an Organization account exists, or appeal first? [B0.6]
6. **0.0.2 store media.** Reshoot screenshots 3 and 8 and re-cut the preview with the new revenue wording, or keep the current media? *Recommended: re-cut only if 0.0.2 needs new screenshots anyway.* [B0.8]
7. **The unused iOS « remote-notification » mode.** Remove it in the next build, which adds one device check, or leave it? *Recommended: remove it in 0.0.2.* [B0.9]

**Pro home and journal (batch 1)**

8. **After « Accepter », « Rejeter », « Terminé » or « Absent » on the booking detail:** show the new status in « Ma journée » immediately, then reload quietly? *Recommended: yes, since the server has already confirmed.* [B1.1] — ✅ **Answered: as recommended** (#665).
9. **Pull-to-refresh on « Accueil » fails while figures are on screen:** keep the figures and say « Pas de connexion. Réessayez. »? *Recommended: yes.* Or replace them with the error state? [B1.2] — ✅ **Answered: as recommended** (#665).
10. Ship the salon-switch race fix **in the same PR** as the « Accueil » refresh fix? *Recommended: yes, they touch the same function.* [B1.3] — ✅ **Answered: as recommended** (#665).

**Lost answers (batch 2)**

11. Fix the lost booking answer **on the web only**, by checking « Mes rendez-vous » before saying it failed? Or add an **idempotency key** on the server, so web and app both get it (backend change and deploy)? *Recommended: idempotency key. It covers bookings, manual bookings, notes and invitations on both surfaces.* [B2.1] — ✅ **Answered: the idempotency key** (#666).

**App failure messages (batch 3)**

12. **Notification « marquer comme lu » whose answer was lost:** keep showing it unread until the next load (today), or retry the write once? A retry is safe because the write is idempotent. *Recommended: retry once.* [B3.3] — ✅ **Answered: retry once** (#671).

**Web Pro (batch 4)**

13. **When the salon's offer can't be read:** leave « Mettre en ligne » clickable and let the server decide? *Recommended: yes, the server re-checks.* Or block it until the offer is read? [B4.1] — ✅ **No longer anything to decide**: « Mettre en ligne » stopped reading the offer on 2026-10-19, so the server already decides; Équipe's case was asked instead (#672: say it, keep « Inviter »).
14. **The rejoin gate after a reload:** remember the last salon's name in the browser, so it can say « Votre accès à {salon} a été retiré », like the app? Or keep the generic line? *Recommended: remember it.* [B4.4] — ✅ **Answered: remember it** (built in #673).
15. **Four minor Pro sections that vanish silently on a failed read** (seats bar, stats tiles, panel client card, client suggestions): give them a one-line « indisponible » note with « Réessayer », or accept the silence? *Recommended: the note, for the three that drive an action; the stats tiles can stay « — ».* [B4.5] — ✅ **Answered: as recommended** (#672).

**Client web (batch 5)**

16. **The web ♥:** show only « Ajouté aux favoris » / « Retiré des favoris », or also « Annuler » like the app? « Annuler » would be the web's first toast with an action. *Recommended: message only for now.* [B5.4] — ✅ **Answered: message + « Annuler »**, like the app (Médias already has an action toast); « Mon compte » announces too ([web-client-polish.md](design/web-client-polish.md) Q2, Q4).

**Backend (batch 6)**

17. **When an owner deletes their account:** erase the salon's phone, WhatsApp, Mobile Money number and address, and keep only the name and the history? *Recommended: yes.* [B6.3] — ✅ **Answered: yes** — erase the numbers and the address, keep the name and the history ([backend-integrity-batch6.md](design/backend-integrity-batch6.md) Q1).
18. **A reviewer's KYC on the demo account:** erase it at the weekly reset (*recommended*), or refuse KYC submission on the demo account like publish and invite? [B6.4] — ✅ **Answered: erase it at the weekly reset** (Q2).
19. **One deposit percentage range for app, web and server:** 5–80 % (today's app slider), 1–100 % (today's web field), or another range? [B6.5] — ✅ **Answered: 5–80 %**, server-enforced when the deposit is on and the % changes (Q3).
20. **Salons reporting reviews:** the same admin queue as client reports, marked « signalé par le salon »? And may every team member report, or only Propriétaire and Gérant? [B6.6] — ✅ **Answered: the same queue, marked « Signalé par le salon »; Propriétaire and Gérant only** (Q4).
21. **Exercising the T72 fix in production:** create and delete one throwaway Pro account, or accept the CI test plus the database check? [B10]
22. **Demo identity lost outside the product:** should the weekly reset re-create it, or is an alert plus manual recovery enough? *Recommended: the alert now; re-creation only if it ever happens.* [B6.9] — ✅ **Answered: the alert now, no re-creation** (Q6).

**Pro app (batch 7)**

23. **Team invitations on the app's « Accueil »:** the web's full card with « Rejoindre » / « Refuser » (*recommended*), or only a badge on Profil? [B7.6] — ✅ **Answered: the web's card on « Accueil » and the staff « Journée »** (Q1).
24. **The « Acompte & annulation » onboarding step:** required, or « facultatif » until the salon saves a choice? *Recommended: facultatif, since deposits are not a go-live condition.* [B7.7] — ✅ **Answered: « facultatif » until a choice is saved** (Q2).
25. **An empty « Ma journée »:** keep the floating « Nouveau » button (*recommended*) or the in-page « + Nouvelle réservation »? [B7.4] — ✅ **Answered: keep the floating « Nouveau »** (Q4).
26. **Orientation:** portrait only for both apps on Android and iPhone, the client app included? *Recommended: yes.* Or a landscape design pass for the client app? [B7.9] — ✅ **Answered: portrait on Android and iPhone for both apps; the iPad unchanged** (Q3).

**Product questions (batch 8)**

27. **Undo** for cancelling a booking, revoking a member and deleting an account? It needs server « pending » states, and a grace period stated in the privacy policy. Or keep confirm-only? [B8.1] — ✅ **Answered: keep confirm-only** (SYSTEM §15's ladder; [product-questions-batch8.md](design/product-questions-batch8.md) Q1).
28. **The Pro account phone:** still a sign-in identity, so changing it needs an SMS code and waits for real SMS? Or only a contact number pros can edit now? [B8.2] — ✅ **Answered: nothing now** — it stopped being an identity in migration 0023 (no longer unique); decide with phone sign-in's return (Q2).
29. **The « Profil » salon card offline:** keep a small offline copy (name, category, address, phone), or accept « could not load / Réessayer »? [B8.3] — ✅ **Answered: a small offline copy** (Q3).
30. **V2 analytics chart:** count « Revenus prévus » or « Total réalisé »? Needed only when V2 is built. [B8.4] — ✅ **Answered: « Total réalisé »** (Q4).
31. **Dormant phone sign-in:** repair and route it when SMS returns, or delete it now and rebuild it later on today's sign-in path? [B8.5] — ✅ **Answered: remove it now** — it opens with the clients' `AUTH_METHODS` switch and signs into the first account carrying a number that is no longer unique (Q5).
32. **Atomic Pro account deletion:** accept today's repeatable order, where a retry completes the deletion, or build full atomicity at real cost? *Recommended: accept, and add the retry test.* [B8.6] — ✅ **Answered: accept, and add the retry test** (Q6).

**Hygiene (batch 9)**

33. **Type-level `SalonId`** across about 34 salon-scoped signatures, to close a test blind spot? Or accept the documented limit? *Recommended: accept for now.* [B9.9] — ✅ **Answered: build the type** (« what is better for the long term »; [hygiene-batch9.md](design/hygiene-batch9.md) Q1).
34. **Alerts:** stay with e-mail plus Sentry push, or build a WhatsApp webhook? And do you want Sentry performance monitoring (paid)? [B9.4] — ✅ **Answered: e-mail plus Sentry push; no performance monitoring for now** (Q2, Q3).
35. **Mock mode:** add a « mark read fails » switch so the revert can be shown by hand? It's already pinned by 32 tests. *Recommended: no.* [B9.6] — ✅ **Answered: no** (Q4).

**Demo salon (batch 10)**

36. OK to fix the demo salon's text nits and re-save its snapshot in production **after Apple's decision**? [B10]
37. **The demo salon photos:** where did each come from? A link and a licence for each. [B10]

---

## 3. The batches

### Batch 0 — Release track (P1, on Apple's clock)

- **B0.1 Carry 0.0.1 through review, then release by hand (P1 · S · decision 1).**
  - **What:** build 587 is in App Review, and its release is set to manual.
  - **How:** while it's in review, nothing the reviewer relies on may change. No `DEMO_PROVIDER_CODE` rotation, no change to Cloudflare in front of `api.myweli.com`, and « Production checks » stay green. Answer any Resolution Center message the same day. If rejected: fix, rebuild through the normal flow, resubmit. If approved: leave it « Pending Developer Release » until you confirm LAUNCH §3, then press Release. Record the dates in LAUNCH §6.2 and app-store-forms §12.3.
- **B0.2 On-device checks on a real iPhone (P1 · M · decision 2).**
  - **What:** no signed build has been checked on a real iPhone. That covers:
    - Sign in with Apple, a real push and staying signed in;
    - the portrait lock and the KYC picker;
    - the demo refusal and the « Ma journée » fix, which were only seen in the simulator.
  - **How (587, now):** you run app-store-forms §11.6 in its written order, in French, against production. The fresh Apple account goes through onboarding, the invite refusal and going live, and is then deleted.
  - **How (0.0.2):** the post-587 list — a 9- and a 10-digit number; deposits off then on; export with the network cut; airplane mode at launch; the switcher offline; a failed « Tout lire »; switching between two salons; revoke then re-invite; **« Appeler » on a salon's page opens the dialer** (B7.11 — two buttons asked `canLaunchUrl(tel:)` first). I turn it into the « What to Test » text and record the results.
- **B0.3 Ship Pro 0.0.2 (P1 · M · decisions 1, 6, 7).**
  - **What:** 22 app commits since 587 (#596–#630) reach users only through a new build.
  - **How:** after Apple decides on 0.0.1:
    1. bump `mobile/pubspec.yaml` to 0.0.2;
    2. `./tool/release_build.sh ios pro` from main;
    3. IPA checks, including the new strings;
    4. upload, with Dart symbols and dSYMs to Sentry;
    5. French « What to Test »;
    6. version 0.0.2 in App Store Connect with **phased release on** (needs B0.7 first);
    7. submit after B0.2.
- **B0.4 Privacy policy: Cloudflare, equivalent protection, each app's export path (P1 · S · decision 3).**
  - **What:** the policy names Cloudflare only for files, but every API request has gone through Cloudflare since 2026-10-07. It also lacks the « equivalent protection » sentence Apple asks for under 5.1.1(i). And it gives the Pro export path as « Exporter mes données », while the Pro app says « Mes données ».
  - **How:** edit `web/app/politique-confidentialite/page.tsx` and bump `LEGAL_UPDATED_AT`. Re-check the « Journaux de requêtes » sentence against Cloud Logging, since the visitor IP may now be Cloudflare's. After the deploy, read the live page.
- **B0.5 Set the Pro iOS `updateUrl` in production (P2 · S · decision 4).** In the admin console, set `com.myweli.pro / ios` to `https://apps.apple.com/app/id6805272779` with both floors at 0. Read it back through `GET /client-version`.
- **B0.6 KYC under an individual developer account (P2 · S · decision 5).**
  - Record the membership type.
  - If Apple rejects under 5.1.1(ix), hide « Vérification » and the deposit switch on iOS only, with forced-iOS tests, until an Organization account exists.
- **B0.7 Replace the crash-free-rate alert before phased release (P2 · S).**
  - **What:** sessions are off to keep the privacy promise, so the planned crash-free-rate alert has nothing to measure.
  - **How:** in Sentry `myweli-app`, three issue alerts on production: a new fatal issue in the latest release; any issue seen by more than 3 users in 1 h; app hangs seen by more than 3 users in 1 h. Send a test event for each, and update observability §8.3 and LAUNCH §1.4.
- **B0.8 0.0.2 store media (P3 · M · decision 6).** If yes: reshoot screenshots 3 and 8 with `tool/app_store_screenshots`, and re-cut the Revenus scene and poster with `tool/app_store_preview`.
- **B0.9 Remove the unused « remote-notification » background mode (P3 · S · decision 7).** Delete it from `Info.plist`, which both apps share, and check a real push with the app killed in the next TestFlight run.
- **B0.10 Google Play forms for both apps (P2 · M).**
  - **What:** nothing has been typed into Play Console yet.
  - **How:** you type play-store-forms §1–§5 with the amended App access text. I check them against the policy and the iOS answers, make the 1024×500 banner, and add a length test for the access text.
  - **Order:** Android is last (LAUNCH §3).

### Batch 1 — Pro « Accueil » and « Ma journée » stay fresh (P1, app, one slice) — ✅ done (#665, 2026-10-21)

This batch takes up three of the six suggested tasks that were never started. It extends #587's `ProSalonScope.bookingCreated` pattern instead of patching screens one by one.

- ✅ **B1.1 Status changes from the booking detail reach « Ma journée » and « Accueil » (P1 · M · decision 8).** **Done in #665** — [app-pro-home-journal-fresh.md](design/app-pro-home-journal-fresh.md).
  - **What:** tap a booking, press « Accepter », go back: the card still says « En attente », and so do the home counts, until a pull. The detail writes one store and the journal reads another. Opening the detail is a plain push (`pro_journal_screen.dart:290`), and nothing announces a status change.
  - **How:**
    1. Red widget test: journal → « Accepter » → back, expecting « Confirmé » and the pending count down by one. Same for Rejeter, Terminé and Absent.
    2. Add `ProSalonScope.bookingChanged(appointment)`, called by the four status writes and by the journal's swipe actions.
    3. The journal updates the row at once, then reloads quietly. The home store re-fetches quietly; the client card reloads.
- ✅ **B1.2 « Accueil » error is a dead end, and pull-to-refresh asks nothing (P1 · M · decision 9).** **Done in #665** — [app-pro-home-journal-fresh.md](design/app-pro-home-journal-fresh.md).
  - **What:** a failed home load shows a bare sentence with no retry (`dashboard_screen.dart:180-189`). Once figures are loaded, pulling down returns early (`pro_dashboard_provider.dart:36-44`).
  - **How:** the house `EmptyState` with « Réessayer » inside `BrandRefresh`, as « Ma journée » does. Plus `refresh(salonId)`, which always asks the server: quietly when figures are on screen (kept on failure, with a message), as a normal load when there are none. The existing KNOWN-DEFECT test should turn red first.
- ✅ **B1.3 « Accueil » can show the previous salon's figures after a switch during loading (P2 · S · decision 10).** **Done in #665** — [app-pro-home-journal-fresh.md](design/app-pro-home-journal-fresh.md).
  - **What:** a late answer for salon A overwrites salon B's figures, revenue included, and later loads skip the server.
  - **How:** a sequence number on the main load (the journal store's pattern), bumped by the salon-switch reset. Outdated answers are dropped. A red unit test with a held answer comes first.

### Batch 2 — Lost answers to writes (P2, decision 11) — ✅ done (#666, 2026-10-21)

- ✅ **B2.1 A write the server saved but whose answer was lost (P2 · L).** **Done in #666** — [write-idempotency.md](design/write-idempotency.md); backend deployed 2026-10-21 (migration 0040), web live; the app's part ships with its next store build. Its keys are pruned by the daily maintenance cron (#667).
  - **What:**
    - Web booking: the server creates it, the answer is lost, and the client reads « La réservation a échoué ». A retry gets « Ce créneau vient d'être pris » for their own slot. With several free chairs and « Sans préférence », it can create a second booking.
    - The same class affects the Pro manual booking, client notes and invitations, where a retry adds a note twice or gets a 409.
    - #630 keeps such a write's 2xx, but its body is empty, so the deposit block is skipped.
  - **How (recommended):**
    - Backend: accept an `Idempotency-Key` on the creating POSTs (bookings, manual booking, notes, invitations). Store (account, route, key) with the first answer for 24 h; a replay returns that answer instead of creating again or answering 409.
    - Clients: one key per form submission (`crypto.randomUUID` / a uuid in the app), reused on every retry; the web proxy forwards the header.
    - Then the web booking flow re-asks after a lost answer and shows the deposit block.
  - **How (web only, if you prefer):** before saying it failed, look for your own appointment in « Mes rendez-vous ».
  - Needs a backend deploy.

### Batch 3 — The app says the right thing when something fails (P2) — ✅ done (#670, #671, 2026-10-21)

- ✅ **B3.1 No raw exception text and no bare « Erreur » (P2 · L).** **Done in #670** — [app-failure-messages.md](design/app-failure-messages.md) §10 (73 sites, not 67; a batch-1 defect found on the way).
  - **What:** 67 `_error = e.toString()` sites in 23 files. A captive-portal Wi-Fi (HTML with status 200) or a Cloudflare error page shows « TypeError… » or « FormatException… ». Several reads say only « Erreur ».
  - **How:** two shared helpers in `mobile/lib/services/api`.
    - A parse helper that turns `FormatException` / `TypeError` into `ApiResponse.error(« Une erreur est survenue. Réessayez. », code: 'unreadable')`. This generalises what #630 did in `listClients`.
    - An `errorFromResponse(res)` that reads `{error}` when the body is JSON and otherwise maps by status. It replaces each service's private `_errorFrom`.
    - Then migrate the 67 sites provider by provider, with a pin test forbidding `e.toString()` in providers.
- ✅ **B3.2 One offline sentence, everywhere (P3 · M).** **Done in #670** — [app-failure-messages.md](design/app-failure-messages.md) §10.
  - **What:** four app services (`api_pro_service`, `api_auth_service`, `api_appointment_service`, `api_provider_service`) say « Connexion au serveur impossible ». Everything else, and the web, says « Pas de connexion. Réessayez. ». Many web save failures say « L'enregistrement a échoué » offline, including the « Mon compte » contact number next to a name field that gets it right.
  - **How:**
    - App: one constant mirroring the web's `NO_CONNECTION_MESSAGE`, used in the four services and the 14 files that spell it out, plus a pin test against the old sentence.
    - Web: `writeFailureMessage(status, …)` on each save-failure sentence, and `loadFailure` moved to `lib/api` for the client pages.
- ✅ **B3.3 Notification read state can lag the server (P2 · S · decision 12).** **Done in #671** — [app-failure-messages.md](design/app-failure-messages.md) §11.
  - **What:** three cases in the client and Pro apps, which share the provider:
    - a reload during an in-flight « marquer comme lu » brings the row back unread;
    - a write whose answer was lost reverts a row the server did mark read;
    - after a successful retry, the failure snackbar stays up for its 6 s.
  - **How:** keep the ids with a write in flight, re-apply them after `load()` and again on success. On a lost answer, retry once (decision 12) or re-read the list instead of reverting blindly. Hide the failure snackbar when a new attempt starts (`AppSnackBar.showOn` returns its controller).

### Batch 4 — Web Pro is truthful on failure (P2, web) — ✅ done (#672, #673, 2026-10-21)

- ✅ **B4.1 Three failed reads show something false, and « Voir le justificatif » does nothing (P2 · M · decision 13).** **Done in #672** — [web-pro-truthful-failure.md](design/web-pro-truthful-failure.md) §1.1, §10: « Mettre en ligne » and « Voir le justificatif » were already fixed on main; the false « Choisissez votre offre » had moved to Équipe, now three-state.
  - **What:**
    - A draft salon whose offer couldn't be read is told « Choisissez votre offre » and can't go live.
    - A client card says « Aucune visite » beside a visit count of 5.
    - A failed « Charger plus » skips a page.
    - « Voir le justificatif » does nothing when its read fails.
  - **How:**
    - A three-state offer (live / missing / unknown), with one shared `isOfferLive`. « Unknown » says « Impossible de vérifier votre offre » with « Réessayer ».
    - A `visitsFailed` state, and a « Charger plus » that retries the same page.
    - A visible failure on the receipt link.
    - Reuse `loadFailureMessage` and the section-level `ErrorState`.
- ✅ **B4.2 « Calendrier » and « Liste » stay stale after a day-grid action (P2 · M)** *(suggested task)*. **Done in #673** — [web-pro-truthful-failure.md](design/web-pro-truthful-failure.md) §11 (also: « + Nouveau rendez-vous » from the Semaine now reloads the week).
  - **What:** after creating, moving, accepting or cancelling in the day view, the other two tabs keep the old data until a reload. `items` is set once at mount.
  - **How:** in `RendezVousClient.tsx`, a `loadItems()` with its own request id (the journal's dedupe), and one `refreshAfterChange()` passed to the grid and to the dialog's `onCreated`.
- ✅ **B4.3 Demo account and suspended salon get a generic error (P2 · S)** *(suggested task)*. **Done in #672** — [web-pro-truthful-failure.md](design/web-pro-truthful-failure.md) §10.
  - **What:** « Mettre en ligne » and the offer page say « …a échoué. Réessayez. » for `demo_account_locked`, so the reviewer retries forever.
  - **How:** `publishSalon` returns `error`. `GoLiveCard` and `AbonnementClient` map `demo_account_locked` to `DEMO_ACCOUNT_LOCKED_MESSAGE`, `provider_suspended` to the existing salon sentence, and status 0 to the offline sentence.
- ✅ **B4.4 Rejoin gate gaps (P2 · S · decision 14).** **Done in #673** — [web-pro-truthful-failure.md](design/web-pro-truthful-failure.md) §11 (the remembered salon is also forgotten at every sign-in: the browser cannot match its id).
  - **What:**
    - Accepting or declining on « Aujourd'hui » with a dead session shows a failure instead of going to sign-in.
    - A failed first `/me` shows the owner's full menu to any role. Nothing leaks, since the server refuses the pages, but the menu is wrong.
    - After a reload, the « accès retiré » line has no salon name.
  - **How:**
    - `onUnauthenticated` on both cards.
    - Start `awaitingProfile` true and use the existing `healProfile` loop on a failed first probe.
    - If you choose to: remember the acting salon `{id, name}` in `localStorage`, cleared at sign-out.
- ✅ **B4.5 Minor sections that vanish silently (P3 · S · decision 15).** **Done in #672** — [web-pro-truthful-failure.md](design/web-pro-truthful-failure.md) §10 (the seats bar is Équipe's offer, in B4.1). The seats bar, the stats tiles, the panel's client card and the « Nouveau rendez-vous » suggestions get a one-line « indisponible » note with « Réessayer », worded by `loadFailureMessage`.

### Batch 5 — Client web polish (P2–P3, web) — ✅ done (#674, #675, 2026-10-21)

- ✅ **B5.1 Sign-in blames the code for every failure (P2 · S).** **Done in #674** — [web-client-polish.md](design/web-client-polish.md) §10 (the send step and the salon sign-up too).
  - **What:** a server error, a rate limit or a broken answer says « Code incorrect ou expiré. » under the code field (`LoginOptions.tsx:159-174`). The Pro web sign-in has the same branch.
  - **How:** map by error code, as the app does.
    - `otp_invalid`, `otp_expired`, `otp_none` and `otp_locked` go under the field.
    - 429 gets a form-level « Trop de tentatives. Réessayez plus tard. ».
    - Everything else gets the form-level generic or offline sentence.
- ✅ **B5.2 The search ♥ (P2 · S).** **Done in #675** — [web-client-polish.md](design/web-client-polish.md) §11.
  - **What:** a failed session check sends a signed-in user to the login page, and a double click sends two requests.
  - **How:** track the probe as ok / anonymous / failed, and treat failed like the salon page's button, where the write's own 401 decides. Add a per-card in-flight set.
- ✅ **B5.3 Export edge cases (P3 · S).** **Done in #674** — [web-client-polish.md](design/web-client-polish.md) §10 (the app's two export screens too, Q3).
  - **What:** after an assembly error, the salon export blames three reads that succeeded. « Mes données » builds its document during render, so one broken favourite entry (`[null]`) hangs or crashes the page instead of refusing.
  - **How:**
    - A dedicated « Le fichier n'a pas pu être préparé. Réessayez. ».
    - Build the document inside `load()` in a try/catch.
    - Validate list elements in `getFavorites`: each must be an object with a string `id` and `name`, otherwise status 0.
- ✅ **B5.4 A favourite added or removed is not announced (P3 · M · decision 16).** **Done in #675** — [web-client-polish.md](design/web-client-polish.md) §11 (with « Annuler », and on « Mon compte » too). On success, a toast « Ajouté aux favoris » / « Retiré des favoris » on the search and salon pages. The live region is already mounted. The spec comes first.

### Batch 6 — Backend integrity (P2–P3, one or two deploys)

- ✅ **B6.1 `POST /appointments` accepts any role (P2 · S).** **Done in #676** — [backend-integrity-batch6.md](design/backend-integrity-batch6.md) §10 (deployed 2026-10-22).
  - **What:** a Pro or admin token can book through the client route. It is written as the client: an invisible, unreviewable booking that still notifies the salon. (Verified: `routes/appointments/index.dart` checks only that someone is signed in.)
  - **How:** POST answers 403 unless the role is `user`, copying `review.dart`. Add a route test, and the 403 in openapi.
- ✅ **B6.2 A dead invitation still creates an account (P2 · S).** **Done in #676** — §10 (deployed 2026-10-22).
  - **What:** opening an expired, revoked or misaddressed invitation creates the Pro account, then refuses. At the next sign-in, the server creates an empty salon for that account.
  - **How:** a read-only `TeamService.checkAcceptable` runs the four checks before `createMemberAccount`. If `accept` still fails in the race, remove the new account.
- ✅ **B6.3 A deleted owner's salon keeps their personal numbers (P2 · S · decision 17).** **Done in #677** — [backend-integrity-batch6.md](design/backend-integrity-batch6.md) §11 (deployed 2026-10-22). After the unpublish loop, blank the phone and address, and null the WhatsApp and Mobile Money fields. Keep the name and the history, and state it in the privacy policy.
- ✅ **B6.4 The demo reset leaves a reviewer's KYC behind (P2 · M · decision 18).** **Done in #677** — §11 (deployed 2026-10-22). At the weekly reset, delete the demo account's `kyc/<accountId>/` objects (the deletion loop) and reset its status, via a new `resetKyc`.
- ✅ **B6.5 One deposit range, and a removed operator must not block a save (P2 · M · decision 19).** **Done in #677** — §11 (an operator outside the catalogue is not judged with deposits off — and not kept, T57; deployed 2026-10-22).
  - **What:** app 5–80 %, web 1–100 %, server 0–100 %. A value saved on one surface can't be shown on another. An operator removed from the catalogue blocks every save, even with deposits off.
  - **How:** the server enforces the chosen range, and both forms use the same bounds. With deposits off, skip the catalogue check. With deposits on, answer `operator_unavailable` so the fault shows under the operator field.
- ✅ **B6.6 Salons can't report reviews of their own salon (P2 · M · decision 20).** **Done in #678** — [backend-integrity-batch6.md](design/backend-integrity-batch6.md) §12 (the key stays `(review_id, reporter_user_id)`, since salon and client ids never collide; a sibling `reportBySalon` holds the « a review of this salon » check; deployed 2026-10-22).
  - **What:** App Store 1.2 expects reporting on user content, and the Pro « Avis » screen has none.
  - **How:**
    - Server: `POST /me/provider/reviews/{id}/report`, behind the same membership gate. It reuses `ModerationService.report` with the reporter recorded as the salon, and a migration adds `reporter_kind`.
    - Clients: a « Signaler » button in the Pro « Avis » on app and web.
- ✅ **B6.7 Revoke the Apple token when an account is deleted (P2 · L).** **Done in #679** — [backend-integrity-batch6.md](design/backend-integrity-batch6.md) §13, §14 (built inactive until the `.p8` key exists — the owner's steps are in DEPLOYMENT.md, Phase C; a token is kept only if Apple's answer names the same `sub`; deployed 2026-10-22).
  - **What:** under 5.1.1(v), MyWeli stays under « Apps using Apple ID » after deletion.
  - **How:**
    1. You create a Sign in with Apple `.p8` key and store it in Secret Manager.
    2. The clients send `authorizationCode` at sign-in.
    3. The server exchanges it for a refresh token, stored per account (migration), and revokes it on deletion.
- ✅ **B6.8 Guards with no live trigger (P3 · S each).** **Done in #676** — §10 (deployed 2026-10-22).
  - `ensureOwner` should behave the same in Postgres and in memory (deny by default).
  - `ensureSalon` should refuse to write an owner row on a salon owned by someone else (T72).
  - The team API should refuse to change the role of a revoked member (409), next to B7.5.
- ✅ **B6.9 Know when the demo identity is lost (P3 · S · decision 22).** **Done in #676** — §10; the server half deployed 2026-10-22; the alert **created on GCP 2026-10-22** (`alertPolicies/10667515608135534511`, to « Owner email »), and added to the list 93/95 read in #681. Put the refusal reason in the cron response, and add a log alert on `demo_reset REFUSED`, copying `96-rebuild-hook-alert.sh`.
- ✅ **B6.10 A Postgres end-to-end test for client account deletion (P3 · M).** **Done in #676** — §10. A victim plus a bystander, all their rows, run through the real repositories, like the Pro one. Tests only.

### Batch 7 — Pro app UI, accessibility and parity (P2–P3, app)

- ✅ **B7.1 The « Propriétaire » chip is about 3:1 (P2 · S).** **Done in #683** — [pro-app-batch7.md](design/pro-app-batch7.md) §10 (measured 2.79:1; ink now). Draw the label in `textPrimary` on the gold tint, as the web does. Add the chip to the contrast test, regenerate the team goldens on Linux, and close SYSTEM §21 row 28.
- ✅ **B7.2 Mid-word breaks at 200 % text (P2 · S).** **Done in #683** — §10 (an `OverflowBar` for the hours; a dialog's icon goes above a title it would break; every dialog title swept).
  - **What:** « Mard/i » in the pause rows; « Abandonne/r les modifi/cations ? » in a dialog title.
  - **How:** use the measured-fit idiom in `WeeklyHoursEditor`, shorten the title to « Abandonner ? », and add weekday names and dialog titles to `expectNoMidWordBreak`.
- ✅ **B7.3 The deletion dialog tells members « Votre salon sera retiré » (P2 · S).** **Done in #682** — [pro-app-batch7.md](design/pro-app-batch7.md) §9 (the sentence follows « the account owns a salon », as the server removes — app and web, Q5). Only owners see that sentence. Members get « Cette action est définitive. Votre compte MyWeli Pro sera supprimé. », with the web picking the same way.
- ✅ **B7.4 Empty-day layout (P2 · S · decision 25).** **Done in #683** — §10 (`fabClearance`; the Liste's empty day is now pull-to-refresh too).
  - **What:** the empty « Calendrier » day is hand-rolled and hides under the FAB at large text. « Ma journée » offers the same action twice.
  - **How:** the shared `EmptyState`, a 96 dp bottom inset, one control in « Ma journée », layout tests at 200 % on a 360 dp screen, and close SYSTEM §21 rows 80–81.
- ✅ **B7.5 « Changer le rôle » on a revoked member (P3 · S).** **Done in #682** — §9. Revoked rows become non-tappable, like the web, with a widget test.
- ✅ **B7.6 Pending invitations on « Accueil » (P2 · M · decision 23).** **Done in #684** — [pro-app-batch7.md](design/pro-app-batch7.md) §11 (the card on « Accueil » and the staff « Journée »; a join reloads « Mes salons »; **also fixed:** offline, every invitation screen said « Invitation impossible à accepter. », not « Pas de connexion »). Reuse `ProTeamProvider.loadMyInvitations()` and `InvitationCard`, on « Accueil » and on the staff « Journée ». A UX spec comes first.
- ✅ **B7.7 The « Acompte & annulation » step is ticked for every salon (P2 · S · decision 24).** **Done in #682** — §9 (app and web; « Facultatif »). It counts as done only once a choice is saved: a stored percentage above 0, or deposits on. Otherwise « facultatif ».
- ✅ **B7.8 The app's salon export has no earnings (P2 · S).** **Done in #684** — §11 (« Revenus » in the summary; a 200 without its transactions refuses the export). A sixth read through `_read`, `ProExportSection.earnings`, the web's exact shape, and a strict `transactions` list per #630's rule.
- ✅ **B7.9 Orientation (P2 · S · decision 26).** **Done in #682** — §9 (checked on an Android 16 emulator: portrait holds on a phone; tablet metrics rotate, as Android 16 decides, and stay usable). Add `android:screenOrientation="portrait"` on `MainActivity`, plus one tablet-emulator smoke run. On Android 16+, orientation locks are ignored on large screens.
- ✅ **B7.10 Long values at large text and large amounts (P3 · M).** **Done in #683** — §10 (four sites broke and were fixed; the total steps down a size, the owner's decision). Add 7-digit amounts to the fixtures, fix the five sites with the measured-fit idiom, and turn `reportGluedTokenBreaks` into an assertion.
- ✅ **B7.11 Call buttons do nothing without a dialer (P3 · S).** **Done in #682** — §9. **Worse than listed:** two buttons asked `canLaunchUrl(tel:)`, which answers « no » on Android 11+ for an undeclared scheme — they most likely did nothing on most phones (device check added to B0.2). `callPhone(context, number)` with a snackbar, plus a pin test against raw `launchUrl`.
- ✅ **B7.12 Two separate links in the consent sentence for screen readers (P3 · S).** **Done in #683** — §10 (proved as is; nothing to change). A test, and `explicitChildNodes` if it fails.
- ✅ **B7.13 Admin console segments have no visible boundary (P3 · S).** **Done in #683** — §10. Use one `AdminSegmentedControl`, with a token border on inactive segments.
- ✅ **B7.14 After a failed fallback to the default salon, per-salon stores keep the old salon's data (P3 · S).** **Done in #682** — §9 (the reset is at the two fallback sites: inside `_clearSalonSelection` it would have emptied the rejoin gate's cards). Call `ProSalonScope.resetAll()` inside `_clearSalonSelection()`.

### Batch 8 — Product questions (P3, need your answers first)

- ✅ **B8.1 Undo for destructive server actions (L · decision 27).** **Decided: keep confirm-only** — [product-questions-batch8.md](design/product-questions-batch8.md) Q1; nothing to build. If wanted: about 10 s « pending » states on the server for cancel and revoke, and a grace period for deletion, stated in the policy.
- ✅ **B8.2 An editable Pro account phone (M · decision 28).** **Decided: nothing now** (Q2) — the number stopped being an identity in migration 0023 and is no longer unique, so there is no 409 to give; it waits for phone sign-in's return. `PATCH /me/provider/account/phone`, with 409 on a number taken by another account and an audit with ids only. Plus an SMS code if it is still a sign-in identity.
- ✅ **B8.3 The « Profil » salon card offline (S · decision 29).** **Done in #686** — [product-questions-batch8.md](design/product-questions-batch8.md) §10 (`SalonFacts` in the session; offline at cold start the card shows the salon; another salon's copy never shows). Persist a slim copy of the acting salon, cleared at logout.
- ✅ **B8.4 V2 analytics wording (S · decision 30).** **Done in #686** — « Total réalisé » (Q4), on a new LAUNCH §1.5 list for turning `futureProviderFeatures` on, and on the screen. Nothing now. Add the label to the checklist for turning V2 on.
- ✅ **B8.5 Dormant phone sign-in (S · decision 31).** **Done in #685** — removed (Q5) — [product-questions-batch8.md](design/product-questions-batch8.md) §9. **Worse than listed:** the server route opened with the CLIENTS' `AUTH_METHODS` switch, and took the first account carrying a number that is no longer unique (T80). Server, contract, web and app. Rebuilt on purpose when SMS returns, with B8.2.
  - **What:** an unrouted screen, and a sign-in that skips the membership load.
  - **How:** decide together with the return of SMS and WhatsApp (company registration).
- ✅ **B8.6 Pro account deletion is only partly atomic (L · decision 32).** **Done in #685** — §9 (the retry test, Postgres and in memory; the « réessayez » half already held on both clients). *Recommended:* accept, add a test that a failed identity delete followed by a retry ends fully deleted, and say « réessayez » after a 5xx.

### Batch 9 — Hygiene, tooling and tests (P3, do when touching the area)

- ✅ **B9.1 Stale release docs and statuses (M).** **Done in #688** — [hygiene-batch9.md](design/hygiene-batch9.md) §9: 33 roadmap entries (20 turn 🟢, 13 wait for 0.0.2), 8 specs and 5 index rows, LAUNCH and app-store-forms. What only App Store Connect can confirm waits for batch 10.
  - **What:** `LAUNCH.md` and `app-store-forms.md` describe states that have passed. Five specs and several 2026-10-13…16 roadmap entries still read 🟡 or « non fusionné ».
  - **How:** one docs PR, after the App Store Connect read-back (batch 10).
- ✅ **B9.2 iOS release tooling (S).** **Done in #697** — [hygiene-batch9.md](design/hygiene-batch9.md) §13. `release_build.sh` refuses a dirty tree, or a HEAD that is not a freshly fetched `origin/main`, before reading any secret; for iOS it also needs `ASC_KEY_ID` and `ASC_ISSUER_ID`. It parks the archive as `Runner-<flavour>-<build>.xcarchive` and validates the IPA (a refusal stops everything). It then prints the symbols command (with the dSYMs), `set-commits` and the upload command. Tested by running the real script in a throwaway repository.
  - ✅ **B9.3** **Done in #697**: `setup_flavours.rb` updates its phase and schemes in place, so a run on the committed project changes nothing. Proven on a copy, run by the macOS iOS workflow.
- ✅ **B9.4 Observability follow-ups (M · decision 34).** **Done in #697, applied and verified on 2026-10-25** — both checks validate the certificate and still pass, the two alerts are live, and their runbooks match the repo (§13).
  - `infra/gcp/81-uptime-tls-latency.sh` switches both checks to `--validate-ssl=true` in place and adds two alerts: a certificate with less than 14 days left, and a mean probe latency above 3 s for 15 min. `80-uptime-checks.sh` creates the checks with validation now.
  - Mobile suspect commits: `release_build.sh` prints `set-commits` for each store build (needs Sentry's GitHub integration — batch 10).
  - Error-rate thresholds stay deferred until there is real traffic (decision 34, observability §8.2).
- ✅ **B9.5 FlutterFire Dependabot group (S).** **Already done** — #632–#636 merged on 2026-10-20 and the `firebase` group is in `dependabot.yml`. **To watch:** the next weekly run opens ONE Firebase PR. Merge or close the five open Dependabot PRs (#632–#636; equatable 3.0.0 is a major bump). Then check that the next run opens ONE Firebase PR.
- ✅ **B9.6 Mock and stub fidelity (M · decision 35).** **Done in #689** — [hygiene-batch9.md](design/hygiene-batch9.md) §10. The invitation caps are the server's two buckets per UTC day, aliases included. A new mock salon is the server's: empty, at 0 %. The catalogue is one store, scoped to the acting salon with the server's `forbidden` and `not_found`; so are the artist and member writes. A counter replaces the 12 clock-built ids (SYSTEM §21 row 43). No mark-read switch (decision 35).
- ✅ **B9.7 Form-validation tests (M).** **Done in #690** — [hygiene-batch9.md](design/hygiene-batch9.md) §11. `_TagSheet` is on `FieldErrors`. Its limit is said for a chip too, a failed save is shown, and the sheet scrolls (it overflowed at ten tags). The notes, admin and Pro sign-ins, staff form and service form have their « under the field » tests: 15 of 17 screens, the last two unrouted until SMS. Also: the three e-mail sign-ins now say a refused code or e-mail under its field, as the web does (SYSTEM §14, §21 row 32).
- ✅ **B9.8 Shared components (L).** `AppCard`, `AppChip` and `AppAsyncView` as SYSTEM §11.3 specifies. `AppAsyncView` makes a forgotten state or a raw error impossible, and pairs with B3.1. **Three PRs (Q12).** **F1 in #699** — [hygiene-batch9.md](design/hygiene-batch9.md) §14, SYSTEM §12.1: `AppAsyncView`, the one load error « Chargement impossible » (Q9), still skeletons on cards (Q11) and `AppCard`; 44 of the 48 spinners moved (39 files), four named ones left, one pin on `lib/`. The move found ten screens that said something false, each fixed at its provider: a detail showing the previous entity (and its actions), lists saying « aucun » for a failed read, a shared `isLoading` or `error`, defaults shown as answers. **F2 in #700** — §15, SYSTEM §3.1, §8, §11.3: every card is `AppCard` (27 Material `Card`s, 31 drawn by hand), no shadow, no border unless a control, `spacingM`; one semantics container, a chosen card said (Q13); the docked « Total » keeps its shadow (Q14). It found six silent tappable cards and six pages carrying cards on `surface`. **F3 in #702** — §16, SYSTEM §11.3: every chip is `AppChip` — `.choice` (Material's `ChoiceChip` under `chipTheme`, the ✓ on a chosen chip in the icon's place, Q16; the booking's slots filled, Q17), `.tag`, `.action`, and `.status`, one tinted pill for every status and badge (Q18), each tone ≥ 4.5:1, the appointment statuses on the B7 kinds (confirmed = ok, completed = neutral; the journal keeps its own). It found the Pro detail's status at 1.02:1, the home tile's « En attente » at 1.6:1, the search filters unannounced, statuses drawn three ways, and a Manager pill the same grey as a Collaborateur's (1.09:1 — the strong tone now carries the brand line).
- **B9.9 The R6 salon-id pin's blind spot (L · decision 33).** A positional account id isn't seen by the pin. The real fix is a `SalonId` extension type. Nothing on main triggers it.
- ✅ **B9.10 One home for fallback copy (S).** **Done in #691** — [hygiene-batch9.md](design/hygiene-batch9.md) §12. There were five forms and an empty string. Now there are words per place, the same in the app and on the web: « Salon » for a title, « le salon » in a client's sentence, « votre salon » in the Pro session's, and « Votre planning ». They live in SYSTEM §17.2, with one constant file and one pin per surface. The calendar, the Pro titles, invitations and « Mes salons » are fixed too.
- **B9.12 Drop the orphaned `provider_otp_codes` table (S — B8.5 deployed 2026-10-22, image `eca4db6`).** B8.5 (#685) stopped every read and write of it, but an older image still deletes from it on each Pro account deletion — dropping it in the same deploy would turn every deletion into a 500 on a rollback. Drop it once no deployed image reads it, with a `// rollback-unsafe:` line (LAUNCH §1.4's contract step).
- ✅ **B9.11 Web list reads that still turn a missing list into `[]` (S, when touched).** **Done in #691** — §12. The eight authed reads and the slots now require their list (status 0). Public pages throw where the build fails closed: ISR keeps the last good page, and a production build fails rather than publish an empty site. Previews still degrade. `getProviderBySlug` no longer turns a 5xx into a 404, and the locality tree follows the same rule. The contract now requires `items`.

### Batch 10 — Only you can check

- **App Store Connect for 0.0.1:**
  - the privacy label, content rights, price and availability (the API shows `CANNOT_SELL` in 175 countries), contact details;
  - whether the amended review notes are in place.

  A read-back unblocks B9.1.
- **`support@myweli.com` reaches a person.** It is the only contact on `/support`, which both store listings use.
- **Sentry's GitHub integration knows `Zaslons/myweli`** (B9.4). Without it, the `set-commits` command that `release_build.sh` prints is refused, and mobile issues get no suspect commits. In Sentry: Settings, then Integrations, then GitHub.
- **App Preview:** whether Apple applied the 25 s poster frame, and how review and the store page treat the preview.
- **Walk the clients list in production** with a Pro session (`pageSize=1`, pages 1…N): all ids distinct and N equal to `total`. This observes #618's tie-breaker, which the deploy check could not.
- **Exercise the T72 fix** (decision 21): register a throwaway Pro account with a foreign `providerId`, check it gets a new draft salon, then delete the account.
- **The demo salon:**
  - the text nits and snapshot re-save after Apple's decision (decision 36);
  - photo sources and licences (decision 37);
  - the « Essai Fix » test booking needs nothing, because the weekly reset around 2026-10-21 removes it.

---

## 4. Checked and not on this list

- **Already fixed:**
  - the search ♥ has component tests (#624);
  - the rate limiter's table is pruned daily;
  - Cloudflare does not challenge the app (measured on 2026-10-07; only the checklist box was never ticked).
- **Not defects:**
  - the web has no client-side salon resolver that could drift from #627's rule;
  - the journal store reloading in the background after a booking is intended.
- **Closed by later PRs:** many recorded follow-ups were fixed by a PR merged later the same week, for example #600, #617–#630 and #616. Their specs say so.
- **Out of scope by decision**, recorded in SYSTEM §21–§22, so not backlog:
  - platform limits;
  - dark mode, the brand font and tablet layouts;
  - V2/V3 screens behind their flag;
  - string externalisation (V3).
