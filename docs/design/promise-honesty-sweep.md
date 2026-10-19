# Ce que l'app promet = ce qu'elle fait : rappels, acompte, notifications du salon — spec

| | |
|---|---|
| **Statut** | **Approved le 2026-10-19** — le propriétaire a validé T1–T6 tels que recommandés (§3) : T1 « dans l’app MyWeli », T2 « sur votre Mobile Money », T3 corrigé maintenant (l'événement serveur en suite, §8), T4–T6 tels qu'écrits |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-19 |
| **PRD ref / phase** | FR-PRO-MKT-001 (rappels) · la décision sans-custody des acomptes (PRD OQ-1, mémoire `payments-no-custody-screenshot`) · V1 |
| **Module** | web Pro (carte d'offre), web public (accueil, `llms.txt`), app Pro (Acompte, Accueil, Notifications) |
| **ROADMAP entry** | à créer au merge : `docs/roadmap/entries/2026-10-19-promise-honesty.md` |
| **Skills checked** | myweli-dev-guardrails ✓ · myweli-web-guardrails ✓ · myweli-backend-guardrails : aucun code serveur modifié (lu seulement) · myweli-verification-guardrails (avant de dire « fait ») |
| **Origine** | La revue d'honnêteté de la vidéo promo, 2026-10-19, relue sur `origin/main` (`a91edc66`) |

## 1. Le constat — chaque défaut relu sur le vrai chemin de code

### 1.1 La carte d'offre Pro vend des rappels WhatsApp/SMS qui ne partent pas

`web/lib/pro/subscription-plans.ts:41` — l'offre Pro liste
« Rappels automatiques WhatsApp/SMS (24 h / 2 h) ». Rendue par
`AbonnementClient.tsx` (le choix d'offre du web).

**Ce qui se passe vraiment** :

- Le planificateur existe et tourne : `ReminderScheduler.tick`
  (`backend/lib/src/messaging/reminder_scheduler.dart`) envoie 24 h et 2 h,
  appelé par le job Cloud Scheduler `myweli-reminders` toutes les 15 min
  (DEPLOYMENT.md §5 — *non ré-observé dans la console aujourd'hui*).
- Chaque rappel passe par `BookingNotifier.notify`
  (`booking_notifier.dart:52-89`), qui essaie **trois** canaux :
  1. **WhatsApp/SMS** via `MessagingService` → en production
     `MESSAGING_PROVIDER=disabled` (`infra/gcp/service.yaml:130-131`), donc
     `DisabledMessagingProvider` : **rien ne part**, l'outbox enregistre un
     échec. Gelé jusqu'à l'immatriculation de la société (mémoire
     `launch-scope-sms-deferred`).
  2. **Push FCM** — seulement si le rendez-vous a un `userId` (réservé dans
     une app/sur le web avec un compte) **et** que l'utilisateur a laissé
     `push` + `reminders` actifs. Il n'y a **pas de push web**
     (aucun `PushManager` / service worker dans `web/`) : le push n'arrive
     que sur un téléphone où l'app MyWeli est installée et connectée.
  3. **Le fil in-app** (`notifications.add`) — toujours écrit pour un
     `userId` ; c'est un historique passif (cloche de l'app, `/compte/notifications`).
- **Un client saisi par le salon** (réservation manuelle, pas de compte) ne
  reçoit **rien** : pas de `userId`, et le seul canal qui l'atteindrait
  (SMS) est éteint.

Donc « Rappels automatiques **WhatsApp/SMS** » est faux sur le canal, et le
salon paie pour ce canal. Déjà noté et laissé en l'état deux fois :
[pro-companion-path.md](pro-companion-path.md) (« Minors noticed ») et
l'entrée [2026-10-13-web-pro-sms-and-phone-parity.md](../roadmap/entries/2026-10-13-web-pro-sms-and-phone-parity.md)
(« Enregistré, non corrigé »).

**L'app** : `mobile/lib/core/config/subscription_plans.dart` n'affiche plus
aucune liste d'avantages depuis la voie compagnon (3.1.3(f)) — rien à
corriger côté app. **Le serveur** : aucun catalogue d'offre ne porte de
texte (le backend ne renvoie que palier/statut/dates/places).

### 1.2 « Acompte payé en ligne » — l'acompte ne se paie pas en ligne

`mobile/lib/screens/provider/settings/deposit_settings_screen.dart:328` —
l'exemple chiffré de l'écran Acompte (app Pro) : « Acompte payé en ligne ·
6 000 FCFA » / « Solde au salon · 14 000 FCFA ».

**Ce qui se passe vraiment** : le client envoie l'acompte par Mobile Money
**directement sur le numéro du salon** (carte « Recevoir l'acompte » du même
écran), puis joint une capture ; le salon confirme. MyWeli ne détient jamais
l'argent. « En ligne » laisse entendre un paiement dans l'app (carte,
agrégateur) — exactement ce que la décision sans-custody exclut.

Les autres surfaces de l'acompte sont **déjà justes** (relues) :
`deposit_payment_sheet.dart` « Versé directement au salon. MyWeli ne prélève
rien. » ; `DepositProof.tsx` « …MyWeli ne prélève rien. » ; l'accueil web
« Acompte direct au salon » et la FAQ « Faut-il payer en ligne sur MyWeli ?
— Non. » ; la page Acompte du web (`AcompteClient.tsx`) n'a pas d'exemple
chiffré, donc pas la phrase.

### 1.3 L'invite push du salon promet « …ou modifie un rendez-vous »

`mobile/lib/screens/provider/dashboard/dashboard_screen.dart:83-84` — à la
première visite de l'Accueil Pro : « Soyez prévenu·e dès qu'un client
réserve, annule ou modifie un rendez-vous, et ne manquez aucune demande. »

**Vérifié : le salon n'est pas prévenu quand un client reporte.**
`SalonNotifier` (`backend/lib/src/messaging/salon_notifier.dart:13`) connaît
trois événements — `newBooking`, `clientCancelled`, `depositSubmitted` —,
appelés par `appointments/index.dart:187`, `[id]/cancel.dart:35`,
`[id]/deposit.dart:56`. La route `[id]/reschedule.dart:71-77` n'appelle que
`BookingNotifier` (le **client** reçoit « Rendez-vous reporté »), jamais
`SalonNotifier`. Or le client **peut** reporter : « Reporter » dans
`appointment_detail_screen.dart:550` → `reschedule_screen.dart`, et
`AppointmentLifecycleService.reschedule` l'accepte pour son propre rendez-vous.

Donc la phrase promet un événement qui n'existe pas — et c'est aussi un vrai
manque produit (§8, suite).

### 1.4 Trouvés par le balayage

| # | Où | Texte | Verdict |
|---|---|---|---|
| 1.4.a | `web/app/page.tsx:166` (accueil web, consommateur) | « **Confirmations WhatsApp** » / « Rappels avant votre rendez-vous. » | **Faux** sur le canal (WhatsApp éteint) ; les rappels existent, par l'app |
| 1.4.b | `web/public/llms.txt:5-6` (lu par les moteurs IA) | « Salons manage bookings, deposits and automated **WhatsApp/SMS reminders**. » | **Faux** — même raison |
| 1.4.c | `mobile/lib/screens/provider/notifications/pro_notifications_screen.dart:89` → `PushBlockedBanner` (texte par défaut, `push_blocked_banner.dart:58-59`) | « Autorisez MyWeli dans les réglages de votre téléphone pour recevoir **vos rappels et confirmations**. » — affiché **au salon** | **Faux pour le salon** : il ne reçoit ni rappel ni confirmation (ses trois événements, §1.3). Juste côté client. Et l'app s'appelle « MyWeli Pro » dans les réglages (`build.gradle.kts:77`, `APP_DISPLAY_NAME`) |
| 1.4.d | `docs/PRD.md:254` et `:482` | « automated WhatsApp/SMS reminders » · « ✅ built — … WhatsApp/SMS reminders » | Doc interne, **construit mais éteint** — à annoter, pas de copie produit |

**Relus et justes — on n'y touche pas :**

- `push_permission_sheet.dart:17` (client) « Recevez vos rappels et
  confirmations de rendez-vous, et soyez prévenu·e dès que votre salon
  répond. » — vrai par push (accept → `bookingAccepted`, rappels 24 h/2 h).
- `push_blocked_banner.dart` côté **client** (`notification_preferences_screen.dart:136`) — vrai.
- `notification_preferences_screen.dart:154-155` et `NotificationsClient.tsx:36-37`
  « Rappels 24 h et 2 h avant vos rendez-vous. » — vrai (push + fil).
- `push_message_handler.dart:22` (canal Android) « Réservations, rappels et
  mises à jour de vos rendez-vous. » — vrai.
- `BookingFlow.tsx:428` « Vous recevrez une notification. » — vrai (le fil
  in-app est toujours écrit ; push si l'app est installée).
- « Réservation en ligne », « mettre en ligne », « en ligne 24/7 » —
  **réserver** en ligne est vrai ; seul **payer** en ligne est faux.
- `ROI_LINE` « Un seul rendez-vous manqué évité paie le mois. » — un argument,
  pas une fonction promise ; laissé.

**Déjà cachés derrière un drapeau (inatteignables) — on n'y touche pas :**
`pro_manual_booking_screen.dart:378` « Envoyer la confirmation par SMS »
(`FeatureFlags.smsInvite = false`) ; `features/whatsapp_notifications_screen.dart`
(écran V2, `FeatureFlags.futureProviderFeatures = false` → `ComingSoonScaffold`).

### 1.5 Les textes des stores

Relus : [play-store-forms.md](play-store-forms.md) §1 (les deux fiches) et
[app-store-forms.md](app-store-forms.md) §4 (MyWeli Pro).

- **MyWeli Pro (Play + App Store)** : aucune promesse de rappel, de canal ni
  de paiement en ligne. « Le client paie l'acompte sur VOTRE Mobile Money et
  joint sa preuve » — juste.
- **MyWeli (Play)** : « Vos réservations, rappels et l'historique de vos
  visites, au même endroit. Modifiez ou annulez en un geste. » — juste (les
  rappels sont dans l'app ; le client peut « Reporter » et annuler).
  « L'acompte éventuel se règle directement au salon par Mobile Money » — juste.

**Aucun texte de store à modifier.** En revanche, **le binaire Pro déjà
envoyé** (build 587, TestFlight externe, rattaché à la version 0.0.1)
contient « Acompte payé en ligne », l'invite « …ou modifie un rendez-vous »
et le bandeau « …vos rappels et confirmations » : la correction de l'app
n'atteint les relecteurs et les testeurs qu'avec **le prochain build** —
décision du propriétaire (§7).

## 2. Ce que l'app fait aujourd'hui — la référence pour le texte

| Promesse | Vrai aujourd'hui ? |
|---|---|
| Rappels 24 h et 2 h au client | **Oui**, par **notification de l'app MyWeli** (push + fil), pour un client qui a réservé avec un compte et n'a pas coupé les rappels |
| … par WhatsApp ou SMS | **Non** — `MESSAGING_PROVIDER=disabled` jusqu'à l'immatriculation |
| … à un client saisi par le salon (sans compte) | **Non** |
| Le salon est prévenu d'une réservation, d'une annulation par le client, d'un justificatif d'acompte | **Oui** (push + fil, `SalonNotifier`) |
| Le salon est prévenu quand le client reporte | **Non** (§1.3) |
| L'acompte se paie en ligne / dans l'app | **Non** — Mobile Money, directement au salon, prouvé par capture |

## 3. Le texte proposé — **à valider mot pour mot**

Apostrophe typographique (’) comme le reste du produit.

| # | Surface | Aujourd'hui | **Proposé (recommandé)** | Variante |
|---|---|---|---|---|
| **T1** | Web Pro — carte d'offre « Pro » (`subscription-plans.ts:41`) | Rappels automatiques WhatsApp/SMS (24 h / 2 h) | **Rappels automatiques à vos clients dans l’app MyWeli (24 h / 2 h)** | Retirer la ligne |
| **T2** | App Pro — Acompte, exemple chiffré (`deposit_settings_screen.dart:328`) | Acompte payé en ligne | **Acompte sur votre Mobile Money** | Acompte par Mobile Money |
| **T3** | App Pro — invite push de l'Accueil (`dashboard_screen.dart:83`) | Soyez prévenu·e dès qu’un client réserve, annule ou modifie un rendez-vous, et ne manquez aucune demande. | **Soyez prévenu·e dès qu’un client réserve, annule ou envoie son acompte, et ne manquez aucune demande.** | Garder la phrase et construire d'abord l'événement serveur (§8) |
| **T4** | App Pro — bandeau « notifications désactivées » (écran Notifications Pro) | Autorisez MyWeli dans les réglages de votre téléphone pour recevoir vos rappels et confirmations. | **Autorisez MyWeli Pro dans les réglages de votre téléphone pour être prévenu·e des réservations, annulations et acomptes de vos clients.** | — (le bandeau **client** ne change pas) |
| **T5** | Web — accueil, 3ᵉ tuile (`page.tsx:166`) | **Confirmations WhatsApp** — Rappels avant votre rendez-vous. | **Rappels dans l’app** — Confirmation du salon, puis rappels 24 h et 2 h avant votre rendez-vous. | **Notifications de l’app** — même texte |
| **T6** | Web — `llms.txt:5-6` (anglais, pour les IA) | Salons manage bookings, deposits and automated WhatsApp/SMS reminders. | **Salons manage bookings and Mobile Money deposits; clients get automatic reminders (24 h and 2 h before) as notifications in the MyWeli app.** | — |

Pourquoi ces choix :

- **T1** dit le canal réel *et* qui le reçoit (« vos clients … dans l'app »),
  sans promettre le rappel aux clients saisis à la main. Retirer la ligne
  serait honnête aussi, mais la fonction existe et compte pour un salon.
- **T2** reprend la formule déjà publiée sur les stores (« sur VOTRE Mobile
  Money ») et s'oppose naturellement à « Solde au salon ». 31 caractères
  contre 21 : `LabelValueRow` passe la valeur à la ligne si besoin (test
  a11y existant, §5).
- **T3** nomme les trois événements que le serveur envoie vraiment — la
  même liste que l'état vide de l'écran Notifications Pro (« Les
  réservations, annulations et acomptes de vos clients apparaîtront ici. »).
- **T4** : même liste que T3 ; et le nom que le salon verra dans ses
  réglages est « MyWeli Pro ».
- **T5** garde la tuile (c'est un vrai avantage) et pousse l'app, comme le
  veut la règle du web (« web converts, the app deepens »).

**Docs internes, sans validation de texte** : `PRD.md:254` et `:482`
annotés « construit — **éteint en production** (`MESSAGING_PROVIDER=disabled`)
jusqu'à l'immatriculation ; les rappels atteignent aujourd'hui les clients par
notification de l'app ». Le commentaire de `label_value_row.dart:21` et la
table de `label_value_row_test.dart` suivent T2.

## 4. Architecture

Copie seulement : aucun écran, aucun état, aucun contrat, aucune route
serveur. Une seule forme nouvelle : `PushBlockedBanner` reçoit un paramètre
`body` optionnel (défaut = le texte client actuel), comme
`showPushPermissionSheet` le fait déjà pour `body` — l'écran Pro passe T4.

## 5. La garde — pour que les phrases ne reviennent pas

Deux épingles de source (le modèle de `pro_subscription_no_pricing_test.dart`
et de `phone-numbering-pin.test.ts`) : commentaires retirés, littéraux
adjacents joints, apostrophes ramenées à une seule forme, insensible à la
casse.

**Trois familles de phrases interdites**, chacune avec **la condition qui la
justifie, relue par le test lui-même** — si la condition change, le test
échoue avec « re-décidez cette épingle » au lieu de se relâcher en silence :

| Famille | Phrases | Condition relue |
|---|---|---|
| Canal de messagerie | « WhatsApp/SMS », « SMS/WhatsApp », « rappels WhatsApp », « rappels SMS », « rappel par SMS », « rappel par WhatsApp », « confirmations WhatsApp », « confirmation WhatsApp », « confirmation par WhatsApp », « WhatsApp reminders », « SMS reminders » | `infra/gcp/service.yaml` dit `MESSAGING_PROVIDER` = `disabled` (le test exige d'avoir trouvé l'entrée) |
| Paiement en ligne | « payé en ligne », « payée en ligne », « paiement en ligne », « payez en ligne », « réglé en ligne », « pay online », « paid online », « online payment » | Permanente (décision sans-custody) |
| Report signalé au salon | « annule ou modifie », « modifie un rendez-vous » | `enum SalonEvent` dans `salon_notifier.dart` n'a aucun membre de report (le test exige d'avoir lu l'enum) |

- **App** — `mobile/test/infra/promise_honesty_pin_test.dart` : tout `lib/`
  **et** les sections fiche de store (`play-store-forms.md` §1,
  `app-store-forms.md` §4), puisque ce sont les textes des apps.
  Plus un test de widget : l'écran Notifications Pro, OS refusé, montre T4 et
  ne contient pas « rappels » ; l'écran client garde son texte.
- **Web** — `web/tests/promise-honesty-pin.test.ts` : `app/`, `components/`,
  `lib/` (hors `lib/api/schema.ts`, généré), `public/llms.txt`. Plus, dans
  `pro-subscription.test.ts` : aucune ligne d'avantage ne nomme WhatsApp ni
  SMS.
- **Rouge d'abord** : chaque test écrit et lancé **avant** la correction,
  vu rouge sur les phrases actuelles ; puis chaque garde de condition vue
  rouge en simulant la condition (une auto-vérification injecte une phrase
  interdite et un `service.yaml` sans `disabled`).

**Pas de golden touché** à vérifier à l'implémentation : si un golden rend
l'écran Acompte, l'invite ou le bandeau, il est régénéré par le workflow
GitHub (Linux) et chaque PNG changé est regardé.

## 6. Accessibilité, perf, sécurité

- T2 est plus long : la table de `label_value_row_test.dart` porte la
  nouvelle chaîne (360/375/390 dp × 1×/2×).
- T3/T4 : texte de feuille et de bandeau, sans limite de lignes ; vérifié à
  200 %.
- Aucun impact perf ni sécurité ; aucune donnée, aucun secret.

## 7. Déploiement

- **Web** (T1, T5, T6) : en production au merge (Vercel).
- **App Pro** (T2, T3, T4) : au **prochain build**. Le 587 en TestFlight
  externe et rattaché à la 0.0.1 porte encore l'ancien texte — **au
  propriétaire** de dire s'il faut un nouveau build avant la soumission.
- **Stores** : rien à modifier (§1.5). Le jour où la messagerie s'allume,
  l'épingle échoue et oblige à revoir T1/T5/T6 *et* les fiches.

## 8. Suite — hors de cette tranche

**Prévenir le salon quand un client reporte** (backend : `SalonEvent` +
appel dans `reschedule.dart` pour le rôle `user`, push + fil, mêmes
destinataires que `newBooking`). C'est un vrai manque : un client déplace
son rendez-vous et le salon ne l'apprend qu'en regardant l'agenda. Une fois
construit, T3 peut redire « modifie » — l'épingle le signalera.

## 9. Questions ouvertes

1. ~~T1–T6 : le texte exact (§3), ou les variantes.~~ **Décidé le 2026-10-19 : les recommandations, toutes.**
2. Un nouveau build Pro avant la soumission App Store (§7) ?
3. « Support prioritaire dédié » (offre Business) — non vérifiable dans ce
   dépôt ; à confirmer par le propriétaire, hors de cette tranche.

## 10. Definition of done

- [ ] Texte validé (§3) ; spec passée à **Approved**.
- [ ] Épingles + tests vus **rouges** sur `main`, puis verts après correction.
- [ ] `flutter analyze` = 0 ; `flutter test` ciblé vert ; web : typecheck, lint, Vitest verts.
- [ ] PRD annoté ; entrée ROADMAP ; spec listée dans `docs/design/README.md`.
- [ ] Branche `fix/promise-honesty` + PR ; CI verte ; commits au nom du propriétaire, sans attribution Claude.
