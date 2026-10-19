# Web Pro — horaires en plusieurs plages et dates bloquées en lot — spec

| | |
|---|---|
| **Statut** | **Draft — en attente du feu vert du propriétaire (§8)** |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-19 |
| **PRD ref / phase** | Disponibilités du salon (FR-PRO-AVAIL) · parité web ↔ app · V1 |
| **Module** | web Pro — `/pro/disponibilites` (`DisponibilitesClient`, `DayHoursEditor`, `lib/pro/availability.ts`) |
| **Origine** | [parity-audit-web-pro-2026-10.md](parity-audit-web-pro-2026-10.md) §3 n° 2 (P1) |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-dev-guardrails ✓ · backend : **aucun changement** (lu seulement) |

## 1. Le constat — relu dans le code

### 1.1 Les horaires : une seule plage par jour sur le web

- **L'app** édite autant de plages qu'il faut par jour
  (`availability_screen.dart`, `_DayScheduleEditScreen` : « Ajouter un
  créneau », modifier, retirer, tri par heure de début, « Copier sur les
  autres jours » qui copie **toutes** les plages, avec confirmation).
- **Le web** n'en montre et n'en édite qu'**une** (`toEditable` prend
  `slots[0]`) ; les suivantes sont gardées **invisibles** à l'enregistrement
  (`toApi` : `.slice(1)`). Un salon fermé à midi (9 h–12 h et 14 h–18 h)
  voit « 9 h – 12 h » sur le web, ne voit pas l'après-midi, ne peut pas le
  changer.
- Le serveur accepte n'importe quel nombre de plages, chacune avec
  début < fin (`provider_catalog_service.dart:899-917`) ; il ne refuse **pas**
  deux plages qui se chevauchent — l'app non plus.
- Les **pauses** et les **horaires par employé** restent à une plage par
  jour : c'est aussi le cas dans l'app (`WeeklyHoursEditor`). Hors périmètre.

### 1.2 Les dates bloquées : une à la fois, passé accepté, sans confirmation

- **L'app** : « Gérer les dates bloquées » ouvre un calendrier
  multi-sélection (d'aujourd'hui à un an), un résumé (« 3 dates bloquées ·
  2 ajoutées »), « Enregistrer », puis **une confirmation qui nomme le sens**
  (bloquer / débloquer / les deux), puis l'écriture. Débloquer une date de la
  liste demande aussi confirmation. Les dates passées restent dans la liste
  avec leur bouton.
- **Le web** : un champ date (une date à la fois, **sans minimum** — une date
  passée s'ajoute), « Bloquer », « Retirer » sans confirmation ; le tout
  attend l'« Enregistrer » du bas de page.

### 1.3 ⚠️ Trouvé en route : la page plante si l'app a bloqué une date

- L'app écrit chaque date bloquée comme un instant (minuit **du salon** en
  UTC, `availability.dart:127` → `"2026-12-25T00:00:00.000Z"`) ; le web écrit
  `"2026-12-25"`. Le serveur stocke tel quel et lit les deux
  (`slot_service.dart:122` : jour du salon).
- Le web affiche chaque date avec `formatDateFr(\`${date}T12:00:00.000Z\`)`.
  Sur une date écrite par l'app, cela donne `"…000ZT12:00…"` → **`RangeError:
  Invalid time value`** (vérifié dans Node). La liste se rend à chaque
  affichage : **la page Disponibilités du web ne s'ouvre plus** pour un salon
  qui a bloqué une date depuis l'app. Le dédoublonnage (`includes`) rate aussi
  entre les deux formats.

## 2. Le parcours proposé

### 2.1 Horaires

Chaque jour : le nom, « Ouvert », puis **ses plages**, une par ligne :
`[début] à [fin]  Retirer` ; sous la dernière, **« Ajouter une plage »** ; et
« Copier sur les autres jours » (copie **toutes** les plages du jour, comme
l'app).

- Cocher « Ouvert » sur un jour sans plage en crée une : 09:00 – 18:00 (comme
  aujourd'hui). Décocher ferme le jour ; recocher retrouve ses plages.
- Nouvelle plage : commence **une heure après la fin de la précédente**, dure
  4 h, plafonnée à 23:00 (9 h–12 h → 13 h–17 h) ; si la précédente finit
  après 22 h, 22:00 – 23:00.
- « Retirer » la dernière plage d'un jour le **ferme** (pas de jour ouvert
  sans plage).
- À l'enregistrement : chaque plage début < fin (le message actuel), les
  plages d'un jour **ne se chevauchent pas** (nouveau, §3 H4 — le web le
  vérifie, l'app non), triées par heure de début.
- Les modèles (« Mar–Sam · 9h–18h »…) mettent **une** plage par jour ouvert,
  comme l'app ; une puce n'est allumée que si chaque jour a exactement cette
  plage.
- Une ligne d'aide sous le titre (§3 H5).

### 2.2 Dates bloquées — le flux de l'app

1. La carte liste les dates bloquées (passées comprises), chacune avec
   **« Débloquer »** ; vide : « Aucune date bloquée. »
2. **« Gérer les dates bloquées »** ouvre une boîte de dialogue « Jours
   bloqués » : un calendrier mensuel (lundi en premier), jours **d'aujourd'hui
   à un an** cliquables (avant : grisés), aujourd'hui marqué, les jours
   bloqués pleins ; ‹ › pour changer de mois. Chaque jour est un bouton
   bascule (`aria-pressed`) nommé par sa date.
3. Sous le calendrier, le résumé vivant de l'app (« Touchez les jours à
   bloquer. » / « 3 dates bloquées » / « Toutes vos dates bloquées seront
   retirées. », et « 2 ajoutées · 1 retirée ») ; « Annuler » / « Enregistrer ».
4. « Enregistrer » → **la confirmation de l'app**, qui nomme le sens ; puis
   **l'écriture immédiate** et la ligne de statut « 2 dates bloquées · 1 date
   débloquée ».
5. Fermer la boîte avec des changements → « Abandonner les modifications ? ».
6. « Débloquer » sur une ligne → sa confirmation → écriture immédiate.

**L'écriture des dates ne touche que les dates** : elle part de la dernière
version **enregistrée** (horaires, pauses, fenêtre, tampon) et n'y change que
`blockedDates`. Une modification des horaires non enregistrée reste en
attente de « Enregistrer » ; elle n'est ni écrite ni perdue.

**Le format** : les dates déjà stockées repartent **à l'identique** (aucune
réécriture) ; une date ajoutée par le web s'écrit comme l'app — minuit du
salon en UTC (`salonWallClockToUtc(jour, 0, tz)`). La lecture accepte les
deux formats (`"YYYY-MM-DD"` est un jour ; un instant devient le jour du
salon via `salonDayKey`) : **plus de plantage**, plus de doublon.

## 3. Le texte — à valider

Repris de l'app mot pour mot quand l'app a le geste ; **nouveau** sinon.

| # | Où | Texte |
|---|---|---|
| H1 | bouton sous les plages | **Ajouter une plage** *(nouveau ; l'app dit « Ajouter un créneau », mais « créneau » désigne ici les créneaux de réservation — voir la ligne CRENEAUX_COPY)* |
| H2 | bouton par plage | **Retirer** — nom accessible « Retirer la plage 2 du lundi » |
| H3 | champs (noms accessibles) | une plage : « Lundi début » / « Lundi fin » (inchangé) ; plusieurs : « Lundi, plage 2, début » |
| H4 | erreur à l'enregistrement | **« Lundi : deux plages se chevauchent. »** *(nouveau)* |
| H5 | aide sous « Horaires » | **« Fermé à midi ? Ajoutez une deuxième plage. »** *(nouveau)* |
| D1 | bouton de la carte | Gérer les dates bloquées *(app)* |
| D2 | titre de la boîte | Jours bloqués *(app)* |
| D3 | résumé | Touchez les jours à bloquer. · {n} date(s) bloquée(s) · Toutes vos dates bloquées seront retirées. · {n} ajoutée(s) · {n} retirée(s) *(app)* |
| D4 | boutons de la boîte | Annuler · Enregistrer |
| D5 | quitter avec des changements | Abandonner les modifications ? — Les dates que vous venez de choisir ne seront pas enregistrées. — Abandonner / Continuer *(app)* |
| D6 | confirmer | Bloquer cette date ? — Le {date}, votre salon n’acceptera aucune réservation. — Bloquer · Bloquer ces dates ? — Votre salon n’acceptera aucune réservation pendant ces {n} journées. — Bloquer {n} dates · Débloquer cette date ? — Le {date}, votre salon acceptera de nouveau des réservations. — Débloquer · Débloquer ces dates ? — … — Débloquer {n} dates · Modifier vos dates bloquées ? — {n} date(s) sera/seront bloquée(s) / débloquée(s) — Enregistrer *(app)* |
| D7 | statut après écriture | {n} date(s) bloquée(s) · {n} date(s) débloquée(s) *(app)* |
| D8 | bouton par ligne | **Débloquer** *(remplace « Retirer » ; le geste de l'app)* |
| D9 | échec | L’enregistrement a échoué. Réessayez. / Pas de connexion. Réessayez. *(existant)* |

## 4. Architecture

- `lib/pro/availability.ts` : le modèle des horaires devient **`DayRanges`**
  (`{ key, label, open, ranges: {start,end}[] }`) — `toEditable`, `toApi`,
  `validateHours`, `applyPreset`, `presetMatches`, `copyDayToAll` passent à
  plusieurs plages ; `nextRange`, `rangesOverlap`. `DayForm` (une plage)
  reste pour les pauses et les horaires d'employé, inchangés.
- Dates : `blockedDayKey(stored, tz)`, `toBlockedDates(current, added,
  removed, tz)` (les entrées non touchées à l'identique), `blockedDelta`.
- Composants : `WeekRangesEditor` (horaires), `BlockedDatesDialog` (sur le
  `Modal` partagé : piège du focus, Échap, retour du focus). Le web n'a pas
  de boîte de confirmation partagée et le `Modal` n'est pas fait pour
  s'empiler : **la confirmation est la deuxième étape de la même boîte**
  (calendrier → confirmation → écriture), et « Débloquer » sur une ligne
  ouvre un `Modal` de confirmation à lui.
- Aucun changement serveur ni de contrat.

## 5. États

- Chargement / erreur / succès de la page : inchangés.
- Écriture des dates : bouton occupé ; échec → la boîte reste ouverte avec
  le message (D9) sous les boutons, rien de perdu ; succès → la boîte se ferme,
  la liste se met à jour, la ligne de statut (D7) s'annonce (`role="status"`).

## 6. Accessibilité et mise en page

Cibles ≥ 48 px (jours du calendrier compris) ; focus visible ; chaque jour
nommé par sa date complète et son état (`aria-pressed`) ; résumé en région
vivante polie ; la boîte de dialogue piège le focus ; reflow à 320 px (les
plages passent à la ligne) ; texte 200 %.

## 7. Tests (rouges d'abord)

- Unitaires : plusieurs plages lues/écrites à l'octet près ; chevauchement
  refusé, plages contiguës acceptées ; nouvelle plage par défaut ; retirer la
  dernière ferme ; modèles et copie sur toutes les plages ; dates : les deux
  formats lus comme un jour du salon (UTC et UTC+1), entrées non touchées
  écrites à l'identique, nouvelles en minuit-salon-UTC.
- RTL : **la page s'ouvre avec une date écrite par l'app** (rouge
  aujourd'hui : elle plante) ; ajouter/retirer une plage puis enregistrer ;
  la boîte (passé grisé, sélection multiple, résumé, confirmation au bon
  sens, écriture immédiate qui ne touche que les dates, abandon) ;
  « Débloquer » avec confirmation.
- e2e : la page dans axe + la matrice de reflow, la boîte ouverte comprise.

## 8. Décisions à valider

1. **Le modèle des dates** : (A, recommandé) comme l'app — boîte de dialogue,
   confirmation, **écriture immédiate** des seules dates ; le reste de la page
   garde son « Enregistrer ». (B) les dates restent en attente du bouton du
   bas, sans confirmation.
2. **Le contrôle de chevauchement** (H4), que l'app n'a pas : oui (recommandé).
3. Le texte du §3 (H1–H5 nouveaux ; D1–D9 repris de l'app).
