# Web Pro — la semaine au-dessus de la Journée (la bande des sept jours de l'app) — spec

| | |
|---|---|
| **Statut** | **Validé le 2026-10-19** — Q1 = **la bande maintenant, l'onglet « Semaine » (grille de sept jours sur ordinateur) en tranche à part** ; Q2 = **sans les annulés, web et app** ; Q3 = **les mots tels qu'écrits** (§8) |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-19 |
| **PRD ref / phase** | Journal (module journal §4.3) · parité web ↔ app Pro · V1 |
| **Module** | web Pro — `/pro/rendez-vous`, vue Journée (`RendezVousClient`) ; app Pro — `ProJournalProvider` (les points de la semaine) |
| **Origine** | [parity-audit-web-pro-2026-10.md](parity-audit-web-pro-2026-10.md) §3 n° 6 (P1) et §2 ligne 1 |
| **Dépend de** | [#645](https://github.com/Zaslons/myweli/pull/645) (le jour dans l'adresse) — cette branche part de la sienne, donc de #644 |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-dev-guardrails ✓ · aucun changement serveur, aucun contrat |

## 1. Le constat — relu sur le vrai chemin de code

- **Ce que « semaine » veut dire dans l'app.** Pas de grille de sept jours :
  sous la date de « Ma journée », une **bande de sept jours** (lundi →
  dimanche de la semaine du jour affiché), chaque jour avec sa lettre, son
  numéro et **un point dont la longueur dit la charge**. Un appui affiche ce
  jour (`pro_journal_screen.dart:611,620-704`). C'est un choix du module :
  « Week strip above (dots = load density) for context **without a week
  grid** » (`docs/modules/journal.md` §4.3 ; `journal-j1b-app.md:54-57`).
- **Le web n'a rien de tel.** La Journée a ‹, le champ date, ›, « Aujourd’hui »
  et c'est tout (`RendezVousClient.tsx:294-344`). Pour savoir quel jour de la
  semaine est chargé, un salon doit passer au Calendrier (des points
  oui/non, sans charge) ou avancer jour par jour.
- La promesse « Vue journée, **semaine** » a déjà été retirée de
  `/professionnels` (#642). Cette tranche ne la remet pas : une bande n'est
  pas une vue semaine, et le module n'en veut pas.
- **En passant, côté app** : les points comptent **tous** les rendez-vous du
  jour, annulés compris (`pro_journal_provider.dart:300,306` —
  `appointments.length` du jour, que le serveur renvoie « every status »,
  `journal_service.dart:59`) alors que la journée **cache** les annulés par
  défaut (`:107-113`). Un jour qui n'a plus qu'un rendez-vous annulé garde
  son point et s'ouvre vide (Q2).

## 2. Le parcours

1. Le salon ouvre la Journée : **sous** la ligne ‹ date › « Aujourd’hui »,
   **au-dessus** de la grille, la bande de la semaine du jour affiché.
2. Chaque jour : l'abréviation (« Lun », « Mar », … « Dim » — celles du
   Calendrier web), le numéro, et un point qui **s'allonge avec le nombre de
   rendez-vous** (1 à 5 et plus ; rien à 0), comme l'app.
3. **Le jour affiché** est plein (fond `primary`, texte `secondary` — le jour
   choisi du Calendrier) ; **aujourd'hui**, s'il n'est pas affiché, a
   l'anneau du Calendrier (`ring-1 ring-primary`).
4. Un clic sur un jour **affiche ce jour** : le même chemin que ‹ › et le
   champ date. L'adresse suit (`?jour=`, #645), Précédent quitte la page
   (l'adresse est remplacée, pas empilée).
5. ‹ › (et ← → au clavier) qui franchissent lundi ou dimanche **changent de
   semaine** : la bande suit toujours le jour affiché. Pas de « semaine
   précédente / suivante » : l'app n'en a pas, le champ date saute où l'on
   veut.

**Ce qui ne change pas** : la grille, le panneau, « Voir les annulés », le
Calendrier, la Liste, les raccourcis.

## 3. Les états

| État | La bande |
|---|---|
| Chargement de la page | rien (le squelette de la page) |
| Chargement d'un jour | la bande **reste** (elle ne dépend pas du jour chargé), le squelette est dessous |
| Erreur du jour | la bande reste ; l'erreur de section dessous (on peut cliquer un autre jour) |
| Semaine vide | sept jours sans point |
| Collaborateur (lecture seule) | la même bande, ses rendez-vous seulement (le serveur filtre déjà la liste **et** la journée de la même façon : `appointments/index.dart:62-70`, `journal_service.dart:41-47,66`) |

## 4. D'où viennent les nombres — sans requête de plus

- **Les autres jours** : la liste des rendez-vous du salon que la page charge
  déjà pour le Calendrier et la Liste (`listProAppointments`), comptée par
  **jour du salon** (`apptDayKey`, son fuseau).
- **Le jour affiché** : la journée chargée elle-même (comme l'app,
  `pro_journal_provider.dart:298-301`) — elle est relue après chaque action de
  la grille (création rapide, accepter, annuler…), la liste non : le point du
  jour affiché est donc toujours juste.
- L'app fait sept requêtes ; le web n'en fait **aucune** de plus.

## 5. Accessibilité (WEB-SYSTEM §4–§8, SYSTEM §13)

- Un `role="group"` nommé « Semaine du 20 octobre » (le lundi), sept
  `<button>` avec `aria-pressed` (le jour affiché) — le motif de `Tabs`.
- **Le nom de chaque bouton contient ce qu'on voit** (WCAG 2.5.3) : « Lun 20 »
  visible, puis, pour les lecteurs d'écran seulement, « octobre, 3
  rendez-vous » (« aucun rendez-vous » à 0) et « aujourd’hui » le cas
  échéant. Le point est `aria-hidden` : sa longueur n'est pas la seule
  information (le nombre est dans le nom).
- **Cibles** : les sept boutons se partagent la largeur sans espace entre eux
  (le `Expanded` de l'app) → ≥ 48 px à 375 px (mesuré dans `tap-targets`) ;
  ~41 px à 320 px, comme l'app (« ≥48 on normal widths ») et au-dessus des
  24 px de WCAG 2.5.8.
- **Texte à 200 %** et 320 px : la bande ne déborde pas (matrice
  `type-overflow`). Anneau de focus visible.

## 6. L'app (Q2 = « sans les annulés »)

`ProJournalProvider._prefetchWeekCounts` compte les rendez-vous **non
annulés** du jour (les deux lignes `:300` et `:306`). Rien d'autre : la
journée, le Calendrier et la Liste de l'app ne changent pas. Les Calendriers
(app et web) gardent leur point « il y a quelque chose ce jour-là » : leur
liste du jour **montre** les annulés, leur point est donc juste.

## 7. Les tests (rouges d'abord)

- **Unitaire (pur)** `lib/pro/week-strip.ts` : la semaine (lundi → dimanche)
  d'un jour, y compris à cheval sur deux mois et deux années ; les comptes par
  jour du salon (un rendez-vous à 23 h 30 à Abidjan, à 00 h 30 ailleurs) ; le
  jour affiché compté depuis la journée ; les annulés (Q2) ; la
  longueur du point (0, 1, 5, 9).
- **Composant** : la bande sous la date ; un clic affiche le jour (la grille
  est relue pour ce jour) ; ‹ un lundi → la semaine d'avant ; `aria-pressed` ;
  le nom « Lun 20 octobre, 3 rendez-vous » ; la bande reste pendant le
  chargement et l'erreur d'un jour.
- **App (Q2)** : `pro_journal_booking_created_test` ou voisin — un jour
  dont le seul rendez-vous est annulé n'a pas de point.
- **e2e** : le parcours Pro (cliquer un jour de la bande → la grille et
  l'adresse suivent) ; axe, reflow (320 px, 200 %), cibles (375 px).

## 8. Questions au propriétaire

- **Q1 — la portée.** (a) **La bande, comme l'app** (recommandé : c'est ce
  que l'app appelle sa semaine, et le module a écarté la grille) ; (b) la
  bande **et** un onglet « Semaine » (une grille de sept jours sur
  ordinateur) — une tranche à part, plus grosse, que l'app n'a pas.
- **Q2 — les annulés dans les points.** (a) **Sans les annulés, web et app**
  (recommandé : le point dit la charge, et la journée cache les annulés par
  défaut) ; (b) comme l'app aujourd'hui (tous les statuts), sur le web aussi.
- **Q3 — les mots.** Visible : « Lun 20 » … « Dim 26 » (rien de nouveau).
  Lecteurs d'écran : le groupe « Semaine du 20 octobre » ; chaque jour
  « Lun 20 octobre, 3 rendez-vous » / « …, aucun rendez-vous », et
  « …, aujourd’hui » pour aujourd'hui.

**Décisions (2026-10-19).** Q1 : (b) — **cette tranche livre la bande** ;
l'onglet « Semaine » est une tranche à part, avec sa propre spec (ce que la
grille montre par artiste, le glisser-déposer entre jours, les petites
largeurs). Q2 : (a). Q3 : approuvé tel qu'écrit.
