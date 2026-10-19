# Le salon est prévenu quand un client reporte son rendez-vous — spec

| | |
|---|---|
| **Statut** | **Approved le 2026-10-19** — N1–N5 validés tels que recommandés : N2 avec l'ancienne **et** la nouvelle heure ; N3–N5 dans ce PR (l'ordre de déploiement du §8 tient) |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-19 |
| **PRD ref / phase** | FR-NOTIF (notifications transactionnelles) · V1 |
| **Module** | backend `messaging` (`SalonNotifier`), route `POST /appointments/{id}/reschedule` ; app Pro (invite push, bandeau, état vide des Notifications) |
| **ROADMAP entry** | à créer : `docs/roadmap/entries/2026-10-19-salon-client-reschedule-notify.md` |
| **Skills checked** | myweli-backend-guardrails ✓ · myweli-dev-guardrails ✓ · myweli-verification-guardrails (avant de dire « fait ») |
| **Dépend de** | [#639](https://github.com/Zaslons/myweli/pull/639) ([promise-honesty-sweep.md](promise-honesty-sweep.md)) — ses épingles relisent `enum SalonEvent` ; cette branche est empilée dessus |

## 1. Le constat

Relu sur `main` pour [promise-honesty-sweep.md](promise-honesty-sweep.md) §1.3 :

- Le client **peut** reporter : « Reporter » (`appointment_detail_screen.dart:550`
  → `reschedule_screen.dart`, et le web), accepté par
  `AppointmentLifecycleService.reschedule` pour son propre rendez-vous.
- `POST /appointments/{id}/reschedule` (`routes/appointments/[id]/reschedule.dart:71-77`)
  n'appelle que `BookingNotifier` → **le client** reçoit « Rendez-vous
  reporté ». `SalonNotifier` connaît `newBooking`, `clientCancelled`,
  `depositSubmitted` — rien pour un report.
- Donc le salon ne l'apprend qu'en regardant son agenda : le créneau libéré
  reste « occupé » dans sa tête, le nouveau arrive sans prévenir — un risque
  de rendez-vous manqué, et l'invite push de l'Accueil ne peut pas promettre
  « modifie » (#639 l'a retiré).

## 2. Le comportement

| | |
|---|---|
| **Événement** | `SalonEvent.clientRescheduled` |
| **Déclenché par** | `POST /appointments/{id}/reschedule`, **branche `user` seulement**, sur succès |
| **Jamais par** | la branche `provider` — un salon qui déplace son propre rendez-vous ne se prévient pas lui-même (même règle que la réservation manuelle, épinglée par test) ; un report refusé (409/403/404/400) |
| **Destinataires** | la règle unique de `_recipients` : membres **actifs** liés qui voient tout le journal + le Collaborateur dont c'est l'artiste. Le report client ne change jamais l'artiste (`_moveTo` sans `artistId`), donc l'artiste du rendez-vous déplacé suffit |
| **Préférences** | transactionnel (rappels/marketing ne s'appliquent pas) ; push soumis à la préférence `push` du compte ; **ligne de fil toujours écrite** |
| **Fil** | `type: reschedule` (existe déjà : `AppNotificationType.reschedule`, icône `event_repeat` ; enum OpenAPI déjà à jour) |
| **Push `data`** | `event: client_rescheduled`, `appointmentId`, `providerId`, `route: /pro/appointment/{id}?salon={providerId}` — la même forme que les trois autres |
| **Corps** | heure **du salon** (multi-pays §3), **aucune donnée client** (T58) — seulement des dates |

## 3. Le texte proposé — **à valider mot pour mot**

### 3.1 La notification (push + fil)

| # | | **Proposé (recommandé)** | Variante |
|---|---|---|---|
| **N1** | Titre | **Réservation reportée** | — (la famille salon : « Nouvelle réservation », « Réservation annulée ») |
| **N2** | Corps | **Le client a reporté le rendez-vous du 27/06/2026 à 10:00 au 28/06/2026 à 15:30.** | **B** — sans l'ancienne heure : « Le client a reporté le rendez-vous au 28/06/2026 à 15:30. » |

- N2 calque « Le client a annulé le rendez-vous du 28/06/2026 à 14:30. »
  L'ancienne heure dit au salon **quel créneau se libère** sans ouvrir l'app ;
  le corps ne porte aucun nom (T58), donc c'est aussi ce qui identifie le
  rendez-vous.
- Si l'ancienne date manque ou ne se lit pas : la variante B. Si la nouvelle
  manque : « Le client a reporté un rendez-vous. »
- Coût de N2 : la route ne connaît pas l'ancienne date (`LifecycleResult`
  rend le rendez-vous **déplacé**). `reschedule` (client) rend un record à
  lui, `RescheduleResult`, qui ajoute `previousAppointmentDate` — lu par le
  service, qui a déjà le rendez-vous en main ; aucune lecture de plus, la
  route ne touche pas au stockage. La variante B n'a pas besoin de ce
  changement.

### 3.2 Ce que l'app Pro peut alors promettre

| # | Surface | Aujourd'hui (#639) | **Proposé** |
|---|---|---|---|
| **N3** | Invite push de l'Accueil (`dashboard_screen.dart`) | Soyez prévenu·e dès qu’un client réserve, annule ou envoie son acompte, et ne manquez aucune demande. | **Soyez prévenu·e dès qu’un client réserve, reporte, annule ou envoie son acompte, et ne manquez aucune demande.** |
| **N4** | Bandeau « notifications désactivées » (Notifications Pro) | …pour être prévenu·e des réservations, annulations et acomptes de vos clients. | **…pour être prévenu·e des réservations, reports, annulations et acomptes de vos clients.** |
| **N5** | État vide des Notifications Pro | Les réservations, annulations et acomptes de vos clients apparaîtront ici. | **Les réservations, reports, annulations et acomptes de vos clients apparaîtront ici.** |

« Reporte » / « reports » : le mot du bouton du client (« Reporter ») et du
push client (« Rendez-vous reporté »), plutôt que « modifie » — un client ne
peut **que** déplacer l'heure, pas changer ses prestations.

## 4. Architecture

- `salon_notifier.dart` : `SalonEvent.clientRescheduled` ; `notify(appointment,
  event, {String? previousAppointmentDate})` — le paramètre ne sert qu'à ce
  corps ; titre, corps, `_eventName`, `_feedType`.
- `appointment_lifecycle_service.dart` : `typedef RescheduleResult` (les trois
  champs de `LifecycleResult` + `previousAppointmentDate`) rendu par
  `reschedule` (client) ; `rescheduleByProvider` et `_moveTo` inchangés.
- `reschedule.dart` : la branche `user` appelle aussi `SalonNotifier`
  (`unawaited`, comme `cancel.dart`) ; la branche `provider` non.
- Aucun endpoint, aucun DTO, aucune migration ; `openapi.yaml` inchangé
  (`reschedule` est déjà un type de notification).

## 5. Sécurité

- Pas de nouvelle surface : la route garde son authentification et sa
  propriété (le client ne reporte que **son** rendez-vous ; le salon est
  résolu depuis le rendez-vous, pas depuis la requête).
- T58 : le corps ne porte que deux dates et deux heures.
- Pas d'auto-notification : un salon qui déplace son rendez-vous n'appelle
  pas `SalonNotifier` — épinglé.
- **Modèle de menaces** : la ligne **T58** de [BACKEND.md](../BACKEND.md) §7
  (« new booking / client cancel / deposit proof ») gagne « client reschedule »,
  avec sa garde (pas d'auto-notification). Le commentaire de
  `salon_notifier.dart` qui cite « T25 » pour l'absence de PII est corrigé en
  T58 (T25 est l'abonnement).

## 6. Les épingles de #639

`promise_honesty_pin_test.dart` et `promise-honesty-pin.test.ts` relisent
`enum SalonEvent` : elles **échoueront exprès** (« re-décidez »). La
re-décision : la famille « report » disparaît (« annule ou modifie » n'est
plus une promesse fausse), et le test de fait **s'inverse** — il exige
désormais un événement de report, puisque N3–N5 le promettent. Si quelqu'un
retire l'événement, les deux épingles rougissent.

## 7. Tests (rouges d'abord)

- `salon_notifier_test.dart` : titre, corps N2 à l'heure du salon
  (Libreville = UTC+1), `type: reschedule`, `event: client_rescheduled`,
  route ; repli B sans ancienne date ; aucun identifiant client ; destinataires
  (Collaborateur de l'artiste oui, autre artiste non).
- `appointment_lifecycle_test.dart` : `reschedule` rend
  `previousAppointmentDate` = l'ancienne date ; route client → `SalonNotifier`
  appelé une fois avec `clientRescheduled` et l'ancienne date ; route salon →
  jamais ; report refusé → jamais.
- App : `pro_notifications_test.dart` (N4, N5) ; les épingles inversées.

## 8. Déploiement — l'ordre compte

L'app Pro promettra « reporte » (N3–N5) : **le serveur doit être en
production avant que le build Pro qui porte ce texte n'atteigne quiconque.**
Le déploiement du backend est une décision du propriétaire (jamais sans
accord) ; le build Pro suivant aussi. Si l'ordre ne peut pas être tenu,
séparer N3–N5 dans un PR suivant.

## 9. Questions ouvertes

1. ~~N1–N5 : le texte exact, N2 ou sa variante B.~~ **Décidé le 2026-10-19 : N2 (ancienne → nouvelle heure), N3–N5 dans ce PR.**
2. Le web Pro n'a pas de centre de notifications (écart de parité préexistant,
   hors de cette tranche).

## 10. Definition of done

- [ ] Texte validé (§3) ; statut **Approved**.
- [ ] Tests vus rouges, puis verts ; `dart analyze --fatal-infos` 0 ; format ; `flutter analyze` 0.
- [ ] [push-notifications-fcm.md](push-notifications-fcm.md) §10 à jour ; entrée ROADMAP ; spec indexée.
- [ ] PR empilé sur #639 ; CI verte ; commits au nom du propriétaire, sans attribution Claude.
