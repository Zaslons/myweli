# Un numéro ivoirien a 10 chiffres — partout où l'on saisit un téléphone — spec

| | |
|---|---|
| **Statut** | **Approuvé le 2026-10-15** (propriétaire : « Do this task here: Reject short Ivorian numbers at the phone step ») — en construction sur `fix/phone-national-length` |
| **Module** | transverse — formulaires (SYSTEM.md §14) · données de marché (SYSTEM.md §18, [multi-pays.md](../modules/multi-pays.md) §6/§9) · identité (T34) |
| **Origine** | Vu sur le simulateur le 2026-10-15 (essai de #601) : l'étape « Votre numéro de téléphone » de l'app client a accepté `+2250700000` — 7 chiffres après +225 — et l'a enregistré. |
| **Régit** | `mobile/lib/core/utils/phone_numbering.dart` (nouveau seam §18) · `mobile/lib/core/utils/validators.dart` (`phoneNumber`) · `mobile/lib/widgets/common/phone_number_field.dart` · les 9 écrans de saisie (§2) · `backend/lib/src/localities/phone_numbering.dart` (nouveau, dans le seam existant) · `backend/lib/src/validators.dart` · les 11 sites `isValidE164` + `POST /me/salons` · `web/lib/phone.ts` (nouveau) et les 9 formulaires web (§2) · `docs/api/openapi.yaml` |
| **Skills consultés** | myweli-dev-guardrails · myweli-backend-guardrails · myweli-web-guardrails · myweli-verification-guardrails |

## 1. Ce qui ne va pas, vérifié

Relevé par une cartographie en lecture seule (app, backend, web, politique) et
son critique de complétude ; 13 affirmations relues à la ligne citée.

1. **Une seule règle, générique, des deux côtés.** L'app (`Validators.phoneNumber`)
   et le serveur (`isValidE164`) acceptent `^\+[1-9]\d{7,14}$` : un `+` puis 8 à
   15 chiffres. `+2250700000` (10 chiffres en tout) passe ; `+22507000` aussi (4
   chiffres nationaux). Le paquet `intl_phone_field` sait que la Côte d'Ivoire a
   10 chiffres (`countries.dart`, CI 10/10) mais son contrôle est éteint exprès
   (`autovalidateMode: disabled`, A7) ; seul son `maxLength` reste : on ne peut
   pas taper plus de 10 caractères, on peut en taper 7.
2. **Le plan de numérotation.** Depuis le 31 janvier 2021 (ARTCI, publié par
   l'UIT — <https://www.itu.int/oth/T0202000031>), tout numéro d'abonné ivoirien
   (mobile 01/05/07, fixe 21/25/27) a **exactement 10 chiffres** après +225, le
   0 initial compris. libphonenumber (déjà dans le web) dit la même chose :
   longueurs possibles `[10]`.
3. **Le web client refuse déjà** (`isPossiblePhoneNumber`) : l'app et le web ne
   jugent pas le même numéro de la même façon sur le même parcours.
4. **Trous voisins, même famille.**
   - `POST /me/salons` enregistre `phoneNumber` **sans aucun contrôle**.
   - Web Pro « Profil » (téléphone, WhatsApp) et « Acompte » (Mobile Money)
     copient la regex générique ; « Ajouter un client » ne contrôle rien.
   - Trois écrans de l'app (Acompte, Profil du salon ×2, Ajouter un salon)
     prennent le numéro dans un champ texte libre : l'indice « Ex : 07 07 12 34
     56 » montre un format que la règle refuse (il faut le `+`), et la valeur
     contrôlée (séparateurs retirés) n'est pas celle envoyée (brute — le serveur
     refuse les espaces).
   - `PhoneNumberField` : changer de pays ne réémet pas la valeur ; un champ
     vidé émet `+225` (donc « valide » au lieu de « Saisissez un numéro », et le
     téléphone facultatif du profil ne peut plus être effacé) ; un numéro
     enregistré étranger est affiché sous le drapeau CI (le commentaire dit le
     contraire).
   - Acompte (app) : dépôts désactivés → le numéro enregistré n'est pas vérifié
     mais il est envoyé, et le serveur le vérifie toujours.
5. **Données existantes — vérifié en production le 2026-10-15** (lecture seule,
   comptes uniquement, aucune valeur affichée) : `users` 5, `provider_users` 2,
   `salon_clients` 4, `appointments.client_phone` 10, salons (`providers.data`,
   un JSON stocké en chaîne) 3 téléphones + 3 WhatsApp, 0 numéro Mobile Money,
   instantané démo 2 numéros : **aucun** `+225` court ou long, **aucun**
   séparateur. Durcir ne crée donc aucune impasse sur les données d'aujourd'hui ;
   aucune migration.

## 2. Ce que l'on construit

### 2.1 La règle (une seule, trois surfaces)

- On retire les séparateurs (espaces, tirets, points, parenthèses).
- **Vide** — rien, ou un indicatif seul (`+225`) — : « Saisissez un numéro de
  téléphone. » si le champ est requis ; accepté s'il est facultatif (et envoyé
  comme `''`, qui efface côté serveur).
- **`+225`** : exactement **10** chiffres après l'indicatif, sinon « Le numéro doit
  comporter 10 chiffres après +225. » (SYSTEM.md §14 règle 4 : dire quoi faire).
- **Tout autre indicatif** : la règle E.164 générique d'aujourd'hui, sinon
  « Saisissez un numéro de téléphone valide. » — le sélecteur laisse choisir
  n'importe quel pays (diaspora, visiteurs) et la table du paquet est périmée
  pour certains (Bénin 8 au lieu de 10 depuis 2024, Liban) : on ne l'adopte pas.
  Le web garde libphonenumber pour tous les pays (plus strict ailleurs que le
  serveur — sans danger : le serveur reste l'autorité sur le minimum).

Le message est construit depuis la table : « Le numéro doit comporter
`$n` chiffres après +`$indicatif`. » — un futur marché n'ajoute qu'une ligne.

### 2.2 Où vit le fait (§18 / multi-pays §9)

Le fait « +225 → 10 chiffres » est une donnée de marché : il vit dans un seam,
nulle part ailleurs, avec la **même clé** sur les trois surfaces — l'indicatif
sans `+` : `'225'`.

| Surface | Seam | Forme |
|---|---|---|
| Mobile | `core/utils/phone_numbering.dart` (**nouveau, ajouté à la liste fermée de §18 dans ce PR**) | `const Map<String, int> kNationalNumberLength = {'225': 10};` + `PhoneNumbering.normalize`, `.nationalLengthFor` |
| Backend | `lib/src/localities/phone_numbering.dart` (dans le seam existant) | `const Map<String, int> nationalNumberLengths = {'225': 10};` + `hasValidNationalLength` |
| Web | la métadonnée libphonenumber (déjà là) via `lib/phone.ts` | aucun littéral : la longueur est lue de la métadonnée |

Gardes croisées (§8) : chaque pays semé dans `localities` a sa ligne ; la table
mobile, la table backend et la métadonnée web disent la même chose pour `225`.

### 2.3 App (mobile) — les 9 saisies

| Écran | Aujourd'hui | Après |
|---|---|---|
| Connexion — étape téléphone (requis) | `PhoneNumberField` | règle §2.1 ; une réponse `invalid_phone` du serveur va **sous le champ**, plus « Numéro ou code invalide. » (il n'y a pas de code sur cet écran) |
| Modifier le profil (facultatif) | `PhoneNumberField`, ne peut pas être effacé | règle §2.1 ; vidé → `''` envoyé → effacé ; `invalid_phone` sous le champ |
| Pro — Ajouter un client | `PhoneNumberField` | règle §2.1 |
| Pro — Réservation manuelle | `PhoneNumberField` (prérempli depuis la fiche) | règle §2.1 ; un numéro prérempli trop court est signalé sous le champ, corrigeable |
| Pro — Inscription du salon | `PhoneNumberField` | règle §2.1 |
| Pro — Acompte, « Numéro Mobile Money » | champ texte, indice local refusé | **`PhoneNumberField`** ; vérifié **dès qu'il n'est pas vide**, dépôts activés ou non ; requis si dépôts activés |
| Pro — Profil du salon, « Téléphone » (requis) et « WhatsApp » (facultatif) | champs texte | **`PhoneNumberField`** ×2 |
| Pro — Ajouter un salon | champ texte, prérempli du compte | **`PhoneNumberField`** |
| Connexion par téléphone (écran mort, non routé) | `PhoneNumberField` | suit la règle — rien d'autre |

`PhoneNumberField` émet désormais une valeur **normalisée** : `''` si aucun
chiffre national, sinon `+<indicatif><chiffres>` sans séparateur — ce qui est
contrôlé est ce qui est envoyé. Changer de pays réémet. Un numéro prérempli en
`+…` est affiché sous **son** pays (indicatif le plus long qui correspond), plus
sous le drapeau CI. `autovalidateMode` reste `disabled` : la règle passe par
`FieldErrors` (au submit, puis à chaque frappe une fois en erreur — §14 règle 2).

Nettoyage dans le même PR : `Validators.localPhoneNumber` (aucun appelant, un fait
de marché hors seam) supprimé ; données mock et `kConsumerPhone` des tests passés
aux 10 chiffres ; commentaire faux de `PhoneNumberField` corrigé.

### 2.4 Backend — l'autorité

- `isValidPhoneNumber(String)` remplace `isValidE164` : E.164 générique **et**
  longueur nationale (§2.1) sur la valeur reçue (sans séparateur — le serveur
  reste strict : il n'accepte que la forme canonique, les clients normalisent).
- Les 11 sites l'emploient, **codes d'erreur inchangés** (`invalid_phone` ou
  `invalid_input` selon la route, comme aujourd'hui — l'unification est hors
  périmètre, §11).
- **`POST /me/salons`** : un `phoneNumber` envoyé est vérifié → 400
  `invalid_phone`. Le repli sur le téléphone du compte (vérifié à l'inscription,
  non modifiable par l'utilisateur) n'est pas revérifié.
- Contrat : chaque champ téléphone de `openapi.yaml` dit « E.164 ; un numéro
  +225 a exactement 10 chiffres après l'indicatif » ; `POST /me/salons` documente
  son 400. `web/lib/api/schema.ts` régénéré.

### 2.5 Web — rattraper les trois sites, un message précis partout

- `lib/phone.ts` : `phoneFieldError(value, { required })` et `normalizePhone(value)`
  sur libphonenumber (métadonnée *min*, déjà chargée). Le message « 10 chiffres
  après +225 » lit la longueur dans la métadonnée.
- Les six sites `isPossiblePhoneNumber` passent par `phoneFieldError` (même
  verdict, message précis).
- Pro « Profil » et « Acompte » : la regex générique est remplacée ; Pro « Ajouter
  un client » gagne un contrôle sous le champ ; les valeurs envoyées sont
  normalisées.
- Hors périmètre, déjà au registre : « Réserver » (`BookingFlow`) et « Mon compte »
  (`AccountClient`) expriment l'invalidité par un bouton désactivé (§14 règle 5)
  — ils refusent déjà le numéro court ; leur correction est une tranche à part.

## 3. API & contrat

Aucune forme ne change : mêmes champs, mêmes codes. Seuls les descriptions et un
400 (`POST /me/salons`) sont ajoutés au contrat.

## 4. Données

Aucune migration (§1.5). Les numéros à 8 chiffres d'avant 2021 restent
**affichés** groupés (`formatPhoneNumber`, données historiques) mais ne sont plus
**acceptés** en saisie.

## 5. Architecture

Mobile : `core/utils` (seam) → `Validators` → `FieldErrors` des écrans ; le
widget partagé porte la normalisation. Backend : seam `localities/` →
`validators.dart` → routes/services. Web : `lib/phone.ts` → `useFieldErrors`.

## 6. Sécurité

Le serveur reste l'autorité (BACKEND.md §3.4) ; un client contourné reçoit 400.
Le téléphone reste un attribut de contact non vérifié (T34) : rien de ce qui
fait confiance à un téléphone ne change. Aucune donnée personnelle n'est
journalisée ; la vérification de production n'a lu que des comptes.

## 7. Performance

Négligeable : une table d'une ligne, des regex.

## 8. Tests — chacun vu rouge d'abord

- **Mobile** — `validators_test` : `+2250700000` (7), `+225070000000011` (11),
  `+2250700` (4) → « 10 chiffres après +225 » ; `+225 07 07 12 34 56` → accepté ;
  `+225` et `''` → « Saisissez un numéro » ; `+33612345678` accepté.
  `phone_number_field_test` : aucun message pendant la frappe (étendu au nouveau
  texte) ; vidé → `''` ; changement de pays réémis ; `+33…` prérempli → France.
  Écrans : connexion (7 chiffres → message sous le champ, aucun `PATCH`),
  profil (vider efface ; `invalid_phone` sous le champ), acompte (dépôts
  désactivés + numéro court → message), profil du salon, ajouter un salon.
  Garde : table mobile = table backend.
- **Backend** — `validators_test` (mêmes vecteurs) ; routes : `PATCH /me`
  (court → 400 `invalid_phone`, `''` efface, 10 chiffres → 200), `POST /me/salons`
  (court → 400), inscription, clients, réservation manuelle, profil, acompte ;
  garde : chaque pays semé a sa ligne.
- **Web** — `lib/phone` (mêmes vecteurs), les formulaires touchés ; garde :
  métadonnée libphonenumber `CI = [10]` = table backend.
- Chaque nouvelle garde est vue échouer (mutation de la règle, ou test lancé
  contre l'ancien code) avant d'être crue.

## 9. Déploiement

Backend : image construite au merge ; **le déploiement en production attend le
feu vert du propriétaire**. Web : Vercel au merge. App : prochain build. L'ordre
est sans risque : chaque client refuse déjà ce que le serveur refusera.

## 10. Définition de terminé

- [ ] analyze/lint/typecheck = 0 sur les trois ; tests ciblés verts ; CI verte.
- [ ] Contrat + `schema.ts` + SYSTEM.md §18/§14 + multi-pays §6/§9 + BACKEND.md
      §3.4 + `mobile-a7-forms.md` à jour ; entrée de roadmap.
- [ ] Gardes vues rouges ; revue adverse passée.
- [ ] Branche + PR ; aucune attribution Claude.

## 11. Questions ouvertes (hors périmètre, consignées)

1. Codes d'erreur : `invalid_input` (inscription, profil, acompte, OTP verify)
   contre `invalid_phone` (le reste) — un client ne peut pas toujours placer la
   faute sous le bon champ. À unifier dans une tranche contrat.
2. `BookingFlow` / `AccountClient` (web) : bouton désactivé en guise de
   validation (§14 règle 5).
3. Un numéro de fiche client (`salon_clients.phone`) n'est pas modifiable ; le
   téléphone du compte Pro non plus (`provider_users`). Sans incidence
   aujourd'hui (§1.5), à prévoir avant d'ouvrir de nouveaux marchés.
4. `Helpers.maskPhoneNumber` ne masque que les anciens numéros à 8 chiffres
   (écrans OTP en sommeil).
