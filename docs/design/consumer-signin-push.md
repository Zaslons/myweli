# A sign-in you can leave, and push you can turn on later (A3) — design spec

| | |
|---|---|
| **Status** | **Approved by the owner on 2026-11-24** (« Approve as recommended »: the ten recommendations of §11, BACKLOG decisions 204–213). An independent reader checked it once against the code (14 findings; each re-read in the code, then folded in, §12). **Built on 2026-11-24** in A3 (branch `feat/consumer-signin-push`; the app, with MyWeli Pro's card). It reaches clients with the next consumer build, and salons with the next Pro build. One change from the approved text, recorded in §2.2: a sign-out never waits for a registration. A3 merged as `aa3fe341` (#854). **A3w, the website's two hearts, built on 2026-11-24** (branch `feat/web-heart-after-signin`, §14); its merge is a production deploy of `myweli.com`, on the owner's word. |
| **Owner** | Sadreddine |
| **Last updated** | 2026-11-24 |
| **PRD ref / phase** | FR-BOOK-008 (the sign-in gate and `returnTo`), FR-NOTIF-001 (push), FR-NOTIF-004 (preferences), FR-FAV-001 (favourites) · V1 · BACKLOG B0.10 (decision 160, Track A) |
| **Module** | `client-app` and `notifications` (MODULES §2): the consumer app; MyWeli Pro only if §11 Q9 says so; the website only if §11 Q2 says so |
| **ROADMAP entry** | [2026-11-24-consumer-signin-push-spec.md](../roadmap/entries/2026-11-24-consumer-signin-push-spec.md) |
| **Skills checked** | myweli-dev-guardrails ✓ · myweli-web-guardrails ✓ (parity read; no web change proposed outside Q2) · myweli-verification-guardrails ✓ |
| **Read at** | `main` `78a6b1e0`. Every « today » below was read in the code on 2026-11-24, with its file and line. |
| **Related** | [consumer-app-release-audit.md](consumer-app-release-audit.md) §7 A3, gaps 10 and 17, §2.3 (FR-BOOK-008), §2.6 · [push-notifications-app.md](push-notifications-app.md) (the ask-once rule this spec replaces for the client) · [notification-preferences.md](notification-preferences.md) · [consumer-account-scope.md](consumer-account-scope.md) (the session that ends; decision Q1 = a, refined by §11 Q10) · [app-auth-social.md](app-auth-social.md) (the mandatory phone step) · [SYSTEM.md](SYSTEM.md) §12 (auth-gated and permission-denied states), §13, §15, §17 |

---

## 1. Goal & scope

**Goal.** Two dead ends in MyWeli (client) close:

- **A guest who meets the sign-in screen can leave it** and land exactly where they were (audit gap 10, FR-BOOK-008). Today a guest who taps a heart is taken to a screen with no way back. On iOS there is no system back at all, so the only exits are signing in or killing the app. A store reviewer who taps a heart is stuck.
- **« Plus tard » on the push sheet no longer ends push for good** (audit gap 17). Today it does: the app never asks again. On an iPhone that never saw the system prompt, Settings has no switch to turn on, and the app's own Préférences say nothing. Reminders reach clients by push only (SMS and WhatsApp are off until the company is registered), so that client never hears of their appointment.

Both say only what is true (A1's rule), and both keep the client's intent: a heart tapped before signing in is a heart applied after, if §11 Q2 says so.

**In scope (one app PR, A3):**

| # | Change | Where |
|---|---|---|
| 2.1 | One rule: the sign-in opens **over** the screen the person is on, and closing it returns there | every way into sign-in |
| 2.2 | The sign-in screen: « Fermer », back on each step, a line saying why it opened | `login_screen.dart` |
| 2.3 | The account's screens load again when an account signs in | the account's stores and screens |
| 2.4 | Each way in, and what happens after sign-in and after « Fermer » | 13 call sites; the booking's gate moves to the hub |
| 2.5 | « Rendez-vous » and « Actu » draw a signed-out page instead of redirecting or failing | two tabs |
| 2.6 | Signing out and deleting the account land on Accueil | Profil |
| 2.7 | A session that ended: the sign-in opens over the screen, and the notice finally knows which screen that is | `session_ended_notice.dart` |
| 2.8 | A heart tapped before signing in is applied after (Q2) | the three hearts |
| 2.9 | Préférences shows this phone's notification state, with « Activer » when it was never asked | `notification_preferences_screen.dart` |
| 2.10 | « Plus tard » means later: the sheet comes back after a later booking, within limits | `push_registration.dart` |
| 2.11 | Préférences says what is true: the push switch's sentence, and the line under the card | Préférences |

**Out of scope, each stated so it is not lost:**

- **The website, for gap 10.** `/connexion` keeps the site header, so it can always be left, and it returns with `router.replace(returnTo)` (`web/components/auth/ConnexionClient.tsx:9-12`). Booking signs in inside the flow, keeping the choice (`web/components/booking/BookingFlow.tsx:585`). Only Q2 would touch the website.
- **Asking for the phone number at booking.** The website asks for it in the booking flow (`BookingFlow.tsx:74-78`, `:427-429`). The app relies on the sign-in's phone step alone. That only matters if Q3 is answered « keep the session ».
- **A session restored without a phone.** Closing the app during the phone step skips it, and nothing asks again (audit §2.8 †). Unchanged here; it is the same follow-up as the line above.
- **A hint on the appointment detail** (« Activez les notifications pour recevoir le rappel »): a follow-up once §2.9 exists.
- **A reinstall with upcoming bookings.** The sheet waits for the next booking (§2.10). Offering it on the first launch that finds an upcoming booking is a follow-up.
- **Revoking the refresh token on sign-out** (audit §2.8 †): a backend change, not A3.
- **MyWeli Pro's sign-in**, which requires an account by design. Pro's push ask on the dashboard stays as it is; only Q9 touches Pro.

**Fits the architecture.** No new service, no API change. The navigation rule lives in one helper; the reload rule in the account's existing coordinator (`AccountScope`); the push rule is a pure function beside `PushRegistration`; the two guest pages reuse `EmptyState`; the notification card takes `PushBlockedBanner`'s shape.

---

## 2. UX & flows

### Today

**The sign-in replaces the screen the person was on.** Every way into it uses `go`, which replaces the route stack:

| # | Where | Today | File |
|---|---|---|---|
| 1 | Salon page, heart | snackbar, then `go('/login?returnTo=<here>')` | `provider_detail_screen.dart:293-302` |
| 2 | Salon card, heart (list layout) | the same | `provider_card.dart:218-230` |
| 3 | Salon card, heart (the other layout) | the same | `provider_card.dart:403-415` |
| 4 | Map, salon sheet, heart | closes the sheet, then `go('/login?returnTo=/carte')` | `map_screen.dart:277-283` |
| 5 | Booking confirmation, as a guest | after the first frame, a snackbar and `go('/login?returnTo=<the confirmation's URL>')` | `booking_confirmation_screen.dart:68-98` |
| 6 | « Rendez-vous » tab, as a guest | after the first frame, a snackbar and `go('/login?returnTo=/bookings')` | `my_bookings_screen.dart:43-56` |
| 7 | Profil, « Modifier le profil », as a guest | `go('/login?returnTo=/profile')` | `profile_screen.dart:73-79` |
| 8 | Profil, « Se connecter » | `go('/login?returnTo=/profile')` | `profile_screen.dart:170-177` |
| 9 | Profil, after « Se déconnecter » | `go('/login')` | `profile_screen.dart:162-165` |
| 10 | Profil, after the account is deleted | `go('/login')`, then « Compte supprimé » | `profile_screen.dart:196-198` |
| 11 | Modifier le profil, signed-out state | `go('/login?returnTo=/profile/edit')` | `edit_profile_screen.dart:172-175` |
| 12 | A session that ended, on an account screen | `router.go('/login?returnTo=<here>')` | `session_ended_notice.dart:76-79` |
| 13 | A session that ended, elsewhere: the snackbar's « Se connecter » | `router.go('/login?returnTo=<here>')` | `session_ended_notice.dart:81-89` |

No other way into the sign-in exists on the client side; the phone and OTP screens are dormant (audit §2.8).

**The sign-in screen has no way out.** Its `AppBar` has a title and no leading button (`login_screen.dart:219`); success always `go`es (`:85`, `_finish`). With the stack replaced, Android's back leaves the app and iOS has nothing.

**`go` also hides a reload the screens never do.** Accueil, the salon page and the map load the account's favourites and bookings once, when they open, and only if someone is signed in (`home_screen.dart:50-65`, `provider_detail_screen.dart:152-162`, `map_screen.dart:72-77`). Nothing loads them when someone signs in later. Today it does not show, because `go(returnTo)` builds every screen again. Any design that returns to a screen still open must load them (§2.3).

**The session-ended notice reads the wrong screen.** It asks the router where the person is (`session_ended_notice.dart:72`, `routerDelegate.currentConfiguration.uri`). In `go_router` 17.5 that address ignores every screen opened with `push` (`match.dart:530-533`: it « only reflects RouteMatches that are not ImperativeRouteMatch »). Every account screen is opened with `push`:
- the « Rendez-vous » and « Actu » tabs (`consumer_bottom_nav.dart:57-61`);
- a booking's detail (`my_bookings_screen.dart:188`, `:244`);
- Profil's children (`profile_screen.dart:80`, `:99`, `:132`);
- the confirmation (`booking_hub_screen.dart:403-405`).

So the notice usually believes the person is on Accueil, and its account-screen branch rarely fires. Its tests build the router at its first location only (`test/widget/account_switch_test.dart:293-316`), so no pushed screen was ever tested.

**The « Actu » tab fails for a guest.** The service answers « Non connecté » without asking the server (`api_notification_service.dart:47-48`). The screen shows a load error with « Réessayer », a retry that cannot succeed (SYSTEM §12: « the way out is a retry only when retrying can succeed »).

**Push is asked once, after the first booking, and « Plus tard » ends it.**
- `maybePromptOnce` sets the « asked » flag as soon as the sheet answers, before the system is asked or « Plus tard » is known to be final (`push_registration.dart:55-56`). Every later call returns at once (`:43`).
- The only caller in the client app is the booking confirmation (`booking_confirmation_screen.dart:130-136`). Nothing else calls `requestPermission()`.
- Préférences shows the blocked banner only when the system says **denied** (`notification_preferences_screen.dart:72-79`, `:127`). After « Plus tard », the system says **not determined**, so the page shows nothing about it.
- **iOS:** an app that never asked has no notification switch in Settings (iOS behaviour; not observed on a device in this repo). That iPhone can never receive push.
- **Android 13+:** the app's switch exists in Settings, off, but nothing in the app points there.
- **Checked, not a defect:** on Android 13+, the plugin in use (`firebase_messaging` 16.7.1) reports a permission never asked as **not determined**, not denied (`FlutterFirebaseMessagingPlugin.java`, `resolveNotificationAuthorizationStatus`). So the app does ask there.

**Préférences says two things that are not true.**
- The « Notifications push » switch reads « Notifications sur cet appareil. » (`notification_preferences_screen.dart:149-154`). The setting is the **account's**: the server reads it before any push (`backend/lib/src/messaging/booking_notifier.dart:66-80`) and sends to every device of the account (`backend/lib/src/push/push_service.dart:56-70`, `devicesForUser`).
- The line under the card reads « Les confirmations et changements de rendez-vous sont toujours envoyés. » (`:170-171`). With push off, and SMS and WhatsApp off in production, nothing is **sent**. What always happens is an entry in « Actu » (`booking_notifier.dart:81-87`, « always — a passive history log »).

**MyWeli Pro has the same push dead end.** Its dashboard asks once through the same `maybePromptOnce` (`dashboard_screen.dart:106-107`), and its notifications page shows the banner only when denied (`pro_notifications_screen.dart:90-100`). A salon that tapped « Plus tard » never hears of a booking.

### 2.1 One rule for every way into sign-in

**The sign-in opens over the screen the person is on, and closing it returns there.**

- **One helper,** `openSignIn(router, {reason})`, **pushes** `/login` and returns `true` when the person comes back signed in, `false` otherwise. It takes the `GoRouter` itself, because the session-ended notice lives above the router, where looking it up from a `BuildContext` finds nothing (`session_ended_notice.dart:35-37`, `main.dart:206-207`).
- **It always answers.** `go_router` completes a pushed route's future only when that route is popped (`delegate.dart:183-197`); a later `go` that removes it would leave the `await` hanging. So the sign-in screen completes the helper when it goes away, by any means (its `dispose`), with « signed in or not » read at that moment.
- **One at a time.** A second call while one is open is ignored; the flag is cleared in a `finally`, so it can never stick.
- **The caller decides what comes next:** carry on (push the confirmation, apply the heart), or nothing.
- **No call site `go`es to `/login` any more.** A source test forbids it (§8).
- **`returnTo` stays for one case only:** a sign-in screen with nothing beneath it, which no current path produces (§2.7 always leaves a screen beneath). Then « Fermer » goes to Accueil, and success goes to `returnTo` (an in-app path; anything else falls back to Accueil, §6).

### 2.2 The sign-in screen

**« Fermer ».** A close icon (`Icons.close`) leads the `AppBar`, with the tooltip « Fermer » and a 48 × 48 target (SYSTEM §13.2). A close, not a back arrow: the screen is a detour the person did not ask for, and closing it cancels the detour.

**Why it opened.** The line under « Bienvenue » says why, instead of a snackbar fired before the screen opens. A snackbar raised on the way in lands on the sign-in screen itself and is gone in three seconds; a line on the screen stays and is read in order. The reasons:

| Reason | The line |
|---|---|
| none (Profil's « Se connecter ») | « Connectez-vous pour réserver en quelques secondes. » (today's line) |
| a heart | « Connectez-vous pour ajouter ce salon à vos favoris. » |
| a booking | « Connectez-vous pour confirmer votre réservation. » |
| « Rendez-vous » | « Connectez-vous pour retrouver vos rendez-vous. » |
| « Actu » | « Connectez-vous pour suivre vos rendez-vous et les réponses des salons. » |
| a profile action | « Connectez-vous pour modifier votre profil. » |
| a session that ended | « Votre session a expiré. Reconnectez-vous. » (`kSessionEndedMessage`, unchanged) |

The five snackbars that used to say this go: `provider_detail_screen.dart:295-298`, the card's two (`provider_card.dart:219-222`, `:404-407`), `booking_confirmation_screen.dart:87-92` and `my_bookings_screen.dart:48-51`.

**Back, step by step:**

| Step | « Fermer » | System back (Android) | The iOS swipe |
|---|---|---|---|
| Options (Google, Apple, e-mail) | closes: back where the person was, signed out | the same as « Fermer » | the same as « Fermer » |
| The e-mail code | closes the sign-in entirely | returns to the e-mail step, as « Changer d’e-mail » does; the code already sent stays valid | **none**: the step holds a `PopScope(canPop: false)`, which turns the swipe off (Flutter); « Changer d’e-mail » and « Fermer » are the ways |
| The phone number | per §11 Q3 (recommended: signs out, then closes) | the same as « Fermer » | none, for the same reason |
| While a request runs (Google's sheet, the code check, saving the number) | disabled until it answers or fails | ignored until then | none until then |

**Why « Fermer » waits for a request.** A sign-in that completes after the screen has gone would leave the person signed in while they believe they cancelled. Each request is short, and the button that started it shows its spinner.

**The phone step (Q3, recommended).** The number stays required for an account in the app (decision of 2026-07-02, [app-auth-social.md](app-auth-social.md)). Leaving the step therefore cancels the sign-in:
- a line under the existing sentence says so before anyone taps: « Sans numéro, la connexion est annulée. »;
- « Fermer » signs out through `AuthProvider.logout`, which also removes the phone's push token;
- the screen beneath shows « Connexion annulée. » (info) **only if the sign-out succeeded**. If it failed, the person is still signed in, the sign-in screen stays on the phone step, and it shows the sign-out's own failure sentence.
- **A race this closes:** signing in starts a token registration that is not awaited (`auth_provider.dart:136-142`). Leaving at once could let it land after the sign-out's unregistration, so the signed-out phone would still receive the account's pushes. **As built:** a registration that has not been sent when an unregistration is asked is dropped, and a sign-out never waits for a registration. *(The approved text said « runs its registrations and unregistrations one after the other, in the order asked ». Built that way, the suites showed every sign-out waiting for whatever registration was in flight — MyWeli Pro's among them — and a stalled best-effort request would have left « Déconnexion » spinning. The race left open is a registration already sent when the sign-out starts: both are in flight, and the server sees them in the order they were sent.)*

**Success.** The sign-in removes **its own** route and completes the helper with `true`. It never pops « whatever is on top »: a notification tap waiting for the sign-in is replayed with a `push` the moment the account is signed in (`main.dart:123-129`), which can be before the sign-in has closed (during the phone step, the account is already signed in). With nothing beneath, it `go`es to `returnTo`, or to Accueil.

**A notification tap waiting for sign-in** is replayed only once no sign-in is open, so it lands on top of where the person ends up.

### 2.3 The account's screens load again when an account signs in

Returning to a screen that stayed open (§2.1) needs what `go` used to hide: the screen must show the account that just signed in.

**One rule.** When the signed-in account changes to a new account, the account's lists load, and every account screen still open loads again:
- **`AccountScope`** already resets every account store when the account changes (`auth_provider.dart:63-71`, `account_scope.dart`). It gains the other half: when the new account is a signed-in one, the favourites (`force`) and the bookings load, once, for the whole app.
- **The screens that read one record** (a booking's detail, Préférences, Mes données, the « Actu » feed, the « Rendez-vous » list) watch the signed-in account and load again when it changes.
- **The test that proves it:** sign in from Profil, go back to Accueil, and the hearts of the salons already in the favourites are filled; « Derniers rendez-vous » is there.

**Why it matters beyond looks.** An empty heart on a salon already in the favourites, tapped, would remove it: `toggleFavorite` reloads, finds it there and removes it (`favorites_provider.dart:86-101`), while the card, built when it was empty, says « Ajouté aux favoris ».

### 2.4 Each way in

| # | Where | After A3 | Signed in on return | Closed |
|---|---|---|---|---|
| 1–3 | A salon's heart (page, card, the card's other layout) | `openSignIn(reason: heart)` | back on the same screen; the salon is added (§2.8, Q2) | back on the same screen, nothing changed |
| 4 | The map's salon sheet, heart | the sheet closes, then `openSignIn(reason: heart)` | back on the map; the salon is added, and the map screen says so (the sheet is gone) | back on the map |
| 5 | **The booking hub's « Confirmer », as a guest** (the gate moves here) | `openSignIn(reason: booking)` before the confirmation opens | the confirmation opens, with the salon, services, time and specialist the person chose | back on the hub, with its choice |
| 5′ | The confirmation, reached signed out anyway (§2.7) | `openSignIn(reason: booking)` over it | it loads | back on the hub (the confirmation closes too) |
| 6 | « Rendez-vous », as a guest | its signed-out page (§2.5); « Se connecter » → `openSignIn(reason: bookings)` | the list loads (§2.3) | the signed-out page |
| — | « Actu », as a guest | its signed-out page (§2.5); `openSignIn(reason: actu)` | the feed loads | the signed-out page |
| 7 | Profil, « Modifier le profil », as a guest | `openSignIn(reason: profile)` | the edit screen opens | Profil, as a guest |
| 8 | Profil, « Se connecter » | `openSignIn()` | Profil, signed in | Profil, as a guest |
| 9 | Profil, after « Se déconnecter » | `go('/home')`, then « Vous êtes déconnecté·e. » (§2.6) | — | — |
| 10 | Profil, after the account is deleted | `go('/home')`, then « Compte supprimé » (§2.6) | — | — |
| 11 | Modifier le profil, signed-out state | `openSignIn(reason: profile)` | the form | the signed-out state |
| 12–13 | A session that ended | §2.7 | | |

*(The hub's button reads « Confirmer » (`booking_hub_screen.dart:900`); the approved text said « Continuer », a slip corrected while building.)* **Why the booking's gate moves to the hub.** Opening the confirmation and then the sign-in over its skeleton makes two transitions, and « Fermer » would have to close both. It would also leave the salon's loading flag up with no load running (`beginProviderLoad`, `booking_confirmation_screen.dart:67`; `provider_provider.dart:234`). Signing in at « Confirmer » (`booking_hub_screen.dart:394-405`) opens the confirmation only for someone signed in, as the website does.

### 2.5 « Rendez-vous » and « Actu » as a guest (Q4)

Both are tabs of the bottom bar. A guest who taps one meets a page that says what it is for and how to get it, instead of being sent away (« Rendez-vous ») or shown an error (« Actu »).

| | « Rendez-vous » | « Actu » |
|---|---|---|
| Icon | `Icons.calendar_today` (the tab's) | `Icons.notifications_none` (the tab's) |
| Title | « Vos rendez-vous » | « Vos notifications » |
| Text | « Connectez-vous pour retrouver vos rendez-vous et en suivre l’état. » | « Connectez-vous pour suivre vos rendez-vous et les réponses des salons. » |
| Button | « Se connecter » | « Se connecter » |
| Hidden for a guest | the « À venir / Passés / Annulés » tab bar (`my_bookings_screen.dart:87`): it would sort nothing | « Tout marquer comme lu »: it would act on nothing |
| The bottom bar | stays; the tab is selected | stays; the tab is selected |

- Both use `EmptyState` (SYSTEM §12: an icon, a French title, why it is empty, and the action that fixes it).
- **Each page watches the session** (§2.3). Signing in anywhere, or a session ending while the page is open, redraws it.

### 2.6 Signing out and deleting the account (Q5)

- **« Se déconnecter »** (after its existing confirmation) lands on Accueil, with « Vous êtes déconnecté·e. » (info). A guest can browse, so the sign-in is no longer where signing out ends. The sentence shows only if the sign-out succeeded.
- **Deleting the account** lands on Accueil, with « Compte supprimé » (success, unchanged).

### 2.7 A session that ended (Q10)

The server refused a renewal; `SessionEndedNotice` hears it (`session_ended_notice.dart:69-90`).

**First, it reads the right screen:** the last route of the stack, whether it was opened with `go` or `push`, instead of the configuration's address that ignores pushed screens (Today). Its tests then open the account screens the way the app does, with `push`.

**Then, two kinds of screen:**

| Where the person is | What happens | After sign-in | After « Fermer » |
|---|---|---|---|
| A screen that can show itself signed out: any public screen, « Rendez-vous », « Actu », Profil, Modifier le profil, the booking hub | the snackbar « Votre session a expiré. Reconnectez-vous. », its action « Se connecter » → `openSignIn(reason: sessionEnded)` | the same screen, which loads again (§2.3) | the same screen, signed out |
| A screen that only exists for an account: a booking's detail, the confirmation, Préférences, Mes données | `openSignIn(reason: sessionEnded)` **over that screen**, at once | the same screen, which loads again (§2.3) | back to the nearest screen beneath that can show itself signed out (Accueil if there is none). From the confirmation, that is the hub, with its choice |

- **This keeps decision Q1 = a** of [consumer-account-scope.md](consumer-account-scope.md) §2.5: the session ends where the person is, and the sign-in brings them back there. What changes is that the sign-in is now over the screen, not instead of it, so the stack beneath survives. §11 Q10 asks for that refinement.
- **The account-only list** (`kAccountOnlyRoutePrefixes`, `session_ended_notice.dart:19-25`) becomes exactly the second row: `/appointment/`, `/booking/confirm`, `/profile/notifications`, `/profile/data`. `/bookings`, `/notifications` and `/profile/edit` leave it, since they draw their own signed-out state.
- **Another account signing in** over an account screen sees that screen load for itself: a booking of another account reads as not found, with its existing state.

### 2.8 A heart tapped before signing in is applied after (Q2)

The person said what they wanted: this salon, in their favourites. After a sign-in started from a heart:

1. **The favourites are read fresh** (`loadFavorites(userId, force: true)`). Signing in may bring favourites saved on another phone or on the website.
2. **If the salon is already one of them,** nothing is sent, and the screen says « Déjà dans vos favoris » (info). Toggling there would have removed it.
3. **If not,** it is added, with the surface's existing words: « Ajouté aux favoris » with « Annuler » (`provider_detail_screen.dart:314` and its siblings). On the map, the sheet is gone, so the map screen shows it as a snackbar.
4. **If the read or the add fails,** the favourites' own failure sentence shows, and the heart stays empty. The person is signed in and can tap again.

**Built so the caller cannot get it wrong:**
- `FavoritesProvider` gains `addIfMissing(userId, salonId)`, which answers one of three outcomes (added, already there, failed). No screen decides with a toggle.
- The caller reads the signed-in account **after** the sign-in returns. The tap's own `userId` and `isFavorite` were the guest's, `''` and `false` (`provider_detail_screen.dart:279-282`, `provider_card.dart:125-128`, `:365-368`), and `toggleFavorite('')` fails with « Utilisateur non connecté ».
- It captures the `ScaffoldMessenger` before the sign-in opens. A card may be rebuilt or unmounted when its list reloads (§2.3).

**The website today returns without applying the heart:** the salon page (`web/components/provider/FavoriteButton.tsx:75-76`) and the search cards (`web/components/discovery/RechercheClient.tsx:133-136`) send a guest to `/connexion?returnTo=…`, and the person taps again. Q2 asks whether the website follows in its own small PR (A3w).

### 2.9 Préférences shows this phone's notification state (Q6)

Préférences reads the system's answer when it opens and each time the app comes back to the foreground (`notification_preferences_screen.dart:65-79`, unchanged). Above the switches:

| The system says | The page shows |
|---|---|
| **Granted** (or iOS's quiet « provisional », `fcm_push_notification_service.dart:94-102`) | nothing; the switches say the rest |
| **Not determined** (never asked, or « Plus tard ») | **a new card:** « Notifications non activées sur ce téléphone », « Activez-les pour recevoir vos rappels et la réponse de votre salon. », and **« Activer les notifications »** |
| **Denied** | the existing `PushBlockedBanner`, unchanged: « Notifications désactivées pour l’appareil », « Ouvrir les réglages » |

**« Activer les notifications »** shows the system's prompt directly (the card is the explanation), then:
- **granted:** the token is registered, as after the booking sheet; the card goes, and « Notifications activées » (success) shows;
- **refused:** the card becomes the blocked banner;
- **no answer or an error** (the app's adapter answers « not determined » when the plugin fails, `fcm_push_notification_service.dart:44-56`): the card stays, and « Une erreur est survenue. Réessayez. » shows (`kGenericErrorMessage`).

**Why « Ouvrir les réglages » for every refusal.** On an iPhone, only Settings can change a refusal. On Android 13+, after one refusal the system would still show its prompt once more, but the plugin reports that and a final refusal alike as « denied » (`FlutterFirebaseMessagingPlugin.java:474-478`), and so does the app. Settings works in both cases.

The card's shape is the banner's (`surfaceVariant`, `border`, `radiusLarge`); its icon is `notifications_none` in `textPrimary`, not the banner's `warning`, since nothing is wrong yet. The button is `AppButtonType.secondary`, as on the banner.

### 2.10 « Plus tard » means later (Q7)

**The new rule, decided by one pure function** of the system's answer, how many times the sheet was offered, when last, and now. It runs at the same moment as today, after a booking is made:

| The system says | Before | The app |
|---|---|---|
| Granted | — | registers the token, silently (as today) |
| Denied | — | nothing; Préférences shows the way (§2.9) |
| Not determined | **the sheet offered fewer than 3 times, the last at least 7 days ago (or never)** | **offers the sheet** |
| Not determined | otherwise | nothing; Préférences keeps « Activer les notifications » |

- **Every offer counts,** whatever its answer: « Activer », « Plus tard », or the sheet dismissed. Counting only « Plus tard » would let a failed « Activer » (the system still « not determined ») bring the sheet back after every booking, without limit.
- **« Activer »** shows the system prompt, as today.
- **The old flag:** a phone with `myweli_push_asked` set and the system still « not determined » counts as one offer with no date. It is offered the sheet after its next booking. The old key is then removed. Every other case is decided by the system's answer, as it already was.
- **Kept on the phone only** (`shared_preferences`): `myweli_push_offer_count` and `myweli_push_offer_at`. Nothing reaches the server.

Three offers over at least two weeks, each after a booking the person just made, is when a reminder matters most. After the third, only Préférences offers it.

### 2.11 Préférences says what is true (Q8)

- **The push switch's sentence** becomes « Sur tous les téléphones connectés à votre compte. » The switch is the account's: turned off, no phone of the account receives a push.
- **The line under the card** becomes « Les confirmations et changements de rendez-vous restent toujours dans « Actu ». » That is what always happens; « envoyés » was true only while push was on.

### Edge cases

- **Signing in as someone else on the way back.** A heart tapped by a guest is applied to whoever signs in: that is the person holding the phone.
- **The booking's slot is taken while the person signs in.** The confirmation opens as today; the server refuses at « Confirmer », with its existing sentence.
- **A deep link to `/login`.** None exists: the push allowlist names `/appointment/`, `/bookings` and `/notifications` (`push_message_handler.dart:27-31`, `kConsumerRoutePrefixes`). If one ever does, nothing is beneath, so §2.1's last rule applies.
- **The sign-in opened twice** (two quick taps on a heart): the second call is ignored (§2.1).
- **A session ends while the sign-in itself is open** (during the phone step): the notice sees the sign-in on top and does nothing more; the sign-in is already the way back.
- **Android 12 and earlier.** Notifications are granted by default, so the sheet never shows and the token registers silently, as today.
- **iOS « provisional ».** Counted as granted, as today (`fcm_push_notification_service.dart:94-102`).
- **Firebase not configured** (a debug build). The system answer is « not determined », and the mock grants on request, as today.
- **Long French at 200 %.** The reason lines, the guest pages and the card wrap; the guest pages scroll (SYSTEM §13.3).
- **Low-end Android.** One extra route on the stack while signing in, and one load of the favourites and bookings after it, which `go` already caused; nothing new to measure.

### Copy, all of it

| Where | Text |
|---|---|
| Sign-in, close button tooltip | « Fermer » |
| Sign-in, reason lines | §2.2 |
| Phone step, the added line | « Sans numéro, la connexion est annulée. » |
| After the phone step is closed | « Connexion annulée. » (info) |
| « Rendez-vous », guest | « Vos rendez-vous » · « Connectez-vous pour retrouver vos rendez-vous et en suivre l’état. » · « Se connecter » |
| « Actu », guest | « Vos notifications » · « Connectez-vous pour suivre vos rendez-vous et les réponses des salons. » · « Se connecter » |
| After « Se déconnecter » | « Vous êtes déconnecté·e. » (info) |
| A heart already a favourite | « Déjà dans vos favoris » (info) |
| Préférences, the new card | « Notifications non activées sur ce téléphone » · « Activez-les pour recevoir vos rappels et la réponse de votre salon. » · « Activer les notifications » |
| After it is granted | « Notifications activées » (success) |
| The push switch | « Sur tous les téléphones connectés à votre compte. » |
| The line under the card | « Les confirmations et changements de rendez-vous restent toujours dans « Actu ». » |
| MyWeli Pro's card (Q9) | « Notifications non activées sur ce téléphone » · « Activez-les pour être prévenu·e des réservations, reports, annulations et acomptes de vos clients. » · « Activer les notifications » |

Unchanged: « Compte supprimé », « Votre session a expiré. Reconnectez-vous. », « Ajouté aux favoris », the sheet's « Activer » and « Plus tard », the blocked banner. Every apostrophe is `’` (SYSTEM §17.1).

---

## 3. API & contract

None. Every change is in the app. The website changes only if Q2 asks for A3w, and that would add no endpoint either.

## 4. Data model

No server data. Two local keys replace one (§2.10): `myweli_push_offer_count` (int) and `myweli_push_offer_at` (ISO-8601 UTC); `myweli_push_asked` is read once, then removed.

## 5. Architecture & patterns

- **`openSignIn`** (`lib/core/auth/open_sign_in.dart`, client app only): §2.1. It takes the `GoRouter`, pushes `/login?reason=<key>`, completes from the sign-in's `dispose`, and ignores a second call while one is open (cleared in `finally`).
- **`LoginScreen`** takes `reason` and `returnTo` from the route (`app_router.dart:33-40`). It adds « Fermer » and a `PopScope` per step (§2.2), and finishes by removing its own route.
- **`SignInReason`**, an enum with its line; an unknown key reads as « none ».
- **`AccountScope`** gains the « signed in » half (§2.3): one load of the favourites and the bookings for a new signed-in account. Screens that read one record watch the account and load again.
- **`FavoritesProvider.addIfMissing`** (§2.8).
- **`PushMessageHandler`'s replay** waits until no sign-in is open (§2.2).
- **`pushOfferDecision(status, offerCount, lastOfferAt, now)`**, a pure function beside `PushRegistration`, answering register, offer or nothing. `PushRegistration` gains `maybeOfferAfterBooking(showRationale)` for the client, built on it, and `enableFromSettings()` for the card. A registration not yet sent when an unregistration is asked is dropped; a sign-out never waits (§2.2). **`maybePromptOnce` stays, unchanged, for MyWeli Pro's dashboard.**
- **`PushOffCard`** (`lib/widgets/push/`), shared by the client's Préférences and, if Q9, Pro's notifications page.
- **The guest pages** live in `my_bookings_screen.dart` and `notifications_screen.dart`, each watching `AuthProvider`. `NotificationsList` stays shared with Pro, unchanged.
- **`SessionEndedNotice`** reads the last route of the stack (§2.7), and its account-only list becomes the four prefixes of §2.7.
- **The booking hub** gates « Confirmer » (§2.4); the confirmation keeps a guard for the case it is reached signed out.

## 6. Security & privacy

- **`returnTo` is used only when nothing is beneath** (§2.1). It must be an in-app path: it starts with « / » and not « // », otherwise Accueil. The router knows no external scheme, but the check costs nothing and holds if one is ever added.
- **No new data leaves the phone.** The two push keys are local.
- **Closing the phone step signs out** (Q3), through the existing `logout`, which also unregisters the push token; a registration not yet sent is dropped, so a late one cannot outlive the sign-out, and the sign-out never waits for it (§2.2). No half-made session stays on the phone.
- **The push token is registered only on « granted »,** as today.
- **A heart applied after sign-in** acts for the account that just signed in, through the existing authenticated favourites call; the server checks ownership as it does today.
- **A notification tap waiting for sign-in** still goes only to the allowlisted routes (`push_message_handler.dart:27-31`), and only once signed in, as today.

## 7. Performance

One more route on the stack while signing in. One load of the favourites and the bookings after a sign-in, which `go` already caused by rebuilding every screen. One favourites read after a heart's sign-in. No list, image or startup cost changes.

## 8. Testing plan

**Unit:**
- `pushOfferDecision`: a table over the three system answers × the offer count (0, 1, 2, 3) × the last date (none, 6 days 23 h ago, 7 days ago). It includes the 7-day boundary, the third offer, and a failed « Activer » (it counts).
- The old key: set with « not determined » counts one offer with no date and is removed; set with « granted » or « denied » changes nothing.
- `SignInReason`: every key has its line; an unknown key reads « none ».
- `returnTo`: « /bookings » kept; « //evil », « https://… » and « » fall back to Accueil.
- `FavoritesProvider.addIfMissing`: added, already there (nothing sent: the mock counts calls), and failed (read fails, add fails).
- `PushRegistration`: a registration not yet sent when a sign-out is asked is dropped; one already sent stays and is unregistered after it (the control); a sign-out answers while a registration hangs.

**Widget:**
- **Sign-in:** « Fermer » on each step; back on the code step returns to the e-mail step; « Fermer » disabled while a request runs; success completes `true`; the helper completes when the sign-in is removed by a `go`; with nothing beneath, « Fermer » goes to Accueil and success goes to `returnTo`; the phone step's « Fermer » signs out and says « Connexion annulée. », and a failed sign-out keeps the step.
- **A notification tap waiting for sign-in** lands after the sign-in closes, on top of where the person is, and the sign-in's success did not close it.
- **Each way in (§2.4):** the sign-in is pushed (the screen beneath is still mounted), and « Fermer » returns to it. The heart's three outcomes, read with the account that signed in. The hub's « Confirmer » as a guest: closed, the hub keeps its choice; signed in, the confirmation opens with it.
- **The reload (§2.3):** sign in from Profil, back on Accueil, the favourites' hearts are filled and « Derniers rendez-vous » shows.
- **The guest pages:** « Rendez-vous » and « Actu » as a guest (no tab bar, no « Tout marquer comme lu »), then signed in (the list or the feed loads), then a session that ends while open.
- **Sign-out and deletion** land on Accueil with their sentence; a failed sign-out says nothing of the kind.
- **A session that ended,** with the account screens opened by `push`, as the app opens them: on a public screen the action opens the sign-in over it; on a booking's detail the sign-in opens over it at once, success returns to the detail, which loads, and « Fermer » returns to « Rendez-vous »; on the confirmation, « Fermer » returns to the hub.
- **Préférences:** the three system answers, with the card's three results (granted registers the token, refused shows the banner, an error keeps the card); the two new sentences.
- **The booking confirmation:** the sheet shown or not per `pushOfferDecision`. *(As built: in `test/unit/push_offer_test.dart` — the rule's table, `maybeOfferAfterBooking`, the old flag, `enableFromSettings`, the dropped registration — rather than in the two files this line first named; `push_registration_test` still passes unchanged.)*

**Tests that change, named so none is skipped:**
- `test/widget/account_switch_test.dart:347` (« on an account screen: it leaves for the sign-in ») and `:424` (« every account-only prefix is a route of the app »): rewritten for §2.7, with pushed screens.
- `test/unit/route_literals_test.dart:322-326`: the Pro exemption for `/login` in `provider_detail_screen.dart` moves with the literal into `open_sign_in.dart`. The heart never shows in Pro's « Aperçu » (`if (!widget.preview)`), and Pro's router has no `/login`; the exemption says so.
- `test/widget/push_blocked_banner_test.dart:86-93`: « not determined » no longer means « nothing to do »; that case moves to the new card's test.
- `login_screen_test`, `my_bookings_screen_test`, `profile_screen_test`, `edit_profile_screen_test`: updated where they assert a `go` to `/login`.

**Source guards, each watched red once:**
- no file under `lib/` outside the Pro screens calls `go` with `/login` (comments stripped);
- `kAccountOnlyRoutePrefixes` is exactly the four of §2.7;
- `maybePromptOnce` has no caller in the client app; `maybeOfferAfterBooking` has none in Pro.

**Goldens (authored on Linux, every changed PNG opened):** the sign-in with « Fermer » and a reason line; the two guest pages; Préférences with the card. Each at 360 px, and at 200 % text.

**Accessibility:** « Fermer » is 48 × 48 with its tooltip; the reason line is read before the buttons; the guest pages and the card pass the layout test at 200 %.

## 9. Rollout & scope discipline

- **One app PR (A3).** It reaches clients with the next consumer build, on the owner's yes. Nothing is deployed at its merge.
- **If Q9:** Pro's card is in the same PR, and reaches salons with the next Pro build.
- **If Q2 includes the website:** A3w, its own PR after A3. Its merge is a production deploy of `myweli.com`, on the owner's word.
- V1 only. No flag: each change replaces a dead end.

## 10. Definition of done

- [ ] `flutter analyze` 0; format clean; the full mobile suite green; each new guard watched red once (the list in the commit message).
- [ ] Goldens regenerated on Linux, and every changed PNG opened.
- [ ] SYSTEM.md: §12's auth-gated line names the guest pages and `openSignIn`; §21 gains nothing.
- [ ] push-notifications-app.md says the client's ask is no longer once; notification-preferences.md carries the two new sentences; consumer-account-scope.md §2.5 carries Q10's refinement.
- [ ] The audit's gaps 10 and 17 are marked done; BACKLOG decisions recorded; a roadmap entry.
- [ ] A feature branch and a PR; CI green; no Claude attribution; merged on the owner's word.

## 11. Open questions (each with a recommendation)

**All ten answered on 2026-11-24: « Approve as recommended »** (BACKLOG decisions 204–213, in the order Q1–Q10). Each answer is the recommendation written under its question; Q2's includes A3w.

**Q1. The sign-in opens over the screen the person is on, with « Fermer », and closing returns exactly there — for every way in (§2.1–§2.4)? The reason is written on the screen instead of a snackbar (§2.2), and the booking's gate moves to the hub's « Confirmer » (§2.4).**
- *Recommended: yes.* It is the audit's gap 10, and the store reviewer's first dead end.

**Q2. After signing in from a heart, add the salon to the favourites (§2.8)?**
- *Recommended: yes in the app; and the website's two hearts follow in their own small PR (A3w), so both surfaces keep the same story.*
- The alternative is the website's behaviour today: come back and tap again.

**Q3. On the phone-number step, does « Fermer » sign the person out (§2.2)?**
- *Recommended: yes.* The number stays required for an account in the app, as decided on 2026-07-02, and a line says so before anyone taps.
- The alternative keeps the session and asks for the number at booking, as the website does. That is a larger change to the booking confirmation, and its own PR.

**Q4. « Rendez-vous » and « Actu » show a signed-out page with « Se connecter » (§2.5)?**
- *Recommended: yes.* « Rendez-vous » sends a guest away today, and « Actu » shows an error with a retry that cannot work.

**Q5. After « Se déconnecter » and after deleting the account, land on Accueil (§2.6)?**
- *Recommended: yes.* Today both end on the sign-in screen, which until A3 had no way out.

**Q6. Préférences shows this phone's state, with « Activer les notifications » when it was never asked (§2.9)?**
- *Recommended: yes.* It is the only way back for an iPhone after « Plus tard ».

**Q7. The sheet comes back after a later booking: at most 3 offers in all, at least 7 days apart (§2.10)?**
- *Recommended: yes, with those two numbers.*
- The alternative is today's rule, never again, with Préférences (Q6) as the only way back.

**Q8. Préférences' two sentences: « Sur tous les téléphones connectés à votre compte. » for the push switch, and « Les confirmations et changements de rendez-vous restent toujours dans « Actu ». » under the card (§2.11)?**
- *Recommended: yes.* « sur cet appareil » is false, since the setting is the account's. « toujours envoyés » is false while push is off, since SMS and WhatsApp are off.

**Q9. MyWeli Pro: the same card on its notifications page (§2.9), in this PR?**
- *Recommended: yes, the card only.* Its dashboard's ask stays as it is. A salon that tapped « Plus tard » otherwise never hears of a booking, and the card reaches salons with the next Pro build.

**Q10. A session that ended on an account screen: the sign-in opens over that screen, and « Fermer » returns to the nearest screen that can show itself signed out (§2.7)?**
- *Recommended: yes.* It keeps decision Q1 = a of consumer-account-scope.md (the session ends where the person is, and comes back there), and the stack beneath survives. From the confirmation, « Fermer » returns to the hub with its choice.

## 12. The independent reading (2026-11-24)

One reader, told to refute this spec against the code, returned 14 findings. Each was re-read in the code before it went in. The four that would have shipped broken behaviour:

1. **The screens beneath never load the new account.** Accueil, the salon page and the map load favourites and bookings once, at opening (`home_screen.dart:50-65`). `go` hid it by rebuilding everything. Returning to an open screen would have shown empty hearts on favourites, and a tap would have removed one. → §2.3.
2. **The session-ended notice reads the wrong screen.** `go_router`'s configuration address ignores pushed screens (`match.dart:530-533`), and every account screen is pushed. This is a defect today, not only in this design. → §2.7.
3. **A `go` back to a booking's detail would rebuild the dead end** (a one-screen stack), and the confirmation would lose its hub. → §2.7: the sign-in opens over the screen instead.
4. **The helper could not serve the notice, and could hang.** The notice lives above the router, and a pushed route's `await` completes only on pop. → §2.1.

The others:
5. A notification tap replayed at sign-in could be closed by the sign-in's success.
6. The iOS swipe cannot step back.
7. Four existing tests change.
8. The offer limit could be bypassed by a failed « Activer ».
9. The heart's caller held the guest's `userId`.
10. Two races on the phone step.
11. A contradiction about Modifier le profil, and an approved decision changed without a question (now Q10).
12. A line under Préférences that is not true.
13. Copy and wording slips.
14. The booking's gate belongs at the hub.

Each is folded into the section named.

## 13. The independent reading of the code (2026-11-24)

The built change was read once by a reviewer told to refute it: 11 findings. Each was re-read in the code. The fixes, each with its test watched red:

1. **A closed sign-in could answer the NEXT one's opener.** Its `dispose` runs after its exit animation, while taps already reach the screen beneath. Each screen now takes its own ticket (`SignInGate.ticket`) and answers only that.
2. **Modifier le profil kept the previous account's details** after a sign-in over it, and « Enregistrer » would have sent them to the new account. It now refills from whoever signed in (`ReloadOnSignIn`), its phone field rebuilt.
3. **A notification tapped during the phone step** (signed in by then) was replayed after « Fermer » had signed the person out. The wait for the sign-in now runs BEFORE the handler's session check (`PushMessageHandler.ready`), so that tap is kept for the next sign-in.
4. The goldens had no images yet: authored on Linux and opened before the commit.
5. — *not fixed, recorded:* a sign-in over a booking's detail starts the root's list read and the detail's own read side by side. Both write `AppointmentProvider`'s shared `isLoading` and `error`, so a failed list read shows its sentence on the detail until the detail's read answers. That sharing predates A3, and the case needs a session ending on a detail plus a list failure. A follow-up: per-read flags in that store.
6. A guest-page assertion that could not fail (the button also hides at 0 unread) now finds the widget by type.
7. Tests the plan named and the first build lacked: the deletion's landing, a failed sign-out on Profil, a session ending on Préférences.
8. The session-ended notice read `router.state`, which throws on go_router's error page (no match). Guarded.
9. On the phone step, « Continuer » spun while « Fermer » signed out. It no longer does. *Recorded, not new:* a sign-out that fails has already removed the phone's push token (`AuthProvider.logout` unregisters first), so that person gets no push until the next sign-in.
10. A forced favourites read could share a read sent before a heart was written. Reads are shared only when no heart was written since.
11. The sign-in popped whatever route was on top. It now closes anything above its own route first, then itself.


## 14. A3w — the website's two hearts (decision 205)

Q2's answer included the website: a heart a guest taps is applied once they have signed in, on the salon page (`web/components/provider/FavoriteButton.tsx`) and on the search's cards (`web/components/discovery/RechercheClient.tsx`). Read at `main` `aa3fe341`. No endpoint changes; the change ships with the next deploy of `myweli.com`.

**The reason line on `/connexion` (14.2 step 2) is the one addition to Q2's wording.** The owner's rule is that the website follows the app's flow screen by screen, and the app's sign-in opened from a heart says why (§2.2). Built in `web/lib/auth/sign-in-reason.ts`; one key today.

### 14.1 Today

- **Salon page.** A guest's tap sends `POST /api/me/favorites/{id}`; its 401 pushes `/connexion?returnTo=/{slug}` (`FavoriteButton.tsx:75-76`).
- **Search.** The favourites read answered 401, so a heart goes straight to `/connexion?returnTo=<the search, with its filters>` through `window.location.assign`. An add that answers 401 does the same (`RechercheClient.tsx:133-136`, called at `:144` and `:165`).
- **`/connexion`** returns with `router.replace(returnTo)` once signed in (`web/components/auth/ConnexionClient.tsx:9-12`). Google and Apple open popups, so the tab never leaves the site (`LoginOptions.tsx`).
- **The person is back where they were, and taps again.** Nothing remembers the heart, and `/connexion` does not say why it opened.

### 14.2 The flow

1. **A guest taps a heart** (or an add answers 401). Before leaving, the page remembers the heart in this tab: `sessionStorage`, the salon's id and the time. It then opens `/connexion?raison=favori&returnTo=…`, where `returnTo` is the same page as today with one more parameter, `suite=favori`.
2. **`/connexion` says why**, under its title: « Connectez-vous pour ajouter ce salon à vos favoris. », the app's reason line (§2.2). Without `raison`, or with any other value, the page is as today.
3. **Signed in, the person is back on the page** (`router.replace(returnTo)`, unchanged). The page reads the favourites, as it already does on load, and that read is fresh: it brings favourites saved on the phone.
4. **When the read answers, the page takes the heart.** The marker is removed from the address (`history.replaceState`; other parameters stay), and the stored heart is removed from the tab. The heart applies only if all of these hold:
   - the address carried `suite=favori`;
   - a heart was stored in this tab less than 30 minutes ago;
   - on the salon page, the stored salon is this page's salon.
5. **Then, as in the app (§2.8):**
   - **already a favourite:** nothing is sent; the heart shows full and « Déjà dans vos favoris » shows (info). A toggle would have removed it;
   - **not yet:** it is added, with the words of an ordinary tap: « Ajouté aux favoris » with « Annuler »;
   - **the read or the add failed:** the surface's own failure sentence shows where a failed tap shows it, under the button or under that card, and the heart stays empty. The person is signed in and can tap again;
   - **the add answers 401 again:** the sign-in opens again, as in step 1.

### 14.3 Why the two keys

The address alone could be forged: a link to `/{slug}?suite=favori` would add that salon for any signed-in visitor who opens it. The stored heart alone would fire too late: a guest who taps a heart, goes back from `/connexion` without signing in, and signs in later from the header would find the salon added on their next visit. Both together mean: **this tab tapped this heart, and is coming back from the sign-in it opened.**

### 14.4 Rules the build holds

- **Read once, then take once.** The heart is taken only inside the favourites read's answer. The take forgets the stored heart, so a second answer finds nothing: React's development double-mount runs the read twice and the heart is applied once. An answer that arrives after the page was left is ignored, so nothing is applied on a page the person has left.
- **The salon page's heart waits for its read**, as the search's already did. Before it, a tap on the empty heart while the read was out raced the heart applied on the way back, and sent the add twice (§14.7). A read that throws counts as a failed read, so the heart never waits for ever.
- **A 401 that answers after the page was left navigates nowhere.**
- **No focus is moved.** The page has just loaded, and moving the focus to the heart scrolled the salon page off its cover at 320 × 568 (`FavoriteButton.tsx`, web-swiss-salon.md §1.4). The toast's polite live region says what happened, and the heart itself stays a way back.
- **The search.** The card is normally on the page, since `returnTo` is the same search. If that salon has left the results, the add still happens, since the person asked; a failure then shows in the toast (error), as there is no card to hold it.
- **Storage refused** (a private window, storage blocked): nothing is stored, the marker is stripped, and the page behaves as today. Every `sessionStorage` call is wrapped.
- **A removal that answers 401** (a session that ended): the sign-in opens without `raison` and without a heart to apply. Only an add is carried.
- **`raison`** maps a known key to a fixed sentence; nothing in the address is ever written to the page.

### 14.5 Copy

| Where | Text |
|---|---|
| `/connexion?raison=favori`, under the title | Connectez-vous pour ajouter ce salon à vos favoris. |
| Already a favourite (toast, info) | Déjà dans vos favoris |
| Added (toast, success, with « Annuler ») | Ajouté aux favoris (unchanged) |
| A failure | the surface's existing sentence (`writeFailureMessage`) |

### 14.6 Tests

- **Unit:** the stored heart (stored, taken once, expired at 30 minutes, needs the marker, keeps the other parameters, storage that throws); the `raison` line (known, unknown, absent).
- **Components:** each surface, for each row of 14.2 step 5; a guest's tap leaves with both keys; no marker or another salon's heart applies nothing; a development double-mount applies once.
- **End to end:** a guest taps the salon page's heart, sees the reason, signs in, and is back on the salon with « Ajouté aux favoris » and one `POST`. The same through the search's card. A salon already among the favourites says « Déjà dans vos favoris » with no write. The address no longer carries `suite`.
- **Mutations:** each condition in 14.2 step 4, the « already » branch, the strip, and the reason's mapping, each watched red.

### 14.7 The independent reading of A3w (2026-11-24)

The built change was read once by a reviewer told to refute it: 7 findings, each re-read in the code. The fixes, each with its test watched red:

1. **A tap during the read added the salon twice.** On the salon page, the heart was enabled while the favourites read was out. Back from the sign-in, a person tapping the empty heart sent one add, and the read's answer sent a second. An « Annuler » tapped in between was then undone. The heart now waits for its read, as the search's do.
2. **The e2e spec was not yet committed.** It is now part of the PR.
3. **Two e2e waits could not fail.** The return from `/connexion` is a soft navigation, so `waitForLoadState('networkidle')` answered at once. The spec now waits for the favourites read after the sign-in, and counts writes from before it. The control could not fail either: it now stores a heart, then signs in another way, so a heart applied without the marker turns it red.
4. **The comments credited the wrong guard.** The take, not the mounted check, is what applies the heart once in React's double-mount. The mounted check matters when the page is left before the read answers. That case now has its own test on each surface.
5. **An open redirect in `/connexion`, from before A3w.** `returnTo=/\evil.example` passed `startsWith('/') && !startsWith('//')`, and the browser reads it as `//evil.example`, another site, reached right after signing in on ours. A3w's reason line would have made such a link more convincing. `returnTo` is now resolved as the browser resolves it, and kept only if it stays on this origin (`web/lib/auth/return-to.ts`).
6. **A 401 answering after the page was left** would still have navigated to `/connexion`. Both surfaces now check that the page is still mounted.
7. *Checked, kept:* `history.replaceState(null, …)`, as Next's documentation writes it. Next 14.2 copies its own history state into the call and fetches nothing; nothing else on these pages keeps history state.

*Recorded, not fixed here:* `web/lib/pro/notifications.ts:16` reads a feed route with the same `startsWith('/') && !startsWith('//')` test. Those routes are written by the server, not by a link, so whether `/\` can reach it is unverified; it is a follow-up for the Pro side.
