# Téléphone — ce que [phone-national-length.md](phone-national-length.md) a laissé (§11/§12) — spec

| | |
|---|---|
| **Statut** | **Construit le 2026-10-15** sur `fix/phone-leftovers` — §2–§7 (approuvés par le propriétaire : « finish the leftovers from the phone work ») et §8 (tranché le même jour : les trois options recommandées) ; §11 dit ce qui a été construit autrement qu'écrit |
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

## 11. Construit — ce qui diffère de ce qui était écrit

**Serveur.**
- Inscription Pro : le nom et le type sont vérifiés **avant** le téléphone (le
  même ordre que `POST /me/salons`).
- `POST /appointments` : un champ du mauvais type répond désormais
  `invalid_body` (il répondait `invalid_input` par une liste de clés tenue à
  la main, remplacée par les lecteurs).
- Trois lectures de service qu'une valeur client atteignait sans contrôle de
  type passent par les lecteurs (description d'une prestation, spécialité d'un
  artiste, texte d'un avis) : un nombre y répond 400, il était **enregistré**
  sur les chemins de mise à jour.
- Quand un service vérifie le type ET la valeur d'un champ, il garde le code
  du champ (un `whatsapp` numérique → `invalid_whatsapp`) ; le composant
  `BadRequest` du contrat le dit.
- `PATCH …/clients/{clientId}` répond la fiche (forme du `GET`) pour toute
  modification, tags seuls compris ; cette relecture est une consultation
  auditée (T46).
- **Une fiche anonymisée ne prend pas de numéro** (décision prise en
  construction, au nom de T48) : une fiche sans compte ET sans numéro n'existe
  qu'après l'effacement d'un compte ; lui attacher un numéro réidentifierait
  ses tags et ses notes. → 409 `client_anonymized` ; l'app et le web ne
  proposent pas « Modifier » sur une fiche sans numéro.
- La ligne d'audit `client.phone_changed` est écrite après la transaction,
  comme toute écriture d'audit du service.

**App et web.**
- La phrase du doublon élide : « la fiche d'Aïcha », pas « de Aïcha »
  (`Formatters.de` / `deName`, mêmes vecteurs) ; l'étiquette « Ouvrir la fiche
  de … » de la liste web aussi.
- Le nom de l'autre fiche (le 409 ne porte que son id) est lu par un `GET` de
  cette fiche — une consultation auditée, exacte puisque son nom est affiché ;
  s'il est illisible : « … la fiche d'un autre client. » (app) / « … sur une
  autre fiche. » (web), le lien gardé.
- Textes ajoutés : la ligne « Les visites de ce client suivent le nouveau
  numéro. » (app) ; un `client_linked` (fiche devenue liée entre-temps) ferme,
  recharge en lecture seule et l'explique.
- Le même numéro : rien n'est envoyé, la feuille se ferme, sans annonce.
- Web Acompte, dépôts désactivés : seul le champ « Numéro Mobile Money » se
  révèle sur un refus (le web n'a pas de carte « Recevoir l'acompte ») ;
  l'opérateur et le pourcentage partent encore vides / à 0 — écart de parité
  restant, hors périmètre.
- « Réserver », « Mon compte » et l'étape téléphone de la connexion (web) ne
  disent plus « Numéro invalide » pour un échec qui n'est pas le numéro
  (réseau, 5xx).
- App : la fiche se recharge quand go_router lui donne un autre client
  (« Ouvrir la fiche » depuis une fiche ouverte par lien) ; `maskClientPhone`
  lit l'indicatif par la même recherche que le reste (un +33 ne lit plus
  « +336 … »).

**`phoneEditable` — pas de fenêtre au déploiement** (revue adverse). Le web
part en production au merge, le serveur sur déclenchement manuel : entre les
deux, « Modifier » aurait parlé à l'ancienne route (`invalid_tags` à
`{phone}`) et échoué à chaque essai. La fiche (`GET` et réponse du `PATCH`)
porte donc `phoneEditable` = pas de compte ET un numéro — exactement les
fiches dont le `PATCH` prend un numéro — et l'app comme le web n'affichent
« Modifier » que si le serveur dit `true` ; un champ absent (ancien serveur)
vaut `false`. La règle vit à un seul endroit, le serveur.

**Revue adverse, autres corrections** : `POST …/artists` lit tous ses champs
avant de promouvoir la photo (un refus laissait une photo orpheline) ; la
feuille de l'app ne se ferme pas pendant l'enregistrement et ignore une
réponse pour un numéro qui n'est plus dans le champ ; le dialogue web ne se
ferme pas pendant l'enregistrement et rend le focus au titre après un
`client_linked` ; un client choisi lié à un compte n'a pas de lien « Ouvrir la
fiche » (son numéro est celui de son compte) ; le bouchon e2e répond dans
l'ordre et avec les codes du serveur ; le mock de l'app tient ses fiches par
salon.

**Ordre de déploiement** : le serveur d'abord reste le bon ordre (l'app parle
au `PATCH` qui accepte `phone`), mais aucune surface ne casse s'il ne l'est
pas : sans `phoneEditable`, pas de « Modifier ».

