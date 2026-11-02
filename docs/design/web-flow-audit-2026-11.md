# Does the website follow the apps' user flows? — audit, 2026-11-02

| | |
|---|---|
| **Status** | Audit. Fixes tracked in [BACKLOG](../BACKLOG.md) Batch 12 |
| **Owner** | Sadreddine Daher |
| **Asked by** | The owner, while choosing the site's look ([web-swiss-direction.md](web-swiss-direction.md)) |
| **Method** | Two independent read-throughs of the code on `main` (`cb5ca7c9`), consumer and pro, each difference cited on both sides. Earlier audits ([web-parity-audit.md](web-parity-audit.md), [parity-audit-web-pro-2026-10.md](parity-audit-web-pro-2026-10.md)) were used only to learn what was deliberate |
| **What it is not** | Nothing was run on a device. **« Checked »** below means I re-read that code myself after the audit; the others rest on the audit's citations |

## The answer

**The core flows match; the moments after them often do not.** Booking, sign-in, the agenda, the catalogue and account deletion follow the same steps as the apps, or differ for a good reason of medium: a split map, a desktop agenda, web-only sign-up for salons (App Store 3.1.1). The gaps sit after the booking, for returning clients, and in a few sentences that say something untrue.

The gaps run both ways: some are the apps behind the web.

| Flow | Verdict |
|---|---|
| Client: home | Adapted for search engines; the returning client's view is missing (C5) |
| Client: search, map | Same sort and filters, split map adapted; C6 |
| Client: salon page | Different order, adapted; **C3** |
| Client: booking | Same hub and steps; **C2**, C8, C9 |
| Client: sign-in | Same, including return to where you were |
| Client: my bookings | Reschedule and review same; **C1**, C4, C7 |
| Client: account | Export, deletion, feed same; C10 |
| Pro: sign-in to go-live | Same 8 steps; sign-up on the web on purpose; **P1**, **P2**, P3, P4 |
| Pro: home, journal | Desktop-adapted, recorded in specs |
| Pro: agenda | Same actions; the web adds a week view and client search |
| Pro: catalogue, team, hours | Same; one « Enregistrer » per page on the web |
| Pro: clients to profile | Same; P5 |
| Pro: subscription to deletion | Deliberately different: the app reads, the web sells |

## Says something untrue (fix first)

| # | Gap | Impact | Evidence | |
|---|---|---|---|---|
| **P1** | The web says the trial starts at go-live, and Équipe sends a draft salon to « Choisissez votre offre ». Choosing creates the subscription with the clock already running; go-live then leaves it alone | **A salon loses free months before it opens** | `subscription-plans.ts:86-87`, `EquipeClient.tsx:226`, `salon_subscription_service.dart:155-160`, `:86` | Checked |
| **C1** | Cancelling with a deposit: the app says the deposit will or won't be refunded, with the amount. The web says « peut ne pas être remboursé » | A client decides about money without the answer the server already has | `appointment_detail_screen.dart:147-155`, `AppointmentDetailClient.tsx:505-507` | Checked |
| **C2** | After booking: « Vous recevrez une notification », but a client on the web alone gets a feed row, and no e-mail or push while WhatsApp and SMS are off. And there is no link to the booking: the only button is the store link, which renders nothing today | A dead end at the most important moment, and a promise that does not hold | `BookingFlow.tsx:439-456`, `booking_notifier.dart:62-88`, `OpenInAppButton.tsx` | Checked |
| **P2** | « Créez votre salon dans l'app MyWeli Pro » on `/pro/connexion`, while the app sends sign-ups to the web. Dormant: it appears the day store URLs are set, and that link goes to the **client** app (the comment there says so) | A loop for new salons, on launch day | `app/pro/connexion/page.tsx:33-44`, `pro_login_screen.dart:465-470` | Checked |

## Web behind the apps

| # | Gap | Evidence | |
|---|---|---|---|
| **C3** | **The salon's description is never shown.** The app shows it; the web only sends it to search engines | `provider_detail_screen.dart:1144-1156`, absent from `ProviderView.tsx` | Checked |
| **C4** | « À venir » sorts by status only, so a past pending or confirmed booking stays there | `web/lib/account/appointments.ts`, `visit_history.dart:15` | Status rule checked |
| C5 | Returning client's home: no recent bookings, favourites or remembered commune. The June audit marked the favourites strip as deliberate for search; worth asking again for signed-in visitors | `home_screen.dart:48,251,351`, `app/page.tsx` | |
| C6 | A recognised service and commune land on a page with no sort, availability filter, map or hearts. The routing was recorded; losing those was not | `discovery.ts:47-53`, `TaxonomyLandingView.tsx`, `RechercheClient.tsx:243-265` | |
| C7 | Past visits: no summary, month groups or inline rebook | `my_bookings_screen.dart:193-248`, `AccountClient.tsx:454` | |
| C8 | A signed-in web booker never sees the consent line | `booking_confirmation_screen.dart:476`, `LoginOptions.tsx:281` | |
| C9 | Deposit details: no percentage, balance, « Copier » or « Acompte confirmé » state | `booking_confirmation_screen.dart:428-453`, `DepositProof.tsx:94-98` | |
| C10 | Profile: no avatar or e-mail editing | `edit_profile_screen.dart:81-123`, `AccountClient.tsx:256,349` | |
| P3 | Invitees: logging in at the wrong address offers « Créer mon compte » with no hint about the invitation, so an employee may create a salon. No « Retour » on invitations | `ProLoginOptions.tsx:163,339`, `failure_messages.dart:24` | |
| P4 | « Configurer mon profil » opens the plain profile, not the checklist; the checklist's « Équipe » lands on the Services tab | `AujourdhuiClient.tsx:259`, `onboarding.ts:113`, `dashboard_screen.dart:285` | |
| P5 | Revenus opens on « Tout », the app on « Aujourd'hui » | `RevenusClient.tsx:34`, `earnings_screen.dart:48` | |

## Apps behind the web

| # | Gap | Evidence | |
|---|---|---|---|
| **A1** | **The client app's search bar does not search.** It opens the salon list, which has no text field; no screen passes `searchQuery`, though the API takes it | `search_bar.dart`, `home_screen.dart:122`, `provider_list_screen.dart` | Checked |
| **A2** | Client app: no nail or massage category chips; only Tous, Barbier, Salon, Spa | `category_chips.dart:12-17`, `web/lib/landing.ts:15-19` | Checked |
| **A3** | Pro app: long-press « Non présenté » has no confirmation and no check that the appointment has started. The web guards both. False absences land on client records | `pro_journal_screen.dart:455-458`, `JournalPanel.tsx:295` | Action checked |
| A4 | Client app: no-shows appear in no tab | `appointment_provider.dart:80-103` | |
| A5 | Pro app: deactivated services are invisible and cannot be reactivated; the toggle exists only on the web | `service_list_screen.dart:116`, `CatalogueClient.tsx:436` | |
| A6 | Pro app, staff: no way to the notification centre except Accueil's bell; « Nouveau » shows and the server refuses | `staff_home_screen.dart:41`, `appointment_list_screen.dart:154` | |
| A7 | Pro app: reviews stop at 50; the web has « Charger plus » | `pro_reviews_provider.dart:71`, `AvisClient.tsx:218` | |

## Not established

- Production settings: store URLs, Apple and Google client IDs, whether WhatsApp or SMS is on. Notes say off; not read here. They decide P2 and how serious C2 is.
- Auto-completion of past bookings: none found in `backend/lib/src`, but the search was not exhaustive. If one exists, C4 shrinks to sort order.
- Whether the server refuses an inactive service on an app manual booking (A5).
- Whether an open web agenda shows a new booking without a reload: the badge polls and the grid does not re-read; the app's behaviour was not established.
- Anything at runtime, on any device.
