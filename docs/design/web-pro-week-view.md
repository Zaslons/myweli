# Web Pro — l'onglet « Semaine » : la semaine du salon sur une grille, sur ordinateur — spec

| | |
|---|---|
| **Statut** | **Validé le 2026-10-20** — Q1 : **côte à côte + filtre « Artiste »** ; Q2 : **glisser vers un autre jour, oui** ; Q3 : **ordinateur seulement** ; Q4 : **les mots tels qu'écrits** (§9) |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-20 |
| **PRD ref / phase** | Journal (module journal) · web Pro, au-delà de l'app (décision du propriétaire, 2026-10-19 : « la bande et un onglet Semaine ») · V1 |
| **Module** | web Pro — `/pro/rendez-vous` (`RendezVousClient` : Journée, Calendrier, Liste → + Semaine), `JournalGrid` (réutilisé), `lib/pro/agenda-url.ts` |
| **Origine** | [web-pro-week-strip.md](web-pro-week-strip.md) Q1 (b) ; audit de parité §3 n° 6 |
| **Dépend de** | #648 (la bande de la semaine) — cette branche part de la sienne, donc de #645 et #644 |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-dev-guardrails ✓ · aucun changement serveur |

## 1. Ce qui existe

- **La Journée** (`JournalGrid`) : un axe des heures (les horaires du jour,
  pauses hachurées), **une colonne par artiste** (+ « Sans artiste »), la
  ligne « maintenant », un clic sur un rendez-vous → le panneau (accepter,
  refuser, arrivé, terminé, absent, acompte, « Voir le rendez-vous ») ; un clic
  dans le vide → « Nouveau rendez-vous » à ce jour, cette heure, cet artiste ;
  glisser un rendez-vous → le reprogrammer (heure et artiste ; le serveur
  refuse un créneau pris).
- **La bande de la semaine** (#648) au-dessus de la Journée : lundi →
  dimanche, un point de charge, un clic affiche le jour.
- **L'app** n'a pas de grille de semaine (le module journal l'a écartée sur
  téléphone). Cet onglet est un **plus du web**, pour l'ordinateur.

## 2. Le parcours proposé

- Un quatrième onglet, **« Semaine »**, entre « Journée » et « Calendrier »,
  **sur ordinateur** (Q3).
- En tête : ‹ « Semaine du 19 octobre » › et « Cette semaine » ; ← / → au
  clavier changent de semaine, T revient à celle-ci (les raccourcis de la
  Journée, à l'échelle de la semaine).
- **La grille** : l'axe des heures commun (du plus tôt ouvert au plus tard
  fermé de la semaine), **une colonne par jour** (« Lun 19 » … « Dim 25 »,
  aujourd'hui marqué comme dans la bande) ; un jour fermé est grisé et dit
  « Fermé » ; les pauses hachurées par jour ; la ligne « maintenant » dans la
  colonne d'aujourd'hui.
- **Plusieurs artistes le même jour** (Q1) : les rendez-vous simultanés se
  partagent la largeur de la colonne, côte à côte ; chaque bloc dit l'heure,
  le client et **l'artiste** ; un filtre **« Artiste »** (« Tous » par défaut,
  puis chaque artiste) réduit la grille à un seul.
- **Les gestes** (Q2) : clic sur un bloc → **le même panneau** que la
  Journée ; clic dans le vide → « Nouveau rendez-vous » à ce jour et cette
  heure (l'artiste filtré, sinon aucun) ; **glisser un bloc vers un autre jour
  ou une autre heure** → le reprogrammer (mêmes règles, même refus « Créneau
  indisponible. »).
- « Voir les annulés » s'applique ici aussi. Le Collaborateur voit sa semaine
  en lecture seule, comme sa Journée.
- **L'adresse** : `?vue=semaine&jour=AAAA-MM-JJ` (le lundi) — retour depuis
  une fiche, rechargement, Précédent : comme les autres vues (#645).

## 3. Les états

| État | La semaine |
|---|---|
| Chargement | l'en-tête, puis un squelette de grille |
| Erreur (un jour ou plus ne se lit pas) | la phrase d'erreur de section et « Réessayer » ; l'en-tête reste |
| Semaine vide | la grille vide (on peut cliquer pour créer) et, au-dessus, « Aucun rendez-vous cette semaine. » |
| Salon fermé toute la semaine | sept colonnes « Fermé » |

## 4. Les données

**Sept lectures de la Journée en parallèle** (`GET /providers/{id}/journal`,
une par jour) : les horaires du jour (fermetures et dates bloquées
comprises), les artistes, les rendez-vous enrichis que le panneau attend —
exactement ce que la Journée lit, sans changement serveur. Une demande de
semaine remplace la précédente (la dernière gagne, comme les jours de la
Journée). Une route « semaine » côté serveur pourrait venir plus tard si sept
lectures pèsent.

## 5. Accessibilité

Les blocs sont des boutons nommés (client, statut, **artiste**, **jour et
heure**) ; les zones vides sont des boutons « Créer un rendez-vous — Lun 19 »
(Q4) ; l'en-tête de jour est un en-tête ; le glisser-déposer a son équivalent
clavier (le panneau → « Voir le rendez-vous » → « Reprogrammer ») ; axe et
contrastes ceux de la Journée.

## 6. Les tests (rouges d'abord)

Pur : l'axe commun, la répartition des blocs simultanés en couloirs, le lundi
de la semaine, l'adresse. Composant : l'onglet, ‹ › et « Cette semaine », les
sept colonnes et « Fermé », le filtre, le clic → panneau, le clic vide →
nouveau rendez-vous à ce jour/heure, le glisser vers un autre jour → la
reprogrammation avec le bon instant (fuseau du salon), le refus qui revient,
la lecture seule. e2e : le parcours, axe, cibles, reflow (largeur
d'ordinateur) ; l'onglet absent sur téléphone.

## 7. Hors de cette tranche

Une route « semaine » côté serveur ; l'impression ; la semaine dans l'app.

## 9. Questions au propriétaire

- **Q1 — plusieurs artistes le même jour.** (a) **Une colonne par jour, tous
  les artistes ensemble, côte à côte, + un filtre « Artiste »** (recommandé) ;
  (b) une colonne par jour **et** par artiste (7 × N colonnes, très large) ;
  (c) un seul artiste à la fois (il faut en choisir un).
- **Q2 — glisser vers un autre jour.** (a) **Oui** (recommandé : c'est le
  geste qu'une semaine appelle) ; (b) pas dans cette tranche (clic et panneau
  seulement).
- **Q3 — sur téléphone.** (a) **L'onglet n'apparaît qu'à partir de la largeur
  d'un ordinateur** (recommandé ; sur téléphone, la bande + la Journée, comme
  l'app) ; (b) partout, avec une grille qui défile de côté.
- **Q4 — les mots** : l'onglet « Semaine » ; « Semaine précédente » /
  « Semaine suivante » (boutons ‹ ›, avec « Raccourci : ← / → ») ; « Cette
  semaine » ; « Semaine du 19 octobre » ; « Lun 19 » … ; « Fermé » ; le filtre
  « Artiste » et « Tous » ; « Aucun rendez-vous cette semaine. » ; les zones
  vides « Créer un rendez-vous — Lun 19 ».

**Décisions (2026-10-20).** Q1 (a), Q2 (a), Q3 (a), Q4 approuvé tel qu'écrit.
