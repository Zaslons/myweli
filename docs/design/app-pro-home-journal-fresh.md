# App Pro — « Accueil » et « Ma journée » restent à jour — spec

| | |
|---|---|
| **Statut** | **Brouillon** — questions au propriétaire : §8 |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-20 |
| **PRD ref / phase** | Journal + tableau de bord Pro (V1) |
| **Module** | app Pro — `ProSalonScope` (`core/access/pro_salon_scope.dart`), `ProJournalProvider`, `ProDashboardProvider`, `ProClientsProvider`, `ProAppointmentProvider` ; écrans « Accueil » (`dashboard_screen.dart`), « Ma journée », la fiche rendez-vous |
| **Origine** | [BACKLOG.md](../BACKLOG.md) lot 1 : B1.1, B1.2, B1.3 et les décisions 8, 9, 10 |
| **Prolonge** | [pro-journal-shows-new-booking.md](pro-journal-shows-new-booking.md) (#587) : une seule annonce, `ProSalonScope.bookingCreated`, entendue par chaque magasin qui montre des rendez-vous |
| **Skills checked** | myweli-dev-guardrails ✓ · aucun changement serveur, aucun changement web |

## 1. Le constat — relu sur le vrai chemin de code

**B1.1 — un statut changé ailleurs n'arrive ni dans « Ma journée » ni sur
« Accueil ».**
- La fiche rendez-vous change le statut par `ProAppointmentProvider`
  (`acceptAppointment`, `rejectAppointment`, `markComplete`, `markNoShow`,
  `pro_appointment_provider.dart:85-212`), puis se ferme
  (`pro_appointment_detail_screen.dart:268-380`). Ces quatre écritures ne
  corrigent que la liste de ce magasin. « Ma journée » (`ProJournalProvider`)
  et « Accueil » (`ProDashboardProvider`) n'en savent rien : la carte dit
  encore « En attente », et le compteur de demandes aussi, jusqu'à un
  glissement vers le bas.
- **Dans l'autre sens aussi** : les gestes de « Ma journée » (glisser, appui
  long, `pro_journal_provider.dart:177-209`) rechargent le jour, mais ni les
  chiffres d'« Accueil » ni la liste « Rendez-vous ». « Client arrivé » depuis
  la fiche passe par le magasin du jour et recharge la liste, pas « Accueil ».
- **Et un geste réussi peut finir sur une erreur** : après un geste, « Ma
  journée » recharge le jour par le chemin normal ; si ce rechargement échoue,
  `load()` vide le jour (`_day = null`) et l'écran montre « Une erreur est
  survenue », alors que le serveur a accepté le geste.
- Les services répondent `ApiResponse<bool>` : pas le rendez-vous à jour. Ce
  que l'on sait après un succès, c'est la transition elle-même (le serveur l'a
  confirmée).

**B1.2 — « Accueil » : une erreur sans issue, un glissement qui ne demande
rien.**
- Chiffres déjà là pour ce salon → `loadDashboardStats` rend la main sans
  rien demander au serveur (`pro_dashboard_provider.dart:36-44`), sauf après
  une création non confirmée. Le glissement vers le bas ne fait donc rien.
  Un test le fige comme « KNOWN DEFECT »
  (`test/unit/pro_dashboard_booking_created_test.dart:84`), en disant qu'il
  doit passer au rouge le jour de la réparation.
- Pas de chiffres et une erreur → un texte nu, `error ?? 'Aucune donnée
  disponible'` (`dashboard_screen.dart:185-194`) : pas de « Réessayer », hors
  du `BrandRefresh` (on ne peut même pas glisser), et `error` peut être le
  texte brut d'une exception (`e.toString()`).

**B1.3 — après un changement de salon pendant le chargement, « Accueil » peut
montrer les chiffres de l'autre salon.**
- Le chargement principal n'a pas de numéro de demande ;
  `resetForSalonSwitch` n'écarte que le rechargement discret. La réponse
  tardive du salon A, arrivée après celle du salon B, écrase les chiffres de B
  (revenus compris) — et le retour anticipé de B1.2 les garde ensuite.

**Le web** n'a pas ces défauts : ses pages lisent à l'arrivée, et le panneau
de la Journée recharge son jour après chaque geste. C'est l'app qui est en
retard.

## 2. Le parcours proposé

### 2.1 Une seule annonce pour un rendez-vous qui change (B1.1)

`ProSalonScope.bookingChanged(BookingChange)`, la sœur de `bookingCreated` :
l'identifiant, le salon, et ce qui a changé (`accepted`, `rejected`,
`completed`, `noShow`, `arrived`, `rescheduled` avec sa nouvelle date).

- **Qui l'annonce** : les écritures elles-mêmes, **après** le succès du
  serveur, jamais avant — les quatre de la fiche, et celles de « Ma journée »
  (accepter, refuser, terminé, absent, arrivé, reprogrammer). Pas chaque écran
  qui les appelle.
- **Comme pour `bookingCreated`** : un magasin qui lève une exception est noté
  dans le journal et sauté ; l'annonce ne peut pas faire croire à l'échec d'un
  geste réussi.
- **Qui l'entend** (`ShowsSalonBookings` gagne `bookingChanged`) :
  - **« Ma journée »** : la carte change **tout de suite** (le statut, le
    badge « Arrivé », un rendez-vous reprogrammé quitte le jour ou y entre), le
    point du jour aussi (un refus ne compte plus) ; puis le jour est relu
    **sans chargeur** — la réponse du serveur remplace la version locale, un
    échec la garde. Ses propres gestes passent par là : plus de « Une erreur
    est survenue » après un geste réussi.
  - **« Accueil »** : les chiffres sont au serveur de les calculer — ils sont
    redemandés sans chargeur ni état d'erreur (le chemin de `bookingCreated`) ;
    un échec les marque « à revoir » pour le prochain glissement.
  - **La fiche client** ouverte, si c'est le client de ce rendez-vous : relue
    sans chargeur (le compteur d'absences, les visites).
  - **La liste « Rendez-vous »** (`ProAppointmentProvider`) : la ligne
    corrigée, sans rechargement.

### 2.2 « Accueil » : le glissement demande toujours au serveur (B1.2)

`refresh(salonId)` :
- **chiffres à l'écran** → demande **sans chargeur** ; la réponse les
  remplace ; un échec **les garde** et le dit par un message en bas de l'écran
  (Q2) ;
- **pas de chiffres** → le chargement normal, avec son chargeur.

### 2.3 « Accueil » : un état d'erreur avec une issue (B1.2)

L'`EmptyState` de la maison, **dans** le `BrandRefresh` (on peut aussi
glisser), comme « Ma journée » : l'icône hors ligne, le titre, la phrase qui
dit pourquoi, « Réessayer » (§9). **Jamais** le texte brut d'une exception.

### 2.4 Le changement de salon (B1.3)

Un numéro sur le chargement principal (le motif de `ProJournalProvider`),
augmenté par `resetForSalonSwitch` et `clearStats` : une réponse dépassée est
écartée, son drapeau de chargement compris.

## 3. Les états d'« Accueil »

| État | Ce que voit le salon |
|---|---|
| Premier chargement | le chargeur |
| Chiffres | les chiffres |
| Glissement en cours, chiffres là | les chiffres, l'indicateur de glissement ; pas de chargeur plein écran |
| Glissement échoué, chiffres là | les chiffres gardés + le message (§9) |
| Échec sans chiffres | l'état d'erreur (§9), « Réessayer », glisser possible |
| Un rendez-vous change ailleurs | les chiffres redemandés en silence |
| Salon changé pendant un chargement | les chiffres du salon choisi, jamais ceux de l'autre |

## 4. Données, contrat

Aucun changement serveur ni de contrat : les lectures existantes
(`getDashboardStats`, `getJournalDay`, la fiche client). Le service fictif
simule déjà latence et échec ; il doit pouvoir répondre « pas de réponse »
(`code: 'network'`) pour les tests de §9.

## 5. Accessibilité

« Réessayer » est un `AppButton` (48 px) ; le message d'échec passe par
`AppSnackBar` (annoncé) ; l'état d'erreur reste glissable et lisible à 200 %.

## 6. Les tests (rouges d'abord)

- **Widget** : « Ma journée » → fiche → « Accepter » → retour : « Confirmé »
  et une demande de moins sur « Accueil » ; idem « Rejeter », « Marquer comme
  terminé », « Marquer comme absent ». Un geste de « Ma journée » → les
  chiffres d'« Accueil » relus.
- **« Ma journée »** : un geste réussi dont la relecture échoue → la carte
  corrigée reste, **pas** d'état d'erreur ; la relecture réussie remplace ;
  le point du jour suit (refus).
- **Magasins** : `bookingChanged` sur chacun (le jour, les chiffres, la fiche
  du bon client seulement, la liste) ; un magasin qui lève est noté et sauté ;
  un autre salon est ignoré.
- **« Accueil »** : le glissement demande au serveur (le test « KNOWN DEFECT »
  passe au rouge, puis est réécrit, comme il l'annonce) ; échec avec chiffres →
  gardés + le bon message (sans réponse / autre) ; échec sans chiffres →
  l'état d'erreur, « Réessayer », jamais de texte brut ; une réponse tenue
  pour le salon A arrive après B → les chiffres de B restent.
- **Golden** : l'état d'erreur d'« Accueil » (générés sur Linux par le
  workflow).
- **Mutations** à voir rouges : l'annonce avant le succès, un magasin oublié,
  le retour anticipé remis, le numéro de demande retiré, le texte brut remis.

## 7. Hors de cette tranche

- Le texte brut des exceptions **ailleurs** (la description d'erreur de « Ma
  journée » comprise) : lot 3 (B3.1).
- Une réponse d'écriture perdue : lot 2.
- Le web : déjà juste (§1).

## 8. Questions au propriétaire

- **Q1 (décision 8) — après « Accepter », « Rejeter », « Terminé » ou
  « Absent »** depuis la fiche : montrer le nouveau statut dans « Ma
  journée » **tout de suite**, puis relire en silence ? *Recommandé : oui, le
  serveur a déjà confirmé.* Et la même annonce pour « Client arrivé » et une
  reprogrammation, et dans l'autre sens (de « Ma journée » vers « Accueil »,
  la fiche client, la liste) ? *Recommandé : oui, même règle.*
- **Q2 (décision 9) — le glissement échoue alors que les chiffres sont à
  l'écran** : les garder et dire « Pas de connexion. Réessayez. » ?
  *Recommandé : oui.* Ou les remplacer par l'état d'erreur ?
- **Q3 (décision 10) — la course au changement de salon dans la même PR** que
  le glissement d'« Accueil » ? *Recommandé : oui, c'est la même fonction.*
- **Q4 — les mots** (§9) : uniquement des phrases que l'app et le web disent
  déjà.

## 9. Les mots (Q4)

- **Glissement échoué, chiffres gardés** (message en bas) : « Pas de
  connexion. Réessayez. » quand rien n'a répondu (la phrase des services de
  l'app) ; « Une erreur est survenue. Réessayez. » sinon (celle des
  notifications).
- **État d'erreur sans chiffres** : titre « Une erreur est survenue » ;
  phrase « Pas de connexion. Réessayez. » quand rien n'a répondu, aucune
  phrase sinon ; bouton « Réessayer » — comme « Ma journée », et comme le web
  (`ErrorState`, `loadFailureMessage`).
