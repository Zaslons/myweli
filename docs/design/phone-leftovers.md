# Téléphone — ce que [phone-national-length.md](phone-national-length.md) a laissé (§11/§12) — spec

| | |
|---|---|
| **Statut** | **Approuvé le 2026-10-15** (propriétaire : « finish the leftovers from the phone work ») — §2 à §7 en construction sur `fix/phone-leftovers` ; **§8 tranché le même jour** (les trois options recommandées), construit après §2–§7 (il touche les mêmes routes) |
| **Module** | transverse — contrat d'erreurs (BACKEND.md §2) · formulaires (SYSTEM.md §14) · clients (C1) |
| **Origine** | [phone-national-length.md](phone-national-length.md) §11 (questions ouvertes) et §12 (constat écarté de la revue : les champs non textuels → 500) |
| **Régit** | `backend/lib/src/http/body_fields.dart` (nouveau) · `backend/lib/src/observability/request_middleware.dart` · les 27 routes qui lisent un corps · `provider_catalog_service.dart`, `routes/auth/provider/register.dart`, OTP verify · `docs/api/openapi.yaml` · app : inscription Pro, profil du salon, acompte, `Helpers.maskPhoneNumber` · web : `BookingFlow`, `AccountClient`, `ProRegisterClient`, `ProfilClient`, `AcompteClient`, `ManualBookingDialog`, `lib/pro/deposit.ts` |
| **Skills consultés** | myweli-dev-guardrails · myweli-backend-guardrails · myweli-web-guardrails · myweli-verification-guardrails |

## 1. Ce qui reste, vérifié

1. **Une faute de téléphone n'a pas le même code partout.** `invalid_phone` sur
   `PATCH /me`, les clients, la réservation manuelle, `POST /me/salons` ;
   `invalid_input` — partagé avec d'autres champs — sur l'inscription Pro, le
   profil du salon (téléphone ET WhatsApp), l'acompte et les deux OTP verify.
   Un client ne peut pas mettre la faute sous le bon champ : l'app affiche
   « Informations invalides. » ou « Numéro ou code invalide. » (sur un écran
   sans code), le web « L'enregistrement a échoué. Réessayez. ».
2. **Un champ du mauvais type JSON répond 500.** `body['x'] as String?` lève
   un `TypeError` sur un nombre ; le middleware le prend pour une panne
   serveur : 500 `internal_error`, et un rapport d'erreur. 66 lectures dans 27
   routes, tous les champs texte de l'API — pas seulement le téléphone.
3. **Web « Réserver » (`BookingFlow`) et « Mon compte » (`AccountClient`)**
   expriment un numéro invalide par un bouton désactivé, sans message (§14
   règle 5) — et sans le plancher E.164 de `phoneFieldError`.
4. **`Helpers.maskPhoneNumber`** ne masque que l'ancien format CI à 8 chiffres
   (une règle de longueur +225 hors seam ; écrans OTP en sommeil) : un numéro
   d'aujourd'hui s'affiche en clair.
5. **Web Acompte, dépôts désactivés** : le numéro Mobile Money est envoyé à
   `null` — il est effacé. L'app le garde. Écart de parité.
6. **Web réservation manuelle, client choisi** : son numéro enregistré part tel
   quel ; un 400 du serveur s'affiche en ligne générique.
7. **Le numéro d'une fiche client n'est pas modifiable** (le `PATCH` ne touche
   que les tags) — §8.

## 2. Codes d'erreur : une faute de téléphone dit `invalid_phone`

| Route | Aujourd'hui | Après |
|---|---|---|
| `POST /auth/provider/register` — `phoneNumber` | `invalid_input` | `invalid_phone` (nom et type restent `invalid_input`) |
| `PATCH /providers/{id}` — `phoneNumber` | `invalid_input` | `invalid_phone` |
| `PATCH /providers/{id}` — `whatsapp` | `invalid_input` | **`invalid_whatsapp`** (deux champs téléphone sur le même formulaire : le code dit lequel) |
| `PUT /providers/{id}/deposit-policy` — `mobileMoneyNumber` | `invalid_input` | `invalid_phone` |
| `POST /auth/otp/verify`, `/auth/provider/otp/verify` (en sommeil) | `invalid_input` (téléphone OU code) | téléphone → `invalid_phone` ; code → `invalid_input` |

Statut inchangé (400). Clients : chaque `invalid_phone` / `invalid_whatsapp`
se place **sous le champ** concerné, avec « Saisissez un numéro de téléphone
valide. » (app : inscription Pro, profil du salon, acompte ; web : inscription
Pro, Profil, Acompte). Un ancien build qui ne connaît pas le code garde son
message générique — et le refus ne vient qu'après une règle client identique.

## 3. Un champ du mauvais type → 400 `invalid_body`, jamais 500

- `lib/src/http/body_fields.dart` : `optionalString(body, key)`,
  `optionalList(body, key)` (et ce dont les 27 routes ont besoin). Absent ou
  `null` → `null` ; du bon type → la valeur ; d'un autre type → lève
  `BodyFieldTypeError(key)`.
- Le middleware répond **400 `invalid_body`** à `BodyFieldTypeError` (c'est
  le code déjà employé pour un corps qui n'est pas un objet JSON), **sans
  rapport d'erreur** (la faute est au client). Un `TypeError` ordinaire reste
  un 500 rapporté : un vrai bug serveur ne doit pas se déguiser en 400.
- Les 66 lectures `body['x'] as …` des routes passent par ces lecteurs.
- `POST /me/salons` : un `phoneNumber` non textuel répondait `invalid_phone`
  (#611) ; il rejoint la règle commune : `invalid_body`.
- Contrat : le composant `BadRequest` dit qu'un champ du mauvais type JSON
  répond `invalid_body`.
- Garde : aucune lecture `body['…'] as` ne reste dans `backend/routes`
  (commentaires retirés avant la recherche), vue rouge sur une lecture ajoutée.

## 4. Web « Réserver » et « Mon compte » : le message sous le champ

`useFieldErrors` + `phoneFieldError` (requis) ; le bouton n'est désactivé que
pendant l'envoi (§14 règle 5) ; un numéro prérempli invalide est signalé à
l'envoi, sous le champ, corrigeable. Valeur envoyée : `normalizePhone`.

## 5. `Helpers.maskPhoneNumber` : générique, via le seam

Masque tout numéro E.164 : l'indicatif, les deux premiers et les deux derniers
chiffres nationaux restent visibles, le reste devient des points ; plus aucune
longueur +225 en dur. La garde « aucune longueur hors seam » et SYSTEM.md
cessent de le nommer comme reliquat.

## 6. Web Acompte : le numéro est gardé quand les dépôts sont désactivés

Comme l'app : un numéro non vide est vérifié et envoyé quel que soit
l'interrupteur ; vide → `null`. Si le serveur le refuse (`invalid_phone`)
alors que la carte est cachée, elle se montre avec le message sous le champ,
et se recache après un enregistrement réussi ou quand l'interrupteur bouge.

## 7. Web réservation manuelle : le numéro d'un client choisi

Un `invalid_phone` du serveur pour un client choisi (son numéro est affiché,
pas éditable ici) dit : « Le numéro enregistré sur la fiche de ce client est
invalide. » avec un lien vers sa fiche. (L'app préremplit un champ
modifiable : déjà corrigeable.)

## 8. Modifier le numéro d'une fiche client — **tranché le 2026-10-15**

Décisions du propriétaire (les trois recommandations) : **l'historique suit
le numéro** ; une fiche **liée à un compte** garde le numéro du compte, en
lecture seule ; un numéro **déjà sur une autre fiche** est refusé, avec un
lien vers cette fiche (pas de fusion).

Ce qui rend la chose délicate, vérifié : la fiche d'un client **invité** (sans
compte) retrouve ses visites **par son numéro** (`_visitsOf`,
`_statsByClient` : rendez-vous `userId == 'manual'` dont `clientPhone` = celui
de la fiche). Changer le numéro de la fiche seule la viderait.

**Contrat.** `PATCH /providers/{id}/clients/{clientId}` accepte `phone`
(texte, optionnel) à côté de `tags` (optionnel) — au moins l'un des deux.
- Même capacité que le reste de la fiche (`clientsView`) ; sinon 403.
- Fiche liée à un compte (`userId` non nul) → **409 `client_linked`** ; rien
  ne change.
- Numéro : `isValidPhoneNumber` → sinon 400 `invalid_phone` ; vide refusé
  (une fiche invitée n'existe que par son numéro — `addClient` l'exige).
- Même numéro que la fiche : rien à faire, 200.
- Numéro déjà sur une autre fiche de CE salon → **409 `client_exists`** avec
  `clientId` de l'autre fiche (la forme de `POST …/clients`) ; une course
  perdue sur l'index unique `(provider_id, phone)` répond pareil, jamais 500.
- Sinon, **dans une transaction** : la fiche prend le nouveau numéro, et les
  rendez-vous manuels de CE salon (`user_id = 'manual'`) portant l'ancien
  `client_phone` prennent le nouveau — jamais ceux d'un autre salon (T45).
  Jumeau en mémoire identique. Audit `client.phone_changed` (identifiants
  seulement, aucun numéro — donnée personnelle).

**App Pro (fiche client)** — sous le numéro, « Modifier » ouvre une feuille :
`PhoneNumberField` prérempli, « Enregistrer » ; la faute sous le champ ; un
409 `client_exists` : « Ce numéro est déjà sur la fiche de {nom}. » +
« Ouvrir la fiche » ; succès : la fiche se recharge (visites comprises),
« Numéro mis à jour ». Fiche liée : pas de « Modifier » ; « Numéro du compte
client » sous le numéro.

**Web Pro (fiche client)** — la même chose dans un `Modal` : `PhoneField`,
message sous le champ, lien vers l'autre fiche, rechargement.

**Tests (rouges d'abord)** : backend — chaque branche ci-dessus, dont
l'historique déplacé (les visites et le compteur suivent ; un autre salon
n'est pas touché ; Postgres ET mémoire) ; app et web — modifier, le doublon,
la fiche liée en lecture seule.

## 9. Tests — chacun vu rouge d'abord

Backend : les nouveaux codes (route par route) ; `optionalString` & co ; le
middleware (400 `invalid_body` sans rapport ; un `TypeError` ordinaire reste
500) ; une requête réelle par famille de route avec un nombre là où le
contrat dit texte ; la garde de recherche. App : les fautes serveur sous le
champ (inscription, profil ×2, acompte) ; le masque. Web : les mêmes, plus
« Réserver », « Mon compte », Acompte dépôts désactivés, réservation manuelle.

## 10. Déploiement

Le backend change des codes d'erreur : les nouveaux clients les comprennent,
les anciens retombent sur leur message générique (§2). Déploiement en
production sur feu vert du propriétaire.
