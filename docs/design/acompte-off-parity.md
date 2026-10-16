# Acompte — désactiver les acomptes n'efface plus la politique, et 0 % veut dire « pas encore choisi » — spec

| | |
|---|---|
| **Statut** | **Approuvé le 2026-10-16** (propriétaire : « merge 615, then fix the web Acompte gap » ; sur le 0 % de l'app : « Fix both, propose 30% ») |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-16 |
| **PRD ref / phase** | Protection anti-no-show (acompte Pro) · V1 — partie [pro-deposit-policy.md](pro-deposit-policy.md) |
| **Module** | `payments` (politique d'acompte du salon) |
| **ROADMAP entry** | [2026-10-16-acompte-off-parity.md](../roadmap/entries/2026-10-16-acompte-off-parity.md) |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-dev-guardrails ✓ (pas de changement serveur — le contrat ne change que dans sa description) |

## 1. Les défauts, vus dans le code

`PUT /providers/{id}/deposit-policy` **remplace la politique entière** :
le serveur enregistre exactement ce qu'il reçoit
(`ProviderCatalogService.updateDepositPolicy`). Ce qu'un client n'envoie pas,
il l'efface.

**D1 — le web efface l'opérateur et le pourcentage quand les acomptes sont
désactivés.** `buildDepositPayload` (`web/lib/pro/deposit.ts`) envoie
`mobileMoneyOperator: null` et `depositPercentage: 0` dès que l'interrupteur
est sur « non ». L'app envoie les deux tels quels
(`ProDepositSettingsProvider.save`). Le numéro, lui, est déjà gardé depuis
[phone-leftovers.md](phone-leftovers.md) §6. Ce que l'effacement casse :

- **Un client qui doit encore son acompte.** La lecture d'un rendez-vous sert
  l'opérateur et le numéro de la politique **actuelle** du salon
  (`appointment_enrichment.dart`, `depositMobileMoneyOperator`), et c'est
  là que le client lit où envoyer l'argent (`DepositProof` sur le web,
  `deposit_payment_sheet` dans l'app). Si le salon désactive les acomptes
  depuis le web, ce client perd le nom de l'opérateur et le lien « Payer avec
  Wave » (il exige l'opérateur).
- **Le retour aux acomptes.** Le web réaffiche « 0 » et « — Choisir — » : le
  salon ressaisit tout. L'app tombe sur D2.

**D2 — l'app ne sait pas lire 0 %.** Tout nouveau salon est créé avec
`depositPercentage: 0.0` (`providers_repository.dart`), et D1 en écrit
d'autres. `load` copie ce 0 : le libellé dit « 0 % » et le curseur est dessiné
à 5 % (`clamp(0.05, 0.80)`). Le salon active les acomptes, ne touche pas au
curseur, enregistre : le serveur refuse (`depositRequired && pct <= 0` →
`invalid_input`), et l'écran affiche « Informations invalides. » dans une
barre, sans dire ce qui ne va pas.

**D3 — le web prend un échec de chargement pour une politique vide.**
`setForm(depositToForm(dp.status === 200 ? dp.policy : undefined))` : un 403,
un 500 ou un 502 affiche un formulaire vierge (acomptes désactivés, pas de
numéro, pas d'opérateur, 24 h). Si le salon enregistre ce formulaire, sa vraie
politique est écrasée. Une coupure réseau fait lever le `fetch` dans le chargement : la
promesse est rejetée sans être gérée et le chargement tourne pour toujours. L'app
affiche un état d'erreur avec « Réessayer » (`loadFailed`).

## 2. Décisions

1. **Le web envoie ce qu'il tient, quel que soit l'interrupteur** — comme
   l'app. Opérateur : la valeur choisie, ou `null` si aucune. Pourcentage :
   la valeur du champ si elle est valide (1–100) ; sinon — le champ est caché
   quand les acomptes sont désactivés, et une faute que le salon ne voit pas ne
   doit ni bloquer ni modifier l'enregistrement — **le dernier pourcentage
   chargé ou enregistré**.
2. **0 % veut dire « pas encore choisi » ; le formulaire propose 30 %** (choix
   du propriétaire). 30 % est déjà la valeur de départ de l'app
   (`ProDepositSettingsProvider`, initiale et changement de salon) ; elle
   devient une constante nommée de chaque côté — `kDefaultDepositPercentage`
   (app, `core/utils/deposit.dart`) et `DEFAULT_DEPOSIT_PERCENT` (web,
   `lib/pro/deposit.ts`) — et un test croisé garde les deux d'accord. Aucune
   migration : la règle couvre les nouveaux salons et ceux que D1 a déjà
   écrits. Aucun changement serveur : le serveur dit ce qui est stocké ; c'est
   au formulaire de proposer.
3. **Le web n'affiche plus de formulaire sur un chargement raté** : tout échec
   (réponse non 200, ou exception) passe par l'`ErrorState` existant et son
   « Réessayer », comme un échec de `getMyProvider` aujourd'hui.

Conséquence voulue de 1 + 2 : un salon qui n'avait jamais choisi et qui
enregistre avec les acomptes désactivés stocke désormais 30 % au lieu de 0. Sans effet
sur les réservations (`BookingService` ne lit le pourcentage que si
`depositRequired`).

## 3. UX

Aucun texte nouveau, aucun composant nouveau.

- **Web** : le champ « Pourcentage de l’acompte (%) » affiche `30` quand rien
  n'a été choisi. Désactiver puis enregistrer ne change rien de visible ;
  réactiver retrouve l'opérateur et le pourcentage. Un chargement raté montre
  l'`ErrorState` « Acompte » avec « Réessayer » au lieu d'un formulaire.
- **App** : le curseur est à 30 % et le libellé dit « 30 % » quand rien n'a
  été choisi ; activer puis enregistrer sans toucher au curseur réussit.

## 4. Contrat

`docs/api/openapi.yaml`, description du `PUT` (et `web/lib/api/schema.ts`
régénéré) : la politique est remplacée entière — un client qui cache
l'opérateur ou le pourcentage quand les acomptes sont désactivés les envoie
quand même, sinon il les efface (et la lecture d'un rendez-vous sert
l'opérateur actuel au client qui doit encore son acompte) ; un nouveau salon
part de `depositPercentage: 0`, que les clients lisent « pas encore choisi ».
Aucun champ, aucun code d'erreur ne change.

## 5. Tests (rouges d'abord, contre le code d'avant)

- **Web, unité** (`tests/pro-profile.test.ts`) : désactivé → la charge utile
  garde opérateur et pourcentage ; désactivé avec un pourcentage caché
  invalide → le dernier pourcentage chargé ou enregistré ; `depositToForm` : 0 ou absent → `'30'`,
  0.4 → `'40'`. L'ancienne assertion « désactivé → `null` / `0` » est
  inversée.
- **Web, composant** : un `GET deposit-policy` non 200 → l'`ErrorState`, pas
  de formulaire ni de bouton « Enregistrer » ; un `fetch` qui lève → pareil ;
  « Réessayer » recharge.
- **Croisé** : un test web lit `mobile/lib/core/utils/deposit.dart` (commentaires
  retirés) et exige `kDefaultDepositPercentage = 0.30` ↔
  `DEFAULT_DEPOSIT_PERCENT = 30`.
- **Web, e2e** (`pro.spec.ts`, bouchon qui stocke le corps du PUT comme le
  serveur) : acomptes activés (opérateur, pourcentage, numéro) → désactiver
  → enregistrer → recharger → réactiver : opérateur et pourcentage
  retrouvés.
- **App, unité** (`pro_deposit_settings_provider_test.dart`) : `load` d'un 0
  → 0.30 ; d'un 0.5 → 0.5 ; `save` désactivé envoie l'opérateur et le
  pourcentage tenus.
- **App, widget** (`deposit_settings_screen_test.dart`) : politique stockée
  à 0 → « 30 % » à l'écran ; activer puis enregistrer sans toucher au curseur
  envoie 0.30.
- **Mutations** : chaque nouvelle garde doit tomber rouge quand on remet
  l'ancienne ligne.

## 6. Déploiement

Web au merge (Vercel). App au prochain build. Serveur : rien à déployer.

**Ce qui existe déjà** : un opérateur effacé par D1 ne peut pas être
retrouvé (on ne sait pas lequel c'était). Le service n'est pas encore public :
les seules lignes touchées sont des données de test. Le serveur et les deux
formulaires exigent de nouveau un opérateur dès qu'un salon réactive les
acomptes. Un pourcentage effacé devient sans effet avec la décision 2.

## 7. Hors périmètre, consigné

- **Plages** : le curseur de l'app va de 5 à 80 %, le champ web de 1 à 100 %,
  le serveur de 0 à 100 %. Un 90 % saisi sur le web s'affiche « 90 % » dans
  l'app avec le curseur dessiné à 80 %.
- **Opérateur retiré du catalogue du pays** : le serveur refuse tout
  l'enregistrement (`invalid_input`), acomptes activés ou non, sur les deux
  surfaces.
