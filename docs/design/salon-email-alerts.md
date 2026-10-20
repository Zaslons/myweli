# Alertes salon par e-mail — quand aucune notification de l'app ne peut arriver — spec

| | |
|---|---|
| **Statut** | **Construit le 2026-10-20** sur `feat/salon-email-alerts` (au-dessus de #642). Validé le 2026-10-19 — Q1 : **les e-mails tels qu'écrits** ; Q2 : **l'interrupteur tel qu'écrit, actif par défaut** ; Q3 : **la phrase ajoutée à la FAQ** (§9). Ce qui a été vu : §10 |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-19 |
| **PRD ref / phase** | Notifications salon (push-notifications-fcm §10) · parité web ↔ app Pro · V1 |
| **Module** | backend `SalonNotifier`, préférences de notification (`/me/notification-preferences`, migration `0039`) ; web Pro `/pro/notifications` (l'interrupteur) ; `/professionnels` (la FAQ) |
| **Origine** | [parity-audit-web-pro-2026-10.md](parity-audit-web-pro-2026-10.md) §3 n° 5 (P1) et §2 ligne 3 ; décision du propriétaire (2026-10-19) : **« les deux, l'e-mail d'abord »** — la notification du navigateur viendra dans une tranche à part |
| **Dépend de** | #642 (donc #639–#641) : les quatre événements (#640), la page Notifications web (#641) et la fiche qui change de salon par `?salon=` |
| **Skills checked** | myweli-backend-guardrails ✓ · myweli-web-guardrails ✓ · myweli-dev-guardrails ✓ |

## 1. Le constat — relu sur le vrai chemin de code

- Le serveur prévient l'équipe d'un salon de **quatre** événements
  (`SalonEvent` : nouvelle demande, report, annulation par le client,
  justificatif d'acompte) par **push de l'app** et une ligne du fil
  (`salon_notifier.dart`). Rien d'autre.
- Le web Pro relit le fil toutes les 60 s **tant que l'onglet est visible**
  (#641). Onglet fermé, ordinateur éteint : **un salon qui n'a pas l'app
  n'apprend rien** — ni la demande à accepter, ni l'annulation.
- L'infrastructure e-mail existe et sert déjà les salons : Resend, le budget
  « warm » (1 000/h, `send_budget.dart`), les avis d'abonnement au
  propriétaire (`subscription_emails.dart`, `subscription_scheduler.dart`).
  La ligne d'adhésion (`Member`) porte l'e-mail de chaque membre.
- `PushService.sendToUser` rend **le nombre de push acceptés** par FCM (0 :
  pas d'appareil, push coupé, ou échec).
- Les préférences de notification (`reminders`, `marketing`, `push`) sont par
  compte, en opt-out ; l'app Pro n'a **pas** d'écran de préférences (celui de
  l'app est celui du client).

## 2. La règle

Pour chaque destinataire de l'événement (la règle existante : les membres
actifs qui voient tout le planning, et le Collaborateur pour ses propres
rendez-vous) :

1. le push part comme aujourd'hui (s'il est permis) ;
2. **si aucun push n'a été accepté par l'app** (0 — un navigateur ne compte
   pas : [web-pro-browser-push.md](web-pro-browser-push.md) Q1) **et** que sa préférence
   « Alertes par e-mail » est active → **un e-mail** à l'adresse de sa ligne
   d'adhésion ;
3. la ligne du fil est écrite comme aujourd'hui.

Donc : un salon qui a l'app reçoit le push **et pas** l'e-mail (pas de double
alerte) ; un salon « web seulement » reçoit l'e-mail ; un push coupé ou un
appareil perdu retombe sur l'e-mail. **Par défaut : actif** (comme les autres
préférences, opt-out) — sinon les salons à qui il manque ne le sauraient
jamais (Q2).

## 3. L'e-mail

- **Pas de donnée client** (menace T58, comme le push) : ni nom ni téléphone ;
  le jour et l'heure **du salon** (son fuseau), le nom du salon (un
  propriétaire peut en avoir plusieurs).
- Le lien ouvre la fiche **sur le web**, dans le bon salon :
  `https://myweli.com/pro/rendez-vous/{id}?salon={salonId}` (la fiche change
  de salon, #641) ; il demande la connexion.
- Gabarit : celui des avis d'abonnement (logo, carte blanche, un bouton,
  pied de page), texte brut en alternative.
- Budget **warm** (un salon, à propos de ses propres rendez-vous).

| Événement | Objet | Texte (Q1) | Bouton |
|---|---|---|---|
| Nouvelle demande | « Nouvelle demande de réservation — {Salon} » | « Nouvelle demande de réservation le 21/10/2026 à 10:00. Acceptez-la ou refusez-la depuis votre Espace Pro. » | « Voir la demande » |
| Report | « Réservation reportée — {Salon} » | la phrase du push (#640) : « Le client a reporté le rendez-vous du 21/10/2026 à 10:00 au 22/10/2026 à 15:00. » | « Voir le rendez-vous » |
| Annulation | « Réservation annulée — {Salon} » | « Le client a annulé le rendez-vous du 21/10/2026 à 10:00. » | « Voir le rendez-vous » |
| Acompte | « Justificatif d’acompte reçu — {Salon} » | « Un justificatif d’acompte a été envoyé pour le rendez-vous du 21/10/2026 à 10:00. Vérifiez-le depuis votre Espace Pro. » | « Voir le justificatif » |

Pied de page, toujours : « Vous recevez cet e-mail parce qu’aucune
notification de l’app MyWeli Pro ne vous est parvenue. Pour ne plus le
recevoir : Espace Pro → Notifications. » (lien vers
`https://myweli.com/pro/notifications`).

## 4. L'interrupteur — web Pro, page Notifications

Sous la liste (comme « Préférences » du web client), une section :

- titre de section « Préférences » ;
- ligne « **Alertes par e-mail** », sous-titre : « Si une notification de
  l’app MyWeli Pro ne peut pas vous parvenir, nous vous écrivons à
  {adresse} : nouvelle demande, report, annulation, justificatif
  d’acompte. » ;
- l'interrupteur (`role="switch"`, nommé par le titre, cible 48 px) — **le
  même** que le web client, sorti dans un composant partagé (déplacé, pas
  copié) ;
- mise à jour optimiste ; en échec, il revient et dit « L’enregistrement a
  échoué. Réessayez. » ;
- chargement : la ligne apparaît quand les préférences sont lues ; échec de
  lecture : la phrase d'erreur et « Réessayer », la liste reste.

Chaque membre règle **ses** e-mails (la préférence est celle du compte). Pas
d'interrupteur dans l'app Pro : elle n'a pas d'écran de préférences, et un
appareil qui reçoit le push ne reçoit pas l'e-mail.

## 5. API, données, contrat

- Migration **`0039_notification_prefs_email_alerts`** :
  `ALTER TABLE notification_preferences ADD COLUMN email_alerts boolean NOT
  NULL DEFAULT true`.
- `NotificationPrefs.emailAlerts` ; `GET /me/notification-preferences` le
  renvoie ; `PUT` accepte `emailAlerts` (booléen, sinon 400
  `invalid_body`). Le client web et l'app client l'ignorent.
- BFF web Pro : `GET`/`PUT /api/pro/notification-preferences` →
  `/me/notification-preferences` avec la session Pro.
- `openapi.yaml` : le champ, dans le même PR.
- `SalonNotifier` reçoit l'`EmailProvider` ; `salon_alert_emails.dart` (les
  gabarits) à côté de `subscription_emails.dart`.

## 6. Sécurité, coûts, limites

- **Menaces** : aucune donnée client dans l'e-mail ; destinataires = la
  règle existante (aucune adresse fournie par un tiers) ; lien authentifié ;
  le nom du salon échappé dans le HTML. Lignes T58 et T24 du modèle de
  menaces (BACKEND.md §7) mises à jour.
- **Volume** : un e-mail par événement et par destinataire sans push. Plafond
  warm 1 000/h ; **à vérifier par le propriétaire : le quota mensuel du plan
  Resend**.
- Envoi après la réponse (`unawaited`, comme le push) : aucune latence pour
  le client ; sur Cloud Run, même exposition que le push.
- Pas de résumé groupé en V1.

## 7. `/professionnels`

La FAQ « Faut-il installer une application ? » peut le dire (Q3) :
« Non : réservations, agenda, clientèle, équipe et acomptes se gèrent depuis
myweli.com, sur ordinateur comme sur téléphone. Sans l’app, les alertes vous
arrivent par e-mail. »

## 8. Les tests (rouges d'abord)

- **Backend** : notifier — pas de push accepté + préférence active →
  e-mail (objet, texte, lien `?salon=`, sans nom ni téléphone) ; push accepté
  → pas d'e-mail ; préférence coupée → pas d'e-mail ; push coupé → e-mail ;
  Collaborateur seulement pour son artiste ; classe `warm` ; un e-mail qui
  échoue n'empêche ni le fil ni les autres destinataires. Préférences :
  défaut `true`, `PUT` partiel, 400 sur un non-booléen ; dépôt Postgres ;
  migration ; contrat.
- **Web** : BFF (session Pro) ; l'interrupteur (lecture, bascule, échec qui
  revient) ; e2e axe + cibles + reflow sur `/pro/notifications`.

## 9. Questions au propriétaire

- **Q1 — les e-mails** (§3) : objets, textes, boutons et pied de page tels
  qu'écrits ?
- **Q2 — l'interrupteur** (§4) : les mots, et **actif par défaut** ?
- **Q3 — la FAQ** (§7) : ajouter « Sans l’app, les alertes vous arrivent par
  e-mail. » ?

**Décisions (2026-10-19).** Q1, Q2 (actif par défaut) et Q3 : approuvés tels
qu'écrits.

## 10. Construit — ce qui a été vu

- **Rouge d'abord** : 14 tests du notifier (qui reçoit, ce que dit chaque
  e-mail, l'heure du salon, aucune donnée client, le nom du salon échappé),
  les préférences (dépôt, route, Postgres, contrat — dont une garde « le
  schéma est exactement ce que le serveur envoie »), et côté web le BFF,
  l'interrupteur (7 cas) et la FAQ.
- **Trouvé dans le navigateur** : la première version reprenait le cadre des
  avis d'abonnement — une carte fixe de 440 px plus 32 px de marge — et
  défilait de côté sur un téléphone (310 px de large, 440 de contenu). Refait
  sur le cadre de l'e-mail du code (`width="100%"`, `max-width:440px`, les
  marges dans les cellules) ; garde vue rouge sur la première version. **Les
  avis d'abonnement ont le même défaut** (hors de cette tranche).
- **Trouvé en construisant** : la référence « menace T25 » du notifier n'est
  pas celle de BACKEND.md (T25 y est l'abonnement) ; la bonne est **T58**,
  mise à jour avec le canal e-mail ; T24 dit « quatre champs ».
- **Le web avant le serveur** : une API qui n'envoie pas `emailAlerts`
  ignore aussi son écriture — la section ne s'affiche alors pas (plutôt qu'un
  interrupteur qui n'enregistrerait rien). **Ordre de déploiement : le
  serveur d'abord.**
- **Mutations vues rouges** : e-mail malgré un push accepté, préférence
  ignorée, envoi sans `try` par membre, HTML non échappé, la route qui perd
  le champ ou ne vérifie plus le booléen, le dépôt Postgres qui n'écrit pas
  la colonne (backend) ; le BFF qui transmet tout, la section montrée sur une
  API ancienne, pas de retour en arrière, la mauvaise valeur écrite (web) ;
  la cible de 32 px, la phrase sur une ligne, le BFF qui écrit toujours
  « actif » (e2e).
- **Vérifié** : backend — analyse 0, **1 779** tests + **85** Postgres
  (base locale neuve) ; web — typecheck et lint propres, **1 659** tests ;
  e2e (pro, axe, cibles, reflow, compte, accueil) **132** verts ; l'e-mail
  rendu et regardé à 310 px.
- **Non vérifié** : un vrai envoi Resend (le budget « warm » et le quota
  mensuel du plan restent à vérifier par le propriétaire) ; l'arrivée en
  boîte de réception (spam, rendu Gmail/Outlook).
