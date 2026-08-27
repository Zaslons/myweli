# Horaires : modèles, « Copier sur les autres jours », et la ligne créneaux — design spec

| | |
|---|---|
| **Status** | Built |
| **Module** | `availability` (pro) — [docs/MODULES.md](../MODULES.md) |
| **Surfaces** | App pro (`availability_screen.dart`) · Web pro (`DisponibilitesClient.tsx` + `DayHoursEditor.tsx`) |
| **Origin** | Curation feedback 2026-08-26 : « why don't we also give them samples they can directly choose from too instead of doing everything manually » + « et les créneaux, comment ça marche ? » |
| **Contract** | AUCUN changement — le `PUT /providers/{id}/availability` existant porte tout |

## 1. Goal & scope

Trois choses, toutes côté client, zéro backend :

1. **Modèles d'horaires** — trois points de départ réalistes qu'un salon
   applique en un geste puis ajuste, au lieu de saisir sept jours à la main.
2. **« Copier sur les autres jours »** — un jour réglé se propage aux six
   autres en un geste (app : depuis l'éditeur du jour, un seul PUT ; web :
   staged, persiste via « Enregistrer »).
3. **La ligne créneaux** — la section Horaires est la SEULE des quatre sans
   phrase explicative ; les salons demandent où « créer » les créneaux alors
   qu'ils sont dérivés. Une phrase le dit.

Hors scope : presets pour les Pauses (l'app n'a pas de copie côté pauses —
parité), presets personnalisés/sauvegardés (V2 si demandé), tout changement
serveur.

## 2. UX & flows

### Les trois modèles (chaînes IDENTIQUES app et web — parité pinnée)

| Label | Jours | Heures |
|---|---|---|
| « Mar–Sam · 9h–18h » | 1–5 (Mardi..Samedi) | 09:00–18:00 |
| « Lun–Sam · 8h–17h » | 0–5 | 08:00–17:00 |
| « Tous les jours · 9h–19h » | 0–6 | 09:00–19:00 |

Le tiret est le demi-cadratin « – » (pas l'ASCII « - ») et le séparateur le
point médian « · », l'idiome des chips A14d (`horizonLabel`).

- **Sélection honnête** : une chip est `selected` ssi l'emploi du temps
  courant correspond exactement au modèle (chaque jour du modèle = une seule
  plage aux bonnes heures, chaque autre jour fermé). Éditer un jour après
  application → plus aucune chip sélectionnée. Les chips sont des modèles,
  pas un état à trois valeurs.
- **App** : appliquer écrit les 7 jours (jours hors modèle → fermés) via UN
  `updateAvailability`. Si l'emploi du temps courant est non-vide et diffère,
  un confirm (« Appliquer ce modèle ? » / « Vos horaires actuels seront
  remplacés par {label}. Vous pourrez les ajuster ensuite. » / « Appliquer »)
  — la règle de l'écran : chaque écriture destructrice passe un confirm.
  Vide → application directe, pas de dialogue à vide.
- **Web** : appliquer est STAGED (`setDays`) comme tout le formulaire ;
  « Enregistrer » persiste. Pas de confirm — rien n'est écrit avant le save
  explicite, et l'annulation est un rechargement.

### « Copier sur les autres jours »

- **App** — dans `_DayScheduleEditScreen`, visible seulement si le jour a des
  créneaux (copier « fermé » sur toute la semaine est un piège, pas une
  fonctionnalité). `OutlinedButton.icon(Icons.copy_all)` sous les cartes de
  créneaux. Confirm (« Copier sur les autres jours ? » — le geste écrit six
  jours qu'on ne regarde pas), puis UN PUT : les 7 jours = les créneaux
  affichés (multi-plages comprises), snackbar « Horaires copiés sur tous les
  jours », pop.
- **Web** — `onCopyToAll?: (index) => void` optionnel sur les lignes de
  `DayHoursEditor` (bouton texte, visible sur une ligne ouverte). Staged :
  toutes les lignes prennent `{open, start, end}` de la ligne source.
  Branché sur les horaires du salon ET les horaires par artiste
  (`CatalogueClient` — même composant, même prop). Pas sur les Pauses
  (parité app). **Piège honoré** : le modèle web est une-plage-par-jour ;
  les plages supplémentaires d'un jour (préservées par `slice(1)` de
  `toApi`/`daysToSchedule`) SURVIVENT à la copie — la copie règle la
  première plage, comme toute édition web.

### La ligne créneaux

Sous le titre « Horaires de travail » (app) / « Horaires » (web), le même
français exactement :

> « Vos créneaux de réservation sont calculés automatiquement à partir de ces
> horaires et de la durée de chaque prestation. »

Style : l'idiome des trois autres sections (bodySmall/textSecondary app ;
`text-bodySmall text-textSecondary` web).

### États

Aucun nouvel état réseau : les trois ajouts s'appuient sur les flux
loading/error/success existants des deux écrans (chips → updateAvailability
app ; staged → save web). Erreur app = snackbar existante ; web = bandeau
existant.

## 3. API & contract

Aucun changement. `PUT /providers/{id}/availability` (app, wholesale) et le
même PUT via le BFF (web) portent déjà un `weeklySchedule` à 7 jours.

## 4. Data model

Aucun. Les modèles sont des constantes client :

- **App** : `WeeklySchedulePresets` dans `booking_horizons.dart`, à côté de
  `BookingWindowPresets` — même invariant testable (« aucun modèle ne peut
  produire fin ≤ début », jours ⊆ 0..6 non vides, labels uniques).
- **Web** : `SCHEDULE_PRESETS` + helpers purs (`applyPreset`,
  `presetMatches`, `copyDayToAll`) dans `lib/pro/availability.ts` — miroir
  champ à champ, unité-testé.

## 5. Architecture & patterns

App : chips = l'idiome `ChoiceChip`/`Wrap` de `_BookingWindowSection` ;
écriture = `updateAvailability(copyWith(weeklySchedule:))`, le canal du day
editor ; heures construites via `salonDateTime` (§18 — jamais
`DateTime(y,m,d,h)` local). Web : helpers purs + staged state, `toApi`
inchangé ; le nouvel état voyage DANS `obj` (le footgun `setBase` d'A14d
reste honoré).

## 6. Security & authz

Rien de nouveau : mêmes écritures, mêmes portes (`availability.manage`
serveur ; le client n'est jamais l'autorité).

## 7. Performance

Constantes + un PUT existant. Golden : `pro_availability_w360` change
(attendu — le harness A14d a été écrit « pour que la prochaine slice ait un
avant ») ; régénéré sur Linux.

## 8. Testing plan

- App unit : invariant des modèles (fin > début, jours valides, labels
  uniques, parité de chaîne pinnée) ; application → 7 jours écrits, jours
  hors modèle VIDES ; sélection honnête (match exact seulement).
- App widget : la ligne créneaux + les chips rendues ; copier-sur-les-jours
  → UN update couvrant les 7 jours.
- Web unit : `applyPreset` (7 lignes, off hors modèle), `presetMatches`
  (édition → false), `copyDayToAll` (open/start/end copiés, extras du base
  préservés au save — pin sur `toApi`).
- Web RTL : chips + ligne + bouton copier rendus ; préréglage staged puis
  save → PUT au bon shape.
- Mutations (contre le travail commité) : jours hors modèle non vidés ;
  copie n'écrivant que le jour source ; `presetMatches` toujours vrai ;
  chaîne créneaux dérivée/altérée d'un côté ; invariant cassé.

## 9. Rollout & scope discipline

Une PR (app + web), goldens régénérés dedans. Rejoint le lot versionCode 527
— pas d'upload Play dédié.

## 10. Definition of done

Gates maison des deux surfaces verts · golden regardé · mutations rouges ·
ROADMAP entry · ce spec en Built.

## 11. Open questions

Aucune — les trois modèles et leurs chaînes sont la décision propriétaire du
plan approuvé (« Resolved judgment calls »).
