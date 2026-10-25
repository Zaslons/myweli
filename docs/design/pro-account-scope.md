# App Pro — un compte qui sort emporte son salon : la déconnexion, la suppression, l'accès retiré, la session refusée — spec

| | |
|---|---|
| **Statut** | **Validé le 2026-10-25** — Q1 = **(a)** les gardes des treize magasins dans cette PR ; Q2 = **(a)** la connexion, avec « Votre session a expiré. Reconnectez-vous. » (§8). |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-25 |
| **PRD ref / phase** | FR-AUTH-003 (session, déconnexion) · FR-AUTH-005 (suppression) · accès d'équipe R3/R4 (rôles) · V1 |
| **Module** | app Pro — `ProAuthProvider`, les magasins montés dans `main_pro.dart` |
| **Origine** | [consumer-account-scope.md](consumer-account-scope.md) §8, Q2 = (a) : « le jumeau Pro dans une PR à lui » · BACKLOG **B9.14** |
| **Base** | `feat/consumer-signout-reset` (#701, rebasée sur `main`) : elle apporte `AccountScope` / `AccountScoped`, le numéro de compte, l'annonce de `RefreshingHttpClient` et `NotificationsProvider` déjà remis à zéro par compte. |
| **Skills checked** | myweli-dev-guardrails ✓ · aucun changement serveur, ni web |

## 1. Le constat — relu sur le vrai chemin de code, et prouvé

**Prouvé par un essai jetable** (le vrai `ProAuthProvider`, le vrai
`DashboardScreen`, les doublures) : la propriétaire de « Salon Excellence »
se connecte, l'Accueil montre ses deux cartes « Revenus prévus » ; elle se
déconnecte ; **la réceptionniste du même salon** se connecte sur le même
téléphone : l'Accueil montre **les deux cartes « Revenus prévus » de la
propriétaire, à chaque image, sans jamais relire** (`loading=false`). La
réception n'a pas `finances.view` ; le serveur ne lui envoie pas ces
chiffres — c'est l'app qui les garde :

- `ProDashboardProvider.loadDashboardStats` (`pro_dashboard_provider.dart:67-73`)
  rend ce qu'il tient quand l'id du salon est le même — et c'est le même
  salon.
- L'écran montre la carte sur la seule donnée (`dashboard_screen.dart:334`,
  `if (stats.hasRevenue)`), pas sur le rôle.
- Personne ne vide rien : `ProAuthProvider.logout()`
  (`pro_auth_provider.dart:1081-1110`) remet à zéro ses propres champs et
  **n'appelle pas `ProSalonScope.resetAll()`** ; aucune connexion non plus
  (`_login` :831, `_bridgedLogin` :877, `acceptPendingInvitation` :919, la
  reprise :775).

Toutes les sorties passent par `logout()` : le bouton
(`pro_profile_screen.dart:356`), la suppression (:429, après
`deleteProviderAccount`), l'accès retiré (`_signOutRevoked` :446), la
porte expirée (`endExpiredRejoin` :622). Un seul endroit à corriger pour les
sorties, quatre pour les entrées.

**Ce que garde le compte précédent** (lu, magasin par magasin) :

| Magasin | Portée | Après la sortie |
|---|---|---|
| Les 16 magasins par salon de `main_pro.dart` (accueil, rendez-vous, journée, clients, services, employés, disponibilité, revenus, avis, profil du salon, acompte, configuration, photos, avant/après, abonnement, équipe) | le salon | tout ce qu'ils tenaient ; quatre rendent leur cache sans relire pour le même salon (accueil, disponibilité, avis, services) |
| Le fil des notifications (la cloche) | le compte | ses notifications — l'essai : 4 restées après la sortie |
| `ProKycProvider` (la vérification) | le compte | **les pièces d'identité** envoyées, le statut, le motif d'un refus |
| `ProviderProvider` (« Aperçu de ma page ») | — | la page du salon précédent ; **jamais montrée** : l'aperçu attend sa propre lecture derrière un squelette (`salon_preview_screen.dart:60-90`) |

**Les réponses en route.** Treize des seize magasins par salon écrivent ce
qui répond, même après une remise à zéro : seuls l'accueil, les clients et
la journée ont une garde. `loadEarnings` (`pro_earnings_provider.dart:25-57`)
en est l'exemple : lancé pour A, répondu après la sortie, il remet les
revenus de A dans le magasin — que l'écran de B garde affichés pendant sa
propre lecture (F1 garde les données pendant un rechargement). **Le même trou
existe aujourd'hui au changement de salon** (« Mes salons ») : une réponse du
salon 1 tombe sous le nom du salon 2.

**La session refusée ne sort de rien** : #701 fait annoncer par
`RefreshingHttpClient` la session qu'il efface ; celle du Pro
(`myweli_provider_session`) n'est écoutée par personne. L'app Pro reste
« connectée », chaque écran en erreur, jusqu'au redémarrage — seule la porte
de réadhésion a sa sortie (`endExpiredRejoin`).

## 2. Ce qui change

### 2.1 Un changement de compte remet tout à zéro

`ProAuthProvider` fait passer chaque changement de `_provider` par un seul
endroit (`_setProvider`, le jumeau de `AuthProvider._setUser`). Quand l'id
du compte change — la reprise, chaque connexion, chaque sortie — dans le même
bloc synchrone, avant la notification :

- `ProSalonScope.resetAll()` — un autre compte, c'est un autre salon ou un
  autre rôle ;
- `AccountScope.resetAll()` — ce qui est du compte : la cloche (déjà
  `AccountScoped` depuis #701) et `ProKycProvider` (le devient), inscrits
  dans `main_pro.dart` par `AccountScope.track`.

`ProviderProvider` et `LocalityProvider` ne sont pas inscrits : publics, et
l'aperçu ne montre que ce qu'il vient de lire. `main_pro.dart` gagne
`proAppProviders(auth)`, comme `consumerAppProviders`, pour que les essais
montent le vrai câblage.

La porte de réadhésion garde son ordre (remise à zéro PUIS les cartes,
`_enterRejoin`) : la remise à zéro de la connexion a lieu avant la
vérification d'adhésion qui ouvre la porte.

### 2.2 Les réponses en route n'appartiennent plus à personne (Q1)

**Proposé (Q1 a)** : chacun des treize magasins sans garde tient un numéro
de salon, avancé par `resetForSalonSwitch` ; chaque lecture et écriture le
relève avant d'attendre et **n'écrit rien** s'il a bougé — l'idiome de #701.
Les trois magasins déjà gardés sont relus pour vérifier que leur garde
avance bien à la remise à zéro. Cela ferme aussi le trou du changement de
salon, qui n'est pas né de cette PR mais vit au même endroit.
`ProKycProvider` reçoit la même garde, au niveau du compte.

### 2.3 La session refusée devient une sortie (Q2)

- `AuthServiceInterface` gagne `Stream<void> get providerSessionEnded` : la
  session **Pro** a pris fin sans déconnexion. `ApiAuthService` relaie
  l'annonce de `_providerSessionStore` et oublie son `_currentProvider` ;
  `MockAuthService.expireProviderSession()` la simule.
- `ProAuthProvider` l'écoute : connecté, il sort (`logout()` — la
  désinscription du téléphone échoue sans session, elle est déjà « au mieux »)
  et va à `/pro/login`. Entendue pendant une sortie, c'est la même sortie ;
  pendant une sortie qui échoue, le compte sort quand même — comme #701.
- **Ce que la personne voit — proposé (Q2 a)** : l'écran de connexion, avec
  **« Votre session a expiré. Reconnectez-vous. »** (la phrase de l'app
  cliente, `kSessionEndedMessage`) à la place où s'affiche « accès retiré » —
  un `InlineFeedback` d'information, consommé une fois
  (`consumeSessionEndedNotice`). Tout écran Pro demande une session : il n'y
  a pas d'« écran public » où rester.
- `endExpiredRejoin` garde sa propre sortie (elle vérifie que la session
  stockée a vraiment disparu) ; l'annonce y arrive d'ordinaire avant elle,
  et la trouve alors déjà sortie.

## 3. Les états et cas limites

- **Propriétaire → réception du même salon** : l'Accueil relit, sans les
  cartes d'argent ; rien de la propriétaire à aucune image (l'essai du §6).
- **Un salon → un autre compte d'un autre salon** : les seize magasins vides,
  chaque écran relit pour son salon.
- **Le même compte se reconnecte** : tout est relu.
- **Une lecture partie sous A répond après** : rien (Q1 a).
- **L'accès retiré** (`_signOutRevoked`) : inchangé — sa bannière « accès
  retiré », plus la remise à zéro.
- **La suppression refusée** (rendez-vous à venir, compte de démonstration) :
  rien ne sort, rien n'est vidé.
- **La session refusée pendant la porte de réadhésion** : la sortie, la
  phrase ; plus de cartes.
- **Une notification touchée pendant la sortie** : inchangé, hors périmètre
  (comme #701 §9).

## 4. Le contrat

Aucun changement serveur ni d'`openapi.yaml`.

## 5. La sécurité

- Ferme **une fuite de capacité dans l'app** : les revenus d'une
  propriétaire affichés à une réceptionniste qui n'a pas `finances.view` —
  le serveur ne les lui envoie pas, l'app les gardait. Et les pièces
  d'identité de la vérification d'un compte au compte suivant.
- Le serveur reste l'autorité ; rien ne bouge au modèle de menace du serveur.

## 6. Les tests (rouges d'abord)

- **Le widget** (`test/widget/pro_account_switch_test.dart`), sur le vrai
  câblage `proAppProviders` : la propriétaire voit « Revenus prévus » ; elle
  se déconnecte par le bouton du Profil ; la réceptionniste du même salon se
  connecte, sa lecture **tenue** : à chaque image, aucune carte « Revenus
  prévus », rien de la cloche de la propriétaire ; puis la lecture répond.
  Et un autre salon : rien du premier sur l'Accueil ni dans « Clients ».
- **`ProAuthProvider`** : la remise à zéro (les deux portées) à chaque
  entrée et chaque sortie, pas pour le même compte, avant la notification ;
  la session refusée (sortie, `/pro/login`, la phrase une fois ; pendant une
  sortie ; ignorée sans compte) ; l'ordre de la porte de réadhésion tenu.
- **Les magasins** (Q1 a) : pour chacun des quatorze, une lecture et une
  écriture parties avant la remise à zéro n'écrivent rien après ; la remise
  à zéro de `ProKycProvider`.
- **Les services** : `ApiAuthService.providerSessionEnded` relaie la session
  Pro, pas celle du client, et oublie `_currentProvider` ; la doublure.
- **Les mutations**, sur le travail commis : chaque déclencheur, chaque
  `track`, chaque garde, l'annonce, le filtre, la phrase.

## 7. Les mots

- **« Votre session a expiré. Reconnectez-vous. »** — la même phrase que
  l'app cliente (#701 §7), une seule constante.

## 8. Questions au propriétaire

- **Q1 — les réponses en route dans les treize magasins par salon.**
  - **(a) Dans cette PR (recommandé).** Sans elles, la remise à zéro est la
    moitié d'une correction : une lecture lancée sous la propriétaire
    remplit le magasin juste après. Environ cinquante méthodes, une garde
    chacune, et le changement de salon est fermé du même coup.
  - (b) La remise à zéro maintenant, les gardes dans une PR à part.
- **Q2 — la session Pro refusée.**
  - **(a) La connexion, avec « Votre session a expiré. Reconnectez-vous. »
    (recommandé).**
  - (b) La connexion sans un mot, comme la porte de réadhésion expirée
    aujourd'hui.

## 9. Hors périmètre — noté

- Le tampon des notifications touchées (comme #701 §9).
- Le renvoi d'une requête sous une autre session (#701 §9) : vrai aussi pour
  la session Pro.

## 10. Definition of done

- [ ] `flutter analyze` = 0 · format propre · la suite verte.
- [ ] Chaque garde vue rouge par mutation sur le travail commis (§6).
- [ ] Ce spec « construit » (§11), le BACKLOG (B9.14), une entrée dans
  `docs/roadmap/entries/`, l'index `docs/design/README.md`.
- [ ] Branche de fonctionnalité, PR ouverte pour revue ; aucune attribution
  à Claude.
