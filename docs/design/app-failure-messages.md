# L'app dit la bonne chose quand quelque chose échoue — spec

| | |
|---|---|
| **Statut** | **Validé le 2026-10-21** — Q1 (décision 12) : **redemander une fois** ; Q2 : **les mots tels qu'écrits** (§8) ; Q3 : **deux PR** ; Q4 : **les pages client aussi** |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-21 |
| **PRD ref / phase** | Toutes les surfaces de l'app (client et Pro) et du web — les états d'erreur (V1) · SYSTEM.md §14 (formulaires), §15 (retours), §16 (microcopie) |
| **Module** | app (les services `lib/services/api`, 23 fournisseurs, la carte, les notifications) ; web (les phrases d'échec d'enregistrement, les pages client) |
| **Origine** | [BACKLOG.md](../BACKLOG.md) lot 3 : B3.1, B3.2, B3.3 (décision 12) |
| **Skills checked** | myweli-dev-guardrails ✓ · myweli-web-guardrails ✓ |

## 1. Le constat — relu sur le vrai chemin de code (main `ff670ee`)

### 1.1 B3.1 — du texte d'exception brut, et « Erreur » tout court

- **73 `e.toString()` dans 23 fournisseurs**, plus un dans `screens/map/map_screen.dart`
  (le backlog en comptait 67 : il en est venu depuis). Tous de la forme
  `catch (e) { _error = e.toString(); }`, et l'écran affiche `_error`.
- **Le chemin qui fuit, vérifié** : un Wi-Fi à portail captif ou une page
  d'erreur de Cloudflare répond **200 avec du HTML**. Par exemple
  `ApiProService.updateProviderAvailability` fait
  `Availability.fromJson(_decode(res.body))` ; `_decode` lève `FormatException` ;
  `ProAvailabilityProvider` met `e.toString()` dans `_error` ; et
  `availability_screen.dart:393` le montre dans un bandeau :
  « FormatException: Unexpected character (at character 1) <html>… ». Un JSON
  inattendu (`as String` sur un nombre) donne de même « type 'int' is not a
  subtype of type 'String'… ».
- **La carte** : une localisation qui échoue (délai dépassé, service coupé
  pendant la demande) affiche le texte anglais du plugin dans son bandeau.
- **« Erreur » tout court** : 11 services ont chacun leur `_errorFrom` ; cinq
  (favoris, notifications, artistes, KYC, avis) rendent le `message` du serveur
  — que ces routes n'envoient pas — ou **« Erreur »** ; environ 20 endroits
  répondent « Erreur » (dont `provider.error ?? 'Erreur'` dans cinq écrans).
- **Ce qui existe déjà et sert de modèle** : #630 a protégé trois lectures
  (`listClients`, les favoris, les artistes) — un corps illisible y est une
  lecture échouée dite en français, jamais une exception.

### 1.2 B3.2 — deux phrases pour « rien n'a répondu »

- **App** : `api_pro_service`, `api_auth_service` (deux fois), `api_provider_service`
  (deux fois), `api_appointment_service` et `admin_service` disent
  **« Connexion au serveur impossible »** ; quinze autres fichiers et le web
  disent **« Pas de connexion. Réessayez. »**. Le lot 2 l'a vu : la réservation
  du client dit maintenant la seconde quand sa réponse s'est perdue deux fois,
  mais le reste de `api_appointment_service` dit encore la première.
  `api_provider_service` dit aussi « Connexion au serveur impossible » pour un
  corps illisible — ce n'est pas la connexion.
- **Web** : treize phrases « L'enregistrement a échoué. Réessayez. » ; trois
  passent déjà par `writeFailureMessage` (qui dit « Pas de connexion » quand
  rien n'a répondu), dix non — dont le numéro de « Mon compte »
  (`AccountClient.tsx:368`), à côté du nom qui, lui, le dit.
- **Web, les pages client** : `loadFailure` / `loadFailureMessage` vivent dans
  `lib/pro/` et seules les pages Pro les utilisent. « Mes rendez-vous »
  (`AppointmentDetailClient`), les notifications (« Chargement impossible. »)…
  ne disent pas « Pas de connexion » quand rien n'a répondu.

### 1.3 B3.3 — l'état « lu » d'une notification peut retarder sur le serveur

`NotificationsProvider` (partagé par l'app client et l'app Pro) :

1. **Une relecture pendant un « marquer comme lu »** remplace la liste par celle
   du serveur, qui ne l'a pas encore écrit : la ligne revient **non lue**, et le
   succès qui suit ne la remet pas lue.
2. **Une réponse perdue** (le serveur a écrit, la réponse ne revient pas) :
   la ligne redevient **non lue**, alors que le serveur l'a marquée.
3. **Après un nouvel essai réussi**, le bandeau d'échec du premier reste
   affiché ses 6 s : `AppSnackBar.showOn` ne rend rien qui permette de le
   cacher.

Les deux écritures sont **sans risque à répéter** : `UPDATE … SET read = true`,
200 à chaque fois (`postgres_notifications_repository.dart:62`, `:74`).

## 2. Ce qui change

### 2.1 App — deux aides partagées (B3.1)

Dans `lib/services/api/` :
- **`readJsonOrUnreadable<T>(res, parse)`** : lit le corps et le convertit ;
  un `FormatException` ou un `TypeError` devient
  `ApiResponse.error(« Une erreur est survenue. Réessayez. », code: 'unreadable')`
  — jamais une exception qui remonte. La généralisation de #630.
- **`errorFromResponse(res, {messageFor})`** : lit `{error}` quand le corps est
  du JSON ; sinon traduit le statut (401 « Veuillez vous reconnecter. », 5xx et
  page HTML : la phrase générique). Il remplace les onze `_errorFrom` ; chaque
  service garde sa table de codes (`messageFor`) — un code connu garde sa
  phrase d'aujourd'hui. **Le `message` du serveur n'est plus jamais montré.**

Puis, fournisseur par fournisseur, `_error = e.toString()` devient la phrase
générique (le `catch` reste, pour ce qui n'est pas une réponse : une exception
de programmation ne doit pas non plus s'afficher en anglais). Les « Erreur »
tout court et les `?? 'Erreur'` des écrans deviennent la même phrase. La carte
dit « Position introuvable. Réessayez. » (Q2).

### 2.2 Une seule phrase pour « rien n'a répondu » (B3.2)

- **App** : une constante `kNoConnectionMessage = 'Pas de connexion. Réessayez.'`
  (le jumeau de `NO_CONNECTION_MESSAGE` du web), utilisée par les sept endroits
  qui disent « Connexion au serveur impossible » et par les quinze fichiers qui
  l'écrivent en toutes lettres. Un corps illisible n'est plus « connexion » :
  c'est la phrase générique (§2.1).
- **Web** : les dix « L'enregistrement a échoué » passent par
  `writeFailureMessage(status, …)` ; `loadFailure` et `loadFailureMessage`
  vont dans `lib/api/` (un ré-export garde `lib/pro/load-failure.ts` le temps
  de la PR) et les pages client s'en servent (Q4).

### 2.3 Les notifications (B3.3)

- **Les identifiants en cours d'écriture sont gardés** ; une relecture les
  réapplique (lus) tant que l'écriture n'a pas répondu, et le succès les
  réapplique encore.
- **Une réponse perdue** (code `network`) : **redemander une fois, tout de
  suite** (décision 12, recommandé) — l'écriture est sans risque ; si la
  seconde se perd aussi : la ligne redevient non lue et le bandeau dit
  « Pas de connexion. Réessayez. ». Un vrai refus : non lue, la phrase générique
  (comme aujourd'hui).
- **Un nouvel essai cache le bandeau d'échec précédent** : `AppSnackBar.showOn`
  rend son contrôleur ; le geste suivant le ferme.

## 3. Les états

| Situation | Avant | Après |
|---|---|---|
| Portail captif / page HTML en 200 | « FormatException: … » | « Une erreur est survenue. Réessayez. » |
| JSON inattendu | « type 'int' is not a subtype… » | « Une erreur est survenue. Réessayez. » |
| Rien n'a répondu (app) | « Connexion au serveur impossible » **ou** « Pas de connexion. Réessayez. » | « Pas de connexion. Réessayez. » |
| Rien n'a répondu (web, un enregistrement) | « L'enregistrement a échoué. Réessayez. » | « Pas de connexion. Réessayez. » |
| Un refus du serveur au code connu | sa phrase | sa phrase (inchangée) |
| Un refus au code inconnu | « Erreur » | « Une erreur est survenue. Réessayez. » |
| La localisation échoue | le texte du plugin | « Position introuvable. Réessayez. » |
| « Marquer comme lu » dont la réponse se perd | redevient non lue | redemandé une fois ; reste lue |
| Une relecture pendant « marquer comme lu » | revient non lue | reste lue |

## 4. Les tests (rouges d'abord)

- **Les deux aides** : un HTML en 200, un corps coupé, un JSON du mauvais type,
  un 401, un 500 en HTML, un code connu, un code inconnu — chaque fois la bonne
  phrase et le bon code, jamais une exception.
- **Une épingle** : aucun `e.toString()` dans `lib/providers/` ni dans
  `lib/screens/` ; aucune « Connexion au serveur impossible » ; aucun
  `'Erreur'` seul dans `lib/` (hors mocks) — la leçon de
  `no_secret_in_url_test` : le dossier entier, pas une liste.
- **Un écran** par famille : la disponibilité qui reçoit du HTML montre la
  phrase générique ; la carte, sa phrase.
- **Web** : les dix enregistrements, hors ligne → « Pas de connexion » ; les
  pages client, une lecture hors ligne → « Pas de connexion ».
- **Notifications** : la relecture pendant l'écriture ; la réponse perdue puis
  redemandée ; perdue deux fois ; le bandeau caché au nouvel essai.
- **Mutations** : l'aide qui laisse passer l'exception, la vieille phrase
  revenue, une page client sans la raison, l'identifiant oublié après la
  relecture, pas de second essai.

## 5. Sécurité

Moins de fuite : ni le texte d'une exception (qui peut contenir un morceau du
corps reçu) ni le `message` du serveur n'atteignent plus l'écran.

## 6. La livraison (Q3)

**Deux PR** : (A) B3.1 + B3.2 — les aides, la phrase unique, les dix phrases
du web, les pages client ; (B) B3.3 — les notifications. Elles ne touchent pas
les mêmes fichiers (sauf `notifications_provider.dart:48`, une ligne de A).
L'app atteint les personnes par la prochaine version des stores.

## 7. Hors de cette tranche

- Le texte des erreurs de l'admin (console interne) au-delà de la phrase
  « Connexion au serveur impossible » de `admin_service`.
- Le journal des erreurs inattendues (Sentry) : ce qui est montré change, ce
  qui est rapporté non.

## 8. Les mots (Q2)

- **« Une erreur est survenue. Réessayez. »** — la phrase générique qui existe
  déjà (`NotificationsProvider.writeFailedMessage`, le web
  `GENERIC_ERROR_MESSAGE`) : un corps illisible, un code inconnu, une exception.
- **« Pas de connexion. Réessayez. »** — la seule phrase pour « rien n'a
  répondu », app et web. **« Connexion au serveur impossible » disparaît.**
- **« Position introuvable. Réessayez. »** — la carte, quand la localisation
  échoue sans être refusée ni coupée (les deux autres phrases de la carte ne
  changent pas).

## 9. Questions au propriétaire

- **Q1 (décision 12)** — « Marquer comme lu » dont la réponse s'est perdue :
  **redemander une fois, tout de suite** (recommandé — l'écriture est sans
  risque), ou garder la ligne non lue jusqu'au prochain chargement (aujourd'hui) ?
- **Q2 — les mots** (§8) : tels qu'écrits ?
- **Q3 — la livraison** : **deux PR** (recommandé — A : les aides et la
  phrase unique ; B : les notifications), ou une seule ?
- **Q4 — le web** : **les pages client disent aussi « Pas de connexion »** quand
  une lecture n'a rien reçu (`loadFailure` dans `lib/api`, recommandé — la
  parité avec le Pro et l'app), ou seulement les dix enregistrements ?

**Décisions (2026-10-21).** Q1, Q2, Q3 et Q4 : les recommandations, telles qu'écrites.
